# FnTypes

Functional programming types for Elixir: Result, Maybe, Pipeline, AsyncResult, Validation, Guards, Timing, Retry, and more.

## Installation

```elixir
def deps do
  [{:fn_types, "~> 0.1.0"}]
end
```

---

## Why FnTypes?

Without functional types, error handling is inconsistent and verbose:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         IMPERATIVE APPROACH                                 │
│                                                                             │
│  # Inconsistent error handling                                              │
│  user = Repo.get(User, id)                                                  │
│  if user do                                                                 │
│    case validate(user) do                                                   │
│      :ok -> case send_email(user) do ...                                   │
│      {:error, e} -> handle_error(e)                                        │
│    end                                                                      │
│  else                                                                       │
│    handle_missing()                                                         │
│  end                                                                        │
│                                                                             │
│  # No composable parallel execution                                         │
│  # No accumulating validation                                               │
│  # No retry with backoff                                                    │
│  # No pipeline with rollback                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WITH FnTypes                                      │
│                                                                             │
│  # Result - composable error handling                                       │
│  fetch_user(id)                                                             │
│  |> Result.and_then(&validate/1)                                           │
│  |> Result.and_then(&send_email/1)                                         │
│  |> Result.map_error(&Error.normalize/1)                                   │
│                                                                             │
│  # Maybe - nil-safe operations                                              │
│  Maybe.from_nilable(user.email)                                            │
│  |> Maybe.map(&String.downcase/1)                                          │
│                                                                             │
│  # Pipeline - multi-step with rollback                                      │
│  Pipeline.new(ctx) |> Pipeline.step(:a, ...) |> Pipeline.run()            │
│                                                                             │
│  # AsyncResult - parallel with fail-fast/settle                            │
│  AsyncResult.parallel([fn -> a() end, fn -> b() end])                      │
│                                                                             │
│  # Validation - accumulate ALL errors                                       │
│  Validation.new(params) |> Validation.field(:email, [...])                 │
│                                                                             │
│  # Retry - exponential backoff                                              │
│  Retry.execute(fn -> api_call() end, max_attempts: 3)                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Benefits:**

| Module | Purpose | Key Feature |
|--------|---------|-------------|
| `Result` | Error handling | Monadic chaining |
| `Maybe` | Optional values | Nil safety |
| `Pipeline` | Multi-step workflows | Context + rollback |
| `AsyncResult` | Concurrent operations | Parallel, race, retry |
| `Validation` | Input validation | Error accumulation |
| `Guards` | Pattern matching | `is_ok/1`, `is_error/1` |
| `Timing` | Performance measurement | Duration + benchmarking |
| `Retry` | Fault tolerance | Backoff strategies |
| `Error` | Structured errors | Normalization |
| `Lens` | Nested data access | Functional lenses |

---

## Quick Start

```elixir
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Validation}

# Result - error handling
fetch_user(id)
|> Result.and_then(&validate/1)
|> Result.map(&format/1)

# Maybe - optional values
Maybe.from_nilable(user.email)
|> Maybe.map(&String.downcase/1)
|> Maybe.unwrap_or("no-email@example.com")

# Pipeline - multi-step workflow
Pipeline.new(%{user_id: id})
|> Pipeline.step(:fetch, &fetch_user/1)
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:notify, &send_notification/1)
|> Pipeline.run()

# AsyncResult - concurrent operations
AsyncResult.parallel([
  fn -> fetch_profile(id) end,
  fn -> fetch_orders(id) end,
  fn -> fetch_preferences(id) end
])

# Validation - error accumulation
Validation.new(params)
|> Validation.field(:email, [required(), format(:email)])
|> Validation.field(:age, [required(), min(18)])
|> Validation.to_result()
```

---

## Result

Monadic error handling with `{:ok, value}` and `{:error, reason}` tuples.

### Basic Operations

```elixir
alias FnTypes.Result

# Create results
Result.ok(42)           #=> {:ok, 42}
Result.error(:not_found) #=> {:error, :not_found}

# Type checking
Result.ok?({:ok, 42})    #=> true
Result.error?({:error, _}) #=> true
```

### Transformations

```elixir
# map - transform success value
{:ok, 5} |> Result.map(&(&1 * 2))
#=> {:ok, 10}

{:error, :not_found} |> Result.map(&(&1 * 2))
#=> {:error, :not_found}  # Unchanged

# map_error - transform error value
{:error, "not found"} |> Result.map_error(&String.upcase/1)
#=> {:error, "NOT FOUND"}
```

### Chaining

```elixir
# and_then - chain result-returning functions
{:ok, user}
|> Result.and_then(&validate/1)      # Returns {:ok, user} or {:error, reason}
|> Result.and_then(&send_email/1)
|> Result.and_then(&log_activity/1)

# or_else - handle errors
{:error, :not_found}
|> Result.or_else(fn _ -> {:ok, default_user()} end)
```

### Extraction

```elixir
# unwrap - with default
Result.unwrap({:ok, 42}, 0)     #=> 42
Result.unwrap({:error, _}, 0)   #=> 0

# unwrap! - raises on error
Result.unwrap!({:ok, 42})       #=> 42
Result.unwrap!({:error, :fail}) #=> raises ArgumentError
```

### Collection Operations

```elixir
results = [fetch_user(1), fetch_user(2), fetch_user(3)]

# collect - all must succeed
Result.collect(results)
#=> {:ok, [user1, user2, user3]} or {:error, first_error}

# partition - split successes and failures
{ok_values, errors} = Result.partition(results)

# traverse - map and collect
Result.traverse([1, 2, 3], &fetch_user/1)
#=> {:ok, [user1, user2, user3]}
```

### Error Recovery

```elixir
# recover_with - transform recoverable errors
Result.recover_with({:error, :timeout}, fn
  :timeout -> {:ok, :cached_value}
  other -> {:error, other}
end)

# try_recover - attempt recovery function
Result.try_recover({:error, :not_found}, fn _ ->
  fetch_from_backup()
end)
```

---

## Maybe

Safe handling of optional (nilable) values.

### Creation

```elixir
alias FnTypes.Maybe

# From nilable values
Maybe.from_nilable("hello")  #=> {:just, "hello"}
Maybe.from_nilable(nil)      #=> :nothing

# Explicit creation
Maybe.just(42)    #=> {:just, 42}
Maybe.nothing()   #=> :nothing
```

### Transformations

```elixir
# map - transform if present
{:just, "hello"} |> Maybe.map(&String.upcase/1)
#=> {:just, "HELLO"}

:nothing |> Maybe.map(&String.upcase/1)
#=> :nothing

# and_then - chain maybe-returning functions
Maybe.from_nilable(user)
|> Maybe.and_then(fn u -> Maybe.from_nilable(u.email) end)
|> Maybe.map(&String.downcase/1)
```

### Extraction

```elixir
# unwrap_or - with default
Maybe.unwrap_or({:just, 42}, 0)  #=> 42
Maybe.unwrap_or(:nothing, 0)     #=> 0

# unwrap_or_else - lazy default
Maybe.unwrap_or_else(:nothing, fn -> expensive_default() end)

# to_result - convert to Result
Maybe.to_result({:just, 42}, :not_found)     #=> {:ok, 42}
Maybe.to_result(:nothing, :not_found)         #=> {:error, :not_found}
```

### Common Patterns

```elixir
# Optional chaining
user = %{profile: %{avatar: nil}}

Maybe.from_nilable(user.profile)
|> Maybe.and_then(&Maybe.from_nilable(&1.avatar))
|> Maybe.map(&resize_image/1)
|> Maybe.unwrap_or(default_avatar())

# Filter
Maybe.from_nilable(score)
|> Maybe.filter(&(&1 > 0))
|> Maybe.map(&format_score/1)
```

---

## Pipeline

Multi-step workflows with context accumulation, branching, and rollback support.

### Basic Usage

```elixir
alias FnTypes.Pipeline

Pipeline.new(%{user_id: 123})
|> Pipeline.step(:fetch_user, fn ctx ->
  case Repo.get(User, ctx.user_id) do
    nil -> {:error, :not_found}
    user -> {:ok, %{user: user}}  # Merges into context
  end
end)
|> Pipeline.step(:validate, fn ctx ->
  validate_user(ctx.user)
end)
|> Pipeline.step(:send_email, fn ctx ->
  Mailer.send_welcome(ctx.user)
end)
|> Pipeline.run()
#=> {:ok, %{user_id: 123, user: %User{}, ...}}
#   or {:error, {:step_failed, :fetch_user, :not_found}}
```

### Conditional Steps

```elixir
Pipeline.new(ctx)
|> Pipeline.step(:notify, &send_notification/1,
  condition: fn ctx -> ctx.user.notifications_enabled end
)

# Or use then_if
|> Pipeline.then_if(
  fn ctx -> ctx.user.premium end,
  fn p -> Pipeline.step(p, :premium_feature, &apply_premium/1) end
)
```

### Parallel Steps

```elixir
Pipeline.new(ctx)
|> Pipeline.parallel([
  {:fetch_profile, &fetch_profile/1},
  {:fetch_orders, &fetch_orders/1},
  {:fetch_preferences, &fetch_preferences/1}
])
# All execute concurrently, results merged into context
|> Pipeline.step(:combine, fn ctx ->
  {:ok, %{summary: build_summary(ctx.profile, ctx.orders, ctx.preferences)}}
end)
|> Pipeline.run()
```

### Branching

```elixir
Pipeline.new(params)
|> Pipeline.step(:determine_type, fn ctx ->
  {:ok, %{payment_type: detect_payment_type(ctx)}}
end)
|> Pipeline.branch(:payment_type, %{
  credit_card: fn p ->
    p
    |> Pipeline.step(:validate_card, &validate_card/1)
    |> Pipeline.step(:charge_card, &charge_card/1)
  end,
  bank_transfer: fn p ->
    p
    |> Pipeline.step(:validate_bank, &validate_bank/1)
    |> Pipeline.step(:initiate_transfer, &initiate_transfer/1)
  end
})
|> Pipeline.run()
```

### Rollback on Error

```elixir
Pipeline.new(ctx)
|> Pipeline.step(:reserve_inventory, &reserve_inventory/1,
  rollback: fn ctx -> release_inventory(ctx.reservation) end
)
|> Pipeline.step(:charge_payment, &charge_payment/1,
  rollback: fn ctx -> refund_payment(ctx.payment) end
)
|> Pipeline.step(:create_order, &create_order/1)
|> Pipeline.run_with_rollback()
# If charge_payment fails, reserve_inventory rollback is called
```

### Checkpoint and Resume

```elixir
# Save checkpoint
Pipeline.new(ctx)
|> Pipeline.step(:step1, &step1/1)
|> Pipeline.checkpoint(:after_step1)  # Saves state
|> Pipeline.step(:step2, &step2/1)
|> Pipeline.run()

# Resume from checkpoint
Pipeline.resume(saved_state)
|> Pipeline.step(:step3, &step3/1)
|> Pipeline.run()
```

---

## AsyncResult

Concurrent operations with configurable error handling, timeouts, and retries.

### Parallel Execution

```elixir
alias FnTypes.AsyncResult

# Execute in parallel, fail on first error
AsyncResult.parallel([
  fn -> fetch_user(1) end,
  fn -> fetch_user(2) end,
  fn -> fetch_user(3) end
])
#=> {:ok, [user1, user2, user3]} or {:error, first_error}

# With options
AsyncResult.parallel(tasks,
  max_concurrency: 5,    # Limit concurrent tasks
  timeout: 5000,         # Per-task timeout
  ordered: true          # Preserve input order
)
```

### Settlement Mode

Collect all results instead of failing fast:

```elixir
AsyncResult.parallel(tasks, settle: true)
#=> %{
#     ok: [result1, result3],
#     errors: [error2],
#     results: [{:ok, result1}, {:error, error2}, {:ok, result3}]
#   }

# Work with settlements
alias AsyncResult.Settlement

Settlement.ok?(result)      #=> true if no errors
Settlement.failed?(result)  #=> true if any errors
{oks, errs} = Settlement.split(result)
```

### Map Over Items

```elixir
# Parallel map
AsyncResult.parallel_map([1, 2, 3], &fetch_user/1)
#=> {:ok, [user1, user2, user3]}

# With indexed settlement
AsyncResult.parallel_map(user_ids, &fetch_user/1, settle: true, indexed: true)
#=> %{ok: [{1, user1}, {3, user3}], errors: [{2, :not_found}], ...}
```

### Race (First Wins)

```elixir
# First successful result wins
AsyncResult.race([
  fn -> fetch_from_cache(key) end,
  fn -> fetch_from_db(key) end,
  fn -> fetch_from_api(key) end
])
#=> {:ok, first_success} or {:error, :all_failed}

# With timeout per task
AsyncResult.race(tasks, timeout: 1000)
```

### Hedged Requests

Start backup request if primary is slow:

```elixir
AsyncResult.hedge(
  fn -> primary_api_call() end,
  fn -> backup_api_call() end,
  delay: 100  # Start backup after 100ms if primary hasn't returned
)
```

### Retry with Backoff

```elixir
AsyncResult.retry(fn -> api_call() end,
  max_attempts: 3,
  initial_delay: 100,
  max_delay: 5000,
  backoff: :exponential,
  jitter: 0.25
)
```

### Explicit Task Handles

```elixir
# Start async task
handle = AsyncResult.async(fn -> expensive_operation() end)

# Do other work...

# Await result
{:ok, result} = AsyncResult.await(handle)

# Or with timeout
{:ok, result} = AsyncResult.await(handle, 5000)
```

### Streaming (Memory Efficient)

```elixir
# For large collections
AsyncResult.stream(items, &process_item/1, max_concurrency: 10)
|> Stream.filter(&Result.ok?/1)
|> Enum.take(100)
```

---

## Validation

Accumulating validation that collects ALL errors (unlike Result which fails fast).

### Basic Usage

```elixir
alias FnTypes.Validation, as: V

# Validate params
V.new(params)
|> V.field(:email, [required(), format(:email)])
|> V.field(:age, [required(), min(18)])
|> V.field(:name, [required(), min_length(2), max_length(50)])
|> V.to_result()
#=> {:ok, params} or {:error, %{email: [...], age: [...]}}
```

### Built-in Validators

```elixir
# Type validators
required()           # Must be present and non-nil
type(:string)        # Must be a string
type(:integer)       # Must be an integer
type(:boolean)       # Must be a boolean

# String validators
min_length(3)        # Minimum string length
max_length(100)      # Maximum string length
format(:email)       # Email format
format(:url)         # URL format
format(~r/^\d+$/)    # Custom regex

# Number validators
min(0)               # Minimum value
max(100)             # Maximum value
between(1, 10)       # Inclusive range

# Collection validators
in_list(["a", "b"])  # Must be in list
not_in_list([...])   # Must not be in list
```

### Custom Validators

```elixir
# Inline validator
V.field(v, :email, [
  fn email ->
    if email_exists?(email) do
      {:error, "email already taken"}
    else
      {:ok, email}
    end
  end
])

# Named validator
def unique_email do
  fn email ->
    if email_exists?(email), do: {:error, :taken}, else: {:ok, email}
  end
end

V.field(v, :email, [required(), format(:email), unique_email()])
```

### Conditional Validation

```elixir
# Only validate if condition met
V.field(v, :phone, [required(), format(:phone)],
  when: fn params -> params[:contact_method] == :phone end
)

# Unless condition
V.field(v, :email, [required()],
  unless: fn params -> params[:anonymous] == true end
)
```

### Cross-Field Validation

```elixir
V.new(params)
|> V.field(:password, [required(), min_length(8)])
|> V.field(:password_confirmation, [required()])
|> V.check(:password_confirmation, fn ctx ->
  if ctx.data[:password] == ctx.data[:password_confirmation] do
    {:ok, ctx.value}
  else
    {:error, "passwords don't match"}
  end
end)
```

### Combining Validations

```elixir
# All must pass
V.all([
  V.validate(email, [format(:email)]),
  V.validate(age, [min(18)]),
  V.validate(name, [required()])
])
#=> {:ok, [email, age, name]} or {:error, [all_errors]}

# Map results into struct
V.map3(
  V.validate(params[:email], [required(), format(:email)]),
  V.validate(params[:name], [required()]),
  V.validate(params[:age], [min(18)]),
  fn email, name, age -> %User{email: email, name: name, age: age} end
)
```

---

## Guards

Guard macros for pattern matching on result types.

```elixir
import FnTypes.Guards

# In function heads
def process(result) when is_ok(result), do: handle_success(result)
def process(result) when is_error(result), do: handle_error(result)

# In case statements
case result do
  r when is_ok(r) -> extract_value(r)
  r when is_error(r) -> log_error(r)
end

# Available guards
is_ok(term)        # Matches {:ok, _}
is_error(term)     # Matches {:error, _}
is_just(term)      # Matches {:just, _}
is_nothing(term)   # Matches :nothing
```

---

## Timing

Execution timing, duration measurement, and benchmarking.

### Basic Measurement

```elixir
alias FnTypes.Timing

# Measure execution time
{result, duration} = Timing.measure(fn -> expensive_operation() end)
IO.puts("Took #{duration.ms}ms")

# Quick measurement (returns milliseconds)
{result, ms} = Timing.measure!(fn -> api_call() end)
```

### Duration Struct

```elixir
alias FnTypes.Timing.Duration

duration = Duration.new(1_500_000)  # nanoseconds
duration.ns   #=> 1_500_000
duration.μs   #=> 1500
duration.ms   #=> 1.5
duration.s    #=> 0.0015

# Format for display
Timing.format(duration)  #=> "1.5ms"
```

### Safe Measurement

Captures exceptions with timing:

```elixir
case Timing.measure_safe(fn -> risky_operation() end) do
  {:ok, result, duration} ->
    Logger.info("Success in #{duration.ms}ms")
    result

  {:error, kind, reason, stacktrace, duration} ->
    Logger.error("Failed after #{duration.ms}ms: #{inspect(reason)}")
    reraise(reason, stacktrace)
end
```

### Callbacks

```elixir
# Callback on completion
Timing.timed(fn -> work() end, fn duration ->
  Logger.info("Operation took #{Timing.format(duration)}")
end)

# Only log slow operations
Timing.timed_if_slow(fn -> query() end, 100, fn duration ->
  Logger.warn("Slow query: #{duration.ms}ms")
end)
```

### Benchmarking

```elixir
stats = Timing.benchmark(fn -> operation() end, iterations: 100)

IO.puts("""
Min: #{stats.min.ms}ms
Max: #{stats.max.ms}ms
Mean: #{stats.mean.ms}ms
Median: #{stats.median.ms}ms
P95: #{stats.p95.ms}ms
P99: #{stats.p99.ms}ms
""")
```

---

## Retry

Unified retry engine with pluggable backoff strategies.

### Basic Usage

```elixir
alias FnTypes.Retry

# Simple retry with defaults
Retry.execute(fn -> api_call() end)

# Custom options
Retry.execute(fn -> api_call() end,
  max_attempts: 5,
  initial_delay: 500,
  max_delay: 30_000
)
```

### Backoff Strategies

```elixir
# Exponential (default): base * 2^(attempt-1)
Retry.execute(task, backoff: :exponential)

# Linear: base * attempt
Retry.execute(task, backoff: :linear)

# Fixed: constant delay
Retry.execute(task, backoff: :fixed)

# AWS-style decorrelated jitter
Retry.execute(task, backoff: :decorrelated)

# Full jitter: random up to exponential cap
Retry.execute(task, backoff: :full_jitter)

# Equal jitter: half exponential + half random
Retry.execute(task, backoff: :equal_jitter)

# Custom strategy
Retry.execute(task, backoff: fn attempt, _opts ->
  min(100 * :math.pow(2, attempt), 10_000)
end)
```

### Retry Callbacks

```elixir
Retry.execute(fn -> api_call() end,
  on_retry: fn error, attempt, delay ->
    Logger.warn("Retry #{attempt}, waiting #{delay}ms: #{inspect(error)}")
  end
)
```

### Selective Retry

```elixir
# Only retry specific errors
Retry.execute(fn -> api_call() end,
  when: fn
    {:error, :timeout} -> true
    {:error, :rate_limited} -> true
    _ -> false
  end
)
```

### Database Transactions

```elixir
# Retry serialization failures
Retry.transaction(fn ->
  user = Repo.get!(User, id)
  Repo.update(User.changeset(user, attrs))
end, repo: MyApp.Repo)
```

---

## Error

Structured error type for consistent error representation.

```elixir
alias FnTypes.Error

# Create structured error
error = Error.new(:not_found,
  message: "User not found",
  context: %{user_id: 123}
)

# Access fields
error.code      #=> :not_found
error.message   #=> "User not found"
error.context   #=> %{user_id: 123}

# Wrap exceptions
Error.wrap(exception, :external_error)

# Normalize various error formats
Error.normalize({:error, "string error"})
Error.normalize(%MyError{})
Error.normalize(:atom_error)
```

---

## Lens

Functional lenses for accessing and updating nested data.

```elixir
alias FnTypes.Lens

# Create lens for nested access
address_city = Lens.compose([
  Lens.key(:address),
  Lens.key(:city)
])

# Get nested value
Lens.view(user, address_city)
#=> "New York"

# Update nested value
Lens.set(user, address_city, "Boston")
#=> %{..., address: %{..., city: "Boston"}}

# Update with function
Lens.over(user, address_city, &String.upcase/1)
#=> %{..., address: %{..., city: "NEW YORK"}}

# Common lenses
Lens.key(:field)           # Map key access
Lens.index(0)              # List index access
Lens.path([:a, :b, :c])    # Nested path
```

---

## Real-World Examples

### 1. User Registration Pipeline

```elixir
defmodule MyApp.Registration do
  alias FnTypes.{Pipeline, Validation, Result}

  def register(params) do
    with {:ok, validated} <- validate_params(params),
         {:ok, result} <- run_registration(validated) do
      {:ok, result.user}
    end
  end

  defp validate_params(params) do
    Validation.new(params)
    |> Validation.field(:email, [required(), format(:email), &unique_email/1])
    |> Validation.field(:password, [required(), min_length(8)])
    |> Validation.field(:name, [required(), min_length(2)])
    |> Validation.to_result()
  end

  defp run_registration(params) do
    Pipeline.new(params)
    |> Pipeline.step(:create_user, &create_user/1,
      rollback: &delete_user/1
    )
    |> Pipeline.step(:send_confirmation, &send_confirmation_email/1)
    |> Pipeline.step(:notify_admins, &notify_admins/1)
    |> Pipeline.run_with_rollback()
  end
end
```

### 2. External API with Retry and Fallback

```elixir
defmodule MyApp.WeatherService do
  alias FnTypes.{AsyncResult, Result, Retry}

  def get_weather(city) do
    # Try primary API with retry
    Retry.execute(fn -> primary_api(city) end,
      max_attempts: 3,
      initial_delay: 100
    )
    |> Result.or_else(fn _ ->
      # Fallback to backup API
      backup_api(city)
    end)
    |> Result.or_else(fn _ ->
      # Return cached data
      get_cached(city)
    end)
  end

  def get_weather_multi(cities) do
    AsyncResult.parallel_map(cities, &get_weather/1,
      max_concurrency: 10,
      timeout: 5000,
      settle: true
    )
  end
end
```

### 3. Dashboard Data Aggregation

```elixir
defmodule MyApp.Dashboard do
  alias FnTypes.{AsyncResult, Pipeline}

  def load_dashboard(user_id) do
    # Fetch all data in parallel
    AsyncResult.parallel([
      fn -> fetch_profile(user_id) end,
      fn -> fetch_notifications(user_id) end,
      fn -> fetch_recent_orders(user_id) end,
      fn -> fetch_recommendations(user_id) end
    ], max_concurrency: 4, timeout: 3000)
    |> Result.map(fn [profile, notifications, orders, recommendations] ->
      %{
        profile: profile,
        notifications: notifications,
        orders: orders,
        recommendations: recommendations
      }
    end)
  end

  # Or with settlement for partial results
  def load_dashboard_partial(user_id) do
    AsyncResult.parallel([
      {:profile, fn -> fetch_profile(user_id) end},
      {:notifications, fn -> fetch_notifications(user_id) end},
      {:orders, fn -> fetch_recent_orders(user_id) end}
    ], settle: true, indexed: true)
    |> build_partial_dashboard()
  end
end
```

### 4. Form Validation with Detailed Errors

```elixir
defmodule MyApp.OrderForm do
  alias FnTypes.Validation, as: V

  def validate(params) do
    V.new(params)
    # Basic fields
    |> V.field(:email, [required(), format(:email)])
    |> V.field(:phone, [format(:phone)], when: &(&1[:contact_method] == :phone))

    # Shipping address
    |> V.field(:shipping_address, [required()])
    |> V.nested(:shipping_address, fn v ->
      v
      |> V.field(:street, [required()])
      |> V.field(:city, [required()])
      |> V.field(:zip, [required(), format(:zip)])
    end)

    # Items validation
    |> V.field(:items, [required(), min_length(1)])
    |> V.each(:items, fn v ->
      v
      |> V.field(:product_id, [required()])
      |> V.field(:quantity, [required(), min(1), max(100)])
    end)

    |> V.to_result()
  end
end
```

---

## Configuration

```elixir
# config/config.exs
config :fn_types,
  telemetry_prefix: [:my_app]

# Retry defaults
config :fn_types, FnTypes.Retry,
  default_repo: MyApp.Repo,
  telemetry_prefix: [:my_app, :retry]
```

---

## Module Reference

| Module | Purpose |
|--------|---------|
| `FnTypes.Result` | Error handling with `{:ok, v}` / `{:error, e}` |
| `FnTypes.Maybe` | Optional values with `{:just, v}` / `:nothing` |
| `FnTypes.Pipeline` | Multi-step workflows with context |
| `FnTypes.AsyncResult` | Concurrent operations |
| `FnTypes.Validation` | Accumulating validation errors |
| `FnTypes.Guards` | Guard macros (`is_ok`, `is_error`, etc.) |
| `FnTypes.Error` | Structured error type |
| `FnTypes.Lens` | Functional lenses for nested data |
| `FnTypes.NonEmptyList` | Non-empty list type |
| `FnTypes.Timing` | Execution timing and benchmarking |
| `FnTypes.Retry` | Retry with backoff strategies |

---

## Best Practices

### 1. Use Result for Error Handling

```elixir
# GOOD: Composable error handling
fetch_user(id)
|> Result.and_then(&validate/1)
|> Result.and_then(&process/1)

# BAD: Nested case statements
case fetch_user(id) do
  {:ok, user} ->
    case validate(user) do
      {:ok, valid} -> process(valid)
      error -> error
    end
  error -> error
end
```

### 2. Use Validation for Forms

```elixir
# GOOD: Collect all errors at once
Validation.new(params)
|> Validation.field(:email, [...])
|> Validation.field(:age, [...])
|> Validation.to_result()
# Returns all validation errors

# BAD: Return only first error
with {:ok, email} <- validate_email(params.email),
     {:ok, age} <- validate_age(params.age) do
  ...
end
# Only shows first error to user
```

### 3. Use AsyncResult for Concurrent Operations

```elixir
# GOOD: Parallel with proper error handling
AsyncResult.parallel([
  fn -> api1() end,
  fn -> api2() end
], max_concurrency: 5, timeout: 5000)

# BAD: Manual task management
tasks = [Task.async(api1), Task.async(api2)]
Task.await_many(tasks)  # No error handling
```

### 4. Use Pipeline for Multi-Step Workflows

```elixir
# GOOD: Clear flow with rollback support
Pipeline.new(ctx)
|> Pipeline.step(:reserve, &reserve/1, rollback: &release/1)
|> Pipeline.step(:charge, &charge/1, rollback: &refund/1)
|> Pipeline.run_with_rollback()

# BAD: Manual cleanup on failure
case reserve(ctx) do
  {:ok, r} ->
    case charge(r) do
      {:ok, c} -> {:ok, c}
      {:error, e} ->
        release(r)  # Easy to forget
        {:error, e}
    end
  error -> error
end
```

## License

MIT
