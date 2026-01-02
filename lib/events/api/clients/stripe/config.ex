defmodule Events.Api.Clients.Stripe.Config do
  @moduledoc """
  Configuration for the Stripe API client.

  Thin wrapper around `OmStripe.Config`.

  See `OmStripe.Config` for full documentation.
  """

  # Re-export the type from OmStripe.Config
  @type t :: OmStripe.Config.t()

  defdelegate new(opts), to: OmStripe.Config
  defdelegate from_env(), to: OmStripe.Config
  defdelegate for_account(config, account_id), to: OmStripe.Config
  defdelegate test_mode?(config), to: OmStripe.Config
  defdelegate live_mode?(config), to: OmStripe.Config
end
