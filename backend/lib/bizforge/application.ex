defmodule Bizforge.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    headless_config = Application.get_env(:bizforge, :headless, [])
    headless? = Keyword.get(headless_config, :enabled, false)

    core_children = [
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
      Bizforge.Workflows.Supervisor
    ]

    children =
      if headless? do
        core_children ++
          [
            Bizforge.Headless.Monitor,
            Bizforge.Headless.Bootstrap,
            Bizforge.Headless.Watchdog,
            Bizforge.Headless.Notifier
          ]
      else
        core_children ++ [BizforgeWeb.Endpoint]
      end

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
    headless_config = Application.get_env(:bizforge, :headless, [])

    unless Keyword.get(headless_config, :enabled, false) do
      BizforgeWeb.Endpoint.config_change(changed, removed)
    end

    :ok
  end
end
