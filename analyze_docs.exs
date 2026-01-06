#!/usr/bin/env elixir

# Script to analyze ex_doc coverage across all libraries

defmodule DocAnalyzer do
  @moduledoc """
  Analyzes documentation coverage in Elixir libraries.
  """

  def analyze_library(lib_path) do
    lib_name = Path.basename(lib_path)

    files = Path.wildcard("#{lib_path}/lib/**/*.ex")

    stats =
      Enum.reduce(
        files,
        %{
          total_modules: 0,
          modules_with_moduledoc: 0,
          total_functions: 0,
          functions_with_doc: 0,
          functions_with_examples: 0,
          functions_with_typespec: 0
        },
        fn file, acc ->
          analyze_file(file, acc)
        end
      )

    {lib_name, stats}
  end

  defp analyze_file(file, acc) do
    content = File.read!(file)

    # Count defmodule
    modules = Regex.scan(~r/defmodule\s+[\w\.]+\s+do/, content)

    # Count @moduledoc
    moduledocs =
      Regex.scan(~r/@moduledoc\s+(""".*?""")|(@moduledoc\s+"[^"]*")|(@moduledoc\s+false)/s, content)

    # Count public functions (def, not defp)
    functions = Regex.scan(~r/^\s+def\s+\w+/m, content)

    # Count @doc
    docs = Regex.scan(~r/@doc\s+(""".*?""")|(@doc\s+"[^"]*")|(@doc\s+false)/s, content)

    # Count @spec
    specs = Regex.scan(~r/@spec\s+\w+/m, content)

    # Count examples in docs (looking for ## Examples or iex>)
    examples = Regex.scan(~r/@doc.*?(##\s*Examples?|iex>)/s, content)

    %{
      total_modules: acc.total_modules + length(modules),
      modules_with_moduledoc: acc.modules_with_moduledoc + length(moduledocs),
      total_functions: acc.total_functions + length(functions),
      functions_with_doc: acc.functions_with_doc + length(docs),
      functions_with_examples: acc.functions_with_examples + length(examples),
      functions_with_typespec: acc.functions_with_typespec + length(specs)
    }
  end

  def format_coverage(lib_name, stats) do
    moduledoc_pct = percentage(stats.modules_with_moduledoc, stats.total_modules)
    doc_pct = percentage(stats.functions_with_doc, stats.total_functions)
    example_pct = percentage(stats.functions_with_examples, stats.total_functions)
    spec_pct = percentage(stats.functions_with_typespec, stats.total_functions)

    """
    #{String.pad_trailing(lib_name, 25)} | Modules: #{stats.modules_with_moduledoc}/#{stats.total_modules} (#{moduledoc_pct}%) | Funcs: #{stats.functions_with_doc}/#{stats.total_functions} (#{doc_pct}%) | Examples: #{stats.functions_with_examples} (#{example_pct}%) | Specs: #{stats.functions_with_typespec} (#{spec_pct}%)
    """
    |> String.trim()
  end

  defp percentage(_count, 0), do: 0
  defp percentage(count, total), do: round(count / total * 100)

  def analyze_all do
    libs =
      Path.wildcard("libs/*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.sort()

    IO.puts("\n" <> String.duplicate("=", 150))
    IO.puts("Documentation Coverage Analysis")
    IO.puts(String.duplicate("=", 150) <> "\n")

    results =
      Enum.map(libs, fn lib ->
        {lib_name, stats} = analyze_library(lib)
        {lib_name, stats, format_coverage(lib_name, stats)}
      end)

    # Print individual results
    Enum.each(results, fn {_name, _stats, formatted} ->
      IO.puts(formatted)
    end)

    # Calculate totals
    totals =
      Enum.reduce(
        results,
        %{
          total_modules: 0,
          modules_with_moduledoc: 0,
          total_functions: 0,
          functions_with_doc: 0,
          functions_with_examples: 0,
          functions_with_typespec: 0
        },
        fn {_name, stats, _formatted}, acc ->
          %{
            total_modules: acc.total_modules + stats.total_modules,
            modules_with_moduledoc: acc.modules_with_moduledoc + stats.modules_with_moduledoc,
            total_functions: acc.total_functions + stats.total_functions,
            functions_with_doc: acc.functions_with_doc + stats.functions_with_doc,
            functions_with_examples: acc.functions_with_examples + stats.functions_with_examples,
            functions_with_typespec: acc.functions_with_typespec + stats.functions_with_typespec
          }
        end
      )

    IO.puts("\n" <> String.duplicate("=", 150))
    IO.puts(format_coverage("TOTAL", totals))
    IO.puts(String.duplicate("=", 150) <> "\n")

    # Identify libraries needing improvement
    needs_improvement =
      Enum.filter(results, fn {_name, stats, _formatted} ->
        moduledoc_pct = percentage(stats.modules_with_moduledoc, stats.total_modules)
        doc_pct = percentage(stats.functions_with_doc, stats.total_functions)
        example_pct = percentage(stats.functions_with_examples, stats.total_functions)

        moduledoc_pct < 80 or doc_pct < 60 or example_pct < 30
      end)

    if length(needs_improvement) > 0 do
      IO.puts("\nLibraries needing documentation improvements:")
      IO.puts(String.duplicate("-", 150))

      Enum.each(needs_improvement, fn {name, stats, _} ->
        moduledoc_pct = percentage(stats.modules_with_moduledoc, stats.total_modules)
        doc_pct = percentage(stats.functions_with_doc, stats.total_functions)
        example_pct = percentage(stats.functions_with_examples, stats.total_functions)

        issues = []
        issues = if moduledoc_pct < 80, do: ["missing module docs" | issues], else: issues
        issues = if doc_pct < 60, do: ["missing function docs" | issues], else: issues
        issues = if example_pct < 30, do: ["needs more examples" | issues], else: issues

        IO.puts("  - #{name}: #{Enum.join(issues, ", ")}")
      end)

      IO.puts("")
    else
      IO.puts("\n✅ All libraries have excellent documentation coverage!\n")
    end
  end
end

DocAnalyzer.analyze_all()
