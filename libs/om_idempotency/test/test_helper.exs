# Start test repo
{:ok, _} = OmIdempotency.Test.Repo.start_link()

# Run migrations
path = Path.join([__DIR__, "..", "priv", "repo", "migrations"])

if File.exists?(path) do
  Ecto.Migrator.run(OmIdempotency.Test.Repo, path, :up, all: true)
end

# Set repo for tests
Application.put_env(:om_idempotency, :repo, OmIdempotency.Test.Repo)

# Use sandbox mode for tests
Ecto.Adapters.SQL.Sandbox.mode(OmIdempotency.Test.Repo, :manual)

ExUnit.start()
