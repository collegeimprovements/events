defmodule FnDecorator.Caching.Helpers do
  @moduledoc """
  Runtime helpers for caching decorators.

  These functions handle match result normalization at runtime to avoid
  compile-time type checker warnings about unreachable pattern match branches.
  Different match functions may return different result shapes (true, {true, value},
  {true, value, opts}, or false), and handling all cases in generated code
  triggers warnings when the type checker can infer a specific function's return type.
  """

  @doc """
  Puts value to cache if match result indicates caching should occur.

  Handles all possible match result formats:
  - `true` - cache the original result
  - `{true, value}` - cache the extracted value
  - `{true, value, opts}` - cache with custom options
  - `false` - don't cache
  """
  @spec put_if_matched(
          match_result :: boolean() | {true, term()} | {true, term(), keyword()} | false,
          original_result :: term(),
          cache :: module(),
          keys :: [term()],
          default_opts :: keyword()
        ) :: :ok
  def put_if_matched(match_result, original_result, cache, keys, default_opts) do
    case match_result do
      true ->
        do_put(cache, keys, original_result, default_opts)

      {true, value} ->
        do_put(cache, keys, value, default_opts)

      {true, value, runtime_opts} ->
        merged_opts = Keyword.merge(default_opts, runtime_opts)
        do_put(cache, keys, value, merged_opts)

      false ->
        :ok
    end
  end

  defp do_put(cache, keys, value, opts) do
    for key <- keys do
      cache.put(key, value, opts)
    end

    :ok
  end
end
