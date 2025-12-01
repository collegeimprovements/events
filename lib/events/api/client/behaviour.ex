defmodule Events.Api.Client.Behaviour do
  @moduledoc """
  Core behaviour for API clients.

  Defines the contract that all API clients must implement to provide
  a consistent interface for making HTTP requests to external APIs.

  ## Implementing a Client

      defmodule MyApp.Clients.Stripe.Client do
        @behaviour Events.Api.Client.Behaviour

        alias Events.Api.Client.{Request, Response}

        @impl true
        def config(opts) do
          %MyApp.Clients.Stripe.Config{
            api_key: Keyword.fetch!(opts, :api_key),
            api_version: Keyword.get(opts, :api_version, "2023-10-16")
          }
        end

        @impl true
        def new(config) do
          Request.new(config)
        end

        @impl true
        def execute(request) do
          request
          |> authenticate()
          |> do_request()
        end

        @impl true
        def base_url(_config), do: "https://api.stripe.com"

        @impl true
        def default_headers(config) do
          [
            {"stripe-version", config.api_version},
            {"authorization", "Bearer \#{config.api_key}"}
          ]
        end
      end

  ## Callbacks

  - `config/1` - Creates a config struct from options
  - `new/1` - Creates a new Request from config
  - `execute/1` - Executes a request and returns a Response
  - `base_url/1` - Returns the base URL for the API
  - `default_headers/1` - Returns default headers for all requests
  """

  alias Events.Api.Client.{Request, Response}

  @doc """
  Creates a config struct from options.

  ## Examples

      config = Client.config(api_key: "sk_test_...")
  """
  @callback config(opts :: keyword()) :: struct()

  @doc """
  Creates a new Request from a config struct.

  ## Examples

      request = Client.new(config)
  """
  @callback new(config :: struct()) :: Request.t()

  @doc """
  Executes a request and returns a response.

  ## Examples

      {:ok, response} = Client.execute(request)
      {:error, reason} = Client.execute(request)
  """
  @callback execute(request :: Request.t()) :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Returns the base URL for the API.

  ## Examples

      Client.base_url(config)
      #=> "https://api.stripe.com"
  """
  @callback base_url(config :: struct()) :: String.t()

  @doc """
  Returns the default headers for all requests.

  ## Examples

      Client.default_headers(config)
      #=> [{"authorization", "Bearer sk_test_..."}, {"stripe-version", "2023-10-16"}]
  """
  @callback default_headers(config :: struct()) :: [{String.t(), String.t()}]

  @doc """
  Optional callback for transforming the response.

  Override this to add custom response handling, error normalization, etc.

  Default implementation returns the response unchanged.
  """
  @callback transform_response(Response.t(), Request.t()) :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Optional callback for handling errors.

  Override this to add custom error handling, logging, etc.

  Default implementation returns the error unchanged.
  """
  @callback handle_error(term(), Request.t()) :: {:error, term()}

  @optional_callbacks [transform_response: 2, handle_error: 2]
end
