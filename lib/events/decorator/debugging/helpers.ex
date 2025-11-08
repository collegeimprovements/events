defmodule Events.Decorator.Debugging.Helpers do
  @moduledoc """
  Shared utilities for debugging decorators.

  Provides helper functions for building AST transformations with
  extensive use of pattern matching and pipelines.
  """

  @type inspect_mode :: :simple | :detailed | :diff
  @type format_opts :: keyword()

  @doc """
  Builds AST to inspect function arguments before execution.

  Uses pattern matching to extract argument names and pipes them through
  inspection.
  """
  @spec inspect_args(Macro.t(), map(), String.t(), keyword()) :: Macro.t()
  def inspect_args(body, context, label, inspect_opts) do
    context.args
    |> extract_arg_names()
    |> build_arg_inspectors(inspect_opts)
    |> wrap_with_header_and_body(label, body)
  end

  @doc """
  Builds AST to inspect function result after execution.
  """
  @spec inspect_result(Macro.t(), String.t(), keyword()) :: Macro.t()
  def inspect_result(body, label, inspect_opts) do
    quote do
      result = unquote(body)

      IO.puts("\n[INSPECT #{unquote(label)}] Result:")
      IO.inspect(result, [label: "  return"] ++ unquote(inspect_opts))

      result
    end
  end

  @doc """
  Builds AST to inspect both arguments and result.
  """
  @spec inspect_both(Macro.t(), map(), String.t(), keyword()) :: Macro.t()
  def inspect_both(body, context, label, inspect_opts) do
    arg_inspectors =
      context.args
      |> extract_arg_names()
      |> build_arg_inspectors(inspect_opts)

    quote do
      IO.puts("\n[INSPECT #{unquote(label)}]")
      IO.puts("  Arguments:")

      unquote_splicing(arg_inspectors)

      result = unquote(body)

      IO.puts("  Result:")
      IO.inspect(result, [label: "    return"] ++ unquote(inspect_opts))
      IO.puts("")

      result
    end
  end

  @doc """
  Builds pry breakpoint with conditional logic.

  Uses pattern matching to handle different condition types and
  breakpoint positions.
  """
  @spec build_pry(Macro.t(), map(), boolean() | function(), boolean(), boolean()) :: Macro.t()
  def build_pry(body, context, condition, before?, after?) do
    function_label = build_label(context)

    {before_pry, after_pry} =
      {condition, before?, after?}
      |> build_pry_points(function_label)

    quote do
      unquote(before_pry)
      result = unquote(body)
      unquote(after_pry)
      result
    end
  end

  @doc """
  Formats traced variables for output.
  """
  @spec format_trace(inspect_mode(), atom(), any()) :: :ok
  @spec format_trace(inspect_mode(), atom(), any(), any()) :: :ok

  def format_trace(:simple, var_name, value) do
    IO.inspect(value, label: "[TRACE] #{var_name}")
  end

  def format_trace(:detailed, var_name, value) do
    value
    |> extract_type_info()
    |> format_detailed_trace(var_name, value)
  end

  def format_trace(:diff, var_name, old_value, new_value) do
    if values_differ?(old_value, new_value) do
      format_diff_trace(var_name, old_value, new_value)
    end
  end

  ## Private Helpers

  defp extract_arg_names(args) do
    Enum.map(args, fn
      {name, _, _} when is_atom(name) -> name
      _ -> :arg
    end)
  end

  defp build_arg_inspectors(arg_names, inspect_opts) do
    arg_names
    |> Enum.map(fn name ->
      quote do
        IO.inspect(
          var!(unquote(Macro.var(name, nil))),
          [label: "    #{unquote(name)}"] ++ unquote(inspect_opts)
        )
      end
    end)
  end

  defp wrap_with_header_and_body(inspectors, label, body) do
    quote do
      IO.puts("\n[INSPECT #{unquote(label)}] Arguments:")
      unquote_splicing(inspectors)
      unquote(body)
    end
  end

  defp build_pry_points({condition, before?, after?}, label) do
    before_pry = if before?, do: build_before_pry(label), else: nil
    after_pry = if after?, do: build_after_pry(condition, label), else: nil

    {before_pry, after_pry}
  end

  defp build_before_pry(label) do
    quote do
      IO.puts("\n[PRY] Breaking BEFORE: #{unquote(label)}")
      require IEx
      IEx.pry()
    end
  end

  defp build_after_pry(condition, label) do
    case condition do
      true -> build_unconditional_pry(label)
      false -> nil
      fun when is_function(fun, 1) -> build_conditional_pry(fun, label)
    end
  end

  defp build_unconditional_pry(label) do
    quote do
      IO.puts("\n[PRY] Breaking AFTER: #{unquote(label)}")
      IO.inspect(result, label: "Result")
      require IEx
      IEx.pry()
    end
  end

  defp build_conditional_pry(condition_fn, label) do
    quote do
      if unquote(condition_fn).(result) do
        IO.puts("\n[PRY] Condition met, breaking AFTER: #{unquote(label)}")
        IO.inspect(result, label: "Result")
        require IEx
        IEx.pry()
      end
    end
  end

  defp build_label(context) do
    "#{context.module}.#{context.name}/#{context.arity}"
  end

  defp extract_type_info(value) when is_struct(value), do: value.__struct__
  defp extract_type_info(value) when is_map(value), do: :map
  defp extract_type_info(value) when is_list(value), do: :list
  defp extract_type_info(value) when is_binary(value), do: :binary
  defp extract_type_info(value) when is_atom(value), do: :atom
  defp extract_type_info(value) when is_number(value), do: :number
  defp extract_type_info(_value), do: :primitive

  defp format_detailed_trace(type_info, var_name, value) do
    IO.puts("[TRACE] #{var_name}:")
    IO.puts("  Type: #{inspect(type_info)}")
    IO.puts("  Value: #{inspect(value, pretty: true, width: 80)}")
    IO.puts("")
  end

  defp values_differ?(old_value, new_value), do: old_value != new_value

  defp format_diff_trace(var_name, old_value, new_value) do
    IO.puts("[TRACE] #{var_name} changed:")
    IO.puts("  From: #{inspect(old_value)}")
    IO.puts("  To:   #{inspect(new_value)}")
    IO.puts("")
  end
end
