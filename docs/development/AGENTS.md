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

### Always Use Enhanced Modules

```elixir
# CORRECT
use OmSchema        # or use Events.Schema
use OmMigration     # or use Events.Migration

# WRONG
use Ecto.Schema
use Ecto.Migration
```

### Schema Example

```elixir
defmodule MyApp.User do
  use OmSchema
  import OmSchema.Presets

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

---

## OmMigration

> Token-based migration DSL with pipelines, FieldBuilders, and full up/down support.

### Two Styles: Pipeline API vs DSL Macros

```elixir
# Pipeline API - composable, testable
create_table(:users)
|> with_uuid_primary_key()
|> with_identity(:name, :email)
|> run()

# DSL Macros - declarative, readable
table :users do
  uuid_primary_key()
  field :email, :citext
  has_authentication()
  timestamps()
end
```

### Create Table (change/0)

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use OmMigration

  def change do
    # Pipeline API
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_identity(:name, :email)
    |> with_authentication()
    |> with_audit()
    |> with_soft_delete()
    |> with_timestamps()
    |> run()
  end
end
```

### Up/Down Migrations

```elixir
defmodule MyApp.Repo.Migrations.UpdateUsers do
  use OmMigration

  def up do
    # DSL style
    alter :users do
      add :phone, :string, null: true
      add :verified_at, :utc_datetime
      modify :status, :string, null: false, default: "active"
    end

    # Or pipeline style
    alter_table(:users)
    |> add_field(:avatar_url, :string)
    |> run()
  end

  def down do
    alter :users do
      remove :phone
      remove :verified_at
      remove :avatar_url
      modify :status, :string, null: true
    end
  end
end
```

### Drop & Rename Operations

```elixir
# Drop operations
drop_table :old_table
drop_table :old_table, if_exists: true
drop_index :users, :users_email_index
drop_constraint :orders, :amount_positive

# Rename operations
rename_table :users, to: :accounts
rename_column :users, :email, to: :email_address
```

### FieldBuilders

Reusable field composition modules. Use directly or via pipeline helpers.

| Builder | Fields Added | Pipeline Helper |
|---------|--------------|-----------------|
| `Timestamps` | inserted_at, updated_at | `with_timestamps()` |
| `AuditFields` | created_by, updated_by, ip, session | `with_audit()` |
| `SoftDelete` | deleted_at, deleted_by | `with_soft_delete()` |
| `StatusFields` | status, substatus | `with_status()` |
| `TypeFields` | type, subtype | `with_type()` |
| `Identity` | email, username, phone, name fields | `with_identity()` |
| `Authentication` | password_hash, oauth, magic_link | `with_authentication()` |
| `Profile` | bio, avatar, location, social | `with_profile()` |
| `Money` | decimal fields with precision | `with_money()` |
| `Metadata` | JSONB field with GIN index | `with_metadata()` |
| `Tags` | string array with GIN index | `with_tags()` |

```elixir
# Direct FieldBuilder usage
alias OmMigration.FieldBuilders.{Identity, Authentication, Profile}

create_table(:users)
|> Identity.add(only: [:email, :username])
|> Authentication.add(type: :password, with_lockout: true)
|> Profile.add(only: [:bio, :avatar])
|> run()

# Via pipeline helpers (equivalent)
create_table(:users)
|> with_identity(:email, :username)
|> with_authentication(type: :password, with_lockout: true)
|> with_profile(:bio, :avatar)
|> run()
```

### DSL Quick Reference

```elixir
# Create table
table :users do
  uuid_primary_key()
  field :email, :citext, unique: true
  field :name, :string
  belongs_to :organization, :organizations
  has_authentication()
  has_profile()
  has_audit()
  has_soft_delete()
  has_metadata()
  has_tags()
  timestamps()
  index [:organization_id]
  unique_index [:email]
  check_constraint :email_format, "email ~* '^[^@]+@[^@]+$'"
end

# Alter table
alter :users do
  add :phone, :string
  remove :legacy_field
  modify :status, :string, null: false
end

# Drop/rename
drop_table :old_table
drop_index :users, :users_email_index
rename_table :users, to: :accounts
rename_column :users, :email, to: :email_address
```

### Pipeline Quick Reference

| Operation | Function |
|-----------|----------|
| Create table | `create_table(:name) \|> ... \|> run()` |
| Alter table | `alter_table(:name) \|> add_field() \|> run()` |
| Drop table | `drop_table(:name) \|> run()` |
| Create index | `create_index(:table, [:cols]) \|> run()` |
| Drop index | `drop_index(:table, :index_name) \|> run()` |
| Rename table | `rename_table(:old, to: :new) \|> run()` |
| Rename column | `rename_column(:table, from: :old, to: :new) \|> run()` |

### TokenValidator

Automatic validation before execution. Catches errors early with clear messages.

```elixir
# Validation happens automatically in run()
# To skip (not recommended):
Executor.execute(token, skip_validation: true)

# Manual validation
{:ok, token} = TokenValidator.validate(token)
{:error, errors} = TokenValidator.validate(invalid_token)
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

## Caching

> **Full Reference:** `docs/claude/CACHING.md`

### Use Presets for Common Patterns

```elixir
alias FnDecorator.Caching.Presets

# High availability - serves stale data, auto-refreshes
@decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
def get_user(id), do: Repo.get(User, id)

# Always fresh - critical config
@decorate cacheable(Presets.always_fresh(cache: MyApp.Cache, key: :feature_flags))
def get_flags, do: ConfigService.fetch()

# External API - resilient to outages
@decorate cacheable(Presets.external_api(cache: MyApp.Cache, key: {:weather, city}))
def get_weather(city), do: WeatherAPI.fetch(city)
```

### Preset Selection Guide

| Use Case | Preset | Why |
|----------|--------|-----|
| User reads | `high_availability` | Tolerate staleness, prioritize availability |
| Feature flags | `always_fresh` | Must be current, short TTL |
| Third-party API | `external_api` | Survive outages, long stale window |
| Reports | `expensive` | Long TTL, cron refresh |
| Sessions | `session` | No stale serving |
| DB queries | `database` | Standard caching pattern |

### Creating Custom Presets

```elixir
# lib/my_app/cache_presets.ex
defmodule MyApp.CachePresets do
  alias FnDecorator.Caching.Presets

  def microservice(opts \\ []) do
    Presets.merge([
      store: [ttl: :timer.seconds(30)],
      refresh: [on: :stale_access],
      serve_stale: [ttl: :timer.minutes(5)]
    ], opts)
  end
end

# Usage
@decorate cacheable(MyApp.CachePresets.microservice(cache: MyApp.Cache, key: {:orders, id}))
def get_orders(id), do: OrderService.fetch(id)
```

---

## S3 API

> **Full Reference:** `docs/claude/S3.md`

```elixir
# Direct API
config = OmS3.from_env()
{:ok, data} = OmS3.get("s3://bucket/file.txt", config)
:ok = OmS3.put("s3://bucket/file.txt", "content", config)

# Pipeline API
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.prefix("uploads/")
|> OmS3.put("file.txt", content)
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
| `use Ecto.Schema` | `use OmSchema` |
| `use Ecto.Migration` | `use OmMigration` |
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
| `docs/claude/CACHING.md` | Caching presets, @cacheable API, custom presets |
| `docs/claude/S3.md` | S3 API reference |
| `docs/functional/OVERVIEW.md` | Comprehensive functional module documentation |
| `docs/EVENTS_REFERENCE.md` | Complete Schema/Migration/Decorator reference |
| `libs/om_migration/CHANGELOG.md` | OmMigration changelog and feature list |
| `libs/om_migration/README.md` | OmMigration full documentation |
