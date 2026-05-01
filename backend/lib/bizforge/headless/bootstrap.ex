defmodule Bizforge.Headless.Bootstrap do
  @moduledoc """
  GenServer that bootstraps all workspace agents on headless boot.

  On init, queries all agents with active/idle status, ensures their
  schedules are registered in Quantum, and optionally fires an initial
  heartbeat for agents without a schedule.
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Schedule}
  import Ecto.Query

  @boot_delay :timer.seconds(3)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :bootstrap, @boot_delay)
    {:ok, %{bootstrapped: false}}
  end

  @impl true
  def handle_info(:bootstrap, state) do
    Logger.info("[Headless.Bootstrap] Starting workspace bootstrap...")

    cleanup_orphaned_pids()
    recover_stuck_agents()

    agents = load_workspace_agents()
    schedules = load_enabled_schedules()

    Logger.info(
      "[Headless.Bootstrap] Found #{length(agents)} agent(s), #{length(schedules)} schedule(s)"
    )

    scheduled_agent_ids = MapSet.new(schedules, & &1.agent_id)

    Enum.each(schedules, fn schedule ->
      case Bizforge.Scheduler.add_schedule(schedule) do
        :ok ->
          Logger.info(
            "[Headless.Bootstrap] Registered schedule '#{schedule.name}' for agent #{schedule.agent_id}"
          )

        {:error, reason} ->
          Logger.warning(
            "[Headless.Bootstrap] Failed to register schedule '#{schedule.name}': #{inspect(reason)}"
          )
      end
    end)

    unscheduled_agents =
      Enum.reject(agents, fn agent ->
        MapSet.member?(scheduled_agent_ids, agent.id)
      end)

    Logger.info(
      "[Headless.Bootstrap] #{length(unscheduled_agents)} agent(s) without schedules"
    )

    adapter_issues = check_adapter_availability(agents)

    print_boot_summary(agents, schedules, unscheduled_agents)

    Bizforge.Headless.Notifier.notify("workspace.boot_complete", %{
      agents: length(agents),
      schedules: length(schedules),
      unscheduled: length(unscheduled_agents),
      adapter_issues: adapter_issues
    })

    {:noreply, %{state | bootstrapped: true}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp cleanup_orphaned_pids do
    pid_dir =
      Application.get_env(:bizforge, :headless, [])
      |> Keyword.get(:pid_dir, ".bizforge/pids")
      |> Path.expand()

    if File.dir?(pid_dir) do
      pid_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".pid"))
      |> Enum.each(fn file ->
        pid_file = Path.join(pid_dir, file)
        pid = pid_file |> File.read!() |> String.trim()
        current_pid = :os.getpid() |> to_string()

        if pid !== current_pid do
          case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
            {_, 0} ->
              Logger.info("[Headless.Bootstrap] Found running instance PID #{pid} (#{file})")

            _ ->
              Logger.warning("[Headless.Bootstrap] Cleaning up orphaned PID file: #{file}")
              File.rm(pid_file)
          end
        end
      end)
    end
  end

  defp recover_stuck_agents do
    import Ecto.Changeset, only: [change: 2]

    stuck =
      Repo.all(
        from a in Agent,
          where: a.status == "working"
      )

    if length(stuck) > 0 do
      Logger.warning(
        "[Headless.Bootstrap] Found #{length(stuck)} agent(s) stuck in 'working' — resetting to 'idle'"
      )

      Enum.each(stuck, fn agent ->
        agent |> change(status: "idle") |> Repo.update()
      end)
    end
  end

  defp load_workspace_agents do
    config = Application.get_env(:bizforge, :headless, [])
    workspace_path = Keyword.get(config, :workspace_path)

    query =
      from a in Agent,
        where: a.status in ["active", "idle"],
        order_by: [asc: a.name]

    query =
      if workspace_path do
        workspace =
          Repo.one(
            from w in Bizforge.Schemas.Workspace,
              where: w.path == ^workspace_path,
              limit: 1
          )

        if workspace do
          from a in query, where: a.workspace_id == ^workspace.id
        else
          query
        end
      else
        query
      end

    Repo.all(query)
  end

  defp load_enabled_schedules do
    Repo.all(
      from s in Schedule,
        where: s.enabled == true,
        preload: [:agent]
    )
  end

  defp check_adapter_availability(agents) do
    adapters =
      agents
      |> Enum.map(& &1.adapter)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.reduce(adapters, [], fn adapter_name, issues ->
      case Bizforge.Adapter.resolve(adapter_name) do
        {:ok, mod} ->
          if function_exported?(mod, :health, 0) do
            case mod.health() do
              :ok ->
                Logger.info("[Headless.Bootstrap] Adapter '#{adapter_name}' is healthy")
                issues

              {:error, reason} ->
                Logger.warning(
                  "[Headless.Bootstrap] Adapter '#{adapter_name}' unhealthy: #{inspect(reason)}"
                )

                [%{adapter: adapter_name, issue: "unhealthy", reason: inspect(reason)} | issues]
            end
          else
            Logger.debug("[Headless.Bootstrap] Adapter '#{adapter_name}' resolved (no health check)")
            issues
          end

        {:error, _} ->
          Logger.warning("[Headless.Bootstrap] Adapter '#{adapter_name}' not found")
          [%{adapter: adapter_name, issue: "not_found"} | issues]
      end
    end)
  end

  defp print_boot_summary(agents, schedules, unscheduled) do
    IO.puts("")
    IO.puts("  Boot Summary")
    IO.puts("  ============")
    IO.puts("  Agents:     #{length(agents)}")
    IO.puts("  Schedules:  #{length(schedules)}")
    IO.puts("  Unscheduled: #{length(unscheduled)}")
    IO.puts("")

    if length(agents) > 0 do
      IO.puts("  Agents:")

      Enum.each(agents, fn agent ->
        adapter = Map.get(agent, :adapter, "none")
        IO.puts("    - #{agent.name} (#{agent.status}, adapter: #{adapter})")
      end)

      IO.puts("")
    end

    IO.puts("  All agents bootstrapped. Heartbeats will fire on schedule.")
    IO.puts("")
  end
end
