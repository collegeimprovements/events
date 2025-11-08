defmodule Events.Decorator.Pipeline.Helpers do
  @moduledoc """
  Shared utilities for pipeline and composition decorators.
  """

  alias Events.Decorator.AST

  @doc """
  Applies a function to the result of another function (pipe operator).

  Similar to the `|>` operator but at the AST level.
  """
  def pipe_result(body, transform_fn) do
    quote do
      result = unquote(body)
      unquote(transform_fn).(result)
    end
  end

  @doc """
  Wraps a function in around advice.

  The wrapper function receives the original function as a closure,
  along with all arguments, allowing it to:
  - Execute code before the function
  - Execute code after the function
  - Transform arguments
  - Transform results
  - Skip execution entirely

  ## Example Wrapper

      def my_wrapper(decorated_fn, arg1, arg2, wrapper_arg) do
        IO.puts("Before: wrapper_arg = " <> inspect(wrapper_arg))
        result = decorated_fn.(arg1, arg2)
        IO.puts("After: result = " <> inspect(result))
        result
      end
  """
  def build_around_advice(defun, wrapper_fn, context) do
    # Generate a private version of the original function
    private_name = :"__decorator_private_#{context.name}"

    private_defun =
      AST.update_head(defun, fn {_name, meta, args} ->
        {private_name, meta, args}
      end)

    # Make it private
    {_def, meta, [head, body]} = private_defun
    private_defun = {:defp, meta, [head, body]}

    # Build the public wrapper
    args_ast = context.args
    args_vars = Enum.map(args_ast, fn {name, meta, _ctx} -> {name, meta, nil} end)

    public_wrapper =
      quote do
        def unquote(context.name)(unquote_splicing(args_vars)) do
          decorated_fn = fn unquote_splicing(args_vars) ->
            unquote(private_name)(unquote_splicing(args_vars))
          end

          unquote(wrapper_fn).(decorated_fn, unquote_splicing(args_vars))
        end
      end

    [private_defun, public_wrapper]
  end

  @doc """
  Composes multiple decorators into a single transformation.

  Decorators are applied in the order they appear in the list,
  with each decorator receiving the result of the previous one.
  """
  def compose_decorators(decorators, body, context) when is_list(decorators) do
    Enum.reduce(decorators, body, fn decorator_call, acc_body ->
      apply_decorator(decorator_call, acc_body, context)
    end)
  end

  defp apply_decorator({decorator, opts}, body, context) when is_atom(decorator) do
    # Call the decorator function
    apply(Events.Decorator.Define, decorator, [opts, body, context])
  end

  defp apply_decorator(decorator, body, context) when is_function(decorator, 3) do
    # Direct function call
    decorator.([], body, context)
  end

  @doc """
  Validates that a pipeline step is valid.

  Valid steps are:
  - Function captures: `&MyModule.step/1`
  - Anonymous functions: `fn result -> ... end`
  - MFA tuples: `{MyModule, :function, extra_args}`
  """
  def validate_pipeline_step({:&, _meta, _args}), do: :ok
  def validate_pipeline_step({:fn, _meta, _args}), do: :ok

  def validate_pipeline_step({module, fun, args})
      when is_atom(module) and is_atom(fun) and is_list(args), do: :ok

  def validate_pipeline_step(step) do
    raise ArgumentError, """
    Invalid pipeline step: #{inspect(step)}

    Valid pipeline steps are:
    - Function captures: &MyModule.step/1
    - Anonymous functions: fn result -> ... end
    - MFA tuples: {MyModule, :function, [extra, args]}
    """
  end

  @doc """
  Applies a pipeline of transformations to the result.
  """
  def apply_pipeline(body, steps) when is_list(steps) do
    Enum.each(steps, &validate_pipeline_step/1)

    quote do
      result = unquote(body)

      Enum.reduce(unquote(steps), result, fn
        step, acc when is_function(step, 1) ->
          step.(acc)

        {module, function, extra_args}, acc ->
          apply(module, function, [acc | extra_args])
      end)
    end
  end
end
