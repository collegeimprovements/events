defmodule Events.Credo.Checks.UseEventsMigration do
  @moduledoc """
  Checks that all migrations use `Events.Migration` instead of raw `Ecto.Migration`.

  This ensures consistency across the codebase and leverages our enhanced migration features.

  ## Why This Matters

  `Events.Migration` provides:
  - Pipeline-based table creation
  - Standard field builders (with_uuid_primary_key, with_audit, etc.)
  - DSL-enhanced macros for common patterns
  - Consistent index and constraint creation

  ## Examples

  Incorrect:

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration  # Bad - use Events.Migration instead
      end

  Correct:

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Events.Migration
      end
  """

  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: """
      Always use `Events.Migration` instead of `Ecto.Migration` in migration files.

      Events.Migration wraps Ecto.Migration and provides pipeline-based table
      creation with standard field builders for common patterns.
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    # Only check migration files
    if should_check?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp should_check?(filename) do
    String.contains?(filename, "/priv/repo/migrations/") and
      String.ends_with?(filename, ".exs")
  end

  # Match: use Ecto.Migration
  defp traverse(
         {:use, meta, [{:__aliases__, _, [:Ecto, :Migration]} | _]} = ast,
         issues,
         issue_meta
       ) do
    issue = issue_for(issue_meta, meta[:line], "Ecto.Migration")
    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message: "Use `Events.Migration` instead of `Ecto.Migration` for consistency.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
