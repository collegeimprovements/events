defmodule OmSchema.Helpers.Length do
  @moduledoc """
  Shared length validation helpers for strings, arrays, and maps.

  Provides consistent length validation logic across different validator modules,
  eliminating duplication between String, Array, and Map validators.

  ## Usage

  These helpers are used internally by type-specific validators. You generally
  won't call them directly, but through the validator modules.

  ## Examples

      # In a custom validator
      import OmSchema.Helpers.Length

      def validate(changeset, field, opts) do
        changeset
        |> validate_min_length(field, opts[:min_length], opts)
        |> validate_max_length(field, opts[:max_length], opts)
      end
  """

  import Ecto.Changeset

  @doc """
  Validates minimum length for strings and arrays.

  Supports custom messages via `min_length_message` option.

  ## Options

  - `min_length_message` - Custom error message (supports `%{count}` interpolation)

  ## Examples

      validate_min_length(changeset, :name, 3, [])
      validate_min_length(changeset, :tags, 1, min_length_message: "must have at least %{count} tag(s)")
  """
  @spec validate_min_length(Ecto.Changeset.t(), atom(), non_neg_integer() | nil, keyword()) ::
          Ecto.Changeset.t()
  def validate_min_length(changeset, _field, nil, _opts), do: changeset

  def validate_min_length(changeset, field, min, opts) when is_integer(min) do
    message = Keyword.get(opts, :min_length_message, default_min_message(field, changeset))
    validate_length(changeset, field, min: min, message: message)
  end

  @doc """
  Validates maximum length for strings and arrays.

  Supports custom messages via `max_length_message` option.

  ## Options

  - `max_length_message` - Custom error message (supports `%{count}` interpolation)
  """
  @spec validate_max_length(Ecto.Changeset.t(), atom(), non_neg_integer() | nil, keyword()) ::
          Ecto.Changeset.t()
  def validate_max_length(changeset, _field, nil, _opts), do: changeset

  def validate_max_length(changeset, field, max, opts) when is_integer(max) do
    message = Keyword.get(opts, :max_length_message, default_max_message(field, changeset))
    validate_length(changeset, field, max: max, message: message)
  end

  @doc """
  Validates exact length for strings and arrays.

  Supports custom messages via `length_message` option.

  ## Options

  - `length_message` - Custom error message (supports `%{count}` interpolation)
  """
  @spec validate_exact_length(Ecto.Changeset.t(), atom(), non_neg_integer() | nil, keyword()) ::
          Ecto.Changeset.t()
  def validate_exact_length(changeset, _field, nil, _opts), do: changeset

  def validate_exact_length(changeset, field, length, opts) when is_integer(length) do
    message = Keyword.get(opts, :length_message)
    validate_length(changeset, field, is: length, message: message)
  end

  @doc """
  Validates length using min/max/exact options from a keyword list.

  This is a convenience function that checks for `:min_length`, `:max_length`,
  and `:length` options and applies the appropriate validations.

  ## Options

  - `:min_length` - Minimum length
  - `:max_length` - Maximum length
  - `:length` - Exact length (overrides min/max if present)

  ## Examples

      validate_length_opts(changeset, :name, min_length: 2, max_length: 100)
      validate_length_opts(changeset, :code, length: 6)
  """
  @spec validate_length_opts(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_length_opts(changeset, field, opts) do
    cond do
      # Exact length takes precedence
      length = opts[:length] ->
        validate_exact_length(changeset, field, length, opts)

      # Otherwise apply min/max
      true ->
        changeset
        |> validate_min_length(field, opts[:min_length], opts)
        |> validate_max_length(field, opts[:max_length], opts)
    end
  end

  @doc """
  Validates array length with custom item terminology.

  Unlike `validate_length/3`, this provides array-specific error messages
  referring to "items" instead of "characters".

  ## Options

  - `:min_length` - Minimum number of items
  - `:max_length` - Maximum number of items
  - `:length` - Exact number of items
  """
  @spec validate_array_length(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_array_length(changeset, field, opts) do
    changeset
    |> maybe_validate_array_min(field, opts[:min_length])
    |> maybe_validate_array_max(field, opts[:max_length])
    |> maybe_validate_array_exact(field, opts[:length])
  end

  defp maybe_validate_array_min(changeset, _field, nil), do: changeset

  defp maybe_validate_array_min(changeset, field, min) do
    validate_change(changeset, field, fn _, value ->
      if is_list(value) and length(value) >= min do
        []
      else
        [{field, "should have at least #{min} item(s)"}]
      end
    end)
  end

  defp maybe_validate_array_max(changeset, _field, nil), do: changeset

  defp maybe_validate_array_max(changeset, field, max) do
    validate_change(changeset, field, fn _, value ->
      if is_list(value) and length(value) <= max do
        []
      else
        [{field, "should have at most #{max} item(s)"}]
      end
    end)
  end

  defp maybe_validate_array_exact(changeset, _field, nil), do: changeset

  defp maybe_validate_array_exact(changeset, field, count) do
    validate_change(changeset, field, fn _, value ->
      if is_list(value) and length(value) == count do
        []
      else
        [{field, "should have exactly #{count} item(s)"}]
      end
    end)
  end

  @doc """
  Validates map size (number of keys).

  ## Options

  - `:min_keys` - Minimum number of keys
  - `:max_keys` - Maximum number of keys
  """
  @spec validate_map_size(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_map_size(changeset, field, opts) do
    changeset
    |> maybe_validate_map_min_keys(field, opts[:min_keys])
    |> maybe_validate_map_max_keys(field, opts[:max_keys])
  end

  defp maybe_validate_map_min_keys(changeset, _field, nil), do: changeset

  defp maybe_validate_map_min_keys(changeset, field, min) do
    validate_change(changeset, field, fn _, value ->
      if is_map(value) and map_size(value) >= min do
        []
      else
        [{field, "should have at least #{min} key(s)"}]
      end
    end)
  end

  defp maybe_validate_map_max_keys(changeset, _field, nil), do: changeset

  defp maybe_validate_map_max_keys(changeset, field, max) do
    validate_change(changeset, field, fn _, value ->
      if is_map(value) and map_size(value) <= max do
        []
      else
        [{field, "should have at most #{max} key(s)"}]
      end
    end)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp default_min_message(field, changeset) do
    case get_field_type(changeset, field) do
      {:array, _} -> "should have at least %{count} item(s)"
      :map -> "should have at least %{count} key(s)"
      _ -> nil
    end
  end

  defp default_max_message(field, changeset) do
    case get_field_type(changeset, field) do
      {:array, _} -> "should have at most %{count} item(s)"
      :map -> "should have at most %{count} key(s)"
      _ -> nil
    end
  end

  defp get_field_type(changeset, field) do
    if changeset.data && changeset.data.__struct__ do
      changeset.data.__struct__.__schema__(:type, field)
    end
  rescue
    _ -> nil
  end
end
