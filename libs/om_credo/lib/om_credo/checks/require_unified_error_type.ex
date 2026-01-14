defmodule OmCredo.Checks.RequireUnifiedErrorType do
  @moduledoc """
  Checks that error tuples use consistent, normalized error types.

  This ensures error handling is consistent across the codebase using
  the FnTypes.Error struct or structured error atoms/tuples.

  ## Why This Matters

  Consistent error types provide:
  - Predictable error handling patterns
  - Better error composition with FnTypes.Result
  - Structured error information for logging/monitoring
  - Clear error contracts in API boundaries

  ## What This Checks

  - Functions returning `{:error, reason}` where `reason` is a bare string
  - Inconsistent error atom naming (e.g., mixing `:not_found` and `:NotFound`)
  - Missing error context (bare atoms without details)

  ## Recommended Patterns

  Good:

      # Structured atoms
      {:error, :not_found}
      {:error, :unauthorized}

      # Atoms with context
      {:error, {:not_found, User, id}}
      {:error, {:validation_failed, field, reason}}

      # FnTypes.Error struct
      {:error, FnTypes.Error.new(:not_found, :user_not_found)}

      # Ecto changesets (handled by Normalizable protocol)
      {:error, changeset}

  Bad:

      # Bare strings (hard to pattern match)
      {:error, "User not found"}

      # Inconsistent casing
      {:error, :NotFound}  # Should be :not_found

      # Overly generic
      {:error, :error}
      {:error, :failed}

  ## Configuration

      {OmCredo.Checks.RequireUnifiedErrorType, [
        paths: ["/lib/myapp/"],
        excluded_paths: ["/lib/myapp/legacy/"],
        allowed_string_errors: false,
        warn_on_generic_atoms: true
      ]}
  """

  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      paths: [],
      excluded_paths: [],
      path_patterns: [],
      allowed_string_errors: false,
      warn_on_generic_atoms: true,
      generic_atoms: [:error, :failed, :failure, :invalid, :bad]
    ],
    explanations: [
      check: """
      Error tuples should use consistent, structured error types.
      Prefer atoms, tuples with context, or FnTypes.Error structs.
      """,
      params: [
        paths: "List of paths to check",
        excluded_paths: "List of paths to exclude",
        path_patterns: "List of filename patterns to check",
        allowed_string_errors: "Whether to allow bare string errors",
        warn_on_generic_atoms: "Warn on overly generic error atoms like :error, :failed",
        generic_atoms: "List of atoms considered too generic"
      ]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    paths = Params.get(params, :paths, __MODULE__)
    excluded = Params.get(params, :excluded_paths, __MODULE__)
    patterns = Params.get(params, :path_patterns, __MODULE__)

    if should_check?(source_file.filename, paths, excluded, patterns) do
      issue_meta = IssueMeta.for(source_file, params)
      allowed_strings = Params.get(params, :allowed_string_errors, __MODULE__)
      warn_generic = Params.get(params, :warn_on_generic_atoms, __MODULE__)
      generic_atoms = Params.get(params, :generic_atoms, __MODULE__)

      opts = %{
        allowed_strings: allowed_strings,
        warn_generic: warn_generic,
        generic_atoms: generic_atoms
      }

      source_file
      |> Credo.Code.prewalk(&collect_error_tuples(&1, &2, opts))
      |> generate_issues(issue_meta)
    else
      []
    end
  end

  defp should_check?(filename, paths, excluded, patterns) do
    not_excluded = Enum.empty?(excluded) or not Enum.any?(excluded, &String.contains?(filename, &1))
    path_match = Enum.empty?(paths) or Enum.any?(paths, &String.contains?(filename, &1))
    pattern_match = Enum.empty?(patterns) or Enum.any?(patterns, &String.contains?(filename, &1))

    not_excluded and path_match and pattern_match
  end

  # Match {:error, "string"} patterns
  defp collect_error_tuples(
         {:{}, meta, [:error, reason]} = ast,
         acc,
         opts
       )
       when is_binary(reason) do
    case opts.allowed_strings do
      true ->
        {ast, acc}

      false ->
        issue = %{
          type: :string_error,
          line: meta[:line],
          reason: reason,
          message: "Error tuple uses bare string: #{inspect(reason)}. Use an atom or FnTypes.Error instead."
        }
        {ast, [issue | acc]}
    end
  end

  # Match {:error, :atom} patterns - check for generic/inconsistent atoms
  defp collect_error_tuples(
         {:{}, meta, [:error, reason]} = ast,
         acc,
         opts
       )
       when is_atom(reason) do
    issues = check_error_atom(reason, meta, opts)
    {ast, issues ++ acc}
  end

  # Match two-tuple form: {:error, value}
  defp collect_error_tuples(
         {{:error, reason}, meta} = ast,
         acc,
         opts
       )
       when is_binary(reason) do
    case opts.allowed_strings do
      true ->
        {ast, acc}

      false ->
        issue = %{
          type: :string_error,
          line: meta[:line] || 0,
          reason: reason,
          message: "Error tuple uses bare string: #{inspect(reason)}. Use an atom or FnTypes.Error instead."
        }
        {ast, [issue | acc]}
    end
  end

  # Catch the most common pattern: {:error, reason} in return position
  defp collect_error_tuples(
         {:error, meta, [reason]} = ast,
         acc,
         opts
       )
       when is_binary(reason) do
    case opts.allowed_strings do
      true ->
        {ast, acc}

      false ->
        issue = %{
          type: :string_error,
          line: meta[:line] || 0,
          reason: reason,
          message: "Error tuple uses bare string: #{inspect(reason)}. Use an atom or FnTypes.Error instead."
        }
        {ast, [issue | acc]}
    end
  end

  defp collect_error_tuples(ast, acc, _opts), do: {ast, acc}

  defp check_error_atom(reason, meta, opts) do
    issues = []

    # Check for generic atoms
    issues =
      case opts.warn_generic and reason in opts.generic_atoms do
        true ->
          [%{
            type: :generic_atom,
            line: meta[:line],
            reason: reason,
            message: "Error atom :#{reason} is too generic. Use a more descriptive atom like :validation_failed or :not_found."
          } | issues]

        false ->
          issues
      end

    # Check for incorrect casing (should be snake_case)
    reason_string = Atom.to_string(reason)
    issues =
      cond do
        String.match?(reason_string, ~r/[A-Z]/) and not String.starts_with?(reason_string, "Elixir.") ->
          [%{
            type: :invalid_casing,
            line: meta[:line],
            reason: reason,
            message: "Error atom :#{reason} should use snake_case. Consider :#{to_snake_case(reason_string)} instead."
          } | issues]

        true ->
          issues
      end

    issues
  end

  defp to_snake_case(string) do
    string
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  defp generate_issues(issues, issue_meta) when is_list(issues) do
    issues
    |> Enum.uniq_by(fn issue -> {issue.line, issue.reason} end)
    |> Enum.map(fn issue ->
      format_issue(
        issue_meta,
        message: issue.message,
        trigger: inspect(issue.reason),
        line_no: issue.line
      )
    end)
  end

  defp generate_issues(_, _), do: []
end
