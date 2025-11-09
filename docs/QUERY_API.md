# Query API Guide

Simple, keyword-based database operations following Elixir conventions.

## Philosophy

- **Keyword lists everywhere** - Simple, composable, extendable
- **Pattern matching** - {:ok, result} | {:error, reason}
- **Soft delete by default** - Preserve data, restore when needed
- **Zero magic** - Just functions and keyword lists

## Quick Start

```elixir
alias Events.Repo.Query
alias Events.Repo.QueryHelpers, as: QH

# Fetch all
products = Query.all(Product, where: [status: "active"], limit: 10)

# Fetch one
{:ok, product} = Query.fetch(Product, id)
product = Query.one!(Product, where: [slug: "my-product"])

# Create
{:ok, product} = Query.insert(Product, %{
  name: "Widget",
  price: 9.99
}, created_by: user_id)

# Update
{:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)

# Delete (soft by default)
{:ok, product} = Query.delete(product, deleted_by: user_id)

# Restore
{:ok, product} = Query.restore(product)
```

## Query Functions

### Fetching Records

```elixir
# All records
products = Query.all(Product)

# With conditions
products = Query.all(Product, where: [status: "active", type: "widget"])

# With pagination
products = Query.all(Product,
  where: [status: "active"],
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
)

# With preloads
products = Query.all(Product,
  where: [status: "published"],
  preload: [:category, :tags]
)

# Single record
product = Query.one(Product, where: [id: id])  # Returns nil if not found
product = Query.one!(Product, where: [slug: "my-product"])  # Raises if not found

# By ID
{:ok, product} = Query.fetch(Product, id)
product = Query.fetch!(Product, id)

# With preloads
{:ok, product} = Query.fetch(Product, id, preload: [:category])
```

### Available Options

All query functions accept these keyword options:

- `:where` - Filter conditions (keyword list)
- `:limit` - Limit results
- `:offset` - Offset for pagination
- `:order_by` - Order results (e.g., `[desc: :inserted_at, asc: :name]`)
- `:preload` - Preload associations (e.g., `[:category, :tags]`)
- `:select` - Select specific fields
- `:include_deleted` - Include soft-deleted records (default: `false`)

### Counting & Existence

```elixir
# Count
count = Query.count(Product, where: [status: "active"])

# Exists?
exists? = Query.exists?(Product, where: [slug: "my-product"])
```

## CRUD Operations

### Insert

```elixir
# Single record
{:ok, product} = Query.insert(Product, %{
  name: "Widget",
  price: 9.99,
  status: "active"
}, created_by: user_id)

# Multiple records
{:ok, products} = Query.insert_all(Product, [
  %{name: "Widget A", price: 9.99},
  %{name: "Widget B", price: 12.99},
  %{name: "Widget C", price: 15.99}
], created_by: user_id)
```

### Update

```elixir
# Single record
{:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)

# Multiple records
{:ok, count} = Query.update_all(Product, %{status: "published"},
  where: [status: "draft"],
  updated_by: user_id
)
```

### Delete

```elixir
# Soft delete (default)
{:ok, product} = Query.delete(product, deleted_by: user_id)

# Hard delete (permanent)
{:ok, product} = Query.delete(product, hard: true)

# Soft delete multiple
{:ok, count} = Query.delete_all(Product,
  where: [status: "draft"],
  deleted_by: user_id
)

# Hard delete multiple
{:ok, count} = Query.delete_all(Product,
  where: [status: "draft"],
  hard: true
)
```

### Restore

```elixir
# Single record
{:ok, product} = Query.restore(product)

# Multiple records
{:ok, count} = Query.restore_all(Product, where: [type: "widget"])
```

## Soft Delete

### Querying Deleted Records

```elixir
# Only active (default)
products = Query.all(Product, where: [status: "active"])

# Include deleted
products = Query.all(Product,
  where: [status: "active"],
  include_deleted: true
)

# Only deleted
import Ecto.Query
products = Product |> Query.only_deleted() |> Repo.all()
```

### Using Scopes

```elixir
alias Events.Repo

# In your queries
products = Product
  |> Query.not_deleted()
  |> where([p], p.status == "active")
  |> Repo.all()

# Active scope (status = active AND not deleted)
products = Product |> Query.active() |> Repo.all()
```

## Transactions

```elixir
{:ok, product} = Query.transaction(fn ->
  with {:ok, product} <- Query.insert(Product, %{name: "Widget"}, created_by: user_id),
       {:ok, _category} <- Query.update(category, %{product_count: count + 1}, updated_by: user_id) do
    {:ok, product}
  end
end)
```

## Aggregations

```elixir
# Sum
total_revenue = Query.sum(Order, :total, where: [status: "completed"])

# Average
avg_price = Query.avg(Product, :price, where: [status: "active"])

# Min/Max
min_price = Query.min(Product, :price, where: [status: "active"])
max_price = Query.max(Product, :price, where: [status: "active"])
```

## Composable Query Helpers

Use `QueryHelpers` to build reusable query options:

```elixir
alias Events.Repo.QueryHelpers, as: QH

# Build query options
opts = []
|> QH.where(status: "active")
|> QH.where(type: "widget")
|> QH.order_by(desc: :inserted_at)
|> QH.limit(10)

products = Query.all(Product, opts)

# Pagination
opts = QH.paginate([], page: 2, per_page: 20)
products = Query.all(Product, opts)

# Get pagination metadata
total = Query.count(Product)
metadata = QH.pagination_metadata(
  page: 2,
  per_page: 20,
  total_count: total
)
# => %{page: 2, per_page: 20, total_count: 150, total_pages: 8, has_prev: true, has_next: true}
```

### Common Patterns

```elixir
# Active records
products = Query.all(Product, QH.active())

# Published records
posts = Query.all(Post, QH.published())

# Recent records (last 7 days)
products = Query.all(Product, QH.recent())

# Recent with custom days
products = Query.all(Product, QH.recent(days: 30))

# Compose multiple patterns
opts = QH.active()
  |> QH.merge(QH.recent(days: 7))
  |> QH.limit(10)

products = Query.all(Product, opts)
```

## Context Pattern

Create a context module with keyword-based functions:

```elixir
defmodule Events.Products do
  alias Events.Product
  alias Events.Repo.Query
  alias Events.Repo.QueryHelpers, as: QH

  def list_products(opts \\ []) do
    base_opts = QH.active()
    final_opts = QH.merge(base_opts, opts)

    Query.all(Product, final_opts)
  end

  def list_products_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    pagination_opts = QH.paginate([], page: page, per_page: per_page)
    query_opts = opts
      |> Keyword.delete(:page)
      |> Keyword.delete(:per_page)
      |> QH.merge(pagination_opts)

    products = list_products(query_opts)
    total = Query.count(Product, Keyword.take(opts, [:where]))

    %{
      entries: products,
      metadata: QH.pagination_metadata(
        page: page,
        per_page: per_page,
        total_count: total
      )
    }
  end

  def get_product(id, opts \\ []) do
    Query.fetch(Product, id, opts)
  end

  def get_product!(id, opts \\ []) do
    Query.fetch!(Product, id, opts)
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

  def restore_product(product) do
    Query.restore(product)
  end

  def publish_products(product_ids, opts \\ []) do
    Query.update_all(Product, %{status: "published"},
      where: [id: {:in, product_ids}, status: "draft"],
      updated_by: Keyword.get(opts, :updated_by)
    )
  end
end
```

### Usage

```elixir
# List products
products = Products.list_products(status: "active", type: "widget")

# Paginated
%{entries: products, metadata: meta} = Products.list_products_paginated(
  page: 2,
  per_page: 20,
  where: [status: "active"]
)

# Get one
{:ok, product} = Products.get_product(id)
product = Products.get_product!(id, preload: [:category])

# Create
{:ok, product} = Products.create_product(%{
  name: "Widget",
  price: 9.99
}, created_by: user_id)

# Update
{:ok, product} = Products.update_product(product, %{price: 19.99}, updated_by: user_id)

# Delete
{:ok, product} = Products.delete_product(product, deleted_by: user_id)

# Bulk operations
{:ok, count} = Products.publish_products([id1, id2, id3], updated_by: user_id)
```

## Advanced Ecto Queries

For complex queries, use Ecto.Query directly and compose with Query helpers:

```elixir
import Ecto.Query

# Complex filtering
products = from(p in Product,
  where: p.price >= 10 and p.price <= 100,
  where: fragment("? @> ?", p.metadata, ^%{featured: true}),
  order_by: [desc: p.inserted_at]
)
|> Query.not_deleted()
|> Repo.all()

# Joins
products = from(p in Product,
  join: c in assoc(p, :category),
  where: c.name == "Electronics",
  where: p.status == "active"
)
|> Query.not_deleted()
|> Repo.all()

# Aggregations
stats = from(p in Product,
  where: p.status == "active",
  group_by: p.type,
  select: {p.type, count(p.id), avg(p.price)}
)
|> Query.not_deleted()
|> Repo.all()
```

## Best Practices

### 1. Always Use Audit Fields

```elixir
# ✅ Good
Query.insert(Product, %{name: "Widget"}, created_by: user_id)
Query.update(product, %{price: 19.99}, updated_by: user_id)
Query.delete(product, deleted_by: user_id)

# ❌ Bad
Query.insert(Product, %{name: "Widget"})
Query.update(product, %{price: 19.99})
```

### 2. Prefer Soft Delete

```elixir
# ✅ Good - can be restored
Query.delete(product, deleted_by: user_id)

# ⚠️ Use sparingly - permanent
Query.delete(product, hard: true)
```

### 3. Use Transactions for Multi-Step Operations

```elixir
# ✅ Good - atomic
Query.transaction(fn ->
  with {:ok, order} <- Query.insert(Order, attrs, created_by: user_id),
       {:ok, _} <- Query.update(product, %{stock: stock - 1}, updated_by: user_id) do
    {:ok, order}
  end
end)

# ❌ Bad - not atomic
{:ok, order} = Query.insert(Order, attrs, created_by: user_id)
{:ok, _} = Query.update(product, %{stock: stock - 1}, updated_by: user_id)
```

### 4. Build Composable Query Options

```elixir
# ✅ Good - composable and reusable
defp base_query_opts do
  QH.active()
  |> QH.order_by(desc: :inserted_at)
end

defp apply_filters(opts, filters) do
  Enum.reduce(filters, opts, fn
    {:status, status}, acc -> QH.where(acc, status: status)
    {:type, type}, acc -> QH.where(acc, type: type)
    {:limit, limit}, acc -> QH.limit(acc, limit)
    _, acc -> acc
  end)
end

# ❌ Bad - hard to reuse
def list_products(status, type, limit) do
  Query.all(Product,
    where: [status: status, type: type],
    limit: limit,
    order_by: [desc: :inserted_at]
  )
end
```

### 5. Use Pattern Matching

```elixir
# ✅ Good
case Query.fetch(Product, id) do
  {:ok, product} ->
    # Use product
  {:error, :not_found} ->
    # Handle not found
end

# ✅ Also good with `with`
with {:ok, product} <- Query.fetch(Product, id),
     {:ok, updated} <- Query.update(product, attrs, updated_by: user_id) do
  {:ok, updated}
end
```

### 6. Default Scopes in Contexts

```elixir
# In your context module
defp default_opts do
  QH.active() |> QH.order_by(desc: :inserted_at)
end

def list_products(opts \\ []) do
  final_opts = QH.merge(default_opts(), opts)
  Query.all(Product, final_opts)
end

# Now all queries exclude deleted by default
products = Products.list_products()
products = Products.list_products(where: [type: "widget"])
```

## Summary

The Query API provides a simple, keyword-based interface for all database operations:

- **Query.all/2** - Fetch multiple records
- **Query.one/2** - Fetch single record (nil if not found)
- **Query.one!/2** - Fetch single record (raises if not found)
- **Query.fetch/2,3** - Fetch by ID
- **Query.insert/3** - Create record
- **Query.insert_all/3** - Create multiple records
- **Query.update/3** - Update record
- **Query.update_all/3** - Update multiple records
- **Query.delete/2** - Delete record (soft by default)
- **Query.delete_all/2** - Delete multiple records
- **Query.restore/1** - Restore soft-deleted record
- **Query.restore_all/2** - Restore multiple records
- **Query.transaction/1** - Run in transaction
- **Query.count/2** - Count records
- **Query.exists?/2** - Check existence

All functions:
- Accept keyword lists for options
- Return `{:ok, result}` or `{:error, reason}`
- Support audit tracking (created_by, updated_by, deleted_by)
- Exclude soft-deleted records by default
- Are composable and reusable

**Keep it simple. Use keyword lists. Pattern match everything.**
