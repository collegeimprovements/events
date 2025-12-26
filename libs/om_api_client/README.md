# OmApiClient

HTTP API client with middleware, retries, and telemetry.

## Installation

```elixir
def deps do
  [{:om_api_client, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.GitHubClient do
  use OmApiClient,
    base_url: "https://api.github.com",
    headers: [{"Accept", "application/vnd.github.v3+json"}]

  def get_user(username) do
    get("/users/#{username}")
  end

  def create_repo(name, opts \\ []) do
    post("/user/repos", %{name: name, private: opts[:private] || false})
  end
end

# Usage
{:ok, user} = MyApp.GitHubClient.get_user("octocat")
```

## Configuration

```elixir
use OmApiClient,
  base_url: "https://api.example.com",
  headers: [{"Authorization", "Bearer #{token}"}],
  timeout: 30_000,
  retry: [max_attempts: 3, initial_delay: 100],
  telemetry_prefix: [:my_app, :github]
```

## Request Methods

```elixir
get(path, opts \\ [])
post(path, body, opts \\ [])
put(path, body, opts \\ [])
patch(path, body, opts \\ [])
delete(path, opts \\ [])
```

## Options

```elixir
get("/users",
  query: %{page: 1, per_page: 20},
  headers: [{"X-Custom", "value"}],
  timeout: 5_000
)
```

## Middleware

Built-in middleware:

```elixir
use OmApiClient,
  middleware: [
    OmApiClient.Middleware.Logger,
    OmApiClient.Middleware.Telemetry,
    OmApiClient.Middleware.Retry,
    {OmApiClient.Middleware.RateLimit, limit: 100, window: :minute}
  ]
```

Custom middleware:

```elixir
defmodule MyMiddleware do
  @behaviour OmApiClient.Middleware

  def call(request, next, opts) do
    request
    |> add_header("X-Request-ID", generate_id())
    |> next.()
  end
end
```

## Response Handling

```elixir
case MyApp.API.get("/resource") do
  {:ok, %{status: 200, body: body}} ->
    {:ok, body}
  {:ok, %{status: 404}} ->
    {:error, :not_found}
  {:ok, %{status: status}} ->
    {:error, {:http_error, status}}
  {:error, reason} ->
    {:error, reason}
end
```

## Telemetry Events

- `[:om_api_client, :request, :start]`
- `[:om_api_client, :request, :stop]`
- `[:om_api_client, :request, :exception]`

## License

MIT
