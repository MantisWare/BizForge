defmodule Bizforge.CLI.Stop do
  @moduledoc """
  Handles the `bizforge stop` command.

  Sends a graceful shutdown signal to a running headless instance,
  triggering session compaction for all active agents.
  """

  def run(_argv) do
    pid_dir = headless_config(:pid_dir, ".bizforge/pids")

    case find_running_instance(pid_dir) do
      {:ok, pid_file, pid} ->
        IO.puts("Stopping BizForge headless instance (PID #{pid})...")
        IO.puts("Compacting active sessions before shutdown...")

        case System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true) do
          {_, 0} ->
            File.rm(pid_file)
            IO.puts("Shutdown signal sent. Instance will compact sessions and exit.")

          {output, _} ->
            IO.puts(:stderr, "Failed to stop process: #{output}")
            System.halt(1)
        end

      :none ->
        IO.puts("No running headless instance found.")
    end
  end

  defp find_running_instance(pid_dir) do
    pid_dir = Path.expand(pid_dir)

    if File.dir?(pid_dir) do
      pid_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".pid"))
      |> Enum.find_value(:none, fn file ->
        pid_file = Path.join(pid_dir, file)
        pid = pid_file |> File.read!() |> String.trim() |> String.to_integer()

        case System.cmd("kill", ["-0", to_string(pid)], stderr_to_stdout: true) do
          {_, 0} -> {:ok, pid_file, pid}
          _ -> :none
        end
      end)
    else
      :none
    end
  end

  defp headless_config(key, default) do
    case Application.get_env(:bizforge, :headless) do
      nil -> default
      config -> Keyword.get(config, key, default)
    end
  end
end
