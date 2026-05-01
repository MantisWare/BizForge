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
      ["rollback" | rest] -> rollback(rest)
      ["diff" | rest] -> diff(rest)
      ["versions" | _] -> versions()
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

  defp rollback(argv) do
    case argv do
      [version_str | _] ->
        case Integer.parse(version_str) do
          {version, ""} ->
            IO.puts("Rolling back to version #{version}...")

            case Snapshots.rollback(version) do
              {:ok, summary} ->
                IO.puts("Rollback to version #{version} successful.")
                IO.puts("  Workspace:       #{summary.workspace}")
                IO.puts("  Agents restored: #{summary.agents_restored}")
                IO.puts("  Files restored:  #{summary.files_restored}")

              {:error, :version_not_found} ->
                IO.puts(:stderr, "Version #{version} not found.")
                IO.puts(:stderr, "Use 'bizforge snapshot versions' to see history.")
                System.halt(1)

              {:error, :not_found} ->
                IO.puts(:stderr, "Snapshot file for version #{version} not found on disk.")
                System.halt(1)

              {:error, reason} ->
                IO.puts(:stderr, "Rollback failed: #{inspect(reason)}")
                System.halt(1)
            end

          _ ->
            IO.puts(:stderr, "Error: version must be an integer")
            System.halt(1)
        end

      [] ->
        IO.puts(:stderr, "Error: version number required")
        IO.puts(:stderr, "Usage: bizforge snapshot rollback <version>")
        System.halt(1)
    end
  end

  defp diff(argv) do
    case argv do
      [v1_str, v2_str | _] ->
        with {v1, ""} <- Integer.parse(v1_str),
             {v2, ""} <- Integer.parse(v2_str) do
          case Snapshots.diff(v1, v2) do
            {:ok, result} ->
              IO.puts("Diff: version #{v1} → version #{v2}")
              IO.puts("  Integrity changed: #{result.integrity_changed}")
              IO.puts("")

              if result.agents.added !== [] do
                IO.puts("  Agents added:")
                Enum.each(result.agents.added, &IO.puts("    + #{&1}"))
              end

              if result.agents.removed !== [] do
                IO.puts("  Agents removed:")
                Enum.each(result.agents.removed, &IO.puts("    - #{&1}"))
              end

              if result.schedules.added !== [] do
                IO.puts("  Schedules added:")
                Enum.each(result.schedules.added, &IO.puts("    + #{&1}"))
              end

              if result.schedules.removed !== [] do
                IO.puts("  Schedules removed:")
                Enum.each(result.schedules.removed, &IO.puts("    - #{&1}"))
              end

              if result.agents.added === [] && result.agents.removed === [] &&
                   result.schedules.added === [] && result.schedules.removed === [] do
                IO.puts("  No structural changes (agents/schedules unchanged).")
              end

            {:error, {:version_not_found, v}} ->
              IO.puts(:stderr, "Version #{v} not found.")
              System.halt(1)

            {:error, reason} ->
              IO.puts(:stderr, "Diff failed: #{inspect(reason)}")
              System.halt(1)
          end
        else
          _ ->
            IO.puts(:stderr, "Error: both arguments must be integers")
            System.halt(1)
        end

      _ ->
        IO.puts(:stderr, "Usage: bizforge snapshot diff <version1> <version2>")
        System.halt(1)
    end
  end

  defp versions do
    entries = Snapshots.versions()

    if entries === [] do
      IO.puts("No version history found.")
    else
      IO.puts("Snapshot version history:")
      IO.puts("")

      Enum.each(entries, fn entry ->
        IO.puts("  v#{entry["version"]}  #{entry["name"]}")
        IO.puts("        Created: #{entry["created_at"]}")

        if entry["description"] !== "" do
          IO.puts("        Description: #{entry["description"]}")
        end

        IO.puts("        Integrity: #{entry["integrity_hash"]}")
        IO.puts("")
      end)
    end
  end

  defp print_usage do
    IO.puts("""
    Usage:
      bizforge snapshot create <name> [workspace-path]   Create a workspace snapshot
      bizforge snapshot list                              List available snapshots
      bizforge snapshot restore <name>                    Restore from a snapshot
      bizforge snapshot rollback <version>                Rollback to a specific version
      bizforge snapshot diff <v1> <v2>                    Show changes between versions
      bizforge snapshot versions                          Show version history
    """)
  end
end
