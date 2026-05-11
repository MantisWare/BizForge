defmodule BizforgeWeb.Plugs.RateLimiter do
  @moduledoc """
  Token-bucket rate limiter using ETS.

  Limits requests per user (authenticated) or per IP (unauthenticated).
  Uses the full request path for bucket granularity so nested resources
  (e.g. /projects/:id/phases) don't starve the parent resource bucket.

  Defaults:
    - 300 req/min for authenticated API routes
    - 120 req/min for unauthenticated API routes
    - 10 req/min for auth endpoints (login/register)

  Override via application config:
    config :bizforge, BizforgeWeb.Plugs.RateLimiter,
      default_limit: 300,
      unauth_limit: 120,
      auth_limit: 10,
      window_ms: 60_000
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @table :bizforge_rate_limiter

  defp config(key, fallback) do
    Application.get_env(:bizforge, __MODULE__, [])
    |> Keyword.get(key, fallback)
  end

  def init(opts), do: opts

  def call(conn, opts) do
    limit = opts[:limit] || rate_limit_for(conn)
    window_ms = opts[:window_ms] || config(:window_ms, 60_000)
    key = bucket_key(conn)

    case check_rate(key, limit, window_ms) do
      {:ok, remaining} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(remaining))

      {:error, retry_after_ms} ->
        retry_after = max(1, div(retry_after_ms, 1000))

        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_status(429)
        |> json(%{error: "rate_limited", message: "Too many requests", retry_after: retry_after})
        |> halt()
    end
  end

  defp bucket_key(conn) do
    identifier =
      case conn.assigns[:current_user] do
        %{id: user_id} -> "user:#{user_id}"
        _ -> "ip:#{format_ip(conn.remote_ip)}"
      end

    path_segment = bucket_path(conn.path_info)

    "#{identifier}:#{path_segment}"
  end

  defp bucket_path(["api", "v1", "auth" | _]), do: "auth"
  defp bucket_path(["api", "v1", resource, id, nested | _]),
    do: "#{resource}/*/#{nested}"
  defp bucket_path(["api", "v1", resource, _id]),
    do: "#{resource}/*"
  defp bucket_path(["api", "v1", resource | _]), do: resource
  defp bucket_path(_), do: "global"

  defp rate_limit_for(conn) do
    case conn.path_info do
      ["api", "v1", "auth" | _] ->
        config(:auth_limit, 10)

      _ ->
        case conn.assigns[:current_user] do
          %{id: _} -> config(:default_limit, 300)
          _ -> config(:unauth_limit, 120)
        end
    end
  end

  defp check_rate(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)
    window_start = now - window_ms

    :ets.select_delete(@table, [
      {{key, :"$1"}, [{:<, :"$1", window_start}], [true]}
    ])

    count = :ets.select_count(@table, [{{key, :"$1"}, [], [true]}])

    if count < limit do
      :ets.insert(@table, {key, now})
      {:ok, limit - count - 1}
    else
      oldest =
        case :ets.select(@table, [{{key, :"$1"}, [], [:"$1"]}]) do
          [first | _] -> first
          [] -> now
        end

      {:error, oldest + window_ms - now}
    end
  rescue
    _ -> {:ok, limit}
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip), do: to_string(:inet.ntoa(ip))
end
