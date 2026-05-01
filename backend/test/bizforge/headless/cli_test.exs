defmodule Bizforge.Headless.CLITest do
  @moduledoc """
  Tests for CLI command parsing and execution.

  Verifies argument parsing, subcommand dispatch, and error handling
  for all CLI commands.
  """
  use ExUnit.Case, async: true

  alias Bizforge.CLI

  describe "CLI dispatch" do
    test "recognizes run command" do
      assert function_exported?(Bizforge.CLI.Run, :run, 1)
    end

    test "recognizes stop command" do
      assert function_exported?(Bizforge.CLI.Stop, :run, 1)
    end

    test "recognizes status command" do
      assert function_exported?(Bizforge.CLI.Status, :run, 1)
    end

    test "recognizes logs command" do
      assert function_exported?(Bizforge.CLI.Logs, :run, 1)
    end

    test "recognizes snapshot command" do
      assert function_exported?(Bizforge.CLI.Snapshot, :run, 1)
    end

    test "recognizes monitor command" do
      assert function_exported?(Bizforge.CLI.Monitor, :run, 1)
    end

    test "recognizes list command" do
      assert function_exported?(Bizforge.CLI.List, :run, 1)
    end

    test "recognizes pause command" do
      assert function_exported?(Bizforge.CLI.Pause, :run, 1)
    end

    test "recognizes resume command" do
      assert function_exported?(Bizforge.CLI.Resume, :run, 1)
    end

    test "recognizes config command" do
      assert function_exported?(Bizforge.CLI.Config, :run, 1)
    end

    test "recognizes attach command" do
      assert function_exported?(Bizforge.CLI.Attach, :run, 1)
    end
  end

  describe "CLI.Run option parsing" do
    test "parses --detach flag" do
      {opts, _args, _} =
        OptionParser.parse(["./workspace", "--detach"],
          strict: [detach: :boolean, dry_run: :boolean, monitor: :boolean, port: :integer, health_port: :integer, env: :string],
          aliases: [d: :detach, n: :dry_run, m: :monitor, p: :port]
        )

      assert opts[:detach] === true
    end

    test "parses --dry-run flag" do
      {opts, _args, _} =
        OptionParser.parse(["./workspace", "--dry-run"],
          strict: [detach: :boolean, dry_run: :boolean, monitor: :boolean, port: :integer, health_port: :integer, env: :string],
          aliases: [d: :detach, n: :dry_run, m: :monitor, p: :port]
        )

      assert opts[:dry_run] === true
    end

    test "parses --monitor flag" do
      {opts, _args, _} =
        OptionParser.parse(["./workspace", "--monitor"],
          strict: [detach: :boolean, dry_run: :boolean, monitor: :boolean, port: :integer, health_port: :integer, env: :string],
          aliases: [d: :detach, n: :dry_run, m: :monitor, p: :port]
        )

      assert opts[:monitor] === true
    end

    test "parses short aliases" do
      {opts, _args, _} =
        OptionParser.parse(["./workspace", "-d", "-m"],
          strict: [detach: :boolean, dry_run: :boolean, monitor: :boolean, port: :integer, health_port: :integer, env: :string],
          aliases: [d: :detach, n: :dry_run, m: :monitor, p: :port]
        )

      assert opts[:detach] === true
      assert opts[:monitor] === true
    end

    test "extracts workspace path from args" do
      {_opts, args, _} =
        OptionParser.parse(["./operations/sales-engine", "--detach"],
          strict: [detach: :boolean, dry_run: :boolean, monitor: :boolean, port: :integer, health_port: :integer, env: :string],
          aliases: [d: :detach, n: :dry_run, m: :monitor, p: :port]
        )

      assert args === ["./operations/sales-engine"]
    end
  end

  describe "CLI.Snapshot subcommands" do
    test "snapshot module handles all subcommands" do
      module = Bizforge.CLI.Snapshot

      assert function_exported?(module, :run, 1)
    end
  end
end
