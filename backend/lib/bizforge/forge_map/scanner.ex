defmodule Bizforge.ForgeMap.Scanner do
  @moduledoc """
  Walks a project's output_path and extracts structured metadata from each
  source file: exports, imports, language, and line count.
  """

  @source_extensions ~w(.ts .tsx .js .jsx .svelte .vue .py .ex .exs .rs .go .rb .java .kt .cs .cpp .c .h .swift .php)

  @ignore_dirs ~w(node_modules .git dist build _build deps target __pycache__ .next .svelte-kit .nuxt vendor .bizforge .cache)

  @max_file_size 512_000

  defstruct [:path, :name, :language, :exports, :imports, :line_count, :size]

  @type t :: %__MODULE__{
    path: String.t(),
    name: String.t(),
    language: String.t(),
    exports: [String.t()],
    imports: [%{from: String.t(), symbols: [String.t()]}],
    line_count: non_neg_integer(),
    size: non_neg_integer()
  }

  def scan(output_path) when is_binary(output_path) do
    expanded = Path.expand(output_path)

    if File.dir?(expanded) do
      files = walk(expanded, expanded)
      {:ok, files}
    else
      {:error, :not_a_directory}
    end
  end

  defp walk(dir, root) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full = Path.join(dir, entry)

          cond do
            entry in @ignore_dirs -> []
            String.starts_with?(entry, ".") -> []
            File.dir?(full) -> walk(full, root)
            scannable?(entry) -> [analyze_file(full, root)]
            true -> []
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp scannable?(filename) do
    Path.extname(filename) in @source_extensions
  end

  defp analyze_file(full_path, root) do
    relative = Path.relative_to(full_path, root)
    stat = File.stat!(full_path)

    if stat.size > @max_file_size do
      %__MODULE__{
        path: relative,
        name: Path.basename(full_path),
        language: language_for(full_path),
        exports: [],
        imports: [],
        line_count: 0,
        size: stat.size
      }
    else
      content = File.read!(full_path)
      lines = String.split(content, "\n")
      lang = language_for(full_path)

      %__MODULE__{
        path: relative,
        name: Path.basename(full_path),
        language: lang,
        exports: extract_exports(content, lang),
        imports: extract_imports(content, lang),
        line_count: length(lines),
        size: stat.size
      }
    end
  rescue
    _ -> nil
  end

  defp language_for(path) do
    case Path.extname(path) do
      e when e in [".ts", ".tsx"] -> "TypeScript"
      e when e in [".js", ".jsx"] -> "JavaScript"
      ".svelte" -> "Svelte"
      ".vue" -> "Vue"
      ".py" -> "Python"
      e when e in [".ex", ".exs"] -> "Elixir"
      ".rs" -> "Rust"
      ".go" -> "Go"
      ".rb" -> "Ruby"
      e when e in [".java", ".kt"] -> "Java"
      ".cs" -> "C#"
      e when e in [".cpp", ".c", ".h"] -> "C/C++"
      ".swift" -> "Swift"
      ".php" -> "PHP"
      _ -> "Other"
    end
  end

  def extract_exports(content, lang) when lang in ["TypeScript", "JavaScript", "Svelte"] do
    named_patterns = [
      ~r/export\s+(?:default\s+)?(?:function|const|let|var|class|interface|type|enum)\s+(\w+)/,
      ~r/export\s+\{([^}]+)\}/
    ]

    named =
      Enum.flat_map(named_patterns, fn pattern ->
        Regex.scan(pattern, content)
        |> Enum.flat_map(fn
          [_, group] ->
            group
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.map(fn s ->
              s |> String.split(~r/\s+as\s+/) |> List.last() |> String.trim()
            end)
            |> Enum.reject(&(&1 === ""))
        end)
      end)

    has_default =
      Regex.match?(~r/export\s+default\s/, content) and
        not Enum.any?(named, &(&1 === "default"))

    all = if has_default, do: ["default" | named], else: named
    Enum.uniq(all)
  end

  def extract_exports(content, "Elixir") do
    Regex.scan(~r/^\s*def\s+(\w+)/m, content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.reject(&String.starts_with?(&1, "_"))
    |> Enum.uniq()
  end

  def extract_exports(content, "Python") do
    patterns = [
      ~r/^def\s+(\w+)/m,
      ~r/^class\s+(\w+)/m,
      ~r/^(\w+)\s*=/m
    ]

    Enum.flat_map(patterns, fn p ->
      Regex.scan(p, content) |> Enum.map(fn [_, name] -> name end)
    end)
    |> Enum.reject(&String.starts_with?(&1, "_"))
    |> Enum.uniq()
  end

  def extract_exports(_content, _lang), do: []

  def extract_imports(content, lang) when lang in ["TypeScript", "JavaScript", "Svelte"] do
    named_imports =
      Regex.scan(~r/import\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, named, from] ->
        symbols =
          named
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(fn s -> s |> String.split(~r/\s+as\s+/) |> List.first() |> String.trim() end)
          |> Enum.reject(&(&1 === ""))
        %{from: from, symbols: symbols}
      end)

    default_imports =
      Regex.scan(~r/import\s+(\w+)\s+from\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, name, from] -> %{from: from, symbols: [name]} end)

    wildcard_imports =
      Regex.scan(~r/import\s+\*\s+as\s+(\w+)\s+from\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, _alias, from] -> %{from: from, symbols: ["*"]} end)

    type_imports =
      Regex.scan(~r/import\s+type\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, named, from] ->
        symbols =
          named
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 === ""))
        %{from: from, symbols: symbols}
      end)

    side_effect_imports =
      Regex.scan(~r/import\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, from] -> %{from: from, symbols: []} end)

    (wildcard_imports ++ named_imports ++ type_imports ++ default_imports ++ side_effect_imports)
    |> Enum.uniq_by(fn imp -> {imp.from, Enum.sort(imp.symbols)} end)
  end

  def extract_imports(content, "Elixir") do
    patterns = [
      ~r/alias\s+([\w.]+)/,
      ~r/import\s+([\w.]+)/,
      ~r/use\s+([\w.]+)/
    ]

    Enum.flat_map(patterns, fn p ->
      Regex.scan(p, content)
      |> Enum.map(fn [_, mod] -> %{from: mod, symbols: []} end)
    end)
  end

  def extract_imports(content, "Python") do
    patterns = [
      ~r/from\s+([\w.]+)\s+import\s+(.+)/,
      ~r/^import\s+([\w.]+)/m
    ]

    Enum.flat_map(patterns, fn p ->
      Regex.scan(p, content)
      |> Enum.map(fn
        [_, mod, names] ->
          symbols = names |> String.split(",") |> Enum.map(&String.trim/1)
          %{from: mod, symbols: symbols}

        [_, mod] ->
          %{from: mod, symbols: []}
      end)
    end)
  end

  def extract_imports(_content, _lang), do: []
end
