defmodule Bizforge.Qa.Runner do
  @moduledoc """
  Optional pre-flight QA runner that executes project delivery checks
  before the QA agent session, providing a fast-fail signal.

  When a QA task is dispatched, the runner can execute the project's
  `config.delivery.checks` as smoke tests. If they fail, the QA task
  is immediately reported as failed without waiting for an agent session.
  """

  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Project}

  @doc """
  Run delivery smoke checks for a QA task's parent project.

  Returns `{:ok, :pass}` if all required checks pass,
  `{:ok, :fail, failures}` if any required check fails,
  or `{:skip, reason}` if no checks are configured.
  """
  @spec smoke_check(Task.t()) :: {:ok, :pass} | {:ok, :fail, [map()]} | {:skip, String.t()}
  def smoke_check(%Task{project_id: nil}), do: {:skip, "no project"}

  def smoke_check(%Task{project_id: project_id}) do
    project = Repo.get(Project, project_id)

    cond do
      project === nil ->
        {:skip, "project not found"}

      project.output_path === nil || project.output_path == "" ->
        {:skip, "no output_path"}

      true ->
        delivery_config = get_in(project.config || %{}, ["delivery"])

        if delivery_config === nil || delivery_config == %{} do
          {:skip, "no delivery config"}
        else
          run_checks(project, delivery_config)
        end
    end
  end

  defp run_checks(project, delivery_config) do
    output_path = Path.expand(project.output_path)
    cwd_relative = Map.get(delivery_config, "cwd", "")

    cwd =
      if cwd_relative == "" do
        output_path
      else
        Path.join(output_path, cwd_relative)
      end

    if !File.dir?(cwd) do
      {:ok, :fail, [%{"test" => "cwd_exists", "error" => "Directory #{cwd} does not exist"}]}
    else
      checks = Map.get(delivery_config, "checks", [])
      required_checks = Enum.filter(checks, fn c -> Map.get(c, "required", true) !== false end)

      failures =
        Enum.reduce(required_checks, [], fn check, acc ->
          command = Map.get(check, "command", "")

          if command == "" do
            acc
          else
            case System.cmd("sh", ["-c", command], cd: cwd, stderr_to_stdout: true) do
              {_output, 0} ->
                acc

              {output, exit_code} ->
                [%{
                  "test" => Map.get(check, "name", "unnamed"),
                  "error" => "Exit code #{exit_code}: #{String.slice(output, 0..500)}"
                } | acc]
            end
          end
        end)

      if failures === [] do
        Logger.info("[Qa.Runner] All smoke checks passed for project #{project.id}")
        {:ok, :pass}
      else
        Logger.info("[Qa.Runner] #{length(failures)} smoke check(s) failed for project #{project.id}")
        {:ok, :fail, Enum.reverse(failures)}
      end
    end
  end
end
