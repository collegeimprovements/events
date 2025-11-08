# Migration Macros Reference

Complete reference table for all field and index macros in `Events.Repo.MigrationMacros`.

---

## Field Macros Reference

| Field Name | Field Macro | Field Type | Available Options | Index Macro | Index Type | Available Index Options | Example |
|------------|-------------|------------|-------------------|-------------|------------|-------------------------|---------|
| `type` | `type_fields/1` | Type Classification | `:only`, `:except`, `:type_default`, `:subtype_default`, `:null` | `type_indexes/2` | Standard B-tree | `:only`, `:except`, `:where`, `:name`, `:unique`, `:concurrently`, `:composite` | `type_fields(type_default: "standard")`<br>`type_indexes(:table, where: "deleted_at IS NULL")` |
| `subtype` | `type_fields/1` | Type Classification | `:only`, `:except`, `:type_default`, `:subtype_default`, `:null` | `type_indexes/2` | Standard B-tree | `:only`, `:except`, `:where`, `:name`, `:unique`, `:concurrently`, `:composite` | `type_fields(only: :type)`<br>`type_indexes(:table, only: :type)` |
| `metadata` | `metadata_field/1` | JSONB Storage | `:null`, `:default` | `metadata_index/2` | GIN | `:name`, `:concurrently`, `:json_path`, `:using` | `metadata_field()`<br>`metadata_index(:table, json_path: "status")` |
| `created_by_urm_id` | `audit_fields/1` | Audit Tracking | `:only`, `:except`, `:references`, `:on_delete`, `:null` | `audit_indexes/2` | Standard B-tree (FK) | `:only`, `:except`, `:where`, `:name`, `:concurrently` | `audit_fields(null: false)`<br>`audit_indexes(:table)` |
| `updated_by_urm_id` | `audit_fields/1` | Audit Tracking | `:only`, `:except`, `:references`, `:on_delete`, `:null` | `audit_indexes/2` | Standard B-tree (FK) | `:only`, `:except`, `:where`, `:name`, `:concurrently` | `audit_fields(only: :created_by_urm_id)`<br>`audit_indexes(:table, only: :created_by_urm_id)` |
| `deleted_at` | `deleted_fields/1` | Soft Delete | `:only`, `:except`, `:null` | `deleted_indexes/2` | Standard B-tree | `:only`, `:except`, `:where`, `:name`, `:concurrently` | `deleted_fields()`<br>`deleted_indexes(:table)` |
| `deleted_by_urm_id` | `deleted_fields/1` | Soft Delete | `:only`, `:except`, `:references`, `:on_delete`, `:null` | `deleted_indexes/2` | Standard B-tree (FK) | `:only`, `:except`, `:where`, `:name`, `:concurrently` | `deleted_fields(only: :deleted_at)`<br>`deleted_indexes(:table, only: :deleted_at)` |
| `inserted_at` | `timestamps/1` | Timestamps | `:only`, `:except` | `timestamp_indexes/2` | Standard B-tree | `:only`, `:except`, `:where`, `:name`, `:concurrently`, `:composite_with` | `timestamps()`<br>`timestamp_indexes(:table, composite_with: [:status])` |
| `updated_at` | `timestamps/1` | Timestamps | `:only`, `:except` | `timestamp_indexes/2` | Standard B-tree | `:only`, `:except`, `:where`, `:name`, `:concurrently`, `:composite_with` | `timestamps(only: :updated_at)`<br>`timestamp_indexes(:table, only: :updated_at)` |
| `name` | `standard_entity_fields/1` | Standard Entity | `:include_name`, `:except` | `standard_indexes/2` | Not indexed by default | N/A | `standard_entity_fields()`<br>`create unique_index(:table, [:name])` |
| `slug` | `standard_entity_fields/1` | Standard Entity | `:include_slug`, `:except` | `standard_indexes/2` | Unique B-tree | `:slug_unique`, `:has`, `:only`, `:except`, `:concurrently` | `standard_entity_fields()`<br>`standard_indexes(:table)` |
| `status` | `standard_entity_fields/1` | Standard Entity | `:status_default`, `:except` | `standard_indexes/2` | Partial B-tree | `:status_where`, `:has`, `:only`, `:except`, `:concurrently` | `standard_entity_fields(status_default: "active")`<br>`standard_indexes(:table, status_where: "status = 'active'")` |
| `description` | `standard_entity_fields/1` | Standard Entity | `:include_description`, `:except` | `standard_indexes/2` | Not indexed by default | N/A | `standard_entity_fields()`<br>_No index recommended_ |

---

## Complete Field Options Reference

### `type_fields/1`

**Field Type**: Type Classification

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Add only specific field | `:type`, `:subtype` |
| `:except` | atom | `nil` | Exclude specific field | `:type`, `:subtype` |
| `:type_default` | string | `nil` | Default value for type field | Any string |
| `:subtype_default` | string | `nil` | Default value for subtype field | Any string |
| `:null` | boolean | `true` | Allow NULL values | `true`, `false` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both fields with defaults
type_fields(type_default: "event", subtype_default: "conference")

# Only type field, required
type_fields(only: :type, type_default: "standard", null: false)

# Exclude subtype
type_fields(except: :subtype)
```

---

### `metadata_field/1`

**Field Type**: JSONB Storage

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:null` | boolean | `false` | Allow NULL values | `true`, `false` |
| `:default` | fragment | `fragment("'{}'")` | Default JSON value | Any `fragment()` |

**Examples**:
```elixir
# Standard usage (empty object, NOT NULL)
metadata_field()

# Allow NULL
metadata_field(null: true)

# Custom default with version
metadata_field(default: fragment("'{\"version\": 1}'"))
```

---

### `audit_fields/1`

**Field Type**: Audit Tracking

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Add only specific field | `:created_by_urm_id`, `:updated_by_urm_id` |
| `:except` | atom | `nil` | Exclude specific field | `:created_by_urm_id`, `:updated_by_urm_id` |
| `:references` | boolean | `true` | Add FK constraints | `true`, `false` |
| `:on_delete` | atom | `:nilify_all` | FK deletion behavior | `:nothing`, `:delete_all`, `:nilify_all`, `:restrict` |
| `:null` | boolean | `true` | Allow NULL values | `true`, `false` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Standard usage with FK constraints
audit_fields()

# Only track creator
audit_fields(only: :created_by_urm_id)

# Required audit trail
audit_fields(null: false)

# Without FK constraints (for early migrations)
audit_fields(references: false)
```

---

### `deleted_fields/1`

**Field Type**: Soft Delete

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Add only specific field | `:deleted_at`, `:deleted_by_urm_id` |
| `:except` | atom | `nil` | Exclude specific field | `:deleted_at`, `:deleted_by_urm_id` |
| `:references` | boolean | `true` | Add FK constraint for deleted_by | `true`, `false` |
| `:on_delete` | atom | `:nilify_all` | FK deletion behavior | `:nothing`, `:delete_all`, `:nilify_all`, `:restrict` |
| `:null` | boolean | `true` | Allow NULL values | `true`, `false` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both fields (timestamp + who deleted)
deleted_fields()

# Only timestamp
deleted_fields(only: :deleted_at)

# Exclude who deleted
deleted_fields(except: :deleted_by_urm_id)
```

---

### `timestamps/1`

**Field Type**: Timestamps

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Add only specific field | `:inserted_at`, `:updated_at` |
| `:except` | atom | `nil` | Exclude specific field | `:inserted_at`, `:updated_at` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both fields (default)
timestamps()

# Only inserted_at (immutable records)
timestamps(only: :inserted_at)

# Exclude updated_at
timestamps(except: :updated_at)
```

---

### `standard_entity_fields/1`

**Field Type**: Standard Entity (All-in-one)

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:include_name` | boolean | `true` | Add name field | `true`, `false` |
| `:include_slug` | boolean | `true` | Add slug field | `true`, `false` |
| `:include_description` | boolean | `true` | Add description field | `true`, `false` |
| `:except` | list | `[]` | Exclude field groups | `[:name, :slug, :status, :description, :type_fields, :metadata, :audit_fields, :timestamps]` |
| `:status_default` | string | `"active"` | Default status value | Any string |
| `:type_default` | string | `nil` | Default type value | Any string |
| `:null` | boolean | `true` | Allow NULL for audit fields | `true`, `false` |
| `:references` | boolean | `true` | Add FK constraints for audit | `true`, `false` |

**Examples**:
```elixir
# Full standard entity
standard_entity_fields()

# Exclude slug and description
standard_entity_fields(except: [:slug, :description])

# Exclude entire field groups
standard_entity_fields(except: [:type_fields, :audit_fields])

# Custom status default
standard_entity_fields(status_default: "pending")
```

---

## Complete Index Options Reference

### `type_indexes/2`

**Index Type**: Standard B-tree

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Index only specific field | `:type`, `:subtype` |
| `:except` | atom | `nil` | Skip indexing specific field | `:type`, `:subtype` |
| `:where` | string | `nil` | Partial index condition | SQL WHERE clause |
| `:name` | atom/string | Auto-generated | Custom index name | Any valid identifier |
| `:unique` | boolean | `false` | Create unique index | `true`, `false` |
| `:concurrently` | boolean | `false` | Create concurrently | `true`, `false` |
| `:composite` | boolean | `false` | Composite index on both fields | `true`, `false` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both fields
type_indexes(:products)

# Only type field
type_indexes(:products, only: :type)

# Partial index for non-deleted
type_indexes(:products, where: "deleted_at IS NULL")

# Unique type
type_indexes(:products, only: :type, unique: true)

# Composite index
type_indexes(:products, composite: true)

# Production-safe
type_indexes(:products, concurrently: true)
```

---

### `audit_indexes/2`

**Index Type**: Standard B-tree (Foreign Key)

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Index only specific field | `:created_by_urm_id`, `:updated_by_urm_id` |
| `:except` | atom | `nil` | Skip indexing specific field | `:created_by_urm_id`, `:updated_by_urm_id` |
| `:where` | string | `nil` | Partial index condition | SQL WHERE clause |
| `:name` | atom/string | Auto-generated | Custom index name | Any valid identifier |
| `:concurrently` | boolean | `false` | Create concurrently | `true`, `false` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both audit fields
audit_indexes(:products)

# Only creator
audit_indexes(:products, only: :created_by_urm_id)

# Partial index for active records
audit_indexes(:products, where: "deleted_at IS NULL")

# Production-safe
audit_indexes(:products, concurrently: true)
```

---

### `deleted_indexes/2`

**Index Type**: Standard B-tree

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Index only specific field | `:deleted_at`, `:deleted_by_urm_id` |
| `:except` | atom | `nil` | Skip indexing specific field | `:deleted_at`, `:deleted_by_urm_id` |
| `:where` | string | `nil` | Partial index condition | SQL WHERE clause |
| `:name` | atom/string | Auto-generated | Custom index name | Any valid identifier |
| `:concurrently` | boolean | `false` | Create concurrently | `true`, `false` |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both fields
deleted_indexes(:documents)

# Only timestamp
deleted_indexes(:documents, only: :deleted_at)

# Partial index for deleted records
deleted_indexes(:documents, where: "deleted_at IS NOT NULL")

# Custom name
deleted_indexes(:documents, name: :docs_soft_delete_idx)
```

---

### `timestamp_indexes/2`

**Index Type**: Standard B-tree

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:only` | atom | `nil` | Index only specific field | `:inserted_at`, `:updated_at` |
| `:except` | atom | `nil` | Skip indexing specific field | `:inserted_at`, `:updated_at` |
| `:where` | string | `nil` | Partial index condition | SQL WHERE clause |
| `:name` | atom/string | Auto-generated | Custom index name | Any valid identifier |
| `:concurrently` | boolean | `false` | Create concurrently | `true`, `false` |
| `:composite_with` | list | `nil` | Create composite with other fields | List of field atoms |

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Both timestamps
timestamp_indexes(:products)

# Only updated_at
timestamp_indexes(:products, only: :updated_at)

# Composite with status
timestamp_indexes(:products, only: :updated_at, composite_with: [:status])
# Creates: index on [:status, :updated_at]

# For recent active records
timestamp_indexes(:products,
  only: :inserted_at,
  where: "status = 'active'",
  name: :recent_active_products
)
```

---

### `metadata_index/2`

**Index Type**: GIN (Generalized Inverted Index)

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:name` | atom/string | Auto-generated | Custom index name | Any valid identifier |
| `:concurrently` | boolean | `false` | Create concurrently | `true`, `false` |
| `:json_path` | string | `nil` | Index specific JSON key | JSON key path |
| `:using` | atom | `:gin` | Index method | `:gin`, `:gist`, `:btree`, etc. |

**⚠️ Performance Note**: GIN indexes are expensive. Only create if frequently querying JSON keys.

**Examples**:
```elixir
# Full GIN index
metadata_index(:products)

# Specific JSON key (more efficient)
metadata_index(:products, json_path: "status")
# Creates: index on (metadata->>'status')

# Multiple specific keys
metadata_index(:products, json_path: "external_id")
metadata_index(:products, json_path: "sync_status")

# Production-safe
metadata_index(:products, concurrently: true)
```

---

### `standard_indexes/2`

**Index Type**: Multiple (Unique B-tree, Partial B-tree, Standard B-tree)

| Option | Type | Default | Description | Valid Values |
|--------|------|---------|-------------|--------------|
| `:has` | atom/list | `:all` | What field groups exist | `:all` or list of field groups |
| `:only` | list | `[]` | Create indexes only for these groups | List of field groups |
| `:except` | list | `[]` | Skip indexes for these groups | List of field groups |
| `:slug_unique` | boolean | `true` | Make slug index unique | `true`, `false` |
| `:status_where` | string | `"deleted_at IS NULL"` | WHERE clause for status | SQL WHERE clause or `nil` |
| `:concurrently` | boolean | `false` | Create all indexes concurrently | `true`, `false` |
| `:composite` | list | `[]` | Additional composite indexes | List of field lists |

**Field Groups**: `:slug`, `:status`, `:type_fields`, `:audit_fields`, `:deleted_fields`, `:timestamps`, `:metadata`

**Mutually Exclusive**: `:only` and `:except`

**Examples**:
```elixir
# Full standard entity (assumes standard_entity_fields was used)
standard_indexes(:products)
# Creates: slug (unique), status (partial), type, subtype, created_by_urm_id, updated_by_urm_id

# Partial fields - be explicit
standard_indexes(:categories, has: [:status, :type_fields])
# Only creates: status, type, subtype indexes

# With deleted fields
standard_indexes(:documents,
  has: [:slug, :status, :type_fields, :audit_fields, :deleted_fields]
)

# Production-safe
standard_indexes(:products, concurrently: true)

# Custom status condition
standard_indexes(:products, status_where: "status IN ('active', 'pending')")

# No status WHERE clause
standard_indexes(:products, status_where: nil)

# Additional composite indexes
standard_indexes(:products, composite: [
  [:type, :status],
  [:status, :updated_at]
])

# Only specific groups
standard_indexes(:products, only: [:slug, :status])

# Skip specific groups
standard_indexes(:products, except: [:metadata, :timestamps])
```

---

## Common Option Patterns

### `:only` vs `:except` Pattern

**Rule**: These are mutually exclusive. Choose one approach.

| Scenario | Use `:only` | Use `:except` |
|----------|-------------|---------------|
| Need 1 field from 2 | ✅ `only: :field1` | ✅ `except: :field2` |
| Need most fields | ❌ Verbose | ✅ `except: [:field3]` |
| Need few fields | ✅ `only: [:field1, :field2]` | ❌ Verbose |
| Need all fields | ❌ Not needed | ❌ Not needed |

### Partial Index Patterns

| Use Case | WHERE Clause | Example |
|----------|--------------|---------|
| Active records only | `"deleted_at IS NULL"` | `type_indexes(:table, where: "deleted_at IS NULL")` |
| Active + specific status | `"deleted_at IS NULL AND status = 'active'"` | `type_indexes(:table, where: "deleted_at IS NULL AND status = 'active'")` |
| Deleted records | `"deleted_at IS NOT NULL"` | `deleted_indexes(:table, where: "deleted_at IS NOT NULL")` |
| Date range | `"created_at > '2024-01-01'"` | `timestamp_indexes(:table, where: "created_at > '2024-01-01'")` |

### Production Migration Patterns

| Scenario | Options | Example |
|----------|---------|---------|
| Zero-downtime index | `:concurrently` | `standard_indexes(:table, concurrently: true)` |
| Custom naming | `:name` | `type_indexes(:table, name: :custom_idx)` |
| Composite queries | `:composite_with` | `timestamp_indexes(:table, composite_with: [:status, :type])` |

---

## Quick Reference: Complete Example

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    # ====================
    # TABLE CREATION
    # ====================
    create table(:products) do
      # Standard fields (name, slug, status, description, type, subtype, metadata, audit, timestamps)
      standard_entity_fields(
        status_default: "draft",
        type_default: "physical"
      )

      # Soft delete
      deleted_fields()

      # Custom fields
      add :sku, :citext, null: false
      add :price, :decimal, precision: 10, scale: 2
    end

    # ====================
    # INDEX CREATION
    # ====================

    # All standard indexes
    standard_indexes(:products,
      has: [:slug, :status, :type_fields, :audit_fields, :deleted_fields],
      status_where: "status IN ('active', 'draft') AND deleted_at IS NULL"
    )

    # Custom indexes
    create unique_index(:products, [:sku])
    create index(:products, [:price], where: "price > 0")

    # Composite for common queries
    create index(:products, [:type, :status, :updated_at])
  end
end
```

**Generated Indexes**:
1. `unique_index` on `[:slug]`
2. `index` on `[:status]` WHERE `status IN ('active', 'draft') AND deleted_at IS NULL`
3. `index` on `[:type]`
4. `index` on `[:subtype]`
5. `index` on `[:created_by_urm_id]`
6. `index` on `[:updated_by_urm_id]`
7. `index` on `[:deleted_at]`
8. `index` on `[:deleted_by_urm_id]`
9. `unique_index` on `[:sku]`
10. `index` on `[:price]` WHERE `price > 0`
11. `index` on `[:type, :status, :updated_at]`

---

## Index Type Reference

| Index Type | SQL Type | Use Case | Performance | Example Field |
|------------|----------|----------|-------------|---------------|
| Standard B-tree | `USING btree` | Equality, range queries, sorting | Fast lookups, moderate writes | `type`, `status`, `created_by_urm_id` |
| Unique B-tree | `USING btree UNIQUE` | Enforce uniqueness, lookups | Fast lookups, moderate writes | `slug`, `email` |
| Partial B-tree | `USING btree WHERE ...` | Filtered queries | Smaller index, faster for subset | `status WHERE deleted_at IS NULL` |
| GIN | `USING gin` | JSONB queries, full-text search | Slower writes, fast JSONB queries | `metadata` |
| Composite | Multiple columns | Multi-column queries, sorting | Covers complex queries | `[:type, :status, :updated_at]` |

---

**Version**: 2.0
**Last Updated**: 2024-01-09
