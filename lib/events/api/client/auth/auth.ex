defprotocol Events.Api.Client.Auth do
  @moduledoc """
  Protocol for authentication strategies.

  Allows different authentication mechanisms to be used interchangeably
  with API clients. Implementations handle adding auth to requests,
  validating credentials, and refreshing tokens when needed.

  ## Implementations

  - `Events.Api.Client.Auth.APIKey` - API key in header or query
  - `Events.Api.Client.Auth.Basic` - HTTP Basic authentication
  - `OmApiClient.Auth.OAuth2` - OAuth2 bearer tokens with refresh

  ## Usage

      # Create auth credentials
      auth = APIKey.new("sk_test_123", header: "Authorization", prefix: "Bearer")

      # Authenticate a request
      request = Auth.authenticate(auth, request)

      # Check if credentials are valid
      Auth.valid?(auth)

      # Refresh credentials if needed
      {:ok, new_auth} = Auth.refresh(auth)

  ## Custom Implementation

      defmodule MyApp.CustomAuth do
        defstruct [:token, :expires_at]

        defimpl Events.Api.Client.Auth do
          def authenticate(auth, request) do
            Request.header(request, "X-Custom-Token", auth.token)
          end

          def valid?(%{expires_at: nil}), do: true
          def valid?(%{expires_at: exp}), do: DateTime.compare(exp, DateTime.utc_now()) == :gt

          def refresh(auth) do
            # Custom refresh logic
            {:ok, auth}
          end
        end
      end
  """

  alias Events.Api.Client.Request

  @doc """
  Adds authentication to a request.

  Returns the request with auth headers/query params added.

  ## Examples

      Auth.authenticate(api_key_auth, request)
      #=> %Request{headers: [{"Authorization", "Bearer sk_test_..."}]}
  """
  @spec authenticate(t, Request.t()) :: Request.t()
  def authenticate(auth, request)

  @doc """
  Checks if the credentials are still valid.

  For API keys, this typically returns true.
  For OAuth2 tokens, this checks expiration.

  ## Examples

      Auth.valid?(api_key_auth)
      #=> true

      Auth.valid?(expired_oauth_token)
      #=> false
  """
  @spec valid?(t) :: boolean()
  def valid?(auth)

  @doc """
  Refreshes the credentials if needed.

  For API keys, this returns the auth unchanged.
  For OAuth2 tokens, this fetches a new access token.

  Returns `{:ok, auth}` or `{:error, reason}`.

  ## Examples

      Auth.refresh(oauth_auth)
      #=> {:ok, %OAuth2{access_token: "new_token", ...}}
  """
  @spec refresh(t) :: {:ok, t} | {:error, term()}
  def refresh(auth)
end
