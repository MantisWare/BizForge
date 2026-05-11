defmodule BizforgeWeb.SidebarBadgeController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Notification, Approval, Task, Agent, Session}
  import Ecto.Query

  def show(conn, params) do
    workspace_id = params["workspace_id"]

    inbox_unread = count_inbox_unread(workspace_id)
    pending_approvals = count_pending_approvals(workspace_id)
    open_tasks = count_open_tasks(workspace_id)
    active_agents = count_active_agents(workspace_id)
    active_sessions = count_active_sessions(workspace_id)

    json(conn, %{
      inbox_unread: inbox_unread,
      pending_approvals: pending_approvals,
      open_tasks: open_tasks,
      active_agents: active_agents,
      active_sessions: active_sessions
    })
  end

  # --- Private helpers ---

  defp count_inbox_unread(workspace_id) do
    query =
      from n in Notification,
        where: is_nil(n.read_at) and is_nil(n.dismissed_at)

    query =
      if workspace_id,
        do: where(query, [n], n.workspace_id == ^workspace_id),
        else: query

    Repo.aggregate(query, :count)
  end

  defp count_pending_approvals(workspace_id) do
    query = from a in Approval, where: a.status == "pending"

    query =
      if workspace_id,
        do: where(query, [a], a.workspace_id == ^workspace_id),
        else: query

    Repo.aggregate(query, :count)
  end

  defp count_open_tasks(workspace_id) do
    query = from i in Task, where: i.status not in ["done", "cancelled", "closed"]

    query =
      if workspace_id,
        do: where(query, [i], i.workspace_id == ^workspace_id),
        else: query

    Repo.aggregate(query, :count)
  end

  defp count_active_agents(workspace_id) do
    query = from a in Agent, where: a.status in ["active", "working"]

    query =
      if workspace_id,
        do: where(query, [a], a.workspace_id == ^workspace_id),
        else: query

    Repo.aggregate(query, :count)
  end

  defp count_active_sessions(workspace_id) do
    query = from s in Session, where: s.status == "active"

    query =
      if workspace_id,
        do: where(query, [s], s.workspace_id == ^workspace_id),
        else: query

    Repo.aggregate(query, :count)
  end
end
