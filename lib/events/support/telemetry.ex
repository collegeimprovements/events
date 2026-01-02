defmodule Events.Support.Telemetry do
  @moduledoc """
  Telemetry helpers for consistent instrumentation across the codebase.

  Thin wrapper around `FnDecorator.Telemetry.Helpers` with Events-specific defaults.

  See `FnDecorator.Telemetry.Helpers` for full documentation.
  """

  defdelegate timed(fun, opts \\ []), to: FnDecorator.Telemetry.Helpers
  defdelegate start_span(event, metadata), to: FnDecorator.Telemetry.Helpers
  defdelegate stop_span(ctx, opts \\ []), to: FnDecorator.Telemetry.Helpers
  defdelegate exception_span(ctx, kind, reason, stacktrace), to: FnDecorator.Telemetry.Helpers
  defdelegate attach_logger(prefix, opts \\ []), to: FnDecorator.Telemetry.Helpers

  defmacro __using__(opts) do
    quote do
      use FnDecorator.Telemetry.Helpers, unquote(opts)
    end
  end

  # Re-export macros
  defmacro span(event, metadata, opts_or_block) do
    quote do
      require FnDecorator.Telemetry.Helpers
      FnDecorator.Telemetry.Helpers.span(unquote(event), unquote(metadata), unquote(opts_or_block))
    end
  end

  defmacro span(event, metadata, opts, block) do
    quote do
      require FnDecorator.Telemetry.Helpers

      FnDecorator.Telemetry.Helpers.span(
        unquote(event),
        unquote(metadata),
        unquote(opts),
        unquote(block)
      )
    end
  end

  defmacro emit(event, measurements, metadata) do
    quote do
      require FnDecorator.Telemetry.Helpers
      FnDecorator.Telemetry.Helpers.emit(unquote(event), unquote(measurements), unquote(metadata))
    end
  end

  defmacro emit(event, measurements, metadata, opts) do
    quote do
      require FnDecorator.Telemetry.Helpers

      FnDecorator.Telemetry.Helpers.emit(
        unquote(event),
        unquote(measurements),
        unquote(metadata),
        unquote(opts)
      )
    end
  end
end
