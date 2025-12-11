defmodule OmSchema.Introspection do
  @moduledoc """
  Introspection utilities for OmSchema validations.

  Provides functions to inspect and analyze schema field validations at runtime.
  Useful for documentation generation, API clients, and form builders.
  """

  @doc """
  Get detailed validation information for a schema module.

  Returns a list of field specifications with their validations.
  """
  @spec inspect_schema(module()) :: [map()]
  def inspect_schema(schema_module) do
    if function_exported?(schema_module, :__field_validations__, 0) do
      schema_module.__field_validations__()
      |> Enum.map(&field_to_spec/1)
    else
      []
    end
  end

  @doc """
  Get validation rules for a specific field.
  """
  @spec inspect_field(module(), atom()) :: map() | nil
  def inspect_field(schema_module, field_name) do
    schema_module
    |> inspect_schema()
    |> Enum.find(&(&1.field == field_name))
  end

  @doc """
  Generate human-readable validation documentation for a schema.
  """
  @spec document_schema(module()) :: String.t()
  def document_schema(schema_module) do
    schema_module
    |> inspect_schema()
    |> Enum.map(&field_to_doc/1)
    |> Enum.join("\n\n")
  end

  @doc """
  Generate JSON schema from OmSchema validations.
  """
  @spec to_json_schema(module()) :: map()
  def to_json_schema(schema_module) do
    properties =
      schema_module
      |> inspect_schema()
      |> Map.new(fn spec ->
        {spec.field, field_to_json_schema(spec)}
      end)

    required_fields =
      schema_module
      |> inspect_schema()
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.field)

    %{
      type: "object",
      properties: properties,
      required: required_fields
    }
  end

  @doc """
  Check if a field has specific validation.
  """
  @spec has_validation?(module(), atom(), atom()) :: boolean()
  def has_validation?(schema_module, field_name, validation_type) do
    case inspect_field(schema_module, field_name) do
      nil -> false
      spec -> Map.has_key?(spec.validations, validation_type)
    end
  end

  @doc """
  Get all required fields for a schema.
  """
  @spec required_fields(module()) :: [atom()]
  def required_fields(schema_module) do
    schema_module
    |> inspect_schema()
    |> Enum.filter(& &1.required)
    |> Enum.map(& &1.field)
  end

  @doc """
  Get all fields with a specific validation.
  """
  @spec fields_with_validation(module(), atom()) :: [atom()]
  def fields_with_validation(schema_module, validation_type) do
    schema_module
    |> inspect_schema()
    |> Enum.filter(&Map.has_key?(&1.validations, validation_type))
    |> Enum.map(& &1.field)
  end

  # Private helpers

  defp field_to_spec({name, type, opts}) do
    %{
      field: name,
      type: normalize_type(type),
      required: Keyword.get(opts, :required, false),
      required_when: Keyword.get(opts, :required_when),
      nullable: Keyword.get(opts, :null, !Keyword.get(opts, :required, false)),
      default: Keyword.get(opts, :default),
      cast: Keyword.get(opts, :cast, true),
      immutable: Keyword.get(opts, :immutable, false),
      sensitive: Keyword.get(opts, :sensitive, false),
      doc: Keyword.get(opts, :doc),
      example: Keyword.get(opts, :example),
      validations: extract_validations(opts),
      normalizations: extract_normalizations(opts)
    }
  end

  defp normalize_type({:array, inner}), do: {:array, normalize_type(inner)}
  defp normalize_type({:map, inner}), do: {:map, inner}
  defp normalize_type(type), do: type

  defp extract_validations(opts) do
    opts
    |> Enum.filter(fn {k, _v} -> k in validation_keys() end)
    |> Map.new()
    |> format_validation_values()
  end

  defp validation_keys do
    [
      :min_length,
      :max_length,
      :length,
      :min,
      :max,
      :greater_than,
      :less_than,
      :greater_than_or_equal_to,
      :less_than_or_equal_to,
      :equal_to,
      :not_equal_to,
      :positive,
      :non_negative,
      :negative,
      :non_positive,
      :format,
      :in,
      :not_in,
      :unique_items,
      :item_format,
      :item_min,
      :item_max,
      :required_keys,
      :forbidden_keys,
      :min_keys,
      :max_keys,
      :past,
      :future,
      :after,
      :before,
      :acceptance,
      :unique,
      :foreign_key,
      :check
    ]
  end

  defp extract_normalizations(opts) do
    case Keyword.get(opts, :normalize) do
      nil -> []
      list when is_list(list) -> list
      single -> [single]
    end
  end

  defp format_validation_values(validations) do
    Map.new(validations, fn
      {key, {value, _opts}} -> {key, value}
      {key, value} -> {key, value}
    end)
  end

  defp field_to_doc(spec) do
    validations = format_validations_doc(spec.validations)
    normalizations = format_normalizations_doc(spec.normalizations)

    doc = """
    **#{spec.field}** (#{spec.type})
      Required: #{spec.required}
      Nullable: #{spec.nullable}
      Cast: #{spec.cast}
    """

    doc =
      if spec.required_when do
        doc <> "  Required when: #{inspect(spec.required_when)}\n"
      else
        doc
      end

    doc =
      if spec.immutable do
        doc <> "  Immutable: true\n"
      else
        doc
      end

    doc =
      if spec.sensitive do
        doc <> "  Sensitive: true (redacted in logs)\n"
      else
        doc
      end

    doc =
      if spec.doc do
        doc <> "  Description: #{spec.doc}\n"
      else
        doc
      end

    doc =
      if spec.example do
        doc <> "  Example: #{inspect(spec.example)}\n"
      else
        doc
      end

    doc =
      if spec.default do
        doc <> "  Default: #{inspect(spec.default)}\n"
      else
        doc
      end

    doc =
      if validations != "" do
        doc <> "  Validations:\n#{validations}"
      else
        doc
      end

    if normalizations != "" do
      doc <> "  Normalizations: #{normalizations}"
    else
      doc
    end
  end

  defp format_validations_doc(validations) when map_size(validations) == 0, do: ""

  defp format_validations_doc(validations) do
    validations
    |> Enum.map(fn {k, v} -> "    - #{k}: #{inspect(v)}" end)
    |> Enum.join("\n")
  end

  defp format_normalizations_doc([]), do: ""
  defp format_normalizations_doc(norms), do: inspect(norms)

  defp field_to_json_schema(spec) do
    base = %{type: type_to_json_type(spec.type)}

    base
    |> add_json_constraints(spec.validations)
    |> add_json_format(spec.validations)
    |> add_json_enum(spec.validations)
    |> add_json_default(spec.default)
    |> add_json_doc(spec.doc, spec.example)
    |> add_json_readonly(spec.immutable)
    |> add_json_write_only(spec.sensitive)
  end

  defp type_to_json_type(:string), do: "string"
  defp type_to_json_type(:citext), do: "string"
  defp type_to_json_type(:integer), do: "integer"
  defp type_to_json_type(:float), do: "number"
  defp type_to_json_type(:decimal), do: "number"
  defp type_to_json_type(:boolean), do: "boolean"
  defp type_to_json_type({:array, _}), do: "array"
  defp type_to_json_type(:map), do: "object"
  defp type_to_json_type({:map, _}), do: "object"
  defp type_to_json_type(:date), do: "string"
  defp type_to_json_type(:time), do: "string"
  defp type_to_json_type(:naive_datetime), do: "string"
  defp type_to_json_type(:utc_datetime), do: "string"
  defp type_to_json_type(_), do: "string"

  defp add_json_constraints(schema, validations) do
    schema
    |> add_if_present(validations, :min_length, :minLength)
    |> add_if_present(validations, :max_length, :maxLength)
    |> add_if_present(validations, :min, :minimum)
    |> add_if_present(validations, :max, :maximum)
  end

  defp add_json_format(schema, validations) do
    case Map.get(validations, :format) do
      :email -> Map.put(schema, :format, "email")
      :url -> Map.put(schema, :format, "uri")
      :uuid -> Map.put(schema, :format, "uuid")
      :date -> Map.put(schema, :format, "date")
      :time -> Map.put(schema, :format, "time")
      _ -> schema
    end
  end

  defp add_json_enum(schema, validations) do
    case Map.get(validations, :in) do
      nil -> schema
      values -> Map.put(schema, :enum, values)
    end
  end

  defp add_json_default(schema, nil), do: schema
  defp add_json_default(schema, default), do: Map.put(schema, :default, default)

  defp add_json_doc(schema, nil, nil), do: schema

  defp add_json_doc(schema, doc, example) do
    schema
    |> maybe_put(:description, doc)
    |> maybe_put(:examples, if(example, do: [example], else: nil))
  end

  defp add_json_readonly(schema, false), do: schema
  defp add_json_readonly(schema, true), do: Map.put(schema, :readOnly, true)

  defp add_json_write_only(schema, false), do: schema
  defp add_json_write_only(schema, true), do: Map.put(schema, :writeOnly, true)

  defp add_if_present(schema, source, source_key, target_key) do
    case Map.get(source, source_key) do
      nil -> schema
      value -> Map.put(schema, target_key, value)
    end
  end

  defp maybe_put(schema, _key, nil), do: schema
  defp maybe_put(schema, key, value), do: Map.put(schema, key, value)
end
