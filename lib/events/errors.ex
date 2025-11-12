defmodule Events.Errors do
  @moduledoc """
  Unified error handling system for Events application.

  This module provides a clean, well-organized error handling layer with clear
  separation of concerns:

  ## Architecture

  - **Core** (`Events.Errors.Error`) - Standard error struct and type definitions
  - **Registry** (`Events.Errors.Registry`) - Error codes and message catalog
  - **Normalizer** (`Events.Errors.Normalizer`) - Public API for error normalization
  - **Mappers** (`Events.Errors.Mappers.*`) - Convert external errors to Error structs
  - **Enrichment** (`Events.Errors.Enrichment.*`) - Add context and metadata
  - **Persistence** (`Events.Errors.Persistence.*`) - Store and query errors

  ## Quick Start

      # Normalize any error
      Events.Errors.normalize({:error, :not_found})
      Events.Errors.normalize(%Ecto.Changeset{valid?: false})

      # Enrich with context
      error
      |> Events.Errors.enrich(user: [user_id: 123], request: [request_id: "req_123"])

      # Store for analysis
      Events.Errors.store(error)

  ## Usage Examples

      # Basic normalization
      {:error, :not_found}
      |> Events.Errors.normalize()
      #=> %Error{type: :not_found, code: :not_found, message: "Resource not found"}

      # With context enrichment
      changeset
      |> Events.Errors.normalize()
      |> Events.Errors.enrich(
        user: [user_id: user.id, role: user.role],
        request: [request_id: request_id, path: "/api/users"]
      )
      |> Events.Errors.store()

      # In result tuples
      User.create(attrs)
      |> Events.Errors.normalize_result()
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, %Error{} = error} -> handle_error(error)
      end

      # Wrapping risky operations
      Events.Errors.wrap(fn ->
        dangerous_operation()
      end)
      #=> {:ok, result} | {:error, %Error{}}

  ## Supported Error Sources

  - **Ecto** - Changesets, queries, constraints
  - **HTTP** - Status codes, Req/Tesla errors
  - **AWS** - ExAws service errors
  - **POSIX** - File system errors
  - **Stripe** - Payment processing errors
  - **GraphQL** - Absinthe errors
  - **Business** - Domain-specific errors
  - **Exceptions** - All Elixir exceptions
  """

  # Re-export core modules
  alias Events.Errors.Error
  alias Events.Errors.Registry
  alias Events.Errors.Normalizer
  alias Events.Errors.Enrichment.Context
  alias Events.Errors.Persistence.Storage
  alias Events.Errors.Handler

  # Core error creation
  def new(type, code, opts \\ []), do: Error.new(type, code, opts)
  defdelegate validation?(error), to: Error
  defdelegate not_found?(error), to: Error
  defdelegate unauthorized?(error), to: Error
  defdelegate internal?(error), to: Error
  defdelegate retriable?(error), to: Error

  # Error transformation
  defdelegate to_tuple(error), to: Error
  defdelegate to_map(error), to: Error
  defdelegate with_metadata(error, metadata), to: Error
  defdelegate with_message(error, message), to: Error
  defdelegate with_details(error, details), to: Error

  # Registry functions
  defdelegate message(type, code), to: Registry
  defdelegate exists?(type, code), to: Registry
  defdelegate list(type), to: Registry
  defdelegate types(), to: Registry

  # Normalization (main API)
  def normalize(error, opts \\ []), do: Normalizer.normalize(error, opts)
  def normalize_result(result, opts \\ []), do: Normalizer.normalize_result(result, opts)
  def normalize_pipe(value, opts \\ []), do: Normalizer.normalize_pipe(value, opts)
  def wrap(fun, opts \\ []), do: Normalizer.wrap(fun, opts)

  # Enrichment
  defdelegate enrich(error, context), to: Context
  defdelegate capture_caller(error), to: Context
  defdelegate with_environment(error), to: Context
  defdelegate with_timestamp(error), to: Context

  # Persistence
  def store(error, opts \\ []), do: Storage.store(error, opts)
  def store_async(error, opts \\ []), do: Storage.store_async(error, opts)
  defdelegate get(id), to: Storage
  defdelegate get_by_fingerprint(fingerprint), to: Storage
  defdelegate get_recent(opts), to: Storage
  def group_by(field, opts \\ []), do: Storage.group_by(field, opts)
  defdelegate resolve(id, opts), to: Storage

  # Universal error handler (recommended for most use cases)
  def handle_error(error, context_or_opts \\ [], opts \\ []),
    do: Handler.handle_error(error, context_or_opts, opts)

  def handle_error_tuple(error, context_or_opts \\ [], opts \\ []),
    do: Handler.handle_error_tuple(error, context_or_opts, opts)

  def handle_plug_error(conn, error, opts \\ []),
    do: Handler.handle_plug_error(conn, error, opts)

  def handle_graphql_error(error, context, opts \\ []),
    do: Handler.handle_graphql_error(error, context, opts)

  def handle_worker_error(error, context, opts \\ []),
    do: Handler.handle_worker_error(error, context, opts)

  @doc """
  Full error handling pipeline: normalize, enrich, and store.

  ## Examples

      error_tuple
      |> Events.Errors.handle(
        context: [user: [user_id: 123], request: [request_id: "req_123"]],
        store: true
      )
  """
  @spec handle(term(), keyword()) :: Error.t()
  def handle(error, opts \\ []) do
    error
    |> normalize(Keyword.take(opts, [:metadata]))
    |> maybe_enrich(Keyword.get(opts, :context))
    |> maybe_store(Keyword.get(opts, :store, false), Keyword.get(opts, :store_opts, []))
  end

  ## Helpers

  defp maybe_enrich(error, nil), do: error
  defp maybe_enrich(error, context), do: Context.enrich(error, context)

  defp maybe_store(error, false, _opts), do: error

  defp maybe_store(error, true, opts) do
    case Storage.store(error, opts) do
      {:ok, _stored} -> error
      {:error, _changeset} -> error
    end
  end
end
