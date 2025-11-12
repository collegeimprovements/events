defmodule Events.Decorator.SchemaFragments do
  @moduledoc """
  Reusable schema fragments for decorator options.

  This module provides common schema field definitions used across
  multiple decorators to reduce duplication and ensure consistency.

  ## Usage

      @my_schema NimbleOptions.new!(
        threshold: SchemaFragments.threshold_field(default: 1000),
        on_error: SchemaFragments.on_error_field(),
        metadata: SchemaFragments.metadata_field()
      )
  """

  @log_levels [:emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug]

  @doc """
  Common error handling strategy field.

  Supports: `:raise`, `:nothing`, `:return_error`, `:return_nil`, `:log`, `:ignore`

  ## Options

  * `:default` - Default strategy (default: `:raise`)
  * `:strategies` - List of allowed strategies (default: all)
  * `:doc` - Custom documentation string

  ## Examples

      on_error: SchemaFragments.on_error_field()
      on_error: SchemaFragments.on_error_field(default: :return_error)
      on_error: SchemaFragments.on_error_field(strategies: [:raise, :return_error])
  """
  def on_error_field(opts \\ []) do
    strategies = opts[:strategies] || [:raise, :nothing, :return_error, :return_nil, :log, :ignore]
    default = opts[:default] || :raise

    [
      type: {:in, strategies},
      default: default,
      doc: opts[:doc] || "Error handling strategy: #{inspect(strategies)}"
    ]
  end

  @doc """
  Threshold value field (positive integer).

  ## Options

  * `:default` - Default threshold value
  * `:required` - Whether field is required (default: `false`)
  * `:doc` - Custom documentation string

  ## Examples

      threshold: SchemaFragments.threshold_field()
      threshold: SchemaFragments.threshold_field(default: 1000, required: true)
  """
  def threshold_field(opts \\ []) do
    [
      type: :pos_integer,
      required: opts[:required] || false,
      default: opts[:default],
      doc: opts[:doc] || "Threshold value"
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Log level field.

  ## Options

  * `:default` - Default log level (default: `:info`)
  * `:doc` - Custom documentation string

  ## Examples

      level: SchemaFragments.log_level_field()
      level: SchemaFragments.log_level_field(default: :warn)
  """
  def log_level_field(opts \\ []) do
    [
      type: {:in, @log_levels},
      default: opts[:default] || :info,
      doc: opts[:doc] || "Log level: #{inspect(@log_levels)}"
    ]
  end

  @doc """
  Metadata map field.

  ## Options

  * `:default` - Default metadata map (default: `%{}`)
  * `:doc` - Custom documentation string

  ## Examples

      metadata: SchemaFragments.metadata_field()
      metadata: SchemaFragments.metadata_field(default: %{service: "api"})
  """
  def metadata_field(opts \\ []) do
    [
      type: :map,
      default: opts[:default] || %{},
      doc: opts[:doc] || "Additional metadata"
    ]
  end

  @doc """
  Cache module or MFA tuple field.

  ## Options

  * `:required` - Whether field is required (default: `true`)
  * `:doc` - Custom documentation string

  ## Examples

      cache: SchemaFragments.cache_field()
      cache: SchemaFragments.cache_field(required: false)
  """
  def cache_field(opts \\ []) do
    [
      type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
      required: opts[:required] != false,
      doc: opts[:doc] || "Cache module or MFA tuple {Module, :function, args}"
    ]
  end

  @doc """
  Duration field (milliseconds).

  ## Options

  * `:required` - Whether field is required (default: `false`)
  * `:default` - Default duration value
  * `:doc` - Custom documentation string
  * `:unit` - Time unit for documentation (default: "milliseconds")

  ## Examples

      duration: SchemaFragments.duration_field()
      duration: SchemaFragments.duration_field(default: 5000, required: true)
      ttl: SchemaFragments.duration_field(doc: "Time-to-live", unit: "milliseconds")
  """
  def duration_field(opts \\ []) do
    unit = opts[:unit] || "milliseconds"

    [
      type: :pos_integer,
      required: opts[:required] || false,
      default: opts[:default],
      doc: opts[:doc] || "Duration in #{unit}"
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Time window field (second, minute, hour, day).

  ## Options

  * `:default` - Default window (default: `:minute`)
  * `:doc` - Custom documentation string

  ## Examples

      window: SchemaFragments.time_window_field()
      window: SchemaFragments.time_window_field(default: :hour)
  """
  def time_window_field(opts \\ []) do
    [
      type: {:in, [:second, :minute, :hour, :day]},
      default: opts[:default] || :minute,
      doc: opts[:doc] || "Time window for operation: :second, :minute, :hour, :day"
    ]
  end

  @doc """
  Match function field.

  Match functions determine if a result should be processed/cached/etc.

  ## Match Function Protocol

  Match functions should return:
  * `true | false` - Simple boolean match
  * `{true, value}` - Match with transformed value
  * `{true, value, opts}` - Match with value and runtime opts

  ## Options

  * `:doc` - Custom documentation string
  * `:required` - Whether field is required (default: `false`)

  ## Examples

      match: SchemaFragments.match_function_field("Determines if result should be cached")
      match: SchemaFragments.match_function_field(required: true)
  """
  def match_function_field(doc_or_opts \\ [])

  def match_function_field(doc) when is_binary(doc) do
    [
      type: {:fun, 1},
      required: false,
      doc: doc
    ]
  end

  def match_function_field(opts) when is_list(opts) do
    [
      type: {:fun, 1},
      required: opts[:required] || false,
      doc: opts[:doc] || "Match function to filter results"
    ]
  end

  @doc """
  Boolean field with default.

  ## Options

  * `:default` - Default boolean value (default: `false`)
  * `:doc` - Custom documentation string
  * `:required` - Whether field is required (default: `false`)

  ## Examples

      async: SchemaFragments.boolean_field(default: true, doc: "Process asynchronously")
      strict: SchemaFragments.boolean_field()
  """
  def boolean_field(opts \\ []) do
    [
      type: :boolean,
      default: opts[:default] || false,
      required: opts[:required] || false,
      doc: opts[:doc] || "Boolean flag"
    ]
  end

  @doc """
  Field name list for capturing arguments or metadata.

  ## Options

  * `:doc` - Custom documentation string
  * `:default` - Default field list (default: `[]`)

  ## Examples

      fields: SchemaFragments.field_list("Fields to capture in audit log")
      include: SchemaFragments.field_list(default: [:id, :name])
  """
  def field_list(doc_or_opts \\ [])

  def field_list(doc) when is_binary(doc) do
    [
      type: {:list, :atom},
      default: [],
      doc: doc
    ]
  end

  def field_list(opts) when is_list(opts) do
    [
      type: {:list, :atom},
      default: opts[:default] || [],
      doc: opts[:doc] || "List of field names"
    ]
  end

  @doc """
  Module atom field.

  ## Options

  * `:required` - Whether field is required (default: `true`)
  * `:default` - Default module
  * `:doc` - Custom documentation string

  ## Examples

      reporter: SchemaFragments.module_field(doc: "Error reporting module")
      backend: SchemaFragments.module_field(default: MyApp.DefaultBackend)
  """
  def module_field(opts \\ []) do
    [
      type: :atom,
      required: opts[:required] != false,
      default: opts[:default],
      doc: opts[:doc] || "Module name"
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Keyword list field for options.

  ## Options

  * `:default` - Default keyword list (default: `[]`)
  * `:doc` - Custom documentation string

  ## Examples

      opts: SchemaFragments.keyword_list_field()
      options: SchemaFragments.keyword_list_field(default: [debug: true])
  """
  def keyword_list_field(opts \\ []) do
    [
      type: :keyword_list,
      default: opts[:default] || [],
      doc: opts[:doc] || "Keyword list options"
    ]
  end

  @doc """
  Function reference field.

  ## Options

  * `:arity` - Required arity (default: `1`)
  * `:required` - Whether field is required (default: `false`)
  * `:doc` - Custom documentation string

  ## Examples

      callback: SchemaFragments.function_field(arity: 2, doc: "Callback function")
      transform: SchemaFragments.function_field()
  """
  def function_field(opts \\ []) do
    arity = opts[:arity] || 1

    [
      type: {:fun, arity},
      required: opts[:required] || false,
      doc: opts[:doc] || "Function with arity #{arity}"
    ]
  end

  @doc """
  Enum choice field.

  ## Options

  * `:choices` - List of allowed values (required)
  * `:default` - Default value
  * `:doc` - Custom documentation string

  ## Examples

      format: SchemaFragments.enum_field(choices: [:json, :xml, :csv], default: :json)
      type: SchemaFragments.enum_field(choices: [:internal, :external], default: :internal)
  """
  def enum_field(opts) do
    choices = opts[:choices] || raise ArgumentError, "choices is required for enum_field"

    [
      type: {:in, choices},
      default: opts[:default],
      doc: opts[:doc] || "One of: #{inspect(choices)}"
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Combined schema for common decorator options.

  Returns a map of field definitions that can be merged into NimbleOptions schemas.

  ## Options

  * `:on_error` - Include error handling field (default: `false`)
  * `:metadata` - Include metadata field (default: `false`)
  * `:level` - Include log level field (default: `false`)

  ## Examples

      @my_schema NimbleOptions.new!(
        SchemaFragments.common_fields(on_error: true, metadata: true)
        |> Map.merge(%{
          my_field: [type: :string, required: true]
        })
      )
  """
  def common_fields(opts \\ []) do
    fields = %{}

    fields =
      if opts[:on_error] do
        Map.put(fields, :on_error, on_error_field())
      else
        fields
      end

    fields =
      if opts[:metadata] do
        Map.put(fields, :metadata, metadata_field())
      else
        fields
      end

    fields =
      if opts[:level] do
        Map.put(fields, :level, log_level_field())
      else
        fields
      end

    fields
  end
end
