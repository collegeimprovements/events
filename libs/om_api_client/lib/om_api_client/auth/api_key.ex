defmodule OmApiClient.Auth.APIKey do
  @moduledoc """
  API Key authentication strategy.

  Supports multiple placement options:
  - Header: Custom header name (default: "x-api-key")
  - Bearer: Authorization header with Bearer prefix
  - Query: Query parameter

  ## Usage

      # Header (default)
      auth = APIKey.new("sk_test_xxx")
      auth = APIKey.new("sk_test_xxx", header: "x-api-key")

      # Bearer token
      auth = APIKey.bearer("sk_test_xxx")

      # Query parameter
      auth = APIKey.query("sk_test_xxx", param: :api_key)

  ## Examples

      # Stripe-style bearer token
      config = %{auth: APIKey.bearer("sk_test_xxx")}

      # Custom header
      config = %{auth: APIKey.new("xxx", header: "x-custom-key")}

      # Query parameter
      config = %{auth: APIKey.query("xxx", param: :key)}
  """

  alias OmApiClient.Request

  @type placement :: :header | :bearer | :query
  @type t :: %__MODULE__{
          key: String.t(),
          placement: placement(),
          header_name: String.t() | nil,
          param_name: atom() | nil
        }

  @enforce_keys [:key, :placement]
  defstruct [:key, :placement, :header_name, :param_name]

  @default_header "x-api-key"

  @doc """
  Creates a new API key authentication with custom header placement.

  ## Options

  - `:header` - Header name (default: "x-api-key")

  ## Examples

      APIKey.new("sk_test_xxx")
      APIKey.new("sk_test_xxx", header: "x-custom-key")
  """
  @spec new(String.t(), keyword()) :: t()
  def new(key, opts \\ []) when is_binary(key) do
    %__MODULE__{
      key: key,
      placement: :header,
      header_name: Keyword.get(opts, :header, @default_header)
    }
  end

  @doc """
  Creates a bearer token authentication.

  Adds `Authorization: Bearer <token>` header.

  ## Examples

      APIKey.bearer("sk_test_xxx")
  """
  @spec bearer(String.t()) :: t()
  def bearer(key) when is_binary(key) do
    %__MODULE__{
      key: key,
      placement: :bearer
    }
  end

  @doc """
  Creates query parameter authentication.

  ## Options

  - `:param` - Parameter name (default: :api_key)

  ## Examples

      APIKey.query("xxx")
      APIKey.query("xxx", param: :key)
  """
  @spec query(String.t(), keyword()) :: t()
  def query(key, opts \\ []) when is_binary(key) do
    %__MODULE__{
      key: key,
      placement: :query,
      param_name: Keyword.get(opts, :param, :api_key)
    }
  end

  # ============================================
  # Protocol Implementation
  # ============================================

  defimpl OmApiClient.Auth do
    def authenticate(%{placement: :header, key: key, header_name: header}, request) do
      Request.header(request, header, key)
    end

    def authenticate(%{placement: :bearer, key: key}, request) do
      Request.header(request, "authorization", "Bearer #{key}")
    end

    def authenticate(%{placement: :query, key: key, param_name: param}, request) do
      Request.query(request, param, key)
    end

    def valid?(_auth), do: true

    def refresh(auth), do: {:ok, auth}
  end
end
