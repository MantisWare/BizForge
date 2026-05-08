defmodule Bizforge.AdapterCircuitBreaker do
  @moduledoc """
  Tracks per-adapter health and prevents cascading failures when an LLM
  provider is down.

  ## Circuit states

    - `:closed`    — healthy, requests pass through
    - `:open`      — tripped, requests are rejected immediately
    - `:half_open` — cooldown expired, one probe request is allowed

  ## Thresholds

    - 3 consecutive failures within 60 s opens the circuit
    - After 120 s in `:open`, the circuit moves to `:half_open`
    - 1 success in `:half_open` closes the circuit
    - 1 failure in `:half_open` reopens immediately
  """
  use GenServer
  require Logger

  @failure_threshold 3
  @failure_window_ms :timer.seconds(60)
  @open_duration_ms :timer.seconds(120)

  # ── Client API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record a successful adapter call. Resets failures / closes half-open."
  def record_success(adapter_type) when is_binary(adapter_type) do
    GenServer.cast(__MODULE__, {:success, adapter_type})
  catch
    :exit, _ -> :ok
  end

  @doc "Record a failed adapter call. May open the circuit."
  def record_failure(adapter_type) when is_binary(adapter_type) do
    GenServer.cast(__MODULE__, {:failure, adapter_type})
  catch
    :exit, _ -> :ok
  end

  @doc "Returns `true` when the adapter is accepting requests."
  def available?(adapter_type) when is_binary(adapter_type) do
    GenServer.call(__MODULE__, {:available?, adapter_type})
  catch
    :exit, _ -> true
  end

  @doc "Returns the full circuit state map (for dashboards / monitoring)."
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _ -> %{}
  end

  # ── Server ──────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{circuits: %{}}}
  end

  @impl true
  def handle_cast({:success, adapter_type}, state) do
    circuit = Map.get(state.circuits, adapter_type, default_circuit())

    updated =
      case circuit.state do
        :half_open ->
          Logger.info("[CircuitBreaker] #{adapter_type}: half_open -> closed (success)")
          default_circuit()

        _ ->
          %{circuit | failures: [], state: :closed}
      end

    {:noreply, put_in(state, [:circuits, adapter_type], updated)}
  end

  def handle_cast({:failure, adapter_type}, state) do
    now = System.monotonic_time(:millisecond)
    circuit = Map.get(state.circuits, adapter_type, default_circuit())

    updated =
      case circuit.state do
        :half_open ->
          Logger.warning("[CircuitBreaker] #{adapter_type}: half_open -> open (probe failed)")
          %{circuit | state: :open, opened_at: now, failures: [now]}

        :open ->
          circuit

        :closed ->
          failures = prune_old_failures([now | circuit.failures], now)

          if length(failures) >= @failure_threshold do
            Logger.warning(
              "[CircuitBreaker] #{adapter_type}: closed -> open (#{length(failures)} failures in window)"
            )

            Bizforge.Headless.Notifier.notify("adapter.circuit_opened", %{
              adapter: adapter_type,
              failure_count: length(failures)
            })

            %{circuit | state: :open, opened_at: now, failures: failures}
          else
            %{circuit | failures: failures}
          end
      end

    {:noreply, put_in(state, [:circuits, adapter_type], updated)}
  end

  @impl true
  def handle_call({:available?, adapter_type}, _from, state) do
    now = System.monotonic_time(:millisecond)
    circuit = Map.get(state.circuits, adapter_type, default_circuit())

    {available, updated_circuit} =
      case circuit.state do
        :closed ->
          {true, circuit}

        :open ->
          if now - circuit.opened_at >= @open_duration_ms do
            Logger.info("[CircuitBreaker] #{adapter_type}: open -> half_open (cooldown expired)")
            {true, %{circuit | state: :half_open}}
          else
            {false, circuit}
          end

        :half_open ->
          {true, circuit}
      end

    state = put_in(state, [:circuits, adapter_type], updated_circuit)
    {:reply, available, state}
  end

  def handle_call(:status, _from, state) do
    summary =
      Map.new(state.circuits, fn {adapter, circuit} ->
        {adapter, %{
          state: circuit.state,
          failure_count: length(circuit.failures),
          opened_at: circuit.opened_at
        }}
      end)

    {:reply, summary, state}
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp default_circuit do
    %{state: :closed, failures: [], opened_at: nil}
  end

  defp prune_old_failures(failures, now) do
    cutoff = now - @failure_window_ms
    Enum.filter(failures, fn ts -> ts > cutoff end)
  end
end
