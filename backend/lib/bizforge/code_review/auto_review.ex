defmodule Bizforge.CodeReview.AutoReview do
  @moduledoc """
  Hybrid code review gate — auto-approves trivial virtual PRs and spawns a
  review agent task for non-trivial diffs.

  Called from `TaskLifecycle` immediately after `open_code_review/2`.
  """

  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Agent}
  alias Bizforge.Work
  import Ecto.Query

  @default_trivial_line_threshold 20

  @doc """
  Evaluate whether a code review can be auto-approved or requires a human/agent
  review.

  Returns:
    - `{:auto_approved, handle}` — diff was trivial, PR already approved
    - `{:review_dispatched, child_task}` — non-trivial diff, review task created
    - `{:skipped, reason}` — auto-review disabled or no PR to evaluate
  """
  @spec evaluate(Task.t(), map(), map() | nil) ::
          {:auto_approved, map()} | {:review_dispatched, Task.t()} | {:skipped, String.t()}
  def evaluate(task, project, pr_handle) do
    lifecycle = get_lifecycle_config(task, project)

    cond do
      lifecycle["auto_review"] === false ->
        {:skipped, "auto_review disabled in lifecycle config"}

      pr_handle === nil ->
        {:skipped, "no PR handle available"}

      true ->
        case classify_diff(pr_handle, project, lifecycle) do
          :trivial ->
            auto_approve(pr_handle, task)

          :non_trivial ->
            dispatch_review(task, project, pr_handle)
        end
    end
  end

  defp classify_diff(pr_handle, _project, lifecycle) do
    threshold = Map.get(lifecycle, "review_line_threshold", @default_trivial_line_threshold)

    case pr_handle.adapter.get_diff(pr_handle) do
      {:ok, diff} ->
        cond do
          trivial_diff?(diff) -> :trivial
          diff_line_count(diff) <= threshold && no_binary_paths?(diff) -> :trivial
          true -> :non_trivial
        end

      {:error, _} ->
        :non_trivial
    end
  end

  defp trivial_diff?(diff) do
    trimmed = String.trim(diff)
    trimmed == "" || trimmed == "(no changes detected)"
  end

  defp diff_line_count(diff) do
    diff
    |> String.split("\n")
    |> Enum.count(fn line ->
      String.starts_with?(line, "+") && !String.starts_with?(line, "+++")
      || String.starts_with?(line, "-") && !String.starts_with?(line, "---")
    end)
  end

  defp no_binary_paths?(diff) do
    not String.contains?(diff, "Binary files")
  end

  defp auto_approve(pr_handle, task) do
    case pr_handle.adapter.approve(pr_handle) do
      {:ok, approved_handle} ->
        Logger.info("[AutoReview] Auto-approved trivial PR for task #{task.id}")
        {:auto_approved, approved_handle}

      {:error, reason} ->
        Logger.warning("[AutoReview] Auto-approve failed: #{inspect(reason)}, dispatching review")
        {:skipped, "auto-approve failed: #{inspect(reason)}"}
    end
  end

  defp dispatch_review(task, project, pr_handle) do
    review_agent_id = find_review_agent(task)

    diff_summary =
      case pr_handle.adapter.get_diff(pr_handle) do
        {:ok, diff} -> String.slice(diff, 0..2000)
        _ -> "(diff unavailable)"
      end

    exec_paths = Bizforge.ProjectExecution.resolve_for_task(task, %{})
    code_dir_info =
      case exec_paths do
        {:ok, paths} -> paths.code_dir
        _ -> "(unknown)"
      end

    attrs = %{
      title: "Review: #{task.title}",
      description: """
      **Code review for task #{task.id}**

      Review the changes made in the following PR and approve or request changes.

      **Code directory:** `#{code_dir_info}`
      **PR type:** #{pr_handle.adapter |> to_string() |> String.split(".") |> List.last()}
      **PR branch:** #{pr_handle.branch_name}

      ### Diff summary (first 2000 chars)
      ```
      #{diff_summary}
      ```

      ### Review instructions
      - Check for correctness, style, and potential bugs
      - If changes look good, respond with: `{"verdict": "approve"}`
      - If changes need work, respond with: `{"verdict": "request_changes", "reason": "..."}`
      """,
      workspace_id: task.workspace_id,
      project_id: task.project_id,
      task_type: "validation",
      status: "backlog",
      priority: task.priority,
      assignee_id: review_agent_id,
      delegation_chain: %{
        "step_1" => %{
          "from_issue_id" => task.id,
          "type" => "code_review",
          "pr_id" => pr_handle.pr_id,
          "delegated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
    }

    case Work.create_task(attrs) do
      {:ok, review_task} ->
        Logger.info(
          "[AutoReview] Dispatched review task #{review_task.id} for parent #{task.id}"
        )

        {:review_dispatched, review_task}

      {:error, reason} ->
        Logger.error("[AutoReview] Failed to create review task: #{inspect(reason)}")
        {:skipped, "failed to create review task"}
    end
  end

  defp find_review_agent(task) do
    developer_agent = if task.assignee_id, do: Repo.get(Agent, task.assignee_id), else: nil
    team_id = if developer_agent, do: developer_agent.team_id, else: nil

    case Bizforge.Dispatch.SkillRouter.choose(
           %{task | title: "Review #{task.title}", description: "code review"},
           team_id: team_id,
           project_id: task.project_id,
           exclude_ids: if(task.assignee_id, do: [task.assignee_id], else: [])
         ) do
      {:ok, agent_id} -> agent_id
      {:error, _} -> find_review_agent_fallback(task.workspace_id)
    end
  end

  defp find_review_agent_fallback(workspace_id) do
    Repo.one(
      from a in Agent,
        join: s in assoc(a, :skills),
        where: a.workspace_id == ^workspace_id,
        where: s.name in ["development/code-review", "development/review"],
        where: a.status in ["idle", "active"],
        order_by: [asc: a.inserted_at],
        limit: 1,
        select: a.id
    )
  end

  defp get_lifecycle_config(%Task{}, project) do
    cond do
      is_map(project.lifecycle_config) && project.lifecycle_config != %{} ->
        project.lifecycle_config

      is_map(project.config) && is_map(project.config["lifecycle"]) ->
        project.config["lifecycle"]

      true ->
        Bizforge.LifecycleConfigs.generic_development()
    end
  rescue
    _ -> Bizforge.LifecycleConfigs.generic_development()
  end
end
