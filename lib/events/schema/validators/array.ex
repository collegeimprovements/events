defmodule Events.Schema.Validators.Array do
  @moduledoc """
  Array-specific validations for enhanced schema fields.

  Provides length, subset, and item-level validations for array fields.

  Implements `Events.Schema.Behaviours.Validator` behavior.
  """

  @behaviour Events.Schema.Behaviours.Validator

  alias Events.Schema.Helpers.Messages

  @impl true
  def field_types, do: [:array]

  @impl true
  def supported_options do
    [:min_length, :max_length, :length, :in, :item_format, :item_min, :item_max, :unique_items]
  end

  @doc """
  Apply all array validations to a changeset.
  """
  @impl true
  def validate(changeset, field_name, opts) do
    changeset
    |> apply_array_length_validation(field_name, opts)
    |> apply_subset_validation(field_name, opts)
    |> apply_items_validation(field_name, opts)
  end

  # Array length validation

  defp apply_array_length_validation(changeset, field_name, opts) do
    changeset
    |> validate_array_min_length(field_name, opts)
    |> validate_array_max_length(field_name, opts)
    |> validate_array_exact_length(field_name, opts)
  end

  defp validate_array_min_length(changeset, field_name, opts) do
    case opts[:min_length] do
      nil ->
        changeset

      {min_val, inline_opts} when is_list(inline_opts) ->
        Ecto.Changeset.validate_length(changeset, field_name,
          min: min_val,
          message: inline_opts[:message]
        )

      min_val ->
        msg = Messages.get_from_opts(opts, :length)

        if msg do
          Ecto.Changeset.validate_length(changeset, field_name, min: min_val, message: msg)
        else
          Ecto.Changeset.validate_length(changeset, field_name, min: min_val)
        end
    end
  end

  defp validate_array_max_length(changeset, field_name, opts) do
    case opts[:max_length] do
      nil ->
        changeset

      {max_val, inline_opts} when is_list(inline_opts) ->
        Ecto.Changeset.validate_length(changeset, field_name,
          max: max_val,
          message: inline_opts[:message]
        )

      max_val ->
        msg = Messages.get_from_opts(opts, :length)

        if msg do
          Ecto.Changeset.validate_length(changeset, field_name, max: max_val, message: msg)
        else
          Ecto.Changeset.validate_length(changeset, field_name, max: max_val)
        end
    end
  end

  defp validate_array_exact_length(changeset, field_name, opts) do
    case opts[:length] do
      nil ->
        changeset

      {len_val, inline_opts} when is_list(inline_opts) ->
        Ecto.Changeset.validate_length(changeset, field_name,
          is: len_val,
          message: inline_opts[:message]
        )

      len_val ->
        msg = Messages.get_from_opts(opts, :length)

        if msg do
          Ecto.Changeset.validate_length(changeset, field_name, is: len_val, message: msg)
        else
          Ecto.Changeset.validate_length(changeset, field_name, is: len_val)
        end
    end
  end

  # Subset validation

  defp apply_subset_validation(changeset, field_name, opts) do
    case opts[:in] do
      nil ->
        changeset

      values when is_list(values) ->
        subset_opts = Messages.add_to_opts([], opts, :subset)
        Ecto.Changeset.validate_subset(changeset, field_name, values, subset_opts)
    end
  end

  # Item validations

  defp apply_items_validation(changeset, field_name, opts) do
    case Ecto.Changeset.get_change(changeset, field_name) do
      nil ->
        changeset

      items when is_list(items) ->
        changeset
        |> validate_item_format(field_name, items, opts)
        |> validate_item_range(field_name, items, opts)
        |> validate_unique_items(field_name, items, opts)

      _ ->
        changeset
    end
  end

  defp validate_item_format(changeset, field_name, items, opts) do
    case opts[:item_format] do
      nil ->
        changeset

      %Regex{} = regex ->
        invalid = Enum.reject(items, fn item -> is_binary(item) && String.match?(item, regex) end)

        if invalid != [] do
          Ecto.Changeset.add_error(
            changeset,
            field_name,
            "contains invalid items: #{inspect(invalid)}"
          )
        else
          changeset
        end
    end
  end

  defp validate_item_range(changeset, field_name, items, opts) do
    min = opts[:item_min]
    max = opts[:item_max]

    if (min || max) && Enum.all?(items, &is_number/1) do
      invalid =
        Enum.filter(items, fn item ->
          (min && item < min) || (max && item > max)
        end)

      if invalid != [] do
        Ecto.Changeset.add_error(
          changeset,
          field_name,
          "contains out of range items: #{inspect(invalid)}"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_unique_items(changeset, field_name, items, opts) do
    if opts[:unique_items] do
      if length(items) != length(Enum.uniq(items)) do
        Ecto.Changeset.add_error(changeset, field_name, "must have unique items")
      else
        changeset
      end
    else
      changeset
    end
  end
end
