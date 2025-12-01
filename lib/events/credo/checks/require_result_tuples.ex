defmodule Events.Credo.Checks.RequireResultTuples do
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

  Public functions (not starting with `_`) in modules under:
  - `lib/events/accounts/`
  - `lib/events/services/`
  - Any module with `Context` or `Service` in the name

  Should have @spec annotations with result tuple returns.

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
  """

  use Credo.Check,
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Public functions in context/service modules should return result tuples
      and have @spec annotations declaring the return type.
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if should_check?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_specs_and_defs(&1, &2))
      |> check_for_issues(issue_meta, source_file)
    else
      []
    end
  end

  defp should_check?(filename) do
    cond do
      String.contains?(filename, "/lib/events/accounts/") -> true
      String.contains?(filename, "/lib/events/services/") -> true
      String.contains?(filename, "_context.ex") -> true
      String.contains?(filename, "_service.ex") -> true
      true -> false
    end
  end

  # Collect @spec definitions
  defp collect_specs_and_defs(
         {:@, _, [{:spec, _, [{:"::", _, [{name, _, args}, _return]}]}]} = ast,
         acc
       )
       when is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {ast, Map.update(acc, :specs, [{name, arity}], &[{name, arity} | &1])}
  end

  # Collect public function definitions
  defp collect_specs_and_defs({:def, meta, [{name, _, args} | _]} = ast, acc)
       when is_atom(name) do
    # Skip private-looking functions (convention: functions not meant for public API)
    name_string = Atom.to_string(name)

    excluded_functions = [:changeset, :base_changeset, :validate, :apply_validations]

    if not String.starts_with?(name_string, "_") and
         not String.starts_with?(name_string, "handle_") and
         name not in excluded_functions do
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

  defp collect_specs_and_defs(ast, acc), do: {ast, acc}

  defp check_for_issues(%{specs: specs, defs: defs}, issue_meta, _source_file) do
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

  defp check_for_issues(_, _, _), do: []
end
