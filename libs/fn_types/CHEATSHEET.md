# FnTypes Cheatsheet

> Functional programming types for Elixir. For full docs, see `README.md`.

## Setup

```elixir
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Validation, Guards, Error, Timing, Retry, Lens, NonEmptyList}
import FnTypes.Guards
```

---

## Result

```elixir
# Create
Result.ok(value)
Result.error(reason)
Result.from_nilable(value, :not_found)
Result.try_with(fn -> dangerous() end)

# Check
Result.ok?(result)
Result.error?(result)

# Transform
Result.map(result, &String.upcase/1)           # transform ok value
Result.map_error(result, &format_error/1)       # transform error
Result.bimap(result, on_ok: &up/1, on_error: &fmt/1)

# Chain
Result.and_then(result, &process/1)             # monadic bind
Result.or_else(result, &recover/1)              # error recovery

# Extract
Result.unwrap!(result)                          # value or raise
Result.unwrap_or(result, default)               # value or default
Result.unwrap_or_else(result, fn _ -> calc() end)

# Collections
Result.collect([{:ok, 1}, {:ok, 2}])            #=> {:ok, [1, 2]}
Result.collect([{:ok, 1}, {:error, :x}])         #=> {:error, :x}
Result.traverse(list, &process/1)               # map + collect
Result.partition(results)                        #=> {oks, errors}
Result.cat_ok(results)                           #=> [ok_values]

# Combine
Result.combine(r1, r2)                          #=> {:ok, {v1, v2}}
Result.combine_with(r1, r2, &merge/2)
Result.flatten({:ok, {:ok, value}})             #=> {:ok, value}

# Conversion
Result.to_bool(result)                          #=> true | false
Result.to_option(result)                        #=> value | nil

# Side effects
Result.tap(result, &log/1)                      # tap ok value
Result.tap_error(result, &report/1)             # tap error

# Error context
Result.wrap_error(result, :step_name)
Result.normalize_error(result, context: "fetch")
```

---

## Maybe

```elixir
# Create
Maybe.some(value)
Maybe.none()
Maybe.from_nilable(value)                       # nil -> :none
Maybe.from_result({:ok, v})                     #=> {:some, v}
Maybe.from_string("")                           #=> :none
Maybe.from_list([])                             #=> :none

# Check
Maybe.some?(maybe)
Maybe.none?(maybe)

# Transform
Maybe.map(maybe, &String.upcase/1)
Maybe.filter(maybe, &(&1 > 0))
Maybe.reject(maybe, &(&1 == 0))

# Chain
Maybe.and_then(maybe, &lookup/1)
Maybe.or_else({:some, alt})                     # fallback

# Extract
Maybe.unwrap!(maybe)                            # value or raise
Maybe.unwrap_or(maybe, default)
Maybe.to_nilable(maybe)                         #=> value | nil
Maybe.to_result(maybe, :not_found)              #=> Result

# Collections
Maybe.collect([{:some, 1}, {:some, 2}])          #=> {:some, [1, 2]}
Maybe.cat_somes(list)                            #=> [values]
Maybe.first_some([fn -> m1 end, fn -> m2 end])   # first some wins

# Combine
Maybe.combine(m1, m2)                           #=> {:some, {v1, v2}}
Maybe.zip_with(m1, m2, &merge/2)

# Safe access
Maybe.get(map, :key)                            #=> {:some, v} | :none
Maybe.fetch_path(map, [:a, :b, :c])             #=> {:some, v} | :none

# Conditional
Maybe.when_true(condition, value)               #=> {:some, v} | :none
```

---

## Pipeline

```elixir
# Create
Pipeline.new(%{user_id: 123})

# Steps
|> Pipeline.step(:validate, fn ctx -> {:ok, %{valid: true}} end)
|> Pipeline.step(:create, fn ctx -> {:ok, %{user: user}} end)
|> Pipeline.assign(:flag, true)                  # direct assign
|> Pipeline.transform(:user, &enrich/1)          # transform key
|> Pipeline.tap(:log, &log_step/1)               # side effect
|> Pipeline.validate(:check, &valid?/1)          # guard step

# Conditional
|> Pipeline.step_if(:notify, &should_notify?/1, &send_notification/1)
|> Pipeline.branch(:path, &admin?/1, &admin_flow/1, &user_flow/1)

# Retry
|> Pipeline.step_with_retry(:api_call, &call_api/1, max_attempts: 3)

# Parallel
|> Pipeline.parallel(:fetch, [
  {:user, &fetch_user/1},
  {:orders, &fetch_orders/1}
])

# Transaction
|> Pipeline.transaction(:db_ops, &do_db_work/1)

# Execute
|> Pipeline.run()                                #=> {:ok, context} | {:error, reason}
|> Pipeline.run!()                               # raises on error
|> Pipeline.run_with_rollback()                  # auto-rollback on failure
|> Pipeline.run_with_timeout(30_000)

# Composition
Pipeline.compose(pipeline1, pipeline2)
segment = Pipeline.segment(mini_pipeline)
Pipeline.include(pipeline, segment)

# Debug
Pipeline.dry_run(pipeline)                       #=> step names
Pipeline.completed_steps(pipeline)
Pipeline.pending_steps(pipeline)
```

---

## AsyncResult

```elixir
# Parallel (fail-fast)
AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
], timeout: 5_000)
#=> {:ok, [user, orders]} | {:error, first_error}

# Parallel map
AsyncResult.parallel_map(ids, &fetch/1, max_concurrency: 10)

# Race (first success)
AsyncResult.race([
  fn -> Cache.get(key) end,
  fn -> DB.get(key) end
], timeout: 3_000)

# Hedge (backup after delay)
AsyncResult.hedge(fn -> primary() end, fn -> backup() end, delay: 100)

# Retry
AsyncResult.retry(fn -> api_call() end,
  max_attempts: 3, initial_delay: 100, max_delay: 5_000,
  backoff: :exponential, jitter: 0.25
)

# Fire and forget
AsyncResult.fire_and_forget([fn -> log() end, fn -> metric() end])

# Lazy
lazy = AsyncResult.lazy(fn -> expensive() end)
AsyncResult.run_lazy(lazy)

# Streaming
AsyncResult.stream(items, &process/1, max_concurrency: 5)
```

---

## Validation

```elixir
# Single value
Validation.validate("test@email.com", [Validation.required(), Validation.format(:email)])

# Context-based (accumulates ALL errors)
Validation.new(%{name: "Jo", email: "bad", age: -1})
|> Validation.field(:name, [Validation.required(), Validation.min_length(3)])
|> Validation.field(:email, [Validation.required(), Validation.format(:email)])
|> Validation.field(:age, [Validation.required(), Validation.min(0)])
|> Validation.to_result()
#=> {:error, %{name: ["min length 3"], email: ["invalid email"], age: ["min 0"]}}

# Built-in validators
Validation.required()
Validation.type(:string | :integer | :float | :boolean | :atom)
Validation.min_length(n)
Validation.max_length(n)
Validation.format(:email | :url | ~r/pattern/)
Validation.min(n)
Validation.max(n)
Validation.between(min, max)
Validation.in_list([:a, :b])
Validation.not_in_list([:x])

# Combine
Validation.all([v1, v2, v3])                     # all must pass
Validation.map2(v1, v2, &build_struct/2)          # combine 2
```

---

## Guards

```elixir
import FnTypes.Guards

# In function heads and guards
def process(result) when is_ok(result), do: ...
def process(result) when is_error(result), do: ...
def handle(maybe) when is_some(maybe), do: ...
def handle(maybe) when is_none(maybe), do: ...
def check(r) when is_result(r), do: ...

# Pattern matching macros
case result do
  ok(value) -> value
  error(reason) -> handle(reason)
end

case maybe do
  some(value) -> value
  none() -> default
end

# Utility guards
when is_non_empty_string(s)
when is_non_empty_list(l)
when is_non_empty_map(m)
when is_positive_integer(n)
when is_non_negative_integer(n)
```

---

## Error

```elixir
# Create
Error.new(:not_found, "User not found", context: %{id: 123})
Error.normalize(any_error, context: "fetch_user")

# Error types
:validation | :not_found | :unauthorized | :forbidden | :conflict
:rate_limited | :internal | :external | :timeout | :network | :business

# Enrich
Error.with_context(error, %{step: :payment})
Error.with_details(error, %{amount: 100})
Error.with_step(error, :charge)

# Wrap function
Error.wrap(fn -> risky() end, context: "risky_op")
```

---

## Timing

```elixir
# Measure
{result, duration} = Timing.measure(fn -> work() end)
ms = Timing.measure!(fn -> work() end)           # just milliseconds

# Safe (captures exceptions)
# {:ok, result, duration} on success
# {:error, kind, reason, stacktrace, duration} on failure
Timing.measure_safe(fn -> work() end)

# Conditional
Timing.timed_if_slow(fn -> work() end, 1000, fn ms -> Logger.warn("slow: #{ms}ms") end)

# Benchmark
stats = Timing.benchmark(fn -> work() end, iterations: 1000)
# => %{min: _, max: _, mean: _, median: _, p95: _, p99: _}

# Format
Timing.format(duration)                          #=> "1.23ms"
```

---

## Retry

```elixir
# Basic
Retry.execute(fn -> api_call() end, max_attempts: 3)

# With strategy
Retry.execute(fn -> api_call() end,
  max_attempts: 5,
  backoff: :exponential,    # :exponential | :linear | :fixed | :decorrelated
  initial_delay: 100,
  max_delay: 30_000,
  jitter: 0.25,
  when: fn {:error, reason} -> reason in [:timeout, :unavailable] end,
  on_retry: fn attempt, delay, error -> Logger.info("retry #{attempt}") end
)

# Transaction retry
Retry.transaction(fn -> Repo.transaction(fn -> ... end) end, max_attempts: 3)
```

---

## Lens

```elixir
# Create
lens = Lens.key(:name)
nested = Lens.path([:address, :city])
idx = Lens.at(0)

# Use
Lens.get(lens, data)                            #=> value
Lens.set(lens, data, new_value)                  #=> updated_data
Lens.update(lens, data, &String.upcase/1)

# Compose
address_city = Lens.key(:address) |> Lens.compose(Lens.key(:city))
# or
address_city = Lens.key(:address) ~> Lens.key(:city)

# Safe access
Lens.get_maybe(lens, data)                       #=> {:some, v} | :none
Lens.get_result(lens, data)                      #=> {:ok, v} | {:error, _}
```

---

## NonEmptyList

```elixir
# Create (guaranteed non-empty)
nel = NonEmptyList.new(1, [2, 3])
nel = NonEmptyList.singleton(42)
{:ok, nel} = NonEmptyList.from_list([1, 2, 3])
nel = NonEmptyList.from_list!([1, 2, 3])

# Access (head is always safe)
NonEmptyList.head(nel)                           #=> 1 (guaranteed)
NonEmptyList.tail(nel)                           #=> [2, 3]
NonEmptyList.last(nel)                           #=> 3

# Transform
NonEmptyList.map(nel, &(&1 * 2))
NonEmptyList.reduce(nel, &+/2)                   # no initial needed
NonEmptyList.append(nel1, nel2)

# Convert
NonEmptyList.to_list(nel)                        #=> [1, 2, 3]
```

---

## Protocols

```elixir
# Normalizable - normalize errors to FnTypes.Error
FnTypes.Protocols.Normalizable.normalize(changeset, [])
FnTypes.Protocols.Normalizable.normalize(postgrex_error, [])

# Recoverable - recovery strategy for errors
FnTypes.Protocols.Recoverable.recoverable?(error)    #=> true
FnTypes.Protocols.Recoverable.strategy(error)         #=> :retry_with_backoff
FnTypes.Protocols.Recoverable.max_attempts(error)     #=> 3

# Identifiable - entity identity
FnTypes.Protocols.Identifiable.entity_type(user)      #=> :user
FnTypes.Protocols.Identifiable.id(user)               #=> "uuid..."
FnTypes.Protocols.Identifiable.identity(user)          #=> {:user, "uuid..."}
```

---

## When to Use What

| Scenario | Use |
|----------|-----|
| Fallible operation | `Result` |
| Optional/nullable value | `Maybe` |
| Multi-step with context | `Pipeline` |
| Concurrent tasks (fail-fast) | `AsyncResult.parallel` |
| First success from multiple sources | `AsyncResult.race` |
| Retry with backoff | `Retry.execute` or `AsyncResult.retry` |
| Collect ALL validation errors | `Validation` |
| Guard clauses | `Guards` |
| Nested data access | `Lens` |
| Guaranteed non-empty collection | `NonEmptyList` |
| Measure execution time | `Timing` |
| Structured errors | `Error` |
| Normalize external errors | `Normalizable` protocol |
| Recovery strategy for errors | `Recoverable` protocol |

---

## Common Patterns

```elixir
# Pipeline + AsyncResult
Pipeline.new(%{user_id: id})
|> Pipeline.step(:user, fn ctx -> fetch_user(ctx.user_id) end)
|> Pipeline.parallel(:data, [
  {:orders, fn ctx -> fetch_orders(ctx.user.id) end},
  {:prefs, fn ctx -> fetch_preferences(ctx.user.id) end}
])
|> Pipeline.step(:enrich, &enrich_user/1)
|> Pipeline.run()

# Result chain
user_id
|> fetch_user()
|> Result.and_then(&validate_active/1)
|> Result.and_then(&authorize/1)
|> Result.map(&serialize/1)
|> Result.unwrap_or(%{error: "failed"})

# Maybe chain
params
|> Maybe.from_nilable()
|> Maybe.and_then(&Map.fetch(&1, :email))
|> Maybe.filter(&valid_email?/1)
|> Maybe.to_result(:missing_email)
```
