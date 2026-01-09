defmodule OmGoogle.Error do
  @moduledoc """
  Google API error with protocol implementations for normalization and recovery.

  Provides structured error handling for Google API operations with:
  - Error categorization (auth errors, quota exceeded, etc.)
  - Recovery strategies for transient failures
  - Integration with `FnTypes.Error` normalization

  ## Error Types

  - `:invalid_credentials` - Service account credentials invalid
  - `:token_expired` - Access token expired
  - `:permission_denied` - Insufficient API permissions
  - `:not_found` - Resource not found
  - `:quota_exceeded` - API quota limit reached
  - `:rate_limited` - Too many requests
  - `:invalid_request` - Malformed request
  - `:service_unavailable` - Google service temporarily unavailable
  - `:internal_error` - Google internal error
  - `:connection_error` - Network/connection failure
  - `:unknown` - Unrecognized error

  ## Examples

      # Create from API response
      error = OmGoogle.Error.from_response(403, %{
        "error" => %{
          "code" => 403,
          "message" => "Permission denied",
          "status" => "PERMISSION_DENIED"
        }
      })
      error.type
      #=> :permission_denied

      # Check recoverability
      FnTypes.Protocols.Recoverable.recoverable?(error)
      #=> false

      # Normalize to FnTypes.Error
      FnTypes.Error.normalize(error)
      #=> %FnTypes.Error{type: :forbidden, ...}
  """

  @type error_type ::
          :invalid_credentials
          | :token_expired
          | :permission_denied
          | :not_found
          | :quota_exceeded
          | :rate_limited
          | :invalid_request
          | :service_unavailable
          | :internal_error
          | :connection_error
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          code: String.t() | nil,
          message: String.t(),
          status: pos_integer() | nil,
          grpc_status: String.t() | nil,
          details: map()
        }

  defstruct [
    :type,
    :code,
    :message,
    :status,
    :grpc_status,
    details: %{}
  ]

  @doc """
  Creates an error from a Google API HTTP response.

  Handles both standard Google API error format and OAuth2 token errors.

  ## Examples

      # Standard API error
      OmGoogle.Error.from_response(403, %{
        "error" => %{
          "code" => 403,
          "message" => "Permission denied",
          "status" => "PERMISSION_DENIED"
        }
      })

      # OAuth2 token error
      OmGoogle.Error.from_response(400, %{
        "error" => "invalid_grant",
        "error_description" => "Token has been expired or revoked"
      })
  """
  @spec from_response(pos_integer(), map() | binary()) :: t()
  def from_response(status, %{"error" => error} = body) when is_map(error) do
    # Standard Google API error format
    code = to_string(error["code"] || status)
    message = error["message"] || "Google API error"
    grpc_status = error["status"]

    %__MODULE__{
      type: classify_error(status, grpc_status, code),
      code: code,
      message: message,
      status: status,
      grpc_status: grpc_status,
      details: body
    }
  end

  def from_response(status, %{"error" => error_code, "error_description" => desc} = body)
      when is_binary(error_code) do
    # OAuth2 error format
    %__MODULE__{
      type: classify_oauth_error(error_code),
      code: error_code,
      message: desc,
      status: status,
      details: body
    }
  end

  def from_response(status, %{"error" => error_code} = body) when is_binary(error_code) do
    # Simple OAuth2 error
    %__MODULE__{
      type: classify_oauth_error(error_code),
      code: error_code,
      message: error_code,
      status: status,
      details: body
    }
  end

  def from_response(status, body) when is_map(body) do
    %__MODULE__{
      type: classify_by_status(status),
      code: to_string(status),
      message: body["message"] || "Google API error",
      status: status,
      details: body
    }
  end

  def from_response(status, body) when is_binary(body) do
    %__MODULE__{
      type: classify_by_status(status),
      code: to_string(status),
      message: body,
      status: status,
      details: %{raw_body: body}
    }
  end

  @doc """
  Creates an error from ServiceAccount token errors.

  ## Examples

      OmGoogle.Error.from_token_error({:token_error, 400, body})
      #=> %OmGoogle.Error{type: :invalid_credentials, ...}
  """
  @spec from_token_error(term()) :: t()
  def from_token_error({:token_error, status, body}) do
    from_response(status, body)
  end

  def from_token_error({:request_error, reason}) do
    from_exception(reason)
  end

  def from_token_error({:env_not_set, var}) do
    %__MODULE__{
      type: :invalid_credentials,
      code: "env_not_set",
      message: "Environment variable #{var} not set",
      details: %{env_var: var}
    }
  end

  def from_token_error({:missing_field, field}) do
    %__MODULE__{
      type: :invalid_credentials,
      code: "missing_field",
      message: "Required field '#{field}' missing from credentials",
      details: %{field: field}
    }
  end

  def from_token_error({:file_read_error, reason}) do
    %__MODULE__{
      type: :invalid_credentials,
      code: "file_read_error",
      message: "Failed to read credentials file: #{inspect(reason)}",
      details: %{reason: reason}
    }
  end

  def from_token_error({:json_decode_error, reason}) do
    %__MODULE__{
      type: :invalid_credentials,
      code: "json_decode_error",
      message: "Failed to parse credentials JSON",
      details: %{reason: reason}
    }
  end

  def from_token_error(reason) do
    from_exception(reason)
  end

  @doc """
  Creates an error from a connection/network failure.

  ## Examples

      OmGoogle.Error.from_exception(%Mint.TransportError{reason: :timeout})
      #=> %OmGoogle.Error{type: :connection_error, ...}
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

  # ============================================
  # Private: Error Classification
  # ============================================

  defp classify_error(status, grpc_status, _code) do
    case {status, grpc_status} do
      # Authentication errors
      {401, _} -> :token_expired
      {_, "UNAUTHENTICATED"} -> :token_expired

      # Permission errors
      {403, _} -> :permission_denied
      {_, "PERMISSION_DENIED"} -> :permission_denied

      # Not found
      {404, _} -> :not_found
      {_, "NOT_FOUND"} -> :not_found

      # Quota / Rate limiting
      {429, _} -> :rate_limited
      {_, "RESOURCE_EXHAUSTED"} -> :quota_exceeded

      # Invalid request
      {400, _} -> :invalid_request
      {_, "INVALID_ARGUMENT"} -> :invalid_request
      {_, "FAILED_PRECONDITION"} -> :invalid_request

      # Service errors
      {503, _} -> :service_unavailable
      {_, "UNAVAILABLE"} -> :service_unavailable

      {500, _} -> :internal_error
      {_, "INTERNAL"} -> :internal_error

      # Timeout
      {_, "DEADLINE_EXCEEDED"} -> :connection_error

      _ -> :unknown
    end
  end

  defp classify_oauth_error(error_code) do
    case error_code do
      "invalid_grant" -> :token_expired
      "invalid_client" -> :invalid_credentials
      "invalid_request" -> :invalid_request
      "unauthorized_client" -> :permission_denied
      "access_denied" -> :permission_denied
      "unsupported_grant_type" -> :invalid_request
      _ -> :unknown
    end
  end

  defp classify_by_status(status) do
    case status do
      401 -> :token_expired
      403 -> :permission_denied
      404 -> :not_found
      429 -> :rate_limited
      400 -> :invalid_request
      500 -> :internal_error
      503 -> :service_unavailable
      _ -> :unknown
    end
  end

  defp classify_exception(exception) do
    cond do
      match?(%{reason: :timeout}, exception) ->
        {:connection_error, "Connection timed out"}

      match?(%{reason: :connect_timeout}, exception) ->
        {:connection_error, "Connection timeout"}

      match?(%{reason: :econnrefused}, exception) ->
        {:connection_error, "Connection refused"}

      match?(%{reason: :nxdomain}, exception) ->
        {:connection_error, "DNS lookup failed"}

      match?(%{reason: {:tls_alert, _}}, exception) ->
        {:connection_error, "SSL/TLS error"}

      true ->
        {:connection_error, Exception.message(exception)}
    end
  end
end

# ============================================
# Protocol Implementations
# ============================================

defimpl FnTypes.Protocols.Normalizable, for: OmGoogle.Error do
  alias FnTypes.Error

  def normalize(%OmGoogle.Error{} = error, opts) do
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
      :invalid_credentials -> :unauthorized
      :token_expired -> :unauthorized
      :permission_denied -> :forbidden
      :not_found -> :not_found
      :quota_exceeded -> :rate_limited
      :rate_limited -> :rate_limited
      :invalid_request -> :validation
      :service_unavailable -> :external
      :internal_error -> :external
      :connection_error -> :network
      :unknown -> :external
    end
  end

  defp map_to_code(type, nil), do: type

  defp map_to_code(_type, code) when is_binary(code) do
    code
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_atom()
  end

  defp map_to_code(type, _code), do: type

  defp build_details(error) do
    %{
      google_code: error.code,
      google_status: error.status,
      grpc_status: error.grpc_status
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp recoverable?(type) do
    type in [:rate_limited, :quota_exceeded, :service_unavailable, :connection_error]
  end
end

defimpl FnTypes.Protocols.Recoverable, for: OmGoogle.Error do
  def recoverable?(%OmGoogle.Error{type: type}) do
    type in [
      :rate_limited,
      :quota_exceeded,
      :service_unavailable,
      :internal_error,
      :connection_error
    ]
  end

  def strategy(%OmGoogle.Error{type: type}) do
    case type do
      :rate_limited -> :retry_with_backoff
      :quota_exceeded -> :retry_with_backoff
      :service_unavailable -> :retry_with_backoff
      :internal_error -> :retry_with_backoff
      :connection_error -> :retry
      :token_expired -> :retry  # Usually triggers token refresh
      _ -> :fail_fast
    end
  end

  def retry_delay(%OmGoogle.Error{type: type}, attempt) do
    base_delay =
      case type do
        :rate_limited -> 1000
        :quota_exceeded -> 2000
        :service_unavailable -> 500
        :internal_error -> 500
        _ -> 100
      end

    # Exponential backoff with jitter
    delay = base_delay * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(delay * 0.1))
    round(delay + jitter)
  end

  def max_attempts(%OmGoogle.Error{type: type}) do
    case type do
      :rate_limited -> 5
      :quota_exceeded -> 3
      :service_unavailable -> 5
      :internal_error -> 3
      :connection_error -> 3
      :token_expired -> 2
      _ -> 1
    end
  end

  def trips_circuit?(%OmGoogle.Error{type: type}) do
    type in [:service_unavailable, :internal_error, :quota_exceeded]
  end

  def severity(%OmGoogle.Error{type: type}) do
    case type do
      :rate_limited -> :transient
      :connection_error -> :transient
      :service_unavailable -> :degraded
      :internal_error -> :degraded
      :quota_exceeded -> :degraded
      :token_expired -> :transient
      :invalid_credentials -> :permanent
      :permission_denied -> :permanent
      :not_found -> :permanent
      :invalid_request -> :permanent
      _ -> :critical
    end
  end

  def fallback(%OmGoogle.Error{}) do
    nil
  end
end
