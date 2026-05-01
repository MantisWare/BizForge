defmodule BizforgeWeb.InboxController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Notification, Agent}
  import Ecto.Query

  def index(conn, params) do
    workspace_id = params["workspace_id"]
    unread_only = params["unread"] == "true"
    limit = min(String.to_integer(params["limit"] || "50"), 200)
    offset = String.to_integer(params["offset"] || "0")

    query =
      from n in Notification,
        where: is_nil(n.dismissed_at),
        order_by: [desc: n.inserted_at],
        limit: ^limit,
        offset: ^offset

    query = if workspace_id, do: where(query, [n], n.workspace_id == ^workspace_id), else: query

    query =
      if unread_only do
        where(query, [n], is_nil(n.read_at))
      else
        query
      end

    notifications = Repo.all(query)

    total_query = from(n in Notification, where: is_nil(n.dismissed_at))
    total_query = if workspace_id, do: where(total_query, [n], n.workspace_id == ^workspace_id), else: total_query
    total = Repo.aggregate(total_query, :count)

    unread_query = from(n in Notification, where: is_nil(n.dismissed_at) and is_nil(n.read_at))
    unread_query = if workspace_id, do: where(unread_query, [n], n.workspace_id == ^workspace_id), else: unread_query
    unread_count = Repo.aggregate(unread_query, :count)

    agent_ids =
      notifications
      |> Enum.map(& &1.sender_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    agent_names =
      if agent_ids !== [] do
        Repo.all(from a in Agent, where: a.id in ^agent_ids, select: {a.id, a.name})
        |> Map.new()
      else
        %{}
      end

    json(conn, %{
      items: Enum.map(notifications, &serialize(&1, agent_names)),
      total: total,
      unread_count: unread_count
    })
  end

  def read(conn, %{"id" => id}) do
    case Repo.get(Notification, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      notification ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        case notification
             |> Ecto.Changeset.change(read_at: now)
             |> Repo.update() do
          {:ok, updated} ->
            json(conn, %{item: serialize(updated, %{})})

          {:error, _changeset} ->
            conn |> put_status(500) |> json(%{error: "update_failed"})
        end
    end
  end

  def read_all(conn, params) do
    workspace_id = params["workspace_id"]
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query = from(n in Notification, where: is_nil(n.read_at) and is_nil(n.dismissed_at))
    query = if workspace_id, do: where(query, [n], n.workspace_id == ^workspace_id), else: query

    {count, _} = Repo.update_all(query, set: [read_at: now])

    json(conn, %{ok: true, updated: count})
  end

  def perform_action(conn, %{"id" => id} = params) do
    action_type = params["action"] || params["action_id"] || "acknowledge"

    case Repo.get(Notification, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      notification ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        updated_metadata =
          (notification.metadata || %{})
          |> Map.put("action", action_type)
          |> Map.put("actioned_at", DateTime.to_iso8601(now))

        case notification
             |> Ecto.Changeset.change(read_at: now, metadata: updated_metadata)
             |> Repo.update() do
          {:ok, updated} ->
            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.activity_topic(),
              %{event: "inbox.actioned", message_id: id, action: action_type}
            )

            json(conn, %{ok: true, item: serialize(updated, %{}), action: action_type})

          {:error, _changeset} ->
            conn |> put_status(500) |> json(%{error: "update_failed"})
        end
    end
  end

  def stream(conn, params) do
    workspace_id = params["workspace_id"]

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    if workspace_id do
      Bizforge.EventBus.subscribe(Bizforge.EventBus.notifications_topic(workspace_id))
    end

    inbox_stream_loop(conn)
  end

  defp inbox_stream_loop(conn) do
    receive do
      %{event: "notification.created", data: data} ->
        payload = Jason.encode!(%{event: "notification.created", data: data})

        case Plug.Conn.chunk(conn, "event: notification.created\ndata: #{payload}\n\n") do
          {:ok, conn} -> inbox_stream_loop(conn)
          {:error, _} -> conn
        end

      _other ->
        inbox_stream_loop(conn)
    after
      30_000 ->
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> inbox_stream_loop(conn)
          {:error, _} -> conn
        end
    end
  end

  def reply(conn, %{"id" => id} = params) do
    body = params["body"] || ""

    case Repo.get(Notification, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      %Notification{source_channel: nil} ->
        conn |> put_status(422) |> json(%{error: "no_reply_channel"})

      %Notification{source_channel: "slack"} = notification ->
        reply_to = notification.reply_to || %{}
        bot_token = resolve_slack_bot_token(notification.workspace_id)

        case bot_token do
          nil ->
            conn |> put_status(422) |> json(%{error: "slack_not_configured"})

          token ->
            case Bizforge.Integrations.Slack.Client.send_reply(token, reply_to, body) do
              :ok ->
                json(conn, %{ok: true, channel: "slack"})

              {:error, reason} ->
                conn |> put_status(502) |> json(%{error: "slack_send_failed", reason: inspect(reason)})
            end
        end

      %Notification{source_channel: channel} ->
        conn |> put_status(422) |> json(%{error: "unsupported_channel", channel: channel})
    end
  end

  defp resolve_slack_bot_token(workspace_id) do
    case workspace_id do
      nil ->
        nil

      wid ->
        case Repo.one(
               from s in Bizforge.Schemas.SlackInstallation,
                 where: s.workspace_id == ^wid and s.active == true,
                 limit: 1
             ) do
          nil -> nil
          installation -> installation.bot_token
        end
    end
  end

  defp serialize(%Notification{} = n, agent_names) do
    status =
      cond do
        n.dismissed_at !== nil -> "dismissed"
        get_in(n.metadata || %{}, ["action"]) !== nil -> "actioned"
        n.read_at !== nil -> "read"
        true -> "unread"
      end

    agent_name =
      case n.sender_id do
        nil -> nil
        id -> Map.get(agent_names, id, id)
      end

    actions = build_actions(n)

    %{
      id: n.id,
      type: category_to_inbox_type(n.category),
      status: status,
      title: n.title,
      body: n.body || "",
      source_agent: agent_name,
      source_entity_type: n.sender_type,
      source_entity_id: n.sender_id,
      source_channel: n.source_channel,
      reply_to: n.reply_to,
      actions: actions,
      action_url: n.action_url,
      action_label: n.action_label,
      category: n.category,
      severity: n.severity,
      workspace_id: n.workspace_id,
      metadata: n.metadata,
      created_at: n.inserted_at,
      inserted_at: n.inserted_at,
      read: n.read_at !== nil
    }
  end

  defp category_to_inbox_type("task"), do: "report"
  defp category_to_inbox_type("approval"), do: "approval"
  defp category_to_inbox_type("alert"), do: "alert"
  defp category_to_inbox_type("mention"), do: "mention"
  defp category_to_inbox_type("system"), do: "alert"
  defp category_to_inbox_type("budget"), do: "budget_warning"
  defp category_to_inbox_type("workflow"), do: "report"
  defp category_to_inbox_type("message"), do: "message"
  defp category_to_inbox_type("integration"), do: "integration"
  defp category_to_inbox_type(_), do: "alert"

  defp build_actions(%Notification{category: "approval"} = n) do
    approval_id = get_in(n.metadata || %{}, ["approval_id"])

    base = [
      %{id: "approve", label: "Approve", type: "approve"},
      %{id: "reject", label: "Reject", type: "reject"}
    ]

    if approval_id do
      base ++ [%{id: "nav", label: "Review", type: "navigate", payload: %{url: n.action_url || "/approvals"}}]
    else
      base
    end
  end

  defp build_actions(%Notification{action_url: url, action_label: label})
       when is_binary(url) and is_binary(label) do
    [%{id: "nav", label: label, type: "navigate", payload: %{url: url}}]
  end

  defp build_actions(_notification) do
    [%{id: "ack", label: "Acknowledge", type: "acknowledge"}]
  end
end
