defmodule Events.Query.PaginationValidator do
  @moduledoc """
  Validates cursor pagination configuration to prevent data loss.

  Ensures cursor_fields match order_by specification exactly to avoid
  skipped or duplicated records during pagination.
  """

  require Logger

  @type order_spec :: {atom(), :asc | :desc} | atom()
  @type cursor_spec :: {atom(), :asc | :desc} | atom()
  @type validation_result :: :ok | {:error, String.t()}

  @doc """
  Validates that cursor_fields match order_by specification.

  ## Rules

  1. cursor_fields must contain all fields from order_by in the same order
  2. Directions must match if specified
  3. cursor_fields can have one extra field at the end (typically :id)
  4. If cursor_fields is nil, it will be inferred (no validation needed)

  ## Examples

      # Valid - exact match
      validate([{:title, :asc}], [{:title, :asc}])
      # => :ok

      # Valid - with :id appended
      validate([{:title, :asc}, {:age, :desc}], [{:title, :asc}, {:age, :desc}, {:id, :asc}])
      # => :ok

      # Invalid - wrong order
      validate([{:title, :asc}, {:age, :desc}], [{:age, :desc}, {:title, :asc}])
      # => {:error, "cursor_fields order must match order_by specification"}

      # Invalid - wrong direction
      validate([{:title, :asc}], [{:title, :desc}])
      # => {:error, "cursor_fields direction for :title must be :asc, got :desc"}
  """
  @spec validate(list(order_spec()), list(cursor_spec()) | nil) :: validation_result()
  # Will be inferred
  def validate(_order_by, nil), do: :ok
  # No order_by to validate against
  def validate([], _cursor_fields), do: :ok

  def validate(order_by, cursor_fields) when is_list(order_by) and is_list(cursor_fields) do
    normalized_order = normalize_specs(order_by)
    normalized_cursor = normalize_specs(cursor_fields)

    cond do
      # Check if cursor_fields is a prefix of order_by (with optional :id at end)
      is_valid_prefix?(normalized_order, normalized_cursor) ->
        :ok

      # Check if they're completely different
      true ->
        check_mismatch(normalized_order, normalized_cursor)
    end
  end

  @doc """
  Infers cursor_fields from order_by specification.

  Includes field directions and automatically appends {:id, :asc} if not present.

  ## Examples

      infer([{:title, :asc}, {:age, :desc}])
      # => [{:title, :asc}, {:age, :desc}, {:id, :asc}]

      infer([{:title, :asc}, {:id, :desc}])
      # => [{:title, :asc}, {:id, :desc}]  # :id already present

      infer([:title, :age])
      # => [{:title, :asc}, {:age, :asc}, {:id, :asc}]

      infer([])
      # => [{:id, :asc}]
  """
  @spec infer(list(order_spec())) :: list(cursor_spec())
  def infer([]) do
    [{:id, :asc}]
  end

  def infer(order_by) when is_list(order_by) do
    normalized = normalize_specs(order_by)

    # Check if :id is already present
    has_id? = Enum.any?(normalized, fn {field, _dir} -> field == :id end)

    if has_id? do
      normalized
    else
      normalized ++ [{:id, :asc}]
    end
  end

  @doc """
  Validates and returns cursor_fields, inferring if needed.

  If cursor_fields are provided, validates them against order_by.
  If cursor_fields are nil, infers them from order_by.
  Logs warnings for validation failures and halts with error.

  ## Examples

      validate_or_infer([{:title, :asc}], nil)
      # => {:ok, [{:title, :asc}, {:id, :asc}]}

      validate_or_infer([{:title, :asc}], [{:title, :asc}, {:id, :asc}])
      # => {:ok, [{:title, :asc}, {:id, :asc}]}

      validate_or_infer([{:title, :asc}], [{:title, :desc}])
      # => {:error, "cursor_fields direction for :title must be :asc, got :desc"}
  """
  @spec validate_or_infer(list(order_spec()), list(cursor_spec()) | nil) ::
          {:ok, list(cursor_spec())} | {:error, String.t()}
  def validate_or_infer(order_by, cursor_fields \\ nil)

  def validate_or_infer(order_by, nil) do
    inferred = infer(order_by)
    Logger.debug("Inferred cursor_fields from order_by: #{inspect(inferred)}")
    {:ok, inferred}
  end

  def validate_or_infer(order_by, cursor_fields) do
    case validate(order_by, cursor_fields) do
      :ok ->
        {:ok, normalize_specs(cursor_fields)}

      {:error, reason} = error ->
        Logger.error("""
        Cursor pagination validation FAILED:
        #{reason}

        order_by:      #{inspect(order_by)}
        cursor_fields: #{inspect(cursor_fields)}

        This will cause incorrect pagination results!
        Either remove cursor_fields to allow automatic inference,
        or fix cursor_fields to match order_by exactly.
        """)

        error
    end
  end

  # Private helpers

  defp normalize_specs(specs) do
    Enum.map(specs, &normalize_one/1)
  end

  defp normalize_one({:order, field, dir, _opts}), do: {field, dir}
  defp normalize_one({field, dir, _opts}), do: {field, dir}
  defp normalize_one({field, dir}), do: {field, dir}
  defp normalize_one(field) when is_atom(field), do: {field, :asc}

  defp is_valid_prefix?(order_specs, cursor_specs) do
    # cursor_specs should start with all order_specs fields (in same order)
    # and can have at most one extra field at the end (must be :id)

    order_count = length(order_specs)
    cursor_count = length(cursor_specs)

    cond do
      # cursor_specs has fewer fields than order_specs
      cursor_count < order_count ->
        false

      # cursor_specs has more than 1 extra field
      cursor_count > order_count + 1 ->
        false

      # Exactly matches (no extra fields)
      cursor_count == order_count ->
        order_specs == cursor_specs

      # Has one extra field - must be :id
      cursor_count == order_count + 1 ->
        first_n_match = order_specs == Enum.take(cursor_specs, order_count)
        {extra_field, _dir} = Enum.at(cursor_specs, order_count)

        first_n_match and extra_field == :id

      true ->
        false
    end
  end

  defp check_mismatch(order_specs, cursor_specs) do
    order_fields = Enum.map(order_specs, fn {field, _} -> field end)
    cursor_fields = Enum.map(cursor_specs, fn {field, _} -> field end)

    order_count = length(order_fields)
    cursor_count = length(cursor_fields)

    cond do
      # cursor has too many extra fields (more than just :id)
      cursor_count > order_count + 1 ->
        extra = cursor_fields -- (order_fields -- [:id])

        {:error,
         "cursor_fields has extra fields not in order_by: #{inspect(extra)}. Only :id can be appended."}

      # cursor has one extra field but it's not :id
      cursor_count == order_count + 1 ->
        extra_field = Enum.at(cursor_fields, order_count)

        if extra_field != :id do
          {:error,
           "cursor_fields has extra field #{inspect(extra_field)}. Only :id can be appended to order_by fields."}
        else
          # Extra field is :id, check if first N fields match
          check_first_n_match(order_specs, cursor_specs, order_count)
        end

      # Different fields entirely
      MapSet.new(order_fields) != MapSet.new(cursor_fields) ->
        missing = order_fields -- cursor_fields
        extra = cursor_fields -- order_fields

        msg =
          cond do
            missing != [] ->
              "cursor_fields missing required fields from order_by: #{inspect(missing)}"

            extra != [] ->
              "cursor_fields has extra fields not in order_by: #{inspect(extra)}"

            true ->
              "cursor_fields has different fields than order_by"
          end

        {:error, msg}

      # Same fields but different order
      order_fields != cursor_fields ->
        {:error,
         "cursor_fields field order must match order_by. Expected: #{inspect(order_fields)}, got: #{inspect(cursor_fields)}"}

      # Same fields and order, but check directions
      true ->
        check_direction_mismatch(order_specs, cursor_specs)
    end
  end

  defp check_first_n_match(order_specs, cursor_specs, n) do
    order_first_n = Enum.take(order_specs, n)
    cursor_first_n = Enum.take(cursor_specs, n)

    if order_first_n != cursor_first_n do
      order_fields = Enum.map(order_first_n, fn {f, _} -> f end)
      cursor_fields = Enum.map(cursor_first_n, fn {f, _} -> f end)

      if order_fields != cursor_fields do
        {:error,
         "cursor_fields field order must match order_by. Expected: #{inspect(order_fields)}, got: #{inspect(cursor_fields)}"}
      else
        check_direction_mismatch(order_first_n, cursor_first_n)
      end
    else
      :ok
    end
  end

  defp check_direction_mismatch(order_specs, cursor_specs) do
    Enum.zip(order_specs, cursor_specs)
    |> Enum.find_value(:ok, fn
      {{field, order_dir}, {field, cursor_dir}} when order_dir != cursor_dir ->
        {:error,
         "cursor_fields direction for #{inspect(field)} must be #{inspect(order_dir)}, got #{inspect(cursor_dir)}"}

      _ ->
        nil
    end)
  end
end
