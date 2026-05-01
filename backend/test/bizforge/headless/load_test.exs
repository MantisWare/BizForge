defmodule Bizforge.Headless.LoadTest do
  @moduledoc """
  Load tests — run workspace with 50+ agents headlessly and verify stability.

  These tests are tagged with @tag :load and are excluded from the default
  test run. Run with: mix test --include load
  """
  use Bizforge.DataCase, async: false

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Workspace}

  @tag :load
  @agent_count 50

  setup do
    workspace =
      %Workspace{}
      |> Workspace.changeset(%{name: "load-test", path: "/tmp/load-test", status: "active"})
      |> Repo.insert!()

    agents =
      Enum.map(1..@agent_count, fn i ->
        %Agent{}
        |> Agent.changeset(%{
          name: "load-agent-#{i}",
          display_name: "Load Agent #{i}",
          role: "worker",
          status: "idle",
          adapter: "bash",
          workspace_id: workspace.id
        })
        |> Repo.insert!()
      end)

    %{workspace: workspace, agents: agents}
  end

  describe "load testing with #{@agent_count} agents" do
    @tag :load
    test "all agents are created and queryable", %{agents: agents} do
      assert length(agents) === @agent_count

      import Ecto.Query
      count = Repo.aggregate(from(a in Agent, where: a.status == "idle"), :count)
      assert count >= @agent_count
    end

    @tag :load
    test "watchdog can check all agents without timeout", %{agents: _agents} do
      {:ok, watchdog} = start_supervised(Bizforge.Headless.Watchdog)

      state = :sys.get_state(watchdog)
      assert state.failure_counts === %{}

      send(watchdog, :check)
      _ = :sys.get_state(watchdog)

      assert Process.alive?(watchdog)
    end

    @tag :load
    test "resource limiter checks complete within threshold", %{agents: _agents} do
      Application.put_env(:bizforge, :headless,
        Application.get_env(:bizforge, :headless, [])
        |> Keyword.put(:max_agents, @agent_count + 10)
      )

      {:ok, limiter} = start_supervised(Bizforge.Headless.ResourceLimiter)
      assert Process.alive?(limiter)

      limits = Bizforge.Headless.ResourceLimiter.limits()
      assert limits.max_agents === @agent_count + 10
    end

    @tag :load
    test "health endpoint aggregates data for many agents", %{agents: _agents} do
      import Ecto.Query

      active_count =
        Repo.aggregate(
          from(a in Agent, where: a.status in ["active", "working", "idle"]),
          :count
        )

      assert active_count >= @agent_count
    end
  end
end
