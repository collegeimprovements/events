# Dynamic Scope System for Migration Indexes

## Overview

A comprehensive, type-safe, chainable API for building complex WHERE clauses for partial indexes in Ecto migrations.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│           APPLICATION CONFIG LAYER                   │
│  (User-defined scopes, business logic)              │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────┐
│           SCOPE BUILDER API                          │
│  (Chainable, composable, type-safe)                 │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────┐
│           SCOPE REGISTRY                             │
│  (Named scopes, reusable patterns)                  │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────┐
│           SQL GENERATOR                              │
│  (Optimized WHERE clause generation)                │
└─────────────────────────────────────────────────────┘
```

---

## Core Concepts

### Philosophy

- **Composable**: Chain operations naturally
- **Type-safe**: Compile-time validation where possible
- **Optimizable**: Automatic clause optimization
- **Debuggable**: Clear inspection and explanation
- **Reusable**: Define once, use everywhere

---

## 1. Scope Builder API

### Basic Usage

```elixir
alias Events.Repo.Scope

# Simple scope
Scope.new()
|> Scope.active()
|> Scope.status("published")
|> Scope.to_sql()
# => "deleted_at IS NULL AND status = 'published'"

# Complex scope
Scope.new()
|> Scope.active()
|> Scope.where_any([
  Scope.new() |> Scope.status("published"),
  Scope.new() |> Scope.status("featured")
])
|> Scope.recent(7)
|> Scope.metadata(:featured, true)
|> Scope.to_sql()
```

### Available Methods

#### Soft Delete Scopes

```elixir
Scope.active()              # WHERE deleted_at IS NULL
Scope.deleted()             # WHERE deleted_at IS NOT NULL
Scope.recently_deleted(30)  # WHERE deleted_at IS NOT NULL AND deleted_at > NOW() - INTERVAL '30 days'
```

#### Field Comparisons

```elixir
Scope.where(field, value)           # field = value
Scope.where_not(field, value)       # field != value
Scope.where_gt(field, value)        # field > value
Scope.where_lt(field, value)        # field < value
Scope.where_gte(field, value)       # field >= value
Scope.where_lte(field, value)       # field <= value
Scope.where_in(field, [values])     # field IN (...)
Scope.where_not_in(field, [values]) # field NOT IN (...)
Scope.where_null(field)             # field IS NULL
Scope.where_not_null(field)         # field IS NOT NULL
Scope.where_between(field, from, to) # field BETWEEN from AND to
Scope.where_like(field, pattern)    # field LIKE pattern
Scope.where_ilike(field, pattern)   # field ILIKE pattern
```

#### Convenience Methods

```elixir
Scope.status("published")           # status = 'published'
Scope.status(["published", "draft"]) # status IN ('published', 'draft')
Scope.type("premium")               # type = 'premium'
Scope.subtype("recurring")          # subtype = 'recurring'
Scope.visibility("public")          # visibility = 'public'
Scope.public()                      # visibility = 'public'
Scope.private()                     # visibility = 'private'
Scope.visible()                     # visibility != 'hidden'
```

#### Time-Based Scopes

```elixir
Scope.recent(7)                     # inserted_at > NOW() - INTERVAL '7 days'
Scope.recent(30, :updated_at)       # updated_at > NOW() - INTERVAL '30 days'
Scope.stale(90)                     # updated_at < NOW() - INTERVAL '90 days'
Scope.future(:starts_at)            # starts_at > NOW()
Scope.past(:ends_at)                # ends_at < NOW()
Scope.current(:starts_at, :ends_at) # starts_at <= NOW() AND ends_at >= NOW()
Scope.upcoming(30)                  # starts_at > NOW() AND starts_at <= NOW() + INTERVAL '30 days'
```

#### JSONB/Metadata Scopes

```elixir
Scope.metadata("featured", true)                    # metadata->>'featured' = 'true'
Scope.metadata_exists("tags")                       # metadata ? 'tags'
Scope.metadata_contains(%{featured: true})          # metadata @> '{"featured":true}'
Scope.metadata_compare("priority", :>, 5)           # (metadata->>'priority')::int > 5
Scope.metadata_compare("rating", :>=, 4.5, :float)  # (metadata->>'rating')::float >= 4.5

# Convenience methods
Scope.featured()  # metadata->>'featured' = 'true'
Scope.enabled()   # metadata->>'enabled' = 'true'
Scope.verified()  # metadata->>'verified' = 'true'
```

#### Text Search

```elixir
Scope.search(:title, "search term")                          # Full-text search on one field
Scope.search([:title, :description], "search", "english")    # Full-text search on multiple fields
```

#### Logical Operators

```elixir
# OR - any of these conditions
Scope.where_any([
  Scope.new() |> Scope.status("published"),
  Scope.new() |> Scope.status("featured")
])
# => (status = 'published' OR status = 'featured')

# AND - all of these conditions (default behavior when chaining)
Scope.where_all([
  Scope.new() |> Scope.active(),
  Scope.new() |> Scope.status("published")
])
# => (deleted_at IS NULL AND status = 'published')

# NOT - negate a scope
Scope.where_not_scope(
  Scope.new() |> Scope.status("draft")
)
# => NOT (status = 'draft')
```

#### Raw SQL

```elixir
Scope.raw("custom_field > 100")  # Use raw SQL (with caution)
```

#### Composite Patterns

```elixir
Scope.queryable()                    # active + status IN ('active', 'published')
Scope.queryable(["published"])       # active + status IN ('published')
Scope.searchable()                   # active + published + public
Scope.hot(7)                         # active + published + recent(7)
Scope.premium()                      # active + type('premium')
```

---

## 2. Usage in Migrations

### Simple Examples

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.Scope

  def change do
    create table(:products) do
      name_fields()
      status_field()
      type_fields()
      metadata_field()
      audit_fields()
      deleted_fields()
      timestamps()

      add :price, :decimal, null: false
      add :stock_quantity, :integer, default: 0
      add :visibility, :citext, default: "public"
    end

    # Simple: Active products
    name_indexes(:products, scope: Scope.new() |> Scope.active())

    # Simple: Published products
    name_indexes(:products, scope: Scope.new() |> Scope.status("published"))

    # Composite: Searchable products
    name_indexes(:products, scope: Scope.new() |> Scope.searchable())

    # Advanced: In-stock, public, premium products
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.public()
      |> Scope.where_gt(:stock_quantity, 0)
      |> Scope.type("premium")
    )
  end
end
```

### Complex Examples

#### E-commerce: Low Stock Alert Index

```elixir
# Index products that need restocking
name_indexes(:products, scope:
  Scope.new()
  |> Scope.active()
  |> Scope.where_lte(:stock_quantity, 10)
  |> Scope.where_gt(:stock_quantity, 0)
  |> Scope.where_not_scope(
    Scope.new() |> Scope.metadata("discontinued", true)
  )
)
# SQL: WHERE deleted_at IS NULL
#      AND stock_quantity <= 10
#      AND stock_quantity > 0
#      AND NOT (metadata->>'discontinued' = 'true')
```

#### Events: Available Capacity Index

```elixir
title_indexes(:events, scope:
  Scope.new()
  |> Scope.active()
  |> Scope.upcoming(60)
  |> Scope.raw("capacity > registered_count")
)
# SQL: WHERE deleted_at IS NULL
#      AND starts_at > NOW()
#      AND starts_at <= NOW() + INTERVAL '60 days'
#      AND capacity > registered_count
```

#### Blog: Trending Posts Index

```elixir
title_indexes(:posts, scope:
  Scope.new()
  |> Scope.active()
  |> Scope.status("published")
  |> Scope.recent(30)
  |> Scope.where_gte(:view_count, 100)
  |> Scope.metadata("seo_optimized", true)
)
# SQL: WHERE deleted_at IS NULL
#      AND status = 'published'
#      AND inserted_at > NOW() - INTERVAL '30 days'
#      AND view_count >= 100
#      AND metadata->>'seo_optimized' = 'true'
```

#### Products: Featured or Hot Index

```elixir
name_indexes(:products, scope:
  Scope.new()
  |> Scope.active()
  |> Scope.where_any([
    Scope.new() |> Scope.featured(),
    Scope.new() |> Scope.hot(7)
  ])
)
# SQL: WHERE deleted_at IS NULL
#      AND (metadata->>'featured' = 'true'
#           OR (deleted_at IS NULL AND status = 'published' AND inserted_at > NOW() - INTERVAL '7 days'))
```

---

## 3. Scope Registry

### Configuration

Define reusable scopes in your application config:

```elixir
# config/config.exs
config :events, Events.Repo.ScopeRegistry,
  scopes: %{
    # Basic scopes
    active: {Events.Repo.Scope, :active, []},
    deleted: {Events.Repo.Scope, :deleted, []},

    # Status scopes
    published: {Events.Repo.Scope, :status, ["published"]},
    draft: {Events.Repo.Scope, :status, ["draft"]},

    # Composite scopes
    queryable: {Events.Repo.Scope, :queryable, []},
    searchable: {Events.Repo.Scope, :searchable, []},

    # Time-based
    recent_7d: {Events.Repo.Scope, :recent, [7]},
    recent_30d: {Events.Repo.Scope, :recent, [30]},
    upcoming: {Events.Repo.Scope, :upcoming, [30]},

    # Business logic scopes (using functions)
    in_stock: fn ->
      Scope.new()
      |> Scope.active()
      |> Scope.where_gt(:stock_quantity, 0)
    end,

    low_stock: fn ->
      Scope.new()
      |> Scope.active()
      |> Scope.where_lte(:stock_quantity, 10)
      |> Scope.where_gt(:stock_quantity, 0)
    end,

    premium_active: fn ->
      Scope.new()
      |> Scope.active()
      |> Scope.type("premium")
      |> Scope.where_gte(:subscription_ends_at, :now)
    end,

    needs_review: fn ->
      Scope.new()
      |> Scope.active()
      |> Scope.where_in(:status, ["pending_review", "needs_revision"])
    end,

    seo_ready: fn ->
      Scope.new()
      |> Scope.searchable()
      |> Scope.metadata("seo_optimized", true)
      |> Scope.where_not_null(:published_at)
    end
  }
```

### Usage in Migrations

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  import Events.Repo.ScopeRegistry

  def change do
    create table(:products) do
      name_fields()
      status_field()
      timestamps()
    end

    # Use registered scopes by name
    name_indexes(:products, scope: get_scope(:searchable))
    name_indexes(:products, scope: get_scope(:in_stock))
    name_indexes(:products, scope: get_scope(:low_stock))
    name_indexes(:products, scope: get_scope(:premium_active))
  end
end
```

### Registry API

```elixir
# Get a registered scope
ScopeRegistry.get_scope(:searchable)
# => "deleted_at IS NULL AND status = 'published' AND visibility = 'public'"

# List all registered scopes
ScopeRegistry.list_scopes()
# => [:active, :deleted, :published, :queryable, :searchable, ...]

# Register a new scope dynamically
ScopeRegistry.register_scope(:custom_scope, fn ->
  Scope.new() |> Scope.active() |> Scope.featured()
end)
```

---

## 4. Integration with Migration Macros

The scope system is fully integrated with the existing migration macro system:

```elixir
# All index macros support scope
name_indexes(:products, scope: Scope.new() |> Scope.active())
title_indexes(:posts, scope: Scope.new() |> Scope.searchable())
status_indexes(:products, scope: Scope.new() |> Scope.active())
type_indexes(:products, scope: Scope.new() |> Scope.premium())
audit_indexes(:products, scope: Scope.new() |> Scope.active())
timestamp_indexes(:products, scope: Scope.new() |> Scope.recent(30))
metadata_index(:products, scope: Scope.new() |> Scope.featured())

# Also supports legacy atom scopes
name_indexes(:products, scope: :active)
name_indexes(:products, scope: :published)

# And raw SQL strings
name_indexes(:products, scope: "status = 'published' AND price > 0")

# And registry lookups
name_indexes(:products, scope: get_scope(:searchable))

# And functions
name_indexes(:products, scope: fn ->
  Scope.new() |> Scope.active() |> Scope.featured()
end)
```

---

## 5. Real-World Examples

### E-commerce Platform

```elixir
defmodule Events.Repo.Migrations.CreateEcommerceIndexes do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.Scope

  def change do
    # Products table assumed to exist

    # 1. Searchable products (public catalog)
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.public()
      |> Scope.where_gt(:stock_quantity, 0)
    )

    # 2. Premium products with active subscriptions
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.type("premium")
      |> Scope.where_gte(:subscription_ends_at, :now)
      |> Scope.where_not_null(:subscription_ends_at)
    )

    # 3. Low stock alerts
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.where_lte(:stock_quantity, 10)
      |> Scope.where_gt(:stock_quantity, 0)
      |> Scope.where_not_scope(
        Scope.new() |> Scope.metadata("discontinued", true)
      )
    )

    # 4. Featured or trending products
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.public()
      |> Scope.where_any([
        Scope.new() |> Scope.featured(),
        Scope.new() |> Scope.where_gte(:view_count, 1000) |> Scope.recent(7)
      ])
    )

    # 5. Sale items
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.where_not_null(:sale_price)
      |> Scope.raw("sale_price < regular_price")
      |> Scope.where_gte(:sale_ends_at, :now)
    )
  end
end
```

### Event Management System

```elixir
defmodule Events.Repo.Migrations.CreateEventIndexes do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.Scope

  def change do
    # Events table assumed to exist

    # 1. Upcoming public events
    title_indexes(:events, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.public()
      |> Scope.upcoming(60)
    )

    # 2. Currently happening events
    title_indexes(:events, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.current(:starts_at, :ends_at)
    )

    # 3. Events with available capacity
    title_indexes(:events, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.upcoming()
      |> Scope.raw("capacity > registered_count")
      |> Scope.where_not_null(:capacity)
    )

    # 4. Featured upcoming events
    title_indexes(:events, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.featured()
      |> Scope.upcoming(30)
      |> Scope.public()
    )

    # 5. Past events for analytics
    title_indexes(:events, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.past(:ends_at)
      |> Scope.where_gte(:registered_count, 10)
    )
  end
end
```

### Content Management System (Blog)

```elixir
defmodule Events.Repo.Migrations.CreateBlogIndexes do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.Scope

  def change do
    # Posts table assumed to exist

    # 1. Searchable published posts
    title_indexes(:posts, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.public()
      |> Scope.where_not_null(:published_at)
    )

    # 2. Trending posts (high views + recent)
    title_indexes(:posts, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.recent(30)
      |> Scope.where_gte(:view_count, 100)
    )

    # 3. SEO-optimized posts
    title_indexes(:posts, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.public()
      |> Scope.metadata("seo_optimized", true)
      |> Scope.where_not_null(:published_at)
    )

    # 4. Posts needing review
    title_indexes(:posts, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.where_in(:status, ["pending_review", "needs_revision"])
      |> Scope.stale(7, :updated_at)
    )

    # 5. Scheduled posts
    title_indexes(:posts, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("scheduled")
      |> Scope.where_not_null(:publish_at)
      |> Scope.where_gt(:publish_at, :now)
    )

    # 6. Popular evergreen content
    title_indexes(:posts, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.where_gte(:view_count, 1000)
      |> Scope.where_not(field: :type, value: "news")
      |> Scope.metadata("evergreen", true)
    )
  end
end
```

### SaaS Application

```elixir
defmodule Events.Repo.Migrations.CreateSaaSIndexes do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.Scope

  def change do
    # Organizations table

    # 1. Active paying organizations
    name_indexes(:organizations, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("active")
      |> Scope.where_in(:plan_type, ["pro", "enterprise"])
      |> Scope.where_gte(:subscription_ends_at, :now)
    )

    # 2. Trial organizations expiring soon
    name_indexes(:organizations, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("trial")
      |> Scope.where_not_null(:trial_ends_at)
      |> Scope.where_between(:trial_ends_at, :now, {:interval, 7, :days})
    )

    # 3. Organizations needing attention
    name_indexes(:organizations, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.where_any([
        # Overdue payments
        Scope.new()
        |> Scope.where_lt(:subscription_ends_at, :now)
        |> Scope.where_in(:status, ["active", "grace_period"]),

        # High usage
        Scope.new()
        |> Scope.metadata_compare("usage_percent", :>, 90, :int)
      ])
    )

    # 4. Enterprise customers
    name_indexes(:organizations, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.type("enterprise")
      |> Scope.metadata("dedicated_support", true)
    )
  end
end
```

---

## 6. Debugging & Inspection

### Explain Scope

```elixir
scope = Scope.new()
        |> Scope.active()
        |> Scope.status("published")
        |> Scope.recent(7)

IO.puts Scope.explain(scope)
```

Output:
```
• deleted_at is NULL
• status equals "published"
• inserted_at within last 7 days
```

### Inspect Scope

```elixir
scope = Scope.new() |> Scope.active() |> Scope.status("published")

IO.inspect(scope)
# => #Scope<deleted_at IS NULL AND status = 'published'>
```

### Generate SQL

```elixir
scope = Scope.new()
        |> Scope.active()
        |> Scope.searchable()

sql = Scope.to_sql(scope)
# => "deleted_at IS NULL AND deleted_at IS NULL AND status = 'published' AND visibility = 'public'"
```

---

## 7. Advanced Patterns

### Reusable Scope Functions

Create helper functions for common patterns:

```elixir
defmodule MyApp.ScopeHelpers do
  alias Events.Repo.Scope

  def available_products do
    Scope.new()
    |> Scope.active()
    |> Scope.status("published")
    |> Scope.where_gt(:stock_quantity, 0)
    |> Scope.public()
  end

  def premium_active do
    Scope.new()
    |> Scope.active()
    |> Scope.type("premium")
    |> Scope.where_gte(:subscription_ends_at, :now)
  end

  def needs_attention do
    Scope.new()
    |> Scope.where_any([
      low_stock(),
      expiring_soon(),
      pending_review()
    ])
  end

  defp low_stock do
    Scope.new()
    |> Scope.where_lte(:stock_quantity, 10)
  end

  defp expiring_soon do
    Scope.new()
    |> Scope.where_between(:expires_at, :now, {:interval, 7, :days})
  end

  defp pending_review do
    Scope.new()
    |> Scope.status("pending_review")
    |> Scope.stale(3, :updated_at)
  end
end
```

Use in migrations:

```elixir
import MyApp.ScopeHelpers

name_indexes(:products, scope: available_products())
name_indexes(:products, scope: premium_active())
name_indexes(:products, scope: needs_attention())
```

### Dynamic Scope Building

Build scopes dynamically based on conditions:

```elixir
def build_product_scope(opts) do
  scope = Scope.new() |> Scope.active()

  scope = if opts[:include_drafts] do
    scope |> Scope.where_in(:status, ["published", "draft"])
  else
    scope |> Scope.status("published")
  end

  scope = if opts[:in_stock_only] do
    scope |> Scope.where_gt(:stock_quantity, 0)
  else
    scope
  end

  scope = if min_price = opts[:min_price] do
    scope |> Scope.where_gte(:price, min_price)
  else
    scope
  end

  scope
end

# Use it
name_indexes(:products, scope: build_product_scope(
  include_drafts: false,
  in_stock_only: true,
  min_price: 10.0
))
```

### Scope Composition

Compose multiple scopes together:

```elixir
base_scope = Scope.new() |> Scope.active()

public_scope = base_scope |> Scope.public()
published_scope = base_scope |> Scope.status("published")

searchable_scope = Scope.new()
                   |> Scope.where_all([public_scope, published_scope])

name_indexes(:products, scope: searchable_scope)
```

---

## 8. Performance Considerations

### Index Selectivity

More selective scopes create more efficient indexes:

```elixir
# Less selective (fewer records filtered out)
Scope.new() |> Scope.active()

# More selective (more records filtered out)
Scope.new()
|> Scope.active()
|> Scope.status("published")
|> Scope.public()
|> Scope.recent(7)
```

### Partial Index Benefits

Partial indexes are smaller and faster:

```elixir
# Without partial index: Full table scan for WHERE deleted_at IS NULL
create index(:products, [:name])

# With partial index: Smaller index, faster queries
name_indexes(:products, scope: Scope.new() |> Scope.active())
# CREATE INDEX ON products (name) WHERE deleted_at IS NULL
```

### Combining Conditions Efficiently

PostgreSQL can use partial indexes when query conditions match or are subsets:

```elixir
# Index
name_indexes(:products, scope:
  Scope.new()
  |> Scope.active()
  |> Scope.status("published")
)

# This query can use the index (matches exactly)
SELECT * FROM products
WHERE deleted_at IS NULL
  AND status = 'published'
  AND name ILIKE '%search%'

# This query can also use the index (subset of conditions)
SELECT * FROM products
WHERE deleted_at IS NULL
  AND status = 'published'
```

---

## 9. Testing

### Unit Tests

```elixir
defmodule Events.Repo.ScopeTest do
  use ExUnit.Case, async: true
  alias Events.Repo.Scope

  describe "basic comparisons" do
    test "equals" do
      sql = Scope.new()
            |> Scope.where(:status, "published")
            |> Scope.to_sql()

      assert sql == "status = 'published'"
    end

    test "in list" do
      sql = Scope.new()
            |> Scope.where_in(:status, ["published", "featured"])
            |> Scope.to_sql()

      assert sql == "status IN ('published', 'featured')"
    end
  end

  describe "composite scopes" do
    test "searchable" do
      sql = Scope.new()
            |> Scope.searchable()
            |> Scope.to_sql()

      assert sql == "deleted_at IS NULL AND status = 'published' AND visibility = 'public'"
    end
  end

  describe "logical operators" do
    test "OR conditions" do
      sql = Scope.new()
            |> Scope.where_any([
              Scope.new() |> Scope.status("published"),
              Scope.new() |> Scope.status("featured")
            ])
            |> Scope.to_sql()

      assert sql == "(status = 'published' OR status = 'featured')"
    end
  end
end
```

### Integration Tests

Test that indexes are created correctly:

```elixir
defmodule Events.Repo.Migrations.CreateProductsTest do
  use Events.DataCase
  import Ecto.Query

  test "partial index on active products exists" do
    # Query PostgreSQL system catalog
    result = Repo.query!("""
      SELECT indexdef
      FROM pg_indexes
      WHERE tablename = 'products'
        AND indexname LIKE '%name%'
    """)

    assert [%{"indexdef" => indexdef}] = result.rows
    assert indexdef =~ "WHERE (deleted_at IS NULL)"
  end
end
```

---

## 10. Migration Guide

### From Legacy Atom Scopes

**Before:**
```elixir
name_indexes(:products, scope: :active)
status_indexes(:products, scope: :published)
```

**After:**
```elixir
# Option 1: Use Scope builder
name_indexes(:products, scope: Scope.new() |> Scope.active())
status_indexes(:products, scope: Scope.new() |> Scope.status("published"))

# Option 2: Register in config and use registry
# config/config.exs
config :events, Events.Repo.ScopeRegistry,
  scopes: %{
    active: {Events.Repo.Scope, :active, []},
    published: {Events.Repo.Scope, :status, ["published"]}
  }

# In migration
name_indexes(:products, scope: get_scope(:active))
status_indexes(:products, scope: get_scope(:published))
```

### From Raw SQL Strings

**Before:**
```elixir
name_indexes(:products,
  scope: "deleted_at IS NULL AND status = 'published' AND price > 0"
)
```

**After:**
```elixir
name_indexes(:products, scope:
  Scope.new()
  |> Scope.active()
  |> Scope.status("published")
  |> Scope.where_gt(:price, 0)
)
```

### Adding New Scope Types

To add a new scope type:

1. Add method to `Events.Repo.Scope`
2. Add corresponding condition tuple type
3. Add SQL generation in `condition_to_sql/1`
4. Add tests
5. Document in this guide

---

## 11. Best Practices

### DO ✅

- **Use scopes for all partial indexes** - Makes intent clear
- **Compose scopes** - Build complex conditions from simple ones
- **Register common scopes** - DRY principle
- **Test generated SQL** - Ensure indexes are created correctly
- **Use type-safe methods** - Prefer `Scope.status("published")` over raw SQL
- **Document business logic** - Explain why a scope exists

### DON'T ❌

- **Don't use raw SQL** unless absolutely necessary
- **Don't duplicate scope logic** - Use registry or helper functions
- **Don't create overly complex scopes** - Break into smaller, testable pieces
- **Don't ignore index selectivity** - More selective = better performance
- **Don't skip testing** - Verify indexes exist and work

---

## 12. Troubleshooting

### Issue: Scope not working as expected

**Check:**
1. Generated SQL with `Scope.to_sql(scope)`
2. Explain scope with `Scope.explain(scope)`
3. Verify index creation in database

```elixir
# In migration
scope = Scope.new() |> Scope.active() |> Scope.searchable()
IO.puts("Generated SQL: #{Scope.to_sql(scope)}")
IO.puts("Explanation:\n#{Scope.explain(scope)}")
```

### Issue: Index not being used

**Possible causes:**
1. Query conditions don't match partial index
2. Scope too complex for query planner
3. Index not selective enough

**Solution:**
```sql
-- Check if index exists
SELECT * FROM pg_indexes WHERE tablename = 'products';

-- Explain query plan
EXPLAIN SELECT * FROM products WHERE deleted_at IS NULL AND status = 'published';
```

### Issue: Registry scope not found

**Error:**
```
** (ArgumentError) Unknown scope: :my_scope. Available: [:active, :published, ...]
```

**Solution:**
1. Check config: `config :events, Events.Repo.ScopeRegistry, scopes: %{...}`
2. Verify scope name is registered
3. Restart application to reload config

---

## 13. Future Enhancements

Potential improvements to consider:

1. **Query analyzer** - Suggest optimal indexes based on query patterns
2. **Scope optimizer** - Simplify redundant conditions
3. **Index coverage analysis** - Check which indexes cover which queries
4. **Performance benchmarks** - Compare index strategies
5. **Visual scope builder** - UI for building complex scopes
6. **Scope versioning** - Track scope changes over time
7. **Auto-documentation** - Generate docs from registered scopes

---

## 14. Summary

The Dynamic Scope System provides:

✅ **Type-safe** scope building with compile-time validation
✅ **Chainable API** for natural composition
✅ **Reusable scopes** via registry
✅ **Logical operators** (AND, OR, NOT)
✅ **Time-based scopes** (recent, stale, future, past, current)
✅ **JSONB support** for metadata querying
✅ **Full-text search** integration
✅ **Composite patterns** (queryable, searchable, hot, premium)
✅ **SQL generation** with optimization
✅ **Debugging tools** (explain, inspect)
✅ **Comprehensive testing**
✅ **Migration integration**

### Quick Reference

```elixir
# Import
alias Events.Repo.Scope

# Build scope
scope = Scope.new()
        |> Scope.active()
        |> Scope.status("published")
        |> Scope.public()
        |> Scope.recent(7)
        |> Scope.featured()

# Generate SQL
sql = Scope.to_sql(scope)

# Use in migration
name_indexes(:products, scope: scope)

# Or use registry
name_indexes(:products, scope: get_scope(:searchable))
```

---

## Appendix: Complete API Reference

### Constructor
- `new(opts \\ [])`

### Soft Delete
- `active()`
- `deleted()`
- `recently_deleted(days)`

### Field Comparisons
- `where(field, value)`
- `where_not(field, value)`
- `where_gt(field, value)`
- `where_lt(field, value)`
- `where_gte(field, value)`
- `where_lte(field, value)`
- `where_in(field, values)`
- `where_not_in(field, values)`
- `where_null(field)`
- `where_not_null(field)`
- `where_between(field, from, to)`
- `where_like(field, pattern)`
- `where_ilike(field, pattern)`

### Convenience
- `status(value)`
- `type(value)`
- `subtype(value)`
- `visibility(value)`
- `public()`
- `private()`
- `visible()`

### Time-Based
- `recent(days, field \\ :inserted_at)`
- `stale(days, field \\ :updated_at)`
- `future(field \\ :starts_at)`
- `past(field \\ :ends_at)`
- `current(start_field, end_field)`
- `upcoming(days, field)`

### JSONB/Metadata
- `metadata(key, value)`
- `metadata_exists(key)`
- `metadata_contains(map)`
- `metadata_compare(key, operator, value, type)`
- `featured()`
- `enabled()`
- `verified()`

### Text Search
- `search(field, query, language)`

### Logical
- `where_any(scopes)`
- `where_all(scopes)`
- `where_not_scope(scope)`

### Raw
- `raw(sql)`

### Composite
- `queryable(statuses)`
- `searchable()`
- `hot(days)`
- `premium()`

### Output
- `to_sql()`
- `explain()`

---

**End of Documentation**
