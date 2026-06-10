defmodule Bizforge.ProjectDelivery do
  @moduledoc """
  Stack-agnostic Project Delivery Gate.

  Runs user-configured commands (build, test, etc.) against a project's
  output directory and produces a pass/fail delivery report. When all
  checks pass, the project transitions to `completed`.

  ## Config shape (on `project.config["delivery"]`)

      %{
        "cwd"                    => "code",          # relative to output_path
        "require_all_tasks_done" => true,
        "checks" => [
          %{"name" => "build", "command" => "npm run build", "timeout_ms" => 120_000, "required" => true},
          %{"name" => "test",  "command" => "npm test",      "timeout_ms" => 180_000, "required" => false}
        ]
      }
  """

  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Project, Task}
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  @default_timeout_ms 120_000

  @type check_result :: %{
          name: String.t(),
          command: String.t(),
          exit_code: integer(),
          stdout: String.t(),
          pass: boolean(),
          required: boolean(),
          elapsed_ms: integer()
        }

  @type delivery_report :: %{
          timestamp: String.t(),
          checks: [check_result()],
          overall_pass: boolean(),
          all_tasks_done: boolean()
        }

  @doc """
  Run the delivery gate for a project. Returns `{:ok, report}` or `{:error, reason}`.
  """
  @spec run(Project.t()) :: {:ok, delivery_report()} | {:error, term()}
  def run(%Project{} = project) do
    delivery_config = get_in(project.config || %{}, ["delivery"])

    cond do
      project.output_path === nil || project.output_path == "" ->
        {:error, :no_output_path}

      delivery_config === nil || delivery_config == %{} ->
        {:error, :no_delivery_config}

      true ->
        execute_gate(project, delivery_config)
    end
  end

  @doc """
  Check whether a project is ready for delivery (tasks done, output_path set, config present).
  """
  @spec readiness(Project.t()) :: %{ready: boolean(), reasons: [String.t()]}
  def readiness(%Project{} = project) do
    reasons = []
    delivery_config = get_in(project.config || %{}, ["delivery"])

    reasons =
      if project.output_path === nil || project.output_path == "",
        do: ["output_path not configured" | reasons],
        else: reasons

    reasons =
      if delivery_config === nil || delivery_config == %{},
        do: ["no delivery checks configured" | reasons],
        else: reasons

    reasons =
      if tasks_pending?(project.id),
        do: ["not all tasks are done" | reasons],
        else: reasons

    %{ready: reasons === [], reasons: Enum.reverse(reasons)}
  end

  defp execute_gate(project, delivery_config) do
    output_path = Path.expand(project.output_path)
    cwd_relative = Map.get(delivery_config, "cwd", "")

    cwd =
      if cwd_relative == "" do
        output_path
      else
        Path.join(output_path, cwd_relative)
      end

    if !File.dir?(cwd) do
      {:error, {:cwd_not_found, cwd}}
    else
      checks = Map.get(delivery_config, "checks", [])
      all_tasks_done = !tasks_pending?(project.id)
      require_all = Map.get(delivery_config, "require_all_tasks_done", true) !== false

      if require_all && !all_tasks_done do
        report = %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          checks: [],
          overall_pass: false,
          all_tasks_done: false
        }

        save_report(project, report)
        {:ok, report}
      else
        check_results = Enum.map(checks, &run_check(&1, cwd))
        required_pass = Enum.all?(check_results, fn r -> !r.required || r.pass end)

        report = %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          checks: check_results,
          overall_pass: required_pass,
          all_tasks_done: all_tasks_done
        }

        save_report(project, report)

        if required_pass do
          transition_to_completed(project)
        else
          notify_failure(project, report)
        end

        {:ok, report}
      end
    end
  end

  defp run_check(check, cwd) do
    name = Map.get(check, "name", "unnamed")
    command = Map.get(check, "command", "")
    timeout_ms = Map.get(check, "timeout_ms", @default_timeout_ms)
    required = Map.get(check, "required", true) !== false

    if command == "" do
      %{name: name, command: command, exit_code: -1, stdout: "empty command", pass: false, required: required, elapsed_ms: 0}
    else
      start = System.monotonic_time(:millisecond)

      {stdout, exit_code} =
        try do
          System.cmd("sh", ["-c", command], cd: cwd, stderr_to_stdout: true, env: [{"CI", "true"}])
        rescue
          e ->
            {Exception.message(e), 127}
        after
          elapsed = System.monotonic_time(:millisecond) - start
          if elapsed > timeout_ms do
            Logger.warning("[ProjectDelivery] Check '#{name}' exceeded timeout of #{timeout_ms}ms")
          end
        end

      elapsed_ms = System.monotonic_time(:millisecond) - start

      %{
        name: name,
        command: command,
        exit_code: exit_code,
        stdout: String.slice(to_string(stdout), 0..5000),
        pass: exit_code === 0,
        required: required,
        elapsed_ms: elapsed_ms
      }
    end
  end

  defp tasks_pending?(project_id) do
    Repo.exists?(
      from t in Task,
        where: t.project_id == ^project_id and t.status not in ["done", "cancelled"]
    )
  end

  defp save_report(project, report) do
    config = project.config || %{}
    updated_config = Map.put(config, "last_delivery", report)

    project
    |> change(config: updated_config)
    |> Repo.update()
  end

  defp transition_to_completed(project) do
    {:ok, updated} = project |> change(status: "completed") |> Repo.update()

    Logger.info("[ProjectDelivery] Project #{project.id} → completed")

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.workspace_topic(updated.workspace_id),
      %{event: "project.completed", project_id: updated.id, project_name: updated.name}
    )
  end

  defp notify_failure(project, _report) do
    Bizforge.Notifications.Dispatcher.notify_system_alert(
      "Delivery gate failed: #{project.name}",
      "One or more required delivery checks failed. Review the report for details.",
      "warning",
      project.workspace_id
    )
  end
end
