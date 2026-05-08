defmodule Bizforge.IssueLifecycle do
  @moduledoc """
  Issue lifecycle FSM — manages state transitions between dev, review, QA, and done.

  Subscribes to workspace PubSub topics and handles:
    - session.completed → transition issue from in_progress to in_review
    - pr.approved → transition from in_review to testing, spawn QA child issue
    - qa.report_ready → on pass: mark done; on fail: create bug issues routed to developer
    - pr.changes_requested → transition back to in_progress

  The FSM is configurable per project via `project.config["lifecycle"]`.
  Default behaviour if no config exists: dev → review → QA → done.
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Issue, Agent, Workspace}
  alias Bizforge.Work
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Notify that an agent session completed work on an issue."
  def notify_session_complete(issue_id, agent_id, work_product_id \\ nil) do
    GenServer.cast(__MODULE__, {:session_complete, issue_id, agent_id, work_product_id})
  end

  @doc "Notify that a PR/review was approved for an issue."
  def notify_review_approved(issue_id) do
    GenServer.cast(__MODULE__, {:review_approved, issue_id})
  end

  @doc "Notify that a PR review requested changes."
  def notify_changes_requested(issue_id) do
    GenServer.cast(__MODULE__, {:changes_requested, issue_id})
  end

  @doc "Notify that a QA report is ready for an issue."
  def notify_qa_report(issue_id, report) do
    GenServer.cast(__MODULE__, {:qa_report, issue_id, report})
  end

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    try do
      workspace_ids = Repo.all(from w in Workspace, select: w.id)

      for ws_id <- workspace_ids do
        Bizforge.EventBus.subscribe(Bizforge.EventBus.workspace_topic(ws_id))
      end

      Logger.info("[IssueLifecycle] Subscribed to #{length(workspace_ids)} workspace topics")
    rescue
      e ->
        Logger.warning("[IssueLifecycle] Subscription failed, retrying: #{Exception.message(e)}")
        Process.send_after(self(), :retry_subscribe, 5_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  def handle_info(%{event: "session.completed", issue_id: issue_id, agent_id: agent_id}, state)
      when is_binary(issue_id) do
    notify_session_complete(issue_id, agent_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:session_complete, issue_id, _agent_id, _work_product_id}, state) do
    case Repo.get(Issue, issue_id) do
      %Issue{status: "in_progress"} = issue ->
        transition_to_review(issue)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:review_approved, issue_id}, state) do
    case Repo.get(Issue, issue_id) do
      %Issue{status: "in_review"} = issue ->
        transition_to_testing(issue)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:changes_requested, issue_id}, state) do
    case Repo.get(Issue, issue_id) do
      %Issue{status: "in_review"} = issue ->
        transition_back_to_progress(issue)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:qa_report, issue_id, report}, state) do
    case Repo.get(Issue, issue_id) do
      %Issue{} = qa_issue ->
        handle_qa_result(qa_issue, report)

      nil ->
        Logger.warning("[IssueLifecycle] QA report for unknown issue #{issue_id}")
    end

    {:noreply, state}
  end

  defp transition_to_review(issue) do
    {:ok, updated} = issue |> change(status: "in_review", checked_out_by: nil) |> Repo.update()
    updated = Repo.preload(updated, [project: :integration_bindings])

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.workspace_topic(updated.workspace_id),
      %{event: "issue.status_changed", issue_id: updated.id, from: "in_progress", to: "in_review"}
    )

    if updated.project do
      open_code_review(updated, updated.project)
    end

    Logger.info("[IssueLifecycle] Issue #{updated.id} → in_review")
  end

  defp open_code_review(issue, project) do
    {adapter_mod, opts} =
      case Bizforge.CodeReview.Adapter.adapter_for(project) do
        {:ok, mod, opts} -> {mod, opts}
        :no_remote -> {Bizforge.CodeReview.VirtualPRAdapter, []}
      end

    case adapter_mod.open_pr(issue, project, opts) do
      {:ok, _handle} ->
        Logger.info("[IssueLifecycle] Opened code review (#{inspect(adapter_mod)}) for issue #{issue.id}")

      {:error, reason} ->
        Logger.warning("[IssueLifecycle] Failed to open code review: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("[IssueLifecycle] Code review open crashed: #{Exception.message(e)}")
  end

  defp transition_to_testing(issue) do
    spawn_qa_child(issue)

    Logger.info("[IssueLifecycle] Issue #{issue.id} → testing (QA child spawned, parent stays in_review until QA completes)")
  end

  defp transition_back_to_progress(issue) do
    {:ok, updated} = issue |> change(status: "in_progress") |> Repo.update()

    if updated.assignee_id do
      Bizforge.EventBus.broadcast(
        Bizforge.EventBus.workspace_topic(updated.workspace_id),
        %{event: "issue.assigned", issue_id: updated.id, agent_id: updated.assignee_id}
      )
    end

    Logger.info("[IssueLifecycle] Issue #{updated.id} → in_progress (changes requested)")
  end

  defp spawn_qa_child(parent_issue) do
    qa_agent_id = find_qa_agent(parent_issue)

    if qa_agent_id !== nil do
      attrs = %{
        title: "QA: #{parent_issue.title}",
        description: "Run automated QA against the work product for issue #{parent_issue.id}.\n\nParent issue: #{parent_issue.title}\nPriority: #{parent_issue.priority}",
        workspace_id: parent_issue.workspace_id,
        project_id: parent_issue.project_id,
        status: "backlog",
        priority: parent_issue.priority,
        assignee_id: qa_agent_id,
        delegation_chain: %{
          "step_1" => %{
            "from_issue_id" => parent_issue.id,
            "type" => "qa_review",
            "original_assignee_id" => parent_issue.assignee_id,
            "delegated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
      }

      case Work.create_issue(attrs) do
        {:ok, qa_issue} ->
          Logger.info("[IssueLifecycle] Created QA child #{qa_issue.id} for parent #{parent_issue.id}")

        {:error, reason} ->
          Logger.error("[IssueLifecycle] Failed to create QA child: #{inspect(reason)}")
      end
    else
      Logger.warning("[IssueLifecycle] No QA agent found for issue #{parent_issue.id}, parking in review")

      Bizforge.EventBus.broadcast(
        Bizforge.EventBus.workspace_topic(parent_issue.workspace_id),
        %{
          event: "notification.created",
          type: "team.missing_role",
          message: "No QA agent available to test issue: #{parent_issue.title}",
          issue_id: parent_issue.id
        }
      )
    end
  end

  defp find_qa_agent(issue) do
    developer_agent = if issue.assignee_id, do: Repo.get(Agent, issue.assignee_id), else: nil
    team_id = if developer_agent, do: developer_agent.team_id, else: nil

    case Bizforge.Dispatch.SkillRouter.choose(
           %{issue | title: "QA test #{issue.title}", description: "qa automate test"},
           team_id: team_id,
           project_id: issue.project_id,
           exclude_ids: if(issue.assignee_id, do: [issue.assignee_id], else: [])
         ) do
      {:ok, agent_id} -> agent_id
      {:error, _} -> find_qa_agent_fallback(issue.workspace_id)
    end
  end

  defp find_qa_agent_fallback(workspace_id) do
    Repo.one(
      from a in Agent,
        join: s in assoc(a, :skills),
        where: a.workspace_id == ^workspace_id,
        where: s.name in ["qa/automate", "browser/automation"],
        where: a.status in ["idle", "active"],
        order_by: [asc: a.inserted_at],
        limit: 1,
        select: a.id
    )
  end

  defp handle_qa_result(qa_issue, report) do
    pass? = report["pass"] == true || report["status"] == "pass"
    parent_issue_id = get_in(qa_issue.delegation_chain || %{}, ["step_1", "from_issue_id"])

    if pass? do
      {:ok, _} = qa_issue |> change(status: "done", checked_out_by: nil) |> Repo.update()

      if parent_issue_id do
        case Repo.get(Issue, parent_issue_id) do
          %Issue{} = parent ->
            {:ok, _} = parent |> change(status: "done", checked_out_by: nil) |> Repo.update()

            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.workspace_topic(parent.workspace_id),
              %{event: "issue.status_changed", issue_id: parent.id, from: "in_review", to: "done"}
            )

            Logger.info("[IssueLifecycle] QA passed — parent #{parent.id} → done")

          _ ->
            :ok
        end
      end
    else
      {:ok, _} = qa_issue |> change(status: "done", checked_out_by: nil) |> Repo.update()
      create_bug_issues(qa_issue, report)
    end
  end

  defp create_bug_issues(qa_issue, report) do
    failures = report["failures"] || []
    parent_issue_id = get_in(qa_issue.delegation_chain || %{}, ["step_1", "from_issue_id"])
    original_dev_id = get_in(qa_issue.delegation_chain || %{}, ["step_1", "original_assignee_id"])

    if parent_issue_id do
      case Repo.get(Issue, parent_issue_id) do
        %Issue{} = parent ->
          {:ok, _} = parent |> change(status: "in_progress") |> Repo.update()
          :ok

        _ ->
          :ok
      end
    end

    for failure <- Enum.take(failures, 10) do
      attrs = %{
        title: "Bug: #{failure["test"] || failure["name"] || "Test failure"}",
        description: """
        **Auto-generated from QA failure**

        Error: #{failure["error"] || "Unknown error"}
        File: #{failure["file"] || "N/A"}
        Line: #{failure["line"] || "N/A"}
        Screenshot: #{failure["screenshot"] || "N/A"}

        Parent issue: #{parent_issue_id}
        """,
        workspace_id: qa_issue.workspace_id,
        project_id: qa_issue.project_id,
        status: "backlog",
        priority: map_severity_to_priority(failure["severity"]),
        assignee_id: original_dev_id
      }

      case Work.create_issue(attrs) do
        {:ok, bug} ->
          Logger.info("[IssueLifecycle] Created bug #{bug.id} from QA failure")

        {:error, reason} ->
          Logger.error("[IssueLifecycle] Failed to create bug issue: #{inspect(reason)}")
      end
    end
  end

  defp map_severity_to_priority("critical"), do: "critical"
  defp map_severity_to_priority("high"), do: "high"
  defp map_severity_to_priority("medium"), do: "medium"
  defp map_severity_to_priority(_), do: "medium"
end
