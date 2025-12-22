defmodule OmApiClient.Auth.Basic do
  @moduledoc """
  HTTP Basic authentication strategy.

  Commonly used by services like Twilio that require username:password
  authentication encoded in Base64.

  ## Usage

      # Standard Basic auth
      auth = Basic.new("username", "password")

      # Twilio-style (Account SID + Auth Token)
      auth = Basic.new("AC123...", "auth_token_here")

  ## How it works

  Basic auth encodes `username:password` in Base64 and adds it
  to the Authorization header:

      Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQ=
  """

  alias OmApiClient.Request

  @type t :: %__MODULE__{
          username: String.t(),
          password: String.t()
        }

  @enforce_keys [:username, :password]
  defstruct [:username, :password]

  @doc """
  Creates a new Basic authentication.

  ## Examples

      Basic.new("user", "pass")
      Basic.new("ACxxx", "auth_token")
  """
  @spec new(String.t(), String.t()) :: t()
  def new(username, password) when is_binary(username) and is_binary(password) do
    %__MODULE__{
      username: username,
      password: password
    }
  end

  @doc """
  Creates Twilio-style authentication.

  Twilio uses the Account SID as username and Auth Token as password.

  ## Examples

      Basic.twilio("ACxxx...", "auth_token")
  """
  @spec twilio(String.t(), String.t()) :: t()
  def twilio(account_sid, auth_token) do
    new(account_sid, auth_token)
  end

  @doc """
  Returns the encoded credentials string.

  ## Examples

      Basic.encoded_credentials(auth)
      #=> "dXNlcm5hbWU6cGFzc3dvcmQ="
  """
  @spec encoded_credentials(t()) :: String.t()
  def encoded_credentials(%__MODULE__{username: username, password: password}) do
    Base.encode64("#{username}:#{password}")
  end

  # ============================================
  # Protocol Implementation
  # ============================================

  defimpl OmApiClient.Auth do
    def authenticate(auth, request) do
      encoded = OmApiClient.Auth.Basic.encoded_credentials(auth)
      Request.header(request, "authorization", "Basic #{encoded}")
    end

    def valid?(_auth), do: true

    def refresh(auth), do: {:ok, auth}
  end
end
