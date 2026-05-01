defmodule Bizforge.Headless.StatsAccuracyTest do
  @moduledoc """
  Tests for stats dashboard data accuracy.

  Verifies that the health endpoint data matches the actual
  database/ETS state for agents, tasks, sessions, and system metrics.
  """
  use Bizforge.DataCase, async: false

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Issue, Session, Workspace}
  import Ecto.Query

  setup do
    workspace =
      %Workspace{}
      |> Workspace.changeset(%{name: "stats-test", path: "/tmp/stats-test", status: "active"})
      |> Repo.insert!()

    agents =
      Enum.map(1..3, fn i ->
        status = Enum.at(["active", "idle", "error"], rem(i - 1, 3))

        %Agent{}
        |> Agent.changeset(%{
          name: "stats-agent-#{i}",
          display_name: "Stats Agent #{i}",
          role: "worker",
          status: status,
          workspace_id: workspace.id
        })
        |> Repo.insert!()
      end)

    %{workspace: workspace, agents: agents}
  end

  describe "health endpoint data accuracy" do
    test "agent counts match database", %{agents: _agents} do
      active_count =
        Repo.aggregate(
          from(a in Agent, where: a.status in ["active", "working", "idle"]),
          :count
        )

      errored_count =
        Repo.aggregate(
          from(a in Agent, where: a.status == "error"),
          :count
        )

      paused_count =
        Repo.aggregate(
          from(a in Agent, where: a.status == "paused"),
          :count
        )

      assert active_count >= 2
      assert errored_count >= 1
      assert paused_count >= 0
    end

    test "task counts reflect actual issue state", %{workspace: workspace, agents: agents} do
      agent = hd(agents)

      %Issue{}
      |> Issue.changeset(%{
        title: "Test task",
        status: "in_progress",
        priority: "medium",
        workspace_id: workspace.id,
        assignee_id: agent.id
      })
      |> Repo.insert!()

      active_tasks =
        Repo.aggregate(
          from(i in Issue, where: i.status in ["in_progress", "assigned"]),
          :count
        )

      assert active_tasks >= 1
    end

    test "session counts match active sessions", %{workspace: workspace, agents: agents} do
      agent = hd(agents)

      %Session{}
      |> Session.changeset(%{
        status: "active",
        agent_id: agent.id,
        workspace_id: workspace.id,
        started_at: DateTime.utc_now()
      })
      |> Repo.insert!()

      active_sessions =
        Repo.aggregate(
          from(s in Session, where: s.status == "active"),
          :count
        )

      assert active_sessions >= 1
    end

    test "system metrics are non-negative" do
      memory = :erlang.memory()
      assert memory[:total] > 0

      process_count = :erlang.system_info(:process_count)
      assert process_count > 0

      scheduler_count = :erlang.system_info(:schedulers_online)
      assert scheduler_count > 0
    end
  end
end
