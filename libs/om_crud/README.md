# OmCrud

Unified CRUD operations for Ecto with token-based execution, Multi transactions, PostgreSQL MERGE, batch processing, soft deletes, atomic helpers, and context generators.

## Installation

```elixir
def deps do
  [{:om_crud, "~> 0.1.0"}]
end
```

## 1 min Setup Guide

**1. Add dependency** (`mix.exs`):

```elixir
{:om_crud, "~> 0.1.0"}
```

**2. Configure** (`config/config.exs`):

```elixir
config :om_crud,
  default_repo: MyApp.Repo,                 # Required for all CRUD operations
  telemetry_prefix: [:my_app, :crud]         # Optional: telemetry events
```

No supervision, no environment variables. You can also pass `repo: MyApp.Repo` per-call to override the default.

## Why OmCrud?

Without OmCrud, CRUD operations are scattered and inconsistent:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RAW ECTO APPROACH                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Every module has different patterns                                      │
│  Repo.insert(changeset)              # Returns {:ok, record} | {:error, _}  │
│  Repo.get(User, id)                  # Returns record | nil                 │
│  Repo.get!(User, id)                 # Raises on not found                  │
│  Repo.update(changeset)              # Need to build changeset first        │
│  Repo.delete(record)                 # Different return types               │
│                                                                             │
│  # Multi transactions are verbose                                           │
│  Ecto.Multi.new()                                                           │
│  |> Ecto.Multi.insert(:user, changeset)                                     │
│  |> Ecto.Multi.run(:account, fn repo, %{user: u} ->                        │
│       cs = Account.changeset(%Account{}, %{owner_id: u.id})                │
│       repo.insert(cs)                                                       │
│     end)                                                                    │
│  |> Repo.transaction()                                                      │
│                                                                             │
│  # Context modules are boilerplate-heavy                                    │
│  def create_user(attrs) do                                                  │
│    %User{}                                                                  │
│    |> User.changeset(attrs)                                                 │
│    |> Repo.insert()                                                         │
│  end                                                                        │
│  # Repeat for every schema...                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    ▼

┌─────────────────────────────────────────────────────────────────────────────┐
│                          WITH OMCRUD                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Consistent API for all operations                                        │
│  OmCrud.create(User, attrs)          # Always {:ok, record} | {:error, _}   │
│  OmCrud.fetch(User, id)              # Always {:ok, record} | {:error, _}   │
│  OmCrud.update(user, attrs)          # Changeset handled automatically      │
│  OmCrud.delete(user)                 # Consistent return types              │
│                                                                             │
│  # Multi transactions are clean pipelines                                   │
│  Multi.new()                                                                │
│  |> Multi.create(:user, User, attrs)                                        │
│  |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)│
│  |> OmCrud.run()                                                            │
│                                                                             │
│  # Context modules are one-liners                                           │
│  defmodule Accounts do                                                      │
│    use OmCrud.Context                                                       │
│    crud User  # Generates all CRUD functions                                │
│  end                                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```elixir
alias OmCrud
alias OmCrud.{Multi, Merge}

# Configure default repo
config :om_crud, default_repo: MyApp.Repo

# Simple CRUD
{:ok, user} = OmCrud.create(User, %{name: "John", email: "john@example.com"})
{:ok, user} = OmCrud.fetch(User, user.id)
{:ok, user} = OmCrud.update(user, %{name: "Jane"})
{:ok, _user} = OmCrud.delete(user)

# Multi transactions
{:ok, %{user: user, account: account}} =
  Multi.new()
  |> Multi.create(:user, User, user_attrs)
  |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
  |> OmCrud.run()

# PostgreSQL MERGE
{:ok, results} =
  User
  |> Merge.new(external_users)
  |> Merge.match_on(:email)
  |> Merge.when_matched(:update, [:name, :updated_at])
  |> Merge.when_not_matched(:insert)
  |> OmCrud.run()
```

## Features

- **Unified Execution** - Single `run/1` function for Multi, Merge, and Query tokens
- **Token-Based** - Operations are data, execution is explicit
- **Result Tuples** - Consistent `{:ok, result}` | `{:error, reason}` returns
- **Find-or-Create / Update-or-Create** - Common patterns as first-class operations
- **Multi Transactions** - Clean pipeline API for atomic operations with conditionals
- **PostgreSQL MERGE** - Full MERGE syntax for complex upserts
- **Atomic Operations** - Transaction helper with step!, optional_step!, and accumulator pattern
- **Batch Processing** - Memory-efficient chunked processing with streaming and parallelism
- **Soft Deletes** - Configurable soft delete with query filtering and Multi integration
- **Schema Defaults** - Schema-level CRUD config via `crud_config` macro
- **Context Generator** - `crud` macro generates boilerplate-free context modules
- **Rich Error Types** - Structured errors with HTTP status mapping and JSON conversion
- **Changeset Resolution** - Smart changeset function discovery
- **Telemetry** - Automatic instrumentation for all operations (including Batch and SoftDelete)
- **Multi-Tenancy** - First-class prefix/schema support
- **Pessimistic Locking** - `FOR UPDATE`, `FOR SHARE`, and custom lock modes

---

## Table of Contents

- [Core Concepts](#core-concepts)
- [Single Record Operations](#single-record-operations)
- [Bulk Operations](#bulk-operations)
- [Multi Transactions](#multi-transactions)
- [PostgreSQL MERGE](#postgresql-merge)
- [Atomic Operations](#atomic-operations)
- [Batch Processing](#batch-processing)
- [Soft Delete](#soft-delete)
- [Result & Pagination](#result--pagination)
- [Schema Integration](#schema-integration)
- [Context Module](#context-module)
- [Changeset Resolution](#changeset-resolution)
- [Error Handling](#error-handling)
- [Options Reference](#options-reference)
- [Telemetry Events](#telemetry-events)
- [Configuration](#configuration)
- [When to Use What](#when-to-use-what)
- [Migrating from Raw Ecto](#migrating-from-raw-ecto)
- [Real-World Examples](#real-world-examples)
- [Best Practices](#best-practices)

> **Note:** OmCrud depends on [OmQuery](../om_query) for query building, filtering, cursor pagination, and MERGE SQL generation. Functions like `Query.new()`, `Query.where()`, and filter tuples `{field, op, value}` come from OmQuery. See the OmQuery README for the full query DSL.

---

## Core Concepts

### Token-Based Execution

OmCrud uses a **token pattern** where operations are built as data structures (tokens), then explicitly executed:

```elixir
# Build a token (no database call yet)
multi =
  Multi.new()
  |> Multi.create(:user, User, attrs)
  |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)

# Execute the token
{:ok, results} = OmCrud.run(multi)
```

This separation provides:
- **Testability** - Inspect operations before execution
- **Composability** - Combine multiple tokens
- **Observability** - Telemetry at execution boundaries

### Unified API

All operations go through a single execution path:

```elixir
# Multi transactions
OmCrud.run(multi)

# Merge operations
OmCrud.run(merge)

# Query tokens (with OmQuery)
OmCrud.run(query_token)

# Alias for pipe-friendliness
multi |> OmCrud.execute()
```

### Protocols

OmCrud defines three protocols for extensibility:

| Protocol | Purpose | Function |
|----------|---------|----------|
| `OmCrud.Executable` | Execute a token | `execute(token, opts)` |
| `OmCrud.Validatable` | Validate before execution | `validate(token)` |
| `OmCrud.Debuggable` | Debug inspection | `to_debug(token)` |

---

## Single Record Operations

### Create

```elixir
# Basic create
{:ok, user} = OmCrud.create(User, %{email: "test@example.com", name: "Test"})

# With custom changeset
{:ok, user} = OmCrud.create(User, attrs, changeset: :registration_changeset)

# With preload after creation
{:ok, user} = OmCrud.create(User, attrs, preload: [:account])

# With custom timeout
{:ok, user} = OmCrud.create(User, attrs, timeout: 30_000)

# With returning specific fields
{:ok, user} = OmCrud.create(User, attrs, returning: [:id, :email])
```

### Fetch

```elixir
# Basic fetch - returns {:ok, record} or {:error, :not_found}
{:ok, user} = OmCrud.fetch(User, user_id)
{:error, :not_found} = OmCrud.fetch(User, "nonexistent")

# With preload
{:ok, user} = OmCrud.fetch(User, user_id, preload: [:account, :memberships])

# With custom repo
{:ok, user} = OmCrud.fetch(User, user_id, repo: MyApp.ReadOnlyRepo)

# With schema prefix (multi-tenancy)
{:ok, user} = OmCrud.fetch(User, user_id, prefix: "tenant_123")

# With pessimistic locking (inside a transaction)
OmCrud.transaction(fn ->
  {:ok, user} = OmCrud.fetch(User, id, lock: :for_update)
  OmCrud.update(user, %{balance: user.balance - 100})
end)
```

### Get

```elixir
# Returns record or nil (no error tuple)
user = OmCrud.get(User, user_id)
nil = OmCrud.get(User, "nonexistent")

# With preload
user = OmCrud.get(User, user_id, preload: [:account])
```

### Update

```elixir
# Update struct
{:ok, user} = OmCrud.update(user, %{name: "Updated Name"})

# Update by schema and ID
{:ok, user} = OmCrud.update(User, user_id, %{name: "Updated"})

# With custom changeset
{:ok, user} = OmCrud.update(user, attrs, changeset: :admin_changeset)

# Force specific fields to be marked as changed
{:ok, user} = OmCrud.update(user, %{}, force: [:updated_at])

# With preload after update
{:ok, user} = OmCrud.update(user, attrs, preload: [:account])
```

### Delete

```elixir
# Delete struct
{:ok, user} = OmCrud.delete(user)

# Delete by schema and ID
{:ok, user} = OmCrud.delete(User, user_id)

# With options
{:ok, user} = OmCrud.delete(user, timeout: 5000)
```

### Upsert

```elixir
# Insert or update user by email
{:ok, user} = OmCrud.upsert(User, %{email: "test@example.com", name: "Test"},
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)

# Insert or do nothing on conflict
{:ok, user} = OmCrud.upsert(User, attrs,
  conflict_target: [:org_id, :email],
  on_conflict: :nothing
)

# Replace all fields on conflict
{:ok, user} = OmCrud.upsert(User, attrs,
  conflict_target: :email,
  on_conflict: :replace_all
)
```

### Find or Create

```elixir
# Find user by email, or create if not found
{:ok, user} = OmCrud.find_or_create(User,
  %{email: "test@example.com", name: "Test"},
  find_by: :email
)

# Find by composite key
{:ok, membership} = OmCrud.find_or_create(Membership,
  %{user_id: user.id, org_id: org.id, role: :member},
  find_by: [:user_id, :org_id]
)

# With preload
{:ok, user} = OmCrud.find_or_create(User, attrs,
  find_by: :email, preload: [:account]
)
```

### Update or Create

```elixir
# Update user by email, or create if not found
{:ok, user} = OmCrud.update_or_create(User,
  %{email: "test@example.com", name: "Updated"},
  find_by: :email
)

# With separate changesets for create vs update
{:ok, setting} = OmCrud.update_or_create(Setting,
  %{key: "theme", value: "dark"},
  find_by: :key,
  create_changeset: :create_changeset,
  update_changeset: :update_changeset
)
```

### Exists?

```elixir
# Check if record exists
true = OmCrud.exists?(User, user_id)
false = OmCrud.exists?(User, "nonexistent")

# With custom repo
OmCrud.exists?(User, user_id, repo: MyApp.ReadOnlyRepo)
```

---

## Bulk Operations

### Create All

```elixir
# Basic bulk insert
{:ok, users} = OmCrud.create_all(User, [
  %{email: "a@test.com", name: "A"},
  %{email: "b@test.com", name: "B"}
])

# With returning
{:ok, users} = OmCrud.create_all(User, entries, returning: true)
{:ok, users} = OmCrud.create_all(User, entries, returning: [:id, :email])

# With placeholders (reduce data transfer)
now = DateTime.utc_now()
placeholders = %{now: now, org_id: org.id}

entries = [
  %{email: "a@test.com", org_id: {:placeholder, :org_id}, inserted_at: {:placeholder, :now}},
  %{email: "b@test.com", org_id: {:placeholder, :org_id}, inserted_at: {:placeholder, :now}}
]

{:ok, users} = OmCrud.create_all(User, entries, placeholders: placeholders)
```

### Upsert All

```elixir
# Upsert with conflict handling
{:ok, users} = OmCrud.upsert_all(User, users_data,
  conflict_target: :email,
  on_conflict: :nothing
)

# Replace specific fields on conflict
{:ok, users} = OmCrud.upsert_all(User, users_data,
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)

# Replace all fields on conflict
{:ok, users} = OmCrud.upsert_all(User, users_data,
  conflict_target: [:org_id, :email],
  on_conflict: :replace_all,
  returning: true
)

# Using constraint name
{:ok, users} = OmCrud.upsert_all(User, users_data,
  conflict_target: {:constraint, :users_email_unique},
  on_conflict: {:replace, [:name]}
)
```

### Update All

```elixir
# Update all matching records
{:ok, count} =
  User
  |> Query.new()
  |> Query.where(:status, :inactive)
  |> OmCrud.update_all(set: [archived_at: DateTime.utc_now()])
```

### Delete All

```elixir
# Delete all matching records
{:ok, count} =
  Token
  |> Query.new()
  |> Query.where(:expired_at, :<, DateTime.utc_now())
  |> OmCrud.delete_all()
```

---

## Multi Transactions

Multi provides a clean pipeline API for building atomic transactions.

### Basic Usage

```elixir
alias OmCrud.Multi

# Create multiple related records
{:ok, results} =
  Multi.new()
  |> Multi.create(:user, User, %{email: "test@example.com"})
  |> Multi.create(:account, Account, fn %{user: user} ->
       %{owner_id: user.id, name: "#{user.email}'s Account"}
     end)
  |> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
       %{user_id: u.id, account_id: a.id, role: :owner}
     end)
  |> OmCrud.run()

# Access results
results.user      #=> %User{...}
results.account   #=> %Account{...}
results.membership #=> %Membership{...}
```

### Operations

```elixir
# Create
Multi.create(multi, :user, User, %{email: "test@example.com"})
Multi.create(multi, :user, User, attrs, changeset: :registration)

# Update by struct
Multi.update(multi, :user, user, %{name: "Updated"})

# Update by schema + id
Multi.update(multi, :user, {User, user_id}, %{name: "Updated"})

# Update from previous result
Multi.update(multi, :confirmed, fn %{user: u} -> u end, %{confirmed_at: DateTime.utc_now()})

# Delete
Multi.delete(multi, :user, user)
Multi.delete(multi, :user, {User, user_id})
Multi.delete(multi, :token, fn %{user: u} -> u.token end)

# Upsert
Multi.upsert(multi, :user, User, attrs,
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)
```

### Bulk Operations in Multi

```elixir
# Bulk create
Multi.create_all(multi, :users, User, [
  %{email: "a@test.com"},
  %{email: "b@test.com"}
])

# Bulk upsert
Multi.upsert_all(multi, :users, User, users_data,
  conflict_target: :email,
  on_conflict: {:replace, [:name]}
)

# Bulk update
query = from(u in User, where: u.status == :inactive)
Multi.update_all(multi, :deactivate, query, set: [archived_at: DateTime.utc_now()])

# Bulk delete
query = from(t in Token, where: t.expired_at < ^DateTime.utc_now())
Multi.delete_all(multi, :cleanup, query)

# Merge inside a Multi
merge_token =
  User
  |> Merge.new(external_data)
  |> Merge.match_on(:email)
  |> Merge.when_matched(:update, [:name])
  |> Merge.when_not_matched(:insert)

Multi.merge(multi, :sync, merge_token)
```

### Custom Operations

```elixir
# Run custom logic
Multi.run(multi, :validate, fn %{user: user} ->
  if valid_email?(user.email) do
    {:ok, :valid}
  else
    {:error, :invalid_email}
  end
end)

# Call module function
Multi.run(multi, :notify, MyApp.Notifications, :send_welcome, [:user_created])

# Inspect for debugging
Multi.inspect_results(multi, :debug, fn results ->
  IO.inspect(results, label: "Transaction state")
end)
```

### Conditional Operations

```elixir
# Dynamic - based on previous results
Multi.when_ok(multi, :admin_setup, fn %{user: user} ->
  if user.role == :admin do
    Multi.new()
    |> Multi.create(:admin_record, AdminRecord, %{user_id: user.id})
    |> Multi.create(:permissions, Permission, %{user_id: user.id, level: :all})
  else
    Multi.new()  # Empty multi = no additional operations
  end
end)

# Static condition
Multi.when_cond(multi, should_notify?, fn m ->
  Multi.run(m, :notify, fn %{user: u} -> send_notification(u) end)
end)

# Inverse condition
Multi.unless(multi, skip_audit?, fn m ->
  Multi.run(m, :audit, fn results -> log_audit(results) end)
end)

# Branch - if/else
Multi.branch(multi, is_admin?,
  fn m -> Multi.create(m, :admin, AdminRecord, admin_attrs) end,
  fn m -> Multi.create(m, :member, MemberRecord, member_attrs) end
)

# Iterate (fn receives multi, item, index, results)
Multi.each(multi, :create_items, items, fn m, item, index, results ->
  Multi.create(m, :"item_#{index}", Item, %{name: item.name})
end)

# Match on previous result value
Multi.when_value(multi, :user, :admin, fn m ->
  Multi.create(m, :admin_setup, AdminSetup, %{})
end)

# Match with function
Multi.when_match(multi, :user, &(&1.role == :admin), fn m ->
  Multi.create(m, :admin_setup, AdminSetup, %{})
end)
```

### Composition

```elixir
# Append operations
user_multi = Multi.new() |> Multi.create(:user, User, user_attrs)
account_multi = Multi.new() |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)

combined = Multi.append(user_multi, account_multi)

# Prepend operations
combined = Multi.prepend(account_multi, user_multi)

# Embed with prefix (avoid name conflicts)
user_setup = Multi.new() |> Multi.create(:record, User, attrs)
Multi.embed(multi, user_setup, prefix: :user)  # Creates :user_record operation
```

### Introspection

```elixir
Multi.names(multi)                  #=> [:user, :account, :membership]
Multi.operation_count(multi)        #=> 3
Multi.has_operation?(multi, :user)  #=> true
Multi.empty?(multi)                 #=> false
```

### Converting to Ecto.Multi

```elixir
# For integration with existing code
ecto_multi = Multi.to_ecto_multi(multi)
Repo.transaction(ecto_multi)
```

---

## PostgreSQL MERGE

Merge provides PostgreSQL MERGE syntax for complex upsert operations (requires PostgreSQL 18+).

### Basic Usage

```elixir
alias OmCrud.Merge

# Simple upsert
{:ok, results} =
  User
  |> Merge.new(%{email: "test@example.com", name: "Test"})
  |> Merge.match_on(:email)
  |> Merge.when_matched(:update, [:name, :updated_at])
  |> Merge.when_not_matched(:insert)
  |> OmCrud.run()
```

### Source Types

```elixir
# Single record
Merge.new(User, %{email: "test@example.com"})

# Multiple records
Merge.new(User, [
  %{email: "a@test.com", name: "A"},
  %{email: "b@test.com", name: "B"}
])

# Set source separately
Merge.new(User)
|> Merge.source(external_data)

# From query (merge from another table)
external_query = from(e in ExternalUser, select: %{email: e.email, name: e.name})
Merge.new(User) |> Merge.source(external_query)
```

### Match Columns

```elixir
# Single column
Merge.match_on(merge, :email)

# Multiple columns (compound key)
Merge.match_on(merge, [:org_id, :email])
```

### WHEN MATCHED Clauses

```elixir
Merge.when_matched(merge, :update)                       # Update all source fields
Merge.when_matched(merge, :update, [:name, :updated_at]) # Update specific fields
Merge.when_matched(merge, :delete)                        # Delete matched rows
Merge.when_matched(merge, :nothing)                       # Do nothing

# Conditional - only update if source is newer
Merge.when_matched(merge, &source_newer/1, :update)
Merge.when_matched(merge, :nothing)  # Fallback
```

### WHEN NOT MATCHED Clauses

```elixir
Merge.when_not_matched(merge, :insert)                             # Insert from source
Merge.when_not_matched(merge, :insert, %{status: :pending})       # Insert with defaults
Merge.when_not_matched(merge, :nothing)                            # Do nothing
Merge.when_not_matched(merge, &valid_email?/1, :insert)           # Conditional insert
```

### Returning & Options

```elixir
Merge.returning(merge, true)                    # Return all fields
Merge.returning(merge, false)                   # Return nothing
Merge.returning(merge, [:id, :email])           # Return specific fields

Merge.opts(merge, prefix: "tenant_123", timeout: 60_000)
```

### Validation & SQL

```elixir
:ok = Merge.validate(merge)                    # Validate before execution
{sql, params} = Merge.to_sql(merge)            # Get raw SQL
```

### Complete Example

```elixir
# Sync users from external system
{:ok, synced_users} =
  User
  |> Merge.new(external_users)
  |> Merge.match_on(:external_id)
  |> Merge.when_matched(fn query ->
       where(query, [s, t], s.updated_at > t.synced_at)
     end, :update, [:name, :email, :synced_at])
  |> Merge.when_matched(:nothing)  # Skip if not newer
  |> Merge.when_not_matched(:insert, %{status: :pending})
  |> Merge.returning([:id, :external_id, :email])
  |> Merge.opts(timeout: 120_000)
  |> OmCrud.run()
```

---

## Atomic Operations

`OmCrud.Atomic` provides a clean, functional approach to transactions with automatic error handling.

### Basic Usage

```elixir
import OmCrud.Atomic

atomic fn ->
  with {:ok, user} <- OmCrud.create(User, user_attrs),
       {:ok, account} <- OmCrud.create(Account, %{user_id: user.id}) do
    {:ok, %{user: user, account: account}}
  end
end
```

### Step Functions (Raising)

Use `step!/1` or `step!/2` for cleaner code that raises on error, triggering automatic rollback:

```elixir
atomic fn ->
  user = step!(OmCrud.create(User, user_attrs))
  account = step!(OmCrud.create(Account, %{user_id: user.id}))
  settings = step!(OmCrud.create(Settings, %{user_id: user.id}))

  {:ok, %{user: user, account: account, settings: settings}}
end
```

### Named Steps

For better error reporting:

```elixir
atomic fn ->
  user = step!(:create_user, OmCrud.create(User, user_attrs))
  account = step!(:create_account, OmCrud.create(Account, %{user_id: user.id}))

  {:ok, %{user: user, account: account}}
end
# On error: {:error, %OmCrud.Error{type: :step_failed, step: :create_account, ...}}
```

### Optional Steps

Use `optional_step!/2` for steps that may return `:not_found` without failing the transaction:

```elixir
atomic fn ->
  user = step!(:create_user, OmCrud.create(User, attrs))
  # Returns nil if org not found, doesn't fail
  org = optional_step!(:fetch_org, OmCrud.fetch(Org, org_id))

  org = org || step!(:create_org, OmCrud.create(Org, %{owner_id: user.id}))
  {:ok, %{user: user, org: org}}
end
```

### Non-Raising Steps

```elixir
atomic fn ->
  case step(:fetch_user, OmCrud.fetch(User, id)) do
    {:ok, user} -> do_something(user)
    {:error, %Error{type: :not_found}} -> create_default_user()
    {:error, error} -> {:error, error}
  end
end
```

### Accumulator Pattern

Build up context across steps using a pipeline:

```elixir
atomic fn ->
  %{}
  |> accumulate(:user, fn -> OmCrud.create(User, user_attrs) end)
  |> accumulate(:account, fn ctx -> OmCrud.create(Account, %{user_id: ctx.user.id}) end)
  |> accumulate(:settings, fn ctx -> OmCrud.create(Settings, %{user_id: ctx.user.id}) end)
  |> accumulate_optional(:org, fn ctx -> OmCrud.fetch(Org, ctx.user.org_id) end)
  |> finalize()
end
#=> {:ok, %{user: user, account: account, settings: settings, org: nil}}
```

### With Context

```elixir
atomic_with_context(%{org_id: 123}, fn ctx ->
  user = step!(OmCrud.create(User, %{org_id: ctx.org_id, name: "Test"}))
  {:ok, user}
end)

# With options
atomic_with_context(%{org_id: 123}, [timeout: 30_000], fn ctx ->
  user = step!(OmCrud.create(User, %{org_id: ctx.org_id}))
  {:ok, user}
end)
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:repo` | configured | Repository module |
| `:timeout` | 15_000 | Transaction timeout |
| `:mode` | nil | `:read_only` or `:read_write` |
| `:telemetry_prefix` | `[:om_crud, :atomic]` | Custom telemetry prefix |

---

## Batch Processing

`OmCrud.Batch` provides memory-efficient processing of large datasets.

### Iteration

```elixir
alias OmCrud.Batch

# Process all users in batches (side effects only)
Batch.each(User, fn batch ->
  Enum.each(batch, &send_notification/1)
end)

# With filtering and custom batch size
Batch.each(User, fn batch ->
  :ok
end, where: [status: :active], batch_size: 100)
```

### Processing with Result Tracking

```elixir
# Track results and errors
{:ok, %{processed: 1000, errors: []}} = Batch.process(User, fn batch ->
  {:ok, Enum.count(batch)}
end)

# With error collection
{:ok, %{processed: 950, errors: errors}} = Batch.process(User, fn batch ->
  case process_batch(batch) do
    {:ok, count} -> {:ok, count}
    {:error, reason} -> {:error, reason}
  end
end, on_error: :collect)
```

### Batch Update

```elixir
# Add points to all users
{:ok, %{processed: count}} = Batch.update(User, fn user ->
  %{points: user.points + 10}
end)

# With custom changeset and filters
{:ok, _} = Batch.update(User, fn user ->
  %{status: :archived}
end, changeset: :admin_changeset, where: [status: :inactive])
```

### Batch Delete

```elixir
# Delete all inactive users
{:ok, %{processed: count}} = Batch.delete(User, where: [status: :inactive])
```

### Chunked Inserts

```elixir
# Insert 10,000 users in batches of 1,000
{:ok, %{processed: 10000}} = Batch.create_all(User, users_data, batch_size: 1000)

# Upsert in batches
{:ok, _} = Batch.upsert_all(User, users_data,
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)
```

### Streaming

```elixir
# Stream individual records (must be inside transaction)
repo.transaction(fn ->
  User
  |> Batch.stream(batch_size: 100)
  |> Stream.map(&process_user/1)
  |> Stream.run()
end)

# Stream batches as lists
repo.transaction(fn ->
  User
  |> Batch.stream_chunks(batch_size: 100)
  |> Stream.map(&process_batch/1)
  |> Stream.run()
end)

# Auto-wrapped in transaction
{:ok, users} = Batch.stream_in_transaction(User,
  where: [status: :active],
  batch_size: 100
)
```

### Parallel Processing

```elixir
# Process batches concurrently
{:ok, results} = Batch.parallel(User, fn batch ->
  Enum.map(batch, &expensive_operation/1)
end, max_concurrency: 4, batch_size: 500)
```

### Batch Options

| Option | Default | Description |
|--------|---------|-------------|
| `:batch_size` | 500 | Records per batch |
| `:timeout` | 30_000 | Timeout per batch |
| `:repo` | configured | Repository module |
| `:on_error` | `:halt` | `:halt`, `:continue`, or `:collect` |
| `:order_by` | `:id` | Field(s) for consistent ordering |
| `:where` | `[]` | Filter conditions as keyword list |
| `:max_concurrency` | schedulers | Max parallel tasks (for `parallel/3`) |

---

## Soft Delete

`OmCrud.SoftDelete` provides soft deletion by setting a timestamp instead of removing records.

### Schema Setup

```elixir
schema "users" do
  field :deleted_at, :utc_datetime_usec
  # ...
end

# Or with custom field name via module attribute
defmodule MyApp.User do
  use OmSchema
  @soft_delete_field :archived_at

  schema "users" do
    field :archived_at, :utc_datetime_usec
  end
end
```

### Basic Operations

```elixir
alias OmCrud.SoftDelete

# Soft delete
{:ok, user} = SoftDelete.delete(user)
{:ok, user} = SoftDelete.delete(User, user_id)

# Restore
{:ok, user} = SoftDelete.restore(user)
{:ok, user} = SoftDelete.restore(User, user_id)

# Check status
SoftDelete.deleted?(user)     #=> true
SoftDelete.deleted_at(user)   #=> ~U[2024-01-15 10:30:00Z]

# With custom field
{:ok, user} = SoftDelete.delete(user, field: :archived_at)
```

### Multi Integration

```elixir
Multi.new()
|> SoftDelete.multi_delete(:user, user)
|> SoftDelete.multi_restore(:other_user, other_user)
|> OmCrud.run()
```

### Query Filtering

```elixir
# Exclude soft-deleted records
User
|> OmQuery.new()
|> SoftDelete.exclude_deleted()
|> OmCrud.fetch_all()

# Only soft-deleted records
User
|> OmQuery.new()
|> SoftDelete.only_deleted()
|> OmCrud.fetch_all()

# Works with Ecto.Query too
query = from(u in User, where: u.status == :active)
query = SoftDelete.exclude_deleted(query)
```

### Configuration

```elixir
# Global config
config :om_crud, OmCrud.SoftDelete,
  field: :deleted_at,
  timestamp: &DateTime.utc_now/0
```

---

## Result & Pagination

### OmCrud.Result

The `Result` struct wraps query results with optional pagination metadata:

```elixir
%OmCrud.Result{
  data: [%User{}, %User{}, ...],
  pagination: %OmCrud.Pagination{...}  # nil for unpaginated results
}

# Create result without pagination
result = OmCrud.Result.all(users)

# Create result with pagination
result = OmCrud.Result.new(users, pagination)

# Check navigation
OmCrud.Result.has_more?(result)      #=> true
OmCrud.Result.has_previous?(result)  #=> false
```

### OmCrud.Pagination

Cursor-based pagination metadata:

```elixir
%OmCrud.Pagination{
  type: :cursor,
  has_more: true,
  has_previous: false,
  start_cursor: "eyJpbnNlcnRlZF9hdCI6...",
  end_cursor: "eyJpbnNlcnRlZF9hdCI6...",
  limit: 20
}
```

#### Navigation

```elixir
# First page
{:ok, result} = Accounts.list_users(limit: 20)

# Next page (forward)
{:ok, page2} = Accounts.list_users(after: result.pagination.end_cursor)

# Previous page (backward)
{:ok, prev} = Accounts.list_users(before: result.pagination.start_cursor)
```

#### API Helpers

```elixir
# Build from records
pagination = OmCrud.Pagination.from_records(records, [:inserted_at, :id], 20,
  fetched_extra: true,
  has_previous: after_cursor != nil
)

# JSON serialization
OmCrud.Pagination.to_map(pagination)
#=> %{type: "cursor", has_more: true, has_previous: false, start_cursor: "...", ...}

# Cursor encoding/decoding
cursor = OmCrud.Pagination.encode_cursor(record, [:inserted_at, :id])
{:ok, values} = OmCrud.Pagination.decode_cursor(cursor)
```

#### Configuration

```elixir
# Cursor format: :json (default, API-friendly) or :binary (faster)
config :om_crud, :pagination,
  cursor_format: :json
```

---

## Schema Integration

`OmCrud.Schema` provides schema-level CRUD configuration. All defaults set here are automatically merged into every `OmCrud` convenience function call (`create`, `fetch`, `update`, `delete`, `find_or_create`, etc.) — explicit call-site options take precedence.

```elixir
defmodule MyApp.User do
  use OmCrud.Schema

  # Default changeset for all CRUD operations on this schema
  @crud_changeset :admin_changeset

  # Custom soft delete field (default: :deleted_at)
  @soft_delete_field :archived_at

  # Default CRUD options — merged into all OmCrud calls for this schema
  crud_config preload: [:account], timeout: 30_000

  schema "users" do
    field :email, :string
    field :archived_at, :utc_datetime_usec
    timestamps()
  end

  def changeset(user, attrs), do: ...
  def admin_changeset(user, attrs), do: ...

  # Dynamic changeset resolution
  def changeset_for(:create, _opts), do: :registration_changeset
  def changeset_for(:update, opts) do
    if opts[:admin], do: :admin_changeset, else: :changeset
  end
end
```

---

## Context Module

Generate CRUD functions for your context modules with zero boilerplate.

### Basic Usage

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  # Generate all CRUD functions
  crud User

  # Generate specific functions
  crud Role, only: [:create, :fetch, :update]

  # Exclude specific functions
  crud Session, except: [:delete_all]
end
```

### Generated Functions

For `crud User`, the following functions are generated (all `defoverridable`):

| Function | Return Type |
|----------|-------------|
| `fetch_user(id, opts)` | `{:ok, user}` \| `{:error, :not_found}` |
| `fetch_user!(id, opts)` | `user` or raises |
| `get_user(id, opts)` | `user` \| `nil` |
| `list_users(opts)` | `{:ok, %OmCrud.Result{data: [...], pagination: ...}}` |
| `filter_users(filters, opts)` | `{:ok, %OmCrud.Result{}}` (wrapper for `list_users`) |
| `count_users(opts)` | `{:ok, integer}` |
| `first_user(opts)` | `{:ok, user}` \| `{:error, :not_found}` |
| `first_user!(opts)` | `user` or raises |
| `last_user(opts)` | `{:ok, user}` \| `{:error, :not_found}` |
| `last_user!(opts)` | `user` or raises |
| `user_exists?(id_or_filters, opts)` | `boolean` |
| `stream_users(opts)` | `Enumerable.t()` |
| `create_user(attrs, opts)` | `{:ok, user}` \| `{:error, changeset}` |
| `create_user!(attrs, opts)` | `user` or raises |
| `update_user(record, attrs, opts)` | `{:ok, user}` \| `{:error, changeset}` |
| `update_user!(record, attrs, opts)` | `user` or raises |
| `delete_user(record, opts)` | `{:ok, user}` \| `{:error, changeset}` |
| `delete_user!(record, opts)` | `user` or raises |
| `create_all_users(entries, opts)` | `{:ok, [user]}` |
| `update_all_users(filters, changes, opts)` | `{:ok, count}` |
| `delete_all_users(filters, opts)` | `{:ok, count}` |

### Cursor Pagination

`list_*` and `filter_*` functions use cursor pagination by default:

```elixir
# First page (default limit: 20, max: 100)
{:ok, result} = Accounts.list_users()
result.data        #=> [%User{}, ...]
result.pagination  #=> %OmCrud.Pagination{has_more: true, end_cursor: "..."}

# Next page
{:ok, page2} = Accounts.list_users(after: result.pagination.end_cursor)

# Previous page
{:ok, prev} = Accounts.list_users(before: result.pagination.start_cursor)

# Custom limit
{:ok, result} = Accounts.list_users(limit: 50)

# All records (no pagination)
{:ok, result} = Accounts.list_users(limit: :all)
```

### Filter Syntax

Filters use OmQuery's `{field, operator, value}` tuple syntax:

```elixir
# Basic filtering
Accounts.filter_users([{:status, :eq, :active}])
Accounts.filter_users([{:email, :ilike, "%@corp.com"}])

# Multiple filters (AND)
Accounts.filter_users([
  {:status, :eq, :active},
  {:role, :in, [:admin, :moderator]}
])

# Via list_users with :filters option
Accounts.list_users(
  filters: [{:status, :eq, :active}],
  preload: [:account],
  limit: 50
)
```

### List/Filter Options

| Option | Default | Description |
|--------|---------|-------------|
| `:limit` | 20 | Page size (or `:all` for no limit) |
| `:after` | nil | Cursor for next page |
| `:before` | nil | Cursor for previous page |
| `:filters` | `[]` | Filter tuples `[{field, op, value}]` |
| `:preload` | configured | Associations to preload |
| `:order_by` | `[desc: :inserted_at, asc: :id]` | Custom ordering |
| `:cursor_fields` | `[:inserted_at, :id]` | Fields for cursor encoding |
| `:select` | nil | Fields to select |
| `:distinct` | nil | Enable distinct |
| `:lock` | nil | Row locking mode |

### Create/Update `:reload` Option

After creating or updating, use `:reload` to preload associations on the result:

```elixir
# Reload with specific preloads
{:ok, user} = Accounts.create_user(attrs, reload: [:account, :memberships])

# Reload with default preloads (from crud config)
{:ok, user} = Accounts.update_user(user, attrs, reload: true)
```

### Macro Options

```elixir
crud User,
  # Function generation
  only: [:create, :fetch, :update],           # Specific functions only
  except: [:delete_all, :update_all],         # Exclude functions
  as: :member,                                # Custom name: create_member, fetch_member, etc.
  bang: true,                                 # Generate bang (!) versions (default: true)
  filterable: true,                           # Generate filter functions (default: true)

  # Pagination
  pagination: :cursor,                        # Pagination type (default: :cursor)
  default_limit: 20,                          # Default page size
  max_limit: 100,                             # Maximum page size

  # Query defaults
  order_by: [desc: :inserted_at, asc: :id],  # Default ordering
  cursor_fields: [:inserted_at, :id],         # Fields for cursor pagination
  preload: [:account, :memberships],          # Default preloads
  batch_size: 500,                            # Batch size for streaming

  # Execution defaults
  repo: MyApp.ReadOnlyRepo,                   # Custom repo
  timeout: 30_000,                            # Custom timeout
  prefix: "tenant_123",                       # Multi-tenancy prefix
  changeset: :admin_changeset,                # Default changeset
  log: false                                  # Disable logging
```

### Overriding Generated Functions

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context
  crud User

  # Override with custom logic
  def create_user(attrs, opts \\ []) do
    attrs
    |> Map.put(:created_by, opts[:current_user_id])
    |> then(&OmCrud.create(User, &1, opts))
  end

  # Use super() to call the generated implementation
  def fetch_user(id, opts \\ []) do
    case super(id, opts) do
      {:ok, user} -> {:ok, enrich_user(user)}
      error -> error
    end
  end

  defp enrich_user(user) do
    %{user | display_name: "#{user.first_name} #{user.last_name}"}
  end
end
```

---

## Changeset Resolution

OmCrud automatically resolves which changeset function to use.

### Resolution Priority

1. Explicit `:changeset` option
2. Action-specific option (`:create_changeset`, `:update_changeset`, `:delete_changeset`)
3. Schema's `@crud_changeset` attribute
4. Schema's `changeset_for/2` callback
5. Default `:changeset` function

### Examples

```elixir
# 1. Explicit option
OmCrud.create(User, attrs, changeset: :registration_changeset)

# 2. Action-specific option
OmCrud.create(User, attrs, create_changeset: :registration_changeset)
OmCrud.update(user, attrs, update_changeset: :profile_changeset)

# 3. Schema attribute
defmodule User do
  use Ecto.Schema
  @crud_changeset :admin_changeset
end

# 4. Schema callback
defmodule User do
  def changeset_for(:create, _opts), do: :registration_changeset
  def changeset_for(:update, opts) do
    if opts[:admin], do: :admin_changeset, else: :changeset
  end
end

# 5. Default - uses :changeset function
```

### Manual Changeset Building

```elixir
alias OmCrud.ChangesetBuilder

changeset = ChangesetBuilder.build(User, %{email: "test@example.com"})
changeset = ChangesetBuilder.build(user, %{name: "Updated"})
changeset = ChangesetBuilder.build(User, attrs, changeset: :registration)

fn_name = ChangesetBuilder.resolve(User, :create, [])          #=> :changeset
fn_name = ChangesetBuilder.resolve(User, :create, changeset: :registration) #=> :registration
```

---

## Error Handling

### OmCrud.Error

Structured error types with context:

```elixir
alias OmCrud.Error

# Error types
:not_found | :validation_error | :constraint_violation |
:step_failed | :transaction_error | :stale_entry | :unknown
```

### Smart Constructors

```elixir
Error.not_found(User, 123)
Error.from_changeset(changeset)
Error.constraint_violation(:users_email_unique, User)
Error.validation_error(:email, "is invalid", schema: User)
Error.step_failed(:create_user, {:error, changeset})
Error.transaction_error(:rollback, step: :create_account)
Error.stale_entry(User, 123)
Error.wrap(any_error)
```

### Utilities

```elixir
Error.message(error)          #=> "User with id 123 not found"
Error.to_map(error)           #=> %{type: :not_found, schema: "User", id: 123, ...}
Error.to_http_status(error)   #=> 404
Error.is_type?(error, :not_found) #=> true
Error.on_field?(error, :email)    #=> true
```

### HTTP Status Mapping

| Error Type | HTTP Status |
|------------|-------------|
| `:not_found` | 404 |
| `:validation_error` | 422 |
| `:constraint_violation` | 409 |
| `:stale_entry` | 409 |
| Other | 500 |

### Transaction Errors

```elixir
case OmCrud.run(multi) do
  {:ok, results} ->
    {:ok, results.user}

  {:error, failed_operation, failed_value, changes_so_far} ->
    Logger.error("Operation #{failed_operation} failed: #{inspect(failed_value)}")
    {:error, failed_value}
end
```

### Changeset Errors

```elixir
case OmCrud.create(User, attrs) do
  {:ok, user} ->
    {:ok, user}

  {:error, %Ecto.Changeset{} = changeset} ->
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    {:error, errors}
end
```

---

## Options Reference

### Common Options (All Operations)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:repo` | module | configured | Repository module |
| `:prefix` | string | nil | Schema prefix for multi-tenancy |
| `:timeout` | integer | 15_000 | Query timeout in milliseconds |
| `:log` | atom/false | :debug | Log level or false to disable |

### Write Options (Insert/Update/Delete)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:returning` | bool/list | false | Return inserted/updated fields |
| `:stale_error_field` | atom | nil | Field for stale error messages |
| `:stale_error_message` | string | nil | Custom stale error message |
| `:allow_stale` | boolean | false | Allow stale records |

### Changeset Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:changeset` | atom | :changeset | Changeset function name |
| `:create_changeset` | atom | nil | Changeset for create operations |
| `:update_changeset` | atom | nil | Changeset for update operations |
| `:delete_changeset` | atom | nil | Changeset for delete operations |

### Update Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:force` | list | [] | Fields to mark as changed |

### Find/Update-or-Create Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:find_by` | atom/list | required | Field(s) to look up by |

### Bulk Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:placeholders` | map | nil | Reusable values for bulk inserts |
| `:conflict_target` | atom/list/tuple | nil | Column(s) for conflict detection |
| `:on_conflict` | atom/tuple | :nothing | Conflict handling action |

### Read Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:preload` | list | [] | Associations to preload |
| `:lock` | atom/string | nil | Pessimistic lock mode |

### Lock Modes

| Mode | SQL | Use Case |
|------|-----|----------|
| `:for_update` | `FOR UPDATE` | Exclusive row lock |
| `:for_share` | `FOR SHARE` | Shared lock, blocks writes |
| `:for_no_key_update` | `FOR NO KEY UPDATE` | Lock without blocking FK checks |
| `:for_key_share` | `FOR KEY SHARE` | Shared lock allowing FK checks |
| `"FOR UPDATE NOWAIT"` | Custom SQL | Any valid lock fragment |

### Conflict Handling

```elixir
on_conflict: :nothing                                # Do nothing
on_conflict: :replace_all                            # Replace all fields
on_conflict: {:replace, [:name, :updated_at]}        # Replace specific fields
on_conflict: {:replace_all_except, [:id, :inserted_at]}  # Replace all except

conflict_target: :email                              # Single column
conflict_target: [:org_id, :email]                   # Compound key
conflict_target: {:constraint, :users_email_unique}  # Constraint name
```

---

## Telemetry Events

### Execution Events

```
[:om_crud, :execute, :start]
[:om_crud, :execute, :stop]
[:om_crud, :execute, :exception]
```

### Atomic Events

```
[:om_crud, :atomic, :start]
[:om_crud, :atomic, :stop]
[:om_crud, :atomic, :exception]
```

### Operation Events

```
[:om_crud, <operation>, :start]
[:om_crud, <operation>, :stop]
[:om_crud, <operation>, :exception]
```

**CRUD operations:** `:list`, `:filter`, `:fetch`, `:get`, `:create`, `:update`, `:delete`, `:count`, `:first`, `:last`, `:stream`, `:exists`, `:update_all`, `:delete_all`, `:find_or_create`, `:update_or_create`

**Batch operations:** `:batch_each`, `:batch_process`, `:batch_update`, `:batch_delete`, `:batch_create_all`, `:batch_upsert_all`, `:batch_parallel`

**Soft delete operations:** `:soft_delete`, `:soft_restore`

### Measurements

| Measurement | Type | Description |
|-------------|------|-------------|
| `:duration` | native time | Operation duration |
| `:duration_ms` | milliseconds | Operation duration |
| `:system_time` | timestamp | Absolute timestamp (start only) |

### Metadata

| Field | Type | Description |
|-------|------|-------------|
| `:type` | atom | Execution type (`:transaction`, `:merge`, `:query`) |
| `:operation` | atom | Operation name |
| `:schema` | module | Schema module |
| `:id` | term | Record ID (single record ops) |
| `:count` | integer | Record count (bulk ops) |
| `:source` | atom | Origin (`:convenience`, `:direct`) |
| `:result` | atom | Result type (`:ok`, `:error`) on stop events |

### Attaching Handlers

```elixir
defmodule MyApp.CrudTelemetry do
  require Logger

  def setup do
    :telemetry.attach_many(
      "crud-logger",
      [
        [:om_crud, :execute, :start],
        [:om_crud, :execute, :stop],
        [:om_crud, :execute, :exception]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:om_crud, :execute, :stop], measurements, metadata, _config) do
    Logger.info("CRUD #{metadata.operation} completed in #{measurements.duration_ms}ms")
  end

  def handle_event([:om_crud, :execute, :exception], _measurements, metadata, _config) do
    Logger.error("CRUD exception: #{inspect(metadata.reason)}")
  end
end
```

---

## Configuration

```elixir
# config/config.exs
config :om_crud,
  default_repo: MyApp.Repo,
  telemetry_prefix: [:my_app, :crud, :execute]

# Batch processing defaults
config :om_crud, OmCrud.Batch,
  default_batch_size: 500,
  default_timeout: 30_000

# Soft delete defaults
config :om_crud, OmCrud.SoftDelete,
  field: :deleted_at,
  timestamp: &DateTime.utc_now/0
```

---

## Real-World Examples

### User Registration Flow

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context
  alias OmCrud.Multi

  crud User, changeset: :registration_changeset
  crud Account
  crud Membership

  def register_user(attrs) do
    Multi.new()
    |> Multi.create(:user, User, attrs)
    |> Multi.create(:account, Account, fn %{user: u} ->
         %{name: "#{u.email}'s Account", owner_id: u.id}
       end)
    |> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
         %{user_id: u.id, account_id: a.id, role: :owner}
       end)
    |> Multi.run(:welcome_email, fn %{user: u} ->
         MyApp.Mailer.send_welcome(u)
         {:ok, :sent}
       end)
    |> OmCrud.run()
  end
end
```

### Atomic Registration with Steps

```elixir
defmodule MyApp.Accounts do
  import OmCrud.Atomic

  def register_user(attrs) do
    atomic fn ->
      %{}
      |> accumulate(:user, fn -> OmCrud.create(User, attrs) end)
      |> accumulate(:account, fn ctx ->
           OmCrud.create(Account, %{owner_id: ctx.user.id})
         end)
      |> accumulate(:membership, fn ctx ->
           OmCrud.create(Membership, %{
             user_id: ctx.user.id,
             account_id: ctx.account.id,
             role: :owner
           })
         end)
      |> finalize()
    end
  end
end
```

### Multi-Tenant Operations

```elixir
defmodule MyApp.Tenants do
  def create_tenant_user(tenant, attrs) do
    OmCrud.create(User, attrs, prefix: "tenant_#{tenant.id}")
  end

  def list_tenant_users(tenant, opts \\ []) do
    opts = Keyword.put(opts, :prefix, "tenant_#{tenant.id}")
    OmCrud.fetch_all(User, opts)
  end
end
```

### External System Sync

```elixir
defmodule MyApp.Sync do
  alias OmCrud.Merge

  def sync_users_from_external(external_users) do
    User
    |> Merge.new(normalize_external_users(external_users))
    |> Merge.match_on(:external_id)
    |> Merge.when_matched(:update, [:name, :email, :synced_at])
    |> Merge.when_not_matched(:insert, %{status: :pending, source: :external})
    |> Merge.returning([:id, :external_id])
    |> OmCrud.run()
  end

  defp normalize_external_users(users) do
    Enum.map(users, fn user ->
      %{
        external_id: user["id"],
        name: user["full_name"],
        email: user["email"],
        synced_at: DateTime.utc_now()
      }
    end)
  end
end
```

### Batch Import with Placeholders

```elixir
defmodule MyApp.Import do
  def import_records(org_id, records) do
    now = DateTime.utc_now()
    placeholders = %{now: now, org_id: org_id, status: :imported}

    entries =
      Enum.map(records, fn record ->
        %{
          name: record.name,
          email: record.email,
          org_id: {:placeholder, :org_id},
          status: {:placeholder, :status},
          inserted_at: {:placeholder, :now},
          updated_at: {:placeholder, :now}
        }
      end)

    OmCrud.create_all(User, entries,
      placeholders: placeholders,
      returning: true,
      timeout: 120_000
    )
  end
end
```

### Large Dataset Processing

```elixir
defmodule MyApp.Migration do
  alias OmCrud.Batch

  def migrate_user_data do
    # Process in parallel batches
    Batch.parallel(User, fn batch ->
      Enum.each(batch, fn user ->
        attrs = compute_new_fields(user)
        OmCrud.update(user, attrs)
      end)
    end, batch_size: 1000, max_concurrency: 4)
  end

  def archive_inactive_users do
    Batch.update(User, fn user ->
      %{status: :archived, archived_at: DateTime.utc_now()}
    end, where: [status: :inactive], batch_size: 500)
  end
end
```

### Soft Delete Workflow

```elixir
defmodule MyApp.Accounts do
  alias OmCrud.{Multi, SoftDelete}

  def deactivate_user(user) do
    Multi.new()
    |> SoftDelete.multi_delete(:user, user)
    |> Multi.run(:revoke_sessions, fn %{user: u} ->
         Session
         |> Query.where(:user_id, u.id)
         |> OmCrud.delete_all()
       end)
    |> Multi.run(:notify, fn %{user: u} ->
         Mailer.send_deactivation(u)
         {:ok, :notified}
       end)
    |> OmCrud.run()
  end

  def reactivate_user(user) do
    SoftDelete.restore(user)
  end
end
```

---

## Best Practices

### 1. Always Use Result Tuples

```elixir
# Good: Pattern match on results
case OmCrud.fetch(User, id) do
  {:ok, user} -> process_user(user)
  {:error, :not_found} -> handle_not_found()
end

# Avoid: Using get without nil check
user = OmCrud.get(User, id)  # Could be nil!
```

### 2. Use Placeholders for Bulk Operations

```elixir
# Good: Reduces data transfer
placeholders = %{now: DateTime.utc_now(), org_id: org.id}
entries = Enum.map(data, &Map.put(&1, :org_id, {:placeholder, :org_id}))
OmCrud.create_all(User, entries, placeholders: placeholders)

# Avoid: Repeating values in every entry
entries = Enum.map(data, &Map.put(&1, :org_id, org.id))  # Sends org_id N times
```

### 3. Set Appropriate Timeouts

```elixir
# Good: Increase timeout for long operations
OmCrud.create_all(User, large_dataset, timeout: 120_000)

# Good: Use default for quick operations
OmCrud.fetch(User, id)  # Default 15s is fine
```

### 4. Use Context Modules for Domain Logic

```elixir
# Good: Domain-specific context
defmodule MyApp.Accounts do
  use OmCrud.Context
  crud User

  def register_user(attrs) do
    with {:ok, user} <- create_user(attrs),
         :ok <- send_welcome_email(user) do
      {:ok, user}
    end
  end
end

# Avoid: Using OmCrud directly everywhere
OmCrud.create(User, attrs)  # No domain context
```

### 5. Leverage Multi for Atomicity

```elixir
# Good: All-or-nothing operations
Multi.new()
|> Multi.create(:user, User, attrs)
|> Multi.create(:account, Account, fn %{user: u} -> ... end)
|> OmCrud.run()

# Avoid: Separate calls that can partially fail
{:ok, user} = OmCrud.create(User, attrs)
{:ok, account} = OmCrud.create(Account, %{owner_id: user.id})  # User created but account might fail!
```

### 6. Use Batch for Large Datasets

```elixir
# Good: Memory-efficient batch processing
Batch.each(User, &process_batch/1, batch_size: 500)

# Avoid: Loading everything into memory
users = Repo.all(User)  # Could OOM on large tables
Enum.each(users, &process/1)
```

### 7. Use Atomic for Complex Transactions

```elixir
# Good: Clean step-based approach
atomic fn ->
  user = step!(:create_user, OmCrud.create(User, attrs))
  account = step!(:create_account, OmCrud.create(Account, %{user_id: user.id}))
  {:ok, %{user: user, account: account}}
end

# Good alternative: Multi pipeline
Multi.new()
|> Multi.create(:user, User, attrs)
|> Multi.create(:account, Account, fn %{user: u} -> %{user_id: u.id} end)
|> OmCrud.run()
```

---

## When to Use What

OmCrud provides several tools for database operations. Here's when to reach for each:

### Decision Table

| Scenario | Use | Why |
|----------|-----|-----|
| Simple create/fetch/update/delete | `OmCrud.create/3`, `fetch/3`, etc. | Minimal ceremony, result tuples |
| Get existing or create new | `OmCrud.find_or_create/3` | Atomic lookup + create in one call |
| Update existing or create new | `OmCrud.update_or_create/3` | Atomic lookup + update/create |
| Multiple related records atomically | `OmCrud.Multi` | Pipeline API, named steps, composable |
| Complex transaction with branching logic | `OmCrud.Multi` with conditionals | `when_ok`, `branch`, `when_cond` |
| Transaction with imperative control flow | `OmCrud.Atomic` | `step!`, `optional_step!`, `with` chains |
| Build up context across many steps | `OmCrud.Atomic` accumulator | `accumulate/3` + `finalize/1` pipeline |
| Sync data from external system | `OmCrud.Merge` | PostgreSQL MERGE with conditional clauses |
| Bulk insert thousands of records | `OmCrud.create_all/3` | Single transaction, placeholders |
| Process millions of records | `OmCrud.Batch` | Chunked, memory-efficient, streaming |
| Parallel heavy processing | `OmCrud.Batch.parallel/3` | Concurrent batch processing |
| Context module with full CRUD | `OmCrud.Context` | `crud` macro generates 20+ functions |
| Soft delete instead of hard delete | `OmCrud.SoftDelete` | Timestamp-based, query filtering |

### Multi vs Atomic

Both handle transactions, but they have different strengths:

```elixir
# Multi: Declarative pipeline. Best when steps are independent creates/updates.
# Each step is named and composable. Supports conditionals and composition.
Multi.new()
|> Multi.create(:user, User, attrs)
|> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
|> Multi.when_ok(:admin, fn %{user: u} ->
     if u.role == :admin, do: Multi.new() |> Multi.create(:perms, Perm, %{user_id: u.id}), else: Multi.new()
   end)
|> OmCrud.run()

# Atomic: Imperative control flow. Best when you need if/else, loops,
# or complex business logic between steps.
import OmCrud.Atomic

atomic fn ->
  user = step!(:create_user, OmCrud.create(User, attrs))

  account = if user.needs_account? do
    step!(:create_account, OmCrud.create(Account, %{owner_id: user.id}))
  end

  org = optional_step!(:fetch_org, OmCrud.fetch(Org, user.org_id))
  org = org || step!(:create_org, OmCrud.create(Org, %{owner_id: user.id}))

  {:ok, %{user: user, account: account, org: org}}
end
```

### Bulk Operations vs Batch

```elixir
# OmCrud.create_all - Single transaction, all-or-nothing.
# Use for: up to ~10,000 records that must succeed together.
OmCrud.create_all(User, entries, placeholders: placeholders)

# OmCrud.Batch.create_all - Multiple transactions in chunks.
# Use for: 10,000+ records where partial success is acceptable.
Batch.create_all(User, large_list, batch_size: 1000, on_error: :collect)

# OmCrud.Batch.parallel - Concurrent chunked processing.
# Use for: CPU-heavy per-record work on large datasets.
Batch.parallel(User, &heavy_computation/1, max_concurrency: 4)
```

---

## Migrating from Raw Ecto

### Single Operations

```elixir
# Before: Raw Ecto
%User{}
|> User.changeset(attrs)
|> Repo.insert()

# After: OmCrud (changeset auto-resolved)
OmCrud.create(User, attrs)
```

```elixir
# Before: Repo.get returns nil
case Repo.get(User, id) do
  nil -> {:error, :not_found}
  user -> {:ok, user}
end

# After: OmCrud.fetch returns result tuple
OmCrud.fetch(User, id)
```

```elixir
# Before: Manual changeset for update
user
|> User.changeset(attrs)
|> Repo.update()

# After: OmCrud handles changeset
OmCrud.update(user, attrs)
```

### Transactions

```elixir
# Before: Ecto.Multi (verbose)
Ecto.Multi.new()
|> Ecto.Multi.insert(:user, User.changeset(%User{}, user_attrs))
|> Ecto.Multi.run(:account, fn repo, %{user: u} ->
     %Account{}
     |> Account.changeset(%{owner_id: u.id})
     |> repo.insert()
   end)
|> Repo.transaction()

# After: OmCrud.Multi (clean pipeline)
Multi.new()
|> Multi.create(:user, User, user_attrs)
|> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
|> OmCrud.run()
```

### Find-or-Create Pattern

```elixir
# Before: Manual get_by + insert
case Repo.get_by(User, email: attrs.email) do
  nil ->
    %User{} |> User.changeset(attrs) |> Repo.insert()
  user ->
    {:ok, user}
end

# After: One call
OmCrud.find_or_create(User, attrs, find_by: :email)
```

### Update-or-Create Pattern

```elixir
# Before: Manual get_by + insert/update
case Repo.get_by(Setting, key: key) do
  nil ->
    %Setting{} |> Setting.changeset(%{key: key, value: value}) |> Repo.insert()
  existing ->
    existing |> Setting.changeset(%{value: value}) |> Repo.update()
end

# After: One call
OmCrud.update_or_create(Setting, %{key: key, value: value}, find_by: :key)
```

### Bulk Operations

```elixir
# Before: Raw insert_all
Repo.insert_all(User, entries, on_conflict: :nothing, conflict_target: :email)

# After: OmCrud with result tuple
OmCrud.upsert_all(User, entries,
  conflict_target: :email,
  on_conflict: :nothing
)
```

### Context Modules

```elixir
# Before: Manual boilerplate (repeat for every schema)
defmodule MyApp.Accounts do
  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end

  def get_user(id), do: Repo.get(User, id)

  def update_user(user, attrs) do
    user |> User.changeset(attrs) |> Repo.update()
  end

  def delete_user(user), do: Repo.delete(user)

  def list_users do
    User |> order_by(desc: :inserted_at) |> Repo.all()
  end
  # ... repeat for Role, Membership, Session, etc.
end

# After: One line per schema, 20+ functions each
defmodule MyApp.Accounts do
  use OmCrud.Context

  crud User
  crud Role, only: [:create, :fetch, :update]
  crud Membership, preload: [:user, :account]
  crud Session, except: [:update]
end
```

### Gradual Adoption

OmCrud can be adopted incrementally. You don't need to convert everything at once:

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  # New schemas use crud macro
  crud User
  crud Role

  # Existing code works alongside — OmCrud.Multi.to_ecto_multi/1
  # converts to Ecto.Multi for integration with legacy code
  def legacy_operation(user) do
    multi = Multi.new() |> Multi.update(:user, user, %{migrated: true})
    ecto_multi = Multi.to_ecto_multi(multi)

    # Combine with existing Ecto.Multi
    ecto_multi
    |> Ecto.Multi.run(:legacy, fn repo, _ -> legacy_step(repo) end)
    |> Repo.transaction()
  end
end
```

---

## Architecture

```
OmCrud (Unified API)
├── OmCrud.Multi        → Token-based transaction builder
├── OmCrud.Merge        → PostgreSQL MERGE adapter (delegates to OmQuery.Merge)
├── OmCrud.Atomic       → Functional transaction helper with step! pattern
├── OmCrud.Batch        → Memory-efficient batch processing
├── OmCrud.SoftDelete   → Soft delete support
├── OmCrud.Context      → crud macro for generating CRUD functions
├── OmCrud.Options      → Unified option handling
├── OmCrud.ChangesetBuilder → Smart changeset resolution
├── OmCrud.Error        → Rich structured error types
├── OmCrud.Telemetry    → Telemetry event emission
├── OmCrud.Pagination   → Cursor pagination metadata
├── OmCrud.Result       → Type-safe result container
├── OmCrud.Schema       → Schema-level CRUD integration
├── OmCrud.Config       → Configuration management
└── Protocols
    ├── OmCrud.Executable  → Execute tokens
    ├── OmCrud.Validatable → Validate tokens
    └── OmCrud.Debuggable  → Debug inspection
```

## License

MIT
