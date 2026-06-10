defmodule BizforgeWeb.Plugs.RequestLogger do
  @moduledoc """
  Structured request/response logger for API debugging.

  Logs every API request with method, path, key params, user context,
  response status, and wall-clock timing. Sensitive params are redacted.
  """
  import Plug.Conn
  require Logger

  @sensitive_keys ~w(password password_hash token secret api_key)

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time(:microsecond)

    conn
    |> put_private(:request_logger_start, start_time)
    |> register_before_send(&log_response/1)
  end

  defp log_response(conn) do
    start_time = conn.private[:request_logger_start]

    duration_us =
      if start_time do
        System.monotonic_time(:microsecond) - start_time
      else
        0
      end

    duration_ms = Float.round(duration_us / 1000, 1)

    user_id =
      case conn.assigns[:current_user] do
        %{id: id} -> String.slice(to_string(id), 0, 8) <> "…"
        _ -> "anon"
      end

    params = sanitize_params(conn.params)

    level = if conn.status >= 400, do: :warning, else: :info

    Logger.log(level, fn ->
      "[API] #{conn.method} #{conn.request_path} → #{conn.status} (#{duration_ms}ms) " <>
        "user=#{user_id} params=#{inspect(params, limit: 200)}"
    end)

    conn
  end

  defp sanitize_params(params) when is_map(params) do
    params
    |> Map.drop(["_format", "_utf8"])
    |> Map.new(fn
      {k, _v} when k in @sensitive_keys -> {k, "[REDACTED]"}
      {k, v} when is_map(v) -> {k, sanitize_params(v)}
      pair -> pair
    end)
  end

  defp sanitize_params(other), do: other
end
