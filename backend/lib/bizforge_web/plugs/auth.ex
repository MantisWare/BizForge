defmodule BizforgeWeb.Plugs.Auth do
  @moduledoc "JWT authentication plug."
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    token = extract_token(conn)

    case token do
      nil ->
        Logger.debug("[Auth] No token for #{conn.method} #{conn.request_path}")

        conn
        |> put_status(401)
        |> json(%{error: "unauthorized", code: "INVALID_TOKEN"})
        |> halt()

      token ->
        try do
          with {:ok, claims} <- Bizforge.Guardian.decode_and_verify(token),
               {:ok, user} <- Bizforge.Guardian.resource_from_claims(claims) do
            conn
            |> assign(:current_user, user)
            |> assign(:claims, claims)
          else
            {:error, reason} ->
              Logger.warning("[Auth] Token rejected for #{conn.method} #{conn.request_path}: #{inspect(reason)}")

              conn
              |> put_status(401)
              |> json(%{error: "unauthorized", code: "INVALID_TOKEN"})
              |> halt()

            _ ->
              Logger.warning("[Auth] Token invalid for #{conn.method} #{conn.request_path}")

              conn
              |> put_status(401)
              |> json(%{error: "unauthorized", code: "INVALID_TOKEN"})
              |> halt()
          end
        rescue
          e ->
            Logger.error("[Auth] Exception during auth for #{conn.method} #{conn.request_path}: #{Exception.message(e)}")

            conn
            |> put_status(503)
            |> json(%{error: "service_unavailable", message: "Auth service initializing"})
            |> halt()
        end
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        token

      _ ->
        # Fallback: query param token for SSE streaming routes only
        if is_streaming_request?(conn) do
          conn.params["token"]
        else
          nil
        end
    end
  end

  defp is_streaming_request?(conn) do
    path = conn.request_path || ""
    accept = get_req_header(conn, "accept") |> List.first() || ""
    String.contains?(path, "/stream") or String.contains?(accept, "text/event-stream")
  end
end
