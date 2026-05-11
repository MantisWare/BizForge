defmodule Bizforge.ForgeMap.Tools do
  @moduledoc """
  MCP-style tool definitions for ForgeMap operations.
  These can be injected into agent sessions so agents can query
  and update the ForgeMap index.
  """

  alias Bizforge.ForgeMap.{Indexer, Scanner, Resolver, Annotator}
  alias Bizforge.Repo
  alias Bizforge.Schemas.Project

  @doc "Returns tool definitions for ForgeMap in MCP-compatible format."
  def definitions do
    [
      %{
        name: "bizforge_forgemap_index",
        description: "Query the ForgeMap file index for a project. Returns metadata for all indexed source files including exports, imports, and used_by references.",
        input_schema: %{
          type: "object",
          properties: %{
            project_id: %{type: "string", description: "The project ID to query"},
            query: %{type: "string", description: "Optional keyword filter for file paths or tags"}
          },
          required: ["project_id"]
        }
      },
      %{
        name: "bizforge_forgemap_update",
        description: "Update a file's ForgeMap annotation and memory entry after modifying it. Call this after you edit a source file to keep the index current.",
        input_schema: %{
          type: "object",
          properties: %{
            project_id: %{type: "string", description: "The project ID"},
            file_path: %{type: "string", description: "Relative path of the modified file"},
            content: %{type: "string", description: "New ForgeMap header content"},
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Updated tags (exports, language)"
            }
          },
          required: ["project_id", "file_path"]
        }
      },
      %{
        name: "bizforge_forgemap_rescan",
        description: "Re-scan a single file and update its ForgeMap entry. Use when you've substantially changed a file's exports or imports.",
        input_schema: %{
          type: "object",
          properties: %{
            project_id: %{type: "string", description: "The project ID"},
            file_path: %{type: "string", description: "Relative path of the file to rescan"}
          },
          required: ["project_id", "file_path"]
        }
      }
    ]
  end

  @doc "Execute a ForgeMap tool call by name and arguments."
  def execute("bizforge_forgemap_index", %{"project_id" => project_id} = args) do
    entries = Indexer.get_index(project_id)
    query = Map.get(args, "query", "")

    filtered =
      if query !== "" and query !== nil do
        pattern = String.downcase(query)

        Enum.filter(entries, fn e ->
          String.contains?(String.downcase(e.key), pattern) or
            Enum.any?(e.tags || [], &String.contains?(String.downcase(&1), pattern))
        end)
      else
        entries
      end

    results =
      Enum.map(filtered, fn e ->
        %{path: e.key, content: e.content, tags: e.tags || []}
      end)

    {:ok, %{file_count: length(results), files: Enum.take(results, 50)}}
  end

  def execute("bizforge_forgemap_update", %{"project_id" => project_id, "file_path" => file_path} = args) do
    updates = Map.take(args, ["content", "tags"])

    case Indexer.update_entry(project_id, file_path, updates) do
      {:ok, entry} ->
        {:ok, %{updated: true, path: entry.key}}

      {:error, :not_found} ->
        {:error, "File #{file_path} not found in ForgeMap index"}

      {:error, _} ->
        {:error, "Failed to update ForgeMap entry"}
    end
  end

  def execute("bizforge_forgemap_rescan", %{"project_id" => project_id, "file_path" => file_path}) do
    case Repo.get(Project, project_id) do
      nil ->
        {:error, "Project not found"}

      %Project{output_path: nil} ->
        {:error, "Project has no output_path"}

      project ->
        full_path = Path.join(project.output_path, file_path)

        if File.exists?(full_path) do
          case Scanner.scan(project.output_path) do
            {:ok, all_files} ->
              file_entry = Enum.find(all_files, &(&1.path === file_path))

              if file_entry !== nil do
                usage_map = Resolver.resolve(all_files)
                annotation = Annotator.generate(file_entry, usage_map)

                case Indexer.update_entry(project_id, file_path, %{
                  "content" => annotation.header,
                  "tags" => [file_entry.language | file_entry.exports] |> Enum.take(20)
                }) do
                  {:ok, _} -> {:ok, %{rescanned: true, path: file_path, exports: file_entry.exports}}
                  {:error, :not_found} -> {:error, "File not in index — run a full scan first"}
                  {:error, _} -> {:error, "Failed to update ForgeMap entry after rescan"}
                end
              else
                {:error, "File not found during scan"}
              end

            {:error, reason} ->
              {:error, "Scan failed: #{reason}"}
          end
        else
          {:error, "File does not exist: #{file_path}"}
        end
    end
  end

  def execute(tool_name, _args) do
    {:error, "Unknown ForgeMap tool: #{tool_name}"}
  end
end
