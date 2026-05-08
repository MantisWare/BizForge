defmodule Bizforge.Browser.Sidecar do
  @moduledoc """
  Manages a Playwright sidecar Node.js process.

  Communicates via JSON-RPC over stdio. Each sidecar owns one Chromium
  browser instance and can host multiple BrowserContexts (one per session).
  """
  use GenServer
  require Logger

  @sidecar_startup_timeout 15_000
  @call_timeout 60_000

  defstruct [:port, :pending, :buffer, :ready]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc "Send a JSON-RPC call to the sidecar and return the result."
  @spec call(atom() | pid(), String.t(), map(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def call(server \\ __MODULE__, method, params \\ %{}, timeout \\ @call_timeout) do
    GenServer.call(server, {:rpc, method, params}, timeout)
  end

  @doc "Check if the sidecar is alive and responsive."
  def ping(server \\ __MODULE__) do
    case call(server, "ping", %{}, 5_000) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, _} -> :ok
      other -> other
    end
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      port: nil,
      pending: %{},
      buffer: "",
      ready: false
    }

    {:ok, state, {:continue, :start_sidecar}}
  end

  @impl true
  def handle_continue(:start_sidecar, state) do
    case start_sidecar_process() do
      {:ok, port} ->
        Logger.info("[Browser.Sidecar] Playwright sidecar started")
        {:noreply, %{state | port: port, ready: true}}

      {:error, reason} ->
        Logger.error("[Browser.Sidecar] Failed to start sidecar: #{inspect(reason)}")
        Process.send_after(self(), :retry_start, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:rpc, _method, _params}, _from, %{ready: false} = state) do
    {:reply, {:error, :sidecar_not_ready}, state}
  end

  def handle_call({:rpc, method, params}, from, state) do
    id = System.unique_integer([:positive])
    request = Jason.encode!(%{jsonrpc: "2.0", id: id, method: method, params: params})

    Port.command(state.port, request <> "\n")
    pending = Map.put(state.pending, id, from)
    {:noreply, %{state | pending: pending}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    buffer = state.buffer <> data
    {messages, remaining} = split_lines(buffer)

    state = %{state | buffer: remaining}

    state =
      Enum.reduce(messages, state, fn line, acc ->
        handle_sidecar_line(line, acc)
      end)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[Browser.Sidecar] Sidecar exited with code #{code}, restarting...")

    for {_id, from} <- state.pending do
      GenServer.reply(from, {:error, :sidecar_crashed})
    end

    Process.send_after(self(), :retry_start, 2_000)
    {:noreply, %{state | port: nil, ready: false, pending: %{}, buffer: ""}}
  end

  def handle_info(:retry_start, state) do
    {:noreply, state, {:continue, :start_sidecar}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    try do
      Port.command(port, Jason.encode!(%{jsonrpc: "2.0", id: 0, method: "shutdown", params: %{}}) <> "\n")
      Process.sleep(500)
      Port.close(port)
    rescue
      _ -> :ok
    end
  end

  def terminate(_reason, _state), do: :ok

  defp start_sidecar_process do
    sidecar_path = resolve_sidecar_path()

    if sidecar_path === nil do
      {:error, :sidecar_not_found}
    else
      port =
        Port.open(
          {:spawn_executable, System.find_executable("node")},
          [
            :binary,
            :exit_status,
            {:line, 65_536},
            :stderr_to_stdout,
            args: [sidecar_path]
          ]
        )

      {:ok, port}
    end
  end

  defp resolve_sidecar_path do
    candidates = [
      Path.join([File.cwd!(), "..", "desktop", "playwright-sidecar", "dist", "index.js"]),
      Path.join([File.cwd!(), "desktop", "playwright-sidecar", "dist", "index.js"]),
      Path.join([:code.priv_dir(:bizforge) |> to_string(), "playwright-sidecar", "index.js"])
    ]

    Enum.find(candidates, &File.exists?/1)
  end

  defp split_lines(buffer) do
    case String.split(buffer, "\n", parts: :infinity) do
      [single] -> {[], single}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  defp handle_sidecar_line("", state), do: state

  defp handle_sidecar_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"jsonrpc" => "2.0", "id" => id} = resp} ->
        case Map.pop(state.pending, id) do
          {nil, _pending} ->
            state

          {from, pending} ->
            result =
              if Map.has_key?(resp, "error") do
                {:error, resp["error"]["message"]}
              else
                {:ok, resp["result"]}
              end

            GenServer.reply(from, result)
            %{state | pending: pending}
        end

      {:error, _} ->
        if String.contains?(line, "[playwright-sidecar] Ready") do
          Logger.info("[Browser.Sidecar] Sidecar reports ready")
        end

        state
    end
  end
end
