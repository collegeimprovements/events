defmodule Events.Decorator.Types.ResultNormalizer do
  @moduledoc """
  Result normalization utilities for the normalize_result decorator.

  Converts various return values into consistent `{:ok, value} | {:error, reason}` format.
  """

  # ============================================
  # Result Normalization
  # ============================================

  @doc """
  Normalizes any value into a result tuple format.

  ## Normalization Rules

  1. **Already a result tuple** - Pass through (with optional mapping)
  2. **Error patterns** - Convert to `{:error, pattern}`
  3. **nil** - `{:ok, nil}` or `{:error, :nil_value}` based on config
  4. **false** - `{:ok, false}` or `{:error, :false_value}` based on config
  5. **All other values** - Wrap in `{:ok, value}`

  ## Examples

      normalize_to_result("hello", [], false, false, nil, nil)
      # => {:ok, "hello"}

      normalize_to_result(:error, [:error], false, false, nil, nil)
      # => {:error, :error}

      normalize_to_result(nil, [], true, false, nil, nil)
      # => {:error, :nil_value}
  """
  @spec normalize_to_result(
          any(),
          [atom() | String.t()],
          boolean(),
          boolean(),
          (any() -> any()) | nil,
          (any() -> any()) | nil
        ) :: {:ok, any()} | {:error, any()}
  def normalize_to_result(
        result,
        error_patterns,
        nil_is_error,
        false_is_error,
        error_mapper,
        success_mapper
      ) do
    case result do
      # Already a result tuple - apply mappers if present
      {:ok, value} ->
        if success_mapper do
          {:ok, success_mapper.(value)}
        else
          {:ok, value}
        end

      {:error, reason} ->
        if error_mapper do
          {:error, error_mapper.(reason)}
        else
          {:error, reason}
        end

      # nil handling
      nil ->
        if nil_is_error do
          error_value = if error_mapper, do: error_mapper.(:nil_value), else: :nil_value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(nil), else: nil
          {:ok, success_value}
        end

      # false handling
      false ->
        if false_is_error do
          error_value = if error_mapper, do: error_mapper.(:false_value), else: :false_value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(false), else: false
          {:ok, success_value}
        end

      # Check if result matches error patterns
      value when is_atom(value) or is_binary(value) ->
        if value in error_patterns do
          error_value = if error_mapper, do: error_mapper.(value), else: value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(value), else: value
          {:ok, success_value}
        end

      # All other values are considered success
      value ->
        success_value = if success_mapper, do: success_mapper.(value), else: value
        {:ok, success_value}
    end
  end

  # ============================================
  # Result Unwrapping
  # ============================================

  @doc """
  Unwraps a result tuple, raising on error.

  ## Examples

      unwrap_result({:ok, value}, context)
      # => value

      unwrap_result({:error, reason}, context)
      # raises UnwrapError
  """
  @spec unwrap_result(any(), map()) :: any() | no_return()
  def unwrap_result({:ok, value}, _context), do: value

  def unwrap_result({:error, reason}, context) do
    raise Events.Decorator.Types.UnwrapError,
      message: "Cannot unwrap {:error, _} in #{Events.Context.full_name(context)}",
      reason: reason
  end

  def unwrap_result(value, _context), do: value
end
