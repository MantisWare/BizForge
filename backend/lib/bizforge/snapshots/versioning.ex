defmodule Bizforge.Snapshots.Versioning do
  @moduledoc """
  Tracks snapshot version history for a workspace.

  Maintains a `versions.json` manifest in the snapshots directory that records
  each snapshot's version number, parent version, timestamp, description, and
  integrity hash. Supports rollback to any previous version.
  """
  require Logger

  @manifest_file "versions.json"

  def manifest_path(snapshot_dir) do
    Path.join(snapshot_dir, @manifest_file)
  end

  def load_manifest(snapshot_dir) do
    path = manifest_path(snapshot_dir)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end

      {:error, _} ->
        []
    end
  end

  def save_manifest(snapshot_dir, manifest) do
    path = manifest_path(snapshot_dir)
    File.mkdir_p!(snapshot_dir)
    File.write!(path, Jason.encode!(manifest, pretty: true))
    :ok
  end

  def next_version(manifest) do
    case manifest do
      [] -> 1
      entries -> Enum.max_by(entries, & &1["version"])["version"] + 1
    end
  end

  def record_version(snapshot_dir, attrs) do
    manifest = load_manifest(snapshot_dir)
    version = next_version(manifest)

    entry = %{
      "version" => version,
      "parent_version" => max(version - 1, 0),
      "name" => attrs.name,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "description" => Map.get(attrs, :description, ""),
      "integrity_hash" => attrs.integrity_hash,
      "snapshot_file" => "#{attrs.name}.json"
    }

    updated_manifest = manifest ++ [entry]
    save_manifest(snapshot_dir, updated_manifest)

    {:ok, version, entry}
  end

  def get_version(snapshot_dir, version) when is_integer(version) do
    manifest = load_manifest(snapshot_dir)
    Enum.find(manifest, fn e -> e["version"] === version end)
  end

  def get_by_name(snapshot_dir, name) when is_binary(name) do
    manifest = load_manifest(snapshot_dir)
    Enum.find(manifest, fn e -> e["name"] === name end)
  end

  def latest_version(snapshot_dir) do
    manifest = load_manifest(snapshot_dir)

    case manifest do
      [] -> nil
      entries -> Enum.max_by(entries, & &1["version"])
    end
  end

  def diff(snapshot_dir, v1, v2) when is_integer(v1) and is_integer(v2) do
    entry1 = get_version(snapshot_dir, v1)
    entry2 = get_version(snapshot_dir, v2)

    cond do
      entry1 === nil -> {:error, {:version_not_found, v1}}
      entry2 === nil -> {:error, {:version_not_found, v2}}
      true -> compute_diff(snapshot_dir, entry1, entry2)
    end
  end

  defp compute_diff(snapshot_dir, entry1, entry2) do
    file1 = Path.join(snapshot_dir, entry1["snapshot_file"])
    file2 = Path.join(snapshot_dir, entry2["snapshot_file"])

    with {:ok, raw1} <- File.read(file1),
         {:ok, raw2} <- File.read(file2),
         {:ok, data1} <- Jason.decode(raw1),
         {:ok, data2} <- Jason.decode(raw2) do
      agents1 = MapSet.new(data1["agents"] || [], & &1["name"])
      agents2 = MapSet.new(data2["agents"] || [], & &1["name"])

      added_agents = MapSet.difference(agents2, agents1) |> MapSet.to_list()
      removed_agents = MapSet.difference(agents1, agents2) |> MapSet.to_list()

      schedules1 = MapSet.new(data1["schedules"] || [], & &1["name"])
      schedules2 = MapSet.new(data2["schedules"] || [], & &1["name"])

      added_schedules = MapSet.difference(schedules2, schedules1) |> MapSet.to_list()
      removed_schedules = MapSet.difference(schedules1, schedules2) |> MapSet.to_list()

      {:ok,
       %{
         from_version: entry1["version"],
         to_version: entry2["version"],
         integrity_changed: entry1["integrity_hash"] !== entry2["integrity_hash"],
         agents: %{
           added: added_agents,
           removed: removed_agents
         },
         schedules: %{
           added: added_schedules,
           removed: removed_schedules
         }
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
