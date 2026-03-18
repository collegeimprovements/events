# Effect Cheatsheet

> Composable, resumable workflow orchestration with DAG-based execution and saga patterns. For full docs, see `README.md`.

## Quick Start

```elixir
Effect.new(:order_processing)
|> Effect.step(:validate, &validate/1)
|> Effect.step(:charge, &charge/1, retry: [max: 3], rollback: &refund/1)
|> Effect.step(:fulfill, &fulfill/1, after: :charge, rollback: &cancel_fulfillment/1)
|> Effect.step(:notify, &notify/1, after: :fulfill)
|> Effect.run(%{order_id: 123, amount: 9900})
#=> {:ok, final_context} | {:error, %Effect.Error{}}
```

---

## Building Effects

```elixir
# Create
effect = Effect.new(:name)
effect = Effect.new(:name, label: "...", tags: [:critical], metadata: %{v: 1})

# Steps
|> Effect.step(:name, &function/1)
|> Effect.step(:name, &function/1, after: :dependency)
|> Effect.step(:name, &function/1,
  after: :dep,
  timeout: 30_000,
  retry: [max: 3, delay: 1000, backoff: :exponential],
  when: fn ctx -> ctx.amount > 0 end,
  rollback: &rollback_fn/1,
  catch: &error_handler/1,
  fallback: %{default: true}
)

# Static values
|> Effect.assign(:key, value)
|> Effect.assign(:key, fn ctx -> compute(ctx) end)

# Side effects (no context change)
|> Effect.tap(:log, fn ctx -> Logger.info("Order #{ctx.order_id}") end)

# Preconditions
|> Effect.require(:auth, fn ctx -> ctx.user.admin? end, :unauthorized)

# Validation
|> Effect.validate(:check, fn ctx ->
  if ctx.amount > 0, do: :ok, else: {:error, :invalid}
end)
```

---

## Step Return Values

| Return | Behavior |
|--------|----------|
| `{:ok, map}` | Merge map into context, continue |
| `{:error, term}` | Stop, trigger rollbacks |
| `{:halt, term}` | Stop gracefully, no rollback |

---

## Step Options

| Option | Description |
|--------|-------------|
| `after: :step` | Dependency (or list) |
| `timeout: ms` | Per-attempt timeout |
| `retry: [max: 3]` | Retry config |
| `when: &predicate/1` | Skip if false |
| `rollback: &fn/1` | Rollback on failure |
| `catch: &fn/1` | Error handler |
| `fallback: value` | Default on error |

---

## Retry

```elixir
|> Effect.step(:api_call, &call/1,
  retry: [
    max: 5,                          # max attempts
    delay: 1000,                     # initial delay (ms)
    backoff: :exponential,           # :fixed | :linear | :exponential
    max_delay: 30_000,               # cap delay
    jitter: 0.25,                    # random jitter (0-1)
    when: fn {:error, r} -> r in [:timeout, :unavailable] end
  ]
)
```

---

## Parallel Steps

```elixir
# Steps with same `after:` but no dependency on each other run in parallel
|> Effect.step(:fetch_user, &fetch_user/1)
|> Effect.step(:fetch_orders, &fetch_orders/1, after: :fetch_user)
|> Effect.step(:fetch_prefs, &fetch_prefs/1, after: :fetch_user)
# fetch_orders and fetch_prefs run concurrently

# Explicit parallel group
|> Effect.parallel(:fetch_all, [
  {:user, &fetch_user/1},
  {:orders, &fetch_orders/1},
  {:prefs, &fetch_prefs/1}
])
```

---

## Branching

```elixir
|> Effect.branch(:route, fn ctx ->
  if ctx.premium?, do: :premium_flow, else: :standard_flow
end)
|> Effect.step(:premium_flow, &premium_process/1, when: fn ctx -> ctx.premium? end)
|> Effect.step(:standard_flow, &standard_process/1, when: fn ctx -> !ctx.premium? end)
```

---

## Saga (Rollback)

```elixir
Effect.new(:order)
|> Effect.step(:reserve, &reserve/1, rollback: &release/1)
|> Effect.step(:charge, &charge/1, rollback: &refund/1)
|> Effect.step(:ship, &ship/1)
|> Effect.run(ctx)

# If :ship fails, rollbacks run in reverse:
# 1. refund (charge rollback)
# 2. release (reserve rollback)
```

---

## Checkpoints (Resume)

```elixir
# Save checkpoint
|> Effect.checkpoint(:after_payment)

# Resume from checkpoint (execution_id is a String returned from checkpoint)
Effect.resume(effect, execution_id)
```

---

## Execution

```elixir
# Run
{:ok, context} = Effect.run(effect, initial_context)
{:error, %Effect.Error{step: :charge, reason: :declined}} = Effect.run(effect, ctx)

# Run with options
Effect.run(effect, ctx, timeout: 60_000, telemetry: true)
```

---

## Middleware

```elixir
|> Effect.middleware(:logging, fn step, ctx, next ->
  Logger.info("Starting #{step}")
  result = next.()
  Logger.info("Completed #{step}")
  result
end)
```

---

## Composition

```elixir
# Embed sub-effect
|> Effect.embed(:sub_workflow, child_effect)
```

---

## Introspection

```elixir
Effect.step_names(effect)                          #=> [:validate, :charge, ...]
Effect.to_ascii(effect)                            # ASCII diagram
Effect.to_mermaid(effect)                          # Mermaid diagram
Effect.summary(effect)                             # Summary map
```
