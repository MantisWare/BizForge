defmodule BizforgeWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Plug that authenticates requests using a static API key.

  Used for CLI-to-instance communication in headless mode. The API key
  is set via `BIZFORGE_API_KEY` env var or stored in `.bizforge/auth`.

  Expects the key as a Bearer token in the Authorization header:

      Authorization: Bearer <api-key>

  If no API key is configured (both env var and auth file are absent),
  this plug passes all requests through without authentication.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_configured_key() do
      nil ->
        conn

      expected_key ->
        case get_bearer_token(conn) do
          ^expected_key ->
            conn

          nil ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{error: "API key required"}))
            |> halt()

          _wrong ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(403, Jason.encode!(%{error: "Invalid API key"}))
            |> halt()
        end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  defp get_configured_key do
    config = Application.get_env(:bizforge, :headless, [])
    env_key = Keyword.get(config, :api_key)

    if env_key !== nil do
      env_key
    else
      auth_file = Path.expand(".bizforge/auth")

      case File.read(auth_file) do
        {:ok, content} ->
          key = content |> String.trim()
          if key === "", do: nil, else: key

        {:error, _} ->
          nil
      end
    end
  end
end
