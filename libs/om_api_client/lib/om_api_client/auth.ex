defprotocol OmApiClient.Auth do
  @moduledoc """
  Protocol for authentication strategies.

  Implement this protocol to create custom authentication
  mechanisms for your API clients.

  ## Built-in Implementations

  - `OmApiClient.Auth.APIKey` - API key authentication (header, query, bearer)
  - `OmApiClient.Auth.Basic` - HTTP Basic authentication
  - `OmApiClient.Auth.OAuth2` - OAuth2 with automatic refresh

  ## Custom Implementation

      defmodule MyApp.Auth.HMAC do
        defstruct [:key, :secret]

        defimpl OmApiClient.Auth do
          def authenticate(auth, request) do
            signature = compute_signature(auth, request)
            OmApiClient.Request.header(request, "x-signature", signature)
          end

          def valid?(_auth), do: true

          def refresh(auth), do: {:ok, auth}

          defp compute_signature(auth, request) do
            # HMAC implementation
          end
        end
      end

  ## Protocol Functions

  - `authenticate/2` - Adds authentication to a request
  - `valid?/1` - Checks if the auth credentials are valid/not expired
  - `refresh/1` - Refreshes expired credentials (e.g., OAuth2 tokens)
  """

  alias OmApiClient.Request

  @doc """
  Applies authentication to a request.

  Returns the modified request with authentication headers/params added.
  """
  @spec authenticate(t, Request.t()) :: Request.t()
  def authenticate(auth, request)

  @doc """
  Checks if the authentication credentials are valid.

  For OAuth2, this checks if the access token is expired.
  For API keys, this typically returns true.
  """
  @spec valid?(t) :: boolean()
  def valid?(auth)

  @doc """
  Refreshes expired credentials.

  For OAuth2, this uses the refresh token to obtain a new access token.
  For non-refreshable auth types, returns `{:ok, auth}` unchanged.
  """
  @spec refresh(t) :: {:ok, t} | {:error, term()}
  def refresh(auth)
end
