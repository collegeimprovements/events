# OmCrud

Unified CRUD operations for Ecto with Multi transactions, PostgreSQL MERGE support, and context generators.

## Installation

```elixir
def deps do
  [{:om_crud, "~> 0.1.0"}]
end
```

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
:ok = OmCrud.delete(user)

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

- **Unified Execution** - Single `run/1` function for all operations
- **Token-Based** - Operations are data, execution is explicit
- **Result Tuples** - Consistent `{:ok, result}` | `{:error, reason}` returns
- **Multi Transactions** - Clean pipeline API for atomic operations
- **PostgreSQL MERGE** - Full MERGE syntax support for complex upserts
- **Context Generator** - `crud` macro generates boilerplate-free context modules
- **Changeset Resolution** - Smart changeset function discovery
- **Telemetry** - Automatic instrumentation for all operations
- **Multi-Tenancy** - First-class prefix/schema support

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

# With returning
{:ok, count} =
  User
  |> Query.where(:role, :guest)
  |> OmCrud.update_all([set: [status: :active]], returning: true)
```

### Delete All

```elixir
# Delete all matching records
{:ok, count} =
  Token
  |> Query.new()
  |> Query.where(:expired_at, :<, DateTime.utc_now())
  |> OmCrud.delete_all()

# With returning
{:ok, count} =
  Session
  |> Query.where(:user_id, user_id)
  |> OmCrud.delete_all(returning: [:id])
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
# Conditional based on previous results
Multi.when_ok(multi, :admin_setup, fn %{user: user} ->
  if user.role == :admin do
    Multi.new()
    |> Multi.create(:admin_record, AdminRecord, %{user_id: user.id})
    |> Multi.create(:permissions, Permission, %{user_id: user.id, level: :all})
  else
    Multi.new()  # Empty multi = no additional operations
  end
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
# Get operation names
Multi.names(multi)
#=> [:user, :account, :membership]

# Count operations
Multi.operation_count(multi)
#=> 3

# Check for operation
Multi.has_operation?(multi, :user)
#=> true

# Check if empty
Multi.empty?(multi)
#=> false
```

### Converting to Ecto.Multi

```elixir
# For integration with existing code
ecto_multi = Multi.to_ecto_multi(multi)
Repo.transaction(ecto_multi)
```

---

## PostgreSQL MERGE

Merge provides PostgreSQL 18+ MERGE syntax for complex upsert operations.

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
Merge.new(User)
|> Merge.source(external_query)
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
# Update all fields from source
Merge.when_matched(merge, :update)

# Update specific fields
Merge.when_matched(merge, :update, [:name, :updated_at])

# Update with explicit values
Merge.when_matched(merge, :update, set: [login_count: {:increment, 1}])

# Delete matched rows
Merge.when_matched(merge, :delete)

# Do nothing
Merge.when_matched(merge, :nothing)

# Conditional - only update if source is newer
Merge.when_matched(merge, &source_newer/1, :update)
Merge.when_matched(merge, :nothing)  # Fallback
```

### WHEN NOT MATCHED Clauses

```elixir
# Insert from source
Merge.when_not_matched(merge, :insert)

# Insert with default values
Merge.when_not_matched(merge, :insert, %{status: :pending, role: :member})

# Do nothing
Merge.when_not_matched(merge, :nothing)

# Conditional insert
Merge.when_not_matched(merge, &valid_email?/1, :insert)
```

### Output Configuration

```elixir
# Return all fields (default)
Merge.returning(merge, true)

# Return nothing
Merge.returning(merge, false)

# Return specific fields
Merge.returning(merge, [:id, :email, :updated_at])
```

### Options

```elixir
# Set execution options
Merge.opts(merge, prefix: "tenant_123", timeout: 60_000)
```

### Complete Example

```elixir
# Sync users from external system
{:ok, synced_users} =
  User
  |> Merge.new(external_users)
  |> Merge.match_on(:external_id)
  |> Merge.when_matched(fn query ->
       # Only update if external data is newer
       where(query, [s, t], s.updated_at > t.synced_at)
     end, :update, [:name, :email, :synced_at])
  |> Merge.when_matched(:nothing)  # Skip if not newer
  |> Merge.when_not_matched(:insert, %{status: :pending})
  |> Merge.returning([:id, :external_id, :email])
  |> Merge.opts(timeout: 120_000)
  |> OmCrud.run()
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

For `crud User`, the following functions are generated:

```elixir
# Read operations
fetch_user(id, opts \\ [])        # {:ok, user} | {:error, :not_found}
get_user(id, opts \\ [])          # user | nil
list_users(opts \\ [])            # [user, ...]
user_exists?(id, opts \\ [])      # true | false

# Write operations
create_user(attrs, opts \\ [])    # {:ok, user} | {:error, changeset}
update_user(user, attrs, opts \\ [])  # {:ok, user} | {:error, changeset}
delete_user(user, opts \\ [])     # {:ok, user} | {:error, changeset}

# Bulk operations
create_all_users(entries, opts \\ [])  # {count, users}
update_all_users(query, updates, opts \\ [])  # {count, users}
delete_all_users(query, opts \\ [])  # {count, users}
```

### Options

```elixir
# Control which functions are generated
crud User, only: [:create, :fetch, :update]
crud User, except: [:delete_all, :update_all]

# Custom resource name
crud Membership, as: :member
# Generates: create_member, fetch_member, etc.

# Default preloads
crud User, preload: [:account, :memberships]
# All read operations will preload these associations

# Default changeset
crud User, changeset: :admin_changeset
# All write operations use this changeset

# Default repo
crud AuditLog, repo: MyApp.ReadOnlyRepo

# Default timeout
crud ImportRecord, timeout: 60_000

# Default prefix (multi-tenancy)
crud TenantUser, prefix: "tenant_123"

# Disable logging
crud SensitiveData, log: false

# Combined options
crud User,
  preload: [:account],
  changeset: :admin_changeset,
  timeout: 30_000
```

### Overriding Generated Functions

All generated functions are `defoverridable`:

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
2. Action-specific option (`:create_changeset`, `:update_changeset`)
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
  @crud_changeset :admin_changeset  # Used by default

  def changeset(user, attrs), do: ...
  def admin_changeset(user, attrs), do: ...
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

### Building Changesets Manually

```elixir
alias OmCrud.ChangesetBuilder

# Build changeset for create
changeset = ChangesetBuilder.build(User, %{email: "test@example.com"})

# Build with explicit changeset function
changeset = ChangesetBuilder.build(User, attrs, changeset: :registration)

# Build for update (from existing struct)
changeset = ChangesetBuilder.build(user, %{name: "Updated"})

# Resolve changeset function name
fn_name = ChangesetBuilder.resolve(User, :create, [])
#=> :changeset

fn_name = ChangesetBuilder.resolve(User, :create, changeset: :registration)
#=> :registration
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
| `:returning` | bool/list | false | Return inserted/updated record |
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

### Bulk Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:placeholders` | map | nil | Reusable values for bulk inserts |
| `:conflict_target` | atom/list | nil | Column(s) for conflict detection |
| `:on_conflict` | atom/tuple | :nothing | Conflict handling action |

### Read Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:preload` | list | [] | Associations to preload |

### Conflict Handling

```elixir
# Do nothing on conflict
on_conflict: :nothing

# Replace all fields
on_conflict: :replace_all

# Replace specific fields
on_conflict: {:replace, [:name, :updated_at]}

# Replace all except specific fields
on_conflict: {:replace_all_except, [:id, :inserted_at]}

# Using constraint name
conflict_target: {:constraint, :users_email_unique}
```

---

## Telemetry Events

All operations emit telemetry events for observability.

### Event Names

```
[:om_crud, :execute, :start]
[:om_crud, :execute, :stop]
[:om_crud, :execute, :exception]
```

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
| `:operation` | atom | Operation (`:create`, `:update`, `:delete`, `:fetch`, etc.) |
| `:schema` | module | Schema module |
| `:id` | string | Record ID (single record operations) |
| `:count` | integer | Number of records (bulk operations) |
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

  def handle_event([:om_crud, :execute, :start], measurements, metadata, _config) do
    Logger.debug("CRUD start: #{inspect(metadata)}")
  end

  def handle_event([:om_crud, :execute, :stop], measurements, metadata, _config) do
    Logger.info("CRUD #{metadata.operation} completed in #{measurements.duration_ms}ms")
  end

  def handle_event([:om_crud, :execute, :exception], measurements, metadata, _config) do
    Logger.error("CRUD exception: #{inspect(metadata.reason)}")
  end
end
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
    placeholders = %{
      now: now,
      org_id: org_id,
      status: :imported
    }

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

### Archiving with Transaction

```elixir
defmodule MyApp.Archive do
  alias OmCrud.Multi

  def archive_user(user) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.update(:archive, user, %{archived_at: now, status: :archived})
    |> Multi.run(:archive_related, fn %{archive: archived_user} ->
         # Archive related sessions
         Session
         |> Query.where(:user_id, archived_user.id)
         |> OmCrud.update_all(set: [archived_at: now])
       end)
    |> Multi.run(:revoke_tokens, fn %{archive: archived_user} ->
         Token
         |> Query.where(:user_id, archived_user.id)
         |> OmCrud.delete_all()
       end)
    |> Multi.run(:notify, fn %{archive: archived_user} ->
         MyApp.Notifications.user_archived(archived_user)
         {:ok, :notified}
       end)
    |> OmCrud.run()
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
    # Add domain logic around generated functions
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

---

## Configuration

```elixir
# config/config.exs
config :om_crud,
  # Required: Default repository
  default_repo: MyApp.Repo,

  # Optional: Default timeout (default: 15_000)
  timeout: 30_000,

  # Optional: Telemetry event prefix
  telemetry_prefix: [:my_app, :crud, :execute]
```

---

## Error Handling

### Transaction Errors

```elixir
case OmCrud.run(multi) do
  {:ok, results} ->
    # Success - access results by operation name
    {:ok, results.user}

  {:error, failed_operation, failed_value, changes_so_far} ->
    # Transaction failed
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

### Not Found Errors

```elixir
case OmCrud.fetch(User, id) do
  {:ok, user} -> {:ok, user}
  {:error, :not_found} -> {:error, :user_not_found}
end
```

---

## License

MIT
