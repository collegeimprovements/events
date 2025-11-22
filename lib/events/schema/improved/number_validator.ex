defmodule Events.Schema.Improved.NumberValidator do
  @moduledoc """
  Improved number validator using better pattern matching and pipelines.

  Demonstrates cleaner code patterns for number validations.
  """

  import Ecto.Changeset
  alias Events.Schema.Helpers.Messages

  # Main validation pipeline
  def validate(changeset, field, opts) do
    changeset
    |> validate_range(field, opts)
    |> validate_shortcuts(field, opts)
    |> validate_field_inclusion(field, opts)
  end

  # Range validation using pipeline
  defp validate_range(changeset, field, opts) do
    opts
    |> build_range_options()
    |> apply_number_validation(changeset, field, opts)
  end

  # Build range options using pattern matching
  defp build_range_options(opts) do
    []
    |> add_range_option(:min, :greater_than_or_equal_to, opts)
    |> add_range_option(:max, :less_than_or_equal_to, opts)
    |> add_range_option(:greater_than, :greater_than, opts)
    |> add_range_option(:less_than, :less_than, opts)
    |> add_range_option(:greater_than_or_equal_to, :greater_than_or_equal_to, opts)
    |> add_range_option(:less_than_or_equal_to, :less_than_or_equal_to, opts)
    |> add_range_option(:equal_to, :equal_to, opts)
    |> add_range_option(:not_equal_to, :not_equal_to, opts)
  end

  # Add range option with pattern matching
  defp add_range_option(acc, source_key, target_key, opts) do
    case extract_value_and_message(opts[source_key]) do
      {nil, _} -> acc
      {value, nil} -> Keyword.put(acc, target_key, value)
      {value, msg} -> acc |> Keyword.put(target_key, value) |> Keyword.put(:message, msg)
    end
  end

  # Extract value and message using pattern matching
  defp extract_value_and_message(nil), do: {nil, nil}
  defp extract_value_and_message({value, [message: msg]}), do: {value, msg}
  defp extract_value_and_message({value, _}), do: {value, nil}
  defp extract_value_and_message(value), do: {value, nil}

  # Apply number validation if options exist
  defp apply_number_validation([], changeset, _, _), do: changeset

  defp apply_number_validation(number_opts, changeset, field, opts) do
    final_opts = Messages.add_to_opts(number_opts, opts, :number)
    validate_number(changeset, field, final_opts)
  end

  # Validate shortcuts using pattern matching
  defp validate_shortcuts(changeset, field, opts) do
    shortcuts = [
      positive: {:greater_than, 0},
      non_negative: {:greater_than_or_equal_to, 0},
      negative: {:less_than, 0},
      non_positive: {:less_than_or_equal_to, 0}
    ]

    Enum.reduce(shortcuts, changeset, fn {shortcut, {validation, value}}, acc ->
      if opts[shortcut] do
        validate_number(acc, field, [{validation, value}])
      else
        acc
      end
    end)
  end

  # Inclusion validation with better flow
  defp validate_field_inclusion(changeset, field, opts) do
    case opts[:in] do
      nil ->
        changeset

      values when is_list(values) ->
        opts
        |> Messages.add_to_opts([], :inclusion)
        |> then(&validate_inclusion(changeset, field, values, &1))
    end
  end
end
