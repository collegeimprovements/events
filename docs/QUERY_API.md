# Query API - Composable Builder with Smart Filters

A powerful query builder that composes with both keyword and pipe syntax, featuring smart filter operations, join support, and built-in soft delete awareness.

## Features

✅ **Builder Pattern** - Accumulates query operations
✅ **Smart Filter Syntax** - `{field, operation, value, options}` with intelligent defaults
✅ **Join Support** - Filter on joined tables
✅ **Soft Delete** - Automatically excludes deleted records
✅ **Dual Syntax** - Works with both keyword and pipe syntax
✅ **Final Execution** - Use with `Repo.all()`, `Repo.one()`, or `to_sql()`

## Quick Start

```elixir
alias Events.Repo.Query
alias Events.Repo

# Pipe syntax
Query.new(Product)
|> Query.where(status: "active")
|> Query.where({:price, :gt, 100})
|> Query.limit(10)
|> Repo.all()

# Keyword syntax
Query.new(Product, [
  where: [status: "active"],
  where: {:price, :gt, 100},
  limit: 10
])
|> Repo.all()

# Get SQL for debugging
{sql, params} = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.to_sql()
```

## Filter Syntax

The `where/2` function supports multiple formats for maximum flexibility:

### Simple Equality (Inferred)

```elixir
# String/integer equality
Query.where(query, status: "active")
Query.where(query, price: 100)

# Multiple conditions
Query.where(query, [status: "active", type: "widget"])
```

### List = IN Operator (Inferred)

```elixir
# List automatically uses :in
Query.where(query, status: ["active", "pending", "published"])

# Equivalent to
Query.where(query, {:status, :in, ["active", "pending", "published"]})
```

### With Explicit Operators

```elixir
# Comparisons
Query.where(query, {:price, :gt, 100})
Query.where(query, {:price, :gte, 100})
Query.where(query, {:price, :lt, 1000})
Query.where(query, {:price, :lte, 1000})

# Range
Query.where(query, {:price, :between, {10, 100}})

# Pattern matching
Query.where(query, {:name, :like, "%widget%"})
Query.where(query, {:name, :ilike, "%widget%"})  # case-insensitive

# NULL checks
Query.where(query, {:deleted_at, :is_nil, nil})
Query.where(query, {:deleted_at, :not_nil, nil})

# List operations
Query.where(query, {:id, :in, [id1, id2, id3]})
Query.where(query, {:id, :not_in, [id1, id2, id3]})
```

### With Options

```elixir
# Include NULL values
Query.where(query, {:email, :eq, "user@example.com", include_nil: true})

# Case-insensitive matching
Query.where(query, {:name, :ilike, "%widget%", case_sensitive: false})
```

## List-Based Filters

The Query API supports passing all filters as a list for easy composition and dynamic query building.

### Using `filters:` Option

```elixir
# Simple list of filters
Query.new(Product, filters: [
  status: "active",
  {:price, :gt, 100},
  {:name, :ilike, "%widget%"}
]) |> Repo.all()

# Mix keyword and tuple formats
Query.new(Product, filters: [
  status: "active",
  type: "physical",
  {:price, :between, {10, 100}},
  {:name, :ilike, "%widget%", case_sensitive: false}
]) |> Repo.all()
```

### Using `where:` with a List

```elixir
# Pass list to where: option
Query.new(Product, where: [
  status: "active",
  {:price, :gt, 100},
  {:stock, :gte, 1}
]) |> Repo.all()

# Build filter list dynamically
filters = [
  status: "active",
  {:price, :gt, 100}
]

if include_featured do
  filters = filters ++ [tags: ["featured"]]
end

Query.new(Product, where: filters) |> Repo.all()
```

### Passing Lists to `where/2`

```elixir
# Pass list directly to where/2
query = Query.new(Product)

filters = [
  status: "active",
  {:price, :gt, 100},
  {:name, :ilike, "%widget%"}
]

query
|> Query.where(filters)
|> Repo.all()
```

### Dynamic Filter Building

```elixir
# Build filters from params
def search_products(params) do
  filters = []

  filters = if params[:status], do: filters ++ [status: params[:status]], else: filters
  filters = if params[:min_price], do: filters ++ [{:price, :gte, params[:min_price]}], else: filters
  filters = if params[:max_price], do: filters ++ [{:price, :lte, params[:max_price]}], else: filters
  filters = if params[:search], do: filters ++ [{:name, :ilike, "%#{params[:search]}%"}], else: filters

  Query.new(Product, filters: filters) |> Repo.all()
end

# More functional approach
def search_products_v2(params) do
  filters = [
    {:status, params[:status]},
    {:min_price, params[:min_price]},
    {:max_price, params[:max_price]},
    {:search, params[:search]}
  ]
  |> Enum.reject(fn {_key, val} -> is_nil(val) end)
  |> Enum.flat_map(fn
    {:status, status} -> [status: status]
    {:min_price, min} -> [{:price, :gte, min}]
    {:max_price, max} -> [{:price, :lte, max}]
    {:search, term} -> [{:name, :ilike, "%#{term}%"}]
  end)

  Query.new(Product, filters: filters) |> Repo.all()
end
```

### Combining Multiple Options

```elixir
# Combine filters with other options
Query.new(Product, [
  filters: [
    status: "active",
    {:price, :gt, 100}
  ],
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
]) |> Repo.all()

# Mix filters: and where: options
Query.new(Product, [
  filters: [status: "active"],
  where: {:price, :gt, 100},
  limit: 10
]) |> Repo.all()
```

### Filters with Joins

```elixir
# Filters list can include join filters
Query.new(Product, [
  join: :category,
  filters: [
    status: "active",
    {:price, :gt, 100},
    {:category, :name, "Electronics"}  # Filter on joined table
  ]
]) |> Repo.all()

# More complex example
Query.new(Product, [
  join: :category,
  filters: [
    status: "active",
    type: "physical",
    {:price, :between, {10, 100}},
    {:category, :name, "Electronics"},
    {:category, :active, true}
  ],
  order_by: [desc: :price],
  limit: 10
]) |> Repo.all()
```

### Nested Lists

```elixir
# where: accepts nested lists
Query.new(Product, where: [
  [status: "active"],  # First batch of filters
  {:price, :gt, 100},  # Single filter
  [type: "physical", stock: 1]  # Another batch
]) |> Repo.all()

# Useful for grouping related filters
base_filters = [status: "active", type: "physical"]
price_filters = [{:price, :gte, 10}, {:price, :lte, 100}]
category_filters = [{:category, :name, "Electronics"}]

Query.new(Product, [
  join: :category,
  where: [base_filters, price_filters, category_filters]
]) |> Repo.all()
```

## Operations Reference

| Operation | Description | Example |
|-----------|-------------|---------|
| `:eq` | Equal | `{:status, :eq, "active"}` |
| `:neq` | Not equal | `{:status, :neq, "deleted"}` |
| `:gt` | Greater than | `{:price, :gt, 100}` |
| `:gte` | Greater than or equal | `{:price, :gte, 100}` |
| `:lt` | Less than | `{:price, :lt, 1000}` |
| `:lte` | Less than or equal | `{:price, :lte, 1000}` |
| `:in` | In list | `{:status, :in, ["active", "pending"]}` |
| `:not_in` | Not in list | `{:status, :not_in, ["deleted"]}` |
| `:like` | Pattern match (case-sensitive) | `{:name, :like, "%widget%"}` |
| `:ilike` | Pattern match (case-insensitive) | `{:name, :ilike, "%widget%"}` |
| `:not_like` | Not like | `{:name, :not_like, "%test%"}` |
| `:not_ilike` | Not ilike | `{:name, :not_ilike, "%test%"}` |
| `:is_nil` | Is NULL | `{:deleted_at, :is_nil, nil}` |
| `:not_nil` | Is not NULL | `{:email, :not_nil, nil}` |
| `:between` | Between range | `{:price, :between, {10, 100}}` |
| `:contains` | Array contains | `{:tags, :contains, ["featured"]}` |
| `:contained_by` | Array contained by | `{:tags, :contained_by, [...]}` |
| `:jsonb_contains` | JSONB contains | `{:metadata, :jsonb_contains, %{key: "value"}}` |
| `:jsonb_has_key` | JSONB has key | `{:metadata, :jsonb_has_key, "featured"}` |

## Joins

### Basic Joins

```elixir
# Inner join (default)
Query.new(Product)
|> Query.join(:category)
|> Query.where({:category, :name, "Electronics"})
|> Repo.all()

# Left join
Query.new(Product)
|> Query.join(:category, :left)
|> Repo.all()

# Right join
Query.new(Product)
|> Query.join(:category, :right)
|> Repo.all()
```

### Filtering on Joined Tables

```elixir
# Filter on main table AND joined table
Query.new(Product)
|> Query.where(status: "active")  # Main table
|> Query.join(:category)
|> Query.where({:category, :name, "Electronics"})  # Joined table
|> Query.where({:category, :active, true})  # Another joined filter
|> Repo.all()

# With operators on joined tables
Query.new(Product)
|> Query.join(:category)
|> Query.where({:category, :priority, :gt, 5})
|> Repo.all()
```

### Multiple Joins

```elixir
Query.new(Product)
|> Query.join(:category)
|> Query.join(:brand)
|> Query.where({:category, :name, "Electronics"})
|> Query.where({:brand, :name, "ACME"})
|> Repo.all()
```

## Query Building

### Pipe Syntax

```elixir
products = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.where({:price, :gte, 10})
  |> Query.where({:price, :lte, 100})
  |> Query.order_by(desc: :inserted_at)
  |> Query.limit(20)
  |> Query.offset(40)
  |> Repo.all()
```

### Keyword Syntax

```elixir
# Using multiple where: options
products = Query.new(Product, [
  where: [status: "active"],
  where: {:price, :gte, 10},
  where: {:price, :lte, 100},
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
])
|> Repo.all()

# Using filters: option (recommended for multiple filters)
products = Query.new(Product, [
  filters: [
    status: "active",
    {:price, :gte, 10},
    {:price, :lte, 100}
  ],
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
])
|> Repo.all()

# With joins
products = Query.new(Product, [
  join: :category,
  filters: [
    status: "active",
    {:category, :name, "Electronics"}
  ],
  order_by: [desc: :inserted_at],
  limit: 10
])
|> Repo.all()
```

### Mixed Syntax

```elixir
# Start with keyword, continue with pipe
products = Query.new(Product, [
  where: [status: "active"],
  limit: 10
])
|> Query.where({:price, :gt, 100})
|> Query.order_by(desc: :price)
|> Repo.all()
```

## Execution

### With Repo Functions

```elixir
# All records
products = Query.new(Product)
  |> Query.where(status: "active")
  |> Repo.all()

# One record
product = Query.new(Product)
  |> Query.where(slug: "my-product")
  |> Repo.one()

# One record (raises if not found)
product = Query.new(Product)
  |> Query.where(id: id)
  |> Repo.one!()

# Count
count = Query.new(Product)
  |> Query.where(status: "active")
  |> Repo.aggregate(:count)

# Exists?
exists = Query.new(Product)
  |> Query.where(slug: "my-product")
  |> Repo.exists?()
```

### Convert to Ecto.Query

```elixir
# Get the underlying Ecto.Query
ecto_query = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.to_query()

# Use with any Ecto functions
Repo.all(ecto_query)
Repo.stream(ecto_query)
```

### Get SQL

```elixir
# For debugging or logging
{sql, params} = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.where({:price, :gt, 100})
  |> Query.to_sql()

IO.puts(sql)
# => SELECT p0.* FROM products AS p0 WHERE (p0.deleted_at IS NULL) AND (p0.status = $1) AND (p0.price > $2)

IO.inspect(params)
# => ["active", 100]
```

## CRUD Operations

### Insert

```elixir
{:ok, product} = Query.insert(Product, %{
  name: "Widget",
  price: 9.99,
  status: "active"
}, created_by: user_id)
```

### Update

```elixir
# Update single record
{:ok, product} = Query.update(product, %{
  price: 12.99
}, updated_by: user_id)

# Update all matching query
{:ok, count} = Query.new(Product)
  |> Query.where(status: "draft")
  |> Query.update_all([set: [status: "published"]], updated_by: user_id)
```

### Delete

```elixir
# Soft delete (default)
{:ok, product} = Query.delete(product, deleted_by: user_id)

# Hard delete (permanent)
{:ok, product} = Query.delete(product, hard: true)

# Delete all matching query
{:ok, count} = Query.new(Product)
  |> Query.where(status: "draft")
  |> Query.delete_all(deleted_by: user_id)

# Hard delete all
{:ok, count} = Query.new(Product)
  |> Query.where(status: "old")
  |> Query.delete_all(hard: true)
```

## Soft Delete

### Default Behavior

By default, all queries exclude soft-deleted records:

```elixir
# Only returns non-deleted products
products = Query.new(Product)
  |> Query.where(status: "active")
  |> Repo.all()
```

### Including Deleted Records

```elixir
# Include soft-deleted records
products = Query.new(Product, include_deleted: true)
  |> Query.where(status: "active")
  |> Repo.all()

# Or with pipe
products = Query.new(Product)
  |> Query.include_deleted()
  |> Query.where(status: "active")
  |> Repo.all()
```

### Lifecycle

```elixir
# Create
{:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)

# Soft delete
{:ok, deleted} = Query.delete(product, deleted_by: user_id)
# deleted.deleted_at => ~U[2024-01-15 10:30:00]
# deleted.deleted_by_urm_id => user_id

# Query won't find it (soft-deleted)
Query.new(Product) |> Query.where(id: product.id) |> Repo.one()
# => nil

# Unless we include deleted
Query.new(Product, include_deleted: true)
|> Query.where(id: product.id)
|> Repo.one()
# => %Product{deleted_at: ~U[...]}
```

## Complex Examples

### E-Commerce Product Search

```elixir
def search_products(params) do
  query = Query.new(Product)

  query = if params[:category] do
    query
    |> Query.join(:category)
    |> Query.where({:category, :slug, params[:category]})
  else
    query
  end

  query = if params[:min_price] do
    Query.where(query, {:price, :gte, params[:min_price]})
  else
    query
  end

  query = if params[:max_price] do
    Query.where(query, {:price, :lte, params[:max_price]})
  else
    query
  end

  query = if params[:search] do
    Query.where(query, {:name, :ilike, "%#{params[:search]}%"})
  else
    query
  end

  query
  |> Query.order_by(desc: :inserted_at)
  |> Query.limit(params[:per_page] || 20)
  |> Query.offset((params[:page] || 0) * (params[:per_page] || 20))
  |> Repo.all()
end
```

### Paginated List with Filters

```elixir
def list_products_paginated(filters, page, per_page) do
  base_query = Query.new(Product)

  query = Enum.reduce(filters, base_query, fn
    {:status, status}, acc ->
      Query.where(acc, status: status)

    {:type, type}, acc ->
      Query.where(acc, type: type)

    {:min_price, min}, acc ->
      Query.where(acc, {:price, :gte, min})

    {:max_price, max}, acc ->
      Query.where(acc, {:price, :lte, max})

    {:category_id, cat_id}, acc ->
      acc
      |> Query.join(:category)
      |> Query.where({:category, :id, cat_id})

    _, acc -> acc
  end)

  products = query
    |> Query.order_by(desc: :inserted_at)
    |> Query.limit(per_page)
    |> Query.offset((page - 1) * per_page)
    |> Repo.all()

  total = query |> Repo.aggregate(:count)

  %{
    entries: products,
    page: page,
    per_page: per_page,
    total_count: total,
    total_pages: ceil(total / per_page)
  }
end
```

### JSONB Metadata Filtering

```elixir
# Find products with featured flag
Query.new(Product)
|> Query.where({:metadata, :jsonb_contains, %{"featured" => true}})
|> Repo.all()

# Find products with video_url in metadata
Query.new(Product)
|> Query.where({:metadata, :jsonb_has_key, "video_url"})
|> Repo.all()
```

### Multi-Table Search

```elixir
Query.new(Product)
|> Query.join(:category)
|> Query.join(:brand)
|> Query.where(status: "active")
|> Query.where({:category, :name, "Electronics"})
|> Query.where({:brand, :country, "USA"})
|> Query.where({:price, :between, {100, 500}})
|> Query.order_by([desc: :popularity, asc: :price])
|> Query.limit(10)
|> Repo.all()
```

## Context Pattern

```elixir
defmodule Events.Products do
  alias Events.Product
  alias Events.Repo
  alias Events.Repo.Query

  def list_products(filters \\ []) do
    build_query(filters)
    |> Repo.all()
  end

  def list_products_paginated(filters, page, per_page) do
    query = build_query(filters)

    products = query
      |> Query.limit(per_page)
      |> Query.offset((page - 1) * per_page)
      |> Repo.all()

    total = query |> Repo.aggregate(:count)

    %{
      entries: products,
      page: page,
      per_page: per_page,
      total_count: total,
      total_pages: ceil(total / per_page)
    }
  end

  def get_product(id) do
    case Query.new(Product)
         |> Query.where(id: id)
         |> Repo.one() do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  def create_product(attrs, opts \\ []) do
    Query.insert(Product, attrs, opts)
  end

  def update_product(product, attrs, opts \\ []) do
    Query.update(product, attrs, opts)
  end

  def delete_product(product, opts \\ []) do
    Query.delete(product, opts)
  end

  def publish_products(product_ids, user_id) do
    Query.new(Product)
    |> Query.where({:id, :in, product_ids})
    |> Query.where(status: "draft")
    |> Query.update_all([set: [status: "published"]], updated_by: user_id)
  end

  # Private

  defp build_query(filters) do
    Enum.reduce(filters, Query.new(Product), fn
      {:status, status}, acc ->
        Query.where(acc, status: status)

      {:type, type}, acc ->
        Query.where(acc, type: type)

      {:price_min, min}, acc ->
        Query.where(acc, {:price, :gte, min})

      {:price_max, max}, acc ->
        Query.where(acc, {:price, :lte, max})

      {:search, term}, acc ->
        Query.where(acc, {:name, :ilike, "%#{term}%"})

      {:category, category}, acc ->
        acc
        |> Query.join(:category)
        |> Query.where({:category, :slug, category})

      {:order, order}, acc ->
        Query.order_by(acc, order)

      _, acc -> acc
    end)
  end
end
```

## Best Practices

### 1. Use Smart Defaults

```elixir
# ✅ Good - let Query infer the operation
Query.where(query, status: "active")
Query.where(query, tags: ["featured", "new"])

# ❌ Unnecessary - operation is inferred
Query.where(query, {:status, :eq, "active"})
Query.where(query, {:tags, :in, ["featured", "new"]})
```

### 2. Compose Filters

```elixir
# ✅ Good - build filters incrementally
def build_query(filters) do
  Enum.reduce(filters, Query.new(Product), fn filter, acc ->
    apply_filter(acc, filter)
  end)
end

defp apply_filter(query, {:status, status}), do: Query.where(query, status: status)
defp apply_filter(query, {:min_price, min}), do: Query.where(query, {:price, :gte, min})
defp apply_filter(query, _), do: query
```

### 3. Use to_sql() for Debugging

```elixir
# ✅ Good - inspect generated SQL during development
query = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.join(:category)

{sql, params} = Query.to_sql(query)
IO.puts("\nSQL: #{sql}")
IO.inspect(params, label: "Params")
```

### 4. Always Use Audit Fields

```elixir
# ✅ Good
Query.insert(Product, attrs, created_by: user_id)
Query.update(product, attrs, updated_by: user_id)
Query.delete(product, deleted_by: user_id)

# ❌ Bad - no audit trail
Query.insert(Product, attrs)
Query.update(product, attrs)
```

### 5. Prefer Soft Delete

```elixir
# ✅ Good - preserves data
Query.delete(product, deleted_by: user_id)

# ⚠️ Use sparingly - permanent
Query.delete(product, hard: true)
```

## Summary

The Query API provides:

- **Builder pattern** with `Query.new/2`
- **Smart filters** with `{field, op, value, opts}`
- **Join support** with filters on joined tables
- **Soft delete** by default
- **Dual syntax** - keyword and pipe
- **Final execution** - `Repo.all()`, `Repo.one()`, `to_sql()`

**Build queries naturally. Filter intelligently. Execute simply.**
