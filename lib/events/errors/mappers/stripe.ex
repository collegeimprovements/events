defmodule Events.Errors.Mappers.Stripe do
  @moduledoc """
  Error mapper for Stripe API errors.

  Handles normalization of errors from Stripe payment processing,
  webhooks, and API calls.
  """

  alias Events.Errors.Error

  @doc """
  Normalizes a Stripe error struct.

  ## Examples

      iex> Stripe.normalize(%Stripe.Error{code: :card_declined})
      %Error{type: :unprocessable, code: :card_declined}
  """
  @spec normalize(struct()) :: Error.t()
  def normalize(%{__struct__: struct_module} = stripe_error)
      when struct_module in [Stripe.Error, Stripe.APIError] do
    code = extract_code(stripe_error)
    raw_error = Map.get(stripe_error, :extra, %{}) |> Map.get(:raw_error, %{})
    message = extract_message(stripe_error, raw_error)

    {type, normalized_code} = map_stripe_code(code)

    Error.new(type, normalized_code,
      message: message,
      source: :stripe,
      details: %{
        stripe_code: code,
        stripe_type: Map.get(raw_error, "type"),
        decline_code: Map.get(raw_error, "decline_code"),
        param: Map.get(raw_error, "param"),
        charge_id: Map.get(raw_error, "charge"),
        payment_intent_id: Map.get(raw_error, "payment_intent"),
        raw_error: raw_error
      }
    )
  end

  ## Helpers

  defp extract_code(%{code: code}) when is_atom(code), do: code
  defp extract_code(%{code: code}) when is_binary(code), do: safe_to_atom(code)

  defp extract_code(%{} = error) do
    error
    |> Map.get(:extra, %{})
    |> Map.get(:raw_error, %{})
    |> Map.get("code", :unknown)
    |> case do
      code when is_binary(code) -> safe_to_atom(code)
      code when is_atom(code) -> code
      _ -> :unknown
    end
  end

  # Safe atom conversion - tries existing atoms first
  # Stripe error codes are bounded, but we still prefer existing atoms
  defp safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
      # Stripe may add new error codes, so we allow creating new atoms
      # The set of Stripe error codes is bounded
      String.to_atom(string)
  end

  defp extract_message(stripe_error, raw_error) do
    Map.get(stripe_error, :message) ||
      Map.get(raw_error, "message") ||
      Map.get(raw_error, "error_description") ||
      "Stripe error occurred"
  end

  ## Stripe Error Code Mappings

  # Card Errors
  defp map_stripe_code(:card_declined),
    do: {:unprocessable, :card_declined}

  defp map_stripe_code(:insufficient_funds),
    do: {:unprocessable, :insufficient_funds}

  defp map_stripe_code(:lost_card),
    do: {:unprocessable, :lost_card}

  defp map_stripe_code(:stolen_card),
    do: {:unprocessable, :stolen_card}

  defp map_stripe_code(:expired_card),
    do: {:unprocessable, :expired_card}

  defp map_stripe_code(:incorrect_cvc),
    do: {:validation, :incorrect_cvc}

  defp map_stripe_code(:incorrect_number),
    do: {:validation, :incorrect_card_number}

  defp map_stripe_code(:invalid_cvc),
    do: {:validation, :invalid_cvc}

  defp map_stripe_code(:invalid_expiry_month),
    do: {:validation, :invalid_expiry_month}

  defp map_stripe_code(:invalid_expiry_year),
    do: {:validation, :invalid_expiry_year}

  defp map_stripe_code(:invalid_number),
    do: {:validation, :invalid_card_number}

  defp map_stripe_code(:card_velocity_exceeded),
    do: {:rate_limit, :card_velocity_exceeded}

  # Processing Errors
  defp map_stripe_code(:processing_error),
    do: {:external, :processing_error}

  defp map_stripe_code(:issuer_not_available),
    do: {:service_unavailable, :issuer_not_available}

  defp map_stripe_code(:payment_intent_authentication_failure),
    do: {:unauthorized, :authentication_failed}

  # API Errors
  defp map_stripe_code(:api_key_expired),
    do: {:unauthorized, :api_key_expired}

  defp map_stripe_code(:invalid_request_error),
    do: {:bad_request, :invalid_request}

  defp map_stripe_code(:rate_limit),
    do: {:rate_limit, :rate_limit_exceeded}

  defp map_stripe_code(:authentication_error),
    do: {:unauthorized, :authentication_error}

  # Resource Errors
  defp map_stripe_code(:resource_missing),
    do: {:not_found, :resource_not_found}

  defp map_stripe_code(:charge_already_captured),
    do: {:conflict, :already_captured}

  defp map_stripe_code(:charge_already_refunded),
    do: {:conflict, :already_refunded}

  defp map_stripe_code(:amount_too_large),
    do: {:validation, :amount_too_large}

  defp map_stripe_code(:amount_too_small),
    do: {:validation, :amount_too_small}

  # Idempotency Errors
  defp map_stripe_code(:idempotency_error),
    do: {:conflict, :idempotency_error}

  # Payment Method Errors
  defp map_stripe_code(:payment_method_unactivated),
    do: {:unprocessable, :payment_method_unactivated}

  defp map_stripe_code(:payment_method_unexpected_state),
    do: {:conflict, :payment_method_unexpected_state}

  # Setup Intent Errors
  defp map_stripe_code(:setup_intent_authentication_failure),
    do: {:unauthorized, :setup_authentication_failed}

  defp map_stripe_code(:setup_intent_unexpected_state),
    do: {:conflict, :setup_intent_unexpected_state}

  # Webhook Errors
  defp map_stripe_code(:signature_verification_failed),
    do: {:unauthorized, :signature_verification_failed}

  # Balance/Payout Errors
  defp map_stripe_code(:balance_insufficient),
    do: {:unprocessable, :insufficient_balance}

  defp map_stripe_code(:payout_reconciliation_not_ready),
    do: {:unprocessable, :reconciliation_not_ready}

  # Tax Errors
  defp map_stripe_code(:tax_id_invalid),
    do: {:validation, :tax_id_invalid}

  # Fallback
  defp map_stripe_code(code) when is_atom(code),
    do: {:external, code}

  defp map_stripe_code(_),
    do: {:external, :stripe_error}
end
