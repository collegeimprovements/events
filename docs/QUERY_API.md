# Query API Guide

Simple CRUD helpers that compose naturally with Ecto.Query.

## Philosophy

- **Compose with `from`** - Works seamlessly with Ecto's query syntax
- **Simple functions** - No builders, no magic
- **Soft delete by default** - Automatically excludes deleted records
- **Pattern matching** - {:ok, result} | {:error, reason}

## Quick Start

```elixir
alias Events.Repo.Query
import Ecto.Query

# Compose with from
from(p in Product, where: p.status == "active")
|> Query.all()

# Pipe through helpers
Product
|> Query.where(status: "active", type: "widget")
|> Query.order_by(desc: :inserted_at)
|> Query.limit(10)
|> Query.all()

# CRUD operations
{:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)
{:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)
{:ok, product} = Query.delete(product, deleted_by: user_id)
```

## Querying Records

### Basic Queries

```elixir
# All records (excludes soft-deleted by default)
Query.all(Product)

# With Ecto query
from(p in Product, where: p.status == "active")
|> Query.all()

# With keyword where
Query.all(Product, where: [status: "active", type: "widget"])

# Include soft-deleted
Query.all(Product, include_deleted: true)
```

### Composable Helpers

```elixir
# Chain helpers
Product
|> Query.where(status: "active")
|> Query.where(type: "widget")
|> Query.order_by(desc: :inserted_at)
|> Query.limit(10)
|> Query.all()

# Mix with from
from(p in Product, where: p.price > 10)
|> Query.where(status: "active")
|> Query.order_by(desc: :price)
|> Query.all()

# Pagination
Product
|> Query.where(status: "active")
|> Query.paginate(page: 2, per_page: 20)
|> Query.all()
```

### Single Record

```elixir
# One (returns nil if not found)
product = Query.one(Product, where: [slug: "my-product"])

from(p in Product, where: p.slug == ^slug)
|> Query.one()

# One! (raises if not found)
product = from(p in Product, where: p.id == ^id)
  |> Query.one!()

# Get by ID
{:ok, product} = Query.get(Product, id)
product = Query.get!(Product, id)
```

### Counting & Existence

```elixir
# Count
count = Query.count(Product)

from(p in Product, where: p.status == "active")
|> Query.count()

# Exists?
exists = from(p in Product, where: p.slug == ^slug)
  |> Query.exists?()
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
{:ok, {3, products}} = Query.insert_all(Product, [
  %{name: "Widget A", price: 9.99},
  %{name: "Widget B", price: 12.99},
  %{name: "Widget C", price: 15.99}
], created_by: user_id)
```

### Update

```elixir
# Single record
{:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)

# Update all matching query
{:ok, count} = from(p in Product, where: p.status == "draft")
  |> Query.update_all([set: [status: "published"]], updated_by: user_id)

# With keyword where
{:ok, count} = Query.update_all(Product, [set: [status: "published"]],
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

# Delete all matching query
{:ok, count} = from(p in Product, where: p.status == "draft")
  |> Query.delete_all(deleted_by: user_id)

# Hard delete all
{:ok, count} = from(p in Product, where: p.status == "draft")
  |> Query.delete_all(hard: true)
```

### Restore

```elixir
# Single record
{:ok, product} = Query.restore(product)

# Restore all matching query
{:ok, count} = from(p in Product, where: p.type == "widget")
  |> Query.restore_all()

# With keyword where
{:ok, count} = Query.restore_all(Product, where: [type: "widget"])
```

## Soft Delete Scopes

```elixir
# Not deleted (default behavior)
Product
|> Query.not_deleted()
|> Repo.all()

from(p in Product, where: p.status == "active")
|> Query.not_deleted()
|> Repo.all()

# Only deleted
Product
|> Query.only_deleted()
|> Repo.all()

# Active (status = active AND not deleted)
Product
|> Query.active()
|> Repo.all()
```

## Transactions

```elixir
{:ok, product} = Query.transaction(fn ->
  with {:ok, product} <- Query.insert(Product, %{name: "Widget"}, created_by: user_id),
       {:ok, _} <- Query.update(category, %{product_count: count + 1}, updated_by: user_id) do
    {:ok, product}
  end
end)
```

## Aggregations

```elixir
# Sum
total = from(o in Order, where: o.status == "completed")
  |> Query.sum(:total)

# Average
avg_price = Product
  |> Query.not_deleted()
  |> Query.avg(:price)

# Min/Max
min_price = Product |> Query.min(:price)
max_price = Product |> Query.max(:price)
```

## Context Pattern

```elixir
defmodule Events.Products do
  alias Events.Product
  alias Events.Repo
  alias Events.Repo.Query
  import Ecto.Query

  def list_products(opts \\ []) do
    Product
    |> Query.not_deleted()
    |> apply_filters(opts)
    |> Query.all()
  end

  def list_products_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    query = Product
    |> Query.not_deleted()
    |> apply_filters(opts)

    products = query
    |> Query.paginate(page: page, per_page: per_page)
    |> Query.all()

    total = Query.count(query)

    %{
      entries: products,
      page: page,
      per_page: per_page,
      total_count: total,
      total_pages: ceil(total / per_page)
    }
  end

  def get_product(id) do
    Query.get(Product, id)
  end

  def get_product!(id) do
    Query.get!(Product, id)
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
    from(p in Product, where: p.id in ^product_ids, where: p.status == "draft")
    |> Query.update_all([set: [status: "published"]], opts)
  end

  # Private helpers
  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, q -> Query.where(q, status: status)
      {:type, type}, q -> Query.where(q, type: type)
      {:min_price, min}, q -> from(p in q, where: p.price >= ^min)
      {:max_price, max}, q -> from(p in q, where: p.price <= ^max)
      {:order, order}, q -> Query.order_by(q, order)
      _, q -> q
    end)
  end
end
```

### Usage

```elixir
# List products
products = Products.list_products(status: "active", type: "widget")

# Paginated
%{entries: products, total_count: total} = Products.list_products_paginated(
  page: 2,
  per_page: 20,
  status: "active"
)

# Get one
{:ok, product} = Products.get_product(id)
product = Products.get_product!(id)

# Create
{:ok, product} = Products.create_product(%{name: "Widget"}, created_by: user_id)

# Update
{:ok, product} = Products.update_product(product, %{price: 19.99}, updated_by: user_id)

# Delete
{:ok, product} = Products.delete_product(product, deleted_by: user_id)

# Bulk operations
{:ok, count} = Products.publish_products([id1, id2, id3], updated_by: user_id)
```

## Complex Queries

### JSONB Queries

```elixir
# JSONB contains
from(p in Product,
  where: fragment("? @> ?", p.metadata, ^%{featured: true})
)
|> Query.all()

# JSONB has key
from(p in Product,
  where: fragment("? ? ?", p.metadata, "?", "video_url")
)
|> Query.all()
```

### Joins

```elixir
from(p in Product,
  join: c in assoc(p, :category),
  where: c.name == "Electronics",
  where: p.price > 10
)
|> Query.not_deleted()
|> Query.all()
```

### Subqueries

```elixir
expensive_products = from(p in Product,
  where: p.price > 100,
  select: p.id
)

from(o in Order,
  where: o.product_id in subquery(expensive_products)
)
|> Query.all()
```

### Aggregations with Group By

```elixir
from(p in Product,
  group_by: p.type,
  select: {p.type, count(p.id), avg(p.price)}
)
|> Query.not_deleted()
|> Repo.all()
```

## Helper Functions

All these functions are composable and work with both schemas and queries:

### Query Builders
- `Query.where(queryable, keyword)` - Add where conditions
- `Query.limit(queryable, integer)` - Limit results
- `Query.offset(queryable, integer)` - Offset results
- `Query.order_by(queryable, keyword)` - Order results
- `Query.preload(queryable, list)` - Preload associations
- `Query.paginate(queryable, keyword)` - Paginate results

### Fetching
- `Query.all(queryable, opts)` - Fetch all records
- `Query.one(queryable, opts)` - Fetch one record (nil if not found)
- `Query.one!(queryable, opts)` - Fetch one record (raises if not found)
- `Query.get(schema, id, opts)` - Get by ID
- `Query.get!(schema, id, opts)` - Get by ID (raises if not found)
- `Query.count(queryable, opts)` - Count records
- `Query.exists?(queryable, opts)` - Check existence

### CRUD
- `Query.insert(schema, attrs, opts)` - Insert record
- `Query.insert_all(schema, records, opts)` - Insert multiple
- `Query.update(struct, attrs, opts)` - Update record
- `Query.update_all(queryable, updates, opts)` - Update all matching
- `Query.delete(struct, opts)` - Delete record
- `Query.delete_all(queryable, opts)` - Delete all matching
- `Query.restore(struct)` - Restore soft-deleted record
- `Query.restore_all(queryable, opts)` - Restore all matching
- `Query.transaction(fun)` - Run in transaction

### Scopes
- `Query.not_deleted(queryable)` - Exclude soft-deleted
- `Query.only_deleted(queryable)` - Only soft-deleted
- `Query.active(queryable)` - Active and not deleted

### Aggregations
- `Query.sum(queryable, field)` - Sum field values
- `Query.avg(queryable, field)` - Average field values
- `Query.min(queryable, field)` - Minimum value
- `Query.max(queryable, field)` - Maximum value

## Best Practices

### 1. Use `from` for Complex Queries

```elixir
# ✅ Good - clear and expressive
from(p in Product,
  where: p.price > 10,
  where: p.price < 100,
  where: fragment("? @> ?", p.metadata, ^%{featured: true})
)
|> Query.not_deleted()
|> Query.all()

# ❌ Less ideal - harder to express complex conditions
Product
|> Query.where(status: "active")
|> Query.all()
```

### 2. Compose Naturally

```elixir
# ✅ Good - compose Ecto queries with Query helpers
from(p in Product, where: p.price > 10)
|> Query.where(status: "active")
|> Query.order_by(desc: :price)
|> Query.limit(10)
|> Query.all()
```

### 3. Always Use Audit Fields

```elixir
# ✅ Good
Query.insert(Product, attrs, created_by: user_id)
Query.update(product, attrs, updated_by: user_id)
Query.delete(product, deleted_by: user_id)

# ❌ Bad - no audit trail
Query.insert(Product, attrs)
Query.update(product, attrs)
```

### 4. Soft Delete by Default

```elixir
# ✅ Good - can be restored
Query.delete(product, deleted_by: user_id)

# ⚠️ Use sparingly - permanent
Query.delete(product, hard: true)
```

### 5. Use Transactions

```elixir
# ✅ Good - atomic
Query.transaction(fn ->
  with {:ok, order} <- Query.insert(Order, attrs, created_by: user_id),
       {:ok, _} <- Query.update(product, %{stock: stock - 1}, updated_by: user_id) do
    {:ok, order}
  end
end)
```

### 6. Pattern Match Results

```elixir
# ✅ Good
case Query.get(Product, id) do
  {:ok, product} -> # use product
  {:error, :not_found} -> # handle not found
end

# ✅ Also good with `with`
with {:ok, product} <- Query.get(Product, id),
     {:ok, updated} <- Query.update(product, attrs, updated_by: user_id) do
  {:ok, updated}
end
```

## Summary

The Query API provides simple helpers that compose naturally with Ecto.Query:

- **Compose with `from`** - Use Ecto's powerful query syntax
- **Pipe through helpers** - Chain operations naturally
- **Soft delete aware** - Automatically excludes deleted records
- **Simple CRUD** - Insert, update, delete with audit tracking
- **Pattern matching** - {:ok, result} | {:error, reason}
- **Keyword opts** - All options via keyword lists

**Write queries the Ecto way. Let Query handle the rest.**
