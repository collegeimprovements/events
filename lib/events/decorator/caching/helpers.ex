defmodule Events.Decorator.Caching.Helpers do
  @moduledoc """
  Shared utilities for caching decorators.

  Provides common functionality used across cacheable, cache_put, and cache_evict decorators.
  """

  @doc """
  Resolves the cache module from decorator options.

  Supports:
  - Direct module: `cache: MyCache`
  - MFA tuple: `cache: {MyModule, :get_cache, []}`
  - MFA with args: `cache: {MyModule, :get_cache, ["extra_arg"]}`

  ## Examples

      iex> resolve_cache([cache: MyCache])
      quote do: MyCache

      iex> resolve_cache([cache: {MyModule, :get_cache, []}])
      quote do: MyModule.get_cache()
  """
  def resolve_cache(opts) do
    case Keyword.fetch!(opts, :cache) do
      {mod, fun, args} ->
        quote do: unquote(mod).unquote(fun)(unquote_splicing(args))

      module when is_atom(module) ->
        module
    end
  end

  @doc """
  Generates code to resolve a cache key.

  Supports:
  - Explicit key: `key: {User, id}`
  - Custom generator: `key_generator: MyGenerator`
  - Default generator from cache

  ## Examples

      iex> resolve_key([key: {User, id}], context)
      quote do: {User, id}

      iex> resolve_key([], context)
      # Uses default key generator
  """
  def resolve_key(opts, context) do
    cond do
      # Explicit key provided
      Keyword.has_key?(opts, :key) ->
        key = Keyword.get(opts, :key)
        quote do: unquote(key)

      # Custom key generator
      Keyword.has_key?(opts, :key_generator) ->
        generate_key_with_generator(opts, context)

      # Use cache's default key generator
      true ->
        generate_key_with_cache_default(opts, context)
    end
  end

  defp generate_key_with_generator(opts, context) do
    case Keyword.get(opts, :key_generator) do
      {mod, args} ->
        quote do
          unquote(mod).generate(
            unquote(context.module),
            unquote(context.name),
            unquote(extract_args(context.args)),
            unquote_splicing(args)
          )
        end

      {mod, fun, args} ->
        quote do
          unquote(mod).unquote(fun)(
            unquote(context.module),
            unquote(context.name),
            unquote(extract_args(context.args)),
            unquote_splicing(args)
          )
        end

      mod when is_atom(mod) ->
        quote do
          unquote(mod).generate(
            unquote(context.module),
            unquote(context.name),
            unquote(extract_args(context.args))
          )
        end
    end
  end

  defp generate_key_with_cache_default(opts, context) do
    cache = resolve_cache(opts)

    quote do
      cache = unquote(cache)

      cache.__default_key_generator__().generate(
        unquote(context.module),
        unquote(context.name),
        unquote(extract_args(context.args))
      )
    end
  end

  @doc """
  Extracts argument variables from context.args AST for key generation.

  Only includes explicitly assigned variables, excludes ignored args.
  """
  def extract_args(args_ast) when is_list(args_ast) do
    args_ast
  end

  @doc """
  Generates code to evaluate a match function.

  Match functions determine if a result should be cached:
  - `match_fn(result) -> true` - Cache the result
  - `match_fn(result) -> {true, value}` - Cache specific value
  - `match_fn(result) -> {true, value, opts}` - Cache with runtime options
  - `match_fn(result) -> false` - Don't cache

  ## Examples

      iex> opts = [match: &match_ok/1]
      iex> eval_match(opts, quote(do: result))
      # Returns code that calls match_ok(result)
  """
  def eval_match(opts, result_var) do
    case Keyword.get(opts, :match) do
      nil ->
        # No match function, always cache
        quote do: {true, unquote(result_var)}

      match_fn ->
        quote do
          case unquote(match_fn).(unquote(result_var)) do
            true ->
              {true, unquote(result_var)}

            {true, value} ->
              {true, value}

            {true, value, runtime_opts} ->
              {true, value, runtime_opts}

            false ->
              false

            other ->
              raise ArgumentError,
                    "Match function must return true, {true, value}, {true, value, opts}, or false. Got: #{inspect(other)}"
          end
        end
    end
  end

  @doc """
  Handles errors based on the on_error option.

  - `:raise` (default) - Propagate the error
  - `:nothing` - Swallow the error and return default value
  """
  def handle_error(opts, default \\ nil) do
    case Keyword.get(opts, :on_error, :raise) do
      :raise ->
        quote do
          fn error -> raise error end
        end

      :nothing ->
        quote do
          fn _error -> unquote(default) end
        end
    end
  end

  @doc """
  Normalizes cache operation options.

  Merges runtime TTL with static options.
  """
  def merge_opts(static_opts, runtime_opts \\ []) do
    quote do
      unquote(static_opts)
      |> Keyword.merge(unquote(runtime_opts))
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end
  end
end
