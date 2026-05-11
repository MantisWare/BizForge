defmodule Bizforge.TaskContext do
  @moduledoc """
  Pure functions for building structured context strings that are injected
  into an agent's prompt when it is assigned a task.

  Callers are responsible for preloading associations before calling
  `build_context/2`:

      task
      |> Repo.preload([:workspace, phase: :project])

      agent
      |> Repo.preload(:workspace)
  """

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Task, MemoryEntry}
  import Ecto.Query

  @spec build_context(Task.t(), Agent.t()) :: String.t()
  def build_context(%Task{} = task, %Agent{} = agent) do
    phase_title = phase_title(task)
    project_name = project_name(task)
    workspace_path = workspace_path(agent)

    forgemap_section = build_forgemap_section(task)
    deps_section = build_deps_section(task)

    """
    ## Assigned Task

    **Task:** #{task.title}
    **Priority:** #{task.priority}
    **Phase:** #{phase_title}
    **Project:** #{project_name}
    #{if task.task_type, do: "**Task Type:** #{task.task_type}", else: ""}

    ### Description
    #{task.description || "No description provided."}
    #{deps_section}
    #{forgemap_section}

    ### Instructions
    - Read any referenced input files before starting
    - Write your output to the appropriate output/ subdirectory
    - Follow the methodology defined in your system prompt
    - Ensure output meets quality gates defined in the workspace spec
    - When modifying files, update their ForgeMap header annotations

    ### Workspace
    - Path: #{workspace_path}
    - Your role: #{agent.role}
    """
    |> String.trim_trailing()
  end

  defp phase_title(%Task{phase: %{title: title}}) when is_binary(title), do: title
  defp phase_title(_task), do: "None"

  defp project_name(%Task{phase: %{project: %{name: name}}}) when is_binary(name), do: name
  defp project_name(_task), do: "None"

  defp workspace_path(%Agent{workspace: %{path: path}}) when is_binary(path), do: path
  defp workspace_path(_agent), do: "Unknown"

  defp build_forgemap_section(%Task{project_id: nil}), do: ""

  defp build_forgemap_section(%Task{project_id: project_id} = task) do
    keywords = extract_keywords(task)

    all_entries =
      Repo.all(
        from m in MemoryEntry,
          where:
            m.project_id == ^project_id and
              m.source == "forgemap",
          order_by: [asc: m.key]
      )

    entries =
      if keywords === [] do
        Enum.take(all_entries, 15)
      else
        scored =
          Enum.map(all_entries, fn entry ->
            searchable =
              String.downcase(
                (entry.key || "") <> " " <> Enum.join(entry.tags || [], " ")
              )

            score = Enum.count(keywords, fn kw -> String.contains?(searchable, kw) end)
            {entry, score}
          end)

        scored
        |> Enum.filter(fn {_e, score} -> score > 0 end)
        |> Enum.sort_by(fn {_e, score} -> -score end)
        |> Enum.take(15)
        |> Enum.map(fn {e, _score} -> e end)
      end

    if entries === [] do
      ""
    else
      file_summaries =
        Enum.map_join(entries, "\n", fn e ->
          "- `#{e.key}`: #{String.slice(e.content || "", 0..200)}"
        end)

      """

      ### ForgeMap (Relevant Files)
      #{file_summaries}
      """
    end
  end

  defp build_deps_section(%Task{depends_on_ids: ids}) when is_list(ids) and ids !== [] do
    dep_tasks =
      Repo.all(from t in Task, where: t.id in ^ids, select: {t.id, t.title, t.status})

    lines =
      Enum.map_join(dep_tasks, "\n", fn {_id, title, status} ->
        "- #{title} (#{status})"
      end)

    """

    ### Dependencies
    #{lines}
    """
  end

  defp build_deps_section(_task), do: ""

  defp extract_keywords(%Task{} = task) do
    text = "#{task.title} #{task.description || ""}"

    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split()
    |> Enum.reject(&(String.length(&1) < 4))
    |> Enum.uniq()
    |> Enum.take(10)
  end
end
