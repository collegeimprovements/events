# Events Migration System Reference

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [Field Sets](#field-sets)
5. [Indexes](#indexes)
6. [Examples](#examples)
7. [Best Practices](#best-practices)

## Overview

The Events migration system provides a clean, modular DSL for PostgreSQL migrations with:
- **UUIDv7 Primary Keys** - Automatic generation for PostgreSQL 18+
- **Field Sets** - Predefined combinations for common patterns
- **Smart Indexes** - Automatic index creation with naming conventions
- **Pattern Matching** - Clean option handling throughout
- **Pipelines** - Functional composition for transformations

## Architecture

The migration system is organized into focused modules:

```
lib/events/migration/
├── token.ex                  # Core token data structure
├── token_validator.ex        # Token validation logic
├── pipeline.ex               # Pipeline functions (with_* pattern)
├── pipeline_extended.ex      # Extended pipeline functions
├── field_macros.ex           # Field macros for pipelines
├── field_definitions.ex      # Single source of truth for field types
├── dsl.ex                    # DSL functions
├── dsl_enhanced.ex           # Enhanced DSL with Ecto macros
├── executor.ex               # Migration execution
├── helpers.ex                # Utility functions
├── fields.ex                 # Field operations
└── field_builders/           # Behavior-based field builders
    ├── audit_fields.ex       # Audit field builder
    ├── soft_delete.ex        # Soft delete field builder
    ├── timestamps.ex         # Timestamp field builder
    ├── status_fields.ex      # Status field builder
    └── type_fields.ex        # Type field builder
```

### Module Overview

| Module | Purpose |
|--------|---------|
| `Token` | Core data structure representing a migration token |
| `TokenValidator` | Validates tokens before execution |
| `Pipeline` | Functional composition with `with_*` pattern |
| `FieldMacros` | Reusable field macros for tokens |
| `FieldDefinitions` | Single source of truth for field types |
| `DSLEnhanced` | Ecto.Migration macro wrappers |
| `FieldBuilders.*` | Behavior-based field generation |

## Quick Start

### Pipeline API (Recommended)

The pipeline API provides functional composition with the `with_*` pattern:

```elixir
alias Events.Migration.{Token, Pipeline}

# Create a table using pipelines
token =
  Token.new(:table, :users)
  |> Pipeline.with_uuid_primary_key()
  |> Pipeline.with_identity(:email)
  |> Pipeline.with_authentication()
  |> Pipeline.with_soft_delete()
  |> Pipeline.with_timestamps()

# Validate and execute
token
|> Pipeline.validate!()
|> Events.Migration.Executor.execute()
```

### DSL Enhanced (Ecto Macro Based)

For use within Ecto migrations:

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration
  import Events.Migration.DSLEnhanced

  def change do
    create table(:users, primary_key: false) do
      uuid_primary_key()
      type_fields(only: [:type, :category])
      status_fields(only: [:status])
      audit_fields(track_user: true)
      soft_delete_fields()
      timestamps(type: :utc_datetime_usec)
    end

    # Create indexes
    type_field_indexes(:users, only: [:type, :category])
    status_field_indexes(:users, only: [:status])
  end
end
```

### Basic Usage (Traditional)

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Repo.Migration

  def change do
    # Enable extensions
    enable_citext()

    # Create table with UUIDv7 primary key
    create_table :users do
      name_fields(type: :citext)
      email_field(unique: true)
      status_field()
      timestamps()
    end

    # Create indexes
    name_indexes(:users)
    status_indexes(:users)
  end
end
```

### Selective Import

```elixir
# Import only specific modules
use Events.Repo.Migration, only: [:field_sets, :indexes]

# Exclude specific modules
use Events.Repo.Migration, except: [:helpers]
```

## Field Sets

### Name Fields

Adds first_name, last_name, display_name, full_name fields.

```elixir
# Basic usage
name_fields()

# With options
name_fields(type: :citext, required: true, unique: true)
```

### Title Fields

Adds title, subtitle, short_title with optional translations.

```elixir
# Basic title fields
title_fields()

# With translations
title_fields(
  with_translations: true,
  languages: [:es, :fr, :de]
)
```

### Status Field

Adds status field with enum validation.

```elixir
# Default statuses
status_field()

# Custom statuses
status_field(
  values: ["pending", "processing", "completed"],
  default: "pending"
)
```

### Type Fields

Adds categorization fields.

```elixir
# Single type field
type_fields()

# Primary and secondary
type_fields(primary: :category, secondary: :subcategory)
```

### Metadata Field

Adds JSONB field for flexible data storage.

```elixir
# Basic metadata
metadata_field()

# Custom name and default
metadata_field(name: :settings, default: %{})
```

### Audit Fields

Adds created_by/updated_by tracking.

```elixir
# Basic audit
audit_fields()

# With user references
audit_fields(with_user: true)

# With role tracking
audit_fields(with_role: true, role_table: :user_roles)
```

### Deleted Fields

Adds soft delete support.

```elixir
# Basic soft delete
deleted_fields()

# With user tracking
deleted_fields(with_user: true)

# With reason
deleted_fields(with_reason: true)
```

## Specialized Field Macros

### Contact Fields

```elixir
# Email field
email_field(type: :citext, unique: true)

# Phone field
phone_field(name: :mobile)

# URL field
url_field(name: :website)
```

### Address Fields

```elixir
# Basic address
address_fields()

# With prefix for multiple addresses
address_fields(prefix: :billing)
address_fields(prefix: :shipping)
```

### Financial Fields

```elixir
# Money fields
money_field(:price, precision: 10, scale: 2)
money_field(:tax)
money_field(:total)

# Percentage
percentage_field(:discount)
percentage_field(:tax_rate, as: :decimal)
```

### Content Fields

```elixir
# Slug with unique constraint
slug_field()

# Tags as array
tags_field()

# Settings as JSONB
settings_field(name: :preferences)
```

### Media Fields

```elixir
# File attachment
file_fields(:avatar, with_metadata: true)

# Multiple files
file_fields(:document)
file_fields(:cover_image)
```

### Location Fields

```elixir
# Geolocation
geo_fields()

# With altitude and accuracy
geo_fields(with_altitude: true, with_accuracy: true)

# With prefix
geo_fields(prefix: :pickup)
```

### Counter Fields

```elixir
# Non-negative counter
counter_field(:view_count)
counter_field(:like_count)
counter_field(:stock_quantity)
```

## Indexes

### Name Indexes

```elixir
# Basic indexes
name_indexes(:users)

# With unique constraint
name_indexes(:users, unique: true)

# With fulltext search
name_indexes(:users, fulltext: true)
```

### Status Indexes

```elixir
# Basic status index
status_indexes(:orders)

# With partial index
status_indexes(:orders, partial: "status != 'deleted'")
```

### Timestamp Indexes

```elixir
# Basic timestamp indexes
timestamp_indexes(:events)

# With descending order
timestamp_indexes(:events, order: :desc)

# Custom fields
timestamp_indexes(:events, fields: [:created_at, :published_at])
```

### Deleted Indexes

```elixir
# Soft delete indexes
deleted_indexes(:users)

# With active record index
deleted_indexes(:users, active_index: true)
```

### Metadata Index

```elixir
# GIN index for JSONB
metadata_index(:products)

# Custom field
metadata_index(:products, field: :attributes)

# With specific paths
metadata_index(:products, paths: ["tags", "categories"])
```

### Custom Indexes

```elixir
# Unique index
unique_index(:users, :email)

# Composite unique
unique_index(:products, [:category, :sku])

# Partial unique
unique_index(:users, :email, where: "deleted_at IS NULL")
```

## Examples

### User Table

```elixir
create_table :users do
  # Identity
  name_fields(type: :citext, required: true)
  email_field(type: :citext, unique: true)

  # Authentication
  add :password_hash, :string, null: false
  add :confirmed_at, :utc_datetime

  # Profile
  url_field(name: :website)
  settings_field(name: :preferences)

  # Status
  status_field()
  deleted_fields()
  timestamps()
end
```

### Product Table

```elixir
create_table :products do
  # Identity
  add :sku, :string, null: false
  title_fields(with_translations: true)
  slug_field()

  # Categorization
  type_fields(primary: :category, secondary: :subcategory)
  tags_field()

  # Pricing
  money_field(:price)
  percentage_field(:discount)

  # Inventory
  counter_field(:stock_quantity)

  # Metadata
  metadata_field(name: :specifications)

  # Audit
  audit_fields(with_user: true)
  timestamps()
end
```

### Order Table

```elixir
create_table :orders do
  # Identification
  add :order_number, :string, null: false

  # Relationships
  add :customer_id, references(:users, type: :binary_id)

  # Status
  status_field(values: [
    "pending", "confirmed", "shipped", "delivered"
  ])

  # Financial
  money_field(:subtotal)
  money_field(:tax)
  money_field(:total, required: true)

  # Timestamps
  add :placed_at, :utc_datetime, null: false
  add :shipped_at, :utc_datetime
  timestamps()
end
```

## Best Practices

### 1. Use Field Sets

Prefer field sets over manual field definitions:

```elixir
# Good - consistent and maintainable
name_fields(type: :citext)

# Avoid - manual and error-prone
add :first_name, :citext
add :last_name, :citext
```

### 2. Leverage Type Safety

Use appropriate field types with constraints:

```elixir
# Money with precision
money_field(:price, precision: 10, scale: 2)

# Counter with non-negative constraint
counter_field(:quantity)

# Percentage with range check
percentage_field(:discount)
```

### 3. Create Appropriate Indexes

Add indexes based on query patterns:

```elixir
# Partial index for active records
status_indexes(:users, partial: "deleted_at IS NULL")

# Composite index for common queries
create index(:orders, [:customer_id, :status])

# GIN index for JSONB searches
metadata_index(:products, field: :attributes)
```

### 4. Use Soft Deletes

Prefer soft deletes for data recovery:

```elixir
# Add soft delete fields
deleted_fields(with_user: true, with_reason: true)

# Create appropriate indexes
deleted_indexes(:users, active_index: true)
```

### 5. Add Audit Trail

Track changes for compliance:

```elixir
# User and role tracking
audit_fields(with_user: true, with_role: true)

# Timestamp tracking
timestamps()
```

### 6. Organize Migrations

Structure migrations logically:

```elixir
def change do
  # 1. Extensions
  enable_citext()

  # 2. Table creation
  create_table :table_name do
    # Identity fields
    # Relationship fields
    # Data fields
    # Metadata fields
    # Audit fields
    # Timestamps
  end

  # 3. Indexes
  # 4. Constraints
  # 5. Triggers (if any)
end
```

## Migration Patterns

### Multi-tenant

```elixir
create_table :tenants do
  add :subdomain, :citext, null: false
  name_fields(type: :string, required: true)
  status_field()
  settings_field()
  timestamps()
end

create unique_index(:tenants, [:subdomain])
```

### Hierarchical Data

```elixir
create_table :categories do
  title_fields()
  slug_field()
  add :parent_id, references(:categories, type: :binary_id)
  add :path, :string  # Materialized path
  add :depth, :integer, default: 0
  counter_field(:children_count)
  timestamps()
end

create index(:categories, [:parent_id])
create index(:categories, [:path])
```

### Event Sourcing

```elixir
create_table :events do
  add :aggregate_id, :binary_id, null: false
  add :event_type, :string, null: false
  add :event_data, :jsonb, null: false
  add :event_metadata, :jsonb, default: "{}"
  add :version, :integer, null: false
  add :occurred_at, :utc_datetime, null: false
  timestamps(updated_at: false)  # Events are immutable
end

create index(:events, [:aggregate_id, :version])
create index(:events, [:event_type])
create index(:events, [:occurred_at])
```

## Troubleshooting

### UUIDv7 Not Available

If PostgreSQL < 18:

```elixir
# Use uuid-ossp extension instead
execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

# Use uuid_generate_v4() instead of uuidv7()
add :id, :binary_id, primary_key: true,
    default: fragment("uuid_generate_v4()")
```

### Case-Insensitive Search

Enable citext extension:

```elixir
enable_citext()

# Use :citext type
add :email, :citext, null: false
```

### Performance Issues

1. Add appropriate indexes
2. Use partial indexes for filtered queries
3. Consider composite indexes for multi-column queries
4. Use GIN indexes for JSONB/array searches

## Reference

### Field Types

- `:string` - Variable length text
- `:text` - Unlimited text
- `:integer` - 32-bit integer
- `:bigint` - 64-bit integer
- `:decimal` - Precise decimal
- `:float` - Floating point
- `:boolean` - True/false
- `:date` - Date without time
- `:time` - Time without date
- `:utc_datetime` - UTC timestamp
- `:naive_datetime` - Timestamp without timezone
- `:binary_id` - UUID
- `:jsonb` - JSON binary
- `{:array, type}` - Array of type
- `:citext` - Case-insensitive text

### Index Options

- `:unique` - Unique constraint
- `:where` - Partial index condition
- `:using` - Index method (btree, gin, gist)
- `:order` - Sort order (:asc, :desc)
- `:name` - Custom index name

### Constraint Options

- `:null` - Allow NULL values
- `:default` - Default value
- `:primary_key` - Primary key constraint
- `:references` - Foreign key reference
- `:on_delete` - Foreign key delete action
- `:on_update` - Foreign key update action