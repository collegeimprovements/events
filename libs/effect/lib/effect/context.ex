defmodule Effect.Context do
  @moduledoc """
  Context management for Effect execution.

  Context is an immutable map that flows through steps:
  - Each step receives a snapshot of the current context
  - Step results (`{:ok, map}`) are merged into context
  - Parallel steps receive the same pre-parallel snapshot
  - Merge strategy: last writer wins (declaration order for parallel)
  """

  @type t :: map()

  @doc """
  Creates a new context with optional initial values.
  """
  @spec new(map()) :: t()
  def new(initial \\ %{}) when is_map(initial), do: initial

  @doc """
  Merges step results into context.

  Step results must be maps. The new values override existing ones.
  """
  @spec merge(t(), map()) :: t()
  def merge(ctx, results) when is_map(ctx) and is_map(results) do
    Map.merge(ctx, results)
  end

  @doc """
  Takes a snapshot of the context (for parallel execution).

  Currently just returns the context since maps are immutable,
  but this provides a hook for future optimizations.
  """
  @spec snapshot(t()) :: t()
  def snapshot(ctx), do: ctx

  @doc """
  Merges multiple results in order (for parallel execution).

  Results are merged left-to-right, so later results win on conflict.
  """
  @spec merge_parallel(t(), [{atom(), map()}]) :: t()
  def merge_parallel(ctx, results) do
    Enum.reduce(results, ctx, fn {_name, result}, acc ->
      merge(acc, result)
    end)
  end

  @doc """
  Gets a value from context with optional default.
  """
  @spec get(t(), atom(), term()) :: term()
  def get(ctx, key, default \\ nil), do: Map.get(ctx, key, default)

  @doc """
  Puts a value into context.
  """
  @spec put(t(), atom(), term()) :: t()
  def put(ctx, key, value), do: Map.put(ctx, key, value)

  @doc """
  Returns the keys that were added by comparing two contexts.
  """
  @spec added_keys(t(), t()) :: [atom()]
  def added_keys(before_ctx, after_ctx) do
    after_ctx
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(before_ctx, &1))
  end
end
