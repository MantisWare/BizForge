defmodule Bizforge.Integrations.Slack.Client do
  @moduledoc """
  Slack Web API client using Req.

  Wraps `chat.postMessage` and related endpoints for sending messages
  back to Slack channels and threads.
  """
  require Logger

  @base_url "https://slack.com/api"

  @doc """
  Post a message to a Slack channel. Optionally reply in a thread.
  """
  def send_message(bot_token, channel, text, opts \\ []) do
    thread_ts = opts[:thread_ts]

    body =
      %{channel: channel, text: text}
      |> maybe_put(:thread_ts, thread_ts)
      |> maybe_put(:unfurl_links, false)

    case Req.post("#{@base_url}/chat.postMessage",
           json: body,
           headers: [{"authorization", "Bearer #{bot_token}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = resp}} ->
        Logger.debug("[Slack.Client] Message sent to #{channel}")
        {:ok, resp}

      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.warning("[Slack.Client] API error: #{error}")
        {:error, {:slack_api, error}}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[Slack.Client] HTTP #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("[Slack.Client] Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Reply to a Slack thread using reply_to metadata from a notification.

  `reply_to` is expected to have "channel" and "thread_ts" keys.
  """
  def send_reply(bot_token, reply_to, text) when is_map(reply_to) do
    channel = reply_to["channel"]
    thread_ts = reply_to["thread_ts"]

    case {channel, thread_ts} do
      {nil, _} ->
        Logger.warning("[Slack.Client] Missing channel in reply_to")
        {:error, :missing_channel}

      {_, nil} ->
        send_message(bot_token, channel, text)
        :ok

      {ch, ts} ->
        case send_message(bot_token, ch, text, thread_ts: ts) do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  @doc """
  Send a Block Kit message with interactive buttons (for approvals).
  """
  def send_approval_message(bot_token, channel, approval) do
    blocks = [
      %{
        type: "header",
        text: %{type: "plain_text", text: "Approval Required", emoji: true}
      },
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: "*#{approval.title}*\n#{approval.description || ""}"
        }
      },
      %{
        type: "actions",
        elements: [
          %{
            type: "button",
            text: %{type: "plain_text", text: "Approve", emoji: true},
            style: "primary",
            action_id: "approve_#{approval.id}",
            value: approval.id
          },
          %{
            type: "button",
            text: %{type: "plain_text", text: "Reject", emoji: true},
            style: "danger",
            action_id: "reject_#{approval.id}",
            value: approval.id
          }
        ]
      },
      %{
        type: "context",
        elements: [
          %{
            type: "mrkdwn",
            text:
              "BizForge | #{approval.action_type || "action"} | #{DateTime.utc_now() |> DateTime.to_iso8601()}"
          }
        ]
      }
    ]

    body = %{
      channel: channel,
      text: "Approval required: #{approval.title}",
      blocks: blocks
    }

    case Req.post("#{@base_url}/chat.postMessage",
           json: body,
           headers: [{"authorization", "Bearer #{bot_token}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true}}} ->
        Logger.debug("[Slack.Client] Approval message sent for #{approval.id}")
        :ok

      {:ok, %Req.Response{body: %{"error" => error}}} ->
        Logger.warning("[Slack.Client] Approval message failed: #{error}")
        {:error, {:slack_api, error}}

      {:error, reason} ->
        Logger.warning("[Slack.Client] Approval request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
