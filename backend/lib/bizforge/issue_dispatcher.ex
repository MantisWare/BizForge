defmodule Bizforge.IssueDispatcher do
  @moduledoc """
  Subscribes to workspace PubSub topics and auto-dispatches agents
  when issues are assigned to them.

  Lifecycle:
    1. On init, subscribe to all existing workspace topics
    2. Listen for "issue.assigned" events
    3. Validate agent readiness (status, concurrent runs)
    4. Build context string from issue + goal
    5. Spawn heartbeat via Task.Supervisor
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Issue, Session, Workspace}
  import Ecto.Query

  # ── Client API ────────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribe to a new workspace topic (call this when a workspace is created)."
  def subscribe_workspace(workspace_id) do
    GenServer.cast(__MODULE__, {:subscribe, workspace_id})
  end

  @doc "Manually dispatch an issue to its assigned agent."
  def dispatch(issue_id) do
    GenServer.call(__MODULE__, {:dispatch, issue_id})
  catch
    # If the GenServer is not running (e.g. during tests or startup), convert
    # the exit signal into a normal error tuple so callers can handle it cleanly
    # instead of crashing with an unhandled exit.
    :exit, reason -> {:error, {:dispatcher_unavailable, reason}}
  end

  # ── Server Callbacks ──────────────────────────────────────────────────────────

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
          "[IssueDispatcher] Failed to load workspaces for subscription (will retry in #{div(@subscription_retry_ms, 1_000)}s): #{Exception.message(e)}"
        )

        Process.send_after(self(), :retry_subscribe_workspaces, @subscription_retry_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_subscribe_workspaces, state) do
    try do
      subscribe_all_workspaces()
      {:noreply, state}
    rescue
      e ->
        Logger.warning(
          "[IssueDispatcher] Still unable to load workspaces (will retry in #{div(@subscription_retry_ms, 1_000)}s): #{Exception.message(e)}"
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

    Logger.info("[IssueDispatcher] Subscribed to #{length(workspace_ids)} workspace topics")
  end

  @impl true
  def handle_cast({:subscribe, workspace_id}, state) do
    Bizforge.EventBus.subscribe(Bizforge.EventBus.workspace_topic(workspace_id))
    Logger.info("[IssueDispatcher] Subscribed to workspace #{workspace_id}")
    {:noreply, state}
  end

  # Matches the map broadcast by Work.assign_issue/2 (atom keys).
  @impl true
  def handle_info(%{event: "issue.assigned", issue_id: issue_id, agent_id: agent_id}, state) do
    Logger.info("[IssueDispatcher] issue.assigned — issue=#{issue_id} agent=#{agent_id}")
    do_dispatch(issue_id, agent_id)
    {:noreply, state}
  end

  # Ignore all other PubSub messages.
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:dispatch, issue_id}, _from, state) do
    result =
      case Repo.get(Issue, issue_id) do
        %Issue{assignee_id: nil} ->
          {:error, :not_assigned}

        %Issue{assignee_id: agent_id} ->
          do_dispatch(issue_id, agent_id)

        nil ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp do_dispatch(issue_id, agent_id) do
    with %Issue{} = issue <-
           Repo.get(Issue, issue_id) |> Repo.preload([:workspace, goal: :project]),
         %Agent{} = agent <- Repo.get(Agent, agent_id) |> Repo.preload(:workspace),
         :ok <- validate_agent(agent),
         {:ok, _checked_out_issue} <- Bizforge.Work.checkout_issue(issue_id, agent_id) do
      context = Bizforge.IssueContext.build_context(issue, agent)

      Task.Supervisor.start_child(Bizforge.HeartbeatRunner, fn ->
        Bizforge.Heartbeat.run(agent_id, context: context, issue_id: issue_id)
      end)

      Logger.info("[IssueDispatcher] Dispatched agent #{agent.name} for issue: #{issue.title}")
      {:ok, :dispatched}
    else
      nil ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("[IssueDispatcher] Skipped dispatch: #{inspect(reason)}")
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
        "[IssueDispatcher] Agent #{agent.name} at capacity (#{active_count}/#{agent.max_concurrent_runs} active runs)"
      )

      {:error, {:at_capacity, active_count}}
    else
      :ok
    end
  end
end
