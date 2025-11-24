defmodule Events.CRUD.Monitor do
  @moduledoc """
  Performance monitoring hooks for CRUD operations.
  Disabled by default - enable via config for production monitoring.
  """

  require Logger

  @spec with_monitoring((-> result), keyword()) :: result when result: var
  def with_monitoring(fun, opts \\ []) do
    if Events.CRUD.Config.enable_observability?() do
      start_time = System.monotonic_time()

      try do
        result = fun.()
        execution_time = System.monotonic_time() - start_time

        # Record metrics
        record_metrics(opts[:operation], execution_time, opts)

        # Add timing to result if it's a Result struct
        add_timing_to_result(result, execution_time)
      rescue
        e ->
          execution_time = System.monotonic_time() - start_time
          record_error(opts[:operation], execution_time, e, opts)
          reraise e, __STACKTRACE__
      end
    else
      fun.()
    end
  end

  @spec record_metrics(atom(), integer(), keyword()) :: :ok
  def record_metrics(operation, execution_time, opts) do
    # Placeholder for metrics recording
    # In production, this would send to monitoring system
    if Events.CRUD.Config.enable_timing?() do
      Logger.debug("CRUD Operation #{operation} took #{execution_time}μs", opts)
    end

    :ok
  end

  @spec record_error(atom(), integer(), term(), keyword()) :: :ok
  def record_error(operation, execution_time, error, opts) do
    # Placeholder for error recording
    Logger.error(
      "CRUD Operation #{operation} failed after #{execution_time}μs: #{inspect(error)}",
      opts
    )

    :ok
  end

  @spec add_timing_to_result(term(), integer()) :: term()
  def add_timing_to_result(%Events.CRUD.Result{} = result, execution_time) do
    timing = Map.put(result.metadata.timing, :execution_time, execution_time)
    metadata = Map.put(result.metadata, :timing, timing)
    %{result | metadata: metadata}
  end

  def add_timing_to_result(result, _execution_time), do: result
end
