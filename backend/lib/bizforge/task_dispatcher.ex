defmodule Bizforge.TaskDispatcher do
  @moduledoc """
  Subscribes to workspace PubSub topics and auto-dispatches agents
  when tasks are assigned to them.

  Lifecycle:
    1. On init, subscribe to all existing workspace topics
    2. Listen for "task.assigned" events
    3. Validate agent readiness (status, concurrent runs)
    4. Build context string from task + phase
    5. Spawn heartbeat via Task.Supervisor
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Task, Session, Workspace}
  import Ecto.Query

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe to a new workspace topic (call this when a workspace is created)."
  def subscribe_workspace(workspace_id) do
    GenServer.cast(__MODULE__, {:subscribe, workspace_id})
  end

  @doc "Manually dispatch a task to its assigned agent."
  def dispatch(task_id) do
    GenServer.call(__MODULE__, {:dispatch, task_id})
  catch
    :exit, reason -> {:error, {:dispatcher_unavailable, reason}}
  end

  @subscription_retry_ms :timer.seconds(5)

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :subscribe_workspaces}}
  end

  @impl true
  def handle_continue(:subscribe_workspaces, state) do
    try do
      subscribe_all_workspaces()
      {:noreply, state}
    rescue
      e ->
        Logger.warning(
          "[TaskDispatcher] Failed to load workspaces for subscription (will retry in #{div(@subscription_retry_ms, 1_000)}s): #{Exception.message(e)}"
        )

        Process.send_after(self(), :retry_subscribe_workspaces, @subscription_retry_ms)
        {:noreply, state}
    end
  end

  defp subscribe_all_workspaces do
    workspace_ids = Repo.all(from w in Workspace, select: w.id)

    for ws_id <- workspace_ids do
      Bizforge.EventBus.subscribe(Bizforge.EventBus.workspace_topic(ws_id))
    end

    Logger.info("[TaskDispatcher] Subscribed to #{length(workspace_ids)} workspace topics")
  end

  @impl true
  def handle_cast({:subscribe, workspace_id}, state) do
    Bizforge.EventBus.subscribe(Bizforge.EventBus.workspace_topic(workspace_id))
    Logger.info("[TaskDispatcher] Subscribed to workspace #{workspace_id}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:retry_subscribe_workspaces, state) do
    try do
      subscribe_all_workspaces()
      {:noreply, state}
    rescue
      e ->
        Logger.warning(
          "[TaskDispatcher] Still unable to load workspaces (will retry in #{div(@subscription_retry_ms, 1_000)}s): #{Exception.message(e)}"
        )

        Process.send_after(self(), :retry_subscribe_workspaces, @subscription_retry_ms)
        {:noreply, state}
    end
  end

  def handle_info(%{event: "task.assigned", task_id: task_id, agent_id: agent_id}, state) do
    Logger.info("[TaskDispatcher] task.assigned — task=#{task_id} agent=#{agent_id}")
    do_dispatch(task_id, agent_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:dispatch, task_id}, _from, state) do
    result =
      case Repo.get(Task, task_id) do
        %Task{assignee_id: nil} ->
          {:error, :not_assigned}

        %Task{assignee_id: agent_id} ->
          do_dispatch(task_id, agent_id)

        nil ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  defp do_dispatch(task_id, agent_id) do
    with %Task{} = task <-
           Repo.get(Task, task_id) |> Repo.preload([:workspace, phase: :project]),
         %Agent{} = agent <- Repo.get(Agent, agent_id) |> Repo.preload(:workspace),
         :ok <- validate_agent(agent),
         {:ok, _checked_out_task} <- Bizforge.Work.checkout_task(task_id, agent_id) do
      context = Bizforge.TaskContext.build_context(task, agent)

      Elixir.Task.Supervisor.start_child(Bizforge.HeartbeatRunner, fn ->
        Bizforge.Heartbeat.run(agent_id, context: context, issue_id: task_id)
      end)

      Logger.info("[TaskDispatcher] Dispatched agent #{agent.name} for task: #{task.title}")
      {:ok, :dispatched}
    else
      nil ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("[TaskDispatcher] Skipped dispatch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_agent(%Agent{status: status}) when status not in ["idle", "active"] do
    {:error, {:agent_not_ready, status}}
  end

  defp validate_agent(%Agent{} = agent) do
    active_count =
      Repo.aggregate(
        from(s in Session,
          where: s.agent_id == ^agent.id and s.status == "active"
        ),
        :count
      )

    if active_count >= agent.max_concurrent_runs do
      Logger.warning(
        "[TaskDispatcher] Agent #{agent.name} at capacity (#{active_count}/#{agent.max_concurrent_runs} active runs)"
      )

      {:error, {:at_capacity, active_count}}
    else
      :ok
    end
  end
end
