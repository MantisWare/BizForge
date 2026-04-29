defmodule CanopyWeb.Plugs.Governance do
  @moduledoc """
  Plug that enforces governance gates on specific controller actions.

  Returns HTTP 202 (Accepted) with the pending approval when an action is
  blocked, halting the controller pipeline. Returns HTTP 403 when an action
  is explicitly denied.

  Usage in a controller:
    plug CanopyWeb.Plugs.Governance, action: :spawn_agent when action in [:create]
    plug CanopyWeb.Plugs.Governance, action: :delete_agent when action in [:delete]

  The plug extracts workspace_id and requester context from:
    1. conn.assigns[:current_user] — for human-initiated requests
    2. conn.params — for workspace_id, agent context
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, opts) do
    action_type = opts[:action]
    params = build_gate_params(conn, action_type)

    case Canopy.Governance.Gate.check(action_type, params) do
      :allowed ->
        conn

      {:pending_approval, approval} ->
        conn
        |> put_status(202)
        |> json(%{
          status: "pending_approval",
          approval_id: approval.id,
          message: "This action requires approval before it can proceed.",
          approval: serialize_approval(approval)
        })
        |> halt()

      {:denied, reason} ->
        conn
        |> put_status(403)
        |> json(%{error: "Action denied: #{reason}"})
        |> halt()
    end
  end

  # --- Private ---

  defp build_gate_params(conn, action_type) do
    current_user = conn.assigns[:current_user]
    params = conn.params

    base = %{
      workspace_id: params["workspace_id"],
      requester_id: requester_id(conn, params),
      requester_role: requester_role(current_user)
    }

    # Merge action-specific context from request params
    action_context =
      case action_type do
        :spawn_agent ->
          %{
            agent_id: params["agent_id"],
            name: params["name"],
            context: params["context"] || params["prompt"],
            model: params["model"]
          }

        :delete_agent ->
          %{
            agent_id: params["id"] || params["agent_id"],
            workspace_id: params["workspace_id"] || infer_workspace_from_agent(params["id"])
          }

        :budget_override ->
          %{
            amount_cents: params["amount_cents"]
          }

        :strategy_proposal ->
          %{
            title: params["title"]
          }

        _ ->
          %{}
      end

    Map.merge(base, action_context)
  end

  defp requester_id(conn, params) do
    cond do
      conn.assigns[:current_user] ->
        conn.assigns[:current_user].id

      params["agent_id"] ->
        params["agent_id"]

      true ->
        nil
    end
  end

  defp requester_role(%{role: role}), do: role
  defp requester_role(_), do: nil

  # For delete actions we may need the workspace_id from the agent record.
  # This is a best-effort lookup — the gate will handle nil workspace gracefully.
  defp infer_workspace_from_agent(nil), do: nil

  defp infer_workspace_from_agent(agent_id) do
    case Canopy.Repo.get(Canopy.Schemas.Agent, agent_id) do
      %{workspace_id: wid} -> wid
      _ -> nil
    end
  end

  defp serialize_approval(approval) do
    %{
      id: approval.id,
      title: approval.title,
      description: approval.description,
      status: approval.status,
      action_type: approval.action_type,
      auto_execute: approval.auto_execute,
      workspace_id: approval.workspace_id,
      requested_by: approval.requested_by,
      created_at: approval.inserted_at,
      updated_at: approval.updated_at
    }
  end
end
