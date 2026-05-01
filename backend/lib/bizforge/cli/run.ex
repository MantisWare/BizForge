defmodule Bizforge.CLI.Run do
  @moduledoc """
  Handles the `bizforge run <workspace-path>` command.

  Boots the Elixir runtime in headless mode, validates the workspace,
  starts all agent heartbeats, and enters the main supervision loop.
  """
  require Logger

  def run(argv) do
    {opts, args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          detach: :boolean,
          dry_run: :boolean,
          monitor: :boolean,
          port: :integer,
          health_port: :integer,
          env: :string
        ],
        aliases: [d: :detach, n: :dry_run, m: :monitor, p: :port]
      )

    workspace_path =
      case args do
        [path | _] -> Path.expand(path)
        [] -> Path.expand(".")
      end

    unless File.dir?(workspace_path) do
      IO.puts(:stderr, "Error: workspace path does not exist: #{workspace_path}")
      System.halt(1)
    end

    IO.puts("BizForge Headless Mode")
    IO.puts("======================")
    IO.puts("Workspace: #{workspace_path}")
    IO.puts("")

    if opts[:dry_run] do
      run_dry(workspace_path, opts)
    else
      run_live(workspace_path, opts)
    end
  end

  defp run_dry(workspace_path, _opts) do
    IO.puts("[dry-run] Validating workspace...")

    case validate_workspace(workspace_path) do
      :ok ->
        IO.puts("[dry-run] Workspace is valid.")
        IO.puts("[dry-run] Would start headless runtime. Exiting.")

      {:error, reasons} ->
        IO.puts(:stderr, "[dry-run] Workspace validation failed:")

        Enum.each(reasons, fn reason ->
          IO.puts(:stderr, "  - #{reason}")
        end)

        System.halt(1)
    end
  end

  defp run_live(workspace_path, opts) do
    IO.puts("Validating workspace...")

    case validate_workspace(workspace_path) do
      :ok ->
        IO.puts("Workspace validated.")

      {:error, reasons} ->
        IO.puts(:stderr, "Workspace validation failed:")

        Enum.each(reasons, fn reason ->
          IO.puts(:stderr, "  - #{reason}")
        end)

        System.halt(1)
    end

    configure_headless(workspace_path, opts)

    IO.puts("Starting headless runtime...")
    IO.puts("")

    if opts[:detach] do
      IO.puts("Detaching to background...")
      IO.puts("Use 'bizforge status' to check or 'bizforge stop' to shut down.")
    else
      IO.puts("Running in foreground. Press Ctrl+C to stop.")
      IO.puts("")

      if opts[:monitor] do
        Task.start(fn ->
          Process.sleep(5_000)
          Bizforge.CLI.Monitor.run(["--tui"])
        end)
      end

      receive do
        :never -> :ok
      end
    end
  end

  defp validate_workspace(path) do
    errors = []

    system_md = Path.join(path, "SYSTEM.md")
    company_yaml = Path.join(path, "company.yaml")

    errors =
      if File.exists?(system_md) do
        errors
      else
        ["Missing SYSTEM.md at #{system_md}" | errors]
      end

    errors =
      if File.exists?(company_yaml) do
        errors
      else
        ["Missing company.yaml at #{company_yaml}" | errors]
      end

    agents_dir = Path.join(path, "agents")

    errors =
      if File.dir?(agents_dir) do
        errors
      else
        ["Missing agents/ directory at #{agents_dir}" | errors]
      end

    if errors === [] do
      :ok
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp configure_headless(workspace_path, opts) do
    System.put_env("BIZFORGE_HEADLESS", "true")
    System.put_env("BIZFORGE_WORKSPACE_PATH", workspace_path)

    if opts[:port] do
      System.put_env("PORT", to_string(opts[:port]))
    end

    if opts[:health_port] do
      System.put_env("BIZFORGE_HEALTH_PORT", to_string(opts[:health_port]))
    end

    if opts[:env] do
      dotenv_path = Path.expand(opts[:env])

      if File.exists?(dotenv_path) do
        dotenv_path
        |> File.read!()
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) === "" || String.starts_with?(String.trim(&1), "#")))
        |> Enum.each(fn line ->
          case String.split(line, "=", parts: 2) do
            [key, value] -> System.put_env(String.trim(key), String.trim(value))
            _ -> :ok
          end
        end)
      end
    end
  end
end
