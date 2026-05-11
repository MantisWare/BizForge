defmodule Bizforge.Adapters.CursorCli do
  @moduledoc """
  Cursor CLI adapter — spawns the `agent` CLI binary for LLM interactions.

  Uses the Cursor `agent` binary (installed via `curl https://cursor.com/install -fsS | bash`)
  as a pass-through to Cursor's AI models. Authentication is via `agent login` (browser OAuth)
  or an optional `CURSOR_API_KEY` environment variable.

  No per-token cost — uses the Cursor subscription.

  ## Config keys

  - `"working_dir"` — workspace directory for execution (default: temp dir)
  - `"model"` — model to use (default: `"auto"`)
  - `"api_key"` — optional `CURSOR_API_KEY` for headless auth
  - `"agent_bin"` — custom path to the `agent` binary (optional)
  - `"mode"` — `"ask"` (read-only, default) or `"agent"` (can write files)
  - `"timeout_ms"` — timeout in ms (default: 300_000 / 5 min)
  """

  @behaviour Bizforge.Adapter

  require Logger

  @default_timeout_ms 300_000

  @anthropic_to_cursor %{
    "claude-opus-4-6" => "claude-4.6-opus-high",
    "claude-opus-4.6" => "claude-4.6-opus-high",
    "claude-sonnet-4-6" => "claude-4.6-sonnet-medium",
    "claude-sonnet-4.6" => "claude-4.6-sonnet-medium",
    "claude-opus-4-5" => "claude-4.5-opus-high",
    "claude-opus-4.5" => "claude-4.5-opus-high",
    "claude-sonnet-4-5" => "claude-4.5-sonnet",
    "claude-sonnet-4.5" => "claude-4.5-sonnet",
    "claude-opus-4" => "claude-4.6-opus-high",
    "claude-sonnet-4" => "claude-4.6-sonnet-medium",
    "claude-haiku-4-5-20251001" => "claude-4.5-sonnet",
    "claude-haiku-4-5" => "claude-4.5-sonnet",
    "claude-haiku-4-6" => "claude-4.6-sonnet-medium",
    "claude-haiku-4" => "claude-4.5-sonnet",
    "claude-opus-4-6-thinking" => "claude-4.6-opus-high-thinking",
    "claude-sonnet-4-6-thinking" => "claude-4.6-sonnet-medium-thinking",
    "claude-opus-4-5-thinking" => "claude-4.5-opus-high-thinking",
    "claude-sonnet-4-5-thinking" => "claude-4.5-sonnet-thinking",
    "claude-sonnet-4-thinking" => "claude-4-sonnet-thinking"
  }

  @fallback_models [
    %{id: "auto", name: "Auto"},
    %{id: "claude-4.6-opus-high", name: "Claude 4.6 Opus (High)"},
    %{id: "claude-4.6-sonnet-medium", name: "Claude 4.6 Sonnet"},
    %{id: "claude-4.5-sonnet", name: "Claude 4.5 Sonnet"}
  ]

  # ── Behaviour Callbacks ─────────────────────────────────────────────────────

  @impl true
  def type, do: "cursor-cli"

  @impl true
  def name, do: "Cursor CLI"

  @impl true
  def supports_session?, do: true

  @impl true
  def supports_concurrent?, do: false

  @impl true
  def capabilities, do: [:chat, :code_edit, :file_read, :file_write, :code_completion]

  @impl true
  def health do
    case find_agent() do
      nil ->
        {:error, "agent binary not found. Install: curl https://cursor.com/install -fsS | bash"}

      path ->
        case check_version(path) do
          {:ok, _version} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def start(config) do
    case find_agent(config["agent_bin"]) do
      nil ->
        {:error, :adapter_not_installed}

      agent_bin ->
        {:ok,
         %{
           agent_bin: agent_bin,
           cwd: config["working_dir"] || System.tmp_dir!(),
           model: resolve_model(config["model"]),
           api_key: config["api_key"],
           mode: config["mode"] || "ask",
           timeout_ms: config["timeout_ms"] || @default_timeout_ms
         }}
    end
  end

  @impl true
  def stop(_session), do: :ok

  @impl true
  def execute_heartbeat(params) do
    prompt = params["context"] || "Review the workspace and report status."
    cwd = params["working_dir"] || "."
    model = resolve_model(params["model"])
    api_key = params["api_key"]
    mode = params["mode"] || "ask"

    case find_agent(params["agent_bin"]) do
      nil -> not_installed_stream()
      agent_bin -> spawn_agent_stream(agent_bin, prompt, cwd, model, api_key, mode)
    end
  end

  @impl true
  def send_message(
        %{agent_bin: agent_bin, cwd: cwd, model: model, api_key: api_key, mode: mode},
        message
      ) do
    spawn_agent_stream(agent_bin, message, cwd, model, api_key, mode)
  end

  def send_message(_session, message) do
    execute_heartbeat(%{"context" => message})
  end

  # ── Public Helpers (for ProviderController) ─────────────────────────────────

  @doc "List models available via `agent --list-models`. Returns `{:ok, models}` or `{:error, reason}`."
  def list_models(agent_bin \\ nil) do
    bin = find_agent(agent_bin)

    if bin === nil do
      {:error, "agent binary not found"}
    else
      do_list_models(bin)
    end
  end

  @doc "Test that the agent binary is installed and authenticated."
  def test_connection(agent_bin \\ nil) do
    bin = find_agent(agent_bin)

    cond do
      bin === nil ->
        {:error, "agent binary not found. Install: curl https://cursor.com/install -fsS | bash"}

      true ->
        case check_version(bin) do
          {:ok, version} ->
            case do_list_models(bin) do
              {:ok, models} ->
                {:ok, %{version: version, models: models}}

              {:error, reason} ->
                if String.contains?(to_string(reason), "Authentication") or
                     String.contains?(to_string(reason), "agent login") do
                  {:error, "Agent CLI v#{version} installed but not authenticated. Run `agent login` in your terminal."}
                else
                  {:ok, %{version: version, models: fallback_model_ids()}}
                end
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ── Model Resolution ────────────────────────────────────────────────────────

  @doc false
  def resolve_model(nil), do: "auto"
  def resolve_model(""), do: "auto"

  def resolve_model(requested) do
    trimmed = String.trim(requested)

    normalized =
      trimmed
      |> String.split("/")
      |> List.last()
      |> Kernel.||(trimmed)
      |> String.downcase()

    Map.get(@anthropic_to_cursor, normalized, normalized)
  end

  # ── Private: Binary Detection ───────────────────────────────────────────────

  defp find_agent(nil), do: find_agent()
  defp find_agent(""), do: find_agent()
  defp find_agent(custom_path) when is_binary(custom_path), do: if(File.exists?(custom_path), do: custom_path, else: find_agent())

  defp find_agent do
    case System.find_executable("agent") do
      nil ->
        home = System.get_env("HOME") || "/"

        known_paths = [
          Path.join([home, ".local", "bin", "agent"]),
          "/usr/local/bin/agent"
        ]

        Enum.find(known_paths, &File.exists?/1)

      path ->
        path
    end
  end

  defp check_version(bin) do
    try do
      case System.cmd(bin, ["--version"], stderr_to_stdout: true) do
        {output, 0} ->
          version = String.trim(output)

          if version !== "" do
            {:ok, version}
          else
            {:error, "agent --version returned empty output"}
          end

        {output, _code} ->
          {:error, "agent --version failed: #{String.trim(output)}"}
      end
    rescue
      e -> {:error, "Failed to run agent binary: #{Exception.message(e)}"}
    end
  end

  # ── Private: Model Listing ──────────────────────────────────────────────────

  defp do_list_models(bin) do
    try do
      case System.cmd(bin, ["--list-models"], stderr_to_stdout: true, env: agent_env(nil)) do
        {output, 0} ->
          models = parse_model_list(output)

          if models === [] do
            {:ok, fallback_model_ids()}
          else
            {:ok, models}
          end

        {output, _code} ->
          trimmed = String.trim(output)

          if String.contains?(trimmed, "Authentication") or String.contains?(trimmed, "agent login") do
            {:error, "Authentication required — run `agent login`"}
          else
            {:error, "agent --list-models failed: #{trimmed}"}
          end
      end
    rescue
      e -> {:error, "Failed to list models: #{Exception.message(e)}"}
    end
  end

  defp parse_model_list(output) do
    output
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 !== ""))
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^([A-Za-z0-9][A-Za-z0-9._:\/-]*)\s+-\s+(.*)$/, line) do
        [_, id, _name] -> [id]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp fallback_model_ids do
    Enum.map(@fallback_models, & &1.id)
  end

  # ── Private: Streaming Execution ────────────────────────────────────────────

  defp spawn_agent_stream(agent_bin, prompt, cwd, model, api_key, mode) do
    args = build_args(cwd, model, prompt, mode)

    Stream.resource(
      fn ->
        env = agent_env_charlist(api_key)

        port =
          Port.open(
            {:spawn_executable, agent_bin},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              args: args,
              cd: to_charlist(cwd),
              env: env
            ]
          )

        {port, ""}
      end,
      fn
        {:done, _} ->
          {:halt, :done}

        {port, buffer} ->
          receive do
            {^port, {:data, data}} ->
              combined = buffer <> data
              {events, remaining} = parse_stream_output(combined)
              {events, {port, remaining}}

            {^port, {:exit_status, 0}} ->
              {[%{event_type: "run.completed", data: %{}, tokens_input: 0, tokens_output: 0}],
               {:done, port}}

            {^port, {:exit_status, code}} ->
              {[
                 %{
                   event_type: "run.failed",
                   data: %{"exit_code" => code, "output" => buffer},
                   tokens_input: 0,
                   tokens_output: 0
                 }
               ], {:done, port}}
          after
            @default_timeout_ms ->
              {:halt, {port, buffer}}
          end
      end,
      fn
        :done -> :ok
        {:done, port} -> close_port(port)
        {port, _buf} -> close_port(port)
      end
    )
  end

  defp build_args(cwd, model, prompt, mode) do
    ["-f", "--print", "--mode", mode, "--workspace", cwd, "--model", model] ++
      ["--stream-partial-output", "--output-format", "stream-json"] ++
      [prompt]
  end

  # ── Private: Stream JSON Parsing ────────────────────────────────────────────

  defp parse_stream_output(buffer) do
    lines = String.split(buffer, "\n")
    {complete_lines, [remaining]} = Enum.split(lines, -1)

    events =
      complete_lines
      |> Enum.filter(&(String.trim(&1) !== ""))
      |> Enum.flat_map(&parse_stream_line/1)

    {events, remaining}
  end

  defp parse_stream_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}}
      when is_list(content) ->
        content
        |> Enum.filter(fn p ->
          is_map(p) and p["type"] === "text" and
            is_binary(p["text"]) and p["text"] !== ""
        end)
        |> Enum.map(fn _p ->
          %{
            event_type: "run.output",
            data: %{"type" => "assistant", "message" => %{"content" => content}},
            tokens_input: 0,
            tokens_output: 0
          }
        end)

      {:ok, %{"type" => "result", "subtype" => "success"}} ->
        [%{event_type: "run.completed", data: %{}, tokens_input: 0, tokens_output: 0}]

      {:ok, %{"type" => "result"}} ->
        [%{event_type: "run.completed", data: %{}, tokens_input: 0, tokens_output: 0}]

      {:ok, %{"type" => "error"} = data} ->
        [%{event_type: "run.failed", data: data, tokens_input: 0, tokens_output: 0}]

      {:ok, _other} ->
        []

      {:error, _} ->
        []
    end
  end

  # ── Private: Environment ────────────────────────────────────────────────────

  defp agent_env(api_key) do
    base = System.get_env()

    base =
      if is_binary(api_key) and api_key !== "" do
        Map.put(base, "CURSOR_API_KEY", api_key)
      else
        base
      end

    augment_path(base)
  end

  defp agent_env_charlist(api_key) do
    agent_env(api_key)
    |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
  end

  defp augment_path(env) do
    home = System.get_env("HOME") || "/"

    search_dirs = [
      Path.join([home, ".local", "bin"]),
      "/usr/local/bin"
    ]

    current_path = Map.get(env, "PATH", "")

    missing =
      Enum.filter(search_dirs, fn dir ->
        not String.contains?(current_path, dir)
      end)

    if missing !== [] do
      Map.put(env, "PATH", Enum.join(missing ++ [current_path], ":"))
    else
      env
    end
  end

  # ── Private: Helpers ────────────────────────────────────────────────────────

  defp not_installed_stream do
    Stream.resource(
      fn -> :once end,
      fn
        :once ->
          event = %{
            event_type: "run.failed",
            data: %{
              "error" => "Cursor agent CLI not found",
              "adapter" => type(),
              "hint" =>
                "Install with: curl https://cursor.com/install -fsS | bash — then run: agent login"
            },
            tokens_input: 0,
            tokens_output: 0
          }

          {[event], :done}

        :done ->
          {:halt, :done}
      end,
      fn _ -> :ok end
    )
  end

  defp close_port(port) do
    try do
      Port.close(port)
    rescue
      _ -> :ok
    end
  end
end
