# OmCrud Cheatsheet

> OmCrud depends on [OmQuery](../om_query) for query building, filtering (`{field, op, value}` tuples), cursor pagination, and MERGE SQL generation.

## Setup

```elixir
config :om_crud, default_repo: MyApp.Repo
```

```elixir
alias OmCrud
alias OmCrud.{Multi, Merge, Batch, SoftDelete, Atomic, Error}
import OmCrud.Atomic  # for atomic/1, step!/1, etc.
```

---

## CRUD Operations

```elixir
# Create
{:ok, user} = OmCrud.create(User, %{email: "a@b.com"})
{:ok, user} = OmCrud.create(User, attrs, changeset: :registration_changeset)

# Fetch (result tuple)
{:ok, user} = OmCrud.fetch(User, id)
{:ok, user} = OmCrud.fetch(User, id, preload: [:account])

# Get (nil on miss)
user = OmCrud.get(User, id)

# Update
{:ok, user} = OmCrud.update(user, %{name: "New"})
{:ok, user} = OmCrud.update(User, id, %{name: "New"})

# Delete
{:ok, user} = OmCrud.delete(user)
{:ok, user} = OmCrud.delete(User, id)

# Upsert (requires :conflict_target)
{:ok, user} = OmCrud.upsert(User, attrs,
  conflict_target: :email, on_conflict: {:replace, [:name]})

# Find or Create (requires :find_by)
{:ok, user} = OmCrud.find_or_create(User, %{email: "a@b.com", name: "A"},
  find_by: :email)

# Update or Create (requires :find_by)
{:ok, user} = OmCrud.update_or_create(User, %{email: "a@b.com", name: "Updated"},
  find_by: :email)

# Exists?
true = OmCrud.exists?(User, id)
```

---

## Bulk Operations

```elixir
# Create all
{:ok, users} = OmCrud.create_all(User, [%{email: "a"}, %{email: "b"}])

# With placeholders (reduces data transfer)
{:ok, users} = OmCrud.create_all(User, entries,
  placeholders: %{now: DateTime.utc_now()}, returning: true)

# Upsert all
{:ok, users} = OmCrud.upsert_all(User, data,
  conflict_target: :email, on_conflict: :replace_all)

# Update all (via query token)
{:ok, count} = query_token |> OmCrud.update_all(set: [status: :archived])

# Delete all
{:ok, count} = query_token |> OmCrud.delete_all()
```

---

## Multi Transactions

```elixir
{:ok, %{user: u, account: a}} =
  Multi.new()
  |> Multi.create(:user, User, user_attrs)
  |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
  |> Multi.update(:user, fn %{user: u} -> u end, %{confirmed: true})
  |> Multi.delete(:token, fn %{user: u} -> u.token end)
  |> Multi.run(:notify, fn %{user: u} -> {:ok, send_email(u)} end)
  |> OmCrud.run()
```

### Multi Bulk

```elixir
Multi.create_all(m, :users, User, entries)
Multi.upsert_all(m, :users, User, data, conflict_target: :email)
Multi.update_all(m, :archive, query, set: [archived: true])
Multi.delete_all(m, :cleanup, query)
Multi.merge(m, :sync, merge_token)
```

### Multi Conditionals

```elixir
Multi.when_ok(m, :setup, fn results -> Multi.new() |> ... end)
Multi.when_cond(m, flag?, fn m -> Multi.run(m, :x, &fun/1) end)
Multi.unless(m, skip?, fn m -> ... end)
Multi.branch(m, cond?, &if_true/1, &if_false/1)
Multi.each(m, :items, list, fn m, item, index, results -> ... end)
Multi.when_value(m, :role, :admin, fn m -> ... end)
Multi.when_match(m, :user, &(&1.role == :admin), fn m -> ... end)
```

### Multi Composition

```elixir
Multi.append(m1, m2)            # m1 ops then m2 ops
Multi.prepend(m1, m2)           # m2 ops then m1 ops
Multi.embed(m1, m2, prefix: :p) # prefixed ops: :p_name
```

### Multi Introspection

```elixir
Multi.names(m)                  #=> [:user, :account]
Multi.operation_count(m)        #=> 2
Multi.has_operation?(m, :user)  #=> true
Multi.empty?(m)                 #=> false
Multi.to_ecto_multi(m)          #=> %Ecto.Multi{}
```

---

## PostgreSQL MERGE

```elixir
{:ok, results} =
  User
  |> Merge.new(source_data)
  |> Merge.match_on(:email)                              # or [:org_id, :email]
  |> Merge.when_matched(:update, [:name, :updated_at])   # :update | :delete | :nothing
  |> Merge.when_not_matched(:insert, %{status: :new})    # :insert | :nothing
  |> Merge.returning([:id, :email])                       # true | false | [fields]
  |> Merge.opts(timeout: 60_000)
  |> OmCrud.run()

# Conditional clauses
|> Merge.when_matched(&source_newer/1, :update, [:name])
|> Merge.when_matched(:nothing)  # fallback

# Validation & SQL
:ok = Merge.validate(merge)
{sql, params} = Merge.to_sql(merge)
```

---

## Atomic Operations

```elixir
import OmCrud.Atomic

# Basic
atomic(fn -> {:ok, result} | {:error, reason} end)
atomic([repo: Repo, timeout: 30_000], fn -> ... end)

# With context
atomic_with_context(%{org_id: 1}, fn ctx -> ... end)

# step! - raises on error (triggers rollback)
user = step!(OmCrud.create(User, attrs))
user = step!(:create_user, OmCrud.create(User, attrs))  # named

# optional_step! - returns nil for :not_found
org = optional_step!(:fetch_org, OmCrud.fetch(Org, id))

# step - non-raising, returns result tuple
{:ok, user} = step(:fetch, OmCrud.fetch(User, id))

# Accumulator pattern
atomic fn ->
  %{}
  |> accumulate(:user, fn -> OmCrud.create(User, attrs) end)
  |> accumulate(:account, fn ctx -> OmCrud.create(Account, %{user_id: ctx.user.id}) end)
  |> accumulate_optional(:org, fn ctx -> OmCrud.fetch(Org, ctx.user.org_id) end)
  |> finalize()        # {:ok, %{user: _, account: _, org: _}}
  # or finalize(:user) # {:ok, user}
end
```

---

## Batch Processing

```elixir
# Iterate (side effects)
Batch.each(User, &process/1, batch_size: 100, where: [status: :active])

# Process with tracking
{:ok, %{processed: n, errors: []}} = Batch.process(User, fn batch ->
  {:ok, length(batch)}
end, on_error: :collect)  # :halt | :continue | :collect

# Batch update
{:ok, _} = Batch.update(User, fn u -> %{points: u.points + 10} end)

# Batch delete
{:ok, _} = Batch.delete(User, where: [status: :inactive])

# Chunked inserts
{:ok, _} = Batch.create_all(User, large_list, batch_size: 1000)
{:ok, _} = Batch.upsert_all(User, data, conflict_target: :email)

# Streaming (requires transaction context)
Repo.transaction(fn ->
  User |> Batch.stream(batch_size: 100) |> Stream.map(&f/1) |> Stream.run()
end)
{:ok, users} = Batch.stream_in_transaction(User, batch_size: 100)

# Parallel
{:ok, results} = Batch.parallel(User, &heavy_fn/1, max_concurrency: 4)
```

---

## Soft Delete

```elixir
# Delete / Restore
{:ok, user} = SoftDelete.delete(user)
{:ok, user} = SoftDelete.delete(User, id)
{:ok, user} = SoftDelete.restore(user)

# Predicates
SoftDelete.deleted?(user)     #=> true
SoftDelete.deleted_at(user)   #=> ~U[2024-01-15 10:30:00Z]

# Query filtering
SoftDelete.exclude_deleted(query_or_token)  # WHERE deleted_at IS NULL
SoftDelete.only_deleted(query_or_token)     # WHERE deleted_at IS NOT NULL

# Multi integration
Multi.new()
|> SoftDelete.multi_delete(:user, user)
|> SoftDelete.multi_restore(:other, other_user)
|> OmCrud.run()
```

---

## Context Generator

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  crud User                                    # All functions
  crud Role, only: [:create, :fetch, :update]  # Selective
  crud Session, except: [:delete_all]          # Exclusion
  crud Membership, as: :member                 # Custom name prefix
  crud User, preload: [:account], changeset: :admin_changeset
end
```

### Generated Functions

| Read | Write | Bulk |
|------|-------|------|
| `fetch_user/2` | `create_user/2` | `create_all_users/2` |
| `fetch_user!/2` | `create_user!/2` | `update_all_users/3` |
| `get_user/2` | `update_user/3` | `delete_all_users/2` |
| `list_users/1` | `update_user!/3` | |
| `filter_users/2` | `delete_user/2` | |
| `count_users/1` | `delete_user!/2` | |
| `first_user/1` | | |
| `last_user/1` | | |
| `user_exists?/2` | | |
| `stream_users/1` | | |

All functions are `defoverridable`. Use `super()` to call generated impl.

### Cursor Pagination

```elixir
{:ok, result} = list_users(limit: 20)
result.data        #=> [%User{}, ...]
result.pagination  #=> %Pagination{has_more: true, end_cursor: "..."}

# Next/previous page
{:ok, page2} = list_users(after: result.pagination.end_cursor)
{:ok, prev}  = list_users(before: result.pagination.start_cursor)

# All records (no pagination)
{:ok, result} = list_users(limit: :all)
```

### Filter Syntax

```elixir
filter_users([{:status, :eq, :active}])
filter_users([{:email, :ilike, "%@corp.com"}, {:role, :in, [:admin]}])
list_users(filters: [{:status, :eq, :active}], limit: 50)
```

### Reload After Write

```elixir
create_user(attrs, reload: [:account])   # Preload specific
update_user(u, attrs, reload: true)      # Preload defaults
```

---

## Schema Integration

```elixir
defmodule MyApp.User do
  use OmCrud.Schema

  @crud_changeset :admin_changeset           # Default changeset
  @soft_delete_field :archived_at            # Custom soft delete field

  # Dynamic changeset resolution
  def changeset_for(:create, _opts), do: :registration_changeset
  def changeset_for(:update, opts), do: if(opts[:admin], do: :admin_changeset, else: :changeset)

  # Default CRUD options (consumed by all OmCrud convenience functions)
  crud_config preload: [:account], timeout: 30_000
end
```

---

## Result & Pagination

```elixir
# Result struct
%OmCrud.Result{data: [%User{}, ...], pagination: %OmCrud.Pagination{...}}

OmCrud.Result.all(users)                  # No pagination
OmCrud.Result.new(users, pagination)      # With pagination
OmCrud.Result.has_more?(result)           #=> true

# Pagination struct
%OmCrud.Pagination{type: :cursor, has_more: true, has_previous: false,
  start_cursor: "...", end_cursor: "...", limit: 20}

# Build from records
OmCrud.Pagination.from_records(records, [:inserted_at, :id], 20, fetched_extra: true)

# Serialization
OmCrud.Pagination.to_map(pagination)     #=> %{type: "cursor", has_more: true, ...}

# Cursor helpers
cursor = OmCrud.Pagination.encode_cursor(record, [:inserted_at, :id])
{:ok, values} = OmCrud.Pagination.decode_cursor(cursor)
```

---

## Error Types

```elixir
# Smart constructors
Error.not_found(User, 123)
Error.from_changeset(changeset)
Error.constraint_violation(:users_email_unique, User)
Error.validation_error(:email, "is invalid")
Error.step_failed(:create_user, {:error, reason})
Error.transaction_error(reason)
Error.stale_entry(User, 123)
Error.wrap(anything)

# Utilities
Error.message(e)               #=> "User with id 123 not found"
Error.to_map(e)                #=> %{type: :not_found, ...}
Error.to_http_status(e)        #=> 404
Error.is_type?(e, :not_found)  #=> true
Error.on_field?(e, :email)     #=> true
```

| Type | HTTP Status |
|------|-------------|
| `:not_found` | 404 |
| `:validation_error` | 422 |
| `:constraint_violation` | 409 |
| `:stale_entry` | 409 |
| Other | 500 |

---

## Changeset Resolution Order

1. `:changeset` option
2. `:create_changeset` / `:update_changeset` / `:delete_changeset`
3. Schema `@crud_changeset` attribute
4. Schema `changeset_for/2` callback
5. Default `:changeset` function

---

## Options Quick Reference

| Option | Scope | Default |
|--------|-------|---------|
| `:repo` | All | configured |
| `:prefix` | All | nil |
| `:timeout` | All | 15_000 |
| `:log` | All | :debug |
| `:preload` | Read/Write | [] |
| `:lock` | Read | nil |
| `:changeset` | Write | :changeset |
| `:returning` | Write/Bulk | false |
| `:force` | Update | [] |
| `:conflict_target` | Upsert | required |
| `:on_conflict` | Upsert | :nothing |
| `:placeholders` | Bulk | nil |
| `:stale_error_field` | Write | nil |
| `:allow_stale` | Write | false |
| `:find_by` | find/update_or_create | required |

---

## Telemetry Events

```
[:om_crud, :execute,    :start | :stop | :exception]  # Unified execution
[:om_crud, :atomic,     :start | :stop | :exception]  # Atomic blocks
[:om_crud, <operation>, :start | :stop | :exception]  # All operations below
```

Operations: `:list`, `:filter`, `:fetch`, `:get`, `:create`, `:update`, `:delete`,
`:count`, `:first`, `:last`, `:stream`, `:exists`, `:update_all`, `:delete_all`,
`:find_or_create`, `:update_or_create`,
`:batch_each`, `:batch_process`, `:batch_update`, `:batch_delete`,
`:batch_create_all`, `:batch_upsert_all`, `:batch_parallel`,
`:soft_delete`, `:soft_restore`

Measurements: `:duration`, `:duration_ms`, `:system_time`
Metadata: `:type`, `:operation`, `:schema`, `:id`, `:count`, `:source`, `:result`

---

## Configuration

```elixir
config :om_crud,
  default_repo: MyApp.Repo,
  telemetry_prefix: [:my_app, :crud, :execute]

config :om_crud, OmCrud.Batch,
  default_batch_size: 500,
  default_timeout: 30_000

config :om_crud, OmCrud.SoftDelete,
  field: :deleted_at,
  timestamp: &DateTime.utc_now/0
```

---

## When to Use What

| Scenario | Use |
|----------|-----|
| Simple CRUD | `OmCrud.create/3`, `fetch/3`, `update/3`, `delete/2` |
| Get or create | `OmCrud.find_or_create/3` with `find_by:` |
| Update or create | `OmCrud.update_or_create/3` with `find_by:` |
| Multiple related records atomically | `OmCrud.Multi` pipeline |
| Transaction with branching | `Multi.when_ok`, `Multi.branch` |
| Transaction with imperative flow | `OmCrud.Atomic` with `step!` |
| Build context across steps | `Atomic` accumulator (`accumulate` + `finalize`) |
| Sync from external system | `OmCrud.Merge` (PostgreSQL MERGE) |
| Bulk insert (< 10K, all-or-nothing) | `OmCrud.create_all/3` |
| Bulk insert (> 10K, partial OK) | `OmCrud.Batch.create_all/3` |
| Process millions of records | `OmCrud.Batch.each/3` or `.stream/2` |
| Parallel heavy processing | `OmCrud.Batch.parallel/3` |
| Context with full CRUD + pagination | `OmCrud.Context` `crud` macro |
| Soft delete | `OmCrud.SoftDelete` |

---

## Migrating from Raw Ecto

```elixir
# Repo.insert(changeset)      →  OmCrud.create(Schema, attrs)
# Repo.get(Schema, id)        →  OmCrud.get(Schema, id)       # nil | struct
# Repo.get + nil check        →  OmCrud.fetch(Schema, id)     # {:ok, _} | {:error, :not_found}
# Repo.update(changeset)      →  OmCrud.update(struct, attrs)
# Repo.delete(struct)         →  OmCrud.delete(struct)
# Ecto.Multi pipeline         →  OmCrud.Multi pipeline + OmCrud.run()
# Repo.insert_all             →  OmCrud.create_all(Schema, entries)
# Repo.get_by + Repo.insert   →  OmCrud.find_or_create(S, attrs, find_by: :field)
# Repo.get_by + Repo.update   →  OmCrud.update_or_create(S, attrs, find_by: :field)
# Manual context functions     →  use OmCrud.Context; crud Schema
```

---

## Architecture

```
OmCrud ─────────── Unified API (run/1, create/3, fetch/3, update/3, delete/2)
├── Multi ──────── Token-based transaction builder
├── Merge ──────── PostgreSQL MERGE (delegates to OmQuery.Merge)
├── Atomic ─────── step!/optional_step!/accumulate pattern
├── Batch ──────── Chunked processing, streaming, parallel
├── SoftDelete ─── Timestamp-based soft delete
├── Context ────── crud macro (generates 20+ functions per schema)
├── Options ────── Unified option handling
├── ChangesetBuilder ── Smart changeset resolution
├── Error ──────── Rich structured errors
├── Telemetry ──── Event emission
├── Pagination ─── Cursor pagination
├── Result ─────── {data, pagination} container
├── Schema ─────── Schema-level integration
├── Config ─────── Configuration management
└── Protocols ──── Executable, Validatable, Debuggable
```
