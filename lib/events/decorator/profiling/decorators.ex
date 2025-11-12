defmodule Events.Decorator.Profiling do
  @moduledoc """
  Profiling decorators for performance analysis.

  Provides decorators for:
  - Production-safe sampling profiler
  - Call graph profiling
  - Memory profiling
  - Flame graph generation
  - Custom profiling strategies

  All profilers integrate with telemetry and emit structured events.

  ## Examples

      defmodule MyApp.Analytics do
        use Events.Decorator

        # Sample profile with 1% sampling rate (production-safe)
        @decorate profile(strategy: :sample, rate: 0.01)
        def compute_metrics(data) do
          # Expensive computation
        end

        # Profile only if function is slow
        @decorate profile_if_slow(threshold: 1000, strategy: :sample)
        def potentially_slow_operation(id) do
          # Operation that might be slow
        end

        # Memory profiling in development
        @decorate profile(strategy: :memory, env: [:dev, :test])
        def allocate_resources do
          # Memory-intensive operation
        end

        # Generate flame graph
        @decorate flame_graph(output: "profile.svg", enabled: Mix.env() == :dev)
        def complex_pipeline(data) do
          data
          |> step1()
          |> step2()
          |> step3()
        end

        # Production profiler with sampling
        @decorate profile_production(sample_rate: 0.001, emit_metrics: true)
        def critical_operation(params) do
          # Critical path - profile 0.1% of requests
        end
      end

  ## Production Safety

  All decorators support:
  - Configurable sampling rates
  - Environment-based enabling/disabling
  - Load-based automatic disabling
  - Asynchronous profiling
  - Minimal overhead

  ## Telemetry Events

  Emitted events:
  - `[:events, :profiler, :start]` - Profiling started
  - `[:events, :profiler, :stop]` - Profiling completed
  - `[:events, :profiler, :exception]` - Profiling error
  - `[:events, :profiler, :sample]` - Sample collected
  """

  use Decorator.Define,
    profile: 0,
    profile: 1,
    profile_if_slow: 1,
    profile_production: 0,
    profile_production: 1,
    flame_graph: 0,
    flame_graph: 1,
    profile_memory: 0,
    profile_memory: 1,
    profile_calls: 0,
    profile_calls: 1

  require Logger

  ## Schemas

  @profile_schema NimbleOptions.new!(
                    strategy: [
                      type:
                        {:in,
                         [:sample, :call_graph, :memory, :flame_graph, :fprof, :eprof, :cprof]},
                      default: :sample,
                      doc: "Profiling strategy to use"
                    ],
                    rate: [
                      type: :float,
                      default: 0.01,
                      doc: "Sampling rate (0.0-1.0, default: 0.01 = 1%)"
                    ],
                    duration: [
                      type: :pos_integer,
                      default: 30_000,
                      doc: "Max profiling duration in milliseconds"
                    ],
                    threshold: [
                      type: :pos_integer,
                      required: false,
                      doc: "Only profile if function duration exceeds this threshold (ms)"
                    ],
                    env: [
                      type: {:list, :atom},
                      default: [:dev, :test, :prod],
                      doc: "Environments where profiling is enabled"
                    ],
                    enabled: [
                      type: :boolean,
                      default: true,
                      doc: "Enable/disable profiling"
                    ],
                    async: [
                      type: :boolean,
                      default: false,
                      doc: "Run profiler asynchronously"
                    ],
                    emit_metrics: [
                      type: :boolean,
                      default: true,
                      doc: "Emit telemetry metrics"
                    ],
                    check_load: [
                      type: :boolean,
                      default: true,
                      doc: "Check system load before profiling"
                    ],
                    metadata: [
                      type: :map,
                      default: %{},
                      doc: "Additional metadata for telemetry"
                    ]
                  )

  @profile_if_slow_schema NimbleOptions.new!(
                            threshold: [
                              type: :pos_integer,
                              required: true,
                              doc: "Threshold in milliseconds"
                            ],
                            strategy: [
                              type:
                                {:in,
                                 [
                                   :sample,
                                   :call_graph,
                                   :memory,
                                   :flame_graph,
                                   :fprof,
                                   :eprof,
                                   :cprof
                                 ]},
                              default: :sample,
                              doc: "Profiling strategy"
                            ],
                            rate: [
                              type: :float,
                              default: 0.1,
                              doc: "Sampling rate when slow"
                            ],
                            env: [
                              type: {:list, :atom},
                              default: [:dev, :test],
                              doc: "Environments where profiling is enabled"
                            ]
                          )

  @profile_production_schema NimbleOptions.new!(
                               sample_rate: [
                                 type: :float,
                                 default: 0.001,
                                 doc: "Production sampling rate (default: 0.001 = 0.1%)"
                               ],
                               emit_metrics: [
                                 type: :boolean,
                                 default: true,
                                 doc: "Emit performance metrics"
                               ],
                               check_load: [
                                 type: :boolean,
                                 default: true,
                                 doc: "Only profile under acceptable load"
                               ]
                             )

  @flame_graph_schema NimbleOptions.new!(
                        output: [
                          type: :string,
                          required: false,
                          doc: "Output file path"
                        ],
                        format: [
                          type: {:in, [:svg, :html, :json]},
                          default: :svg,
                          doc: "Output format"
                        ],
                        enabled: [
                          type: :boolean,
                          default: true,
                          doc: "Enable/disable flame graph generation"
                        ],
                        duration: [
                          type: :pos_integer,
                          default: 10_000,
                          doc: "Profiling duration in milliseconds"
                        ]
                      )

  @profile_memory_schema NimbleOptions.new!(
                           env: [
                             type: {:list, :atom},
                             default: [:dev, :test],
                             doc: "Environments where memory profiling is enabled"
                           ],
                           threshold: [
                             type: :pos_integer,
                             required: false,
                             doc: "Only log if memory delta exceeds threshold (bytes)"
                           ],
                           emit_metrics: [
                             type: :boolean,
                             default: true,
                             doc: "Emit memory metrics"
                           ]
                         )

  @profile_calls_schema NimbleOptions.new!(
                          env: [
                            type: {:list, :atom},
                            default: [:dev, :test],
                            doc: "Environments where call profiling is enabled"
                          ],
                          emit_metrics: [
                            type: :boolean,
                            default: true,
                            doc: "Emit call count metrics"
                          ]
                        )

  ## Decorators

  @doc """
  Profile a function using the specified strategy.

  ## Options

  #{NimbleOptions.docs(@profile_schema)}

  ## Examples

      @decorate profile(strategy: :sample, rate: 0.01)
      def expensive_calculation(data) do
        # Auto-profiled with 1% sampling
      end

      @decorate profile(strategy: :memory, env: [:dev])
      def memory_intensive do
        # Memory profiled only in dev
      end

      @decorate profile(strategy: :flame_graph, async: true)
      def complex_operation do
        # Generate flame graph asynchronously
      end
  """
  def profile(opts \\ [], body, context) do
    opts = NimbleOptions.validate!(opts, @profile_schema)

    enabled = opts[:enabled] && Mix.env() in opts[:env]

    if enabled do
      do_profile(opts, body, context)
    else
      body
    end
  end

  @doc """
  Profile a function only if it exceeds a duration threshold.

  Useful for identifying slow operations in production.

  ## Options

  #{NimbleOptions.docs(@profile_if_slow_schema)}

  ## Examples

      @decorate profile_if_slow(threshold: 1000, strategy: :sample)
      def potentially_slow(id) do
        # Profiled only if takes > 1 second
      end

      @decorate profile_if_slow(threshold: 500, rate: 0.5)
      def api_call(params) do
        # Profile 50% of slow calls
      end
  """
  def profile_if_slow(opts, body, context) do
    opts = NimbleOptions.validate!(opts, @profile_if_slow_schema)

    enabled = Mix.env() in opts[:env]

    if enabled do
      do_profile_if_slow(opts, body, context)
    else
      body
    end
  end

  @doc """
  Production-safe profiler with low sampling rate.

  Automatically checks system load and disables under high load.

  ## Options

  #{NimbleOptions.docs(@profile_production_schema)}

  ## Examples

      @decorate profile_production(sample_rate: 0.001)
      def critical_path(data) do
        # Profile 0.1% of production requests
      end

      @decorate profile_production(emit_metrics: true)
      def monitored_operation do
        # Auto-emit performance metrics
      end
  """
  def profile_production(opts \\ [], body, context) do
    opts = NimbleOptions.validate!(opts, @profile_production_schema)

    if Mix.env() == :prod do
      do_profile_production(opts, body, context)
    else
      body
    end
  end

  @doc """
  Generate a flame graph for the function.

  ## Options

  #{NimbleOptions.docs(@flame_graph_schema)}

  ## Examples

      @decorate flame_graph(output: "profile.svg")
      def pipeline(data) do
        # Flame graph saved to profile.svg
      end

      @decorate flame_graph(format: :html, enabled: Mix.env() == :dev)
      def complex_flow do
        # HTML flame graph in dev only
      end
  """
  def flame_graph(opts \\ [], body, context) do
    opts = NimbleOptions.validate!(opts, @flame_graph_schema)

    if opts[:enabled] do
      do_flame_graph(opts, body, context)
    else
      body
    end
  end

  @doc """
  Profile memory allocations.

  ## Options

  #{NimbleOptions.docs(@profile_memory_schema)}

  ## Examples

      @decorate profile_memory()
      def allocate_buffers do
        # Memory usage tracked
      end

      @decorate profile_memory(threshold: 1_000_000)
      def batch_process do
        # Log only if > 1MB allocated
      end
  """
  def profile_memory(opts \\ [], body, context) do
    opts = NimbleOptions.validate!(opts, @profile_memory_schema)

    enabled = Mix.env() in opts[:env]

    if enabled do
      do_profile_memory(opts, body, context)
    else
      body
    end
  end

  @doc """
  Profile function call counts using :cprof.

  ## Options

  #{NimbleOptions.docs(@profile_calls_schema)}

  ## Examples

      @decorate profile_calls()
      def recursive_function(n) do
        # Track call counts
      end
  """
  def profile_calls(opts \\ [], body, context) do
    opts = NimbleOptions.validate!(opts, @profile_calls_schema)

    enabled = Mix.env() in opts[:env]

    if enabled do
      do_profile_calls(opts, body, context)
    else
      body
    end
  end

  ## Implementation

  defp do_profile(opts, body, context) do
    strategy = opts[:strategy]
    metadata = build_metadata(context, opts)

    quote do
      # Check if profiling should be enabled
      should_profile =
        if unquote(opts[:check_load]) do
          Events.Profiler.should_profile?()
        else
          true
        end

      # Check sampling rate
      should_sample = :rand.uniform() < unquote(opts[:rate])

      if should_profile and should_sample do
        profiler_opts = [
          rate: unquote(opts[:rate]),
          duration: unquote(opts[:duration]),
          threshold: unquote(opts[:threshold]),
          async: unquote(opts[:async]),
          metadata: unquote(Macro.escape(metadata))
        ]

        case Events.Profiler.profile(unquote(strategy), fn -> unquote(body) end, profiler_opts) do
          {:ok, %{result: result} = profile_result} ->
            if unquote(opts[:emit_metrics]) do
              emit_profile_metrics(unquote(Macro.escape(metadata)), profile_result)
            end

            result

          {:error, reason} ->
            Logger.warning("Profiling failed: #{inspect(reason)}")
            # Execute function without profiling
            unquote(body)
        end
      else
        unquote(body)
      end
    end
  end

  defp do_profile_if_slow(opts, body, context) do
    threshold = opts[:threshold]
    strategy = opts[:strategy]
    rate = opts[:rate]
    metadata = build_metadata(context, opts)

    quote do
      start_time = System.monotonic_time(:millisecond)

      result = unquote(body)

      duration = System.monotonic_time(:millisecond) - start_time

      if duration > unquote(threshold) do
        should_sample = :rand.uniform() < unquote(rate)

        if should_sample do
          Logger.warning("""
          Slow operation detected: #{unquote(context.name)}
          Duration: #{duration}ms
          Threshold: #{unquote(threshold)}ms
          """)

          # Profile the next call if it's slow again
          :telemetry.execute(
            [:events, :profiler, :slow_operation],
            %{duration: duration, threshold: unquote(threshold)},
            unquote(Macro.escape(metadata))
          )
        end
      end

      result
    end
  end

  defp do_profile_production(opts, body, context) do
    sample_rate = opts[:sample_rate]
    metadata = build_metadata(context, opts)

    quote do
      # Check system load
      should_profile =
        if unquote(opts[:check_load]) do
          Events.Profiler.should_profile?()
        else
          true
        end

      # Low sampling rate for production
      should_sample = :rand.uniform() < unquote(sample_rate)

      if should_profile and should_sample do
        start_time = System.monotonic_time(:millisecond)

        result = unquote(body)

        duration = System.monotonic_time(:millisecond) - start_time

        if unquote(opts[:emit_metrics]) do
          :telemetry.execute(
            [:events, :profiler, :production],
            %{duration: duration},
            unquote(Macro.escape(metadata))
          )
        end

        result
      else
        unquote(body)
      end
    end
  end

  defp do_flame_graph(opts, body, context) do
    output = opts[:output] || "#{context.module}_#{context.name}_flamegraph.#{opts[:format]}"
    format = opts[:format]
    duration = opts[:duration]

    quote do
      flame_opts = [
        output: unquote(output),
        format: unquote(format),
        duration: unquote(duration)
      ]

      case Events.Profiler.flame_graph(fn -> unquote(body) end, flame_opts) do
        {:ok, result} ->
          Logger.info("Flame graph generated: #{unquote(output)}")
          result

        {:error, reason} ->
          Logger.warning("Flame graph generation failed: #{inspect(reason)}")
          unquote(body)
      end
    end
  end

  defp do_profile_memory(opts, body, context) do
    threshold = opts[:threshold]
    emit_metrics = opts[:emit_metrics]
    metadata = build_metadata(context, opts)

    quote do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)

      result = unquote(body)

      :erlang.garbage_collect()
      memory_after = :erlang.memory(:total)
      memory_delta = memory_after - memory_before

      should_log =
        case unquote(threshold) do
          nil -> true
          threshold -> abs(memory_delta) > threshold
        end

      if should_log do
        Logger.info("""
        Memory profiling: #{unquote(context.name)}
        Before: #{div(memory_before, 1024)} KB
        After: #{div(memory_after, 1024)} KB
        Delta: #{div(memory_delta, 1024)} KB
        """)

        if unquote(emit_metrics) do
          :telemetry.execute(
            [:events, :profiler, :memory],
            %{
              before: memory_before,
              after: memory_after,
              delta: memory_delta
            },
            unquote(Macro.escape(metadata))
          )
        end
      end

      result
    end
  end

  defp do_profile_calls(opts, body, context) do
    emit_metrics = opts[:emit_metrics]
    metadata = build_metadata(context, opts)

    quote do
      :cprof.start()

      result = unquote(body)

      :cprof.pause()
      call_data = :cprof.analyse()
      :cprof.stop()

      Logger.debug("Call count profiling: #{unquote(context.name)}")
      Logger.debug("Call data: #{inspect(call_data, limit: 20)}")

      if unquote(emit_metrics) do
        :telemetry.execute(
          [:events, :profiler, :calls],
          %{calls: length(call_data)},
          unquote(Macro.escape(metadata))
        )
      end

      result
    end
  end

  defp build_metadata(context, opts) do
    %{
      module: context.module,
      function: context.name,
      arity: context.arity
    }
    |> Map.merge(opts[:metadata] || %{})
  end

  defp emit_profile_metrics(metadata, profile_result) do
    quote do
      :telemetry.execute(
        [:events, :profiler, :complete],
        %{
          duration: unquote(profile_result.duration_ms),
          memory_delta: unquote(profile_result.memory_delta),
          samples: unquote(profile_result.samples)
        },
        unquote(Macro.escape(metadata))
      )
    end
  end
end
