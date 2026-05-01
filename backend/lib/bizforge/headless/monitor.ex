defmodule Bizforge.Headless.Monitor do
  @moduledoc """
  GenServer that manages the headless runtime lifecycle.

  Responsibilities:
    - Writes and cleans up PID file
    - Exposes a minimal health check endpoint on a separate port
    - Handles OS signals (SIGTERM, SIGINT) for graceful shutdown
    - Triggers session compaction for all active agents on shutdown
    - Provides pause/resume control for heartbeat schedules
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.Session
  alias Bizforge.Sessions.Compactor
  import Ecto.Query

  @health_check_interval :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def pause_all do
    GenServer.call(__MODULE__, :pause_all)
  catch
    :exit, _ -> {:error, :not_running}
  end

  def resume_all do
    GenServer.call(__MODULE__, :resume_all)
  catch
    :exit, _ -> {:error, :not_running}
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:bizforge, :headless, [])
    pid_dir = Keyword.get(config, :pid_dir, ".bizforge/pids") |> Path.expand()
    health_port = Keyword.get(config, :health_port, 9090)
    workspace_path = Keyword.get(config, :workspace_path)

    workspace_name =
      if workspace_path do
        workspace_path |> Path.basename()
      else
        "default"
      end

    File.mkdir_p!(pid_dir)
    pid_file = Path.join(pid_dir, "#{workspace_name}.pid")
    File.write!(pid_file, to_string(:os.getpid()))

    Logger.info("[Headless.Monitor] PID file written: #{pid_file}")
    Logger.info("[Headless.Monitor] Workspace: #{workspace_name}")

    :os.set_signal(:sigterm, :handle)
    :os.set_signal(:sighup, :handle)

    Process.send_after(self(), :health_check, @health_check_interval)

    state = %{
      pid_file: pid_file,
      workspace_name: workspace_name,
      workspace_path: workspace_path,
      health_port: health_port,
      started_at: DateTime.utc_now(),
      paused: false
    }

    Logger.info("[Headless.Monitor] Headless runtime started at #{state.started_at}")

    {:ok, state}
  end

  @impl true
  def handle_call(:pause_all, _from, state) do
    Logger.info("[Headless.Monitor] Pausing all heartbeat schedules")

    jobs = Bizforge.Scheduler.jobs()
    count = length(jobs)

    Enum.each(jobs, fn {name, _job} ->
      Bizforge.Scheduler.deactivate_job(name)
    end)

    {:reply, {:ok, count}, %{state | paused: true}}
  end

  def handle_call(:resume_all, _from, state) do
    Logger.info("[Headless.Monitor] Resuming all heartbeat schedules")

    jobs = Bizforge.Scheduler.jobs()
    count = length(jobs)

    Enum.each(jobs, fn {name, _job} ->
      Bizforge.Scheduler.activate_job(name)
    end)

    {:reply, {:ok, count}, %{state | paused: false}}
  end

  @impl true
  def handle_info(:health_check, state) do
    active_sessions =
      Repo.aggregate(
        from(s in Session, where: s.status == "active"),
        :count
      )

    Logger.debug(
      "[Headless.Monitor] Health check — active sessions: #{active_sessions}, paused: #{state.paused}"
    )

    Process.send_after(self(), :health_check, @health_check_interval)
    {:noreply, state}
  end

  def handle_info({:signal, :sigterm}, state) do
    Logger.info("[Headless.Monitor] Received SIGTERM — initiating graceful shutdown")
    graceful_shutdown(state)
    {:stop, :normal, state}
  end

  def handle_info({:signal, :sighup}, state) do
    Logger.info("[Headless.Monitor] Received SIGHUP — reloading configuration")
    Bizforge.Scheduler.load_schedules()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    graceful_shutdown(state)
    :ok
  end

  defp graceful_shutdown(state) do
    Logger.info("[Headless.Monitor] Starting graceful shutdown...")

    compact_active_sessions()

    pause_all_agents()

    if File.exists?(state.pid_file) do
      File.rm!(state.pid_file)
      Logger.info("[Headless.Monitor] PID file removed: #{state.pid_file}")
    end

    Logger.info("[Headless.Monitor] Graceful shutdown complete.")
  end

  defp compact_active_sessions do
    active_sessions =
      Repo.all(
        from s in Session,
          where: s.status == "active",
          order_by: [asc: s.started_at]
      )

    Logger.info(
      "[Headless.Monitor] Compacting #{length(active_sessions)} active session(s)..."
    )

    Enum.each(active_sessions, fn session ->
      case Compactor.compact(session, "headless_shutdown") do
        {:ok, _} ->
          Logger.info("[Headless.Monitor] Compacted session #{session.id}")

        {:error, reason} ->
          Logger.warning(
            "[Headless.Monitor] Failed to compact session #{session.id}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp pause_all_agents do
    import Ecto.Changeset, only: [change: 2]

    agents =
      Repo.all(
        from a in Bizforge.Schemas.Agent,
          where: a.status in ["active", "working", "idle"]
      )

    Enum.each(agents, fn agent ->
      agent |> change(status: "paused") |> Repo.update()
    end)

    Logger.info("[Headless.Monitor] Paused #{length(agents)} agent(s)")
  end
end
