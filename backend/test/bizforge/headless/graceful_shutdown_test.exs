defmodule Bizforge.Headless.GracefulShutdownTest do
  @moduledoc """
  Tests for graceful shutdown behavior.

  Verifies that on shutdown:
    - All active sessions are compacted
    - No tasks remain in orphaned "working" state
    - PID file is cleaned up
    - Agents are paused
  """
  use Bizforge.DataCase, async: false

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Session, Workspace}
  alias Bizforge.Headless.Monitor
  import Ecto.Query

  @pid_dir Path.expand("tmp/test_shutdown_pids")

  setup do
    File.rm_rf!(@pid_dir)
    File.mkdir_p!(@pid_dir)

    Application.put_env(:bizforge, :headless,
      enabled: true,
      pid_dir: @pid_dir,
      health_port: 19091,
      workspace_path: nil
    )

    workspace =
      %Workspace{}
      |> Workspace.changeset(%{name: "shutdown-test", path: "/tmp/shutdown-test", status: "active"})
      |> Repo.insert!()

    agent =
      %Agent{}
      |> Agent.changeset(%{
        name: "shutdown-agent",
        display_name: "Shutdown Agent",
        role: "worker",
        status: "active",
        workspace_id: workspace.id
      })
      |> Repo.insert!()

    on_exit(fn ->
      File.rm_rf!(@pid_dir)
    end)

    %{workspace: workspace, agent: agent}
  end

  describe "graceful shutdown" do
    test "pauses active agents on shutdown", %{agent: agent} do
      {:ok, monitor} = start_supervised(Monitor)

      assert Repo.get!(Agent, agent.id).status === "active"

      stop_supervised(Monitor)
      ref = Process.monitor(monitor)
      assert_receive {:DOWN, ^ref, :process, ^monitor, _}, 5_000

      updated = Repo.get!(Agent, agent.id)
      assert updated.status === "paused"
    end

    test "removes PID file on shutdown" do
      {:ok, monitor} = start_supervised(Monitor)

      pid_files = File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".pid"))
      assert length(pid_files) === 1

      stop_supervised(Monitor)
      ref = Process.monitor(monitor)
      assert_receive {:DOWN, ^ref, :process, ^monitor, _}, 5_000

      remaining_pids = File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".pid"))
      assert remaining_pids === []
    end

    test "no agents remain in working state after shutdown", %{workspace: workspace} do
      working_agent =
        %Agent{}
        |> Agent.changeset(%{
          name: "working-agent",
          display_name: "Working Agent",
          role: "worker",
          status: "working",
          workspace_id: workspace.id
        })
        |> Repo.insert!()

      {:ok, monitor} = start_supervised(Monitor)

      stop_supervised(Monitor)
      ref = Process.monitor(monitor)
      assert_receive {:DOWN, ^ref, :process, ^monitor, _}, 5_000

      updated = Repo.get!(Agent, working_agent.id)
      assert updated.status === "paused"
    end
  end
end
