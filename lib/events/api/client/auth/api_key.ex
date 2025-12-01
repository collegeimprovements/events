defmodule Events.Api.Client.Auth.APIKey do
  @moduledoc """
  API Key authentication strategy.

  Supports placing the API key in a header (default) or query parameter.
  Commonly used by services like Stripe, SendGrid, and many REST APIs.

  ## Usage

      # Bearer token in Authorization header (Stripe style)
      auth = APIKey.new("sk_test_123", header: "Authorization", prefix: "Bearer")

      # API key in custom header (SendGrid style)
      auth = APIKey.new("SG.xxx", header: "Authorization", prefix: "Bearer")

      # API key in query parameter
      auth = APIKey.new("abc123", query: "api_key")

      # Custom header without prefix
      auth = APIKey.new("mykey", header: "X-API-Key")

  ## Presets

      auth = APIKey.bearer("access_token_123")  # Authorization: Bearer <token>
      auth = APIKey.stripe("sk_test_123")       # Authorization: Bearer <key>
  """

  alias Events.Api.Client.Request

  @type location :: {:header, String.t()} | {:query, atom()}

  @type t :: %__MODULE__{
          key: String.t(),
          location: location(),
          prefix: String.t() | nil
        }

  @enforce_keys [:key, :location]
  defstruct [:key, :location, :prefix]

  @doc """
  Creates a new API key authentication.

  ## Options

  - `:header` - Header name to use (default: "Authorization")
  - `:query` - Query parameter name (alternative to header)
  - `:prefix` - Prefix for header value (e.g., "Bearer", "Basic")

  ## Examples

      APIKey.new("sk_test_123")
      APIKey.new("sk_test_123", header: "Authorization", prefix: "Bearer")
      APIKey.new("abc123", query: "api_key")
  """
  @spec new(String.t(), keyword()) :: t()
  def new(key, opts \\ []) when is_binary(key) do
    location =
      cond do
        opts[:query] -> {:query, to_atom(opts[:query])}
        opts[:header] -> {:header, opts[:header]}
        true -> {:header, "authorization"}
      end

    %__MODULE__{
      key: key,
      location: location,
      prefix: opts[:prefix]
    }
  end

  @doc """
  Creates a Bearer token authentication.

  Equivalent to `APIKey.new(token, header: "Authorization", prefix: "Bearer")`

  ## Examples

      APIKey.bearer("eyJ...")
      #=> %APIKey{key: "eyJ...", location: {:header, "authorization"}, prefix: "Bearer"}
  """
  @spec bearer(String.t()) :: t()
  def bearer(token) when is_binary(token) do
    new(token, header: "authorization", prefix: "Bearer")
  end

  @doc """
  Creates Stripe-style API key authentication.

  Equivalent to `APIKey.new(key, header: "Authorization", prefix: "Bearer")`

  ## Examples

      APIKey.stripe("sk_test_...")
  """
  @spec stripe(String.t()) :: t()
  def stripe(api_key) when is_binary(api_key) do
    bearer(api_key)
  end

  @doc """
  Creates a query parameter API key authentication.

  ## Examples

      APIKey.query("abc123", "api_key")
      #=> %APIKey{key: "abc123", location: {:query, "api_key"}, prefix: nil}
  """
  @spec query(String.t(), String.t()) :: t()
  def query(key, param_name) when is_binary(key) and is_binary(param_name) do
    new(key, query: param_name)
  end

  # Convert query param name to atom at construction time
  # This is developer configuration, not user input
  defp to_atom(name) when is_atom(name), do: name
  defp to_atom(name) when is_binary(name), do: String.to_atom(name)

  # ============================================
  # Protocol Implementation
  # ============================================

  defimpl Events.Api.Client.Auth do
    def authenticate(%{location: {:header, name}, key: key, prefix: nil}, request) do
      Request.header(request, name, key)
    end

    def authenticate(%{location: {:header, name}, key: key, prefix: prefix}, request) do
      Request.header(request, name, "#{prefix} #{key}")
    end

    def authenticate(%{location: {:query, name}, key: key}, request) do
      Request.put_query(request, name, key)
    end

    def valid?(_auth), do: true

    def refresh(auth), do: {:ok, auth}
  end
end
