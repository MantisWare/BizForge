defmodule Bizforge.Governance.HeadlessResolver do
  @moduledoc """
  Resolves governance gates automatically in headless mode.

  When running headlessly, governance approvals that would normally require
  UI interaction can be handled in one of two ways based on workspace config:

  1. **Auto-approve**: If `headless_auto_approve: true` is set in the workspace
     governance config, pending approvals are automatically approved.

  2. **Queue and notify**: If auto-approve is disabled, the resolver leaves
     the approval pending but fires notifications via webhooks/Slack/email
     so an external operator can approve via API.

  This GenServer subscribes to PubSub governance events and processes them
  on a periodic sweep of pending approvals.
  """
  use GenServer
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.Approval
  import Ecto.Query

  @sweep_interval :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Bizforge.PubSub, "governance:approvals")
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{auto_approved_count: 0, notified_ids: MapSet.new()}}
  end

  @impl true
  def handle_info(:sweep, state) do
    state = sweep_pending_approvals(state)
    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  def handle_info({:approval_created, approval_id}, state) do
    state = handle_new_approval(approval_id, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp sweep_pending_approvals(state) do
    pending =
      Repo.all(
        from a in Approval,
          where: a.status == "pending",
          order_by: [asc: a.inserted_at]
      )

    Enum.reduce(pending, state, fn approval, acc ->
      resolve_approval(approval, acc)
    end)
  end

  defp handle_new_approval(approval_id, state) do
    case Repo.get(Approval, approval_id) do
      nil -> state
      %Approval{status: "pending"} = approval -> resolve_approval(approval, state)
      _ -> state
    end
  end

  defp resolve_approval(approval, state) do
    config = headless_governance_config(approval.workspace_id)

    cond do
      auto_approve_enabled?(config) ->
        auto_approve(approval)
        %{state | auto_approved_count: state.auto_approved_count + 1}

      MapSet.member?(state.notified_ids, approval.id) ->
        state

      true ->
        notify_pending(approval)
        %{state | notified_ids: MapSet.put(state.notified_ids, approval.id)}
    end
  end

  defp auto_approve(approval) do
    Logger.info(
      "[Governance.HeadlessResolver] Auto-approving: #{approval.action_type} (#{approval.id})"
    )

    approval
    |> Ecto.Changeset.change(%{
      status: "approved",
      resolved_by: "headless_auto_resolver",
      resolved_at: DateTime.utc_now()
    })
    |> Repo.update()

    if approval.auto_execute do
      Bizforge.Governance.Executor.execute_approved(approval)
    end
  end

  defp notify_pending(approval) do
    Logger.info(
      "[Governance.HeadlessResolver] Pending approval queued for external review: #{approval.action_type} (#{approval.id})"
    )

    Bizforge.Headless.Notifier.notify("governance.approval_required", %{
      approval_id: approval.id,
      action_type: approval.action_type,
      title: approval.title,
      description: approval.description,
      workspace_id: approval.workspace_id,
      requested_by: approval.requested_by
    })

    send_slack_approval_buttons(approval)
  end

  defp send_slack_approval_buttons(approval) do
    case approval.workspace_id do
      nil ->
        :ok

      workspace_id ->
        installation =
          Repo.one(
            from s in Bizforge.Schemas.SlackInstallation,
              where: s.workspace_id == ^workspace_id and s.active == true,
              limit: 1
          )

        case installation do
          nil ->
            :ok

          inst ->
            default_channel =
              case inst.channel_mappings do
                %{"approvals" => ch} -> ch
                %{"default" => ch} -> ch
                _ -> nil
              end

            if default_channel do
              Task.start(fn ->
                Bizforge.Integrations.Slack.Client.send_approval_message(
                  inst.bot_token,
                  default_channel,
                  approval
                )
              end)
            end
        end
    end
  end

  defp headless_governance_config(workspace_id) do
    case workspace_id do
      nil ->
        Application.get_env(:bizforge, :headless, [])

      _id ->
        workspace_config =
          case Repo.get(Bizforge.Schemas.Workspace, workspace_id) do
            nil -> %{}
            ws -> Map.get(ws, :config, %{}) || %{}
          end

        governance = Map.get(workspace_config, "governance", %{})
        headless_section = Map.get(governance, "headless", %{})
        headless_section
    end
  end

  defp auto_approve_enabled?(config) when is_map(config) do
    Map.get(config, "auto_approve", false) === true ||
      Map.get(config, :headless_auto_approve, false) === true
  end

  defp auto_approve_enabled?(config) when is_list(config) do
    Keyword.get(config, :headless_auto_approve, false) === true
  end

  defp auto_approve_enabled?(_), do: false
end
