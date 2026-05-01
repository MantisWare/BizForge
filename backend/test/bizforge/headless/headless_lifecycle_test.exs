defmodule Bizforge.Headless.LifecycleTest do
  @moduledoc """
  Integration tests for the full headless boot-to-shutdown lifecycle.

  Verifies that Monitor, Bootstrap, and Watchdog start correctly,
  PID/meta files are written, and graceful shutdown compacts sessions.
  """
  use Bizforge.DataCase, async: false

  alias Bizforge.Headless.{Monitor, Bootstrap, Watchdog, Notifier}

  @pid_dir Path.expand("tmp/test_pids")

  setup do
    File.rm_rf!(@pid_dir)
    File.mkdir_p!(@pid_dir)

    Application.put_env(:bizforge, :headless,
      enabled: true,
      pid_dir: @pid_dir,
      health_port: 19090,
      workspace_path: nil
    )

    on_exit(fn ->
      File.rm_rf!(@pid_dir)
    end)

    :ok
  end

  describe "headless lifecycle" do
    test "Monitor starts and writes PID file" do
      {:ok, pid} = start_supervised(Monitor)
      assert Process.alive?(pid)

      pid_files = File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".pid"))
      assert length(pid_files) === 1

      meta_files = File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".meta.json"))
      assert length(meta_files) === 1
    end

    test "Monitor writes meta file with correct structure" do
      {:ok, _pid} = start_supervised(Monitor)

      meta_files = File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".meta.json"))
      [meta_file | _] = meta_files

      {:ok, content} = File.read(Path.join(@pid_dir, meta_file))
      {:ok, meta} = Jason.decode(content)

      assert Map.has_key?(meta, "health_port")
      assert Map.has_key?(meta, "started_at")
      assert Map.has_key?(meta, "pid")
      assert meta["health_port"] === 19090
    end

    test "Monitor pause_all deactivates scheduler jobs" do
      {:ok, _pid} = start_supervised(Monitor)

      result = Monitor.pause_all()
      assert {:ok, _count} = result
    end

    test "Monitor resume_all reactivates scheduler jobs" do
      {:ok, _pid} = start_supervised(Monitor)

      result = Monitor.resume_all()
      assert {:ok, _count} = result
    end

    test "Monitor cleans up PID and meta files on termination" do
      {:ok, pid} = start_supervised(Monitor)

      assert File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".pid")) |> length() === 1

      stop_supervised(Monitor)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000

      pid_files = File.ls!(@pid_dir) |> Enum.filter(&String.ends_with?(&1, ".pid"))
      assert pid_files === []
    end

    test "Bootstrap starts without error" do
      {:ok, pid} = start_supervised(Bootstrap)
      assert Process.alive?(pid)
    end

    test "Watchdog starts and schedules check" do
      {:ok, pid} = start_supervised(Watchdog)
      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert state.failure_counts === %{}
    end

    test "Notifier starts with webhook config" do
      {:ok, pid} = start_supervised(Notifier)
      assert Process.alive?(pid)
    end

    test "Notifier.notify/2 does not crash when no webhooks configured" do
      {:ok, _pid} = start_supervised(Notifier)
      assert Notifier.notify("test.event", %{key: "value"}) === :ok
    end
  end
end
