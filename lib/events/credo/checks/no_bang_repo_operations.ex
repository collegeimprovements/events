defmodule Events.Credo.Checks.NoBangRepoOperations do
  @moduledoc ~S"""
  Checks that Repo operations don't use bang (!) versions in application code.

  This ensures proper error handling with result tuples.

  ## Why This Matters

  Bang operations raise exceptions on failure, which:
  - Bypasses our result tuple error handling pattern
  - Makes error recovery difficult
  - Can crash processes unexpectedly

  ## Examples

  Incorrect (in non-bang functions):

      def get_user(id) do
        Repo.get_bang(User, id)  # Should use Repo.get
      end

  Correct:

      def get_user(id), do: Repo.get(User, id)

  ## Exceptions

  Bang operations are acceptable in:
  - Test files
  - Seed files
  - Migration files
  - Scripts
  - Functions that are themselves bang functions (e.g., `get_user!`)
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Avoid using bang (!) Repo operations in application code.

      Use non-bang versions and handle errors with result tuples:
      {:ok, record} | {:error, changeset}
      """
    ]

  @bang_operations ~w(insert! update! delete! get! get_by! one! all!)

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
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
    cond do
      String.contains?(filename, "/test/") -> false
      String.contains?(filename, "/priv/repo/seeds") -> false
      String.contains?(filename, "/priv/repo/migrations/") -> false
      String.contains?(filename, "_test.exs") -> false
      String.contains?(filename, "/lib/events/credo/") -> false
      String.contains?(filename, "/lib/") -> true
      true -> false
    end
  end

  # Match: Repo.insert!(...), Events.Repo.insert!(...), etc.
  defp traverse(
         {{:., meta, [{:__aliases__, _, repo_alias}, operation]}, _, _args} = ast,
         issues,
         issue_meta
       )
       when is_atom(operation) do
    op_string = Atom.to_string(operation)

    if repo_module?(repo_alias) and op_string in @bang_operations do
      issue = issue_for(issue_meta, meta[:line], op_string)
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp repo_module?([:Repo]), do: true
  defp repo_module?([:Events, :Repo]), do: true
  defp repo_module?(_), do: false

  defp issue_for(issue_meta, line_no, trigger) do
    non_bang = String.trim_trailing(trigger, "!")

    format_issue(
      issue_meta,
      message: "Use `Repo.#{non_bang}` instead of `Repo.#{trigger}` and handle the result tuple.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
