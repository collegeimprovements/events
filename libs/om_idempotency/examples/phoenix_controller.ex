defmodule MyAppWeb.PaymentController do
  @moduledoc """
  Example Phoenix controller using OmIdempotency for payment processing.

  Demonstrates idempotency in a web API context with proper error handling
  and response caching.
  """

  use MyAppWeb, :controller

  alias OmIdempotency
  alias MyApp.Payments

  @doc """
  Creates a payment with idempotency protection.

  Clients should send an `Idempotency-Key` header for safe retries.
  """
  def create(conn, %{"amount" => amount} = params) do
    idempotency_key = get_idempotency_key(conn, params)

    case OmIdempotency.execute(idempotency_key, fn ->
      Payments.create_charge(params)
    end, scope: "payments", on_duplicate: :wait, wait_timeout: 10_000) do
      {:ok, payment} ->
        conn
        |> put_status(:created)
        |> put_resp_header("idempotency-key", idempotency_key)
        |> json(%{data: payment})

      {:error, {:in_progress, _record}} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: "processing", message: "Payment is being processed"})

      {:error, :wait_timeout} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Request still processing, try again later"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Payment failed", reason: inspect(reason)})
    end
  end

  # Get idempotency key from header or generate one
  defp get_idempotency_key(conn, %{"order_id" => order_id}) do
    case get_req_header(conn, "idempotency-key") do
      [key] when byte_size(key) > 0 ->
        "payments:#{key}"

      _ ->
        # Generate deterministic key from order_id
        OmIdempotency.generate_key(:create_payment, order_id: order_id)
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
