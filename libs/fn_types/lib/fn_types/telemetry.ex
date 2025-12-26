defmodule FnTypes.Telemetry do
  @moduledoc """
  Safe telemetry wrapper that handles the case when :telemetry is not available.

  The :telemetry dependency is optional in fn_types. This module provides a safe
  wrapper that no-ops if telemetry isn't loaded, avoiding compile warnings and
  runtime errors.

  ## Usage

      FnTypes.Telemetry.execute([:my_app, :event], %{count: 1}, %{user_id: 123})

  """

  @doc """
  Safely executes a telemetry event if :telemetry is available.

  Returns `:ok` regardless of whether the event was emitted.
  """
  @spec execute(list(atom()), map(), map()) :: :ok
  def execute(event, measurements, metadata) do
    if telemetry_available?() do
      # Use apply to avoid compile-time warnings when telemetry is not available
      apply(:telemetry, :execute, [event, measurements, metadata])
    end

    :ok
  end

  @doc """
  Safely executes a telemetry span if :telemetry is available.

  If telemetry is not available, simply executes the function and returns the result.
  """
  @spec span(list(atom()), map(), (-> {term(), map()})) :: term()
  def span(event, metadata, fun) do
    if telemetry_available?() do
      # Use apply to avoid compile-time warnings when telemetry is not available
      apply(:telemetry, :span, [event, metadata, fun])
    else
      {result, _metadata} = fun.()
      result
    end
  end

  @doc """
  Returns whether the :telemetry module is available.
  """
  @spec telemetry_available?() :: boolean()
  def telemetry_available? do
    Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :execute, 3)
  end
end
