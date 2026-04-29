defmodule Bizforge.Workspaces do
  @moduledoc "Workspace management context."

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Workspace, Agent, Skill}
  import Ecto.Query

  def list_workspaces do
    Repo.all(from w in Workspace, order_by: [desc: w.inserted_at])
  end

  def get_workspace(id), do: Repo.get(Workspace, id)
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  def get_active_workspace do
    Repo.one(from w in Workspace, where: w.status == "active", limit: 1)
  end

  def create_workspace(attrs) do
    result = %Workspace{} |> Workspace.changeset(attrs) |> Repo.insert()

    case result do
      {:ok, workspace} ->
        init_bizforge_directory(workspace.path)
        {:ok, workspace}

      error ->
        error
    end
  end

  def update_workspace(%Workspace{} = ws, attrs) do
    ws |> Workspace.changeset(attrs) |> Repo.update()
  end

  def delete_workspace(%Workspace{} = ws), do: Repo.delete(ws)

  def activate_workspace(id) do
    Repo.transaction(fn ->
      Repo.update_all(
        from(w in Workspace, where: w.status == "active"),
        set: [status: "archived"]
      )

      case get_workspace(id) do
        nil ->
          Repo.rollback(:not_found)

        ws ->
          {:ok, updated} = ws |> Ecto.Changeset.change(status: "active") |> Repo.update()
          Bizforge.EventBus.broadcast("workspace:global", {:workspace_activated, updated.id})
          updated
      end
    end)
  end

  def workspace_agent_count(workspace_id) do
    Repo.aggregate(from(a in Agent, where: a.workspace_id == ^workspace_id), :count)
  end

  def workspace_skill_count(workspace_id) do
    Repo.aggregate(from(s in Skill, where: s.workspace_id == ^workspace_id), :count)
  end

  def list_workspace_agents(workspace_id) do
    Repo.all(from a in Agent, where: a.workspace_id == ^workspace_id, order_by: [asc: a.name])
  end

  def list_workspace_skills(workspace_id) do
    Repo.all(from s in Skill, where: s.workspace_id == ^workspace_id, order_by: [asc: s.name])
  end

  def read_bizforge_config(workspace_id) do
    case get_workspace(workspace_id) do
      nil ->
        {:error, :not_found}

      workspace ->
        bizforge_dir = Path.join(workspace.path, ".bizforge")
        system = safe_read(Path.join(bizforge_dir, "SYSTEM.md"))
        company = safe_read(Path.join(bizforge_dir, "COMPANY.md"))

        {:ok,
         %{
           has_system: system != nil,
           has_company: company != nil,
           system: system,
           company: company
         }}
    end
  end

  defp init_bizforge_directory(path) when is_binary(path) do
    bizforge = Path.join(path, ".bizforge")
    File.mkdir_p!(Path.join(bizforge, "agents"))
    File.mkdir_p!(Path.join(bizforge, "skills"))
    File.mkdir_p!(Path.join(bizforge, "reference"))

    system_path = Path.join(bizforge, "SYSTEM.md")

    unless File.exists?(system_path) do
      File.write!(system_path, "# System\n\nBizforge workspace system prompt.\n")
    end
  rescue
    _ -> :ok
  end

  defp init_bizforge_directory(_), do: :ok

  defp safe_read(path) do
    case File.read(path) do
      {:ok, content} -> content
      _ -> nil
    end
  end
end
