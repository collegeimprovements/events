# Events.Query Syntax Guide

This guide covers all syntax variations for the Events.Query module, including pipeline style, macro DSL, and all available operations.

## Table of Contents

- [Quick Start](#quick-start)
- [Two Syntax Styles](#two-syntax-styles)
- [Filtering](#filtering)
- [Joins](#joins)
- [Preloads](#preloads)
- [Ordering](#ordering)
- [Pagination](#pagination)
- [Select](#select)
- [Grouping & Aggregates](#grouping--aggregates)
- [Advanced Features](#advanced-features)
- [Complex Examples](#complex-examples)

---

## Quick Start

```elixir
# Pipeline Style - pipe from schema directly (no Query.new needed!)
User
|> Query.filter(:status, "active")
|> Query.filter(:age, :gte, 18)
|> Query.order(:name, :asc)
|> Query.paginate(:cursor, limit: 20)
|> Query.execute()

# Macro DSL Style
import Events.Query.DSL

query User do
  where :status == "active"
  where :age >= 18
  order :name, :asc
  paginate :cursor, limit: 20
end
|> Query.execute()
```

---

## Two Syntax Styles

### Pipeline Style

Use `Query.new/1` or pipe directly from a schema module:

```elixir
# Explicit Query.new (older style)
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.execute()

# Direct piping (new! uses Queryable protocol)
User
|> Query.filter(:status, :eq, "active")
|> Query.execute()

# From table name string (schemaless)
"users"
|> Query.filter(:status, :eq, "active")
|> Query.execute()

# From existing Ecto.Query
import Ecto.Query
from(u in User, where: u.admin == true)
|> Query.filter(:status, :eq, "active")
|> Query.execute()
```

### Macro DSL Style

Import `Events.Query.DSL` for a clean, Ecto-like syntax:

```elixir
import Events.Query.DSL

token = query User do
  where :status == "active"
  where :age >= 18
  order :name, :asc
  limit 20
end

Query.execute(token)
```

---

## Filtering

### Pipeline Syntax

```elixir
# Full syntax: filter(field, operator, value)
User |> Query.filter(:status, :eq, "active")

# Shorthand for :eq operator
User |> Query.filter(:status, "active")

# Keyword syntax for multiple equality filters
User |> Query.filter(status: "active", verified: true, role: "admin")

# With explicit operator
User |> Query.filter(:age, :gte, 18)
User |> Query.filter(:email, :ilike, "%@gmail.com")
User |> Query.filter(:role, :in, ["admin", "moderator"])

# Chaining filters (AND logic)
User
|> Query.filter(:status, "active")
|> Query.filter(:verified, true)
|> Query.filter(:age, :gte, 18)
```

### DSL Syntax

```elixir
import Events.Query.DSL

# Traditional filter syntax
query User do
  filter :status, :eq, "active"
  filter :age, :gte, 18
end

# Ecto-like comparison operators (recommended!)
query User do
  where :status == "active"
  where :age >= 18
  where :role in ["admin", "moderator"]
  where :email != nil
  where :name =~ "%john%"    # ilike pattern
end

# Keyword shorthand
query User do
  where status: "active", verified: true
end
```

### Supported Filter Operators

| Operator | DSL Syntax | Description | Example Value |
|----------|------------|-------------|---------------|
| `:eq` | `==` | Equals | `"active"` |
| `:neq` | `!=` | Not equals | `"deleted"` |
| `:gt` | `>` | Greater than | `18` |
| `:gte` | `>=` | Greater than or equal | `18` |
| `:lt` | `<` | Less than | `100` |
| `:lte` | `<=` | Less than or equal | `65` |
| `:in` | `in` | In list | `["a", "b"]` |
| `:not_in` | - | Not in list | `["x", "y"]` |
| `:like` | - | Case-sensitive pattern | `"John%"` |
| `:ilike` | `=~` | Case-insensitive pattern | `"%john%"` |
| `:is_nil` | `== nil` | Is NULL | `true` |
| `:not_nil` | `!= nil` | Is NOT NULL | `true` |
| `:between` | - | Between range | `{10, 100}` |
| `:contains` | - | Array contains | `["elixir"]` |
| `:jsonb_contains` | - | JSONB contains | `%{key: "val"}` |
| `:jsonb_has_key` | - | JSONB has key | `"settings"` |
| `:similarity` | - | pg_trgm similarity | `"john"` |

### OR Filters

```elixir
# Pipeline - match ANY condition
User
|> Query.where_any([
  {:status, :eq, "active"},
  {:role, :eq, "admin"},
  {:verified, :eq, true}
])

# AND filter group (explicit grouping)
User
|> Query.where_all([
  {:status, :eq, "active"},
  {:verified, :eq, true}
])
```

---

## Joins

### Basic Joins

```elixir
# Pipeline - association join
User
|> Query.join(:posts, :left)
|> Query.join(:comments, :inner)

# Convenience functions (recommended!)
User
|> Query.left_join(:posts)
|> Query.inner_join(:comments)
|> Query.right_join(:orders)
|> Query.full_join(:profiles)

# With named binding (as:)
User
|> Query.left_join(:posts, as: :user_posts)

# DSL - convenience macros
query User do
  left_join :posts
  inner_join :comments, as: :comments
  right_join :orders
end

# DSL - explicit type
query User do
  join :posts, :left
  join :comments, :inner, as: :comments
end
```

### Join Type Reference

| Function | Type | SQL |
|----------|------|-----|
| `left_join/3` | `:left` | `LEFT JOIN` |
| `right_join/3` | `:right` | `RIGHT JOIN` |
| `inner_join/3` | `:inner` | `INNER JOIN` |
| `full_join/3` | `:full` | `FULL OUTER JOIN` |
| `cross_join/3` | `:cross` | `CROSS JOIN` |

### Schema Joins with ON Conditions

Join to a schema (not association) with custom ON conditions:

```elixir
# Pipeline - multiple ON conditions as keyword list
User
|> Query.join(Category, :left,
    as: :cat,
    on: [id: :category_id, tenant_id: :tenant_id]
)
# Generates: LEFT JOIN categories c ON c.id = u.category_id AND c.tenant_id = u.tenant_id

# DSL
query User do
  join Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]
end
```

### Filtering on Joined Tables

**Key distinction:**
- `on:` in `join` = JOIN ON conditions (which rows to match)
- `Query.on/4` or DSL `on` = WHERE filters on joined table (which results to keep)

```elixir
# Pipeline - use Query.on/4 for WHERE filters on joined table
User
|> Query.join(Category, :left, as: :cat, on: [id: :category_id])
|> Query.on(:cat, :active, true)                    # WHERE cat.active = true
|> Query.on(:cat, :name, "Electronics")             # WHERE cat.name = 'Electronics'

# With explicit operator
User
|> Query.join(:posts, :left, as: :posts)
|> Query.on(:posts, :views, :gte, 100)              # WHERE posts.views >= 100
|> Query.on(:posts, :status, :in, ["published", "featured"])

# Using filter with binding: option (equivalent to on/4)
User
|> Query.join(:posts, :left, as: :posts)
|> Query.filter(:published, :eq, true, binding: :posts)

# DSL - use `on` macro for joined table filters
query User do
  join Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]

  # Root table filters
  where :active == true

  # Joined table filters (WHERE, not JOIN ON)
  on :cat, :featured == true
  on :cat, :name =~ "%Electronics%"
end
```

### DSL Binding Tuple Syntax

Alternative syntax using `{:binding, :field}` tuples in `where`:

```elixir
query Product do
  left_join Category, as: :cat, on: [id: :category_id]
  left_join Brand, as: :brand, on: [id: :brand_id]

  # Root table filter
  where :active == true

  # Joined table filters using {:binding, :field} syntax
  where {:cat, :name} == "Electronics"
  where {:cat, :featured} == true
  where {:cat, :priority} >= 5
  where {:cat, :type} in ["A", "B", "C"]
  where {:brand, :verified} == true
  where {:brand, :name} =~ "%Apple%"
end
```

Both `on :binding, :field == value` and `where {:binding, :field} == value` work - choose based on preference.

### Case Insensitive Filtering

Supported for `:eq`, `:in`, and `:not_in` operators:

```elixir
# DSL - case insensitive option
query User do
  where :email == "JOHN@EXAMPLE.COM", case: :insensitive
  where :role in ["Admin", "Moderator"], case: :insensitive
end

# Pipeline - case_insensitive option
User
|> Query.filter(:email, :eq, "JOHN@EXAMPLE.COM", case_insensitive: true)
|> Query.filter(:role, :in, ["Admin", "Moderator"], case_insensitive: true)
|> Query.filter(:status, :not_in, ["Deleted", "Banned"], case_insensitive: true)
```

**Note:** For `:in`/`:not_in`, all string values in the list are automatically lowercased when `case_insensitive: true`.

### Value Casting

Cast string values to appropriate types before comparison. Useful for query params:

```elixir
# Pipeline - cast option
User
|> Query.filter(:age, :gte, params["min_age"], cast: :integer)
|> Query.filter(:score, :gte, params["min_score"], cast: :float)
|> Query.filter(:active, :eq, params["active"], cast: :boolean)
|> Query.filter(:birthday, :eq, params["date"], cast: :date)

# Cast works with :in too - casts all values in the list
User
|> Query.filter(:age, :in, ["18", "21", "25"], cast: :integer)
# => WHERE age IN (18, 21, 25)

# DSL - cast option
query User do
  where :age >= "18", cast: :integer
  where :price >= "9.99", cast: :decimal
  where :active == "true", cast: :boolean
end

# Combined with binding tuple
query Product do
  left_join Category, as: :cat, on: [id: :category_id]
  where {:cat, :priority} >= "5", cast: :integer
end
```

**Supported cast types:**

| Type | Input Examples | Output |
|------|----------------|--------|
| `:integer` | `"25"`, `25` | `25` |
| `:float` | `"9.5"`, `9`, `9.5` | `9.5` |
| `:decimal` | `"9.99"`, `9.99` | `Decimal.new("9.99")` |
| `:boolean` | `"true"`, `"false"`, `"1"`, `"0"` | `true`/`false` |
| `:date` | `"2024-01-15"` | `~D[2024-01-15]` |
| `:datetime` | `"2024-01-15T10:30:00Z"` | `DateTime` or `NaiveDateTime` |
| `:uuid` | `"550e8400-e29b-41d4-..."` | UUID string |
| `:atom` | `"active"` | `:active` (existing atoms only) |

### Multiple Joins Example

```elixir
# Pipeline
Product
|> Query.join(Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id])
|> Query.join(Brand, :left, as: :brand, on: [id: :brand_id, region: :region])
|> Query.filter(:active, true)              # Root table
|> Query.on(:cat, :featured, true)          # Category table
|> Query.on(:brand, :verified, true)        # Brand table
|> Query.execute()

# DSL
query Product do
  join Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]
  join Brand, :left, as: :brand, on: [id: :brand_id, region: :region]

  where :active == true
  on :cat, :featured == true
  on :brand, :verified == true
end
```

---

## Preloads

### Simple Preloads

```elixir
# Pipeline - single association
User |> Query.preload(:posts)

# Multiple associations
User |> Query.preload([:posts, :comments, :profile])

# DSL
query User do
  preload :posts
  preload [:comments, :profile]
end
```

### Preloads with Nested Filters

```elixir
# Pipeline - builder function for nested query
User
|> Query.preload(:posts, fn q ->
  q
  |> Query.filter(:published, true)
  |> Query.filter(:featured, true)
  |> Query.order(:created_at, :desc)
  |> Query.limit(10)
end)

# With new shorthand syntax
User
|> Query.preload(:posts, fn q ->
  q
  |> Query.filter(published: true, featured: true)
  |> Query.order(:views, :desc)
end)

# DSL - do block for nested filters
query User do
  preload :posts do
    where :published == true
    where :featured == true
    order :created_at, :desc
    limit 10
  end
end
```

### Multiple Preloads with Different Filters

```elixir
# Pipeline
User
|> Query.preload(:posts, fn q ->
  q |> Query.filter(:published, true)
end)
|> Query.preload(:comments, fn q ->
  q |> Query.filter(:approved, true) |> Query.limit(5)
end)

# DSL
query User do
  preload :posts do
    where :published == true
    order :created_at, :desc
  end

  preload :comments do
    where :approved == true
    limit 5
  end
end
```

### Nested Preloads

```elixir
# Pipeline - preload within preload
User
|> Query.preload(:posts, fn q ->
  q
  |> Query.filter(:published, true)
  |> Query.preload(:comments, fn c ->
    c |> Query.filter(:approved, true)
  end)
end)
```

---

## Ordering

### Basic Ordering

```elixir
# Pipeline
User
|> Query.order(:name, :asc)
|> Query.order(:created_at, :desc)

# Multiple orders at once
User |> Query.orders([
  {:priority, :desc},
  {:created_at, :desc},
  :id  # defaults to :asc
])

# Ecto keyword syntax also works!
User |> Query.orders([asc: :name, desc: :created_at, asc: :id])

# DSL
query User do
  order :name, :asc
  order :created_at, :desc
end

# DSL multiple orders
query User do
  orders [{:priority, :desc}, {:created_at, :desc}, :id]
end
```

### Ordering on Joined Tables

```elixir
# Pipeline
User
|> Query.join(:posts, :left, as: :posts)
|> Query.order(:created_at, :desc, binding: :posts)

# DSL
query User do
  join :posts, :left, as: :posts
  order :created_at, :desc, binding: :posts
end
```

### Null Handling

```elixir
User |> Query.order(:score, :desc_nulls_last)
User |> Query.orders([desc_nulls_first: :score, asc: :name])
```

---

## Pagination

### Offset Pagination

```elixir
# Pipeline
User
|> Query.paginate(:offset, limit: 20, offset: 40)

# Or use limit/offset directly
User
|> Query.limit(20)
|> Query.offset(40)

# DSL
query User do
  paginate :offset, limit: 20, offset: 40
end
```

### Cursor Pagination (Recommended for large datasets)

```elixir
# Pipeline - first page
User
|> Query.order(:created_at, :desc)
|> Query.paginate(:cursor, limit: 20)
|> Query.execute()
# Result includes: %{pagination: %{end_cursor: "...", has_more: true}}

# Next page - use the cursor
User
|> Query.order(:created_at, :desc)
|> Query.paginate(:cursor, limit: 20, after: "cursor_from_previous_page")
|> Query.execute()

# DSL
query User do
  order :created_at, :desc
  paginate :cursor, limit: 20
end
```

---

## Select

### Basic Select

```elixir
# Pipeline - field list
User |> Query.select([:id, :name, :email])

# With aliases
User |> Query.select(%{
  user_id: :id,
  user_name: :name
})

# DSL
query User do
  select [:id, :name, :email]
end
```

### Select from Joined Tables

```elixir
# Pipeline
Product
|> Query.join(:category, :left, as: :cat)
|> Query.join(:brand, :left, as: :brand)
|> Query.select(%{
  product_id: :id,
  product_name: :name,
  price: :price,
  category_id: {:cat, :id},
  category_name: {:cat, :name},
  brand_name: {:brand, :name}
})

# DSL
query Product do
  join :category, :left, as: :cat
  join :brand, :left, as: :brand

  select %{
    product_id: :id,
    product_name: :name,
    category_name: {:cat, :name},
    brand_name: {:brand, :name}
  }
end
```

---

## Grouping & Aggregates

### Group By

```elixir
# Pipeline
Order
|> Query.select(%{status: :status, count: {:count, :id}})
|> Query.group_by(:status)

# DSL
query Order do
  select %{status: :status, total: {:sum, :amount}}
  group_by :status
end
```

### Having

```elixir
# Pipeline
Order
|> Query.select(%{customer_id: :customer_id, total: {:sum, :amount}})
|> Query.group_by(:customer_id)
|> Query.having(count: {:gt, 5})

# DSL
query Order do
  select %{customer_id: :customer_id, order_count: {:count, :id}}
  group_by :customer_id
  having count: {:gt, 5}
end
```

### Aggregate Shortcuts

```elixir
# Count
User |> Query.filter(:status, "active") |> Query.count()

# Sum, Avg, Min, Max
Order |> Query.filter(:status, "completed") |> Query.aggregate(:sum, :amount)
User |> Query.filter(:status, "active") |> Query.aggregate(:avg, :age)
Product |> Query.aggregate(:min, :price)
Product |> Query.aggregate(:max, :price)

# Exists
User |> Query.filter(:email, "john@example.com") |> Query.exists?()
```

---

## Advanced Features

### Window Functions

```elixir
# Pipeline
Order
|> Query.window(:running_total,
    partition_by: :customer_id,
    order_by: [asc: :created_at],
    frame: {:rows, :unbounded_preceding, :current_row}
)
|> Query.select(%{
  id: :id,
  amount: :amount,
  running_total: {:window, {:sum, :amount}, over: :running_total}
})

# DSL
query Order do
  window :running_total,
    partition_by: :customer_id,
    order_by: [asc: :created_at]

  select %{
    id: :id,
    amount: :amount,
    total: {:window, {:sum, :amount}, over: :running_total}
  }
end
```

### CTEs (Common Table Expressions)

```elixir
# Pipeline
active_users = User |> Query.new() |> Query.filter(:active, true)

Order
|> Query.new()
|> Query.with_cte(:active_users, active_users)
|> Query.join(:active_users, :inner, on: [user_id: :id])

# DSL
query Order do
  with_cte :active_users do
    filter :active, :eq, true
  end
end
```

### Search with Ranking

```elixir
# Simple search (OR across fields)
Product |> Query.search("iphone", [:name, :description, :sku])

# E-commerce search with ranking
Product |> Query.search("wireless headphones", [
  {:sku, :exact, rank: 1, take: 3},           # Exact SKU matches first
  {:name, :similarity, rank: 2, take: 10},    # Fuzzy name matches
  {:brand, :ilike, rank: 3, take: 5},         # Brand contains term
  {:description, :ilike, rank: 4, take: 5}    # Description matches
], rank: true)
```

### Conditional Filtering

```elixir
# Apply filter only if value is truthy
User
|> Query.then_if(params[:status], fn token, status ->
  Query.filter(token, :status, :eq, status)
end)
|> Query.then_if(params[:min_age], fn token, age ->
  Query.filter(token, :age, :gte, age)
end)
|> Query.execute()

# Boolean conditional
User
|> Query.if_true(show_active_only?, fn token ->
  Query.filter(token, :status, :eq, "active")
end)
```

### Filter By Map

```elixir
# Apply multiple filters from a map
params = %{
  status: "active",
  price: {:between, {10, 100}},
  category_id: {:in, [1, 2, 3]},
  rating: {:gte, 4},
  deleted_at: {:is_nil, true}
}

Product |> Query.filter_by(params)
```

---

## Complex Examples

### E-Commerce Product Listing

```elixir
# Pipeline Style
Product
|> Query.left_join(Category, as: :cat, on: [id: :category_id, tenant_id: :tenant_id])
|> Query.left_join(Brand, as: :brand, on: [id: :brand_id])
|> Query.filter(:active, true)
|> Query.filter(:deleted_at, :is_nil, true)
|> Query.on(:cat, :active, true)
|> Query.on(:cat, :name, :in, ["Electronics", "Computers"])
|> Query.on(:brand, :verified, true)
|> Query.search(params[:q], [
  {:sku, :exact, rank: 1},
  {:name, :similarity, rank: 2},
  {:description, :ilike, rank: 3}
], rank: true)
|> Query.order(:featured, :desc)
|> Query.order(:created_at, :desc)
|> Query.paginate(:cursor, limit: 20, after: params[:cursor])
|> Query.preload(:images, fn q ->
  q |> Query.filter(:primary, true) |> Query.limit(1)
end)
|> Query.select(%{
  id: :id,
  name: :name,
  price: :price,
  category_name: {:cat, :name},
  brand_name: {:brand, :name}
})
|> Query.execute()

# DSL Style
import Events.Query.DSL

query Product do
  # Joins with ON conditions (using convenience macros)
  left_join Category, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]
  left_join Brand, as: :brand, on: [id: :brand_id]

  # Root table filters
  where :active == true
  where :deleted_at == nil

  # Joined table filters using {:binding, :field} syntax
  where {:cat, :active} == true
  where {:cat, :name} in ["Electronics", "Computers"]
  where {:brand, :verified} == true

  # Ordering
  order :featured, :desc
  order :created_at, :desc

  # Pagination
  paginate :cursor, limit: 20

  # Filtered preload
  preload :images do
    where :primary == true
    limit 1
  end

  # Select with joined fields
  select %{
    id: :id,
    name: :name,
    price: :price,
    category_name: {:cat, :name},
    brand_name: {:brand, :name}
  }
end
|> Query.execute()
```

### User Dashboard with Related Data

```elixir
# Pipeline Style
User
|> Query.filter(:id, user_id)
|> Query.preload(:posts, fn q ->
  q
  |> Query.filter(:published, true)
  |> Query.order(:created_at, :desc)
  |> Query.limit(5)
  |> Query.preload(:comments, fn c ->
    c |> Query.filter(:approved, true) |> Query.limit(3)
  end)
end)
|> Query.preload(:notifications, fn q ->
  q
  |> Query.filter(:read, false)
  |> Query.order(:created_at, :desc)
  |> Query.limit(10)
end)
|> Query.preload(:followers, fn q ->
  q |> Query.order(:created_at, :desc) |> Query.limit(20)
end)
|> Query.first!()

# DSL Style
query User do
  filter :id, :eq, user_id

  preload :posts do
    where :published == true
    order :created_at, :desc
    limit 5
  end

  preload :notifications do
    where :read == false
    order :created_at, :desc
    limit 10
  end

  preload :followers do
    order :created_at, :desc
    limit 20
  end
end
|> Query.first!()
```

### Analytics Query with Window Functions

```elixir
# Pipeline Style
Order
|> Query.filter(:status, "completed")
|> Query.filter(:created_at, :gte, start_date)
|> Query.window(:daily_rank,
    partition_by: :product_id,
    order_by: [desc: :amount]
)
|> Query.window(:running_total,
    partition_by: :customer_id,
    order_by: [asc: :created_at],
    frame: {:rows, :unbounded_preceding, :current_row}
)
|> Query.select(%{
  order_id: :id,
  product_id: :product_id,
  customer_id: :customer_id,
  amount: :amount,
  daily_rank: {:window, :rank, over: :daily_rank},
  customer_running_total: {:window, {:sum, :amount}, over: :running_total}
})
|> Query.execute()
```

### Multi-Tenant Query with Soft Deletes

```elixir
# Pipeline Style
Product
|> Query.join(Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id])
|> Query.filter(:tenant_id, current_tenant_id)
|> Query.exclude_deleted()                        # deleted_at IS NULL
|> Query.on(:cat, :active, true)
|> Query.then_if(params[:category_id], fn t, cat_id ->
  Query.on(t, :cat, :id, cat_id)
end)
|> Query.then_if(params[:search], fn t, term ->
  Query.search(t, term, [:name, :sku, :description])
end)
|> Query.order(:name, :asc)
|> Query.paginate(:cursor, limit: 50)
|> Query.execute()
```

---

## Execution Methods

### Query.execute vs Query.build

**`Query.execute/2`** - Full execution with structured result:
```elixir
{:ok, result} = User |> Query.filter(:active, true) |> Query.execute()
# Returns %Result{data: [...], pagination: %{...}, metadata: %{...}}

result.data          # => [%User{}, %User{}, ...]
result.pagination    # => %{type: :cursor, has_more: true, end_cursor: "..."}
result.metadata      # => %{query_time_μs: 1234, total_time_μs: 1500}
```

**`Query.build/1`** - Returns raw Ecto.Query (for Repo.all/one/etc):
```elixir
query = User |> Query.filter(:active, true) |> Query.build()
# Returns %Ecto.Query{}

# Use with Repo directly
users = Repo.all(query)       # => [%User{}, %User{}, ...]
user = Repo.one(query)        # => %User{} or nil
count = Repo.aggregate(query, :count)
```

**When to use which:**
- Use `Query.execute/2` when you need pagination info, timing metadata, or structured results
- Use `Query.build/1` + `Repo.*` when you need raw Ecto operations or custom handling

### Method Reference

| Method | Returns | Description |
|--------|---------|-------------|
| `execute/2` | `{:ok, Result.t}` or `{:error, e}` | Safe execution with full result |
| `execute!/2` | `Result.t` | Raises on error |
| `build/1` | `Ecto.Query.t` | Returns raw Ecto query for Repo |
| `first/2` | Record or `nil` | First result |
| `first!/2` | Record | First or raises |
| `one/2` | Record or `nil` | Exactly one result |
| `one!/2` | Record | Exactly one or raises |
| `all/2` | `[Record]` | All results as list |
| `count/2` | `integer` | Count of records |
| `exists?/2` | `boolean` | Check existence |
| `aggregate/4` | `term` | Run aggregate function |
| `stream/2` | `Enumerable.t` | Stream for large datasets |

## Result Structure

```elixir
%Events.Query.Result{
  data: [...],
  pagination: %{
    type: :cursor,
    limit: 20,
    has_more: true,
    end_cursor: "...",
    start_cursor: "..."
  },
  metadata: %{
    query_time_μs: 1234,
    total_time_μs: 1500,
    cached: false
  }
}
```
