defmodule Bizforge.CLI.Config do
  @moduledoc """
  Handles the `bizforge config` command.

  Subcommands:
    - `show`     — display loaded workspace configuration summary
    - `validate` — validate workspace files before running
  """

  def run(argv) do
    case argv do
      ["show" | rest] -> show(rest)
      ["validate" | rest] -> validate(rest)
      _ -> print_usage()
    end
  end

  defp show(argv) do
    path =
      case argv do
        [p | _] -> Path.expand(p)
        [] -> Path.expand(".")
      end

    IO.puts("Workspace Configuration")
    IO.puts("=======================")
    IO.puts("Path: #{path}")
    IO.puts("")

    system_md = Path.join(path, "SYSTEM.md")

    if File.exists?(system_md) do
      content = File.read!(system_md)
      lines = String.split(content, "\n")
      title = Enum.find(lines, fn l -> String.starts_with?(l, "# ") end) || "Untitled"
      IO.puts("System: #{String.trim_leading(title, "# ")}")
    else
      IO.puts("System: (no SYSTEM.md found)")
    end

    company_yaml = Path.join(path, "company.yaml")

    if File.exists?(company_yaml) do
      IO.puts("Company: #{company_yaml} (present)")
    else
      IO.puts("Company: (no company.yaml found)")
    end

    agents_dir = Path.join(path, "agents")

    if File.dir?(agents_dir) do
      agents =
        agents_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))

      IO.puts("Agents: #{length(agents)} defined")

      Enum.each(agents, fn file ->
        name = String.replace_suffix(file, ".md", "")
        IO.puts("  - #{name}")
      end)
    else
      IO.puts("Agents: (no agents/ directory)")
    end

    skills_dir = Path.join(path, "skills")

    if File.dir?(skills_dir) do
      skills =
        skills_dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(skills_dir, &1)))

      IO.puts("Skills: #{length(skills)} defined")
    end

    workflows_dir = Path.join(path, "workflows")

    if File.dir?(workflows_dir) do
      workflows =
        workflows_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))

      IO.puts("Workflows: #{length(workflows)} defined")
    end
  end

  defp validate(argv) do
    path =
      case argv do
        [p | _] -> Path.expand(p)
        [] -> Path.expand(".")
      end

    IO.puts("Validating workspace: #{path}")
    IO.puts("")

    errors = []

    errors = check_file(errors, path, "SYSTEM.md", :required)
    errors = check_file(errors, path, "company.yaml", :required)
    errors = check_dir(errors, path, "agents", :required)
    errors = check_dir(errors, path, "skills", :optional)
    errors = check_dir(errors, path, "workflows", :optional)
    errors = check_dir(errors, path, "reference", :optional)

    agents_dir = Path.join(path, "agents")

    errors =
      if File.dir?(agents_dir) do
        agents_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reduce(errors, fn file, acc ->
          agent_path = Path.join(agents_dir, file)
          content = File.read!(agent_path)

          if String.contains?(content, "# ") do
            acc
          else
            ["Agent file #{file} missing heading (# Title)" | acc]
          end
        end)
      else
        errors
      end

    errors = Enum.reverse(errors)

    if errors === [] do
      IO.puts("  All checks passed.")
    else
      IO.puts("  #{length(errors)} issue(s) found:")

      Enum.each(errors, fn error ->
        IO.puts("    - #{error}")
      end)

      System.halt(1)
    end
  end

  defp check_file(errors, base, name, :required) do
    if File.exists?(Path.join(base, name)) do
      IO.puts("  [ok] #{name}")
      errors
    else
      IO.puts("  [MISSING] #{name}")
      ["Required file missing: #{name}" | errors]
    end
  end

  defp check_dir(errors, base, name, severity) do
    if File.dir?(Path.join(base, name)) do
      IO.puts("  [ok] #{name}/")
      errors
    else
      case severity do
        :required ->
          IO.puts("  [MISSING] #{name}/")
          ["Required directory missing: #{name}/" | errors]

        :optional ->
          IO.puts("  [skip] #{name}/ (optional)")
          errors
      end
    end
  end

  defp print_usage do
    IO.puts("""
    Usage:
      bizforge config show [workspace-path]       Show workspace configuration
      bizforge config validate [workspace-path]   Validate workspace files
    """)
  end
end
