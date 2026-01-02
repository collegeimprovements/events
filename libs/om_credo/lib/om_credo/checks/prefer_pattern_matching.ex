defmodule OmCredo.Checks.PreferPatternMatching do
  @moduledoc """
  Checks for if/else chains that could be replaced with pattern matching.

  This encourages idiomatic Elixir code that uses pattern matching over conditionals.

  ## Why This Matters

  Pattern matching:
  - Is more declarative and readable
  - Leverages Elixir's core strength
  - Enables exhaustiveness checking
  - Reduces nested conditionals

  ## Examples

  Discouraged:

      def process(result) do
        if elem(result, 0) == :ok do
          elem(result, 1)
        else
          {:error, :failed}
        end
      end

  Preferred:

      def process({:ok, value}), do: value
      def process({:error, _}), do: {:error, :failed}

  Or:

      def process(result) do
        case result do
          {:ok, value} -> value
          {:error, _} -> {:error, :failed}
        end
      end

  ## Configuration

      {OmCredo.Checks.PreferPatternMatching, []}

  ## Exceptions

  Simple boolean checks are acceptable:

      if enabled?, do: run(), else: skip()
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      paths: ["/lib/"]
    ],
    explanations: [
      check: """
      Consider using pattern matching (case, function clauses) instead of if/else
      when checking tuple structure or complex conditions.
      """,
      params: [
        paths: "List of path patterns to check (default: [\"/lib/\"])"
      ]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    paths = Params.get(params, :paths, __MODULE__)

    if should_check?(source_file.filename, paths) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp should_check?(filename, paths) do
    Enum.any?(paths, &String.contains?(filename, &1))
  end

  defp traverse({:if, meta, [condition | rest]} = ast, issues, issue_meta) do
    cond do
      has_elem_check?(condition) ->
        issue =
          format_issue(
            issue_meta,
            message: "Consider using `case` or pattern matching instead of `if` with `elem()`.",
            trigger: "if",
            line_no: meta[:line]
          )

        {ast, [issue | issues]}

      has_nested_if?(rest) ->
        issue =
          format_issue(
            issue_meta,
            message: "Nested if/else detected. Consider using `case`, `cond`, or pattern matching.",
            trigger: "if",
            line_no: meta[:line],
            priority: :low
          )

        {ast, [issue | issues]}

      true ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp has_nested_if?([[do: _, else: {:if, _, _}]]), do: true
  defp has_nested_if?(_), do: false

  defp has_elem_check?({:==, _, [{:elem, _, _}, _]}), do: true
  defp has_elem_check?({:==, _, [_, {:elem, _, _}]}), do: true
  defp has_elem_check?({:and, _, [left, right]}), do: has_elem_check?(left) or has_elem_check?(right)
  defp has_elem_check?({:or, _, [left, right]}), do: has_elem_check?(left) or has_elem_check?(right)
  defp has_elem_check?(_), do: false
end
