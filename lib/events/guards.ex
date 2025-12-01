defmodule Events.Guards do
  @moduledoc """
  Guard clauses and pattern matching helpers for functional types.

  Provides guards for use in function heads and case expressions,
  plus pattern matching macros for Maybe, Result, and other types.

  ## Usage

      import Events.Guards

      # In function heads
      def process(result) when is_ok(result), do: ...
      def process(result) when is_error(result), do: ...

      # In case expressions
      case result do
        value when is_ok(value) -> handle_ok(value)
        value when is_error(value) -> handle_error(value)
      end

  ## Pattern Matching Macros

      import Events.Guards

      # Match and extract in one step
      case result do
        ok(value) -> use(value)
        error(reason) -> handle(reason)
      end
  """

  # ============================================
  # Result Guards
  # ============================================

  @doc """
  Guard that checks if a value is an ok tuple.

  ## Examples

      iex> import Events.Guards
      iex> is_ok({:ok, 42})
      true

      iex> import Events.Guards
      iex> is_ok({:error, :bad})
      false
  """
  defguard is_ok(value) when is_tuple(value) and tuple_size(value) == 2 and elem(value, 0) == :ok

  @doc """
  Guard that checks if a value is an error tuple.

  ## Examples

      iex> import Events.Guards
      iex> is_error({:error, :not_found})
      true

      iex> import Events.Guards
      iex> is_error({:ok, 42})
      false
  """
  defguard is_error(value)
           when is_tuple(value) and tuple_size(value) == 2 and elem(value, 0) == :error

  @doc """
  Guard that checks if a value is a result (ok or error tuple).

  ## Examples

      iex> import Events.Guards
      iex> is_result({:ok, 42})
      true

      iex> import Events.Guards
      iex> is_result({:error, :bad})
      true

      iex> import Events.Guards
      iex> is_result(:something_else)
      false
  """
  defguard is_result(value) when is_ok(value) or is_error(value)

  # ============================================
  # Maybe Guards
  # ============================================

  @doc """
  Guard that checks if a value is a some tuple.

  ## Examples

      iex> import Events.Guards
      iex> is_some({:some, 42})
      true

      iex> import Events.Guards
      iex> is_some(:none)
      false
  """
  defguard is_some(value)
           when is_tuple(value) and tuple_size(value) == 2 and elem(value, 0) == :some

  @doc """
  Guard that checks if a value is none.

  ## Examples

      iex> import Events.Guards
      iex> is_none(:none)
      true

      iex> import Events.Guards
      iex> is_none({:some, 42})
      false
  """
  defguard is_none(value) when value == :none

  @doc """
  Guard that checks if a value is a maybe (some or none).

  ## Examples

      iex> import Events.Guards
      iex> is_maybe({:some, 42})
      true

      iex> import Events.Guards
      iex> is_maybe(:none)
      true

      iex> import Events.Guards
      iex> is_maybe(:something_else)
      false
  """
  defguard is_maybe(value) when is_some(value) or is_none(value)

  # ============================================
  # Pattern Matching Macros
  # ============================================

  @doc """
  Pattern macro for matching and extracting ok values.

  ## Examples

      import Events.Guards

      case fetch_user(id) do
        ok(user) -> process(user)
        error(reason) -> handle_error(reason)
      end

      # In function heads
      def handle(ok(value)), do: process(value)
      def handle(error(reason)), do: log_error(reason)
  """
  defmacro ok(value) do
    quote do
      {:ok, unquote(value)}
    end
  end

  @doc """
  Pattern macro for matching and extracting error values.

  ## Examples

      import Events.Guards

      case result do
        ok(_) -> :success
        error(:not_found) -> :missing
        error(reason) -> {:failed, reason}
      end
  """
  defmacro error(reason) do
    quote do
      {:error, unquote(reason)}
    end
  end

  @doc """
  Pattern macro for matching and extracting some values.

  ## Examples

      import Events.Guards

      case maybe_value do
        some(x) -> use(x)
        none() -> default()
      end
  """
  defmacro some(value) do
    quote do
      {:some, unquote(value)}
    end
  end

  @doc """
  Pattern macro for matching none.

  ## Examples

      import Events.Guards

      case maybe_value do
        some(x) -> {:found, x}
        none() -> :not_found
      end
  """
  defmacro none do
    quote do
      :none
    end
  end

  # ============================================
  # Utility Guards
  # ============================================

  @doc """
  Guard that checks if a value is a non-empty string.

  ## Examples

      iex> import Events.Guards
      iex> is_non_empty_string("hello")
      true

      iex> import Events.Guards
      iex> is_non_empty_string("")
      false

      iex> import Events.Guards
      iex> is_non_empty_string(nil)
      false
  """
  defguard is_non_empty_string(value) when is_binary(value) and byte_size(value) > 0

  @doc """
  Guard that checks if a value is a non-empty list.

  ## Examples

      iex> import Events.Guards
      iex> is_non_empty_list([1, 2, 3])
      true

      iex> import Events.Guards
      iex> is_non_empty_list([])
      false
  """
  defguard is_non_empty_list(value) when is_list(value) and length(value) > 0

  @doc """
  Guard that checks if a value is a non-empty map.

  ## Examples

      iex> import Events.Guards
      iex> is_non_empty_map(%{a: 1})
      true

      iex> import Events.Guards
      iex> is_non_empty_map(%{})
      false
  """
  defguard is_non_empty_map(value) when is_map(value) and map_size(value) > 0

  @doc """
  Guard that checks if a value is a positive integer.

  ## Examples

      iex> import Events.Guards
      iex> is_positive_integer(5)
      true

      iex> import Events.Guards
      iex> is_positive_integer(0)
      false

      iex> import Events.Guards
      iex> is_positive_integer(-1)
      false
  """
  defguard is_positive_integer(value) when is_integer(value) and value > 0

  @doc """
  Guard that checks if a value is a non-negative integer.

  ## Examples

      iex> import Events.Guards
      iex> is_non_negative_integer(0)
      true

      iex> import Events.Guards
      iex> is_non_negative_integer(5)
      true

      iex> import Events.Guards
      iex> is_non_negative_integer(-1)
      false
  """
  defguard is_non_negative_integer(value) when is_integer(value) and value >= 0
end
