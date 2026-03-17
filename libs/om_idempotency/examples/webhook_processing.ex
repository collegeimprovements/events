defmodule MyApp.Webhooks.StripeHandler do
  @moduledoc """
  Example webhook handler using OmIdempotency.

  Webhooks can be retried by external services, so idempotency is critical
  to prevent duplicate processing.
  """

  alias OmIdempotency
  alias MyApp.{Orders, Subscriptions, Accounts}

  @doc """
  Handles incoming Stripe webhook events with idempotency protection.

  The event ID is used as the idempotency key to ensure each event
  is processed exactly once.
  """
  def handle_event(%{"id" => event_id, "type" => type} = event) do
    # Use event ID as idempotency key
    key = OmIdempotency.hash_key(:stripe_webhook, %{event_id: event_id})

    # Long TTL for webhooks since they might be retried over days
    OmIdempotency.execute(key, fn ->
      process_event(type, event)
    end,
      scope: "webhooks:stripe",
      ttl: :timer.hours(72),
      metadata: %{
        event_id: event_id,
        event_type: type,
        received_at: DateTime.utc_now()
      }
    )
  end

  # Process different event types
  defp process_event("payment_intent.succeeded", %{"data" => %{"object" => payment_intent}}) do
    order_id = payment_intent["metadata"]["order_id"]

    with {:ok, order} <- Orders.get(order_id),
         {:ok, _} <- Orders.mark_paid(order, payment_intent) do
      {:ok, :processed}
    end
  end

  defp process_event("payment_intent.failed", %{"data" => %{"object" => payment_intent}}) do
    order_id = payment_intent["metadata"]["order_id"]

    with {:ok, order} <- Orders.get(order_id),
         {:ok, _} <- Orders.mark_failed(order, payment_intent) do
      {:ok, :processed}
    end
  end

  defp process_event("customer.subscription.created", %{"data" => %{"object" => subscription}}) do
    customer_id = subscription["customer"]

    with {:ok, account} <- Accounts.get_by_stripe_id(customer_id),
         {:ok, _} <- Subscriptions.create_from_stripe(account, subscription) do
      {:ok, :processed}
    end
  end

  defp process_event("customer.subscription.deleted", %{"data" => %{"object" => subscription}}) do
    subscription_id = subscription["id"]

    with {:ok, sub} <- Subscriptions.get_by_stripe_id(subscription_id),
         {:ok, _} <- Subscriptions.cancel(sub) do
      {:ok, :processed}
    end
  end

  # Ignore unknown events
  defp process_event(_type, _event) do
    {:ok, :ignored}
  end
end
