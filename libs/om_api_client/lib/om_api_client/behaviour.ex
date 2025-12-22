defmodule OmApiClient.Behaviour do
  @moduledoc """
  Behaviour for API clients built with OmApiClient.

  Implement this behaviour to create custom API clients with
  full access to the framework's features.

  ## Example

      defmodule MyApp.Clients.GitHub do
        @behaviour OmApiClient.Behaviour

        alias OmApiClient.{Request, Response}

        @impl true
        def base_url(_config), do: "https://api.github.com"

        @impl true
        def default_headers(config) do
          [
            {"accept", "application/vnd.github.v3+json"},
            {"user-agent", "MyApp/1.0"}
          ]
        end

        @impl true
        def new(config) do
          Request.new(config)
        end

        @impl true
        def execute(request) do
          # Custom execution logic
        end
      end

  ## Custom Request/Response Types

  Clients can use custom Request and Response types that implement
  the same interface as `OmApiClient.Request` and `OmApiClient.Response`.
  This allows extending the types with additional functionality
  (e.g., idempotency tracking).
  """

  @typedoc "Any struct that implements the Request interface"
  @type request :: struct()

  @typedoc "Any struct that implements the Response interface"
  @type response :: struct()

  @doc """
  Returns the base URL for API requests.

  The config is passed to allow dynamic base URLs (e.g., for sandbox vs production).
  """
  @callback base_url(config :: map()) :: String.t()

  @doc """
  Returns default headers to include with every request.

  Common uses:
  - API version headers
  - User-Agent strings
  - Accept headers
  """
  @callback default_headers(config :: map()) :: [{String.t(), String.t()}]

  @doc """
  Creates a new request builder with the given configuration.

  This is the entry point for the pipeline API.
  """
  @callback new(config :: map()) :: request()

  @doc """
  Executes a request and returns the response.

  This is where authentication, middleware, and the actual HTTP call happen.
  """
  @callback execute(request :: request()) :: {:ok, response()} | {:error, term()}
end
