defmodule Events.Support.Credo.Checks.UseOmSchema do
  @moduledoc """
  Checks that all schemas in the lib/ directory use `OmSchema` instead of raw `Ecto.Schema`.

  This ensures consistency across the codebase and leverages our enhanced schema features.

  ## Why This Matters

  `OmSchema` provides:
  - UUIDv7 primary keys
  - Enhanced field validation
  - Field group macros (type_fields, status_fields, etc.)
  - Automatic changeset helpers

  Events defaults are configured in config/config.exs.

  ## Examples

  Incorrect:

      defmodule MyApp.User do
        use Ecto.Schema  # Bad - use OmSchema instead
      end

  Correct:

      defmodule MyApp.User do
        use OmSchema
      end
  """

  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: """
      Always use `OmSchema` instead of `Ecto.Schema` in lib/ files.

      OmSchema provides additional features like UUIDv7 primary keys, field validation,
      and field group macros. Events defaults are configured in config/config.exs.
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    # Only check files in lib/events/ directory (not deps, test, etc.)
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
    # Check files in lib/ but exclude the schema module itself and infrastructure
    cond do
      String.contains?(filename, "/lib/events/schema") -> false
      String.contains?(filename, "/lib/events/migration") -> false
      String.contains?(filename, "/lib/events/credo/") -> false
      String.contains?(filename, "/lib/events/decorator/") -> false
      String.contains?(filename, "/lib/") -> true
      true -> false
    end
  end

  # Match: use Ecto.Schema (with or without opts)
  defp traverse(
         {:use, meta, [{:__aliases__, _, [:Ecto, :Schema]} | _rest]} = ast,
         issues,
         issue_meta
       ) do
    issue = issue_for(issue_meta, meta[:line], "Ecto.Schema")
    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message: "Use `OmSchema` instead of `Ecto.Schema`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
