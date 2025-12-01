defmodule Events.Core.Schema.Validators.Number do
  @moduledoc """
  Number-specific validations for enhanced schema fields.

  Provides range, comparison, and inclusion validations for numeric fields
  (integer, float, decimal).

  Implements `Events.Core.Schema.Behaviours.Validator` behavior.
  """

  @behaviour Events.Core.Schema.Behaviours.Validator

  alias Events.Core.Schema.Helpers.Messages

  @impl true
  def field_types, do: [:integer, :float, :decimal]

  @impl true
  def supported_options do
    [
      :min,
      :max,
      :positive,
      :non_negative,
      :negative,
      :non_positive,
      :greater_than,
      :gt,
      :greater_than_or_equal_to,
      :gte,
      :less_than,
      :lt,
      :less_than_or_equal_to,
      :lte,
      :equal_to,
      :eq,
      :in
    ]
  end

  @doc """
  Apply all number validations to a changeset.
  """
  @impl true
  def validate(changeset, field_name, opts) do
    changeset
    |> apply_number_range_validation(field_name, opts)
    |> apply_inclusion_validation(field_name, opts)
  end

  # Number range validation

  defp apply_number_range_validation(changeset, field_name, opts) do
    number_opts = build_number_opts(opts)

    if number_opts != [] do
      Ecto.Changeset.validate_number(changeset, field_name, number_opts)
    else
      changeset
    end
  end

  defp build_number_opts(opts) do
    []
    |> add_min_max_aliases(opts)
    |> add_full_ecto_options(opts)
    |> add_shortcut_options(opts)
    |> Messages.add_to_opts(opts, :number)
    |> add_tuple_messages(opts)
  end

  # Simple min/max aliases
  defp add_min_max_aliases(number_opts, opts) do
    number_opts
    |> put_if_present(:greater_than_or_equal_to, extract_value(opts[:min]))
    |> put_if_present(:less_than_or_equal_to, extract_value(opts[:max]))
  end

  # Full Ecto number options (including tuple shortcuts)
  defp add_full_ecto_options(number_opts, opts) do
    number_opts
    |> put_if_present(:greater_than, extract_comparison_value(opts[:greater_than] || opts[:gt]))
    |> put_if_present(
      :greater_than_or_equal_to,
      extract_comparison_value(opts[:greater_than_or_equal_to] || opts[:gte])
    )
    |> put_if_present(:less_than, extract_comparison_value(opts[:less_than] || opts[:lt]))
    |> put_if_present(
      :less_than_or_equal_to,
      extract_comparison_value(opts[:less_than_or_equal_to] || opts[:lte])
    )
    |> put_if_present(:equal_to, extract_comparison_value(opts[:equal_to] || opts[:eq]))
  end

  # Shortcut options (positive, non_negative, etc.)
  defp add_shortcut_options(number_opts, opts) do
    number_opts
    |> maybe_add_positive(opts)
    |> maybe_add_non_negative(opts)
    |> maybe_add_negative(opts)
    |> maybe_add_non_positive(opts)
  end

  # Tuple messages for min/max and comparison shortcuts
  defp add_tuple_messages(number_opts, opts) do
    number_opts
    |> add_message_from_tuple(opts[:min], :greater_than_or_equal_to)
    |> add_message_from_tuple(opts[:max], :less_than_or_equal_to)
    |> add_message_from_tuple(opts[:gt], :greater_than)
    |> add_message_from_tuple(opts[:gte], :greater_than_or_equal_to)
    |> add_message_from_tuple(opts[:lt], :less_than)
    |> add_message_from_tuple(opts[:lte], :less_than_or_equal_to)
    |> add_message_from_tuple(opts[:eq], :equal_to)
    |> add_message_from_tuple(opts[:greater_than], :greater_than)
    |> add_message_from_tuple(opts[:greater_than_or_equal_to], :greater_than_or_equal_to)
    |> add_message_from_tuple(opts[:less_than], :less_than)
    |> add_message_from_tuple(opts[:less_than_or_equal_to], :less_than_or_equal_to)
    |> add_message_from_tuple(opts[:equal_to], :equal_to)
  end

  defp maybe_add_positive(number_opts, opts) do
    if opts[:positive] do
      Keyword.put(number_opts, :greater_than, 0)
    else
      number_opts
    end
  end

  defp maybe_add_non_negative(number_opts, opts) do
    if opts[:non_negative] do
      Keyword.put(number_opts, :greater_than_or_equal_to, 0)
    else
      number_opts
    end
  end

  defp maybe_add_negative(number_opts, opts) do
    if opts[:negative] do
      Keyword.put(number_opts, :less_than, 0)
    else
      number_opts
    end
  end

  defp maybe_add_non_positive(number_opts, opts) do
    if opts[:non_positive] do
      Keyword.put(number_opts, :less_than_or_equal_to, 0)
    else
      number_opts
    end
  end

  # Inclusion validation
  #
  # For numeric fields, ranges are converted to min/max validations rather than inclusion lists
  # because floating point values won't match integer list items (e.g., 50.5 not in [0..100])

  defp apply_inclusion_validation(changeset, field_name, opts) do
    case opts[:in] do
      nil ->
        changeset

      # Range directly: in: 0..100 - use range validation instead of inclusion
      %Range{first: min_val, last: max_val} ->
        number_opts =
          []
          |> Keyword.put(:greater_than_or_equal_to, min_val)
          |> Keyword.put(:less_than_or_equal_to, max_val)
          |> Messages.add_to_opts(opts, :number)

        Ecto.Changeset.validate_number(changeset, field_name, number_opts)

      # Range in list: in: [0..100] - extract range
      [%Range{first: min_val, last: max_val}] ->
        number_opts =
          []
          |> Keyword.put(:greater_than_or_equal_to, min_val)
          |> Keyword.put(:less_than_or_equal_to, max_val)
          |> Messages.add_to_opts(opts, :number)

        Ecto.Changeset.validate_number(changeset, field_name, number_opts)

      # List of specific values: in: [1, 2, 3] - use inclusion validation
      values when is_list(values) ->
        inclusion_opts = Messages.add_to_opts([], opts, :inclusion)
        Ecto.Changeset.validate_inclusion(changeset, field_name, values, inclusion_opts)
    end
  end

  # Helper functions

  defp put_if_present(list, _key, nil), do: list
  defp put_if_present(list, key, value), do: Keyword.put(list, key, value)

  # Extract comparison value from tuples or direct values
  defp extract_comparison_value({value, _opts}), do: value
  defp extract_comparison_value(value), do: value

  # Legacy support for min/max
  defp extract_value({value, _opts}), do: value
  defp extract_value(value), do: value

  defp add_message_from_tuple(validation_opts, {_value, inline_opts}, _key)
       when is_list(inline_opts) do
    if msg = inline_opts[:message] do
      Keyword.put(validation_opts, :message, msg)
    else
      validation_opts
    end
  end

  defp add_message_from_tuple(validation_opts, _field_value, _key), do: validation_opts
end
