# OmMigration

Pipeline-based Ecto migrations with composable field helpers and a clean DSL.

## Installation

```elixir
def deps do
  [{:om_migration, "~> 0.1.0"}]
end
```

## Why OmMigration?

Traditional migrations are verbose and repetitive:

```
Traditional Ecto                       OmMigration
─────────────────────────────────────────────────────────────────────
create table(:users,                   create_table(:users)
       primary_key: false) do          |> with_uuid_primary_key()
  add :id, :binary_id,                 |> with_identity(:name, :email)
      primary_key: true,               |> with_authentication()
      default: fragment("...")         |> with_profile(:bio, :avatar)
  add :first_name, :string             |> with_audit()
  add :last_name, :string              |> with_soft_delete()
  add :email, :citext, null: false     |> with_timestamps()
  add :password_hash, :string          |> execute()
  add :confirmed_at, :utc_datetime
  add :bio, :text
  add :avatar_url, :string
  add :created_by_id, :binary_id
  # ... 20+ more lines
end
```

**Benefits:**
- **Pipeline Composition** - Chain transformations with `|>`
- **Field Helpers** - Common patterns with one function
- **Dual API** - Pipeline or DSL syntax
- **Testable Tokens** - Validate before executing
- **Built-in Indexes** - Auto-creates indexes where needed

---

## Quick Start

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use OmMigration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_fields(
      email: :string,
      name: :string,
      age: :integer
    )
    |> with_authentication()      # password_hash, confirmed_at, etc.
    |> with_audit()               # created_by_id, updated_by_id
    |> with_soft_delete()         # deleted_at
    |> with_timestamps()
    |> with_index(:email, unique: true)
    |> execute()
  end
end
```

---

## Two API Styles

### Pipeline API (Recommended)

Functional composition with explicit flow:

```elixir
def change do
  create_table(:products)
  |> with_uuid_primary_key()
  |> with_fields(
    name: :string,
    sku: :string,
    price: :decimal
  )
  |> with_type_fields()           # type, subtype
  |> with_status()                # status with constraints
  |> with_metadata()              # JSONB metadata
  |> with_belongs_to(:category)
  |> with_timestamps()
  |> with_index(:sku, unique: true)
  |> with_index([:category_id, :status])
  |> execute()
end
```

### DSL API

Declarative syntax within blocks:

```elixir
def change do
  create table(:products, primary_key: false) do
    uuid_primary_key()

    add :name, :string, null: false
    add :sku, :string, null: false
    add :price, :decimal, precision: 10, scale: 2

    belongs_to :category, :categories, type: :binary_id

    type_fields()
    status_fields()
    metadata_field()
    soft_delete_fields()
    timestamps(type: :utc_datetime_usec)
  end

  create unique_index(:products, [:sku])
  create index(:products, [:category_id, :status])
end
```

---

## Primary Keys

### UUIDv7 (Recommended)

```elixir
# Pipeline
create_table(:users)
|> with_uuid_primary_key()

# DSL
create table(:users, primary_key: false) do
  uuid_primary_key()
end
```

UUIDv7 provides time-ordered UUIDs for better index performance.

### UUID v4 (Legacy)

```elixir
# Pipeline
create_table(:users)
|> with_uuid_v4_primary_key()

# DSL
create table(:users, primary_key: false) do
  uuid_v4_primary_key()
end
```

### Bigint (Auto-increment)

```elixir
# Pipeline
create_table(:users)
|> with_bigint_primary_key()

# Default Ecto behavior
create table(:users) do
  # id is auto-added as bigint
end
```

---

## Field Helpers

### Basic Fields

```elixir
create_table(:products)
|> with_fields(
  name: :string,
  description: :text,
  price: :decimal,
  quantity: :integer,
  available: :boolean,
  published_at: :utc_datetime
)
```

### Identity Fields

Common user identity patterns:

```elixir
# Add specific identity fields
create_table(:users)
|> with_identity(:name)        # first_name, last_name, display_name, full_name
|> with_identity(:email)       # email (citext, unique index)
|> with_identity(:username)    # username (citext, unique index)
|> with_identity(:phone)       # phone

# Multiple at once
|> with_identity([:name, :email, :phone])
```

**Fields added by each identity type:**

| Identity | Fields | Indexes |
|----------|--------|---------|
| `:name` | `first_name`, `last_name`, `display_name`, `full_name` | None |
| `:email` | `email` (citext) | Unique on email |
| `:username` | `username` (citext) | Unique on username |
| `:phone` | `phone` | None |

### Profile Fields

```elixir
create_table(:users)
|> with_profile(:bio)          # bio (text)
|> with_profile(:avatar)       # avatar_url, avatar_thumbnail_url
|> with_profile(:location)     # address + geo fields

# Multiple
|> with_profile([:bio, :avatar, :location])
```

### Authentication Fields

```elixir
# Password authentication (default)
create_table(:users)
|> with_authentication()

# OAuth authentication
|> with_authentication(type: :oauth)

# Magic link authentication
|> with_authentication(type: :magic_link)
```

**Fields by authentication type:**

| Type | Fields |
|------|--------|
| `:password` | `password_hash`, `confirmed_at`, `confirmation_token`, `confirmation_sent_at`, `reset_password_token`, `reset_password_sent_at`, `failed_attempts`, `locked_at` |
| `:oauth` | `provider`, `provider_id`, `provider_token`, `provider_refresh_token`, `provider_token_expires_at` |
| `:magic_link` | `magic_token`, `magic_token_sent_at`, `magic_token_expires_at` |

### Type Fields

Classification fields for polymorphic records:

```elixir
# Pipeline
create_table(:products)
|> with_type_fields()

# DSL
create table(:products) do
  type_fields()
  type_fields(only: [:type, :subtype])
  type_fields(except: [:variant])
  type_fields(type: :string)  # Use string instead of citext
end
```

**Available type fields:** `type`, `subtype`, `kind`, `category`, `variant`

### Status Fields

Status tracking with optional transition history:

```elixir
# Basic status
create_table(:orders)
|> with_status_fields()

# With transition tracking
|> with_status_fields(with_transition: true)

# DSL
create table(:orders) do
  status_fields()
  status_fields(only: [:status])
  status_fields(with_transition: true)
end
```

**Available status fields:** `status`, `substatus`, `state`, `workflow_state`, `approval_status`

**Transition fields:** `previous_status`, `status_changed_at`, `status_changed_by`, `status_history` (JSONB)

### Status with Constraints

```elixir
# Constrained status with enum values
create_table(:orders)
|> with_status(
  values: ["pending", "processing", "shipped", "delivered"],
  default: "pending"
)
```

This creates a CHECK constraint ensuring valid values.

### Audit Fields

```elixir
# URM tracking (default)
create_table(:documents)
|> with_audit()

# User ID tracking
|> with_audit(track_urm: false, track_user: true)

# Full audit trail
|> with_audit(track_user: true, track_ip: true)

# DSL
create table(:documents) do
  audit_fields()
  audit_fields(track_urm: false, track_user: true)
  audit_fields(track_ip: true, track_session: true)
  audit_fields(track_changes: true)  # version + change_history
end
```

**Audit options:**

| Option | Fields Added |
|--------|-------------|
| `track_urm: true` (default) | `created_by_urm_id`, `updated_by_urm_id` |
| `track_user: true` | `created_by_user_id`, `updated_by_user_id` |
| `track_ip: true` | `created_from_ip`, `updated_from_ip` |
| `track_session: true` | `created_session_id`, `updated_session_id` |
| `track_changes: true` | `change_history` (JSONB), `version` |

### Soft Delete

```elixir
# Basic soft delete
create_table(:users)
|> with_soft_delete()

# With user tracking
|> with_soft_delete(track_user: true)

# With reason
|> with_soft_delete(track_reason: true)

# Without URM tracking
|> with_soft_delete(track_urm: false)

# DSL
create table(:users) do
  soft_delete_fields()
  soft_delete_fields(track_user: true, track_reason: true)
end
```

**Soft delete options:**

| Option | Fields Added |
|--------|-------------|
| Base | `deleted_at` |
| `track_urm: true` (default) | `deleted_by_urm_id` |
| `track_user: true` | `deleted_by_user_id` |
| `track_reason: true` | `deletion_reason` |

**Indexes created:**
- Index on `deleted_at`
- Partial index on `id WHERE deleted_at IS NULL` (for active records)

### Timestamps

```elixir
# Standard timestamps (utc_datetime_usec)
create_table(:articles)
|> with_timestamps()

# Only specific timestamps
|> with_timestamps(only: [:inserted_at])

# With lifecycle timestamps
|> with_timestamps(with_lifecycle: true)

# DSL - use Ecto's timestamps with our type
create table(:articles) do
  timestamps(type: :utc_datetime_usec)
end
```

**Lifecycle fields:** `published_at`, `archived_at`, `expires_at`

### Metadata Fields

```elixir
# Default metadata field
create_table(:products)
|> with_metadata()

# Custom name
|> with_metadata(name: :properties)

# DSL
create table(:products) do
  metadata_field()
  metadata_field(:properties)
end
```

Creates a JSONB field with default `{}` and GIN index.

### Tags

```elixir
create_table(:articles)
|> with_tags()
|> with_tags(name: :categories)

# DSL
create table(:articles) do
  tags_field()
  tags_field(:categories)
end
```

Creates an array field with GIN index.

### Settings

```elixir
create_table(:users)
|> with_settings()
```

Alias for `with_metadata(name: :settings)`.

### Money Fields

```elixir
create_table(:invoices)
|> with_money(:subtotal)
|> with_money(:tax)
|> with_money(:total)

# Multiple at once
|> with_money([:subtotal, :tax, :total])

# DSL
create table(:invoices) do
  money_field(:subtotal)
  money_field(:tax)
  money_field(:total, precision: 12, scale: 4)
end
```

Creates decimal fields with precision 10, scale 2.

---

## Relationships

### Belongs To

```elixir
# Pipeline
create_table(:posts)
|> with_belongs_to(:user)              # user_id
|> with_belongs_to(:category)          # category_id
|> with_belongs_to(:user, :author)     # author_id -> users

# DSL
create table(:posts, primary_key: false) do
  uuid_primary_key()
  belongs_to :user, :users, type: :binary_id
  belongs_to :category, :categories, type: :binary_id, null: true
end
```

Automatically adds foreign key index.

---

## Indexes

### Pipeline API

```elixir
create_table(:users)
|> with_index(:email)                           # Simple index
|> with_index(:email, unique: true)             # Unique index
|> with_index([:org_id, :name], unique: true)   # Composite unique
|> with_index(:status, where: "deleted_at IS NULL")  # Partial index
|> with_index(:metadata, using: :gin)           # GIN index for JSONB
```

### Index Token API

For standalone index operations:

```elixir
def change do
  # Create index with chained options
  create_index(:users, [:email])
  |> unique()
  |> where("deleted_at IS NULL")
  |> execute()

  # GIN index
  create_index(:products, [:tags])
  |> using(:gin)
  |> execute()
end
```

### DSL API

```elixir
def change do
  create table(:users) do
    # ...
  end

  # Standard indexes
  create index(:users, [:email])
  create unique_index(:users, [:email])
  create index(:users, [:status], where: "deleted_at IS NULL")

  # Auto-create standard indexes
  type_field_indexes(:products)
  status_field_indexes(:orders)
  audit_field_indexes(:documents)
  timestamp_indexes(:articles)

  # All standard indexes at once
  create_standard_indexes(:products)
end
```

---

## Pre-built Field Sets

### Address Fields

```elixir
# Returns tuples for manual use
Fields.address_fields()
#=> [
#     {:street, :string, null: true},
#     {:street2, :string, null: true},
#     {:city, :string, null: true},
#     {:state, :string, null: true},
#     {:postal_code, :string, null: true},
#     {:country, :string, null: true}
#   ]

# With prefix
Fields.address_fields(prefix: :billing)
#=> [{:billing_street, ...}, {:billing_city, ...}, ...]

# Required fields
Fields.address_fields(required: true)
#=> [{:street, :string, null: false}, ...]
```

### Geolocation Fields

```elixir
Fields.geo_fields()
#=> [
#     {:latitude, :decimal, precision: 10, scale: 7},
#     {:longitude, :decimal, precision: 10, scale: 7}
#   ]

# With altitude and accuracy
Fields.geo_fields(with_altitude: true, with_accuracy: true)
#=> [...latitude, longitude, altitude, accuracy...]
```

### Contact Fields

```elixir
Fields.contact_fields()
#=> [{:email, :citext}, {:phone, :string}, {:mobile, :string}, {:fax, :string}]

Fields.contact_fields(prefix: :billing)
#=> [{:billing_email, ...}, {:billing_phone, ...}, ...]
```

### Social Media Fields

```elixir
Fields.social_fields()
#=> [
#     {:website, :string},
#     {:twitter, :string},
#     {:facebook, :string},
#     {:instagram, :string},
#     {:linkedin, :string},
#     {:github, :string},
#     {:youtube, :string}
#   ]
```

### SEO Fields

```elixir
Fields.seo_fields()
#=> [
#     {:meta_title, :string},
#     {:meta_description, :text},
#     {:meta_keywords, {:array, :string}},
#     {:canonical_url, :string},
#     {:og_title, :string},
#     {:og_description, :text},
#     {:og_image, :string}
#   ]
```

### File Attachment Fields

```elixir
Fields.file_fields(:avatar)
#=> [{:avatar_url, :string}, {:avatar_key, :string}]

# With metadata
Fields.file_fields(:document, with_metadata: true)
#=> [
#     {:document_url, :string},
#     {:document_key, :string},
#     {:document_name, :string},
#     {:document_size, :integer},
#     {:document_content_type, :string},
#     {:document_uploaded_at, :utc_datetime}
#   ]
```

### Counter Fields

```elixir
Fields.counter_fields([:views_count, :likes_count, :comments_count])
#=> [
#     {:views_count, :integer, default: 0},
#     {:likes_count, :integer, default: 0},
#     {:comments_count, :integer, default: 0}
#   ]
```

### Money Fields

```elixir
Fields.money_fields([:price, :tax, :total])
#=> [
#     {:price, :decimal, precision: 10, scale: 2},
#     {:tax, :decimal, precision: 10, scale: 2},
#     {:total, :decimal, precision: 10, scale: 2}
#   ]

Fields.money_fields([:amount], precision: 12, scale: 4)
#=> [{:amount, :decimal, precision: 12, scale: 4}]
```

---

## Constraints

### Check Constraints

```elixir
# DSL
create table(:products) do
  add :price, :decimal
  add :quantity, :integer
end

# Add check constraints
create constraint(:products, :price_positive, check: "price >= 0")
create constraint(:products, :quantity_positive, check: "quantity >= 0")
```

### In Pipeline

```elixir
create_table(:products)
|> with_status(values: ["draft", "active", "archived"])
# Automatically adds CHECK constraint for valid values
```

---

## Real-World Examples

### User Table with Full Authentication

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use OmMigration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_identity([:name, :email, :username])
    |> with_authentication(type: :password)
    |> with_profile([:bio, :avatar])
    |> with_fields(
      role: :string,
      locale: :string,
      timezone: :string,
      last_sign_in_at: :utc_datetime,
      sign_in_count: :integer
    )
    |> with_type_fields()
    |> with_status_fields()
    |> with_audit()
    |> with_soft_delete(track_reason: true)
    |> with_timestamps()
    |> with_index(:role)
    |> execute()
  end
end
```

### E-commerce Order

```elixir
defmodule MyApp.Repo.Migrations.CreateOrders do
  use OmMigration

  def change do
    create_table(:orders)
    |> with_uuid_primary_key()
    |> with_belongs_to(:user)
    |> with_belongs_to(:shipping_address)
    |> with_belongs_to(:billing_address)
    |> with_fields(
      order_number: :string,
      currency: :string,
      notes: :text
    )
    |> with_money([:subtotal, :tax, :shipping, :discount, :total])
    |> with_status(
      values: ["pending", "confirmed", "processing", "shipped", "delivered", "cancelled"],
      default: "pending"
    )
    |> with_status_fields(with_transition: true)
    |> with_metadata()
    |> with_audit()
    |> with_soft_delete()
    |> with_timestamps()
    |> with_index(:order_number, unique: true)
    |> with_index(:status)
    |> with_index([:user_id, :status])
    |> execute()
  end
end
```

### CMS Article

```elixir
defmodule MyApp.Repo.Migrations.CreateArticles do
  use OmMigration

  def change do
    create_table(:articles)
    |> with_uuid_primary_key()
    |> with_belongs_to(:author)
    |> with_belongs_to(:category)
    |> with_fields(
      title: :string,
      slug: :string,
      excerpt: :text,
      body: :text,
      cover_image_url: :string,
      reading_time_minutes: :integer,
      published_at: :utc_datetime,
      featured: :boolean
    )
    |> with_tags()
    |> with_type_fields()
    |> with_status(values: ["draft", "review", "published", "archived"])
    |> with_metadata()  # For SEO and custom fields
    |> with_audit()
    |> with_soft_delete()
    |> with_timestamps()
    |> with_index(:slug, unique: true)
    |> with_index(:published_at)
    |> with_index(:featured)
    |> with_index([:category_id, :status], where: "deleted_at IS NULL")
    |> execute()
  end
end
```

---

## Pipeline Utilities

### Conditional Application

```elixir
create_table(:users)
|> with_uuid_primary_key()
|> maybe(&with_soft_delete/1, opts[:soft_delete])
|> maybe(&with_audit/1, opts[:audit])
|> execute()
```

### Debugging

```elixir
create_table(:users)
|> with_uuid_primary_key()
|> tap_inspect("After primary key")
|> with_identity(:email)
|> tap_inspect("After identity")
|> execute()
```

### Validation

```elixir
create_table(:users)
|> with_uuid_primary_key()
|> with_fields(name: :string)
|> validate!()   # Raises if invalid
|> execute()
```

---

## Help System

```elixir
# General help
OmMigration.help()

# Topic-specific help
OmMigration.help(:fields)     # Field helpers
OmMigration.help(:indexes)    # Index helpers
OmMigration.help(:examples)   # Complete examples
```

---

## Token System

OmMigration uses a token-based architecture for composability and testability:

```elixir
# Tokens are immutable data structures
token = create_table(:users)
#=> %OmMigration.Token{
#     type: :table,
#     name: :users,
#     fields: [],
#     indexes: [],
#     constraints: [],
#     options: []
#   }

# Each pipeline function returns a new token
token = token |> with_uuid_primary_key()
#=> %OmMigration.Token{
#     fields: [{:id, :uuid, primary_key: true, ...}],
#     ...
#   }

# Validate before executing
{:ok, token} = Token.validate(token)

# Execute to run the migration
Executor.execute(token)
```

---

## Best Practices

### 1. Use Pipeline for Complex Tables

```elixir
# Good - clear flow, easy to read
create_table(:orders)
|> with_uuid_primary_key()
|> with_belongs_to(:user)
|> with_money([:total, :tax])
|> with_status()
|> with_timestamps()
|> execute()

# Avoid - hard to see what's added
create table(:orders, primary_key: false) do
  add :id, :binary_id, primary_key: true, default: fragment("uuidv7()")
  add :user_id, references(:users, type: :binary_id)
  add :total, :decimal, precision: 10, scale: 2
  # ... many more lines
end
```

### 2. Use Field Helpers for Common Patterns

```elixir
# Good - semantic intent is clear
|> with_authentication()
|> with_audit()
|> with_soft_delete()

# Avoid - manual field definitions
add :password_hash, :string
add :confirmed_at, :utc_datetime
add :created_by_id, :binary_id
add :updated_by_id, :binary_id
add :deleted_at, :utc_datetime
```

### 3. Create Indexes for Foreign Keys

```elixir
# Automatic with belongs_to
|> with_belongs_to(:user)  # Creates user_id + index

# Manual - don't forget the index
|> with_fields(user_id: :binary_id)
|> with_index(:user_id)
```

### 4. Use Partial Indexes for Soft Delete

```elixir
# Only index active records for most queries
|> with_index(:email, unique: true, where: "deleted_at IS NULL")
|> with_index(:status, where: "deleted_at IS NULL")
```

### 5. Use JSONB for Flexible Data

```elixir
# Structured but flexible
|> with_metadata()  # For extensible properties
|> with_settings()  # For user preferences
|> with_tags()      # For categorization
```

---

## Configuration

```elixir
# config/config.exs
config :om_migration,
  # Default primary key type
  default_primary_key: :uuid,

  # Default timestamp type
  timestamp_type: :utc_datetime_usec,

  # Default citext for identity fields
  use_citext: true
```

## License

MIT
