# FnDecorator Cheatsheet

> Quick-reference card for all 40+ decorators. For full docs, see `README.md`.

## Setup

```elixir
defmodule MyApp.Users do
  use FnDecorator
  alias FnDecorator.Caching.Presets
end
```

---

## Caching

```elixir
# Read-through — use presets
@decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
@decorate cacheable(Presets.high_availability(store: [cache: MyCache, key: {User, id}]))
@decorate cacheable(Presets.always_fresh(store: [cache: MyCache, key: :flags]))
@decorate cacheable(Presets.external_api(store: [cache: MyCache, key: {:weather, city}]))
@decorate cacheable(Presets.expensive(store: [cache: MyCache, key: {:report, date}]))
@decorate cacheable(Presets.session(store: [cache: MyCache, key: {:session, sid}]))
@decorate cacheable(Presets.reference_data(store: [cache: MyCache, key: :countries]))

# Read-through — full control
@decorate cacheable(
  store: [cache: MyCache, key: {User, id}, ttl: :timer.minutes(5), only_if: &match?({:ok, _}, &1)],
  serve_stale: [ttl: :timer.hours(1)],
  refresh: [on: :stale_access],
  prevent_thunder_herd: [max_wait: 5_000, lock_ttl: 30_000, on_timeout: :serve_stale],
  fallback: [on_error: :serve_stale]
)

# Write-through
@decorate cache_put(cache: MyCache, keys: [{User, user.id}])

# Invalidate
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
@decorate cache_evict(cache: MyCache, tags: [:users])
@decorate cache_evict(cache: MyCache, all_entries: true)
@decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
```

### Preset Quick Reference

| Preset | Fresh | Stale | Wait | Timeout | Use Case |
|--------|-------|-------|------|---------|----------|
| `minimal` | — | — | default | — | Full control |
| `database` | 30s | 5m | 2s | stale | CRUD reads |
| `session` | 1m | — | 1s | error | Auth/session |
| `high_availability` | 1m | 1h | 5s | stale | User-facing reads |
| `always_fresh` | 10s | — | 5s | error | Feature flags, config |
| `external_api` | 5m | 1h | 30s | stale | Third-party APIs |
| `expensive` | 1h | 24h | 60s | stale | Reports, ML |
| `reference_data` | 1h | 24h | default | — | Lookup tables |

---

## Types

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
@decorate returns_maybe(type: User.t())
@decorate returns_maybe(type: String.t(), default: "Unknown")
@decorate returns_bang(type: User.t())
@decorate returns_struct(type: User)
@decorate returns_struct(type: User, nullable: true)
@decorate returns_list(of: User.t(), min_length: 1, max_length: 100)
@decorate returns_union(types: [User.t(), Organization.t(), nil])
@decorate returns_pipeline(ok: User.t(), error: :atom)
@decorate normalize_result(nil_is_error: true, wrap_exceptions: true)
@decorate normalize_result(false_is_error: true, error_mapper: &format/1)
```

---

## Telemetry & Logging

```elixir
@decorate telemetry_span([:app, :users, :get])
@decorate telemetry_span([:app, :process], include: [:id], metadata: %{source: :api})
@decorate otel_span("users.create")
@decorate otel_span("payment.process", include: [:amount], attributes: %{currency: "USD"})
@decorate log_call(level: :info)
@decorate log_call(level: :debug, message: "Processing order")
@decorate log_context([:user_id, :request_id])
@decorate log_if_slow(threshold: 1000)
@decorate log_if_slow(threshold: 500, level: :error, message: "Critical path slow")
@decorate log_query(slow_threshold: 500)
@decorate log_remote(service: WeatherAPI, async: true)
@decorate capture_errors(reporter: Sentry)
@decorate track_memory(threshold: 10_000_000)
@decorate benchmark(iterations: 1000, warmup: 10, memory: true)
@decorate measure(unit: :microsecond, label: "DB Query")
```

---

## Security

```elixir
@decorate role_required(roles: [:admin])
@decorate role_required(roles: [:admin, :mod], on_error: :return_error)
@decorate role_required(roles: [:owner], check_fn: fn user, roles -> user.role in roles end)
@decorate rate_limit(max: 100, window: :minute)
@decorate rate_limit(max: 10, window: :hour, by: :user_id, on_error: :return_error)
@decorate audit_log(level: :critical, fields: [:user_id, :amount])
@decorate audit_log(level: :info, include_result: true, store: ComplianceLog)
```

---

## Validation

```elixir
@decorate validate_schema(schema: UserSchema, on_error: :return_error)
@decorate coerce_types(args: [id: :integer, active: :boolean])
@decorate serialize(format: :json, only: [:id, :name, :email])
@decorate contract(pre: fn args -> length(args) > 0 end, post: fn r -> match?({:ok, _}, r) end)
```

---

## Debugging (auto-disabled in prod)

```elixir
@decorate debug()
@decorate debug(label: "User Creation")
@decorate inspect(what: :args)
@decorate inspect(what: :result, label: "Query Result")
@decorate inspect(what: :both, opts: [pretty: true])
@decorate pry()
@decorate pry(condition: fn result -> match?({:error, _}, result) end)
@decorate trace_vars(vars: [:user, :order])
```

---

## Tracing (auto-disabled in prod)

```elixir
@decorate trace_calls(depth: 3, format: :tree)
@decorate trace_modules(filter: ~r/MyApp/, exclude_stdlib: true)
@decorate trace_dependencies(type: :external, format: :graph)
```

---

## Purity

```elixir
@decorate pure()
@decorate pure(verify: true, samples: 10, strict: true)
@decorate deterministic(samples: 5, on_failure: :raise)
@decorate idempotent(calls: 3, compare: :deep_equality)
@decorate memoizable(verify: true)
```

---

## Testing

```elixir
@decorate with_fixtures(fixtures: [:user, :org], cleanup: true)
@decorate sample_data(generator: &Faker.Internet.email/0, count: 5)
@decorate timeout_test(timeout: 1000, on_timeout: :return_error)
@decorate mock(module: HTTPClient, functions: [get: fn _ -> {:ok, %{}} end])
```

---

## Composition

```elixir
@decorate pipe_through([&validate/1, &transform/1, &persist/1])
@decorate around(fn body, args -> with_retries(fn -> body.(args) end) end)
@decorate compose([{:telemetry_span, [[:app, :op]]}, {:log_if_slow, [threshold: 1000]}])
```

---

## Decorator Order

Applied **bottom to top** (innermost first):

```elixir
@decorate telemetry_span(...)   # 3rd — outermost (captures everything)
@decorate cacheable(...)        # 2nd — middle (avoid expensive work)
@decorate returns_result(...)   # 1st — innermost (validate return)
def get_user(id), do: ...
```

**Recommended stacking:**

```
Outermost → telemetry_span, log_call, capture_errors
Middle    → cacheable, rate_limit, role_required
Inner     → returns_result, normalize_result, validate_schema
```

---

## Telemetry Helpers (non-decorator)

```elixir
use FnDecorator.Telemetry.Helpers

span [:app, :service, :fetch], %{id: id} do
  do_fetch(id)
end

emit [:app, :event], %{}, %{count: 42}

{time_ms, result} = timed(fn -> do_work() end)
```

---

## Custom Cache Presets

```elixir
defmodule MyApp.CachePresets do
  alias FnDecorator.Caching.Presets

  def microservice(opts) do
    Presets.merge([
      store: [ttl: :timer.seconds(30)],
      serve_stale: [ttl: :timer.minutes(5)],
      refresh: [on: :stale_access],
      prevent_thunder_herd: [max_wait: 5_000]
    ], opts)
  end
end

# Usage
@decorate cacheable(MyApp.CachePresets.microservice(store: [cache: MyCache, key: {User, id}]))
```

---

## Config

```elixir
# config/config.exs
config :fn_decorator,
  telemetry_enabled: true,
  log_level: :info

config :fn_decorator, FnDecorator.Telemetry,
  telemetry_prefix: [:my_app],
  repo: MyApp.Repo

# Distributed lock adapter (optional)
config :fn_decorator, :lock_adapter, MyApp.RedisLock
```
