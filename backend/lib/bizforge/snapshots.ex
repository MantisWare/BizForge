defmodule Bizforge.Snapshots do
  @moduledoc """
  Context module for workspace snapshots.

  A snapshot serializes the full state of a workspace — agents, teams,
  budgets, workflows, governance rules, org hierarchy, and markdown files —
  into a portable JSON file with an SHA-256 integrity manifest.
  """

  alias Bizforge.Snapshots.{Exporter, Importer}

  @snapshot_dir ".bizforge/snapshots"
  @lock_file ".bizforge/lock"

  def snapshot_dir, do: Path.expand(@snapshot_dir)

  def create(name, workspace_path) do
    Exporter.export(name, workspace_path, snapshot_dir())
  end

  def list do
    dir = snapshot_dir()

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.sort()
      |> Enum.map(fn file ->
        path = Path.join(dir, file)

        case File.read(path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, data} ->
                %{
                  name: String.replace_suffix(file, ".json", ""),
                  file: file,
                  created_at: Map.get(data, "created_at"),
                  workspace_path: Map.get(data, "workspace_path"),
                  agent_count: length(Map.get(data, "agents", [])),
                  integrity: Map.get(data, "integrity")
                }

              {:error, _} ->
                %{name: String.replace_suffix(file, ".json", ""), file: file, error: "corrupt"}
            end

          {:error, _} ->
            %{name: String.replace_suffix(file, ".json", ""), file: file, error: "unreadable"}
        end
      end)
    else
      []
    end
  end

  def restore(name) do
    snapshot_file = Path.join(snapshot_dir(), "#{name}.json")
    Importer.import(snapshot_file)
  end

  def lock(workspace_path) do
    lock_path = Path.join(workspace_path, @lock_file)
    File.mkdir_p!(Path.dirname(lock_path))

    lock_data = %{
      locked_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      pid: :os.getpid() |> to_string(),
      reason: "headless_mode"
    }

    File.write!(lock_path, Jason.encode!(lock_data, pretty: true))
    {:ok, lock_path}
  end

  def unlock(workspace_path) do
    lock_path = Path.join(workspace_path, @lock_file)

    if File.exists?(lock_path) do
      File.rm!(lock_path)
      :ok
    else
      {:error, :not_locked}
    end
  end

  def locked?(workspace_path) do
    lock_path = Path.join(workspace_path, @lock_file)
    File.exists?(lock_path)
  end
end
