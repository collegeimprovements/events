# Complete OmSchema Feature Reference

> **Comprehensive reference for all OmSchema capabilities.**
> For quick reference, see `SCHEMA.md`. For full docs, see `docs/EVENTS_REFERENCE.md`.

---

## 1. Core Schema Definition

```elixir
defmodule MyApp.User do
  use OmSchema

  schema "users" do
    field :name, :string, required: true
    field :email, :string, required: true, format: :email
    timestamps()
  end
end
```

**What `use OmSchema` provides:**
- UUIDv7 primary keys (`@primary_key {:id, :binary_id, autogenerate: true}`)
- Auto-generated `base_changeset/2` and `base_changeset/3`
- Field introspection functions
- Constraint helpers
- Sensitive field protocol implementations (Inspect, Jason.Encoder)

---

## 2. Field Validation Options

### 2.1 Core Options

| Option | Type | Description |
|--------|------|-------------|
| `required: true` | boolean | Field must be present |
| `cast: false` | boolean | Exclude from cast (set programmatically) |
| `immutable: true` | boolean | Can only be set on create, not update |
| `sensitive: true` | boolean | Redacted in logs/inspect |
| `null: false` | boolean | NOT NULL in DB (auto-set from required) |

### 2.2 Documentation Options

| Option | Type | Description |
|--------|------|-------------|
| `doc: "Description"` | string | Field documentation |
| `example: "value"` | term | Example value for docs/OpenAPI |

### 2.3 String Validations

| Option | Example | Description |
|--------|---------|-------------|
| `min_length: 3` | | Minimum string length |
| `max_length: 100` | | Maximum string length |
| `length: 10` | | Exact length |
| `format: :email` | | Built-in format (see list below) |
| `format: ~r/^[A-Z]+$/` | | Custom regex |
| `in: ["a", "b"]` | | Allowed values |
| `not_in: ["x"]` | | Forbidden values |
| `mappers: [:trim, :downcase]` | | Auto-transform values |

**Built-in Formats:**
`:email`, `:url`, `:uuid`, `:slug`, `:username`, `:phone`, `:ipv4`, `:ipv6`

**Available Mappers:**
`:trim`, `:downcase`, `:upcase`, `:capitalize`, `:titlecase`, `:squish`, `:slugify`, `:digits_only`, `:alphanumeric_only`

### 2.4 Numeric Validations

| Option | Description |
|--------|-------------|
| `min: 0` | Minimum value (alias: `greater_than_or_equal_to`) |
| `max: 100` | Maximum value (alias: `less_than_or_equal_to`) |
| `positive: true` | Value > 0 |
| `non_negative: true` | Value >= 0 |
| `negative: true` | Value < 0 |
| `greater_than: 5` | Value > 5 |
| `less_than: 10` | Value < 10 |
| `equal_to: 42` | Value == 42 |
| `multiple_of: 5` | Must be multiple of 5 |

### 2.5 Array Validations

| Option | Description |
|--------|-------------|
| `min_length: 1` | Minimum array length |
| `max_length: 10` | Maximum array length |
| `unique_items: true` | All items must be unique |
| `item_format: ~r/\d+/` | Validate each string item |
| `item_min: 0` | Minimum value for numeric items |
| `item_max: 100` | Maximum value for numeric items |

### 2.6 Map Validations

| Option | Description |
|--------|-------------|
| `required_keys: [:name]` | Keys that must be present |
| `optional_keys: [:bio]` | Keys that may be present |
| `forbidden_keys: [:password]` | Keys that cannot be present |
| `min_keys: 1` | Minimum number of keys |
| `max_keys: 50` | Maximum number of keys |

### 2.7 Date/Time Validations

| Option | Description |
|--------|-------------|
| `past: true` | Must be in the past |
| `future: true` | Must be in the future |
| `after: ~D[2020-01-01]` | Must be after date |
| `before: ~D[2030-01-01]` | Must be before date |

### 2.8 Constraint Declarations

| Option | Description |
|--------|-------------|
| `unique: true` | Declare unique constraint |
| `unique: :custom_idx` | With custom index name |
| `unique: [name: :idx, where: "..."]` | With options |
| `check: :positive_age` | Declare check constraint |
| `validators: [{Mod, :fun}]` | Custom validators |

---

## 3. Validation Presets

```elixir
field :email, :string, preset: email()
field :username, :string, preset: username(min_length: 4)
field :phone, :string, preset: phone()
```

### 3.1 String Presets

| Preset | Description |
|--------|-------------|
| `email()` | Email format, max 255, lowercase |
| `username()` | 4-30 alphanumeric, lowercase |
| `password()` | 8-128 chars, not trimmed |
| `url()` | URL format, max 2048 |
| `slug()` | URL-safe slug with auto-slugify |
| `phone()` | E.164 format, 10-20 chars |
| `uuid()` | UUID format, lowercase |
| `ipv4()` | IPv4 address format |
| `ipv6()` | IPv6 address format |
| `hex_color()` | #RRGGBB format |
| `rgb_color()` | rgb(r,g,b) format |
| `semver()` | Semantic version |
| `jwt()` | JWT format |
| `base64()` | Base64 encoded |
| `domain()` | Domain name |
| `file_path()` | File path |
| `timezone()` | Timezone name |
| `mime_type()` | MIME type |
| `social_handle()` | @username format |
| `hashtag()` | #tag format |
| `country_code()` | ISO 3166-1 alpha-2 |
| `language_code()` | ISO 639-1 |
| `currency_code()` | ISO 4217 |
| `zip_code()` | US ZIP+4 format |
| `mac_address()` | MAC address |

### 3.2 Financial/Cryptographic Presets

| Preset | Description |
|--------|-------------|
| `credit_card()` | 13-19 digits with format |
| `ssn()` | SSN format |
| `iban()` | IBAN validation |
| `isbn()` | ISBN validation |
| `bitcoin_address()` | Bitcoin address |
| `ethereum_address()` | Ethereum address |

### 3.3 Numeric Presets

| Preset | Description |
|--------|-------------|
| `positive_integer()` | Integer > 0, default 0 |
| `money()` | Non-negative, max 999,999,999.99 |
| `percentage()` | 0-100 |
| `age()` | 0-150 |
| `rating()` | 1-5 stars |
| `latitude()` | -90 to 90 |
| `longitude()` | -180 to 180 |

### 3.4 Other Presets

| Preset | Description |
|--------|-------------|
| `enum(in: [...])` | Enum with allowed values |
| `tags()` | String array with unique items |
| `metadata()` | Map with max 100 keys |
| `timestamp()` | Optional timestamp |

---

## 4. Field Group Macros

```elixir
schema "orders" do
  field :name, :string

  type_fields(only: [:type])
  status_fields(values: [:pending, :paid], default: :pending)
  audit_fields()
  timestamps()
  metadata_field()
  soft_delete_field()
end
```

| Macro | Fields Added | Options |
|-------|--------------|---------|
| `type_fields()` | `:type`, `:subtype` | `only:`, field opts |
| `status_fields(values: [...])` | `:status` (enum) | `values:`, `default:`, `required:` |
| `audit_fields()` | `:created_by_urm_id`, `:updated_by_urm_id` | `only:`, field opts |
| `timestamps()` | `:inserted_at`, `:updated_at` | `only:`, `type:` |
| `metadata_field()` | `:metadata` (map) | `default:` |
| `assets_field()` | `:assets` (map) | `default:` |
| `soft_delete_field()` | `:deleted_at` + helpers | `track_urm:` |

### Soft Delete Helpers (auto-generated)

```elixir
User.deleted?(user)                    # Check if soft-deleted
User.soft_delete_changeset(user)       # Mark as deleted
User.restore_changeset(user)           # Restore from deletion
User.not_deleted(query)                # Exclude deleted
User.only_deleted(query)               # Only deleted
User.with_deleted(query)               # All records
```

---

## 5. Constraint DSL

```elixir
schema "memberships" do
  belongs_to :user, User
  belongs_to :account, Account
  field :role, :string

  constraints do
    unique [:user_id, :account_id], name: :memberships_user_account_idx
    foreign_key :user_id, references: :users, on_delete: :cascade
    check :valid_role, expr: "role IN ('admin', 'member', 'viewer')"
    index :role, name: :memberships_role_idx
    exclude :no_overlap, using: :gist, expr: "room WITH =, period WITH &&"
  end
end
```

| Macro | Description |
|-------|-------------|
| `unique(fields, opts)` | Unique constraint (single or composite) |
| `foreign_key(field, opts)` | FK with on_delete, on_update, deferrable |
| `check(name, expr: "...")` | Check constraint with SQL expression |
| `index(fields, opts)` | Non-unique index |
| `exclude(name, opts)` | PostgreSQL exclusion constraint |

### Foreign Key Options

```elixir
foreign_key :user_id,
  references: :users,
  column: :id,
  on_delete: :cascade,      # :nothing, :cascade, :restrict, :nilify_all, :delete_all
  on_update: :nothing,
  deferrable: :initially_deferred,
  name: :custom_fk_name
```

---

## 6. Auto-Generated Functions

### 6.1 Introspection

```elixir
User.field_validations()       # [{:name, :string, [required: true]}, ...]
User.cast_fields()             # [:name, :email, ...]
User.required_fields()         # [:name, :email]
User.sensitive_fields()        # [:password_hash, :api_key]
User.immutable_fields()        # [:id, :created_at]
User.conditional_required_fields()  # [{:phone, [contact_method: :phone]}]
User.field_docs()              # %{name: %{doc: "...", example: "..."}}
User.embedded_schemas()        # [{:address, :one, Address, true}]
```

### 6.2 Constraint Introspection

```elixir
User.constraints()             # %{unique: [...], foreign_key: [...], check: [...]}
User.indexes()                 # [%{name: :idx, fields: [...], unique: true}]
User.unique_constraints()      # [%{fields: [:email], name: :users_email_idx}]
User.foreign_keys()            # [%{field: :account_id, references: :accounts}]
User.check_constraints()       # [%{name: :positive_age, expr: "age > 0"}]
```

### 6.3 Changeset Helpers

```elixir
# Basic usage
User.base_changeset(%User{}, attrs)
User.base_changeset(%User{}, attrs, action: :create)

# With options
User.base_changeset(%User{}, attrs,
  only_cast: [:name, :email],
  skip_cast: [:password],
  also_cast: [:extra_field],
  only_required: [:name],
  skip_required: [:email],
  also_required: [:phone],
  check_immutable: true,
  check_conditional_required: true,
  skip_field_validations: false
)

# Apply validations only
User.apply_validations(changeset)
```

### 6.4 Constraint Application

```elixir
changeset
|> User.unique_constraints([{:email, []}, {[:user_id, :role_id], [name: :composite_idx]}])
|> User.foreign_key_constraints([{:account_id, [name: :users_account_id_fkey]}])
|> User.check_constraints([{:age, [name: :users_age_positive]}])
|> User.no_assoc_constraints([{:memberships, [message: "has active memberships"]}])
```

### 6.5 Type Generation

```elixir
User.__typespec_ast__()   # AST for @type t()
User.typespec_string()    # "@type t() :: %__MODULE__{id: binary() | nil, ...}"
```

---

## 7. Conditional Required

```elixir
# Simple equality
field :phone, :string, required_when: [contact_method: :phone]

# AND logic
field :address, :string, required_when: [
  [shipping_required: true], :and, [type: :physical]
]

# OR logic
field :notes, :string, required_when: [
  [status: :rejected], :or, [status: :on_hold]
]

# Comparison operators
field :discount, :decimal, required_when: {order_total, :gt, 100}

# Inclusion
field :priority, :string, required_when: {status, :in, [:urgent, :critical]}

# Unary checks
field :verified_at, :utc_datetime, required_when: {is_verified, :truthy}
field :reason, :string, required_when: {notes, :present}

# Custom function
field :custom, :string, required_when: &MyModule.check_condition/1
```

**Operators:**
- Equality: `[field: value]`
- Comparison: `{field, :gt, value}`, `:gte`, `:lt`, `:lte`, `:eq`, `:neq`
- Inclusion: `{field, :in, [values]}`, `:not_in`
- Boolean: `:and`, `:or`
- Negation: `{:not, condition}`
- Unary: `{field, :truthy}`, `:falsy`, `:present`, `:blank`

---

## 8. Association Macros

### belongs_to

```elixir
belongs_to :account, Account,
  constraint: [
    on_delete: :cascade,
    deferrable: :initially_deferred,
    name: :custom_fk_name
  ]

# Shorthand
belongs_to :user, User, on_delete: :cascade

# Skip FK validation (polymorphic)
belongs_to :commentable, Comment, constraint: false
```

### has_many

```elixir
has_many :memberships, Membership,
  expect_on_delete: :cascade,   # Expected FK behavior on child table
  validate_fk: true             # Enable/disable FK validation
```

### Embedded Schemas

```elixir
embeds_one :address, Address, propagate_validations: true
embeds_many :phone_numbers, PhoneNumber, propagate_validations: true
```

When `propagate_validations: true`, the embedded schema's `base_changeset/2` is automatically used.

---

## 9. Sensitive Field Handling

```elixir
field :password_hash, :string, sensitive: true
field :api_key, :string, sensitive: true
field :ssn, :string, sensitive: true
```

**Auto-generated behavior:**
- `Inspect` protocol: shows `"[REDACTED]"` instead of value
- `Jason.Encoder`: excludes sensitive fields from JSON
- OpenAPI: marks as `writeOnly: true`
- Ecto: sets `redact: true`

**Helper functions:**
```elixir
OmSchema.Sensitive.redact(user)           # Replace values with "[REDACTED]"
OmSchema.Sensitive.to_safe_map(user)      # Map without sensitive fields
OmSchema.Sensitive.to_redacted_map(user)  # Map with redacted markers
OmSchema.Sensitive.has_sensitive_fields?(user)  # Boolean check
```

---

## 10. Custom Validators

```elixir
field :credit_card, :string, validators: [
  {MyApp.Validators, :validate_luhn},
  {MyApp.Validators, :validate_card_network, [:visa, :mastercard]}
]

# Or with function capture
field :code, :string, validators: [&MyApp.validate_code/2]
```

**Built-in custom validators (OmSchema.CustomValidators):**

| Validator | Description |
|-----------|-------------|
| `validate_luhn/2` | Credit card checksum (Luhn algorithm) |
| `validate_no_html/2` | Reject HTML/script tags |
| `validate_json/2` | Valid JSON string |
| `validate_url/2` | URL format |
| `validate_phone_format/2` | Phone number format |
| `validate_semantic_version/2` | SemVer format |
| `validate_not_disposable_email/2` | Block disposable email domains |

---

## 11. State Transitions

```elixir
@transitions %{
  pending: [:approved, :rejected],
  approved: [:shipped],
  rejected: [],
  shipped: [:delivered]
}

def changeset(order, attrs) do
  order
  |> base_changeset(attrs)
  |> validate_transition(:status, @transitions)
end
```

---

## 12. OpenAPI Generation

```elixir
# Single schema
OmSchema.OpenAPI.to_schema(User)
# => %{
#   "type" => "object",
#   "properties" => %{
#     "name" => %{"type" => "string", "minLength" => 1},
#     "email" => %{"type" => "string", "format" => "email"}
#   },
#   "required" => ["name", "email"]
# }

# Multiple schemas as components
OmSchema.OpenAPI.to_components([User, Account])

# Generate paths for CRUD
OmSchema.OpenAPI.to_paths(User, base_path: "/api/users")

# Complete document
OmSchema.OpenAPI.to_document([User, Account],
  title: "My API",
  version: "1.0.0",
  description: "API description"
)
```

**Options:**
- `include_examples: true` - Include example values
- `nullable_style: :openapi_3_0` or `:openapi_3_1`
- `include_id: true` - Include id field

---

## 13. Schema Diffing

```elixir
# Compare schema to database
diff = OmSchema.SchemaDiff.diff(User, repo: MyApp.Repo)
# => %{
#   module: User,
#   table: "users",
#   in_sync: false,
#   missing_in_db: [{:column, :new_field}],
#   missing_in_schema: [{:column, :legacy_field}],
#   type_mismatches: [{:column, :status, :string, "integer"}],
#   nullable_mismatches: [{:column, :email, :required, :nullable}],
#   constraint_mismatches: [{:constraint, :idx, :missing}]
# }

# Human-readable output
OmSchema.SchemaDiff.format(diff)

# Check multiple schemas
OmSchema.SchemaDiff.diff_all([User, Account], repo: MyApp.Repo)

# Check if in sync
OmSchema.SchemaDiff.in_sync?([User, Account], repo: MyApp.Repo)

# Generate migration to fix differences
OmSchema.SchemaDiff.generate_migration(diff)
```

---

## 14. I18n Support

```elixir
# In schema
field :email, :string, message: {:i18n, "email.invalid"}
field :age, :integer, message: {:i18n, "age.too_young", min: 18}

# Per-validation messages
field :password, :string,
  messages: %{
    min_length: {:i18n, "password.too_short", min: 8},
    format: {:i18n, "password.weak"}
  }
```

**Configuration:**
```elixir
config :om_schema, translator: MyApp.Gettext
```

**Usage:**
```elixir
# Translate all errors in changeset
OmSchema.I18n.translate_errors(changeset)

# Create i18n tuple
OmSchema.I18n.i18n("error.key", count: 5)
# => {:i18n, "error.key", [count: 5]}
```

---

## 15. Database Validation

```bash
# Mix task
mix schema.validate
mix schema.validate MyApp.User
mix schema.validate --fail-on-extra-db-columns
```

```elixir
# Programmatic
OmSchema.DatabaseValidator.validate(User)
OmSchema.DatabaseValidator.validate_all()
OmSchema.DatabaseValidator.report(User)
```

**Validates:**
- Columns exist with correct types
- NOT NULL matches `required: true`
- Unique constraints exist
- Foreign key constraints configured correctly
- Check constraints present
- Indexes created
- has_many associations have FKs

---

## 16. Introspection Module

```elixir
# Schema inspection
OmSchema.Introspection.inspect_schema(User)
OmSchema.Introspection.inspect_field(User, :email)
OmSchema.Introspection.document_schema(User)

# JSON Schema generation
OmSchema.Introspection.to_json_schema(User)

# Queries
OmSchema.Introspection.has_validation?(User, :email, :format)
OmSchema.Introspection.required_fields(User)
OmSchema.Introspection.fields_with_validation(User, :min_length)
```

---

## 17. Utility Modules

| Module | Purpose |
|--------|---------|
| `OmSchema.Validation` | Main validation entry point |
| `OmSchema.ValidationPipeline` | Orchestrates validation flow |
| `OmSchema.ValidatorRegistry` | Maps types to validators |
| `OmSchema.Validators.String` | String validations |
| `OmSchema.Validators.Number` | Numeric validations |
| `OmSchema.Validators.Array` | Array validations |
| `OmSchema.Validators.Map` | Map validations |
| `OmSchema.Validators.DateTime` | Date/time validations |
| `OmSchema.Validators.CrossField` | Multi-field validations |
| `OmSchema.Helpers.Normalizer` | String normalization |
| `OmSchema.Helpers.Messages` | Error message handling |
| `OmSchema.Slugify` | Slug generation |
| `OmSchema.TypeGenerator` | Typespec generation |
| `OmSchema.FieldNames` | Configurable field naming |

---

## 18. Configuration

```elixir
# config/config.exs
config :om_schema,
  default_repo: Events.Data.Repo,
  app_name: :events,
  schema_warnings: true,
  translator: MyApp.Gettext

config :om_schema, OmSchema.FieldNames,
  created_by: :created_by_urm_id,
  updated_by: :updated_by_urm_id,
  deleted_by: :deleted_by_urm_id

config :om_schema, :schema_validation,
  enabled: true,
  on_startup: false,
  fail_on_error: false
```

---

## Summary Statistics

| Category | Count |
|----------|-------|
| Field validation options | 50+ |
| Validation presets | 35+ |
| Field group macros | 8 |
| Constraint types | 5 |
| Auto-generated functions | 25+ |
| Built-in mappers | 10 |
| Custom validators | 7 |
| Helper modules | 15+ |
