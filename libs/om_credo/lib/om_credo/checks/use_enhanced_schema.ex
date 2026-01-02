defmodule OmCredo.Checks.UseEnhancedSchema do
  @moduledoc """
  Checks that schemas use an enhanced Schema module instead of raw Ecto.Schema.

  This ensures consistency across the codebase and leverages enhanced schema features.

  ## Why This Matters

  Enhanced Schema modules typically provide:
  - UUIDv7 primary keys
  - Enhanced field validation
  - Field group macros (type_fields, status_fields, etc.)
  - Automatic changeset helpers

  ## Examples

  Incorrect:

      defmodule MyApp.User do
        use Ecto.Schema  # Should use enhanced schema
      end

  Correct:

      defmodule MyApp.User do
        use OmSchema  # or your configured enhanced module
      end

  ## Configuration

      {OmCredo.Checks.UseEnhancedSchema, [
        enhanced_module: OmSchema,
        raw_module: Ecto.Schema,
        included_paths: ["/lib/"],
        excluded_paths: ["/lib/myapp/schema"]
      ]}
  """

  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    param_defaults: [
      enhanced_module: OmSchema,
      raw_module: Ecto.Schema,
      included_paths: ["/lib/"],
      excluded_paths: []
    ],
    explanations: [
      check: """
      Always use the enhanced Schema module instead of raw Ecto.Schema.

      Enhanced schema modules provide additional features like UUIDv7 primary keys,
      field validation, and field group macros.
      """,
      params: [
        enhanced_module: "The enhanced schema module to use (e.g., OmSchema)",
        raw_module: "The raw module to detect and warn against (default: Ecto.Schema)",
        included_paths: "List of path patterns to check (default: [\"/lib/\"])",
        excluded_paths: "List of path patterns to exclude"
      ]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    included = Params.get(params, :included_paths, __MODULE__)
    excluded = Params.get(params, :excluded_paths, __MODULE__)

    if should_check?(source_file.filename, included, excluded) do
      issue_meta = IssueMeta.for(source_file, params)
      enhanced = Params.get(params, :enhanced_module, __MODULE__)
      raw_module = Params.get(params, :raw_module, __MODULE__)
      raw_parts = module_to_parts(raw_module)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta, enhanced, raw_parts))
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp should_check?(filename, included, excluded) do
    included_match = Enum.any?(included, &String.contains?(filename, &1))
    excluded_match = Enum.any?(excluded, &String.contains?(filename, &1))
    included_match and not excluded_match
  end

  defp module_to_parts(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  defp module_to_parts(parts) when is_list(parts), do: parts

  # Match: use Ecto.Schema (or configured raw module)
  defp traverse(
         {:use, meta, [{:__aliases__, _, alias_parts} | _rest]} = ast,
         issues,
         issue_meta,
         enhanced,
         raw_parts
       ) do
    if alias_parts == raw_parts do
      issue = issue_for(issue_meta, meta[:line], format_module(raw_parts), enhanced)
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _enhanced, _raw_parts), do: {ast, issues}

  defp format_module(parts) do
    parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
  end

  defp issue_for(issue_meta, line_no, trigger, enhanced) do
    enhanced_name =
      if is_atom(enhanced), do: inspect(enhanced), else: format_module(enhanced)

    format_issue(
      issue_meta,
      message: "Use `#{enhanced_name}` instead of `#{trigger}`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
