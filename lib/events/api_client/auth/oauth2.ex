defmodule Events.APIClient.Auth.OAuth2 do
  @moduledoc """
  OAuth2 authentication strategy with automatic token refresh.

  Supports the standard OAuth2 authorization code flow, client credentials,
  and refresh token grants. Automatically refreshes expired access tokens.

  ## Usage

      # Create from existing tokens (e.g., after authorization code exchange)
      auth = OAuth2.new(
        access_token: "ya29.xxx",
        refresh_token: "1//xxx",
        expires_at: ~U[2024-01-15 12:00:00Z],
        client_id: "your-client-id",
        client_secret: "your-client-secret",
        token_url: "https://oauth2.googleapis.com/token"
      )

      # Client credentials flow
      auth = OAuth2.client_credentials(
        client_id: "your-client-id",
        client_secret: "your-client-secret",
        token_url: "https://accounts.spotify.com/api/token",
        scope: "playlist-read-private"
      )

  ## Presets

      # Google APIs
      auth = OAuth2.google(
        access_token: "ya29.xxx",
        refresh_token: "1//xxx",
        expires_at: expires_at,
        client_id: "xxx.apps.googleusercontent.com",
        client_secret: "xxx"
      )

      # GitHub
      auth = OAuth2.github(access_token: "gho_xxx")

  ## Auto-Refresh

  When `Auth.valid?/1` returns false (token expired), the client framework
  will automatically call `Auth.refresh/1` to obtain a new access token
  using the refresh token.

      if Auth.valid?(auth) do
        Auth.authenticate(auth, request)
      else
        {:ok, new_auth} = Auth.refresh(auth)
        Auth.authenticate(new_auth, request)
      end
  """

  alias Events.APIClient.Request

  @type t :: %__MODULE__{
          access_token: String.t(),
          refresh_token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          token_url: String.t() | nil,
          scope: String.t() | nil,
          token_type: String.t()
        }

  @enforce_keys [:access_token]
  defstruct [
    :access_token,
    :refresh_token,
    :expires_at,
    :client_id,
    :client_secret,
    :token_url,
    :scope,
    token_type: "Bearer"
  ]

  # Buffer time before expiration (5 minutes)
  @expiry_buffer_seconds 300

  # ============================================
  # Constructor
  # ============================================

  @doc """
  Creates a new OAuth2 authentication.

  ## Options

  - `:access_token` - The access token (required)
  - `:refresh_token` - Refresh token for obtaining new access tokens
  - `:expires_at` - DateTime when the access token expires
  - `:expires_in` - Seconds until expiration (alternative to expires_at)
  - `:client_id` - OAuth2 client ID (required for refresh)
  - `:client_secret` - OAuth2 client secret (required for refresh)
  - `:token_url` - Token endpoint URL (required for refresh)
  - `:scope` - OAuth2 scope
  - `:token_type` - Token type (default: "Bearer")

  ## Examples

      OAuth2.new(
        access_token: "ya29.xxx",
        refresh_token: "1//xxx",
        expires_in: 3600,
        client_id: "xxx",
        client_secret: "xxx",
        token_url: "https://oauth2.googleapis.com/token"
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    access_token = Keyword.fetch!(opts, :access_token)

    expires_at =
      case {Keyword.get(opts, :expires_at), Keyword.get(opts, :expires_in)} do
        {nil, nil} -> nil
        {expires_at, _} when not is_nil(expires_at) -> expires_at
        {nil, expires_in} -> DateTime.add(DateTime.utc_now(), expires_in, :second)
      end

    %__MODULE__{
      access_token: access_token,
      refresh_token: Keyword.get(opts, :refresh_token),
      expires_at: expires_at,
      client_id: Keyword.get(opts, :client_id),
      client_secret: Keyword.get(opts, :client_secret),
      token_url: Keyword.get(opts, :token_url),
      scope: Keyword.get(opts, :scope),
      token_type: Keyword.get(opts, :token_type, "Bearer")
    }
  end

  @doc """
  Creates OAuth2 auth from a token response map.

  Useful when parsing responses from token endpoints.

  ## Examples

      {:ok, %{"access_token" => token, "expires_in" => 3600, ...}} = response
      auth = OAuth2.from_token_response(response, base_auth)
  """
  @spec from_token_response(map(), t() | keyword()) :: t()
  def from_token_response(response, base \\ [])

  def from_token_response(response, %__MODULE__{} = base) when is_map(response) do
    expires_at =
      case Map.get(response, "expires_in") do
        nil -> base.expires_at
        expires_in -> DateTime.add(DateTime.utc_now(), expires_in, :second)
      end

    %__MODULE__{
      access_token: Map.get(response, "access_token", base.access_token),
      refresh_token: Map.get(response, "refresh_token", base.refresh_token),
      expires_at: expires_at,
      client_id: base.client_id,
      client_secret: base.client_secret,
      token_url: base.token_url,
      scope: Map.get(response, "scope", base.scope),
      token_type: Map.get(response, "token_type", base.token_type)
    }
  end

  def from_token_response(response, opts) when is_map(response) and is_list(opts) do
    from_token_response(response, new(Keyword.put_new(opts, :access_token, "")))
  end

  # ============================================
  # Presets
  # ============================================

  @doc """
  Creates Google OAuth2 authentication.

  ## Examples

      OAuth2.google(
        access_token: "ya29.xxx",
        refresh_token: "1//xxx",
        expires_at: expires_at,
        client_id: "xxx.apps.googleusercontent.com",
        client_secret: "xxx"
      )
  """
  @spec google(keyword()) :: t()
  def google(opts) do
    opts
    |> Keyword.put(:token_url, "https://oauth2.googleapis.com/token")
    |> new()
  end

  @doc """
  Creates GitHub OAuth2 authentication.

  GitHub tokens don't expire by default, so refresh is not needed.

  ## Examples

      OAuth2.github(access_token: "gho_xxxx")
      OAuth2.github(access_token: "ghu_xxxx")  # User token
  """
  @spec github(keyword()) :: t()
  def github(opts) do
    opts
    |> Keyword.put(:token_url, "https://github.com/login/oauth/access_token")
    |> new()
  end

  @doc """
  Creates Slack OAuth2 authentication.

  ## Examples

      OAuth2.slack(
        access_token: "xoxb-xxx",
        refresh_token: "xoxr-xxx",
        expires_at: expires_at,
        client_id: "xxx",
        client_secret: "xxx"
      )
  """
  @spec slack(keyword()) :: t()
  def slack(opts) do
    opts
    |> Keyword.put(:token_url, "https://slack.com/api/oauth.v2.access")
    |> new()
  end

  @doc """
  Creates Microsoft/Azure OAuth2 authentication.

  ## Options

  - `:tenant` - Azure AD tenant (default: "common")
  - All other OAuth2 options

  ## Examples

      OAuth2.microsoft(
        access_token: "eyJ...",
        refresh_token: "M.xxx",
        expires_at: expires_at,
        client_id: "xxx",
        client_secret: "xxx",
        tenant: "your-tenant-id"
      )
  """
  @spec microsoft(keyword()) :: t()
  def microsoft(opts) do
    tenant = Keyword.get(opts, :tenant, "common")
    token_url = "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token"

    opts
    |> Keyword.delete(:tenant)
    |> Keyword.put(:token_url, token_url)
    |> new()
  end

  @doc """
  Creates Spotify OAuth2 authentication.

  ## Examples

      OAuth2.spotify(
        access_token: "BQxxx",
        refresh_token: "AQxxx",
        expires_at: expires_at,
        client_id: "xxx",
        client_secret: "xxx"
      )
  """
  @spec spotify(keyword()) :: t()
  def spotify(opts) do
    opts
    |> Keyword.put(:token_url, "https://accounts.spotify.com/api/token")
    |> new()
  end

  # ============================================
  # Client Credentials Flow
  # ============================================

  @doc """
  Obtains an access token using the client credentials flow.

  This is used for server-to-server authentication where no user is involved.

  ## Options

  - `:client_id` - OAuth2 client ID (required)
  - `:client_secret` - OAuth2 client secret (required)
  - `:token_url` - Token endpoint URL (required)
  - `:scope` - Requested scope (optional)

  ## Examples

      {:ok, auth} = OAuth2.client_credentials(
        client_id: "xxx",
        client_secret: "xxx",
        token_url: "https://accounts.spotify.com/api/token",
        scope: "playlist-read-private"
      )
  """
  @spec client_credentials(keyword()) :: {:ok, t()} | {:error, term()}
  def client_credentials(opts) do
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    token_url = Keyword.fetch!(opts, :token_url)
    scope = Keyword.get(opts, :scope)

    body = %{grant_type: "client_credentials"}
    body = if scope, do: Map.put(body, :scope, scope), else: body

    auth_header = Base.encode64("#{client_id}:#{client_secret}")

    case Req.post(token_url,
           form: body,
           headers: [{"authorization", "Basic #{auth_header}"}]
         ) do
      {:ok, %{status: 200, body: response}} ->
        auth =
          from_token_response(response,
            client_id: client_id,
            client_secret: client_secret,
            token_url: token_url
          )

        {:ok, auth}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================
  # Helpers
  # ============================================

  @doc """
  Checks if the token is expired or about to expire.

  Returns true if the token will expire within the buffer period (5 minutes).

  ## Examples

      OAuth2.expired?(auth)
      #=> true
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    buffer = DateTime.add(DateTime.utc_now(), @expiry_buffer_seconds, :second)
    DateTime.compare(expires_at, buffer) != :gt
  end

  @doc """
  Checks if the auth can be refreshed.

  Requires refresh_token, client_id, client_secret, and token_url.

  ## Examples

      OAuth2.can_refresh?(auth)
      #=> true
  """
  @spec can_refresh?(t()) :: boolean()
  def can_refresh?(%__MODULE__{} = auth) do
    auth.refresh_token != nil and
      auth.client_id != nil and
      auth.client_secret != nil and
      auth.token_url != nil
  end

  @doc """
  Returns the time until the token expires.

  ## Examples

      OAuth2.expires_in(auth)
      #=> 3542  # seconds
  """
  @spec expires_in(t()) :: integer() | nil
  def expires_in(%__MODULE__{expires_at: nil}), do: nil

  def expires_in(%__MODULE__{expires_at: expires_at}) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second)
  end

  # ============================================
  # Protocol Implementation
  # ============================================

  defimpl Events.APIClient.Auth do
    alias Events.APIClient.Auth.OAuth2

    def authenticate(%OAuth2{access_token: token, token_type: type}, request) do
      Request.header(request, "authorization", "#{type} #{token}")
    end

    def valid?(%OAuth2{} = auth) do
      not OAuth2.expired?(auth)
    end

    def refresh(%OAuth2{} = auth) do
      cond do
        not OAuth2.can_refresh?(auth) ->
          {:error, :cannot_refresh}

        true ->
          do_refresh(auth)
      end
    end

    defp do_refresh(%OAuth2{} = auth) do
      body = %{
        grant_type: "refresh_token",
        refresh_token: auth.refresh_token,
        client_id: auth.client_id,
        client_secret: auth.client_secret
      }

      case Req.post(auth.token_url, form: body) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, OAuth2.from_token_response(response, auth)}

        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, body: body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
