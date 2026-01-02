# Events Framework Reference

A comprehensive guide to the Schema, Migration, and Decorator macro systems in the Events application.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
   - [Extensibility Patterns](#extensibility-patterns)
   - [Registry Pattern](#registry-pattern)
   - [Introspection APIs](#introspection-apis)
2. [Schema System](#schema-system)
   - [Getting Started](#getting-started)
   - [Field Macro Reference](#field-macro-reference)
   - [Field Group Macros](#field-group-macros)
   - [Validation Options](#validation-options)
   - [Presets](#presets)
   - [Mappers](#mappers)
   - [Constraints](#constraints)
   - [Association Macros](#association-macros)
   - [Generated Functions](#generated-functions)
   - [Changeset Helpers](#changeset-helpers)
2. [Migration System](#migration-system)
   - [Pipeline Pattern](#pipeline-pattern)
   - [DSL Enhanced Macros](#dsl-enhanced-macros)
   - [Field Builder Reference](#field-builder-reference)
   - [Index Helpers](#index-helpers)
3. [Decorator System](#decorator-system)
   - [Type Decorators](#type-decorators)
   - [Caching Decorators](#caching-decorators)
   - [Telemetry Decorators](#telemetry-decorators)
   - [Validation Decorators](#validation-decorators)
   - [Security Decorators](#security-decorators)
   - [Debugging Decorators](#debugging-decorators)
   - [Purity Decorators](#purity-decorators)
4. [Complete Examples](#complete-examples)

---

# Architecture Overview

The Events framework is built on a modular, extensible architecture with consistent patterns across Schema, Migration, and Decorator systems.

## Extensibility Patterns

All major systems follow the **Behavior + Registry** pattern:

1. **Behavior** - Defines the contract (callbacks) that implementations must follow
2. **Registry** - Maps identifiers to implementations, enabling runtime lookup
3. **Default Implementations** - Built-in implementations for common use cases

```elixir
# 1. Define behavior
defmodule OmSchema.Behaviours.Validator do
  @callback validate(changeset, field_name, opts) :: changeset
  @callback field_types() :: [atom()]
  @callback supported_options() :: [atom()]
end

# 2. Implement behavior
defmodule MyApp.CustomValidator do
  @behaviour OmSchema.Behaviours.Validator

  @impl true
  def field_types, do: [:money]

  @impl true
  def validate(changeset, field_name, opts) do
    # Custom validation logic
    changeset
  end
end

# 3. Register implementation
OmSchema.ValidatorRegistry.register(:money, MyApp.CustomValidator)
```

## Registry Pattern

### ValidatorRegistry (Schema System)

Maps field types to validator modules:

```elixir
# Get validator for a field type
OmSchema.ValidatorRegistry.get(:string)
# => OmSchema.Validators.String

# Register custom validator
OmSchema.ValidatorRegistry.register(:phone, MyApp.PhoneValidator)

# List all validators
OmSchema.ValidatorRegistry.all()
# => %{string: OmSchema.Validators.String, integer: OmSchema.Validators.Number, ...}
```

### DecoratorRegistry (Decorator System)

Maps decorator names to modules and functions (use `FnDecorator.Registry` directly from libs):

```elixir
# Get decorator implementation
FnDecorator.Registry.get(:cacheable)
# => {FnDecorator.Caching, :cacheable}

# Register custom decorator
FnDecorator.Registry.register(:my_decorator, MyModule, :my_decorator)

# List decorators by category
FnDecorator.Registry.by_category()
# => %{caching: [:cacheable, :cache_put, :cache_evict], ...}
```

## Introspection APIs

### Token Introspection (Migration System)

Query migration token structure at runtime:

```elixir
alias Events.Core.Migration.Token

# Create and inspect a token
token = Token.new(:table, :users)
|> Token.add_field(:email, :string, null: false, unique: true)
|> Token.add_field(:user_id, {:references, :users, type: :uuid}, [])
|> Token.add_index(:users_email_idx, [:email], unique: true)

# Query the token
Token.field_names(token)      # => [:email, :user_id]
Token.has_field?(token, :email)  # => true
Token.unique_fields(token)    # => [:email]
Token.required_fields(token)  # => [:email]
Token.foreign_keys(token)     # => [{:user_id, {:references, :users, ...}, []}]
Token.referenced_tables(token) # => [:users]

# Get full summary
Token.summary(token)
# => %{type: :table, name: :users, field_count: 2, has_primary_key: true, ...}

# Generate schema fields
Token.to_schema_fields(token)
# => ["field :email, :string, null: false", "field :user_id, references(:users)"]
```

### Token Validation (Migration System)

Comprehensive validation before execution:

```elixir
alias Events.Core.Migration.TokenValidator

# Validate with detailed errors
case TokenValidator.validate(token) do
  {:ok, valid_token} ->
    # Execute migration

  {:error, errors} ->
    # errors is a list of %{code: atom, message: string, field: atom | nil, details: map}
    Enum.each(errors, &IO.puts(&1.message))
end

# Validate and raise on error
token = TokenValidator.validate!(token)

# Quick check
if TokenValidator.valid?(token), do: execute(token)
```

### Decorator Introspection

Query decorator metadata at runtime (use `FnDecorator.Introspection` directly from libs):

```elixir
alias FnDecorator.Introspection

# Get all decorated functions
Introspection.decorators(MyModule)
# => %{{:get_user, 1} => [{:cacheable, [cache: MyCache]}], ...}

# Check specific function
Introspection.has_decorator?(MyModule, :get_user, 1, :cacheable)
# => true

# Get decorator options
Introspection.get_decorator_opts(MyModule, :get_user, 1, :cacheable)
# => [cache: MyCache, key: id]

# Find all cached functions
Introspection.functions_with_decorator(MyModule, :cacheable)
# => [{:get_user, 1}, {:find_user, 2}]
```

---

# Schema System

## Getting Started

Replace `use Ecto.Schema` with `use OmSchema`:

```elixir
defmodule MyApp.Accounts.User do
  use Events.Schema

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

# Only updated_at
timestamps(only: [:updated_at])

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
| Other groups | `keyword` | Options per group |

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

**Built-in formats:**
- `:email` - Email address
- `:url` - URL format
- `:uuid` - UUID format
- `:slug` - URL slug format
- Custom regex

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
| `email()` | String | `required: true, format: :email, max_length: 255, normalize: [:trim, :downcase]` |
| `username()` | String | `required: true, min_length: 4, max_length: 30, format: ~r/^[a-zA-Z0-9_-]+$/` |
| `password()` | String | `required: true, min_length: 8, max_length: 128, trim: false` |
| `phone()` | String | `required: true, min_length: 10, max_length: 20` |
| `url()` | String | `required: true, format: :url, max_length: 2048` |
| `slug()` | String | `format: :slug, max_length: 255, normalize: {:slugify, uniquify: true}` |
| `uuid()` | String | `format: :uuid, normalize: [:trim, :downcase]` |
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

### Usage with Presets

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
# In your own presets module
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

For complex constraints (composite unique, explicit FK options, etc.):

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

# Migration System

## Pipeline Pattern

Migrations use a token-based pipeline pattern:

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Migration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_identity(:name, :email)
    |> with_authentication()
    |> with_profile(:bio, :avatar)
    |> with_audit()
    |> with_soft_delete()
    |> with_timestamps()
    |> execute()
  end
end
```

## Pipeline Functions Reference

### Primary Key

| Function | Description |
|----------|-------------|
| `with_uuid_primary_key(opts)` | UUIDv7 primary key |
| `with_uuid_v4_primary_key()` | Legacy UUID v4 |

Options: `name: :id`, `type: :uuidv7/:uuidv4`

### Identity

| Function | Description |
|----------|-------------|
| `with_identity(fields)` | Add identity fields |

Fields: `:name`, `:email`, `:phone`, `:username`

```elixir
|> with_identity(:name, :email)
|> with_identity([:name, :email, :phone])
```

### Authentication

| Function | Description |
|----------|-------------|
| `with_authentication(opts)` | Add auth fields |

Types: `:password`, `:oauth`, `:magic_link`

```elixir
|> with_authentication()  # password (default)
|> with_authentication(type: :oauth)
|> with_authentication(type: :magic_link)
```

### Profile

| Function | Description |
|----------|-------------|
| `with_profile(fields)` | Add profile fields |

Fields: `:bio`, `:avatar`, `:location`

### Business/Financial

| Function | Description |
|----------|-------------|
| `with_money(fields)` | Decimal fields (10,2) |
| `with_status(opts)` | Status with check constraint |

```elixir
|> with_money(:amount, :tax, :total)
|> with_money([:subtotal, :discount])
|> with_status(values: ["draft", "active"], default: "draft")
```

### Metadata

| Function | Description |
|----------|-------------|
| `with_metadata(opts)` | JSONB metadata with GIN index |
| `with_tags(opts)` | String array with GIN index |
| `with_settings(opts)` | JSONB settings field |

```elixir
|> with_metadata()
|> with_metadata(name: :properties)
|> with_tags()
|> with_tags(name: :categories)
```

### Type & Status Fields

| Function | Description |
|----------|-------------|
| `with_type_fields(opts)` | Type classification (citext) |
| `with_status_fields(opts)` | Status tracking (citext) |

```elixir
|> with_type_fields()
|> with_type_fields(only: [:type, :subtype])
|> with_status_fields()
|> with_status_fields(with_transition: true)
```

### Audit

| Function | Description |
|----------|-------------|
| `with_audit_fields(opts)` | Audit tracking |
| `with_audit(opts)` | Alias for audit_fields |

Options: `track_user`, `track_ip`, `track_session`, `track_changes`

```elixir
|> with_audit()
|> with_audit(track_user: true, track_ip: true)
|> with_audit(track_changes: true)  # Adds version + history
```

### Soft Delete

| Function | Description |
|----------|-------------|
| `with_soft_delete(opts)` | Soft delete support |

Options: `track_urm` (default: true), `track_user`, `track_reason`

```elixir
|> with_soft_delete()
|> with_soft_delete(track_user: true, track_reason: true)
|> with_soft_delete(track_urm: false)
```

### Timestamps

| Function | Description |
|----------|-------------|
| `with_timestamps(opts)` | Timestamp fields |

Options: `only`, `type`, `with_deleted`, `with_lifecycle`

```elixir
|> with_timestamps()
|> with_timestamps(only: [:inserted_at])
|> with_timestamps(with_deleted: true)
|> with_timestamps(with_lifecycle: true)  # published_at, archived_at, expires_at
```

### Index Pipelines

For standalone indexes:

```elixir
create_index(:users, [:email])
|> unique()
|> where("deleted_at IS NULL")
|> execute()

create_index(:products, [:tags])
|> using(:gin)
|> execute()
```

### Composition Helpers

| Function | Description |
|----------|-------------|
| `maybe(token, fun, condition)` | Conditionally apply function |
| `tap_inspect(token, label)` | Debug pipeline |
| `validate!(token)` | Validate before execute |

```elixir
|> maybe(&with_soft_delete/1, opts[:soft_delete])
|> tap_inspect("After fields")
|> validate!()
|> execute()
```

---

## DSL Enhanced Macros

For use inside `create table()` blocks:

### Primary Keys

```elixir
create table(:users, primary_key: false) do
  uuid_primary_key()        # UUIDv7
  uuid_primary_key(:uuid)   # Custom name
  uuid_v4_primary_key()     # Legacy UUID v4
end
```

### Field Groups

```elixir
create table(:products, primary_key: false) do
  uuid_primary_key()

  # Type classification
  type_fields()
  type_fields(only: [:type, :subtype])
  type_fields(type: :string)

  # Status tracking
  status_fields()
  status_fields(only: [:status])
  status_fields(with_transition: true)

  # Audit fields
  audit_fields()
  audit_fields(track_user: true, track_ip: true)
  audit_fields(track_changes: true)

  # Soft delete
  soft_delete_fields()
  soft_delete_fields(track_user: true, track_reason: true)

  # Timestamps (use Ecto's version inside create block)
  timestamps(type: :utc_datetime_usec)
end
```

### Metadata Fields

```elixir
create table(:articles, primary_key: false) do
  uuid_primary_key()

  metadata_field()           # :metadata
  metadata_field(:properties)

  tags_field()               # :tags
  tags_field(:categories)

  money_field(:price)
  money_field(:cost, precision: 12, scale: 4)
end
```

### Foreign Keys

```elixir
create table(:posts, primary_key: false) do
  uuid_primary_key()

  belongs_to_field(:user)
  belongs_to_field(:category, null: true)
  belongs_to_field(:author, on_delete: :cascade)
end
```

### Index Macros

```elixir
# After create table block
type_field_indexes(:products)
type_field_indexes(:products, only: [:type])

status_field_indexes(:orders)
status_field_indexes(:orders, only: [:status])

audit_field_indexes(:documents, track_user: true)

timestamp_indexes(:articles)
timestamp_indexes(:articles, with_deleted: true)

metadata_index(:products)
metadata_index(:products, :properties)

tags_index(:articles)

foreign_key_index(:posts, :user_id)

# All standard indexes
create_standard_indexes(:products)
```

---

## Field Builder Reference

### Token Structure

```elixir
%Events.Core.Migration.Token{
  type: :table | :index | :constraint | :alter,
  name: :users,
  fields: [{:email, :citext, [null: false]}, ...],
  indexes: [{:users_email_index, [:email], [unique: true]}, ...],
  constraints: [{:status_check, :check, [check: "..."]}, ...],
  options: [primary_key: false],
  meta: %{created_at: ~U[...]}
}
```

### Token Functions

| Function | Description |
|----------|-------------|
| `Token.new(type, name, opts)` | Create new token |
| `Token.add_field(token, name, type, opts)` | Add field |
| `Token.add_fields(token, fields)` | Add multiple fields |
| `Token.add_index(token, name, columns, opts)` | Add index |
| `Token.add_constraint(token, name, type, opts)` | Add constraint |
| `Token.put_option(token, key, value)` | Set option |
| `Token.merge_options(token, opts)` | Merge options |
| `Token.validate(token)` | Validate token |
| `Token.validate!(token)` | Validate or raise |
| `Token.has_field?(token, name)` | Check field exists |
| `Token.get_field(token, name)` | Get field definition |
| `Token.field_names(token)` | List field names |
| `Token.index_names(token)` | List index names |
| `Token.has_primary_key?(token)` | Has PK defined? |

### Pre-built Field Sets

```elixir
alias Events.Core.Migration.Fields

# Name fields
Fields.name_fields()
Fields.name_fields(required: true)

# Address fields
Fields.address_fields()
Fields.address_fields(prefix: :billing)

# Geolocation
Fields.geo_fields()
Fields.geo_fields(with_altitude: true, with_accuracy: true)

# Contact
Fields.contact_fields()
Fields.contact_fields(prefix: :work)

# Social media
Fields.social_fields()

# SEO
Fields.seo_fields()

# File attachments
Fields.file_fields(:avatar)
Fields.file_fields(:document, with_metadata: true)

# Counters
Fields.counter_fields([:view_count, :like_count])
Fields.counter_field(:comment_count)

# Money
Fields.money_fields([:subtotal, :tax, :total])
Fields.money_fields([:amount], precision: 12, scale: 4)
```

---

# Decorator System

The Events decorator system provides cross-cutting concerns through function decorators. Use decorators for type contracts, caching, telemetry, validation, and security.

## Getting Started

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:my_app, :users, :get])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

---

## Type Decorators

Type decorators document and optionally validate function return types. **All fallible functions should use type decorators.**

### `returns_result/1`

Declares function returns `{:ok, value} | {:error, reason}`.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ok` | `type` | `:any` | Type for success value |
| `error` | `type` | `:any` | Type for error value |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |
| `coerce` | `boolean` | `false` | Attempt type coercion |

```elixir
# Basic result type
@decorate returns_result(ok: User.t(), error: :atom)
def get_user(id), do: Repo.get(User, id) |> wrap_result()

# With validation
@decorate returns_result(ok: %User{}, error: Ecto.Changeset.t(), validate: true)
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

# Strict mode (raises on wrong type)
@decorate returns_result(ok: String.t(), error: :atom, strict: true)
def format_name(user), do: {:ok, String.upcase(user.name)}
```

### `returns_maybe/1`

Declares function returns `value | nil`.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | `type` | **required** | Type for non-nil value |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |
| `default` | `any` | `nil` | Default if nil returned |

```elixir
# Basic maybe type
@decorate returns_maybe(User.t())
def find_user_by_email(email), do: Repo.get_by(User, email: email)

# With default value
@decorate returns_maybe(String.t(), default: "Unknown")
def get_username(user_id) do
  case Repo.get(User, user_id) do
    %User{name: name} -> name
    nil -> nil
  end
end
```

### `returns_bang/1`

Declares function returns value or raises.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | `type` | **required** | Type for return value |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |
| `on_error` | `:raise \| :unwrap` | `:raise` | How to handle `{:error, _}` |

```elixir
# Basic bang variant
@decorate returns_bang(User.t())
def get_user!(id), do: Repo.get!(User, id)

# Auto-unwrap result tuples
@decorate returns_bang(User.t(), on_error: :unwrap)
def create_user!(attrs) do
  # If this returns {:error, changeset}, decorator raises
  User.create(attrs)
end
```

### `returns_struct/1`

Declares function returns a specific struct.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | `atom` | **required** | Struct module name |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |
| `nullable` | `boolean` | `false` | Allow nil returns |

```elixir
@decorate returns_struct(User)
def build_user(attrs), do: struct(User, attrs)

@decorate returns_struct(User, nullable: true)
def find_user(id), do: Repo.get(User, id)
```

### `returns_list/1`

Declares function returns a list of specific type.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `of` | `type` | **required** | Element type |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |
| `min_length` | `integer` | `nil` | Minimum list length |
| `max_length` | `integer` | `nil` | Maximum list length |

```elixir
@decorate returns_list(of: User.t())
def list_users, do: Repo.all(User)

@decorate returns_list(of: %User{}, min_length: 1, max_length: 100)
def get_active_users do
  User |> where([u], u.active == true) |> Repo.all()
end
```

### `returns_union/1`

Declares function returns one of multiple types.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `types` | `list` | **required** | List of allowed types |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |

```elixir
@decorate returns_union(types: [User.t(), Organization.t()])
def find_entity(id) do
  Repo.get(User, id) || Repo.get(Organization, id)
end

@decorate returns_union(types: [String.t(), nil])
def get_optional_name(user), do: user.name
```

### `returns_pipeline/1`

Returns pipeline-compatible result with chainable helpers.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ok` | `type` | **required** | Type for success case |
| `error` | `type` | `:atom` | Type for error case |
| `validate` | `boolean` | `false` | Enable runtime validation |
| `strict` | `boolean` | `false` | Raise on type mismatch |
| `chain` | `boolean` | `true` | Enable pipeline chaining |

```elixir
@decorate returns_pipeline(ok: User.t(), error: Ecto.Changeset.t())
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end

# Usage with pipeline helpers
def register_user(attrs) do
  create_user(attrs)
  |> and_then(&send_welcome_email/1)
  |> and_then(&create_user_settings/1)
  |> map_ok(&UserView.render/1)
  |> map_error(&format_error/1)
end
```

### `normalize_result/1`

Normalizes any return value to `{:ok, _} | {:error, _}` pattern.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `error_patterns` | `list` | `[:error, :invalid, ...]` | Values treated as errors |
| `nil_is_error` | `boolean` | `false` | Treat nil as error |
| `false_is_error` | `boolean` | `false` | Treat false as error |
| `wrap_exceptions` | `boolean` | `true` | Catch and wrap exceptions |
| `error_mapper` | `function` | `nil` | Transform error values |
| `success_mapper` | `function` | `nil` | Transform success values |

```elixir
# Basic normalization
@decorate normalize_result()
def get_user(id), do: Repo.get(User, id)
# Returns: {:ok, %User{}} or {:ok, nil}

# Treat nil as error
@decorate normalize_result(nil_is_error: true)
def get_user(id), do: Repo.get(User, id)
# Returns: {:ok, %User{}} or {:error, :nil_value}

# Wrap exceptions
@decorate normalize_result(wrap_exceptions: true)
def risky_operation, do: raise "Something went wrong"
# Returns: {:error, %RuntimeError{...}}

# Transform errors
@decorate normalize_result(error_mapper: fn e -> "Failed: #{inspect(e)}" end)
def fetch_data, do: {:error, :timeout}
# Returns: {:error, "Failed: :timeout"}
```

---

## Caching Decorators

### `cacheable/1`

Read-through caching - returns cached value on hit, executes function on miss.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache` | `atom \| mfa` | **required** | Cache module or MFA tuple |
| `key` | `any` | `nil` | Explicit cache key |
| `key_generator` | `atom \| mfa` | `nil` | Custom key generator |
| `ttl` | `integer` | `nil` | Time-to-live (ms) |
| `match` | `function` | `nil` | Filter cacheable results |
| `on_error` | `:raise \| :nothing` | `:raise` | Error handling |

```elixir
# Simple caching with explicit key
@decorate cacheable(cache: MyCache, key: {User, id})
def get_user(id), do: Repo.get(User, id)

# With TTL
@decorate cacheable(cache: MyCache, key: id, ttl: :timer.hours(1))
def get_user(id), do: Repo.get(User, id)

# With match function (only cache successful results)
@decorate cacheable(cache: MyCache, key: id, match: &match_ok/1)
def get_user(id), do: Repo.get(User, id)

defp match_ok(%User{}), do: true
defp match_ok(nil), do: false

# Dynamic cache resolution
@decorate cacheable(cache: {MyApp.Config, :get_cache, []}, key: id)
def get_user(id), do: Repo.get(User, id)
```

### `cache_put/1`

Write-through caching - always executes and updates cache.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache` | `atom \| mfa` | **required** | Cache module |
| `keys` | `list` | **required** | Cache keys to update |
| `ttl` | `integer` | `nil` | Time-to-live (ms) |
| `match` | `function` | `nil` | Filter cacheable results |
| `on_error` | `:raise \| :nothing` | `:raise` | Error handling |

```elixir
# Update multiple keys
@decorate cache_put(cache: MyCache, keys: [{User, user.id}, {User, user.email}])
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

# With match function
@decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

defp match_ok({:ok, user}), do: {true, user}
defp match_ok({:error, _}), do: false
```

### `cache_evict/1`

Cache invalidation - removes entries from cache.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache` | `atom \| mfa` | **required** | Cache module |
| `keys` | `list` | **required** | Cache keys to evict |
| `all_entries` | `boolean` | `false` | Delete all entries |
| `before_invocation` | `boolean` | `false` | Evict before execution |
| `on_error` | `:raise \| :nothing` | `:raise` | Error handling |

```elixir
# Evict specific keys
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
def delete_user(id), do: Repo.delete(User, id)

# Evict multiple keys
@decorate cache_evict(cache: MyCache, keys: [{User, user.id}, {User, user.email}])
def delete_user(user), do: Repo.delete(user)

# Evict all entries
@decorate cache_evict(cache: MyCache, all_entries: true)
def delete_all_users, do: Repo.delete_all(User)

# Evict before invocation (safer for failures)
@decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
def logout(token), do: revoke_session(token)
```

---

## Telemetry Decorators

### `telemetry_span/1`

Wraps function in `:telemetry.span/3` for Erlang telemetry events.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `event` | `list(atom)` | auto | Telemetry event name |
| `include` | `list(atom)` | `[]` | Variables to include |
| `metadata` | `map` | `%{}` | Static metadata |

```elixir
@decorate telemetry_span([:my_app, :users, :create])
def create_user(attrs), do: Repo.insert(User.changeset(%User{}, attrs))

# With variable capture
@decorate telemetry_span([:my_app, :process], include: [:user_id, :result])
def process_data(user_id, data) do
  result = do_processing(data)
  {:ok, result}
end
```

**Events Emitted:**
- `event ++ [:start]` - When function starts
- `event ++ [:stop]` - When function completes
- `event ++ [:exception]` - When function raises

### `otel_span/1`

Creates an OpenTelemetry span for distributed tracing.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | `string` | auto | Span name |
| `include` | `list(atom)` | `[]` | Variables for attributes |
| `attributes` | `map` | `%{}` | Static attributes |

```elixir
@decorate otel_span("user.create")
def create_user(attrs), do: Repo.insert(User.changeset(%User{}, attrs))

# With attributes
@decorate otel_span("payment.process", include: [:amount, :currency])
def process_payment(amount, currency, card) do
  PaymentGateway.charge(amount, currency, card)
end
```

### `log_call/1`

Logs function entry with arguments.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `level` | `atom` | `:info` | Log level |
| `message` | `string` | auto | Custom message |
| `metadata` | `map` | `%{}` | Additional metadata |

```elixir
@decorate log_call(level: :info)
def important_operation, do: # Logs "Calling Module.important_operation/0"

@decorate log_call(level: :debug, message: "Starting background task")
def background_task(data), do: process(data)
```

### `log_context/1`

Sets Logger metadata from function arguments.

| Option | Type | Description |
|--------|------|-------------|
| `fields` | `list(atom)` | Fields to include in Logger metadata |

```elixir
@decorate log_context([:user_id, :request_id])
def handle_request(user_id, request_id, params) do
  Logger.info("Processing") # Includes user_id and request_id
  do_work(params)
end
```

### `log_if_slow/1`

Warns if function execution exceeds threshold.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `threshold` | `integer` | **required** | Threshold in ms |
| `level` | `atom` | `:warn` | Log level |
| `message` | `string` | auto | Custom message |

```elixir
@decorate log_if_slow(threshold: 1000)
def potentially_slow_query(params), do: Repo.all(complex_query(params))

@decorate log_if_slow(threshold: 500, level: :error, message: "Critical path too slow")
def critical_operation, do: perform_critical_work()
```

### `track_memory/1`

Logs warning if memory usage exceeds threshold.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `threshold` | `integer` | **required** | Threshold in bytes |
| `level` | `atom` | `:warn` | Log level |

```elixir
@decorate track_memory(threshold: 10_000_000) # 10MB
def memory_intensive_operation(data), do: process_large_dataset(data)
```

### `capture_errors/1`

Reports exceptions to error tracking service.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `reporter` | `atom` | **required** | Reporter module (e.g., Sentry) |
| `threshold` | `integer` | `1` | Report after N attempts |

```elixir
@decorate capture_errors(reporter: Sentry)
def risky_operation(data), do: perform_risky_work(data)

@decorate capture_errors(reporter: Sentry, threshold: 3)
def operation_with_retries(data), do: try_with_retries(data)
```

### `log_query/1`

Logs database queries with timing.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `slow_threshold` | `integer` | `1000` | Slow query threshold (ms) |
| `level` | `atom` | `:debug` | Normal log level |
| `slow_level` | `atom` | `:warn` | Slow query log level |
| `include_query` | `boolean` | `true` | Include query in log |

```elixir
@decorate log_query(slow_threshold: 500)
def get_user_with_posts(user_id) do
  User |> where(id: ^user_id) |> preload(:posts) |> Repo.one()
end
```

### `measure/1`

Simple execution time measurement.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `unit` | `atom` | `:millisecond` | Time unit |
| `label` | `string` | auto | Custom label |
| `include_result` | `boolean` | `false` | Include result info |

```elixir
@decorate measure()
def calculate(x, y), do: x * y
# Output: [MEASURE] MyModule.calculate/2 took 15ms

@decorate measure(unit: :microsecond, label: "DB Query")
def query_database, do: Repo.all(User)
# Output: [MEASURE] DB Query took 1234μs
```

### `benchmark/1`

Comprehensive benchmarking with statistics.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `iterations` | `integer` | `1` | Number of iterations |
| `warmup` | `integer` | `0` | Warmup iterations |
| `format` | `atom` | `:simple` | Output format |
| `memory` | `boolean` | `false` | Track memory |

```elixir
@decorate benchmark(iterations: 1000)
def fast_operation(x, y), do: x + y

@decorate benchmark(iterations: 100, warmup: 10, format: :statistical, memory: true)
def complex_operation(data), do: process(data)
```

**Output formats:**
- `:simple` - Average, min, max
- `:detailed` - Add median, range
- `:statistical` - Add std dev, percentiles (p95, p99)

---

## Validation Decorators

### `validate_schema/1`

Validates function arguments against a schema.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `schema` | `atom \| map` | **required** | Schema module or inline |
| `on_error` | `atom` | `:return_error` | Error handling |
| `coerce` | `boolean` | `true` | Coerce types |
| `strict` | `boolean` | `false` | Reject unknown fields |

```elixir
# Ecto schema validation
@decorate validate_schema(schema: UserSchema)
def create_user(params), do: User.create(params)

# Inline schema
@decorate validate_schema(
  schema: %{
    name: [type: :string, required: true],
    age: [type: :integer, min: 18]
  }
)
def process_adult(data), do: process(data)

# With error handling
@decorate validate_schema(schema: OrderSchema, on_error: :return_error, strict: true)
def place_order(order_params), do: Order.create(order_params)
```

### `coerce_types/1`

Coerces argument types before execution.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `args` | `keyword` | **required** | Argument type map |
| `on_error` | `atom` | `:keep_original` | Error handling |

```elixir
@decorate coerce_types(args: [
  age: :integer,
  active: :boolean,
  price: :float
])
def process_data(age, active, price) do
  # "25" -> 25, "true" -> true, "19.99" -> 19.99
end

@decorate coerce_types(args: [id: :integer, tags: {:list, :string}], on_error: :raise)
def update_item(id, tags), do: Item.update(id, tags)
```

### `serialize/1`

Transforms function output to specified format.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `format` | `atom` | `:json` | Output format |
| `only` | `list(atom)` | `nil` | Fields to include |
| `except` | `list(atom)` | `[]` | Fields to exclude |
| `rename` | `keyword` | `[]` | Field renaming |
| `transform` | `function` | `nil` | Custom transform |

**Formats:** `:json`, `:map`, `:keyword`, `:binary`

```elixir
@decorate serialize(format: :json, except: [:password, :token])
def get_user(id), do: Repo.get(User, id)

@decorate serialize(format: :map, only: [:id, :name, :email], rename: [email: :email_address])
def get_profile(user_id), do: Repo.get(User, user_id)

# Custom transformation
@decorate serialize(
  format: :json,
  transform: fn result, _opts -> Map.put(result, :fetched_at, DateTime.utc_now()) end
)
def fetch_data(params), do: External.fetch(params)
```

### `contract/1`

Design by Contract - preconditions, postconditions, invariants.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pre` | `function \| list` | `nil` | Precondition(s) |
| `post` | `function \| list` | `nil` | Postcondition(s) |
| `invariant` | `function` | `nil` | Invariant check |
| `on_error` | `atom` | `:raise` | Violation handling (`:raise`, `:warn`, `:return_error`) |

```elixir
@decorate contract(
  pre: fn [x] -> x > 0 end,
  post: fn [x], result -> result >= 0 and result * result == x end
)
def square_root(x), do: :math.sqrt(x)

@decorate contract(
  pre: [
    fn [list] -> is_list(list) end,
    fn [list] -> length(list) > 0 end
  ],
  post: fn [input], output -> length(output) == length(input) end
)
def sort_list(list), do: Enum.sort(list)

# With invariant
@decorate contract(
  pre: fn [account, amount] -> account.balance >= amount end,
  post: fn [account, amount], result -> result.balance == account.balance - amount end,
  invariant: fn account -> account.balance >= 0 end,
  on_error: :raise
)
def withdraw(account, amount) do
  %{account | balance: account.balance - amount}
end
```

---

## Security Decorators

### `role_required/1`

Role-based access control.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `roles` | `list(atom)` | **required** | Allowed roles |
| `check_fn` | `function` | default | Custom role checker |
| `on_error` | `atom` | `:raise` | Error handling (`:raise`, `:return_error`, `:return_nil`) |

```elixir
@decorate role_required(roles: [:admin])
def delete_user(current_user, user_id), do: Repo.delete(User, user_id)

@decorate role_required(roles: [:admin, :moderator], on_error: :return_error)
def ban_user(context, user_id), do: User.ban(user_id)

# Custom role check function
@decorate role_required(
  roles: [:owner],
  check_fn: fn user, roles -> user.role in roles or user.is_superadmin end
)
def sensitive_operation(user, data), do: process(data)
```

### `rate_limit/1`

Rate limiting for functions.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max` | `integer` | **required** | Max calls allowed |
| `window` | `atom` | `:minute` | Time window |
| `by` | `atom` | `:global` | Grouping strategy |
| `key_fn` | `function` | `nil` | Custom key function |
| `on_error` | `atom` | `:raise` | Error handling (`:raise`, `:return_error`, `:sleep`) |
| `backend` | `atom` | `Events.RateLimiter` | Backend module |

**Windows:** `:second`, `:minute`, `:hour`, `:day`
**By:** `:global`, `:ip`, `:user_id`, `:custom`

```elixir
@decorate rate_limit(max: 100, window: :minute)
def public_api_endpoint(params), do: process(params)

@decorate rate_limit(max: 10, window: :hour, by: :user_id, on_error: :return_error)
def expensive_operation(user_id, data), do: perform_expensive_work(data)

# Custom key function
@decorate rate_limit(max: 50, window: :minute, by: :custom, key_fn: fn [conn | _] -> conn.remote_ip end)
def api_endpoint(conn, params), do: process(params)
```

### `audit_log/1`

Audit trail for sensitive operations.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `level` | `atom` | `:info` | Audit level |
| `fields` | `list(atom)` | `[]` | Fields to capture |
| `store` | `atom` | `Events.AuditLog` | Storage module |
| `async` | `boolean` | `true` | Async logging |
| `include_result` | `boolean` | `false` | Include result |
| `metadata` | `map` | `%{}` | Extra metadata |

**Levels:** `:info`, `:warning`, `:critical`

```elixir
@decorate audit_log(level: :critical)
def delete_account(admin_user, account_id), do: Account.delete(account_id)

@decorate audit_log(level: :info, fields: [:user_id, :amount], include_result: true)
def transfer_funds(user_id, from_account, to_account, amount) do
  perform_transfer(from_account, to_account, amount)
end

@decorate audit_log(store: ComplianceAuditLog, metadata: %{regulation: "SOX", system: "financial"})
def modify_financial_records(user, changes), do: apply_changes(changes)
```

---

## Debugging Decorators

**Note:** Debugging decorators are automatically disabled in production.

### `debug/1`

Uses Elixir's `dbg/2` for execution tracing.

```elixir
@decorate debug()
def complex_calculation(x, y) do
  intermediate = x * y
  result = intermediate + 10
  result
end
```

### `inspect/1`

Inspects function arguments and results.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `only` | `atom` | `:both` | `:args`, `:result`, or `:both` |
| `label` | `string` | auto | Custom label |

```elixir
@decorate inspect(only: :args)
def process(data), do: transform(data)

@decorate inspect(label: "User lookup")
def get_user(id), do: Repo.get(User, id)
```

### `pry/1`

Interactive IEx.pry breakpoint.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `condition` | `function` | `nil` | Conditional breakpoint |

```elixir
@decorate pry()
def debug_me(data), do: process(data)

@decorate pry(condition: fn [data] -> data.suspicious end)
def conditional_debug(data), do: process(data)
```

---

## Purity Decorators

### `pure/1`

Marks function as pure (no side effects).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `verify` | `boolean` | `false` | Runtime verification |
| `sample_rate` | `float` | `0.01` | Verification sample rate |

```elixir
@decorate pure()
def add(a, b), do: a + b

@decorate pure(verify: true, sample_rate: 0.1)
def calculate(x), do: x * 2
```

### `deterministic/1`

Verifies same inputs produce same outputs.

```elixir
@decorate deterministic()
def hash(input), do: :crypto.hash(:sha256, input)
```

### `idempotent/1`

Marks function as idempotent (safe to call multiple times).

```elixir
@decorate idempotent()
def set_status(user, :active), do: %{user | status: :active}
```

### `memoizable/1`

Indicates function is safe to cache.

```elixir
@decorate memoizable()
def expensive_calculation(input), do: complex_math(input)
```

---

## Decorator Best Practices

1. **Always use type decorators** for function contracts
2. **Stack decorators** for comprehensive behavior:
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom)
   @decorate telemetry_span([:app, :users, :create])
   @decorate validate_schema(schema: UserSchema)
   def create_user(params), do: ...
   ```
3. **Use `normalize_result/1`** for external APIs
4. **Add telemetry spans** to all public API functions
5. **Use caching decorators** instead of manual caching
6. **Apply security decorators** to protected endpoints

---

## Decorator Quick Reference

| Category | Decorators |
|----------|-----------|
| **Types** | `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `returns_pipeline`, `normalize_result` |
| **Caching** | `cacheable`, `cache_put`, `cache_evict` |
| **Telemetry** | `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `log_query`, `log_remote`, `capture_errors`, `measure`, `benchmark`, `track_memory` |
| **Validation** | `validate_schema`, `coerce_types`, `serialize`, `contract` |
| **Security** | `role_required`, `rate_limit`, `audit_log` |
| **Debugging** | `debug`, `inspect`, `pry`, `trace_vars` |
| **Purity** | `pure`, `deterministic`, `idempotent`, `memoizable`, `referentially_transparent` |

---

# Complete Examples

## Full Schema Example

```elixir
defmodule MyApp.Accounts.User do
  use Events.Schema
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

## Full Migration Example

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Migration

  def change do
    # Enable extensions
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto", ""

    # Create users table with pipeline
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_identity(:name, :email, :username)
    |> with_authentication()
    |> with_profile(:bio, :avatar, :location)
    |> with_type_fields(only: [:type])
    |> with_status_fields(only: [:status])
    |> with_metadata()
    |> with_audit(track_user: true)
    |> with_soft_delete(track_reason: true)
    |> with_timestamps()
    |> execute()

    # Add indexes
    create unique_index(:users, [:email], where: "deleted_at IS NULL")
    create unique_index(:users, [:username], where: "deleted_at IS NULL")
    create index(:users, [:status])
    create index(:users, [:account_id])
    create index(:users, [:metadata], using: :gin)

    # Add constraints
    create constraint(:users, :users_age_positive, check: "age > 0 OR age IS NULL")
    create constraint(:users, :valid_coordinates,
      check: "(latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL)")
  end
end
```

## Alternative: DSL Enhanced Style

```elixir
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Events.Migration

  def change do
    create table(:products, primary_key: false) do
      uuid_primary_key()

      add :name, :citext, null: false
      add :slug, :citext, null: false
      add :description, :text
      add :price, :decimal, precision: 10, scale: 2
      add :quantity, :integer, default: 0

      type_fields(only: [:type, :category])
      status_fields(only: [:status])
      metadata_field()
      tags_field()

      belongs_to_field(:account)
      belongs_to_field(:created_by_user, null: true)

      soft_delete_fields()
      timestamps(type: :utc_datetime_usec)
    end

    # Indexes
    create unique_index(:products, [:account_id, :slug], where: "deleted_at IS NULL")
    create index(:products, [:status])
    type_field_indexes(:products, only: [:type, :category])
    metadata_index(:products)
    tags_index(:products)
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

### Migration Pipeline

```
create_table(:name)
|> with_uuid_primary_key()       # Primary key
|> with_identity(:name, :email)  # Identity fields
|> with_authentication()         # Auth fields
|> with_profile(:bio, :avatar)   # Profile fields
|> with_money(:price, :tax)      # Decimal fields
|> with_type_fields()            # Type classification
|> with_status_fields()          # Status tracking
|> with_metadata()               # JSONB metadata
|> with_tags()                   # String array
|> with_audit()                  # Audit tracking
|> with_soft_delete()            # Soft delete
|> with_timestamps()             # Timestamps
|> execute()                     # Run migration
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
