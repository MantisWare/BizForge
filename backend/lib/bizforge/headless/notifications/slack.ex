defmodule Bizforge.Headless.Notifications.Slack do
  @moduledoc """
  Slack notification channel for headless mode alerts.

  Sends structured Block Kit messages to a configured Slack webhook URL.
  Supports all event types from the Notifier system.

  Configure via `BIZFORGE_SLACK_WEBHOOK_URL` environment variable.
  """
  require Logger

  @severity_colors %{
    "critical" => "#dc2626",
    "warning" => "#f59e0b",
    "info" => "#3b82f6",
    "success" => "#10b981"
  }

  def configured? do
    url() !== nil
  end

  def send(event, payload) when is_binary(event) and is_map(payload) do
    case url() do
      nil ->
        {:error, :not_configured}

      webhook_url ->
        body = build_slack_message(event, payload)

        case Req.post(webhook_url, json: body, receive_timeout: 10_000) do
          {:ok, %Req.Response{status: status}} when status >= 200 and status < 300 ->
            Logger.debug("[Slack] Delivered #{event}")
            :ok

          {:ok, %Req.Response{status: status, body: resp_body}} ->
            Logger.warning("[Slack] Webhook returned #{status}: #{inspect(resp_body)}")
            {:error, {:http_error, status}}

          {:error, reason} ->
            Logger.warning("[Slack] Delivery failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp url do
    Application.get_env(:bizforge, :headless, [])
    |> Keyword.get(:slack_webhook_url)
  end

  defp build_slack_message(event, payload) do
    severity = infer_severity(event)
    color = Map.get(@severity_colors, severity, "#6b7280")

    header_text = format_event_title(event)
    detail_lines = format_payload(payload)

    %{
      blocks: [
        %{
          type: "header",
          text: %{type: "plain_text", text: header_text, emoji: true}
        },
        %{
          type: "section",
          text: %{type: "mrkdwn", text: detail_lines}
        },
        %{
          type: "context",
          elements: [
            %{
              type: "mrkdwn",
              text: "BizForge Headless | #{DateTime.utc_now() |> DateTime.to_iso8601()}"
            }
          ]
        }
      ],
      attachments: [
        %{color: color, blocks: []}
      ]
    }
  end

  defp infer_severity(event) do
    cond do
      String.contains?(event, "exceeded") -> "critical"
      String.contains?(event, "error") -> "critical"
      String.contains?(event, "exhausted") -> "critical"
      String.contains?(event, "warning") -> "warning"
      String.contains?(event, "stuck") -> "warning"
      String.contains?(event, "recovery") -> "warning"
      String.contains?(event, "complete") -> "success"
      String.contains?(event, "boot") -> "success"
      true -> "info"
    end
  end

  defp format_event_title(event) do
    event
    |> String.replace(".", " › ")
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_payload(payload) when map_size(payload) === 0, do: "_No additional details_"

  defp format_payload(payload) do
    payload
    |> Enum.map(fn {k, v} -> "*#{k}:* #{format_value(v)}" end)
    |> Enum.join("\n")
  end

  defp format_value(v) when is_map(v), do: "`#{Jason.encode!(v)}`"
  defp format_value(v) when is_list(v), do: Enum.join(v, ", ")
  defp format_value(v), do: to_string(v)
end
