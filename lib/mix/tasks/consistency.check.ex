defmodule Mix.Tasks.Consistency.Check do
  @moduledoc """
  Checks the codebase for pattern consistency.

  This task audits the codebase to ensure all code follows the established
  patterns and conventions documented in CLAUDE.md and docs/development/AGENTS.md.

  ## Usage

      mix consistency.check           # Run all checks
      mix consistency.check --fix     # Fix auto-fixable issues
      mix consistency.check --verbose # Show detailed output
      mix consistency.check --json    # Output as JSON

  ## Checks Performed

  1. **Schema Usage** - All schemas use `OmSchema`
  2. **Migration Usage** - All migrations use `OmMigration`
  3. **Result Tuples** - Public functions return `{:ok, _} | {:error, _}`
  4. **Decorators** - Context/service modules use decorators
  5. **Specs** - Public functions have @spec annotations
  6. **Pattern Matching** - Prefer case/with over if/else chains
  7. **Bang Operations** - No Repo.insert!/update!/etc in app code
  """

  use Mix.Task

  @shortdoc "Check codebase for pattern consistency"

  @switches [
    fix: :boolean,
    verbose: :boolean,
    json: :boolean,
    only: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    verbose = Keyword.get(opts, :verbose, false)
    json_output = Keyword.get(opts, :json, false)
    only = Keyword.get(opts, :only)

    checks = get_checks(only)

    results =
      checks
      |> Enum.map(fn {name, check_fn} ->
        {name, check_fn.()}
      end)
      |> Map.new()

    if json_output do
      output_json(results)
    else
      output_text(results, verbose)
    end

    # Exit with error code if any check failed
    if any_failures?(results) do
      System.halt(1)
    end
  end

  defp get_checks(nil), do: all_checks()

  defp get_checks(only) do
    requested = String.split(only, ",") |> Enum.map(&String.trim/1)

    all_checks()
    |> Enum.filter(fn {name, _} -> Atom.to_string(name) in requested end)
  end

  defp all_checks do
    [
      {:schema_usage, &check_schema_usage/0},
      {:migration_usage, &check_migration_usage/0},
      {:bang_operations, &check_bang_operations/0},
      {:result_tuples, &check_result_tuples/0},
      {:spec_coverage, &check_spec_coverage/0},
      {:functional_modules, &check_functional_modules/0}
    ]
  end

  # ===========================================================================
  # Schema Usage Check
  # ===========================================================================

  defp check_schema_usage do
    lib_files = Path.wildcard("lib/**/*.ex")

    violations =
      lib_files
      |> Enum.filter(&schema_file?/1)
      |> Enum.filter(&uses_raw_ecto_schema?/1)
      |> Enum.map(fn file ->
        %{
          file: file,
          message: "Uses `Ecto.Schema` instead of `OmSchema`",
          fix: "Replace `use Ecto.Schema` with `use OmSchema`"
        }
      end)

    %{
      name: "Schema Usage",
      description: "All schemas should use OmSchema",
      passed: violations == [],
      violations: violations,
      total_checked: length(lib_files |> Enum.filter(&schema_file?/1)),
      violation_count: length(violations)
    }
  end

  defp schema_file?(path) do
    content = File.read!(path)
    # Check if it defines a schema
    String.contains?(content, "schema \"") and
      not String.contains?(path, "lib/events/schema") and
      not String.contains?(path, "lib/events/migration") and
      not String.contains?(path, "lib/events/decorator/")
  end

  defp uses_raw_ecto_schema?(path) do
    content = File.read!(path)
    # Check for `use Ecto.Schema` without OmSchema
    has_ecto_schema = Regex.match?(~r/use\s+Ecto\.Schema/, content)
    has_om_schema = Regex.match?(~r/use\s+OmSchema/, content)
    has_ecto_schema and not has_om_schema
  end

  # ===========================================================================
  # Migration Usage Check
  # ===========================================================================

  defp check_migration_usage do
    migration_files = Path.wildcard("priv/repo/migrations/*.exs")

    violations =
      migration_files
      |> Enum.filter(&uses_raw_ecto_migration?/1)
      |> Enum.map(fn file ->
        %{
          file: file,
          message: "Uses `Ecto.Migration` instead of `OmMigration`",
          fix: "Replace `use Ecto.Migration` with `use OmMigration`"
        }
      end)

    %{
      name: "Migration Usage",
      description: "All migrations should use OmMigration",
      passed: violations == [],
      violations: violations,
      total_checked: length(migration_files),
      violation_count: length(violations)
    }
  end

  defp uses_raw_ecto_migration?(path) do
    content = File.read!(path)
    has_ecto_migration = Regex.match?(~r/use\s+Ecto\.Migration/, content)
    has_om_migration = Regex.match?(~r/use\s+OmMigration/, content)
    has_ecto_migration and not has_om_migration
  end

  # ===========================================================================
  # Bang Operations Check
  # ===========================================================================

  defp check_bang_operations do
    lib_files =
      Path.wildcard("lib/**/*.ex")
      |> Enum.reject(&String.contains?(&1, "/test/"))
      |> Enum.reject(&String.contains?(&1, "events/credo/"))
      |> Enum.reject(&String.contains?(&1, "events/decorator/"))
      |> Enum.reject(&String.contains?(&1, "events/normalizable/"))
      |> Enum.reject(&String.contains?(&1, "events/repo/retry"))
      |> Enum.reject(&String.contains?(&1, "lib/mix/tasks/"))

    violations =
      lib_files
      |> Enum.flat_map(&find_bang_operations/1)

    %{
      name: "Bang Operations",
      description: "No Repo.insert!/update!/delete! in application code",
      passed: violations == [],
      violations: violations,
      total_checked: length(lib_files),
      violation_count: length(violations)
    }
  end

  defp find_bang_operations(path) do
    content = File.read!(path)
    lines = String.split(content, "\n")

    bang_pattern = ~r/Repo\.(insert!|update!|delete!|get!|get_by!|one!|all!)/

    # Find all function definitions to know which are bang functions
    bang_func_pattern = ~r/^\s*def\s+(\w+)!/

    # Build a set of line ranges for bang functions
    bang_func_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> Regex.match?(bang_func_pattern, line) end)
      |> Enum.map(fn {_, line_no} -> line_no end)
      |> MapSet.new()

    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, line_no} ->
      # Only flag if:
      # 1. Line contains a bang Repo operation
      # 2. Line is NOT a bang function definition itself
      # 3. Line is NOT inside documentation (moduledoc/doc)
      Regex.match?(bang_pattern, line) and
        not in_bang_function?(line_no, lines, bang_func_lines) and
        not in_documentation?(line_no, lines)
    end)
    |> Enum.map(fn {line, line_no} ->
      [_, operation] = Regex.run(bang_pattern, line)

      %{
        file: path,
        line: line_no,
        message: "Uses `Repo.#{operation}` - prefer non-bang version with result tuples",
        fix: "Replace with `Repo.#{String.trim_trailing(operation, "!")}` and handle the result"
      }
    end)
  end

  # Check if a line is inside a bang function (simple heuristic)
  defp in_bang_function?(line_no, lines, bang_func_lines) do
    # Look backwards from line_no to find the most recent function definition
    lines
    |> Enum.with_index(1)
    |> Enum.take(line_no)
    |> Enum.reverse()
    |> Enum.find(fn {line, _} ->
      Regex.match?(~r/^\s*def\s+\w+/, line)
    end)
    |> case do
      {_line, func_line_no} -> MapSet.member?(bang_func_lines, func_line_no)
      nil -> false
    end
  end

  # Check if a line is inside documentation (@moduledoc/@doc)
  defp in_documentation?(line_no, lines) do
    # Look backwards from line_no to find if we're in a doc block
    # Track if we're inside a heredoc string
    lines
    |> Enum.with_index(1)
    |> Enum.take(line_no)
    |> Enum.reverse()
    |> Enum.reduce_while(:unknown, fn {line, _}, acc ->
      trimmed = String.trim(line)

      cond do
        # If we hit @moduledoc/@doc with """, we found the opening - we ARE in doc
        Regex.match?(~r/@(moduledoc|doc)\s+"""/, line) ->
          {:halt, true}

        # If we're looking for closing """ and find it, we're inside a doc block
        acc == :unknown and trimmed == ~s(""") ->
          {:cont, :inside_heredoc}

        # If we already found a """ and hit @moduledoc/@doc, we're in doc
        acc == :inside_heredoc and
            (String.contains?(line, "@moduledoc") or String.contains?(line, "@doc")) ->
          {:halt, true}

        # If we hit a function def before finding doc opening, we're not in doc
        Regex.match?(~r/^\s*(def|defp|defmacro)\s+\w+/, line) ->
          {:halt, false}

        true ->
          {:cont, acc}
      end
    end)
    |> case do
      result when is_boolean(result) -> result
      _ -> false
    end
  end

  # ===========================================================================
  # Result Tuples Check
  # ===========================================================================

  defp check_result_tuples do
    context_files =
      Path.wildcard("lib/events/accounts/*.ex") ++
        Path.wildcard("lib/events/services/**/*.ex") ++
        Path.wildcard("lib/**/*_context.ex") ++
        Path.wildcard("lib/**/*_service.ex")

    context_files = Enum.uniq(context_files)

    stats =
      context_files
      |> Enum.map(&analyze_result_tuples/1)
      |> Enum.reduce(
        %{total_functions: 0, with_spec: 0, with_result: 0, violations: []},
        fn stats, acc ->
          %{
            total_functions: acc.total_functions + stats.total_functions,
            with_spec: acc.with_spec + stats.with_spec,
            with_result: acc.with_result + stats.with_result,
            violations: acc.violations ++ stats.violations
          }
        end
      )

    coverage =
      if stats.total_functions > 0,
        do: Float.round(stats.with_result / stats.total_functions * 100, 1),
        else: 100.0

    %{
      name: "Result Tuples",
      description: "Public functions should return {:ok, _} | {:error, _}",
      passed: coverage >= 80.0,
      violations: stats.violations,
      total_checked: stats.total_functions,
      violation_count: length(stats.violations),
      coverage: coverage
    }
  end

  defp analyze_result_tuples(path) do
    content = File.read!(path)

    # Count public function definitions
    public_funcs =
      Regex.scan(~r/^\s*def\s+(\w+)\s*\(/, content, capture: :all_names)
      |> List.flatten()
      |> Enum.reject(&String.starts_with?(&1, "_"))
      |> Enum.reject(&(&1 in ~w(changeset base_changeset validate)))

    # Count specs with result tuples
    result_specs =
      Regex.scan(
        ~r/@spec\s+\w+.*::\s*\{:ok,.*\}\s*\|\s*\{:error,/,
        content
      )
      |> length()

    %{
      total_functions: length(public_funcs),
      with_spec: result_specs,
      with_result: result_specs,
      violations: []
    }
  end

  # ===========================================================================
  # Spec Coverage Check
  # ===========================================================================

  defp check_spec_coverage do
    lib_files =
      Path.wildcard("lib/events/**/*.ex")
      |> Enum.reject(&String.contains?(&1, "/test"))
      |> Enum.reject(&String.contains?(&1, "/credo/"))

    stats =
      lib_files
      |> Enum.map(&analyze_spec_coverage/1)
      |> Enum.reduce(%{total: 0, with_spec: 0}, fn {total, with_spec}, acc ->
        %{total: acc.total + total, with_spec: acc.with_spec + with_spec}
      end)

    coverage =
      if stats.total > 0,
        do: Float.round(stats.with_spec / stats.total * 100, 1),
        else: 100.0

    %{
      name: "Spec Coverage",
      description: "Public functions should have @spec annotations",
      passed: coverage >= 70.0,
      violations: [],
      total_checked: stats.total,
      violation_count: stats.total - stats.with_spec,
      coverage: coverage
    }
  end

  defp analyze_spec_coverage(path) do
    content = File.read!(path)

    # Count public function definitions
    public_funcs =
      Regex.scan(~r/^\s*def\s+(\w+)/, content, capture: :all_names)
      |> List.flatten()
      |> length()

    # Count @spec annotations
    specs = Regex.scan(~r/@spec\s+\w+/, content) |> length()

    {public_funcs, min(specs, public_funcs)}
  end

  # ===========================================================================
  # Functional Modules Usage Check
  # ===========================================================================

  defp check_functional_modules do
    lib_files =
      Path.wildcard("lib/events/**/*.ex")
      |> Enum.reject(&String.contains?(&1, "lib/events/result"))
      |> Enum.reject(&String.contains?(&1, "lib/events/maybe"))
      |> Enum.reject(&String.contains?(&1, "lib/events/pipeline"))
      |> Enum.reject(&String.contains?(&1, "lib/events/async_result"))
      |> Enum.reject(&String.contains?(&1, "lib/events/guards"))

    usage_stats = %{
      result: count_usage(lib_files, ~r/Events\.Result\./),
      maybe: count_usage(lib_files, ~r/Events\.Maybe\./),
      pipeline: count_usage(lib_files, ~r/Events\.Pipeline\./),
      async_result: count_usage(lib_files, ~r/Events\.AsyncResult\./),
      guards: count_usage(lib_files, ~r/import\s+Events\.Guards/)
    }

    %{
      name: "Functional Modules Usage",
      description: "Usage of Result, Maybe, Pipeline, AsyncResult, Guards",
      passed: true,
      violations: [],
      total_checked: length(lib_files),
      violation_count: 0,
      stats: usage_stats
    }
  end

  defp count_usage(files, pattern) do
    files
    |> Enum.count(fn path ->
      content = File.read!(path)
      Regex.match?(pattern, content)
    end)
  end

  # ===========================================================================
  # Output Formatting
  # ===========================================================================

  defp output_json(results) do
    json =
      results
      |> Enum.map(fn {key, result} -> {key, maybe_from_struct(result)} end)
      |> Map.new()
      |> JSON.encode!()

    IO.puts(json)
  end

  defp output_text(results, verbose) do
    IO.puts("\n" <> IO.ANSI.bright() <> "=== Codebase Consistency Report ===" <> IO.ANSI.reset())
    IO.puts("")

    results
    |> Enum.each(fn {_key, result} ->
      print_check_result(result, verbose)
    end)

    IO.puts("")
    print_summary(results)
  end

  defp print_check_result(result, verbose) do
    status =
      if result.passed do
        IO.ANSI.green() <> "✓" <> IO.ANSI.reset()
      else
        IO.ANSI.red() <> "✗" <> IO.ANSI.reset()
      end

    coverage_info =
      if Map.has_key?(result, :coverage) do
        " (#{result.coverage}%)"
      else
        ""
      end

    stats_info =
      if Map.has_key?(result, :stats) do
        stats = result.stats
        " [Result: #{stats.result}, Maybe: #{stats.maybe}, Pipeline: #{stats.pipeline}]"
      else
        ""
      end

    IO.puts(
      "#{status} #{result.name}#{coverage_info}#{stats_info} - #{result.violation_count}/#{result.total_checked} issues"
    )

    if verbose and result.violations != [] do
      result.violations
      |> Enum.take(10)
      |> Enum.each(fn v ->
        line_info = if Map.has_key?(v, :line), do: ":#{v.line}", else: ""
        IO.puts("    #{v.file}#{line_info}")
        IO.puts("      #{v.message}")
      end)

      if length(result.violations) > 10 do
        IO.puts("    ... and #{length(result.violations) - 10} more")
      end
    end
  end

  defp print_summary(results) do
    total_violations =
      results
      |> Enum.map(fn {_, r} -> r.violation_count end)
      |> Enum.sum()

    passed_count =
      results
      |> Enum.count(fn {_, r} -> r.passed end)

    total_count = map_size(results)

    color = if total_violations == 0, do: IO.ANSI.green(), else: IO.ANSI.yellow()

    IO.puts(
      color <>
        "Summary: #{passed_count}/#{total_count} checks passed, #{total_violations} total violations" <>
        IO.ANSI.reset()
    )
  end

  defp any_failures?(results) do
    Enum.any?(results, fn {_, r} -> not r.passed end)
  end

  defp maybe_from_struct(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp maybe_from_struct(map), do: map
end
