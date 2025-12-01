defmodule Events.Errors.Mappers do
  @moduledoc """
  Collection of error mappers for converting external errors to Events.Error.

  ## Deprecation Notice

  **This module and its sub-modules are deprecated.** Use the `Events.Normalizable`
  protocol instead, which provides:

  - Type-based dispatch (extensible without modifying core code)
  - Consistent interface for all error types
  - Integration with `Events.Recoverable` protocol

  ## Migration Guide

      # OLD (deprecated)
      Mappers.Ecto.normalize(changeset)
      Mappers.Http.normalize_status(404)

      # NEW (preferred)
      Events.Normalizable.normalize(changeset)
      Events.HttpError.new(404) |> Events.Normalizable.normalize()

      # Or via Normalizer (uses protocol internally)
      Events.Errors.Normalizer.normalize(changeset)

  ## Available Protocol Implementations

  The `Events.Normalizable` protocol has implementations for:
  - `Ecto.Changeset`, `Ecto.NoResultsError`, `Ecto.StaleEntryError`, etc.
  - `Postgrex.Error`, `DBConnection.ConnectionError`
  - `Mint.TransportError`, `Mint.HTTPError`
  - `Events.HttpError` (wrapper for HTTP status codes)
  - `Events.PosixError` (wrapper for POSIX error atoms)
  - Any exception (via `Any` fallback)
  """

  @deprecated "Use Events.Normalizable protocol instead"

  # Re-export all mappers for convenience
  defdelegate normalize_ecto(changeset), to: Events.Errors.Mappers.Ecto, as: :normalize

  # Direct implementation instead of delegation to avoid deprecation warning cascade
  # (Http.normalize_status is also deprecated, and we don't want double warnings)
  @doc false
  @spec normalize_http_status(integer()) :: Events.Error.t()
  def normalize_http_status(status) do
    Events.HttpError.new(status) |> Events.Normalizable.normalize()
  end

  defdelegate normalize_posix(error), to: Events.Errors.Mappers.Posix, as: :normalize
  defdelegate normalize_aws(error), to: Events.Errors.Mappers.Aws, as: :normalize
  defdelegate normalize_stripe(error), to: Events.Errors.Mappers.Stripe, as: :normalize
  defdelegate normalize_graphql(error), to: Events.Errors.Mappers.Graphql, as: :normalize

  def normalize_business(code, details \\ %{}),
    do: Events.Errors.Mappers.Business.normalize(code, details)

  def normalize_exception(exception, stacktrace \\ nil),
    do: Events.Errors.Mappers.Exception.normalize(exception, stacktrace)
end
