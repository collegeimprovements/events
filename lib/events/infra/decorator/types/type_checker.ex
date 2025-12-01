defmodule Events.Infra.Decorator.Types.TypeChecker do
  @moduledoc """
  Runtime type checking utilities for type decorators.

  Provides functions for validating that values match expected type specifications.
  Used internally by the type decorators to perform runtime validation when enabled.

  ## Type Specifications

  Supports various type formats:
  - Primitive atoms: `:atom`, `:string`, `:integer`, `:float`, `:boolean`, `:list`, `:map`
  - Module names: `User`, `Ecto.Changeset`
  - Struct patterns: `%User{}`
  - Special types: `:any`, `nil`
  """

  require Logger

  # ============================================
  # Type Checking
  # ============================================

  @doc """
  Checks if a value matches the expected type specification.

  ## Examples

      check_type("hello", :string)  # => true
      check_type(123, :integer)     # => true
      check_type(%User{}, User)     # => true
      check_type(:foo, :string)     # => false
  """
  @spec check_type(any(), any()) :: boolean()
  def check_type(_value, nil), do: true
  def check_type(nil, _type), do: true
  def check_type(_value, :any), do: true
  def check_type(value, :atom) when is_atom(value), do: true
  def check_type(value, :string) when is_binary(value), do: true
  def check_type(value, :integer) when is_integer(value), do: true
  def check_type(value, :float) when is_float(value), do: true
  def check_type(value, :boolean) when is_boolean(value), do: true
  def check_type(value, :list) when is_list(value), do: true
  def check_type(value, :map) when is_map(value), do: true
  def check_type(value, :tuple) when is_tuple(value), do: true

  # Struct checking
  def check_type(value, module) when is_atom(module) do
    is_struct(value, module)
  end

  # Pattern matching for struct patterns
  def check_type(value, pattern) when is_map(pattern) do
    is_struct(value) && value.__struct__ == pattern.__struct__
  end

  def check_type(_value, _type), do: true

  @doc """
  Returns a human-readable name for a type or value.

  ## Examples

      type_name("hello")       # => "String.t()"
      type_name(123)           # => "integer()"
      type_name(%User{})       # => "%User{}"
      type_name({:ok, value})  # => "{:ok, _}"
  """
  @spec type_name(any()) :: String.t()
  def type_name(nil), do: "nil"
  def type_name(value) when is_atom(value), do: Kernel.inspect(value)
  def type_name(value) when is_binary(value), do: "String.t()"
  def type_name(value) when is_integer(value), do: "integer()"
  def type_name(value) when is_float(value), do: "float()"
  def type_name(value) when is_boolean(value), do: "boolean()"
  def type_name(value) when is_list(value), do: "list()"
  def type_name(value) when is_map(value) and not is_struct(value), do: "map()"
  def type_name(%{__struct__: module}), do: "%#{Kernel.inspect(module)}{}"
  def type_name({:ok, _}), do: "{:ok, _}"
  def type_name({:error, _}), do: "{:error, _}"
  def type_name(value), do: Kernel.inspect(value)

  # ============================================
  # Mismatch Handling
  # ============================================

  @doc """
  Handles a type mismatch based on strict mode.

  In strict mode, raises a TypeError. Otherwise, logs a warning.
  """
  @spec handle_type_mismatch(String.t(), boolean(), map()) :: :ok | no_return()
  def handle_type_mismatch(message, true, context) do
    raise Events.Infra.Decorator.Types.TypeError,
      message: "Type mismatch in #{Events.Support.Context.full_name(context)}: #{message}"
  end

  def handle_type_mismatch(message, false, context) do
    Logger.warning("Type mismatch in #{Events.Support.Context.full_name(context)}: #{message}")
    :ok
  end
end
