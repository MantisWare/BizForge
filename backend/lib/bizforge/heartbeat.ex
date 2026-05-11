defmodule Bizforge.Heartbeat do
  @moduledoc """
  Executes a heartbeat run for an agent.

  Lifecycle (12 steps):
    1. Check governance gates (heartbeat_blocked?)
    2. Resolve adapter via dispatch router (task override → labels → content → agent default)
    3. Create or reuse session record
    4. Resolve workspace path (fail fast before setting agent to "working")
    5. Set agent status to "working" and broadcast run.started
    6. Optionally checkout an issue (atomic lock with FOR UPDATE)
    7. Build full context: system prompt + continuation from prior sessions + task context
    8. Execute heartbeat via adapter — stream events, persist each to DB and broadcast
    9. Complete session with token counts and cost, set agent to "idle"
   10. Compact session — generate summary and handoff notes for next heartbeat
   11. Mark issue as done and create WorkProduct record (if issue_id provided)
   12. Cleanup workspace and record cost with BudgetEnforcer
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Session, SessionEvent, Workspace, WorkProduct, ActivityEvent}
  alias Bizforge.Sessions.Compactor
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [from: 2]

  @max_heartbeat_retries 2
  @heartbeat_backoff_base_ms 5_000

  @doc """
  Run a heartbeat for the given agent.

  ## Options
    - `:schedule_id` — UUID of the triggering schedule (optional)
    - `:session_id`  — UUID of an already-created session row (optional).
                       When provided, Heartbeat reuses that row rather than
                       inserting a new one.  SpawnController uses this to
                       avoid the duplicate-session bug.
    - `:context`     — instruction string passed to the adapter (default: generic heartbeat prompt)
    - `:issue_id`    — UUID of an issue to checkout before execution and complete after (optional)
  """
  def run(agent_id, opts \\ []) do
    schedule_id = opts[:schedule_id]
    existing_session_id = opts[:session_id]
    context = opts[:context] || "Perform your scheduled heartbeat."
    issue_id = opts[:issue_id]

    # Pre-fetch the issue (if provided) so the dispatch router can inspect it.
    # This is done before adapter resolution to enable task-level override routing.
    prefetched_issue =
      if issue_id, do: Repo.get(Bizforge.Schemas.Task, issue_id), else: nil

    with %Agent{} = agent <- Repo.get(Agent, agent_id),
         :clear <- Bizforge.Governance.Gate.heartbeat_blocked?(agent_id),
         {:ok, adapter_mod} <- resolve_adapter(prefetched_issue, agent) do
      try do
      session =
        if existing_session_id do
          Repo.get!(Session, existing_session_id)
        else
          create_session!(agent, schedule_id)
        end

      # Resolve workspace early so that any failure (missing path, bad config)
      # is caught here — before we set the agent to "working" — allowing
      # fail_session! to run and preventing a stuck "active" session.
      workspace =
        try do
          resolve_workspace(agent)
        rescue
          e ->
            fail_session!(session, Exception.message(e))
            agent |> change(status: "error") |> Repo.update!()
            raise e
        end

      agent |> change(status: "working") |> Repo.update!()

      broadcast_workspace(agent, %{
        event: "run.started",
        agent_id: agent.id,
        session_id: session.id,
        agent_name: agent.name
      })

      BizforgeWeb.Endpoint.broadcast("activity:global", "new_event", %{
        event: "run.started",
        agent_id: agent.id,
        session_id: session.id,
        timestamp: DateTime.utc_now()
      })

      persist_activity_event(
        agent,
        "run.started",
        "Agent #{agent.name} started a heartbeat run",
        %{session_id: session.id}
      )

      if issue_id do
        Repo.transaction(fn ->
          case Repo.one(
                 from i in Bizforge.Schemas.Task, where: i.id == ^issue_id, lock: "FOR UPDATE"
               ) do
            nil ->
              Logger.warning("[Heartbeat] Task #{issue_id} not found, skipping checkout")

            %{checked_out_by: existing} when not is_nil(existing) ->
              Logger.warning(
                "[Heartbeat] Task #{issue_id} already checked out by #{existing}, skipping"
              )

              Repo.rollback(:already_checked_out)

            issue ->
              issue |> change(status: "in_progress", checked_out_by: agent.id) |> Repo.update!()
              Logger.info("[Heartbeat] Checked out issue #{issue_id} for agent #{agent.name}")
          end
        end)
      end

      # Build continuation context from previous sessions (cross-heartbeat resumption)
      continuation_context = Compactor.build_continuation_context(agent)

      # Prepend system prompt, then continuation context, then the task context
      full_context =
        cond do
          agent.system_prompt && agent.system_prompt != "" && continuation_context != "" ->
            "#{agent.system_prompt}\n\n---\n\n#{continuation_context}#{context}"

          agent.system_prompt && agent.system_prompt != "" ->
            "#{agent.system_prompt}\n\n---\n\n#{context}"

          continuation_context != "" ->
            "#{continuation_context}#{context}"

          true ->
            context
        end

      integration_env = resolve_integration_env(agent, prefetched_issue)

      params = %{
        "context" => full_context,
        "model" => agent.model,
        "working_dir" => workspace.path,
        "workspace_path" => workspace.path,
        "url" => agent.config["url"],
        "env" => integration_env
      }

      Logger.info(
        "[Heartbeat] Executing agent #{agent.name} (#{agent.id}) via #{agent.adapter} in #{workspace.path} (#{map_size(integration_env)} env vars from integrations)"
      )

      unless Bizforge.AdapterCircuitBreaker.available?(agent.adapter) do
        Logger.warning(
          "[Heartbeat] Circuit breaker OPEN for adapter #{agent.adapter} — skipping execution"
        )

        fail_session!(session, "Adapter #{agent.adapter} circuit breaker is open")
        agent |> change(status: "idle") |> Repo.update!()

        if issue_id do
          Repo.transaction(fn ->
            case Repo.one(from i in Bizforge.Schemas.Task, where: i.id == ^issue_id, lock: "FOR UPDATE") do
              nil -> :ok
              task -> task |> change(status: "backlog", checked_out_by: nil) |> Repo.update!()
            end
          end)
        end

        Bizforge.SupervisorEscalation.escalate(agent, "Adapter #{agent.adapter} is unavailable (circuit breaker open)", %{
          session_id: session.id,
          issue_id: issue_id
        })

        throw({:circuit_open, agent.adapter})
      end

      stream_result = execute_with_retries(adapter_mod, params, session, agent, 0)

      case stream_result do
        {:error, reason, _partial_totals} ->
          handle_run_failure(session, agent, issue_id, reason)
          throw({:execution_failed, reason})

        _totals ->
          :ok
      end

      totals = stream_result
      session = complete_session!(session, totals)
      agent |> change(status: "idle") |> Repo.update!()

      # Compact the session — generate summary and handoff for next heartbeat
      case Compactor.compact(session, "session_complete") do
        {:ok, _compacted} ->
          Logger.info("[Heartbeat] Session #{session.id} compacted successfully")

        {:error, reason} ->
          Logger.warning(
            "[Heartbeat] Session compaction failed for #{session.id}: #{inspect(reason)}"
          )
      end

      if issue_id do
        wp_id =
          case %WorkProduct{}
               |> WorkProduct.changeset(%{
                 title: "Heartbeat output for issue #{issue_id}",
                 type: "code",
                 product_type: "heartbeat",
                 status: "final",
                 issue_id: issue_id,
                 session_id: session.id,
                 agent_id: agent.id,
                 workspace_id: agent.workspace_id
               })
               |> Repo.insert() do
            {:ok, wp} ->
              Logger.info("[Heartbeat] Created WorkProduct #{wp.id} for issue #{issue_id}")
              wp.id

            {:error, changeset} ->
              Logger.warning(
                "[Heartbeat] Failed to create WorkProduct for issue #{issue_id}: #{inspect(changeset.errors)}"
              )
              nil
          end

        Bizforge.TaskLifecycle.notify_session_complete(issue_id, agent.id, wp_id)
        Logger.info("[Heartbeat] Notified TaskLifecycle for task #{issue_id}")
      end

      cleanup_workspace(workspace)

      if totals.cost > 0 do
        Bizforge.BudgetEnforcer.record_cost(%{
          agent_id: agent.id,
          session_id: session.id,
          model: agent.model,
          tokens_input: totals.input,
          tokens_output: totals.output,
          tokens_cache: totals.cache,
          cost_cents: totals.cost
        })
      end

      broadcast_workspace(agent, %{
        event: "run.completed",
        agent_id: agent.id,
        session_id: session.id,
        agent_name: agent.name,
        cost_cents: totals.cost
      })

      BizforgeWeb.Endpoint.broadcast("activity:global", "new_event", %{
        event: "run.completed",
        agent_id: agent.id,
        session_id: session.id,
        timestamp: DateTime.utc_now()
      })

      persist_activity_event(
        agent,
        "run.completed",
        "Agent #{agent.name} completed run (cost: #{totals.cost}\u00A2)",
        %{session_id: session.id, cost_cents: totals.cost}
      )

      {:ok, session.id}
      rescue
        e ->
          Logger.error("[Heartbeat] Unhandled error in run/2: #{Exception.message(e)}")
          {:error, {:unhandled, Exception.message(e)}}
      catch
        {:circuit_open, adapter} ->
          {:error, {:circuit_open, adapter}}

        {:execution_failed, reason} ->
          {:error, {:execution_failed, reason}}
      end
    else
      nil ->
        {:error, :agent_not_found}

      {:blocked, approval_ids} ->
        Logger.info(
          "[Heartbeat] Skipping agent #{agent_id}: #{length(approval_ids)} pending approval(s) blocking execution"
        )

        {:error, {:blocked_by_approvals, approval_ids}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp create_session!(agent, schedule_id) do
    %Session{}
    |> Session.changeset(%{
      agent_id: agent.id,
      schedule_id: schedule_id,
      model: agent.model,
      status: "active",
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  # Returns the updated session struct so callers can pass it to Compactor.
  defp complete_session!(session, totals) do
    session
    |> change(%{
      status: "completed",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      tokens_input: totals.input,
      tokens_output: totals.output,
      tokens_cache: totals.cache,
      cost_cents: totals.cost
    })
    |> Repo.update!()
  end

  defp handle_run_failure(session, agent, issue_id, reason) do
    fail_session!(session, reason)
    agent |> change(status: "error") |> Repo.update!()

    if issue_id !== nil do
      Repo.transaction(fn ->
        case Repo.one(
               from i in Bizforge.Schemas.Task,
                 where: i.id == ^issue_id,
                 lock: "FOR UPDATE"
             ) do
          nil ->
            :ok

          task ->
            task |> change(status: "backlog", checked_out_by: nil) |> Repo.update!()
            Logger.info("[Heartbeat] Rolled back task #{issue_id} to backlog after failure")
        end
      end)
    end

    broadcast_workspace(agent, %{
      event: "run.failed",
      agent_id: agent.id,
      session_id: session.id,
      error: reason
    })

    BizforgeWeb.Endpoint.broadcast("activity:global", "new_event", %{
      event: "run.failed",
      agent_id: agent.id,
      session_id: session.id,
      timestamp: DateTime.utc_now()
    })

    persist_activity_event(
      agent,
      "run.failed",
      "Agent #{agent.name} run failed: #{reason}",
      %{session_id: session.id}
    )

    Bizforge.Notifications.Dispatcher.notify_system_alert(
      "Agent failure: #{agent.name}",
      "Heartbeat run failed: #{reason}",
      "error",
      agent.workspace_id
    )

    Bizforge.SupervisorEscalation.escalate(agent, reason, %{
      session_id: session.id,
      issue_id: issue_id
    })
  end

  defp fail_session!(session, reason) do
    session
    |> change(%{
      status: "failed",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()

    Logger.error("[Heartbeat] Session #{session.id} failed: #{reason}")
  end

  # Returns a map with :path and :strategy keys.
  # Looks up the actual workspace path from the DB instead of using CWD.
  defp resolve_workspace(agent) do
    workspace_path =
      case Repo.get(Workspace, agent.workspace_id) do
        %Workspace{path: path} when is_binary(path) and path != "" ->
          path

        %Workspace{path: path_value} ->
          raise "No workspace path found for agent #{agent.id} " <>
                  "(workspace_id: #{inspect(agent.workspace_id)}, workspace.path was: #{inspect(path_value)}). " <>
                  "Set workspace.path to a valid directory before running the heartbeat."

        nil ->
          raise "No workspace found for agent #{agent.id} " <>
                  "(workspace_id: #{inspect(agent.workspace_id)}). " <>
                  "The workspace record does not exist in the database."
      end

    unless File.dir?(workspace_path) do
      Logger.warning(
        "[Heartbeat] Workspace path #{workspace_path} does not exist on disk for agent #{agent.id}. " <>
          "The heartbeat will likely fail. Ensure the workspace is initialized."
      )
    end

    Logger.info("[Heartbeat] Resolved workspace path: #{workspace_path} for agent #{agent.id}")

    if agent.config["workspace_strategy"] == "shared" do
      %{path: workspace_path, strategy: :shared}
    else
      case Bizforge.ExecutionWorkspace.create(workspace_path, strategy: :worktree) do
        {:ok, ws} ->
          ws

        {:error, reason} ->
          Logger.warning(
            "[Heartbeat] Worktree creation failed (#{inspect(reason)}), using shared workspace"
          )

          %{path: workspace_path, strategy: :shared}
      end
    end
  end

  defp cleanup_workspace(%{strategy: :shared}), do: :ok

  defp cleanup_workspace(workspace) do
    Bizforge.ExecutionWorkspace.cleanup(workspace)
  end

  defp execute_with_retries(adapter_mod, params, session, agent, attempt) do
    result =
      try do
        execute_and_stream(adapter_mod, params, session, agent)
      rescue
        e ->
          Logger.error(
            "[Heartbeat] FATAL (attempt #{attempt + 1}): #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
          )

          {:error, Exception.message(e), %{input: 0, output: 0, cache: 0, cost: 0}}
      end

    case result do
      {:error, reason, _partial} when attempt < @max_heartbeat_retries ->
        backoff = (@heartbeat_backoff_base_ms * :math.pow(2, attempt)) |> round()

        Logger.warning(
          "[Heartbeat] Adapter failure (attempt #{attempt + 1}/#{@max_heartbeat_retries + 1}): #{reason} — retrying in #{backoff}ms"
        )

        Process.sleep(backoff)
        execute_with_retries(adapter_mod, params, session, agent, attempt + 1)

      other ->
        other
    end
  end

  defp execute_and_stream(adapter_mod, params, session, agent) do
    result =
      try do
        totals =
          adapter_mod.execute_heartbeat(params)
          |> Enum.reduce(%{input: 0, output: 0, cache: 0, cost: 0, had_failure: false}, fn raw_event, acc ->
            event = normalize_event(raw_event)
            event_type = event["event_type"] || "run.output"
            data = event["data"] || %{}

            persist_event!(event_type, data, raw_event, session)

            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.session_topic(session.id),
              %{
                event: event_type,
                data: data,
                session_id: session.id,
                agent_id: agent.id
              }
            )

            input_tokens = raw_event[:tokens_input] || raw_event["tokens_input"] || raw_event[:tokens] || raw_event["tokens"] || 0
            output_tokens = raw_event[:tokens_output] || raw_event["tokens_output"] || 0
            cache_tokens = raw_event[:tokens_cache] || raw_event["tokens_cache"] || 0

            new_input = acc.input + input_tokens
            new_output = acc.output + output_tokens
            new_cache = acc.cache + cache_tokens
            cost = estimate_cost(new_input, new_output, new_cache, agent.model)

            had_failure = acc.had_failure or event_type == "run.failed"

            %{acc | input: new_input, output: new_output, cache: new_cache, cost: cost, had_failure: had_failure}
          end)

        {:ok, totals}
      rescue
        e ->
          Logger.error(
            "[Heartbeat] Execution error for agent #{agent.id}: #{Exception.message(e)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )

          Bizforge.AdapterCircuitBreaker.record_failure(agent.adapter)
          {:error, Exception.message(e), %{input: 0, output: 0, cache: 0, cost: 0}}
      end

    case result do
      {:ok, %{had_failure: true} = totals} ->
        has_output = session_has_output_events?(session.id)

        if has_output do
          Map.delete(totals, :had_failure)
        else
          Bizforge.AdapterCircuitBreaker.record_failure(agent.adapter)
          {:error, "Adapter returned run.failed with no output", Map.delete(totals, :had_failure)}
        end

      {:ok, totals} ->
        Bizforge.AdapterCircuitBreaker.record_success(agent.adapter)
        Map.delete(totals, :had_failure)

      {:error, _reason, _partial} = err ->
        err
    end
  end

  defp session_has_output_events?(session_id) do
    Repo.exists?(
      from e in SessionEvent,
        where: e.session_id == ^session_id and e.event_type in ["run.output", "run.result"]
    )
  end

  defp normalize_event(event) when is_map(event) do
    cond do
      is_binary(Map.get(event, "event_type")) -> event
      is_binary(Map.get(event, :event_type)) ->
        %{
          "event_type" => Map.get(event, :event_type),
          "data" => Map.get(event, :data, %{})
        }
      true -> %{"event_type" => "run.output", "data" => event}
    end
  end

  defp persist_event!(event_type, data, raw_event, session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    tokens = (raw_event[:tokens_input] || raw_event["tokens_input"] || raw_event[:tokens] || raw_event["tokens"] || 0) +
             (raw_event[:tokens_output] || raw_event["tokens_output"] || 0)

    %SessionEvent{}
    |> SessionEvent.changeset(%{
      session_id: session.id,
      event_type: event_type,
      data: data,
      tokens: tokens,
      inserted_at: now
    })
    |> Repo.insert!()
  end

  defp broadcast_workspace(agent, payload) do
    Bizforge.EventBus.broadcast(Bizforge.EventBus.workspace_topic(agent.workspace_id), payload)
  end

  # Cost estimation in cents using per-direction pricing.
  # Rates are cents per 1K tokens based on Anthropic API pricing (March 2026).
  # Includes separate cache token rate (cache reads are ~10x cheaper than input).
  # Returns an integer — cents.
  defp estimate_cost(input_tokens, output_tokens, cache_tokens, model) do
    {input_rate, output_rate, cache_rate} = model_rates(model)

    input_cost = input_tokens / 1000 * input_rate
    output_cost = output_tokens / 1000 * output_rate
    cache_cost = cache_tokens / 1000 * cache_rate

    # Use ceil to avoid rounding small sessions to $0
    ceil(input_cost + output_cost + cache_cost)
  end

  # Rates in cents per 1K tokens: {input, output, cache_read}
  # Uses String.contains? to match both full model IDs ("claude-opus-4-6")
  # and short names ("opus", "sonnet") that agents typically use.
  defp model_rates(model) when is_binary(model) do
    normalized = String.downcase(model)

    cond do
      String.contains?(normalized, "opus") -> {1.5, 7.5, 0.15}
      String.contains?(normalized, "haiku") -> {0.08, 0.4, 0.008}
      String.contains?(normalized, "sonnet") -> {0.3, 1.5, 0.03}
      true -> {0.3, 1.5, 0.03}
    end
  end

  defp model_rates(_), do: {0.3, 1.5, 0.03}

  # Resolve the adapter to use for this heartbeat run.
  #
  # Priority:
  #   1. Task-level adapter_override (if an issue is present and has one)
  #   2. Dynamic dispatch via Dispatch.Router (label -> content -> agent default)
  #
  # Falls back to the agent's default adapter on any routing failure so the
  # heartbeat always proceeds rather than crashing at the resolution step.
  defp resolve_adapter(nil, agent), do: Bizforge.Adapter.resolve(agent.adapter)

  defp resolve_adapter(%{adapter_override: override}, agent)
       when is_binary(override) and override != "" do
    case Bizforge.Adapter.resolve(override) do
      {:ok, _} = ok ->
        Logger.info("[Heartbeat] Using task adapter override: #{override}")
        ok

      {:error, _} ->
        Logger.warning(
          "[Heartbeat] Unknown adapter override #{inspect(override)}, falling back to agent default"
        )

        Bizforge.Adapter.resolve(agent.adapter)
    end
  end

  defp resolve_adapter(issue, agent) do
    Bizforge.Dispatch.Router.resolve(issue, agent)
  end

  defp resolve_integration_env(agent, issue) do
    project_id = if issue, do: issue.project_id, else: nil

    resolutions =
      if project_id do
        case Bizforge.IntegrationResolver.resolve_for_agent_in_project(agent, project_id) do
          {:ok, list} -> list
          {:error, _} -> []
        end
      else
        case Bizforge.IntegrationResolver.resolve_for_agent(agent) do
          {:ok, list} -> list
          {:error, _} -> []
        end
      end

    Enum.reduce(resolutions, %{}, fn resolution, acc ->
      provider_env = build_provider_env(resolution)
      Map.merge(acc, provider_env)
    end)
  rescue
    e ->
      Logger.warning("[Heartbeat] Integration resolution failed: #{Exception.message(e)}")
      %{}
  end

  @provider_env_mapping %{
    "domo" => [{"DOMO_INSTANCE", "instance"}, {"DOMO_TOKEN", "token"}, {"DOMO_PROXY_ID", "proxy_id"}],
    "github" => [{"GITHUB_TOKEN", "token"}, {"GITHUB_REPO", "repo"}, {"GITHUB_OWNER", "owner"}],
    "gitlab" => [{"GITLAB_TOKEN", "token"}, {"GITLAB_PROJECT_ID", "project_id"}],
    "slack" => [{"SLACK_BOT_TOKEN", "bot_token"}, {"SLACK_SIGNING_SECRET", "signing_secret"}],
    "linear" => [{"LINEAR_API_KEY", "api_key"}, {"LINEAR_TEAM_ID", "team_id"}],
    "jira" => [{"JIRA_EMAIL", "email"}, {"JIRA_TOKEN", "token"}, {"JIRA_DOMAIN", "domain"}],
    "notion" => [{"NOTION_TOKEN", "token"}],
    "datadog" => [{"DATADOG_API_KEY", "api_key"}, {"DATADOG_APP_KEY", "app_key"}]
  }

  defp build_provider_env(%{provider: provider, config: config, secrets: secrets}) do
    mappings = Map.get(@provider_env_mapping, provider, [])

    Enum.reduce(mappings, %{}, fn {env_name, config_key}, acc ->
      value = secrets[config_key] || config[config_key]
      if is_binary(value) && value != "" do
        Map.put(acc, env_name, value)
      else
        acc
      end
    end)
  end

  defp build_provider_env(_), do: %{}

  defp persist_activity_event(agent, event_type, message, metadata) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ActivityEvent{}
    |> ActivityEvent.changeset(%{
      event_type: event_type,
      message: message,
      metadata: metadata,
      level: if(String.contains?(event_type, "failed"), do: "error", else: "info"),
      workspace_id: agent.workspace_id,
      agent_id: agent.id
    })
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Repo.insert()

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.activity_topic(),
      %{
        event: event_type,
        agent_id: agent.id,
        agent_name: agent.name,
        message: message,
        workspace_id: agent.workspace_id,
        metadata: metadata,
        created_at: now
      }
    )
  end
end
