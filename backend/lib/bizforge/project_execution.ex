defmodule Bizforge.ProjectExecution do
  @moduledoc """
  Resolves execution paths for project-scoped tasks.

  When a heartbeat runs for a task that belongs to a project with an `output_path`,
  this module determines the correct `working_dir`, `code_dir`, and `git_root`
  so that adapters operate in the project's artifact tree instead of the
  `.bizforge/` workspace directory.

  Path resolution by task type:
    - scaffold, prerequisite → output_path (project root)
    - feature, subtask, validation → output_path/code (code subdir)
    - any other / nil → output_path
  """

  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Project, Workspace}

  @type exec_paths :: %{
          output_path: String.t(),
          working_dir: String.t(),
          code_dir: String.t(),
          git_root: String.t()
        }

  @code_task_types ~w(feature subtask validation)

  @doc """
  Resolve execution paths for a task + agent combination.

  Returns `{:ok, exec_paths}` when the task has a project with `output_path`,
  or `:no_project` when the task is not project-scoped (callers fall back to
  the workspace path).
  """
  @spec resolve_for_task(Task.t() | nil, map()) :: {:ok, exec_paths()} | :no_project | {:error, term()}
  def resolve_for_task(nil, _agent), do: :no_project

  def resolve_for_task(%Task{project_id: nil}, _agent), do: :no_project

  def resolve_for_task(%Task{project_id: project_id} = task, _agent) do
    project = Repo.get(Project, project_id)

    cond do
      project === nil ->
        Logger.warning("[ProjectExecution] Project #{project_id} not found for task #{task.id}")
        :no_project

      project.output_path === nil || project.output_path == "" ->
        {:error, {:no_output_path, project_id}}

      true ->
        output_path = Path.expand(project.output_path)
        code_dir = Path.join(output_path, "code")

        working_dir =
          if task.task_type in @code_task_types do
            ensure_dir(code_dir)
            code_dir
          else
            ensure_dir(output_path)
            output_path
          end

        {:ok,
         %{
           output_path: output_path,
           working_dir: working_dir,
           code_dir: code_dir,
           git_root: output_path
         }}
    end
  end

  @doc """
  Resolve the workspace for a heartbeat run, preferring project paths when
  a task with a project is provided.

  Returns a map compatible with `ExecutionWorkspace` (`%{path, strategy, ...}`).
  """
  @spec resolve_workspace(map(), Task.t() | nil) :: map()
  def resolve_workspace(agent, task) do
    case resolve_for_task(task, agent) do
      {:ok, exec_paths} ->
        strategy = agent_strategy(agent)

        unless File.dir?(exec_paths.working_dir) do
          Logger.warning(
            "[ProjectExecution] Working dir #{exec_paths.working_dir} does not exist on disk " <>
              "for agent #{agent.id}. The heartbeat may fail."
          )
        end

        Logger.info(
          "[ProjectExecution] Resolved project paths for agent #{agent.id}: " <>
            "working_dir=#{exec_paths.working_dir}, code_dir=#{exec_paths.code_dir}"
        )

        if strategy == :shared do
          %{path: exec_paths.working_dir, strategy: :shared, exec_paths: exec_paths}
        else
          case maybe_worktree(exec_paths) do
            {:ok, ws} ->
              Map.put(ws, :exec_paths, exec_paths)

            {:error, _reason} ->
              %{path: exec_paths.working_dir, strategy: :shared, exec_paths: exec_paths}
          end
        end

      {:error, {:no_output_path, project_id}} ->
        raise "Project #{project_id} has no output_path configured. " <>
                "Set the project's output directory before running tasks."

      :no_project ->
        resolve_workspace_only(agent)
    end
  end

  @doc "Return the code_dir for a project, or nil."
  @spec code_dir(Project.t() | nil) :: String.t() | nil
  def code_dir(%Project{output_path: path}) when is_binary(path) and path != "" do
    Path.join(Path.expand(path), "code")
  end

  def code_dir(_), do: nil

  # Falls back to the original workspace-based resolution when no project is involved.
  defp resolve_workspace_only(agent) do
    workspace_path =
      case Repo.get(Workspace, agent.workspace_id) do
        %Workspace{path: path} when is_binary(path) and path != "" ->
          path

        %Workspace{path: path_value} ->
          raise "No workspace path found for agent #{agent.id} " <>
                  "(workspace_id: #{inspect(agent.workspace_id)}, workspace.path was: #{inspect(path_value)}). " <>
                  "Set workspace.path to a valid directory before running the heartbeat."

        nil ->
          raise "No workspace found for agent #{agent.id} " <>
                  "(workspace_id: #{inspect(agent.workspace_id)}). " <>
                  "The workspace record does not exist in the database."
      end

    unless File.dir?(workspace_path) do
      Logger.warning(
        "[ProjectExecution] Workspace path #{workspace_path} does not exist on disk for agent #{agent.id}."
      )
    end

    Logger.info("[ProjectExecution] Resolved workspace path: #{workspace_path} for agent #{agent.id}")

    if agent_strategy(agent) == :shared do
      %{path: workspace_path, strategy: :shared}
    else
      case Bizforge.ExecutionWorkspace.create(workspace_path, strategy: :worktree) do
        {:ok, ws} ->
          ws

        {:error, reason} ->
          Logger.warning(
            "[ProjectExecution] Worktree creation failed (#{inspect(reason)}), using shared workspace"
          )

          %{path: workspace_path, strategy: :shared}
      end
    end
  end

  defp agent_strategy(agent) do
    if agent.config["workspace_strategy"] == "shared", do: :shared, else: :worktree
  end

  defp maybe_worktree(exec_paths) do
    git_dir = Path.join(exec_paths.git_root, ".git")

    if File.exists?(git_dir) do
      Bizforge.ExecutionWorkspace.create(exec_paths.git_root, strategy: :worktree)
    else
      {:error, :no_git}
    end
  end

  defp ensure_dir(path) do
    unless File.dir?(path) do
      File.mkdir_p(path)
    end
  end
end
