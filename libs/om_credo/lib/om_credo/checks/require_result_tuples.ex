defmodule OmCredo.Checks.RequireResultTuples do
  @moduledoc """
  Checks that public functions in context/service modules return result tuples.

  This ensures consistent error handling across the codebase.

  ## Why This Matters

  Result tuples (`{:ok, value} | {:error, reason}`) provide:
  - Explicit error handling
  - Composable operations with `with` statements
  - Clear function contracts
  - Better debugging

  ## What This Checks

  Public functions (not starting with `_`) in configured paths
  should have @spec annotations with result tuple returns.

  ## Examples

  Incorrect:

      def get_user(id) do
        Repo.get(User, id)
      end

  Correct:

      @spec get_user(binary()) :: {:ok, User.t()} | {:error, :not_found}
      def get_user(id) do
        case Repo.get(User, id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end
      end

  ## Configuration

      {OmCredo.Checks.RequireResultTuples, [
        paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"],
        path_patterns: ["_context.ex", "_service.ex"],
        excluded_functions: [:changeset, :validate]
      ]}
  """

  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      paths: [],
      path_patterns: ["_context.ex", "_service.ex"],
      excluded_functions: [:changeset, :base_changeset, :validate, :apply_validations],
      excluded_prefixes: ["_", "handle_"]
    ],
    explanations: [
      check: """
      Public functions in context/service modules should return result tuples
      and have @spec annotations declaring the return type.
      """,
      params: [
        paths: "List of paths to check (e.g., [\"/lib/myapp/contexts/\"])",
        path_patterns: "List of filename patterns to check (e.g., [\"_context.ex\"])",
        excluded_functions: "List of function names to exclude",
        excluded_prefixes: "List of function name prefixes to exclude"
      ]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    paths = Params.get(params, :paths, __MODULE__)
    patterns = Params.get(params, :path_patterns, __MODULE__)

    if should_check?(source_file.filename, paths, patterns) do
      issue_meta = IssueMeta.for(source_file, params)
      excluded_fns = Params.get(params, :excluded_functions, __MODULE__)
      excluded_prefixes = Params.get(params, :excluded_prefixes, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&collect_specs_and_defs(&1, &2, excluded_fns, excluded_prefixes))
      |> check_for_issues(issue_meta)
    else
      []
    end
  end

  defp should_check?(filename, paths, patterns) do
    path_match = Enum.empty?(paths) or Enum.any?(paths, &String.contains?(filename, &1))
    pattern_match = Enum.any?(patterns, &String.contains?(filename, &1))
    path_match and pattern_match
  end

  defp collect_specs_and_defs(
         {:@, _, [{:spec, _, [{:"::", _, [{name, _, args}, _return]}]}]} = ast,
         acc,
         _excluded_fns,
         _excluded_prefixes
       )
       when is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {ast, Map.update(acc, :specs, [{name, arity}], &[{name, arity} | &1])}
  end

  defp collect_specs_and_defs(
         {:def, meta, [{name, _, args} | _]} = ast,
         acc,
         excluded_fns,
         excluded_prefixes
       )
       when is_atom(name) do
    name_string = Atom.to_string(name)

    excluded_by_name = name in excluded_fns
    excluded_by_prefix = Enum.any?(excluded_prefixes, &String.starts_with?(name_string, &1))

    if not excluded_by_name and not excluded_by_prefix do
      arity = if is_list(args), do: length(args), else: 0

      func_info = %{
        name: name,
        arity: arity,
        line: meta[:line]
      }

      {ast, Map.update(acc, :defs, [func_info], &[func_info | &1])}
    else
      {ast, acc}
    end
  end

  defp collect_specs_and_defs(ast, acc, _excluded_fns, _excluded_prefixes), do: {ast, acc}

  defp check_for_issues(%{specs: specs, defs: defs}, issue_meta) do
    spec_set = MapSet.new(specs)

    defs
    |> Enum.reject(fn %{name: name, arity: arity} ->
      MapSet.member?(spec_set, {name, arity})
    end)
    |> Enum.map(fn %{name: name, arity: arity, line: line} ->
      format_issue(
        issue_meta,
        message:
          "Public function `#{name}/#{arity}` should have an @spec with result tuple return type.",
        trigger: "#{name}/#{arity}",
        line_no: line
      )
    end)
  end

  defp check_for_issues(_, _), do: []
end
