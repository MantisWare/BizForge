defmodule Bizforge.ForgeMap.Resolver do
  @moduledoc """
  Resolves cross-file `used_by` references by matching each file's exports
  against other files' imports.
  """

  alias Bizforge.ForgeMap.Scanner

  @type usage :: %{file: String.t(), symbols: [String.t()]}

  @spec resolve([Scanner.t()]) :: %{String.t() => [usage()]}
  def resolve(scanned_files) do
    export_index = build_export_index(scanned_files)

    Enum.reduce(scanned_files, %{}, fn file, acc ->
      usages =
        Enum.flat_map(file.imports, fn imp ->
          target_path = resolve_import_path(imp.from, file.path, export_index)

          if target_path !== nil do
            matched_symbols =
              case Map.get(export_index, target_path) do
                nil ->
                  []

                exported ->
                  cond do
                    imp.symbols === [] -> []
                    "*" in imp.symbols -> exported
                    true -> Enum.filter(imp.symbols, &(&1 in exported))
                  end
              end

            if matched_symbols !== [] do
              [{target_path, %{file: file.path, symbols: matched_symbols}}]
            else
              []
            end
          else
            []
          end
        end)

      Enum.reduce(usages, acc, fn {target, usage}, a ->
        Map.update(a, target, [usage], &[usage | &1])
      end)
    end)
  end

  defp build_export_index(files) do
    Map.new(files, fn f -> {f.path, f.exports} end)
  end

  defp resolve_import_path(from, _importer_path, export_index) do
    cond do
      Map.has_key?(export_index, from) ->
        from

      Map.has_key?(export_index, from <> ".ts") ->
        from <> ".ts"

      Map.has_key?(export_index, from <> ".tsx") ->
        from <> ".tsx"

      Map.has_key?(export_index, from <> ".js") ->
        from <> ".js"

      Map.has_key?(export_index, from <> "/index.ts") ->
        from <> "/index.ts"

      Map.has_key?(export_index, from <> "/index.js") ->
        from <> "/index.js"

      true ->
        stripped =
          from
          |> String.replace(~r/^[.\/]+/, "")
          |> String.replace(~r/^(src|lib)\//, "")

        Enum.find(Map.keys(export_index), fn key ->
          String.ends_with?(key, "/" <> stripped) or
            String.ends_with?(key, "/" <> stripped <> ".ts") or
            String.ends_with?(key, "/" <> stripped <> ".tsx") or
            String.ends_with?(key, "/" <> stripped <> ".js") or
            key === stripped
        end)
    end
  end
end
