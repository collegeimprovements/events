# CRUD System Reference

The CRUD system provides a unified, composable API for all database operations. All mutations go through `Ecto.Multi` internally, enabling future audit integration.

## Table of Contents

- [Architecture](#architecture)
- [Quick Reference](#quick-reference)
- [OmCrud.Context](#omcrudcontext) - Generate CRUD functions for contexts
- [OmCrud.Result & Pagination](#omcrudresult--pagination) - Type-safe result structs
- [OmCrud.Telemetry](#omcrudtelemetry) - Observability events
- [OmCrud Core API](#omcrud-core-api) - Direct CRUD operations
- [OmCrud.Multi](#omcrudmulti) - Transaction composition
- [OmCrud.Merge](#omcrudmerge) - PostgreSQL MERGE operations
- [OmQuery Filter Operators](#omquery-filter-operators) - Available filter operations
- [Complete Options Reference](#complete-options-reference)
- [Real-World Examples](#real-world-examples)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        OmCrud                               │
│         Unified execution: run/1, create/3, fetch/3         │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  OmCrud.Multi │    │  OmCrud.Merge │    │  OmQuery.Token│
│  Transactions │    │ PostgreSQL 18 │    │   Queries     │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
     ┌────────────────────────┴────────────────────────┐
     ▼                                                 ▼
┌─────────────────────────┐            ┌─────────────────────────┐
│  OmCrud.ChangesetBuilder│            │      OmCrud.Options     │
│  Changeset building &   │            │  Option extraction,     │
│  resolution             │            │  validation, defaults   │
└─────────────────────────┘            └─────────────────────────┘
```

## Quick Reference

| Module | Purpose |
|--------|---------|
| `OmCrud` | Unified execution API |
| `OmCrud.Context` | Context-level `crud` macro with pagination, telemetry |
| `OmCrud.Result` | Type-safe paginated result container |
| `OmCrud.Pagination` | Cursor pagination metadata |
| `OmCrud.Telemetry` | Telemetry event emission |
| `OmCrud.Multi` | Transaction composer |
| `OmCrud.Merge` | PostgreSQL MERGE operations |
| `OmCrud.ChangesetBuilder` | Changeset building and resolution |
| `OmCrud.Options` | Option extraction, validation, defaults |
| `OmCrud.Schema` | Schema-level integration |

---

## OmCrud.Context

Generate comprehensive CRUD functions in context modules with cursor pagination, telemetry, and bang variants.

### Basic Usage

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  # Generate all CRUD functions with defaults
  crud User

  # Multiple schemas in one context
  crud Role
  crud Membership
  crud Session
end
```

This generates 30+ functions per schema including pagination, filtering, streaming, and bang variants.

### Generated Functions Overview

For `crud User`, the following functions are generated:

#### Read Operations (12 functions)

```elixir
# Fetch by ID - returns {:ok, user} or {:error, :not_found}
fetch_user(id)
fetch_user(id, preload: [:account, :roles])

# Fetch by ID - returns user or raises Ecto.NoResultsError
fetch_user!(id)
fetch_user!(id, preload: [:account])

# Get by ID - returns user or nil (Ecto pattern)
get_user(id)
get_user(id, preload: [:account])

# List with cursor pagination - returns {:ok, %OmCrud.Result{}}
list_users()
list_users(limit: 50, preload: [:account])

# Filter with cursor pagination - returns {:ok, %OmCrud.Result{}}
filter_users([{:status, :eq, :active}])
filter_users([{:email, :ilike, "%@corp.com"}], limit: 100)

# Count records - returns {:ok, integer}
count_users()
count_users(filters: [{:status, :eq, :active}])

# First by ordering - returns {:ok, user} or {:error, :not_found}
first_user()
first_user(filters: [{:status, :eq, :active}])
first_user!()  # raises on not found

# Last by ordering - returns {:ok, user} or {:error, :not_found}
last_user()
last_user(filters: [{:role, :eq, :admin}])
last_user!()  # raises on not found

# Check existence - returns boolean
user_exists?(id)
user_exists?([{:email, :eq, "test@example.com"}])

# Memory-efficient streaming - returns Stream.t()
stream_users()
stream_users(filters: [{:status, :eq, :active}], batch_size: 100)
```

#### Write Operations (6 functions)

```elixir
# Create - returns {:ok, user} or {:error, changeset}
create_user(%{email: "test@example.com", name: "Test"})
create_user(attrs, changeset: :registration_changeset)
create_user(attrs, reload: [:account])  # preload after create

# Create - returns user or raises Ecto.InvalidChangesetError
create_user!(attrs)

# Update - returns {:ok, user} or {:error, changeset}
update_user(user, %{name: "Updated"})
update_user(user, attrs, changeset: :admin_changeset)
update_user(user, attrs, reload: true)  # reload with default preloads

# Update - returns user or raises
update_user!(user, attrs)

# Delete - returns {:ok, user} or {:error, changeset}
delete_user(user)

# Delete - returns user or raises
delete_user!(user)
```

#### Bulk Operations (3 functions)

```elixir
# Bulk insert - returns {count, users | nil}
create_all_users([%{email: "a@test.com"}, %{email: "b@test.com"}])
create_all_users(entries, returning: [:id, :email])

# Bulk update with filters - returns {:ok, count} or {:ok, {count, users}}
update_all_users(
  [{:status, :eq, :pending}],           # filters
  [status: :active, updated_at: now]    # changes
)
update_all_users(filters, changes, returning: true)

# Bulk delete with filters - returns {:ok, count} or {:ok, {count, users}}
delete_all_users([{:status, :eq, :deleted}])
delete_all_users(filters, returning: [:id])
```

---

### Result Struct

All list and filter operations return `{:ok, %OmCrud.Result{}}`:

```elixir
{:ok, result} = list_users()

# Result structure
%OmCrud.Result{
  data: [%User{id: "1", name: "Alice"}, %User{id: "2", name: "Bob"}],
  pagination: %OmCrud.Pagination{
    type: :cursor,
    has_more: true,
    has_previous: false,
    start_cursor: "eyJpbnNlcnRlZF9hdCI6IjIwMjQtMDEtMTVUMTI6MDA6MDBaIiwiaWQiOiIxIn0",
    end_cursor: "eyJpbnNlcnRlZF9hdCI6IjIwMjQtMDEtMTVUMTI6MDA6MDBaIiwiaWQiOiIyIn0",
    limit: 20
  }
}

# Access data
users = result.data

# Check pagination
if result.pagination.has_more do
  # Fetch next page
  {:ok, next_page} = list_users(after: result.pagination.end_cursor)
end

# Helper functions
OmCrud.Result.has_more?(result)      # => true
OmCrud.Result.has_previous?(result)  # => false
OmCrud.Result.next_cursor(result)    # => "eyJpbnNl..."
OmCrud.Result.count(result)          # => 2
OmCrud.Result.empty?(result)         # => false

# Transform data
result
|> OmCrud.Result.map(&Map.get(&1, :email))
|> OmCrud.Result.filter(&String.contains?(&1, "@corp.com"))
```

---

### Pagination Examples

#### Default Pagination (Cursor, Limit 20)

```elixir
# First page - 20 records by default
{:ok, page1} = list_users()
# page1.pagination.limit = 20
# page1.pagination.has_more = true (if more than 20 users)

# Next page using cursor
{:ok, page2} = list_users(after: page1.pagination.end_cursor)

# Previous page
{:ok, prev} = list_users(before: page2.pagination.start_cursor)
```

#### Custom Limit

```elixir
# Request 50 records (clamped to max_limit if exceeded)
{:ok, result} = list_users(limit: 50)

# Request 200 records - will be clamped to max_limit (default 100)
{:ok, result} = list_users(limit: 200)
# result.pagination.limit = 100
```

#### Get All Records (No Pagination)

```elixir
# Return all records without pagination
{:ok, result} = list_users(limit: :all)
# result.pagination = nil
# result.data = [all users]

# With filters
{:ok, result} = filter_users([{:status, :eq, :active}], limit: :all)
```

#### Pagination with Filters

```elixir
# Paginate filtered results
{:ok, result} = filter_users(
  [{:status, :eq, :active}, {:role, :eq, :admin}],
  limit: 25,
  after: cursor
)
```

---

### Filter Examples

#### Basic Filtering

```elixir
# Equality
filter_users([{:status, :eq, :active}])
filter_users([{:role, :neq, :guest}])

# Comparison
filter_users([{:age, :gt, 18}])
filter_users([{:age, :gte, 21}])
filter_users([{:balance, :lt, 1000}])
filter_users([{:created_at, :lte, DateTime.utc_now()}])

# Range
filter_users([{:age, :between, {18, 65}}])

# Inclusion
filter_users([{:status, :in, [:active, :pending]}])
filter_users([{:role, :not_in, [:banned, :suspended]}])

# Null checks
filter_users([{:deleted_at, :is_nil, true}])
filter_users([{:confirmed_at, :not_nil, true}])
```

#### String Filtering

```elixir
# LIKE patterns (case-sensitive)
filter_users([{:name, :like, "John%"}])
filter_users([{:email, :not_like, "%@spam.com"}])

# ILIKE patterns (case-insensitive)
filter_users([{:email, :ilike, "%@gmail.com"}])
filter_users([{:name, :not_ilike, "%test%"}])

# Similarity search (requires pg_trgm extension)
filter_users([{:name, :similarity, "Jon"}])           # Similar to "Jon"
filter_users([{:name, :word_similarity, "database"}]) # Word-level similarity
```

#### JSONB Filtering

```elixir
# Check if JSONB contains value
filter_users([{:metadata, :jsonb_contains, %{vip: true}}])

# Check if key exists
filter_users([{:settings, :jsonb_has_key, "notifications"}])

# Get value at path and compare
filter_users([{:metadata, :jsonb_get, {["preferences", "theme"], "dark"}}])

# Check if path exists
filter_users([{:profile, :jsonb_path_exists, ["contact", "phone"]}])

# JSONPath expression match (PostgreSQL 12+)
filter_users([{:metadata, :jsonb_path_match, "$.roles[*] == \"admin\""}])

# Any of these keys exist
filter_users([{:permissions, :jsonb_any_key, ["read", "write", "admin"]}])

# All of these keys exist
filter_users([{:settings, :jsonb_all_keys, ["email", "phone", "address"]}])

# JSONB array contains element
filter_users([{:tags, :jsonb_array_elem, "featured"}])
```

#### Array Filtering

```elixir
# Array contains all elements
filter_users([{:roles, :contains, ["admin", "moderator"]}])
```

#### Combining Filters

```elixir
# Multiple filters (AND)
filter_users([
  {:status, :eq, :active},
  {:role, :in, [:admin, :moderator]},
  {:email, :ilike, "%@company.com"},
  {:created_at, :gte, ~U[2024-01-01 00:00:00Z]}
])

# With pagination and preloads
filter_users(
  [
    {:status, :eq, :active},
    {:metadata, :jsonb_get, {["tier"], "premium"}}
  ],
  limit: 50,
  preload: [:account, :subscriptions],
  order_by: [desc: :created_at]
)
```

#### Filter with 4-tuple (Advanced Options)

```elixir
# 4-tuple format: {field, operator, value, options}
filter_users([{:email, :eq, email, binding: :user}])

# Useful for joins
list_orders(
  filters: [{:status, :eq, :shipped, binding: :order}],
  join: [{:user, :inner, binding: :user}]
)
```

---

### Query Options

#### Select Specific Fields

```elixir
# Only load specific fields (lighter queries)
list_users(select: [:id, :email, :name])

# Useful for large tables
stream_users(select: [:id], batch_size: 1000)
|> Enum.each(&process_id/1)
```

#### Distinct Results

```elixir
# Distinct on all selected fields
list_users(distinct: true)

# Distinct on specific field (PostgreSQL)
list_users(distinct: :email)
list_users(distinct: [:org_id, :role])
```

#### Row Locking

```elixir
# FOR UPDATE - exclusive lock for update
list_users(
  filters: [{:status, :eq, :pending}],
  lock: :for_update,
  limit: 10
)

# FOR SHARE - shared lock for reading
list_users(
  filters: [{:id, :in, user_ids}],
  lock: :for_share
)

# Custom lock string
list_users(lock: "FOR UPDATE NOWAIT")
list_users(lock: "FOR UPDATE SKIP LOCKED")
```

#### Custom Ordering

```elixir
# Custom order (default: [desc: :inserted_at, asc: :id])
list_users(order_by: [asc: :name])
list_users(order_by: [desc: :created_at, asc: :id])

# Nulls handling
list_users(order_by: [asc_nulls_first: :deleted_at])
list_users(order_by: [desc_nulls_last: :priority])

# IMPORTANT: For cursor pagination, cursor_fields must match order_by
list_users(
  order_by: [asc: :email],
  cursor_fields: [:email]  # Must match!
)
```

#### Preloading Associations

```elixir
# Single association
list_users(preload: [:account])

# Multiple associations
list_users(preload: [:account, :roles, :memberships])

# Nested preloads
list_users(preload: [account: [:owner, :settings]])

# Preload with custom query
list_users(preload: [posts: from(p in Post, where: p.published == true)])
```

---

### Stream Operations

Memory-efficient iteration for large datasets:

```elixir
# Basic streaming (default batch_size: 500)
stream_users()
|> Stream.filter(&(&1.status == :active))
|> Enum.each(&send_newsletter/1)

# With custom batch size
stream_users(batch_size: 100)
|> Stream.map(&transform/1)
|> Enum.to_list()

# With filters
stream_users(filters: [{:role, :eq, :subscriber}])
|> Stream.chunk_every(50)
|> Enum.each(&process_batch/1)

# Export all active users
stream_users(filters: [{:status, :eq, :active}])
|> Stream.map(&to_csv_row/1)
|> CSV.encode()
|> Enum.into(File.stream!("users.csv"))

# Count with streaming (memory efficient for huge tables)
stream_users(filters: [{:status, :eq, :active}])
|> Enum.count()
```

---

### Bulk Operations

#### Bulk Create

```elixir
# Simple bulk insert
create_all_users([
  %{email: "a@test.com", name: "Alice"},
  %{email: "b@test.com", name: "Bob"},
  %{email: "c@test.com", name: "Carol"}
])
# => {3, nil}

# With returning
{count, users} = create_all_users(entries, returning: true)
# => {3, [%User{}, %User{}, %User{}]}

# Return specific fields only
{count, users} = create_all_users(entries, returning: [:id, :email])

# With conflict handling (upsert)
create_all_users(entries,
  conflict_target: :email,
  on_conflict: {:replace, [:name, :updated_at]}
)

# With placeholders (optimize repeated values)
now = DateTime.utc_now()
placeholders = %{now: now, org_id: org_id}

entries = [
  %{email: "a@test.com", org_id: {:placeholder, :org_id}, inserted_at: {:placeholder, :now}},
  %{email: "b@test.com", org_id: {:placeholder, :org_id}, inserted_at: {:placeholder, :now}}
]

create_all_users(entries, placeholders: placeholders)
```

#### Bulk Update

```elixir
# Update all matching records
{:ok, count} = update_all_users(
  [{:status, :eq, :pending}],
  [status: :active, activated_at: DateTime.utc_now()]
)
# => {:ok, 42}

# With returning
{:ok, {count, users}} = update_all_users(
  [{:role, :eq, :trial}],
  [role: :member, upgraded_at: DateTime.utc_now()],
  returning: true
)
# => {:ok, {15, [%User{}, ...]}}

# Complex filter + update
{:ok, count} = update_all_users(
  [
    {:status, :eq, :active},
    {:last_login_at, :lt, thirty_days_ago},
    {:role, :neq, :admin}
  ],
  [status: :inactive, inactivated_at: DateTime.utc_now()]
)
```

#### Bulk Delete

```elixir
# Delete all matching records
{:ok, count} = delete_all_users([{:status, :eq, :deleted}])
# => {:ok, 100}

# With returning (get deleted records)
{:ok, {count, users}} = delete_all_users(
  [{:deleted_at, :lt, one_year_ago}],
  returning: true
)

# Archive old sessions
{:ok, count} = delete_all_sessions([
  {:expires_at, :lt, DateTime.utc_now()},
  {:remember_me, :eq, false}
])
```

---

### exists? with Filters

```elixir
# Check by ID
user_exists?("550e8400-e29b-41d4-a716-446655440000")
# => true

# Check by filters
user_exists?([{:email, :eq, "admin@example.com"}])
# => true

# Complex existence check
user_exists?([
  {:email, :eq, email},
  {:status, :eq, :active},
  {:org_id, :eq, org_id}
])
# => false
```

---

### Configuration Options

#### All Options Reference

```elixir
crud User,
  # Function Selection
  as: :member,                          # Override resource name (default: derived from schema)
  only: [:fetch, :list, :create],       # Generate only these functions
  except: [:delete_all],                # Exclude these functions
  bang: true,                           # Generate bang variants (default: true)
  filterable: true,                     # Generate filter_* function (default: true)

  # Pagination
  pagination: :cursor,                  # :cursor | :offset | false (default: :cursor)
  default_limit: 20,                    # Default page size (default: 20)
  max_limit: 100,                       # Maximum allowed limit (default: 100)

  # Query Defaults
  order_by: [desc: :inserted_at, asc: :id],  # Default ordering
  cursor_fields: [:inserted_at, :id],   # Fields for cursor (must match order_by)
  preload: [],                          # Default associations to preload
  batch_size: 500,                      # Default stream batch size

  # Write Defaults
  changeset: :changeset,                # Default changeset function

  # Execution Defaults
  repo: MyApp.Repo,                     # Custom repo module
  timeout: 15_000,                      # Query timeout in ms
  prefix: nil,                          # Schema prefix (multi-tenant)
  log: nil                              # Logging level or false
```

#### Common Configurations

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  # Standard user entity
  crud User

  # Read-only audit logs (no write operations)
  crud AuditLog,
    only: [:fetch, :list, :filter, :count, :stream],
    default_limit: 100,
    max_limit: 1000,
    order_by: [desc: :occurred_at]

  # High-volume events with larger pages
  crud Event,
    default_limit: 100,
    max_limit: 1000,
    timeout: 30_000,
    batch_size: 1000,
    order_by: [desc: :timestamp, asc: :id],
    cursor_fields: [:timestamp, :id]

  # Entity with common preloads
  crud Order,
    preload: [:items, :customer, :shipping_address],
    order_by: [desc: :created_at]

  # Multi-tenant entity
  crud TenantUser,
    prefix: "tenant_",
    preload: [:roles]

  # Minimal - no pagination, no filtering
  crud Setting,
    only: [:fetch, :get, :create, :update],
    pagination: false,
    filterable: false

  # Custom resource name
  crud UserRoleMapping, as: :role_assignment
end
```

---

### Overriding Generated Functions

All generated functions are marked as `defoverridable`. You can customize behavior:

#### Complete Override

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  crud User

  # Completely replace create_user
  def create_user(attrs, opts \\ []) do
    attrs
    |> Map.put(:status, :pending)
    |> Map.put(:created_by, opts[:current_user_id])
    |> then(&OmCrud.create(User, &1, opts))
  end
end
```

#### Wrap with super()

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  crud User

  # Add logging around fetch
  def fetch_user(id, opts \\ []) do
    Logger.info("Fetching user: #{id}")
    result = super(id, opts)

    case result do
      {:ok, user} ->
        Logger.info("Found user: #{user.email}")
        {:ok, user}

      {:error, :not_found} ->
        Logger.warn("User not found: #{id}")
        {:error, :not_found}
    end
  end

  # Add authorization
  def update_user(user, attrs, opts \\ []) do
    current_user = opts[:current_user]

    if authorized?(current_user, :update, user) do
      super(user, attrs, opts)
    else
      {:error, :unauthorized}
    end
  end
end
```

#### Add Custom Functions

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  crud User

  # Custom domain function using generated helpers
  def activate_user(user) do
    update_user(user, %{
      status: :active,
      activated_at: DateTime.utc_now()
    })
  end

  def deactivate_users_inactive_for(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    update_all_users(
      [
        {:status, :eq, :active},
        {:last_login_at, :lt, cutoff}
      ],
      [status: :inactive, deactivated_at: DateTime.utc_now()]
    )
  end

  def purge_deleted_users(before_date) do
    delete_all_users([
      {:status, :eq, :deleted},
      {:deleted_at, :lt, before_date}
    ])
  end
end
```

---

## OmCrud.Result & Pagination

### OmCrud.Result

Type-safe container for paginated query results.

```elixir
defstruct [:data, :pagination]

@type t :: %__MODULE__{
  data: [struct()],
  pagination: OmCrud.Pagination.t() | nil
}
```

#### Creating Results

```elixir
# With pagination
result = OmCrud.Result.new(users, pagination)

# Without pagination (all records)
result = OmCrud.Result.all(users)
```

#### Helper Functions

```elixir
# Navigation
OmCrud.Result.has_more?(result)        # => boolean
OmCrud.Result.has_previous?(result)    # => boolean
OmCrud.Result.next_cursor(result)      # => String.t() | nil
OmCrud.Result.previous_cursor(result)  # => String.t() | nil

# Stats
OmCrud.Result.count(result)            # => non_neg_integer
OmCrud.Result.empty?(result)           # => boolean

# Transform
OmCrud.Result.map(result, &transform/1)
OmCrud.Result.filter(result, &predicate/1)

# Serialization
OmCrud.Result.to_map(result)           # For JSON APIs
```

### OmCrud.Pagination

Cursor pagination metadata.

```elixir
defstruct [:type, :has_more, :has_previous, :start_cursor, :end_cursor, :limit]

@type t :: %__MODULE__{
  type: :cursor | :offset,
  has_more: boolean(),
  has_previous: boolean(),
  start_cursor: String.t() | nil,
  end_cursor: String.t() | nil,
  limit: pos_integer()
}
```

#### Cursor Format

Cursors are Base64-encoded JSON containing the cursor field values:

```elixir
# Decoded cursor
%{
  "inserted_at" => "2024-01-15T12:00:00Z",
  "id" => "550e8400-e29b-41d4-a716-446655440000"
}

# Encode manually
OmCrud.Pagination.encode_cursor(user, [:inserted_at, :id])
# => "eyJpbnNlcnRlZF9hdCI6..."

# Decode
OmCrud.Pagination.decode_cursor(cursor)
# => {:ok, %{"inserted_at" => ..., "id" => ...}}
```

---

## OmCrud.Telemetry

All CRUD operations emit telemetry events for observability.

### Event Pattern

```
[:om_crud, <operation>, :start | :stop | :exception]
```

### Available Events

| Operation | Event Names |
|-----------|------------|
| list | `[:om_crud, :list, :start/:stop/:exception]` |
| filter | `[:om_crud, :filter, :start/:stop/:exception]` |
| fetch | `[:om_crud, :fetch, :start/:stop/:exception]` |
| get | `[:om_crud, :get, :start/:stop/:exception]` |
| create | `[:om_crud, :create, :start/:stop/:exception]` |
| update | `[:om_crud, :update, :start/:stop/:exception]` |
| delete | `[:om_crud, :delete, :start/:stop/:exception]` |
| count | `[:om_crud, :count, :start/:stop/:exception]` |
| first | `[:om_crud, :first, :start/:stop/:exception]` |
| last | `[:om_crud, :last, :start/:stop/:exception]` |
| stream | `[:om_crud, :stream, :start/:stop/:exception]` |
| exists | `[:om_crud, :exists, :start/:stop/:exception]` |
| update_all | `[:om_crud, :update_all, :start/:stop/:exception]` |
| delete_all | `[:om_crud, :delete_all, :start/:stop/:exception]` |

### Event Data

#### Start Events

```elixir
# Measurements
%{system_time: integer()}

# Metadata
%{
  schema: User,
  operation: :list,
  filters: [{:status, :eq, :active}],
  limit: 20
  # ... operation-specific fields
}
```

#### Stop Events

```elixir
# Measurements
%{
  duration: integer(),      # Native time units
  duration_ms: integer()    # Milliseconds
}

# Metadata
%{
  schema: User,
  operation: :list,
  result: :ok | :error,
  # ... same as start
}
```

#### Exception Events

```elixir
# Measurements
%{duration: integer(), duration_ms: integer()}

# Metadata
%{
  schema: User,
  operation: :create,
  kind: :error | :exit | :throw,
  reason: term(),
  stacktrace: list()
}
```

### Attaching Handlers

```elixir
defmodule MyApp.Telemetry do
  require Logger

  def setup do
    events = [
      [:om_crud, :list, :stop],
      [:om_crud, :create, :stop],
      [:om_crud, :update, :stop],
      [:om_crud, :delete, :stop],
      [:om_crud, :create, :exception],
      [:om_crud, :update, :exception]
    ]

    :telemetry.attach_many(
      "myapp-crud-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:om_crud, operation, :stop], measurements, metadata, _config) do
    Logger.info(
      "[OmCrud] #{operation} on #{inspect(metadata.schema)} " <>
      "completed in #{measurements.duration_ms}ms"
    )
  end

  def handle_event([:om_crud, operation, :exception], _measurements, metadata, _config) do
    Logger.error(
      "[OmCrud] Exception in #{operation}: #{inspect(metadata.reason)}"
    )
  end
end
```

### Metrics with :telemetry_metrics

```elixir
defmodule MyApp.Telemetry.Metrics do
  import Telemetry.Metrics

  def metrics do
    [
      # Distribution of query times
      distribution("om_crud.list.duration",
        unit: {:native, :millisecond},
        tags: [:schema],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),

      # Count operations
      counter("om_crud.create.stop.count",
        tags: [:schema, :result]
      ),

      # Last value (for debugging)
      last_value("om_crud.list.duration",
        unit: {:native, :millisecond},
        tags: [:schema]
      )
    ]
  end
end
```

### Manual Telemetry

```elixir
# Use span/3 for automatic start/stop/exception
OmCrud.Telemetry.span(:custom_operation, %{schema: User}, fn ->
  # Your code here
  {:ok, result}
end)

# Or manual control for streaming
start_time = OmCrud.Telemetry.start(:stream, %{schema: User})
# ... streaming ...
OmCrud.Telemetry.stop(:stream, start_time, %{schema: User, count: 1000})
```

---

## OmQuery Filter Operators

Complete list of available filter operators:

### Comparison Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:eq` | `=` | `{:status, :eq, :active}` |
| `:neq` | `<>` | `{:status, :neq, :deleted}` |
| `:gt` | `>` | `{:age, :gt, 18}` |
| `:gte` | `>=` | `{:age, :gte, 21}` |
| `:lt` | `<` | `{:balance, :lt, 0}` |
| `:lte` | `<=` | `{:attempts, :lte, 3}` |
| `:between` | `BETWEEN` | `{:age, :between, {18, 65}}` |

### Inclusion Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:in` | `IN` | `{:status, :in, [:active, :pending]}` |
| `:not_in` | `NOT IN` | `{:role, :not_in, [:banned]}` |
| `:in_subquery` | `IN (SELECT...)` | `{:org_id, :in_subquery, subquery}` |
| `:not_in_subquery` | `NOT IN (SELECT...)` | `{:id, :not_in_subquery, subquery}` |

### String Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:like` | `LIKE` | `{:name, :like, "John%"}` |
| `:ilike` | `ILIKE` | `{:email, :ilike, "%@gmail.com"}` |
| `:not_like` | `NOT LIKE` | `{:email, :not_like, "%spam%"}` |
| `:not_ilike` | `NOT ILIKE` | `{:name, :not_ilike, "%test%"}` |

### Null Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:is_nil` | `IS NULL` | `{:deleted_at, :is_nil, true}` |
| `:not_nil` | `IS NOT NULL` | `{:confirmed_at, :not_nil, true}` |

### Array Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:contains` | `@>` | `{:tags, :contains, ["elixir"]}` |

### JSONB Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:jsonb_contains` | `@>` | `{:meta, :jsonb_contains, %{vip: true}}` |
| `:jsonb_has_key` | `?` | `{:settings, :jsonb_has_key, "theme"}` |
| `:jsonb_get` | `#>> =` | `{:meta, :jsonb_get, {["user", "role"], "admin"}}` |
| `:jsonb_path_exists` | `@?` | `{:data, :jsonb_path_exists, ["user", "email"]}` |
| `:jsonb_path_match` | `@@` | `{:data, :jsonb_path_match, "$.active == true"}` |
| `:jsonb_any_key` | `?|` | `{:perms, :jsonb_any_key, ["read", "write"]}` |
| `:jsonb_all_keys` | `?&` | `{:config, :jsonb_all_keys, ["host", "port"]}` |
| `:jsonb_array_elem` | `@>` | `{:tags, :jsonb_array_elem, "featured"}` |

### Text Search Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:similarity` | `%` | `{:name, :similarity, "Jon"}` |
| `:word_similarity` | `<%` | `{:title, :word_similarity, "database"}` |
| `:strict_word_similarity` | `<<%` | `{:content, :strict_word_similarity, "query"}` |

### Field Comparison

| Operator | SQL | Example |
|----------|-----|---------|
| `:field_compare` | Dynamic | `{:field_compare, {:end_date, :gt, :start_date, []}}` |

---

## OmCrud Core API

Direct CRUD operations without context macros.

### Single Record Operations

```elixir
# Create
{:ok, user} = OmCrud.create(User, %{email: "test@example.com"})
{:ok, user} = OmCrud.create(User, attrs, changeset: :registration_changeset)

# Update
{:ok, user} = OmCrud.update(user, %{name: "Updated"})
{:ok, user} = OmCrud.update(User, user_id, %{name: "Updated"})

# Delete
{:ok, user} = OmCrud.delete(user)
{:ok, user} = OmCrud.delete(User, user_id)

# Fetch (returns {:ok, record} or {:error, :not_found})
{:ok, user} = OmCrud.fetch(User, id)
{:ok, user} = OmCrud.fetch(User, id, preload: [:account])

# Get (returns record or nil)
user = OmCrud.get(User, id)

# Exists
true = OmCrud.exists?(User, id)
```

### Bulk Operations

```elixir
# Create all
{count, users} = OmCrud.create_all(User, entries, returning: true)

# Upsert all
{count, users} = OmCrud.upsert_all(User, entries,
  conflict_target: :email,
  on_conflict: {:replace, [:name]}
)

# Update all
{:ok, count} = query |> OmCrud.update_all(set: [status: :active])

# Delete all
{:ok, count} = query |> OmCrud.delete_all()
```

### Unified Execution

```elixir
# Execute any token (Multi, Merge, Query)
OmCrud.run(multi_or_merge_or_query)
OmCrud.run(token, timeout: 30_000)

# Transaction
{:ok, results} = OmCrud.transaction(multi)
```

---

## OmCrud.Multi

Token-based transaction builder.

### Basic Usage

```elixir
alias OmCrud.Multi

Multi.new()
|> Multi.create(:user, User, %{email: "test@example.com"})
|> Multi.create(:account, Account, fn %{user: user} ->
  %{owner_id: user.id, name: "#{user.name}'s Account"}
end)
|> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
  %{user_id: u.id, account_id: a.id, role: :owner}
end)
|> OmCrud.run()
# => {:ok, %{user: %User{}, account: %Account{}, membership: %Membership{}}}
```

### Operations

```elixir
# Create
Multi.create(multi, :name, Schema, attrs)
Multi.create(multi, :name, Schema, attrs, changeset: :custom)

# Update
Multi.update(multi, :name, record, attrs)
Multi.update(multi, :name, {Schema, id}, attrs)
Multi.update(multi, :name, fn results -> record end, attrs)

# Delete
Multi.delete(multi, :name, record)
Multi.delete(multi, :name, {Schema, id})

# Upsert
Multi.upsert(multi, :name, Schema, attrs,
  conflict_target: :email,
  on_conflict: {:replace, [:name]}
)

# Bulk
Multi.create_all(multi, :name, Schema, entries)
Multi.update_all(multi, :name, query, set: [...])
Multi.delete_all(multi, :name, query)

# Custom operation
Multi.run(multi, :name, fn results ->
  # Return {:ok, result} or {:error, reason}
end)

# Conditional
Multi.when_ok(multi, :name, fn results ->
  if condition do
    Multi.new() |> Multi.create(...)
  else
    Multi.new()
  end
end)
```

### Composition

```elixir
# Append
combined = Multi.append(multi1, multi2)

# Prepend
combined = Multi.prepend(multi2, multi1)

# Embed with prefix
Multi.embed(multi, other_multi, prefix: :setup)
```

---

## OmCrud.Merge

PostgreSQL MERGE operations (PostgreSQL 15+).

### Basic Usage

```elixir
alias OmCrud.Merge

User
|> Merge.new(%{email: "test@example.com", name: "Test"})
|> Merge.match_on(:email)
|> Merge.when_matched(:update, [:name, :updated_at])
|> Merge.when_not_matched(:insert)
|> OmCrud.run()
```

### Bulk Sync

```elixir
User
|> Merge.new(external_users)
|> Merge.match_on([:org_id, :external_id])
|> Merge.when_matched(:update, [:name, :email, :synced_at])
|> Merge.when_not_matched(:insert, %{status: :pending})
|> Merge.returning(true)
|> OmCrud.run()
```

### Conditional Actions

```elixir
User
|> Merge.new(incoming_data)
|> Merge.match_on(:id)
|> Merge.when_matched(&source_newer?/1, :update)  # Conditional
|> Merge.when_matched(:nothing)                    # Fallback
|> Merge.when_not_matched(:insert)
|> OmCrud.run()
```

---

## Complete Options Reference

### Universal Options (All Operations)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:repo` | `module()` | configured | Custom repo module |
| `:prefix` | `String.t()` | `nil` | Schema prefix (multi-tenant) |
| `:timeout` | `integer()` | `15_000` | Query timeout in ms |
| `:log` | `atom() \| false` | repo default | Logger level |

### Read Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:preload` | `list()` | `[]` | Associations to preload |
| `:select` | `list()` | all | Fields to select |
| `:distinct` | `boolean() \| atom()` | `false` | Enable distinct |
| `:lock` | `atom() \| String.t()` | `nil` | Row locking mode |

### Write Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:changeset` | `atom()` | `:changeset` | Changeset function |
| `:returning` | `boolean() \| list()` | `false` | Fields to return |
| `:reload` | `boolean() \| list()` | `false` | Preloads after write |
| `:force` | `list()` | `[]` | Fields to mark changed |

### Bulk Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:placeholders` | `map()` | `nil` | Reusable values |
| `:conflict_target` | `atom() \| list()` | required | Conflict column(s) |
| `:on_conflict` | various | `:nothing` | Conflict action |

---

## Real-World Examples

### User Registration with Account

```elixir
def register_user(attrs) do
  Multi.new()
  |> Multi.create(:user, User, attrs, changeset: :registration_changeset)
  |> Multi.create(:account, Account, fn %{user: u} ->
    %{name: "#{u.name}'s Account", owner_id: u.id}
  end)
  |> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
    %{user_id: u.id, account_id: a.id, role: :owner}
  end)
  |> Multi.run(:welcome_email, fn %{user: user} ->
    case Mailer.send_welcome(user) do
      :ok -> {:ok, :sent}
      error -> error
    end
  end)
  |> OmCrud.run()
end
```

### Paginated API Endpoint

```elixir
def index(conn, params) do
  filters = build_filters(params)
  cursor = params["cursor"]
  limit = min(params["limit"] || 20, 100)

  {:ok, result} = Accounts.filter_users(filters,
    limit: limit,
    after: cursor,
    preload: [:account]
  )

  json(conn, %{
    users: Enum.map(result.data, &UserView.render/1),
    pagination: %{
      has_more: result.pagination.has_more,
      next_cursor: result.pagination.end_cursor
    }
  })
end

defp build_filters(params) do
  []
  |> maybe_add_filter(params["status"], fn status ->
    {:status, :eq, String.to_existing_atom(status)}
  end)
  |> maybe_add_filter(params["search"], fn search ->
    {:email, :ilike, "%#{search}%"}
  end)
  |> maybe_add_filter(params["role"], fn role ->
    {:role, :eq, String.to_existing_atom(role)}
  end)
end
```

### Bulk Import with Progress

```elixir
def import_users(csv_stream, progress_callback) do
  now = DateTime.utc_now()
  placeholders = %{now: now, status: :pending}

  csv_stream
  |> Stream.map(&parse_row/1)
  |> Stream.chunk_every(1000)
  |> Stream.with_index()
  |> Enum.reduce({0, []}, fn {batch, index}, {total, errors} ->
    entries = Enum.map(batch, fn row ->
      %{
        email: row.email,
        name: row.name,
        status: {:placeholder, :status},
        inserted_at: {:placeholder, :now},
        updated_at: {:placeholder, :now}
      }
    end)

    case create_all_users(entries, placeholders: placeholders) do
      {count, _} ->
        progress_callback.(index, count)
        {total + count, errors}

      {:error, reason} ->
        {total, [{index, reason} | errors]}
    end
  end)
end
```

### Soft Delete with Cascade

```elixir
def soft_delete_account(account) do
  now = DateTime.utc_now()

  Multi.new()
  |> Multi.update(:account, account, %{deleted_at: now, status: :deleted})
  |> Multi.run(:memberships, fn %{account: a} ->
    update_all_memberships(
      [{:account_id, :eq, a.id}],
      [deleted_at: now, status: :removed]
    )
  end)
  |> Multi.run(:invites, fn %{account: a} ->
    update_all_invites(
      [{:account_id, :eq, a.id}],
      [deleted_at: now, status: :revoked]
    )
  end)
  |> OmCrud.run()
end
```

### Stream Processing

```elixir
def send_newsletter_to_all_subscribers do
  stream_users(
    filters: [
      {:subscribed, :eq, true},
      {:email_verified, :eq, true}
    ],
    batch_size: 100
  )
  |> Task.async_stream(
    fn user -> Mailer.send_newsletter(user) end,
    max_concurrency: 10,
    timeout: 30_000
  )
  |> Enum.reduce({0, 0}, fn
    {:ok, :ok}, {sent, failed} -> {sent + 1, failed}
    {:ok, {:error, _}}, {sent, failed} -> {sent, failed + 1}
    {:exit, _}, {sent, failed} -> {sent, failed + 1}
  end)
end
```

### Conditional Updates

```elixir
def process_order(order) do
  Multi.new()
  |> Multi.update(:order, order, %{status: :processing})
  |> Multi.when_ok(:rewards, fn %{order: o} ->
    if o.total >= 100 do
      Multi.new()
      |> Multi.create(:reward, Reward, %{
        order_id: o.id,
        points: div(o.total, 10)
      })
    else
      Multi.new()
    end
  end)
  |> Multi.run(:notify, fn %{order: o} ->
    Notifications.order_processing(o)
    {:ok, :notified}
  end)
  |> OmCrud.run()
end
```

### Using Locking for Inventory

```elixir
def reserve_inventory(product_id, quantity) do
  Repo.transaction(fn ->
    # Lock the row to prevent concurrent updates
    {:ok, result} = filter_products(
      [{:id, :eq, product_id}],
      lock: "FOR UPDATE NOWAIT",
      limit: 1
    )

    case result.data do
      [] ->
        Repo.rollback(:product_not_found)

      [product] when product.stock < quantity ->
        Repo.rollback(:insufficient_stock)

      [product] ->
        {:ok, updated} = update_product(product, %{
          stock: product.stock - quantity,
          reserved: product.reserved + quantity
        })
        updated
    end
  end)
end
```
