defmodule BizforgeWeb.DocumentController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Workspace, DocumentRevision}
  import Ecto.Query

  def index(conn, params) do
    with {:ok, ref_dir} <- resolve_reference_dir(params) do
      scan_dir =
        case params["project_id"] do
          nil -> ref_dir
          pid -> Path.join([ref_dir, "projects", pid])
        end

      files = scan_directory(scan_dir)
      documents = files_to_documents(files, ref_dir)
      tree = build_tree(files, ref_dir)

      json(conn, %{files: files, documents: documents, tree: tree, directory: scan_dir})
    else
      {:error, reason} ->
        conn |> put_status(404) |> json(%{error: reason})
    end
  end

  def show(conn, %{"path" => path_parts} = params) do
    with {:ok, ref_dir} <- resolve_reference_dir(params),
         file_path = Path.join([ref_dir | path_parts]),
         true <- safe_path?(ref_dir, file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          json(conn, %{
            path: Path.join(path_parts),
            content: content,
            size: byte_size(content)
          })

        {:error, :enoent} ->
          conn |> put_status(404) |> json(%{error: "not_found"})

        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: friendly_error(reason)})
      end
    else
      false ->
        conn |> put_status(400) |> json(%{error: "invalid_path"})

      {:error, reason} ->
        conn |> put_status(404) |> json(%{error: reason})
    end
  end

  def create(conn, %{"content" => content} = params) do
    with {:ok, ref_dir} <- resolve_reference_dir(params) do
      base_path =
        case {params["path"], params["title"]} do
          {path, _} when is_binary(path) and path != "" ->
            path

          {_, title} when is_binary(title) ->
            ext = format_to_ext(params["format"])
            slug = slugify(title)
            "#{slug}#{ext}"

          _ ->
            "untitled.md"
        end

      relative_path =
        case params["project_id"] do
          pid when is_binary(pid) and pid != "" ->
            if String.starts_with?(base_path, "projects/#{pid}/") do
              base_path
            else
              Path.join(["projects", pid, base_path])
            end

          _ ->
            base_path
        end

      file_path = Path.join(ref_dir, relative_path)

      if safe_path?(ref_dir, file_path) do
        dir = Path.dirname(file_path)

        with :ok <- File.mkdir_p(dir),
             :ok <- File.write(file_path, content) do
          stat = File.stat!(file_path)

          doc = %{
            id: relative_path,
            title: params["title"] || Path.basename(relative_path, Path.extname(relative_path)),
            path: relative_path,
            content: content,
            format: params["format"] || "markdown",
            project_id: params["project_id"],
            last_edited_by: "user",
            created_at: format_mtime(stat.mtime),
            updated_at: format_mtime(stat.mtime)
          }

          conn |> put_status(201) |> json(%{document: doc})
        else
          {:error, reason} ->
            conn |> put_status(500) |> json(%{error: friendly_error(reason)})
        end
      else
        conn |> put_status(400) |> json(%{error: "invalid_path"})
      end
    else
      {:error, reason} ->
        conn |> put_status(404) |> json(%{error: reason})
    end
  end

  def update(conn, %{"path" => path_parts, "content" => content} = params) do
    with {:ok, ref_dir} <- resolve_reference_dir(params),
         file_path = Path.join([ref_dir | path_parts]),
         true <- safe_path?(ref_dir, file_path) do
      dir = Path.dirname(file_path)
      relative_path = Path.join(path_parts)

      with :ok <- File.mkdir_p(dir),
           :ok <- File.write(file_path, content) do
        # Create a DocumentRevision record for history tracking
        workspace_id = params["workspace_id"] || conn.assigns[:workspace_id]
        user_id = conn.assigns[:current_user] && conn.assigns[:current_user].id

        if workspace_id do
          %DocumentRevision{}
          |> DocumentRevision.changeset(%{
            path: relative_path,
            content: content,
            message: params["message"] || "Updated via API",
            author_type: if(user_id, do: "user", else: "agent"),
            author_id: user_id || params["agent_id"],
            workspace_id: workspace_id
          })
          |> Repo.insert()
        end

        json(conn, %{ok: true, path: relative_path})
      else
        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: friendly_error(reason)})
      end
    else
      false ->
        conn |> put_status(400) |> json(%{error: "invalid_path"})

      {:error, reason} ->
        conn |> put_status(404) |> json(%{error: reason})
    end
  end

  def delete(conn, %{"path" => path_parts} = params) do
    with {:ok, ref_dir} <- resolve_reference_dir(params),
         file_path = Path.join([ref_dir | path_parts]),
         true <- safe_path?(ref_dir, file_path) do
      case File.rm(file_path) do
        :ok ->
          json(conn, %{ok: true})

        {:error, :enoent} ->
          conn |> put_status(404) |> json(%{error: "not_found"})

        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: friendly_error(reason)})
      end
    else
      false ->
        conn |> put_status(400) |> json(%{error: "invalid_path"})

      {:error, reason} ->
        conn |> put_status(404) |> json(%{error: reason})
    end
  end

  # GET /document-revisions?path=some/doc.md&workspace_id=...
  # Lists DocumentRevision entries. Path filter is optional — omit to list all revisions.
  def revisions(conn, params) do
    limit = min(String.to_integer(params["limit"] || "50"), 200)

    query =
      from r in DocumentRevision,
        order_by: [desc: r.inserted_at],
        limit: ^limit

    query =
      if params["path"],
        do: where(query, [r], r.path == ^params["path"]),
        else: query

    query =
      if params["workspace_id"],
        do: where(query, [r], r.workspace_id == ^params["workspace_id"]),
        else: query

    revisions = Repo.all(query)

    json(conn, %{
      revisions:
        Enum.map(revisions, fn r ->
          %{
            id: r.id,
            path: r.path,
            content: r.content,
            message: r.message,
            author_type: r.author_type,
            author_id: r.author_id,
            workspace_id: r.workspace_id,
            inserted_at: r.inserted_at
          }
        end)
    })
  end

  # --- Private helpers ---

  defp friendly_error(:enoent), do: "File not found"
  defp friendly_error(:eacces), do: "Permission denied"
  defp friendly_error(:eisdir), do: "Path is a directory"
  defp friendly_error(:enospc), do: "No space left on device"
  defp friendly_error(_other), do: "Operation failed"

  defp resolve_reference_dir(%{"workspace_id" => workspace_id}) when is_binary(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      nil ->
        {:error, "workspace_not_found"}

      workspace ->
        dir = Path.join([expand_home(workspace.path), ".bizforge", "reference"])
        File.mkdir_p!(dir)
        {:ok, dir}
    end
  end

  defp resolve_reference_dir(_params) do
    case Repo.one(from w in Workspace, where: w.status == "active", limit: 1) do
      nil ->
        {:error, "no_active_workspace"}

      workspace ->
        dir = Path.join([expand_home(workspace.path), ".bizforge", "reference"])
        File.mkdir_p!(dir)
        {:ok, dir}
    end
  end

  defp expand_home("~" <> rest), do: Path.expand("~") <> rest
  defp expand_home(path), do: path

  defp safe_path?(ref_dir, file_path) do
    expanded = Path.expand(file_path)
    expanded_ref = Path.expand(ref_dir)
    String.starts_with?(expanded, expanded_ref <> "/") or expanded == expanded_ref
  end

  defp format_mtime({{y, mo, d}, {h, mi, s}}) do
    NaiveDateTime.new!(y, mo, d, h, mi, s)
    |> NaiveDateTime.to_iso8601()
    |> Kernel.<>("Z")
  end

  defp format_mtime(_), do: nil

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s_-]/, "")
    |> String.replace(~r/[\s-]+/, "_")
    |> String.trim("_")
  end

  defp format_to_ext("json"), do: ".json"
  defp format_to_ext("yaml"), do: ".yaml"
  defp format_to_ext("text"), do: ".txt"
  defp format_to_ext("sql"), do: ".sql"
  defp format_to_ext("dbml"), do: ".dbml"
  defp format_to_ext("pdf"), do: ".pdf"
  defp format_to_ext(_), do: ".md"

  defp scan_directory(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&(not String.starts_with?(&1, ".")))
        |> Enum.flat_map(fn name ->
          path = Path.join(dir, name)
          stat = File.stat!(path)

          if stat.type == :directory do
            sub_files = scan_directory(path)
            [%{name: name, path: path, size: 0, type: "directory", modified_at: format_mtime(stat.mtime)} | sub_files]
          else
            [%{name: name, path: path, size: stat.size, type: "file", modified_at: format_mtime(stat.mtime)}]
          end
        end)
        |> Enum.sort_by(& &1.name)

      {:error, _} ->
        []
    end
  end

  defp files_to_documents(files, ref_dir) do
    files
    |> Enum.filter(&(&1.type == "file"))
    |> Enum.map(fn file ->
      rel_path = Path.relative_to(file.path, ref_dir)
      title = Path.basename(rel_path, Path.extname(rel_path))
      content =
        case File.read(file.path) do
          {:ok, c} -> c
          _ -> ""
        end

      %{
        id: rel_path,
        title: title,
        path: rel_path,
        content: content,
        format: ext_to_format(Path.extname(rel_path)),
        project_id: extract_project_id(rel_path),
        last_edited_by: "system",
        created_at: file.modified_at,
        updated_at: file.modified_at
      }
    end)
  end

  defp build_tree(files, ref_dir) do
    files
    |> Enum.filter(&(&1.type == "file"))
    |> Enum.map(fn file ->
      rel_path = Path.relative_to(file.path, ref_dir)
      %{
        path: rel_path,
        name: Path.basename(rel_path),
        type: "file"
      }
    end)
  end

  defp ext_to_format(".json"), do: "json"
  defp ext_to_format(".yaml"), do: "yaml"
  defp ext_to_format(".yml"), do: "yaml"
  defp ext_to_format(".txt"), do: "text"
  defp ext_to_format(".sql"), do: "sql"
  defp ext_to_format(".dbml"), do: "dbml"
  defp ext_to_format(".pdf"), do: "pdf"
  defp ext_to_format(".doc"), do: "binary"
  defp ext_to_format(".docx"), do: "binary"
  defp ext_to_format(".xls"), do: "binary"
  defp ext_to_format(".xlsx"), do: "binary"
  defp ext_to_format(_), do: "markdown"

  defp extract_project_id(rel_path) do
    case Path.split(rel_path) do
      ["projects", project_id | _rest] -> project_id
      _ -> nil
    end
  end
end
