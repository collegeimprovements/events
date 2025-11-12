defmodule Events.Errors.Mappers do
  @moduledoc """
  Collection of error mappers for converting external errors to Events.Errors.Error.

  This module serves as a namespace for all mapper modules:

  - `Mappers.Ecto` - Ecto changeset and query errors
  - `Mappers.Http` - HTTP status codes and client errors
  - `Mappers.Aws` - AWS service errors
  - `Mappers.Posix` - POSIX file system errors
  - `Mappers.Stripe` - Stripe payment errors
  - `Mappers.Graphql` - Graphql/Absinthe errors
  - `Mappers.Business` - Domain-specific business errors
  - `Mappers.Exception` - Generic Elixir exceptions

  ## Usage

      # Direct mapper usage
      Mappers.Ecto.normalize(changeset)
      Mappers.Http.normalize_status(404)
      Mappers.Aws.normalize({:error, {:http_error, 403, %{}}})

      # Via Normalizer (recommended)
      Normalizer.normalize(changeset)
      Normalizer.normalize({:error, :not_found})
  """

  # Re-export all mappers for convenience
  defdelegate normalize_ecto(changeset), to: Events.Errors.Mappers.Ecto, as: :normalize
  defdelegate normalize_http_status(status), to: Events.Errors.Mappers.Http, as: :normalize_status
  defdelegate normalize_posix(error), to: Events.Errors.Mappers.Posix, as: :normalize
  defdelegate normalize_aws(error), to: Events.Errors.Mappers.Aws, as: :normalize
  defdelegate normalize_stripe(error), to: Events.Errors.Mappers.Stripe, as: :normalize
  defdelegate normalize_graphql(error), to: Events.Errors.Mappers.Graphql, as: :normalize

  def normalize_business(code, details \\ %{}),
    do: Events.Errors.Mappers.Business.normalize(code, details)

  def normalize_exception(exception, stacktrace \\ nil),
    do: Events.Errors.Mappers.Exception.normalize(exception, stacktrace)
end
