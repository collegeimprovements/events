defmodule FnDecorator.Shared do
  @moduledoc """
  Shared utilities for all decorator types.
  Consolidates common functionality to reduce duplication.
  """

  # ============================================================================
  # Cache Resolution
  # ============================================================================

  @doc """
  Resolves cache module from options.
  Supports direct module or MFA tuple for dynamic resolution.
  """
  def resolve_cache(opts) do
    case Keyword.fetch!(opts, :cache) do
      {mod, fun, args} ->
        quote do: unquote(mod).unquote(fun)(unquote_splicing(args))

      module when is_atom(module) ->
        module
    end
  end

  @doc """
  Generates cache key resolution code.
  """
  def resolve_key(opts, context) do
    cond do
      Keyword.has_key?(opts, :key) ->
        quote do: unquote(opts[:key])

      Keyword.has_key?(opts, :key_generator) ->
        generate_key(opts[:key_generator], context)

      true ->
        generate_default_key(opts, context)
    end
  end

  defp generate_key({mod, args}, context) when is_list(args) do
    quote do
      unquote(mod).generate(
        unquote(context.module),
        unquote(context.name),
        unquote(context.args),
        unquote_splicing(args)
      )
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

  defp generate_default_key(opts, context) do
    cache = resolve_cache(opts)

    quote do
      cache = unquote(cache)

      cache.__default_key_generator__().generate(
        unquote(context.module),
        unquote(context.name),
        unquote(context.args)
      )
    end
  end

  # ============================================================================
  # Match Functions
  # ============================================================================

  @doc """
  Evaluates match function for conditional caching/processing.
  """
  def eval_match(opts, result_var) do
    case opts[:match] do
      nil ->
        quote do: {true, unquote(result_var)}

      match_fn ->
        quote do
          case unquote(match_fn).(unquote(result_var)) do
            true ->
              {true, unquote(result_var)}

            {true, value} ->
              {true, value}

            {true, value, opts} ->
              {true, value, opts}

            false ->
              false

            other ->
              raise ArgumentError,
                    "Match function must return true, {true, value}, {true, value, opts}, or false. Got: #{inspect(other)}"
          end
        end
    end
  end

  # ============================================================================
  # Error Handling
  # ============================================================================

  @doc """
  Generates error handling code based on strategy.
  """
  def handle_error(opts, default \\ nil) do
    case opts[:on_error] || :raise do
      :raise ->
        quote do: fn error -> raise error end

      :nothing ->
        quote do: fn _error -> unquote(default) end
    end
  end

  @doc """
  Wraps body in error tracking.
  """
  def wrap_error_tracking(body, reporter, opts) do
    threshold = opts[:threshold] || 1

    quote do
      try do
        unquote(body)
      rescue
        error ->
          stacktrace = __STACKTRACE__
          attempt = var!(attempt, nil) || 1

          if attempt >= unquote(threshold) do
            unquote(reporter).capture_exception(error,
              stacktrace: stacktrace,
              extra: %{
                module: unquote(opts[:module]),
                function: unquote(opts[:function]),
                attempt: attempt
              }
            )
          end

          reraise error, stacktrace
      end
    end
  end

  # ============================================================================
  # Telemetry & Metadata
  # ============================================================================

  @doc """
  Extracts metadata from context for telemetry.
  """
  def extract_metadata(include_vars, context) when is_list(include_vars) do
    base_metadata =
      quote do
        %{
          module: unquote(context.module),
          function: unquote(context.name),
          arity: unquote(context.arity)
        }
      end

    if Enum.empty?(include_vars) do
      base_metadata
    else
      var_captures =
        for var_name <- include_vars do
          quote do
            {unquote(var_name), var!(unquote(Macro.var(var_name, nil)))}
          end
        end

      quote do
        Map.merge(
          unquote(base_metadata),
          Map.new([unquote_splicing(var_captures)])
        )
      end
    end
  end

  @doc """
  Creates measurement map with timing.
  """
  def measurement_map(start_var, stop_var) do
    quote do
      %{
        duration: unquote(stop_var) - unquote(start_var),
        monotonic_time: unquote(stop_var)
      }
    end
  end

  @doc """
  Creates start measurement map.
  """
  def start_measurement_map(start_var) do
    quote do
      %{
        system_time: System.system_time(),
        monotonic_time: unquote(start_var)
      }
    end
  end

  @doc """
  Converts time duration to specified unit.
  """
  def convert_duration(duration_var, unit) do
    quote do
      System.convert_time_unit(unquote(duration_var), :native, unquote(unit))
    end
  end

  # ============================================================================
  # Process Info
  # ============================================================================

  @doc """
  Gets memory usage for current process.
  """
  def get_memory do
    quote do: :erlang.memory(:total)
  end

  @doc """
  Gets process info for current process.
  """
  def get_process_info(keys) when is_list(keys) do
    quote do
      Process.info(self(), unquote(keys))
      |> Enum.into(%{})
    end
  end

  # ============================================================================
  # Logging
  # ============================================================================

  @doc """
  Validates log level at compile time.
  """
  def validate_log_level!(level)
      when level in ~w(emergency alert critical error warning warn notice info debug)a do
    level
  end

  def validate_log_level!(level) do
    raise ArgumentError, """
    Invalid log level: #{inspect(level)}
    Valid levels: :emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug
    """
  end

  @doc """
  Creates Logger metadata from function arguments.
  """
  def logger_metadata_from_args(field_names, context) when is_list(field_names) do
    Enum.zip(field_names, Enum.take(context.args, length(field_names)))
  end

  # ============================================================================
  # Option Merging
  # ============================================================================

  @doc """
  Merges static and runtime options.
  """
  def merge_opts(static_opts, runtime_opts \\ []) do
    quote do
      unquote(static_opts)
      |> Keyword.merge(unquote(runtime_opts))
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end
  end

  # ============================================================================
  # Debugging Utilities
  # ============================================================================

  @doc """
  Formats value for debug output.
  """
  def format_debug(value, label, opts \\ []) do
    max_width = opts[:width] || 80

    quote do
      value = unquote(value)
      label = unquote(label)

      formatted = inspect(value, pretty: true, limit: :infinity, width: unquote(max_width))
      IO.puts("#{label}: #{formatted}")
      value
    end
  end

  @doc """
  Wraps code with timing measurement.
  """
  def with_timing(body) do
    quote do
      start = System.monotonic_time()
      result = unquote(body)
      stop = System.monotonic_time()
      duration = System.convert_time_unit(stop - start, :native, :microsecond)
      {result, duration}
    end
  end

  # ============================================================================
  # Testing Utilities
  # ============================================================================

  @doc """
  Generates sample data based on spec.
  """
  def generate_sample_data(spec) do
    quote do
      case unquote(spec) do
        {:list, type, count} ->
          for _ <- 1..count, do: unquote(__MODULE__).generate_sample_data(type)

        {:map, keys} ->
          Map.new(keys, fn {k, v_spec} ->
            {k, unquote(__MODULE__).generate_sample_data(v_spec)}
          end)

        :string ->
          "test_string_#{:rand.uniform(1000)}"

        :integer ->
          :rand.uniform(1000)

        :float ->
          :rand.uniform() * 1000

        :boolean ->
          :rand.uniform(2) == 1

        :atom ->
          :"test_atom_#{:rand.uniform(1000)}"

        generator when is_function(generator, 0) ->
          generator.()

        literal ->
          literal
      end
    end
  end

  # ============================================================================
  # Timing and Measurement Utilities
  # ============================================================================

  @doc """
  Wraps body with timing, returns {result, duration}.

  The duration is in the specified unit (default: milliseconds).

  ## Examples

      timed_execution(body, :microsecond)
      # Returns: {result, duration_in_microseconds}
  """
  defmacro timed_execution(body, unit \\ :millisecond) do
    quote do
      start_time = System.monotonic_time()
      result = unquote(body)
      duration = System.monotonic_time() - start_time
      duration_converted = System.convert_time_unit(duration, :native, unquote(unit))
      {result, duration_converted}
    end
  end

  @doc """
  Wraps body with timing, binds duration to variable, returns result.

  ## Examples

      quote do
        result = unquote(__MODULE__).measure_and_bind(unquote(body), duration, :millisecond)
        IO.puts("Took: \#{duration}ms")
        result
      end
  """
  def measure_and_bind(body, unit \\ :millisecond) do
    quote do
      start_time = System.monotonic_time()
      result = unquote(body)
      duration = System.monotonic_time() - start_time
      duration_converted = System.convert_time_unit(duration, :native, unquote(unit))
      {result, duration_converted}
    end
  end

  # ============================================================================
  # Argument Extraction Utilities
  # ============================================================================

  @doc """
  Generates code to build a map from runtime arguments using context.

  Returns quoted expression that evaluates to %{arg_name => value}.

  ## Examples

      # In a decorator
      quote do
        args_map = unquote(__MODULE__).args_to_map(var!(args), unquote(context))
        # args_map is now %{user_id: 123, name: "John"}
      end
  """
  def args_to_map(context) do
    arg_names = FnDecorator.Support.Context.arg_names(context)

    quote do
      unquote(arg_names)
      |> Enum.zip(var!(args))
      |> Map.new()
    end
  end

  @doc """
  Extracts specific fields from arguments into a map.

  ## Examples

      # In a decorator
      quote do
        captured = unquote(__MODULE__).extract_fields(
          var!(args),
          unquote(context),
          [:user_id, :amount]
        )
        # captured is %{user_id: 123, amount: 100}
      end
  """
  def extract_fields(context, field_names) do
    arg_names = FnDecorator.Support.Context.arg_names(context)

    quote do
      unquote(arg_names)
      |> Enum.zip(var!(args))
      |> Map.new()
      |> Map.take(unquote(field_names))
    end
  end

  # ============================================================================
  # Error Handling Utilities
  # ============================================================================

  @doc """
  Standardized error handling wrapper with multiple strategies.

  ## Strategies

  * `:raise` - Let errors bubble up (default)
  * `:nothing` - Catch all errors, return nil
  * `:return_error` - Catch errors, return {:error, exception}
  * `:return_nil` - Catch errors, return nil
  * `:log` - Log error then reraise
  * `:ignore` - Silently catch and ignore

  ## Examples

      wrap_with_error_handling(body, :return_error)
      wrap_with_error_handling(body, :log, logger_metadata: [context: "api"])
  """
  def wrap_with_error_handling(body, strategy, opts \\ [])

  def wrap_with_error_handling(body, :raise, _opts) do
    body
  end

  def wrap_with_error_handling(body, :nothing, _opts) do
    quote do
      try do
        unquote(body)
      rescue
        _ -> nil
      end
    end
  end

  def wrap_with_error_handling(body, :return_error, _opts) do
    quote do
      try do
        unquote(body)
      rescue
        error -> {:error, error}
      end
    end
  end

  def wrap_with_error_handling(body, :return_nil, _opts) do
    quote do
      try do
        unquote(body)
      rescue
        _ -> nil
      end
    end
  end

  def wrap_with_error_handling(body, :log, opts) do
    metadata = opts[:logger_metadata] || []

    quote do
      try do
        unquote(body)
      rescue
        error ->
          require Logger

          Logger.error(
            "Error in decorated function: #{Kernel.inspect(error)}",
            unquote(metadata)
          )

          reraise error, __STACKTRACE__
      end
    end
  end

  def wrap_with_error_handling(body, :ignore, _opts) do
    quote do
      try do
        unquote(body)
      rescue
        _ -> :ok
      catch
        _ -> :ok
      end
    end
  end

  # ============================================================================
  # Environment Utilities
  # ============================================================================

  @doc """
  Returns true if running in development or test environment.
  """
  def development?, do: Mix.env() in [:dev, :test]

  @doc """
  Returns true if running in production environment.
  """
  def production?, do: Mix.env() == :prod

  @doc """
  Returns true if running in test environment.
  """
  def test?, do: Mix.env() == :test

  @doc """
  Conditionally compiles code based on environment.

  ## Examples

      when_dev(quote do
        IO.puts("Debug info")
      end)
      # Only included in dev/test builds
  """
  defmacro when_dev(body) do
    if Mix.env() in [:dev, :test] do
      body
    else
      quote do: nil
    end
  end

  @doc """
  Conditionally compiles code in test environment only.
  """
  defmacro when_test(body) do
    if Mix.env() == :test do
      body
    else
      quote do: nil
    end
  end
end
