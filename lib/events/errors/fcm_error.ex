defmodule Events.Errors.FCMError do
  @moduledoc """
  Wrapper struct for Firebase Cloud Messaging (FCM) error responses.

  Provides structured error handling for FCM API responses with protocol
  implementations for `Normalizable` and `Recoverable`.

  ## Error Codes

  FCM returns specific error codes that indicate the nature of the failure:

  - `UNSPECIFIED_ERROR` - Unknown error
  - `INVALID_ARGUMENT` - Invalid request parameters
  - `UNREGISTERED` - Token is no longer valid (device unregistered)
  - `SENDER_ID_MISMATCH` - Token doesn't match sender
  - `QUOTA_EXCEEDED` - Rate limit exceeded
  - `UNAVAILABLE` - FCM service temporarily unavailable
  - `INTERNAL` - FCM internal error
  - `THIRD_PARTY_AUTH_ERROR` - APNs/Web Push auth error

  ## Usage

      # Create from FCM response
      error = FCMError.new("UNREGISTERED",
        message: "Token not registered",
        status: "NOT_FOUND",
        device_token: "abc123..."
      )

      # Normalize to standard Error
      FnTypes.Protocols.Normalizable.normalize(error)

      # Check if recoverable
      FnTypes.Protocols.Recoverable.recoverable?(error)  #=> false (permanent)

      FnTypes.Protocols.Recoverable.recoverable?(
        FCMError.new("QUOTA_EXCEEDED")
      )  #=> true (transient)

  ## Integration with FCM Client

      case FCM.push(config, message_opts) do
        {:ok, response} -> {:ok, response}
        {:error, %FCMError{code: "UNREGISTERED"} = error} ->
          # Remove invalid token from database
          Tokens.invalidate(error.device_token)
          {:error, Normalizable.normalize(error)}
      end
  """

  @type t :: %__MODULE__{
          code: String.t() | nil,
          status: String.t() | nil,
          message: String.t() | nil,
          details: list() | nil,
          device_token: String.t() | nil,
          http_status: pos_integer() | nil
        }

  defstruct [:code, :status, :message, :details, :device_token, :http_status]

  # Error codes that indicate permanent failures (token is invalid)
  @permanent_errors ["UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"]

  # Error codes that indicate transient failures (retry may succeed)
  @transient_errors ["QUOTA_EXCEEDED", "UNAVAILABLE", "INTERNAL"]

  @doc """
  Creates a new FCM error.

  ## Options

  - `:message` - Error message from FCM
  - `:status` - HTTP status string (e.g., "NOT_FOUND")
  - `:details` - Full error details from FCM response
  - `:device_token` - The device token that caused the error
  - `:http_status` - HTTP status code (e.g., 400, 500)

  ## Examples

      FCMError.new("UNREGISTERED", message: "Token not registered")
      FCMError.new("QUOTA_EXCEEDED", http_status: 429)
  """
  @spec new(String.t() | nil, keyword()) :: t()
  def new(code, opts \\ []) do
    %__MODULE__{
      code: code,
      status: Keyword.get(opts, :status),
      message: Keyword.get(opts, :message),
      details: Keyword.get(opts, :details),
      device_token: Keyword.get(opts, :device_token),
      http_status: Keyword.get(opts, :http_status)
    }
  end

  @doc """
  Creates an FCM error from a normalized error map.

  Used internally by the FCM client to wrap error responses.
  """
  @spec from_map(map()) :: t()
  def from_map(error_map) when is_map(error_map) do
    %__MODULE__{
      code: Map.get(error_map, :code),
      status: Map.get(error_map, :status),
      message: Map.get(error_map, :message),
      details: Map.get(error_map, :details)
    }
  end

  @doc """
  Checks if the error indicates a permanent failure.

  Permanent failures mean the token should be removed from the database.
  """
  @spec permanent?(t()) :: boolean()
  def permanent?(%__MODULE__{code: code}) when code in @permanent_errors, do: true
  def permanent?(_), do: false

  @doc """
  Checks if the error indicates a transient failure.

  Transient failures may succeed on retry.
  """
  @spec transient?(t()) :: boolean()
  def transient?(%__MODULE__{code: code}) when code in @transient_errors, do: true
  def transient?(_), do: false
end

defimpl FnTypes.Protocols.Normalizable, for: Events.Errors.FCMError do
  @moduledoc """
  Normalizable implementation for FCM errors.

  Maps FCM error codes to appropriate FnTypes.Error types.
  """

  alias FnTypes.Error
  alias Events.Errors.FCMError

  def normalize(%FCMError{} = fcm_error, opts) do
    {type, code, message, recoverable} = map_error_code(fcm_error.code)

    Error.new(type, code,
      message: Keyword.get(opts, :message, fcm_error.message || message),
      source: :fcm,
      recoverable: recoverable,
      details: build_details(fcm_error),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp build_details(%FCMError{} = error) do
    %{
      fcm_code: error.code,
      fcm_status: error.status,
      http_status: error.http_status
    }
    |> maybe_add(:device_token, error.device_token)
    |> maybe_add(:details, error.details)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  # Permanent failures - token is invalid
  defp map_error_code("UNREGISTERED"),
    do: {:not_found, :token_unregistered, "Device token is no longer valid", false}

  defp map_error_code("INVALID_ARGUMENT"),
    do: {:validation, :invalid_argument, "Invalid request parameter", false}

  defp map_error_code("SENDER_ID_MISMATCH"),
    do: {:forbidden, :sender_mismatch, "Token doesn't match sender ID", false}

  # Transient failures - may succeed on retry
  defp map_error_code("QUOTA_EXCEEDED"),
    do: {:rate_limited, :quota_exceeded, "FCM rate limit exceeded", true}

  defp map_error_code("UNAVAILABLE"),
    do: {:external, :fcm_unavailable, "FCM service temporarily unavailable", true}

  defp map_error_code("INTERNAL"),
    do: {:external, :fcm_internal, "FCM internal error", true}

  # Auth errors
  defp map_error_code("THIRD_PARTY_AUTH_ERROR"),
    do: {:unauthorized, :third_party_auth, "APNs/Web Push authentication failed", false}

  # Fallback
  defp map_error_code(nil),
    do: {:unknown, :unknown_fcm_error, "Unknown FCM error", false}

  defp map_error_code(_code),
    do: {:unknown, :unspecified_error, "Unspecified FCM error", false}
end

defimpl FnTypes.Protocols.Recoverable, for: Events.Errors.FCMError do
  @moduledoc """
  Recoverable implementation for FCM errors.

  Defines retry strategies based on error type.
  """

  alias Events.Errors.FCMError

  @transient_codes ["QUOTA_EXCEEDED", "UNAVAILABLE", "INTERNAL"]
  @max_attempts_rate_limit 5
  @max_attempts_server_error 3

  def recoverable?(%FCMError{code: code}) when code in @transient_codes, do: true
  def recoverable?(_), do: false

  def strategy(%FCMError{code: "QUOTA_EXCEEDED"}), do: :retry_with_backoff
  def strategy(%FCMError{code: "UNAVAILABLE"}), do: :retry_with_backoff
  def strategy(%FCMError{code: "INTERNAL"}), do: :retry
  def strategy(_), do: :fail_fast

  def retry_delay(%FCMError{code: "QUOTA_EXCEEDED"}, attempt) do
    # Exponential backoff with jitter for rate limits
    base_delay = 1000 * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(base_delay * 0.1))
    min(round(base_delay + jitter), 60_000)
  end

  def retry_delay(%FCMError{code: "UNAVAILABLE"}, attempt) do
    # Longer delays for service unavailability
    base_delay = 2000 * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(base_delay * 0.2))
    min(round(base_delay + jitter), 120_000)
  end

  def retry_delay(%FCMError{}, attempt) do
    # Default fixed delay with backoff
    min(1000 * attempt, 10_000)
  end

  def max_attempts(%FCMError{code: "QUOTA_EXCEEDED"}), do: @max_attempts_rate_limit

  def max_attempts(%FCMError{code: code}) when code in ["UNAVAILABLE", "INTERNAL"] do
    @max_attempts_server_error
  end

  def max_attempts(_), do: 1

  def trips_circuit?(%FCMError{code: "UNAVAILABLE"}), do: true
  def trips_circuit?(%FCMError{code: "INTERNAL"}), do: true
  def trips_circuit?(_), do: false

  def severity(%FCMError{code: "QUOTA_EXCEEDED"}), do: :degraded
  def severity(%FCMError{code: "UNAVAILABLE"}), do: :critical
  def severity(%FCMError{code: "INTERNAL"}), do: :critical

  def severity(%FCMError{code: code}) when code in ["UNREGISTERED", "SENDER_ID_MISMATCH"] do
    :permanent
  end

  def severity(_), do: :permanent

  def fallback(_), do: nil
end
