defmodule Bizforge.Headless.Notifications.DeadManSwitch do
  @moduledoc """
  Periodic heartbeat ping to an external monitoring URL.

  Compatible with services like Healthchecks.io, Cronitor, Better Uptime,
  and any endpoint that expects periodic GET/POST pings.

  If the ping fails 3 consecutive times, logs a warning but continues
  operating (the external service handles alerting).

  Configure via `BIZFORGE_HEARTBEAT_URL` environment variable.
  Default ping interval is 60 seconds.
  """
  use GenServer
  require Logger

  @default_interval :timer.seconds(60)
  @max_consecutive_failures 3

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def configured? do
    heartbeat_url() !== nil
  end

  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _ -> %{configured: false}
  end

  @impl true
  def init(_opts) do
    url = heartbeat_url()
    interval = ping_interval()

    if url !== nil do
      Logger.info("[DeadManSwitch] Pinging #{url} every #{div(interval, 1000)}s")
      Process.send_after(self(), :ping, interval)
    else
      Logger.info("[DeadManSwitch] Not configured — disabled")
    end

    {:ok,
     %{
       url: url,
       interval: interval,
       consecutive_failures: 0,
       last_ping: nil,
       last_status: nil,
       total_pings: 0
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       configured: state.url !== nil,
       url: state.url,
       consecutive_failures: state.consecutive_failures,
       last_ping: state.last_ping,
       last_status: state.last_status,
       total_pings: state.total_pings
     }, state}
  end

  @impl true
  def handle_info(:ping, %{url: nil} = state), do: {:noreply, state}

  def handle_info(:ping, state) do
    state = do_ping(state)
    Process.send_after(self(), :ping, state.interval)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp do_ping(state) do
    case Req.get(state.url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: status}} when status >= 200 and status < 300 ->
        %{
          state
          | consecutive_failures: 0,
            last_ping: DateTime.utc_now(),
            last_status: :ok,
            total_pings: state.total_pings + 1
        }

      {:ok, %Req.Response{status: status}} ->
        failures = state.consecutive_failures + 1
        log_failure(state.url, "HTTP #{status}", failures)

        %{
          state
          | consecutive_failures: failures,
            last_ping: DateTime.utc_now(),
            last_status: {:error, status},
            total_pings: state.total_pings + 1
        }

      {:error, reason} ->
        failures = state.consecutive_failures + 1
        log_failure(state.url, inspect(reason), failures)

        %{
          state
          | consecutive_failures: failures,
            last_ping: DateTime.utc_now(),
            last_status: {:error, reason},
            total_pings: state.total_pings + 1
        }
    end
  end

  defp log_failure(url, reason, failures) do
    if failures >= @max_consecutive_failures do
      Logger.warning(
        "[DeadManSwitch] #{failures} consecutive failures pinging #{url}: #{reason}"
      )
    else
      Logger.debug("[DeadManSwitch] Ping failed (#{failures}/#{@max_consecutive_failures}): #{reason}")
    end
  end

  defp heartbeat_url do
    Application.get_env(:bizforge, :headless, [])
    |> Keyword.get(:heartbeat_url)
  end

  defp ping_interval do
    case System.get_env("BIZFORGE_HEARTBEAT_INTERVAL") do
      nil -> @default_interval
      val -> String.to_integer(val) * 1000
    end
  end
end
