defmodule Bizforge.Dispatch.Delegation do
  @moduledoc """
  Handles task delegation between agents with adapter-aware routing.

  When an agent delegates a subtask, the delegation module:
    1. Creates the child task
    2. Routes to the optimal adapter via Dispatch.Router
    3. Assigns to the best available agent for that adapter (optional)
    4. Tracks the delegation chain via delegation_chain metadata

  ## Example

      parent = Repo.get!(Task, parent_id)
      {:ok, child} = Delegation.delegate(parent, "Analyze screenshots for layout issues")
      # child.adapter_override == "gemini"
  """

  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Agent}
  import Ecto.Query, only: [from: 2]

  @doc """
  Delegate a subtask from a parent task.

  ## Options
    - `:adapter`    — explicit adapter type string (skips inference)
    - `:agent_id`   — assign to a specific agent UUID
    - `:priority`   — override priority (defaults to parent's priority)

  Returns `{:ok, issue}` or `{:error, changeset}`.
  """
  @spec delegate(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def delegate(%{} = parent_task, description, opts \\ []) when is_binary(description) do
    adapter_type = opts[:adapter] || infer_adapter(description)

    assignee_id =
      opts[:agent_id] || find_agent_for_adapter(adapter_type, parent_task.workspace_id)

    # Build delegation chain: parent chain + this delegation step
    parent_chain = Map.get(parent_task, :delegation_chain) || %{}
    step_key = "step_#{map_size(parent_chain) + 1}"

    delegation_chain =
      Map.put(parent_chain, step_key, %{
        "from_issue_id" => to_string(parent_task.id),
        "adapter" => adapter_type,
        "delegated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    attrs =
      %{
        title: description,
        description: description,
        workspace_id: parent_task.workspace_id,
        status: "backlog",
        priority: opts[:priority] || Map.get(parent_task, :priority) || "medium",
        adapter_override: adapter_type,
        delegation_chain: delegation_chain
      }
      |> maybe_put(:assignee_id, assignee_id)
      |> maybe_put(:project_id, Map.get(parent_task, :project_id))
      |> maybe_put(:phase_id, Map.get(parent_task, :phase_id))

    result = %Task{} |> Task.changeset(attrs) |> Repo.insert()

    case result do
      {:ok, task} ->
        Logger.info(
          "[Delegation] Created subtask #{task.id} (#{adapter_type}) from parent #{parent_task.id}"
        )

        if task.assignee_id do
          Bizforge.EventBus.broadcast(
            Bizforge.EventBus.workspace_topic(task.workspace_id),
            %{event: "task.assigned", task_id: task.id, agent_id: task.assignee_id}
          )
        end

        {:ok, task}

      {:error, changeset} ->
        Logger.warning("[Delegation] Failed to create subtask: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp infer_adapter(description) do
    Bizforge.Dispatch.Router.infer_adapter_type(description) || "osa"
  end

  # Find the best idle agent in the workspace that uses this adapter type.
  # Prefers idle agents, then any non-working agent. Returns nil if none found.
  defp find_agent_for_adapter(adapter_type, workspace_id)
       when is_binary(adapter_type) and is_binary(workspace_id) do
    query =
      from a in Agent,
        where: a.workspace_id == ^workspace_id and a.adapter == ^adapter_type,
        order_by: [
          asc:
            fragment(
              "CASE WHEN ? = 'idle' THEN 0 WHEN ? = 'sleeping' THEN 1 ELSE 2 END",
              a.status,
              a.status
            ),
          asc: a.inserted_at
        ],
        limit: 1,
        select: a.id

    case Repo.one(query) do
      nil ->
        Logger.debug(
          "[Delegation] No agent found for adapter #{adapter_type} in workspace #{workspace_id}"
        )

        nil

      agent_id ->
        Logger.debug("[Delegation] Assigned to agent #{agent_id} (adapter: #{adapter_type})")
        agent_id
    end
  end

  defp find_agent_for_adapter(_, _), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
