defmodule BizforgeWeb.HealthController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.Agent
  import Ecto.Query

  @start_time System.monotonic_time(:second)

  def show(conn, _params) do
    uptime_seconds = System.monotonic_time(:second) - @start_time

    agents_active =
      try do
        Repo.aggregate(from(a in Agent, where: a.status in ["active", "working"]), :count)
      rescue
        _ -> 0
      end

    db_status =
      try do
        Repo.query!("SELECT 1")
        "connected"
      rescue
        _ -> "unavailable"
      end

    json(conn, %{
      status: if(db_status == "connected", do: "ok", else: "degraded"),
      version: "1.0.0",
      provider: "anthropic",
      model: "claude-sonnet-4-20250514",
      context_window: 200_000,
      uptime_seconds: uptime_seconds,
      agents_active: agents_active,
      database: db_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
