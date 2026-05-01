defmodule BizforgeWeb.Plugs.WorkspaceAuth do
  @moduledoc """
  Validates that the current user owns (or has access to) the workspace
  referenced in the request params.

  Extracts `workspace_id` from:
    1. `params["workspace_id"]` (query string or body)
    2. Resource's `workspace_id` for show/update/delete on nested resources

  If no `workspace_id` is present in the request, the plug passes through
  (the endpoint may not be workspace-scoped). When a `workspace_id` IS
  present, the plug verifies the authenticated user owns that workspace.

  Must be placed AFTER `BizforgeWeb.Plugs.Auth` in the pipeline so that
  `conn.assigns.current_user` is available.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  import Ecto.Query

  alias Bizforge.Repo
  alias Bizforge.Schemas.Workspace

  def init(opts), do: opts

  def call(conn, _opts) do
    workspace_id = conn.params["workspace_id"]
    user = conn.assigns[:current_user]

    cond do
      # No workspace_id in params — scope to all workspaces owned by the current user
      is_nil(workspace_id) or workspace_id == "" ->
        assign(conn, :user_workspace_ids, user_workspace_ids(user))

      # workspace_id is not a valid UUID (e.g. mock-generated ID) — ignore it
      !valid_uuid?(workspace_id) ->
        assign(conn, :user_workspace_ids, user_workspace_ids(user))

      # Validate ownership when workspace_id is present
      true ->
        case Repo.get(Workspace, workspace_id) do
          %Workspace{owner_id: owner_id} = workspace when owner_id == user.id ->
            conn
            |> assign(:workspace, workspace)
            |> assign(:user_workspace_ids, [workspace_id])

          %Workspace{} ->
            conn
            |> put_status(403)
            |> json(%{error: "forbidden", message: "You do not have access to this workspace"})
            |> halt()

          nil ->
            # Workspace not found — fall back to all user workspaces instead of 404.
            # The frontend may send stale or mock-generated workspace IDs during
            # mode transitions; rejecting them blocks every scoped page on first load.
            assign(conn, :user_workspace_ids, user_workspace_ids(user))
        end
    end
  end

  defp user_workspace_ids(user) do
    Repo.all(from w in Workspace, where: w.owner_id == ^user.id, select: w.id)
  end

  defp valid_uuid?(str) do
    case Ecto.UUID.cast(str) do
      {:ok, _} -> true
      :error -> false
    end
  end
end
