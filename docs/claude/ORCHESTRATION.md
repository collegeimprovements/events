# Orchestration Patterns

> **When to use Pipeline, Workflow, Multi, or Effects for composing operations.**

## Quick Decision Guide

| Need | Use | Why |
|------|-----|-----|
| Sequential steps with context | `FnTypes.Pipeline` | General-purpose, in-memory |
| Database transaction | `OmCrud.Multi` | Atomic, rollback on failure |
| Long-running process | `OmScheduler.Workflow` | Persistence, resume, approval |
| Concurrent operations | `FnTypes.AsyncResult` | Parallel execution |
| Deferred/streaming | `FnTypes.Lazy` | Memory efficiency |
| Document side effects | `FnTypes.SideEffects` | Annotations for analysis |

---

## Pipeline vs Multi vs Workflow

### FnTypes.Pipeline

**Use for**: In-memory multi-step operations with shared context.

```elixir
alias FnTypes.Pipeline

Pipeline.new(%{user_id: 123})
|> Pipeline.step(:fetch_user, fn ctx ->
  case Repo.get(User, ctx.user_id) do
    nil -> {:error, :not_found}
    user -> {:ok, %{user: user}}
  end
end)
|> Pipeline.step(:validate, fn ctx ->
  case User.active?(ctx.user) do
    true -> {:ok, %{}}
    false -> {:error, :inactive_user}
  end
end)
|> Pipeline.step(:send_email, fn ctx ->
  Mailer.send_welcome(ctx.user)
  {:ok, %{email_sent: true}}
end)
|> Pipeline.run()
#=> {:ok, %{user_id: 123, user: %User{}, email_sent: true}}
#   | {:error, {:step_failed, :fetch_user, :not_found}}
```

**Characteristics**:
- In-memory execution
- Context accumulates across steps
- Early termination on error
- Optional rollback support
- Parallel step execution
- Telemetry integration

### OmCrud.Multi

**Use for**: Database transactions that must be atomic.

```elixir
alias OmCrud.Multi

Multi.new()
|> Multi.create(:user, User, %{email: "test@example.com"})
|> Multi.create(:account, Account, fn %{user: u} ->
  %{owner_id: u.id, name: "Default"}
end)
|> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
  %{user_id: u.id, account_id: a.id, role: :owner}
end)
|> OmCrud.run()
#=> {:ok, %{user: %User{}, account: %Account{}, membership: %Membership{}}}
#   | {:error, :user, changeset, %{}}
```

**Characteristics**:
- Database transaction wrapper
- All-or-nothing execution
- Automatic rollback on failure
- Access to previous results
- Supports bulk operations

### OmScheduler.Workflow

**Use for**: Long-running, persistent workflows with human approval or external dependencies.

```elixir
defmodule MyApp.OnboardingWorkflow do
  use Events.Extensions.Decorator,
    name: :user_onboarding,
    schedule: [manual: true]  # Triggered programmatically

  @decorate step()
  def create_account(ctx) do
    {:ok, %{account: Accounts.create!(ctx.user_id)}}
  end

  @decorate step(after: :create_account, await_approval: true)
  def verify_identity(ctx) do
    # Pauses workflow until approved
    {:ok, %{verified: true}}
  end

  @decorate step(after: :verify_identity, rollback: :refund_payment)
  def charge_payment(ctx) do
    {:ok, %{payment: Payments.charge(ctx.account)}}
  end

  @decorate step(after: :charge_payment)
  def activate_account(ctx) do
    Accounts.activate(ctx.account)
  end

  def refund_payment(ctx) do
    Payments.refund(ctx.payment)
  end
end

# Start workflow
{:ok, execution_id} = Workflow.start(:user_onboarding, %{user_id: 123})

# Later: approve the identity verification step
Workflow.approve(execution_id, :verify_identity)
```

**Characteristics**:
- Persistent state (survives restarts)
- Human approval gates
- Scheduled execution (cron)
- DAG-based dependencies
- Automatic retries
- Compensation/rollback

---

## Combining Orchestration Patterns

### Pipeline + Multi (Database Steps in Pipeline)

Use `Pipeline.transaction/3` to embed atomic database operations:

```elixir
Pipeline.new(%{user_attrs: attrs, send_welcome: true})
|> Pipeline.step(:validate, fn ctx ->
  case User.validate(ctx.user_attrs) do
    :ok -> {:ok, %{}}
    {:error, _} = err -> err
  end
end)
|> Pipeline.transaction(:create_user, fn ctx ->
  # Returns Multi - executed atomically
  Multi.new()
  |> Multi.create(:user, User, ctx.user_attrs)
  |> Multi.create(:profile, Profile, fn %{user: u} ->
    %{user_id: u.id}
  end)
end)
|> Pipeline.step_if(:send_email,
  fn ctx -> ctx.send_welcome end,
  fn ctx ->
    Mailer.send_welcome(ctx.user)
    {:ok, %{}}
  end
)
|> Pipeline.run()
```

### Pipeline + AsyncResult (Parallel Steps)

```elixir
Pipeline.new(%{user_id: 123})
|> Pipeline.step(:fetch_user, &fetch_user/1)
|> Pipeline.parallel([
  {:fetch_orders, &fetch_orders/1},
  {:fetch_preferences, &fetch_preferences/1},
  {:fetch_notifications, &fetch_notifications/1}
])
|> Pipeline.step(:build_dashboard, fn ctx ->
  {:ok, %{dashboard: build_dashboard(ctx)}}
end)
|> Pipeline.run()
```

### Pipeline + Lazy (Streaming Large Data)

```elixir
Pipeline.new(%{query: User})
|> Pipeline.step(:stream_users, fn ctx ->
  users =
    ctx.query
    |> Repo.stream()
    |> Lazy.stream(&process_user/1, on_error: :skip)
    |> Lazy.stream_collect()

  case users do
    {:ok, processed} -> {:ok, %{users: processed}}
    {:error, _} = err -> err
  end
end)
|> Pipeline.run()
```

---

## Decision Matrix

### Use Pipeline When:

- Steps are in-memory transformations
- You need accumulated context
- Operations are relatively fast
- You want declarative step composition
- Rollback is optional/simple

### Use Multi When:

- All operations touch the database
- You need transactional guarantees
- Failure should roll back everything
- Operations are CRUD-focused

### Use Workflow When:

- Process spans hours/days
- Human approval is required
- State must survive restarts
- You need scheduled execution
- Complex dependency graphs
- Compensation logic is critical

### Use AsyncResult When:

- Operations are independent
- You want parallel execution
- Racing alternatives (first wins)
- Batch processing with concurrency

### Use Lazy When:

- Processing large datasets
- Memory efficiency matters
- Deferred computation
- Paginated API consumption

---

## Anti-Patterns

### Don't: Nest Pipelines Deeply

```elixir
# BAD - Hard to follow
Pipeline.new(%{})
|> Pipeline.step(:outer, fn ctx ->
  inner_result =
    Pipeline.new(ctx)
    |> Pipeline.step(:inner1, ...)
    |> Pipeline.step(:inner2, ...)
    |> Pipeline.run()

  case inner_result do
    {:ok, inner_ctx} -> {:ok, inner_ctx}
    {:error, _} = err -> err
  end
end)

# GOOD - Use composition
inner_segment = Pipeline.segment([
  {:inner1, &inner1/1},
  {:inner2, &inner2/1}
])

Pipeline.new(%{})
|> Pipeline.step(:outer, &outer/1)
|> Pipeline.include(inner_segment)
|> Pipeline.run()
```

### Don't: Use Pipeline for Pure Database Transactions

```elixir
# BAD - Not atomic
Pipeline.new(%{})
|> Pipeline.step(:create_user, fn _ ->
  case Repo.insert(user_changeset) do
    {:ok, user} -> {:ok, %{user: user}}
    {:error, cs} -> {:error, cs}
  end
end)
|> Pipeline.step(:create_account, fn ctx ->
  # If this fails, user is already created!
  case Repo.insert(account_changeset(ctx.user)) do
    {:ok, account} -> {:ok, %{account: account}}
    {:error, cs} -> {:error, cs}
  end
end)

# GOOD - Atomic transaction
Multi.new()
|> Multi.create(:user, User, user_attrs)
|> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
|> OmCrud.run()
```

### Don't: Use Workflow for Simple Sequences

```elixir
# BAD - Overkill for simple operations
defmodule SimpleWorkflow do
  use Events.Extensions.Decorator, name: :simple

  @decorate step()
  def validate(ctx), do: {:ok, %{}}

  @decorate step(after: :validate)
  def transform(ctx), do: {:ok, %{}}
end

# GOOD - Just use Pipeline or even `with`
with {:ok, validated} <- validate(input),
     {:ok, transformed} <- transform(validated) do
  {:ok, transformed}
end
```

---

## Side Effect Annotations

Use `FnTypes.SideEffects` to document what side effects functions produce:

```elixir
defmodule MyApp.Orders do
  use FnTypes.SideEffects

  @side_effects [:db_read]
  def get_order(id), do: Repo.get(Order, id)

  @side_effects [:db_write, :external_api, :email]
  def complete_order(order) do
    with {:ok, order} <- mark_complete(order),
         {:ok, _} <- notify_warehouse(order),
         {:ok, _} <- send_confirmation(order) do
      {:ok, order}
    end
  end

  @side_effects [:pure]
  def calculate_total(items) do
    Enum.sum(items, & &1.price * &1.quantity)
  end
end

# Query side effects
FnTypes.SideEffects.with_effect(MyApp.Orders, :db_write)
#=> [{:complete_order, 1}]

FnTypes.SideEffects.pure?(MyApp.Orders, :calculate_total, 1)
#=> true
```

---

## Summary

| Pattern | State | Atomicity | Duration | Use Case |
|---------|-------|-----------|----------|----------|
| Pipeline | In-memory | No | Seconds | Request processing |
| Multi | Database | Yes | Seconds | CRUD transactions |
| Workflow | Persistent | Compensating | Hours/Days | Business processes |
| AsyncResult | In-memory | No | Seconds | Parallel operations |
| Lazy | Streaming | No | Variable | Large datasets |
