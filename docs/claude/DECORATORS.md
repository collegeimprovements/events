# Decorators Reference

> **Quick reference for type contracts, caching, telemetry, and validation.**
> For complete reference, see `docs/DECORATOR_REFERENCE.md`.

## Getting Started

```elixir
defmodule MyApp.Users do
  use Events.Infra.Decorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:my_app, :users, :get])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

---

## Type Decorators

### returns_result

Validates `{:ok, value} | {:error, reason}` returns.

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
def find_user(id), do: ...

@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
def create_user(attrs), do: ...
```

### returns_maybe

Validates `value | nil` returns.

```elixir
@decorate returns_maybe(User.t())
def find_user_by_email(email), do: Repo.get_by(User, email: email)
```

### returns_bang

Unwraps `{:ok, value}` or raises on `{:error, _}`.

```elixir
@decorate returns_bang(User.t())
def get_user!(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
# Returns user directly, raises on error
```

### returns_struct

Validates struct type.

```elixir
@decorate returns_struct(User)
def build_user(attrs), do: %User{} |> struct(attrs)
```

### returns_list

Validates list element types.

```elixir
@decorate returns_list(of: User.t())
def list_users, do: Repo.all(User)
```

### normalize_result

Converts various return formats to result tuples.

```elixir
@decorate normalize_result(
  nil_is_error: true,
  wrap_exceptions: true,
  error_mapper: &format_api_error/1
)
def fetch_external(id), do: ExternalAPI.get(id)
```

---

## Caching Decorators

### cacheable

Caches function results.

```elixir
@decorate cacheable(
  cache: MyApp.Cache,
  key: {:user, id},
  ttl: :timer.minutes(5)
)
def get_user(id), do: Repo.get(User, id)
```

### cache_put

Updates cache on function call.

```elixir
@decorate cache_put(cache: MyApp.Cache, key: {:user, user.id})
def update_user(user, attrs), do: ...
```

### cache_evict

Evicts cache entry.

```elixir
@decorate cache_evict(cache: MyApp.Cache, key: {:user, id})
def delete_user(id), do: ...
```

---

## Telemetry Decorators

### telemetry_span

Emits telemetry events.

```elixir
@decorate telemetry_span([:my_app, :users, :create])
def create_user(attrs), do: ...

# Emits:
# [:my_app, :users, :create, :start]
# [:my_app, :users, :create, :stop]
# [:my_app, :users, :create, :exception]
```

### otel_span

OpenTelemetry span.

```elixir
@decorate otel_span("users.create", attributes: [user_type: :standard])
def create_user(attrs), do: ...
```

### log_call

Logs function calls.

```elixir
@decorate log_call(level: :info, include_args: true)
def process_order(order), do: ...
```

### log_if_slow

Logs if execution exceeds threshold.

```elixir
@decorate log_if_slow(threshold_ms: 100, level: :warning)
def heavy_computation(data), do: ...
```

### capture_errors

Captures and reports errors.

```elixir
@decorate capture_errors(reporter: Sentry)
def risky_operation(data), do: ...
```

---

## Validation Decorators

### validate_schema

Validates input against schema.

```elixir
@decorate validate_schema(schema: UserSchema)
def create_user(params), do: ...
```

### coerce_types

Coerces input types.

```elixir
@decorate coerce_types(id: :integer, active: :boolean)
def get_user(id, active), do: ...
```

### contract

Pre/post condition contracts.

```elixir
@decorate contract(
  pre: fn args -> length(args) > 0 end,
  post: fn result -> match?({:ok, _}, result) end
)
def process(items), do: ...
```

---

## Security Decorators

### role_required

Requires specific role.

```elixir
@decorate role_required(:admin)
def admin_action(ctx), do: ...
```

### rate_limit

Rate limits function calls.

```elixir
@decorate rate_limit(max: 100, period: :timer.minutes(1))
def api_call(params), do: ...
```

### audit_log

Logs action for audit trail.

```elixir
@decorate audit_log(action: :user_update, resource: :user)
def update_user(user, attrs), do: ...
```

---

## Purity Decorators

### pure

Marks function as pure (no side effects).

```elixir
@decorate pure()
def calculate_total(items), do: Enum.sum(items)
```

### deterministic

Marks function as deterministic.

```elixir
@decorate deterministic()
def hash_password(password), do: Bcrypt.hash_pwd_salt(password)
```

### idempotent

Marks function as idempotent.

```elixir
@decorate idempotent()
def set_status(record, status), do: ...
```

---

## Stacking Decorators

Combine decorators for comprehensive behavior:

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
@decorate telemetry_span([:my_app, :users, :create])
@decorate validate_schema(schema: UserSchema)
@decorate audit_log(action: :user_create)
def create_user(params) do
  # Validates params against schema
  # Emits telemetry
  # Logs audit trail
  # Validates return type
  ...
end
```

---

## Quick Reference

| Category | Decorators |
|----------|-----------|
| **Types** | `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `normalize_result` |
| **Caching** | `cacheable`, `cache_put`, `cache_evict` |
| **Telemetry** | `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `log_query`, `capture_errors`, `measure`, `benchmark`, `track_memory` |
| **Validation** | `validate_schema`, `coerce_types`, `serialize`, `contract` |
| **Security** | `role_required`, `rate_limit`, `audit_log` |
| **Debugging** | `debug`, `inspect`, `pry` (dev only) |
| **Purity** | `pure`, `deterministic`, `idempotent`, `memoizable` |
