defmodule MyApp.StripeClient do
  @moduledoc """
  Example API client using OmIdempotency middleware for automatic
  idempotency protection on all Stripe API calls.
  """

  alias OmIdempotency.Middleware
  alias MyApp.HTTPClient

  @base_url "https://api.stripe.com"

  @doc """
  Creates a Stripe charge with automatic idempotency.
  """
  def create_charge(params, opts \\ []) do
    idempotency_key = Keyword.get_lazy(opts, :idempotency_key, fn ->
      OmIdempotency.generate_key(:stripe_charge,
        amount: params.amount,
        customer: params.customer
      )
    end)

    request = %{
      method: :post,
      path: "/v1/charges",
      body: params,
      idempotency_key: idempotency_key
    }

    Middleware.wrap(request, &execute_request/1, scope: "stripe")
  end

  @doc """
  Creates a Stripe customer with idempotency protection.
  """
  def create_customer(params, opts \\ []) do
    idempotency_key = Keyword.get_lazy(opts, :idempotency_key, fn ->
      OmIdempotency.generate_key(:stripe_customer, email: params.email)
    end)

    request = %{
      method: :post,
      path: "/v1/customers",
      body: params,
      idempotency_key: idempotency_key
    }

    Middleware.wrap(request, &execute_request/1, scope: "stripe")
  end

  @doc """
  Updates a subscription with idempotency protection.
  """
  def update_subscription(subscription_id, params, opts \\ []) do
    idempotency_key = Keyword.get_lazy(opts, :idempotency_key, fn ->
      OmIdempotency.hash_key(:stripe_update_subscription, %{
        subscription_id: subscription_id,
        params: params
      })
    end)

    request = %{
      method: :post,
      path: "/v1/subscriptions/#{subscription_id}",
      body: params,
      idempotency_key: idempotency_key
    }

    Middleware.wrap(request, &execute_request/1,
      scope: "stripe",
      on_duplicate: :wait
    )
  end

  # Execute the actual HTTP request
  defp execute_request(request) do
    HTTPClient.post(
      "#{@base_url}#{request.path}",
      request.body,
      headers: [
        {"Authorization", "Bearer #{api_key()}"},
        {"Idempotency-Key", request.idempotency_key}
      ]
    )
  end

  defp api_key do
    Application.get_env(:my_app, :stripe_api_key)
  end
end

# Alternative: Using Req with idempotency middleware

defmodule MyApp.StripeClientWithReq do
  @moduledoc """
  Example using Req library with automatic idempotency middleware.
  """

  alias OmIdempotency.Middleware

  def client do
    Req.new(base_url: "https://api.stripe.com")
    |> Middleware.attach(scope: "stripe")
    |> Req.Request.put_header("authorization", "Bearer #{api_key()}")
  end

  def create_charge(params) do
    idempotency_key = OmIdempotency.generate_key(:stripe_charge,
      amount: params.amount,
      customer: params.customer
    )

    client()
    |> Req.post("/v1/charges",
      json: params,
      idempotency_key: idempotency_key
    )
  end

  defp api_key do
    Application.get_env(:my_app, :stripe_api_key)
  end
end
