defmodule Events.Infra.Idempotency.RequestBehaviour do
  @moduledoc """
  Behaviour for request structs that can be used with idempotency middleware.

  This allows the idempotency middleware to work with any request implementation,
  breaking the circular dependency between Api.Client and Infra.Idempotency.

  ## Implementation

      defmodule MyApp.Request do
        @behaviour Events.Infra.Idempotency.RequestBehaviour

        defstruct [:method, :path, :body, :idempotency_key, :config, :metadata]

        @impl true
        def idempotency_key(%__MODULE__{idempotency_key: key}), do: key

        @impl true
        def method(%__MODULE__{method: method}), do: method

        @impl true
        def path(%__MODULE__{path: path}), do: path

        @impl true
        def body(%__MODULE__{body: body}), do: body

        @impl true
        def config(%__MODULE__{config: config}), do: config

        @impl true
        def metadata(%__MODULE__{metadata: meta}), do: meta
      end
  """

  @doc "Returns the idempotency key for the request, or nil if not set."
  @callback idempotency_key(request :: struct()) :: String.t() | nil

  @doc "Returns the HTTP method of the request."
  @callback method(request :: struct()) :: atom()

  @doc "Returns the path of the request."
  @callback path(request :: struct()) :: String.t()

  @doc "Returns the body of the request, or nil if not set."
  @callback body(request :: struct()) :: term() | nil

  @doc "Returns the config struct associated with the request, or nil."
  @callback config(request :: struct()) :: struct() | nil

  @doc "Returns metadata map associated with the request."
  @callback metadata(request :: struct()) :: map()

  @doc """
  Default implementation that extracts fields from a struct.

  Works with any struct that has the expected field names.
  """
  @spec extract(struct()) :: map()
  def extract(request) when is_struct(request) do
    %{
      idempotency_key: Map.get(request, :idempotency_key),
      method: Map.get(request, :method),
      path: Map.get(request, :path),
      body: Map.get(request, :body),
      config: Map.get(request, :config),
      metadata: Map.get(request, :metadata, %{})
    }
  end
end
