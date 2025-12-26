# FnDecorator

A comprehensive decorator library for Elixir with caching, telemetry, debugging, types, and more.

## Installation

```elixir
def deps do
  [{:fn_decorator, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.Users do
  use FnDecorator

  @decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
  @decorate telemetry_span([:my_app, :users, :get])
  @decorate log_if_slow(threshold: 1000)
  def get_user(id) do
    Repo.get(User, id)
  end

  @decorate cache_evict(cache: MyCache, keys: [{User, id}])
  def delete_user(id) do
    Repo.delete(User, id)
  end

  @decorate returns_result(ok: User.t(), error: :atom)
  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end
end
```

## Available Decorators

### Caching

```elixir
@decorate cacheable(cache: MyCache, key: id, ttl: 3600)
@decorate cache_put(cache: MyCache, keys: [{User, user.id}])
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
```

### Telemetry & Logging

```elixir
@decorate telemetry_span([:app, :users, :get])
@decorate log_call(level: :info)
@decorate log_if_slow(threshold: 1000)
@decorate otel_span("user.get")
```

### Type Enforcement

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
@decorate returns_maybe(some: User.t())
@decorate returns_bang(error: RuntimeError)
@decorate normalize_result()
```

### Debugging (Dev/Test)

```elixir
@decorate debug(label: "user_lookup")
@decorate inspect(args: true, result: true)
@decorate pry(when: &match?({:error, _}, &1))
```

### Performance

```elixir
@decorate benchmark(iterations: 1000)
@decorate measure(emit: [:my_app, :timing])
```

### Purity

```elixir
@decorate pure()           # Verify no side effects
@decorate deterministic()  # Same input = same output
@decorate idempotent()     # Multiple calls = same result
```

### Security

```elixir
@decorate role_required([:admin])
@decorate rate_limit(limit: 100, window: :minute)
@decorate audit_log(action: :user_delete)
```

## Configuration

```elixir
# config/config.exs
config :fn_decorator, FnDecorator.Telemetry,
  telemetry_prefix: [:my_app],
  repo: MyApp.Repo
```

## License

MIT
