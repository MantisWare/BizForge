defmodule Bizforge.Snapshots.Importer do
  @moduledoc """
  Restores a workspace from a snapshot file.

  Hydrates the database with agents, schedules, teams, and workflows
  from the snapshot, and restores workspace files to disk.
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Schedule, Workspace}
  import Ecto.Query

  def import(snapshot_file) do
    unless File.exists?(snapshot_file) do
      {:error, :not_found}
    else
      case File.read!(snapshot_file) |> Jason.decode() do
        {:ok, data} ->
          Logger.info("[Snapshots.Importer] Restoring snapshot '#{data["name"]}'")
          do_import(data)

        {:error, reason} ->
          {:error, {:parse_error, reason}}
      end
    end
  end

  defp do_import(data) do
    workspace_path = data["workspace_path"]

    workspace = ensure_workspace(workspace_path)

    restore_files(workspace_path, data)

    agents_map = restore_agents(workspace, data["agents"] || [])

    restore_schedules(agents_map, data["schedules"] || [])

    summary = %{
      workspace: workspace_path,
      agents_restored: map_size(agents_map),
      files_restored: count_files(data)
    }

    Logger.info("[Snapshots.Importer] Restore complete: #{inspect(summary)}")

    {:ok, summary}
  end

  defp ensure_workspace(workspace_path) do
    case Repo.one(from w in Workspace, where: w.path == ^workspace_path, limit: 1) do
      nil ->
        %Workspace{}
        |> Workspace.changeset(%{
          name: Path.basename(workspace_path),
          path: workspace_path,
          status: "active"
        })
        |> Repo.insert!()

      workspace ->
        workspace
    end
  end

  defp restore_files(workspace_path, data) do
    files = data["files"] || %{}

    if files["system_md"] do
      path = Path.join(workspace_path, "SYSTEM.md")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, files["system_md"])
      Logger.info("[Snapshots.Importer] Restored SYSTEM.md")
    end

    if files["company_yaml"] do
      path = Path.join(workspace_path, "company.yaml")
      File.write!(path, files["company_yaml"])
      Logger.info("[Snapshots.Importer] Restored company.yaml")
    end

    agent_files = data["agent_files"] || []
    agents_dir = Path.join(workspace_path, "agents")
    File.mkdir_p!(agents_dir)

    Enum.each(agent_files, fn af ->
      file_path = Path.join(agents_dir, af["file"])
      File.write!(file_path, af["content"])
    end)

    if length(agent_files) > 0 do
      Logger.info("[Snapshots.Importer] Restored #{length(agent_files)} agent file(s)")
    end

    skill_files = data["skill_files"] || []
    skills_dir = Path.join(workspace_path, "skills")

    Enum.each(skill_files, fn sf ->
      if sf["content"] do
        skill_dir = Path.join(skills_dir, sf["name"])
        File.mkdir_p!(skill_dir)
        File.write!(Path.join(skill_dir, "SKILL.md"), sf["content"])
      end
    end)

    if length(skill_files) > 0 do
      Logger.info("[Snapshots.Importer] Restored #{length(skill_files)} skill file(s)")
    end
  end

  defp restore_agents(workspace, agents_data) do
    Enum.reduce(agents_data, %{}, fn agent_data, acc ->
      old_id = agent_data["id"]

      existing =
        Repo.one(
          from a in Agent,
            where: a.workspace_id == ^workspace.id and a.name == ^agent_data["name"],
            limit: 1
        )

      agent =
        case existing do
          nil ->
            %Agent{}
            |> Agent.changeset(%{
              name: agent_data["name"],
              display_name: agent_data["display_name"] || agent_data["name"],
              role: agent_data["role"] || "worker",
              status: "idle",
              adapter: agent_data["adapter"],
              model: agent_data["model"],
              system_prompt: agent_data["system_prompt"],
              config: agent_data["config"] || %{},
              workspace_id: workspace.id
            })
            |> Repo.insert!()

          existing_agent ->
            existing_agent
            |> Agent.changeset(%{
              adapter: agent_data["adapter"],
              model: agent_data["model"],
              system_prompt: agent_data["system_prompt"],
              config: agent_data["config"] || %{}
            })
            |> Repo.update!()
        end

      Map.put(acc, old_id, agent.id)
    end)
  end

  defp restore_schedules(agents_map, schedules_data) do
    Enum.each(schedules_data, fn sched_data ->
      new_agent_id = Map.get(agents_map, sched_data["agent_id"])

      if new_agent_id do
        existing =
          Repo.one(
            from s in Schedule,
              where: s.agent_id == ^new_agent_id and s.name == ^sched_data["name"],
              limit: 1
          )

        unless existing do
          %Schedule{}
          |> Schedule.changeset(%{
            name: sched_data["name"],
            cron_expression: sched_data["cron_expression"],
            timezone: sched_data["timezone"] || "UTC",
            context: sched_data["context"],
            enabled: sched_data["enabled"] || true,
            agent_id: new_agent_id
          })
          |> Repo.insert()
          |> case do
            {:ok, schedule} ->
              Logger.info(
                "[Snapshots.Importer] Restored schedule '#{schedule.name}' for agent #{new_agent_id}"
              )

            {:error, changeset} ->
              Logger.warning(
                "[Snapshots.Importer] Failed to restore schedule '#{sched_data["name"]}': #{inspect(changeset.errors)}"
              )
          end
        end
      end
    end)
  end

  defp count_files(data) do
    system = if data["files"]["system_md"], do: 1, else: 0
    company = if data["files"]["company_yaml"], do: 1, else: 0
    agents = length(data["agent_files"] || [])
    skills = length(data["skill_files"] || [])
    system + company + agents + skills
  end
end
