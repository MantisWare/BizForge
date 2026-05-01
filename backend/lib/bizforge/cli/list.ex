defmodule Bizforge.CLI.List do
  @moduledoc """
  Handles the `bizforge list` command.

  Shows all running headless workspace instances by scanning PID files,
  including their health ports and resource usage.
  """

  def run(_argv) do
    pid_dir = Path.expand(".bizforge/pids")

    IO.puts("Running BizForge instances:")
    IO.puts("")

    if File.dir?(pid_dir) do
      pid_files =
        pid_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".pid"))

      if pid_files === [] do
        IO.puts("  No instances found.")
      else
        Enum.each(pid_files, fn file ->
          pid_file = Path.join(pid_dir, file)
          pid = pid_file |> File.read!() |> String.trim()
          workspace = String.replace_suffix(file, ".pid", "")

          alive? =
            case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
              {_, 0} -> true
              _ -> false
            end

          if alive? do
            meta = read_instance_meta(pid_dir, workspace)
            port_info = if meta.health_port, do: "port=#{meta.health_port}", else: "port=?"
            IO.puts("  #{workspace}  PID=#{pid}  #{port_info}  [running]")

            if meta.workspace_path do
              IO.puts("    Path: #{meta.workspace_path}")
            end
          else
            IO.puts("  #{workspace}  PID=#{pid}  [dead — stale PID file]")
            File.rm(pid_file)
          end
        end)
      end
    else
      IO.puts("  No instances found.")
    end
  end

  defp read_instance_meta(pid_dir, workspace) do
    meta_file = Path.join(pid_dir, "#{workspace}.meta.json")

    case File.read(meta_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            %{
              health_port: data["health_port"],
              workspace_path: data["workspace_path"],
              started_at: data["started_at"]
            }

          _ ->
            %{health_port: nil, workspace_path: nil, started_at: nil}
        end

      {:error, _} ->
        %{health_port: nil, workspace_path: nil, started_at: nil}
    end
  end
end
