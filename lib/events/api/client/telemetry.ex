defmodule Events.Api.Client.Telemetry do
  @moduledoc """
  Telemetry integration for API clients.

  This module delegates to `OmApiClient.Telemetry`.
  See `OmApiClient.Telemetry` for full documentation.
  """

  @prefix [:events, :api_client]

  def prefix, do: @prefix

  defdelegate events(), to: OmApiClient.Telemetry
  defdelegate events(prefix), to: OmApiClient.Telemetry

  def emit_start(client, metadata) do
    OmApiClient.Telemetry.emit_start(client, metadata, @prefix)
  end

  def emit_stop(start_time, client, metadata) do
    OmApiClient.Telemetry.emit_stop(start_time, client, metadata, @prefix)
  end

  def emit_exception(start_time, client, kind, reason, stacktrace, metadata) do
    OmApiClient.Telemetry.emit_exception(
      start_time,
      client,
      kind,
      reason,
      stacktrace,
      metadata,
      @prefix
    )
  end

  def emit_retry(client, attempt, delay_ms, metadata) do
    OmApiClient.Telemetry.emit_retry(client, attempt, delay_ms, metadata, @prefix)
  end

  def span(client, fun, metadata \\ %{}) do
    OmApiClient.Telemetry.span(client, fun, metadata, @prefix)
  end

  defdelegate attach_default_handlers(opts \\ []), to: OmApiClient.Telemetry
  defdelegate attach_logger(opts \\ []), to: OmApiClient.Telemetry
  defdelegate detach_logger(), to: OmApiClient.Telemetry
end
