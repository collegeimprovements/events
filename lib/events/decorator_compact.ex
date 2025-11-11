defmodule Events.DecoratorCompact do
  @moduledoc """
  Ultra-compact decorator system with minimal function surface area.
  All decorators go through a single apply/4 function.
  """

  use Decorator.Define,
    # Define all decorators to use the same handler
    cacheable: 1,
    cache_put: 1,
    cache_evict: 1,
    telemetry_span: 1,
    telemetry_span: 2,
    log_call: 1,
    log_context: 1,
    log_if_slow: 1,
    benchmark: 1,
    measure: 1,
    debug: 1,
    inspect: 1,
    pry: 1,
    pipe_through: 1,
    around: 1,
    compose: 1

  import Events.DecoratorUtils

  # All decorators route through this single function
  def apply_decorator(name, opts, body, context) do
    config = decorator_config(name, opts, context)
    build_ast(config, body)
  end

  # Delegate all decorator functions to the single apply function
  def cacheable(opts, body, ctx), do: apply_decorator(:cacheable, opts, body, ctx)
  def cache_put(opts, body, ctx), do: apply_decorator(:cache_put, opts, body, ctx)
  def cache_evict(opts, body, ctx), do: apply_decorator(:cache_evict, opts, body, ctx)
  def telemetry_span(opts, body, ctx), do: apply_decorator(:telemetry_span, opts, body, ctx)

  def telemetry_span(event, opts, body, ctx),
    do: apply_decorator(:telemetry_span, Keyword.put(opts, :event, event), body, ctx)

  def log_call(opts, body, ctx), do: apply_decorator(:log_call, opts, body, ctx)
  def log_context(fields, body, ctx), do: apply_decorator(:log_context, fields, body, ctx)
  def log_if_slow(opts, body, ctx), do: apply_decorator(:log_if_slow, opts, body, ctx)
  def benchmark(opts, body, ctx), do: apply_decorator(:benchmark, opts, body, ctx)
  def measure(opts, body, ctx), do: apply_decorator(:measure, opts, body, ctx)
  def debug(opts, body, ctx), do: apply_decorator(:debug, opts, body, ctx)
  def inspect(opts, body, ctx), do: apply_decorator(:inspect, opts, body, ctx)
  def pry(opts, body, ctx), do: apply_decorator(:pry, opts, body, ctx)
  def pipe_through(pipeline, body, ctx), do: apply_decorator(:pipe_through, pipeline, body, ctx)
  def around(wrapper, body, ctx), do: apply_decorator(:around, wrapper, body, ctx)
  def compose(decorators, body, ctx), do: apply_decorator(:compose, decorators, body, ctx)

  # Configuration for each decorator type
  defp decorator_config(name, opts, context) do
    base = %{
      name: name,
      opts: opts,
      context: context
    }

    case name do
      :cacheable ->
        Map.merge(base, %{
          type: :cache,
          strategy: :read_through,
          cache: resolve(:module, opts[:cache]),
          key: resolve(:key, opts, context)
        })

      :cache_put ->
        Map.merge(base, %{
          type: :cache,
          strategy: :write_through,
          cache: resolve(:module, opts[:cache]),
          keys: opts[:keys] || []
        })

      :cache_evict ->
        Map.merge(base, %{
          type: :cache,
          strategy: :evict,
          cache: resolve(:module, opts[:cache]),
          keys: opts[:keys] || [],
          before: opts[:before_invocation]
        })

      :telemetry_span ->
        Map.merge(base, %{
          type: :telemetry,
          strategy: :span,
          event: opts[:event] || [context.module, context.name],
          metadata: build_metadata(context, opts[:include] || [], opts[:metadata] || %{})
        })

      :log_call ->
        Map.merge(base, %{
          type: :telemetry,
          strategy: :log,
          level: opts[:level] || :info,
          message: opts[:message] || "Calling #{context.name}/#{context.arity}"
        })

      :log_if_slow ->
        Map.merge(base, %{
          type: :telemetry,
          strategy: :slow,
          threshold: opts[:threshold],
          level: opts[:level] || :warn
        })

      :log_context ->
        Map.merge(base, %{
          type: :telemetry,
          strategy: :context,
          fields: opts
        })

      :benchmark ->
        Map.merge(base, %{
          type: :performance,
          strategy: :benchmark,
          iterations: opts[:iterations] || 1,
          print: opts[:print] != false
        })

      :measure ->
        Map.merge(base, %{
          type: :performance,
          strategy: :measure,
          unit: opts[:unit] || :microsecond,
          print: opts[:print] != false
        })

      :debug ->
        Map.merge(base, %{
          type: :debug,
          strategy: :debug,
          label: opts[:label] || "Debug"
        })

      :inspect ->
        Map.merge(base, %{
          type: :debug,
          strategy: :inspect
        })

      :pry ->
        Map.merge(base, %{
          type: :debug,
          strategy: :pry,
          before: opts[:before],
          after: opts[:after] != false
        })

      :pipe_through ->
        Map.merge(base, %{
          type: :pipeline,
          strategy: :pipe,
          pipeline: opts
        })

      :around ->
        Map.merge(base, %{
          type: :pipeline,
          strategy: :around,
          wrapper: opts
        })

      :compose ->
        Map.merge(base, %{
          type: :pipeline,
          strategy: :compose,
          decorators: opts
        })

      _ ->
        base
    end
  end

  # Single AST builder for all decorator types
  defp build_ast(%{type: :cache} = config, body) do
    case config.strategy do
      :read_through ->
        quote do
          cache = unquote(config.cache)
          key = unquote(config.key)

          case cache.get(key) do
            nil ->
              result = unquote(body)
              cache.put(key, result, unquote(Keyword.take(config.opts, [:ttl])))
              result

            cached ->
              cached
          end
        end

      :write_through ->
        quote do
          cache = unquote(config.cache)
          result = unquote(body)

          for key <- unquote(config.keys) do
            cache.put(key, result, unquote(Keyword.take(config.opts, [:ttl])))
          end

          result
        end

      :evict ->
        evict_code =
          quote do
            cache = unquote(config.cache)
            for key <- unquote(config.keys), do: cache.delete(key)
          end

        if config.before do
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

  defp build_ast(%{type: :telemetry} = config, body) do
    case config.strategy do
      :span ->
        quote do
          :telemetry.span(unquote(config.event), unquote(config.metadata), fn ->
            result = unquote(body)
            {result, unquote(config.metadata)}
          end)
        end

      :log ->
        quote do
          require Logger
          Logger.unquote(config.level)(unquote(config.message))
          unquote(body)
        end

      :slow ->
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

          if duration_ms > unquote(config.threshold) do
            Logger.unquote(config.level)("Slow operation took #{duration_ms}ms")
          end

          result
        end

      :context ->
        metadata = Enum.zip(config.fields, Enum.take(config.context.args, length(config.fields)))

        quote do
          require Logger
          Logger.metadata(unquote(metadata))
          unquote(body)
        end
    end
  end

  defp build_ast(%{type: :performance} = config, body) do
    case config.strategy do
      :benchmark ->
        quote do
          times =
            for _ <- 1..unquote(config.iterations) do
              {_, duration} = unquote(with_timing(body))
              System.convert_time_unit(duration, :native, :microsecond)
            end

          if unquote(config.print) do
            avg = Enum.sum(times) / length(times)
            IO.puts("Benchmark: avg #{avg}μs")
          end

          unquote(body)
        end

      :measure ->
        quote do
          {result, duration} = unquote(with_timing(body))
          duration = System.convert_time_unit(duration, :native, unquote(config.unit))

          if unquote(config.print) do
            IO.puts("Execution: #{duration}#{unquote(unit_suffix(config.unit))}")
          end

          result
        end
    end
  end

  defp build_ast(%{type: :debug} = config, body) do
    if Mix.env() in [:dev, :test] do
      case config.strategy do
        :debug ->
          quote do
            IO.puts("=== #{unquote(config.label)} ===")
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
          before_code =
            if config.before do
              quote do
                require IEx
                IEx.pry()
              end
            end

          after_code =
            if config.after do
              quote do
                require IEx
                IEx.pry()
              end
            end

          quote do
            unquote(before_code)
            result = unquote(body)
            unquote(after_code)
            result
          end
      end
    else
      body
    end
  end

  defp build_ast(%{type: :pipeline} = config, body) do
    case config.strategy do
      :pipe ->
        Enum.reduce(config.pipeline, body, fn fun, acc ->
          quote do: unquote(acc) |> unquote(fun).()
        end)

      :around ->
        quote do: unquote(config.wrapper).(fn -> unquote(body) end)

      :compose ->
        Enum.reduce(config.decorators, body, fn {decorator, opts}, acc ->
          apply_decorator(decorator, opts, acc, config.context)
        end)
    end
  end

  defp build_ast(_config, body), do: body

  defp unit_suffix(:nanosecond), do: "ns"
  defp unit_suffix(:microsecond), do: "μs"
  defp unit_suffix(:millisecond), do: "ms"
  defp unit_suffix(:second), do: "s"
end
