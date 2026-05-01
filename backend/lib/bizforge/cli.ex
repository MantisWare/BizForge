defmodule Bizforge.CLI do
  @moduledoc """
  CLI entrypoint for headless workspace execution.

  Dispatches subcommands to dedicated modules under `Bizforge.CLI.*`.
  Invoked via the release overlay script: `bin/bizforge <command> [args]`.
  """

  @commands %{
    "run" => Bizforge.CLI.Run,
    "stop" => Bizforge.CLI.Stop,
    "status" => Bizforge.CLI.Status,
    "logs" => Bizforge.CLI.Logs,
    "config" => Bizforge.CLI.Config,
    "snapshot" => Bizforge.CLI.Snapshot,
    "pause" => Bizforge.CLI.Pause,
    "resume" => Bizforge.CLI.Resume,
    "list" => Bizforge.CLI.List,
    "attach" => Bizforge.CLI.Attach,
    "monitor" => Bizforge.CLI.Monitor
  }

  def main(argv) do
    case argv do
      [] ->
        print_usage()

      ["help" | _] ->
        print_usage()

      ["--help" | _] ->
        print_usage()

      [command | rest] ->
        case Map.get(@commands, command) do
          nil ->
            IO.puts(:stderr, "Unknown command: #{command}")
            print_usage()
            System.halt(1)

          module ->
            module.run(rest)
        end
    end
  end

  defp print_usage do
    IO.puts("""
    bizforge — Headless workspace execution for BizForge

    Usage:
      bizforge <command> [options]

    Commands:
      run <workspace-path>   Boot backend, load workspace, start all heartbeats
      stop                   Graceful shutdown with session compaction
      status                 Print running agents, tasks, budget usage, health
      logs                   Tail agent activity logs (structured, filterable)
      pause                  Pause all heartbeats without killing sessions
      resume                 Resume paused heartbeats
      config <subcommand>    Show or validate workspace configuration
      snapshot <subcommand>  Create, list, or restore workspace snapshots
      list                   Show all running headless workspace instances
      attach <workspace>     Connect to a running instance's log stream
      monitor                Open the stats dashboard

    Flags:
      --detach               Run as a background daemon
      --dry-run              Simulate boot without executing heartbeats
      --monitor              Open stats dashboard alongside run
      --port <port>          Override backend port (default: 9089)
      --health-port <port>   Override health check port (default: 9090)

    Examples:
      bizforge run ./operations/sales-engine
      bizforge run ./operations/dev-shop --detach
      bizforge status
      bizforge stop
      bizforge config validate ./operations/sales-engine
      bizforge snapshot create my-snapshot
    """)
  end
end
