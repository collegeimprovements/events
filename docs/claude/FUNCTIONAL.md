# Functional Modules Reference

> **Quick reference for Result, Maybe, Pipeline, AsyncResult, and Guards.**
> For comprehensive examples, see `docs/functional/OVERVIEW.md`.

## Module Overview

| Module | Purpose | Returns |
|--------|---------|---------|
| `FnTypes.Result` | Error handling | `{:ok, value} \| {:error, reason}` |
| `FnTypes.Maybe` | Optional values | `{:some, value} \| :none` |
| `FnTypes.Pipeline` | Multi-step workflows | `{:ok, context} \| {:error, reason}` |
| `FnTypes.AsyncResult` | Concurrent operations | `{:ok, value} \| {:error, reason}` |
| `FnTypes.Guards` | Pattern matching | Guards + macros |

---

## FnTypes.Result

**Use for:** Database operations, API calls, any function that can fail.

```elixir
alias FnTypes.Result

# Chain operations
{:ok, user}
|> Result.and_then(&validate_user/1)
|> Result.and_then(&save_user/1)
|> Result.map(&format_response/1)

# Unwrap with default
Result.unwrap_or({:error, :not_found}, default_user())

# Collect multiple results
Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])  # {:ok, [1, 2, 3]}
Result.collect([{:ok, 1}, {:error, :bad}])       # {:error, :bad}

# Safe exception handling
Result.try_with(fn -> risky_operation() end)

# Add context to errors
{:error, :not_found}
|> Result.wrap_error(user_id: 123, action: :fetch)
```

**Functions:** `ok/1`, `error/1`, `map/2`, `and_then/2`, `or_else/2`, `unwrap!/1`, `unwrap_or/2`, `collect/1`, `traverse/2`, `try_with/1`, `wrap_error/2`

---

## FnTypes.Maybe

**Use for:** Optional config values, nullable fields, safe nested access.

```elixir
alias FnTypes.Maybe

# From nilable value
Maybe.from_nilable(nil)    # :none
Maybe.from_nilable("val")  # {:some, "val"}

# Safe nested access
user
|> Maybe.from_nilable()
|> Maybe.and_then(&Maybe.from_nilable(&1.address))
|> Maybe.and_then(&Maybe.from_nilable(&1.city))
|> Maybe.unwrap_or("Unknown")

# Map over value
{:some, "hello"}
|> Maybe.map(&String.upcase/1)  # {:some, "HELLO"}

# Filter
{:some, 5}
|> Maybe.filter(&(&1 > 3))  # {:some, 5}
|> Maybe.filter(&(&1 > 10)) # :none
```

**Functions:** `some/1`, `none/0`, `from_nilable/1`, `map/2`, `and_then/2`, `unwrap_or/2`, `unwrap_or_else/2`, `filter/2`, `collect/1`

---

## FnTypes.Pipeline

**Use for:** User registration, order processing, data import, multi-step workflows.

```elixir
alias FnTypes.Pipeline

# Basic pipeline
Pipeline.new(%{user_id: 123})
|> Pipeline.step(:fetch_user, fn ctx ->
  case Repo.get(User, ctx.user_id) do
    nil -> {:error, :not_found}
    user -> {:ok, %{user: user}}
  end
end)
|> Pipeline.step(:validate, &validate_user/1)
|> Pipeline.step(:send_email, &send_welcome/1)
|> Pipeline.run()

# With rollback
Pipeline.new(%{})
|> Pipeline.step(:reserve, &reserve_inventory/1, rollback: &release_inventory/1)
|> Pipeline.step(:charge, &charge_payment/1, rollback: &refund_payment/1)
|> Pipeline.run_with_rollback()

# Conditional step
Pipeline.step_if(pipeline, :notify,
  fn ctx -> ctx.user.notifications_enabled end,
  &send_notification/1
)

# Branching
Pipeline.branch(pipeline, :user_type, %{
  :premium => fn p -> Pipeline.step(p, :premium_flow, &premium/1) end,
  :standard => fn p -> Pipeline.step(p, :standard_flow, &standard/1) end
})

# Parallel steps
Pipeline.parallel(pipeline, [
  {:fetch_profile, &fetch_profile/1},
  {:fetch_settings, &fetch_settings/1}
])

# Checkpoints
Pipeline.checkpoint(pipeline, :after_validation)

# Cleanup that always runs
Pipeline.ensure(pipeline, :cleanup, fn ctx, result ->
  release_resources(ctx)
end)
|> Pipeline.run_with_ensure()
```

**Functions:** `new/1`, `step/3`, `step/4`, `step_if/4`, `branch/4`, `parallel/3`, `checkpoint/2`, `guard/4`, `ensure/3`, `assign/3`, `transform/4`, `tap/3`, `run/1`, `run_with_rollback/1`, `run_with_ensure/1`, `run_with_timeout/2`

---

## FnTypes.AsyncResult

**Use for:** Parallel API calls, concurrent queries, race conditions, retry with backoff.

> **Full reference:** See `ASYNC_RESULT.md` for comprehensive documentation.

```elixir
alias FnTypes.AsyncResult

# Parallel execution (fail-fast)
AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
])
# {:ok, [user, orders]} or {:error, first_error}

# Parallel map
AsyncResult.parallel_map(user_ids, &fetch_user/1, max_concurrency: 10)

# Settle all (collect successes and failures)
AsyncResult.parallel_settle([...])
# %{ok: [1, 3], errors: [:bad], results: [...]}

# Track which inputs failed
AsyncResult.parallel_map_indexed(ids, &fetch/1)
# %{ok: [{1, val1}], errors: [{2, :not_found}], ...}

# Race - first success wins
AsyncResult.race([
  fn -> fetch_from_cache() end,
  fn -> fetch_from_db() end
])

# Explicit task handles
handle = AsyncResult.async(fn -> expensive_op() end)
do_other_work()
{:ok, result} = AsyncResult.await(handle)

# Pre-computed for mixed sync/async
handles = Enum.map(items, fn item ->
  case Cache.get(item) do
    {:ok, v} -> AsyncResult.completed({:ok, v})
    :miss -> AsyncResult.async(fn -> fetch(item) end)
  end
end)
AsyncResult.await_many(handles)

# Streaming large collections
items
|> AsyncResult.stream(&process/1, on_error: :skip)
|> Stream.map(fn {:ok, v} -> v end)
|> Enum.each(&save/1)

# Supervised (crash isolation)
AsyncResult.supervised(tasks, supervisor: MyApp.TaskSupervisor)

# Fire and forget
AsyncResult.fire_and_forget(fn -> send_analytics(event) end)

# Retry with exponential backoff
AsyncResult.retry(fn -> flaky_api() end,
  max_attempts: 3, initial_delay: 100
)
```

**Key Functions:**

| Category | Functions |
|----------|-----------|
| Parallel | `parallel/2`, `parallel_map/3`, `parallel_settle/2`, `parallel_map_indexed/3` |
| Handles | `async/1`, `await/2`, `await_many/2`, `yield/2`, `shutdown/2`, `completed/1` |
| Racing | `race/2`, `race_with_fallback/3`, `first_ok/1` |
| Streaming | `stream/3`, `stream_ok/3`, `stream_settle/3` |
| Supervised | `supervised/2`, `supervised_map/3`, `async_nolink/2` |
| Side Effects | `fire_and_forget/2`, `run_all/3`, `take_ok/4` |
| Utilities | `retry/2`, `batch/2`, `combine/3`, `with_timeout/2` |

---

## FnTypes.Guards

**Use for:** Pattern matching in function heads, cleaner case statements.

```elixir
import Events.Guards

# Guard macros in function heads
def handle(result) when is_ok(result), do: :success
def handle(result) when is_error(result), do: :failure

def process(maybe) when is_some(maybe), do: :present
def process(maybe) when is_none(maybe), do: :absent

def validate(s) when is_non_empty_string(s), do: :valid
def check(list) when is_non_empty_list(list), do: :has_items
def verify(n) when is_positive_integer(n), do: :positive

# Pattern matching macros in case
case fetch_user(id) do
  ok(user) -> process(user)
  error(reason) -> handle_error(reason)
end

case get_optional_value() do
  some(value) -> use(value)
  none() -> use_default()
end
```

**Guards:** `is_ok/1`, `is_error/1`, `is_result/1`, `is_some/1`, `is_none/1`, `is_maybe/1`, `is_non_empty_string/1`, `is_non_empty_list/1`, `is_positive_integer/1`

**Pattern Macros:** `ok/1`, `error/1`, `some/1`, `none/0`

---

## Pipeline + AsyncResult Composition

Use AsyncResult **inside** Pipeline steps for async operations.

| Feature | AsyncResult | Pipeline | Composition |
|---------|-------------|----------|-------------|
| Parallel execution | `parallel/2` | `parallel/3` | Pipeline wraps AsyncResult |
| Race (first wins) | `race/2` | — | Use inside step |
| Retry | `retry/2` | `step_with_retry/4` | Both available |
| Timeout | `with_timeout/2` | `run_with_timeout/2` | Different levels |
| Batch | `batch/2` | — | Use inside step |
| Context | — | `step/3`, `assign/3` | Pipeline-only |
| Rollback | — | `run_with_rollback/1` | Pipeline-only |

```elixir
# Race inside Pipeline step
Pipeline.new(%{id: 123})
|> Pipeline.step(:fetch_data, fn ctx ->
  AsyncResult.race([
    fn -> Cache.get(ctx.id) end,
    fn -> DB.get(ctx.id) end
  ])
  |> Result.map(&%{data: &1})
end)
|> Pipeline.run()

# Parallel enrichment inside Pipeline step
Pipeline.new(%{user: user})
|> Pipeline.step(:enrich, fn ctx ->
  AsyncResult.parallel([
    fn -> fetch_preferences(ctx.user.id) end,
    fn -> fetch_notifications(ctx.user.id) end
  ])
  |> Result.map(fn [prefs, notifs] ->
    %{preferences: prefs, notifications: notifs}
  end)
end)
|> Pipeline.run()
```

See `docs/claude/EXAMPLES.md` for comprehensive real-world examples.
