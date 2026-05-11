defmodule Bizforge.ForgeMap.Annotator do
  @moduledoc """
  Generates ForgeMap header annotations for source files.
  Optionally writes the header block back to the file on disk.
  """

  alias Bizforge.ForgeMap.Scanner

  @type annotation :: %{
    path: String.t(),
    header: String.t(),
    exports: [String.t()],
    used_by: [%{file: String.t(), symbols: [String.t()]}],
    language: String.t()
  }

  @spec generate(Scanner.t(), %{String.t() => [map()]}, keyword()) :: annotation()
  def generate(%Scanner{} = file, usage_map, opts \\ []) do
    used_by = Map.get(usage_map, file.path, [])
    session_id = Keyword.get(opts, :session_id, "s_auto")
    timestamp = Keyword.get(opts, :timestamp, Date.utc_today() |> Date.to_iso8601())

    header = build_header(file, used_by, session_id, timestamp)

    %{
      path: file.path,
      header: header,
      exports: file.exports,
      used_by: used_by,
      language: file.language
    }
  end

  @spec write_header(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_header(output_path, relative_path, header) do
    full = Path.join(output_path, relative_path)

    case File.read(full) do
      {:ok, content} ->
        stripped = strip_existing_header(content, comment_prefix_for(relative_path))
        new_content = header <> "\n" <> stripped
        File.write(full, new_content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_header(file, used_by, session_id, timestamp) do
    prefix = comment_prefix_for(file.path)
    is_html_comment = prefix === "<!--"

    export_str =
      if file.exports !== [] do
        Enum.join(file.exports, ", ")
      else
        "(none)"
      end

    used_by_str =
      if used_by !== [] do
        Enum.map_join(used_by, "; ", fn u ->
          symbols = Enum.join(u.symbols, ", ")
          "#{u.file} → #{symbols}"
        end)
      else
        "(none)"
      end

    if is_html_comment do
      "<!--\n" <>
        "  #{file.path} — #{file.name}\n" <>
        "\n" <>
        "  exports: #{export_str}\n" <>
        "  used_by: #{used_by_str}\n" <>
        "  rules:\n" <>
        "  agent: forgemap-cli (no-llm) | forgemap-cli | #{timestamp} | #{session_id} | ForgeMap annotation pass\n" <>
        "  messages:\n" <>
        "-->"
    else
      lines = [
        "#{prefix} #{file.path} — #{file.name}",
        "#{prefix}",
        "#{prefix} exports: #{export_str}",
        "#{prefix} used_by: #{used_by_str}",
        "#{prefix} rules:",
        "#{prefix} agent: forgemap-cli (no-llm) | forgemap-cli | #{timestamp} | #{session_id} | ForgeMap annotation pass",
        "#{prefix} messages:"
      ]
      Enum.join(lines, "\n")
    end
  end

  defp comment_prefix_for(path) do
    case Path.extname(path) do
      e when e in [".py", ".rb"] -> "#"
      e when e in [".ex", ".exs"] -> "#"
      e when e in [".svelte", ".vue", ".html"] -> "<!--"
      _ -> "//"
    end
  end

  defp strip_existing_header(content, prefix) do
    if prefix === "<!--" do
      strip_html_forgemap_block(content)
    else
      lines = String.split(content, "\n")
      {_, rest} = strip_header_lines(lines, prefix, true)
      Enum.join(rest, "\n")
    end
  end

  defp strip_html_forgemap_block(content) do
    case Regex.run(~r/\A\s*<!--[\s\S]*?ForgeMap[\s\S]*?-->\s*\n?/i, content) do
      [match] -> String.replace_prefix(content, match, "")
      nil ->
        case Regex.run(~r/\A\s*<!--[\s\S]*?exports:[\s\S]*?-->\s*\n?/i, content) do
          [match] -> String.replace_prefix(content, match, "")
          nil -> content
        end
    end
  end

  defp strip_header_lines([], _prefix, _in_header), do: {true, []}

  defp strip_header_lines([line | rest], prefix, true) do
    trimmed = String.trim(line)

    is_header_line = String.starts_with?(trimmed, prefix) or trimmed === ""

    is_forgemap = String.contains?(trimmed, "forgemap") or String.contains?(trimmed, "ForgeMap")
    is_annotation_field =
      String.contains?(trimmed, "exports:") or
        String.contains?(trimmed, "used_by:") or
        String.contains?(trimmed, "rules:") or
        String.contains?(trimmed, "agent:") or
        String.contains?(trimmed, "messages:")

    if is_header_line and (is_forgemap or is_annotation_field or trimmed === "" or String.ends_with?(trimmed, "—")) do
      strip_header_lines(rest, prefix, true)
    else
      {false, [line | rest]}
    end
  end

  defp strip_header_lines(lines, _prefix, false), do: {false, lines}
end
