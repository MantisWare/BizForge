defmodule BizforgeWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Plug that authenticates requests using API keys with role-based access.

  Supports two roles:
    - `operator` — full control (pause, resume, stop, read)
    - `viewer` — read-only access (stats, logs, health)

  Keys are resolved from:
    1. `BIZFORGE_API_KEY` env var (operator role)
    2. `.bizforge/auth` file (operator role)
    3. `.bizforge/auth.json` file (multiple keys with roles)
    4. Token rotation (current + grace-period previous key)

  Expects the key as a Bearer token:
      Authorization: Bearer <api-key>

  If no API key is configured, passes all requests through.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    required_role = Keyword.get(opts, :role, :any)

    case get_valid_keys() do
      [] ->
        conn

      keys ->
        case get_bearer_token(conn) do
          nil ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{error: "API key required"}))
            |> halt()

          token ->
            case find_matching_key(keys, token) do
              nil ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(403, Jason.encode!(%{error: "Invalid API key"}))
                |> halt()

              %{role: role} ->
                if role_sufficient?(role, required_role) do
                  conn |> assign(:api_role, role)
                else
                  conn
                  |> put_resp_content_type("application/json")
                  |> send_resp(403, Jason.encode!(%{error: "Insufficient permissions", required: to_string(required_role)}))
                  |> halt()
                end
            end
        end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  defp get_valid_keys do
    keys_from_config() ++ keys_from_auth_json() ++ keys_from_rotation()
  end

  defp keys_from_config do
    config = Application.get_env(:bizforge, :headless, [])
    env_key = Keyword.get(config, :api_key)

    if env_key !== nil do
      [%{key: env_key, role: :operator}]
    else
      auth_file = Path.expand(".bizforge/auth")

      case File.read(auth_file) do
        {:ok, content} ->
          key = content |> String.trim()
          if key === "", do: [], else: [%{key: key, role: :operator}]

        {:error, _} ->
          []
      end
    end
  end

  defp keys_from_auth_json do
    auth_json = Path.expand(".bizforge/auth.json")

    case File.read(auth_json) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"keys" => keys}} when is_list(keys) ->
            Enum.map(keys, fn entry ->
              role =
                case Map.get(entry, "role", "viewer") do
                  "operator" -> :operator
                  _ -> :viewer
                end

              %{key: Map.get(entry, "key"), role: role}
            end)
            |> Enum.filter(fn e -> e.key !== nil end)

          _ ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp keys_from_rotation do
    try do
      Bizforge.Headless.TokenRotator.current_keys()
      |> Enum.map(fn key -> %{key: key, role: :operator} end)
    catch
      _, _ -> []
    end
  end

  defp find_matching_key(keys, token) do
    Enum.find(keys, fn %{key: key} -> key === token end)
  end

  defp role_sufficient?(_role, :any), do: true
  defp role_sufficient?(:operator, :operator), do: true
  defp role_sufficient?(:operator, :viewer), do: true
  defp role_sufficient?(:viewer, :viewer), do: true
  defp role_sufficient?(_role, _required), do: false
end
