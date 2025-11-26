defmodule Events.Schema.Warnings do
  @moduledoc """
  Compile-time warning system for common Events.Schema mistakes.

  Detects and warns about:
  - Conflicting options
  - Performance issues
  - Common mistakes
  - Best practice violations
  """

  require Logger

  @doc """
  Check field options for potential issues and emit warnings.
  """
  @spec check_field_options(atom(), atom(), keyword()) :: :ok
  def check_field_options(field_name, field_type, opts) do
    opts
    |> check_conflicting_options(field_name)
    |> check_performance_issues(field_name, field_type)
    |> check_best_practices(field_name, field_type)
    |> check_type_mismatches(field_name, field_type)
    |> check_required_when_syntax(field_name)

    :ok
  end

  # Check for conflicting options
  defp check_conflicting_options(opts, field_name) do
    # required: true with null: true
    if opts[:required] == true && opts[:null] == true do
      warn("""
      Field '#{field_name}' has both required: true and null: true.
      These options conflict - required fields should not be nullable.
      """)
    end

    # min > max
    if opts[:min] && opts[:max] && extract_value(opts[:min]) > extract_value(opts[:max]) do
      warn("""
      Field '#{field_name}' has min (#{inspect(opts[:min])}) greater than max (#{inspect(opts[:max])}).
      This will make the field always invalid.
      """)
    end

    # min_length > max_length
    if opts[:min_length] && opts[:max_length] &&
         extract_value(opts[:min_length]) > extract_value(opts[:max_length]) do
      warn("""
      Field '#{field_name}' has min_length greater than max_length.
      This will make the field always invalid.
      """)
    end

    # positive with non_positive
    if opts[:positive] && opts[:non_positive] do
      warn("""
      Field '#{field_name}' has both positive: true and non_positive: true.
      These options are mutually exclusive.
      """)
    end

    # trim: false with normalize that includes :trim
    normalizations = List.wrap(opts[:normalize])

    if opts[:trim] == false && :trim in normalizations do
      warn("""
      Field '#{field_name}' has trim: false but normalize includes :trim.
      The normalize option will override the trim setting.
      """)
    end

    opts
  end

  # Check for performance issues
  defp check_performance_issues(opts, field_name, field_type) do
    # Large composite unique constraints
    if is_list(opts[:unique]) && length(opts[:unique]) > 3 do
      warn("""
      Field '#{field_name}' has composite unique constraint with #{length(opts[:unique])} fields.
      This may impact database performance. Consider using a database index instead.
      """)
    end

    # Complex regex on arrays
    if field_type == {:array, :string} && opts[:item_format] do
      case opts[:item_format] do
        %Regex{source: source} when byte_size(source) > 100 ->
          warn("""
          Field '#{field_name}' has complex regex validation on array items.
          This may be slow for large arrays. Consider simplifying or moving to custom validation.
          """)

        _ ->
          :ok
      end
    end

    # Many required keys on maps
    if field_type in [:map, {:map, :any}] &&
         is_list(opts[:required_keys]) &&
         length(opts[:required_keys]) > 10 do
      warn("""
      Field '#{field_name}' requires #{length(opts[:required_keys])} keys.
      Consider using an embedded schema for complex nested structures.
      """)
    end

    opts
  end

  # Check for best practice violations
  defp check_best_practices(opts, field_name, field_type) do
    # Password fields should not be trimmed
    if String.contains?(to_string(field_name), "password") && opts[:trim] != false do
      warn("""
      Field '#{field_name}' appears to be a password field but doesn't have trim: false.
      Password fields should preserve exact user input.
      """)
    end

    # Sensitive fields that look like passwords should have trim: false
    if opts[:sensitive] == true &&
         String.contains?(to_string(field_name), ["password", "secret", "token", "key"]) &&
         opts[:trim] != false do
      warn("""
      Field '#{field_name}' is marked sensitive and appears to be a secret/password.
      Consider adding trim: false to preserve exact input.
      """)
    end

    # Immutable fields shouldn't have cast: false (they need to be set initially)
    if opts[:immutable] == true && opts[:cast] == false do
      warn("""
      Field '#{field_name}' is immutable but has cast: false.
      Immutable fields need to be cast on creation. Consider allowing cast.
      """)
    end

    # Email fields should be normalized to lowercase
    if String.contains?(to_string(field_name), "email") && field_type == :string do
      normalizations = List.wrap(opts[:normalize])
      mappers = List.wrap(opts[:mappers])

      unless :downcase in normalizations or :downcase in mappers do
        warn("""
        Field '#{field_name}' appears to be an email field but doesn't normalize to lowercase.
        Consider adding mappers: [:trim, :downcase] or normalize: :downcase.
        """)
      end
    end

    # UUID fields should use binary_id type
    if String.ends_with?(to_string(field_name), "_id") && field_type == :string do
      if opts[:format] == :uuid do
        warn("""
        Field '#{field_name}' is a UUID field using :string type.
        Consider using :binary_id type instead for better performance.
        """)
      end
    end

    # Slug fields should have format validation
    if String.contains?(to_string(field_name), "slug") && field_type == :string do
      unless opts[:format] || opts[:normalize] do
        warn("""
        Field '#{field_name}' appears to be a slug field but has no format validation or normalization.
        Consider adding format: :slug or normalize: :slugify.
        """)
      end
    end

    opts
  end

  # Check for type mismatches
  defp check_type_mismatches(opts, field_name, field_type) do
    # String validations on non-string types
    if field_type not in [:string, :citext] do
      if opts[:min_length] || opts[:max_length] || opts[:format] do
        warn("""
        Field '#{field_name}' (type: #{inspect(field_type)}) has string validations.
        Length and format validations only work on string types.
        """)
      end
    end

    # Number validations on non-number types
    if field_type not in [:integer, :float, :decimal] do
      if opts[:positive] || opts[:non_negative] || opts[:greater_than] do
        warn("""
        Field '#{field_name}' (type: #{inspect(field_type)}) has number validations.
        These validations only work on numeric types.
        """)
      end
    end

    # Array validations on non-array types
    unless match?({:array, _}, field_type) do
      if opts[:unique_items] || opts[:item_format] || opts[:item_min] do
        warn("""
        Field '#{field_name}' (type: #{inspect(field_type)}) has array validations.
        These validations only work on array types.
        """)
      end
    end

    opts
  end

  defp extract_value({value, _opts}), do: value
  defp extract_value(value), do: value

  # Check required_when DSL syntax
  defp check_required_when_syntax(opts, field_name) do
    case Keyword.get(opts, :required_when) do
      nil ->
        opts

      condition ->
        case Events.Schema.ConditionalRequired.validate_syntax(condition) do
          :ok ->
            opts

          {:error, message} ->
            warn("""
            Field '#{field_name}' has invalid required_when syntax: #{message}
            """)

            opts
        end
    end
  end

  defp warn(message) do
    # Use IO.warn for compile-time warnings that show in mix compile
    IO.warn(String.trim(message), [])
  end

  @doc """
  Run validation analysis on a schema module and return a report.
  """
  @spec analyze_schema(module()) :: map()
  def analyze_schema(schema_module) do
    validations =
      if function_exported?(schema_module, :__field_validations__, 0) do
        schema_module.__field_validations__()
      else
        []
      end

    %{
      total_fields: length(validations),
      required_fields: count_required(validations),
      complex_validations: find_complex_validations(validations),
      suggestions: generate_suggestions(validations)
    }
  end

  defp count_required(validations) do
    Enum.count(validations, fn {_, _, opts} -> opts[:required] == true end)
  end

  defp find_complex_validations(validations) do
    validations
    |> Enum.filter(fn {_, _, opts} ->
      has_many_validations?(opts) || has_complex_validation?(opts)
    end)
    |> Enum.map(fn {name, _, _} -> name end)
  end

  defp has_many_validations?(opts) do
    validation_count =
      opts
      |> Enum.filter(fn {k, _} -> k in validation_option_keys() end)
      |> length()

    validation_count > 5
  end

  defp has_complex_validation?(opts) do
    opts[:validate] != nil ||
      is_list(opts[:unique]) ||
      (is_list(opts[:normalize]) && length(opts[:normalize]) > 3)
  end

  defp validation_option_keys do
    [
      :required,
      :min_length,
      :max_length,
      :format,
      :in,
      :not_in,
      :min,
      :max,
      :positive,
      :non_negative,
      :unique,
      :validate,
      :item_format,
      :required_keys,
      :past,
      :future
    ]
  end

  defp generate_suggestions(validations) do
    validations
    |> Enum.flat_map(fn {name, type, opts} ->
      suggest_for_field(name, type, opts)
    end)
    |> Enum.uniq()
  end

  defp suggest_for_field(name, _type, opts) do
    suggestions = []

    # Suggest presets
    suggestions =
      cond do
        String.contains?(to_string(name), "email") && !opts[:format] ->
          ["Consider using Events.Schema.Presets.email() for field #{name}" | suggestions]

        String.contains?(to_string(name), "url") && !opts[:format] ->
          ["Consider using Events.Schema.Presets.url() for field #{name}" | suggestions]

        String.contains?(to_string(name), "slug") && !opts[:normalize] ->
          ["Consider using Events.Schema.Presets.slug() for field #{name}" | suggestions]

        true ->
          suggestions
      end

    # Suggest indexes
    if opts[:unique] == true do
      ["Add database index for unique field #{name}" | suggestions]
    else
      suggestions
    end
  end
end
