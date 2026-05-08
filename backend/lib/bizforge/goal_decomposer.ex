defmodule Bizforge.GoalDecomposer do
  @moduledoc """
  Decomposes a goal into actionable issues using an LLM.

  The decomposer:
  1. Reads goal + project context
  2. Reads available agents and their roles
  3. Prompts the LLM for a structured list of issues
  4. Creates issues in the DB with suggested assignees
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Goal, Agent, Workspace}
  import Ecto.Query

  @doc """
  Decompose a goal into issues.

  Options:
    - :max_issues   - maximum number of issues to create (default: 10)
    - :auto_assign  - whether to auto-assign issues to agents (default: true)

  Returns `{:ok, [%Issue{}]}` or `{:error, reason}`.
  """
  def decompose(goal_id, opts \\ []) do
    max_issues = Keyword.get(opts, :max_issues, 10)
    auto_assign = Keyword.get(opts, :auto_assign, true)

    with %Goal{} = goal <- Repo.get(Goal, goal_id) |> Repo.preload(:project),
         workspace_id when not is_nil(workspace_id) <- goal.workspace_id,
         %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         agents <- Repo.all(from a in Agent, where: a.workspace_id == ^workspace_id),
         {:ok, issues_data} <- generate_issues(goal, workspace, agents, max_issues) do
      created_issues = create_issues(issues_data, goal, workspace_id, agents, auto_assign)
      {:ok, created_issues}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp generate_issues(goal, workspace, agents, max_issues) do
    agent_roster =
      agents
      |> Enum.map(fn a -> "- #{a.name} (#{a.role}): #{a.slug}" end)
      |> Enum.join("\n")

    project_name =
      case goal.project do
        nil -> "None"
        project -> project.name
      end

    prompt = """
    You are a project manager. Decompose the following goal into #{max_issues} or fewer actionable issues.

    ## Goal
    Title: #{goal.title}
    Description: #{goal.description || "No description provided"}
    Project: #{project_name}

    ## Available Agents
    #{agent_roster}

    ## Instructions
    Return a JSON array of issues. Each issue must have:
    - "title": string (clear, actionable task title)
    - "description": string (detailed instructions for the agent, including input files to read and output files to write)
    - "priority": "critical" | "high" | "medium" | "low"
    - "suggested_agent_slug": string (slug of the best agent for this task, from the roster above)
    - "depends_on": number (0-indexed position of another issue this depends on, or null)

    Return ONLY the JSON array, no other text. Example:
    [{"title": "...", "description": "...", "priority": "high", "suggested_agent_slug": "market-researcher", "depends_on": null}]
    """

    case run_claude_prompt(prompt, workspace.path) do
      {:ok, response} ->
        case parse_issues_json(response) do
          {:ok, issues_data} -> {:ok, sanitize_dependencies(issues_data)}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_claude_prompt(prompt, cwd) do
    claude_path = Bizforge.ClaudeBinary.find()

    case System.cmd(
           claude_path,
           ["--print", "--output-format", "text", prompt],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.error("[GoalDecomposer] Claude exited #{code}: #{String.slice(output, 0, 200)}")
        {:error, {:claude_failed, code}}
    end
  end

  defp parse_issues_json(response) do
    # Strip markdown code fences if present, then find the JSON array.
    cleaned =
      response
      |> String.replace(~r/```json\n?/, "")
      |> String.replace(~r/```\n?/, "")
      |> String.trim()

    case Regex.run(~r/\[[\s\S]*\]/, cleaned) do
      [json] ->
        case Jason.decode(json) do
          {:ok, list} when is_list(list) -> {:ok, list}
          {:ok, _} -> {:error, :unexpected_json_shape}
          {:error, _} -> {:error, :invalid_json}
        end

      nil ->
        {:error, :no_json_found}
    end
  end

  # Validate the dependency graph from LLM output and strip any cyclic edges.
  # Each issue's "depends_on" is a 0-based index into the list.
  defp sanitize_dependencies(issues_data) do
    size = length(issues_data)

    # Build adjacency: node -> list of nodes it depends on
    edges =
      issues_data
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {item, idx}, acc ->
        dep = item["depends_on"]

        if is_integer(dep) and dep >= 0 and dep < size and dep != idx do
          Map.update(acc, idx, [dep], &[dep | &1])
        else
          acc
        end
      end)

    cyclic_edges = detect_cycles(edges, size)

    if cyclic_edges == MapSet.new() do
      issues_data
    else
      Logger.warning(
        "[GoalDecomposer] Stripped #{MapSet.size(cyclic_edges)} cyclic dependency edge(s) from LLM output"
      )

      issues_data
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        if MapSet.member?(cyclic_edges, idx) do
          Map.put(item, "depends_on", nil)
        else
          item
        end
      end)
    end
  end

  # Returns a MapSet of node indices whose depends_on edges participate in a cycle.
  # Uses DFS with :unvisited / :visiting / :visited coloring.
  defp detect_cycles(edges, size) do
    initial_colors = Map.new(0..(size - 1), fn i -> {i, :unvisited} end)

    {_colors, cyclic} =
      Enum.reduce(0..(size - 1), {initial_colors, MapSet.new()}, fn node, {colors, cyclic} ->
        if Map.get(colors, node) == :unvisited do
          dfs_visit(node, edges, colors, cyclic)
        else
          {colors, cyclic}
        end
      end)

    cyclic
  end

  defp dfs_visit(node, edges, colors, cyclic) do
    colors = Map.put(colors, node, :visiting)

    deps = Map.get(edges, node, [])

    {colors, cyclic} =
      Enum.reduce(deps, {colors, cyclic}, fn dep, {c, cy} ->
        case Map.get(c, dep) do
          :visiting ->
            # Back edge detected — cycle. Mark the source node as cyclic.
            {c, MapSet.put(cy, node)}

          :unvisited ->
            dfs_visit(dep, edges, c, cy)

          :visited ->
            {c, cy}
        end
      end)

    colors = Map.put(colors, node, :visited)
    {colors, cyclic}
  end

  defp create_issues(issues_data, goal, workspace_id, agents, auto_assign) do
    agents_by_slug = Map.new(agents, fn a -> {a.slug, a} end)

    issues_data
    |> Enum.map(fn data ->
      assignee_id =
        if auto_assign do
          case Map.get(agents_by_slug, data["suggested_agent_slug"]) do
            %Agent{id: id} -> id
            nil -> nil
          end
        end

      attrs = %{
        "title" => data["title"],
        "description" => data["description"],
        "priority" => data["priority"] || "medium",
        "status" => "backlog",
        "goal_id" => goal.id,
        "project_id" => goal.project_id,
        "workspace_id" => workspace_id,
        "assignee_id" => assignee_id
      }

      case Bizforge.Work.create_issue(attrs) do
        {:ok, issue} ->
          if assignee_id do
            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.workspace_topic(workspace_id),
              %{event: "issue.assigned", issue_id: issue.id, agent_id: assignee_id}
            )
          end

          issue

        {:error, changeset} ->
          Logger.warning(
            "[GoalDecomposer] Failed to create issue #{inspect(data["title"])}: #{inspect(changeset.errors)}"
          )

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
