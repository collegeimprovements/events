defmodule Events.DecoratorSchemas do
  @moduledoc """
  Consolidated schema definitions for all decorators.
  Uses NimbleOptions for compile-time validation.
  """

  # Common type definitions
  @log_levels ~w(emergency alert critical error warning warn notice info debug)a

  # ============================================================================
  # Caching Schemas
  # ============================================================================

  def cacheable_schema do
    NimbleOptions.new!(
      cache: [
        type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
        required: true,
        doc: "Cache module or MFA tuple for dynamic resolution"
      ],
      key: [
        type: :any,
        required: false,
        doc: "Explicit cache key (overrides key_generator)"
      ],
      key_generator: [
        type: {:or, [:atom, {:tuple, [:atom, :any]}, {:tuple, [:atom, :atom, :any]}]},
        required: false,
        doc: "Custom key generator module or MFA"
      ],
      ttl: [
        type: :pos_integer,
        required: false,
        doc: "Time-to-live in milliseconds"
      ],
      match: [
        type: {:fun, 1},
        required: false,
        doc: "Match function to determine if result should be cached"
      ],
      on_error: [
        type: {:in, [:raise, :nothing]},
        default: :raise,
        doc: "Error handling strategy"
      ]
    )
  end

  def cache_put_schema do
    NimbleOptions.new!(
      cache: [
        type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
        required: true,
        doc: "Cache module or MFA tuple"
      ],
      keys: [
        type: {:list, :any},
        required: true,
        doc: "List of cache keys to update"
      ],
      ttl: [
        type: :pos_integer,
        required: false,
        doc: "Time-to-live in milliseconds"
      ],
      match: [
        type: {:fun, 1},
        required: false,
        doc: "Match function for conditional caching"
      ],
      on_error: [
        type: {:in, [:raise, :nothing]},
        default: :raise,
        doc: "Error handling strategy"
      ]
    )
  end

  def cache_evict_schema do
    NimbleOptions.new!(
      cache: [
        type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
        required: true,
        doc: "Cache module or MFA tuple"
      ],
      keys: [
        type: {:list, :any},
        required: true,
        doc: "List of cache keys to evict"
      ],
      all_entries: [
        type: :boolean,
        default: false,
        doc: "If true, delete all cache entries"
      ],
      before_invocation: [
        type: :boolean,
        default: false,
        doc: "If true, evict before function executes"
      ],
      on_error: [
        type: {:in, [:raise, :nothing]},
        default: :raise,
        doc: "Error handling strategy"
      ]
    )
  end

  # ============================================================================
  # Telemetry Schemas
  # ============================================================================

  def telemetry_span_schema do
    NimbleOptions.new!(
      event: [
        type: {:list, :atom},
        required: false,
        doc: "Telemetry event name as list of atoms"
      ],
      include: [
        type: {:list, :atom},
        default: [],
        doc: "Variable names to include in metadata"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Additional static metadata"
      ]
    )
  end

  def log_call_schema do
    NimbleOptions.new!(
      level: [
        type: {:in, @log_levels},
        default: :info,
        doc: "Log level"
      ],
      message: [
        type: :string,
        required: false,
        doc: "Custom log message"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Additional metadata"
      ]
    )
  end

  def log_if_slow_schema do
    NimbleOptions.new!(
      threshold: [
        type: :pos_integer,
        required: true,
        doc: "Threshold in milliseconds"
      ],
      level: [
        type: {:in, @log_levels},
        default: :warn,
        doc: "Log level"
      ],
      message: [
        type: :string,
        required: false,
        doc: "Custom log message"
      ]
    )
  end

  def log_context_schema do
    NimbleOptions.new!(
      fields: [
        type: {:list, :atom},
        required: true,
        doc: "Field names from function arguments"
      ]
    )
  end

  # ============================================================================
  # Performance Schemas
  # ============================================================================

  def benchmark_schema do
    NimbleOptions.new!(
      iterations: [
        type: :pos_integer,
        default: 1,
        doc: "Number of iterations"
      ],
      warmup: [
        type: :pos_integer,
        default: 0,
        doc: "Number of warmup iterations"
      ],
      print: [
        type: :boolean,
        default: true,
        doc: "Print results to console"
      ]
    )
  end

  def measure_schema do
    NimbleOptions.new!(
      unit: [
        type: {:in, [:nanosecond, :microsecond, :millisecond, :second]},
        default: :microsecond,
        doc: "Time unit for measurement"
      ],
      print: [
        type: :boolean,
        default: true,
        doc: "Print results to console"
      ]
    )
  end

  # ============================================================================
  # Debugging Schemas
  # ============================================================================

  def debug_schema do
    NimbleOptions.new!(
      label: [
        type: :string,
        required: false,
        doc: "Debug label"
      ],
      width: [
        type: :pos_integer,
        default: 80,
        doc: "Output width for formatting"
      ]
    )
  end

  def inspect_schema do
    NimbleOptions.new!(
      args: [
        type: :boolean,
        default: true,
        doc: "Inspect function arguments"
      ],
      result: [
        type: :boolean,
        default: true,
        doc: "Inspect function result"
      ],
      label: [
        type: :string,
        required: false,
        doc: "Inspection label"
      ]
    )
  end

  def pry_schema do
    NimbleOptions.new!(
      before: [
        type: :boolean,
        default: false,
        doc: "Add pry before function execution"
      ],
      after: [
        type: :boolean,
        default: true,
        doc: "Add pry after function execution"
      ]
    )
  end

  # ============================================================================
  # Schema Registry
  # ============================================================================

  @schemas %{
    cacheable: &__MODULE__.cacheable_schema/0,
    cache_put: &__MODULE__.cache_put_schema/0,
    cache_evict: &__MODULE__.cache_evict_schema/0,
    telemetry_span: &__MODULE__.telemetry_span_schema/0,
    log_call: &__MODULE__.log_call_schema/0,
    log_if_slow: &__MODULE__.log_if_slow_schema/0,
    log_context: &__MODULE__.log_context_schema/0,
    benchmark: &__MODULE__.benchmark_schema/0,
    measure: &__MODULE__.measure_schema/0,
    debug: &__MODULE__.debug_schema/0,
    inspect: &__MODULE__.inspect_schema/0,
    pry: &__MODULE__.pry_schema/0
  }

  @doc "Get schema for a decorator"
  def get(name) when is_atom(name) do
    case Map.get(@schemas, name) do
      nil -> nil
      schema_fn -> schema_fn.()
    end
  end

  @doc "Validate options against schema"
  def validate!(name, opts) when is_atom(name) do
    case get(name) do
      nil -> opts
      schema -> NimbleOptions.validate!(opts, schema)
    end
  end
end
