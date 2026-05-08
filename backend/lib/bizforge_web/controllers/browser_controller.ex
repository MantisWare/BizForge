defmodule BizforgeWeb.BrowserController do
  @moduledoc """
  REST interface for browser automation tools.

  Used by bash-adapter agents that cannot inject LLM tool calls natively.
  Authenticates via session token and validates ToolPermission server-side.
  """
  use BizforgeWeb, :controller

  alias Bizforge.Browser.Tools

  def call(conn, %{"method" => method} = params) do
    agent_id = resolve_agent_id(conn, params)

    if agent_id === nil do
      conn |> put_status(401) |> json(%{error: "agent_id required"})
    else
      tool_params = Map.drop(params, ["method", "agent_id", "session_id"])

      case Tools.dispatch(method, tool_params, agent_id) do
        {:ok, result} ->
          conn |> put_status(200) |> json(%{ok: true, result: result})

        {:error, :permission_denied} ->
          conn
          |> put_status(403)
          |> json(%{error: "browser_automation permission not granted for this agent"})

        {:error, :sidecar_not_ready} ->
          conn
          |> put_status(503)
          |> json(%{error: "Browser sidecar not ready"})

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Browser tool error", details: to_string(reason)})
      end
    end
  end

  defp resolve_agent_id(conn, params) do
    params["agent_id"] || conn.assigns[:agent_id] || extract_agent_from_session(params)
  end

  defp extract_agent_from_session(%{"session_id" => session_id}) when is_binary(session_id) do
    case Bizforge.Repo.get(Bizforge.Schemas.Session, session_id) do
      nil -> nil
      session -> session.agent_id
    end
  end

  defp extract_agent_from_session(_), do: nil
end
