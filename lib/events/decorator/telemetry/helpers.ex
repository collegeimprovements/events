defmodule Events.Decorator.Telemetry.Helpers do
  @moduledoc """
  Shared utilities for telemetry and logging decorators.
  """

  @doc """
  Extracts variable values from context for telemetry metadata.

  Given a list of variable names to include, generates code that captures
  those variables' values at runtime.
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
      # Generate code to capture specified variables
      var_captures =
        for var_name <- include_vars do
          quote do
            {unquote(var_name), var!(unquote(Macro.var(var_name, nil)))}
          end
        end

      quote do
        base = unquote(base_metadata)
        vars = Map.new([unquote_splicing(var_captures)])
        Map.merge(base, vars)
      end
    end
  end

  @doc """
  Generates measurement map with timing information.
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
  Generates start measurement map.
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
  Converts duration from native units to specified unit.
  """
  def convert_duration(duration_var, unit) do
    quote do
      System.convert_time_unit(unquote(duration_var), :native, unquote(unit))
    end
  end

  @doc """
  Gets current memory usage for the process.
  """
  def get_memory do
    quote do: :erlang.memory(:total)
  end

  @doc """
  Gets process info for the current process.
  """
  def get_process_info(keys) when is_list(keys) do
    quote do
      Process.info(self(), unquote(keys))
      |> Enum.into(%{})
    end
  end

  @doc """
  Validates log level at compile time.
  """
  def validate_log_level!(level) when level in [:emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug] do
    level
  end

  def validate_log_level!(level) do
    raise ArgumentError, """
    Invalid log level: #{inspect(level)}

    Valid levels are: :emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug
    """
  end

  @doc """
  Generates Logger metadata from function arguments.
  """
  def logger_metadata_from_args(field_names, context) when is_list(field_names) do
    # Match field names with context arguments
    args = context.args

    metadata_pairs =
      Enum.zip(field_names, Enum.take(args, length(field_names)))
      |> Enum.map(fn {field_name, arg_ast} ->
        {field_name, arg_ast}
      end)

    quote do: unquote(metadata_pairs)
  end

  @doc """
  Wraps code in a try/rescue that reports errors to a tracking service.
  """
  def wrap_error_tracking(body, reporter, opts) do
    threshold = Keyword.get(opts, :threshold, 1)

    quote do
      try do
        unquote(body)
      rescue
        error ->
          stacktrace = __STACKTRACE__

          # Only report if this is a genuine error (not first attempt in retry scenario)
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
end
