defmodule Events.Data.Repo do
  use Ecto.Repo,
    otp_app: :events,
    adapter: Ecto.Adapters.Postgres
end
