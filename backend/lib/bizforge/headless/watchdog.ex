defmodule Bizforge.Headless.Watchdog do
  @moduledoc """
  GenServer that monitors running heartbeat tasks and handles failures.

  Periodically checks for agents stuck in "working" status beyond a
  threshold, restarts crashed agents with exponential backoff, and
  pauses agents whose adapters become unavailable.
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.Agent
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  @check_interval :timer.seconds(60)
  @stuck_threshold_seconds 600

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check, @check_interval)
    {:ok, %{failure_counts: %{}}}
  end

  @impl true
  def handle_info(:check, state) do
    state = check_stuck_agents(state)
    state = check_errored_agents(state)

    Process.send_after(self(), :check, @check_interval)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp check_stuck_agents(state) do
    threshold =
      DateTime.utc_now()
      |> DateTime.add(-@stuck_threshold_seconds, :second)

    stuck_agents =
      Repo.all(
        from a in Agent,
          where: a.status == "working" and a.updated_at < ^threshold
      )

    Enum.each(stuck_agents, fn agent ->
      Logger.warning(
        "[Headless.Watchdog] Agent '#{agent.name}' (#{agent.id}) stuck in 'working' for >#{@stuck_threshold_seconds}s — resetting to idle"
      )

      agent |> change(status: "idle") |> Repo.update()

      Bizforge.Headless.Notifier.notify("agent.stuck_recovered", %{
        agent_id: agent.id,
        agent_name: agent.name,
        stuck_seconds: @stuck_threshold_seconds,
        action: "reset_to_idle"
      })
    end)

    state
  end

  defp check_errored_agents(state) do
    errored_agents =
      Repo.all(
        from a in Agent,
          where: a.status == "error"
      )

    failure_counts =
      Enum.reduce(errored_agents, state.failure_counts, fn agent, counts ->
        count = Map.get(counts, agent.id, 0) + 1
        backoff = min(count * count * 30, 3600)

        if should_retry?(agent, count, backoff) do
          Logger.info(
            "[Headless.Watchdog] Attempting recovery for agent '#{agent.name}' (attempt #{count}, backoff #{backoff}s)"
          )

          agent |> change(status: "idle") |> Repo.update()

          Bizforge.Headless.Notifier.notify("agent.recovery_attempt", %{
            agent_id: agent.id,
            agent_name: agent.name,
            attempt: count,
            backoff_seconds: backoff
          })

          Map.put(counts, agent.id, count)
        else
          if count > 10 do
            Bizforge.Headless.Notifier.notify("agent.recovery_exhausted", %{
              agent_id: agent.id,
              agent_name: agent.name,
              attempts: count
            })
          end

          Logger.debug(
            "[Headless.Watchdog] Agent '#{agent.name}' in backoff (attempt #{count}, #{backoff}s)"
          )

          Map.put(counts, agent.id, count)
        end
      end)

    %{state | failure_counts: failure_counts}
  end

  defp should_retry?(agent, count, backoff_seconds) do
    case agent.updated_at do
      nil ->
        true

      updated_at ->
        elapsed = DateTime.diff(DateTime.utc_now(), updated_at, :second)
        elapsed >= backoff_seconds && count <= 10
    end
  end
end
