defmodule Bizforge.CLI.Monitor do
  @moduledoc """
  Handles the `bizforge monitor` command.

  Auto-discovers running headless instances via PID/meta files,
  opens the Tauri stats dashboard window if available, or falls back
  to a live TUI stats display in the terminal.
  """

  @refresh_interval 5_000

  def run(argv) do
    {opts, _args, _} = OptionParser.parse(argv, strict: [tui: :boolean, workspace: :string])

    IO.puts("BizForge Monitor")
    IO.puts("================")
    IO.puts("")

    case discover_instance(opts) do
      {:ok, instance} ->
        IO.puts("Found instance: #{instance.workspace_name} (port #{instance.health_port})")
        IO.puts("")

        cond do
          opts[:tui] ->
            run_tui(instance)

          tauri_available?() ->
            launch_tauri(instance)

          true ->
            run_tui(instance)
        end

      {:error, :none_found} ->
        IO.puts(:stderr, "No running headless instance found.")
        IO.puts(:stderr, "Start one with 'bizforge run <workspace-path>' first.")
        System.halt(1)
    end
  end

  defp discover_instance(opts) do
    pid_dir =
      Application.get_env(:bizforge, :headless, [])
      |> Keyword.get(:pid_dir, ".bizforge/pids")
      |> Path.expand()

    target_workspace = opts[:workspace]

    if File.dir?(pid_dir) do
      meta_files =
        pid_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".meta.json"))

      instances =
        Enum.flat_map(meta_files, fn file ->
          path = Path.join(pid_dir, file)

          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, data} -> [data]
                _ -> []
              end

            _ ->
              []
          end
        end)
        |> Enum.filter(fn inst ->
          pid = inst["pid"]

          case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
            {_, 0} -> true
            _ -> false
          end
        end)

      instance =
        if target_workspace do
          Enum.find(instances, fn i -> i["workspace_name"] === target_workspace end)
        else
          List.first(instances)
        end

      case instance do
        nil -> {:error, :none_found}
        data -> {:ok, %{health_port: data["health_port"], workspace_name: data["workspace_name"], workspace_path: data["workspace_path"]}}
      end
    else
      {:error, :none_found}
    end
  end

  defp tauri_available? do
    case System.find_executable("cargo-tauri") do
      nil -> false
      _ -> true
    end
  end

  defp launch_tauri(instance) do
    IO.puts("Launching Tauri stats dashboard...")
    IO.puts("Dashboard URL: http://127.0.0.1:5200/monitor?workspace=#{instance.workspace_name}")
    IO.puts("")
    IO.puts("If the desktop app is running, the monitor window will open automatically.")
    IO.puts("Otherwise, open the URL above in your browser.")
  end

  defp run_tui(instance) do
    IO.puts("Starting TUI monitor (refresh every #{div(@refresh_interval, 1000)}s)...")
    IO.puts("Press Ctrl+C to exit.")
    IO.puts("")

    tui_loop(instance.health_port)
  end

  defp tui_loop(port) do
    case fetch_health(port) do
      {:ok, data} ->
        render_tui(data)

      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "  Connection lost: #{inspect(reason)}" <> IO.ANSI.reset())
    end

    Process.sleep(@refresh_interval)
    IO.puts(IO.ANSI.clear())
    tui_loop(port)
  end

  defp fetch_health(port) do
    case Req.get("http://127.0.0.1:#{port}/health", receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          _ -> {:error, :invalid_response}
        end
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp render_tui(data) do
    agents = data["agents"] || %{}
    tasks = data["tasks"] || %{}
    system = data["system"] || %{}

    IO.puts(IO.ANSI.bright() <> "  BizForge Headless Monitor" <> IO.ANSI.reset())
    IO.puts("  ─────────────────────────")
    IO.puts("  Status:    #{data["status"]}")
    IO.puts("  Uptime:    #{format_uptime(data["uptime_seconds"])}")
    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "  Agents" <> IO.ANSI.reset())
    IO.puts("    Active:  #{agents["active"] || 0}")
    IO.puts("    Errored: #{agents["errored"] || 0}")
    IO.puts("    Paused:  #{agents["paused"] || 0}")
    IO.puts("")
    IO.puts(IO.ANSI.green() <> "  Tasks" <> IO.ANSI.reset())
    IO.puts("    Active:    #{tasks["active"] || 0}")
    IO.puts("    Completed: #{tasks["completed"] || 0}")
    IO.puts("")
    IO.puts(IO.ANSI.yellow() <> "  System" <> IO.ANSI.reset())
    IO.puts("    Memory:     #{system["memory_mb"] || 0} MB")
    IO.puts("    Processes:  #{system["process_count"] || 0}")
    IO.puts("    Schedulers: #{system["scheduler_count"] || 0}")
    IO.puts("")
    IO.puts("  Last update: #{data["timestamp"]}")
  end

  defp format_uptime(nil), do: "?"

  defp format_uptime(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)
    "#{hours}h #{minutes}m #{secs}s"
  end

  defp format_uptime(_), do: "?"
end
