defmodule OmStripe do
  @moduledoc """
  Stripe API client with dual API support.

  Provides both direct and pipeline-style APIs for interacting with
  the Stripe API, with built-in retry, rate limiting, and error handling.

  ## Direct API

  Simple function calls with config as the last argument:

      config = OmStripe.config(api_key: "sk_test_...")

      {:ok, customer} = OmStripe.create_customer(%{email: "user@example.com"}, config)
      {:ok, customer} = OmStripe.get_customer("cus_123", config)
      {:ok, customers} = OmStripe.list_customers([limit: 10], config)

  ## Pipeline API

  Chainable operations with config first:

      OmStripe.new(config)
      |> OmStripe.customers()
      |> OmStripe.create(%{email: "user@example.com"})

      OmStripe.new(config)
      |> OmStripe.customers("cus_123")
      |> OmStripe.get()

  ## Configuration

      # From options
      config = OmStripe.config(api_key: "sk_test_...")

      # From environment
      config = OmStripe.config_from_env()

      # For connected accounts
      config = OmStripe.config(api_key: "sk_test_...", connect_account: "acct_123")

  ## Error Handling

  All operations return `{:ok, result}` or `{:error, %StripeError{}}`:

      alias FnTypes.Errors.StripeError
      alias FnTypes.Protocols.{Normalizable, Recoverable}

      case OmStripe.create_customer(%{email: "invalid"}, config) do
        {:ok, customer} ->
          IO.puts("Created: \#{customer["id"]}")

        {:error, %StripeError{type: "card_error"} = error} ->
          # Card errors - show user-friendly message
          IO.puts("Card error: \#{error.message}")

        {:error, %StripeError{type: "rate_limit_error"} = error} ->
          # Rate limit - check if retryable
          if Recoverable.recoverable?(error) do
            delay = Recoverable.retry_delay(error, 1)
            Process.sleep(delay)
            # retry...
          end

        {:error, %StripeError{} = error} ->
          # Normalize to standard error format
          normalized = Normalizable.normalize(error)
          Logger.error("Stripe error: \#{inspect(normalized)}")
      end

  ## Idempotency

      OmStripe.create_customer(%{email: "user@example.com"}, config,
        idempotency_key: "unique_key_123"
      )
  """

  use OmApiClient,
    base_url: "https://api.stripe.com",
    auth: :bearer,
    content_type: :form

  alias OmStripe.Config
  alias OmApiClient.{Request, Response}
  alias FnTypes.Errors.StripeError

  # ============================================
  # Configuration
  # ============================================

  @doc """
  Creates a Stripe configuration from options.

  ## Options

  - `:api_key` - Stripe API key (required)
  - `:api_version` - Stripe API version
  - `:connect_account` - Connected account ID
  - `:timeout` - Request timeout in ms

  ## Examples

      OmStripe.config(api_key: "sk_test_...")
      OmStripe.config(api_key: "sk_test_...", api_version: "2023-10-16")
  """
  def config(opts) when is_list(opts) do
    Config.new(opts)
  end

  @doc """
  Creates a Stripe configuration from environment variables.

  ## Examples

      config = OmStripe.config_from_env()
  """
  @spec config_from_env() :: Config.t()
  def config_from_env do
    Config.from_env()
  end

  @impl true
  def default_headers(%Config{} = config) do
    headers = [
      {"stripe-version", config.api_version}
    ]

    case config.connect_account do
      nil -> headers
      account -> [{"stripe-account", account} | headers]
    end
  end

  # ============================================
  # Pipeline API - Resource Selectors
  # ============================================

  @doc """
  Selects the customers resource.

  ## Examples

      OmStripe.new(config)
      |> OmStripe.customers()
      |> OmStripe.list()

      OmStripe.new(config)
      |> OmStripe.customers("cus_123")
      |> OmStripe.get()
  """
  @spec customers(Request.t(), String.t() | nil) :: Request.t()
  def customers(req, id \\ nil)

  def customers(%Request{} = req, nil) do
    req
    |> Request.path("/v1/customers")
    |> Request.metadata(:resource, :customer)
  end

  def customers(%Request{} = req, id) when is_binary(id) do
    req
    |> Request.path("/v1/customers/#{id}")
    |> Request.metadata(:resource, :customer)
    |> Request.metadata(:resource_id, id)
  end

  @doc """
  Selects the charges resource.

  ## Examples

      OmStripe.new(config)
      |> OmStripe.charges()
      |> OmStripe.create(%{amount: 1000, currency: "usd", source: "tok_..."})
  """
  @spec charges(Request.t(), String.t() | nil) :: Request.t()
  def charges(req, id \\ nil)

  def charges(%Request{} = req, nil) do
    req
    |> Request.path("/v1/charges")
    |> Request.metadata(:resource, :charge)
  end

  def charges(%Request{} = req, id) when is_binary(id) do
    req
    |> Request.path("/v1/charges/#{id}")
    |> Request.metadata(:resource, :charge)
    |> Request.metadata(:resource_id, id)
  end

  @doc """
  Selects the payment intents resource.

  ## Examples

      OmStripe.new(config)
      |> OmStripe.payment_intents()
      |> OmStripe.create(%{amount: 1000, currency: "usd"})
  """
  @spec payment_intents(Request.t(), String.t() | nil) :: Request.t()
  def payment_intents(req, id \\ nil)

  def payment_intents(%Request{} = req, nil) do
    req
    |> Request.path("/v1/payment_intents")
    |> Request.metadata(:resource, :payment_intent)
  end

  def payment_intents(%Request{} = req, id) when is_binary(id) do
    req
    |> Request.path("/v1/payment_intents/#{id}")
    |> Request.metadata(:resource, :payment_intent)
    |> Request.metadata(:resource_id, id)
  end

  @doc """
  Selects the subscriptions resource.

  ## Examples

      OmStripe.new(config)
      |> OmStripe.subscriptions()
      |> OmStripe.list(customer: "cus_123")
  """
  @spec subscriptions(Request.t(), String.t() | nil) :: Request.t()
  def subscriptions(req, id \\ nil)

  def subscriptions(%Request{} = req, nil) do
    req
    |> Request.path("/v1/subscriptions")
    |> Request.metadata(:resource, :subscription)
  end

  def subscriptions(%Request{} = req, id) when is_binary(id) do
    req
    |> Request.path("/v1/subscriptions/#{id}")
    |> Request.metadata(:resource, :subscription)
    |> Request.metadata(:resource_id, id)
  end

  @doc """
  Selects the invoices resource.

  ## Examples

      OmStripe.new(config)
      |> OmStripe.invoices()
      |> OmStripe.list(customer: "cus_123")
  """
  @spec invoices(Request.t(), String.t() | nil) :: Request.t()
  def invoices(req, id \\ nil)

  def invoices(%Request{} = req, nil) do
    req
    |> Request.path("/v1/invoices")
    |> Request.metadata(:resource, :invoice)
  end

  def invoices(%Request{} = req, id) when is_binary(id) do
    req
    |> Request.path("/v1/invoices/#{id}")
    |> Request.metadata(:resource, :invoice)
    |> Request.metadata(:resource_id, id)
  end

  # ============================================
  # Pipeline API - CRUD Operations
  # ============================================

  @doc """
  Creates a resource (POST).

  ## Examples

      OmStripe.new(config)
      |> OmStripe.customers()
      |> OmStripe.create(%{email: "user@example.com"})
  """
  @spec create(Request.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(%Request{} = req, params, opts \\ []) when is_map(params) do
    req
    |> maybe_add_idempotency_key(opts)
    |> post(req.path, params)
    |> handle_response()
  end

  @doc """
  Retrieves a resource (GET).

  ## Examples

      OmStripe.new(config)
      |> OmStripe.customers("cus_123")
      |> OmStripe.retrieve()
  """
  @spec retrieve(Request.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def retrieve(%Request{} = req, opts \\ []) do
    req
    |> get(req.path, opts)
    |> handle_response()
  end

  @doc """
  Updates a resource (POST for Stripe).

  ## Examples

      OmStripe.new(config)
      |> OmStripe.customers("cus_123")
      |> OmStripe.update(%{email: "new@example.com"})
  """
  @spec update(Request.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def update(%Request{} = req, params, opts \\ []) when is_map(params) do
    req
    |> maybe_add_idempotency_key(opts)
    |> post(req.path, params)
    |> handle_response()
  end

  @doc """
  Deletes a resource (DELETE).

  ## Examples

      OmStripe.new(config)
      |> OmStripe.customers("cus_123")
      |> OmStripe.remove()
  """
  @spec remove(Request.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def remove(%Request{} = req, opts \\ []) do
    delete(req, req.path, opts)
    |> handle_response()
  end

  @doc """
  Lists resources (GET).

  ## Examples

      OmStripe.new(config)
      |> OmStripe.customers()
      |> OmStripe.list(limit: 10)
  """
  @spec list(Request.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list(%Request{} = req, params \\ []) do
    req
    |> get(req.path, query: params)
    |> handle_response()
  end

  # ============================================
  # Direct API - Customers
  # ============================================

  @doc """
  Creates a customer.

  ## Examples

      OmStripe.create_customer(%{email: "user@example.com"}, config)
      OmStripe.create_customer(%{email: "user@example.com"}, config,
        idempotency_key: "unique_key"
      )
  """
  @spec create_customer(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_customer(params, config, opts \\ []) do
    new(config)
    |> customers()
    |> create(params, opts)
  end

  @doc """
  Retrieves a customer.

  ## Examples

      OmStripe.get_customer("cus_123", config)
  """
  @spec get_customer(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
  def get_customer(id, config) do
    new(config)
    |> customers(id)
    |> retrieve()
  end

  @doc """
  Updates a customer.

  ## Examples

      OmStripe.update_customer("cus_123", %{email: "new@example.com"}, config)
  """
  @spec update_customer(String.t(), map(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def update_customer(id, params, config, opts \\ []) do
    new(config)
    |> customers(id)
    |> update(params, opts)
  end

  @doc """
  Deletes a customer.

  ## Examples

      OmStripe.delete_customer("cus_123", config)
  """
  @spec delete_customer(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
  def delete_customer(id, config) do
    new(config)
    |> customers(id)
    |> remove()
  end

  @doc """
  Lists customers.

  ## Examples

      OmStripe.list_customers(config)
      OmStripe.list_customers(config, limit: 10, email: "user@example.com")
  """
  @spec list_customers(Config.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_customers(config, params \\ []) do
    new(config)
    |> customers()
    |> list(params)
  end

  # ============================================
  # Direct API - Charges
  # ============================================

  @doc """
  Creates a charge.

  ## Examples

      OmStripe.create_charge(%{amount: 1000, currency: "usd", source: "tok_..."}, config)
  """
  @spec create_charge(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_charge(params, config, opts \\ []) do
    new(config)
    |> charges()
    |> create(params, opts)
  end

  @doc """
  Retrieves a charge.

  ## Examples

      OmStripe.get_charge("ch_123", config)
  """
  @spec get_charge(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
  def get_charge(id, config) do
    new(config)
    |> charges(id)
    |> retrieve()
  end

  # ============================================
  # Direct API - Payment Intents
  # ============================================

  @doc """
  Creates a payment intent.

  ## Examples

      OmStripe.create_payment_intent(%{amount: 1000, currency: "usd"}, config)
  """
  @spec create_payment_intent(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_payment_intent(params, config, opts \\ []) do
    new(config)
    |> payment_intents()
    |> create(params, opts)
  end

  @doc """
  Retrieves a payment intent.

  ## Examples

      OmStripe.get_payment_intent("pi_123", config)
  """
  @spec get_payment_intent(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
  def get_payment_intent(id, config) do
    new(config)
    |> payment_intents(id)
    |> retrieve()
  end

  @doc """
  Confirms a payment intent.

  ## Examples

      OmStripe.confirm_payment_intent("pi_123", config)
      OmStripe.confirm_payment_intent("pi_123", config, payment_method: "pm_...")
  """
  @spec confirm_payment_intent(String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def confirm_payment_intent(id, config, params \\ []) do
    new(config)
    |> payment_intents(id)
    |> Request.append_path("confirm")
    |> post("/v1/payment_intents/#{id}/confirm", Map.new(params))
    |> handle_response()
  end

  @doc """
  Cancels a payment intent.

  ## Examples

      OmStripe.cancel_payment_intent("pi_123", config)
  """
  @spec cancel_payment_intent(String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def cancel_payment_intent(id, config, params \\ []) do
    new(config)
    |> post("/v1/payment_intents/#{id}/cancel", Map.new(params))
    |> handle_response()
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp maybe_add_idempotency_key(req, opts) do
    case Keyword.get(opts, :idempotency_key) do
      nil -> req
      key -> Request.header(req, "idempotency-key", key)
    end
  end

  defp handle_response({:ok, %Response{} = resp}) do
    if Response.success?(resp) do
      {:ok, resp.body}
    else
      {:error, to_stripe_error(resp)}
    end
  end

  defp handle_response({:error, _} = error), do: error

  defp to_stripe_error(%Response{body: %{"error" => error}} = resp) do
    StripeError.new(resp.status,
      type: error["type"],
      code: error["code"],
      message: error["message"],
      param: error["param"],
      decline_code: error["decline_code"],
      request_id: resp.api_request_id,
      doc_url: error["doc_url"]
    )
  end

  defp to_stripe_error(%Response{} = resp) do
    StripeError.new(resp.status,
      message: extract_error_message(resp.body),
      request_id: resp.api_request_id
    )
  end

  defp extract_error_message(%{"message" => msg}), do: msg
  defp extract_error_message(%{"error" => msg}) when is_binary(msg), do: msg
  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(_), do: nil
end
