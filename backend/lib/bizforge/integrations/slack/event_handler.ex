defmodule Bizforge.Integrations.Slack.EventHandler do
  @moduledoc """
  Processes inbound Slack events and routes them to agents or the inbox.

  Supported event types:
    - `message` — channel messages mentioning the bot
    - `app_mention` — explicit @mentions of the bot
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{SlackInstallation, Agent, Session, SessionEvent}
  alias Bizforge.Notifications.Dispatcher
  import Ecto.Query

  @doc """
  Handle a Slack event callback. Dispatches based on event type.
  """
  def handle_event(%{"type" => "app_mention"} = event, team_id) do
    handle_message_event(event, team_id)
  end

  def handle_event(%{"type" => "message", "subtype" => _subtype}, _team_id) do
    :ignored
  end

  def handle_event(%{"type" => "message"} = event, team_id) do
    handle_message_event(event, team_id)
  end

  def handle_event(%{"type" => type}, _team_id) do
    Logger.debug("[Slack.EventHandler] Ignoring event type: #{type}")
    :ignored
  end

  defp handle_message_event(event, team_id) do
    channel = event["channel"]
    text = event["text"] || ""
    user = event["user"]
    thread_ts = event["thread_ts"] || event["ts"]
    ts = event["ts"]

    installation = find_installation(team_id)

    case installation do
      nil ->
        Logger.warning("[Slack.EventHandler] No installation for team #{team_id}")
        {:error, :no_installation}

      inst ->
        agent = resolve_target_agent(inst, channel)
        workspace_id = inst.workspace_id

        reply_to = %{
          "channel" => channel,
          "thread_ts" => thread_ts,
          "ts" => ts,
          "team_id" => team_id,
          "user" => user
        }

        {:ok, notification} =
          Dispatcher.notify_integration_message(%{
            workspace_id: workspace_id,
            title: "Slack: message from #{user_display(user)} in ##{channel}",
            body: strip_bot_mention(text),
            source_channel: "slack",
            reply_to: reply_to,
            metadata: %{
              "slack_channel" => channel,
              "slack_user" => user,
              "slack_ts" => ts
            }
          })

        if agent do
          route_to_agent(agent, strip_bot_mention(text), workspace_id, reply_to)
        end

        {:ok, notification}
    end
  end

  defp find_installation(team_id) when is_binary(team_id) do
    Repo.one(
      from s in SlackInstallation,
        where: s.team_id == ^team_id and s.active == true,
        limit: 1
    )
  end

  defp find_installation(_), do: nil

  defp resolve_target_agent(%SlackInstallation{} = inst, channel) do
    agent_id =
      case inst.channel_mappings do
        %{^channel => mapped_id} -> mapped_id
        mappings when is_map(mappings) -> Map.get(mappings, channel, inst.default_agent_id)
        _ -> inst.default_agent_id
      end

    if agent_id do
      Repo.get(Agent, agent_id)
    else
      nil
    end
  end

  defp route_to_agent(agent, message, workspace_id, reply_to) do
    session = find_or_create_session(agent, workspace_id, reply_to)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %SessionEvent{
      session_id: session.id,
      event_type: "user_message",
      data: %{
        "body" => message,
        "source" => "slack",
        "reply_to" => reply_to
      },
      tokens: 0,
      inserted_at: now
    }
    |> Repo.insert!()

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.session_topic(session.id),
      %{event: "user_message", body: message, session_id: session.id, source: "slack"}
    )

    Task.Supervisor.start_child(Bizforge.HeartbeatRunner, fn ->
      execute_and_reply(session, agent, message, reply_to)
    end)

    {:ok, session.id}
  end

  defp find_or_create_session(agent, workspace_id, reply_to) do
    thread_ts = reply_to["thread_ts"]

    existing =
      if thread_ts do
        Repo.one(
          from s in Session,
            where:
              s.agent_id == ^agent.id and
                s.status == "active" and
                fragment("?->>'slack_thread_ts' = ?", s.context, ^thread_ts),
            order_by: [desc: s.started_at],
            limit: 1
        )
      else
        nil
      end

    case existing do
      %Session{} = session ->
        session

      nil ->
        %Session{}
        |> Session.changeset(%{
          agent_id: agent.id,
          workspace_id: workspace_id,
          model: agent.model,
          status: "active",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          context: Jason.encode!(%{
            "source" => "slack",
            "slack_thread_ts" => thread_ts,
            "reply_to" => reply_to
          })
        })
        |> Repo.insert!()
    end
  end

  defp execute_and_reply(_session, agent, message, reply_to) do
    adapter_type = agent.adapter || "osa"

    case Bizforge.Adapter.resolve(adapter_type) do
      {:ok, adapter_mod} ->
        config = %{
          "url" => (agent.config || %{})["url"],
          "model" => agent.model || "claude-sonnet-4-6"
        }

        case adapter_mod.start(config) do
          {:ok, osa_session} ->
            response_parts =
              try do
                adapter_mod.send_message(osa_session, message)
                |> Enum.reduce([], fn raw_event, acc ->
                  event = normalize_adapter_event(raw_event)
                  text = extract_text(event)

                  if text !== "" do
                    [text | acc]
                  else
                    acc
                  end
                end)
              after
                adapter_mod.stop(osa_session)
              end

            full_response = response_parts |> Enum.reverse() |> Enum.join("")

            if full_response !== "" do
              installation =
                Repo.one(
                  from s in SlackInstallation,
                    where:
                      s.workspace_id == ^agent.workspace_id and
                        s.active == true,
                    limit: 1
                )

              if installation do
                Bizforge.Integrations.Slack.Client.send_reply(
                  installation.bot_token,
                  reply_to,
                  full_response
                )
              end
            end

          {:error, reason} ->
            Logger.error("[Slack.EventHandler] Adapter start failed: #{inspect(reason)}")
        end

      {:error, _} ->
        Logger.error("[Slack.EventHandler] Unknown adapter: #{adapter_type}")
    end
  end

  defp normalize_adapter_event(event) when is_map(event) do
    cond do
      is_binary(Map.get(event, "event_type")) -> event
      is_binary(Map.get(event, :event_type)) ->
        %{"event_type" => to_string(event[:event_type]), "data" => Map.get(event, :data, %{})}
      true ->
        %{"event_type" => "run.output", "data" => event}
    end
  end

  defp extract_text(%{"data" => data}) when is_map(data) do
    cond do
      is_binary(data["delta"]) -> data["delta"]
      is_map(data["delta"]) && is_binary(data["delta"]["text"]) -> data["delta"]["text"]
      is_binary(data["text"]) -> data["text"]
      is_binary(data["content"]) -> data["content"]
      is_binary(data["body"]) -> data["body"]
      true -> ""
    end
  end

  defp extract_text(_), do: ""

  defp strip_bot_mention(text) do
    Regex.replace(~r/<@[A-Z0-9]+>\s*/, text, "")
    |> String.trim()
  end

  defp user_display(nil), do: "unknown"
  defp user_display(user_id), do: user_id
end
