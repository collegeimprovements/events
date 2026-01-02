defmodule Events.Api.Clients.Stripe do
  @moduledoc """
  Stripe API client for Events application.

  Thin wrapper around `OmStripe` with Events-specific defaults.

  See `OmStripe` for full documentation.
  """

  # Delegate all functions to OmStripe
  defdelegate config(opts), to: OmStripe
  defdelegate config_from_env(), to: OmStripe
  defdelegate new(config), to: OmStripe

  # Resource selectors
  defdelegate customers(req, id \\ nil), to: OmStripe
  defdelegate charges(req, id \\ nil), to: OmStripe
  defdelegate payment_intents(req, id \\ nil), to: OmStripe
  defdelegate subscriptions(req, id \\ nil), to: OmStripe
  defdelegate invoices(req, id \\ nil), to: OmStripe

  # CRUD operations
  defdelegate create(req, params, opts \\ []), to: OmStripe
  defdelegate retrieve(req, opts \\ []), to: OmStripe
  defdelegate update(req, params, opts \\ []), to: OmStripe
  defdelegate remove(req, opts \\ []), to: OmStripe
  defdelegate list(req, params \\ []), to: OmStripe

  # Direct API - Customers
  defdelegate create_customer(params, config, opts \\ []), to: OmStripe
  defdelegate get_customer(id, config), to: OmStripe
  defdelegate update_customer(id, params, config, opts \\ []), to: OmStripe
  defdelegate delete_customer(id, config), to: OmStripe
  defdelegate list_customers(config, params \\ []), to: OmStripe

  # Direct API - Charges
  defdelegate create_charge(params, config, opts \\ []), to: OmStripe
  defdelegate get_charge(id, config), to: OmStripe

  # Direct API - Payment Intents
  defdelegate create_payment_intent(params, config, opts \\ []), to: OmStripe
  defdelegate get_payment_intent(id, config), to: OmStripe
  defdelegate confirm_payment_intent(id, config, params \\ []), to: OmStripe
  defdelegate cancel_payment_intent(id, config, params \\ []), to: OmStripe
end
