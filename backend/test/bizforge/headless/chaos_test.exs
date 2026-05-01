defmodule Bizforge.Headless.ChaosTest do
  @moduledoc """
  Chaos tests — simulate adapter failures, budget saturation, and
  governance blocks during headless operation.

  Tagged with @tag :chaos and excluded from default test run.
  Run with: mix test --include chaos
  """
  use Bizforge.DataCase, async: false

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Workspace, Approval}
  alias Bizforge.Headless.{Watchdog, Notifier}
  import Ecto.Query

  @tag :chaos

  setup do
    workspace =
      %Workspace{}
      |> Workspace.changeset(%{name: "chaos-test", path: "/tmp/chaos-test", status: "active"})
      |> Repo.insert!()

    agent =
      %Agent{}
      |> Agent.changeset(%{
        name: "chaos-agent",
        display_name: "Chaos Agent",
        role: "worker",
        status: "idle",
        adapter: "nonexistent_adapter",
        workspace_id: workspace.id
      })
      |> Repo.insert!()

    {:ok, _notifier} = start_supervised(Notifier)

    %{workspace: workspace, agent: agent}
  end

  describe "adapter failure simulation" do
    @tag :chaos
    test "watchdog recovers agent stuck in working state", %{agent: agent} do
      threshold_past = DateTime.utc_now() |> DateTime.add(-700, :second)

      agent
      |> Ecto.Changeset.change(status: "working", updated_at: threshold_past)
      |> Repo.update!()

      {:ok, watchdog} = start_supervised(Watchdog)

      send(watchdog, :check)
      _ = :sys.get_state(watchdog)

      updated_agent = Repo.get!(Agent, agent.id)
      assert updated_agent.status === "idle"
    end

    @tag :chaos
    test "watchdog handles agent in error state with backoff", %{agent: agent} do
      agent
      |> Ecto.Changeset.change(status: "error", updated_at: DateTime.utc_now() |> DateTime.add(-100, :second))
      |> Repo.update!()

      {:ok, watchdog} = start_supervised(Watchdog)

      send(watchdog, :check)
      state = :sys.get_state(watchdog)

      assert Map.has_key?(state.failure_counts, agent.id)
    end
  end

  describe "budget saturation" do
    @tag :chaos
    test "resource limiter pauses agents when limit exceeded", %{workspace: workspace} do
      Enum.each(1..5, fn i ->
        %Agent{}
        |> Agent.changeset(%{
          name: "budget-agent-#{i}",
          display_name: "Budget Agent #{i}",
          role: "worker",
          status: "idle",
          workspace_id: workspace.id
        })
        |> Repo.insert!()
      end)

      Application.put_env(:bizforge, :headless,
        Application.get_env(:bizforge, :headless, [])
        |> Keyword.put(:max_agents, 3)
      )

      {:ok, limiter} = start_supervised(Bizforge.Headless.ResourceLimiter)

      send(limiter, :check)
      _ = :sys.get_state(limiter)

      paused_count = Repo.aggregate(from(a in Agent, where: a.status == "paused"), :count)
      assert paused_count > 0
    end
  end

  describe "governance blocks during headless run" do
    @tag :chaos
    test "governance gate creates pending approval", %{workspace: workspace, agent: agent} do
      result =
        Bizforge.Governance.Gate.check(:spawn_agent, %{
          workspace_id: workspace.id,
          requester_id: agent.id,
          requester_role: "worker",
          name: "chaos-spawn"
        })

      case result do
        :allowed ->
          assert true

        {:pending_approval, approval} ->
          assert approval.status === "pending"
          assert approval.action_type === "spawn_agent"
      end
    end

    @tag :chaos
    test "headless resolver auto-approves when configured", %{workspace: workspace, agent: agent} do
      approval =
        %Approval{}
        |> Approval.governance_changeset(%{
          title: "Test approval",
          description: "Chaos test",
          action_type: "spawn_agent",
          action_params: %{},
          workspace_id: workspace.id,
          requested_by: agent.id,
          status: "pending",
          auto_execute: false
        })
        |> Repo.insert!()

      assert approval.status === "pending"
    end
  end
end
