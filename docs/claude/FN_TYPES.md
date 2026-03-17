# FnTypes — Comprehensive Cheatsheet

> Functional programming types for Elixir. Result, Maybe, Pipeline, AsyncResult, Validation, Lens, Retry, Timing, and more.

---

## Table of Contents

1. [Result](#result) — Monadic error handling
2. [Maybe](#maybe) — Optional/nilable values
3. [Pipeline](#pipeline) — Multi-step workflows
4. [AsyncResult](#asyncresult) — Concurrent operations
5. [Validation](#validation) — Accumulating error collection
6. [Error](#error) — Structured error type
7. [Lens](#lens) — Nested data access
8. [Ior](#ior) — Success with warnings
9. [Lazy](#lazy) — Deferred computation & streaming
10. [Diff](#diff) — Data structure comparison
11. [Retry & Backoff](#retry--backoff) — Fault tolerance
12. [Timing](#timing) — Performance measurement
13. [Resource](#resource) — Safe cleanup
14. [Guards](#guards) — Pattern matching
15. [NonEmptyList](#nonemptylist) — Guaranteed non-empty
16. [RateLimiter / Throttler / Debouncer](#rate-limiting)
17. [Config](#config) — Type-safe env vars
18. [SideEffects](#sideeffects) — Effect annotations
19. [Testing](#testing) — Assertion macros
20. [Protocols](#protocols) — Normalizable, Recoverable, Identifiable
21. [Real-World Patterns](#real-world-patterns)

---

## Result

Monadic error handling with `{:ok, value}` | `{:error, reason}`.

### Create

```elixir
Result.ok(42)                          #=> {:ok, 42}
Result.error(:not_found)               #=> {:error, :not_found}
Result.pure(42)                        #=> {:ok, 42}
Result.from_nilable(user, :not_found)  #=> {:ok, user} | {:error, :not_found}
Result.from_nilable(nil, :not_found)   #=> {:error, :not_found}
Result.try_with(fn -> risky() end)     #=> {:ok, val} | {:error, exception}
```

### Type Check

```elixir
Result.ok?({:ok, 1})      #=> true
Result.error?({:error, _}) #=> true
```

### Transform

```elixir
{:ok, 5}    |> Result.map(&(&1 * 2))       #=> {:ok, 10}
{:error, e} |> Result.map(&(&1 * 2))       #=> {:error, e}  (unchanged)

{:error, "bad"} |> Result.map_error(&String.upcase/1) #=> {:error, "BAD"}

# bimap — transform both sides
Result.bimap({:ok, 5}, on_ok: &(&1 * 2), on_error: &String.upcase/1)
#=> {:ok, 10}
```

### Chain (and_then / or_else)

```elixir
# and_then — chain operations that may fail (flatMap/bind)
fetch_user(id)
|> Result.and_then(&validate/1)
|> Result.and_then(&save/1)
#=> {:ok, saved_user} | {:error, first_failure}

# or_else — recover from errors
{:error, :not_found}
|> Result.or_else(fn :not_found -> {:ok, default_user()} end)
#=> {:ok, default_user}

# Fallback chain
fetch_primary(id)
|> Result.or_else(fn _ -> fetch_cache(id) end)
|> Result.or_else(fn _ -> fetch_backup(id) end)
```

### Extract

```elixir
Result.unwrap_or({:ok, 42}, 0)     #=> 42
Result.unwrap_or({:error, _}, 0)   #=> 0
Result.unwrap_or_else({:error, e}, fn e -> compute_default(e) end)
Result.unwrap!({:ok, 42})          #=> 42 (raises on error)
Result.to_option({:ok, v})         #=> v
Result.to_option({:error, _})      #=> nil
```

### Collections

```elixir
# collect — all must succeed (fail-fast)
Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])
#=> {:ok, [1, 2, 3]}

Result.collect([{:ok, 1}, {:error, :bad}, {:ok, 3}])
#=> {:error, :bad}

# partition — split into successes and failures
Result.partition([{:ok, 1}, {:error, :a}, {:ok, 2}])
#=> %{ok: [1, 2], errors: [:a]}

# traverse — map then collect
Result.traverse([1, 2, 3], &fetch_user/1)
#=> {:ok, [user1, user2, user3]} | {:error, first_error}

# cat_ok — extract only successes
Result.cat_ok([{:ok, 1}, {:error, :x}, {:ok, 2}])
#=> [1, 2]
```

### Combine

```elixir
# combine two results into a tuple
Result.combine({:ok, 1}, {:ok, 2})
#=> {:ok, {1, 2}}

# combine_with — merge with a function
Result.combine_with({:ok, "hello"}, {:ok, " world"}, &<>/2)
#=> {:ok, "hello world"}

# zip / zip_with — aliases
Result.zip({:ok, 1}, {:ok, 2})                    #=> {:ok, {1, 2}}
Result.zip_with({:ok, 2}, {:ok, 3}, &Kernel.*/2)   #=> {:ok, 6}
```

### Side Effects

```elixir
# tap — execute side effect, return result unchanged
{:ok, user}
|> Result.tap(fn user -> Logger.info("Got user: #{user.id}") end)
|> Result.and_then(&process/1)

# tap_error — side effect on error only
result |> Result.tap_error(fn e -> Logger.error("Failed: #{inspect(e)}") end)
```

### Flatten & Swap

```elixir
Result.flatten({:ok, {:ok, 42}})  #=> {:ok, 42}
Result.flatten({:ok, {:error, e}}) #=> {:error, e}
Result.swap({:ok, 1})             #=> {:error, 1}
Result.swap({:error, :x})         #=> {:ok, :x}
```

### Function Lifting

```elixir
# lift — make regular function work on Results
add_one = Result.lift(&(&1 + 1))
add_one.({:ok, 5})    #=> {:ok, 6}
add_one.({:error, e}) #=> {:error, e}

# lift_apply — apply lifted function directly
Result.lift_apply(&String.upcase/1, {:ok, "hello"})  #=> {:ok, "HELLO"}
```

### Pipeline Integration

```elixir
# with_step — wrap error with step context
{:error, :bad} |> Result.with_step(:validate)
#=> {:error, {:step_failed, :validate, :bad}}

# unwrap_step — extract inner error
{:error, {:step_failed, :validate, :bad}} |> Result.unwrap_step()
#=> {:error, :bad}

# normalize_error — convert to FnTypes.Error struct
{:error, :not_found} |> Result.normalize_error()
#=> {:error, %FnTypes.Error{type: :not_found, ...}}
```

---

## Maybe

Optional values with `{:some, value}` | `:none`. Never use `nil` — wrap it.

### Create

```elixir
Maybe.some(42)               #=> {:some, 42}
Maybe.none()                 #=> :none
Maybe.from_nilable("hello")  #=> {:some, "hello"}
Maybe.from_nilable(nil)      #=> :none
Maybe.from_nilable(false)    #=> {:some, false}  (preserves false/0/"")
Maybe.from_result({:ok, v})  #=> {:some, v}
Maybe.from_result({:error,_})#=> :none
Maybe.from_bool(true, 42)    #=> {:some, 42}
Maybe.from_bool(false, 42)   #=> :none
Maybe.from_string("")        #=> :none  (trims whitespace)
Maybe.from_string("  hi  ") #=> {:some, "hi"}
Maybe.from_map(%{})          #=> :none
Maybe.from_map(%{a: 1})      #=> {:some, %{a: 1}}
```

### Transform & Chain

```elixir
{:some, "hello"} |> Maybe.map(&String.upcase/1)  #=> {:some, "HELLO"}
:none            |> Maybe.map(&String.upcase/1)  #=> :none

# and_then — chain maybe-returning functions
Maybe.from_nilable(user)
|> Maybe.and_then(fn u -> Maybe.from_nilable(u.email) end)
|> Maybe.map(&String.downcase/1)
#=> {:some, "user@example.com"} | :none

# filter / reject
{:some, 5} |> Maybe.filter(&(&1 > 3))  #=> {:some, 5}
{:some, 1} |> Maybe.filter(&(&1 > 3))  #=> :none
{:some, 5} |> Maybe.reject(&(&1 > 3))  #=> :none
```

### Extract

```elixir
Maybe.unwrap_or({:some, 42}, 0)       #=> 42
Maybe.unwrap_or(:none, 0)             #=> 0
Maybe.unwrap_or_else(:none, &default/0)
Maybe.to_nilable({:some, 42})         #=> 42
Maybe.to_nilable(:none)               #=> nil
Maybe.to_result({:some, 42}, :missing) #=> {:ok, 42}
Maybe.to_result(:none, :missing)       #=> {:error, :missing}
Maybe.to_list({:some, 42})            #=> [42]
Maybe.to_list(:none)                  #=> []
```

### Map Access

```elixir
Maybe.get(%{name: "Alice"}, :name)    #=> {:some, "Alice"}
Maybe.get(%{name: "Alice"}, :email)   #=> :none

# Deep path access
Maybe.fetch_path(%{user: %{profile: %{name: "Alice"}}}, [:user, :profile, :name])
#=> {:some, "Alice"}

Maybe.fetch_path(%{user: nil}, [:user, :profile, :name])
#=> :none
```

### Collections

```elixir
Maybe.collect([{:some, 1}, {:some, 2}])  #=> {:some, [1, 2]}
Maybe.collect([{:some, 1}, :none])       #=> :none
Maybe.cat_somes([{:some, 1}, :none, {:some, 2}])  #=> [1, 2]
Maybe.first_some([fn -> :none end, fn -> {:some, 42} end])  #=> {:some, 42}
```

### Side Effects

```elixir
{:some, user} |> Maybe.tap_some(fn u -> Logger.info("Got: #{u.id}") end)
:none         |> Maybe.tap_none(fn -> Logger.warn("No user") end)
```

### Combine

```elixir
Maybe.zip({:some, 1}, {:some, 2})                    #=> {:some, {1, 2}}
Maybe.zip_with({:some, 2}, {:some, 3}, &Kernel.*/2)   #=> {:some, 6}
Maybe.combine_with({:some, "a"}, {:some, "b"}, &<>/2) #=> {:some, "ab"}
```

---

## Pipeline

Multi-step workflows with context accumulation, branching, rollback, and parallel execution.

### Basic Flow

```elixir
Pipeline.new(%{user_id: 123})
|> Pipeline.step(:fetch_user, fn ctx ->
  case Repo.get(User, ctx.user_id) do
    nil -> {:error, :not_found}
    user -> {:ok, %{user: user}}  # merged into context
  end
end)
|> Pipeline.step(:validate, fn ctx ->
  if valid?(ctx.user), do: {:ok, %{}}, else: {:error, :invalid}
end)
|> Pipeline.step(:notify, fn ctx ->
  send_email(ctx.user)
  {:ok, %{notified: true}}
end)
|> Pipeline.run()
#=> {:ok, %{user_id: 123, user: %User{}, notified: true}}
#   | {:error, {:step_failed, :fetch_user, :not_found}}
```

### Assign & Transform

```elixir
Pipeline.new(%{})
|> Pipeline.assign(:now, DateTime.utc_now())          # static value
|> Pipeline.assign(:config, fn _ -> load_config() end) # lazy value
|> Pipeline.transform(:user, :display_name, fn user ->
  {:ok, "#{user.first_name} #{user.last_name}"}
end)
```

### Conditional Steps

```elixir
# Condition option
Pipeline.step(p, :notify, &notify/1,
  condition: fn ctx -> ctx.user.notifications_enabled end
)

# step_if
Pipeline.step_if(p, :premium, &ctx.user.premium?, &apply_discount/1)

# guard — halt with error if condition fails
Pipeline.guard(p, :auth, fn ctx -> ctx.user.admin? end, :unauthorized)

# when_true — conditionally add steps
Pipeline.when_true(p, should_notify?, fn p ->
  Pipeline.step(p, :notify, &send_notification/1)
end)
```

### Parallel Steps

```elixir
Pipeline.new(%{user_id: id})
|> Pipeline.parallel([
  {:profile, fn ctx -> fetch_profile(ctx.user_id) end},
  {:orders, fn ctx -> fetch_orders(ctx.user_id) end},
  {:prefs, fn ctx -> fetch_preferences(ctx.user_id) end}
], max_concurrency: 5, timeout: 5000)
|> Pipeline.run()
#=> {:ok, %{user_id: id, profile: %{...}, orders: [...], prefs: %{...}}}
```

### Branching

```elixir
Pipeline.new(%{type: :premium})
|> Pipeline.branch(:type, %{
  premium: fn p ->
    p |> Pipeline.step(:discount, &apply_premium_discount/1)
  end,
  standard: fn p ->
    p |> Pipeline.step(:rate, &apply_standard_rate/1)
  end
}, default: fn p ->
  p |> Pipeline.step(:fallback, &apply_default/1)
end)
|> Pipeline.run()
```

### Rollback on Error

```elixir
Pipeline.new(%{order: order})
|> Pipeline.step(:reserve, &reserve_inventory/1,
  rollback: fn ctx -> release_inventory(ctx.reservation) end)
|> Pipeline.step(:charge, &charge_payment/1,
  rollback: fn ctx -> refund_payment(ctx.payment) end)
|> Pipeline.step(:ship, &create_shipment/1)
|> Pipeline.run_with_rollback()
# If :charge fails → :reserve rollback is called automatically
```

### Retry Step

```elixir
Pipeline.step_with_retry(p, :api_call, &call_external_api/1,
  max_attempts: 3,
  delay: 200,
  should_retry: fn reason -> reason in [:timeout, :rate_limited] end
)
```

### Checkpoints

```elixir
Pipeline.new(%{})
|> Pipeline.step(:step1, &step1/1)
|> Pipeline.checkpoint(:after_step1)
|> Pipeline.step(:step2, &step2/1)
|> Pipeline.rollback_to(:after_step1)  # restore to checkpoint
|> Pipeline.step(:alt_step2, &alt/1)
|> Pipeline.run()
```

### Cleanup (Ensure)

```elixir
Pipeline.new(%{})
|> Pipeline.step(:open_file, &open/1)
|> Pipeline.step(:process, &process/1)
|> Pipeline.ensure(:close_file, fn ctx, _result ->
  File.close(ctx.file_handle)
end)
|> Pipeline.run_with_ensure()  # ensure always runs
```

### Transaction (OmCrud.Multi)

```elixir
Pipeline.new(%{attrs: attrs})
|> Pipeline.transaction(:create, fn ctx ->
  OmCrud.Multi.new()
  |> OmCrud.Multi.create(:user, User, ctx.attrs)
  |> OmCrud.Multi.create(:profile, Profile, fn %{user: u} -> %{user_id: u.id} end)
end)
|> Pipeline.run()
```

### Inspection & Debugging

```elixir
Pipeline.dry_run(p)        #=> [:fetch_user, :validate, :notify]
Pipeline.inspect_steps(p)  #=> [%{name: :fetch, has_rollback: true, ...}]
Pipeline.completed_steps(p)
Pipeline.pending_steps(p)
Pipeline.halted?(p)
Pipeline.error(p)
Pipeline.to_string(p)      # human-readable representation
```

### Timeout

```elixir
Pipeline.run_with_timeout(pipeline, 5000)
#=> {:ok, ctx} | {:error, :timeout}
```

### Composition

```elixir
validation = Pipeline.segment([{:v1, &v1/1}, {:v2, &v2/1}])
processing = Pipeline.segment([{:p1, &p1/1}, {:p2, &p2/1}])

Pipeline.new(%{})
|> Pipeline.include(validation)
|> Pipeline.include(processing)
|> Pipeline.run()
```

---

## AsyncResult

Concurrent operations with fail-fast, settlement, race, hedge, retry, and streaming.

### Parallel (Fail-Fast)

```elixir
AsyncResult.parallel([
  fn -> fetch_user(1) end,
  fn -> fetch_orders(1) end,
  fn -> fetch_prefs(1) end
])
#=> {:ok, [user, orders, prefs]} | {:error, first_failure}

# With options
AsyncResult.parallel(tasks,
  max_concurrency: 10,
  timeout: 5000,
  ordered: true,
  supervisor: MyApp.TaskSupervisor
)
```

### Parallel (Settlement — collect all)

```elixir
AsyncResult.parallel(tasks, settle: true)
#=> %{ok: [val1, val3], errors: [reason2], results: [{:ok,..},{:error,..},...]}

# Helpers
alias AsyncResult.Settlement
Settlement.ok?(result)       #=> true if no errors
Settlement.failed?(result)
{oks, errs} = Settlement.split(result)
```

### Parallel Map

```elixir
AsyncResult.parallel_map(user_ids, &fetch_user/1)
#=> {:ok, [user1, user2, user3]}

# With indexed settlement — know which inputs failed
AsyncResult.parallel_map(user_ids, &fetch/1, settle: true, indexed: true)
#=> %{ok: [{1, user1}], errors: [{2, :not_found}]}
```

### Race (First Wins)

```elixir
AsyncResult.race([
  fn -> fetch_from_cache(key) end,
  fn -> fetch_from_db(key) end,
  fn -> fetch_from_api(key) end
])
#=> {:ok, first_success}  (remaining tasks cancelled)
#   {:error, [:all_errors]} (only if ALL fail)
```

### Hedge (Backup if Primary Slow)

```elixir
AsyncResult.hedge(
  fn -> primary_api_call() end,
  fn -> backup_api_call() end,
  delay: 100,    # start backup after 100ms
  timeout: 5000  # overall timeout
)
```

### Retry

```elixir
AsyncResult.retry(fn -> flaky_api() end,
  max_attempts: 5,
  initial_delay: 100,
  max_delay: 5000,
  multiplier: 2,
  jitter: true,
  when: fn {:error, reason} -> reason in [:timeout, :rate_limited] end,
  on_retry: fn attempt, error, delay ->
    Logger.warn("Retry #{attempt}: #{inspect(error)}, waiting #{delay}ms")
  end
)

# Protocol-aware retry (uses Recoverable protocol)
AsyncResult.retry_from_error(fn -> api_call() end)
```

### Batch

```elixir
AsyncResult.batch(tasks,
  batch_size: 10,
  delay_between_batches: 1000,  # rate limiting
  timeout: 5000
)
```

### Sequential Fallback

```elixir
AsyncResult.first_ok([
  fn -> check_l1_cache() end,
  fn -> check_l2_cache() end,
  fn -> fetch_from_db() end
])
#=> {:ok, first_success} | {:error, :all_failed}
```

### Streaming (Large Collections)

```elixir
large_dataset
|> AsyncResult.stream(&transform/1,
  max_concurrency: 20,
  on_error: :skip  # :halt | :skip | :include | {:default, val}
)
|> Stream.each(&save/1)
|> Stream.run()
```

### Explicit Task Handles

```elixir
handle = AsyncResult.async(fn -> expensive() end)
# ... do other work ...
{:ok, result} = AsyncResult.await(handle, timeout: 10_000)

# Mix cached + async
handles = Enum.map(items, fn item ->
  case Cache.get(item) do
    {:ok, cached} -> AsyncResult.completed({:ok, cached})
    :miss -> AsyncResult.async(fn -> fetch(item) end)
  end
end)
{:ok, results} = AsyncResult.await_many(handles)
```

### Fire and Forget

```elixir
AsyncResult.fire_and_forget(fn -> send_analytics(event) end)
AsyncResult.run_all(users, &send_notification/1, max_concurrency: 50)
```

### Lazy (Deferred)

```elixir
lazy = AsyncResult.lazy(fn -> expensive() end)
# Nothing runs yet
{:ok, result} = AsyncResult.run_lazy(lazy)

# Chain
lazy = AsyncResult.lazy(fn -> fetch_user(id) end)
|> AsyncResult.lazy_then(fn user ->
  AsyncResult.lazy(fn -> fetch_orders(user.id) end)
end)
{:ok, orders} = AsyncResult.run_lazy(lazy)
```

### Timeout Wrapper

```elixir
AsyncResult.timeout(fn -> slow_operation() end, 1000)
#=> {:ok, result} | {:error, :timeout}
```

---

## Validation

Accumulating validation — collects ALL errors instead of failing at the first one.

### Basic

```elixir
alias FnTypes.Validation, as: V
import V  # for required(), min(), etc.

V.new(%{email: "bad", age: 15, name: ""})
|> V.field(:email, [required(), format(:email)])
|> V.field(:age, [required(), min(18)])
|> V.field(:name, [required(), min_length(2)])
|> V.to_result()
#=> {:error, %{
#     email: ["invalid format"],
#     age: [{:min, 18}],
#     name: [{:min_length, 2}]
#   }}
```

### Built-in Validators

```elixir
# Presence
required()                  # non-nil, non-empty string

# Numeric
min(18)                     # >= 18
max(100)                    # <= 100
between(1, 10)              # 1..10 inclusive
positive()                  # > 0
non_negative()              # >= 0

# String length
min_length(3)               # string or list length >= 3
max_length(100)             # string or list length <= 100
exact_length(5)             # exactly 5

# Format
format(:email)              # email regex
format(:url)                # URL regex
format(:phone)              # phone regex
format(:uuid)               # UUID v4
format(:slug)               # URL-safe slug
format(~r/^\d{3}$/)         # custom regex

# Inclusion/Exclusion
inclusion([:active, :inactive])
exclusion([:banned, :deleted])

# Equality
equals("expected")
not_equals("forbidden")

# Date/Time
past()                      # Date/DateTime in the past
future()                    # Date/DateTime in the future

# Boolean
acceptance()                # must be true (terms of service)

# Custom
predicate(&is_binary/1, "must be string")
when_present([min_length(3)])  # only validate if value present

# Custom message
min(18, message: "Must be 18 or older")
required(message: "This field is required")
```

### Conditional Validation

```elixir
V.field(v, :phone, [required(), format(:phone)],
  when: fn params -> params[:contact_method] == :phone end
)
```

### Cross-Field Validation

```elixir
V.new(params)
|> V.field(:password, [required(), min_length(8)])
|> V.field(:password_confirm, [required()])
|> V.check(:password_confirm, fn ctx ->
  if ctx.data[:password] == ctx.data[:password_confirm],
    do: {:ok, ctx.value},
    else: {:error, "passwords don't match"}
end)

# Built-in cross-field validators
|> V.at_least_one_of([:email, :phone], "Provide email or phone")
|> V.exactly_one_of([:card, :bank], "Choose one payment method")
|> V.all_or_none_of([:street, :city, :zip], "Complete address required")
```

### Nested Validation

```elixir
V.new(params)
|> V.field(:shipping, [required()])
|> V.nested(:shipping, fn v ->
  v
  |> V.field(:street, [required()])
  |> V.field(:city, [required()])
  |> V.field(:zip, [required(), format(~r/^\d{5}$/)])
end)
# Error keys: "shipping.street", "shipping.city", etc.
```

### List Validation

```elixir
V.new(params)
|> V.field(:items, [required(), min_length(1)])
|> V.each(:items, fn v ->
  v
  |> V.field(:product_id, [required()])
  |> V.field(:quantity, [required(), min(1), max(100)])
end)
# Error keys: "items.0.quantity", "items.1.product_id", etc.
```

### Applicative Composition

```elixir
# Validate independently, combine results
V.map2(
  V.validate(email, [required(), format(:email)]),
  V.validate(age, [required(), min(18)]),
  fn email, age -> %{email: email, age: age} end
)

V.map3(v1, v2, v3, fn a, b, c -> %{a: a, b: b, c: c} end)

# Collect all validations
V.all([
  V.validate(email, [format(:email)]),
  V.validate(age, [min(18)]),
  V.validate(name, [required()])
])
#=> {:ok, [email, age, name]} | {:error, [all_accumulated_errors]}
```

### Custom Validators

```elixir
def unique_email do
  fn email ->
    if Repo.exists?(User, email: email),
      do: {:error, [:email_taken]},
      else: {:ok, email}
  end
end

V.field(v, :email, [required(), format(:email), unique_email()])
```

### Convert to Error Struct

```elixir
V.to_error(validation)  # converts to {:error, %FnTypes.Error{}}
V.to_result(validation) # converts to {:ok, value} | {:error, error_map}
```

---

## Error

Unified structured error type with normalization, context, handling, and chaining.

### Create

```elixir
Error.new(:validation, :invalid_email,
  message: "Email is invalid",
  details: %{field: :email, value: "bad"},
  context: %{user_id: 123},
  recoverable: false
)
```

### Error Types

| Type | HTTP | Recoverable? |
|------|------|-------------|
| `:validation` | 422 | No |
| `:not_found` | 404 | No |
| `:unauthorized` | 401 | No |
| `:forbidden` | 403 | No |
| `:conflict` | 409 | No |
| `:rate_limited` | 429 | Yes |
| `:timeout` | 408 | Yes |
| `:internal` | 500 | No |
| `:external` | 502 | Yes |
| `:network` | 503 | Yes |
| `:business` | 500 | No |

### Normalize (any error → Error struct)

```elixir
Error.normalize(:not_found)                    # atom
Error.normalize(%Ecto.Changeset{valid?: false}) # changeset
Error.normalize(%RuntimeError{message: "x"})   # exception
Error.normalize({:error, "string"})            # tuple
Error.normalize(%{code: "ERR", message: "x"})  # map

# Normalize result tuple
Error.normalize_result({:error, :not_found})
#=> {:error, %Error{type: :not_found, ...}}

# Wrap function call
Error.wrap(fn -> dangerous_operation() end)
#=> {:ok, result} | {:error, %Error{}}
```

### Enrich

```elixir
error
|> Error.with_context(user_id: 123, request_id: "req_abc")
|> Error.with_details(field: "email", constraint: "unique")
|> Error.with_step(:create_user)
|> Error.with_cause(inner_error)
```

### Handle

```elixir
Error.handle(error, :http)
#=> {422, %{error: %{type: :validation, code: :invalid_email, ...}}}

Error.handle(error, :graphql)
#=> %{message: "...", extensions: %{type: ..., code: ...}}

Error.handle(error, :log)
# Logs error and returns it
```

### Inspect

```elixir
Error.type?(error, :validation)   #=> true
Error.validation?(error)          #=> true
Error.not_found?(error)
Error.auth_error?(error)          # unauthorized or forbidden
Error.client_error?(error)        # validation/not_found/unauthorized/forbidden/conflict
Error.server_error?(error)        # internal/external/timeout/network
Error.recoverable?(error)

Error.root_cause(error)           # deepest error in cause chain
Error.cause_chain(error)          # [outer, middle, root]
Error.format(error)               # "[validation] Email invalid (step: create_user)"
Error.to_map(error)               # JSON-safe map
```

---

## Lens

Functional lenses for composable access/update of nested immutable data.

### Create

```elixir
name_lens = Lens.key(:name)
city_lens = Lens.path([:address, :city])
first_lens = Lens.at(0)
elem_lens = Lens.elem(1)
id_lens = Lens.identity()
```

### Get / Set / Update

```elixir
user = %{name: "Alice", address: %{city: "NYC", zip: "10001"}}

Lens.get(Lens.key(:name), user)                  #=> "Alice"
Lens.set(Lens.key(:name), user, "Bob")           #=> %{name: "Bob", ...}
Lens.update(Lens.key(:name), user, &String.upcase/1) #=> %{name: "ALICE", ...}

Lens.get(Lens.path([:address, :city]), user)      #=> "NYC"
Lens.set(Lens.path([:address, :city]), user, "LA") #=> %{..., address: %{city: "LA", ...}}
```

### Compose

```elixir
# Compose lenses for deep access
address_lens = Lens.key(:address)
city_lens = Lens.key(:city)
user_city = Lens.compose(address_lens, city_lens)

# Operator syntax
import Lens, only: [~>: 2]
user_city = Lens.key(:address) ~> Lens.key(:city)

# Compose many
deep_lens = Lens.compose_all([Lens.key(:a), Lens.key(:b), Lens.key(:c)])
```

### Safe Access (with Maybe/Result)

```elixir
Lens.get_maybe(Lens.key(:email), user)
#=> {:some, "alice@example.com"} | :none

Lens.get_result(Lens.key(:email), user)
#=> {:ok, "alice@example.com"} | {:error, :not_found}

Lens.get_result(Lens.key(:email), user, error: :missing_email)
```

### Collection Operations

```elixir
users = [%{name: "Alice"}, %{name: "Bob"}]
name_lens = Lens.key(:name)

Lens.map_get(name_lens, users)                    #=> ["Alice", "Bob"]
Lens.map_update(name_lens, users, &String.upcase/1) #=> [%{name: "ALICE"}, ...]
Lens.map_set(name_lens, users, "Unknown")         #=> [%{name: "Unknown"}, ...]
```

### Conditional & Utility

```elixir
Lens.update_if(lens, data, &transform/1)    # only if non-nil
Lens.set_default(lens, data, "fallback")     # only if nil
Lens.update_when(lens, data, &(&1 > 0), &(&1 + 1))  # only if predicate
Lens.matches?(lens, data, &(&1 > 18))       #=> true/false
Lens.nil?(lens, data)
Lens.present?(lens, data)
```

### Iso (Bidirectional Transform)

```elixir
# View cents as dollars
dollars = Lens.key(:price_cents)
|> Lens.iso(&(&1 / 100), &(&1 * 100))

Lens.get(dollars, %{price_cents: 1999})       #=> 19.99
Lens.set(dollars, %{price_cents: 1999}, 25.0) #=> %{price_cents: 2500}
```

### Special Lenses

```elixir
Lens.first()              # first element of list/tuple
Lens.last()               # last element of list
Lens.ok()                 # value inside {:ok, _}
Lens.error()              # value inside {:error, _}
Lens.some()               # value inside {:some, _}
Lens.keys([:a, :b])       # subset of map keys
Lens.path_force([:a, :b]) # creates intermediate maps if missing
```

---

## Ior

Inclusive-Or type: success, failure, OR partial success with warnings.

```elixir
Ior.success(42)                    #=> {:success, 42}
Ior.failure([:error])              #=> {:failure, [:error]}
Ior.partial([:warning], 42)        #=> {:partial, [:warning], 42}

# Transform
Ior.map({:partial, [:w], 5}, &(&1 * 2))  #=> {:partial, [:w], 10}

# Chain (warnings accumulate!)
{:partial, [:w1], 5}
|> Ior.and_then(fn v -> {:partial, [:w2], v + 1} end)
#=> {:partial, [:w1, :w2], 6}

# Add warnings
Ior.add_warning({:success, 42}, :deprecation_notice)
#=> {:partial, [:deprecation_notice], 42}

Ior.warn_if({:success, 42}, &(&1 > 100), :too_large)
#=> {:success, 42}  (condition false, no warning)

# Convert
Ior.to_result({:success, 42})      #=> {:ok, 42}
Ior.to_result({:failure, [:err]})  #=> {:error, [:err]}
Ior.to_result({:partial, [:w], 42}) #=> {:ok, 42}  (warnings dropped)
Ior.to_result_with_warnings({:partial, [:w], 42}) #=> {:ok, {42, [:w]}}

# Recover from failure
Ior.recover({:failure, [:err]}, :default)
#=> {:partial, [:err], :default}

# Inspect
Ior.warnings({:partial, [:w1, :w2], 42})  #=> [:w1, :w2]
Ior.value({:partial, _, 42})              #=> {:some, 42}
Ior.value({:failure, _})                  #=> :none
```

---

## Lazy

Deferred computation and memory-efficient streaming.

### Deferred Computation

```elixir
lazy = Lazy.defer(fn -> {:ok, expensive_query()} end)
# Nothing executes yet

{:ok, result} = Lazy.run(lazy)  # Now it executes

# Memoization (caches result in process dictionary)
lazy = Lazy.defer(fn -> api_call() end, memoize: true)
Lazy.run(lazy)  # calls API
Lazy.run(lazy)  # returns cached result
```

### Transform & Chain

```elixir
Lazy.pure(5)
|> Lazy.map(&(&1 * 2))
|> Lazy.and_then(fn n -> Lazy.defer(fn -> {:ok, n + 1} end) end)
|> Lazy.run()
#=> {:ok, 11}

Lazy.error(:fail) |> Lazy.or_else(fn _ -> Lazy.pure(:default) end) |> Lazy.run()
#=> {:ok, :default}
```

### Streaming

```elixir
# Create result-aware stream
users
|> Lazy.stream(&process_user/1, on_error: :skip, max_errors: 10)
|> Lazy.stream_filter(fn u -> {:ok, u.active?} end)
|> Lazy.stream_take(100)
|> Lazy.stream_collect()
#=> {:ok, [processed_active_users]}

# Batch processing
items
|> Lazy.stream(&{:ok, &1})
|> Lazy.stream_batch(100, fn batch -> Repo.insert_all(Item, batch) end)
|> Lazy.stream_collect()

# Settlement mode
Lazy.stream_collect(stream, settle: true)
#=> %{ok: [...], errors: [...]}
```

### Pagination

```elixir
Lazy.paginate(
  fn cursor -> API.list_users(cursor: cursor, limit: 100) end,
  fn page -> page.next_cursor end,
  get_items: & &1.data
)
|> Lazy.stream_map(&process/1)
|> Lazy.stream_collect()
```

### Combine

```elixir
Lazy.zip(Lazy.pure(1), Lazy.pure(2)) |> Lazy.run()      #=> {:ok, {1, 2}}
Lazy.zip_with(Lazy.pure(2), Lazy.pure(3), &*/2) |> Lazy.run() #=> {:ok, 6}
Lazy.sequence([Lazy.pure(1), Lazy.pure(2)]) |> Lazy.run()     #=> {:ok, [1, 2]}
```

---

## Diff

Compare, patch, and merge nested data structures.

### Diff

```elixir
old = %{name: "Alice", age: 30, tags: ["a", "b"]}
new = %{name: "Alice", age: 31, tags: ["a", "c"], role: :admin}

diff = Diff.diff(old, new)
#=> %{
#     age: {:changed, 30, 31},
#     tags: {:list_diff, [{:keep, "a"}, {:remove, "b"}, {:add, "c"}]},
#     role: {:added, :admin}
#   }

Diff.diff(%{a: 1}, %{a: 1})  #=> nil (identical)
```

### Patch

```elixir
Diff.patch(old, diff)  #=> new  (applies diff to produce new value)
Diff.apply_patch(old, diff)  #=> {:ok, new} | {:error, :patch_failed}
```

### Reverse (Undo)

```elixir
undo_diff = Diff.reverse(diff)
Diff.patch(new, undo_diff)  #=> old  (back to original)
```

### Three-Way Merge

```elixir
base  = %{x: 1, y: 2, z: 3}
left  = %{x: 10, y: 2, z: 3}  # changed x
right = %{x: 1, y: 20, z: 3}  # changed y

Diff.merge3(base, left, right)
#=> {:ok, %{x: 10, y: 20, z: 3}}  (non-conflicting merge)

# With conflict
left  = %{x: 10}
right = %{x: 20}
Diff.merge3(base, left, right)
#=> {:conflict, %{x: {:conflict, 10, 20}}, [{[:x], 10, 20}]}

# Resolve conflicts
Diff.merge3(base, left, right, :left_wins)
Diff.merge3(base, left, right, :right_wins)
Diff.merge3(base, left, right, fn _key, left, right -> {:ok, max(left, right)} end)
```

### Inspect Diff

```elixir
Diff.empty?(diff)         #=> false
Diff.changed_paths(diff)  #=> [[:age], [:tags], [:role]]
Diff.summarize(diff)      #=> %{added: 1, removed: 0, changed: 2, nested: 0}
Diff.filter(diff, [:age]) #=> %{age: {:changed, 30, 31}}
Diff.reject(diff, [:age]) # everything except :age
```

---

## Retry & Backoff

### Retry

```elixir
Retry.execute(fn -> api_call() end,
  max_attempts: 5,
  initial_delay: 200,
  max_delay: 10_000,
  backoff: :exponential,   # :linear | :fixed | :decorrelated | :full_jitter | :equal_jitter
  jitter: 0.25,
  should_retry: fn {:error, reason} -> reason in [:timeout, :rate_limited] end,
  on_retry: fn error, attempt, delay ->
    Logger.warn("Attempt #{attempt} failed, retrying in #{delay}ms")
  end
)

# Database transaction retry (handles serialization failures)
Retry.transaction(fn ->
  Repo.update(changeset)
end, repo: MyApp.Repo, max_attempts: 3)
```

### Backoff Strategies

```elixir
# Create strategy
b = Backoff.exponential(initial: 100, max: 30_000, jitter: 0.25)
b = Backoff.linear(initial: 500, max: 10_000)
b = Backoff.constant(2000)
b = Backoff.decorrelated(base: 100, max: 10_000)
b = Backoff.full_jitter(base: 1000)
b = Backoff.equal_jitter(base: 500)

# Calculate delay
{:ok, delay_ms} = Backoff.delay(b, attempt: 3)

# Jitter
Backoff.apply_jitter(1000, 0.25)  #=> 750..1250 (±25%)

# Parse delay formats
Backoff.parse_delay(5)               #=> 5000 (seconds → ms)
Backoff.parse_delay({500, :ms})      #=> 500
Backoff.parse_delay({5, :seconds})   #=> 5000
Backoff.parse_delay({1, :minutes})   #=> 60000
```

### Strategy Comparison

| Strategy | Formula | Best For |
|----------|---------|----------|
| `:exponential` | `base * 2^(n-1)` | Most APIs |
| `:linear` | `base * n` | Gradual backoff |
| `:constant` | `base` | Fixed intervals |
| `:decorrelated` | AWS jitter | Distributed systems |
| `:full_jitter` | `random(0, 2^n * base)` | Max collision avoidance |
| `:equal_jitter` | `exp/2 + random(exp/2)` | Balanced |

---

## Timing

Execution measurement with multiple time units.

```elixir
# Basic measurement
{result, duration} = Timing.measure(fn -> Repo.all(User) end)
IO.puts("Query took #{duration.ms}ms")

# Duration fields
duration.native   # raw native time
duration.ns       # nanoseconds
duration.us       # microseconds
duration.ms       # milliseconds
duration.seconds  # float seconds

# Safe (captures exceptions with timing)
case Timing.measure_safe(fn -> risky() end) do
  {:ok, result, duration} -> Logger.info("OK in #{duration.ms}ms")
  {:error, _kind, reason, _stack, duration} -> Logger.error("Failed after #{duration.ms}ms")
end

# Slow check
Timing.slow?(duration, 200)  # > 200ms?

# Format
Timing.format(duration)  #=> "1.5ms" | "2.3s" | "456µs"

# Benchmark
stats = Timing.benchmark(fn -> operation() end, iterations: 100)
stats.min.ms   stats.max.ms   stats.mean.ms   stats.median.ms   stats.p95.ms   stats.p99.ms
```

---

## Resource

Guaranteed cleanup with acquire/use/release pattern.

```elixir
# Single resource
Resource.with_resource(
  fn -> File.open!("data.txt") end,       # acquire
  fn file -> File.close(file) end,         # release (always runs)
  fn file -> {:ok, IO.read(file, :all)} end # use
)

# Multiple resources (released in reverse order)
Resource.with_resources([
  {fn -> File.open!("in.txt") end, &File.close/1},
  {fn -> File.open!("out.txt", [:write]) end, &File.close/1}
], fn [input, output] ->
  {:ok, IO.write(output, IO.read(input, :all))}
end)

# Reusable definition
db_resource = Resource.define(
  acquire: fn -> DB.connect(config) end,
  release: fn conn -> DB.disconnect(conn) end
)
Resource.using(db_resource, fn conn -> DB.query(conn, sql) end)

# With timeout
Resource.with_timeout(fn -> slow_work() end, fn -> cleanup() end, 5000)
```

---

## Guards

Pattern matching macros for guard clauses.

```elixir
import FnTypes.Guards

def process(r) when is_ok(r), do: handle_ok(r)
def process(r) when is_error(r), do: handle_error(r)
def handle(m) when is_some(m), do: unwrap(m)
def handle(m) when is_none(m), do: :default

# All guards
is_ok(term)       # {:ok, _}
is_error(term)    # {:error, _}
is_result(term)   # {:ok, _} | {:error, _}
is_some(term)     # {:some, _}
is_none(term)     # :none
is_maybe(term)    # {:some, _} | :none
is_success(term)  # {:success, _}  (Ior)
is_failure(term)  # {:failure, _}  (Ior)
is_partial(term)  # {:partial, _, _}  (Ior)
is_ior(term)      # any Ior variant
```

---

## NonEmptyList

List guaranteed to have at least one element.

```elixir
alias FnTypes.NonEmptyList, as: NEL

nel = NEL.new(1, [2, 3])         #=> {1, [2, 3]}
NEL.head(nel)                     #=> 1  (always safe)
NEL.tail(nel)                     #=> [2, 3]
NEL.to_list(nel)                  #=> [1, 2, 3]

NEL.from_list([1, 2])            #=> {:ok, {1, [2]}}
NEL.from_list([])                #=> {:error, :empty_list}
NEL.from_list!([1, 2])           #=> {1, [2]}  (raises on empty)

NEL.map(nel, &(&1 * 2))          #=> {2, [4, 6]}
NEL.reduce(nel, &+/2)            #=> 6  (no initial value needed!)
NEL.append(nel1, nel2)           #=> combined
NEL.reverse(nel)
NEL.length(nel)
```

---

## Rate Limiting

### RateLimiter (Pure/Functional)

```elixir
# Token Bucket — allows bursts
{:ok, limiter} = RateLimiter.new(:token_bucket, capacity: 10, refill_rate: 1)
case RateLimiter.check(limiter) do
  {:allow, new_state} -> proceed(new_state)
  {:deny, new_state, retry_after} -> reject(retry_after)
end

# Sliding Window — smooth enforcement
{:ok, limiter} = RateLimiter.new(:sliding_window, max_requests: 100, window_ms: 60_000)

# Leaky Bucket — constant output rate
{:ok, limiter} = RateLimiter.new(:leaky_bucket, capacity: 50, leak_rate: 10)

# Fixed Window — simple counting
{:ok, limiter} = RateLimiter.new(:fixed_window, max_requests: 1000, window_ms: 3_600_000)

# With cost (weighted requests)
RateLimiter.check(limiter, cost: 5)
```

### Throttler (GenServer)

```elixir
{:ok, t} = Throttler.start_link(interval: 1000)
Throttler.call(t, fn -> update_progress() end)  #=> {:ok, result} | {:error, :throttled}
# First call: executes immediately
# Next calls within 1s: {:error, :throttled}
```

### Debouncer (GenServer)

```elixir
{:ok, d} = Debouncer.start_link()
Debouncer.call(d, fn -> search(q1) end, 200)
Debouncer.call(d, fn -> search(q2) end, 200)
Debouncer.call(d, fn -> search(q3) end, 200)
# Only search(q3) executes, 200ms after last call
Debouncer.cancel(d)  # cancel pending
```

---

## Config

Type-safe environment variable access.

```elixir
alias FnTypes.Config, as: Cfg

# Typed getters
Cfg.string("API_KEY", "default")
Cfg.integer("PORT", 4000)
Cfg.boolean("DEBUG", false)       # "true"/"1"/"yes" → true
Cfg.atom("LOG_LEVEL", :info)
Cfg.float("RATE", 1.0)
Cfg.list("HOSTS", ",", [])        # "a,b,c" → ["a", "b", "c"]
Cfg.url("PROXY_URL")

# Required (raises if missing)
Cfg.string!("DATABASE_URL")
Cfg.integer!("PORT")
Cfg.string!("API_KEY", message: "Set API_KEY in .env")

# Fallback chain — tries each name in order
Cfg.string(["AWS_REGION", "AWS_DEFAULT_REGION"], "us-east-1")

# Priority chain
Cfg.first_of([
  Cfg.boolean("FEATURE_FLAG"),      # env var first
  Cfg.from_app(:my_app, :feature),  # app config second
  fn -> expensive_lookup() end,      # lazy function third
  true                               # default last
])

# Presence check
Cfg.present?("DATABASE_URL")
```

---

## SideEffects

Compile-time annotations for documenting function side effects.

```elixir
defmodule MyApp.Users do
  use FnTypes.SideEffects

  @side_effects [:db_read]
  def get_user(id), do: Repo.get(User, id)

  @side_effects [:db_write, :email]
  def create_user(attrs) do
    with {:ok, user} <- Repo.insert(changeset),
         :ok <- Mailer.send_welcome(user),
    do: {:ok, user}
  end

  @side_effects [:pure]
  def format_name(user), do: "#{user.first} #{user.last}"
end

# Introspection
SideEffects.list(MyApp.Users)
#=> [{:get_user, 1, [:db_read]}, {:create_user, 1, [:db_write, :email]}, ...]

SideEffects.pure_functions(MyApp.Users)
#=> [{:format_name, 1}]

SideEffects.validate(MyApp.Users)
#=> {:ok, []} | {:warnings, [{:create_user, 1, [:unknown_effect]}]}
```

### Effect Types

| Effect | Meaning |
|--------|---------|
| `:pure` | No side effects |
| `:db_read` | Database reads |
| `:db_write` | Database writes |
| `:http` | HTTP requests |
| `:io` | File system / stdout |
| `:time` | Uses current time |
| `:random` | Uses random values |
| `:process` | Spawns/messages processes |
| `:ets` | ETS table access |
| `:cache` | Cache operations |
| `:email` | Sends emails |
| `:pubsub` | Publishes events |
| `:telemetry` | Emits telemetry |
| `:external_api` | External service calls |

---

## Testing

Assertion macros for Result, Maybe, and Pipeline types.

```elixir
use FnTypes.Testing

# Result assertions
value = assert_ok({:ok, 42})              #=> 42
reason = assert_error({:error, :not_found}) #=> :not_found

# Typed error assertions
assert_error_type(:validation, {:error, %Error{type: :validation}})
assert_error_match(%Error{type: :not_found}, {:error, error})

# Maybe assertions
value = assert_some({:some, 42})  #=> 42
assert_none(:none)                #=> passes

# Pipeline assertions
ctx = assert_pipeline_ok({:ok, %{user: user}})
reason = assert_pipeline_error(:validate, {:error, {:step_failed, :validate, :bad}})
assert_pipeline_error(:validate, :bad, result)  # assert step AND reason
```

---

## Protocols

### Normalizable

Convert any error type to `FnTypes.Error`:

```elixir
defimpl FnTypes.Protocols.Normalizable, for: MyApp.ApiError do
  def normalize(%{status: status, body: body}, opts) do
    FnTypes.Error.new(:external, :api_error,
      message: body["message"],
      details: %{status: status},
      context: Keyword.get(opts, :context, %{})
    )
  end
end
```

### Recoverable

Define retry behavior per error type:

```elixir
defimpl FnTypes.Protocols.Recoverable, for: MyApp.ApiError do
  def recoverable?(%{status: s}) when s in [429, 503, 504], do: true
  def recoverable?(_), do: false

  def strategy(%{status: 429}), do: :wait_until
  def strategy(_), do: :retry_with_backoff

  def retry_delay(%{status: 429, headers: h}, _attempt), do: parse_retry_after(h)
  def retry_delay(_, attempt), do: Backoff.exponential(attempt, base: 1000)

  def max_attempts(_), do: 3
  def trips_circuit?(%{status: s}) when s >= 500, do: true
  def trips_circuit?(_), do: false
  def severity(%{status: 429}), do: :degraded
  def severity(_), do: :transient
  def fallback(_), do: nil
end
```

### Identifiable

Extract identity from entities:

```elixir
defimpl FnTypes.Protocols.Identifiable, for: MyApp.User do
  def entity_type(_), do: :user
  def id(%{id: id}), do: id
  def identity(user), do: {:user, user.id}
end
```

### Protocol Registry

```elixir
alias FnTypes.Protocols.Registry

Registry.list_protocols()
Registry.list_implementations(Normalizable)
Registry.implemented?(Normalizable, Postgrex.Error)
Registry.summary()
```

---

## Real-World Patterns

### User Registration with Validation + Pipeline + Rollback

```elixir
defmodule MyApp.Registration do
  alias FnTypes.{Pipeline, Validation, Result}
  import Validation

  def register(params) do
    with {:ok, validated} <- validate(params),
         {:ok, ctx} <- execute(validated) do
      {:ok, ctx.user}
    end
  end

  defp validate(params) do
    Validation.new(params)
    |> Validation.field(:email, [required(), format(:email), &unique_email/1])
    |> Validation.field(:password, [required(), min_length(8)])
    |> Validation.field(:name, [required(), min_length(2), max_length(50)])
    |> Validation.to_result()
  end

  defp execute(params) do
    Pipeline.new(params)
    |> Pipeline.step(:create_user, &create_user/1,
      rollback: fn ctx -> Repo.delete(ctx.user) end)
    |> Pipeline.step(:create_profile, &create_profile/1)
    |> Pipeline.step(:send_welcome, &send_welcome/1)
    |> Pipeline.step(:notify_admins, &notify_admins/1)
    |> Pipeline.run_with_rollback()
  end
end
```

### External API with Retry + Fallback + Hedging

```elixir
defmodule MyApp.WeatherService do
  alias FnTypes.{AsyncResult, Result, Retry}

  def get_weather(city) do
    # Hedge: start backup if primary is slow
    AsyncResult.hedge(
      fn -> primary_api(city) end,
      fn -> backup_api(city) end,
      delay: 200
    )
    |> Result.or_else(fn _ -> get_cached(city) end)
  end

  def get_weather_batch(cities) do
    AsyncResult.parallel_map(cities, &get_weather/1,
      max_concurrency: 10,
      timeout: 5000,
      settle: true
    )
  end

  defp primary_api(city) do
    Retry.execute(fn -> PrimaryAPI.fetch(city) end,
      max_attempts: 3,
      initial_delay: 100,
      backoff: :exponential
    )
  end
end
```

### Dashboard Data Aggregation (Parallel + Partial Results)

```elixir
defmodule MyApp.Dashboard do
  alias FnTypes.{AsyncResult, Result, Maybe}

  def load(user_id) do
    AsyncResult.parallel([
      fn -> fetch_profile(user_id) end,
      fn -> fetch_notifications(user_id) end,
      fn -> fetch_orders(user_id) end,
      fn -> fetch_recommendations(user_id) end
    ], settle: true, timeout: 3000)
    |> build_dashboard()
  end

  defp build_dashboard(%{ok: results, errors: errors}) do
    [profile, notifications, orders, recommendations] =
      Enum.map(0..3, fn i -> Enum.at(results, i) end)

    {:ok, %{
      profile: profile,
      notifications: notifications || [],
      orders: orders || [],
      recommendations: recommendations || [],
      degraded: length(errors) > 0
    }}
  end
end
```

### Order Processing Pipeline with Branch + Transaction

```elixir
defmodule MyApp.OrderPipeline do
  alias FnTypes.Pipeline

  def process(order_params) do
    Pipeline.new(%{params: order_params})
    |> Pipeline.step(:validate, &validate_order/1)
    |> Pipeline.step(:detect_type, &detect_payment_type/1)
    |> Pipeline.branch(:payment_type, %{
      credit_card: fn p ->
        p
        |> Pipeline.step(:authorize, &authorize_card/1)
        |> Pipeline.step(:capture, &capture_payment/1,
          rollback: fn ctx -> void_payment(ctx.authorization) end)
      end,
      bank_transfer: fn p ->
        p |> Pipeline.step(:initiate, &initiate_transfer/1)
      end
    })
    |> Pipeline.transaction(:create_records, fn ctx ->
      OmCrud.Multi.new()
      |> OmCrud.Multi.create(:order, Order, ctx.order_attrs)
      |> OmCrud.Multi.create(:payment, Payment, fn %{order: o} ->
        %{order_id: o.id, amount: ctx.amount}
      end)
    end)
    |> Pipeline.step(:send_confirmation, &send_confirmation/1)
    |> Pipeline.run_with_rollback()
  end
end
```

### Data Import with Lazy Streaming + Rate Limiting

```elixir
defmodule MyApp.DataImport do
  alias FnTypes.{Lazy, RateLimiter}

  def import_from_api do
    {:ok, limiter} = RateLimiter.new(:token_bucket, capacity: 10, refill_rate: 5)

    Lazy.paginate(
      fn cursor -> API.list_records(cursor: cursor, limit: 100) end,
      fn page -> page.next_cursor end,
      get_items: & &1.data
    )
    |> Lazy.stream_map(fn record ->
      with {:allow, _} <- RateLimiter.check(limiter) do
        transform_and_insert(record)
      else
        {:deny, _, retry_after} ->
          Process.sleep(retry_after)
          transform_and_insert(record)
      end
    end)
    |> Lazy.stream_batch(50, fn batch ->
      Repo.insert_all(ImportedRecord, batch)
      {:ok, length(batch)}
    end)
    |> Lazy.stream_collect(settle: true)
  end
end
```

### Config-Driven Feature with Lens Updates

```elixir
defmodule MyApp.Settings do
  alias FnTypes.{Lens, Config, Maybe}

  @theme_lens Lens.path([:preferences, :theme])
  @notifications_lens Lens.path([:preferences, :notifications, :enabled])

  def load_with_overrides(user_settings) do
    user_settings
    |> Lens.set_default(@theme_lens, Config.string("DEFAULT_THEME", "light"))
    |> Lens.update_if(@notifications_lens, fn enabled ->
      enabled and Config.boolean("NOTIFICATIONS_ENABLED", true)
    end)
  end

  def toggle_theme(settings) do
    Lens.update(@theme_lens, settings, fn
      "dark" -> "light"
      _ -> "dark"
    end)
  end
end
```

### Error Handling with Normalization + Protocols

```elixir
defmodule MyApp.ErrorHandler do
  alias FnTypes.{Error, Result}

  def handle_result(result, conn) do
    result
    |> Result.map_error(&Error.normalize/1)
    |> Result.map_error(fn error ->
      error
      |> Error.with_context(request_id: conn.assigns.request_id)
      |> Error.with_context(user_id: conn.assigns[:current_user_id])
    end)
    |> case do
      {:ok, data} ->
        json(conn, 200, data)

      {:error, error} ->
        Error.handle(error, :log)
        {status, body} = Error.handle(error, :http)
        json(conn, status, body)
    end
  end
end
```

---

## Module Quick Reference

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `Result` | Error handling | `and_then`, `map`, `or_else`, `collect`, `traverse` |
| `Maybe` | Optional values | `from_nilable`, `map`, `unwrap_or`, `fetch_path` |
| `Pipeline` | Workflows | `step`, `parallel`, `branch`, `run_with_rollback` |
| `AsyncResult` | Concurrency | `parallel`, `race`, `hedge`, `retry`, `stream` |
| `Validation` | Error accumulation | `field`, `nested`, `each`, `to_result` |
| `Error` | Structured errors | `new`, `normalize`, `handle`, `with_context` |
| `Lens` | Nested data | `key`, `path`, `get`, `set`, `compose` |
| `Ior` | Success+warnings | `partial`, `and_then`, `add_warning`, `to_result` |
| `Lazy` | Deferred/streams | `defer`, `stream`, `paginate`, `stream_collect` |
| `Diff` | Data comparison | `diff`, `patch`, `merge3`, `reverse` |
| `Retry` | Fault tolerance | `execute`, `transaction` |
| `Backoff` | Delay strategies | `exponential`, `linear`, `delay` |
| `Timing` | Performance | `measure`, `benchmark`, `format` |
| `Resource` | Safe cleanup | `with_resource`, `with_resources`, `bracket` |
| `Guards` | Pattern matching | `is_ok`, `is_error`, `is_some`, `is_none` |
| `NonEmptyList` | Non-empty lists | `new`, `head`, `from_list`, `map`, `reduce` |
| `RateLimiter` | Rate control | `new`, `check` (token_bucket, sliding_window, etc.) |
| `Throttler` | Execution throttle | `start_link`, `call` |
| `Debouncer` | Execution debounce | `start_link`, `call`, `cancel` |
| `Config` | Env var access | `string`, `integer`, `boolean`, `first_of` |
| `SideEffects` | Effect docs | `@side_effects`, `list`, `validate` |
| `Testing` | Test assertions | `assert_ok`, `assert_error`, `assert_some` |
