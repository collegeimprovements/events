defmodule Events.Core.Schema.Errors do
  @moduledoc """
  Error handling and prioritization for Events.Core.Schema validations.

  Provides utilities for organizing, prioritizing, and formatting validation errors.
  """

  @type error_tuple :: {atom(), {String.t(), keyword()}}
  @type prioritized_errors :: %{
          high: [error_tuple()],
          medium: [error_tuple()],
          low: [error_tuple()]
        }

  @error_priorities %{
    # High priority - fundamental issues
    required: 1,
    cast: 1,
    type: 2,

    # Medium priority - format and structure
    format: 3,
    acceptance: 3,
    confirmation: 3,

    # Lower priority - constraints
    length: 4,
    min_length: 4,
    max_length: 4,

    # Lowest priority - business rules
    unique: 5,
    foreign_key: 5,
    check: 5,
    custom: 6
  }

  @doc """
  Sort errors by priority.

  Required fields and type errors come first, followed by format errors,
  then length/range validations, and finally custom validations.
  """
  @spec prioritize(Ecto.Changeset.t()) :: [error_tuple()]
  def prioritize(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.sort_by(&error_priority/1)
  end

  @doc """
  Group errors by priority level.
  """
  @spec group_by_priority(Ecto.Changeset.t()) :: prioritized_errors()
  def group_by_priority(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.group_by(&priority_level/1)
    |> Map.put_new(:high, [])
    |> Map.put_new(:medium, [])
    |> Map.put_new(:low, [])
  end

  @doc """
  Get only the highest priority error for each field.
  """
  @spec highest_priority_per_field(Ecto.Changeset.t()) :: [error_tuple()]
  def highest_priority_per_field(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.group_by(fn {field, _} -> field end)
    |> Enum.map(fn {_field, field_errors} ->
      field_errors
      |> Enum.min_by(&error_priority/1)
    end)
  end

  @doc """
  Format errors as a simple map of field => [messages].
  """
  @spec to_simple_map(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def to_simple_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Format errors as a flat list of messages.
  """
  @spec to_flat_list(Ecto.Changeset.t()) :: [String.t()]
  def to_flat_list(changeset) do
    changeset
    |> to_simple_map()
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn msg ->
        "#{humanize(field)}: #{msg}"
      end)
    end)
  end

  @doc """
  Format errors as a user-friendly message.
  """
  @spec to_message(Ecto.Changeset.t()) :: String.t()
  def to_message(changeset) do
    case to_flat_list(changeset) do
      [] ->
        "No errors"

      [single] ->
        single

      multiple ->
        "Multiple validation errors:\n" <>
          (multiple |> Enum.map(&"  • #{&1}") |> Enum.join("\n"))
    end
  end

  @doc """
  Get errors for a specific field.
  """
  @spec for_field(Ecto.Changeset.t(), atom()) :: [String.t()]
  def for_field(changeset, field) do
    changeset
    |> to_simple_map()
    |> Map.get(field, [])
  end

  @doc """
  Check if a specific validation error exists.
  """
  @spec has_error?(Ecto.Changeset.t(), atom(), atom() | String.t()) :: boolean()
  def has_error?(changeset, field, validation_type) when is_atom(validation_type) do
    changeset.errors
    |> Enum.any?(fn
      {^field, {_, opts}} -> Keyword.get(opts, :validation) == validation_type
      _ -> false
    end)
  end

  def has_error?(changeset, field, message) when is_binary(message) do
    field
    |> for_field(changeset)
    |> Enum.any?(&(&1 == message))
  end

  @doc """
  Count total errors in changeset.
  """
  @spec count_errors(Ecto.Changeset.t()) :: non_neg_integer()
  def count_errors(%Ecto.Changeset{errors: errors}) do
    length(errors)
  end

  @doc """
  Count unique fields with errors.
  """
  @spec count_fields_with_errors(Ecto.Changeset.t()) :: non_neg_integer()
  def count_fields_with_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, _} -> field end)
    |> Enum.uniq()
    |> length()
  end

  @doc """
  Merge errors from multiple changesets.
  """
  @spec merge([Ecto.Changeset.t()]) :: [error_tuple()]
  def merge(changesets) do
    changesets
    |> Enum.flat_map(& &1.errors)
    |> Enum.uniq()
  end

  @doc """
  Clear errors for specific fields.
  """
  @spec clear_fields(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  def clear_fields(changeset, fields) do
    errors =
      changeset.errors
      |> Enum.reject(fn {field, _} -> field in fields end)

    %{changeset | errors: errors, valid?: errors == []}
  end

  @doc """
  Add context to error messages.
  """
  @spec add_context(Ecto.Changeset.t(), String.t()) :: Ecto.Changeset.t()
  def add_context(changeset, context) do
    errors =
      changeset.errors
      |> Enum.map(fn {field, {msg, opts}} ->
        {field, {"#{context}: #{msg}", opts}}
      end)

    %{changeset | errors: errors}
  end

  # Private helpers

  defp error_priority({_field, {_msg, opts}}) do
    validation = Keyword.get(opts, :validation)
    Map.get(@error_priorities, validation, 999)
  end

  defp error_priority({_field, _msg}) do
    999
  end

  defp priority_level(error) do
    case error_priority(error) do
      p when p <= 2 -> :high
      p when p <= 4 -> :medium
      _ -> :low
    end
  end

  defp humanize(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
