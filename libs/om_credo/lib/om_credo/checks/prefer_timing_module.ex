defmodule OmCredo.Checks.PreferTimingModule do
  @moduledoc """
  Suggests using `FnTypes.Timing` instead of manual timing with `System.monotonic_time()`.

  ## Why This Matters

  Manual timing with `System.monotonic_time()` has several drawbacks:
  - Units are unclear (native time units, not milliseconds/seconds)
  - No automatic unit conversion
  - Lost timing information when exceptions occur
  - Verbose and repetitive
  - Hard to test

  `FnTypes.Timing` provides:
  - Clear duration units (ms, μs, seconds, native)
  - Exception-safe timing with `measure_safe/1`
  - Human-readable formatting with `format/1`
  - Built-in benchmarking and statistics
  - Composable with telemetry

  ## Examples

  ### Incorrect

  ```elixir
  start = System.monotonic_time()
  result = expensive_operation()
  duration = System.monotonic_time() - start
  Logger.info("Took \#{duration}ns")  # Unclear units
  ```

  ### Correct

  ```elixir
  alias FnTypes.Timing

  {result, duration} = Timing.measure(fn -> expensive_operation() end)
  Logger.info("Took \#{duration.ms}ms")  # Clear units
  ```

  ### Incorrect - Lost timing on exception

  ```elixir
  start = System.monotonic_time()
  result = risky_operation()  # If this raises, timing is lost
  duration = System.monotonic_time() - start
  ```

  ### Correct - Exception-safe

  ```elixir
  case Timing.measure_safe(fn -> risky_operation() end) do
    {:ok, result, duration} -> ...
    {:error, kind, reason, stacktrace, duration} -> # Duration still captured
  end
  ```

  ## Configuration

  ```elixir
  {OmCredo.Checks.PreferTimingModule, [
    exclude_patterns: ["telemetry.ex", "timing.ex"],
    exclude_paths: ["/test/"]
  ]}
  ```

  ## Params

  - `exclude_patterns` - List of filename patterns to exclude (default: ["telemetry.ex", "timing.ex"])
  - `exclude_paths` - List of paths to exclude (default: ["/test/"])
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [
      exclude_patterns: ["telemetry.ex", "timing.ex", "timing_test.exs"],
      exclude_paths: ["/test/"]
    ],
    explanations: [
      check: """
      Manual timing with System.monotonic_time() should be replaced with
      FnTypes.Timing for better clarity, exception safety, and unit conversion.
      """,
      params: [
        exclude_patterns: "List of filename patterns to exclude from this check",
        exclude_paths: "List of paths to exclude from this check"
      ]
    ]

  alias Credo.Check.Params

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    exclude_patterns = Params.get(params, :exclude_patterns, __MODULE__)
    exclude_paths = Params.get(params, :exclude_paths, __MODULE__)

    if should_check?(source_file.filename, exclude_patterns, exclude_paths) do
      issue_meta = IssueMeta.for(source_file, params)

      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp should_check?(filename, exclude_patterns, exclude_paths) do
    not excluded_by_pattern?(filename, exclude_patterns) and
      not excluded_by_path?(filename, exclude_paths)
  end

  defp excluded_by_pattern?(filename, patterns) do
    Enum.any?(patterns, fn pattern ->
      String.contains?(filename, pattern)
    end)
  end

  defp excluded_by_path?(filename, paths) do
    Enum.any?(paths, fn path ->
      String.contains?(filename, path)
    end)
  end

  # Detect: start = System.monotonic_time()
  # Followed later by: duration = System.monotonic_time() - start
  defp traverse(
         {:=, _meta,
          [
            {var_name, _var_meta, nil},
            {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:System]}, :monotonic_time]}, _, []}
          ]} = ast,
         acc,
         _issue_meta
       )
       when is_atom(var_name) do
    # Found a variable assignment from System.monotonic_time()
    # Track this variable as potentially being a timing start
    new_acc = Map.put(acc, :timing_vars, Map.put(Map.get(acc, :timing_vars, %{}), var_name, true))
    {ast, new_acc}
  end

  # Detect: System.monotonic_time() - var_name
  # This is the duration calculation pattern
  defp traverse(
         {:-, meta,
          [
            {{:., _, [{:__aliases__, _, [:System]}, :monotonic_time]}, _, []},
            {var_name, _, nil}
          ]} = ast,
         acc,
         issue_meta
       )
       when is_atom(var_name) do
    timing_vars = Map.get(acc, :timing_vars, %{})

    issues =
      if Map.get(timing_vars, var_name, false) do
        [
          format_issue(
            issue_meta,
            message:
              "Consider using `FnTypes.Timing.measure/1` instead of manual timing with System.monotonic_time(). " <>
                "See: https://hexdocs.pm/fn_types/FnTypes.Timing.html",
            trigger: "System.monotonic_time()",
            line_no: meta[:line]
          )
        ]
      else
        []
      end

    {ast, Map.put(acc, :issues, Map.get(acc, :issues, []) ++ issues)}
  end

  # Also detect the reverse pattern: var_name - System.monotonic_time()
  # (Less common but possible)
  defp traverse(
         {:-, meta,
          [
            {var_name, _, nil},
            {{:., _, [{:__aliases__, _, [:System]}, :monotonic_time]}, _, []}
          ]} = ast,
         acc,
         issue_meta
       )
       when is_atom(var_name) do
    timing_vars = Map.get(acc, :timing_vars, %{})

    issues =
      if Map.get(timing_vars, var_name, false) do
        [
          format_issue(
            issue_meta,
            message:
              "Consider using `FnTypes.Timing.measure/1` instead of manual timing with System.monotonic_time(). " <>
                "See: https://hexdocs.pm/fn_types/FnTypes.Timing.html",
            trigger: "System.monotonic_time()",
            line_no: meta[:line]
          )
        ]
      else
        []
      end

    {ast, Map.put(acc, :issues, Map.get(acc, :issues, []) ++ issues)}
  end

  # Pass through other AST nodes
  defp traverse(ast, acc, _issue_meta) do
    {ast, acc}
  end
end
