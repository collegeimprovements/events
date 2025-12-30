defmodule FnDecorator.Support.AST do
  @moduledoc """
  AST manipulation utilities for decorators.

  Provides clean, composable transformations for function definitions.

  ## Extractors

  Functions to extract information from function AST:

  - `get_name/1` - Extract function name
  - `get_args/1` - Extract function arguments
  - `get_arity/1` - Get function arity
  - `get_guards/1` - Extract guard clauses
  - `get_body/1` - Extract function body
  - `public?/1` - Check if function is public
  - `guarded?/1` - Check if function has guards

  ## Transformers

  Functions to transform function AST:

  - `update_body/2` - Transform function body
  - `inject_before/2` - Inject code before body
  - `inject_after/2` - Inject code after body (preserving return)
  - `wrap_try/2` - Wrap body in try/rescue/after
  - `rename/2` - Rename function
  - `make_private/1` - Convert def to defp
  - `make_public/1` - Convert defp to def
  - `add_guard/2` - Add guard clause

  ## Examples

      # Inject logging before function body
      ast
      |> AST.inject_before(quote do: Logger.debug("entering"))
      |> AST.inject_after(quote do: Logger.debug("exiting"))

      # Create private implementation
      ast
      |> AST.rename(:__impl__)
      |> AST.make_private()
  """

  @type defun :: {:def | :defp, keyword(), [Macro.t()]}

  # ============================================================================
  # Core Extractors
  # ============================================================================

  @doc "Extracts function name from definition"
  def get_name({_def, _, [{name, _, _} | _]}) when is_atom(name), do: name
  def get_name({_def, _, [{:when, _, [{name, _, _} | _]} | _]}), do: name

  @doc "Extracts function arguments from definition"
  def get_args({_def, _, [head | _]}), do: extract_args(head)

  defp extract_args({:when, _, [head | _]}), do: extract_args(head)
  defp extract_args({_name, _, args}) when is_list(args), do: args
  defp extract_args({_name, _, nil}), do: []

  @doc "Gets function arity"
  def get_arity(ast), do: ast |> get_args() |> length()

  @doc "Extracts guards if present"
  def get_guards({_def, _, [{:when, _, [_ | guards]} | _]}) do
    case guards do
      [single] -> single
      multiple -> {:__block__, [], multiple}
    end
  end

  def get_guards(_), do: nil

  @doc "Extracts function body"
  def get_body({_def, _, [_, body]}), do: body
  def get_body({_def, _, [_]}), do: [do: nil]

  @doc "Returns true if function is public (def), false if private (defp)"
  @spec public?(defun()) :: boolean()
  def public?({:def, _, _}), do: true
  def public?({:defp, _, _}), do: false

  @doc "Returns true if function has guard clauses"
  @spec guarded?(defun()) :: boolean()
  def guarded?(ast), do: get_guards(ast) != nil

  @doc """
  Extracts all variable names from a pattern (e.g., function arguments).

  ## Examples

      iex> args = [{:user, [], nil}, {:opts, [], nil}]
      iex> FnDecorator.Support.AST.get_variables(args)
      [:user, :opts]
  """
  @spec get_variables(Macro.t()) :: [atom()]
  def get_variables(pattern) when is_list(pattern) do
    Enum.flat_map(pattern, &get_variables/1)
  end

  def get_variables({name, _, context}) when is_atom(name) and is_atom(context) do
    if String.starts_with?(Atom.to_string(name), "_"), do: [], else: [name]
  end

  def get_variables({:=, _, [left, right]}) do
    get_variables(left) ++ get_variables(right)
  end

  def get_variables({:%{}, _, pairs}) do
    Enum.flat_map(pairs, fn {_key, value} -> get_variables(value) end)
  end

  def get_variables({:{}, _, elements}) do
    Enum.flat_map(elements, &get_variables/1)
  end

  def get_variables({_, _} = tuple) do
    tuple |> Tuple.to_list() |> Enum.flat_map(&get_variables/1)
  end

  def get_variables(_), do: []

  # ============================================================================
  # Core Transformers
  # ============================================================================

  @doc """
  Updates function body with transform function.

  Example:
      update_body(ast, fn body ->
        quote do
          Logger.debug("Entering function")
          unquote(body)
        end
      end)
  """
  def update_body({def_type, meta, [head, body]}, transform) do
    new_body =
      case body do
        [do: do_body] ->
          [do: transform.(do_body)]

        [do: do_body, rescue: rescue_clauses] ->
          [do: transform.(do_body), rescue: rescue_clauses]

        keyword when is_list(keyword) ->
          Keyword.update!(keyword, :do, transform)
      end

    {def_type, meta, [head, new_body]}
  end

  @doc """
  Wraps function body in try/rescue/after blocks.
  """
  def wrap_try(defun, clauses) do
    update_body(defun, fn body ->
      quote do
        try do
          unquote(body)
        rescue
          unquote(clauses[:rescue] || [])
        catch
          unquote(clauses[:catch] || [])
        after
          unquote(clauses[:after] || [])
        end
      end
    end)
  end

  @doc """
  Injects code before the function body.

  ## Examples

      ast |> AST.inject_before(quote do: Logger.debug("entering"))
  """
  @spec inject_before(defun(), Macro.t()) :: defun()
  def inject_before(defun, code) do
    update_body(defun, fn body ->
      quote do
        unquote(code)
        unquote(body)
      end
    end)
  end

  @doc """
  Injects code after the function body, preserving the return value.

  ## Examples

      ast |> AST.inject_after(quote do: Logger.debug("exiting"))
  """
  @spec inject_after(defun(), Macro.t()) :: defun()
  def inject_after(defun, code) do
    update_body(defun, fn body ->
      quote do
        result = unquote(body)
        unquote(code)
        result
      end
    end)
  end

  @doc """
  Renames a function.

  ## Examples

      ast |> AST.rename(:__original__)
  """
  @spec rename(defun(), atom()) :: defun()
  def rename({def_type, meta, [head, body]}, new_name) do
    new_head = rename_head(head, new_name)
    {def_type, meta, [new_head, body]}
  end

  defp rename_head({:when, meta, [call | guards]}, new_name) do
    {:when, meta, [rename_call(call, new_name) | guards]}
  end

  defp rename_head(call, new_name), do: rename_call(call, new_name)

  defp rename_call({_old_name, meta, args}, new_name), do: {new_name, meta, args}

  @doc """
  Converts a public function to private (def -> defp).

  ## Examples

      ast |> AST.make_private()
  """
  @spec make_private(defun()) :: defun()
  def make_private({:def, meta, args}), do: {:defp, meta, args}
  def make_private({:defp, _, _} = defun), do: defun

  @doc """
  Converts a private function to public (defp -> def).

  ## Examples

      ast |> AST.make_public()
  """
  @spec make_public(defun()) :: defun()
  def make_public({:defp, meta, args}), do: {:def, meta, args}
  def make_public({:def, _, _} = defun), do: defun

  @doc """
  Adds a guard clause to a function.

  ## Examples

      ast |> AST.add_guard(quote do: is_binary(name))
  """
  @spec add_guard(defun(), Macro.t()) :: defun()
  def add_guard({def_type, meta, [head, body]}, guard) do
    new_head =
      case head do
        {:when, when_meta, [call | existing_guards]} ->
          combined = combine_guards(existing_guards, guard)
          {:when, when_meta, [call | combined]}

        call ->
          {:when, [], [call, guard]}
      end

    {def_type, meta, [new_head, body]}
  end

  defp combine_guards([single], new_guard) do
    [quote(do: unquote(single) and unquote(new_guard))]
  end

  defp combine_guards(guards, new_guard) when is_list(guards) do
    [quote(do: unquote({:__block__, [], guards}) and unquote(new_guard))]
  end

  # ============================================================================
  # Context Building
  # ============================================================================

  @doc """
  Builds context from function definition.
  """
  def build_context(defun, module) do
    FnDecorator.Support.Context.new(
      name: get_name(defun),
      arity: get_arity(defun),
      module: module,
      args: get_args(defun),
      guards: get_guards(defun)
    )
  end
end
