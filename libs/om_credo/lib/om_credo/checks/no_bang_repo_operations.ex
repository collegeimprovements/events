defmodule OmCredo.Checks.NoBangRepoOperations do
  @moduledoc ~S"""
  Checks that Repo operations don't use bang (!) versions in application code.

  This ensures proper error handling with result tuples.

  ## Why This Matters

  Bang operations raise exceptions on failure, which:
  - Bypasses result tuple error handling patterns
  - Makes error recovery difficult
  - Can crash processes unexpectedly

  ## Examples

  Incorrect (in non-bang functions):

      def get_user(id) do
        Repo.get!(User, id)  # Should use Repo.get
      end

  Correct:

      def get_user(id), do: Repo.get(User, id)

  ## Configuration

      {OmCredo.Checks.NoBangRepoOperations, [
        repo_modules: [[:Repo], [:MyApp, :Repo]],
        excluded_paths: ["/test/", "/priv/repo/seeds", "/priv/repo/migrations/"]
      ]}

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
    param_defaults: [
      repo_modules: [[:Repo]],
      excluded_paths: ["/test/", "/priv/repo/seeds", "/priv/repo/migrations/", "_test.exs"],
      included_paths: ["/lib/"]
    ],
    explanations: [
      check: """
      Avoid using bang (!) Repo operations in application code.

      Use non-bang versions and handle errors with result tuples:
      {:ok, record} | {:error, changeset}
      """,
      params: [
        repo_modules: "List of Repo module aliases to check (e.g., [[:Repo], [:MyApp, :Repo]])",
        excluded_paths: "List of path patterns to exclude",
        included_paths: "List of path patterns to include"
      ]
    ]

  @bang_operations ~w(insert! update! delete! get! get_by! one! all!)

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    excluded = Params.get(params, :excluded_paths, __MODULE__)
    included = Params.get(params, :included_paths, __MODULE__)

    if should_check?(source_file.filename, included, excluded) do
      issue_meta = IssueMeta.for(source_file, params)
      repo_modules = Params.get(params, :repo_modules, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta, repo_modules))
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

  defp traverse(
         {{:., meta, [{:__aliases__, _, repo_alias}, operation]}, _, _args} = ast,
         issues,
         issue_meta,
         repo_modules
       )
       when is_atom(operation) do
    op_string = Atom.to_string(operation)

    if repo_module?(repo_alias, repo_modules) and op_string in @bang_operations do
      issue = issue_for(issue_meta, meta[:line], op_string)
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _repo_modules), do: {ast, issues}

  defp repo_module?(alias, repo_modules) do
    Enum.any?(repo_modules, fn expected ->
      alias == expected or List.last(alias) == List.last(expected)
    end)
  end

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
