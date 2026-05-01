defmodule BizforgeWeb.SlackController do
  @moduledoc """
  Handles inbound Slack Events API callbacks and Interactive Message payloads.

  Endpoints:
    - POST /api/v1/slack/events — Events API (URL verification + event dispatch)
    - POST /api/v1/slack/interactive — Interactive message button clicks
  """
  use BizforgeWeb, :controller

  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{SlackInstallation, Approval}
  import Ecto.Query

  @slack_version "v0"
  @timestamp_tolerance 300

  def events(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def events(conn, %{"type" => "event_callback", "event" => event, "team_id" => team_id} = params) do
    case verify_slack_signature(conn, team_id) do
      :ok ->
        Task.Supervisor.start_child(Bizforge.HeartbeatRunner, fn ->
          Bizforge.Integrations.Slack.EventHandler.handle_event(event, team_id)
        end)

        json(conn, %{ok: true})

      {:error, reason} ->
        Logger.warning("[SlackController] Signature verification failed: #{reason}")

        if params["challenge"] do
          json(conn, %{challenge: params["challenge"]})
        else
          conn |> put_status(401) |> json(%{error: "invalid_signature"})
        end
    end
  end

  def events(conn, _params) do
    conn |> put_status(400) |> json(%{error: "unsupported_event_type"})
  end

  def interactive(conn, params) do
    payload_str = params["payload"] || "{}"

    payload =
      case Jason.decode(payload_str) do
        {:ok, decoded} -> decoded
        {:error, _} -> %{}
      end

    case payload do
      %{"type" => "block_actions", "actions" => actions, "team" => %{"id" => team_id}} ->
        case verify_slack_signature(conn, team_id) do
          :ok ->
            handle_block_actions(actions, payload)
            json(conn, %{ok: true})

          {:error, _reason} ->
            conn |> put_status(401) |> json(%{error: "invalid_signature"})
        end

      _ ->
        conn |> put_status(400) |> json(%{error: "unsupported_payload"})
    end
  end

  defp handle_block_actions(actions, payload) do
    Enum.each(actions, fn action ->
      action_id = action["action_id"] || ""
      value = action["value"] || ""

      cond do
        String.starts_with?(action_id, "approve_") ->
          approval_id = String.replace_prefix(action_id, "approve_", "")
          handle_approval_action(approval_id, "approved", payload)

        String.starts_with?(action_id, "reject_") ->
          approval_id = String.replace_prefix(action_id, "reject_", "")
          handle_approval_action(approval_id, "rejected", payload)

        true ->
          Logger.debug("[SlackController] Unhandled action: #{action_id} = #{value}")
      end
    end)
  end

  defp handle_approval_action(approval_id, decision, payload) do
    case Repo.get(Approval, approval_id) do
      nil ->
        Logger.warning("[SlackController] Approval #{approval_id} not found")

      %Approval{status: "pending"} = approval ->
        user_name = get_in(payload, ["user", "name"]) || "slack_user"

        {:ok, updated} =
          approval
          |> Ecto.Changeset.change(
            status: decision,
            decision: decision,
            decision_comment: "#{String.capitalize(decision)} via Slack by #{user_name}"
          )
          |> Repo.update()

        if updated.auto_execute && decision === "approved" do
          case Bizforge.Governance.Executor.execute_approved(updated) do
            {:ok, _result} ->
              Logger.info("[SlackController] Auto-executed approved action #{approval_id}")

            {:error, reason} ->
              Logger.error(
                "[SlackController] Failed to auto-execute #{approval_id}: #{inspect(reason)}"
              )
          end
        end

        Logger.info("[SlackController] Approval #{approval_id} #{decision} via Slack")

      %Approval{status: status} ->
        Logger.info("[SlackController] Approval #{approval_id} already #{status}")
    end
  end

  defp verify_slack_signature(conn, team_id) do
    installation =
      Repo.one(
        from s in SlackInstallation,
          where: s.team_id == ^team_id and s.active == true,
          limit: 1
      )

    case installation do
      nil ->
        :ok

      inst ->
        timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
        signature = get_req_header(conn, "x-slack-signature") |> List.first()
        raw_body = conn.assigns[:raw_body] || ""

        cond do
          timestamp === nil || signature === nil ->
            {:error, :missing_headers}

          abs(System.os_time(:second) - String.to_integer(timestamp)) > @timestamp_tolerance ->
            {:error, :timestamp_expired}

          true ->
            sig_basestring = "#{@slack_version}:#{timestamp}:#{raw_body}"

            expected =
              "#{@slack_version}=" <>
                Base.encode16(
                  :crypto.mac(:hmac, :sha256, inst.signing_secret, sig_basestring),
                  case: :lower
                )

            if Plug.Crypto.secure_compare(signature, expected) do
              :ok
            else
              {:error, :signature_mismatch}
            end
        end
    end
  end
end
