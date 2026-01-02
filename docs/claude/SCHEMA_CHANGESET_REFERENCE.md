# Events Schema, Field & Changeset Reference Guide

> **Complete reference for the Events schema system.** For quick reference, see `SCHEMA.md`.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Field Macro Reference](#field-macro-reference)
3. [Field Group Macros](#field-group-macros)
4. [Validation Options](#validation-options)
5. [Presets](#presets)
6. [Mappers](#mappers)
7. [Constraints](#constraints)
8. [Association Macros](#association-macros)
9. [Generated Functions](#generated-functions)
10. [Changeset Helpers](#changeset-helpers)
11. [Complete Examples](#complete-examples)

---

## Getting Started

Always use `OmSchema` instead of `Ecto.Schema`:

```elixir
defmodule MyApp.Accounts.User do
  use OmSchema

  schema "users" do
    field :name, :string, required: true, min_length: 2
    field :email, :string, required: true, format: :email
    field :age, :integer, positive: true, max: 150

    # Field groups
    type_fields()
    status_fields(values: [:active, :suspended], default: :active)
    audit_fields()
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> base_changeset(attrs)
  end
end
```

**Key Features:**
- UUIDv7 primary keys by default
- Enhanced field macro with validation options
- Auto-generated changeset helpers
- Field group macros for common patterns
- Constraint declaration DSL

---

## Field Macro Reference

The `field/3` macro is enhanced with validation and behavioral options.

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `required` | `boolean` | `false` | Field must be present |
| `cast` | `boolean` | `true` | Include in cast fields |
| `default` | `any` | `nil` | Default value |
| `null` | `boolean` | inverse of `required` | Allow nil values |

### Behavioral Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `immutable` | `boolean` | `false` | Cannot be changed after creation |
| `sensitive` | `boolean` | `false` | Redacted in logs/inspect |
| `trim` | `boolean` | `true` (strings) | Auto-trim whitespace |

### Documentation Options

| Option | Type | Description |
|--------|------|-------------|
| `doc` | `string` | Field documentation |
| `example` | `any` | Example value |

### Examples

```elixir
schema "users" do
  # Basic required field
  field :name, :string, required: true

  # With behavioral options
  field :account_id, :binary_id, required: true, immutable: true
  field :api_key, :string, sensitive: true

  # With documentation
  field :email, :string,
    required: true,
    doc: "Primary contact email",
    example: "user@example.com"

  # Password - no auto-trim
  field :password, :string, trim: false

  # Not included in cast
  field :computed_field, :string, cast: false
end
```

---

## Field Group Macros

### `type_fields/1`

Adds type classification fields (`:type` and `:subtype`).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `list` | `[:type, :subtype]` | Fields to include |
| `type` | `keyword` | `[]` | Options for `:type` field |
| `subtype` | `keyword` | `[]` | Options for `:subtype` field |

```elixir
# Both type and subtype
type_fields()

# Only type field
type_fields(only: [:type])

# Type as required
type_fields(type: [required: true])

# Both with custom options
type_fields(type: [required: true], subtype: [cast: false])
```

### `status_fields/1`

Adds a status enum field.

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `values` | `list` | **Yes** | Enum values |
| `default` | `atom` | No | Default status |
| `required` | `boolean` | `false` | Field is required |
| `cast` | `boolean` | `true` | Include in cast |

```elixir
# Basic status
status_fields(values: [:active, :inactive], default: :active)

# Required status
status_fields(values: [:pending, :approved, :rejected], required: true)

# Status not cast (set programmatically)
status_fields(values: [:draft, :published], default: :draft, cast: false)
```

### `audit_fields/1`

Adds audit tracking fields (`:created_by_urm_id`, `:updated_by_urm_id`).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `list` | both fields | Fields to include |
| `created_by_urm_id` | `keyword` | `[]` | Options for created_by field |
| `updated_by_urm_id` | `keyword` | `[]` | Options for updated_by field |

```elixir
# Both audit fields
audit_fields()

# Only track creation
audit_fields(only: [:created_by_urm_id])

# Created_by is required
audit_fields(created_by_urm_id: [required: true])
```

### `timestamps/1`

Adds timestamp fields (`:inserted_at`, `:updated_at`).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `list` | both fields | Fields to include |
| `type` | `atom` | `:utc_datetime_usec` | Timestamp type |

```elixir
# Both timestamps
timestamps()

# Only inserted_at
timestamps(only: [:inserted_at])

# Custom type
timestamps(type: :naive_datetime)
```

### `metadata_field/1`

Adds a JSONB metadata field.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default` | `map` | `%{}` | Default value |

```elixir
metadata_field()
metadata_field(default: %{version: 1})
```

### `assets_field/1`

Adds a JSONB assets field for media references.

```elixir
assets_field()
assets_field(default: %{logo: nil})
```

### `soft_delete_field/1`

Adds soft delete support with helper functions.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `track_urm` | `boolean` | `false` | Add `deleted_by_urm_id` |

```elixir
# Basic soft delete
soft_delete_field()

# With deletion tracking
soft_delete_field(track_urm: true)
```

**Generated helpers:**
- `deleted?(record)` - Check if deleted
- `soft_delete_changeset(record, opts)` - Create deletion changeset
- `restore_changeset(record)` - Restore deleted record
- `not_deleted(query)` - Filter out deleted
- `only_deleted(query)` - Only deleted records
- `with_deleted(query)` - All records

### `standard_fields/2`

Unified macro for adding multiple field groups.

| Option | Type | Description |
|--------|------|-------------|
| First arg | `list` | Groups to include |
| `except` | `list` | Groups to exclude |
| `status` | `keyword` | Status field options |

**Available groups:** `:type`, `:status`, `:metadata`, `:assets`, `:audit`, `:timestamps`

```elixir
# All standard fields (requires status values)
standard_fields(status: [values: [:active, :inactive], default: :active])

# Select specific groups
standard_fields([:type, :status, :timestamps],
  status: [values: [:active, :archived], default: :active]
)

# Exclude specific groups
standard_fields(except: [:audit],
  status: [values: [:pending, :approved], default: :pending]
)

# Minimal
standard_fields([:timestamps])
```

---

## Validation Options

### String Validations

| Option | Type | Description |
|--------|------|-------------|
| `min_length` | `integer` | Minimum string length |
| `max_length` | `integer` | Maximum string length |
| `length` | `integer` | Exact string length |
| `format` | `atom/regex` | Format validation |
| `trim` | `boolean` | Auto-trim whitespace (default: true) |
| `mappers` | `list` | Value transformations |

**Built-in formats:** `:email`, `:url`, `:uuid`, `:slug`, custom regex

```elixir
field :email, :string,
  required: true,
  format: :email,
  max_length: 255,
  mappers: [:trim, :downcase]

field :username, :string,
  min_length: 3,
  max_length: 30,
  format: ~r/^[a-zA-Z0-9_]+$/

field :password, :string,
  min_length: 8,
  max_length: 128,
  trim: false  # Preserve whitespace
```

### Number Validations

| Option | Type | Description |
|--------|------|-------------|
| `min` | `number` | Minimum value (inclusive) |
| `max` | `number` | Maximum value (inclusive) |
| `positive` | `boolean` | Must be > 0 |
| `non_negative` | `boolean` | Must be >= 0 |
| `in` | `Range/list` | Value must be in range |

```elixir
field :age, :integer, positive: true, max: 150
field :balance, :decimal, non_negative: true
field :percentage, :integer, min: 0, max: 100
field :rating, :integer, in: 1..5
```

### DateTime Validations

| Option | Type | Description |
|--------|------|-------------|
| `past` | `boolean` | Must be in the past |
| `future` | `boolean` | Must be in the future |
| `after` | `date/tuple` | Must be after this date |
| `before` | `date/tuple` | Must be before this date |

```elixir
field :birth_date, :date, past: true, required: true

field :trial_ends_at, :utc_datetime,
  future: true,
  after: {:now, days: 7}

field :event_date, :date,
  after: ~D[2024-01-01],
  before: ~D[2025-12-31]
```

### Array Validations

| Option | Type | Description |
|--------|------|-------------|
| `min_length` | `integer` | Minimum array length |
| `max_length` | `integer` | Maximum array length |
| `unique_items` | `boolean` | All items must be unique |
| `item_format` | `regex` | Format for each item |

```elixir
field :tags, {:array, :string},
  unique_items: true,
  min_length: 0,
  max_length: 20,
  item_format: ~r/^[a-z0-9-]+$/
```

### Map Validations

| Option | Type | Description |
|--------|------|-------------|
| `required_keys` | `list` | Keys that must be present |
| `max_keys` | `integer` | Maximum number of keys |

```elixir
field :preferences, :map,
  required_keys: [:theme, :language],
  max_keys: 20,
  default: %{}

field :metadata, :map, default: %{}, max_keys: 100
```

### Conditional Validation

| Option | Type | Description |
|--------|------|-------------|
| `required_when` | `keyword/tuple` | Conditionally required |
| `validate_if` | `{module, function}` | Conditional validation |

```elixir
# Required when another field has specific value
field :phone, :string, required_when: [contact_method: :phone]

# Required with complex conditions
field :address, :map, required_when: [type: :physical, needs_shipping: true]

# Comparison operators
field :reason, :string, required_when: {:discount_percent, :gt, 0}
field :notes, :string, required_when: {:status, :in, [:rejected, :on_hold]}

# Boolean operators
field :phone, :string, required_when: [[notify_sms: true], :or, [notify_call: true]]

# Callback-based validation
field :referral_code, :string,
  min_length: 6,
  validate_if: {__MODULE__, :is_referred_user?}
```

### Custom Validation

```elixir
field :custom_field, :string,
  validate: {__MODULE__, :validate_custom}

def validate_custom(value) do
  if String.length(value) > 5 do
    :ok
  else
    {:error, "must be longer than 5 characters"}
  end
end
```

---

## Presets

Import presets for common field patterns:

```elixir
import OmSchema.Presets
```

### Available Presets

| Preset | Type | Key Options |
|--------|------|-------------|
| `email()` | String | `required: true, format: :email, max_length: 255, mappers: [:trim, :downcase]` |
| `username()` | String | `required: true, min_length: 4, max_length: 30, format: ~r/^[a-zA-Z0-9_-]+$/` |
| `password()` | String | `required: true, min_length: 8, max_length: 128, trim: false` |
| `phone()` | String | `required: true, min_length: 10, max_length: 20` |
| `url()` | String | `required: true, format: :url, max_length: 2048` |
| `slug()` | String | `format: :slug, max_length: 255, normalize: {:slugify, uniquify: true}` |
| `uuid()` | String | `format: :uuid, mappers: [:trim, :downcase]` |
| `positive_integer()` | Integer | `positive: true, default: 0` |
| `money()` | Decimal | `non_negative: true, max: 999_999_999.99` |
| `percentage()` | Integer | `min: 0, max: 100` |
| `age()` | Integer | `min: 0, max: 150, non_negative: true` |
| `rating()` | Integer | `min: 1, max: 5` |
| `latitude()` | Decimal | `min: -90.0, max: 90.0` |
| `longitude()` | Decimal | `min: -180.0, max: 180.0` |
| `country_code()` | String | `format: ~r/^[A-Z]{2}$/, length: 2` |
| `language_code()` | String | `format: ~r/^[a-z]{2}(-[A-Z]{2})?$/` |
| `currency_code()` | String | `format: ~r/^[A-Z]{3}$/, length: 3` |
| `timezone()` | String | `format: ~r/^[A-Za-z]+\/[A-Za-z_]+$/` |
| `domain()` | String | Domain name validation |
| `ipv4()` | String | IPv4 address format |
| `ipv6()` | String | IPv6 address format |
| `mac_address()` | String | MAC address format |
| `hex_color()` | String | Hex color code (#RRGGBB) |
| `zip_code()` | String | US ZIP code format |
| `social_handle()` | String | Twitter/Instagram style handle |
| `semver()` | String | Semantic version format |
| `jwt()` | String | JWT token format |
| `base64()` | String | Base64 encoded string |
| `iban()` | String | International Bank Account Number |
| `isbn()` | String | ISBN book number |
| `bitcoin_address()` | String | Bitcoin address format |
| `ethereum_address()` | String | Ethereum address format |

### Usage

```elixir
schema "users" do
  # Using presets directly
  field :email, :string, email()
  field :username, :string, username(min_length: 3)
  field :website, :string, url(required: false)
  field :phone, :string, phone()

  # Override preset options
  field :password, :string, password(min_length: 10)

  # Numeric presets
  field :age, :integer, age()
  field :balance, :decimal, money()
  field :discount, :integer, percentage()

  # Location presets
  field :lat, :decimal, latitude()
  field :lng, :decimal, longitude()
end
```

### Creating Custom Presets

```elixir
def my_custom_preset(custom_opts \\ []) do
  [
    required: true,
    min_length: 5,
    format: ~r/^custom-/
  ]
  |> Keyword.merge(custom_opts)
end

# Usage
field :custom, :string, my_custom_preset(max_length: 50)
```

---

## Mappers

Mappers transform field values. They are applied left-to-right.

### Available Mappers

| Mapper | Description |
|--------|-------------|
| `:trim` | Remove leading/trailing whitespace |
| `:downcase` | Convert to lowercase |
| `:upcase` | Convert to uppercase |
| `:capitalize` | Capitalize first letter |
| `:titlecase` | Capitalize each word |
| `:squish` | Trim and collapse multiple spaces |
| `:slugify` | Convert to URL-safe slug |
| `:digits_only` | Remove all non-numeric characters |
| `:alphanumeric_only` | Remove all non-alphanumeric characters |

### Usage

```elixir
# Single mapper
field :email, :string, mappers: [:trim, :downcase]

# Multiple mappers (applied left-to-right)
field :name, :string, mappers: [:trim, :titlecase]
field :username, :string, mappers: [:trim, :downcase, :slugify]

# Using normalize (alias for mappers)
field :code, :string, normalize: [:trim, :upcase]

# Slugify with uniqueness suffix
field :slug, :string, normalize: {:slugify, uniquify: true}

# Custom mapper function
field :phone, :string, mappers: [:trim, fn v -> String.replace(v, "-", "") end]
```

### Mapper Functions

```elixir
import OmSchema.Mappers

# Get mapper functions
trim = trim()
downcase = downcase()
slugify = slugify(uniquify: true)

# Compose mappers
email_normalizer = compose([trim(), downcase()])
```

---

## Constraints

Declare database constraints in your schema for validation.

### Field-Level Constraints

```elixir
schema "users" do
  # Unique constraint
  field :email, :string, unique: true
  field :username, :string, unique: :users_username_index  # Custom name
  field :slug, :string, unique: [name: :users_slug_idx, where: "deleted_at IS NULL"]

  # Check constraint
  field :age, :integer, check: :users_age_positive
end
```

### Constraints Block

For complex constraints:

```elixir
schema "user_role_mappings" do
  belongs_to :user, User
  belongs_to :role, Role
  belongs_to :account, Account

  constraints do
    # Composite unique
    unique [:user_id, :role_id, :account_id],
      name: :user_role_mappings_user_role_account_idx

    # Foreign key with options
    foreign_key :user_id,
      references: :users,
      on_delete: :cascade

    # Check constraint with expression
    check :valid_dates,
      expr: "started_at IS NULL OR ended_at IS NULL OR started_at < ended_at"

    # Non-unique index
    index [:status], name: :urm_status_idx

    # Exclusion constraint (PostgreSQL)
    exclude :no_overlap,
      using: :gist,
      expr: "room_id WITH =, tsrange(start_at, end_at) WITH &&"
  end
end
```

### Constraint Macros

| Macro | Description |
|-------|-------------|
| `unique fields, opts` | Unique constraint |
| `foreign_key field, opts` | Foreign key constraint |
| `check name` | Check constraint (name only) |
| `check name, opts` | Check constraint with expression |
| `index fields, opts` | Non-unique index |
| `exclude name, opts` | Exclusion constraint |

### Foreign Key Options

| Option | Values | Default |
|--------|--------|---------|
| `references` | table name | **required** |
| `column` | column name | `:id` |
| `on_delete` | `:nothing`, `:cascade`, `:restrict`, `:nilify_all`, `:delete_all` | `:nothing` |
| `on_update` | same as on_delete | `:nothing` |
| `deferrable` | `:initially_immediate`, `:initially_deferred` | `nil` |
| `name` | constraint name | auto-generated |

---

## Association Macros

### `belongs_to/3`

Enhanced `belongs_to` with FK constraint metadata:

```elixir
# Basic - default FK constraint
belongs_to :account, Account

# With cascade delete
belongs_to :account, Account, on_delete: :cascade

# Full constraint options
belongs_to :account, Account,
  constraint: [
    on_delete: :cascade,
    deferrable: :initially_deferred
  ]

# Skip FK validation (polymorphic)
belongs_to :commentable, Commentable, constraint: false
```

### `has_many/3`

Enhanced `has_many` with FK validation expectations:

```elixir
# Basic - validates FK exists on related table
has_many :memberships, Membership

# Expect specific on_delete behavior
has_many :memberships, Membership, expect_on_delete: :cascade

# Skip FK validation
has_many :comments, Comment, validate_fk: false

# Through associations (validation auto-skipped)
has_many :accounts, through: [:memberships, :account]
```

---

## Generated Functions

After schema compilation, these functions are available:

### Field Introspection

| Function | Returns |
|----------|---------|
| `cast_fields()` | Fields with `cast: true` |
| `required_fields()` | Fields with `required: true` |
| `immutable_fields()` | Fields with `immutable: true` |
| `sensitive_fields()` | Fields with `sensitive: true` |
| `field_docs()` | Map of field -> `%{doc: string, example: term}` |
| `conditional_required_fields()` | Fields with `required_when` conditions |
| `field_validations()` | All field validation metadata |

### Constraint Introspection

| Function | Returns |
|----------|---------|
| `constraints()` | All constraint metadata |
| `indexes()` | All index metadata |
| `foreign_keys()` | FK constraint details |
| `unique_constraints()` | Unique constraint details |
| `check_constraints()` | Check constraint details |
| `has_many_expectations()` | has_many FK expectations |

---

## Changeset Helpers

### `base_changeset/3`

Creates a changeset with field definitions applied:

```elixir
def changeset(user, attrs) do
  user
  |> base_changeset(attrs)
  |> unique_constraints([{:email, []}, {[:account_id, :slug], name: :idx}])
end
```

### Action-Specific Options

```elixir
@changeset_actions %{
  create: [also_required: [:password]],
  update: [skip_required: [:password], skip_cast: [:email]],
  profile: [only_cast: [:name, :avatar], only_required: []]
}

def changeset(user, attrs, action \\ :default) do
  base_changeset(user, attrs, action: action)
end
```

### Available Options

| Option | Description |
|--------|-------------|
| `action: atom` | Look up options from `@changeset_actions` |
| `also_cast: [fields]` | Add extra cast fields |
| `only_cast: [fields]` | Override: only cast these |
| `skip_cast: [fields]` | Exclude from cast |
| `also_required: [fields]` | Add extra required fields |
| `only_required: [fields]` | Override: only these required |
| `skip_required: [fields]` | Exclude from required |
| `skip_field_validations: true` | Skip format/length validations |
| `check_immutable: true` | Validate immutable fields |
| `check_conditional_required: true` | Validate conditional required |

### Constraint Helpers

```elixir
# Multiple unique constraints
|> unique_constraints([
     {:email, []},
     {:username, message: "is taken"},
     {[:account_id, :slug], name: :users_account_slug_index}
   ])

# Multiple FK constraints
|> foreign_key_constraints([
     {:account_id, []},
     {:user_id, message: "user not found"}
   ])

# Check constraints
|> check_constraints([
     {:age, name: :users_age_positive, message: "must be positive"}
   ])

# No-assoc constraints (prevent deletion)
|> no_assoc_constraints([
     {:memberships, []},
     {:roles, message: "has associated roles"}
   ])
```

### Validation Helpers

```elixir
# Validate immutable fields
|> validate_immutable()
|> validate_immutable([:account_id, :created_at])
|> validate_immutable(message: "cannot be changed after creation")

# Conditional required
|> validate_conditional_required()

# Status transitions
@status_transitions %{
  active: [:suspended, :deleted],
  suspended: [:active, :deleted],
  deleted: []  # terminal
}

|> validate_transition(:status, @status_transitions)
|> validate_transition(:status, @status_transitions, message: "invalid transition")

# Slug generation
|> maybe_put_slug(from: :name)
|> maybe_put_slug(from: :title, to: :url_slug, uniquify: true)
```

---

## Complete Examples

### Full Schema Example

```elixir
defmodule MyApp.Accounts.User do
  use OmSchema
  import OmSchema.Presets

  @changeset_actions %{
    create: [also_required: [:password]],
    update: [skip_required: [:password]],
    profile: [only_cast: [:name, :email, :avatar_url], only_required: []]
  }

  @status_transitions %{
    active: [:suspended, :deleted],
    suspended: [:active, :deleted],
    deleted: []
  }

  schema "users" do
    # Identity
    field :name, :string, required: true, min_length: 2, max_length: 100
    field :email, :string, email()
    field :username, :string, username()

    # Authentication
    field :password, :string, password(), sensitive: true
    field :password_hash, :string, cast: false

    # Profile
    field :avatar_url, :string, url(required: false)
    field :bio, :string, max_length: 500
    field :birth_date, :date, past: true

    # Location
    field :latitude, :decimal, latitude()
    field :longitude, :decimal, longitude()

    # Associations
    belongs_to :account, Account, on_delete: :cascade
    has_many :memberships, Membership
    has_many :roles, through: [:memberships, :role]

    # Standard fields
    type_fields()
    status_fields(values: [:active, :suspended, :deleted], default: :active)
    metadata_field()
    audit_fields()
    soft_delete_field(track_urm: true)
    timestamps()

    # Constraints
    constraints do
      unique [:account_id, :email], name: :users_account_email_idx
      unique :username, name: :users_username_idx, where: "deleted_at IS NULL"
      check :valid_coordinates,
        expr: "(latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL)"
    end
  end

  def changeset(user, attrs, action \\ :default) do
    user
    |> base_changeset(attrs, action: action, check_immutable: action == :update)
    |> validate_transition(:status, @status_transitions)
    |> maybe_hash_password()
    |> unique_constraints([
         {:email, []},
         {[:account_id, :email], name: :users_account_email_idx}
       ])
    |> foreign_key_constraints([{:account_id, []}])
  end

  defp maybe_hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, hash_password(password))
    end
  end

  defp hash_password(password), do: Bcrypt.hash_pwd_salt(password)
end
```

### Minimal Schema Example

```elixir
defmodule MyApp.Blog.Post do
  use OmSchema

  schema "posts" do
    field :title, :string, required: true, min_length: 1, max_length: 200
    field :body, :string, required: true
    field :slug, :string, required: true, format: :slug

    belongs_to :author, User

    status_fields(values: [:draft, :published, :archived], default: :draft)
    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> base_changeset(attrs)
    |> maybe_put_slug(from: :title)
    |> unique_constraints([{:slug, []}])
  end
end
```

### Product with Money Fields

```elixir
defmodule MyApp.Catalog.Product do
  use OmSchema
  import OmSchema.Presets

  schema "products" do
    field :name, :string, required: true
    field :sku, :string, required: true, format: ~r/^[A-Z0-9-]+$/
    field :description, :string

    # Pricing
    field :price, :decimal, money()
    field :cost, :decimal, money()
    field :discount_percent, :integer, percentage()

    # Inventory
    field :quantity, :integer, non_negative: true, default: 0
    field :low_stock_threshold, :integer, positive: true, default: 10

    # Categorization
    field :tags, {:array, :string}, unique_items: true, max_length: 10

    belongs_to :category, Category

    type_fields()
    status_fields(values: [:draft, :active, :discontinued], default: :draft)
    metadata_field()
    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> base_changeset(attrs)
    |> validate_number(:price, greater_than: :cost)
    |> unique_constraints([{:sku, []}])
  end
end
```

---

## Quick Reference Cards

### Schema Field Options

```
Required/Cast:     required: true, cast: true
Behavioral:        immutable: true, sensitive: true, trim: false
Docs:              doc: "...", example: "..."
String:            min_length, max_length, length, format, mappers
Number:            min, max, positive, non_negative, in: range
DateTime:          past, future, after, before
Array:             min_length, max_length, unique_items, item_format
Map:               required_keys, max_keys
Conditional:       required_when, validate_if
Custom:            validate: {Module, :function}
Constraints:       unique: true, check: :constraint_name
```

### Common Presets

```elixir
email()          # Email validation
username()       # Username validation
password()       # Password (no trim)
phone()          # Phone number
url()            # URL validation
slug()           # URL slug
money()          # Decimal for money
percentage()     # 0-100 integer
age()            # 0-150 integer
rating()         # 1-5 integer
latitude()       # -90 to 90
longitude()      # -180 to 180
country_code()   # 2-letter ISO
currency_code()  # 3-letter ISO
```

### Database Type Conventions

| Use Case | Migration Type | Schema Type |
|----------|---------------|-------------|
| Names, identifiers | `:citext` | `:string` |
| Long text | `:text` | `:string` |
| Structured data | `:jsonb` | `:map` |
| Timestamps | `:utc_datetime_usec` | `:utc_datetime_usec` |
| Money | `:integer` (cents) | `:integer` |
| Precise decimals | `:decimal` | `:decimal` |

### Changeset Options Summary

```elixir
# Action-based changesets
@changeset_actions %{
  create: [also_required: [:password]],
  update: [skip_required: [:password], skip_cast: [:email]],
  admin: [also_cast: [:role], also_required: [:role]]
}

# Usage
base_changeset(struct, attrs, action: :create)
base_changeset(struct, attrs, also_required: [:field])
base_changeset(struct, attrs, skip_cast: [:computed])
base_changeset(struct, attrs, check_immutable: true)
```

### Soft Delete Pattern

```elixir
# Schema
soft_delete_field(track_urm: true)

# Query helpers (auto-generated)
User.not_deleted(query)   # Exclude deleted
User.only_deleted(query)  # Only deleted
User.with_deleted(query)  # Include all

# Operations
User.deleted?(user)                    # Check if deleted
User.soft_delete_changeset(user, by: user_id)  # Mark deleted
User.restore_changeset(user)           # Restore
```
