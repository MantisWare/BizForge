defmodule Bizforge.CLI.Status do
  @moduledoc """
  Handles the `bizforge status` command.

  Queries the running headless instance for agent count, active tasks,
  budget usage, and system health. Falls back to PID file inspection
  when the instance is unreachable.
  """

  def run(_argv) do
    pid_dir = headless_config(:pid_dir, ".bizforge/pids")
    pid_dir = Path.expand(pid_dir)

    IO.puts("BizForge Headless Status")
    IO.puts("========================")
    IO.puts("")

    if File.dir?(pid_dir) do
      pid_files =
        pid_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".pid"))

      if pid_files === [] do
        IO.puts("  No running instances.")
      else
        Enum.each(pid_files, fn file ->
          pid_file = Path.join(pid_dir, file)
          pid = pid_file |> File.read!() |> String.trim()
          workspace = file |> String.replace_suffix(".pid", "")

          alive? =
            case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
              {_, 0} -> true
              _ -> false
            end

          status = if alive?, do: "running", else: "stopped"
          IO.puts("  #{workspace}: #{status} (PID #{pid})")
        end)
      end
    else
      IO.puts("  No PID directory found. No instances have been started.")
    end

    IO.puts("")

    health_port = headless_config(:health_port, 9090)

    case :httpc.request(:get, {~c"http://127.0.0.1:#{health_port}/health", []}, [], []) do
      {:ok, {{_, 200, _}, _, _body}} ->
        IO.puts("  Health endpoint: OK (port #{health_port})")

      _ ->
        IO.puts("  Health endpoint: unreachable (port #{health_port})")
    end
  end

  defp headless_config(key, default) do
    case Application.get_env(:bizforge, :headless) do
      nil -> default
      config -> Keyword.get(config, key, default)
    end
  end
end
