defmodule Bizforge.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BizforgeWeb.Telemetry,
      Bizforge.Repo,
      Bizforge.BudgetEnforcer,
      {Phoenix.PubSub, name: Bizforge.PubSub},
      Bizforge.IssueDispatcher,
      Bizforge.Scheduler,
      {DynamicSupervisor, name: Bizforge.AdapterSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Bizforge.HeartbeatRunner},
      {Task.Supervisor, name: Bizforge.TaskSupervisor},
      Bizforge.AlertEvaluator,
      Bizforge.StaleCleanup,
      Bizforge.IdempotencyCleanup,
      Bizforge.Workflows.Supervisor,
      BizforgeWeb.Endpoint
    ]

    # Create ETS tables before endpoint starts (avoids TOCTOU race)
    :ets.new(:bizforge_idempotency_cache, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(:bizforge_rate_limiter, [:named_table, :bag, :public, write_concurrency: true])

    opts = [strategy: :one_for_one, name: Bizforge.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, _pid} -> Bizforge.Scheduler.load_schedules()
      _ -> :ok
    end

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    BizforgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
