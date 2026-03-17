defmodule OmIdempotency.Test.Repo do
  use Ecto.Repo,
    otp_app: :om_idempotency,
    adapter: Ecto.Adapters.Postgres
end
