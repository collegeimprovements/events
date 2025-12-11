# CRUD System Reference

The CRUD system provides a unified, composable API for all database operations. All mutations go through `Ecto.Multi` internally, enabling future audit integration.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Events.Core.Crud                        │
│         Unified execution: run/1, create/3, fetch/3         │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  Crud.Multi   │    │  Crud.Merge   │    │  Query.Token  │
│  Transactions │    │ PostgreSQL 18 │    │   Queries     │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
     ┌────────────────────────┴────────────────────────┐
     ▼                                                 ▼
┌─────────────────────────┐            ┌─────────────────────────┐
│  Crud.ChangesetBuilder  │            │      Crud.Options       │
│  Changeset building &   │            │  Option extraction,     │
│  resolution             │            │  validation, defaults   │
└─────────────────────────┘            └─────────────────────────┘
```

## Quick Reference

| Module | Purpose |
|--------|---------|
| `Events.Core.Crud` | Unified execution API |
| `Events.Core.Crud.Multi` | Transaction composer |
| `Events.Core.Crud.Merge` | PostgreSQL MERGE operations |
| `Events.Core.Crud.ChangesetBuilder` | Changeset building and resolution |
| `Events.Core.Crud.Options` | Option extraction, validation, defaults |
| `Events.Core.Crud.Op` | **Deprecated** - backwards compatibility layer |
| `Events.Core.Crud.Context` | Context-level `crud` macro |
| `Events.Core.Crud.Schema` | Schema-level integration |

---

## Events.Core.Crud

The main execution API. All functions return result tuples.

### Unified Execution

#### `run/2`
Execute any Executable token (Multi, Merge, Query).

```elixir
# Execute a Multi
Multi.new()
|> Multi.create(:user, User, %{email: "test@example.com"})
|> Crud.run()
# => {:ok, %{user: %User{}}}

# Execute a Merge
User
|> Merge.new(users_data)
|> Merge.match_on(:email)
|> Merge.when_matched(:update)
|> Crud.run()
# => {:ok, [%User{}, ...]}

# Execute a Query
User
|> Query.new()
|> Query.filter(:status, :eq, :active)
|> Crud.run()
# => {:ok, %Query.Result{data: [%User{}, ...]}}
```

#### `transaction/2`
Execute a Multi as a database transaction.

```elixir
multi =
  Multi.new()
  |> Multi.create(:user, User, user_attrs)
  |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)

{:ok, %{user: user, account: account}} = Crud.transaction(multi)

# Also accepts a function for lazy evaluation
Crud.transaction(fn -> build_multi(params) end)
```

**Options:**
- `:timeout` - Transaction timeout in milliseconds
- `:prefix` - Database schema prefix

### Single Record Operations

#### `create/3`
Create a new record.

```elixir
{:ok, user} = Crud.create(User, %{email: "test@example.com"})
{:ok, user} = Crud.create(User, attrs, changeset: :registration_changeset)
{:ok, user} = Crud.create(User, attrs, preload: [:account])
```

**Options:**
- `:changeset` - Changeset function name (default: `:changeset`)
- `:preload` - Associations to preload after creation

#### `update/3` and `update/4`
Update an existing record.

```elixir
# Update a struct
{:ok, user} = Crud.update(user, %{name: "Updated"})

# Update by schema and ID
{:ok, user} = Crud.update(User, user_id, %{name: "Updated"})

# With options
{:ok, user} = Crud.update(user, attrs, changeset: :admin_changeset)
```

#### `delete/2` and `delete/3`
Delete a record.

```elixir
{:ok, user} = Crud.delete(user)
{:ok, user} = Crud.delete(User, user_id)
```

### Read Operations

#### `fetch/3`
Fetch a record, returning `{:ok, record}` or `{:error, :not_found}`.

```elixir
{:ok, user} = Crud.fetch(User, id)
{:ok, user} = Crud.fetch(User, id, preload: [:account, :memberships])

# Using Query token
{:ok, user} =
  User
  |> Query.new()
  |> Query.filter(:email, :eq, email)
  |> Crud.fetch()
```

#### `get/3`
Get a record, returning the record or `nil`.

```elixir
user = Crud.get(User, id)
user = Crud.get(User, id, preload: [:account])
```

#### `exists?/2`
Check if a record exists.

```elixir
true = Crud.exists?(User, user_id)
false = Crud.exists?(User, "nonexistent")
```

#### `fetch_all/2`
Fetch all records matching a Query token.

```elixir
{:ok, users} =
  User
  |> Query.new()
  |> Query.filter(:status, :eq, :active)
  |> Crud.fetch_all()
```

#### `count/1`
Count records matching a Query token.

```elixir
count =
  User
  |> Query.new()
  |> Query.filter(:status, :eq, :active)
  |> Crud.count()
```

### Bulk Operations

#### `create_all/3`
Bulk insert records.

```elixir
{:ok, users} = Crud.create_all(User, [
  %{email: "a@test.com"},
  %{email: "b@test.com"}
])

# With returning
{:ok, users} = Crud.create_all(User, entries, returning: [:id, :email])
```

#### `upsert_all/3`
Bulk upsert with conflict handling.

```elixir
{:ok, users} = Crud.upsert_all(User, users_data,
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)
```

**Conflict options:**
- `:conflict_target` - Column(s) for conflict detection
- `:on_conflict` - `:nothing`, `:replace_all`, `{:replace, fields}`

#### `update_all/3`
Bulk update matching records.

```elixir
{:ok, count} =
  User
  |> Query.new()
  |> Query.filter(:status, :eq, :inactive)
  |> Crud.update_all(set: [archived_at: DateTime.utc_now()])
```

#### `delete_all/2`
Bulk delete matching records.

```elixir
{:ok, count} =
  Token
  |> Query.new()
  |> Query.filter(:expired_at, :<, DateTime.utc_now())
  |> Crud.delete_all()
```

---

## Events.Core.Crud.Multi

Token-based transaction builder. Build transactions with flat pipelines, execute explicitly.

### Creation

```elixir
Multi.new()                 # Empty Multi
Multi.new(User)             # Multi with default schema
```

### Single Record Operations

#### `create/5`
Add a create operation.

```elixir
# Static attributes
Multi.create(multi, :user, User, %{email: "test@example.com"})

# With changeset option
Multi.create(multi, :user, User, attrs, changeset: :registration_changeset)

# Dynamic attributes from previous results
Multi.create(multi, :account, Account, fn %{user: user} ->
  %{owner_id: user.id, name: "#{user.name}'s Account"}
end)
```

#### `update/5`
Add an update operation.

```elixir
# Update a struct
Multi.update(multi, :user, user, %{name: "Updated"})

# Update by {schema, id}
Multi.update(multi, :user, {User, user_id}, %{name: "Updated"})

# Update result from previous operation
Multi.update(multi, :confirm, fn %{user: u} -> u end, %{confirmed_at: DateTime.utc_now()})
```

#### `delete/4`
Add a delete operation.

```elixir
Multi.delete(multi, :user, user)
Multi.delete(multi, :user, {User, user_id})
Multi.delete(multi, :token, fn %{user: u} -> u.token end)
```

### Upsert Operations

#### `upsert/5`
Add an upsert using ON CONFLICT.

```elixir
Multi.upsert(multi, :user, User, attrs,
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)
```

#### `merge/3`
Add a MERGE operation to the Multi.

```elixir
merge_token =
  User
  |> Merge.new(external_data)
  |> Merge.match_on(:external_id)
  |> Merge.when_matched(:update)
  |> Merge.when_not_matched(:insert)

Multi.merge(multi, :sync, merge_token)
```

### Bulk Operations

#### `create_all/5`
Bulk insert.

```elixir
Multi.create_all(multi, :users, User, [
  %{email: "a@test.com"},
  %{email: "b@test.com"}
], returning: true)
```

#### `upsert_all/5`
Bulk upsert.

```elixir
Multi.upsert_all(multi, :users, User, users_data,
  conflict_target: :email,
  on_conflict: {:replace, [:name]}
)
```

#### `update_all/5`
Bulk update.

```elixir
query = from(u in User, where: u.status == :inactive)
Multi.update_all(multi, :deactivate, query, set: [archived_at: DateTime.utc_now()])
```

#### `delete_all/4`
Bulk delete.

```elixir
query = from(t in Token, where: t.expired_at < ^DateTime.utc_now())
Multi.delete_all(multi, :cleanup, query)
```

### Dynamic Operations

#### `run/3`
Add a custom operation with access to previous results.

```elixir
# Function form
Multi.run(multi, :validate, fn %{user: user} ->
  if valid?(user), do: {:ok, user}, else: {:error, :invalid}
end)

# MFA form
Multi.run(multi, :notify, MyModule, :send_notification, [:user_created])
```

#### `inspect_results/3`
Debug by inspecting intermediate results.

```elixir
Multi.inspect_results(multi, :debug, fn results ->
  IO.inspect(results, label: "Transaction state")
end)
```

#### `when_ok/3`
Conditionally add operations based on previous results.

```elixir
Multi.when_ok(multi, :admin_setup, fn %{user: user} ->
  if user.role == :admin do
    Multi.new()
    |> Multi.create(:admin_record, AdminRecord, %{user_id: user.id})
  else
    Multi.new()  # Empty Multi, no operations added
  end
end)
```

### Composition

#### `append/2`
Append one Multi's operations after another.

```elixir
user_multi = Multi.new() |> Multi.create(:user, User, attrs)
account_multi = Multi.new() |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)

combined = Multi.append(user_multi, account_multi)
```

#### `prepend/2`
Prepend one Multi's operations before another.

```elixir
combined = Multi.prepend(account_multi, user_multi)
```

#### `embed/3`
Embed with a name prefix to avoid conflicts.

```elixir
setup = Multi.new() |> Multi.create(:record, User, attrs)
Multi.embed(multi, setup, prefix: :user)
# Creates operation named :user_record
```

### Introspection

```elixir
Multi.names(multi)            # => [:user, :account, :membership]
Multi.operation_count(multi)  # => 3
Multi.has_operation?(multi, :user)  # => true
Multi.empty?(multi)           # => false
```

### Conversion

```elixir
ecto_multi = Multi.to_ecto_multi(multi)
# Use with Repo.transaction directly if needed
```

---

## Events.Core.Crud.Merge

Token builder for PostgreSQL 18+ MERGE operations. More powerful than ON CONFLICT.

### Creation

```elixir
Merge.new(User)
Merge.new(User, %{email: "test@example.com"})
Merge.new(User, [%{email: "a@test.com"}, %{email: "b@test.com"}])
```

### Configuration

#### `source/2`
Set or replace source data.

```elixir
Merge.source(merge, %{email: "test@example.com"})
Merge.source(merge, [%{email: "a@test.com"}, %{email: "b@test.com"}])
Merge.source(merge, from(u in ExternalUser, select: %{email: u.email}))
```

#### `match_on/2`
Set columns for matching.

```elixir
Merge.match_on(merge, :email)
Merge.match_on(merge, [:org_id, :email])
```

### WHEN MATCHED Clauses

#### `when_matched/2` and `when_matched/3`
Define behavior when a matching row exists.

```elixir
# Update all fields from source
Merge.when_matched(merge, :update)

# Update specific fields
Merge.when_matched(merge, :update, [:name, :updated_at])

# Delete matched rows
Merge.when_matched(merge, :delete)

# Do nothing
Merge.when_matched(merge, :nothing)

# Conditional: only update if source is newer
Merge.when_matched(merge, &source_newer/1, :update)
```

### WHEN NOT MATCHED Clauses

#### `when_not_matched/2` and `when_not_matched/3`
Define behavior when no matching row exists.

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

### Output

#### `returning/2`
Configure returned fields.

```elixir
Merge.returning(merge, true)            # All fields
Merge.returning(merge, false)           # No fields
Merge.returning(merge, [:id, :email])   # Specific fields
```

### Complete Examples

```elixir
# Simple upsert
User
|> Merge.new(%{email: "test@example.com", name: "Test"})
|> Merge.match_on(:email)
|> Merge.when_matched(:update, [:name, :updated_at])
|> Merge.when_not_matched(:insert)
|> Crud.run()

# Bulk sync from external source
User
|> Merge.new(external_users)
|> Merge.match_on(:external_id)
|> Merge.when_matched(:update, [:name, :email, :synced_at])
|> Merge.when_not_matched(:insert, %{status: :pending})
|> Merge.returning(true)
|> Crud.run()

# Conditional update - only if source is newer
User
|> Merge.new(incoming_data)
|> Merge.match_on(:id)
|> Merge.when_matched(&newer_than_target/1, :update)
|> Merge.when_matched(:nothing)
|> Merge.when_not_matched(:insert)
|> Crud.run()
```

---

## Events.Core.Crud.ChangesetBuilder

Pure functions for building and resolving changesets. No side effects.

Note: Named `ChangesetBuilder` to avoid confusion with `Ecto.Changeset`.

### Building Changesets

```elixir
# From schema module (for create)
changeset = ChangesetBuilder.build(User, %{email: "test@example.com"})

# From existing struct (for update)
changeset = ChangesetBuilder.build(user, %{name: "Updated"})

# With explicit changeset function
changeset = ChangesetBuilder.build(User, attrs, changeset: :registration_changeset)

# With action hint
changeset = ChangesetBuilder.build(User, attrs, action: :create)
```

### Resolving Changeset Functions

```elixir
# Determine which changeset function to use
changeset_fn = ChangesetBuilder.resolve(User, :create, opts)
# => :changeset

changeset_fn = ChangesetBuilder.resolve(User, :create, changeset: :registration_changeset)
# => :registration_changeset
```

**Resolution priority:**
1. Explicit `:changeset` option
2. Action-specific option (`:create_changeset`, `:update_changeset`)
3. Schema's `@crud_changeset` attribute
4. Schema's `changeset_for/2` callback
5. Default `:changeset` function

---

## Events.Core.Crud.Options

Unified option handling for all CRUD operations. Single source of truth.

### Option Extraction

```elixir
# Extract valid options for insert
Options.insert_opts(returning: true, prefix: "tenant_1", invalid: :ignored)
# => [returning: true, prefix: "tenant_1"]

# Extract valid options for upsert
Options.upsert_opts(conflict_target: :email, on_conflict: :replace_all)
# => [conflict_target: [:email], on_conflict: :replace_all]

# Other operation extractors
Options.update_opts(returning: true, force: [:updated_at])
Options.delete_opts(prefix: "tenant_1")
Options.query_opts(prefix: "tenant", timeout: 15_000)
Options.insert_all_opts(returning: true, on_conflict: :nothing)
Options.update_all_opts(timeout: 60_000)
Options.delete_all_opts(prefix: "tenant_1")
```

### Helper Functions

```elixir
# Get the repo to use
Options.repo(opts)
# => Events.Core.Repo (default) or custom repo from opts

# Extract preloads
Options.preloads(preload: [:account, :memberships])
# => [:account, :memberships]

# Extract SQL/Repo options
Options.sql_opts(prefix: "tenant", timeout: 30_000, log: false)
# => [prefix: "tenant", timeout: 30_000, log: false]
```

---

## Events.Core.Crud.Op (Deprecated)

> **Deprecated**: Use `Events.Core.Crud.ChangesetBuilder` and `Events.Core.Crud.Options` instead.

This module exists for backwards compatibility. All functions delegate to the new modules:

| Old (Op)                | New Module | New Function |
|-------------------------|------------|--------------|
| `Op.changeset/3`        | `ChangesetBuilder` | `build/3` |
| `Op.resolve_changeset/3`| `ChangesetBuilder` | `resolve/3` |
| `Op.insert_opts/1`      | `Options` | `insert_opts/1` |
| `Op.update_opts/1`      | `Options` | `update_opts/1` |
| `Op.delete_opts/1`      | `Options` | `delete_opts/1` |
| `Op.query_opts/1`       | `Options` | `query_opts/1` |
| `Op.upsert_opts/1`      | `Options` | `upsert_opts/1` |
| `Op.insert_all_opts/1`  | `Options` | `insert_all_opts/1` |
| `Op.update_all_opts/1`  | `Options` | `update_all_opts/1` |
| `Op.delete_all_opts/1`  | `Options` | `delete_all_opts/1` |
| `Op.repo/1`             | `Options` | `repo/1` |
| `Op.preloads/1`         | `Options` | `preloads/1` |
| `Op.sql_opts/1`         | `Options` | `sql_opts/1` |

---

## Events.Core.Crud.Context

Generate CRUD functions in context modules with minimal boilerplate.

### Usage

```elixir
defmodule MyApp.Accounts do
  use Events.Core.Crud.Context

  # Generate all CRUD functions
  crud User

  # Generate specific functions
  crud Role, only: [:create, :fetch, :list]

  # Exclude specific functions
  crud Session, except: [:delete_all]

  # Custom resource name
  crud Membership, as: :member

  # Default preloads
  crud Account, preload: [:owner, :memberships]

  # Default changeset
  crud Profile, changeset: :public_changeset
end
```

### Generated Functions

For `crud User`:

| Function | Signature | Returns |
|----------|-----------|---------|
| `fetch_user/2` | `(id, opts)` | `{:ok, user} \| {:error, :not_found}` |
| `get_user/2` | `(id, opts)` | `user \| nil` |
| `list_users/1` | `(opts)` | `[user]` |
| `user_exists?/1` | `(id)` | `boolean` |
| `create_user/2` | `(attrs, opts)` | `{:ok, user} \| {:error, changeset}` |
| `update_user/3` | `(user, attrs, opts)` | `{:ok, user} \| {:error, changeset}` |
| `delete_user/2` | `(user, opts)` | `{:ok, user} \| {:error, changeset}` |
| `create_all_users/2` | `(entries, opts)` | `{count, users}` |
| `update_all_users/3` | `(query, updates, opts)` | `{count, users}` |
| `delete_all_users/2` | `(query, opts)` | `{count, users}` |

### Options

#### Function Selection

| Option | Description | Example |
|--------|-------------|---------|
| `:only` | Generate only these functions | `only: [:create, :fetch]` |
| `:except` | Exclude these functions | `except: [:delete_all]` |
| `:as` | Override resource name | `as: :member` |

#### Operation Defaults

| Option | Description | Example |
|--------|-------------|---------|
| `:preload` | Default preloads for reads | `preload: [:account]` |
| `:changeset` | Default changeset function | `changeset: :public_changeset` |

#### Crud-level Defaults (passed to all generated functions)

| Option | Type | Description |
|--------|------|-------------|
| `:repo` | `module()` | Default repository module for all operations |
| `:timeout` | `integer()` | Default timeout in milliseconds |
| `:prefix` | `String.t()` | Default schema prefix for multi-tenant setups |
| `:log` | `atom() \| false` | Default logging level or `false` to disable |

### Overriding Generated Functions

All generated functions are marked as `defoverridable`. You can define custom
implementations that replace or wrap the generated ones:

```elixir
defmodule MyApp.Accounts do
  use Events.Core.Crud.Context

  crud Role

  # Completely override create_role
  def create_role(attrs, opts \\ []) do
    attrs
    |> Map.put(:created_by, opts[:current_user_id])
    |> then(&Events.Core.Crud.create(Role, &1, opts))
  end

  # Wrap fetch_role using super()
  def fetch_role(id, opts \\ []) do
    case super(id, opts) do
      {:ok, role} -> {:ok, enrich_role(role)}
      error -> error
    end
  end

  defp enrich_role(role) do
    %{role | permissions: load_permissions(role)}
  end
end
```

**Note:** When overriding, match the full arity with defaults:
- Functions with `opts` parameter: `def foo(arg, opts \\ [])`
- Use `super(arg, opts)` to call the generated implementation

### Crud-level Default Options

Configure default options at the `crud` macro level that apply to all generated functions:

```elixir
defmodule MyApp.Accounts do
  use Events.Core.Crud.Context

  # Use a read replica for all User operations with higher timeout
  crud User, repo: MyApp.ReadOnlyRepo, timeout: 30_000

  # Multi-tenant setup with logging disabled
  crud Role, prefix: "tenant_123", log: false

  # Combine with function filtering
  crud Session,
    only: [:fetch, :create, :delete],
    repo: MyApp.SessionRepo,
    timeout: 5_000,
    log: :debug

  # AuditLog with all defaults for a specific tenant
  crud AuditLog,
    repo: MyApp.AuditRepo,
    prefix: "audit",
    timeout: 60_000,
    log: false
end
```

**Overriding at call time:**

Defaults configured at the `crud` level can be overridden for individual calls:

```elixir
# Uses MyApp.ReadOnlyRepo by default (from crud macro)
Accounts.fetch_user(id)

# Override to use the main repo for this specific call
Accounts.fetch_user(id, repo: MyApp.Repo)

# Override timeout for a specific heavy operation
Accounts.list_users(timeout: 60_000)

# All defaults apply, just adding preload
Accounts.fetch_session(id, preload: [:user])
```

**Common use cases:**

```elixir
# Read replicas for heavy read contexts
defmodule MyApp.Reports do
  use Events.Core.Crud.Context

  crud Report, repo: MyApp.ReportsReadReplica, timeout: 120_000, log: false
  crud ReportExport, repo: MyApp.ReportsReadReplica, timeout: 300_000
end

# Multi-tenant with shared config
defmodule MyApp.TenantAccounts do
  use Events.Core.Crud.Context

  @tenant_opts [prefix: "tenant_data", timeout: 10_000]

  crud User, @tenant_opts
  crud Role, @tenant_opts
  crud Permission, @tenant_opts ++ [preload: [:role]]
end

# High-frequency operations with logging disabled
defmodule MyApp.Analytics do
  use Events.Core.Crud.Context

  crud Event, log: false, timeout: 5_000
  crud Metric, log: false, timeout: 5_000
  crud Aggregation, log: :info, timeout: 30_000
end
```

---

## Events.Core.Crud.Schema

Schema-level CRUD integration.

### Usage

```elixir
defmodule MyApp.Accounts.User do
  use Events.Core.Schema
  use Events.Core.Crud.Schema

  schema "users" do
    field :email, :string
    timestamps()
  end

  # Set default changeset for all CRUD operations
  @crud_changeset :registration_changeset

  # Or use macro
  crud_changeset :registration_changeset

  # For dynamic resolution
  def changeset_for(:create, _opts), do: :registration_changeset
  def changeset_for(:update, _opts), do: :update_changeset
  def changeset_for(_, _), do: :changeset
end
```

---

## Real-World Examples

### User Registration with Account

```elixir
def register_user_with_account(user_attrs, account_attrs) do
  Multi.new()
  |> Multi.create(:user, User, user_attrs, changeset: :registration_changeset)
  |> Multi.create(:account, Account, fn _results -> account_attrs end)
  |> Multi.create(:membership, Membership, fn %{user: user, account: account} ->
    %{
      user_id: user.id,
      account_id: account.id,
      type: :owner,
      joined_at: DateTime.utc_now()
    }
  end)
  |> Multi.run(:welcome_email, fn %{user: user} ->
    Mailer.send_welcome(user)
    {:ok, :sent}
  end)
  |> Crud.run()
end
```

### Bulk User Import

```elixir
def import_users(csv_data) do
  users_data =
    csv_data
    |> CSV.parse()
    |> Enum.map(&transform_row/1)

  User
  |> Merge.new(users_data)
  |> Merge.match_on(:email)
  |> Merge.when_matched(:update, [:name, :phone, :updated_at])
  |> Merge.when_not_matched(:insert, %{status: :pending})
  |> Merge.returning([:id, :email, :status])
  |> Crud.run()
end
```

### Account Ownership Transfer

```elixir
def transfer_ownership(account, from_user, to_user) do
  Multi.new()
  |> Multi.run(:validate, fn _results ->
    cond do
      from_user.id == to_user.id -> {:error, :same_user}
      not member?(account, from_user) -> {:error, :not_owner}
      true -> {:ok, :valid}
    end
  end)
  |> Multi.run(:old_membership, fn _results ->
    case Repo.get_by(Membership, account_id: account.id, user_id: from_user.id) do
      nil -> {:error, :membership_not_found}
      m -> {:ok, m}
    end
  end)
  |> Multi.update(:demote, fn %{old_membership: m} -> m end, %{type: :member})
  |> Multi.run(:new_membership, fn _results ->
    case Repo.get_by(Membership, account_id: account.id, user_id: to_user.id) do
      nil -> Crud.create(Membership, %{account_id: account.id, user_id: to_user.id, type: :owner})
      m -> {:ok, m}
    end
  end)
  |> Multi.update(:promote, fn %{new_membership: m} -> m end, %{type: :owner})
  |> Crud.run()
end
```

### Soft Delete with Cascade

```elixir
def soft_delete_account(account) do
  now = DateTime.utc_now()

  Multi.new()
  |> Multi.update(:account, account, %{deleted_at: now, status: :deleted})
  |> Multi.update_all(:memberships,
    from(m in Membership, where: m.account_id == ^account.id),
    set: [deleted_at: now, status: :removed]
  )
  |> Multi.update_all(:invites,
    from(i in Invite, where: i.account_id == ^account.id),
    set: [deleted_at: now, status: :revoked]
  )
  |> Crud.run()
end
```

### Conditional Processing

```elixir
def process_order(order_params) do
  Multi.new()
  |> Multi.create(:order, Order, order_params)
  |> Multi.when_ok(:premium_benefits, fn %{order: order} ->
    if order.total > 100 do
      Multi.new()
      |> Multi.create(:reward, Reward, %{order_id: order.id, points: order.total})
      |> Multi.run(:notify, fn _ -> Notifications.send_premium_reward(order) end)
    else
      Multi.new()
    end
  end)
  |> Multi.run(:receipt, fn %{order: order} ->
    Receipts.generate(order)
  end)
  |> Crud.run()
end
```

---

## Protocols

The CRUD system uses three protocols for unified behavior:

### Executable

Enables `Crud.run/1` for any token type.

```elixir
defprotocol Events.Core.Crud.Executable do
  @spec execute(t(), keyword()) :: {:ok, any()} | {:error, any()}
  def execute(token, opts \\ [])
end
```

Implemented by: `Multi`, `Merge`, `Query.Token`

### Validatable

Pre-execution validation.

```elixir
defprotocol Events.Core.Crud.Validatable do
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(token)
end
```

### Debuggable

Structured debugging output.

```elixir
defprotocol Events.Core.Crud.Debuggable do
  @spec to_debug(t()) :: map()
  def to_debug(token)
end
```

---

## Complete Options Reference

All CRUD options are handled by `Events.Core.Crud.Options`, which provides a unified API
for option extraction, validation, and normalization.

### Options by Category

#### Universal Options (All Operations)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:repo` | `module()` | `Events.Core.Repo` | Custom repo module for the operation |
| `:prefix` | `String.t()` | `nil` | Database schema prefix (multi-tenant) |
| `:timeout` | `integer()` | `15_000` | Query timeout in milliseconds |
| `:log` | `atom() \| false` | repo default | Logger level or `false` to disable |

#### Read Options (fetch, get, list)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:preload` | `list()` | `[]` | Associations to preload |

#### Write Options (create, update, delete)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:changeset` | `atom()` | `:changeset` | Changeset function name |
| `:returning` | `boolean() \| list()` | `false` | Fields to return after operation |
| `:stale_error_field` | `atom()` | `nil` | Field for stale error messages |
| `:stale_error_message` | `String.t()` | `"is stale"` | Custom stale error message |
| `:allow_stale` | `boolean()` | `false` | Don't error on stale records |

#### Update-Specific Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:force` | `list()` | `[]` | Fields to mark changed even if unchanged |

#### Upsert Options (create with conflict handling)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:conflict_target` | `atom() \| list()` | required | Column(s) for conflict detection |
| `:on_conflict` | see below | `:nothing` | Action on conflict |

**`:on_conflict` values:**
- `:nothing` - Do nothing on conflict
- `:replace_all` - Replace all fields from source
- `{:replace, [:field1, :field2]}` - Replace specific fields
- `{:replace_all_except, [:field1]}` - Replace all except specific fields

#### Bulk Insert Options (create_all, upsert_all)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:placeholders` | `map()` | `nil` | Reusable values to reduce data transfer |
| `:returning` | `boolean() \| list()` | `false` | Fields to return |
| `:preload` | `list()` | `[]` | Associations to preload (requires `:returning`) |

#### Merge Options

Options can be stored in the Merge token via `Merge.opts/2` or passed to `Crud.run/2`.
Call-time options take precedence over token options.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:repo` | `module()` | `Events.Core.Repo` | Custom repo module |
| `:timeout` | `integer()` | `15_000` | Query timeout in milliseconds |
| `:prefix` | `String.t()` | `nil` | Database schema prefix |
| `:log` | `atom() \| false` | repo default | Logger level or `false` |

---

## Options Examples

### Custom Repo

Use different repos for read replicas or specific databases:

```elixir
# Read from replica
Crud.fetch(User, id, repo: MyApp.ReadOnlyRepo)
Crud.get(User, id, repo: MyApp.ReadOnlyRepo)
Crud.exists?(User, id, repo: MyApp.ReadOnlyRepo)

# Write to primary
Crud.create(User, attrs, repo: MyApp.PrimaryRepo)

# Transaction with specific repo
Multi.new()
|> Multi.create(:user, User, attrs)
|> Multi.create(:account, Account, account_attrs)
|> Crud.transaction(repo: MyApp.PrimaryRepo)

# Merge with specific repo
User
|> Merge.new(sync_data)
|> Merge.match_on(:external_id)
|> Merge.when_matched(:update)
|> Crud.run(repo: MyApp.SyncRepo)
```

### Custom Timeout

Override default 15s timeout for long-running operations:

```elixir
# Single record with timeout
Crud.create(User, large_attrs, timeout: 30_000)

# Bulk import with 2 minute timeout
Crud.create_all(User, thousands_of_records, timeout: 120_000)

# Complex transaction with 5 minute timeout
Multi.new()
|> Multi.create_all(:users, User, user_data)
|> Multi.create_all(:memberships, Membership, membership_data)
|> Multi.update_all(:notifications, notification_query, set: [sent: true])
|> Crud.transaction(timeout: 300_000)

# Merge operation with timeout
User
|> Merge.new(external_api_data)
|> Merge.match_on(:external_id)
|> Merge.when_matched(:update, [:name, :email, :synced_at])
|> Merge.when_not_matched(:insert)
|> Crud.run(timeout: 60_000)

# Combine repo and timeout
Crud.create_all(User, data,
  repo: MyApp.BulkRepo,
  timeout: 180_000,
  returning: true
)
```

### Logging Control

Control query logging per operation:

```elixir
# Disable logging for noisy/frequent operations
Crud.fetch(User, id, log: false)
Crud.exists?(User, id, log: false)

# Set specific log level
Crud.create(User, attrs, log: :debug)
Crud.create_all(User, entries, log: :info)

# Disable logging for large batch (reduce log noise)
Crud.create_all(User, thousands_of_records,
  log: false,
  timeout: 120_000,
  returning: [:id]
)

# Transaction with logging disabled
Multi.new()
|> Multi.create_all(:records, Record, large_dataset)
|> Crud.transaction(log: false, timeout: 300_000)
```

### Placeholders (Bulk Insert Optimization)

Reduce data transfer when inserting records with repeated values:

```elixir
# Basic placeholder usage
now = DateTime.utc_now()
placeholders = %{now: now}

entries = [
  %{name: "User A", inserted_at: {:placeholder, :now}, updated_at: {:placeholder, :now}},
  %{name: "User B", inserted_at: {:placeholder, :now}, updated_at: {:placeholder, :now}},
  %{name: "User C", inserted_at: {:placeholder, :now}, updated_at: {:placeholder, :now}}
]

Crud.create_all(User, entries, placeholders: placeholders)
```

```elixir
# Multiple placeholders for batch import
org_id = "org_123"
imported_at = DateTime.utc_now()
default_status = :pending

placeholders = %{
  org_id: org_id,
  imported_at: imported_at,
  status: default_status
}

entries =
  raw_data
  |> Enum.map(fn row ->
    %{
      name: row.name,
      email: row.email,
      org_id: {:placeholder, :org_id},
      status: {:placeholder, :status},
      imported_at: {:placeholder, :imported_at},
      inserted_at: {:placeholder, :imported_at},
      updated_at: {:placeholder, :imported_at}
    }
  end)

{:ok, users} = Crud.create_all(User, entries,
  placeholders: placeholders,
  returning: [:id, :email],
  timeout: 120_000
)
```

```elixir
# Placeholder with large repeated value (e.g., shared template)
template = File.read!("large_template.html")
placeholders = %{template: template}

entries = [
  %{name: "Email 1", body: {:placeholder, :template}, recipient: "a@test.com"},
  %{name: "Email 2", body: {:placeholder, :template}, recipient: "b@test.com"},
  %{name: "Email 3", body: {:placeholder, :template}, recipient: "c@test.com"}
]

# Template sent once instead of 3 times - significant bandwidth savings
Crud.create_all(Email, entries, placeholders: placeholders)
```

**When to use placeholders:**
- Bulk imports with shared metadata (org_id, timestamps)
- Records with large repeated TEXT/BLOB values
- High-volume inserts where bandwidth matters
- Importing data with common default values

**Limitations:**
- Cannot nest placeholders within arrays or maps
- Same placeholder key must have consistent type across columns
- Not supported by MySQL (PostgreSQL only)

### Stale Record Handling

Handle optimistic locking and stale records:

```elixir
# Default behavior: raises on stale
Crud.update(user, %{name: "New"})
# => {:error, %Ecto.Changeset{errors: [lock_version: {"is stale", []}]}}

# Allow stale updates (no error)
Crud.update(user, %{name: "New"}, allow_stale: true)
# => {:ok, user}  # even if stale

# Custom error field
Crud.update(user, %{name: "New"}, stale_error_field: :base)
# => {:error, %Ecto.Changeset{errors: [base: {"is stale", []}]}}

# Custom error message
Crud.update(user, %{name: "New"},
  stale_error_field: :lock_version,
  stale_error_message: "Record was modified by another user"
)
```

### Force Update Fields

Mark fields as changed even if the value is the same:

```elixir
# Always update updated_at even if no other changes
Crud.update(user, %{}, force: [:updated_at])

# Touch multiple timestamp fields
Crud.update(record, attrs, force: [:updated_at, :touched_at])

# Useful for "touch" operations
def touch(record) do
  Crud.update(record, %{updated_at: DateTime.utc_now()}, force: [:updated_at])
end
```

### Returning Fields

Control what's returned after write operations:

```elixir
# Return all fields (PostgreSQL)
{:ok, user} = Crud.create(User, attrs, returning: true)

# Return specific fields only
{:ok, user} = Crud.create(User, attrs, returning: [:id, :email])

# Bulk insert with returning
{:ok, users} = Crud.create_all(User, entries, returning: [:id, :email])
# users is a list with only id and email populated

# Upsert with returning
{:ok, users} = Crud.upsert_all(User, entries,
  conflict_target: :email,
  on_conflict: {:replace, [:name]},
  returning: true
)
```

### Multi-Tenant (Prefix)

Use schema prefixes for multi-tenant databases:

```elixir
# All operations support prefix
Crud.fetch(User, id, prefix: "tenant_123")
Crud.create(User, attrs, prefix: "tenant_123")
Crud.update(user, attrs, prefix: "tenant_123")

# Transaction with prefix
Multi.new()
|> Multi.create(:user, User, attrs)
|> Multi.create(:account, Account, account_attrs)
|> Crud.transaction(prefix: "tenant_456")

# Bulk operations
Crud.create_all(User, entries, prefix: "tenant_789", returning: true)

# Merge with prefix
User
|> Merge.new(data)
|> Merge.match_on(:email)
|> Merge.when_matched(:update)
|> Crud.run(prefix: "tenant_123")
```

### Combined Options Example

Real-world example combining multiple options:

```elixir
def bulk_import_users(org_id, csv_data, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 120_000)
  repo = Keyword.get(opts, :repo, Events.Core.Repo)

  now = DateTime.utc_now()
  placeholders = %{
    org_id: org_id,
    now: now,
    status: :pending_verification
  }

  entries =
    csv_data
    |> CSV.parse()
    |> Enum.map(fn row ->
      %{
        email: row["email"],
        name: row["name"],
        org_id: {:placeholder, :org_id},
        status: {:placeholder, :status},
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now}
      }
    end)

  Crud.create_all(User, entries,
    repo: repo,
    timeout: timeout,
    placeholders: placeholders,
    returning: [:id, :email, :status],
    log: :info
  )
end

def sync_external_users(org_id, external_data, opts \\ []) do
  User
  |> Merge.new(external_data)
  |> Merge.match_on([:org_id, :external_id])
  |> Merge.when_matched(:update, [:name, :email, :synced_at])
  |> Merge.when_not_matched(:insert, %{status: :active})
  |> Merge.returning(true)
  |> Crud.run(
    repo: Keyword.get(opts, :repo, Events.Core.Repo),
    timeout: Keyword.get(opts, :timeout, 60_000),
    prefix: Keyword.get(opts, :prefix),
    log: Keyword.get(opts, :log, :info)
  )
end
```
