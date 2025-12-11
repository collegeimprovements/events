defmodule Events.Infra.Idempotency.ResponseBehaviour do
  @moduledoc """
  Behaviour for response structs that can be used with idempotency middleware.

  This allows the idempotency middleware to work with any response implementation,
  breaking the circular dependency between Api.Client and Infra.Idempotency.

  ## Implementation

      defmodule MyApp.Response do
        @behaviour Events.Infra.Idempotency.ResponseBehaviour

        defstruct [:status, :body, :headers]

        @impl true
        def status(%__MODULE__{status: status}), do: status

        @impl true
        def body(%__MODULE__{body: body}), do: body

        @impl true
        def headers(%__MODULE__{headers: headers}), do: headers

        @impl true
        def success?(%__MODULE__{status: status}), do: status >= 200 and status < 300
      end
  """

  @doc "Returns the HTTP status code of the response."
  @callback status(response :: struct()) :: non_neg_integer()

  @doc "Returns the body of the response."
  @callback body(response :: struct()) :: term()

  @doc "Returns the headers of the response as a map."
  @callback headers(response :: struct()) :: map()

  @doc "Returns true if the response indicates success (2xx status)."
  @callback success?(response :: struct()) :: boolean()

  @doc """
  Creates a cacheable map representation of a response.

  Used by idempotency middleware to store response data.
  """
  @spec to_cacheable(struct()) :: map()
  def to_cacheable(response) when is_struct(response) do
    %{
      status: Map.get(response, :status),
      body: Map.get(response, :body),
      headers: Map.get(response, :headers, %{})
    }
  end

  @doc """
  Default success check for any struct with a status field.
  """
  @spec default_success?(struct()) :: boolean()
  def default_success?(response) when is_struct(response) do
    case Map.get(response, :status) do
      status when is_integer(status) -> status >= 200 and status < 300
      _ -> false
    end
  end
end
