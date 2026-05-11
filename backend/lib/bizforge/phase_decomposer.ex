defmodule Bizforge.PhaseDecomposer do
  @moduledoc """
  Decomposes a phase into actionable tasks using an LLM.

  The decomposer:
  1. Reads phase + project context
  2. Reads available agents and their roles
  3. Prompts the LLM for a structured list of tasks
  4. Creates tasks in the DB with suggested assignees
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Phase, Agent, Workspace}
  import Ecto.Query

  @doc """
  Decompose a phase into tasks.

  Options:
    - :max_tasks    - maximum number of tasks to create (default: 10)
    - :auto_assign  - whether to auto-assign tasks to agents (default: true)

  Returns `{:ok, [%Task{}]}` or `{:error, reason}`.
  """
  def decompose(phase_id, opts \\ []) do
    max_tasks = Keyword.get(opts, :max_tasks, 10)
    auto_assign = Keyword.get(opts, :auto_assign, true)

    with %Phase{} = phase <- Repo.get(Phase, phase_id) |> Repo.preload(:project),
         workspace_id when not is_nil(workspace_id) <- phase.workspace_id,
         %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         agents <- Repo.all(from a in Agent, where: a.workspace_id == ^workspace_id),
         {:ok, tasks_data} <- generate_tasks(phase, workspace, agents, max_tasks) do
      created_tasks = create_tasks(tasks_data, phase, workspace_id, agents, auto_assign)
      {:ok, created_tasks}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_tasks(phase, workspace, agents, max_tasks) do
    agent_roster =
      agents
      |> Enum.map(fn a -> "- #{a.name} (#{a.role}): #{a.slug}" end)
      |> Enum.join("\n")

    project_name =
      case phase.project do
        nil -> "None"
        project -> project.name
      end

    prompt = """
    You are a project manager. Decompose the following phase into #{max_tasks} or fewer actionable tasks.

    ## Phase
    Title: #{phase.title}
    Description: #{phase.description || "No description provided"}
    Project: #{project_name}

    ## Available Agents
    #{agent_roster}

    ## Instructions
    Return a JSON array of tasks. Each task must have:
    - "title": string (clear, actionable task title)
    - "description": string (detailed instructions for the agent, including input files to read and output files to write)
    - "priority": "critical" | "high" | "medium" | "low"
    - "suggested_agent_slug": string (slug of the best agent for this task, from the roster above)
    - "depends_on": number (0-indexed position of another task this depends on, or null)

    Return ONLY the JSON array, no other text. Example:
    [{"title": "...", "description": "...", "priority": "high", "suggested_agent_slug": "market-researcher", "depends_on": null}]
    """

    case run_claude_prompt(prompt, workspace.path) do
      {:ok, response} ->
        case parse_tasks_json(response) do
          {:ok, tasks_data} -> {:ok, sanitize_dependencies(tasks_data)}
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
        Logger.error("[PhaseDecomposer] Claude exited #{code}: #{String.slice(output, 0, 200)}")
        {:error, {:claude_failed, code}}
    end
  end

  defp parse_tasks_json(response) do
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

  defp sanitize_dependencies(tasks_data) do
    size = length(tasks_data)

    edges =
      tasks_data
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
      tasks_data
    else
      Logger.warning(
        "[PhaseDecomposer] Stripped #{MapSet.size(cyclic_edges)} cyclic dependency edge(s) from LLM output"
      )

      tasks_data
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

  defp create_tasks(tasks_data, phase, workspace_id, agents, auto_assign) do
    agents_by_slug = Map.new(agents, fn a -> {a.slug, a} end)

    tasks_data
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
        "phase_id" => phase.id,
        "project_id" => phase.project_id,
        "workspace_id" => workspace_id,
        "assignee_id" => assignee_id
      }

      case Bizforge.Work.create_task(attrs) do
        {:ok, task} ->
          if assignee_id do
            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.workspace_topic(workspace_id),
              %{event: "task.assigned", task_id: task.id, agent_id: assignee_id}
            )
          end

          task

        {:error, changeset} ->
          Logger.warning(
            "[PhaseDecomposer] Failed to create task #{inspect(data["title"])}: #{inspect(changeset.errors)}"
          )

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
