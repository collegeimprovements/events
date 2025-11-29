defmodule Events.APIClient.Webhook do
  @moduledoc """
  Webhook signature verification for various API providers.

  Provides functions to verify incoming webhook payloads from
  third-party services like Stripe, GitHub, Slack, and others.

  ## Usage

      # In a Phoenix controller
      def webhook(conn, _params) do
        payload = conn.assigns.raw_body
        signature = get_req_header(conn, "stripe-signature") |> List.first()

        case Webhook.verify(:stripe, payload, signature, webhook_secret) do
          {:ok, event} ->
            handle_event(event)
            send_resp(conn, 200, "OK")

          {:error, reason} ->
            send_resp(conn, 400, "Invalid signature: \#{reason}")
        end
      end

  ## Supported Providers

  - `:stripe` - Stripe webhook signatures
  - `:github` - GitHub webhook signatures
  - `:slack` - Slack request verification
  - `:twilio` - Twilio request validation
  - `:shopify` - Shopify webhook HMAC verification
  - `:sendgrid` - SendGrid Event Webhook verification

  ## Custom Verification

  For providers not listed, you can use the generic HMAC verification:

      Webhook.verify_hmac(payload, signature, secret,
        algorithm: :sha256,
        encoding: :hex
      )
  """

  @type provider :: :stripe | :github | :slack | :twilio | :shopify | :sendgrid
  @type verification_result :: {:ok, map()} | {:error, atom() | String.t()}

  # Stripe allows 5 minute tolerance by default
  @default_tolerance_seconds 300

  # ============================================
  # Unified API
  # ============================================

  @doc """
  Verifies a webhook signature for the given provider.

  ## Examples

      Webhook.verify(:stripe, payload, signature, secret)
      Webhook.verify(:github, payload, signature, secret)
  """
  @spec verify(provider(), binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify(provider, payload, signature, secret, opts \\ [])

  def verify(:stripe, payload, signature, secret, opts) do
    verify_stripe(payload, signature, secret, opts)
  end

  def verify(:github, payload, signature, secret, opts) do
    verify_github(payload, signature, secret, opts)
  end

  def verify(:slack, payload, signature, secret, opts) do
    verify_slack(payload, signature, secret, opts)
  end

  def verify(:twilio, payload, signature, secret, opts) do
    verify_twilio(payload, signature, secret, opts)
  end

  def verify(:shopify, payload, signature, secret, opts) do
    verify_shopify(payload, signature, secret, opts)
  end

  def verify(:sendgrid, payload, signature, secret, opts) do
    verify_sendgrid(payload, signature, secret, opts)
  end

  # ============================================
  # Stripe
  # ============================================

  @doc """
  Verifies a Stripe webhook signature.

  Stripe uses a timestamp-based signature scheme to prevent replay attacks.
  The signature header contains: `t=timestamp,v1=signature`

  ## Options

  - `:tolerance` - Maximum age of the webhook in seconds (default: 300)

  ## Examples

      signature = "t=1614556800,v1=abc123..."
      Webhook.verify_stripe(payload, signature, "whsec_xxx")
      #=> {:ok, %{"type" => "payment_intent.succeeded", ...}}

  ## Signature Format

  Stripe signs: `timestamp.payload`
  Header format: `t=timestamp,v1=signature[,v1=signature...]`
  """
  @spec verify_stripe(binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify_stripe(payload, signature, secret, opts \\ []) do
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance_seconds)

    with {:ok, timestamp, signatures} <- parse_stripe_signature(signature),
         :ok <- verify_timestamp(timestamp, tolerance),
         :ok <- verify_stripe_signature(payload, timestamp, signatures, secret) do
      decode_payload(payload)
    end
  end

  defp parse_stripe_signature(header) when is_binary(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.reduce(%{timestamp: nil, signatures: []}, fn
        ["t", ts], acc -> %{acc | timestamp: String.to_integer(ts)}
        ["v1", sig], acc -> %{acc | signatures: [sig | acc.signatures]}
        _, acc -> acc
      end)

    case parts do
      %{timestamp: nil} -> {:error, :missing_timestamp}
      %{signatures: []} -> {:error, :missing_signature}
      %{timestamp: ts, signatures: sigs} -> {:ok, ts, sigs}
    end
  end

  defp parse_stripe_signature(_), do: {:error, :invalid_signature_format}

  defp verify_stripe_signature(payload, timestamp, signatures, secret) do
    signed_payload = "#{timestamp}.#{payload}"
    expected = compute_hmac(:sha256, signed_payload, secret, :hex)

    if Enum.any?(signatures, &secure_compare(&1, expected)) do
      :ok
    else
      {:error, :signature_mismatch}
    end
  end

  # ============================================
  # GitHub
  # ============================================

  @doc """
  Verifies a GitHub webhook signature.

  GitHub uses HMAC-SHA256 and sends the signature in the `X-Hub-Signature-256` header.

  ## Examples

      signature = "sha256=abc123..."
      Webhook.verify_github(payload, signature, "your-webhook-secret")
      #=> {:ok, %{"action" => "opened", "pull_request" => ...}}

  ## Signature Format

  Header: `sha256=<hex-encoded-signature>`
  """
  @spec verify_github(binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify_github(payload, signature, secret, _opts \\ []) do
    case String.split(signature, "=", parts: 2) do
      ["sha256", sig] ->
        expected = compute_hmac(:sha256, payload, secret, :hex)

        if secure_compare(sig, expected) do
          decode_payload(payload)
        else
          {:error, :signature_mismatch}
        end

      ["sha1", sig] ->
        # Legacy SHA-1 signature (X-Hub-Signature header)
        expected = compute_hmac(:sha, payload, secret, :hex)

        if secure_compare(sig, expected) do
          decode_payload(payload)
        else
          {:error, :signature_mismatch}
        end

      _ ->
        {:error, :invalid_signature_format}
    end
  end

  # ============================================
  # Slack
  # ============================================

  @doc """
  Verifies a Slack request signature.

  Slack uses a versioned signing scheme with timestamps to prevent replay attacks.

  ## Headers Required

  - `X-Slack-Signature` - The signature
  - `X-Slack-Request-Timestamp` - Unix timestamp

  ## Options

  - `:timestamp` - The request timestamp (required)
  - `:tolerance` - Maximum age in seconds (default: 300)

  ## Examples

      Webhook.verify_slack(payload, signature, secret, timestamp: 1614556800)
      #=> {:ok, %{"event" => ...}}

  ## Signature Format

  Slack signs: `v0:timestamp:body`
  Header format: `v0=<hex-signature>`
  """
  @spec verify_slack(binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify_slack(payload, signature, secret, opts) do
    timestamp = Keyword.fetch!(opts, :timestamp)
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance_seconds)

    with :ok <- verify_timestamp(timestamp, tolerance),
         :ok <- verify_slack_signature(payload, signature, timestamp, secret) do
      decode_payload(payload)
    end
  end

  defp verify_slack_signature(payload, signature, timestamp, secret) do
    case String.split(signature, "=", parts: 2) do
      ["v0", sig] ->
        base_string = "v0:#{timestamp}:#{payload}"
        expected = compute_hmac(:sha256, base_string, secret, :hex)

        if secure_compare(sig, expected) do
          :ok
        else
          {:error, :signature_mismatch}
        end

      _ ->
        {:error, :invalid_signature_format}
    end
  end

  # ============================================
  # Twilio
  # ============================================

  @doc """
  Verifies a Twilio request signature.

  Twilio signs the full URL with sorted POST parameters.

  ## Options

  - `:url` - The full webhook URL (required)

  ## Examples

      Webhook.verify_twilio(params, signature, auth_token, url: "https://example.com/webhook")
      #=> {:ok, params}

  ## Signature Format

  Twilio signs: URL + sorted(param_key + param_value)
  Header: Base64-encoded HMAC-SHA1
  """
  @spec verify_twilio(map() | binary(), String.t(), String.t(), keyword()) ::
          verification_result()
  def verify_twilio(params, signature, auth_token, opts) do
    url = Keyword.fetch!(opts, :url)

    # Twilio sends form-encoded params, need to build signature base
    signature_base =
      case params do
        params when is_map(params) ->
          sorted_params =
            params
            |> Enum.sort_by(fn {k, _} -> k end)
            |> Enum.map(fn {k, v} -> "#{k}#{v}" end)
            |> Enum.join()

          url <> sorted_params

        body when is_binary(body) ->
          # If raw body, assume it's the URL for GET requests
          url <> body
      end

    expected = compute_hmac(:sha, signature_base, auth_token, :base64)

    if secure_compare(signature, expected) do
      {:ok, params}
    else
      {:error, :signature_mismatch}
    end
  end

  # ============================================
  # Shopify
  # ============================================

  @doc """
  Verifies a Shopify webhook HMAC signature.

  ## Examples

      signature = "base64encodedhmac"
      Webhook.verify_shopify(payload, signature, "shpss_xxx")
      #=> {:ok, %{"topic" => "orders/create", ...}}

  ## Signature Format

  Header `X-Shopify-Hmac-SHA256`: Base64-encoded HMAC-SHA256
  """
  @spec verify_shopify(binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify_shopify(payload, signature, secret, _opts \\ []) do
    expected = compute_hmac(:sha256, payload, secret, :base64)

    if secure_compare(signature, expected) do
      decode_payload(payload)
    else
      {:error, :signature_mismatch}
    end
  end

  # ============================================
  # SendGrid
  # ============================================

  @doc """
  Verifies a SendGrid Event Webhook signature.

  SendGrid uses ECDSA signatures with a public key.

  ## Options

  - `:timestamp` - The request timestamp from header (required)
  - `:public_key` - SendGrid's verification key (if not using secret)

  ## Examples

      Webhook.verify_sendgrid(payload, signature, verification_key,
        timestamp: "1614556800"
      )
      #=> {:ok, [%{"event" => "delivered", ...}]}

  ## Signature Format

  Header `X-Twilio-Email-Event-Webhook-Signature`: Base64-encoded ECDSA signature
  Header `X-Twilio-Email-Event-Webhook-Timestamp`: Timestamp string
  """
  @spec verify_sendgrid(binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify_sendgrid(payload, signature, verification_key, opts) do
    timestamp = Keyword.fetch!(opts, :timestamp)

    # SendGrid signs timestamp + payload
    signed_payload = timestamp <> payload

    # Decode the base64 signature
    case Base.decode64(signature) do
      {:ok, decoded_sig} ->
        # Verify ECDSA signature
        case verify_ecdsa(signed_payload, decoded_sig, verification_key) do
          true -> decode_payload(payload)
          false -> {:error, :signature_mismatch}
        end

      :error ->
        {:error, :invalid_signature_encoding}
    end
  end

  defp verify_ecdsa(message, signature, public_key_pem) do
    # Parse the public key
    case :public_key.pem_decode(public_key_pem) do
      [{:SubjectPublicKeyInfo, der, _}] ->
        public_key = :public_key.der_decode(:SubjectPublicKeyInfo, der)
        :public_key.verify(message, :sha256, signature, public_key)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  # ============================================
  # Generic HMAC Verification
  # ============================================

  @doc """
  Verifies a webhook using generic HMAC verification.

  Useful for providers not specifically supported.

  ## Options

  - `:algorithm` - Hash algorithm (:sha, :sha256, :sha384, :sha512). Default: :sha256
  - `:encoding` - Signature encoding (:hex, :base64). Default: :hex
  - `:prefix` - Expected signature prefix (e.g., "sha256=")

  ## Examples

      # Hex-encoded SHA-256
      Webhook.verify_hmac(payload, "abc123...", secret)

      # Base64-encoded SHA-256
      Webhook.verify_hmac(payload, "abc123==", secret, encoding: :base64)

      # With prefix
      Webhook.verify_hmac(payload, "sha256=abc123...", secret, prefix: "sha256=")
  """
  @spec verify_hmac(binary(), String.t(), String.t(), keyword()) :: verification_result()
  def verify_hmac(payload, signature, secret, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :sha256)
    encoding = Keyword.get(opts, :encoding, :hex)
    prefix = Keyword.get(opts, :prefix)

    # Strip prefix if present
    signature =
      case prefix do
        nil -> signature
        p -> String.trim_leading(signature, p)
      end

    expected = compute_hmac(algorithm, payload, secret, encoding)

    if secure_compare(signature, expected) do
      decode_payload(payload)
    else
      {:error, :signature_mismatch}
    end
  end

  # ============================================
  # Helpers
  # ============================================

  @doc """
  Computes an HMAC signature.

  ## Examples

      Webhook.compute_hmac(:sha256, "payload", "secret", :hex)
      #=> "abc123..."
  """
  @spec compute_hmac(atom(), binary(), String.t(), :hex | :base64) :: String.t()
  def compute_hmac(algorithm, data, secret, encoding) do
    hmac = :crypto.mac(:hmac, algorithm, secret, data)

    case encoding do
      :hex -> Base.encode16(hmac, case: :lower)
      :base64 -> Base.encode64(hmac)
    end
  end

  @doc """
  Performs a constant-time string comparison to prevent timing attacks.

  ## Examples

      Webhook.secure_compare("abc", "abc")
      #=> true
  """
  @spec secure_compare(String.t(), String.t()) :: boolean()
  def secure_compare(a, b) when is_binary(a) and is_binary(b) do
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end

  def secure_compare(_, _), do: false

  defp verify_timestamp(timestamp, tolerance) do
    now = System.system_time(:second)
    age = now - timestamp

    cond do
      age < 0 -> {:error, :timestamp_in_future}
      age > tolerance -> {:error, :timestamp_expired}
      true -> :ok
    end
  end

  defp decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:ok, payload}
    end
  end

  defp decode_payload(payload), do: {:ok, payload}
end
