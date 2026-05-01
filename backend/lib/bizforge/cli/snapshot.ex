defmodule Bizforge.CLI.Snapshot do
  @moduledoc """
  Handles the `bizforge snapshot` command.

  Subcommands:
    - `create <name>`  — serialize workspace into a deployable snapshot
    - `list`           — list available snapshots
    - `restore <name>` — restore workspace from a snapshot
  """

  alias Bizforge.Snapshots

  def run(argv) do
    case argv do
      ["create" | rest] -> create(rest)
      ["list" | _] -> list()
      ["restore" | rest] -> restore(rest)
      _ -> print_usage()
    end
  end

  defp create(argv) do
    case argv do
      [name | rest] ->
        workspace_path =
          case rest do
            [p | _] -> Path.expand(p)
            [] -> Path.expand(".")
          end

        IO.puts("Creating snapshot '#{name}' from #{workspace_path}...")

        case Snapshots.create(name, workspace_path) do
          {:ok, file, summary} ->
            IO.puts("Snapshot saved: #{file}")
            IO.puts("  Agents (DB):     #{summary.agents}")
            IO.puts("  Schedules:       #{summary.schedules}")
            IO.puts("  Teams:           #{summary.teams}")
            IO.puts("  Workflows:       #{summary.workflows}")
            IO.puts("  Agent files:     #{summary.agent_files}")
            IO.puts("  Skill files:     #{summary.skill_files}")
            IO.puts("  Integrity hash:  #{summary.integrity}")

          {:error, reason} ->
            IO.puts(:stderr, "Failed to create snapshot: #{inspect(reason)}")
            System.halt(1)
        end

      [] ->
        IO.puts(:stderr, "Error: snapshot name required")
        IO.puts(:stderr, "Usage: bizforge snapshot create <name> [workspace-path]")
        System.halt(1)
    end
  end

  defp list do
    snapshots = Snapshots.list()

    if snapshots === [] do
      IO.puts("No snapshots found. Create one with 'bizforge snapshot create <name>'.")
    else
      IO.puts("Available snapshots:")
      IO.puts("")

      Enum.each(snapshots, fn snapshot ->
        IO.puts("  #{snapshot.name}")

        if Map.has_key?(snapshot, :error) do
          IO.puts("    Status: #{snapshot.error}")
        else
          IO.puts("    Created:   #{snapshot.created_at}")
          IO.puts("    Agents:    #{snapshot.agent_count}")
          IO.puts("    Integrity: #{snapshot.integrity}")
        end

        IO.puts("")
      end)
    end
  end

  defp restore(argv) do
    case argv do
      [name | _] ->
        IO.puts("Restoring snapshot '#{name}'...")

        case Snapshots.restore(name) do
          {:ok, summary} ->
            IO.puts("Snapshot restored successfully.")
            IO.puts("  Workspace:       #{summary.workspace}")
            IO.puts("  Agents restored: #{summary.agents_restored}")
            IO.puts("  Files restored:  #{summary.files_restored}")

          {:error, :not_found} ->
            IO.puts(:stderr, "Snapshot not found: #{name}")
            IO.puts(:stderr, "Use 'bizforge snapshot list' to see available snapshots.")
            System.halt(1)

          {:error, reason} ->
            IO.puts(:stderr, "Failed to restore snapshot: #{inspect(reason)}")
            System.halt(1)
        end

      [] ->
        IO.puts(:stderr, "Error: snapshot name required")
        IO.puts(:stderr, "Usage: bizforge snapshot restore <name>")
        System.halt(1)
    end
  end

  defp print_usage do
    IO.puts("""
    Usage:
      bizforge snapshot create <name> [workspace-path]   Create a workspace snapshot
      bizforge snapshot list                              List available snapshots
      bizforge snapshot restore <name>                    Restore from a snapshot
    """)
  end
end
