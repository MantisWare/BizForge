defmodule Bizforge.CLI.List do
  @moduledoc """
  Handles the `bizforge list` command.

  Shows all running headless workspace instances by scanning PID files.
  """

  def run(_argv) do
    pid_dir = Path.expand(".bizforge/pids")

    IO.puts("Running BizForge instances:")
    IO.puts("")

    if File.dir?(pid_dir) do
      pid_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".pid"))
      |> Enum.each(fn file ->
        pid_file = Path.join(pid_dir, file)
        pid = pid_file |> File.read!() |> String.trim()
        workspace = String.replace_suffix(file, ".pid", "")

        alive? =
          case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
            {_, 0} -> true
            _ -> false
          end

        if alive? do
          IO.puts("  #{workspace}  PID=#{pid}  [running]")
        else
          IO.puts("  #{workspace}  PID=#{pid}  [dead — stale PID file]")
          File.rm(pid_file)
        end
      end)
    else
      IO.puts("  No instances found.")
    end
  end
end
