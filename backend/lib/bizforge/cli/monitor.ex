defmodule Bizforge.CLI.Monitor do
  @moduledoc """
  Handles the `bizforge monitor` command.

  Opens the stats dashboard Tauri window or falls back to a terminal
  summary if Tauri is not available.
  """

  def run(_argv) do
    IO.puts("BizForge Monitor")
    IO.puts("================")
    IO.puts("")

    port = headless_config(:health_port, 9090)
    IO.puts("Connecting to headless instance on port #{port}...")

    case check_health(port) do
      :ok ->
        IO.puts("Instance is running. Opening stats dashboard...")
        IO.puts("")
        IO.puts("Stats dashboard URL: http://127.0.0.1:5200/monitor")
        IO.puts("")
        IO.puts("If the Tauri app is available, run:")
        IO.puts("  cd desktop && npm run tauri:dev")
        IO.puts("Then navigate to /monitor in the app.")

      :unreachable ->
        IO.puts(:stderr, "No running headless instance found on port #{port}.")
        IO.puts(:stderr, "Start one with 'bizforge run <workspace-path>' first.")
        System.halt(1)
    end
  end

  defp check_health(port) do
    case :httpc.request(:get, {~c"http://127.0.0.1:#{port}/health", []}, [], []) do
      {:ok, {{_, 200, _}, _, _}} -> :ok
      _ -> :unreachable
    end
  end

  defp headless_config(key, default) do
    case Application.get_env(:bizforge, :headless) do
      nil -> default
      config -> Keyword.get(config, key, default)
    end
  end
end
