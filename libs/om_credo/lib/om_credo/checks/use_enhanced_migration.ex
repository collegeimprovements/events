defmodule OmCredo.Checks.UseEnhancedMigration do
  @moduledoc """
  Checks that migrations use an enhanced Migration module instead of raw Ecto.Migration.

  This ensures consistency across the codebase and leverages enhanced migration features.

  ## Why This Matters

  Enhanced Migration modules typically provide:
  - Pipeline-based table creation
  - Standard field builders (with_uuid_primary_key, with_audit, etc.)
  - DSL-enhanced macros for common patterns
  - Consistent index and constraint creation

  ## Examples

  Incorrect:

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration  # Should use enhanced migration
      end

  Correct:

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use OmMigration  # or your configured enhanced module
      end

  ## Configuration

      {OmCredo.Checks.UseEnhancedMigration, [
        enhanced_module: OmMigration,
        raw_module: Ecto.Migration,
        migration_paths: ["/priv/repo/migrations/"]
      ]}
  """

  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    param_defaults: [
      enhanced_module: OmMigration,
      raw_module: Ecto.Migration,
      migration_paths: ["/priv/repo/migrations/"]
    ],
    explanations: [
      check: """
      Always use the enhanced Migration module instead of raw Ecto.Migration.

      Enhanced migration modules provide pipeline-based table creation with
      standard field builders for common patterns.
      """,
      params: [
        enhanced_module: "The enhanced migration module to use (e.g., OmMigration)",
        raw_module: "The raw module to detect and warn against (default: Ecto.Migration)",
        migration_paths: "List of migration path patterns to check"
      ]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    migration_paths = Params.get(params, :migration_paths, __MODULE__)

    if should_check?(source_file.filename, migration_paths) do
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

  defp should_check?(filename, migration_paths) do
    Enum.any?(migration_paths, &String.contains?(filename, &1)) and
      String.ends_with?(filename, ".exs")
  end

  defp module_to_parts(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  defp module_to_parts(parts) when is_list(parts), do: parts

  # Match: use Ecto.Migration (or configured raw module)
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
      message: "Use `#{enhanced_name}` instead of `#{trigger}` for consistency.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
