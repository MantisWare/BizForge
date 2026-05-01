defmodule Bizforge.Headless.ResourceLimiter do
  @moduledoc """
  Enforces resource limits for headless workspace instances.

  Monitors:
    - Max concurrent agents (pauses excess agents)
    - Max memory usage (triggers GC and pauses agents)
    - Max tokens per hour (hard stop on token spend rate)

  Configured via environment variables:
    - BIZFORGE_MAX_AGENTS (default: unlimited)
    - BIZFORGE_MAX_MEMORY_MB (default: unlimited)
    - BIZFORGE_MAX_TOKENS_PER_HOUR (default: unlimited)
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.Agent
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  @check_interval :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def limits do
    GenServer.call(__MODULE__, :get_limits)
  catch
    :exit, _ -> %{max_agents: nil, max_memory_mb: nil, max_tokens_per_hour: nil}
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:bizforge, :headless, [])

    state = %{
      max_agents: Keyword.get(config, :max_agents),
      max_memory_mb: Keyword.get(config, :max_memory_mb),
      max_tokens_per_hour: Keyword.get(config, :max_tokens_per_hour),
      violations: [],
      last_check: DateTime.utc_now()
    }

    if any_limits_configured?(state) do
      Logger.info("[ResourceLimiter] Active limits: #{format_limits(state)}")
      Process.send_after(self(), :check, @check_interval)
    else
      Logger.info("[ResourceLimiter] No resource limits configured — running unlimited")
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_limits, _from, state) do
    {:reply,
     %{
       max_agents: state.max_agents,
       max_memory_mb: state.max_memory_mb,
       max_tokens_per_hour: state.max_tokens_per_hour
     }, state}
  end

  @impl true
  def handle_info(:check, state) do
    state = run_checks(state)
    Process.send_after(self(), :check, @check_interval)
    {:noreply, %{state | last_check: DateTime.utc_now()}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp run_checks(state) do
    state
    |> check_agent_limit()
    |> check_memory_limit()
    |> check_token_limit()
  end

  defp check_agent_limit(%{max_agents: nil} = state), do: state

  defp check_agent_limit(%{max_agents: max} = state) do
    active_count =
      Repo.aggregate(
        from(a in Agent, where: a.status in ["active", "working", "idle"]),
        :count
      )

    if active_count > max do
      excess = active_count - max

      Logger.warning(
        "[ResourceLimiter] Agent limit exceeded: #{active_count}/#{max} — pausing #{excess} agent(s)"
      )

      excess_agents =
        Repo.all(
          from a in Agent,
            where: a.status in ["active", "idle"],
            order_by: [desc: a.updated_at],
            limit: ^excess
        )

      Enum.each(excess_agents, fn agent ->
        agent |> change(status: "paused") |> Repo.update()
      end)

      Bizforge.Headless.Notifier.notify("resource.agent_limit_exceeded", %{
        active: active_count,
        max: max,
        paused_count: length(excess_agents)
      })

      %{state | violations: [:agent_limit | state.violations]}
    else
      state
    end
  end

  defp check_memory_limit(%{max_memory_mb: nil} = state), do: state

  defp check_memory_limit(%{max_memory_mb: max_mb} = state) do
    memory = :erlang.memory()
    current_mb = div(memory[:total], 1_048_576)

    if current_mb > max_mb do
      Logger.warning(
        "[ResourceLimiter] Memory limit exceeded: #{current_mb}MB / #{max_mb}MB"
      )

      :erlang.garbage_collect()

      Bizforge.Headless.Notifier.notify("resource.memory_limit_exceeded", %{
        current_mb: current_mb,
        max_mb: max_mb
      })

      %{state | violations: [:memory_limit | state.violations]}
    else
      state
    end
  end

  defp check_token_limit(%{max_tokens_per_hour: nil} = state), do: state

  defp check_token_limit(%{max_tokens_per_hour: max_tokens} = state) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    recent_tokens =
      Repo.aggregate(
        from(s in Bizforge.Schemas.Session,
          where: s.started_at >= ^one_hour_ago and not is_nil(s.total_tokens),
          select: sum(s.total_tokens)
        ),
        :count
      )

    tokens_used = recent_tokens || 0

    if tokens_used > max_tokens do
      Logger.warning(
        "[ResourceLimiter] Token limit exceeded: #{tokens_used}/#{max_tokens} tokens in last hour"
      )

      active_agents =
        Repo.all(from a in Agent, where: a.status in ["active", "idle"])

      Enum.each(active_agents, fn agent ->
        agent |> change(status: "paused") |> Repo.update()
      end)

      Bizforge.Headless.Notifier.notify("resource.token_limit_exceeded", %{
        tokens_used: tokens_used,
        max_tokens: max_tokens,
        agents_paused: length(active_agents)
      })

      %{state | violations: [:token_limit | state.violations]}
    else
      state
    end
  end

  defp any_limits_configured?(state) do
    state.max_agents !== nil || state.max_memory_mb !== nil || state.max_tokens_per_hour !== nil
  end

  defp format_limits(state) do
    parts =
      [
        if(state.max_agents, do: "agents=#{state.max_agents}"),
        if(state.max_memory_mb, do: "memory=#{state.max_memory_mb}MB"),
        if(state.max_tokens_per_hour, do: "tokens/hr=#{state.max_tokens_per_hour}")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, ", ")
  end
end
