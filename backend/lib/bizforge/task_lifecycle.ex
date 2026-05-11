defmodule Bizforge.TaskLifecycle do
  @moduledoc """
  Task lifecycle FSM — manages state transitions between dev, review, QA, and done.

  Subscribes to workspace PubSub topics and handles:
    - session.completed → transition task from in_progress to in_review
    - pr.approved → transition from in_review to testing, spawn QA child task
    - qa.report_ready → on pass: mark done; on fail: create bug tasks routed to developer
    - pr.changes_requested → transition back to in_progress

  The FSM is configurable per project via `project.config["lifecycle"]`.
  Default behaviour if no config exists: dev → review → QA → done.
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Agent, Workspace}
  alias Bizforge.Work
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Notify that an agent session completed work on a task."
  def notify_session_complete(task_id, agent_id, work_product_id \\ nil) do
    GenServer.cast(__MODULE__, {:session_complete, task_id, agent_id, work_product_id})
  end

  @doc "Notify that a PR/review was approved for a task."
  def notify_review_approved(task_id) do
    GenServer.cast(__MODULE__, {:review_approved, task_id})
  end

  @doc "Notify that a PR review requested changes."
  def notify_changes_requested(task_id) do
    GenServer.cast(__MODULE__, {:changes_requested, task_id})
  end

  @doc "Notify that a QA report is ready for a task."
  def notify_qa_report(task_id, report) do
    GenServer.cast(__MODULE__, {:qa_report, task_id, report})
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

      Logger.info("[TaskLifecycle] Subscribed to #{length(workspace_ids)} workspace topics")
    rescue
      e ->
        Logger.warning("[TaskLifecycle] Subscription failed, retrying: #{Exception.message(e)}")
        Process.send_after(self(), :retry_subscribe, 5_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:retry_subscribe, state) do
    {:noreply, state, {:continue, :subscribe}}
  end

  def handle_info(%{event: "session.completed", issue_id: task_id, agent_id: agent_id}, state)
      when is_binary(task_id) do
    notify_session_complete(task_id, agent_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:session_complete, task_id, _agent_id, _work_product_id}, state) do
    case Repo.get(Task, task_id) |> Repo.preload(:project) do
      %Task{status: "in_progress"} = task ->
        lifecycle = get_lifecycle_config(task)

        if lifecycle["auto_review"] !== false do
          transition_to_review(task)
        else
          {:ok, _} = task |> change(status: "done", checked_out_by: nil) |> Repo.update()
          Logger.info("[TaskLifecycle] Task #{task.id} → done (no auto_review)")
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:review_approved, task_id}, state) do
    case Repo.get(Task, task_id) do
      %Task{status: "in_review"} = task ->
        transition_to_testing(task)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:changes_requested, task_id}, state) do
    case Repo.get(Task, task_id) do
      %Task{status: "in_review"} = task ->
        transition_back_to_progress(task)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:qa_report, task_id, report}, state) do
    case Repo.get(Task, task_id) do
      %Task{} = qa_task ->
        handle_qa_result(qa_task, report)

      nil ->
        Logger.warning("[TaskLifecycle] QA report for unknown task #{task_id}")
    end

    {:noreply, state}
  end

  defp transition_to_review(task) do
    {:ok, updated} = task |> change(status: "in_review", checked_out_by: nil) |> Repo.update()
    updated = Repo.preload(updated, [project: :integration_bindings])

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.workspace_topic(updated.workspace_id),
      %{event: "task.status_changed", task_id: updated.id, from: "in_progress", to: "in_review"}
    )

    if updated.project do
      open_code_review(updated, updated.project)
    end

    Logger.info("[TaskLifecycle] Task #{updated.id} → in_review")
  end

  defp open_code_review(task, project) do
    {adapter_mod, opts} =
      case Bizforge.CodeReview.Adapter.adapter_for(project) do
        {:ok, mod, opts} -> {mod, opts}
        :no_remote -> {Bizforge.CodeReview.VirtualPRAdapter, []}
      end

    case adapter_mod.open_pr(task, project, opts) do
      {:ok, _handle} ->
        Logger.info("[TaskLifecycle] Opened code review (#{inspect(adapter_mod)}) for task #{task.id}")

      {:error, reason} ->
        Logger.warning("[TaskLifecycle] Failed to open code review: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("[TaskLifecycle] Code review open crashed: #{Exception.message(e)}")
  end

  defp transition_to_testing(task) do
    spawn_qa_child(task)
    Logger.info("[TaskLifecycle] Task #{task.id} → testing (QA child spawned, parent stays in_review until QA completes)")
  end

  defp transition_back_to_progress(task) do
    {:ok, updated} = task |> change(status: "in_progress") |> Repo.update()

    if updated.assignee_id do
      Bizforge.EventBus.broadcast(
        Bizforge.EventBus.workspace_topic(updated.workspace_id),
        %{event: "task.assigned", task_id: updated.id, agent_id: updated.assignee_id}
      )
    end

    Logger.info("[TaskLifecycle] Task #{updated.id} → in_progress (changes requested)")
  end

  defp spawn_qa_child(parent_task) do
    qa_agent_id = find_qa_agent(parent_task)

    if qa_agent_id !== nil do
      attrs = %{
        title: "QA: #{parent_task.title}",
        description: "Run automated QA against the work product for task #{parent_task.id}.\n\nParent task: #{parent_task.title}\nPriority: #{parent_task.priority}",
        workspace_id: parent_task.workspace_id,
        project_id: parent_task.project_id,
        status: "backlog",
        priority: parent_task.priority,
        assignee_id: qa_agent_id,
        delegation_chain: %{
          "step_1" => %{
            "from_issue_id" => parent_task.id,
            "type" => "qa_review",
            "original_assignee_id" => parent_task.assignee_id,
            "delegated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
      }

      case Work.create_task(attrs) do
        {:ok, qa_task} ->
          Logger.info("[TaskLifecycle] Created QA child #{qa_task.id} for parent #{parent_task.id}")

        {:error, reason} ->
          Logger.error("[TaskLifecycle] Failed to create QA child: #{inspect(reason)}")
      end
    else
      Logger.warning("[TaskLifecycle] No QA agent found for task #{parent_task.id}, parking in review")

      Bizforge.EventBus.broadcast(
        Bizforge.EventBus.workspace_topic(parent_task.workspace_id),
        %{
          event: "notification.created",
          type: "team.missing_role",
          message: "No QA agent available to test task: #{parent_task.title}",
          task_id: parent_task.id
        }
      )
    end
  end

  defp find_qa_agent(task) do
    developer_agent = if task.assignee_id, do: Repo.get(Agent, task.assignee_id), else: nil
    team_id = if developer_agent, do: developer_agent.team_id, else: nil

    case Bizforge.Dispatch.SkillRouter.choose(
           %{task | title: "QA test #{task.title}", description: "qa automate test"},
           team_id: team_id,
           project_id: task.project_id,
           exclude_ids: if(task.assignee_id, do: [task.assignee_id], else: [])
         ) do
      {:ok, agent_id} -> agent_id
      {:error, _} -> find_qa_agent_fallback(task.workspace_id)
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

  defp handle_qa_result(qa_task, report) do
    pass? = report["pass"] == true || report["status"] == "pass"
    parent_task_id = get_in(qa_task.delegation_chain || %{}, ["step_1", "from_issue_id"])

    if pass? do
      {:ok, _} = qa_task |> change(status: "done", checked_out_by: nil) |> Repo.update()

      if parent_task_id do
        case Repo.get(Task, parent_task_id) do
          %Task{} = parent ->
            {:ok, _} = parent |> change(status: "done", checked_out_by: nil) |> Repo.update()

            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.workspace_topic(parent.workspace_id),
              %{event: "task.status_changed", task_id: parent.id, from: "in_review", to: "done"}
            )

            Logger.info("[TaskLifecycle] QA passed — parent #{parent.id} → done")

          _ ->
            :ok
        end
      end
    else
      {:ok, _} = qa_task |> change(status: "done", checked_out_by: nil) |> Repo.update()
      create_bug_tasks(qa_task, report)
    end
  end

  defp create_bug_tasks(qa_task, report) do
    failures = report["failures"] || []
    parent_task_id = get_in(qa_task.delegation_chain || %{}, ["step_1", "from_issue_id"])
    original_dev_id = get_in(qa_task.delegation_chain || %{}, ["step_1", "original_assignee_id"])

    if parent_task_id do
      case Repo.get(Task, parent_task_id) do
        %Task{} = parent ->
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

        Parent task: #{parent_task_id}
        """,
        workspace_id: qa_task.workspace_id,
        project_id: qa_task.project_id,
        status: "backlog",
        priority: map_severity_to_priority(failure["severity"]),
        assignee_id: original_dev_id
      }

      case Work.create_task(attrs) do
        {:ok, bug} ->
          Logger.info("[TaskLifecycle] Created bug #{bug.id} from QA failure")

        {:error, reason} ->
          Logger.error("[TaskLifecycle] Failed to create bug task: #{inspect(reason)}")
      end
    end
  end

  defp map_severity_to_priority("critical"), do: "critical"
  defp map_severity_to_priority("high"), do: "high"
  defp map_severity_to_priority("medium"), do: "medium"
  defp map_severity_to_priority(_), do: "medium"

  defp get_lifecycle_config(%Task{project: %{lifecycle_config: config}}) when is_map(config) and config != %{} do
    config
  end

  defp get_lifecycle_config(%Task{project: %{config: config}}) when is_map(config) do
    config["lifecycle"] || Bizforge.LifecycleConfigs.generic_development()
  end

  defp get_lifecycle_config(_task) do
    Bizforge.LifecycleConfigs.generic_development()
  end
end
