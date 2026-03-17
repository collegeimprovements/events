defmodule MyApp.Workers.SendEmailWorker do
  @moduledoc """
  Example Oban worker using OmIdempotency to prevent duplicate emails.

  Oban can retry jobs, so idempotency ensures emails are sent only once
  even if the job is retried.
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 3

  alias OmIdempotency
  alias MyApp.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template, "data" => data}}) do
    # Generate deterministic key from user, template, and a hash of data
    key = OmIdempotency.hash_key(:send_email, %{
      user_id: user_id,
      template: template,
      data: data
    })

    case OmIdempotency.execute(key, fn ->
      send_email(user_id, template, data)
    end, scope: "emails", ttl: :timer.hours(48)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_email(user_id, template, data) do
    with {:ok, user} <- MyApp.Accounts.get_user(user_id),
         {:ok, email} <- build_email(user, template, data),
         {:ok, _} <- Mailer.deliver(email) do
      {:ok, :sent}
    end
  end

  defp build_email(user, "welcome", _data) do
    {:ok, MyApp.Emails.welcome_email(user)}
  end

  defp build_email(user, "password_reset", %{"token" => token}) do
    {:ok, MyApp.Emails.password_reset_email(user, token)}
  end

  defp build_email(user, "order_confirmation", %{"order_id" => order_id}) do
    with {:ok, order} <- MyApp.Orders.get(order_id) do
      {:ok, MyApp.Emails.order_confirmation_email(user, order)}
    end
  end
end
