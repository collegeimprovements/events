defmodule Events.DecoratorMinimal do
  @moduledoc """
  Minimal decorator implementation with reduced function surface area.
  All decorators are handled through a single apply function with pattern matching.
  """

  # Single entry point for all decorators
  def apply(decorator, opts, body, context) do
    case decorator do
      # Caching decorators
      :cacheable -> cache_decorator(:read, opts, body, context)
      :cache_put -> cache_decorator(:write, opts, body, context)
      :cache_evict -> cache_decorator(:evict, opts, body, context)
      # Telemetry decorators
      :telemetry_span -> telemetry_decorator(:span, opts, body, context)
      :log_call -> telemetry_decorator(:log, opts, body, context)
      :log_if_slow -> telemetry_decorator(:slow, opts, body, context)
      :log_context -> telemetry_decorator(:context, opts, body, context)
      # Performance decorators
      :benchmark -> performance_decorator(:benchmark, opts, body, context)
      :measure -> performance_decorator(:measure, opts, body, context)
      # Debug decorators (dev/test only)
      :debug -> debug_decorator(:debug, opts, body, context)
      :inspect -> debug_decorator(:inspect, opts, body, context)
      :pry -> debug_decorator(:pry, opts, body, context)
      # Pipeline decorators
      :pipe_through -> pipeline_decorator(:pipe, opts, body, context)
      :around -> pipeline_decorator(:around, opts, body, context)
      :compose -> pipeline_decorator(:compose, opts, body, context)
      # Unknown decorator, pass through
      _ -> body
    end
  end

  # Unified cache decorator handler
  defp cache_decorator(type, opts, body, context) do
    cache = resolve_module(opts[:cache])

    case type do
      :read ->
        key = resolve_key(opts, context)

        quote do
          cache = unquote(cache)
          key = unquote(key)

          case cache.get(key) do
            nil ->
              result = unquote(body)
              cache.put(key, result, unquote(Keyword.take(opts, [:ttl])))
              result

            cached ->
              cached
          end
        end

      :write ->
        keys = opts[:keys] || []

        quote do
          cache = unquote(cache)
          result = unquote(body)

          for key <- unquote(keys) do
            cache.put(key, result, unquote(Keyword.take(opts, [:ttl])))
          end

          result
        end

      :evict ->
        keys = opts[:keys] || []

        evict_code =
          quote do
            cache = unquote(cache)
            for key <- unquote(keys), do: cache.delete(key)
          end

        if opts[:before_invocation] do
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
  end

  # Unified telemetry decorator handler
  defp telemetry_decorator(type, opts, body, context) do
    case type do
      :span ->
        event = opts[:event] || [context.module, context.name]
        metadata = build_metadata(opts, context)

        quote do
          :telemetry.span(unquote(event), unquote(metadata), fn ->
            result = unquote(body)
            {result, unquote(metadata)}
          end)
        end

      :log ->
        level = opts[:level] || :info
        message = opts[:message] || "Calling #{context.name}/#{context.arity}"

        quote do
          require Logger
          Logger.unquote(level)(unquote(message))
          unquote(body)
        end

      :slow ->
        threshold = opts[:threshold]
        level = opts[:level] || :warn

        quote do
          require Logger
          start = System.monotonic_time()
          result = unquote(body)

          duration_ms =
            System.convert_time_unit(
              System.monotonic_time() - start,
              :native,
              :millisecond
            )

          if duration_ms > unquote(threshold) do
            Logger.unquote(level)("Slow operation took #{duration_ms}ms")
          end

          result
        end

      :context ->
        fields = opts
        metadata = build_logger_metadata(fields, context)

        quote do
          require Logger
          Logger.metadata(unquote(metadata))
          unquote(body)
        end
    end
  end

  # Unified performance decorator handler
  defp performance_decorator(type, opts, body, _context) do
    case type do
      :benchmark ->
        iterations = opts[:iterations] || 1

        quote do
          times =
            for _ <- 1..unquote(iterations) do
              start = System.monotonic_time()
              unquote(body)

              System.convert_time_unit(
                System.monotonic_time() - start,
                :native,
                :microsecond
              )
            end

          if unquote(opts[:print] != false) do
            avg = Enum.sum(times) / length(times)
            IO.puts("Benchmark: #{unquote(iterations)} iterations, avg: #{avg}μs")
          end

          unquote(body)
        end

      :measure ->
        unit = opts[:unit] || :microsecond

        quote do
          start = System.monotonic_time()
          result = unquote(body)

          duration =
            System.convert_time_unit(
              System.monotonic_time() - start,
              :native,
              unquote(unit)
            )

          if unquote(opts[:print] != false) do
            IO.puts("Execution took #{duration}#{unquote(unit_str(unit))}")
          end

          result
        end
    end
  end

  # Unified debug decorator handler (dev/test only)
  defp debug_decorator(type, opts, body, _context) do
    if Mix.env() in [:dev, :test] do
      case type do
        :debug ->
          label = opts[:label] || "Debug"

          quote do
            IO.puts("=== #{unquote(label)} ===")
            result = unquote(body)
            IO.inspect(result, label: "Result")
            result
          end

        :inspect ->
          quote do
            IO.inspect(binding(), label: "Args")
            result = unquote(body)
            IO.inspect(result, label: "Result")
            result
          end

        :pry ->
          pry_before =
            if opts[:before] do
              quote do
                require IEx
                IEx.pry()
              end
            end

          pry_after =
            if opts[:after] != false do
              quote do
                require IEx
                IEx.pry()
              end
            end

          quote do
            unquote(pry_before)
            result = unquote(body)
            unquote(pry_after)
            result
          end
      end
    else
      body
    end
  end

  # Unified pipeline decorator handler
  defp pipeline_decorator(type, arg, body, context) do
    case type do
      :pipe ->
        pipeline = arg

        Enum.reduce(pipeline, body, fn fun, acc ->
          quote do: unquote(acc) |> unquote(fun).()
        end)

      :around ->
        wrapper = arg
        quote do: unquote(wrapper).(fn -> unquote(body) end)

      :compose ->
        decorators = arg

        Enum.reduce(decorators, body, fn {decorator, opts}, acc ->
          apply(__MODULE__, :apply, [decorator, opts, acc, context])
        end)
    end
  end

  # Minimal helper functions

  defp resolve_module(nil), do: quote(do: Events.Cache)
  defp resolve_module(module) when is_atom(module), do: module

  defp resolve_module({mod, fun, args}) do
    quote do: unquote(mod).unquote(fun)(unquote_splicing(args))
  end

  defp resolve_key(opts, context) do
    cond do
      opts[:key] -> quote(do: unquote(opts[:key]))
      opts[:key_generator] -> generate_key(opts[:key_generator], context)
      true -> quote(do: {unquote(context.module), unquote(context.name), unquote(context.args)})
    end
  end

  defp generate_key({mod, fun, args}, context) do
    quote do
      unquote(mod).unquote(fun)(
        unquote(context.module),
        unquote(context.name),
        unquote(context.args),
        unquote_splicing(args)
      )
    end
  end

  defp generate_key(mod, context) when is_atom(mod) do
    quote do
      unquote(mod).generate(
        unquote(context.module),
        unquote(context.name),
        unquote(context.args)
      )
    end
  end

  defp build_metadata(opts, context) do
    base = %{
      module: context.module,
      function: context.name,
      arity: context.arity
    }

    include_vars = opts[:include] || []

    if Enum.empty?(include_vars) do
      quote(do: unquote(Macro.escape(base)))
    else
      var_captures =
        for var_name <- include_vars do
          quote do
            {unquote(var_name), var!(unquote(Macro.var(var_name, nil)))}
          end
        end

      quote do
        Map.merge(
          unquote(Macro.escape(base)),
          Map.new([unquote_splicing(var_captures)])
        )
      end
    end
  end

  defp build_logger_metadata(fields, context) when is_list(fields) do
    Enum.zip(fields, Enum.take(context.args, length(fields)))
  end

  defp unit_str(:nanosecond), do: "ns"
  defp unit_str(:microsecond), do: "μs"
  defp unit_str(:millisecond), do: "ms"
  defp unit_str(:second), do: "s"
end
