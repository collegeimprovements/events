defmodule Events.Core.Query.Predicates do
  @moduledoc false
  # Internal module - use Events.Core.Query public API instead.
  #
  # Value predicates for conditional filters (maybe/maybe_on).
  # Determines whether a value should trigger a filter.

  @doc """
  Check if a value satisfies a predicate.

  ## Built-in Predicates

  - `:present` - not nil, false, "", [], %{}
  - `:not_nil` - only checks for nil
  - `:not_blank` - not nil, "", or whitespace-only string
  - `:not_empty` - not nil, [], or %{}

  Also accepts a 1-arity function for custom predicates.
  """
  @spec check(atom() | (term() -> boolean()), term()) :: boolean()
  def check(:present, value), do: present?(value)
  def check(:not_nil, value), do: not is_nil(value)
  def check(:not_blank, value), do: not blank?(value)
  def check(:not_empty, value), do: not empty?(value)
  def check(fun, value) when is_function(fun, 1), do: fun.(value)

  @doc "Check if value is present (truthy and not empty)"
  @spec present?(term()) :: boolean()
  def present?(nil), do: false
  def present?(false), do: false
  def present?(""), do: false
  def present?([]), do: false
  def present?(%{} = map) when map_size(map) == 0, do: false
  def present?(_), do: true

  @doc "Check if value is blank (nil, empty string, or whitespace)"
  @spec blank?(term()) :: boolean()
  def blank?(nil), do: true
  def blank?(""), do: true
  def blank?(str) when is_binary(str), do: String.trim(str) == ""
  def blank?(_), do: false

  @doc "Check if value is empty (nil, empty list, or empty map)"
  @spec empty?(term()) :: boolean()
  def empty?(nil), do: true
  def empty?([]), do: true
  def empty?(%{} = map) when map_size(map) == 0, do: true
  def empty?(_), do: false
end
