# Development Guidelines

> **Quick References:** See `docs/claude/` for detailed examples and patterns.

## Project Guidelines

- Run `mix precommit` before committing
- Use `Req` for HTTP requests (not HTTPoison, Tesla, or HTTPc)

---

## Code Style: The 5 Rules

### 1. Pattern Matching First

```elixir
# CORRECT - Multiple function clauses
def process({:ok, value}), do: {:ok, transform(value)}
def process({:error, reason}), do: {:error, reason}
def process(nil), do: {:error, :nil_input}

# WRONG - Nested conditionals
def process(result) do
  if result do
    case result do
      {:ok, value} -> transform(value)
      {:error, reason} -> reason
    end
  end
end
```

### 2. No If/Else

```elixir
# CORRECT - case/cond/with
case value do
  :a -> handle_a()
  :b -> handle_b()
  _ -> handle_default()
end

# WRONG - if/else chains
if value == :a do
  handle_a()
else
  if value == :b do
    handle_b()
  end
end
```

### 3. Result Tuples Everywhere

```elixir
# All fallible functions return {:ok, value} | {:error, reason}
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

### 4. No Macros (Use Functions)

```elixir
# WRONG - Macro for simple logic
defmacro double(x), do: quote do: unquote(x) * 2

# CORRECT - Plain function
def double(x), do: x * 2
```

### 5. Flat Code (No Deep Nesting)

```elixir
# CORRECT - with statement
with {:ok, user} <- create_user(attrs),
     {:ok, _} <- send_email(user),
     {:ok, _} <- create_settings(user) do
  {:ok, user}
end

# WRONG - Nested case
case create_user(attrs) do
  {:ok, user} ->
    case send_email(user) do
      {:ok, _} ->
        case create_settings(user) do
          {:ok, _} -> {:ok, user}
          error -> error
        end
      error -> error
    end
  error -> error
end
```

---

## Functional Modules

> **Full Reference:** `docs/claude/FUNCTIONAL.md`

| Module | Purpose | Returns |
|--------|---------|---------|
| `FnTypes.Result` | Error handling | `{:ok, value} \| {:error, reason}` |
| `FnTypes.Maybe` | Optional values | `{:some, value} \| :none` |
| `FnTypes.Pipeline` | Multi-step workflows | `{:ok, context} \| {:error, reason}` |
| `FnTypes.AsyncResult` | Concurrent operations | `{:ok, value} \| {:error, reason}` |
| `FnTypes.Guards` | Pattern matching | Guards + macros |

### Quick Examples

```elixir
# Result - chain operations
{:ok, user}
|> Result.and_then(&validate/1)
|> Result.and_then(&save/1)

# Maybe - optional values
Maybe.from_nilable(user.email)
|> Maybe.map(&String.downcase/1)
|> Maybe.unwrap_or("")

# Pipeline - multi-step workflow
Pipeline.new(%{params: params})
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:create, &create/1)
|> Pipeline.run()

# AsyncResult - parallel execution
AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
])

# Guards - pattern matching
def handle(r) when is_ok(r), do: :success
def handle(r) when is_error(r), do: :failure
```

### Pipeline + AsyncResult Composition

> **Full Examples:** `docs/claude/EXAMPLES.md`

| Feature | AsyncResult | Pipeline |
|---------|-------------|----------|
| Parallel execution | `parallel/2` | `parallel/3` |
| Race (first wins) | `race/2` | Use inside step |
| Retry | `retry/2` | `step_with_retry/4` |
| Batch | `batch/2` | Use inside step |
| Context | — | `step/3`, `assign/3` |
| Rollback | — | `run_with_rollback/1` |

```elixir
# Compose AsyncResult inside Pipeline steps
Pipeline.new(%{id: 123})
|> Pipeline.step(:fetch, fn ctx ->
  AsyncResult.race([
    fn -> Cache.get(ctx.id) end,
    fn -> DB.get(ctx.id) end
  ])
  |> Result.map(&%{data: &1})
end)
|> Pipeline.run()
```

---

## Schema & Migration

> **Full Reference:** `docs/claude/SCHEMA.md`, `docs/EVENTS_REFERENCE.md`

### Always Use Events Modules

```elixir
# CORRECT
use Events.Schema
use Events.Migration

# WRONG
use Ecto.Schema
use Ecto.Migration
```

### Schema Example

```elixir
defmodule MyApp.User do
  use Events.Schema
  import Events.Core.Schema.Presets

  schema "users" do
    field :email, :string, email()
    field :name, :string, required: true

    type_fields()
    status_fields()
    audit_fields()
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> base_changeset(attrs)
    |> unique_constraints([{:email, []}])
  end
end
```

### Migration Example

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Migration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_identity(:name, :email)
    |> with_audit()
    |> with_soft_delete()
    |> with_timestamps()
    |> execute()
  end
end
```

---

## Decorators

> **Full Reference:** `docs/claude/DECORATORS.md`

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:app, :users, :get])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

| Category | Decorators |
|----------|-----------|
| Types | `returns_result`, `returns_maybe`, `returns_bang`, `normalize_result` |
| Cache | `cacheable`, `cache_put`, `cache_evict` |
| Telemetry | `telemetry_span`, `log_call`, `log_if_slow` |
| Security | `role_required`, `rate_limit`, `audit_log` |

---

## S3 API

> **Full Reference:** `docs/claude/S3.md`

```elixir
alias Events.Services.S3

# Direct API
config = S3.from_env()
{:ok, data} = S3.get("s3://bucket/file.txt", config)
:ok = S3.put("s3://bucket/file.txt", "content", config)

# Pipeline API
S3.new(config)
|> S3.bucket("my-bucket")
|> S3.prefix("uploads/")
|> S3.put("file.txt", content)
```

---

## HTTP Layer (Req)

```elixir
# Default: 3 retries, respect proxies
Req.get!("https://api.example.com/users",
  retry: :safe_transient,
  max_retries: 3
)
```

---

## Database Conventions

### Field Types

| Use Case | Migration | Schema |
|----------|-----------|--------|
| Names, identifiers | `:citext` | `:string` |
| Long text | `:text` | `:string` |
| Structured data | `:jsonb` | `:map` |
| Timestamps | `:utc_datetime_usec` | `:utc_datetime_usec` |
| Money | `:integer` (cents) | `:integer` |

### Soft Delete

```elixir
# Migration
deleted_fields()

# Query - always filter
def list_products do
  from p in Product, where: is_nil(p.deleted_at)
end

# Soft delete
def delete_product(product, deleted_by_id) do
  product
  |> Ecto.Changeset.change(%{
    deleted_at: DateTime.utc_now(),
    deleted_by_id: deleted_by_id
  })
  |> Repo.update()
end
```

---

## Phoenix Guidelines

### LiveView

- Use `<Layouts.app>` wrapper
- Use `<.form for={@form}>` (not `form_for`)
- Use `to_form/2` for form assigns
- Use streams for collections
- Never use `live_redirect`/`live_patch` (use `<.link navigate={}>`)

### Templates

```elixir
# CORRECT - HEEx interpolation
<div id={@id}>{@value}</div>

# For conditionals, use <%= %>
<%= if @condition do %>
  ...
<% end %>
```

---

## Elixir Guidelines

- No `String.to_atom/1` on user input
- Predicate functions end with `?` (not `is_`)
- Use `Task.async_stream` with `timeout: :infinity` for concurrent enumeration
- Lists don't support `list[index]` - use `Enum.at/2`

---

## Quick Reference

### Do This / Not That

| Never | Always |
|-------|--------|
| `if...else` | `case`, `cond`, pattern matching |
| `Repo.insert!()` | `Repo.insert()` |
| `use Ecto.Schema` | `use Events.Core.Schema` |
| Nested case | `with` statement |
| Macros for logic | Functions + pattern matching |
| Raising errors | Return `{:error, reason}` |
| `NaiveDateTime` | `DateTime` with UTC |

### Consistency Checks

```bash
mix credo --strict
mix consistency.check
mix dialyzer
```

---

## Documentation Index

| Document | Content |
|----------|---------|
| `docs/claude/PATTERNS.md` | Code patterns with CORRECT/WRONG examples |
| `docs/claude/FUNCTIONAL.md` | Result, Maybe, Pipeline, AsyncResult, Guards |
| `docs/claude/EXAMPLES.md` | 10 real-world Pipeline + AsyncResult examples |
| `docs/claude/SCHEMA.md` | Schema and Migration quick reference |
| `docs/claude/DECORATORS.md` | Decorator quick reference |
| `docs/claude/S3.md` | S3 API reference |
| `docs/functional/OVERVIEW.md` | Comprehensive functional module documentation |
| `docs/EVENTS_REFERENCE.md` | Complete Schema/Migration/Decorator reference |
