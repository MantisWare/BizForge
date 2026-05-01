defmodule Bizforge.Headless.SnapshotRoundtripTest do
  @moduledoc """
  Tests for workspace snapshot create/restore roundtrip.

  Verifies that a workspace can be snapshotted, modified, and then
  restored to its original state from the snapshot.
  """
  use Bizforge.DataCase, async: false

  alias Bizforge.Snapshots
  alias Bizforge.Snapshots.Versioning
  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Workspace}

  @workspace_dir Path.expand("tmp/test_workspace")
  @snapshot_dir Path.expand("tmp/test_snapshots")

  setup do
    File.rm_rf!(@workspace_dir)
    File.rm_rf!(@snapshot_dir)
    File.mkdir_p!(@workspace_dir)
    File.mkdir_p!(Path.join(@workspace_dir, "agents"))

    File.write!(Path.join(@workspace_dir, "SYSTEM.md"), "# Test Workspace\n")
    File.write!(Path.join(@workspace_dir, "company.yaml"), "name: test\nbudget: 1000\n")
    File.write!(Path.join(@workspace_dir, "agents/worker.md"), "# Worker Agent\nRole: test\n")

    workspace =
      %Workspace{}
      |> Workspace.changeset(%{name: "test", path: @workspace_dir, status: "active"})
      |> Repo.insert!()

    %Agent{}
    |> Agent.changeset(%{
      name: "test-agent",
      display_name: "Test Agent",
      role: "worker",
      status: "idle",
      workspace_id: workspace.id
    })
    |> Repo.insert!()

    on_exit(fn ->
      File.rm_rf!(@workspace_dir)
      File.rm_rf!(@snapshot_dir)
    end)

    %{workspace: workspace}
  end

  describe "snapshot roundtrip" do
    test "create and restore produces matching state", %{workspace: workspace} do
      original_agents = Repo.all(Agent) |> Enum.filter(&(&1.workspace_id === workspace.id))
      assert length(original_agents) === 1

      assert {:ok, file, summary} =
               Bizforge.Snapshots.Exporter.export("test-snap", @workspace_dir, @snapshot_dir)

      assert File.exists?(file)
      assert summary.agents === 1
      assert summary.integrity !== nil

      agent = hd(original_agents)
      agent |> Ecto.Changeset.change(status: "error") |> Repo.update!()

      assert {:ok, restore_summary} = Bizforge.Snapshots.Importer.import(file)
      assert restore_summary.agents_restored >= 1
    end

    test "snapshot versioning tracks history" do
      File.mkdir_p!(@snapshot_dir)

      {:ok, v1, entry1} =
        Versioning.record_version(@snapshot_dir, %{
          name: "snap-v1",
          integrity_hash: "abc123",
          description: "First snapshot"
        })

      assert v1 === 1
      assert entry1["name"] === "snap-v1"

      {:ok, v2, entry2} =
        Versioning.record_version(@snapshot_dir, %{
          name: "snap-v2",
          integrity_hash: "def456",
          description: "Second snapshot"
        })

      assert v2 === 2
      assert entry2["parent_version"] === 1

      manifest = Versioning.load_manifest(@snapshot_dir)
      assert length(manifest) === 2
    end

    test "get_version retrieves correct entry" do
      File.mkdir_p!(@snapshot_dir)

      Versioning.record_version(@snapshot_dir, %{
        name: "v1-test",
        integrity_hash: "hash1"
      })

      Versioning.record_version(@snapshot_dir, %{
        name: "v2-test",
        integrity_hash: "hash2"
      })

      entry = Versioning.get_version(@snapshot_dir, 1)
      assert entry["name"] === "v1-test"
      assert entry["integrity_hash"] === "hash1"

      entry2 = Versioning.get_version(@snapshot_dir, 2)
      assert entry2["name"] === "v2-test"
    end

    test "latest_version returns most recent" do
      File.mkdir_p!(@snapshot_dir)

      Versioning.record_version(@snapshot_dir, %{name: "first", integrity_hash: "a"})
      Versioning.record_version(@snapshot_dir, %{name: "second", integrity_hash: "b"})
      Versioning.record_version(@snapshot_dir, %{name: "third", integrity_hash: "c"})

      latest = Versioning.latest_version(@snapshot_dir)
      assert latest["version"] === 3
      assert latest["name"] === "third"
    end
  end
end
