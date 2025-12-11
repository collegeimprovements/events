defmodule FnDecorator.Telemetry do
  @moduledoc """
  Telemetry and observability decorators.

  Provides decorators for:
  - Erlang telemetry events (`:telemetry.span/3`)
  - OpenTelemetry distributed tracing
  - Structured logging
  - Performance monitoring
  - Error tracking

  All decorators use compile-time validation with NimbleOptions.

  ## Examples

      defmodule MyApp.Users do
        use FnDecorator

        @decorate telemetry_span([:my_app, :users, :get])
        @decorate log_if_slow(threshold: 1000)
        def get_user(id) do
          Repo.get(User, id)
        end

        @decorate log_context([:user_id, :request_id])
        @decorate capture_errors(reporter: Sentry)
        def process_request(user_id, request_id, params) do
          # All logs include user_id and request_id
          Logger.info("Processing request")
          # Errors automatically reported to Sentry
          do_work(params)
        end
      end
  """

  import FnDecorator.Shared

  @default_repo Application.compile_env(:fn_decorator, [__MODULE__, :repo], nil)

  ## Schemas

  # Shared log level specification
  @log_levels [:emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug]

  # Magic number constants
  @default_attempt 1
  @p95_percentile 0.95
  @p99_percentile 0.99

  @telemetry_span_schema NimbleOptions.new!(
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

  @otel_span_schema NimbleOptions.new!(
                      name: [
                        type: :string,
                        required: false,
                        doc: "OpenTelemetry span name"
                      ],
                      include: [
                        type: {:list, :atom},
                        default: [],
                        doc: "Variable names to include as span attributes"
                      ],
                      attributes: [
                        type: :map,
                        default: %{},
                        doc: "Additional static span attributes"
                      ]
                    )

  @log_call_schema NimbleOptions.new!(
                     level: [
                       type: {:in, @log_levels},
                       default: :info,
                       doc: "Log level"
                     ],
                     message: [
                       type: :string,
                       required: false,
                       doc: "Custom log message (defaults to function name)"
                     ],
                     metadata: [
                       type: :map,
                       default: %{},
                       doc: "Additional metadata to include in log"
                     ]
                   )

  @log_context_schema NimbleOptions.new!(
                        fields: [
                          type: {:list, :atom},
                          required: true,
                          doc: "Field names from function arguments to include in Logger metadata"
                        ]
                      )

  @log_if_slow_schema NimbleOptions.new!(
                        threshold: [
                          type: :pos_integer,
                          required: true,
                          doc: "Threshold in milliseconds to consider operation slow"
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

  @track_memory_schema NimbleOptions.new!(
                         threshold: [
                           type: :pos_integer,
                           required: true,
                           doc: "Memory threshold in bytes"
                         ],
                         level: [
                           type: {:in, @log_levels},
                           default: :warn,
                           doc: "Log level"
                         ]
                       )

  @capture_errors_schema NimbleOptions.new!(
                           reporter: [
                             type: :atom,
                             required: true,
                             doc: "Error reporting module (e.g., Sentry)"
                           ],
                           threshold: [
                             type: :pos_integer,
                             default: 1,
                             doc: "Only report after N attempts"
                           ]
                         )

  @log_query_schema NimbleOptions.new!(
                      slow_threshold: [
                        type: :pos_integer,
                        default: 1000,
                        doc: "Threshold in ms to log as slow query"
                      ],
                      level: [
                        type: {:in, @log_levels},
                        default: :debug,
                        doc: "Log level"
                      ],
                      slow_level: [
                        type: {:in, @log_levels},
                        default: :warn,
                        doc: "Log level for slow queries"
                      ],
                      include_query: [
                        type: :boolean,
                        default: true,
                        doc: "Include query in log output"
                      ]
                    )

  @log_remote_schema NimbleOptions.new!(
                       service: [
                         type: :atom,
                         required: true,
                         doc: "Remote logging service module"
                       ],
                       async: [
                         type: :boolean,
                         default: true,
                         doc: "Send logs asynchronously"
                       ],
                       metadata: [
                         type: :map,
                         default: %{},
                         doc: "Additional metadata to include"
                       ]
                     )

  @benchmark_schema NimbleOptions.new!(
                      iterations: [
                        type: :pos_integer,
                        default: 1,
                        doc: "Number of iterations to run"
                      ],
                      warmup: [
                        type: :pos_integer,
                        default: 0,
                        doc: "Number of warmup iterations"
                      ],
                      format: [
                        type: {:in, [:simple, :detailed, :statistical]},
                        default: :simple,
                        doc: "Output format"
                      ],
                      memory: [
                        type: :boolean,
                        default: false,
                        doc: "Track memory usage"
                      ]
                    )

  @measure_schema NimbleOptions.new!(
                    unit: [
                      type: {:in, [:nanosecond, :microsecond, :millisecond, :second]},
                      default: :millisecond,
                      doc: "Time unit for measurement"
                    ],
                    label: [
                      type: :string,
                      required: false,
                      doc: "Custom label for measurement"
                    ],
                    include_result: [
                      type: :boolean,
                      default: false,
                      doc: "Include result size/type in output"
                    ]
                  )

  ## Decorator Implementations

  @doc """
  Erlang telemetry span decorator.

  Wraps function execution in a `:telemetry.span/3` call, emitting
  start, stop, and exception events.

  ## Options

  #{NimbleOptions.docs(@telemetry_span_schema)}

  ## Events Emitted

  - `event ++ [:start]` - When function starts
  - `event ++ [:stop]` - When function completes
  - `event ++ [:exception]` - When function raises

  ## Examples

      @decorate telemetry_span([:my_app, :users, :create])
      def create_user(attrs) do
        Repo.insert(User.changeset(%User{}, attrs))
      end

      # With variable capture
      @decorate telemetry_span([:my_app, :process], include: [:user_id, :result])
      def process_data(user_id, data) do
        result = do_processing(data)
        {:ok, result}
      end
  """
  # Single-argument variant: event list directly (e.g., @decorate telemetry_span([:app, :action]))
  def telemetry_span([first | _] = event, body, context) when is_atom(first) do
    telemetry_span([event: event], body, context)
  end

  # Single-argument variant: keyword opts (e.g., @decorate telemetry_span(event: [...], metadata: %{}))
  def telemetry_span(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @telemetry_span_schema)

    event = validated_opts[:event] || default_event_name(context)
    include_vars = validated_opts[:include]
    static_metadata = validated_opts[:metadata]

    metadata = extract_metadata(include_vars, context)

    quote do
      :telemetry.span(
        unquote(event),
        Map.merge(unquote(metadata), unquote(Macro.escape(static_metadata))),
        fn ->
          result = unquote(body)
          metadata = %{result: result}
          {result, metadata}
        end
      )
    end
  end

  # Two-argument variant: event, opts
  def telemetry_span(event, opts, body, context) when is_list(event) and is_list(opts) do
    telemetry_span(Keyword.put(opts, :event, event), body, context)
  end

  @doc """
  OpenTelemetry span decorator.

  Creates an OpenTelemetry span for distributed tracing.

  ## Options

  #{NimbleOptions.docs(@otel_span_schema)}

  ## Examples

      @decorate otel_span("user.create")
      def create_user(attrs) do
        Repo.insert(User.changeset(%User{}, attrs))
      end

      # With attributes
      @decorate otel_span("payment.process", include: [:amount, :currency])
      def process_payment(amount, currency, card) do
        PaymentGateway.charge(amount, currency, card)
      end
  """
  def otel_span(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @otel_span_schema)

    span_name = validated_opts[:name] || default_span_name(context)
    include_vars = validated_opts[:include]
    static_attrs = validated_opts[:attributes]

    quote do
      require OpenTelemetry.Tracer

      OpenTelemetry.Tracer.with_span unquote(span_name) do
        # Set attributes from included variables
        unquote(set_span_attributes(include_vars, static_attrs))

        unquote(body)
      end
    end
  end

  # Two-argument variant: name, opts
  def otel_span(name, opts, body, context) when is_binary(name) and is_list(opts) do
    otel_span(Keyword.put(opts, :name, name), body, context)
  end

  @doc """
  Function call logging decorator.

  Logs function entry with configurable level and metadata.

  ## Options

  #{NimbleOptions.docs(@log_call_schema)}

  ## Examples

      @decorate log_call(level: :info)
      def important_operation do
        # Logs at :info level: "Calling MyModule.important_operation/0"
      end

      @decorate log_call(level: :debug, message: "Starting background task")
      def background_task(data) do
        # ...
      end
  """
  def log_call(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @log_call_schema)
    level = validate_log_level!(validated_opts[:level])

    message =
      validated_opts[:message] ||
        "Calling #{context.module}.#{context.name}/#{context.arity}"

    metadata = validated_opts[:metadata]

    quote do
      require Logger

      Logger.unquote(level)(
        unquote(message),
        unquote(Macro.escape(metadata))
      )

      unquote(body)
    end
  end

  @doc """
  Logger context decorator.

  Sets Logger metadata from function arguments for the duration of the function.

  ## Options

  #{NimbleOptions.docs(@log_context_schema)}

  ## Examples

      @decorate log_context([:user_id, :request_id])
      def handle_request(user_id, request_id, params) do
        Logger.info("Processing") # Includes user_id and request_id
        # ...
      end
  """
  def log_context(fields, body, context) when is_list(fields) do
    validated_opts = NimbleOptions.validate!([fields: fields], @log_context_schema)
    fields = validated_opts[:fields]

    metadata = logger_metadata_from_args(fields, context)

    quote do
      Logger.metadata(unquote(metadata))

      try do
        unquote(body)
      after
        Logger.reset_metadata(unquote(Enum.map(fields, &elem(&1, 0))))
      end
    end
  end

  @doc """
  Performance monitoring decorator.

  Logs a warning if function execution exceeds threshold.

  ## Options

  #{NimbleOptions.docs(@log_if_slow_schema)}

  ## Examples

      @decorate log_if_slow(threshold: 1000)
      def potentially_slow_query(params) do
        Repo.all(complex_query(params))
      end

      @decorate log_if_slow(threshold: 500, level: :error, message: "Critical path too slow")
      def critical_operation do
        # ...
      end
  """
  def log_if_slow(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @log_if_slow_schema)

    threshold_ms = validated_opts[:threshold]
    level = validate_log_level!(validated_opts[:level])

    message =
      validated_opts[:message] ||
        "Slow operation detected: #{context.module}.#{context.name}/#{context.arity}"

    quote do
      require Logger

      start_time = System.monotonic_time()

      result = unquote(body)

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      if duration_ms > unquote(threshold_ms) do
        Logger.unquote(level)(
          unquote(message),
          duration_ms: duration_ms,
          threshold_ms: unquote(threshold_ms),
          module: unquote(context.module),
          function: unquote(context.name)
        )
      end

      result
    end
  end

  @doc """
  Memory tracking decorator.

  Logs a warning if memory usage exceeds threshold.

  ## Options

  #{NimbleOptions.docs(@track_memory_schema)}

  ## Examples

      @decorate track_memory(threshold: 10_000_000) # 10MB
      def memory_intensive_operation(data) do
        # Process large dataset
      end
  """
  def track_memory(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @track_memory_schema)

    threshold_bytes = validated_opts[:threshold]
    level = validate_log_level!(validated_opts[:level])

    quote do
      require Logger

      start_memory = :erlang.memory(:total)

      result = unquote(body)

      end_memory = :erlang.memory(:total)
      memory_used = end_memory - start_memory

      if memory_used > unquote(threshold_bytes) do
        Logger.unquote(level)(
          "High memory usage detected",
          memory_bytes: memory_used,
          threshold_bytes: unquote(threshold_bytes),
          module: unquote(context.module),
          function: unquote(context.name)
        )
      end

      result
    end
  end

  @doc """
  Error tracking decorator.

  Captures exceptions and reports them to an error tracking service.

  ## Options

  #{NimbleOptions.docs(@capture_errors_schema)}

  ## Examples

      @decorate capture_errors(reporter: Sentry)
      def risky_operation(data) do
        # Errors automatically reported to Sentry
      end

      @decorate capture_errors(reporter: Sentry, threshold: 3)
      def operation_with_retries(data) do
        # Only reports after 3 failures
      end
  """
  def capture_errors(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @capture_errors_schema)

    reporter = validated_opts[:reporter]
    threshold = validated_opts[:threshold]

    quote do
      try do
        unquote(body)
      rescue
        error ->
          stacktrace = __STACKTRACE__

          attempt = var!(attempt, nil) || unquote(@default_attempt)

          if attempt >= unquote(threshold) do
            unquote(reporter).capture_exception(error,
              stacktrace: stacktrace,
              extra: %{
                module: unquote(context.module),
                function: unquote(context.name),
                arity: unquote(context.arity),
                attempt: attempt
              }
            )
          end

          reraise error, stacktrace
      end
    end
  end

  ## Private Helpers

  defp default_event_name(context) do
    [
      :events,
      context.module |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom(),
      context.name
    ]
  end

  defp default_span_name(context) do
    module_name = context.module |> Module.split() |> List.last() |> Macro.underscore()
    "#{module_name}.#{context.name}"
  end

  defp set_span_attributes(include_vars, static_attrs) do
    if Enum.empty?(include_vars) and map_size(static_attrs) == 0 do
      quote do: :ok
    else
      quote do
        require OpenTelemetry.Tracer

        # Set static attributes
        for {key, value} <- unquote(Macro.escape(static_attrs)) do
          OpenTelemetry.Tracer.set_attribute(key, value)
        end

        # Set attributes from variables (would need runtime evaluation)
        :ok
      end
    end
  end

  @doc """
  Database query logging decorator.

  Logs database queries with timing information, highlighting slow queries.

  ## Options

  #{NimbleOptions.docs(@log_query_schema)}

  ## Examples

      @decorate log_query(slow_threshold: 500)
      def get_user_with_posts(user_id) do
        User
        |> where(id: ^user_id)
        |> preload(:posts)
        |> Repo.one()
      end

      @decorate log_query(level: :info, include_query: true)
      def complex_aggregation do
        from(u in User,
          join: p in assoc(u, :posts),
          group_by: u.id,
          select: {u.id, count(p.id)}
        )
        |> Repo.all()
      end

  ## Output

      [DEBUG] Query executed in 45ms
      [WARN] SLOW QUERY (1234ms): SELECT * FROM users WHERE ...
  """
  def log_query(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @log_query_schema)

    slow_threshold = validated_opts[:slow_threshold]
    level = validate_log_level!(validated_opts[:level])
    slow_level = validate_log_level!(validated_opts[:slow_level])
    include_query? = validated_opts[:include_query]

    quote do
      require Logger

      start_time = System.monotonic_time()

      result = unquote(body)

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Extract query string if result is an Ecto query or has a query
      query_info =
        if unquote(include_query?) do
          case result do
            %Ecto.Query{} = q ->
              try do
                repo = unquote(@default_repo)
                {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, repo, q)
                sql
              rescue
                _ -> inspect(q, limit: 200)
              end

            {:ok, %{__struct__: _} = struct} ->
              struct.__struct__ |> to_string() |> String.split(".") |> List.last()

            {:ok, list} when is_list(list) ->
              "#{length(list)} records"

            _ ->
              nil
          end
        end

      cond do
        duration_ms > unquote(slow_threshold) ->
          message =
            if query_info,
              do: "SLOW QUERY (#{duration_ms}ms): #{query_info}",
              else: "SLOW QUERY (#{duration_ms}ms)"

          Logger.unquote(slow_level)(
            message,
            module: unquote(context.module),
            function: unquote(context.name),
            duration_ms: duration_ms
          )

        true ->
          message =
            if query_info && unquote(include_query?),
              do: "Query executed in #{duration_ms}ms: #{query_info}",
              else: "Query executed in #{duration_ms}ms"

          Logger.unquote(level)(
            message,
            module: unquote(context.module),
            function: unquote(context.name),
            duration_ms: duration_ms
          )
      end

      result
    end
  end

  @doc """
  Remote logging decorator.

  Sends logs to a remote logging service (e.g., Datadog, Logstash, etc.).

  ## Options

  #{NimbleOptions.docs(@log_remote_schema)}

  ## Examples

      @decorate log_remote(service: DatadogLogger, async: true)
      def critical_operation(data) do
        # Logs sent to Datadog
        process(data)
      end

      @decorate log_remote(service: LogstashLogger, metadata: %{env: "production"})
      def api_call(endpoint) do
        HTTPClient.post(endpoint)
      end

  ## Remote Service Requirements

  The remote service module must implement:
  - `log(level, message, metadata)` - For synchronous logging
  - `log_async(level, message, metadata)` - For async logging
  """
  def log_remote(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @log_remote_schema)

    service = validated_opts[:service]
    async? = validated_opts[:async]
    metadata = validated_opts[:metadata]

    base_metadata =
      quote do
        Map.merge(unquote(Macro.escape(metadata)), %{
          module: unquote(context.module),
          function: unquote(context.name),
          arity: unquote(context.arity),
          timestamp: DateTime.utc_now()
        })
      end

    quote do
      start_time = System.monotonic_time()

      try do
        result = unquote(body)

        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        metadata = Map.put(unquote(base_metadata), :duration_ms, duration_ms)

        if unquote(async?) do
          Task.Supervisor.start_child(Task.Supervisor, fn ->
            unquote(service).log_async(:info, "Function completed", metadata)
          end)
        else
          unquote(service).log(:info, "Function completed", metadata)
        end

        result
      rescue
        error ->
          metadata =
            Map.merge(unquote(base_metadata), %{
              error: Exception.format(:error, error, __STACKTRACE__)
            })

          if unquote(async?) do
            Task.Supervisor.start_child(Task.Supervisor, fn ->
              unquote(service).log_async(:error, "Function failed", metadata)
            end)
          else
            unquote(service).log(:error, "Function failed", metadata)
          end

          reraise error, __STACKTRACE__
      end
    end
  end

  @doc """
  Benchmark decorator for performance testing.

  Runs function multiple times and provides statistical analysis.

  ## Options

  #{NimbleOptions.docs(@benchmark_schema)}

  ## Examples

      @decorate benchmark(iterations: 1000)
      def fast_operation(x, y) do
        x + y
      end
      # Output:
      # Benchmark: MyModule.fast_operation/2
      # Iterations: 1000
      # Average: 0.001ms
      # Min: 0.000ms
      # Max: 0.015ms

      @decorate benchmark(iterations: 100, warmup: 10, format: :statistical, memory: true)
      def complex_operation(data) do
        process(data)
      end
      # Output includes standard deviation, percentiles, memory usage

  ## Use Cases

  - Performance testing
  - Regression detection
  - Optimization validation
  - Comparing implementations
  """
  def benchmark(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @benchmark_schema)

    iterations = validated_opts[:iterations]
    warmup = validated_opts[:warmup]
    format = validated_opts[:format]
    track_memory? = validated_opts[:memory]

    quote do
      IO.puts(
        "\n[BENCHMARK] #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}"
      )

      # Warmup runs
      perform_warmup(unquote(warmup), fn -> unquote(body) end)

      # Benchmark runs and collect metrics
      {timings, memories} =
        collect_benchmark_metrics(
          unquote(iterations),
          unquote(track_memory?),
          fn -> unquote(body) end
        )

      # Calculate and display statistics
      stats = calculate_benchmark_stats(timings, memories)

      display_benchmark_results(
        stats,
        unquote(format),
        unquote(iterations),
        unquote(track_memory?)
      )

      IO.puts("")

      # Return single execution result
      unquote(body)
    end
  end

  # Helper functions for benchmark
  # These are public because they're called from within quote blocks
  @doc false
  def perform_warmup(0, _fun), do: :ok

  @doc false
  def perform_warmup(warmup_count, fun) when warmup_count > 0 do
    for _ <- 1..warmup_count, do: fun.()
    :ok
  end

  @doc false
  def collect_benchmark_metrics(iterations, track_memory?, fun) do
    Enum.reduce(1..iterations, {[], []}, fn _, {times, mems} ->
      start_mem = if track_memory?, do: :erlang.memory(:total), else: 0
      start_time = System.monotonic_time()

      _result = fun.()

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
      memory_used = if track_memory?, do: :erlang.memory(:total) - start_mem, else: 0

      {[duration_ms | times], [memory_used | mems]}
    end)
  end

  @doc false
  def calculate_benchmark_stats(timings, memories) do
    sorted_times = Enum.sort(timings)
    count = length(timings)

    avg_time = Enum.sum(timings) / count

    %{
      avg_time: avg_time,
      min_time: Enum.min(timings),
      max_time: Enum.max(timings),
      median: Enum.at(sorted_times, div(count, 2)),
      sorted_times: sorted_times,
      count: count,
      avg_memory: if(memories != [], do: Enum.sum(memories) / length(memories), else: 0),
      max_memory: if(memories != [], do: Enum.max(memories), else: 0)
    }
  end

  @doc false
  def display_benchmark_results(stats, :simple, iterations, track_memory?) do
    IO.puts("  Iterations: #{iterations}")
    IO.puts("  Average: #{Float.round(stats.avg_time, 3)}ms")
    IO.puts("  Min: #{Float.round(stats.min_time, 3)}ms")
    IO.puts("  Max: #{Float.round(stats.max_time, 3)}ms")

    if track_memory? do
      IO.puts("  Avg Memory: #{Float.round(stats.avg_memory / 1024, 2)}KB")
    end
  end

  @doc false
  def display_benchmark_results(stats, :detailed, iterations, _track_memory?) do
    IO.puts("  Iterations: #{iterations}")
    IO.puts("  Average: #{Float.round(stats.avg_time, 3)}ms")
    IO.puts("  Median: #{Float.round(stats.median, 3)}ms")
    IO.puts("  Min: #{Float.round(stats.min_time, 3)}ms")
    IO.puts("  Max: #{Float.round(stats.max_time, 3)}ms")
    IO.puts("  Range: #{Float.round(stats.max_time - stats.min_time, 3)}ms")
  end

  @doc false
  def display_benchmark_results(stats, :statistical, iterations, track_memory?) do
    # Calculate additional statistics
    variance = calculate_variance(stats.sorted_times, stats.avg_time, stats.count)
    std_dev = :math.sqrt(variance)
    p95 = calculate_percentile(stats.sorted_times, stats.count, @p95_percentile)
    p99 = calculate_percentile(stats.sorted_times, stats.count, @p99_percentile)

    IO.puts("  Iterations: #{iterations}")
    IO.puts("  Average: #{Float.round(stats.avg_time, 3)}ms")
    IO.puts("  Median: #{Float.round(stats.median, 3)}ms")
    IO.puts("  Std Dev: #{Float.round(std_dev, 3)}ms")
    IO.puts("  Min: #{Float.round(stats.min_time, 3)}ms")
    IO.puts("  Max: #{Float.round(stats.max_time, 3)}ms")
    IO.puts("  95th percentile: #{Float.round(p95, 3)}ms")
    IO.puts("  99th percentile: #{Float.round(p99, 3)}ms")

    if track_memory? do
      IO.puts("  Avg Memory: #{Float.round(stats.avg_memory / 1024, 2)}KB")
      IO.puts("  Max Memory: #{Float.round(stats.max_memory / 1024, 2)}KB")
    end
  end

  @doc false
  def calculate_variance(timings, avg_time, count) do
    Enum.reduce(timings, 0, fn t, acc ->
      acc + :math.pow(t - avg_time, 2)
    end) / count
  end

  @doc false
  def calculate_percentile(sorted_times, count, percentile) do
    Enum.at(sorted_times, round(count * percentile))
  end

  @doc """
  Simple measurement decorator.

  Measures and prints execution time of a function.

  ## Options

  #{NimbleOptions.docs(@measure_schema)}

  ## Examples

      @decorate measure()
      def calculate(x, y) do
        # Complex calculation
        x * y
      end
      # Output: [MEASURE] MyModule.calculate/2 took 15ms

      @decorate measure(unit: :microsecond, label: "DB Query")
      def query_database do
        Repo.all(User)
      end
      # Output: [MEASURE] DB Query took 1234μs

      @decorate measure(include_result: true)
      def get_users do
        Repo.all(User)
      end
      # Output: [MEASURE] MyModule.get_users/0 took 45ms (result: list of 150 items)
  """
  def measure(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @measure_schema)

    unit = validated_opts[:unit]
    label = validated_opts[:label] || "#{context.module}.#{context.name}/#{context.arity}"
    include_result? = validated_opts[:include_result]

    unit_symbol =
      case unit do
        :nanosecond -> "ns"
        :microsecond -> "μs"
        :millisecond -> "ms"
        :second -> "s"
      end

    quote do
      start_time = System.monotonic_time()

      result = unquote(body)

      duration = System.monotonic_time() - start_time
      duration_converted = System.convert_time_unit(duration, :native, unquote(unit))

      result_info =
        if unquote(include_result?) do
          cond do
            is_list(result) ->
              " (result: list of #{length(result)} items)"

            is_map(result) ->
              " (result: map with #{map_size(result)} keys)"

            is_binary(result) ->
              " (result: binary of #{byte_size(result)} bytes)"

            true ->
              " (result: #{inspect(result.__struct__ || :primitive)})"
          end
        else
          ""
        end

      IO.puts(
        "[MEASURE] #{unquote(label)} took #{duration_converted}#{unquote(unit_symbol)}#{result_info}"
      )

      result
    end
  end
end
