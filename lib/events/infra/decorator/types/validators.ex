defmodule Events.Infra.Decorator.Types.Validators do
  @moduledoc """
  Validation functions for type decorators.

  Provides runtime validation for various return type patterns:
  - Result types: `{:ok, value} | {:error, reason}`
  - Maybe types: `value | nil`
  - Bang types: value or raises
  - Struct types
  - List types with element validation
  - Union types
  """

  alias Events.Infra.Decorator.Types.TypeChecker

  # ============================================
  # Result Type Validation
  # ============================================

  @doc """
  Validates that a result matches the expected result type pattern.

  Checks that the result is `{:ok, value}` or `{:error, reason}` and
  that the inner values match their type specifications.
  """
  @spec validate_result_type(any(), any(), any(), boolean(), map()) :: :ok
  def validate_result_type(result, ok_type, error_type, strict, context) do
    case result do
      {:ok, value} ->
        unless TypeChecker.check_type(value, ok_type) do
          TypeChecker.handle_type_mismatch(
            "Expected {:ok, #{TypeChecker.type_name(ok_type)}}, got {:ok, #{TypeChecker.type_name(value)}}",
            strict,
            context
          )
        end

      {:error, reason} ->
        unless TypeChecker.check_type(reason, error_type) do
          TypeChecker.handle_type_mismatch(
            "Expected {:error, #{TypeChecker.type_name(error_type)}}, got {:error, #{TypeChecker.type_name(reason)}}",
            strict,
            context
          )
        end

      other ->
        TypeChecker.handle_type_mismatch(
          "Expected {:ok, _} | {:error, _}, got #{TypeChecker.type_name(other)}",
          strict,
          context
        )
    end

    :ok
  end

  # ============================================
  # Maybe Type Validation
  # ============================================

  @doc """
  Validates that a result matches the maybe type pattern (value or nil).
  """
  @spec validate_maybe_type(any(), any(), boolean(), map()) :: :ok
  def validate_maybe_type(result, type_spec, strict, context) do
    case result do
      nil ->
        :ok

      value ->
        unless TypeChecker.check_type(value, type_spec) do
          TypeChecker.handle_type_mismatch(
            "Expected #{TypeChecker.type_name(type_spec)} | nil, got #{TypeChecker.type_name(value)}",
            strict,
            context
          )
        end
    end

    :ok
  end

  # ============================================
  # Bang Type Validation
  # ============================================

  @doc """
  Validates that a result matches the expected bang type (non-nil value).
  """
  @spec validate_bang_type(any(), any(), boolean(), map()) :: :ok
  def validate_bang_type(result, type_spec, strict, context) do
    unless TypeChecker.check_type(result, type_spec) do
      TypeChecker.handle_type_mismatch(
        "Expected #{TypeChecker.type_name(type_spec)}, got #{TypeChecker.type_name(result)}",
        strict,
        context
      )
    end

    :ok
  end

  # ============================================
  # Struct Type Validation
  # ============================================

  @doc """
  Validates that a result is an instance of the expected struct.
  """
  @spec validate_struct_type(any(), module(), boolean(), boolean(), map()) :: :ok
  def validate_struct_type(result, struct_module, nullable, strict, context) do
    cond do
      is_nil(result) and nullable ->
        :ok

      is_nil(result) and not nullable ->
        TypeChecker.handle_type_mismatch(
          "Expected %#{Kernel.inspect(struct_module)}{}, got nil",
          strict,
          context
        )

      is_struct(result, struct_module) ->
        :ok

      true ->
        TypeChecker.handle_type_mismatch(
          "Expected %#{Kernel.inspect(struct_module)}{}, got #{TypeChecker.type_name(result)}",
          strict,
          context
        )
    end

    :ok
  end

  # ============================================
  # List Type Validation
  # ============================================

  @doc """
  Validates that a result is a list with elements matching the expected type.

  Also validates optional length constraints.
  """
  @spec validate_list_type(
          any(),
          any(),
          non_neg_integer() | nil,
          non_neg_integer() | nil,
          boolean(),
          map()
        ) :: :ok
  def validate_list_type(result, element_type, min_length, max_length, strict, context) do
    if not is_list(result) do
      TypeChecker.handle_type_mismatch(
        "Expected list, got #{TypeChecker.type_name(result)}",
        strict,
        context
      )
    else
      length = length(result)

      if min_length && length < min_length do
        TypeChecker.handle_type_mismatch(
          "List length #{length} is less than minimum #{min_length}",
          strict,
          context
        )
      end

      if max_length && length > max_length do
        TypeChecker.handle_type_mismatch(
          "List length #{length} exceeds maximum #{max_length}",
          strict,
          context
        )
      end

      Enum.each(result, fn element ->
        unless TypeChecker.check_type(element, element_type) do
          TypeChecker.handle_type_mismatch(
            "List element #{TypeChecker.type_name(element)} doesn't match expected type #{TypeChecker.type_name(element_type)}",
            strict,
            context
          )
        end
      end)
    end

    :ok
  end

  # ============================================
  # Union Type Validation
  # ============================================

  @doc """
  Validates that a result matches one of the allowed types in a union.
  """
  @spec validate_union_type(any(), [any()], boolean(), map()) :: :ok
  def validate_union_type(result, types, strict, context) do
    matches = Enum.any?(types, fn type -> TypeChecker.check_type(result, type) end)

    unless matches do
      type_names = Enum.map_join(types, " | ", &TypeChecker.type_name/1)

      TypeChecker.handle_type_mismatch(
        "Expected one of [#{type_names}], got #{TypeChecker.type_name(result)}",
        strict,
        context
      )
    end

    :ok
  end
end
