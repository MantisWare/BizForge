defmodule BizforgeWeb.SessionController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Session, SessionEvent, Agent}
  alias Bizforge.Sessions.{Compactor, Chain}
  import Ecto.Query

  def index(conn, params) do
    limit = min(String.to_integer(params["limit"] || "50"), 100)
    offset = String.to_integer(params["offset"] || "0")
    agent_id = params["agent_id"]
    status = params["status"]

    message_count_subquery =
      from e in SessionEvent,
        group_by: e.session_id,
        select: %{session_id: e.session_id, count: count(e.id)}

    query =
      from s in Session,
        join: a in Agent,
        on: s.agent_id == a.id,
        left_join: mc in subquery(message_count_subquery),
        on: mc.session_id == s.id,
        order_by: [desc: s.started_at],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: s.id,
          agent_id: s.agent_id,
          agent_name: a.name,
          title: a.name,
          model: s.model,
          status: s.status,
          message_count: coalesce(mc.count, 0),
          token_usage: %{
            input: s.tokens_input,
            output: s.tokens_output,
            cache_read: s.tokens_cache,
            cache_write: 0
          },
          tokens_input: s.tokens_input,
          tokens_output: s.tokens_output,
          tokens_cache: s.tokens_cache,
          cost_cents: s.cost_cents,
          started_at: s.started_at,
          completed_at: s.completed_at,
          created_at: s.started_at
        }

    query = if agent_id, do: where(query, [s], s.agent_id == ^agent_id), else: query
    query = if status, do: where(query, [s], s.status == ^status), else: query

    count_query = from(s in Session)

    count_query =
      if agent_id, do: where(count_query, [s], s.agent_id == ^agent_id), else: count_query

    count_query = if status, do: where(count_query, [s], s.status == ^status), else: count_query

    sessions = Repo.all(query)
    total = Repo.aggregate(count_query, :count)
    json(conn, %{sessions: sessions, total: total})
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Session, id) |> Repo.preload(:agent) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      session ->
        message_count =
          Repo.aggregate(
            from(e in SessionEvent, where: e.session_id == ^session.id),
            :count
          )

        json(conn, %{
          session: %{
            id: session.id,
            agent_id: session.agent_id,
            agent_name: session.agent.name,
            title: session.agent.name,
            model: session.model,
            status: session.status,
            message_count: message_count,
            token_usage: %{
              input: session.tokens_input,
              output: session.tokens_output,
              cache_read: session.tokens_cache,
              cache_write: 0
            },
            tokens_input: session.tokens_input,
            tokens_output: session.tokens_output,
            tokens_cache: session.tokens_cache,
            cost_cents: session.cost_cents,
            workspace_path: session.workspace_path,
            workspace_branch: session.workspace_branch,
            started_at: session.started_at,
            completed_at: session.completed_at,
            created_at: session.started_at,
            # Continuity fields
            context_summary: session.context_summary,
            handoff_notes: session.handoff_notes,
            continuation_data: session.continuation_data,
            compaction_reason: session.compaction_reason,
            parent_session_id: session.parent_session_id,
            sequence_number: session.sequence_number
          }
        })
    end
  end

  def chain(conn, %{"id" => id}) do
    case Repo.get(Session, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      session ->
        # Load the full chain for this agent (scoped to same issue if present)
        opts = if session.issue_id, do: [issue_id: session.issue_id], else: []
        sessions = Chain.get_chain(session.agent_id, opts)
        total_tokens = Chain.chain_token_usage(session)

        json(conn, %{
          chain: Chain.serialize_chain(sessions),
          total_tokens: total_tokens,
          session_count: length(sessions)
        })
    end
  end

  def compact(conn, %{"id" => id}) do
    case Repo.get(Session, id)
         |> then(fn s -> if s, do: Repo.preload(s, :agent), else: nil end) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      session ->
        case Compactor.compact(session, "manual") do
          {:ok, compacted} ->
            json(conn, %{
              session: %{
                id: compacted.id,
                context_summary: compacted.context_summary,
                handoff_notes: compacted.handoff_notes,
                continuation_data: compacted.continuation_data,
                compaction_reason: compacted.compaction_reason
              }
            })

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> json(%{error: "compaction_failed", details: format_errors(changeset)})
        end
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def delete(conn, %{"id" => id}) do
    case Repo.get(Session, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      session ->
        case session
             |> Ecto.Changeset.change(
               status: "cancelled",
               completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
          {:ok, updated} ->
            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.session_topic(id),
              %{event: "run.cancelled", session_id: id}
            )

            json(conn, %{session: %{id: updated.id, status: updated.status}})

          {:error, _changeset} ->
            conn |> put_status(500) |> json(%{error: "update_failed"})
        end
    end
  end

  def transcript(conn, %{"session_id" => session_id}) do
    events =
      Repo.all(
        from e in SessionEvent,
          where: e.session_id == ^session_id,
          order_by: [asc: e.id]
      )

    messages =
      Enum.map(events, fn e ->
        role =
          case e.event_type do
            t when t in ["run.output", "assistant"] -> "assistant"
            "user_message" -> "user"
            t when t in ["run.tool_call", "run.tool_result"] -> "tool"
            _ -> "system"
          end

        content =
          cond do
            is_map(e.data) and is_binary(e.data["content"]) -> e.data["content"]
            is_map(e.data) and is_binary(e.data["text"]) -> e.data["text"]
            is_map(e.data) and is_binary(e.data["body"]) -> e.data["body"]
            true -> Jason.encode!(e.data)
          end

        %{
          id: e.id,
          session_id: session_id,
          role: role,
          content: sanitize_content(content),
          timestamp: e.inserted_at
        }
      end)

    json(conn, %{messages: messages})
  end

  def create(conn, params) do
    agent_id = params["agent_id"]
    title = params["title"]

    case Repo.get(Agent, agent_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "agent_not_found"})

      agent ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs = %{
          agent_id: agent.id,
          workspace_id: agent.workspace_id,
          model: params["model"] || agent.model,
          status: "active",
          started_at: now
        }

        case %Session{} |> Session.changeset(attrs) |> Repo.insert() do
          {:ok, session} ->
            conn
            |> put_status(201)
            |> json(%{
              id: session.id,
              agent_id: session.agent_id,
              agent_name: agent.name,
              title: title,
              status: session.status,
              started_at: session.started_at,
              created_at: session.started_at
            })

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> json(%{error: "validation_failed", details: format_errors(changeset)})
        end
    end
  end

  def message(conn, %{"session_id" => session_id} = params) do
    body = params["body"] || params["message"] || ""
    model = params["model"]

    case Repo.get(Session, session_id) |> Repo.preload(:agent) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      session ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %SessionEvent{
          session_id: session_id,
          event_type: "user_message",
          data: %{"body" => body},
          tokens: 0,
          inserted_at: now
        }
        |> Repo.insert!()

        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.session_topic(session_id),
          %{event: "user_message", body: body, session_id: session_id}
        )

        agent = session.agent

        if agent do
          Task.Supervisor.start_child(Bizforge.HeartbeatRunner, fn ->
            execute_chat_message(session, agent, body, model)
          end)
        end

        conn |> put_status(202) |> json(%{ok: true, session_id: session_id})
    end
  end

  def stream(conn, %{"session_id" => session_id}) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    Bizforge.EventBus.subscribe(Bizforge.EventBus.session_topic(session_id))

    stream_loop(conn, session_id)
  end

  defp stream_loop(conn, session_id) do
    receive do
      %{event: event_type} = event ->
        data = Jason.encode!(event)

        case Plug.Conn.chunk(conn, "event: #{event_type}\ndata: #{data}\n\n") do
          {:ok, conn} -> stream_loop(conn, session_id)
          {:error, _} -> conn
        end
    after
      30_000 ->
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> stream_loop(conn, session_id)
          {:error, _} -> conn
        end
    end
  end

  defp execute_chat_message(session, agent, message, model_override) do
    adapter_type = agent.adapter || "osa"

    case Bizforge.Adapter.resolve(adapter_type) do
      {:ok, adapter_mod} ->
        base_url = (agent.config || %{})["url"]
        model = model_override || agent.model || "claude-sonnet-4-6"

        config = %{
          "url" => base_url,
          "model" => model
        }

        case adapter_mod.start(config) do
          {:ok, osa_session} ->
            try do
              adapter_mod.send_message(osa_session, message)
              |> Stream.each(fn raw_event ->
                normalized = normalize_event(raw_event)
                event_type = normalized["event_type"] || "run.output"
                data = normalized["data"] || %{}

                %SessionEvent{
                  session_id: session.id,
                  event_type: event_type,
                  data: data,
                  tokens: 0,
                  inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
                }
                |> Repo.insert!()

                for fe_event <- to_frontend_events(event_type, data, session.id, agent.id) do
                  Bizforge.EventBus.broadcast(
                    Bizforge.EventBus.session_topic(session.id),
                    fe_event
                  )
                end
              end)
              |> Stream.run()

              Bizforge.EventBus.broadcast(
                Bizforge.EventBus.session_topic(session.id),
                %{event: "done", session_id: session.id}
              )
            after
              adapter_mod.stop(osa_session)
            end

          {:error, reason} ->
            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.session_topic(session.id),
              %{
                event: "error",
                data: %{"message" => "Adapter start failed: #{inspect(reason)}"},
                session_id: session.id
              }
            )
        end

      {:error, _} ->
        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.session_topic(session.id),
          %{
            event: "error",
            data: %{"message" => "Unknown adapter: #{adapter_type}"},
            session_id: session.id
          }
        )
    end
  end

  defp normalize_event(event) when is_map(event) do
    cond do
      is_binary(Map.get(event, "event_type")) -> event
      is_binary(Map.get(event, :event_type)) ->
        %{
          "event_type" => to_string(Map.get(event, :event_type)),
          "data" => Map.get(event, :data, %{})
        }
      true -> %{"event_type" => "run.output", "data" => event}
    end
  end

  defp to_frontend_events(event_type, data, session_id, agent_id) do
    base = %{session_id: session_id, agent_id: agent_id}

    case event_type do
      t when t in ["content_block_delta", "text_delta", "run.output"] ->
        delta = extract_text_delta(data)
        if delta != "" do
          [Map.merge(base, %{event: "streaming_token", type: "streaming_token", delta: delta})]
        else
          [Map.merge(base, %{event: event_type, data: data})]
        end

      "thinking" ->
        delta = data["thinking"] || data["text"] || ""
        [Map.merge(base, %{event: "thinking_delta", type: "thinking_delta", delta: delta})]

      t when t in ["tool_use", "run.tool_call"] ->
        [Map.merge(base, %{
          event: "tool_call",
          type: "tool_call",
          tool_use_id: data["id"] || data["tool_use_id"],
          tool_name: data["name"] || data["tool_name"],
          input: data["input"] || %{}
        })]

      t when t in ["tool_result", "run.tool_result"] ->
        [Map.merge(base, %{event: "tool_result", type: "tool_result", data: data})]

      "error" ->
        [Map.merge(base, %{event: "error", type: "error", message: data["message"] || "Unknown error"})]

      _ ->
        [Map.merge(base, %{event: event_type, data: data})]
    end
  end

  defp extract_text_delta(data) when is_map(data) do
    cond do
      is_binary(data["delta"]) -> data["delta"]
      is_map(data["delta"]) && is_binary(data["delta"]["text"]) -> data["delta"]["text"]
      is_binary(data["text"]) -> data["text"]
      is_binary(data["content"]) -> data["content"]
      is_binary(data["body"]) -> data["body"]
      true -> ""
    end
  end

  defp extract_text_delta(_), do: ""

  defp sanitize_content(nil), do: ""

  defp sanitize_content(content) when is_binary(content) do
    String.replace(content, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
  end

  defp sanitize_content(other), do: to_string(other)
end
