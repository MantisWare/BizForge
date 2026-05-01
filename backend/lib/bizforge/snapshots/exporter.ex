defmodule Bizforge.Snapshots.Exporter do
  @moduledoc """
  Serializes a workspace into a deployable snapshot.

  Captures both DB state (agents, teams, workflows, budgets, org hierarchy)
  and filesystem state (SYSTEM.md, company.yaml, agent manifests, skill files).
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Workspace, Schedule}
  import Ecto.Query

  def export(name, workspace_path, snapshot_dir) do
    File.mkdir_p!(snapshot_dir)
    snapshot_file = Path.join(snapshot_dir, "#{name}.json")

    workspace_path = Path.expand(workspace_path)

    Logger.info("[Snapshots.Exporter] Creating snapshot '#{name}' from #{workspace_path}")

    workspace = find_workspace(workspace_path)

    snapshot = %{
      name: name,
      version: "1.0",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      workspace_path: workspace_path,
      agents: export_agents(workspace),
      schedules: export_schedules(workspace),
      teams: export_teams(workspace),
      workflows: export_workflows(workspace),
      files: %{
        system_md: read_file(workspace_path, "SYSTEM.md"),
        company_yaml: read_file(workspace_path, "company.yaml")
      },
      agent_files: collect_agent_files(workspace_path),
      skill_files: collect_skill_files(workspace_path),
      integrity: compute_integrity(workspace_path)
    }

    File.write!(snapshot_file, Jason.encode!(snapshot, pretty: true))

    Logger.info("[Snapshots.Exporter] Snapshot saved: #{snapshot_file}")

    {:ok, snapshot_file, summary(snapshot)}
  end

  defp find_workspace(workspace_path) do
    Repo.one(
      from w in Workspace,
        where: w.path == ^workspace_path,
        limit: 1
    )
  end

  defp export_agents(nil), do: []

  defp export_agents(workspace) do
    Repo.all(
      from a in Agent,
        where: a.workspace_id == ^workspace.id,
        order_by: [asc: a.name]
    )
    |> Enum.map(fn agent ->
      %{
        id: agent.id,
        name: agent.name,
        display_name: agent.display_name,
        role: agent.role,
        status: agent.status,
        adapter: agent.adapter,
        model: agent.model,
        system_prompt: agent.system_prompt,
        config: agent.config
      }
    end)
  end

  defp export_schedules(nil), do: []

  defp export_schedules(workspace) do
    agents =
      Repo.all(from a in Agent, where: a.workspace_id == ^workspace.id, select: a.id)

    if agents === [] do
      []
    else
      Repo.all(
        from s in Schedule,
          where: s.agent_id in ^agents,
          order_by: [asc: s.name]
      )
      |> Enum.map(fn schedule ->
        %{
          id: schedule.id,
          name: schedule.name,
          cron_expression: schedule.cron_expression,
          timezone: schedule.timezone,
          context: schedule.context,
          enabled: schedule.enabled,
          agent_id: schedule.agent_id
        }
      end)
    end
  end

  defp export_teams(nil), do: []

  defp export_teams(workspace) do
    case Repo.all(
           from t in Bizforge.Schemas.Team,
             where: t.workspace_id == ^workspace.id,
             order_by: [asc: t.name]
         ) do
      teams ->
        Enum.map(teams, fn team ->
          %{
            id: team.id,
            name: team.name,
            description: Map.get(team, :description)
          }
        end)
    end
  rescue
    _ -> []
  end

  defp export_workflows(nil), do: []

  defp export_workflows(workspace) do
    case Repo.all(
           from w in Bizforge.Schemas.Workflow,
             where: w.workspace_id == ^workspace.id,
             order_by: [asc: w.name]
         ) do
      workflows ->
        Enum.map(workflows, fn wf ->
          %{
            id: wf.id,
            name: wf.name,
            status: wf.status,
            trigger_type: wf.trigger_type,
            trigger_config: wf.trigger_config
          }
        end)
    end
  rescue
    _ -> []
  end

  defp collect_agent_files(workspace_path) do
    agents_dir = Path.join(workspace_path, "agents")

    if File.dir?(agents_dir) do
      agents_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.sort()
      |> Enum.map(fn file ->
        %{
          file: file,
          content: File.read!(Path.join(agents_dir, file))
        }
      end)
    else
      []
    end
  end

  defp collect_skill_files(workspace_path) do
    skills_dir = Path.join(workspace_path, "skills")

    if File.dir?(skills_dir) do
      skills_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(skills_dir, &1)))
      |> Enum.sort()
      |> Enum.map(fn dir ->
        skill_file = Path.join([skills_dir, dir, "SKILL.md"])

        %{
          name: dir,
          content: read_file(skills_dir, Path.join(dir, "SKILL.md"))
        }
      end)
    else
      []
    end
  end

  defp read_file(base, name) do
    path = Path.join(base, name)

    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp compute_integrity(workspace_path) do
    files =
      [
        Path.join(workspace_path, "SYSTEM.md"),
        Path.join(workspace_path, "company.yaml")
      ]
      |> Enum.filter(&File.exists?/1)

    agents_dir = Path.join(workspace_path, "agents")

    agent_files =
      if File.dir?(agents_dir) do
        agents_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&Path.join(agents_dir, &1))
        |> Enum.sort()
      else
        []
      end

    all_files = files ++ agent_files

    Enum.reduce(all_files, :crypto.hash_init(:sha256), fn file, acc ->
      :crypto.hash_update(acc, File.read!(file))
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp summary(snapshot) do
    %{
      name: snapshot.name,
      agents: length(snapshot.agents),
      schedules: length(snapshot.schedules),
      teams: length(snapshot.teams),
      workflows: length(snapshot.workflows),
      agent_files: length(snapshot.agent_files),
      skill_files: length(snapshot.skill_files),
      integrity: snapshot.integrity
    }
  end
end
