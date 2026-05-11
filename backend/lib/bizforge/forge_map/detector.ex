defmodule Bizforge.ForgeMap.Detector do
  @moduledoc """
  Detects whether a project output_path contains an existing codebase
  by scanning for recognizable source files and project manifests.
  """

  @manifest_files ~w(
    package.json mix.exs Cargo.toml pyproject.toml setup.py requirements.txt
    go.mod pom.xml build.gradle Gemfile composer.json CMakeLists.txt Makefile
    tsconfig.json vite.config.ts vite.config.js next.config.js next.config.mjs
    svelte.config.js angular.json pubspec.yaml deno.json
  )

  @source_extensions ~w(.ts .tsx .js .jsx .svelte .vue .py .ex .exs .rs .go .rb .java .kt .cs .cpp .c .h .swift .php .dart .lua .zig .nim)

  @ignore_dirs ~w(node_modules .git dist build _build deps target __pycache__ .next .svelte-kit .nuxt vendor .bizforge)

  def detect(nil), do: {:error, :no_output_path}

  def detect(output_path) do
    expanded = Path.expand(output_path)

    if File.dir?(expanded) do
      {files, languages, manifests} = scan_directory(expanded, expanded)

      %{
        has_codebase: length(files) > 0,
        file_count: length(files),
        languages: Enum.uniq(languages) |> Enum.sort(),
        detected_stack: detect_stack(manifests, languages),
        manifests: manifests,
        output_path: expanded
      }
    else
      %{
        has_codebase: false,
        file_count: 0,
        languages: [],
        detected_stack: [],
        manifests: [],
        output_path: expanded
      }
    end
  end

  defp scan_directory(dir, root) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce(entries, {[], [], []}, fn entry, {files, langs, manifests} ->
          full_path = Path.join(dir, entry)
          relative = Path.relative_to(full_path, root)

          cond do
            entry in @ignore_dirs ->
              {files, langs, manifests}

            String.starts_with?(entry, ".") ->
              {files, langs, manifests}

            File.dir?(full_path) ->
              {sub_files, sub_langs, sub_manifests} = scan_directory(full_path, root)
              {files ++ sub_files, langs ++ sub_langs, manifests ++ sub_manifests}

            entry in @manifest_files ->
              {files, langs, [relative | manifests]}

            source_file?(entry) ->
              lang = language_for_extension(Path.extname(entry))
              {[relative | files], [lang | langs], manifests}

            true ->
              {files, langs, manifests}
          end
        end)

      {:error, _} ->
        {[], [], []}
    end
  end

  defp source_file?(filename) do
    ext = Path.extname(filename)
    ext in @source_extensions
  end

  defp language_for_extension(ext) do
    case ext do
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
      ".dart" -> "Dart"
      _ -> "Other"
    end
  end

  defp detect_stack(manifests, languages) do
    stacks = []

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "mix.exs")),
        do: ["Phoenix/Elixir" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "next.config")),
        do: ["Next.js" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "svelte.config")),
        do: ["SvelteKit" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "vite.config")),
        do: ["Vite" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "angular.json")),
        do: ["Angular" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "Cargo.toml")),
        do: ["Rust" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "go.mod")),
        do: ["Go" | stacks],
        else: stacks

    stacks =
      if Enum.any?(manifests, &String.contains?(&1, "pyproject.toml")) or
           Enum.any?(manifests, &String.contains?(&1, "requirements.txt")),
        do: ["Python" | stacks],
        else: stacks

    stacks =
      if stacks === [] and "TypeScript" in languages,
        do: ["TypeScript" | stacks],
        else: stacks

    stacks =
      if stacks === [] and "JavaScript" in languages,
        do: ["JavaScript" | stacks],
        else: stacks

    Enum.reverse(stacks)
  end
end
