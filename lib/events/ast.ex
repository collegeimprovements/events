defmodule Events.AST do
  @moduledoc """
  Simplified AST manipulation utilities for decorators.
  Provides clean, composable transformations for function definitions.
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
  Builds context from function definition.
  """
  def build_context(defun, module) do
    Events.Context.new(
      name: get_name(defun),
      arity: get_arity(defun),
      module: module,
      args: get_args(defun),
      guards: get_guards(defun)
    )
  end
end
