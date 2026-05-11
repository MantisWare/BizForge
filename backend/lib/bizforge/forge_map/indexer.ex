defmodule Bizforge.ForgeMap.Indexer do
  @moduledoc """
  Creates memory_entries for each scanned file, storing the ForgeMap
  annotation as project-scoped memory with category "forgemap".
  """

  alias Bizforge.Repo
  alias Bizforge.Schemas.MemoryEntry
  import Ecto.Query

  @spec index(String.t(), String.t(), [map()]) :: {:ok, non_neg_integer()}
  def index(workspace_id, project_id, annotations) do
    clear_existing(workspace_id, project_id)

    count =
      Enum.reduce(annotations, 0, fn ann, acc ->
        tags =
          [ann.language | ann.exports]
          |> Enum.take(20)

        attrs = %{
          key: ann.path,
          content: ann.header,
          category: "forgemap",
          tags: tags,
          scope: "project",
          source: "forgemap",
          workspace_id: workspace_id,
          project_id: project_id
        }

        case %MemoryEntry{} |> MemoryEntry.changeset(attrs) |> Repo.insert() do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    {:ok, count}
  end

  @spec clear_existing(String.t(), String.t()) :: non_neg_integer()
  def clear_existing(workspace_id, project_id) do
    {count, _} =
      from(m in MemoryEntry,
        where:
          m.workspace_id == ^workspace_id and
            m.project_id == ^project_id and
            m.source == "forgemap"
      )
      |> Repo.delete_all()

    count
  end

  @spec get_index(String.t()) :: [MemoryEntry.t()]
  def get_index(project_id) do
    Repo.all(
      from m in MemoryEntry,
        where: m.project_id == ^project_id and m.source == "forgemap",
        order_by: [asc: m.key]
    )
  end

  @spec update_entry(String.t(), String.t(), map()) :: {:ok, MemoryEntry.t()} | {:error, term()}
  def update_entry(project_id, file_path, updates) do
    case Repo.one(
           from m in MemoryEntry,
             where:
               m.project_id == ^project_id and
                 m.source == "forgemap" and
                 m.key == ^file_path
         ) do
      nil ->
        {:error, :not_found}

      entry ->
        entry
        |> MemoryEntry.changeset(updates)
        |> Repo.update()
    end
  end
end
