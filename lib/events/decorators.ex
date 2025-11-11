defmodule Events.Decorators do
  @moduledoc """
  All decorator implementations in a single, flat module structure.
  This consolidates functionality previously spread across multiple files.
  """

  import Events.Decorator.Shared

  # ============================================================================
  # Caching Decorators
  # ============================================================================

  def cacheable(opts, body, context) do
    cache = resolve_cache(opts)
    key = resolve_key(opts, context)
    match = eval_match(opts, quote(do: result))
    error_handler = handle_error(opts, quote(do: result))
    ttl_opt = if opts[:ttl], do: [ttl: opts[:ttl]], else: []

    quote do
      cache = unquote(cache)
      key = unquote(key)

      case cache.get(key) do
        nil ->
          result = unquote(body)

          try do
            case unquote(match) do
              {true, value} ->
                cache.put(key, value, unquote(ttl_opt))
                result

              {true, value, runtime_opts} ->
                opts = unquote(merge_opts(ttl_opt, quote(do: runtime_opts)))
                cache.put(key, value, opts)
                result

              false ->
                result
            end
          rescue
            error -> unquote(error_handler).(error)
          end

        cached_value ->
          cached_value
      end
    end
  end

  def cache_put(opts, body, _context) do
    cache = resolve_cache(opts)
    keys = opts[:keys]
    match = eval_match(opts, quote(do: result))
    error_handler = handle_error(opts, quote(do: result))
    ttl_opt = if opts[:ttl], do: [ttl: opts[:ttl]], else: []

    quote do
      cache = unquote(cache)
      result = unquote(body)

      try do
        case unquote(match) do
          {true, value} ->
            for key <- unquote(keys) do
              cache.put(key, value, unquote(ttl_opt))
            end

          {true, value, runtime_opts} ->
            opts = unquote(merge_opts(ttl_opt, quote(do: runtime_opts)))

            for key <- unquote(keys) do
              cache.put(key, value, opts)
            end

          false ->
            :ok
        end
      rescue
        error -> unquote(error_handler).(error)
      end

      result
    end
  end

  def cache_evict(opts, body, _context) do
    cache = resolve_cache(opts)
    keys = opts[:keys]
    all_entries = opts[:all_entries] || false
    before_invocation = opts[:before_invocation] || false
    error_handler = handle_error(opts, quote(do: result))

    evict_code =
      quote do
        cache = unquote(cache)

        try do
          if unquote(all_entries) do
            cache.delete_all()
          else
            for key <- unquote(keys) do
              cache.delete(key)
            end
          end
        rescue
          error -> unquote(error_handler).(error)
        end
      end

    if before_invocation do
      quote do
        unquote(evict_code)
        unquote(body)
      end
    else
      quote do
        result = unquote(body)
        unquote(evict_code)
        result
      end
    end
  end

  # ============================================================================
  # Telemetry Decorators
  # ============================================================================

  def telemetry_span(opts, body, context) when is_list(opts) do
    event = opts[:event] || [context.module, context.name]
    metadata = extract_metadata(opts[:include] || [], context)
    static_metadata = opts[:metadata] || %{}

    quote do
      metadata = Map.merge(unquote(metadata), unquote(Macro.escape(static_metadata)))

      :telemetry.span(
        unquote(event),
        metadata,
        fn ->
          result = unquote(body)
          {result, metadata}
        end
      )
    end
  end

  def telemetry_span(event, opts, body, context) do
    telemetry_span(Keyword.put(opts, :event, event), body, context)
  end

  def log_call(opts, body, context) do
    level = validate_log_level!(opts[:level] || :info)
    message = opts[:message] || "Calling #{context.name}/#{context.arity}"
    metadata = opts[:metadata] || %{}

    quote do
      require Logger
      Logger.unquote(level)(unquote(message), unquote(Macro.escape(metadata)))
      unquote(body)
    end
  end

  def log_if_slow(opts, body, context) do
    threshold = opts[:threshold]
    level = validate_log_level!(opts[:level] || :warn)
    message = opts[:message] || "Slow operation: #{context.name}/#{context.arity}"

    quote do
      require Logger
      start = System.monotonic_time()
      result = unquote(body)
      stop = System.monotonic_time()
      duration_ms = System.convert_time_unit(stop - start, :native, :millisecond)

      if duration_ms > unquote(threshold) do
        Logger.unquote(level)(
          unquote(message) <> " took #{duration_ms}ms (threshold: #{unquote(threshold)}ms)"
        )
      end

      result
    end
  end

  def log_context(fields, body, context) when is_list(fields) do
    metadata = logger_metadata_from_args(fields, context)

    quote do
      require Logger
      Logger.metadata(unquote(metadata))
      unquote(body)
    end
  end

  # ============================================================================
  # Performance Decorators
  # ============================================================================

  def benchmark(opts, body, context) do
    iterations = opts[:iterations] || 1
    warmup = opts[:warmup] || 0
    print = opts[:print] != false

    quote do
      # Warmup
      for _ <- 1..unquote(warmup) do
        unquote(body)
      end

      # Measure
      times =
        for _ <- 1..unquote(iterations) do
          {result, duration} = unquote(with_timing(body))
          duration
        end

      if unquote(print) do
        avg = Enum.sum(times) / length(times)
        min = Enum.min(times)
        max = Enum.max(times)

        IO.puts("""
        Benchmark #{unquote(context.name)}/#{unquote(context.arity)}:
          Iterations: #{unquote(iterations)}
          Avg: #{avg}μs
          Min: #{min}μs
          Max: #{max}μs
        """)
      end

      unquote(body)
    end
  end

  def measure(opts, body, context) do
    unit = opts[:unit] || :microsecond
    print = opts[:print] != false

    quote do
      start = System.monotonic_time()
      result = unquote(body)
      stop = System.monotonic_time()
      duration = System.convert_time_unit(stop - start, :native, unquote(unit))

      if unquote(print) do
        IO.puts(
          "#{unquote(context.name)}/#{unquote(context.arity)} took #{duration}#{unquote(unit_suffix(unit))}"
        )
      end

      result
    end
  end

  defp unit_suffix(:nanosecond), do: "ns"
  defp unit_suffix(:microsecond), do: "μs"
  defp unit_suffix(:millisecond), do: "ms"
  defp unit_suffix(:second), do: "s"

  # ============================================================================
  # Debugging Decorators
  # ============================================================================

  def debug(opts, body, context) do
    if Mix.env() in [:dev, :test] do
      label = opts[:label] || "Debug #{context.name}/#{context.arity}"

      quote do
        IO.puts("=== #{unquote(label)} ===")
        result = unquote(body)
        unquote(format_debug(quote(do: result), "Result", opts))
        result
      end
    else
      body
    end
  end

  def inspect(opts, body, context) do
    if Mix.env() in [:dev, :test] do
      label = opts[:label] || "#{context.name}/#{context.arity}"
      inspect_args = opts[:args] != false
      inspect_result = opts[:result] != false

      quote do
        unquote(if inspect_args, do: format_debug(context.args, "#{label} args"))
        result = unquote(body)
        unquote(if inspect_result, do: format_debug(quote(do: result), "#{label} result"))
        result
      end
    else
      body
    end
  end

  def pry(opts, body, _context) do
    if Mix.env() in [:dev, :test] do
      pry_before = opts[:before] || false
      pry_after = opts[:after] != false

      pry_before_code =
        if pry_before do
          quote do
            require IEx
            IEx.pry()
          end
        end

      pry_after_code =
        if pry_after do
          quote do
            require IEx
            IEx.pry()
          end
        end

      quote do
        unquote(pry_before_code)
        result = unquote(body)
        unquote(pry_after_code)
        result
      end
    else
      body
    end
  end

  # ============================================================================
  # Pipeline Decorators
  # ============================================================================

  def pipe_through(pipeline, body, _context) when is_list(pipeline) do
    Enum.reduce(pipeline, body, fn fun, acc ->
      quote do
        unquote(acc) |> unquote(fun).()
      end
    end)
  end

  def around(wrapper, body, _context) do
    quote do
      unquote(wrapper).(fn -> unquote(body) end)
    end
  end

  def compose(decorators, body, context) when is_list(decorators) do
    Enum.reduce(decorators, body, fn {decorator, opts}, acc ->
      apply(__MODULE__, decorator, [opts, acc, context])
    end)
  end
end
