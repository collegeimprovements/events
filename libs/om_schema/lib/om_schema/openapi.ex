defmodule OmSchema.OpenAPI do
  @moduledoc """
  Generates OpenAPI 3.x schema definitions from OmSchema modules.

  This module converts OmSchema field definitions, validations, and constraints
  into OpenAPI 3.0/3.1 compatible schema objects.

  ## Usage

      # Generate OpenAPI schema for a single module
      OmSchema.OpenAPI.to_schema(MyApp.User)

      # Generate with options
      OmSchema.OpenAPI.to_schema(MyApp.User,
        include_examples: true,
        nullable_style: :type_array  # or :nullable_property for 3.0 compat
      )

      # Generate components for multiple schemas
      OmSchema.OpenAPI.to_components([MyApp.User, MyApp.Account])

  ## OpenAPI 3.0 vs 3.1 Differences

  By default, generates OpenAPI 3.1 compatible schemas:
  - Nullable fields use `type: ["string", "null"]`
  - Uses `examples` array instead of `example`

  For OpenAPI 3.0 compatibility, use `nullable_style: :nullable_property`:
  - Nullable fields use `nullable: true`
  - Uses `example` instead of `examples`

  ## Validation Mapping

  | OmSchema Validation | OpenAPI Property |
  |---------------------|------------------|
  | `:min_length` | `minLength` |
  | `:max_length` | `maxLength` |
  | `:length` | `minLength` + `maxLength` |
  | `:min` | `minimum` |
  | `:max` | `maximum` |
  | `:format` | `format` |
  | `:in` | `enum` |
  | `:doc` | `description` |
  | `:example` | `example` / `examples` |
  | `:immutable` | `readOnly: true` |
  | `:sensitive` | `writeOnly: true` |
  """

  alias OmSchema.Introspection

  @doc """
  Generates an OpenAPI schema object from an OmSchema module.

  ## Options

    * `:include_examples` - Include example values (default: `true`)
    * `:nullable_style` - How to represent nullable fields:
      * `:type_array` - OpenAPI 3.1 style: `type: ["string", "null"]` (default)
      * `:nullable_property` - OpenAPI 3.0 style: `nullable: true`
    * `:include_id` - Include the `id` field (default: `true`)
    * `:include_timestamps` - Include timestamp fields (default: `true`)
    * `:schema_name` - Override the schema name (default: module name)

  ## Returns

  A map representing an OpenAPI Schema Object.

  ## Examples

      iex> OmSchema.OpenAPI.to_schema(MyApp.User)
      %{
        type: "object",
        properties: %{
          id: %{type: "string", format: "uuid", readOnly: true},
          email: %{type: "string", format: "email", maxLength: 255},
          name: %{type: ["string", "null"], maxLength: 100}
        },
        required: ["email"]
      }

  """
  @spec to_schema(module(), keyword()) :: map()
  def to_schema(schema_module, opts \\ []) do
    include_examples = Keyword.get(opts, :include_examples, true)
    nullable_style = Keyword.get(opts, :nullable_style, :type_array)
    include_id = Keyword.get(opts, :include_id, true)
    include_timestamps = Keyword.get(opts, :include_timestamps, true)

    field_specs = Introspection.inspect_schema(schema_module)

    # Filter fields if needed
    field_specs =
      field_specs
      |> maybe_filter_id(include_id)
      |> maybe_filter_timestamps(include_timestamps)

    properties =
      Map.new(field_specs, fn spec ->
        {spec.field, field_to_openapi(spec, nullable_style, include_examples)}
      end)

    # Add id field if needed and not already present
    properties =
      if include_id and not Map.has_key?(properties, :id) do
        id_schema = %{
          type: "string",
          format: "uuid",
          readOnly: true,
          description: "Unique identifier"
        }

        Map.put(properties, :id, id_schema)
      else
        properties
      end

    required_fields =
      field_specs
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.field)

    base_schema = %{
      type: "object",
      properties: properties
    }

    if required_fields == [] do
      base_schema
    else
      Map.put(base_schema, :required, required_fields)
    end
  end

  @doc """
  Generates OpenAPI components/schemas for multiple schema modules.

  ## Options

    * `:use_refs` - Generate `$ref` references for nested schemas (default: `true`)
    * All options from `to_schema/2`

  ## Returns

  A map suitable for the `components/schemas` section of an OpenAPI spec.

  ## Examples

      iex> OmSchema.OpenAPI.to_components([MyApp.User, MyApp.Account])
      %{
        "User" => %{type: "object", properties: %{...}},
        "Account" => %{type: "object", properties: %{...}}
      }

  """
  @spec to_components([module()], keyword()) :: map()
  def to_components(schema_modules, opts \\ []) when is_list(schema_modules) do
    Map.new(schema_modules, fn module ->
      name = schema_name(module, opts)
      schema = to_schema(module, opts)
      {name, schema}
    end)
  end

  @doc """
  Generates a complete OpenAPI paths object for CRUD operations.

  ## Options

    * `:base_path` - Base path for the resource (default: derived from module name)
    * `:operations` - List of operations to include (default: all CRUD)
    * `:tags` - Tags for the operations

  ## Examples

      iex> OmSchema.OpenAPI.to_paths(MyApp.User, base_path: "/users")
      %{
        "/users" => %{
          get: %{...},   # List
          post: %{...}   # Create
        },
        "/users/{id}" => %{
          get: %{...},    # Get
          put: %{...},    # Update
          delete: %{...}  # Delete
        }
      }

  """
  @spec to_paths(module(), keyword()) :: map()
  def to_paths(schema_module, opts \\ []) do
    name = schema_name(schema_module, opts)
    base_path = Keyword.get(opts, :base_path, "/#{String.downcase(name)}s")
    operations = Keyword.get(opts, :operations, [:list, :create, :get, :update, :delete])
    tags = Keyword.get(opts, :tags, [name])

    collection_ops = build_collection_operations(name, operations, tags)
    resource_ops = build_resource_operations(name, operations, tags)

    paths = %{}

    paths =
      if map_size(collection_ops) > 0 do
        Map.put(paths, base_path, collection_ops)
      else
        paths
      end

    paths =
      if map_size(resource_ops) > 0 do
        Map.put(paths, "#{base_path}/{id}", resource_ops)
      else
        paths
      end

    paths
  end

  @doc """
  Generates an OpenAPI document structure for a set of schemas.

  ## Options

    * `:title` - API title
    * `:version` - API version
    * `:description` - API description
    * `:servers` - List of server objects

  """
  @spec to_document([module()], keyword()) :: map()
  def to_document(schema_modules, opts \\ []) do
    title = Keyword.get(opts, :title, "API")
    version = Keyword.get(opts, :version, "1.0.0")
    description = Keyword.get(opts, :description, "Generated from OmSchema")
    servers = Keyword.get(opts, :servers, [])

    components = to_components(schema_modules, opts)

    paths =
      schema_modules
      |> Enum.map(&to_paths(&1, opts))
      |> Enum.reduce(%{}, &Map.merge/2)

    %{
      openapi: "3.1.0",
      info: %{
        title: title,
        version: version,
        description: description
      },
      servers: servers,
      paths: paths,
      components: %{
        schemas: components
      }
    }
  end

  # Private helpers

  defp field_to_openapi(spec, nullable_style, include_examples) do
    base =
      %{}
      |> add_type(spec.type, spec.nullable, nullable_style)
      |> add_format(spec.type, spec.validations)
      |> add_constraints(spec.validations)
      |> add_enum(spec.validations)
      |> add_description(spec.doc)
      |> add_default(spec.default)
      |> add_readonly(spec.immutable)
      |> add_writeonly(spec.sensitive)

    if include_examples do
      add_example(base, spec.example)
    else
      base
    end
  end

  defp add_type(schema, type, nullable, nullable_style) do
    openapi_type = ecto_type_to_openapi(type)

    case {nullable, nullable_style} do
      {false, _} ->
        Map.put(schema, :type, openapi_type)

      {true, :type_array} ->
        Map.put(schema, :type, [openapi_type, "null"])

      {true, :nullable_property} ->
        schema
        |> Map.put(:type, openapi_type)
        |> Map.put(:nullable, true)
    end
  end

  defp ecto_type_to_openapi(:string), do: "string"
  defp ecto_type_to_openapi(:citext), do: "string"
  defp ecto_type_to_openapi(:integer), do: "integer"
  defp ecto_type_to_openapi(:float), do: "number"
  defp ecto_type_to_openapi(:decimal), do: "number"
  defp ecto_type_to_openapi(:boolean), do: "boolean"
  defp ecto_type_to_openapi(:binary), do: "string"
  defp ecto_type_to_openapi(:binary_id), do: "string"
  defp ecto_type_to_openapi(Ecto.UUID), do: "string"
  defp ecto_type_to_openapi(:map), do: "object"
  defp ecto_type_to_openapi({:map, _}), do: "object"
  defp ecto_type_to_openapi({:array, _}), do: "array"
  defp ecto_type_to_openapi(:date), do: "string"
  defp ecto_type_to_openapi(:time), do: "string"
  defp ecto_type_to_openapi(:time_usec), do: "string"
  defp ecto_type_to_openapi(:naive_datetime), do: "string"
  defp ecto_type_to_openapi(:naive_datetime_usec), do: "string"
  defp ecto_type_to_openapi(:utc_datetime), do: "string"
  defp ecto_type_to_openapi(:utc_datetime_usec), do: "string"
  defp ecto_type_to_openapi(Ecto.Enum), do: "string"
  defp ecto_type_to_openapi(_), do: "string"

  defp add_format(schema, type, validations) do
    format = determine_format(type, validations)

    if format do
      Map.put(schema, :format, format)
    else
      schema
    end
  end

  defp determine_format(:binary_id, _validations), do: "uuid"
  defp determine_format(Ecto.UUID, _validations), do: "uuid"
  defp determine_format(:date, _validations), do: "date"
  defp determine_format(:time, _validations), do: "time"
  defp determine_format(:time_usec, _validations), do: "time"
  defp determine_format(:naive_datetime, _validations), do: "date-time"
  defp determine_format(:naive_datetime_usec, _validations), do: "date-time"
  defp determine_format(:utc_datetime, _validations), do: "date-time"
  defp determine_format(:utc_datetime_usec, _validations), do: "date-time"

  defp determine_format(_type, validations) do
    case Map.get(validations, :format) do
      :email -> "email"
      :url -> "uri"
      :uuid -> "uuid"
      :date -> "date"
      :time -> "time"
      :datetime -> "date-time"
      :uri -> "uri"
      :hostname -> "hostname"
      :ipv4 -> "ipv4"
      :ipv6 -> "ipv6"
      _ -> nil
    end
  end

  defp add_constraints(schema, validations) do
    schema
    |> add_if_present(validations, :min_length, :minLength)
    |> add_if_present(validations, :max_length, :maxLength)
    |> add_length_constraint(validations)
    |> add_if_present(validations, :min, :minimum)
    |> add_if_present(validations, :max, :maximum)
    |> add_if_present(validations, :greater_than, :exclusiveMinimum)
    |> add_if_present(validations, :less_than, :exclusiveMaximum)
    |> add_if_present(validations, :greater_than_or_equal_to, :minimum)
    |> add_if_present(validations, :less_than_or_equal_to, :maximum)
    |> add_if_present(validations, :multiple_of, :multipleOf)
    |> add_array_constraints(validations)
    |> add_pattern(validations)
  end

  defp add_length_constraint(schema, validations) do
    case Map.get(validations, :length) do
      nil -> schema
      len when is_integer(len) -> Map.merge(schema, %{minLength: len, maxLength: len})
      _ -> schema
    end
  end

  defp add_array_constraints(schema, validations) do
    schema
    |> add_if_present(validations, :item_min, :minItems)
    |> add_if_present(validations, :item_max, :maxItems)
    |> add_unique_items(validations)
  end

  defp add_unique_items(schema, validations) do
    if Map.get(validations, :unique_items) do
      Map.put(schema, :uniqueItems, true)
    else
      schema
    end
  end

  defp add_pattern(schema, validations) do
    case Map.get(validations, :format) do
      %Regex{} = regex ->
        Map.put(schema, :pattern, Regex.source(regex))

      _ ->
        schema
    end
  end

  defp add_enum(schema, validations) do
    case Map.get(validations, :in) do
      nil -> schema
      values when is_list(values) -> Map.put(schema, :enum, values)
      _ -> schema
    end
  end

  defp add_description(schema, nil), do: schema
  defp add_description(schema, doc), do: Map.put(schema, :description, doc)

  defp add_default(schema, nil), do: schema
  defp add_default(schema, default), do: Map.put(schema, :default, default)

  defp add_example(schema, nil), do: schema
  defp add_example(schema, example), do: Map.put(schema, :example, example)

  defp add_readonly(schema, false), do: schema
  defp add_readonly(schema, true), do: Map.put(schema, :readOnly, true)

  defp add_writeonly(schema, false), do: schema
  defp add_writeonly(schema, true), do: Map.put(schema, :writeOnly, true)

  defp add_if_present(schema, source, source_key, target_key) do
    case Map.get(source, source_key) do
      nil -> schema
      value -> Map.put(schema, target_key, value)
    end
  end

  defp maybe_filter_id(specs, true), do: specs
  defp maybe_filter_id(specs, false), do: Enum.reject(specs, &(&1.field == :id))

  defp maybe_filter_timestamps(specs, true), do: specs

  defp maybe_filter_timestamps(specs, false) do
    timestamp_fields = [:inserted_at, :updated_at, :created_at, :deleted_at]
    Enum.reject(specs, &(&1.field in timestamp_fields))
  end

  defp schema_name(module, opts) do
    Keyword.get_lazy(opts, :schema_name, fn ->
      module
      |> Module.split()
      |> List.last()
    end)
  end

  defp build_collection_operations(name, operations, tags) do
    ops = %{}

    ops =
      if :list in operations do
        Map.put(ops, :get, %{
          tags: tags,
          summary: "List #{name}s",
          operationId: "list#{name}s",
          responses: %{
            "200" => %{
              description: "Successful response",
              content: %{
                "application/json" => %{
                  schema: %{
                    type: "array",
                    items: %{"$ref" => "#/components/schemas/#{name}"}
                  }
                }
              }
            }
          }
        })
      else
        ops
      end

    if :create in operations do
      Map.put(ops, :post, %{
        tags: tags,
        summary: "Create #{name}",
        operationId: "create#{name}",
        requestBody: %{
          required: true,
          content: %{
            "application/json" => %{
              schema: %{"$ref" => "#/components/schemas/#{name}"}
            }
          }
        },
        responses: %{
          "201" => %{
            description: "Created",
            content: %{
              "application/json" => %{
                schema: %{"$ref" => "#/components/schemas/#{name}"}
              }
            }
          },
          "422" => %{
            description: "Validation error"
          }
        }
      })
    else
      ops
    end
  end

  defp build_resource_operations(name, operations, tags) do
    ops = %{}

    id_param = %{
      name: "id",
      in: "path",
      required: true,
      schema: %{type: "string", format: "uuid"}
    }

    ops =
      if :get in operations do
        Map.put(ops, :get, %{
          tags: tags,
          summary: "Get #{name}",
          operationId: "get#{name}",
          parameters: [id_param],
          responses: %{
            "200" => %{
              description: "Successful response",
              content: %{
                "application/json" => %{
                  schema: %{"$ref" => "#/components/schemas/#{name}"}
                }
              }
            },
            "404" => %{description: "Not found"}
          }
        })
      else
        ops
      end

    ops =
      if :update in operations do
        Map.put(ops, :put, %{
          tags: tags,
          summary: "Update #{name}",
          operationId: "update#{name}",
          parameters: [id_param],
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{"$ref" => "#/components/schemas/#{name}"}
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Updated",
              content: %{
                "application/json" => %{
                  schema: %{"$ref" => "#/components/schemas/#{name}"}
                }
              }
            },
            "404" => %{description: "Not found"},
            "422" => %{description: "Validation error"}
          }
        })
      else
        ops
      end

    if :delete in operations do
      Map.put(ops, :delete, %{
        tags: tags,
        summary: "Delete #{name}",
        operationId: "delete#{name}",
        parameters: [id_param],
        responses: %{
          "204" => %{description: "Deleted"},
          "404" => %{description: "Not found"}
        }
      })
    else
      ops
    end
  end
end
