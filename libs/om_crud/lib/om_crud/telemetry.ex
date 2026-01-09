defmodule OmCrud.Telemetry do
  @moduledoc """
  Telemetry event emission for OmCrud operations.

  All CRUD operations emit telemetry events for observability.
  Events follow the standard Erlang telemetry pattern with
  `:start`, `:stop`, and `:exception` suffixes.

  ## Event Pattern

      [:om_crud, <operation>, :start | :stop | :exception]

  ## Operations

  | Operation | Event Name |
  |-----------|------------|
  | list | `[:om_crud, :list, :start/:stop]` |
  | filter | `[:om_crud, :filter, :start/:stop]` |
  | fetch | `[:om_crud, :fetch, :start/:stop]` |
  | get | `[:om_crud, :get, :start/:stop]` |
  | create | `[:om_crud, :create, :start/:stop]` |
  | update | `[:om_crud, :update, :start/:stop]` |
  | delete | `[:om_crud, :delete, :start/:stop]` |
  | count | `[:om_crud, :count, :start/:stop]` |
  | first | `[:om_crud, :first, :start/:stop]` |
  | last | `[:om_crud, :last, :start/:stop]` |
  | stream | `[:om_crud, :stream, :start/:stop]` |
  | exists | `[:om_crud, :exists, :start/:stop]` |
  | update_all | `[:om_crud, :update_all, :start/:stop]` |
  | delete_all | `[:om_crud, :delete_all, :start/:stop]` |

  ## Measurements

  On `:stop` events:
  - `:duration` - Operation duration in native time units
  - `:duration_ms` - Operation duration in milliseconds

  On `:start` events:
  - `:system_time` - Absolute timestamp

  ## Metadata

  Common metadata fields:
  - `:schema` - The schema module being queried
  - `:context` - The context module that generated the function
  - `:operation` - The operation type (`:list`, `:create`, etc.)

  Operation-specific metadata:
  - `:id` - Record ID (for single record operations)
  - `:filters` - Applied filters (for list/filter operations)
  - `:count` - Number of records (for bulk operations)
  - `:limit` - Page size (for paginated operations)
  - `:result` - `:ok` or `:error` (on stop events)

  ## Attaching Handlers

      :telemetry.attach_many(
        "om-crud-logger",
        [
          [:om_crud, :list, :stop],
          [:om_crud, :create, :stop],
          [:om_crud, :update, :stop],
          [:om_crud, :delete, :stop]
        ],
        &MyApp.Telemetry.handle_event/4,
        nil
      )

  ## Example Handler

      defmodule MyApp.Telemetry do
        require Logger

        def handle_event([:om_crud, operation, :stop], measurements, metadata, _config) do
          Logger.info(
            "[OmCrud] \#{operation} on \#{inspect(metadata.schema)} " <>
            "completed in \#{measurements.duration_ms}ms"
          )
        end

        def handle_event([:om_crud, _operation, :exception], _measurements, metadata, _config) do
          Logger.error(
            "[OmCrud] Exception in \#{metadata.operation}: \#{inspect(metadata.reason)}"
          )
        end
      end
  """

  @type operation ::
          :list
          | :filter
          | :fetch
          | :get
          | :create
          | :update
          | :delete
          | :count
          | :first
          | :last
          | :stream
          | :exists
          | :update_all
          | :delete_all

  @type metadata :: %{
          required(:schema) => module(),
          required(:operation) => operation(),
          optional(:context) => module(),
          optional(:id) => binary(),
          optional(:filters) => list(),
          optional(:count) => non_neg_integer(),
          optional(:limit) => pos_integer() | :all,
          optional(:result) => :ok | :error
        }

  @doc """
  Execute a function with telemetry instrumentation.

  This wraps the function call with `:telemetry.span/3` to emit
  start, stop, and exception events.

  ## Arguments

  - `operation` - The operation type (e.g., `:list`, `:create`)
  - `metadata` - Map of metadata to include in events
  - `fun` - Zero-arity function to execute

  ## Examples

      OmCrud.Telemetry.span(:list, %{schema: User, limit: 20}, fn ->
        # Query execution
        {:ok, users}
      end)
  """
  @spec span(operation(), metadata(), (-> result)) :: result when result: any()
  def span(operation, metadata, fun) when is_atom(operation) and is_function(fun, 0) do
    event_prefix = [:om_crud, operation]
    enriched_meta = Map.put(metadata, :operation, operation)

    :telemetry.span(event_prefix, enriched_meta, fn ->
      result = fun.()
      final_meta = Map.put(enriched_meta, :result, classify_result(result))
      {result, final_meta}
    end)
  end

  @doc """
  Emit a start event for an operation.

  Use this when you need manual control over event timing,
  such as for streaming operations.

  ## Examples

      start_time = OmCrud.Telemetry.start(:stream, %{schema: User})
      # ... streaming ...
      OmCrud.Telemetry.stop(:stream, start_time, %{schema: User, count: 1000})
  """
  @spec start(operation(), metadata()) :: integer()
  def start(operation, metadata) when is_atom(operation) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:om_crud, operation, :start],
      %{system_time: System.system_time()},
      Map.put(metadata, :operation, operation)
    )

    start_time
  end

  @doc """
  Emit a stop event for an operation.

  ## Arguments

  - `operation` - The operation type
  - `start_time` - The monotonic time from `start/2`
  - `metadata` - Map of metadata to include

  ## Examples

      OmCrud.Telemetry.stop(:stream, start_time, %{schema: User, count: 1000})
  """
  @spec stop(operation(), integer(), metadata()) :: :ok
  def stop(operation, start_time, metadata) when is_atom(operation) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    :telemetry.execute(
      [:om_crud, operation, :stop],
      %{duration: duration, duration_ms: duration_ms},
      Map.put(metadata, :operation, operation)
    )

    :ok
  end

  @doc """
  Emit an exception event for an operation.

  ## Examples

      OmCrud.Telemetry.exception(:create, start_time, :error, reason, stacktrace, metadata)
  """
  @spec exception(operation(), integer(), atom(), any(), list(), metadata()) :: :ok
  def exception(operation, start_time, kind, reason, stacktrace, metadata) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    :telemetry.execute(
      [:om_crud, operation, :exception],
      %{duration: duration, duration_ms: duration_ms},
      metadata
      |> Map.put(:operation, operation)
      |> Map.put(:kind, kind)
      |> Map.put(:reason, reason)
      |> Map.put(:stacktrace, stacktrace)
    )

    :ok
  end

  @metadata_keys [:limit, :filters, :id, :count]

  @doc """
  Build metadata map for a CRUD operation.

  ## Examples

      OmCrud.Telemetry.build_metadata(User, MyApp.Accounts, limit: 20, filters: [...])
      #=> %{schema: User, context: MyApp.Accounts, limit: 20, filters: [...]}
  """
  @spec build_metadata(module(), module() | nil, keyword()) :: metadata()
  def build_metadata(schema, context \\ nil, opts \\ []) do
    base = build_base_metadata(schema, context)
    merge_allowed_opts(base, opts)
  end

  defp build_base_metadata(schema, nil), do: %{schema: schema}
  defp build_base_metadata(schema, context), do: %{schema: schema, context: context}

  defp merge_allowed_opts(base, opts) do
    opts
    |> Keyword.take(@metadata_keys)
    |> Map.new()
    |> Map.merge(base)
  end

  @doc """
  List all telemetry events emitted by OmCrud.

  Useful for setting up telemetry handlers.

  ## Examples

      events = OmCrud.Telemetry.events()
      :telemetry.attach_many("my-handler", events, &handler/4, nil)
  """
  @spec events() :: [[atom()]]
  def events do
    operations = [
      :list,
      :filter,
      :fetch,
      :get,
      :create,
      :update,
      :delete,
      :count,
      :first,
      :last,
      :stream,
      :exists,
      :update_all,
      :delete_all
    ]

    for op <- operations, suffix <- [:start, :stop, :exception] do
      [:om_crud, op, suffix]
    end
  end

  @doc """
  List stop events only (most commonly used for metrics).

  ## Examples

      :telemetry.attach_many("metrics", OmCrud.Telemetry.stop_events(), &handler/4, nil)
  """
  @spec stop_events() :: [[atom()]]
  def stop_events do
    for [_, _, :stop] = event <- events(), do: event
  end

  # Private helpers

  defp classify_result({:ok, _}), do: :ok
  defp classify_result({:error, _}), do: :error
  defp classify_result({:error, _, _, _}), do: :error
  defp classify_result(nil), do: :not_found
  defp classify_result(false), do: :not_found
  defp classify_result(_), do: :ok
end
