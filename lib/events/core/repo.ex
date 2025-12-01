defmodule Events.Core.Repo do
  use Ecto.Repo,
    otp_app: :events,
    adapter: Ecto.Adapters.Postgres
end
