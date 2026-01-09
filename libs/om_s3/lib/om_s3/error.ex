defmodule OmS3.Error do
  @moduledoc """
  S3 error with protocol implementations for normalization and recovery.

  Provides structured error handling for S3 operations with:
  - Error categorization (access denied, not found, timeout, etc.)
  - Recovery strategies for transient failures
  - Integration with `FnTypes.Error` normalization

  ## Error Types

  - `:access_denied` - Insufficient permissions (403)
  - `:not_found` - Object or bucket not found (404)
  - `:conflict` - Bucket already exists, concurrent modification (409)
  - `:precondition_failed` - ETag mismatch, conditional request failed (412)
  - `:request_timeout` - Request took too long (408)
  - `:service_unavailable` - S3 temporarily unavailable (503)
  - `:internal_error` - S3 internal error (500)
  - `:slow_down` - Rate limiting / throttling (503)
  - `:invalid_request` - Malformed request
  - `:connection_error` - Network/connection failure
  - `:unknown` - Unrecognized error

  ## Examples

      # Create from S3 response
      error = OmS3.Error.from_response(403, %{"Code" => "AccessDenied", "Message" => "Access Denied"})
      error.type
      #=> :access_denied

      # Check recoverability
      FnTypes.Protocols.Recoverable.recoverable?(error)
      #=> false

      # Normalize to FnTypes.Error
      FnTypes.Error.normalize(error)
      #=> %FnTypes.Error{type: :forbidden, ...}
  """

  @type error_type ::
          :access_denied
          | :not_found
          | :conflict
          | :precondition_failed
          | :request_timeout
          | :service_unavailable
          | :internal_error
          | :slow_down
          | :invalid_request
          | :connection_error
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          code: String.t() | nil,
          message: String.t(),
          status: pos_integer() | nil,
          request_id: String.t() | nil,
          resource: String.t() | nil,
          details: map()
        }

  defstruct [
    :type,
    :code,
    :message,
    :status,
    :request_id,
    :resource,
    details: %{}
  ]

  @doc """
  Creates an error from an S3 HTTP response.

  ## Examples

      OmS3.Error.from_response(404, %{"Code" => "NoSuchKey", "Message" => "Not found"})
      #=> %OmS3.Error{type: :not_found, ...}
  """
  @spec from_response(pos_integer(), map() | binary()) :: t()
  def from_response(status, body) when is_map(body) do
    code = body["Code"] || body["code"]
    message = body["Message"] || body["message"] || "S3 error"
    request_id = body["RequestId"] || body["x-amz-request-id"]
    resource = body["Resource"] || body["Key"] || body["BucketName"]

    %__MODULE__{
      type: classify_error(status, code),
      code: code,
      message: message,
      status: status,
      request_id: request_id,
      resource: resource,
      details: body
    }
  end

  def from_response(status, body) when is_binary(body) do
    %__MODULE__{
      type: classify_error(status, nil),
      code: nil,
      message: body,
      status: status,
      details: %{raw_body: body}
    }
  end

  @doc """
  Creates an error from a connection/network failure.

  ## Examples

      OmS3.Error.from_exception(%Mint.TransportError{reason: :timeout})
      #=> %OmS3.Error{type: :connection_error, ...}
  """
  @spec from_exception(Exception.t() | term()) :: t()
  def from_exception(%{__exception__: true} = exception) do
    {type, message} = classify_exception(exception)

    %__MODULE__{
      type: type,
      code: nil,
      message: message,
      details: %{exception: exception.__struct__, reason: Exception.message(exception)}
    }
  end

  def from_exception(reason) do
    %__MODULE__{
      type: :connection_error,
      code: nil,
      message: inspect(reason),
      details: %{reason: reason}
    }
  end

  @doc """
  Creates an error from the Client's raw error tuple.

  ## Examples

      OmS3.Error.from_raw({:s3_error, 404, body})
      #=> %OmS3.Error{type: :not_found, ...}
  """
  @spec from_raw(term()) :: t()
  def from_raw({:s3_error, status, body}) do
    from_response(status, body)
  end

  def from_raw(:not_found) do
    %__MODULE__{
      type: :not_found,
      code: "NotFound",
      message: "Object not found",
      status: 404
    }
  end

  def from_raw({:presign_error, reason}) do
    %__MODULE__{
      type: :invalid_request,
      code: "PresignError",
      message: "Failed to generate presigned URL",
      details: %{reason: reason}
    }
  end

  def from_raw({:parse_error, reason}) do
    %__MODULE__{
      type: :invalid_request,
      code: "ParseError",
      message: "Failed to parse S3 response",
      details: %{reason: reason}
    }
  end

  def from_raw(reason) do
    from_exception(reason)
  end

  # ============================================
  # Private: Error Classification
  # ============================================

  defp classify_error(status, code) do
    case {status, code} do
      # Access errors
      {403, _} -> :access_denied
      {_, "AccessDenied"} -> :access_denied
      {_, "InvalidAccessKeyId"} -> :access_denied
      {_, "SignatureDoesNotMatch"} -> :access_denied

      # Not found errors
      {404, _} -> :not_found
      {_, "NoSuchKey"} -> :not_found
      {_, "NoSuchBucket"} -> :not_found
      {_, "NotFound"} -> :not_found

      # Conflict errors
      {409, _} -> :conflict
      {_, "BucketAlreadyExists"} -> :conflict
      {_, "BucketAlreadyOwnedByYou"} -> :conflict
      {_, "OperationAborted"} -> :conflict

      # Precondition errors
      {412, _} -> :precondition_failed
      {_, "PreconditionFailed"} -> :precondition_failed

      # Timeout errors
      {408, _} -> :request_timeout
      {_, "RequestTimeout"} -> :request_timeout

      # Throttling / rate limiting
      {503, "SlowDown"} -> :slow_down
      {_, "SlowDown"} -> :slow_down
      {_, "ServiceUnavailable"} -> :service_unavailable
      {503, _} -> :service_unavailable

      # Internal errors
      {500, _} -> :internal_error
      {_, "InternalError"} -> :internal_error

      # Invalid request
      {400, _} -> :invalid_request
      {_, "InvalidRequest"} -> :invalid_request
      {_, "MalformedXML"} -> :invalid_request
      {_, "InvalidArgument"} -> :invalid_request

      # Default
      _ -> :unknown
    end
  end

  defp classify_exception(exception) do
    cond do
      # Timeout exceptions
      match?(%{reason: :timeout}, exception) ->
        {:request_timeout, "Connection timed out"}

      match?(%{reason: :connect_timeout}, exception) ->
        {:request_timeout, "Connection timeout"}

      # Connection refused
      match?(%{reason: :econnrefused}, exception) ->
        {:connection_error, "Connection refused"}

      # DNS errors
      match?(%{reason: :nxdomain}, exception) ->
        {:connection_error, "DNS lookup failed"}

      # SSL errors
      match?(%{reason: {:tls_alert, _}}, exception) ->
        {:connection_error, "SSL/TLS error"}

      # Generic connection error
      true ->
        {:connection_error, Exception.message(exception)}
    end
  end
end

# ============================================
# Protocol Implementations
# ============================================

defimpl FnTypes.Protocols.Normalizable, for: OmS3.Error do
  alias FnTypes.Error

  def normalize(%OmS3.Error{} = error, opts) do
    Error.new(
      map_to_fn_type(error.type),
      map_to_code(error.type, error.code),
      message: error.message,
      details: build_details(error),
      context: Keyword.get(opts, :context, %{}),
      source: error,
      recoverable: recoverable?(error.type)
    )
  end

  defp map_to_fn_type(type) do
    case type do
      :access_denied -> :forbidden
      :not_found -> :not_found
      :conflict -> :conflict
      :precondition_failed -> :conflict
      :request_timeout -> :timeout
      :service_unavailable -> :external
      :internal_error -> :external
      :slow_down -> :rate_limited
      :invalid_request -> :validation
      :connection_error -> :network
      :unknown -> :external
    end
  end

  defp map_to_code(type, nil), do: type
  defp map_to_code(_type, code), do: String.to_atom(Macro.underscore(code))

  defp build_details(error) do
    %{
      s3_code: error.code,
      s3_status: error.status,
      request_id: error.request_id,
      resource: error.resource
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp recoverable?(type) do
    type in [:request_timeout, :service_unavailable, :slow_down, :connection_error]
  end
end

defimpl FnTypes.Protocols.Recoverable, for: OmS3.Error do
  def recoverable?(%OmS3.Error{type: type}) do
    type in [:request_timeout, :service_unavailable, :slow_down, :connection_error, :internal_error]
  end

  def strategy(%OmS3.Error{type: type}) do
    case type do
      :slow_down -> :retry_with_backoff
      :service_unavailable -> :retry_with_backoff
      :internal_error -> :retry_with_backoff
      :request_timeout -> :retry
      :connection_error -> :retry
      _ -> :fail_fast
    end
  end

  def retry_delay(%OmS3.Error{type: type}, attempt) do
    base_delay =
      case type do
        :slow_down -> 1000
        :service_unavailable -> 500
        :internal_error -> 500
        _ -> 100
      end

    # Exponential backoff with jitter
    delay = base_delay * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(delay * 0.1))
    round(delay + jitter)
  end

  def max_attempts(%OmS3.Error{type: type}) do
    case type do
      :slow_down -> 5
      :service_unavailable -> 5
      :internal_error -> 3
      :request_timeout -> 3
      :connection_error -> 3
      _ -> 1
    end
  end

  def trips_circuit?(%OmS3.Error{type: type}) do
    type in [:service_unavailable, :internal_error]
  end

  def severity(%OmS3.Error{type: type}) do
    case type do
      :slow_down -> :transient
      :request_timeout -> :transient
      :connection_error -> :transient
      :service_unavailable -> :degraded
      :internal_error -> :degraded
      :access_denied -> :permanent
      :not_found -> :permanent
      :invalid_request -> :permanent
      _ -> :critical
    end
  end

  def fallback(%OmS3.Error{}) do
    nil
  end
end
