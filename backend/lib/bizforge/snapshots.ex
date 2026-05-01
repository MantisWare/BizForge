defmodule Bizforge.Snapshots do
  @moduledoc """
  Context module for workspace snapshots.

  A snapshot serializes the full state of a workspace — agents, teams,
  budgets, workflows, governance rules, org hierarchy, and markdown files —
  into a portable JSON file with an SHA-256 integrity manifest.

  Supports versioned history and rollback to any previous snapshot.
  """

  alias Bizforge.Snapshots.{Exporter, Importer, Versioning}

  @snapshot_dir ".bizforge/snapshots"
  @lock_file ".bizforge/lock"

  def snapshot_dir, do: Path.expand(@snapshot_dir)

  def create(name, workspace_path, opts \\ []) do
    dir = snapshot_dir()

    case Exporter.export(name, workspace_path, dir) do
      {:ok, file, summary} ->
        description = Keyword.get(opts, :description, "")

        {:ok, version, _entry} =
          Versioning.record_version(dir, %{
            name: name,
            integrity_hash: summary.integrity,
            description: description
          })

        {:ok, file, Map.put(summary, :version, version)}

      error ->
        error
    end
  end

  def list do
    dir = snapshot_dir()

    if File.dir?(dir) do
      manifest = Versioning.load_manifest(dir)

      dir
      |> File.ls!()
      |> Enum.filter(fn f -> String.ends_with?(f, ".json") && f !== "versions.json" end)
      |> Enum.sort()
      |> Enum.map(fn file ->
        path = Path.join(dir, file)

        case File.read(path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, data} ->
                name = String.replace_suffix(file, ".json", "")
                version_entry = Enum.find(manifest, fn e -> e["name"] === name end)

                %{
                  name: name,
                  file: file,
                  version: if(version_entry, do: version_entry["version"], else: nil),
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

  def rollback(version) when is_integer(version) do
    dir = snapshot_dir()

    case Versioning.get_version(dir, version) do
      nil ->
        {:error, :version_not_found}

      entry ->
        snapshot_file = Path.join(dir, entry["snapshot_file"])
        Importer.import(snapshot_file)
    end
  end

  def diff(v1, v2) when is_integer(v1) and is_integer(v2) do
    Versioning.diff(snapshot_dir(), v1, v2)
  end

  def versions do
    Versioning.load_manifest(snapshot_dir())
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
