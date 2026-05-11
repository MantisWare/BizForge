defmodule Bizforge.Headless.Notifications.EmailDigest do
  @moduledoc """
  Accumulates headless runtime events and sends periodic email digests.

  Supports three modes:
    - `:hourly` — send a digest every hour
    - `:daily` — send a digest every 24 hours
    - `:on_error` — send immediately only on critical events

  Configure via environment variables:
    - BIZFORGE_EMAIL_FROM
    - BIZFORGE_EMAIL_TO
    - BIZFORGE_SMTP_HOST
    - BIZFORGE_SMTP_PORT (default 587)
    - BIZFORGE_SMTP_USERNAME
    - BIZFORGE_SMTP_PASSWORD
  """
  use GenServer
  require Logger

  @hourly_interval :timer.hours(1)
  @daily_interval :timer.hours(24)

  @critical_events [
    "resource.agent_limit_exceeded",
    "resource.memory_limit_exceeded",
    "resource.token_limit_exceeded",
    "agent.recovery_exhausted"
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_event(event, payload) do
    GenServer.cast(__MODULE__, {:add_event, event, payload})
  catch
    :exit, _ -> :ok
  end

  def configured? do
    config = smtp_config()
    config.host !== nil && config.from !== nil && config.to !== nil
  end

  @impl true
  def init(_opts) do
    config = smtp_config()
    mode = determine_mode()

    if config.host !== nil && config.from !== nil && config.to !== nil do
      Logger.info("[EmailDigest] Configured (mode: #{mode}, to: #{config.to})")
      schedule_digest(mode)
    else
      Logger.info("[EmailDigest] Not configured — email digests disabled")
    end

    {:ok, %{events: [], mode: mode, config: config}}
  end

  @impl true
  def handle_cast({:add_event, event, payload}, state) do
    entry = %{
      event: event,
      payload: payload,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    state = %{state | events: [entry | state.events]}

    if state.mode === :on_error && event in @critical_events do
      send_digest(state)
      {:noreply, %{state | events: []}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:send_digest, state) do
    if state.events !== [] do
      send_digest(state)
      schedule_digest(state.mode)
      {:noreply, %{state | events: []}}
    else
      schedule_digest(state.mode)
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_digest(:hourly), do: Process.send_after(self(), :send_digest, @hourly_interval)
  defp schedule_digest(:daily), do: Process.send_after(self(), :send_digest, @daily_interval)
  defp schedule_digest(:on_error), do: :ok

  defp send_digest(state) do
    config = state.config
    events = Enum.reverse(state.events)

    subject = "[BizForge] Activity Digest — #{length(events)} event(s)"
    body = build_html_body(events)

    case send_email(config, subject, body) do
      :ok ->
        Logger.info("[EmailDigest] Sent digest with #{length(events)} event(s) to #{config.to}")

      {:error, reason} ->
        Logger.warning("[EmailDigest] Failed to send digest: #{inspect(reason)}")
    end
  end

  defp send_email(config, subject, html_body) do
    headers = [
      {"From", config.from},
      {"To", config.to},
      {"Subject", subject},
      {"MIME-Version", "1.0"},
      {"Content-Type", "text/html; charset=UTF-8"}
    ]

    message =
      Enum.map(headers, fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\r\n")
      |> Kernel.<>("\r\n\r\n#{html_body}")

    relay_opts = [
      relay: config.host,
      port: config.port,
      username: config.username,
      password: config.password,
      tls: :always,
      auth: :always
    ]

    if Code.ensure_loaded?(:gen_smtp_client) do
      try do
        case :gen_smtp_client.send_blocking(
               {config.from, [config.to], message},
               relay_opts
             ) do
          receipt when is_binary(receipt) -> :ok
          {:error, reason} -> {:error, reason}
        end
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, reason -> {:error, reason}
      end
    else
      Logger.warning("[EmailDigest] gen_smtp not available — add {:gen_smtp, \"~> 1.2\"} to deps")
      {:error, :gen_smtp_not_available}
    end
  end

  defp build_html_body(events) do
    rows =
      Enum.map(events, fn entry ->
        payload_str =
          entry.payload
          |> Enum.map(fn {k, v} -> "<strong>#{k}:</strong> #{inspect(v)}" end)
          |> Enum.join("<br/>")

        """
        <tr>
          <td style="padding:8px;border:1px solid #e5e7eb;font-family:monospace;font-size:12px;">#{entry.timestamp}</td>
          <td style="padding:8px;border:1px solid #e5e7eb;"><code>#{entry.event}</code></td>
          <td style="padding:8px;border:1px solid #e5e7eb;font-size:12px;">#{payload_str}</td>
        </tr>
        """
      end)
      |> Enum.join("")

    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"></head>
    <body style="font-family:system-ui,-apple-system,sans-serif;padding:20px;background:#f9fafb;">
      <h2 style="color:#111827;">BizForge Headless — Activity Digest</h2>
      <p style="color:#6b7280;">#{length(events)} event(s) recorded</p>
      <table style="border-collapse:collapse;width:100%;margin-top:16px;">
        <thead>
          <tr style="background:#f3f4f6;">
            <th style="padding:8px;border:1px solid #e5e7eb;text-align:left;">Time</th>
            <th style="padding:8px;border:1px solid #e5e7eb;text-align:left;">Event</th>
            <th style="padding:8px;border:1px solid #e5e7eb;text-align:left;">Details</th>
          </tr>
        </thead>
        <tbody>#{rows}</tbody>
      </table>
      <p style="color:#9ca3af;font-size:12px;margin-top:20px;">
        Generated by BizForge Headless Runtime
      </p>
    </body>
    </html>
    """
  end

  defp smtp_config do
    config = Application.get_env(:bizforge, :headless, [])

    %{
      host: Keyword.get(config, :smtp_host),
      port: Keyword.get(config, :smtp_port, 587),
      username: Keyword.get(config, :smtp_username),
      password: Keyword.get(config, :smtp_password),
      from: Keyword.get(config, :email_from),
      to: Keyword.get(config, :email_to)
    }
  end

  defp determine_mode do
    case System.get_env("BIZFORGE_EMAIL_DIGEST_MODE") do
      "daily" -> :daily
      "on_error" -> :on_error
      _ -> :hourly
    end
  end
end
