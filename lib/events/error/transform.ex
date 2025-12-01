defmodule Events.Error.Transform do
  @moduledoc """
  Transformation modules for converting various error sources to Error structs.

  ## Deprecation Notice

  **This module and its sub-modules are deprecated.** Use the `Events.Normalizable`
  protocol instead, which provides:

  - Type-based dispatch (extensible without modifying core code)
  - Consistent interface for all error types
  - Integration with `Events.Recoverable` protocol
  - Better error context and recoverability tracking

  ## Migration Guide

      # OLD (deprecated)
      Events.Error.Transform.Ecto.transform(changeset)
      Events.Error.Transform.HTTP.transform(404)
      Events.Error.Transform.POSIX.transform(:enoent)

      # NEW (preferred)
      Events.Normalizable.normalize(changeset)
      Events.HttpError.new(404) |> Events.Normalizable.normalize()
      Events.PosixError.new(:enoent) |> Events.Normalizable.normalize()

      # Or via unified API
      Events.Errors.Normalizer.normalize(changeset)
      Events.Error.normalize(changeset)

  ## Available Protocol Implementations

  The `Events.Normalizable` protocol has implementations for:
  - `Ecto.Changeset`, `Ecto.NoResultsError`, `Ecto.StaleEntryError`, etc.
  - `Postgrex.Error`, `DBConnection.ConnectionError`
  - `Mint.TransportError`, `Mint.HTTPError`
  - `Events.HttpError` (wrapper for HTTP status codes)
  - `Events.PosixError` (wrapper for POSIX error atoms)
  - Any exception (via `Any` fallback)

  This module contains submodules for transforming specific error types:
  - Ecto - Database and changeset errors
  - HTTP - HTTP status codes and request errors
  - AWS - AWS service errors
  - POSIX - File system errors
  - Business - Domain-specific errors
  """

  defmodule Ecto do
    @moduledoc """
    Transforms Ecto errors into standard Error structs.

    **Deprecated:** Use `Events.Normalizable.normalize/1` instead.
    """

    @deprecated "Use Events.Normalizable.normalize/1 instead"

    alias Events.Error

    @doc """
    Transforms an Ecto changeset into an Error.
    """
    def transform(%{__struct__: Ecto.Changeset, valid?: false} = changeset) do
      errors = traverse_errors(changeset)

      Error.new(:validation, :validation_failed,
        message: "Validation failed",
        details: errors,
        source: changeset
      )
    end

    def transform({:error, %{__struct__: Ecto.Changeset} = changeset}) do
      transform(changeset)
    end

    def transform(%{__struct__: Ecto.NoResultsError} = error) do
      Error.new(:not_found, :no_results,
        message: "No results found",
        source: error
      )
    end

    def transform(%{__struct__: Ecto.MultipleResultsError} = error) do
      Error.new(:conflict, :multiple_results,
        message: "Multiple results found when expecting one",
        source: error
      )
    end

    def transform(%{__struct__: Ecto.Query.CastError} = error) do
      Error.new(:validation, :invalid_query,
        message: "Invalid query parameter",
        details: %{
          type: error.type,
          value: error.value,
          message: Exception.message(error)
        },
        source: error
      )
    end

    def transform(error) do
      Error.new(:internal, :database_error,
        message: "Database error occurred",
        source: error
      )
    end

    defp traverse_errors(changeset) do
      changeset.__struct__.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    end
  end

  defmodule HTTP do
    @moduledoc """
    Transforms HTTP errors into standard Error structs.

    **Deprecated:** Use `Events.HttpError.new/1` with `Events.Normalizable.normalize/1` instead.
    """

    @deprecated "Use Events.HttpError with Events.Normalizable protocol instead"

    alias Events.Error

    @doc """
    Transforms HTTP status codes and response errors.
    """
    def transform(status) when is_integer(status) do
      {type, code, message} = status_to_error(status)
      Error.new(type, code, message: message, details: %{status: status})
    end

    def transform({:error, %Req.Response{status: status, body: body}}) do
      {type, code, message} = status_to_error(status)

      Error.new(type, code,
        message: message,
        details: %{status: status, body: body}
      )
    end

    def transform({:error, %Mint.TransportError{reason: reason}}) do
      Error.new(:network, :transport_error,
        message: "Network transport error",
        details: %{reason: reason}
      )
    end

    def transform({:error, :timeout}) do
      Error.new(:timeout, :request_timeout, message: "Request timed out")
    end

    def transform(error) do
      Error.new(:network, :http_error,
        message: "HTTP error occurred",
        source: error
      )
    end

    defp status_to_error(status) do
      case status do
        400 ->
          {:validation, :bad_request, "Bad request"}

        401 ->
          {:unauthorized, :unauthorized, "Authentication required"}

        403 ->
          {:forbidden, :forbidden, "Access denied"}

        404 ->
          {:not_found, :not_found, "Resource not found"}

        409 ->
          {:conflict, :conflict, "Resource conflict"}

        422 ->
          {:validation, :unprocessable_entity, "Validation failed"}

        429 ->
          {:rate_limited, :too_many_requests, "Too many requests"}

        500 ->
          {:internal, :internal_server_error, "Internal server error"}

        502 ->
          {:external, :bad_gateway, "Bad gateway"}

        503 ->
          {:external, :service_unavailable, "Service unavailable"}

        504 ->
          {:timeout, :gateway_timeout, "Gateway timeout"}

        _ when status >= 400 and status < 500 ->
          {:validation, :client_error, "Client error"}

        _ when status >= 500 ->
          {:internal, :server_error, "Server error"}

        _ ->
          {:internal, :unknown_status, "Unknown status code"}
      end
    end
  end

  defmodule AWS do
    @moduledoc """
    Transforms AWS service errors into standard Error structs.

    **Deprecated:** Implement `Events.Normalizable` for AWS error types instead.
    """

    @deprecated "Implement Events.Normalizable for AWS error types instead"

    alias Events.Error

    @doc """
    Transforms AWS/S3 errors.
    """
    def transform({:error, {:s3_error, status, body}}) do
      Error.new(:external, :s3_error,
        message: "S3 operation failed",
        details: %{status: status, body: body}
      )
    end

    def transform({:error, {:http_error, status, body}}) do
      Error.new(:external, :aws_http_error,
        message: "AWS HTTP error",
        details: %{status: status, body: body}
      )
    end

    def transform({:error, "AccessDenied"}) do
      Error.new(:forbidden, :aws_access_denied, message: "AWS access denied")
    end

    def transform({:error, "NoSuchBucket"}) do
      Error.new(:not_found, :bucket_not_found, message: "S3 bucket not found")
    end

    def transform({:error, "NoSuchKey"}) do
      Error.new(:not_found, :key_not_found, message: "S3 object not found")
    end

    def transform({:error, "InvalidAccessKeyId"}) do
      Error.new(:unauthorized, :invalid_access_key, message: "Invalid AWS access key")
    end

    def transform({:error, "SignatureDoesNotMatch"}) do
      Error.new(:unauthorized, :invalid_signature, message: "Invalid AWS signature")
    end

    def transform({:error, "RequestTimeout"}) do
      Error.new(:timeout, :aws_timeout, message: "AWS request timed out")
    end

    def transform(error) do
      Error.new(:external, :aws_error,
        message: "AWS error occurred",
        source: error
      )
    end
  end

  defmodule POSIX do
    @moduledoc """
    Transforms POSIX/file system errors into standard Error structs.

    **Deprecated:** Use `Events.PosixError.new/1` with `Events.Normalizable.normalize/1` instead.
    """

    @deprecated "Use Events.PosixError with Events.Normalizable protocol instead"

    alias Events.Error

    @doc """
    Transforms file system errors.
    """
    def transform(:enoent) do
      Error.new(:not_found, :file_not_found, message: "File or directory not found")
    end

    def transform(:eacces) do
      Error.new(:forbidden, :permission_denied, message: "Permission denied")
    end

    def transform(:eexist) do
      Error.new(:conflict, :file_exists, message: "File already exists")
    end

    def transform(:eisdir) do
      Error.new(:validation, :is_directory, message: "Is a directory")
    end

    def transform(:enotdir) do
      Error.new(:validation, :not_directory, message: "Not a directory")
    end

    def transform(:enospc) do
      Error.new(:internal, :no_space, message: "No space left on device")
    end

    def transform(:emfile) do
      Error.new(:internal, :too_many_files, message: "Too many open files")
    end

    def transform(:enametoolong) do
      Error.new(:validation, :name_too_long, message: "File name too long")
    end

    def transform(error) when is_atom(error) do
      Error.new(:internal, :file_error,
        message: "File system error: #{error}",
        details: %{posix_error: error}
      )
    end

    def transform(error) do
      Error.new(:internal, :file_error,
        message: "File system error",
        source: error
      )
    end
  end

  defmodule Business do
    @moduledoc """
    Transforms business/domain errors into standard Error structs.

    **Deprecated:** Implement `Events.Normalizable` for your business error types instead.
    """

    @deprecated "Implement Events.Normalizable for business error types instead"

    alias Events.Error

    @doc """
    Transforms domain-specific business errors.
    """
    def transform({:insufficient_funds, amount, available}) do
      Error.new(:business, :insufficient_funds,
        message: "Insufficient funds",
        details: %{
          required: amount,
          available: available,
          shortfall: amount - available
        }
      )
    end

    def transform({:invalid_state_transition, from, to}) do
      Error.new(:business, :invalid_state_transition,
        message: "Invalid state transition",
        details: %{from: from, to: to}
      )
    end

    def transform({:business_rule_violation, rule, context}) do
      Error.new(:business, :business_rule_violation,
        message: "Business rule violation: #{rule}",
        details: context
      )
    end

    def transform({:quota_exceeded, resource, limit}) do
      Error.new(:business, :quota_exceeded,
        message: "Quota exceeded for #{resource}",
        details: %{resource: resource, limit: limit}
      )
    end

    def transform(error) do
      Error.new(:business, :business_error,
        message: "Business logic error",
        source: error
      )
    end
  end
end
