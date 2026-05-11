defmodule Bizforge.Headless.Watchdog do
  @moduledoc """
  GenServer that monitors running heartbeat tasks and handles failures.

  Periodically checks for agents stuck in "working" status beyond a
  threshold, restarts crashed agents with exponential backoff, cleans
  up orphaned sessions/issues, and escalates to supervisors when
  recovery is exhausted.
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Session, Task}
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  @check_interval :timer.seconds(60)
  @stuck_threshold_seconds 600
  @max_recovery_attempts 10

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check, @check_interval)
    {:ok, %{failure_counts: %{}, escalated: MapSet.new()}}
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

      cleanup_orphaned_state(agent)
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

    Enum.reduce(errored_agents, state, fn agent, acc ->
      count = Map.get(acc.failure_counts, agent.id, 0) + 1
      backoff = min(count * count * 30, 3600)

      if should_retry?(agent, count, backoff) do
        Logger.info(
          "[Headless.Watchdog] Attempting recovery for agent '#{agent.name}' (attempt #{count}, backoff #{backoff}s)"
        )

        cleanup_orphaned_state(agent)
        agent |> change(status: "idle") |> Repo.update()

        Bizforge.Headless.Notifier.notify("agent.recovery_attempt", %{
          agent_id: agent.id,
          agent_name: agent.name,
          attempt: count,
          backoff_seconds: backoff
        })

        put_in(acc, [:failure_counts, agent.id], count)
      else
        if count > @max_recovery_attempts and not MapSet.member?(acc.escalated, agent.id) do
          Logger.warning(
            "[Headless.Watchdog] Recovery exhausted for agent '#{agent.name}' — escalating to supervisor"
          )

          Bizforge.Headless.Notifier.notify("agent.recovery_exhausted", %{
            agent_id: agent.id,
            agent_name: agent.name,
            attempts: count
          })

          Bizforge.SupervisorEscalation.escalate(
            agent,
            "Agent has failed #{count} times and recovery is exhausted",
            %{}
          )

          acc
          |> put_in([:failure_counts, agent.id], count)
          |> Map.update!(:escalated, &MapSet.put(&1, agent.id))
        else
          Logger.debug(
            "[Headless.Watchdog] Agent '#{agent.name}' in backoff (attempt #{count}, #{backoff}s)"
          )

          put_in(acc, [:failure_counts, agent.id], count)
        end
      end
    end)
  end

  defp should_retry?(agent, count, backoff_seconds) do
    if count > @max_recovery_attempts do
      false
    else
      case agent.updated_at do
        nil ->
          true

        updated_at ->
          elapsed = DateTime.diff(DateTime.utc_now(), updated_at, :second)
          elapsed >= backoff_seconds
      end
    end
  end

  # Fail any active sessions and release checked-out issues for this agent.
  defp cleanup_orphaned_state(agent) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {session_count, _} =
      Repo.update_all(
        from(s in Session,
          where: s.agent_id == ^agent.id and s.status == "active"
        ),
        set: [status: "failed", completed_at: now]
      )

    if session_count > 0 do
      Logger.info("[Headless.Watchdog] Failed #{session_count} orphaned session(s) for agent #{agent.name}")
    end

    {issue_count, _} =
      Repo.update_all(
        from(i in Task,
          where: i.checked_out_by == ^agent.id and i.status == "in_progress"
        ),
        set: [checked_out_by: nil, status: "backlog", updated_at: now]
      )

    if issue_count > 0 do
      Logger.info("[Headless.Watchdog] Released #{issue_count} checked-out issue(s) for agent #{agent.name}")
    end
  end
end
