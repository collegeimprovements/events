defmodule Events.Api.Client do
  @moduledoc """
  Unified framework for building external API clients.

  This module delegates to `OmApiClient` for core functionality.
  See `OmApiClient` for full documentation.

  ## Quick Start

      defmodule MyApp.Clients.Stripe do
        use Events.Api.Client,
          base_url: "https://api.stripe.com",
          auth: :bearer,
          content_type: :form

        def create_customer(params, config) do
          new(config)
          |> post("/v1/customers", params)
        end
      end

  ## Options

  - `:base_url` - Base URL for all requests (required)
  - `:auth` - Default auth type (`:bearer`, `:basic`, `:api_key`, `:none`)
  - `:content_type` - Default content type (`:json`, `:form`)
  - `:retry` - Enable retries (default: true)
  - `:circuit_breaker` - Circuit breaker name (atom)
  - `:rate_limiter` - Rate limiter name (atom)
  - `:telemetry` - Enable telemetry events (default: true)
  - `:idempotency` - Idempotency settings (scope, enabled for mutating requests)

  ## Telemetry

  All requests emit telemetry events:

  - `[:events, :api_client, :request, :start]` - Request started
  - `[:events, :api_client, :request, :stop]` - Request completed
  - `[:events, :api_client, :request, :exception]` - Request failed

  See `OmApiClient.Telemetry` for details.
  """

  defmacro __using__(opts) do
    # Add Events-specific defaults
    opts =
      opts
      |> Keyword.put_new(:telemetry_prefix, [:events, :api_client])
      |> Keyword.put_new(:request_module, Events.Api.Client.Request)
      |> Keyword.put_new(:response_module, Events.Api.Client.Response)

    quote do
      use OmApiClient, unquote(opts)

      # Alias OmApiClient modules
      alias OmApiClient.{Auth, Telemetry}
      alias Events.Api.Client.{Request, Response}
    end
  end
end
