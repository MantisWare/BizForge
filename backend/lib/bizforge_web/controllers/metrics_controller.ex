defmodule BizforgeWeb.MetricsController do
  @moduledoc """
  Exposes a Prometheus-compatible `/metrics` endpoint in text format.

  Provides agent counts, task counts, budget usage, heartbeat durations,
  and system metrics for headless monitoring infrastructure.
  """
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Session}
  import Ecto.Query

  def show(conn, _params) do
    metrics = build_metrics()

    conn
    |> put_resp_content_type("text/plain; version=0.0.4; charset=utf-8")
    |> send_resp(200, metrics)
  end

  defp build_metrics do
    agents = agent_metrics()
    sessions = session_metrics()
    system = system_metrics()

    [
      "# HELP bizforge_agents_total Total number of agents",
      "# TYPE bizforge_agents_total gauge",
      "bizforge_agents_total #{agents.total}",
      "",
      "# HELP bizforge_agents_by_status Agent count per status",
      "# TYPE bizforge_agents_by_status gauge",
      Enum.map(agents.by_status, fn {status, count} ->
        "bizforge_agents_by_status{status=\"#{status}\"} #{count}"
      end),
      "",
      "# HELP bizforge_sessions_active Number of active sessions",
      "# TYPE bizforge_sessions_active gauge",
      "bizforge_sessions_active #{sessions.active}",
      "",
      "# HELP bizforge_sessions_total Total sessions created",
      "# TYPE bizforge_sessions_total counter",
      "bizforge_sessions_total #{sessions.total}",
      "",
      "# HELP bizforge_system_uptime_seconds System uptime in seconds",
      "# TYPE bizforge_system_uptime_seconds gauge",
      "bizforge_system_uptime_seconds #{system.uptime}",
      "",
      "# HELP bizforge_beam_process_count Number of BEAM processes",
      "# TYPE bizforge_beam_process_count gauge",
      "bizforge_beam_process_count #{system.process_count}",
      "",
      "# HELP bizforge_beam_memory_bytes BEAM memory usage in bytes",
      "# TYPE bizforge_beam_memory_bytes gauge",
      "bizforge_beam_memory_bytes{type=\"total\"} #{system.memory_total}",
      "bizforge_beam_memory_bytes{type=\"processes\"} #{system.memory_processes}",
      "bizforge_beam_memory_bytes{type=\"ets\"} #{system.memory_ets}",
      ""
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp agent_metrics do
    agents =
      Repo.all(from a in Agent, select: a.status)

    by_status =
      Enum.reduce(agents, %{}, fn status, acc ->
        Map.update(acc, status, 1, &(&1 + 1))
      end)

    %{
      total: length(agents),
      by_status: by_status
    }
  end

  defp session_metrics do
    active =
      Repo.aggregate(
        from(s in Session, where: s.status == "active"),
        :count
      )

    total = Repo.aggregate(Session, :count)

    %{active: active, total: total}
  end

  defp system_metrics do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    memory = :erlang.memory()

    %{
      uptime: div(uptime_ms, 1000),
      process_count: :erlang.system_info(:process_count),
      memory_total: memory[:total],
      memory_processes: memory[:processes],
      memory_ets: memory[:ets]
    }
  end
end
