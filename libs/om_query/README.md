# OmQuery

Composable query builder for Ecto with cursor pagination, full-text search, faceted filtering, and dynamic query construction.

## Installation

```elixir
def deps do
  [{:om_query, "~> 0.1.0"}]
end
```

---

## Why OmQuery?

Without OmQuery, building dynamic queries is verbose and error-prone:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RAW ECTO APPROACH                                   │
│                                                                             │
│  # Scattered, procedural query building                                     │
│  query = from(u in User)                                                    │
│  query = if status, do: from(q in query, where: q.status == ^status), else: query │
│  query = if age, do: from(q in query, where: q.age >= ^age), else: query   │
│  query = from(q in query, order_by: [desc: q.inserted_at])                 │
│  query = from(q in query, limit: ^limit, offset: ^offset)                  │
│  Repo.all(query)                                                            │
│                                                                             │
│  # No cursor pagination                                                     │
│  # No full-text search                                                      │
│  # No faceted search                                                        │
│  # No debug tools                                                           │
│  # Manual pagination metadata                                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WITH OmQuery                                      │
│                                                                             │
│  User                                                                       │
│  |> OmQuery.maybe(:status, params["status"])                               │
│  |> OmQuery.maybe(:age, :gte, params["min_age"])                           │
│  |> OmQuery.order(:inserted_at, :desc)                                     │
│  |> OmQuery.paginate(:cursor, limit: 20, after: cursor)                    │
│  |> OmQuery.execute()                                                       │
│  #=> {:ok, %Result{data: [...], pagination: %{has_more: true, ...}}}       │
│                                                                             │
│  # Full-text search                                                         │
│  |> OmQuery.search("john", [:name, :email, :bio])                          │
│                                                                             │
│  # Faceted search for e-commerce                                            │
│  FacetedSearch.new(Product)                                                 │
│  |> FacetedSearch.facet(:categories, :category_id)                         │
│                                                                             │
│  # Debug anywhere in pipeline                                               │
│  |> OmQuery.debug(:raw_sql)                                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Benefits:**

| Feature | Raw Ecto | OmQuery |
|---------|----------|---------|
| Query Building | Procedural, scattered | Composable pipeline |
| Conditional Filters | Manual `if/else` | `maybe/3`, `maybe/4` |
| Pagination | Offset only, manual | Cursor & offset, automatic metadata |
| Full-Text Search | Manual SQL | `search/4` with ranking |
| Faceted Search | Build yourself | `FacetedSearch` module |
| Debug Tools | None | `debug/3` with multiple formats |
| Result Format | Raw list | Structured `%Result{}` |
| Dynamic Params | Manual parsing | `from_params/2` |
| Type Casting | Manual | Automatic with Cast |

---

## Quick Start

```elixir
alias OmQuery

# Build and execute a query
User
|> OmQuery.filter(:status, :eq, "active")
|> OmQuery.filter(:age, :gte, 18)
|> OmQuery.order(:name, :asc)
|> OmQuery.paginate(:cursor, limit: 20)
|> OmQuery.execute(repo: MyApp.Repo)

#=> {:ok, %OmQuery.Result{
#     data: [%User{}, ...],
#     pagination: %{
#       type: :cursor,
#       limit: 20,
#       has_more: true,
#       end_cursor: "eyJpZCI6MTIzfQ"
#     },
#     metadata: %{query_time_μs: 1234}
#   }}
```

---

## Configuration

```elixir
# In config/config.exs
config :om_query,
  default_repo: MyApp.Repo

# Token limits
config :om_query, OmQuery.Token,
  default_limit: 20,
  max_limit: 1000
```

---

## Filtering

### Basic Filters

```elixir
# Equality
OmQuery.filter(token, :status, :eq, "active")

# Comparison
OmQuery.filter(token, :age, :gte, 18)
OmQuery.filter(token, :price, :lt, 100)

# In/Not In
OmQuery.filter(token, :role, :in, ["admin", "moderator"])
OmQuery.filter(token, :status, :not_in, ["deleted", "banned"])

# Pattern matching
OmQuery.filter(token, :name, :like, "john%")
OmQuery.filter(token, :email, :ilike, "%@gmail.com")

# Null checks
OmQuery.filter(token, :deleted_at, :is_nil)
OmQuery.filter(token, :verified_at, :is_not_nil)

# Range
OmQuery.filter(token, :score, :between, {50, 100})

# Array/JSONB (PostgreSQL)
OmQuery.filter(token, :tags, :contains, ["elixir", "phoenix"])
OmQuery.filter(token, :metadata, :jsonb_has_key, "premium")
```

### Shorthand Syntax

```elixir
# Equality shorthand (omit :eq)
OmQuery.filter(token, :status, "active")

# Keyword list for multiple equality filters
OmQuery.filter(token, status: "active", verified: true, role: "admin")

# Direct from schema (auto-wraps in token)
User
|> OmQuery.filter(:status, "active")
|> OmQuery.filter(:age, :gte, 18)
```

### Conditional Filters (maybe)

Build queries from optional parameters without `if/else`:

```elixir
# These only apply if the value is truthy
User
|> OmQuery.maybe(:status, params["status"])
|> OmQuery.maybe(:role, params["role"])
|> OmQuery.maybe(:age, :gte, params["min_age"])
|> OmQuery.maybe(:age, :lte, params["max_age"])
|> OmQuery.execute()

# Equivalent to this verbose code:
token = OmQuery.new(User)
token = if params["status"], do: OmQuery.filter(token, :status, params["status"]), else: token
token = if params["role"], do: OmQuery.filter(token, :role, params["role"]), else: token
# ... and so on
```

### Filter Groups (OR/AND)

```elixir
# OR: Match any condition
OmQuery.where_any(token, [
  {:status, :eq, "active"},
  {:role, :eq, "admin"},
  {:verified, :eq, true}
])
# WHERE status = 'active' OR role = 'admin' OR verified = true

# AND: Match all conditions
OmQuery.where_all(token, [
  {:status, :eq, "active"},
  {:age, :gte, 18}
])
# WHERE status = 'active' AND age >= 18
```

### Filtering on Joined Tables

```elixir
# Using binding option
User
|> OmQuery.join(:posts, :left, as: :posts)
|> OmQuery.filter(:published, :eq, true, binding: :posts)
|> OmQuery.filter(:likes, :gte, 10, binding: :posts)

# Using on/4 shorthand
User
|> OmQuery.join(:posts, :left, as: :posts)
|> OmQuery.on(:posts, :published, true)
|> OmQuery.on(:posts, :likes, :gte, 10)
```

### All Filter Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `:eq` | Equals | `filter(:status, :eq, "active")` |
| `:ne` | Not equals | `filter(:status, :ne, "deleted")` |
| `:gt` | Greater than | `filter(:age, :gt, 18)` |
| `:gte` | Greater than or equal | `filter(:age, :gte, 18)` |
| `:lt` | Less than | `filter(:price, :lt, 100)` |
| `:lte` | Less than or equal | `filter(:price, :lte, 100)` |
| `:in` | In list | `filter(:role, :in, ["a", "b"])` |
| `:not_in` | Not in list | `filter(:role, :not_in, ["x"])` |
| `:like` | Case-sensitive pattern | `filter(:name, :like, "J%")` |
| `:ilike` | Case-insensitive pattern | `filter(:email, :ilike, "%@gmail%")` |
| `:is_nil` | Is null | `filter(:deleted_at, :is_nil)` |
| `:is_not_nil` | Is not null | `filter(:verified_at, :is_not_nil)` |
| `:between` | In range | `filter(:score, :between, {1, 10})` |
| `:contains` | Array contains | `filter(:tags, :contains, ["a"])` |
| `:contained_by` | Array contained by | `filter(:tags, :contained_by, [...])` |
| `:jsonb_contains` | JSONB contains | `filter(:meta, :jsonb_contains, %{})` |
| `:jsonb_has_key` | JSONB has key | `filter(:meta, :jsonb_has_key, "k")` |

---

## Ordering

### Basic Ordering

```elixir
# Single field
OmQuery.order(token, :inserted_at, :desc)
OmQuery.order(token, :name, :asc)

# Multiple fields
OmQuery.orders(token, [
  {:priority, :desc},
  {:inserted_at, :desc},
  {:name, :asc}
])
```

### Null Handling

```elixir
# Nulls first/last
OmQuery.order(token, :completed_at, :asc_nulls_last)
OmQuery.order(token, :priority, :desc_nulls_first)
```

### Ordering on Joined Tables

```elixir
User
|> OmQuery.join(:profile, :left, as: :profile)
|> OmQuery.order(:score, :desc, binding: :profile)
```

---

## Pagination

OmQuery supports two pagination strategies: offset-based and cursor-based.

### Offset Pagination

Best for small datasets or when you need page numbers:

```elixir
User
|> OmQuery.paginate(:offset, limit: 20, offset: 40)
|> OmQuery.execute()

#=> {:ok, %Result{
#     data: [...],
#     pagination: %{
#       type: :offset,
#       limit: 20,
#       offset: 40,
#       current_page: 3,
#       total_pages: 10,    # if total_count requested
#       has_more: true,
#       has_previous: true,
#       next_offset: 60,
#       prev_offset: 20
#     }
#   }}
```

### Cursor Pagination (Recommended)

Best for large datasets - maintains consistent performance regardless of page:

```elixir
# First page
{:ok, result} = User
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.paginate(:cursor, limit: 20)
|> OmQuery.execute()

# Next page using cursor
{:ok, next_page} = User
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.paginate(:cursor, limit: 20, after: result.pagination.end_cursor)
|> OmQuery.execute()

# Previous page
{:ok, prev_page} = User
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.paginate(:cursor, limit: 20, before: result.pagination.start_cursor)
|> OmQuery.execute()
```

**Cursor Pagination Result:**

```elixir
%Result{
  data: [...],
  pagination: %{
    type: :cursor,
    limit: 20,
    has_more: true,
    has_previous: false,
    start_cursor: "eyJpZCI6MX0",
    end_cursor: "eyJpZCI6MjB9"
  }
}
```

### Pagination Comparison

| Aspect | Offset | Cursor |
|--------|--------|--------|
| Performance | Degrades at high offsets | Constant |
| Page jumping | Supported | Not supported |
| Real-time data | May skip/duplicate | Consistent |
| API compatibility | Simpler | More complex |
| Use case | Admin panels | Infinite scroll |

---

## Search

### Basic Search (ILIKE)

```elixir
# Search across multiple fields
User
|> OmQuery.search("john doe", [:name, :email, :bio])
|> OmQuery.execute()

# Search generates: WHERE name ILIKE '%john doe%' OR email ILIKE '%john doe%' OR bio ILIKE '%john doe%'
```

### Search Modes

```elixir
# ILIKE (default, case-insensitive)
OmQuery.search(token, "john", [:name, :email])

# Starts with
OmQuery.search(token, "john", [:name], mode: :starts_with)
# WHERE name ILIKE 'john%'

# Ends with
OmQuery.search(token, "@gmail.com", [:email], mode: :ends_with)
# WHERE email ILIKE '%@gmail.com'

# Exact match
OmQuery.search(token, "john@example.com", [:email], mode: :exact)
# WHERE email = 'john@example.com'

# Trigram similarity (requires pg_trgm extension)
OmQuery.search(token, "jonh", [:name], mode: :similarity, threshold: 0.3)
# Finds "john" even with typo
```

### Per-Field Configuration

```elixir
# Different modes per field
OmQuery.search(token, "search term", [
  :name,                                    # Default: ilike
  {:email, :exact},                         # Exact match
  {:bio, :similarity, threshold: 0.5},      # Fuzzy match
  {:title, :ilike, binding: :posts}         # On joined table
])
```

### Search with Ranking

```elixir
# Rank results by relevance
OmQuery.search(token, "elixir phoenix", [:title, :body], rank: true)
|> OmQuery.order(:search_rank, :desc)

# Custom ranking weights
OmQuery.search(token, "elixir", [
  {:title, :ilike, rank: 1},      # Highest priority
  {:summary, :ilike, rank: 2},
  {:body, :ilike, rank: 3}        # Lowest priority
], rank: true)
```

---

## Joins and Preloads

### Joins

```elixir
# Association join
User
|> OmQuery.join(:posts, :left, as: :posts)
|> OmQuery.filter(:published, true, binding: :posts)

# Inner join
|> OmQuery.join(:profile, :inner)

# Multiple joins
OmQuery.joins(token, [
  {:posts, :left, as: :posts},
  {:comments, :left, as: :comments},
  {:profile, :inner}
])

# Join with custom conditions
OmQuery.join(token, :posts, :left, as: :posts, on: [status: "published"])
```

### Preloads

```elixir
# Simple preload
OmQuery.preload(token, [:posts, :comments])

# Nested preload
OmQuery.preload(token, [posts: [:comments, :tags]])

# Preload with query
OmQuery.preload(token, [posts: from(p in Post, where: p.published == true)])
```

---

## Execution

### Execute Methods

```elixir
# Standard execution - returns {:ok, %Result{}} or {:error, error}
{:ok, result} = OmQuery.execute(token)
{:ok, result} = OmQuery.execute(token, repo: MyApp.Repo)

# Bang version - returns result or raises
result = OmQuery.execute!(token)

# Get all records as list
users = OmQuery.all(token)

# Get first record
user = OmQuery.first(token)

# Get exactly one record (raises if multiple)
user = OmQuery.one(token)

# Count records
count = OmQuery.count(token)

# Check existence
exists = OmQuery.exists?(token)

# Aggregate
total = OmQuery.aggregate(token, :price, :sum)
avg = OmQuery.aggregate(token, :score, :avg)
```

### Streaming

For memory-efficient processing of large datasets:

```elixir
User
|> OmQuery.filter(:status, "active")
|> OmQuery.stream(repo: Repo)
|> Stream.each(&process_user/1)
|> Stream.run()
```

### Batch Execution

Execute multiple queries in parallel:

```elixir
queries = [
  OmQuery.new(User) |> OmQuery.filter(:role, "admin"),
  OmQuery.new(User) |> OmQuery.filter(:role, "moderator"),
  OmQuery.new(User) |> OmQuery.filter(:role, "user")
]

results = OmQuery.batch(queries, repo: Repo)
#=> [{:ok, %Result{}}, {:ok, %Result{}}, {:ok, %Result{}}]
```

### Transaction

```elixir
OmQuery.transaction(fn ->
  {:ok, users} = OmQuery.execute(user_query)
  {:ok, posts} = OmQuery.execute(post_query)
  {users, posts}
end, repo: Repo)
```

---

## Result Structure

All query executions return a `%OmQuery.Result{}`:

```elixir
%OmQuery.Result{
  # The actual data
  data: [%User{}, %User{}, ...],

  # Pagination info
  pagination: %{
    type: :cursor | :offset | nil,
    limit: 20,
    offset: 0,                    # Offset only
    total_count: 150,             # If requested
    has_more: true,
    has_previous: false,

    # Offset pagination
    current_page: 1,
    total_pages: 8,
    next_offset: 20,
    prev_offset: nil,

    # Cursor pagination
    start_cursor: "eyJpZCI6MX0",
    end_cursor: "eyJpZCI6MjB9"
  },

  # Query metadata
  metadata: %{
    query_time_μs: 1234,
    total_time_μs: 1500,
    cached: false,
    cache_key: nil,
    sql: "SELECT ...",
    operation_count: 5,
    optimizations_applied: [:index_hint]
  }
}
```

---

## DSL (Macro Syntax)

For more expressive query definitions:

```elixir
import OmQuery.DSL

# Comparison operators
query User do
  where :status == "active"
  where :age >= 18
  where :role in ["admin", "moderator"]
  where :name =~ "%john%"  # ilike
  order :inserted_at, :desc
  limit 20
end
|> OmQuery.execute()

# With joins
query Product do
  join :category, :left, as: :cat
  where {:cat, :name} == "Electronics"
  where :price >= 100
  select %{name: :name, category: {:cat, :name}}
end

# Define reusable query modules
defmodule MyApp.UserQueries do
  use OmQuery.DSL

  defquery active_adults do
    filter :status, :eq, "active"
    filter :age, :gte, 18
    order :name, :asc
  end

  defquery admins do
    filter :role, :eq, "admin"
    order :inserted_at, :desc
  end
end

# Usage
User
|> MyApp.UserQueries.active_adults()
|> OmQuery.execute()
```

---

## Dynamic Queries from Params

Build queries from API/form parameters:

```elixir
params = %{
  "filter" => %{
    "status" => "active",
    "age_gte" => "18",
    "role_in" => "admin,moderator"
  },
  "sort" => "-inserted_at,name",
  "page" => %{
    "limit" => "20",
    "after" => "eyJpZCI6MTIzfQ"
  }
}

User
|> OmQuery.from_params(params)
|> OmQuery.execute()

# Equivalent to:
User
|> OmQuery.filter(:status, :eq, "active")
|> OmQuery.filter(:age, :gte, 18)
|> OmQuery.filter(:role, :in, ["admin", "moderator"])
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.order(:name, :asc)
|> OmQuery.paginate(:cursor, limit: 20, after: "eyJpZCI6MTIzfQ")
```

**Param Conventions:**

| Param Pattern | Translates To |
|---------------|---------------|
| `status=active` | `filter(:status, :eq, "active")` |
| `age_gte=18` | `filter(:age, :gte, 18)` |
| `role_in=a,b` | `filter(:role, :in, ["a", "b"])` |
| `sort=-created_at` | `order(:created_at, :desc)` |
| `sort=name` | `order(:name, :asc)` |

---

## Faceted Search

For e-commerce and catalog applications:

```elixir
alias OmQuery.FacetedSearch

result = FacetedSearch.new(Product)
|> FacetedSearch.search("iphone", [:name, :description])
|> FacetedSearch.filter_by(%{
  category_id: {:in, [1, 2, 3]},
  price: {:between, {100, 1000}},
  in_stock: true
})
|> FacetedSearch.paginate(:cursor, limit: 24)
|> FacetedSearch.order(:relevance, :desc)

# Define facets (sidebar filters)
|> FacetedSearch.facet(:categories, :category_id,
  join: :category,
  count_field: :name
)
|> FacetedSearch.facet(:brands, :brand_id,
  join: :brand,
  count_field: :name
)
|> FacetedSearch.facet(:price_ranges, :price,
  ranges: [
    {0, 50, "Under $50"},
    {50, 100, "$50 - $100"},
    {100, 500, "$100 - $500"},
    {500, nil, "Over $500"}
  ]
)
|> FacetedSearch.execute()

#=> %FacetedSearch.Result{
#     data: [%Product{}, ...],
#     pagination: %{...},
#     facets: %{
#       categories: [
#         %{id: 1, name: "Electronics", count: 42},
#         %{id: 2, name: "Accessories", count: 15}
#       ],
#       brands: [
#         %{id: 5, name: "Apple", count: 25},
#         %{id: 6, name: "Samsung", count: 17}
#       ],
#       price_ranges: [
#         %{label: "Under $50", count: 10},
#         %{label: "$50 - $100", count: 35}
#       ]
#     },
#     total_count: 150
#   }
```

---

## Debug Tools

Debug queries at any point in the pipeline:

```elixir
# Print raw SQL (default)
token |> OmQuery.debug()

# Specific format
token |> OmQuery.debug(:raw_sql)
token |> OmQuery.debug(:sql_params)   # SQL + params separately
token |> OmQuery.debug(:ecto)         # Ecto.Query struct
token |> OmQuery.debug(:pipeline)     # Pipeline syntax
token |> OmQuery.debug(:token)        # Token struct
token |> OmQuery.debug(:explain)      # PostgreSQL EXPLAIN
token |> OmQuery.debug(:explain_analyze)  # EXPLAIN ANALYZE (executes!)

# Multiple formats
token |> OmQuery.debug([:raw_sql, :ecto])

# With options
token |> OmQuery.debug(:raw_sql,
  label: "User Search Query",
  color: :green,
  stacktrace: true
)

# Debug at multiple points
Product
|> OmQuery.debug(:token, label: "Initial")
|> OmQuery.filter(:active, true)
|> OmQuery.debug(:raw_sql, label: "After filter")
|> OmQuery.join(:category, :left)
|> OmQuery.debug(:raw_sql, label: "After join")
|> OmQuery.execute()
```

---

## Advanced Features

### Common Table Expressions (CTEs)

```elixir
# Recursive CTE for hierarchical data
OmQuery.with_cte(token, :category_tree, fn ->
  Category
  |> OmQuery.filter(:parent_id, nil)
  |> OmQuery.union_all(fn ->
    from(c in Category,
      join: ct in "category_tree",
      on: c.parent_id == ct.id
    )
  end)
end, recursive: true)
```

### Subqueries

```elixir
# Filter with subquery
OmQuery.filter_subquery(token, :id, :in,
  from(p in Post,
    where: p.published == true,
    select: p.author_id
  )
)

# EXISTS subquery
OmQuery.exists(token,
  Post |> OmQuery.filter(:author_id, :field, :id)
)
```

### Raw SQL

```elixir
# Raw where clause
OmQuery.raw_where(token, "created_at > NOW() - INTERVAL '30 days'")

# With parameters
OmQuery.raw_where(token, "score > :min_score", %{min_score: 100})
```

### Window Functions

```elixir
OmQuery.window(token, :ranking, [
  partition_by: :category_id,
  order_by: [desc: :price]
])
|> OmQuery.select(%{
  name: :name,
  price: :price,
  rank: fragment("ROW_NUMBER() OVER (?)", window(:ranking))
})
```

### Locking

```elixir
# Row-level lock
OmQuery.lock(token, "FOR UPDATE")
OmQuery.lock(token, "FOR UPDATE NOWAIT")
OmQuery.lock(token, "FOR UPDATE SKIP LOCKED")
```

---

## Real-World Examples

### 1. User Search API (Phoenix)

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def index(conn, params) do
    result = User
    |> OmQuery.maybe(:status, params["status"])
    |> OmQuery.maybe(:role, params["role"])
    |> OmQuery.maybe(:verified, params["verified"])
    |> OmQuery.search(params["q"], [:name, :email], mode: :ilike)
    |> apply_date_filters(params)
    |> OmQuery.order(:inserted_at, :desc)
    |> OmQuery.paginate(:cursor,
      limit: parse_limit(params["limit"]),
      after: params["after"]
    )
    |> OmQuery.execute!()

    json(conn, %{
      users: result.data,
      pagination: %{
        has_more: result.pagination.has_more,
        end_cursor: result.pagination.end_cursor
      }
    })
  end

  defp apply_date_filters(token, %{"from" => from, "to" => to}) do
    token
    |> OmQuery.filter(:inserted_at, :gte, Date.from_iso8601!(from))
    |> OmQuery.filter(:inserted_at, :lte, Date.from_iso8601!(to))
  end
  defp apply_date_filters(token, _), do: token

  defp parse_limit(nil), do: 20
  defp parse_limit(limit), do: min(String.to_integer(limit), 100)
end
```

### 2. Admin Dashboard with Filters

```elixir
defmodule MyApp.Admin.Orders do
  def list_orders(filters \\ %{}) do
    Order
    |> OmQuery.join(:customer, :left, as: :customer)
    |> OmQuery.join(:items, :left, as: :items)
    |> OmQuery.preload([customer: :profile, items: :product])

    # Apply filters
    |> OmQuery.maybe(:status, filters[:status])
    |> OmQuery.maybe(:total, :gte, filters[:min_total])
    |> OmQuery.maybe(:total, :lte, filters[:max_total])
    |> maybe_customer_filter(filters[:customer_search])
    |> maybe_date_range(filters)

    # Sorting
    |> apply_sorting(filters[:sort] || "-created_at")

    # Pagination with total count
    |> OmQuery.paginate(:offset,
      limit: filters[:limit] || 25,
      offset: filters[:offset] || 0
    )
    |> OmQuery.execute!(include_total: true)
  end

  defp maybe_customer_filter(token, nil), do: token
  defp maybe_customer_filter(token, search) do
    OmQuery.search(token, search, [
      {:name, :ilike, binding: :customer},
      {:email, :ilike, binding: :customer}
    ])
  end

  defp maybe_date_range(token, %{from: from, to: to}) do
    token
    |> OmQuery.filter(:created_at, :gte, from)
    |> OmQuery.filter(:created_at, :lte, to)
  end
  defp maybe_date_range(token, _), do: token

  defp apply_sorting(token, "-" <> field) do
    OmQuery.order(token, String.to_existing_atom(field), :desc)
  end
  defp apply_sorting(token, field) do
    OmQuery.order(token, String.to_existing_atom(field), :asc)
  end
end
```

### 3. E-commerce Product Listing

```elixir
defmodule MyApp.Catalog do
  alias OmQuery.FacetedSearch

  def search_products(params) do
    FacetedSearch.new(Product)
    |> FacetedSearch.filter(:active, true)
    |> FacetedSearch.filter(:in_stock, true)

    # Text search
    |> maybe_search(params[:q])

    # Category filter
    |> maybe_filter(:category_id, :in, params[:categories])

    # Price range
    |> maybe_filter(:price, :gte, params[:min_price])
    |> maybe_filter(:price, :lte, params[:max_price])

    # Brand filter
    |> maybe_filter(:brand_id, :in, params[:brands])

    # Facets for sidebar
    |> FacetedSearch.facet(:categories, :category_id,
      join: :category,
      count_field: :name,
      exclude_from_self: true  # Don't filter facet by category selection
    )
    |> FacetedSearch.facet(:brands, :brand_id,
      join: :brand,
      count_field: :name
    )
    |> FacetedSearch.facet(:price_ranges, :price,
      ranges: price_ranges()
    )

    # Pagination
    |> FacetedSearch.paginate(:cursor, limit: 24, after: params[:cursor])

    # Sorting
    |> apply_sort(params[:sort])

    |> FacetedSearch.execute()
  end

  defp maybe_search(builder, nil), do: builder
  defp maybe_search(builder, ""), do: builder
  defp maybe_search(builder, q) do
    FacetedSearch.search(builder, q, [
      {:name, :ilike, rank: 1},
      {:description, :ilike, rank: 2},
      {:sku, :exact, rank: 1}
    ], rank: true)
  end

  defp maybe_filter(builder, _field, _op, nil), do: builder
  defp maybe_filter(builder, _field, _op, []), do: builder
  defp maybe_filter(builder, field, op, value) do
    FacetedSearch.filter(builder, field, op, value)
  end

  defp price_ranges do
    [
      {0, 25, "Under $25"},
      {25, 50, "$25 - $50"},
      {50, 100, "$50 - $100"},
      {100, 250, "$100 - $250"},
      {250, nil, "Over $250"}
    ]
  end

  defp apply_sort(builder, "price_asc"), do: FacetedSearch.order(builder, :price, :asc)
  defp apply_sort(builder, "price_desc"), do: FacetedSearch.order(builder, :price, :desc)
  defp apply_sort(builder, "newest"), do: FacetedSearch.order(builder, :inserted_at, :desc)
  defp apply_sort(builder, "popular"), do: FacetedSearch.order(builder, :sales_count, :desc)
  defp apply_sort(builder, _), do: FacetedSearch.order(builder, :relevance, :desc)
end
```

### 4. Reports with Aggregation

```elixir
defmodule MyApp.Reports do
  def sales_summary(date_range) do
    Order
    |> OmQuery.filter(:status, "completed")
    |> OmQuery.filter(:completed_at, :gte, date_range.from)
    |> OmQuery.filter(:completed_at, :lte, date_range.to)
    |> OmQuery.join(:items, :inner, as: :items)
    |> OmQuery.group_by([:category_id])
    |> OmQuery.select(%{
      category_id: :category_id,
      order_count: fragment("COUNT(DISTINCT ?)", field(:id)),
      item_count: fragment("COUNT(?)", field(:items, :id)),
      total_revenue: fragment("SUM(?)", field(:items, :subtotal)),
      avg_order_value: fragment("AVG(?)", field(:total))
    })
    |> OmQuery.order(fragment("SUM(?) DESC", field(:items, :subtotal)))
    |> OmQuery.all()
  end
end
```

---

## Best Practices

### 1. Use Cursor Pagination for APIs

```elixir
# GOOD: Consistent performance at any offset
|> OmQuery.paginate(:cursor, limit: 20, after: cursor)

# BAD: Performance degrades at high offsets
|> OmQuery.paginate(:offset, limit: 20, offset: 10000)
```

### 2. Use `maybe` for Optional Filters

```elixir
# GOOD: Clean, no conditionals
User
|> OmQuery.maybe(:status, params["status"])
|> OmQuery.maybe(:role, params["role"])

# BAD: Verbose conditionals
token = OmQuery.new(User)
token = if params["status"], do: OmQuery.filter(token, :status, params["status"]), else: token
```

### 3. Index Your Filter Fields

```sql
-- Basic index for equality/range
CREATE INDEX idx_users_status ON users(status);

-- Composite for common filter combinations
CREATE INDEX idx_users_status_role ON users(status, role);

-- Partial for common conditions
CREATE INDEX idx_products_active ON products(category_id)
  WHERE deleted_at IS NULL;

-- Trigram for similarity search
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_products_name_trgm ON products USING gin(name gin_trgm_ops);
```

### 4. Use Named Bindings for Joins

```elixir
# GOOD: Clear binding references
User
|> OmQuery.join(:posts, :left, as: :posts)
|> OmQuery.filter(:published, true, binding: :posts)

# BAD: Positional bindings are confusing
User
|> OmQuery.join(:posts, :left)
|> OmQuery.filter(:published, true, binding: 1)
```

### 5. Debug During Development

```elixir
# Add debug anywhere in the pipeline
User
|> OmQuery.filter(:status, "active")
|> OmQuery.debug(:raw_sql, label: "After status filter")
|> OmQuery.order(:name)
|> OmQuery.execute()
```

---

## Error Types

OmQuery provides specific error types for better error handling:

| Error | Cause |
|-------|-------|
| `OmQuery.ValidationError` | Invalid operation or value |
| `OmQuery.LimitExceededError` | Limit exceeds configured max |
| `OmQuery.PaginationError` | Invalid pagination config |
| `OmQuery.CursorError` | Invalid or expired cursor |
| `OmQuery.FilterGroupError` | Invalid filter group structure |

```elixir
case OmQuery.execute(token) do
  {:ok, result} -> handle_success(result)
  {:error, %OmQuery.CursorError{}} -> {:error, :invalid_cursor}
  {:error, %OmQuery.ValidationError{} = e} -> {:error, e.reason}
  {:error, error} -> {:error, error}
end
```

---

## Configuration Reference

```elixir
# Default repo (used when not specified in execute/2)
config :om_query, default_repo: MyApp.Repo

# Token limits
config :om_query, OmQuery.Token,
  default_limit: 20,    # Default pagination limit
  max_limit: 1000       # Maximum allowed limit
```

---

## Performance Tips

1. **Use cursor pagination** for large datasets (offset becomes slow at high offsets)

2. **Index filter fields properly:**
   - B-tree for equality/range: `CREATE INDEX idx_users_status ON users(status)`
   - Partial index for common filters: `CREATE INDEX ... WHERE deleted_at IS NULL`
   - GIN for array/JSONB: `CREATE INDEX ... USING gin(tags)`
   - Trigram for fuzzy search: `CREATE INDEX ... USING gin(name gin_trgm_ops)`

3. **Use `binding:` option** for filters on joined tables (avoids subqueries)

4. **Limit preloads** - each preload is a separate query. Use joins + select for denormalized results

5. **Use `maybe/3`** instead of conditional logic to keep queries composable

## License

MIT
