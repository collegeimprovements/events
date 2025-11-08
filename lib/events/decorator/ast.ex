defmodule Events.Decorator.AST do
  @moduledoc """
  AST manipulation utilities for decorators.

  Provides functions for transforming function definitions at compile time,
  inspired by the `deco` library's approach. All functions use pattern matching
  for clean, composable transformations.

  ## Common Patterns

  - `update_*` functions transform specific parts of function definitions
  - `get_*` functions extract information from AST
  - All functions work with function definition AST: `{:def | :defp, meta, [head, body]}`
  """

  alias Events.Decorator.Context

  @type defun :: {:def | :defp, keyword(), [Macro.t()]}
  @type fun_head :: {atom(), keyword(), [Macro.t()]}
  @type fun_body :: [do: Macro.t()] | [do: Macro.t(), rescue: Macro.t()] | keyword()

  ## Extractors

  @doc """
  Extracts the function head from a function definition.

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.get_head(ast)
      {:foo, [context: Elixir, imports: [{1, Kernel}]], [{:x, [], Elixir}, {:y, [], Elixir}]}
  """
  @spec get_head(defun()) :: fun_head()
  def get_head({_def, _meta, [head, _body]}), do: head
  def get_head({_def, _meta, [head]}), do: head

  @doc """
  Extracts the function name from a function definition or head.

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.get_name(ast)
      :foo
  """
  @spec get_name(defun() | fun_head()) :: atom()
  def get_name({:def, _meta, [{name, _, _} | _]}), do: name
  def get_name({:defp, _meta, [{name, _, _} | _]}), do: name
  def get_name({:when, _meta, [{name, _, _} | _]}), do: name
  def get_name({name, _meta, _args}) when is_atom(name), do: name

  @doc """
  Extracts the function arguments from a function definition or head.

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.get_args(ast)
      [{:x, [], Elixir}, {:y, [], Elixir}]
  """
  @spec get_args(defun() | fun_head()) :: [Macro.t()]
  def get_args({_def, _meta, [head | _]}) do
    get_args(head)
  end

  def get_args({:when, _meta, [head | _]}) do
    get_args(head)
  end

  def get_args({_name, _meta, args}) when is_list(args), do: args
  def get_args({_name, _meta, nil}), do: []

  @doc """
  Extracts function arity from a function definition or head.

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.get_arity(ast)
      2
  """
  @spec get_arity(defun() | fun_head()) :: non_neg_integer()
  def get_arity(ast) do
    ast |> get_args() |> length()
  end

  @doc """
  Extracts guards from a function definition, if present.

  ## Examples

      iex> ast = quote do: def foo(x) when is_integer(x), do: x + 1
      iex> AST.get_guards(ast)
      # AST for: is_integer(x)
  """
  @spec get_guards(defun()) :: Macro.t() | nil
  def get_guards({_def, _meta, [{:when, _when_meta, [_head | guards]} | _]}) do
    case guards do
      [single_guard] -> single_guard
      multiple -> {:__block__, [], multiple}
    end
  end

  def get_guards(_), do: nil

  @doc """
  Extracts the function body from a function definition.

  ## Examples

      iex> ast = quote do: def foo(x), do: x + 1
      iex> AST.get_body(ast)
      [do: {:+, [context: Elixir, imports: [{2, Kernel}]], [{:x, [], Elixir}, 1]}]
  """
  @spec get_body(defun()) :: fun_body()
  def get_body({_def, _meta, [_head, body]}), do: body
  def get_body({_def, _meta, [_head]}), do: [do: nil]

  ## Transformers

  @doc """
  Updates the function body while preserving head, guards, and metadata.

  The transform function receives the current body and returns the new body.

  ## Examples

      iex> ast = quote do: def foo(x), do: x + 1
      iex> AST.update_body(ast, fn body ->
      ...>   quote do
      ...>     IO.puts("Before")
      ...>     unquote(body)
      ...>   end
      ...> end)
      # def foo(x) do
      #   IO.puts("Before")
      #   x + 1
      # end
  """
  @spec update_body(defun(), (Macro.t() -> Macro.t())) :: defun()
  def update_body({def_type, meta, [head, body]}, transform) when is_function(transform, 1) do
    new_body =
      case body do
        [do: do_body] ->
          [do: transform.(do_body)]

        [do: do_body, rescue: rescue_clauses] ->
          [do: transform.(do_body), rescue: rescue_clauses]

        keyword_body when is_list(keyword_body) ->
          Keyword.update!(keyword_body, :do, transform)
      end

    {def_type, meta, [head, new_body]}
  end

  @doc """
  Updates the function head (name and/or arguments).

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.update_head(ast, fn {name, meta, args} ->
      ...>   {String.to_atom("internal_" <> Atom.to_string(name)), meta, args}
      ...> end)
      # def internal_foo(x, y), do: x + y
  """
  @spec update_head(defun(), (fun_head() -> fun_head())) :: defun()
  def update_head({def_type, def_meta, [head, body]}, transform)
      when is_function(transform, 1) do
    new_head =
      case head do
        {:when, when_meta, [inner_head | guards]} ->
          {:when, when_meta, [transform.(inner_head) | guards]}

        head ->
          transform.(head)
      end

    {def_type, def_meta, [new_head, body]}
  end

  @doc """
  Updates the function guards.

  ## Examples

      iex> ast = quote do: def foo(x) when is_integer(x), do: x + 1
      iex> AST.update_guards(ast, fn guard ->
      ...>   quote do: unquote(guard) and x > 0
      ...> end)
      # def foo(x) when is_integer(x) and x > 0, do: x + 1
  """
  @spec update_guards(defun(), (Macro.t() | nil -> Macro.t())) :: defun()
  def update_guards({def_type, def_meta, [head, body]}, transform)
      when is_function(transform, 1) do
    current_guards = get_guards({def_type, def_meta, [head, body]})
    new_guards = transform.(current_guards)

    new_head =
      case head do
        {:when, _when_meta, [inner_head | _]} ->
          if new_guards do
            {:when, [], [inner_head, new_guards]}
          else
            inner_head
          end

        head ->
          if new_guards do
            {:when, [], [head, new_guards]}
          else
            head
          end
      end

    {def_type, def_meta, [new_head, body]}
  end

  @doc """
  Updates the function arguments.

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.update_args(ast, fn args ->
      ...>   args ++ [{:z, [], Elixir}]
      ...> end)
      # def foo(x, y, z), do: x + y
  """
  @spec update_args(defun(), ([Macro.t()] -> [Macro.t()])) :: defun()
  def update_args({def_type, def_meta, [head, body]}, transform)
      when is_function(transform, 1) do
    {inner_head, guards} =
      case head do
        {:when, _when_meta, [inner_head | guards]} -> {inner_head, guards}
        head -> {head, []}
      end

    {name, head_meta, args} = inner_head
    new_args = transform.(args || [])
    new_inner_head = {name, head_meta, new_args}

    new_head =
      case guards do
        [] -> new_inner_head
        guards -> {:when, [], [new_inner_head | guards]}
      end

    {def_type, def_meta, [new_head, body]}
  end

  ## Higher-Level Transformations

  @doc """
  Wraps the function body with try/rescue/after blocks.

  ## Examples

      iex> ast = quote do: def foo(x), do: x + 1
      iex> AST.wrap_try(ast,
      ...>   rescue: quote do
      ...>     e in RuntimeError -> {:error, e}
      ...>   end,
      ...>   after: quote do
      ...>     IO.puts("Cleanup")
      ...>   end
      ...> )
  """
  @spec wrap_try(defun(), keyword()) :: defun()
  def wrap_try(defun, clauses) when is_list(clauses) do
    update_body(defun, fn body ->
      try_clauses = Keyword.put_new(clauses, :do, body)

      quote do
        try do
          unquote(try_clauses[:do])
        rescue
          unquote(try_clauses[:rescue] || [])
        catch
          unquote(try_clauses[:catch] || [])
        after
          unquote(try_clauses[:after] || [])
        end
      end
    end)
  end

  @doc """
  Creates a privatized version of the function with a prefixed name.

  Useful for around advice pattern where the original function needs to be
  made private and a public wrapper created.

  ## Examples

      iex> ast = quote do: def foo(x), do: x + 1
      iex> AST.privatize(ast, prefix: "__decorator_")
      # defp __decorator_foo(x), do: x + 1
  """
  @spec privatize(defun(), keyword()) :: defun()
  def privatize({_def, meta, [head, body]}, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "__private_")

    new_head =
      update_head({:def, meta, [head, body]}, fn {name, head_meta, args} ->
        new_name = String.to_atom("#{prefix}#{name}")
        {new_name, head_meta, args}
      end)
      |> get_head()

    {:defp, meta, [new_head, body]}
  end

  @doc """
  Generates fresh variable names to avoid conflicts.

  ## Examples

      iex> AST.fresh_vars([:result, :start_time], __ENV__)
      [{:result_1, [], Elixir}, {:start_time_2, [], Elixir}]
  """
  @spec fresh_vars([atom()], Macro.Env.t()) :: [Macro.t()]
  def fresh_vars(names, env) when is_list(names) do
    Enum.map(names, fn name ->
      Macro.var(name, env.module)
    end)
  end

  @doc """
  Builds a context struct from a function definition AST.

  ## Examples

      iex> ast = quote do: def foo(x, y), do: x + y
      iex> AST.build_context(ast, MyModule)
      %Context{name: :foo, arity: 2, module: MyModule, args: [...]}
  """
  @spec build_context(defun(), module()) :: Context.t()
  def build_context(defun, module) do
    Context.new(
      name: get_name(defun),
      arity: get_arity(defun),
      module: module,
      args: get_args(defun),
      guards: get_guards(defun)
    )
  end
end
