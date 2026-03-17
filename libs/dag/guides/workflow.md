# Dag.Workflow Guide

## Overview

`Dag.Workflow` is a composable dataflow engine built on top of the `Dag` graph library. It combines:

- **Typed components** — Step, Rule, Branch, Saga, Accumulator
- **Fact-based data flow** — immutable, traceable values between components
- **Three-phase execution** — prepare, execute, apply (decoupled for distributed dispatch)
- **Scoped context** — per-component runtime configuration

```elixir
alias Dag.{Workflow, Components.Step}

workflow =
  Workflow.new(:text_analysis)
  |> Workflow.pipe(:tokenize, fn text -> {:ok, String.split(text)} end)
  |> Workflow.pipe(:count, fn tokens -> {:ok, length(tokens)} end)
  |> Workflow.pipe(:first, fn tokens -> {:ok, hd(tokens)} end)
  |> Workflow.react_until_satisfied("hello world")

Workflow.raw_productions(workflow)
#=> %{tokenize: ["hello", "world"], count: 2, first: "hello"}
```

## Why Fact-Based Data Flow?

Traditional workflow engines pass a mutable context map through all steps. Dag.Workflow uses **facts** — immutable typed values that carry provenance.

```
Context Map Passing                    Fact-Based Data Flow
──────────────────────                 ────────────────────
ctx = %{input: "hello"}               tokenize produces Fact(["hello", "world"])
ctx = step_a(ctx)                     count reads tokenize's fact → Fact(2)
ctx = step_b(ctx)                     first reads tokenize's fact → Fact("hello")
# step_b can see/corrupt step_a       # count and first are independent
# no data lineage                      # full lineage: fact → source component
# diamond patterns re-execute          # shared computation: one fact, many readers
```

Benefits:
- **Shared computation** — diamond dependencies read the same fact without re-executing
- **Data lineage** — trace any value back through the DAG to its origin
- **Isolation** — components can't corrupt each other's data
- **Replay** — re-execute from any point using cached facts

## Component Types

### When to Use Which

| Situation | Component | Why |
|-----------|-----------|-----|
| Transform data | **Step** | Simple input → output |
| Conditional execution | **Rule** | Only fires when condition is true |
| Route to different paths | **Branch** | Produces tagged fact, downstream uses `edge: %{when: :tag}` |
| Need rollback on failure | **Saga** | Has compensate function for undo |
| Merge parallel results | **Accumulator** | Reduces multiple predecessor values into one |

### Step

The workhorse. Takes input, applies function, produces output.

```elixir
Step.new(:transform, fn value -> {:ok, String.upcase(value)} end)
```

### Rule

Fires only when condition returns true. If condition is false, the rule and its downstream chain become `:not_activated`.

```elixir
Rule.new(:guard,
  condition: fn value -> value > 100 end,
  action: fn value -> {:ok, {:alert, value}} end
)
```

Use when: you want to conditionally skip an entire branch based on data, not route between alternatives (use Branch for that).

### Branch

Evaluates a condition, produces a tagged fact. Downstream components use `edge: %{when: :tag}` to only activate on matching branches.

```elixir
Branch.new(:route, condition: fn amount -> if amount > 1000, do: :high, else: :low end)
```

The key difference from Rule: Branch always fires, always produces a fact, and the routing happens at the edge level. Rule might not fire at all.

### Saga

Like Step but with a compensate function. When a downstream step fails, the engine can roll back sagas in reverse order.

```elixir
Saga.new(:charge_payment,
  execute: fn order -> {:ok, Payments.charge(order)} end,
  compensate: fn _inputs, result, _ctx ->
    Payments.refund(result.charge_id)
    :ok
  end
)
```

### Accumulator

Fan-in component that reduces values from multiple predecessors into a single output.

```elixir
Accumulator.new(:total, reducer: fn value, acc -> acc + value end, initial: 0)
```

## Three-Phase Execution

The engine separates **what** to execute from **where** to execute it.

```
Phase 1: Prepare          Phase 2: Execute           Phase 3: Apply
─────────────────         ─────────────────          ──────────────
Component + inputs        Runnable runs in           Result → Facts
→ Runnable                isolation (any process,    → store in workflow
  (self-contained)        any node, any queue)       → propagate downstream
```

### Why Three Phases?

The Runnable carries its function, inputs, and context — nothing else. This means execution can happen:
- Locally (default)
- In a Task pool (async mode)
- In Oban/Broadway workers
- On a different node
- In a test harness with mocked inputs

### Internal Execution

```elixir
# Run everything locally, synchronously
w = Workflow.react_until_satisfied(w, input)

# Run ready components in parallel
w = Workflow.react_until_satisfied(w, input, async: true, max_concurrency: 8)
```

### External Dispatch

```elixir
# Inject input and prepare first batch
{w, runnables} = Workflow.prepare_for_dispatch(w, input)

# Execute runnables however you want
results = Enum.map(runnables, fn r ->
  # Could be: Oban.insert(MyWorker.new(%{runnable: r}))
  Dag.Runnable.execute(r)
end)

# Apply results back
w = Enum.reduce(results, w, fn {id, result}, w ->
  Workflow.apply_result(w, id, result)
end)

# Prepare next batch (components whose predecessors just completed)
{w, more_runnables} = Workflow.prepare_for_dispatch(w)
# ... repeat until no more runnables
```

## Execution Lifecycle

```
                    react_until_satisfied(input)
                    ┌─────────┐
                    │         v
:pending ──input──► :running ──► :satisfied  (all components terminal, no failures)
                    │    │
                    │    └────► :failed     (at least one component failed)
                    │
                    └─────────► :halted     (max_iterations reached)

After :satisfied or :failed:
  - graft + continue → :running again
  - reset → :pending (clean slate)
```

## Error Handling

### Result Tuples

All component functions must return `{:ok, value}` or `{:error, reason}`. Non-tuple returns are auto-wrapped as `{:ok, value}`. Exceptions are caught and returned as `{:error, {exception, stacktrace}}`.

### Failure Propagation

When a component fails, the engine marks all downstream components that have no alternative (non-failed) path as `:failed` with reason `:upstream_failure`.

```elixir
# A fails → B and C are :failed (:upstream_failure)
# But if D has TWO predecessors (A and E), and E succeeds,
# D still fires because it has a viable path.

w =
  Workflow.new(:recovery)
  |> Workflow.add(Step.new(:a, fn _ -> {:error, :boom} end))
  |> Workflow.add(Step.new(:e, fn _ -> {:ok, :backup} end))
  |> Workflow.add(Step.new(:d, fn inputs, _ -> {:ok, inputs[:e]} end), after: [:a, :e])
  |> Workflow.react_until_satisfied(:go)

Workflow.status(w, :a)  #=> :failed
Workflow.status(w, :d)  #=> :completed (e provided viable input)
```

### Inspecting Errors

```elixir
w = Workflow.react_until_satisfied(w, input)

case w.state do
  :satisfied ->
    Workflow.raw_productions(w)

  :failed ->
    # Find which components failed
    failed = Enum.filter(w.activations, fn {_, s} -> s == :failed end)

    # Get the root cause (not :upstream_failure)
    Enum.each(failed, fn {id, _} ->
      error = Workflow.error(w, id)
      if error != :upstream_failure, do: IO.inspect({id, error})
    end)

  :halted ->
    IO.puts("Hit iteration limit")
end
```

### Crash Safety

The engine handles crashes gracefully:

| Crash Location | Behavior |
|----------------|----------|
| Step/Saga/Rule function | Caught by Runnable.execute, returned as `{:error, {exception, stack}}` |
| Rule condition in `activates?` | Caught, logged as warning, component stays pending → `:not_activated` |
| Accumulator `emit_when` | Same — caught, logged, `:not_activated` |
| Saga compensation | Caught, logged, marked `:compensation_failed`, remaining sagas still compensate |
| `on_complete` callback | Caught, silently ignored, workflow unaffected |

## Patterns

### Linear Pipeline

```elixir
Workflow.new(:pipeline)
|> Workflow.pipe(:parse, fn text -> {:ok, String.to_integer(text)} end)
|> Workflow.pipe(:double, fn n -> {:ok, n * 2} end)
|> Workflow.pipe(:format, fn n -> {:ok, "Result: #{n}"} end)
|> Workflow.react_until_satisfied("42")
```

### Diamond (Shared Computation)

```elixir
Workflow.new(:diamond)
|> Workflow.add(Step.new(:fetch, fn url -> {:ok, HTTP.get!(url)} end))
|> Workflow.add(Step.new(:parse_json, fn inputs, _ -> {:ok, Jason.decode!(inputs.fetch)} end), after: :fetch)
|> Workflow.add(Step.new(:extract_ids, fn inputs, _ -> {:ok, Enum.map(inputs.parse_json, & &1["id"])} end), after: :parse_json)
|> Workflow.add(Step.new(:count, fn inputs, _ -> {:ok, length(inputs.parse_json)} end), after: :parse_json)
```

`parse_json` runs once, both `extract_ids` and `count` read the same fact.

### Fan-Out / Fan-In

```elixir
Workflow.new(:parallel)
|> Workflow.add(Step.new(:fetch_users, fn _ -> {:ok, Users.list()} end))
|> Workflow.add(Step.new(:fetch_orders, fn _ -> {:ok, Orders.list()} end))
|> Workflow.add(
  Accumulator.new(:merge,
    reducer: fn value, acc -> [value | acc] end,
    initial: []
  ),
  after: [:fetch_users, :fetch_orders]
)
```

### Conditional Routing

```elixir
Workflow.new(:routing)
|> Workflow.add(Branch.new(:check_amount,
  condition: fn order -> if order.total > 1000, do: :high_value, else: :standard end
))
|> Workflow.add(Step.new(:manual_review, fn order, _ -> {:ok, ReviewQueue.enqueue(order)} end),
  after: :check_amount, edge: %{when: :high_value}
)
|> Workflow.add(Step.new(:auto_approve, fn order, _ -> {:ok, %{order | approved: true}} end),
  after: :check_amount, edge: %{when: :standard}
)
```

### Saga Transaction

```elixir
w =
  Workflow.new(:order)
  |> Workflow.add(Saga.new(:reserve_inventory,
    execute: fn order -> {:ok, Inventory.reserve(order)} end,
    compensate: fn _, result, _ -> Inventory.release(result) ; :ok end
  ))
  |> Workflow.add(Saga.new(:charge_payment,
    execute: fn inputs, _ -> {:ok, Payments.charge(inputs.reserve_inventory)} end,
    compensate: fn _, result, _ -> Payments.refund(result) ; :ok end
  ), after: :reserve_inventory)
  |> Workflow.add(Step.new(:confirm, fn inputs, _ ->
    {:ok, Mailer.send_confirmation(inputs.charge_payment)}
  end), after: :charge_payment)
  |> Workflow.react_until_satisfied(order)

if w.state == :failed do
  Workflow.compensate(w)  # refund → release, in reverse order
end
```

### Composing Workflows

```elixir
auth_workflow =
  Workflow.new(:auth)
  |> Workflow.add(Step.new(:validate_token, &Auth.validate/1))
  |> Workflow.add(Step.new(:load_user, &Auth.load_user/1), after: :validate_token)

processing_workflow =
  Workflow.new(:process)
  |> Workflow.add(Step.new(:transform, &Data.transform/1))
  |> Workflow.add(Step.new(:store, &Data.store/1), after: :transform)

combined = Workflow.merge(auth_workflow, processing_workflow)
# Both workflows run in parallel (no edges between them)
```

### Dynamic Extension (Graft)

```elixir
# Execute initial workflow
w = Workflow.react_until_satisfied(w, input)

# Inspect results, decide to add more processing
if Workflow.raw_productions(w).classify == :needs_review do
  w =
    w
    |> Workflow.graft(Step.new(:review, &manual_review/1), after: :classify)
    |> Workflow.graft(Step.new(:notify, &send_notification/1), after: :review)
    |> Workflow.continue()
end
```

### Long-Running Workflows (Checkpoint)

```elixir
# Save state before risky operation
checkpoint = Workflow.checkpoint(w)
:ok = File.write!("workflow.bin", :erlang.term_to_binary(checkpoint))

# Later: restore and continue
binary = File.read!("workflow.bin")
checkpoint = :erlang.binary_to_term(binary)
{:ok, w} = Workflow.restore(checkpoint, component_map())

w =
  w
  |> Workflow.graft(Step.new(:next_phase, &process/1), after: :last_completed)
  |> Workflow.continue()
```

## Groups

Groups organize components for logical grouping. They don't affect execution — components still fire based on DAG dependencies — but they're useful for organization and visualization.

```elixir
Workflow.new(:grouped)
|> Workflow.add(Step.new(:fetch_a, &fetch_a/1), group: :data_fetch)
|> Workflow.add(Step.new(:fetch_b, &fetch_b/1), group: :data_fetch)
|> Workflow.add(Step.new(:fetch_c, &fetch_c/1), group: :data_fetch)
|> Workflow.add(Accumulator.new(:merge, reducer: &merge/2, initial: %{}),
  after: [:fetch_a, :fetch_b, :fetch_c]
)
```

## Callbacks

Track execution progress with `on_complete`:

```elixir
Workflow.react_until_satisfied(w, input,
  on_complete: fn component_id, result, _workflow ->
    IO.puts("#{component_id} finished: #{inspect(result)}")
  end
)
```

## Visualization

```elixir
# Mermaid with status colors (green=completed, red=failed, grey=skipped)
Workflow.to_mermaid(w)

# Plain Mermaid (no status)
Workflow.to_mermaid(w, show_status: false)

# Graphviz DOT
Dag.to_dot(Workflow.to_dag(w))

# ASCII
Dag.to_ascii(Workflow.to_dag(w))
```

## Context System

Three-level context with clear precedence: **scoped > global > default**.

```elixir
w =
  Workflow.new(:api)
  |> Workflow.put_context(:default, :timeout, 5000)           # fallback for all
  |> Workflow.put_context(:global, :api_url, "https://...")    # available to all
  |> Workflow.put_context(:scoped, :auth, :api_key, "sk-...") # only for :auth

# Or bulk:
w = Workflow.put_run_context(w, %{
  _global: %{api_url: "https://...", env: :prod},
  auth: %{api_key: "sk-..."},
  notify: %{slack_webhook: "https://..."}
})
```

Components access context as the second argument:

```elixir
Step.new(:auth, fn _inputs, ctx ->
  {:ok, authenticate(ctx[:api_url], ctx[:api_key])}
end)
```

## Validation

Check workflow structure before execution:

```elixir
case Workflow.validate(w) do
  :ok ->
    Workflow.react_until_satisfied(w, input)

  {:error, {:invalid_components, errors}} ->
    # Component validation failures (missing function, etc.)
    IO.inspect(errors)

  {:error, {:cycle_detected, path}} ->
    IO.inspect(path)

  {:error, {:nodes_without_components, ids}} ->
    # DAG has nodes that aren't registered as components
    IO.inspect(ids)
end
```
