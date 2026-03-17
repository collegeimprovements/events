# Dag Workflow Cheatsheet

## Components

### Step — basic function

```elixir
# 1-arity (simple pipelines)
Step.new(:upcase, fn text -> {:ok, String.upcase(text)} end)

# 2-arity (access context, multiple predecessors)
Step.new(:fetch, fn inputs, ctx -> {:ok, fetch(inputs.url, ctx[:api_key])} end)

# With options
Step.new(:call_api, fn v -> {:ok, api(v)} end,
  name: "Call API",
  timeout: 5000,
  retries: 3,
  retry_delay: 100,
  retry_backoff: :exponential
)
```

### Rule — conditional activation

```elixir
# Only fires when condition returns true
Rule.new(:guard,
  condition: fn value -> value > 10 end,
  action: fn value -> {:ok, value * 2} end
)

# 2-arity with context
Rule.new(:threshold,
  condition: fn inputs, ctx -> inputs[:__input__] > ctx[:limit] end,
  action: fn inputs, _ctx -> {:ok, inputs[:__input__]} end
)
```

### Branch — conditional routing

```elixir
Branch.new(:route,
  condition: fn amount -> if amount > 1000, do: :high, else: :low end
)

# Downstream steps use edge conditions
workflow
|> Workflow.add(branch)
|> Workflow.add(high_step, after: :route, edge: %{when: :high})
|> Workflow.add(low_step, after: :route, edge: %{when: :low})
```

### Saga — compensatable step

```elixir
Saga.new(:charge,
  execute: fn order -> {:ok, Payments.charge(order)} end,
  compensate: fn _inputs, result, _ctx ->
    Payments.refund(result.charge_id)
    :ok
  end
)
```

### Accumulator — fan-in reduction

```elixir
Accumulator.new(:total,
  reducer: fn value, acc -> acc + value end,
  initial: 0
)

# Custom early emit
Accumulator.new(:fast,
  reducer: fn value, acc -> [value | acc] end,
  initial: [],
  emit_when: fn acc, _received, _expected -> length(acc) >= 3 end
)
```

## Aliases

```elixir
alias Dag.Workflow
alias Dag.Components.{Step, Rule, Branch, Saga, Accumulator}
```

## Building Workflows

### Linear pipeline

```elixir
Workflow.new(:pipeline)
|> Workflow.pipe(:parse, fn text -> {:ok, String.to_integer(text)} end)
|> Workflow.pipe(:double, fn n -> {:ok, n * 2} end)
|> Workflow.pipe(:format, fn n -> {:ok, "Result: #{n}"} end)
|> Workflow.react_until_satisfied("42")
```

### Diamond pattern (shared computation)

```elixir
Workflow.new(:diamond)
|> Workflow.add(Step.new(:tokenize, fn text -> {:ok, String.split(text)} end))
|> Workflow.add(Step.new(:count, fn inputs, _ -> {:ok, length(inputs.tokenize)} end), after: :tokenize)
|> Workflow.add(Step.new(:first, fn inputs, _ -> {:ok, hd(inputs.tokenize)} end), after: :tokenize)
|> Workflow.react_until_satisfied("hello world")
```

### Fan-in

```elixir
Workflow.new(:fanin)
|> Workflow.add(Step.new(:a, fn _ -> {:ok, 10} end))
|> Workflow.add(Step.new(:b, fn _ -> {:ok, 20} end))
|> Workflow.add(Accumulator.new(:sum, reducer: &+/2, initial: 0), after: [:a, :b])
|> Workflow.react_until_satisfied(:go)
```

### Conditional routing

```elixir
Workflow.new(:routing)
|> Workflow.add(Branch.new(:check, condition: fn v -> if v > 100, do: :high, else: :low end))
|> Workflow.add(Step.new(:high, fn _ -> {:ok, :expensive} end), after: :check, edge: %{when: :high})
|> Workflow.add(Step.new(:low, fn _ -> {:ok, :cheap} end), after: :check, edge: %{when: :low})
|> Workflow.react_until_satisfied(200)
```

### Merge workflows

```elixir
auth = Workflow.new(:auth)
  |> Workflow.add(Step.new(:validate, &Auth.validate/1))

process = Workflow.new(:process)
  |> Workflow.add(Step.new(:transform, &Data.transform/1))

combined = Workflow.merge(auth, process)  # both run in parallel (no edges between them)
```

### Groups

```elixir
Workflow.new(:grouped)
|> Workflow.add(Step.new(:a, &fetch_a/1), group: :fetchers)
|> Workflow.add(Step.new(:b, &fetch_b/1), group: :fetchers)
|> Workflow.add(Accumulator.new(:merge, reducer: &collect/2, initial: []),
  after: [:a, :b]
)
```

## Execution Modes

### Run to completion

```elixir
w = Workflow.react_until_satisfied(w, input)
w = Workflow.react_until_satisfied(w, input, async: true, max_concurrency: 8)
```

### Step-by-step

```elixir
w = Workflow.react(w, input)      # one pass
w = Workflow.react(w, input)      # next pass
```

### Three-phase dispatch (external execution)

```elixir
# Single cycle
{w, runnables} = Workflow.prepare_for_dispatch(w, input)
results = Enum.map(runnables, &Dag.Runnable.execute/1)
w = Enum.reduce(results, w, fn {id, result}, w ->
  Workflow.apply_result(w, id, result)
end)

# Full loop — keep dispatching until no more runnables
defp dispatch_loop(w) do
  case Workflow.prepare_for_dispatch(w) do
    {w, []} -> w
    {w, runnables} ->
      results = Enum.map(runnables, &Dag.Runnable.execute/1)
      w = Enum.reduce(results, w, fn {id, result}, w ->
        Workflow.apply_result(w, id, result)
      end)
      dispatch_loop(w)
  end
end

{w, runnables} = Workflow.prepare_for_dispatch(w, input)
results = Enum.map(runnables, &Dag.Runnable.execute/1)
w = Enum.reduce(results, w, fn {id, r}, w -> Workflow.apply_result(w, id, r) end)
w = dispatch_loop(w)
```

### on_complete callback

```elixir
Workflow.react_until_satisfied(w, input,
  on_complete: fn component_id, result, _workflow ->
    IO.puts("#{component_id}: #{inspect(result)}")
  end
)
```

## Context

```elixir
# Scoped (per-component)
Workflow.put_context(w, :scoped, :my_step, :api_key, "sk-...")

# Global (all components)
Workflow.put_context(w, :global, :env, :prod)

# Default (fallback)
Workflow.put_context(w, :default, :timeout, 5000)

# Bulk
Workflow.put_run_context(w, %{
  _global: %{env: :prod},
  my_step: %{api_key: "sk-..."}
})
```

Resolution: scoped > global > default.

## Retry

```elixir
# Works on ALL component types
Step.new(:flaky, &call_api/1,
  retries: 3,             # max retry attempts
  retry_delay: 100,       # base delay ms
  retry_backoff: :exponential,  # :fixed | :linear | :exponential
  max_delay: 30_000       # cap for backoff
)
```

## Graft + Continue

Add components to a running/completed workflow and resume.

```elixir
w = Workflow.react_until_satisfied(w, input)

w =
  w
  |> Workflow.graft(Step.new(:extra, &process/1), after: :existing_step)
  |> Workflow.graft(Step.new(:extra2, &process2/1), after: :extra)
  |> Workflow.continue()
```

## Checkpoint / Restore

Serialize workflow state for persistence or transfer.

```elixir
# Save
checkpoint = Workflow.checkpoint(w)
binary = :erlang.term_to_binary(checkpoint)
File.write!("checkpoint.bin", binary)

# Restore
binary = File.read!("checkpoint.bin")
checkpoint = :erlang.binary_to_term(binary)
{:ok, w} = Workflow.restore(checkpoint, %{
  step_a: Step.new(:step_a, &MyModule.step_a/1),
  step_b: Step.new(:step_b, &MyModule.step_b/1)
})
```

## Error Handling

```elixir
w = Workflow.react_until_satisfied(w, input)

case w.state do
  :satisfied ->
    Workflow.raw_productions(w)

  :failed ->
    # Find root cause (skip :upstream_failure cascades)
    for {id, :failed} <- w.activations,
        (error = Workflow.error(w, id)) != :upstream_failure do
      {id, error}
    end

  :halted ->
    # Hit max_iterations safety limit
    w.metadata[:iterations]
end
```

## Validation

```elixir
case Workflow.validate(w) do
  :ok -> :ready
  {:error, {:invalid_components, errors}} -> errors   # bad function, missing id
  {:error, {:cycle_detected, path}} -> path            # DAG has cycle
  {:error, {:nodes_without_components, ids}} -> ids    # orphan DAG nodes
end
```

## Saga Compensation

```elixir
w = Workflow.react_until_satisfied(w, input)

if w.state == :failed do
  w = Workflow.compensate(w)  # runs in reverse completion order
end
```

## Inspection

```elixir
Workflow.status(w, :my_step)         # :pending | :running | :completed | :failed | ...
Workflow.raw_productions(w)          # %{step_id: value, ...}
Workflow.production(w, :my_step)     # [%Fact{...}]
Workflow.error(w, :failed_step)      # reason
Workflow.execution_log(w)            # [%{component_id, status, duration_us, timestamp}]
Workflow.ready_components(w)         # [:step_id, ...]
Workflow.lineage(w, fact_id)         # [%Fact{}, ...] causal chain
Workflow.validate(w)                 # :ok | {:error, reason}
```

## Reset

```elixir
w2 = w |> Workflow.reset() |> Workflow.react_until_satisfied(new_input)
```

## Visualization

```elixir
Workflow.to_mermaid(w)                          # Mermaid with status colors
Workflow.to_mermaid(w, show_status: false)       # Plain Mermaid
Dag.to_dot(Workflow.to_dag(w))                   # Graphviz DOT
Dag.to_ascii(Workflow.to_dag(w))                 # ASCII
```

## Component Options (all types)

| Option | Description | Default |
|--------|-------------|---------|
| `:name` | Human-readable display name | Component ID |
| `:timeout` | Execution timeout in ms | None |
| `:retries` | Max retry attempts on failure | 0 |
| `:retry_delay` | Base delay between retries (ms) | 100 |
| `:retry_backoff` | `:fixed`, `:linear`, `:exponential` | `:fixed` |
| `:max_delay` | Cap for backoff delay (ms) | 30,000 |

## Workflow States

```
:pending → :running → :satisfied
                    → :failed
                    → :halted (max_iterations)
```

## Component Statuses

```
:pending → :running → :completed
                    → :failed → (propagates downstream)
         → :skipped (branch not taken)
         → :not_activated (rule condition false)
         → :compensated (after saga rollback)
         → :compensation_failed
```

## Function Arity Rules

| Component | 1-arity receives | 2-arity receives |
|-----------|-----------------|-----------------|
| **Root** (no predecessors) | Raw workflow input | `(%{__input__: value}, ctx)` |
| **Single predecessor** | Predecessor's output value | `(%{pred_id: value}, ctx)` |
| **Multiple predecessors** | Full inputs map | `(%{pred_a: val, pred_b: val}, ctx)` |

Applies to: Step, Rule (condition + action), Branch (condition), Saga (execute).
Accumulator uses `fn value, acc -> acc` reducer (not normalized).
Saga compensate is always 3-arity: `fn inputs, result, ctx -> :ok`.
