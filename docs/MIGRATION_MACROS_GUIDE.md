# Migration Macros Guide

Comprehensive guide to using `Events.Repo.MigrationMacros` for standardized database migrations.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Field Macros](#field-macros)
  - [type_fields](#type_fields)
  - [metadata_field](#metadata_field)
  - [audit_fields](#audit_fields)
  - [deleted_fields](#deleted_fields)
  - [timestamps](#timestamps)
  - [standard_entity_fields](#standard_entity_fields)
- [Index Macros](#index-macros)
  - [type_indexes](#type_indexes)
  - [audit_indexes](#audit_indexes)
  - [deleted_indexes](#deleted_indexes)
  - [timestamp_indexes](#timestamp_indexes)
  - [metadata_index](#metadata_index)
  - [standard_indexes](#standard_indexes)
- [Real-World Examples](#real-world-examples)
- [Best Practices](#best-practices)
- [Migration Patterns](#migration-patterns)

---

## Overview

The Migration Macros module provides:

1. **Consistent field patterns** - Add common fields with a single macro
2. **Flexible field selection** - Use `:only` and `:except` to control which fields are added
3. **Automatic indexing helpers** - Create recommended indexes with matching macros
4. **UUIDv7 primary keys** - Time-ordered, indexable primary keys by default

### Key Features

- ✅ **Backward compatible** - Default behavior unchanged
- ✅ **Explicit control** - Use `:has` option to specify what fields exist for indexing
- ✅ **Production ready** - Support for concurrent index creation
- ✅ **Type safe** - Validation of field names at compile time

---

## Quick Start

### Simple Product Table

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:products) do
      # Add standard fields
      standard_entity_fields()

      # Custom fields
      add :price, :decimal, null: false
      add :sku, :citext, null: false
    end

    # Create recommended indexes
    standard_indexes(:products)

    # Custom indexes
    create unique_index(:products, [:sku])
    create index(:products, [:price])
  end
end
```

### Custom Fields with Selective Indexing

```elixir
defmodule Events.Repo.Migrations.CreateCategories do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:categories) do
      add :name, :citext, null: false

      # Only type field, no subtype
      type_fields(only: :type)

      # No audit tracking
      timestamps()
    end

    # Only index what we added
    type_indexes(:categories, only: :type)

    create unique_index(:categories, [:name])
  end
end
```

---

## Field Macros

### type_fields

Adds `type` and `subtype` fields for polymorphic entities.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:only` | atom | `nil` | Add only `:type` or `:subtype` |
| `:except` | atom | `nil` | Exclude `:type` or `:subtype` |
| `:type_default` | string | `nil` | Default value for type |
| `:subtype_default` | string | `nil` | Default value for subtype |
| `:null` | boolean | `true` | Allow NULL values |

**Note**: `:only` and `:except` are mutually exclusive.

#### Examples

```elixir
# Both fields (default)
type_fields()
# => add :type, :citext, null: true
# => add :subtype, :citext, null: true

# Only type field
type_fields(only: :type, type_default: "standard")
# => add :type, :citext, default: "standard", null: true

# Exclude subtype
type_fields(except: :subtype)
# => add :type, :citext, null: true

# Required fields with defaults
type_fields(
  type_default: "event",
  subtype_default: "conference",
  null: false
)
```

#### Use Cases

```elixir
# 1. Events system
create table(:events) do
  add :title, :citext, null: false

  type_fields(type_default: "conference", null: false)
  # type: "conference", "workshop", "webinar"
  # subtype: "technical", "business", "social"

  timestamps()
end

# 2. Product catalog with only main type
create table(:products) do
  add :name, :citext, null: false

  type_fields(only: :type, type_default: "physical")
  # type: "physical", "digital", "service"

  timestamps()
end

# 3. Complex entity with both classification levels
create table(:content_items) do
  add :title, :citext, null: false

  type_fields(
    type_default: "article",
    subtype_default: "blog"
  )
  # type: "article", "video", "podcast"
  # subtype: "blog", "tutorial", "news"

  timestamps()
end
```

---

### metadata_field

Adds a JSONB `metadata` field for flexible schema extensions.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:null` | boolean | `false` | Allow NULL values |
| `:default` | fragment | `fragment("'{}'")` | Default JSON value |

#### Examples

```elixir
# Standard usage (empty object, NOT NULL)
metadata_field()
# => add :metadata, :jsonb, default: fragment("'{}'"), null: false

# Allow NULL
metadata_field(null: true)

# Custom default with version
metadata_field(default: fragment("'{\"version\": 1}'"))
```

#### Use Cases

```elixir
# 1. Feature flags per record
create table(:users) do
  add :email, :citext, null: false

  metadata_field()
  # Store: %{enabled_features: ["analytics", "export"]}

  timestamps()
end

# 2. External integrations
create table(:accounts) do
  add :name, :citext, null: false

  metadata_field()
  # Store: %{
  #   stripe_customer_id: "cus_123",
  #   last_sync: "2024-01-01T00:00:00Z"
  # }

  timestamps()
end

# 3. Versioned configuration
create table(:settings) do
  add :key, :citext, null: false

  metadata_field(default: fragment("'{\"version\": 1}'"))
  # Store versioned config data

  timestamps()
end
```

---

### audit_fields

Adds `created_by_urm_id` and `updated_by_urm_id` for audit tracking.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:only` | atom | `nil` | Add only `:created_by_urm_id` or `:updated_by_urm_id` |
| `:except` | atom | `nil` | Exclude specific field |
| `:references` | boolean | `true` | Add FK constraints |
| `:on_delete` | atom | `:nilify_all` | FK deletion behavior |
| `:null` | boolean | `true` | Allow NULL values |

#### Examples

```elixir
# Both fields with FK constraints (default)
audit_fields()
# => add :created_by_urm_id, references(:user_role_mappings, ...), null: true
# => add :updated_by_urm_id, references(:user_role_mappings, ...), null: true

# Only track creator
audit_fields(only: :created_by_urm_id)

# Exclude updater
audit_fields(except: :updated_by_urm_id)

# Required audit trail
audit_fields(null: false)

# Without FK constraints (for early migrations)
audit_fields(references: false)

# Restrict deletion
audit_fields(on_delete: :restrict)
```

#### Use Cases

```elixir
# 1. Full audit trail
create table(:invoices) do
  add :invoice_number, :string, null: false
  add :total, :decimal, null: false

  audit_fields(null: false)  # Required audit info
  timestamps()
end

# 2. Only track creator (immutable records)
create table(:logs) do
  add :message, :text, null: false

  audit_fields(only: :created_by_urm_id)  # Only who created
  timestamps()
end

# 3. Foundation table without FK (created before user_role_mappings)
create table(:users) do
  add :email, :citext, null: false

  # No audit fields here, or:
  audit_fields(references: false)  # Add fields without FK
  timestamps()
end
```

---

### deleted_fields

Adds `deleted_at` and `deleted_by_urm_id` for soft delete functionality.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:only` | atom | `nil` | Add only `:deleted_at` or `:deleted_by_urm_id` |
| `:except` | atom | `nil` | Exclude specific field |
| `:references` | boolean | `true` | Add FK constraint for deleted_by_urm_id |
| `:on_delete` | atom | `:nilify_all` | FK deletion behavior |
| `:null` | boolean | `true` | Allow NULL values |

#### Examples

```elixir
# Both fields (timestamp + who deleted)
deleted_fields()
# => add :deleted_at, :utc_datetime_usec, null: true
# => add :deleted_by_urm_id, references(...), null: true

# Only timestamp (no audit)
deleted_fields(only: :deleted_at)

# Exclude who deleted
deleted_fields(except: :deleted_by_urm_id)

# Without FK constraint
deleted_fields(references: false)
```

#### Use Cases

```elixir
# 1. Full soft delete with audit
create table(:documents) do
  add :title, :citext, null: false
  add :content, :text

  audit_fields()
  deleted_fields()  # Track when and who deleted
  timestamps()
end

deleted_indexes(:documents)

# 2. Simple soft delete (timestamp only)
create table(:comments) do
  add :body, :text, null: false

  deleted_fields(only: :deleted_at)  # Just track when deleted
  timestamps()
end

deleted_indexes(:comments, only: :deleted_at)

# 3. Using soft delete in queries
# Schema:
defmodule MyApp.Catalog.Product do
  use Ecto.Schema

  schema "products" do
    field :name, :string
    field :deleted_at, :utc_datetime_usec
    timestamps()
  end

  # Default scope - exclude deleted
  def not_deleted(query \\ __MODULE__) do
    from q in query, where: is_nil(q.deleted_at)
  end

  # Soft delete function
  def soft_delete(product, deleted_by_urm_id) do
    product
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(),
      deleted_by_urm_id: deleted_by_urm_id
    })
    |> Repo.update()
  end
end
```

---

### timestamps

Adds `inserted_at` and `updated_at` timestamp fields.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:only` | atom | `nil` | Add only `:inserted_at` or `:updated_at` |
| `:except` | atom | `nil` | Exclude specific field |

#### Examples

```elixir
# Both fields (default)
timestamps()
# => add :inserted_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
# => add :updated_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")

# Only inserted_at
timestamps(only: :inserted_at)

# Exclude updated_at
timestamps(except: :updated_at)
```

#### Use Cases

```elixir
# 1. Standard timestamps
create table(:products) do
  add :name, :citext, null: false
  timestamps()
end

# 2. Immutable records (only track creation)
create table(:events_log) do
  add :event_type, :string, null: false
  add :data, :jsonb

  timestamps(only: :inserted_at)  # Never updated
end

# 3. Custom tracking (only update time)
create table(:session_state) do
  add :session_id, :uuid, null: false
  add :state, :jsonb

  timestamps(only: :updated_at)  # Only care about last update
end
```

---

### standard_entity_fields

All-in-one macro that adds a complete set of standard fields.

#### Fields Added

| Field | Type | Default | Can Exclude? |
|-------|------|---------|--------------|
| `name` | citext | - | Yes (`:include_name` or `:except`) |
| `slug` | citext | - | Yes (`:include_slug` or `:except`) |
| `status` | citext | `"active"` | Yes (`:except`) |
| `description` | text | - | Yes (`:include_description` or `:except`) |
| `type` | citext | - | Yes (`:except` with `:type_fields`) |
| `subtype` | citext | - | Yes (`:except` with `:type_fields`) |
| `metadata` | jsonb | `{}` | Yes (`:except`) |
| `created_by_urm_id` | uuid | - | Yes (`:except` with `:audit_fields`) |
| `updated_by_urm_id` | uuid | - | Yes (`:except` with `:audit_fields`) |
| `inserted_at` | timestamp | CURRENT_TIMESTAMP | Yes (`:except` with `:timestamps`) |
| `updated_at` | timestamp | CURRENT_TIMESTAMP | Yes (`:except` with `:timestamps`) |

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:include_name` | boolean | `true` | Add name field |
| `:include_slug` | boolean | `true` | Add slug field |
| `:include_description` | boolean | `true` | Add description field |
| `:except` | list | `[]` | Exclude field groups |
| `:status_default` | string | `"active"` | Default status value |
| `:type_default` | string | `nil` | Default type value |
| `:null` | boolean | `true` | Allow NULL for audit fields |
| `:references` | boolean | `true` | Add FK constraints for audit fields |

**Field groups for `:except`**: `:name`, `:slug`, `:status`, `:description`, `:type_fields`, `:metadata`, `:audit_fields`, `:timestamps`

#### Examples

```elixir
# Full standard entity
standard_entity_fields()
# Adds all 11 fields

# Exclude slug and description
standard_entity_fields(except: [:slug, :description])

# Exclude entire field groups
standard_entity_fields(except: [:type_fields, :audit_fields])

# Custom status default
standard_entity_fields(status_default: "pending")

# Without name/slug (using old approach)
standard_entity_fields(include_name: false, include_slug: false)

# Required audit fields
standard_entity_fields(null: false)
```

#### Use Cases

```elixir
# 1. Full-featured entity
create table(:products) do
  standard_entity_fields()

  # Custom fields
  add :price, :decimal, null: false
  add :sku, :citext, null: false
end

standard_indexes(:products)

# 2. Simple entity without slug
create table(:categories) do
  standard_entity_fields(except: [:slug, :description])

  add :parent_id, references(:categories, type: :uuid)
end

standard_indexes(:categories, has: [:status, :type_fields, :audit_fields])

# 3. Minimal entity
create table(:tags) do
  standard_entity_fields(
    except: [:slug, :description, :type_fields, :metadata, :audit_fields]
  )
  # Only adds: name, status, timestamps
end

standard_indexes(:tags, has: [:status])

# 4. Audit trail required
create table(:transactions) do
  standard_entity_fields(null: false, status_default: "pending")

  add :amount, :decimal, null: false
  add :currency, :string, default: "USD"
end

standard_indexes(:transactions)
```

---

## Index Macros

### type_indexes

Creates indexes for type classification fields.

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `:only` | atom | Index only `:type` or `:subtype` |
| `:except` | atom | Skip indexing specific field |
| `:where` | string | Partial index condition |
| `:name` | atom/string | Custom index name |
| `:unique` | boolean | Create unique index |
| `:concurrently` | boolean | Create concurrently |
| `:composite` | boolean | Create single composite index on both fields |

#### Examples

```elixir
# Both fields
type_indexes(:products)
# => create index(:products, [:type])
# => create index(:products, [:subtype])

# Only type
type_indexes(:products, only: :type)

# Exclude subtype
type_indexes(:products, except: :subtype)

# Partial index for non-deleted records
type_indexes(:products, where: "deleted_at IS NULL")

# Unique type
type_indexes(:products, only: :type, unique: true)

# Composite index
type_indexes(:products, composite: true)
# => create index(:products, [:type, :subtype])

# Production-safe concurrent creation
type_indexes(:products, concurrently: true)

# Custom name
type_indexes(:products, name: :products_classification_idx)
```

---

### audit_indexes

Creates indexes for audit tracking fields.

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `:only` | atom | Index only `:created_by_urm_id` or `:updated_by_urm_id` |
| `:except` | atom | Skip indexing specific field |
| `:where` | string | Partial index condition |
| `:name` | atom/string | Custom index name |
| `:concurrently` | boolean | Create concurrently |

#### Examples

```elixir
# Both audit fields
audit_indexes(:products)
# => create index(:products, [:created_by_urm_id])
# => create index(:products, [:updated_by_urm_id])

# Only creator
audit_indexes(:products, only: :created_by_urm_id)

# Exclude updater
audit_indexes(:products, except: :updated_by_urm_id)

# Partial index for active records
audit_indexes(:products, where: "deleted_at IS NULL")

# Concurrent creation
audit_indexes(:products, concurrently: true)
```

---

### deleted_indexes

Creates indexes for soft delete fields.

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `:only` | atom | Index only `:deleted_at` or `:deleted_by_urm_id` |
| `:except` | atom | Skip indexing specific field |
| `:where` | string | Partial index condition |
| `:name` | atom/string | Custom index name |
| `:concurrently` | boolean | Create concurrently |

#### Examples

```elixir
# Both fields
deleted_indexes(:documents)
# => create index(:documents, [:deleted_at])
# => create index(:documents, [:deleted_by_urm_id])

# Only timestamp
deleted_indexes(:documents, only: :deleted_at)

# Partial index for deleted records
deleted_indexes(:documents, where: "deleted_at IS NOT NULL")

# Custom name
deleted_indexes(:documents, name: :docs_soft_delete_idx)
```

---

### timestamp_indexes

Creates indexes for timestamp fields.

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `:only` | atom | Index only `:inserted_at` or `:updated_at` |
| `:except` | atom | Skip indexing specific field |
| `:where` | string | Partial index condition |
| `:name` | atom/string | Custom index name |
| `:concurrently` | boolean | Create concurrently |
| `:composite_with` | list | Create composite index with other fields |

#### Examples

```elixir
# Both timestamps
timestamp_indexes(:products)
# => create index(:products, [:inserted_at])
# => create index(:products, [:updated_at])

# Only updated_at
timestamp_indexes(:products, only: :updated_at)

# Composite with status
timestamp_indexes(:products, only: :updated_at, composite_with: [:status])
# => create index(:products, [:status, :updated_at])

# Multiple composite indexes for complex queries
timestamp_indexes(:products, composite_with: [:type, :status])
# => create index(:products, [:type, :status, :inserted_at])
# => create index(:products, [:type, :status, :updated_at])

# For recent active records
timestamp_indexes(:products,
  only: :inserted_at,
  where: "status = 'active'",
  name: :recent_active_products
)
```

---

### metadata_index

Creates a GIN index on the metadata JSONB field.

**⚠️ Performance Note**: GIN indexes on JSONB are expensive to maintain. Only create if you frequently query JSON keys.

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `:name` | atom/string | Custom index name |
| `:concurrently` | boolean | Create concurrently (recommended) |
| `:json_path` | string | Index specific JSON key instead of entire field |
| `:using` | atom | Index method (default: `:gin`) |

#### Examples

```elixir
# Full GIN index
metadata_index(:products)
# => create index(:products, [:metadata], using: :gin)

# Specific JSON key (more efficient)
metadata_index(:products, json_path: "status")
# => create index(:products, [fragment("(metadata->>'status')")])

# Multiple specific keys
metadata_index(:products, json_path: "external_id")
metadata_index(:products, json_path: "sync_status")

# Concurrent creation (recommended for production)
metadata_index(:products, concurrently: true)

# Custom name
metadata_index(:products, name: :products_metadata_gin)
```

#### Use Cases

```elixir
# 1. Full-text search in metadata
metadata_index(:articles)
# Query: where: fragment("? @> ?", a.metadata, ~s({"published": true}))

# 2. Specific key lookups
metadata_index(:integrations, json_path: "provider")
# Query: where: fragment("? ->> 'provider' = ?", i.metadata, "stripe")

# 3. Multiple key indexes for common queries
metadata_index(:orders, json_path: "external_id")
metadata_index(:orders, json_path: "payment_status")
# Better than full GIN if you only query specific keys
```

---

### standard_indexes

All-in-one macro for creating recommended indexes on standard entity fields.

**Key Feature**: Uses `:has` option to explicitly specify which field groups exist in your table.

#### Default Behavior

When `has: :all` (default), assumes `standard_entity_fields()` was used and creates:
- Unique index on `:slug`
- Partial index on `:status` (WHERE deleted_at IS NULL)
- Standard indexes on `:type`, `:subtype`
- Standard indexes on `:created_by_urm_id`, `:updated_by_urm_id`

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `:has` | `:all` or list | What field groups exist in the table |
| `:only` | list | Create indexes only for specific field groups |
| `:except` | list | Skip indexes for specific field groups |
| `:slug_unique` | boolean | Make slug index unique (default: true) |
| `:status_where` | string | Custom WHERE clause for status |
| `:concurrently` | boolean | Create all indexes concurrently |
| `:composite` | list of lists | Additional composite indexes |

**Field groups**: `:slug`, `:status`, `:type_fields`, `:audit_fields`, `:deleted_fields`, `:timestamps`, `:metadata`

#### Examples

```elixir
# Full standard entity with all indexes
create table(:products) do
  standard_entity_fields()
  add :price, :decimal
end

standard_indexes(:products)
# Creates: slug (unique), status, type, subtype, created_by_urm_id, updated_by_urm_id

# Partial fields - be explicit about what exists
create table(:categories) do
  standard_entity_fields(except: [:slug, :audit_fields])
end

standard_indexes(:categories, has: [:status, :type_fields])
# Only creates indexes for status, type, subtype

# Custom field setup
create table(:logs) do
  add :name, :citext
  type_fields(only: :type)
  timestamps()
end

standard_indexes(:logs, has: [:type_fields])
# Only creates type indexes (not subtype since it doesn't exist)

# With deleted fields
create table(:documents) do
  standard_entity_fields()
  deleted_fields()
end

standard_indexes(:documents, has: [:slug, :status, :type_fields, :audit_fields, :deleted_fields])

# Production-safe (concurrent)
standard_indexes(:products, concurrently: true)

# Custom status condition
standard_indexes(:products, status_where: "status IN ('active', 'pending')")

# Additional composite indexes
standard_indexes(:products, composite: [
  [:type, :status],
  [:status, :updated_at]
])
```

---

## Real-World Examples

### Example 1: E-Commerce Product Table

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:products) do
      # All standard fields
      standard_entity_fields(status_default: "draft")

      # Soft delete support
      deleted_fields()

      # Product-specific fields
      add :sku, :citext, null: false
      add :price, :decimal, precision: 10, scale: 2, null: false
      add :inventory_count, :integer, default: 0
      add :category_id, references(:categories, type: :uuid)
    end

    # Standard indexes
    standard_indexes(:products,
      has: [:slug, :status, :type_fields, :audit_fields, :deleted_fields]
    )

    # Custom indexes
    create unique_index(:products, [:sku])
    create index(:products, [:category_id])
    create index(:products, [:price], where: "status = 'active' AND deleted_at IS NULL")

    # Composite indexes for common queries
    create index(:products, [:category_id, :status, :updated_at])
  end
end
```

### Example 2: Simple Category Table

```elixir
defmodule Events.Repo.Migrations.CreateCategories do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:categories) do
      # Minimal standard fields (no slug, no description, no audit)
      standard_entity_fields(
        except: [:slug, :description, :type_fields, :audit_fields]
      )

      # Self-referencing hierarchy
      add :parent_id, references(:categories, type: :uuid)
      add :level, :integer, default: 0
    end

    # Only index what exists
    standard_indexes(:categories, has: [:status])

    # Custom indexes
    create unique_index(:categories, [:name])
    create index(:categories, [:parent_id])
    create index(:categories, [:level])
  end
end
```

### Example 3: Audit Log Table

```elixir
defmodule Events.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:audit_logs) do
      # Basic info
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :uuid, null: false
      add :changes, :jsonb

      # Only track who created (immutable records)
      audit_fields(only: :created_by_urm_id)

      # Only track creation time
      timestamps(only: :inserted_at)
    end

    # Indexes for audit queries
    audit_indexes(:audit_logs, only: :created_by_urm_id)
    create index(:audit_logs, [:entity_type, :entity_id])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:inserted_at])

    # Composite for common queries
    create index(:audit_logs, [:entity_type, :entity_id, :inserted_at])
  end
end
```

### Example 4: User Table (Foundation)

```elixir
defmodule Events.Repo.Migrations.CreateUsers do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:users) do
      # Standard fields but no audit (circular dependency)
      standard_entity_fields(except: [:audit_fields])

      # User-specific
      add :email, :citext, null: false
      add :password_hash, :string
    end

    # Standard indexes minus audit
    standard_indexes(:users, has: [:slug, :status, :type_fields])

    # Custom indexes
    create unique_index(:users, [:email])
  end
end
```

### Example 5: Session State Table

```elixir
defmodule Events.Repo.Migrations.CreateSessions do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:sessions) do
      add :session_key, :string, null: false
      add :user_id, references(:users, type: :uuid)
      add :expires_at, :utc_datetime_usec, null: false

      # Store session data
      metadata_field()

      # Only track last update
      timestamps(only: :updated_at)
    end

    create unique_index(:sessions, [:session_key])
    create index(:sessions, [:user_id])
    create index(:sessions, [:expires_at])

    # GIN index for querying session data
    metadata_index(:sessions, concurrently: true)
  end
end
```

### Example 6: Event Tracking with Types

```elixir
defmodule Events.Repo.Migrations.CreateEvents do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:events) do
      add :title, :citext, null: false
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec

      # Type classification
      type_fields(type_default: "conference", null: false)

      # Flexible event data
      metadata_field()

      # Full audit trail
      audit_fields(null: false)

      # Soft delete
      deleted_fields()

      timestamps()
    end

    # Type indexes with partial index for active events
    type_indexes(:events, where: "deleted_at IS NULL")

    # Audit indexes
    audit_indexes(:events)

    # Deleted indexes
    deleted_indexes(:events)

    # Time-based queries
    create index(:events, [:starts_at])
    create index(:events, [:ends_at])

    # Composite for common queries
    create index(:events, [:type, :starts_at], where: "deleted_at IS NULL")
  end
end
```

### Example 7: Production Migration with Concurrency

```elixir
defmodule Events.Repo.Migrations.CreateOrdersProduction do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    create table(:orders) do
      standard_entity_fields()

      add :user_id, references(:users, type: :uuid), null: false
      add :total, :decimal, precision: 10, scale: 2, null: false
      add :currency, :string, default: "USD"
    end

    # All indexes created concurrently for zero-downtime
    standard_indexes(:orders, concurrently: true)

    create index(:orders, [:user_id], concurrently: true)
    create index(:orders, [:total], concurrently: true)

    # Composite indexes
    create index(:orders, [:user_id, :status, :inserted_at], concurrently: true)
  end
end
```

---

## Best Practices

### 1. Use Standard Fields When Appropriate

```elixir
# ✅ Good: Use standard_entity_fields for typical business entities
create table(:products) do
  standard_entity_fields()
  add :price, :decimal
end

# ❌ Avoid: Manually adding all fields
create table(:products) do
  add :name, :citext
  add :slug, :citext
  add :status, :citext
  # ... etc
end
```

### 2. Be Explicit About Indexes

```elixir
# ✅ Good: Specify what fields exist
standard_entity_fields(except: [:slug, :audit_fields])
standard_indexes(:table, has: [:status, :type_fields])

# ❌ Avoid: Letting standard_indexes guess
standard_entity_fields(except: [:slug, :audit_fields])
standard_indexes(:table)  # Might try to index non-existent fields
```

### 3. Use Partial Indexes for Common Query Patterns

```elixir
# ✅ Good: Partial index for active records
type_indexes(:products, where: "deleted_at IS NULL AND status = 'active'")

# ✅ Good: Index deleted records separately if needed
deleted_indexes(:products, only: :deleted_at, where: "deleted_at IS NOT NULL")
```

### 4. Create Composite Indexes for Common Queries

```elixir
# If you frequently query:
# WHERE type = ? AND status = ? ORDER BY updated_at DESC

# ✅ Good: Create composite index
create index(:products, [:type, :status, :updated_at])

# Or use standard_indexes with composite option
standard_indexes(:products, composite: [
  [:type, :status, :updated_at]
])
```

### 5. Use Concurrent Index Creation in Production

```elixir
# ✅ Good: Production migration
def change do
  create table(:products) do
    standard_entity_fields()
  end

  standard_indexes(:products, concurrently: true)
end

# ⚠️ Note: Concurrent indexes cannot be created inside a transaction
def change do
  create table(:products) do
    standard_entity_fields()
  end
end

def up do
  standard_indexes(:products, concurrently: true)
end
```

### 6. Index Foreign Keys

```elixir
# ✅ Good: Always index foreign keys
create table(:order_items) do
  add :order_id, references(:orders, type: :uuid), null: false
  add :product_id, references(:products, type: :uuid), null: false

  timestamps()
end

create index(:order_items, [:order_id])
create index(:order_items, [:product_id])
```

### 7. Don't Over-Index

```elixir
# ❌ Avoid: Indexing rarely-queried fields
create index(:products, [:description])  # Text field, rarely queried

# ❌ Avoid: Duplicate indexes
type_indexes(:products)  # Already creates type index
create index(:products, [:type])  # Duplicate!

# ✅ Good: Only index what you actually query
create index(:products, [:price], where: "status = 'active'")
```

### 8. Use Specific JSON Path Indexes Instead of Full GIN

```elixir
# ❌ Expensive: Full GIN index
metadata_index(:products)

# ✅ Better: Index only the keys you query
metadata_index(:products, json_path: "external_id")
metadata_index(:products, json_path: "sync_status")
```

---

## Migration Patterns

### Pattern 1: Full Standard Entity

**When**: Creating a typical business entity with all bells and whistles.

```elixir
def change do
  create table(:entity_name) do
    standard_entity_fields()

    # Custom fields
    add :custom_field, :type
  end

  standard_indexes(:entity_name)

  # Additional custom indexes
  create index(:entity_name, [:custom_field])
end
```

### Pattern 2: Minimal Entity

**When**: Creating a simple lookup table or reference data.

```elixir
def change do
  create table(:entity_name) do
    standard_entity_fields(
      except: [:slug, :description, :type_fields, :metadata, :audit_fields]
    )
  end

  standard_indexes(:entity_name, has: [:status])
  create unique_index(:entity_name, [:name])
end
```

### Pattern 3: Immutable Log/Event Table

**When**: Creating audit logs, events, or other write-once data.

```elixir
def change do
  create table(:entity_name) do
    add :data_fields, :type

    audit_fields(only: :created_by_urm_id)
    timestamps(only: :inserted_at)
  end

  audit_indexes(:entity_name, only: :created_by_urm_id)
  create index(:entity_name, [:inserted_at])
end
```

### Pattern 4: Soft Delete Entity

**When**: Entities that should be soft-deleted rather than hard-deleted.

```elixir
def change do
  create table(:entity_name) do
    standard_entity_fields()
    deleted_fields()

    # Custom fields
  end

  standard_indexes(:entity_name, has: [:slug, :status, :type_fields, :audit_fields, :deleted_fields])

  # Partial indexes for active records
  create index(:entity_name, [:custom_field], where: "deleted_at IS NULL")
end
```

### Pattern 5: Foundation/Bootstrap Table

**When**: Creating tables before user_role_mappings exists (no audit references).

```elixir
def change do
  create table(:entity_name) do
    standard_entity_fields(except: [:audit_fields])

    # Or with audit fields but no FK:
    # audit_fields(references: false)
  end

  standard_indexes(:entity_name, has: [:slug, :status, :type_fields])
end
```

### Pattern 6: Join/Association Table

**When**: Creating many-to-many relationship tables.

```elixir
def change do
  create table(:entity_a_entity_b, primary_key: false) do
    add :entity_a_id, references(:entity_a, type: :uuid), null: false
    add :entity_b_id, references(:entity_b, type: :uuid), null: false

    # Optional: Track who created association
    audit_fields(only: :created_by_urm_id)
    timestamps(only: :inserted_at)
  end

  create unique_index(:entity_a_entity_b, [:entity_a_id, :entity_b_id])
  create index(:entity_a_entity_b, [:entity_b_id])  # For reverse lookups
end
```

---

## Common Scenarios

### Scenario 1: "I want a simple table with just name and timestamps"

```elixir
create table(:simple_things) do
  standard_entity_fields(
    except: [:slug, :description, :status, :type_fields, :metadata, :audit_fields]
  )
end

standard_indexes(:simple_things, has: [])  # No standard indexes
create unique_index(:simple_things, [:name])
```

### Scenario 2: "I need full audit trail with soft delete"

```elixir
create table(:audited_things) do
  standard_entity_fields(null: false)  # Required audit
  deleted_fields()

  # Custom fields
end

standard_indexes(:audited_things,
  has: [:slug, :status, :type_fields, :audit_fields, :deleted_fields]
)
```

### Scenario 3: "I only need type classification, nothing else"

```elixir
create table(:typed_things) do
  add :name, :citext, null: false

  type_fields(type_default: "standard")
  timestamps()
end

type_indexes(:typed_things)
create unique_index(:typed_things, [:name])
```

### Scenario 4: "I'm migrating an existing table to add soft delete"

```elixir
def change do
  alter table(:existing_table) do
    deleted_fields()
  end

  deleted_indexes(:existing_table)
end
```

### Scenario 5: "I need indexes but the table is huge (production)"

```elixir
# Don't use change, use up/down for concurrent
def up do
  standard_indexes(:huge_table, concurrently: true)
end

def down do
  drop index(:huge_table, [:slug])
  drop index(:huge_table, [:status])
  # etc...
end
```

---

## Troubleshooting

### Error: "cannot specify both :only and :except options"

**Cause**: You're using both `:only` and `:except` on the same macro.

**Fix**: Choose one or the other.

```elixir
# ❌ Wrong
type_fields(only: :type, except: :subtype)

# ✅ Correct
type_fields(only: :type)
# or
type_fields(except: :subtype)
```

### Error: Index creation fails with "relation does not exist"

**Cause**: Trying to index fields that weren't added to the table.

**Fix**: Use `:has` option to specify what fields exist.

```elixir
# ❌ Wrong
standard_entity_fields(except: [:slug])
standard_indexes(:table)  # Tries to index slug!

# ✅ Correct
standard_entity_fields(except: [:slug])
standard_indexes(:table, has: [:status, :type_fields, :audit_fields])
```

### Compilation Warning: unused variable

**Cause**: Using options that aren't applicable to a macro.

**Fix**: Check the macro's documentation for supported options.

---

## Additional Resources

- [Ecto.Migration Documentation](https://hexdocs.pm/ecto_sql/Ecto.Migration.html)
- [PostgreSQL Indexing Best Practices](https://www.postgresql.org/docs/current/indexes.html)
- [UUIDv7 RFC](https://datatracker.ietf.org/doc/html/rfc9562)

---

**Version**: 2.0
**Last Updated**: 2024-01-09
