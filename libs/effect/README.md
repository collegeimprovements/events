# Effect

Algebraic effects for Elixir - composable side effects and dependency injection.

## Installation

```elixir
def deps do
  [{:effect, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.Effects do
  use Effect

  # Define effects
  defeffect :log, [:level, :message]
  defeffect :http_get, [:url]
  defeffect :db_query, [:query]
end

# Use effects in your code
defmodule MyApp.Service do
  import MyApp.Effects

  def fetch_user(id) do
    effect do
      log(:info, "Fetching user #{id}")
      response <- http_get("https://api.example.com/users/#{id}")
      user <- db_query(from u in User, where: u.id == ^id)
      {:ok, user}
    end
  end
end

# Run with handlers
MyApp.Service.fetch_user(1)
|> Effect.run(
  log: fn level, msg -> Logger.log(level, msg) end,
  http_get: fn url -> HTTPoison.get(url) end,
  db_query: fn query -> Repo.one(query) end
)
```

## Effect Definition

```elixir
defmodule MyApp.Effects do
  use Effect

  defeffect :log, [:level, :message]
  defeffect :send_email, [:to, :subject, :body]
  defeffect :get_config, [:key]
end
```

## Effect Composition

```elixir
def send_welcome_email(user) do
  effect do
    config <- get_config(:email)
    log(:info, "Sending welcome email to #{user.email}")
    send_email(user.email, "Welcome!", config.welcome_template)
  end
end
```

## Testing with Mock Handlers

```elixir
test "sends welcome email" do
  emails_sent = Agent.start_link(fn -> [] end)

  MyApp.send_welcome_email(user)
  |> Effect.run(
    log: fn _, _ -> :ok end,
    get_config: fn :email -> %{welcome_template: "Hello!"} end,
    send_email: fn to, subject, body ->
      Agent.update(emails_sent, &[{to, subject, body} | &1])
      :ok
    end
  )

  assert [{user.email, "Welcome!", "Hello!"}] = Agent.get(emails_sent, & &1)
end
```

## Benefits

- **Testability**: Mock effects without mocking modules
- **Composability**: Combine effects freely
- **Dependency Injection**: Inject implementations at runtime
- **Separation of Concerns**: Pure business logic, impure effects

## License

MIT
