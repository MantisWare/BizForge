defmodule Bizforge.SupervisorEscalation do
  @moduledoc """
  Walks the agent `reports_to` hierarchy to escalate failures.

  When an agent fails a task or exhausts retries, this module finds the
  nearest available superior and creates an escalation issue assigned to
  them.  If no superior exists or the chain is exhausted, a system-level
  notification is emitted instead.

  Cycle safety is enforced via a visited `MapSet` and a hard depth cap.
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Issue}
  import Ecto.Query, only: [from: 2]

  @max_escalation_depth 5

  @doc """
  Escalate a failure from `agent` up the `reports_to` chain.

  `reason` is a human-readable string describing what went wrong.
  `metadata` is an optional map with `:session_id`, `:issue_id`, etc.

  Accepts either an `%Agent{}` struct or a binary agent ID as the first argument.

  Returns `{:ok, :escalated, issue}` | `{:ok, :notified}` | `{:error, reason}`.
  """
  def escalate(agent_or_id, reason, metadata \\ %{})

  def escalate(%Agent{} = agent, reason, metadata) do
    case find_superior(agent, MapSet.new([agent.id]), 0) do
      {:ok, superior} ->
        create_escalation_issue(agent, superior, reason, metadata)

      :none ->
        Logger.warning(
          "[SupervisorEscalation] No superior found for agent #{agent.name} (#{agent.id}) — sending system alert"
        )

        Bizforge.Notifications.Dispatcher.notify_system_alert(
          "Escalation: #{agent.name} has no supervisor",
          "Agent #{agent.name} failed (#{reason}) and has no superior to escalate to. Manual intervention required.",
          "warning",
          agent.workspace_id
        )

        {:ok, :notified}
    end
  end

  def escalate(agent_id, reason, metadata) when is_binary(agent_id) do
    case Repo.get(Agent, agent_id) do
      %Agent{} = agent -> escalate(agent, reason, metadata)
      nil -> {:error, :agent_not_found}
    end
  end

  # Walk the reports_to chain with cycle detection and depth limit.
  defp find_superior(_agent, _visited, depth) when depth >= @max_escalation_depth, do: :none

  defp find_superior(%Agent{reports_to: nil}, _visited, _depth), do: :none
  defp find_superior(%Agent{reports_to: ""}, _visited, _depth), do: :none

  defp find_superior(%Agent{reports_to: superior_id}, visited, depth) do
    if MapSet.member?(visited, superior_id) do
      Logger.warning("[SupervisorEscalation] Cycle detected at agent #{superior_id}")
      :none
    else
      case Repo.get(Agent, superior_id) do
        nil ->
          Logger.warning("[SupervisorEscalation] Superior #{superior_id} not found in DB")
          :none

        %Agent{status: status} = superior when status in ["idle", "active", "sleeping"] ->
          {:ok, superior}

        %Agent{} = superior ->
          # Superior is busy/errored/paused — try their superior instead
          Logger.info(
            "[SupervisorEscalation] Superior #{superior.name} is #{superior.status}, checking next level"
          )

          find_superior(superior, MapSet.put(visited, superior_id), depth + 1)
      end
    end
  end

  defp create_escalation_issue(failing_agent, superior, reason, metadata) do
    session_summary = failing_agent.last_session_summary || "No session summary available."

    description = """
    ## Escalation from #{failing_agent.name}

    **Failure reason:** #{reason}

    **Original context:**
    - Session ID: #{metadata[:session_id] || "N/A"}
    - Issue ID: #{metadata[:issue_id] || "N/A"}

    **Last session summary:**
    #{session_summary}

    **Action required:**
    Review the failure, provide guidance, or reassign the work to an appropriate agent.
    """

    attrs = %{
      title: "[Escalation] #{failing_agent.name} failed: #{String.slice(reason, 0, 80)}",
      description: description,
      workspace_id: failing_agent.workspace_id,
      status: "backlog",
      priority: "high",
      assignee_id: superior.id,
      project_id: resolve_project_id(metadata[:issue_id])
    }

    case Bizforge.Work.create_issue(attrs) do
      {:ok, issue} ->
        Logger.info(
          "[SupervisorEscalation] Created escalation issue #{issue.id} assigned to #{superior.name}"
        )

        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.workspace_topic(issue.workspace_id),
          %{event: "issue.assigned", issue_id: issue.id, agent_id: superior.id}
        )

        {:ok, :escalated, issue}

      {:error, changeset} ->
        Logger.error(
          "[SupervisorEscalation] Failed to create escalation issue: #{inspect(changeset.errors)}"
        )

        {:error, :issue_creation_failed}
    end
  end

  # Pull the project_id from the original issue if available.
  defp resolve_project_id(nil), do: nil

  defp resolve_project_id(issue_id) do
    case Repo.one(from i in Issue, where: i.id == ^issue_id, select: i.project_id) do
      nil -> nil
      project_id -> project_id
    end
  end
end
