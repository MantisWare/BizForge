defmodule BizforgeWeb.Plugs.CORS do
  @moduledoc """
  CORS plug for the Bizforge API.

  Allowed origins are configurable via the :bizforge, :cors_origins application env.
  Defaults to localhost development ports. In production, set to your actual domain.

  Uses `register_before_send` to guarantee CORS headers appear on every response,
  including 500 error responses rendered by Phoenix's exception handler — those
  bypass normal plug pipelines and would otherwise strip the headers.
  """
  import Plug.Conn

  @default_origins [
    "http://localhost:5200",
    "http://localhost:8089",
    "http://127.0.0.1:5200",
    "http://127.0.0.1:8089",
    "tauri://localhost"
  ]

  @cors_methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  @cors_headers "authorization, content-type, accept, cache-control, x-accel-buffering, idempotency-key"
  @cors_max_age "86400"

  def init(opts), do: opts

  def call(%{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    conn
    |> put_cors_headers()
    |> register_before_send(&ensure_cors_headers/1)
  end

  defp put_cors_headers(conn) do
    allow_origin = resolve_origin(conn)

    conn
    |> put_resp_header("access-control-allow-origin", allow_origin)
    |> put_resp_header("access-control-allow-methods", @cors_methods)
    |> put_resp_header("access-control-allow-headers", @cors_headers)
    |> put_resp_header("access-control-max-age", @cors_max_age)
    |> put_resp_header("vary", "Origin")
  end

  # Runs just before every response is sent. If the CORS headers were stripped
  # (e.g. by Phoenix error rendering), re-inject them so the browser accepts
  # the response instead of raising an opaque CORS error.
  defp ensure_cors_headers(conn) do
    if get_resp_header(conn, "access-control-allow-origin") == [] do
      put_cors_headers(conn)
    else
      conn
    end
  end

  defp resolve_origin(conn) do
    origin = get_req_header(conn, "origin") |> List.first()
    allowed_origins = Application.get_env(:bizforge, :cors_origins, @default_origins)

    cond do
      origin in allowed_origins -> origin
      "*" in allowed_origins -> "*"
      true -> List.first(allowed_origins) || "http://localhost:5200"
    end
  end
end
