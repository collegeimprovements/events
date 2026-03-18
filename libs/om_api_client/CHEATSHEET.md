# OmApiClient Cheatsheet

> Production HTTP API client with resilience and observability. For full docs, see `README.md`.

## Define a Client

```elixir
defmodule MyApp.Clients.GitHub do
  use OmApiClient,
    base_url: "https://api.github.com",
    auth: :bearer,                     # :bearer | :basic | :api_key | :none
    content_type: :json,               # :json | :form
    retry: [max_attempts: 3],
    circuit_breaker: :github,
    telemetry: true

  def get_user(username, config) do
    new(config) |> get("/users/#{username}")
  end

  def create_repo(params, config) do
    new(config) |> post("/user/repos", params)
  end

  def list_repos(username, config, opts \\ []) do
    new(config) |> get("/users/#{username}/repos", query: opts)
  end
end
```

---

## Usage

```elixir
config = %{api_key: "ghp_xxxx"}

case MyApp.Clients.GitHub.get_user("octocat", config) do
  {:ok, %{status: 200, body: user}} -> {:ok, user}
  {:ok, %{status: 404}} -> {:error, :not_found}
  {:ok, %{status: s}} when s >= 500 -> {:error, :server_error}
  {:error, reason} -> {:error, reason}
end
```

---

## Request Building

```elixir
alias OmApiClient.Request

Request.new(config)
|> Request.method(:post)
|> Request.path("/v1/customers")
|> Request.json(%{email: "user@example.com"})
|> Request.header("idempotency-key", key)
|> Request.query(limit: 50, offset: 0)
|> Request.timeout(30_000)
|> Request.metadata(:operation, :create_customer)
```

---

## HTTP Methods

```elixir
new(config) |> get("/users", query: [page: 1])
new(config) |> post("/users", %{name: "John"})
new(config) |> put("/users/123", %{name: "Updated"})
new(config) |> patch("/users/123", %{name: "Patched"})
new(config) |> delete("/users/123")
```

---

## Body Formats

```elixir
Request.json(req, %{email: "user@example.com"})   # JSON
Request.form(req, email: "user@example.com")       # form-encoded
Request.multipart(req, [{:file, path, filename: "doc.pdf"}, {"field", "value"}])
Request.body(req, <<binary>>)                      # raw
```

---

## Client Options

| Option | Default | Description |
|--------|---------|-------------|
| `base_url` | required | Base URL |
| `auth` | `:none` | `:bearer`, `:basic`, `:api_key`, `:none` |
| `content_type` | `:json` | `:json`, `:form` |
| `retry` | `false` | `true` or `[max_attempts: 3, base_delay: 1000]` |
| `circuit_breaker` | `nil` | Circuit breaker name (atom) |
| `rate_limiter` | `nil` | Rate limiter name (atom) |
| `telemetry` | `false` | Enable telemetry events |
| `telemetry_prefix` | auto | Custom prefix |

---

## Telemetry Events

```
[:om_api_client, :request, :start | :stop | :exception]
```

Measurements: `duration`, `status`
Metadata: `method`, `path`, `base_url`, `status`
