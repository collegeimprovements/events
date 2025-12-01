# Schema & Migration Reference

> **Always use `Events.Core.Schema` and `Events.Core.Migration`** instead of raw Ecto.
> For complete reference, see `docs/EVENTS_REFERENCE.md`.

## Schema Rules

### 1. Always Use Events.Schema

```elixir
# CORRECT
use Events.Core.Schema

# WRONG
use Ecto.Schema
```

### 2. Use Field Group Macros

```elixir
schema "users" do
  # Custom fields first
  field :name, :string, required: true
  field :email, :string, required: true, format: :email

  # Then field groups
  type_fields()
  status_fields(values: [:active, :inactive], default: :active)
  audit_fields()
  timestamps()
end
```

### 3. Use Presets for Common Patterns

```elixir
import Events.Core.Schema.Presets

field :email, :string, email()
field :username, :string, username()
field :password, :string, password()
field :phone, :string, phone()
field :url, :string, url()
field :slug, :string, slug()
```

### 4. Validation Options on Fields

```elixir
field :age, :integer, required: true, positive: true, max: 150
field :email, :string, required: true, format: :email, mappers: [:trim, :downcase]
field :name, :string, required: true, min: 2, max: 100, mappers: [:trim, :squish]
```

### 5. Use base_changeset/3

```elixir
def changeset(user, attrs) do
  user
  |> base_changeset(attrs)
  |> unique_constraints([{:email, []}])
end
```

---

## Migration Rules

### 1. Always Use Events.Migration

```elixir
# CORRECT
use Events.Core.Migration

# WRONG
use Ecto.Migration
```

### 2. Pipeline Pattern for Tables

```elixir
def change do
  create_table(:users)
  |> with_uuid_primary_key()
  |> with_identity(:name, :email)
  |> with_audit()
  |> with_soft_delete()
  |> with_timestamps()
  |> execute()
end
```

### 3. DSL Macros in Create Blocks

```elixir
create table(:products, primary_key: false) do
  uuid_primary_key()
  type_fields()
  status_fields()
  metadata_field()
  timestamps(type: :utc_datetime_usec)
end
```

---

## Quick Reference

### Schema Presets

| Preset | Description |
|--------|-------------|
| `email()` | Email validation with trim/downcase |
| `username()` | Alphanumeric, 3-30 chars |
| `password()` | Min 8 chars, redacted |
| `phone()` | Phone format validation |
| `url()` | URL format validation |
| `slug()` | URL-safe slug |
| `money()` | Decimal with 2 precision |
| `percentage()` | 0-100 range |
| `age()` | 0-150 range |
| `rating()` | 1-5 range |
| `latitude()` | -90 to 90 |
| `longitude()` | -180 to 180 |

### Field Groups

| Group | Fields Added |
|-------|--------------|
| `type_fields()` | `type`, `subtype` |
| `status_fields()` | `status`, `substatus` |
| `audit_fields()` | `created_by_id`, `updated_by_id` |
| `timestamps()` | `inserted_at`, `updated_at` |
| `metadata_field()` | `metadata` (JSONB) |
| `soft_delete_field()` | `deleted_at`, `deleted_by_id` |
| `standard_fields()` | All of the above |

### Migration Pipelines

| Function | Description |
|----------|-------------|
| `with_uuid_primary_key()` | UUIDv7 primary key |
| `with_identity(:name, :email)` | Identity fields |
| `with_authentication()` | Password hash, tokens |
| `with_profile()` | Name, avatar, bio |
| `with_type_fields()` | Type/subtype |
| `with_status_fields()` | Status tracking |
| `with_metadata()` | JSONB metadata |
| `with_tags()` | Tags array |
| `with_audit()` | Audit fields |
| `with_soft_delete()` | Soft delete |
| `with_timestamps()` | Timestamps |

### Mappers

| Mapper | Effect |
|--------|--------|
| `:trim` | Remove leading/trailing whitespace |
| `:downcase` | Lowercase string |
| `:upcase` | Uppercase string |
| `:capitalize` | Capitalize first letter |
| `:titlecase` | Capitalize each word |
| `:squish` | Trim + collapse internal whitespace |
| `:slugify` | Convert to URL-safe slug |
| `:digits_only` | Remove non-digits |
| `:alphanumeric_only` | Remove non-alphanumeric |

---

## Database Conventions

### Field Types

| Use Case | Migration Type | Schema Type |
|----------|---------------|-------------|
| Names, identifiers | `:citext` | `:string` |
| Long text | `:text` | `:string` |
| Structured data | `:jsonb` | `:map` |
| Timestamps | `:utc_datetime_usec` | `:utc_datetime_usec` |
| Money | `:integer` (cents) | `:integer` |
| Precise decimals | `:decimal` | `:decimal` |

### Soft Delete

```elixir
# Migration
deleted_fields()  # Adds deleted_at and deleted_by_id

# Query - always filter deleted
def list_products do
  from p in Product, where: is_nil(p.deleted_at)
end

# Soft delete
def delete_product(product, deleted_by_id) do
  product
  |> Ecto.Changeset.change(%{
    deleted_at: DateTime.utc_now(),
    deleted_by_id: deleted_by_id
  })
  |> Repo.update()
end

# Restore
def restore_product(product) do
  product
  |> Ecto.Changeset.change(%{deleted_at: nil, deleted_by_id: nil})
  |> Repo.update()
end
```
