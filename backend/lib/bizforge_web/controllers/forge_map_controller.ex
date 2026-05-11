defmodule BizforgeWeb.ForgeMapController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.Project
  alias Bizforge.ForgeMap.{Detector, Scanner, Resolver, Annotator, Indexer}

  def detect(conn, %{"project_id" => project_id}) do
    case Repo.get(Project, project_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "project_not_found"})

      project ->
        result = Detector.detect(project.output_path)
        json(conn, %{detection: result})
    end
  end

  def scan(conn, %{"project_id" => project_id} = params) do
    write_headers = params["write_headers"] === true or params["write_headers"] === "true"

    case Repo.get(Project, project_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "project_not_found"})

      %Project{output_path: nil} ->
        conn |> put_status(422) |> json(%{error: "no_output_path"})

      project ->
        case Scanner.scan(project.output_path) do
          {:ok, files} ->
            usage_map = Resolver.resolve(files)

            annotations =
              Enum.map(files, fn file ->
                Annotator.generate(file, usage_map,
                  session_id: params["session_id"] || "s_auto",
                  timestamp: Date.utc_today() |> Date.to_iso8601()
                )
              end)

            if write_headers do
              Enum.each(annotations, fn ann ->
                Annotator.write_header(project.output_path, ann.path, ann.header)
              end)
            end

            {:ok, indexed_count} = Indexer.index(project.workspace_id, project_id, annotations)

            languages =
              files
              |> Enum.map(& &1.language)
              |> Enum.uniq()
              |> Enum.sort()

            total_exports =
              files
              |> Enum.flat_map(& &1.exports)
              |> length()

            json(conn, %{
              scan: %{
                file_count: length(files),
                indexed_count: indexed_count,
                languages: languages,
                total_exports: total_exports,
                headers_written: write_headers,
                files:
                  Enum.map(files, fn f ->
                    %{
                      path: f.path,
                      name: f.name,
                      language: f.language,
                      exports: f.exports,
                      line_count: f.line_count,
                      size: f.size,
                      used_by: Map.get(usage_map, f.path, [])
                    }
                  end)
              }
            })

          {:error, reason} ->
            conn |> put_status(422) |> json(%{error: to_string(reason)})
        end
    end
  end

  def index(conn, %{"project_id" => project_id}) do
    entries = Indexer.get_index(project_id)

    json(conn, %{
      entries:
        Enum.map(entries, fn e ->
          %{
            id: e.id,
            key: e.key,
            content: e.content,
            category: e.category,
            tags: e.tags || [],
            scope: e.scope,
            source: e.source,
            inserted_at: e.inserted_at,
            updated_at: e.updated_at
          }
        end)
    })
  end

  def update_entry(conn, %{"project_id" => project_id, "file_path" => file_path} = params) do
    updates = Map.take(params, ["content", "tags"])

    case Indexer.update_entry(project_id, file_path, updates) do
      {:ok, entry} ->
        json(conn, %{
          entry: %{
            id: entry.id,
            key: entry.key,
            content: entry.content,
            tags: entry.tags || [],
            updated_at: entry.updated_at
          }
        })

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "entry_not_found"})

      {:error, _changeset} ->
        conn |> put_status(422) |> json(%{error: "update_failed"})
    end
  end
end
