defmodule Bizforge.CLI.Attach do
  @moduledoc """
  Handles the `bizforge attach <workspace>` command.

  Connects to a running headless instance's log stream. Finds the instance
  by workspace name via PID file, then tails the corresponding log.
  """

  def run(argv) do
    case argv do
      [workspace_name | _] ->
        pid_dir = Path.expand(".bizforge/pids")
        pid_file = Path.join(pid_dir, "#{workspace_name}.pid")

        unless File.exists?(pid_file) do
          IO.puts(:stderr, "No running instance found for workspace '#{workspace_name}'.")
          IO.puts(:stderr, "Use 'bizforge list' to see running instances.")
          System.halt(1)
        end

        pid = pid_file |> File.read!() |> String.trim()

        alive? =
          case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
            {_, 0} -> true
            _ -> false
          end

        unless alive? do
          IO.puts(:stderr, "Instance for '#{workspace_name}' (PID #{pid}) is not running.")
          File.rm(pid_file)
          System.halt(1)
        end

        IO.puts("Attached to '#{workspace_name}' (PID #{pid})")
        IO.puts("Press Ctrl+C to detach.")
        IO.puts("")

        log_file = Path.expand(".bizforge/logs/headless.log")

        if File.exists?(log_file) do
          port =
            Port.open(
              {:spawn_executable, System.find_executable("tail")},
              [:binary, args: ["-f", "-n", "50", log_file]]
            )

          stream_output(port)
        else
          IO.puts("No log file found at #{log_file}")
          IO.puts("Instance may be using a different log path.")
        end

      [] ->
        IO.puts("""
        Usage:
          bizforge attach <workspace-name>

        Connects to a running headless instance's log stream.
        """)
    end
  end

  defp stream_output(port) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        stream_output(port)

      {:EXIT, ^port, _reason} ->
        IO.puts("\nDetached.")
    end
  end
end
