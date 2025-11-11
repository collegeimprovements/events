defmodule Events.DecoratorUtils do
  @moduledoc """
  Minimal set of utility functions for decorators.
  Only essential, reusable functions are included.
  """

  # Single function to handle all option resolution
  def resolve(type, value, context \\ nil) do
    case {type, value} do
      # Module resolution (for cache, etc.)
      {:module, nil} ->
        quote(do: Events.Cache)

      {:module, module} when is_atom(module) ->
        module

      {:module, {mod, fun, args}} ->
        quote do: unquote(mod).unquote(fun)(unquote_splicing(args))

      # Key resolution
      {:key, %{key: key}} ->
        quote(do: unquote(key))

      {:key, %{key_generator: gen}} ->
        generate_key(gen, context)

      {:key, _} ->
        default_key(context)

      # Match function evaluation
      {:match, nil} ->
        quote(do: {true, result})

      {:match, match_fn} ->
        quote do
          case unquote(match_fn).(result) do
            true -> {true, result}
            {true, value} -> {true, value}
            {true, value, opts} -> {true, value, opts}
            false -> false
            _ -> raise ArgumentError, "Invalid match function return"
          end
        end

      # Error handling
      {:error, :raise} ->
        quote(do: fn error -> raise error end)

      {:error, :nothing} ->
        quote(do: fn _error -> nil end)

      # Default passthrough
      _ ->
        value
    end
  end

  # Single metadata builder for all telemetry needs
  def build_metadata(context, include_vars \\ [], extra \\ %{}) do
    base = %{
      module: context.module,
      function: context.name,
      arity: context.arity
    }

    metadata = Map.merge(base, extra)

    if Enum.empty?(include_vars) do
      quote(do: unquote(Macro.escape(metadata)))
    else
      var_captures =
        for var_name <- include_vars do
          quote do
            {unquote(var_name), var!(unquote(Macro.var(var_name, nil)))}
          end
        end

      quote do
        Map.merge(
          unquote(Macro.escape(metadata)),
          Map.new([unquote_splicing(var_captures)])
        )
      end
    end
  end

  # Single timing wrapper
  def with_timing(body) do
    quote do
      start = System.monotonic_time()
      result = unquote(body)
      duration = System.monotonic_time() - start
      {result, duration}
    end
  end

  # Single options merger
  def merge_opts(static_opts, runtime_opts \\ []) do
    quote do
      unquote(static_opts)
      |> Keyword.merge(unquote(runtime_opts))
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end
  end

  # Private helpers (minimal set)

  defp generate_key({mod, fun, args}, context) do
    quote do
      unquote(mod).unquote(fun)(
        unquote(context.module),
        unquote(context.name),
        unquote(context.args),
        unquote_splicing(args)
      )
    end
  end

  defp generate_key(mod, context) when is_atom(mod) do
    quote do
      unquote(mod).generate(
        unquote(context.module),
        unquote(context.name),
        unquote(context.args)
      )
    end
  end

  defp default_key(context) do
    quote do
      {unquote(context.module), unquote(context.name), unquote(context.args)}
    end
  end
end
