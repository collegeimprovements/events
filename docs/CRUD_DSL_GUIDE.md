# CRUD DSL Guide

A comprehensive guide to using the SQL DSL for CRUD operations with built-in support for soft delete, SQL scopes, and transactional operations.

## Table of Contents

1. [Overview](#overview)
2. [Core Modules](#core-modules)
3. [Basic CRUD Operations](#basic-crud-operations)
4. [Soft Delete](#soft-delete)
5. [Query Building](#query-building)
6. [Transactions](#transactions)
7. [Advanced Patterns](#advanced-patterns)
8. [Best Practices](#best-practices)

---

## Overview

The CRUD DSL provides a fluent, chainable API for database operations with:

- **Type-safe queries** using the Scope DSL
- **Soft delete by default** with easy restoration
- **Automatic audit tracking** (created_by, updated_by, deleted_by)
- **Transaction support** with Ecto.Multi integration
- **Composable query building** with pagination and aggregations

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Application Layer                   │
└─────────────────┬───────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌────────┐  ┌──────────┐  ┌──────────────┐
│  Crud  │  │  Query   │  │ Transaction  │
│        │  │ Builder  │  │   Builder    │
└────┬───┘  └────┬─────┘  └──────┬───────┘
     │           │               │
     └───────────┼───────────────┘
                 │
         ┌───────┴────────┐
         │                │
         ▼                ▼
    ┌────────┐      ┌──────────┐
    │ Scope  │      │  Soft    │
    │  DSL   │      │ Delete   │
    └────────┘      └──────────┘
         │                │
         └────────┬───────┘
                  │
                  ▼
         ┌────────────────┐
         │   Ecto.Repo    │
         └────────────────┘
```

---

## Core Modules

### 1. `Events.Repo.Crud`

Low-level CRUD operations with scope support.

```elixir
alias Events.Repo.Crud
alias Events.Repo.SqlScope.Scope

# Create
{:ok, product} = Crud.new(Product)
  |> Crud.insert(%{name: "Widget", price: 9.99}, created_by: user_id)
  |> Crud.execute()

# Read
{:ok, products} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.active() end)
  |> Crud.select()
  |> Crud.execute()

# Update
{:ok, _} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", id) end)
  |> Crud.update(%{price: 12.99}, updated_by: user_id)
  |> Crud.execute()

# Delete (soft)
{:ok, _} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", id) end)
  |> Crud.delete(deleted_by: user_id)
  |> Crud.execute()
```

### 2. `Events.Repo.QueryBuilder`

High-level query building with intuitive API.

```elixir
alias Events.Repo.QueryBuilder

# Simple query
products = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.all()

# Complex query with pagination
%{entries: products, metadata: meta} = QueryBuilder.new(Product)
  |> QueryBuilder.scope(fn s ->
    s
    |> Scope.status("published")
    |> Scope.gte("price", 10.00)
    |> Scope.jsonb_eq("metadata", ["featured"], true)
  end)
  |> QueryBuilder.order_by(desc: :inserted_at)
  |> QueryBuilder.paginate_with_metadata(page: 1, per_page: 20)
```

### 3. `Events.Repo.SoftDelete`

Soft delete lifecycle management.

```elixir
alias Events.Repo.SoftDelete

# Soft delete
{:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: user_id)

# Restore
{:ok, restored} = SoftDelete.restore(product)

# Query deleted records
deleted_products = Product
  |> SoftDelete.only_deleted()
  |> Repo.all()

# Purge old deleted records
{:ok, %{count: purged}} = SoftDelete.purge_deleted(Product, days: 90)
```

### 4. `Events.Repo.TransactionBuilder`

Multi-step transactional operations.

```elixir
alias Events.Repo.TransactionBuilder

{:ok, %{order: order, items: items}} = TransactionBuilder.new()
  |> TransactionBuilder.insert(:order, Order, %{
    customer_id: customer_id,
    total: 99.99
  }, created_by: user_id)
  |> TransactionBuilder.insert_all(:items, OrderItem, fn %{order: order} ->
    [
      %{order_id: order.id, product_id: p1_id, quantity: 2},
      %{order_id: order.id, product_id: p2_id, quantity: 1}
    ]
  end, created_by: user_id)
  |> TransactionBuilder.update_all(:update_stock, Product, fn scope ->
    scope |> Scope.in_list("id", [p1_id, p2_id])
  end, %{reserved: true}, updated_by: user_id)
  |> TransactionBuilder.execute()
```

---

## Basic CRUD Operations

### Creating Records

#### Single Insert

```elixir
# Basic insert
{:ok, product} = Crud.new(Product)
  |> Crud.insert(%{name: "Widget", price: 9.99}, created_by: user_id)
  |> Crud.execute()

# Insert with all standard fields
{:ok, product} = Crud.new(Product)
  |> Crud.insert(%{
    name: "Premium Widget",
    slug: "premium-widget",
    description: "A high-quality widget",
    status: "active",
    type: "physical",
    subtype: "gadget",
    price: 29.99,
    metadata: %{
      featured: true,
      color: "blue",
      weight: 1.5
    }
  }, created_by: user_id)
  |> Crud.execute()
```

#### Bulk Insert

```elixir
{:ok, %{count: count, records: products}} = Crud.new(Product)
  |> Crud.insert_all([
    %{name: "Widget A", price: 9.99},
    %{name: "Widget B", price: 12.99},
    %{name: "Widget C", price: 15.99}
  ], created_by: user_id)
  |> Crud.execute()

# count = 3
# records = [%Product{}, %Product{}, %Product{}]
```

### Reading Records

#### Basic Select

```elixir
# Get all active records
{:ok, products} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.active() end)
  |> Crud.select()
  |> Crud.execute()

# Get single record
{:ok, product} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
  |> Crud.select_one()
  |> Crud.execute()
```

#### With Scopes

```elixir
# Complex filtering
{:ok, products} = Crud.new(Product)
  |> Crud.where(fn scope ->
    scope
    |> Scope.active()
    |> Scope.status("published")
    |> Scope.type("physical")
    |> Scope.between("price", 10.00, 50.00)
    |> Scope.jsonb_eq("metadata", ["featured"], true)
  end)
  |> Crud.select()
  |> Crud.execute()
```

#### With QueryBuilder

```elixir
# Using the higher-level QueryBuilder
products = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.scope(fn s -> s |> Scope.status("published") end)
  |> QueryBuilder.preload([:category, :tags])
  |> QueryBuilder.order_by([desc: :inserted_at])
  |> QueryBuilder.limit(20)
  |> QueryBuilder.all()

# Find by ID
{:ok, product} = QueryBuilder.new(Product)
  |> QueryBuilder.find(product_id)

# Find by field
{:ok, product} = QueryBuilder.new(Product)
  |> QueryBuilder.find_by(slug: "my-product")
```

### Updating Records

#### Single Update

```elixir
# Update by scope
{:ok, product} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
  |> Crud.update(%{price: 19.99}, updated_by: user_id)
  |> Crud.execute()

# Update struct directly
{:ok, updated} = Crud.new(Product)
  |> Crud.update(product, %{price: 19.99}, updated_by: user_id)
  |> Crud.execute()
```

#### Bulk Update

```elixir
# Update all matching records
{:ok, %{count: updated_count}} = Crud.new(Product)
  |> Crud.where(fn scope ->
    scope
    |> Scope.status("draft")
    |> Scope.type("digital")
  end)
  |> Crud.update_all(%{status: "published"}, updated_by: user_id)
  |> Crud.execute()
```

### Deleting Records

#### Soft Delete (Default)

```elixir
# Soft delete by scope
{:ok, %{count: deleted}} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
  |> Crud.delete(deleted_by: user_id)
  |> Crud.execute()

# Soft delete with SoftDelete module
{:ok, product} = SoftDelete.soft_delete(product, deleted_by: user_id)
# product.deleted_at = ~U[2024-01-15 10:30:00.123456Z]
# product.deleted_by_urm_id = user_id
```

#### Hard Delete (Permanent)

```elixir
# Permanent deletion - use with caution!
{:ok, %{count: deleted}} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
  |> Crud.delete(hard: true)
  |> Crud.execute()

# Hard delete with SoftDelete module
{:ok, product} = SoftDelete.hard_delete(product)
```

#### Restoring Deleted Records

```elixir
# Restore single record
{:ok, %{count: restored}} = Crud.new(Product)
  |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
  |> Crud.restore()
  |> Crud.execute()

# Restore with SoftDelete module
{:ok, product} = SoftDelete.restore(product)
# product.deleted_at = nil
# product.deleted_by_urm_id = nil

# Restore multiple records
{:ok, %{count: count}} = SoftDelete.restore_all(
  Product |> where([p], p.type == "widget")
)
```

---

## Soft Delete

### Setup

Add soft delete fields to your migration:

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:products) do
      add :name, :citext, null: false
      add :slug, :citext, null: false
      add :price, :decimal, null: false

      status_field()
      type_fields()
      metadata_field()
      audit_fields()
      deleted_fields()  # Adds deleted_at and deleted_by_urm_id
      timestamps()
    end

    # Recommended indexes
    create unique_index(:products, [:slug])
    create index(:products, [:deleted_at])
    create index(:products, [:status], where: "deleted_at IS NULL")
  end
end
```

### Schema Setup

```elixir
defmodule Events.Product do
  use Ecto.Schema
  import Events.Repo.SoftDelete

  schema "products" do
    field :name, :string
    field :slug, :string
    field :price, :decimal
    field :status, :string
    field :type, :string
    field :subtype, :string
    field :metadata, :map

    field :created_by_urm_id, :binary_id
    field :updated_by_urm_id, :binary_id
    field :deleted_at, :utc_datetime_usec
    field :deleted_by_urm_id, :binary_id

    timestamps()
  end

  # Default scope excludes deleted records
  def base_query do
    not_deleted(__MODULE__)
  end
end
```

### Lifecycle Operations

```elixir
# Create → Active → Soft Delete → Restore → Active
# Create → Active → Hard Delete → [GONE]

# 1. Create
{:ok, product} = Crud.new(Product)
  |> Crud.insert(%{name: "Widget", price: 9.99}, created_by: user_id)
  |> Crud.execute()

# 2. Soft Delete
{:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: user_id)

# 3. Check status
SoftDelete.deleted?(deleted)  # => true
SoftDelete.active?(deleted)   # => false

# 4. Restore
{:ok, restored} = SoftDelete.restore(deleted)

# 5. Check status again
SoftDelete.deleted?(restored)  # => false
SoftDelete.active?(restored)   # => true
```

### Querying Deleted Records

```elixir
# Only active (default)
active_products = Product
  |> SoftDelete.not_deleted()
  |> Repo.all()

# Only deleted
deleted_products = Product
  |> SoftDelete.only_deleted()
  |> Repo.all()

# All records (active + deleted)
all_products = Product
  |> SoftDelete.with_deleted()
  |> Repo.all()

# Using QueryBuilder
active = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.all()

deleted = QueryBuilder.new(Product)
  |> QueryBuilder.only_deleted()
  |> QueryBuilder.all()

all = QueryBuilder.new(Product)
  |> QueryBuilder.with_deleted()
  |> QueryBuilder.all()
```

### Bulk Operations

```elixir
# Soft delete all matching records
{:ok, %{count: count}} = SoftDelete.soft_delete_all(
  Product |> where([p], p.status == "draft"),
  deleted_by: user_id
)

# Restore all matching records
{:ok, %{count: count}} = SoftDelete.restore_all(
  Product |> where([p], p.type == "widget")
)

# Hard delete all matching records (use with caution!)
{:ok, %{count: count}} = SoftDelete.hard_delete_all(
  Product |> where([p], p.deleted_at < ago(90, "day"))
)
```

### Cleanup Operations

```elixir
# Purge deleted records older than 90 days
{:ok, %{count: purged}} = SoftDelete.purge_deleted(Product, days: 90)

# Other time units
{:ok, %{count: purged}} = SoftDelete.purge_deleted(Product, hours: 24)
{:ok, %{count: purged}} = SoftDelete.purge_deleted(Product, weeks: 12)
{:ok, %{count: purged}} = SoftDelete.purge_deleted(Product, months: 6)
{:ok, %{count: purged}} = SoftDelete.purge_deleted(Product, years: 1)
```

### Statistics

```elixir
# Get deletion statistics
stats = SoftDelete.deletion_stats(Product)
# => %{
#   total: 100,
#   active: 85,
#   deleted: 15,
#   deletion_rate: 0.15
# }

# Get recently deleted records
recent = SoftDelete.recently_deleted(Product, limit: 20)
```

---

## Query Building

### Pagination

```elixir
# Basic pagination
products = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.order_by(desc: :inserted_at)
  |> QueryBuilder.paginate(page: 2, per_page: 20)
  |> QueryBuilder.all()

# Pagination with metadata
%{entries: products, metadata: meta} = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.paginate_with_metadata(page: 2, per_page: 20)

# meta = %{
#   page: 2,
#   per_page: 20,
#   total_count: 150,
#   total_pages: 8,
#   has_prev: true,
#   has_next: true
# }
```

### Aggregations

```elixir
# Count
count = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.count()

# Sum
total_revenue = QueryBuilder.new(Order)
  |> QueryBuilder.scope(fn s -> s |> Scope.status("completed") end)
  |> QueryBuilder.sum(:total)

# Average
avg_price = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.avg(:price)

# Min/Max
min_price = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.min(:price)

max_price = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.max(:price)

# Existence check
exists = QueryBuilder.new(Product)
  |> QueryBuilder.scope(fn s -> s |> Scope.eq("slug", "my-product") end)
  |> QueryBuilder.exists?()
```

### Complex Queries

```elixir
# Multi-condition query with JSONB
products = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.scope(fn s ->
    s
    |> Scope.status("published")
    |> Scope.type("physical")
    |> Scope.between("price", 10.00, 100.00)
    |> Scope.jsonb_eq("metadata", ["featured"], true)
    |> Scope.jsonb_has_key("metadata", "video_url")
    |> Scope.or_where(fn or_scope ->
      or_scope
      |> Scope.eq("category", "electronics")
      |> Scope.gte("rating", 4.5)
    end)
  end)
  |> QueryBuilder.preload([:category, :reviews])
  |> QueryBuilder.order_by([desc: :featured_at, desc: :rating, asc: :name])
  |> QueryBuilder.limit(50)
  |> QueryBuilder.all()
```

---

## Transactions

### Basic Transactions

```elixir
# Simple multi-step transaction
{:ok, %{order: order, payment: payment}} = TransactionBuilder.new()
  |> TransactionBuilder.insert(:order, Order, %{
    customer_id: customer_id,
    total: 99.99,
    status: "pending"
  }, created_by: user_id)
  |> TransactionBuilder.insert(:payment, Payment, fn %{order: order} ->
    %{
      order_id: order.id,
      amount: order.total,
      status: "processing"
    }
  end, created_by: user_id)
  |> TransactionBuilder.execute()
```

### Complex Transactions

```elixir
# E-commerce order processing
{:ok, results} = TransactionBuilder.new()
  # 1. Create order
  |> TransactionBuilder.insert(:order, Order, %{
    customer_id: customer_id,
    total: 149.99,
    status: "pending"
  }, created_by: customer_id)

  # 2. Create order items
  |> TransactionBuilder.insert_all(:items, OrderItem, fn %{order: order} ->
    [
      %{order_id: order.id, product_id: product1_id, quantity: 2, price: 29.99},
      %{order_id: order.id, product_id: product2_id, quantity: 1, price: 89.99}
    ]
  end, created_by: customer_id)

  # 3. Update product stock
  |> TransactionBuilder.update_all(:update_stock, Product, fn scope ->
    scope |> Scope.in_list("id", [product1_id, product2_id])
  end, %{reserved: true}, updated_by: system_id)

  # 4. Create payment record
  |> TransactionBuilder.insert(:payment, Payment, fn %{order: order} ->
    %{
      order_id: order.id,
      amount: order.total,
      method: "credit_card",
      status: "processing"
    }
  end, created_by: customer_id)

  # 5. Process payment (custom function)
  |> TransactionBuilder.run(:process_payment, fn %{payment: payment} ->
    PaymentGateway.charge(payment.amount, payment.method)
  end)

  # 6. Update order status
  |> TransactionBuilder.update(:finalize_order, fn %{order: order} ->
    order
  end, %{status: "confirmed"}, updated_by: system_id)

  # 7. Send confirmation email
  |> TransactionBuilder.tap(:send_email, fn %{order: order} ->
    OrderMailer.send_confirmation(order)
  end)

  |> TransactionBuilder.execute()
```

### Conditional Transactions

```elixir
# Conditional steps based on static conditions
{:ok, _} = TransactionBuilder.new()
  |> TransactionBuilder.insert(:user, User, user_attrs, created_by: admin_id)
  |> TransactionBuilder.when(send_welcome_email?, fn multi ->
    TransactionBuilder.run(multi, :send_email, fn %{user: user} ->
      Email.send_welcome(user)
    end)
  end)
  |> TransactionBuilder.execute()

# Conditional steps based on previous results
{:ok, _} = TransactionBuilder.new()
  |> TransactionBuilder.insert(:order, Order, %{total: 150}, created_by: user_id)
  |> TransactionBuilder.when_result(:order, fn order ->
    order.total > 100
  end, fn multi ->
    TransactionBuilder.run(multi, :apply_discount, fn %{order: order} ->
      # Apply 10% bulk order discount
      {:ok, order}
    end)
  end)
  |> TransactionBuilder.execute()
```

### Transaction Error Handling

```elixir
case TransactionBuilder.new()
  |> TransactionBuilder.insert(:product, Product, attrs, created_by: user_id)
  |> TransactionBuilder.update_all(:update_category, Category, fn scope ->
    scope |> Scope.eq("id", category_id)
  end, %{product_count: fragment("product_count + 1")}, updated_by: user_id)
  |> TransactionBuilder.execute() do

  {:ok, %{product: product, update_category: _}} ->
    Logger.info("Created product: #{product.id}")
    {:ok, product}

  {:error, :product, changeset, _changes} ->
    Logger.error("Failed to create product: #{inspect(changeset.errors)}")
    {:error, changeset}

  {:error, :update_category, error, _changes} ->
    Logger.error("Failed to update category: #{inspect(error)}")
    {:error, :category_update_failed}
end
```

---

## Advanced Patterns

### Repository Pattern

Create a context module with common queries:

```elixir
defmodule Events.Products do
  alias Events.Product
  alias Events.Repo.{QueryBuilder, Crud, TransactionBuilder}
  alias Events.Repo.SqlScope.Scope

  # List products with filters
  def list_products(filters \\ []) do
    QueryBuilder.new(Product)
    |> apply_filters(filters)
    |> QueryBuilder.all()
  end

  # Get paginated products
  def list_products_paginated(page, per_page, filters \\ []) do
    QueryBuilder.new(Product)
    |> apply_filters(filters)
    |> QueryBuilder.order_by(desc: :inserted_at)
    |> QueryBuilder.paginate_with_metadata(page: page, per_page: per_page)
  end

  # Find product by ID
  def get_product(id) do
    QueryBuilder.new(Product)
    |> QueryBuilder.find(id)
  end

  # Find product by slug
  def get_product_by_slug(slug) do
    QueryBuilder.new(Product)
    |> QueryBuilder.find_by(slug: slug)
  end

  # Create product
  def create_product(attrs, created_by: user_id) do
    Crud.new(Product)
    |> Crud.insert(attrs, created_by: user_id)
    |> Crud.execute()
  end

  # Update product
  def update_product(product, attrs, updated_by: user_id) do
    Crud.new(Product)
    |> Crud.update(product, attrs, updated_by: user_id)
    |> Crud.execute()
  end

  # Soft delete product
  def delete_product(product, deleted_by: user_id) do
    SoftDelete.soft_delete(product, deleted_by: user_id)
  end

  # Publish products in bulk
  def publish_products(product_ids, user_id) do
    Crud.new(Product)
    |> Crud.where(fn scope ->
      scope
      |> Scope.in_list("id", product_ids)
      |> Scope.status("draft")
    end)
    |> Crud.update_all(%{status: "published"}, updated_by: user_id)
    |> Crud.execute()
  end

  # Private helpers
  defp apply_filters(qb, filters) do
    qb
    |> QueryBuilder.active()
    |> apply_status_filter(filters[:status])
    |> apply_type_filter(filters[:type])
    |> apply_price_range(filters[:min_price], filters[:max_price])
    |> apply_featured_filter(filters[:featured])
  end

  defp apply_status_filter(qb, nil), do: qb
  defp apply_status_filter(qb, status) do
    QueryBuilder.scope(qb, fn s -> Scope.status(s, status) end)
  end

  defp apply_type_filter(qb, nil), do: qb
  defp apply_type_filter(qb, type) do
    QueryBuilder.scope(qb, fn s -> Scope.type(s, type) end)
  end

  defp apply_price_range(qb, nil, nil), do: qb
  defp apply_price_range(qb, min, nil) do
    QueryBuilder.scope(qb, fn s -> Scope.gte(s, "price", min) end)
  end
  defp apply_price_range(qb, nil, max) do
    QueryBuilder.scope(qb, fn s -> Scope.lte(s, "price", max) end)
  end
  defp apply_price_range(qb, min, max) do
    QueryBuilder.scope(qb, fn s -> Scope.between(s, "price", min, max) end)
  end

  defp apply_featured_filter(qb, nil), do: qb
  defp apply_featured_filter(qb, true) do
    QueryBuilder.scope(qb, fn s -> Scope.featured(s) end)
  end
  defp apply_featured_filter(qb, false), do: qb
end
```

### Scoped Queries

Define common scopes for reuse:

```elixir
defmodule Events.ProductScopes do
  alias Events.Repo.SqlScope.Scope

  def published(scope \\ Scope.new()) do
    scope
    |> Scope.active()
    |> Scope.status("published")
  end

  def featured(scope \\ Scope.new()) do
    scope
    |> published()
    |> Scope.jsonb_eq("metadata", ["featured"], true)
  end

  def in_price_range(scope \\ Scope.new(), min, max) do
    scope
    |> Scope.gte("price", min)
    |> Scope.lte("price", max)
  end

  def by_category(scope \\ Scope.new(), category) do
    Scope.eq(scope, "category", category)
  end

  def high_rated(scope \\ Scope.new(), min_rating \\ 4.0) do
    Scope.gte(scope, "rating", min_rating)
  end
end

# Usage
products = QueryBuilder.new(Product)
  |> QueryBuilder.scope(&ProductScopes.featured/1)
  |> QueryBuilder.scope(fn s -> ProductScopes.in_price_range(s, 10, 100) end)
  |> QueryBuilder.all()
```

---

## Best Practices

### 1. Always Use Audit Fields

```elixir
# ✅ Good - includes audit info
Crud.new(Product)
|> Crud.insert(%{name: "Widget"}, created_by: current_user_id)
|> Crud.execute()

# ❌ Bad - no audit trail
Crud.new(Product)
|> Crud.insert(%{name: "Widget"})
|> Crud.execute()
```

### 2. Prefer Soft Delete

```elixir
# ✅ Good - soft delete (can be restored)
Crud.new(Product)
|> Crud.where(fn s -> Scope.eq(s, "id", id) end)
|> Crud.delete(deleted_by: user_id)
|> Crud.execute()

# ⚠️ Use with caution - permanent deletion
Crud.new(Product)
|> Crud.where(fn s -> Scope.eq(s, "id", id) end)
|> Crud.delete(hard: true)
|> Crud.execute()
```

### 3. Use Transactions for Multi-Step Operations

```elixir
# ✅ Good - atomic operation
TransactionBuilder.new()
|> TransactionBuilder.insert(:order, Order, order_attrs, created_by: user_id)
|> TransactionBuilder.update_all(:reserve_stock, Product, fn s ->
  Scope.eq(s, "id", product_id)
end, %{reserved: true}, updated_by: user_id)
|> TransactionBuilder.execute()

# ❌ Bad - not atomic (can leave inconsistent state)
{:ok, order} = Crud.new(Order)
  |> Crud.insert(order_attrs, created_by: user_id)
  |> Crud.execute()

Crud.new(Product)  # If this fails, order is created but stock not reserved!
|> Crud.where(fn s -> Scope.eq(s, "id", product_id) end)
|> Crud.update_all(%{reserved: true}, updated_by: user_id)
|> Crud.execute()
```

### 4. Use QueryBuilder for Reads

```elixir
# ✅ Good - clean and readable
products = QueryBuilder.new(Product)
  |> QueryBuilder.active()
  |> QueryBuilder.scope(fn s -> Scope.status(s, "published") end)
  |> QueryBuilder.order_by(desc: :inserted_at)
  |> QueryBuilder.limit(10)
  |> QueryBuilder.all()

# ❌ Less ideal - more verbose
{:ok, products} = Crud.new(Product)
  |> Crud.where(fn s ->
    s |> Scope.active() |> Scope.status("published")
  end)
  |> Crud.select()
  |> Crud.limit(10)
  |> Crud.order_by(desc: :inserted_at)
  |> Crud.execute()
```

### 5. Handle Errors Properly

```elixir
# ✅ Good - proper error handling
case Crud.new(Product)
  |> Crud.insert(attrs, created_by: user_id)
  |> Crud.execute() do

  {:ok, product} ->
    Logger.info("Created product: #{product.id}")
    {:ok, product}

  {:error, changeset} ->
    Logger.error("Failed to create product: #{inspect(changeset.errors)}")
    {:error, changeset}
end

# ❌ Bad - ignoring errors
{:ok, product} = Crud.new(Product)
  |> Crud.insert(attrs, created_by: user_id)
  |> Crud.execute()  # Will crash if insert fails!
```

### 6. Index Soft Delete Fields

```elixir
# In your migration
create index(:products, [:deleted_at])
create index(:products, [:status], where: "deleted_at IS NULL")

# This makes soft delete queries fast:
# WHERE deleted_at IS NULL
# WHERE deleted_at IS NOT NULL
# WHERE status = 'active' AND deleted_at IS NULL
```

### 7. Regular Cleanup of Deleted Records

```elixir
# Schedule periodic cleanup (e.g., in a background job)
defmodule Events.Maintenance.CleanupJob do
  def run do
    # Purge products deleted more than 90 days ago
    {:ok, %{count: count}} = SoftDelete.purge_deleted(Product, days: 90)
    Logger.info("Purged #{count} old products")

    # Repeat for other schemas
    SoftDelete.purge_deleted(Order, days: 365)
    SoftDelete.purge_deleted(Session, days: 30)
  end
end
```

### 8. Use Scopes Consistently

```elixir
# Define a base_query function in your schemas
defmodule Events.Product do
  use Ecto.Schema
  import Events.Repo.SoftDelete

  # ...

  def base_query do
    __MODULE__
    |> not_deleted()
  end

  def active_query do
    base_query()
    |> where([p], p.status == "active")
  end
end

# Use it consistently
Product.base_query() |> Repo.all()
Product.active_query() |> Repo.all()
```

---

## Summary

The CRUD DSL provides a comprehensive, type-safe way to interact with your database:

- **Crud**: Low-level CRUD operations with scope support
- **QueryBuilder**: High-level query building with intuitive API
- **SoftDelete**: Lifecycle management for soft-deleted records
- **TransactionBuilder**: Multi-step atomic operations

All modules work together seamlessly and integrate with:
- Scope DSL for type-safe filtering
- Audit fields for tracking changes
- Ecto.Multi for transactions
- PostgreSQL advanced features (JSONB, etc.)

Start with `QueryBuilder` for most reads, `Crud` for writes, and `TransactionBuilder` for complex multi-step operations.
