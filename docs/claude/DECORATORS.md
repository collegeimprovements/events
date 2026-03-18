# Decorators Reference

> Quick reference for all FnDecorator decorators.
> For full documentation with examples, see `libs/fn_decorator/README.md`.
> For cheatsheet, see `libs/fn_decorator/CHEATSHEET.md`.

## Setup

```elixir
# Standard decorators
use FnDecorator

# Application decorators (includes standard + step, scheduled, etc.)
use Events.Extensions.Decorator
```

---

## Caching

### Presets (Recommended)

```elixir
alias FnDecorator.Caching.Presets

@decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
@decorate cacheable(Presets.high_availability(store: [cache: MyCache, key: {User, id}]))
@decorate cacheable(Presets.always_fresh(store: [cache: MyCache, key: :flags]))
@decorate cacheable(Presets.external_api(store: [cache: MyCache, key: {:weather, city}]))
@decorate cacheable(Presets.expensive(store: [cache: MyCache, key: {:report, date}]))
@decorate cacheable(Presets.session(store: [cache: MyCache, key: {:session, sid}]))
@decorate cacheable(Presets.reference_data(store: [cache: MyCache, key: :countries]))
```

| Preset | Fresh | Stale | Wait | Timeout | Use Case |
|--------|-------|-------|------|---------|----------|
| `minimal` | — | — | default | — | Full control |
| `database` | 30s | 5m | 2s | stale | CRUD reads |
| `session` | 1m | — | 1s | error | Auth/session |
| `high_availability` | 1m | 1h | 5s | stale | User-facing reads |
| `always_fresh` | 10s | — | 5s | error | Feature flags |
| `external_api` | 5m | 1h | 30s | stale | Third-party APIs |
| `expensive` | 1h | 24h | 60s | stale | Reports, ML |
| `reference_data` | 1h | 24h | default | — | Lookup tables |

### Full cacheable API

```elixir
@decorate cacheable(
  store: [cache: Module, key: term, ttl: ms, only_if: fn/1, tags: [atom]],
  serve_stale: [ttl: ms],
  refresh: [on: :stale_access],
  prevent_thunder_herd: [max_wait: 5000, lock_ttl: 30000, on_timeout: :serve_stale],
  fallback: [on_error: :raise | :serve_stale | {:call, fn} | {:value, term}]
)
```

### Write-through & Invalidation

```elixir
@decorate cache_put(cache: MyCache, keys: [{User, user.id}])
@decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: fn {:ok, u} -> {true, u}; _ -> false end)
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
@decorate cache_evict(cache: MyCache, tags: [:users])
@decorate cache_evict(cache: MyCache, all_entries: true)
@decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
```

### Custom Presets

```elixir
defmodule MyApp.CachePresets do
  alias FnDecorator.Caching.Presets

  def microservice(opts) do
    Presets.merge([store: [ttl: :timer.seconds(30)], serve_stale: [ttl: :timer.minutes(5)],
                   refresh: [on: :stale_access], prevent_thunder_herd: [max_wait: 5_000]], opts)
  end
end
```

---

## Type Decorators

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
@decorate returns_result(ok: User.t(), error: Changeset.t(), validate: true, strict: true)
@decorate returns_maybe(type: User.t())
@decorate returns_maybe(type: String.t(), default: "Unknown")
@decorate returns_bang(type: User.t())
@decorate returns_bang(type: User.t(), on_error: :unwrap)
@decorate returns_struct(type: User)
@decorate returns_struct(type: User, nullable: true)
@decorate returns_list(of: User.t(), min_length: 1, max_length: 100)
@decorate returns_union(types: [User.t(), Organization.t(), nil])
@decorate returns_pipeline(ok: User.t(), error: :atom, chain: true)
```

### normalize_result

```elixir
@decorate normalize_result(nil_is_error: true)
@decorate normalize_result(wrap_exceptions: true)
@decorate normalize_result(false_is_error: true, error_mapper: &format/1, success_mapper: &clean/1)
@decorate normalize_result(nil_is_error: true, wrap_exceptions: true, error_patterns: [:invalid, :timeout])
```

---

## Telemetry & Logging

```elixir
@decorate telemetry_span([:app, :users, :get])
@decorate telemetry_span([:app, :op], include: [:id], metadata: %{source: :api})
@decorate otel_span("users.create")
@decorate otel_span("payment.process", include: [:amount], attributes: %{currency: "USD"})
@decorate log_call(level: :info)
@decorate log_call(level: :debug, message: "Starting task")
@decorate log_context([:user_id, :request_id])
@decorate log_if_slow(threshold: 1000)
@decorate log_if_slow(threshold: 500, level: :error, message: "Critical slow")
@decorate log_query(slow_threshold: 500)
@decorate log_query(level: :info, slow_level: :warning, include_query: true)
@decorate log_remote(service: WeatherAPI, async: true, metadata: %{})
@decorate capture_errors(reporter: Sentry)
@decorate capture_errors(reporter: Sentry, threshold: 3)
@decorate track_memory(threshold: 10_000_000)
@decorate benchmark(iterations: 1000, warmup: 10, format: :statistical, memory: true)
@decorate measure(unit: :microsecond, label: "DB Query", include_result: true)
```

### Telemetry Helpers (non-decorator)

```elixir
use FnDecorator.Telemetry.Helpers

span [:app, :fetch], %{id: id} do ... end
emit [:app, :event], %{}, %{count: 42}
{time_ms, result} = timed(fn -> work() end)
```

---

## Security

```elixir
@decorate role_required(roles: [:admin])
@decorate role_required(roles: [:admin, :mod], on_error: :return_error | :return_nil | :raise)
@decorate role_required(roles: [:owner], check_fn: fn user, roles -> user.role in roles end)
@decorate rate_limit(max: 100, window: :second | :minute | :hour | :day)
@decorate rate_limit(max: 10, window: :hour, by: :user_id | :ip | :global | :custom)
@decorate rate_limit(max: 50, window: :minute, by: :custom, key_fn: fn [conn | _] -> conn.remote_ip end)
@decorate rate_limit(max: 100, window: :minute, on_error: :raise | :return_error | :sleep, backend: Module)
@decorate audit_log(level: :info | :warning | :critical)
@decorate audit_log(level: :critical, fields: [:user_id, :amount], include_result: true, store: Module, async: true, metadata: %{})
```

---

## Validation

```elixir
@decorate validate_schema(schema: UserSchema, on_error: :raise | :return_error | :return_nil, coerce: true, strict: false)
@decorate coerce_types(args: [id: :integer, active: :boolean], on_error: :raise | :return_error | :keep_original)
@decorate serialize(format: :json | :map | :keyword | :binary, only: [:id, :name], except: [:password], rename: [inserted_at: :created_at], transform: fn/2)
@decorate contract(pre: fn/1 | [fn/1], post: fn/1 | [fn/1], invariant: fn/0, on_error: :raise | :warn | :return_error)
```

---

## Debugging (disabled in prod)

```elixir
@decorate debug()
@decorate debug(label: "User Creation")
@decorate inspect(what: :args | :result | :both | :all)
@decorate inspect(what: :result, label: "Query", opts: [pretty: true, width: 100])
@decorate pry()
@decorate pry(condition: fn result -> match?({:error, _}, result) end, before: true, after: true)
@decorate trace_vars(vars: [:user, :order])
```

---

## Tracing (disabled in prod)

```elixir
@decorate trace_calls(depth: 3, filter: ~r/MyApp/, exclude: [:log], format: :simple | :tree | :detailed)
@decorate trace_modules(filter: ~r/MyApp/, unique: true, exclude_stdlib: true)
@decorate trace_dependencies(type: :all | :external | :internal, format: :list | :tree | :graph)
```

---

## Purity

```elixir
@decorate pure()
@decorate pure(verify: true, strict: true, allow_io: false, samples: 10)
@decorate deterministic(samples: 5, on_failure: :raise | :warn | :ignore)
@decorate idempotent(calls: 3, compare: :equality | :deep_equality | :custom, comparator: fn/2)
@decorate memoizable(verify: true, warn_impure: true)
```

---

## Testing

```elixir
@decorate with_fixtures(fixtures: [:user, :org], cleanup: true)
@decorate sample_data(generator: Module | fn/0, count: 5)
@decorate timeout_test(timeout: 1000, on_timeout: :raise | :return_error | :return_nil)
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

## OpenTelemetry (Advanced)

```elixir
@decorate otel_span_advanced(name: "op", kind: :client, attributes: %{}, links: [], status: :ok)
@decorate propagate_context(headers: :http | :grpc)
@decorate with_baggage(entries: %{tenant: "acme"})
```

---

## Decorator Order

Applied **bottom to top** (innermost first):

```elixir
@decorate telemetry_span(...)   # 3rd — outermost
@decorate cacheable(...)        # 2nd — middle
@decorate returns_result(...)   # 1st — innermost
def get_user(id), do: ...
```

**Recommended stacking:**
```
Outermost → telemetry_span, log_call, capture_errors
Middle    → cacheable, rate_limit, role_required, audit_log
Inner     → returns_result, normalize_result, validate_schema
```

---

## Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:fn_decorator, :cache, :hit]` | `%{duration: ns}` | `%{key: _, status: :fresh/:stale}` |
| `[:fn_decorator, :cache, :miss]` | `%{duration: ns}` | `%{key: _}` |
| `[:fn_decorator, :cache, :fetch]` | `%{duration: ns}` | `%{key: _, success: bool}` |
| `[:fn_decorator, :cache, :refresh]` | `%{duration: ns}` | `%{key: _, success: bool, failures: int}` |
| `[:fn_decorator, :cache, :lock]` | `%{duration: ns}` | `%{key: _, result: :acquired/:timeout/:lock_freed}` |
| `event ++ [:start]` | `%{system_time: ns}` | from `telemetry_span` |
| `event ++ [:stop]` | `%{duration: ns}` | from `telemetry_span` |
| `event ++ [:exception]` | `%{duration: ns, kind, reason, stacktrace}` | from `telemetry_span` |

---

## Config

```elixir
config :fn_decorator, telemetry_enabled: true, log_level: :info
config :fn_decorator, FnDecorator.Telemetry, telemetry_prefix: [:my_app], repo: MyApp.Repo
config :fn_decorator, :lock_adapter, MyApp.RedisLock  # Optional distributed lock
```
