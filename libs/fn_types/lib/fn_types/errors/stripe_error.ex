defmodule FnTypes.Errors.StripeError do
  @moduledoc """
  Wrapper struct for Stripe API error responses.

  Provides structured error handling for Stripe API responses with protocol
  implementations for `Normalizable` and `Recoverable`.

  ## Error Types

  Stripe returns specific error types that indicate the nature of the failure:

  - `api_error` - API errors (server-side issues)
  - `card_error` - Card errors (declined, expired, etc.)
  - `idempotency_error` - Conflicting idempotency key
  - `invalid_request_error` - Invalid parameters
  - `authentication_error` - Invalid API key
  - `rate_limit_error` - Too many requests

  ## Error Codes

  Common error codes include:
  - `card_declined` - Card was declined
  - `expired_card` - Card has expired
  - `incorrect_cvc` - CVC verification failed
  - `processing_error` - Card processing error
  - `insufficient_funds` - Insufficient funds
  - `resource_missing` - Resource not found

  ## Decline Codes

  For card errors, Stripe provides specific decline codes:
  - `generic_decline` - Generic decline
  - `insufficient_funds` - Insufficient funds
  - `lost_card` - Lost card
  - `stolen_card` - Stolen card
  - `fraudulent` - Fraudulent transaction

  ## Usage

      # Create from Stripe response
      error = StripeError.from_response(%{
        status: 402,
        body: %{
          "error" => %{
            "type" => "card_error",
            "code" => "card_declined",
            "message" => "Your card was declined.",
            "decline_code" => "insufficient_funds"
          }
        }
      })

      # Normalize to standard Error
      FnTypes.Protocols.Normalizable.normalize(error)

      # Check if recoverable
      FnTypes.Protocols.Recoverable.recoverable?(error)

  ## Integration with Stripe Client

      case Stripe.create_charge(params, config) do
        {:ok, charge} -> {:ok, charge}
        {:error, %StripeError{type: "card_error"} = error} ->
          # Handle card decline
          {:error, Normalizable.normalize(error)}
        {:error, %StripeError{type: "rate_limit_error"} = error} ->
          # Will be retried automatically
          {:error, error}
      end
  """

  @type t :: %__MODULE__{
          status: pos_integer(),
          type: String.t() | nil,
          code: String.t() | nil,
          message: String.t() | nil,
          param: String.t() | nil,
          decline_code: String.t() | nil,
          request_id: String.t() | nil,
          doc_url: String.t() | nil
        }

  defstruct [:status, :type, :code, :message, :param, :decline_code, :request_id, :doc_url]

  # Error types that indicate transient failures (retry may succeed)
  @transient_types ["api_error", "rate_limit_error"]

  # Error codes that indicate transient failures
  @transient_codes ["processing_error", "lock_timeout"]

  # Card error decline codes that might succeed on retry
  @retryable_decline_codes ["processing_error", "try_again_later"]

  @doc """
  Creates a new Stripe error.

  ## Options

  - `:type` - Stripe error type (api_error, card_error, etc.)
  - `:code` - Specific error code
  - `:message` - Human-readable error message
  - `:param` - Parameter that caused the error
  - `:decline_code` - For card errors, the specific decline reason
  - `:request_id` - Stripe request ID for debugging
  - `:doc_url` - Link to Stripe documentation

  ## Examples

      StripeError.new(402, type: "card_error", code: "card_declined")
      StripeError.new(429, type: "rate_limit_error")
  """
  @spec new(pos_integer(), keyword()) :: t()
  def new(status, opts \\ []) when is_integer(status) do
    %__MODULE__{
      status: status,
      type: Keyword.get(opts, :type),
      code: Keyword.get(opts, :code),
      message: Keyword.get(opts, :message),
      param: Keyword.get(opts, :param),
      decline_code: Keyword.get(opts, :decline_code),
      request_id: Keyword.get(opts, :request_id),
      doc_url: Keyword.get(opts, :doc_url)
    }
  end

  @doc """
  Creates a Stripe error from an API response.

  Extracts error details from the Stripe error response format.
  """
  @spec from_response(map()) :: t()
  def from_response(%{status: status, body: %{"error" => error}} = response) do
    %__MODULE__{
      status: status,
      type: error["type"],
      code: error["code"],
      message: error["message"],
      param: error["param"],
      decline_code: error["decline_code"],
      request_id: get_request_id(response),
      doc_url: error["doc_url"]
    }
  end

  def from_response(%{status: status, body: body} = response) do
    %__MODULE__{
      status: status,
      message: extract_message(body),
      request_id: get_request_id(response)
    }
  end

  def from_response(%{status: status}) do
    %__MODULE__{status: status}
  end

  @doc """
  Creates a Stripe error from a normalized error map.

  Used when converting from the legacy map format.
  """
  @spec from_map(map()) :: t()
  def from_map(error_map) when is_map(error_map) do
    %__MODULE__{
      status: Map.get(error_map, :status),
      type: Map.get(error_map, :type),
      code: Map.get(error_map, :code),
      message: Map.get(error_map, :message),
      param: Map.get(error_map, :param),
      decline_code: Map.get(error_map, :decline_code),
      request_id: Map.get(error_map, :request_id)
    }
  end

  @doc """
  Checks if the error indicates a transient failure.

  Transient failures may succeed on retry.
  """
  @spec transient?(t()) :: boolean()
  def transient?(%__MODULE__{type: type}) when type in @transient_types, do: true
  def transient?(%__MODULE__{code: code}) when code in @transient_codes, do: true
  def transient?(%__MODULE__{status: status}) when status >= 500, do: true
  def transient?(%__MODULE__{status: 429}), do: true
  def transient?(_), do: false

  @doc """
  Checks if the error is a card error.
  """
  @spec card_error?(t()) :: boolean()
  def card_error?(%__MODULE__{type: "card_error"}), do: true
  def card_error?(_), do: false

  @doc """
  Checks if the error is a rate limit error.
  """
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{type: "rate_limit_error"}), do: true
  def rate_limited?(%__MODULE__{status: 429}), do: true
  def rate_limited?(_), do: false

  @doc """
  Checks if the card decline might succeed on retry.

  Some decline codes indicate temporary issues that may succeed on retry.
  """
  @spec retryable_decline?(t()) :: boolean()
  def retryable_decline?(%__MODULE__{type: "card_error", decline_code: code})
      when code in @retryable_decline_codes,
      do: true

  def retryable_decline?(_), do: false

  # Private helpers

  defp get_request_id(%{api_request_id: id}) when is_binary(id), do: id
  defp get_request_id(%{headers: headers}) when is_map(headers), do: headers["x-request-id"]
  defp get_request_id(_), do: nil

  defp extract_message(body) when is_binary(body), do: body
  defp extract_message(%{"message" => msg}), do: msg
  defp extract_message(%{"error" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end

defimpl FnTypes.Protocols.Normalizable, for: FnTypes.Errors.StripeError do
  @moduledoc """
  Normalizable implementation for Stripe errors.

  Maps Stripe error types and codes to appropriate FnTypes.Error types.
  """

  alias FnTypes.Error
  alias FnTypes.Errors.StripeError

  def normalize(%StripeError{} = stripe_error, opts) do
    {type, code, message, recoverable} = map_error(stripe_error)

    Error.new(type, code,
      message: Keyword.get(opts, :message, stripe_error.message || message),
      source: :stripe,
      recoverable: recoverable,
      details: build_details(stripe_error),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp build_details(%StripeError{} = error) do
    %{
      stripe_type: error.type,
      stripe_code: error.code,
      status_code: error.status
    }
    |> maybe_add(:param, error.param)
    |> maybe_add(:decline_code, error.decline_code)
    |> maybe_add(:request_id, error.request_id)
    |> maybe_add(:doc_url, error.doc_url)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  # Card errors
  defp map_error(%StripeError{type: "card_error", code: "card_declined", decline_code: dc}) do
    {type, message} = map_decline_code(dc)
    {type, :card_declined, message, false}
  end

  defp map_error(%StripeError{type: "card_error", code: "expired_card"}) do
    {:validation, :expired_card, "Card has expired", false}
  end

  defp map_error(%StripeError{type: "card_error", code: "incorrect_cvc"}) do
    {:validation, :incorrect_cvc, "CVC verification failed", false}
  end

  defp map_error(%StripeError{type: "card_error", code: "incorrect_number"}) do
    {:validation, :incorrect_number, "Invalid card number", false}
  end

  defp map_error(%StripeError{type: "card_error", code: "processing_error"}) do
    {:external, :card_processing_error, "Card processing error", true}
  end

  defp map_error(%StripeError{type: "card_error"}) do
    {:payment, :card_error, "Card error", false}
  end

  # Rate limit errors
  defp map_error(%StripeError{type: "rate_limit_error"}) do
    {:rate_limited, :stripe_rate_limit, "Stripe rate limit exceeded", true}
  end

  defp map_error(%StripeError{status: 429}) do
    {:rate_limited, :stripe_rate_limit, "Too many requests to Stripe", true}
  end

  # Authentication errors
  defp map_error(%StripeError{type: "authentication_error"}) do
    {:unauthorized, :stripe_auth_error, "Invalid Stripe API key", false}
  end

  defp map_error(%StripeError{status: 401}) do
    {:unauthorized, :stripe_unauthorized, "Stripe authentication failed", false}
  end

  # Invalid request errors
  defp map_error(%StripeError{type: "invalid_request_error", code: "resource_missing"}) do
    {:not_found, :stripe_resource_not_found, "Stripe resource not found", false}
  end

  defp map_error(%StripeError{type: "invalid_request_error"}) do
    {:validation, :stripe_invalid_request, "Invalid Stripe request", false}
  end

  # Idempotency errors
  defp map_error(%StripeError{type: "idempotency_error"}) do
    {:conflict, :idempotency_error, "Conflicting idempotency key", false}
  end

  # API errors (server-side)
  defp map_error(%StripeError{type: "api_error"}) do
    {:external, :stripe_api_error, "Stripe API error", true}
  end

  # HTTP status-based fallbacks
  defp map_error(%StripeError{status: 400}) do
    {:bad_request, :stripe_bad_request, "Bad request to Stripe", false}
  end

  defp map_error(%StripeError{status: 402}) do
    {:payment, :payment_required, "Payment required", false}
  end

  defp map_error(%StripeError{status: 403}) do
    {:forbidden, :stripe_forbidden, "Stripe access forbidden", false}
  end

  defp map_error(%StripeError{status: 404}) do
    {:not_found, :stripe_not_found, "Stripe resource not found", false}
  end

  defp map_error(%StripeError{status: status}) when status >= 500 do
    {:external, :stripe_server_error, "Stripe server error", true}
  end

  # Fallback
  defp map_error(%StripeError{}) do
    {:unknown, :stripe_unknown_error, "Unknown Stripe error", false}
  end

  # Decline code mappings
  defp map_decline_code("insufficient_funds") do
    {:payment, "Insufficient funds"}
  end

  defp map_decline_code("lost_card") do
    {:forbidden, "Card reported lost"}
  end

  defp map_decline_code("stolen_card") do
    {:forbidden, "Card reported stolen"}
  end

  defp map_decline_code("fraudulent") do
    {:forbidden, "Transaction flagged as fraudulent"}
  end

  defp map_decline_code("do_not_honor") do
    {:payment, "Card issuer declined transaction"}
  end

  defp map_decline_code("try_again_later") do
    {:external, "Temporary issue, try again later"}
  end

  defp map_decline_code(_) do
    {:payment, "Card was declined"}
  end
end

defimpl FnTypes.Protocols.Recoverable, for: FnTypes.Errors.StripeError do
  @moduledoc """
  Recoverable implementation for Stripe errors.

  Defines retry strategies based on error type and status code.
  """

  alias FnTypes.Errors.StripeError

  @max_attempts_rate_limit 5
  @max_attempts_server_error 3
  @max_attempts_processing 2

  def recoverable?(%StripeError{} = error), do: StripeError.transient?(error)

  def strategy(%StripeError{type: "rate_limit_error"}), do: :wait_until
  def strategy(%StripeError{status: 429}), do: :wait_until
  def strategy(%StripeError{type: "api_error"}), do: :retry_with_backoff
  def strategy(%StripeError{status: status}) when status >= 500, do: :retry_with_backoff
  def strategy(%StripeError{code: "processing_error"}), do: :retry

  def strategy(%StripeError{type: "card_error", decline_code: dc})
      when dc in ["processing_error", "try_again_later"],
      do: :retry

  def strategy(_), do: :fail_fast

  def retry_delay(%StripeError{type: "rate_limit_error"}, _attempt) do
    # Stripe typically suggests waiting 1 second for rate limits
    1000
  end

  def retry_delay(%StripeError{status: 429}, _attempt) do
    1000
  end

  def retry_delay(%StripeError{type: "api_error"}, attempt) do
    # Exponential backoff for API errors
    base_delay = 1000 * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(base_delay * 0.1))
    min(round(base_delay + jitter), 30_000)
  end

  def retry_delay(%StripeError{status: status}, attempt) when status >= 500 do
    # Exponential backoff for server errors
    base_delay = 2000 * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(round(base_delay * 0.2))
    min(round(base_delay + jitter), 60_000)
  end

  def retry_delay(%StripeError{}, attempt) do
    # Default fixed delay with linear increase
    min(1000 * attempt, 5000)
  end

  def max_attempts(%StripeError{type: "rate_limit_error"}), do: @max_attempts_rate_limit
  def max_attempts(%StripeError{status: 429}), do: @max_attempts_rate_limit
  def max_attempts(%StripeError{type: "api_error"}), do: @max_attempts_server_error
  def max_attempts(%StripeError{status: status}) when status >= 500, do: @max_attempts_server_error
  def max_attempts(%StripeError{code: "processing_error"}), do: @max_attempts_processing
  def max_attempts(_), do: 1

  def trips_circuit?(%StripeError{type: "api_error"}), do: true
  def trips_circuit?(%StripeError{status: status}) when status in [502, 503, 504], do: true
  def trips_circuit?(_), do: false

  def severity(%StripeError{type: "rate_limit_error"}), do: :degraded
  def severity(%StripeError{status: 429}), do: :degraded
  def severity(%StripeError{type: "api_error"}), do: :critical
  def severity(%StripeError{status: status}) when status >= 500, do: :critical
  def severity(%StripeError{type: "card_error"}), do: :permanent
  def severity(%StripeError{type: "invalid_request_error"}), do: :permanent
  def severity(%StripeError{type: "authentication_error"}), do: :permanent
  def severity(_), do: :permanent

  def fallback(_), do: nil
end
