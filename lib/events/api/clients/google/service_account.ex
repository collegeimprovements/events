defmodule Events.Api.Clients.Google.ServiceAccount do
  @moduledoc """
  Google Service Account authentication using JWT.

  Handles OAuth2 token generation for Google APIs using service account credentials.
  This replaces the need for Goth by implementing JWT signing and token exchange directly.

  ## Usage

      # Load credentials from JSON file
      {:ok, creds} = ServiceAccount.from_json_file("/path/to/service-account.json")

      # Or from environment variable
      {:ok, creds} = ServiceAccount.from_env("GOOGLE_APPLICATION_CREDENTIALS")

      # Or from JSON string
      {:ok, creds} = ServiceAccount.from_json(json_string)

      # Get an access token for specific scopes
      {:ok, token} = ServiceAccount.get_access_token(creds, [
        "https://www.googleapis.com/auth/firebase.messaging"
      ])

      # Token includes expiration
      %{access_token: "ya29...", expires_at: ~U[...], token_type: "Bearer"}

  ## Caching

  Tokens are valid for 1 hour. Use the `expires_at` field to implement caching:

      case ServiceAccount.get_cached_token(creds, scopes) do
        {:ok, token} -> token
        :expired -> ServiceAccount.get_access_token(creds, scopes)
      end

  ## Service Account JSON Format

  The service account JSON file should contain:

      {
        "type": "service_account",
        "project_id": "your-project",
        "private_key_id": "key-id",
        "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
        "client_email": "service@project.iam.gserviceaccount.com",
        "client_id": "123456789",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        ...
      }
  """

  alias FnTypes.Config, as: Cfg

  @token_uri "https://oauth2.googleapis.com/token"
  @token_lifetime_seconds 3600
  @token_buffer_seconds 300

  @type credentials :: %{
          project_id: String.t(),
          private_key: String.t(),
          private_key_id: String.t(),
          client_email: String.t(),
          client_id: String.t() | nil,
          token_uri: String.t()
        }

  @type token :: %{
          access_token: String.t(),
          expires_at: DateTime.t(),
          token_type: String.t()
        }

  # ============================================
  # Credential Loading
  # ============================================

  @doc """
  Loads service account credentials from a JSON file.

  ## Examples

      {:ok, creds} = ServiceAccount.from_json_file("/path/to/credentials.json")
  """
  @spec from_json_file(String.t()) :: {:ok, credentials()} | {:error, term()}
  def from_json_file(path) do
    case File.read(path) do
      {:ok, contents} -> from_json(contents)
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Loads service account credentials from an environment variable.

  The env var can contain either:
  - A path to a JSON file
  - The JSON content directly

  ## Examples

      {:ok, creds} = ServiceAccount.from_env("GOOGLE_APPLICATION_CREDENTIALS")
      {:ok, creds} = ServiceAccount.from_env("GOOGLE_CREDENTIALS_JSON")
  """
  @spec from_env(String.t()) :: {:ok, credentials()} | {:error, term()}
  def from_env(env_var) do
    case Cfg.string(env_var) do
      nil ->
        {:error, {:env_not_set, env_var}}

      value ->
        # Check if it's a file path or JSON content
        if String.starts_with?(value, "{") do
          from_json(value)
        else
          from_json_file(value)
        end
    end
  end

  @doc """
  Loads service account credentials from a JSON string.

  ## Examples

      {:ok, creds} = ServiceAccount.from_json(json_string)
  """
  @spec from_json(String.t()) :: {:ok, credentials()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, data} -> from_map(data)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  @doc """
  Creates credentials from a decoded map.

  ## Examples

      {:ok, creds} = ServiceAccount.from_map(%{
        "project_id" => "my-project",
        "private_key" => "-----BEGIN...",
        "client_email" => "service@project.iam.gserviceaccount.com",
        ...
      })
  """
  @spec from_map(map()) :: {:ok, credentials()} | {:error, term()}
  def from_map(data) when is_map(data) do
    with {:ok, project_id} <- fetch_required(data, "project_id"),
         {:ok, private_key} <- fetch_required(data, "private_key"),
         {:ok, client_email} <- fetch_required(data, "client_email") do
      {:ok,
       %{
         project_id: project_id,
         private_key: private_key,
         private_key_id: Map.get(data, "private_key_id"),
         client_email: client_email,
         client_id: Map.get(data, "client_id"),
         token_uri: Map.get(data, "token_uri", @token_uri)
       }}
    end
  end

  defp fetch_required(data, key) do
    case Map.get(data, key) do
      nil -> {:error, {:missing_field, key}}
      value -> {:ok, value}
    end
  end

  # ============================================
  # Token Generation
  # ============================================

  @doc """
  Gets an access token for the given scopes.

  Makes a request to Google's OAuth2 token endpoint using a signed JWT assertion.

  ## Examples

      {:ok, token} = ServiceAccount.get_access_token(creds, [
        "https://www.googleapis.com/auth/firebase.messaging"
      ])

      # Use the token
      headers = [{"authorization", "\#{token.token_type} \#{token.access_token}"}]
  """
  @spec get_access_token(credentials(), [String.t()]) :: {:ok, token()} | {:error, term()}
  def get_access_token(credentials, scopes) when is_list(scopes) do
    jwt = build_jwt(credentials, scopes)

    body = %{
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt
    }

    case Req.post(credentials.token_uri, form: body) do
      {:ok, %{status: 200, body: response}} ->
        token = %{
          access_token: response["access_token"],
          expires_at: DateTime.add(DateTime.utc_now(), response["expires_in"], :second),
          token_type: response["token_type"] || "Bearer"
        }

        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_error, status, body}}

      {:error, reason} ->
        {:error, {:request_error, reason}}
    end
  end

  @doc """
  Checks if a token is still valid (with buffer for safety).

  ## Examples

      ServiceAccount.token_valid?(token)
      #=> true
  """
  @spec token_valid?(token()) :: boolean()
  def token_valid?(%{expires_at: expires_at}) do
    buffer = DateTime.add(DateTime.utc_now(), @token_buffer_seconds, :second)
    DateTime.compare(expires_at, buffer) == :gt
  end

  @doc """
  Returns the project ID from credentials.

  ## Examples

      ServiceAccount.project_id(creds)
      #=> "my-project-id"
  """
  @spec project_id(credentials()) :: String.t()
  def project_id(%{project_id: project_id}), do: project_id

  # ============================================
  # JWT Building
  # ============================================

  @doc """
  Builds a signed JWT for the service account.

  The JWT is used as an assertion in the OAuth2 token request.
  """
  @spec build_jwt(credentials(), [String.t()]) :: String.t()
  def build_jwt(credentials, scopes) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims = %{
      "iss" => credentials.client_email,
      "sub" => credentials.client_email,
      "aud" => credentials.token_uri,
      "iat" => now,
      "exp" => now + @token_lifetime_seconds,
      "scope" => Enum.join(scopes, " ")
    }

    jwk = JOSE.JWK.from_pem(credentials.private_key)

    # Use RS256 algorithm for Google service accounts
    {_, jwt} =
      jwk
      |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "JWT"}, claims)
      |> JOSE.JWS.compact()

    jwt
  end

  # ============================================
  # Token Server (GenServer for caching)
  # ============================================

  defmodule TokenServer do
    @moduledoc """
    GenServer for caching Google service account tokens.

    Automatically refreshes tokens before expiration.

    ## Usage

        # Start the server
        {:ok, pid} = TokenServer.start_link(
          credentials: creds,
          scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
          name: :fcm_token_server
        )

        # Get a token (automatically refreshed)
        {:ok, token} = TokenServer.get_token(:fcm_token_server)
    """

    use GenServer
    require Logger

    alias Events.Api.Clients.Google.ServiceAccount

    @refresh_buffer_ms 5 * 60 * 1000

    defstruct [:credentials, :scopes, :token, :refresh_timer]

    @type state :: %__MODULE__{
            credentials: ServiceAccount.credentials(),
            scopes: [String.t()],
            token: ServiceAccount.token() | nil,
            refresh_timer: reference() | nil
          }

    # ============================================
    # Public API
    # ============================================

    @doc """
    Starts the token server.

    ## Options

    - `:credentials` - Service account credentials (required)
    - `:scopes` - OAuth2 scopes (required)
    - `:name` - Process name (optional)
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      name = Keyword.get(opts, :name)
      gen_opts = if name, do: [name: name], else: []
      GenServer.start_link(__MODULE__, opts, gen_opts)
    end

    @doc """
    Gets a valid access token.

    Returns a cached token if valid, otherwise fetches a new one.

    ## Examples

        {:ok, token} = TokenServer.get_token(:fcm_token_server)
        token.access_token
        #=> "ya29..."
    """
    @spec get_token(GenServer.server()) :: {:ok, ServiceAccount.token()} | {:error, term()}
    def get_token(server) do
      GenServer.call(server, :get_token)
    end

    @doc """
    Forces a token refresh.

    ## Examples

        {:ok, token} = TokenServer.refresh_token(:fcm_token_server)
    """
    @spec refresh_token(GenServer.server()) :: {:ok, ServiceAccount.token()} | {:error, term()}
    def refresh_token(server) do
      GenServer.call(server, :refresh_token)
    end

    @doc """
    Returns a child spec for supervision.
    """
    def child_spec(opts) do
      name = Keyword.get(opts, :name, __MODULE__)

      %{
        id: {__MODULE__, name},
        start: {__MODULE__, :start_link, [opts]},
        type: :worker,
        restart: :permanent
      }
    end

    # ============================================
    # GenServer Callbacks
    # ============================================

    @impl true
    def init(opts) do
      credentials = Keyword.fetch!(opts, :credentials)
      scopes = Keyword.fetch!(opts, :scopes)

      state = %__MODULE__{
        credentials: credentials,
        scopes: scopes,
        token: nil,
        refresh_timer: nil
      }

      # Fetch initial token
      {:ok, state, {:continue, :fetch_initial_token}}
    end

    @impl true
    def handle_continue(:fetch_initial_token, state) do
      case do_fetch_token(state) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("[TokenServer] Failed to fetch initial token: #{inspect(reason)}")
          # Schedule retry
          Process.send_after(self(), :retry_fetch, 5_000)
          {:noreply, state}
      end
    end

    @impl true
    def handle_call(:get_token, _from, %{token: nil} = state) do
      case do_fetch_token(state) do
        {:ok, new_state} ->
          {:reply, {:ok, new_state.token}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end

    def handle_call(:get_token, _from, %{token: token} = state) do
      if ServiceAccount.token_valid?(token) do
        {:reply, {:ok, token}, state}
      else
        case do_fetch_token(state) do
          {:ok, new_state} ->
            {:reply, {:ok, new_state.token}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    end

    def handle_call(:refresh_token, _from, state) do
      case do_fetch_token(state) do
        {:ok, new_state} ->
          {:reply, {:ok, new_state.token}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end

    @impl true
    def handle_info(:refresh_token, state) do
      case do_fetch_token(state) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("[TokenServer] Failed to refresh token: #{inspect(reason)}")
          # Schedule retry
          Process.send_after(self(), :refresh_token, 30_000)
          {:noreply, state}
      end
    end

    def handle_info(:retry_fetch, state) do
      case do_fetch_token(state) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("[TokenServer] Retry failed: #{inspect(reason)}")
          Process.send_after(self(), :retry_fetch, 10_000)
          {:noreply, state}
      end
    end

    # ============================================
    # Private Helpers
    # ============================================

    defp do_fetch_token(state) do
      case ServiceAccount.get_access_token(state.credentials, state.scopes) do
        {:ok, token} ->
          # Cancel existing timer
          if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

          # Schedule refresh before expiration
          refresh_in = calculate_refresh_delay(token.expires_at)
          timer = Process.send_after(self(), :refresh_token, refresh_in)

          Logger.debug("[TokenServer] Token fetched, expires at #{token.expires_at}")

          {:ok, %{state | token: token, refresh_timer: timer}}

        {:error, _} = error ->
          error
      end
    end

    defp calculate_refresh_delay(expires_at) do
      expires_in_ms = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)
      max(expires_in_ms - @refresh_buffer_ms, 1000)
    end
  end
end
