defmodule Bizforge.Headless.Notifier do
  @moduledoc """
  Fires HTTP webhooks on key headless runtime events.

  Events include agent state changes, heartbeat completions/failures,
  budget threshold breaches, and watchdog recoveries.

  Webhooks are configured via `.bizforge/webhooks.json` or the
  `BIZFORGE_WEBHOOK_URL` environment variable.
  """
  use GenServer
  require Logger

  @retry_delays [1_000, 5_000, 15_000]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def notify(event, payload) when is_binary(event) and is_map(payload) do
    GenServer.cast(__MODULE__, {:notify, event, payload})
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(_opts) do
    webhooks = load_webhook_config()
    Logger.info("[Headless.Notifier] Loaded #{length(webhooks)} webhook target(s)")
    {:ok, %{webhooks: webhooks}}
  end

  @impl true
  def handle_cast({:notify, event, payload}, state) do
    body = %{
      event: event,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      payload: payload
    }

    Enum.each(state.webhooks, fn webhook ->
      Task.start(fn -> deliver(webhook, body, 0) end)
    end)

    {:noreply, state}
  end

  defp deliver(webhook, body, attempt) do
    encoded = Jason.encode!(body)

    headers = [
      {"content-type", "application/json"},
      {"user-agent", "BizForge-Headless/1.0"},
      {"x-bizforge-event", body.event}
    ]

    headers =
      case Map.get(webhook, :secret) do
        nil ->
          headers

        secret ->
          signature =
            :crypto.mac(:hmac, :sha256, secret, encoded) |> Base.encode16(case: :lower)

          [{"x-bizforge-signature", "sha256=#{signature}"} | headers]
      end

    case :httpc.request(:post, {to_charlist(webhook.url), headers, ~c"application/json", encoded}, [{:timeout, 10_000}], []) do
      {:ok, {{_, status, _}, _, _}} when status >= 200 and status < 300 ->
        Logger.debug("[Headless.Notifier] Delivered #{body.event} to #{webhook.url} (#{status})")

      {:ok, {{_, status, _}, _, _}} ->
        Logger.warning(
          "[Headless.Notifier] Webhook #{webhook.url} returned #{status} for #{body.event}"
        )

        maybe_retry(webhook, body, attempt)

      {:error, reason} ->
        Logger.warning(
          "[Headless.Notifier] Webhook #{webhook.url} failed: #{inspect(reason)}"
        )

        maybe_retry(webhook, body, attempt)
    end
  end

  defp maybe_retry(webhook, body, attempt) when attempt < length(@retry_delays) do
    delay = Enum.at(@retry_delays, attempt)
    Logger.info("[Headless.Notifier] Retrying in #{delay}ms (attempt #{attempt + 1})")
    Process.sleep(delay)
    deliver(webhook, body, attempt + 1)
  end

  defp maybe_retry(webhook, body, _attempt) do
    Logger.error(
      "[Headless.Notifier] Exhausted retries for #{body.event} to #{webhook.url}"
    )
  end

  defp load_webhook_config do
    env_url = System.get_env("BIZFORGE_WEBHOOK_URL")

    env_webhook =
      if env_url !== nil do
        [%{url: env_url, secret: System.get_env("BIZFORGE_WEBHOOK_SECRET")}]
      else
        []
      end

    file_webhooks =
      case File.read(Path.expand(".bizforge/webhooks.json")) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, list} when is_list(list) ->
              Enum.map(list, fn w ->
                %{
                  url: Map.get(w, "url"),
                  secret: Map.get(w, "secret")
                }
              end)
              |> Enum.filter(fn w -> w.url !== nil end)

            _ ->
              []
          end

        {:error, _} ->
          []
      end

    env_webhook ++ file_webhooks
  end
end
