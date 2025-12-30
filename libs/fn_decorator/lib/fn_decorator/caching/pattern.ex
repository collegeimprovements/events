defmodule FnDecorator.Caching.Pattern do
  @moduledoc """
  Pattern matching utilities for cache keys.

  Patterns use `:_` as a wildcard to match any value at that position.

  ## Pattern Syntax

      :all              # Match everything
      {User, :_}        # Match {User, 1}, {User, 2}, etc.
      {:_, :profile}    # Match {X, :profile} for any X
      {User, :_, :meta} # Match {User, X, :meta} for any X
      {:session, :_}    # Match {:session, "abc"}, {:session, "xyz"}

  ## Examples

      Pattern.match?({User, :_}, {User, 123})     # => true
      Pattern.match?({User, :_}, {Admin, 123})    # => false
      Pattern.match?(:all, anything)               # => true

  ## ETS Match Specs

  For ETS operations, patterns are converted to match specifications:

      Pattern.to_match_spec({User, :_})
      # => [{{User, :_}, :_, :_}]
  """

  @type pattern :: :all | tuple() | [term()]
  @type key :: term()

  @doc """
  Check if a key matches a pattern.

  ## Examples

      iex> Pattern.matches?(:all, {User, 123})
      true

      iex> Pattern.matches?({User, :_}, {User, 123})
      true

      iex> Pattern.matches?({User, :_}, {Admin, 123})
      false

      iex> Pattern.matches?({:_, :profile}, {User, :profile})
      true

      iex> Pattern.matches?({User, 1}, {User, 1})
      true

      iex> Pattern.matches?({User, 1}, {User, 2})
      false
  """
  @spec matches?(pattern(), key()) :: boolean()
  def matches?(:all, _key), do: true

  def matches?(pattern, key) when is_tuple(pattern) and is_tuple(key) do
    match_tuples?(pattern, key)
  end

  def matches?(pattern, key) when is_list(pattern) do
    key in pattern
  end

  def matches?(pattern, key), do: pattern == key

  @doc """
  Filter a list of keys by pattern.

  ## Examples

      iex> keys = [{User, 1}, {User, 2}, {Admin, 1}]
      iex> Pattern.filter(keys, {User, :_})
      [{User, 1}, {User, 2}]

      iex> Pattern.filter(keys, :all)
      [{User, 1}, {User, 2}, {Admin, 1}]
  """
  @spec filter([key()], pattern()) :: [key()]
  def filter(keys, :all), do: keys
  def filter(keys, pattern), do: Enum.filter(keys, &matches?(pattern, &1))

  @doc """
  Convert a pattern to an ETS match specification.

  Used for efficient pattern matching in ETS tables.

  ## Examples

      iex> Pattern.to_ets_match_pattern({User, :_})
      {User, :_}

      iex> Pattern.to_ets_match_pattern(:all)
      :_
  """
  @spec to_ets_match_pattern(pattern()) :: term()
  def to_ets_match_pattern(:all), do: :_
  def to_ets_match_pattern(pattern) when is_tuple(pattern), do: pattern
  def to_ets_match_pattern(pattern), do: pattern

  @doc """
  Check if a term is a wildcard pattern (contains :_).

  ## Examples

      iex> Pattern.wildcard?({User, :_})
      true

      iex> Pattern.wildcard?({User, 123})
      false

      iex> Pattern.wildcard?(:all)
      true
  """
  @spec wildcard?(pattern()) :: boolean()
  def wildcard?(:all), do: true

  def wildcard?(pattern) when is_tuple(pattern) do
    pattern
    |> Tuple.to_list()
    |> Enum.any?(&(&1 == :_ or wildcard?(&1)))
  end

  def wildcard?(pattern) when is_list(pattern), do: false
  def wildcard?(:_), do: true
  def wildcard?(_), do: false

  @doc """
  Check if a term is an explicit list of keys (not a pattern).

  Returns true for non-empty lists. Use this to distinguish between
  patterns (`:all`, `{User, :_}`) and explicit key lists.

  Note: This returns true for ANY non-empty list. The distinction between
  a key list and other lists is contextual - callers should know what
  they're passing.

  ## Examples

      iex> Pattern.key_list?([{User, 1}, {User, 2}])
      true

      iex> Pattern.key_list?([])
      false

      iex> Pattern.key_list?({User, :_})
      false

      iex> Pattern.key_list?(:all)
      false
  """
  @spec key_list?(term()) :: boolean()
  def key_list?([_ | _]), do: true
  def key_list?(_), do: false

  # ============================================
  # Private
  # ============================================

  defp match_tuples?(pattern, key) when tuple_size(pattern) != tuple_size(key) do
    false
  end

  defp match_tuples?(pattern, key) do
    pattern_list = Tuple.to_list(pattern)
    key_list = Tuple.to_list(key)

    Enum.zip(pattern_list, key_list)
    |> Enum.all?(fn {p, k} -> p == :_ or match_element?(p, k) end)
  end

  defp match_element?(pattern, key) when is_tuple(pattern) and is_tuple(key) do
    match_tuples?(pattern, key)
  end

  defp match_element?(pattern, key), do: pattern == key
end
