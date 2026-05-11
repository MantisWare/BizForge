defmodule Bizforge.Headless.HealthPlug do
  @moduledoc """
  Minimal Plug router for the dedicated headless health check endpoint.

  Runs on a separate port (default 9090) and serves:
    - GET /health — JSON system status
    - GET /metrics — Prometheus-compatible text metrics

  Protected by API key auth when configured.
  """
  use Plug.Router

  plug BizforgeWeb.Plugs.ApiKeyAuth, role: :viewer
  plug :match
  plug :dispatch

  get "/health" do
    body =
      build_health_response()
      |> Bizforge.Headless.SecretScrubber.scrub_map()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  get "/metrics" do
    metrics = build_prometheus_metrics()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end

  defp build_health_response do
    import Ecto.Query

    started_at = get_started_at()
    now = DateTime.utc_now()

    uptime_seconds =
      case started_at do
        nil -> 0
        ts -> DateTime.diff(now, ts, :second)
      end

    active_agents =
      Bizforge.Repo.aggregate(
        from(a in Bizforge.Schemas.Agent, where: a.status in ["active", "working", "idle"]),
        :count
      )

    errored_agents =
      Bizforge.Repo.aggregate(
        from(a in Bizforge.Schemas.Agent, where: a.status == "error"),
        :count
      )

    paused_agents =
      Bizforge.Repo.aggregate(
        from(a in Bizforge.Schemas.Agent, where: a.status == "paused"),
        :count
      )

    active_tasks =
      Bizforge.Repo.aggregate(
        from(i in Bizforge.Schemas.Task, where: i.status in ["in_progress", "in_review"]),
        :count
      )

    completed_tasks =
      Bizforge.Repo.aggregate(
        from(i in Bizforge.Schemas.Task, where: i.status == "done"),
        :count
      )

    active_sessions =
      Bizforge.Repo.aggregate(
        from(s in Bizforge.Schemas.Session, where: s.status == "active"),
        :count
      )

    memory = :erlang.memory()

    %{
      status: "healthy",
      timestamp: DateTime.to_iso8601(now),
      uptime_seconds: uptime_seconds,
      agents: %{
        active: active_agents,
        errored: errored_agents,
        paused: paused_agents
      },
      tasks: %{
        active: active_tasks,
        completed: completed_tasks
      },
      sessions: %{
        active: active_sessions
      },
      system: %{
        memory_mb: div(memory[:total], 1_048_576),
        process_count: :erlang.system_info(:process_count),
        scheduler_count: :erlang.system_info(:schedulers_online)
      }
    }
  end

  defp build_prometheus_metrics do
    import Ecto.Query

    active_agents =
      Bizforge.Repo.aggregate(
        from(a in Bizforge.Schemas.Agent, where: a.status in ["active", "working", "idle"]),
        :count
      )

    errored_agents =
      Bizforge.Repo.aggregate(
        from(a in Bizforge.Schemas.Agent, where: a.status == "error"),
        :count
      )

    active_sessions =
      Bizforge.Repo.aggregate(
        from(s in Bizforge.Schemas.Session, where: s.status == "active"),
        :count
      )

    memory = :erlang.memory()

    """
    # HELP bizforge_agents_active Number of active agents
    # TYPE bizforge_agents_active gauge
    bizforge_agents_active #{active_agents}
    # HELP bizforge_agents_errored Number of errored agents
    # TYPE bizforge_agents_errored gauge
    bizforge_agents_errored #{errored_agents}
    # HELP bizforge_sessions_active Number of active sessions
    # TYPE bizforge_sessions_active gauge
    bizforge_sessions_active #{active_sessions}
    # HELP bizforge_memory_bytes Total VM memory in bytes
    # TYPE bizforge_memory_bytes gauge
    bizforge_memory_bytes #{memory[:total]}
    # HELP bizforge_process_count Number of BEAM processes
    # TYPE bizforge_process_count gauge
    bizforge_process_count #{:erlang.system_info(:process_count)}
    """
  end

  defp get_started_at do
    try do
      :sys.get_state(Bizforge.Headless.Monitor).started_at
    catch
      _, _ -> nil
    end
  end
end
