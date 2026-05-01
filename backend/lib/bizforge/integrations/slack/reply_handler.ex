defmodule Bizforge.Integrations.Slack.ReplyHandler do
  @moduledoc """
  Subscribes to session events for Slack-initiated sessions and sends
  agent responses back to the originating Slack thread.

  This module is designed to be started as a Task for a specific session
  rather than as a persistent GenServer — the EventHandler spawns it
  when routing a Slack message to an agent.
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.SlackInstallation
  import Ecto.Query

  @doc """
  Monitor a session and relay agent responses back to Slack.

  Should be called with the session_id, workspace_id, and reply_to metadata.
  Blocks until the session is complete (receives a "done" event) or times out.
  """
  def monitor_session(session_id, workspace_id, reply_to, opts \\ []) do
    timeout = opts[:timeout] || 300_000

    Bizforge.EventBus.subscribe(Bizforge.EventBus.session_topic(session_id))

    bot_token = resolve_bot_token(workspace_id)

    if bot_token === nil do
      Logger.warning("[Slack.ReplyHandler] No bot token for workspace #{workspace_id}")
      :ok
    else
      collect_and_reply(bot_token, reply_to, "", timeout)
    end
  end

  defp collect_and_reply(bot_token, reply_to, buffer, timeout) do
    receive do
      %{event: "streaming_token", delta: delta} ->
        collect_and_reply(bot_token, reply_to, buffer <> delta, timeout)

      %{event: "done"} ->
        if buffer !== "" do
          Bizforge.Integrations.Slack.Client.send_reply(bot_token, reply_to, buffer)
        end

        :ok

      %{event: "error", message: error_msg} ->
        error_text = "Agent encountered an error: #{error_msg}"
        Bizforge.Integrations.Slack.Client.send_reply(bot_token, reply_to, error_text)
        :ok

      _other ->
        collect_and_reply(bot_token, reply_to, buffer, timeout)
    after
      timeout ->
        if buffer !== "" do
          Bizforge.Integrations.Slack.Client.send_reply(bot_token, reply_to, buffer)
        end

        :timeout
    end
  end

  defp resolve_bot_token(workspace_id) do
    case Repo.one(
           from s in SlackInstallation,
             where: s.workspace_id == ^workspace_id and s.active == true,
             limit: 1
         ) do
      nil -> nil
      inst -> inst.bot_token
    end
  end
end
