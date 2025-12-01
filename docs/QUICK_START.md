# Quick Start Guide

## Migration Quick Reference

### Direct DSL Style (NEW - Recommended)

```elixir
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Events.Migration

  def change do
    create table(:products, primary_key: false) do
      uuid_primary_key()                    # UUIDv7 primary key
      add :name, :string, null: false
      type_fields(only: [:type])            # Only type field
      status_fields(only: [:status])        # Only status field
      timestamps()                           # inserted_at, updated_at
    end

    # Create indexes
    type_field_indexes(:products, only: [:type])
    status_field_indexes(:products, only: [:status])
  end
end
```

### Pipeline Style (Original)

```elixir
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Events.Migration

  def change do
    create_table(:products)
    |> with_uuid_primary_key()           # UUIDv7 primary key
    |> with_field(:name, :string, null: false)
    |> with_type_fields(only: [:type])   # Only type field
    |> with_status_fields(only: [:status])
    |> with_timestamps()                  # inserted_at, updated_at
    |> execute()
  end
end
```

### All Field Macros

#### Direct DSL
```elixir
create table(:comprehensive, primary_key: false) do
  uuid_primary_key()
  type_fields()           # type, subtype, kind, category, variant
  status_fields()         # status, substatus, state, workflow_state, approval_status
  audit_fields()          # created_by, updated_by
  timestamps()            # inserted_at, updated_at
  metadata_field()        # metadata jsonb field
  tags_field()           # tags array field
  soft_delete_fields()    # deleted_at, deleted_by
end

# Create all standard indexes
create_standard_indexes(:comprehensive)
```

#### Pipeline Style
```elixir
create_table(:comprehensive)
|> with_uuid_primary_key()
|> with_type_fields()           # type, subtype, kind, category, variant
|> with_status_fields()         # status, substatus, state, workflow_state, approval_status
|> with_audit_fields()          # created_by, updated_by
|> with_timestamps()            # inserted_at, updated_at
|> with_metadata()              # metadata jsonb field
|> with_tags()                  # tags array field
|> with_soft_delete()           # deleted_at, deleted_by
|> execute()
```

### Customization Examples

```elixir
# Select specific fields
with_type_fields(only: [:type, :subtype])
with_status_fields(except: [:approval_status])

# Add tracking
with_status_fields(with_transition: true)
with_audit_fields(track_user: true, track_ip: true)
with_timestamps(with_deleted: true, with_lifecycle: true)

# Change types (not recommended)
with_type_fields(type: :string)  # Use citext instead!
with_timestamps(type: :naive_datetime)  # Use utc_datetime_usec!
```

## Schema Quick Reference

### Basic Schema

```elixir
defmodule MyApp.Product do
  use Events.Schema
  import Events.Core.Schema.FieldMacros

  schema "products" do
    field :name, :string
    field :price, :decimal

    type_fields(only: [:type])
    status_fields(only: [:status])
    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :price, :type, :status])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than: 0)
  end
end
```

### Pipeline Validation Mode

```elixir
defmodule MyApp.User do
  use Events.Core.Schema.PipelineMode

  schema "users" do
    field :email, :string
    field :age, :integer
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs)
    |> validate(:email, :required, :email)
    |> validate(:age, min: 18, max: 120)
    |> apply()
  end
end
```

## Common Patterns

### User Account

```elixir
# Migration
create_table(:users)
|> with_uuid_primary_key()
|> with_field(:email, :citext, null: false)
|> with_field(:username, :citext, null: false)
|> with_field(:password_hash, :string, null: false)
|> with_status_fields(only: [:status])
|> with_audit_fields(track_user: true)
|> with_timestamps(with_deleted: true)
|> with_index(:users_email_unique, [:email], unique: true)
|> with_index(:users_username_unique, [:username], unique: true)
|> execute()

# Schema
schema "users" do
  field :email, :string
  field :username, :string
  field :password, :string, virtual: true
  field :password_hash, :string

  status_fields(only: [:status])
  audit_fields(track_user: true)
  soft_delete_fields()
  timestamps()
end
```

### E-commerce Product

```elixir
# Migration
create_table(:products)
|> with_uuid_primary_key()
|> with_field(:name, :string, null: false)
|> with_field(:sku, :string, null: false)
|> with_field(:price, :decimal, precision: 10, scale: 2)
|> with_field(:stock_quantity, :integer, default: 0)
|> with_type_fields(only: [:type, :category])
|> with_status_fields(only: [:status])
|> with_metadata()
|> with_tags()
|> with_timestamps()
|> with_index(:products_sku_unique, [:sku], unique: true)
|> execute()

# Schema
schema "products" do
  field :name, :string
  field :sku, :string
  field :price, :decimal
  field :stock_quantity, :integer

  type_fields(only: [:type, :category])
  status_fields(only: [:status])
  metadata_field()
  tags_field()
  timestamps()
end
```

### Blog Post

```elixir
# Migration
create_table(:posts)
|> with_uuid_primary_key()
|> with_field(:title, :string, null: false)
|> with_field(:slug, :string, null: false)
|> with_field(:content, :text)
|> with_field(:author_id, :binary_id, null: false)
|> with_type_fields(only: [:type])  # article, tutorial, news
|> with_status_fields(only: [:status, :state])  # draft, published, archived
|> with_metadata(name: :seo)
|> with_tags()
|> with_audit_fields(track_user: true)
|> with_timestamps(with_lifecycle: true)  # includes published_at
|> with_index(:posts_slug_unique, [:slug], unique: true)
|> with_index(:posts_author, [:author_id])
|> execute()
```

## Validation Quick Reference

### Common Validators

```elixir
# Required fields
validate(:email, :required)

# String validation
validate(:name, min: 3, max: 100)
validate(:username, format: ~r/^[a-z0-9_]+$/)

# Email/URL
validate(:email, :email)
validate(:website, :url)

# Numbers
validate(:age, min: 18, max: 120)
validate(:price, greater_than: 0)
validate(:quantity, :positive)

# Dates
validate(:birth_date, :past)
validate(:scheduled_for, :future)

# Enums
validate(:status, in: ["active", "pending", "archived"])

# Arrays
validate(:tags, min_length: 1, max_length: 10)

# Conditional
validate_if(:promo_code, :required, fn attrs ->
  attrs["has_discount"] == true
end)

# Cross-field
validate_confirmation(:password, :password_confirmation)
validate_comparison(:start_date, :<=, :end_date)
```

## Type Reference

| Elixir Type | PostgreSQL Type | Use Case |
|-------------|-----------------|----------|
| :binary_id | uuid | Foreign keys, IDs |
| :string | varchar(255) | Short text |
| :text | text | Long text |
| :citext | citext | Case-insensitive text |
| :integer | integer | Whole numbers |
| :decimal | decimal | Money, precision numbers |
| :boolean | boolean | True/false |
| :date | date | Date only |
| :utc_datetime | timestamp | Second precision |
| :utc_datetime_usec | timestamp(6) | Microsecond precision |
| :jsonb | jsonb | Structured data |
| {:array, :string} | text[] | Lists |

## Best Practices Checklist

✅ **DO:**
- Use UUIDv7 for primary keys
- Use citext for enums (type, status, kind)
- Use utc_datetime_usec for timestamps
- Add indexes for foreign keys
- Use field macros instead of manual fields
- Validate at schema level
- Use pipeline validation mode for complex logic

❌ **DON'T:**
- Use NaiveDateTime (use DateTime)
- Use :string for enums in migrations (use citext)
- Create fields manually when macros exist
- Validate in controllers
- Use gen_random_uuid() (use uuidv7())
- Include all field macro options by default

## Common Commands

### Generate Migration

```bash
mix ecto.gen.migration create_products
```

### Run Migrations

```bash
mix ecto.migrate
```

### Rollback

```bash
mix ecto.rollback
```

### Reset Database

```bash
mix ecto.reset
```

## Help Functions

```elixir
# Migration help
Events.Core.Migration.help()
Events.Core.Migration.help(:fields)
Events.Core.Migration.help(:indexes)

# Schema help
Events.Core.Schema.help()
Events.Core.Schema.help(:validators)
Events.Core.Schema.help(:pipelines)
```

## Troubleshooting

### Issue: "function uuidv7() does not exist"
**Solution**: Ensure PostgreSQL 18+ is installed

### Issue: "type citext does not exist"
**Solution**: Enable citext extension
```sql
CREATE EXTENSION IF NOT EXISTS "citext";
```

### Issue: Field type mismatch
**Solution**: Ensure migration and schema types align
```elixir
# Migration
with_type_fields()  # Creates citext fields

# Schema
field :type, :string  # For Ecto.Enum compatibility
```

### Issue: Validation not working
**Solution**: Check pipeline order
```elixir
# Good - cast first, then validate
|> cast(attrs)
|> validate(:email, :required)

# Bad - validate before cast
|> validate(:email, :required)
|> cast(attrs)
```