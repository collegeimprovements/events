defmodule Events.Schema.Helpers.Conditional do
  @moduledoc """
  Helper module for conditional validation logic.

  Provides utilities for evaluating validate_if and validate_unless conditions.
  """

  @doc """
  Check if a field should be validated based on conditional options.

  Returns true if the field should be validated, false otherwise.
  """
  def should_validate?(changeset, opts) do
    cond do
      validate_if = opts[:validate_if] ->
        call_condition(validate_if, changeset)

      validate_unless = opts[:validate_unless] ->
        !call_condition(validate_unless, changeset)

      true ->
        true
    end
  end

  # Call conditional function - supports both MFA tuples and functions at runtime
  defp call_condition({module, function}, changeset) when is_atom(module) and is_atom(function) do
    apply(module, function, [changeset])
  end

  defp call_condition({module, function, args}, changeset)
       when is_atom(module) and is_atom(function) do
    apply(module, function, [changeset | args])
  end

  defp call_condition(fun, changeset) when is_function(fun, 1) do
    fun.(changeset)
  end

  defp call_condition(_, _), do: true
end
