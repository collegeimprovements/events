# Comprehensive Field Validation Design for Events.Schema

## Research Summary

Based on research of:
- **Ecto's built-in validation capabilities** ([Ecto.Changeset](https://hexdocs.pm/ecto/Ecto.Changeset.html))
- **Rails ActiveRecord validations** ([Rails Guides](https://edgeguides.rubyonrails.org/active_record_validations.html))
- **Django model validators** ([Django Validators](https://docs.djangoproject.com/en/5.1/ref/validators/))
- **TypeScript schema validators** (Zod, Valibot)
- **Ecto field types** ([Ecto.Schema](https://hexdocs.pm/ecto/Ecto.Schema.html), [Ecto.Type](https://hexdocs.pm/ecto/Ecto.Type.html))

---

## All Ecto Field Types

### Primitive Types
- `:integer` - 32/64-bit integer
- `:float` - 64-bit float
- `:boolean` - true/false
- `:string` - UTF-8 string
- `:binary` - raw binary data
- `:decimal` - arbitrary precision decimal (via Decimal library)
- `:map` - Elixir map (stored as JSONB in PostgreSQL)
- `:any` - any type (virtual fields only)

### ID Types
- `:id` - integer ID (auto-increment)
- `:binary_id` - binary UUID (typically UUIDv4 or UUIDv7)

### Date/Time Types
- `:date` - date without time
- `:time` - time without date
- `:time_usec` - time with microsecond precision
- `:naive_datetime` - datetime without timezone
- `:naive_datetime_usec` - datetime without timezone, microsecond precision
- `:utc_datetime` - datetime in UTC
- `:utc_datetime_usec` - datetime in UTC, microsecond precision
- `:duration` - ISO 8601 duration (Elixir 1.17+)

### Composite Types
- `{:array, inner_type}` - array of any Ecto type
- `{:map, inner_type}` - map with specific value type

### Enum Types
- `Ecto.Enum` - atom-based enums stored as strings or integers

### PostgreSQL-Specific Types
- `:citext` - case-insensitive text (requires PostgreSQL extension)
- Custom types via `Ecto.Type` behavior

---

## Validation Rules by Type

### 1. String Types (`:string`, `:citext`)

```elixir
field :email, :string,
  # Length validations
  min_length: 5,                    # minimum length
  max_length: 255,                  # maximum length
  length: 10,                       # exact length
  length: 5..20,                    # length range

  # Format validations
  format: ~r/@/,                    # regex pattern
  format: :email,                   # built-in formats (email, url, uuid, etc.)

  # Content validations
  trim: true,                       # auto-trim whitespace (default: true)

  # Normalization options
  normalize: :downcase,             # Basic transformations:
                                    # - :downcase - "Hello World" → "hello world"
                                    # - :upcase - "Hello World" → "HELLO WORLD"
                                    # - :titlecase - "hello world" → "Hello World"
                                    # - :capitalize - "hello world" → "Hello world"
                                    # - :trim - "  hello  " → "hello"
                                    # - :squish - "  hello   world  " → "hello world" (trim + collapse spaces)

  # Slugify transformations
  normalize: :slugify,              # "Hello World!" → "hello-world"
                                    # Default: lowercase, hyphenated, alphanumeric + hyphens

  normalize: {:slugify, separator: "_"},     # "Hello World" → "hello_world"
  normalize: {:slugify, lowercase: false},   # "Hello World" → "Hello-World"
  normalize: {:slugify, uniquify: true},     # "Hello World" → "hello-world-a3b9f2"
  normalize: {:slugify, uniquify: 6},        # "Hello World" → "hello-world-k9x4m2" (6 chars)

  # Custom slugify module (if you have your own implementation)
  normalize: {:slugify, MyModule},           # Uses MyModule.slugify/1 or MyModule.slugify/2

  # Multiple normalizations (applied in order)
  normalize: [:trim, :downcase],             # First trim, then downcase

  # Custom normalization function
  normalize: {:custom, &MyModule.normalize/1}, # Custom transformation

  allow_blank: false,               # allow empty string (default: false if required)

  # Inclusion/exclusion validations
  in: ["active", "inactive"],       # allowed values (whitelist)
  not_in: ["admin", "root"],        # disallowed values (blacklist)

  # Custom validations
  validate: &MyModule.custom_validator/1,

  # Common options
  required: false,                  # required field (default: false)
  cast: true                        # auto-cast in changeset (default: true)
```

**Ecto mapping:**
- `min_length/max_length` → `validate_length(field, min: X, max: Y)`
- `format` → `validate_format(field, regex)`
- `in` → `validate_inclusion(field, list)`
- `trim: true` → Automatic via changeset transformation

---

### 2. Numeric Types (`:integer`, `:float`, `:decimal`)

```elixir
field :age, :integer,
  # Range validations
  min: 0,                           # minimum value (>= 0)
  max: 150,                         # maximum value (<= 150)

  # Comparison validations (Ecto native)
  greater_than: 0,                  # > (exclusive)
  greater_than_or_equal_to: 0,      # >= (inclusive)
  less_than: 200,                   # < (exclusive)
  less_than_or_equal_to: 150,       # <= (inclusive)
  equal_to: 42,                     # == (exact match)

  # Convenience aliases
  positive: true,                   # > 0 (alias for greater_than: 0)
  non_negative: true,               # >= 0 (alias for greater_than_or_equal_to: 0)
  negative: true,                   # < 0 (alias for less_than: 0)
  non_positive: true,               # <= 0 (alias for less_than_or_equal_to: 0)

  # Divisibility
  multiple_of: 5,                   # must be divisible by 5

  # Inclusion
  in: [1, 2, 3, 5, 8, 13],         # must be one of these values
  not_in: [666, 13],                # must not be these values

  # Decimal-specific (only for :decimal type)
  precision: 10,                    # total digits
  scale: 2,                         # decimal places

  # Common options
  required: false,
  cast: true
```

**Ecto mapping:**
- `min/max` → `validate_number(field, greater_than_or_equal_to: X, less_than_or_equal_to: Y)`
- `positive` → `validate_number(field, greater_than: 0)`
- `in` → `validate_inclusion(field, list)`

---

### 3. Boolean Type (`:boolean`)

```elixir
field :is_active, :boolean,
  # Acceptance validation (for checkboxes, terms of service)
  acceptance: true,                 # must be true (for TOS, GDPR consent)

  # Default value
  default: false,                   # Ecto native

  # Common options
  required: false,                  # Required to be set (true or false)
  cast: true
```

**Ecto mapping:**
- `acceptance: true` → `validate_acceptance(field)`

---

### 4. Map/JSON Types (`:map`, `{:map, type}`)

```elixir
field :metadata, :map,
  # Structure validation
  required_keys: [:user_id, :timestamp],          # must have these keys
  optional_keys: [:ip_address, :user_agent],      # may have these keys
  forbidden_keys: [:password, :secret],           # must not have these keys

  # Size validation
  min_keys: 1,                                     # minimum number of keys
  max_keys: 20,                                    # maximum number of keys

  # Value validation (for typed maps)
  value_type: :string,                            # all values must be strings

  # Schema validation (advanced)
  schema: %{
    user_id: {:integer, required: true},
    email: {:string, format: :email},
    age: {:integer, min: 0, max: 150}
  },

  # JSON string validation (if storing as string)
  json: true,                                      # validate as valid JSON

  # Default
  default: %{},                                   # Ecto native

  # Common options
  required: false,
  cast: true
```

**Custom validation needed:**
- Map structure validation requires custom validator
- Could integrate with NimbleOptions for schema validation
- JSON validation can use Jason.decode/1

**Suggested helper:**
```elixir
defmodule Events.Schema.MapValidator do
  def validate_required_keys(changeset, field, keys)
  def validate_key_count(changeset, field, opts)
  def validate_map_schema(changeset, field, schema)
end
```

---

### 5. Array Types (`{:array, type}`)

```elixir
field :tags, {:array, :string},
  # Length validation
  min_length: 1,                    # minimum items
  max_length: 10,                   # maximum items
  length: 5,                        # exact count
  length: 1..10,                    # range

  # Item validation
  item_format: ~r/^[a-z0-9_]+$/,   # each item must match (for string arrays)
  item_min: 0,                      # each number >= 0 (for numeric arrays)
  item_max: 100,                    # each number <= 100 (for numeric arrays)

  # Array inclusion validation
  in: ["a", "b", "c"],             # array values must be subset of this list (same as subset_of)

  # Uniqueness
  unique_items: true,               # no duplicates allowed

  # Default
  default: [],

  # Common options
  required: false,
  cast: true
```

**Ecto mapping:**
- `min_length/max_length` → `validate_length(field, min: X, max: Y)`
- `in` → `validate_subset(field, list)` (for arrays, `in` means subset validation)
- Item validations require custom validators

**Note:** For arrays, `in: [...]` validates that array elements are a subset of the allowed list.
This is different from scalar fields where `in` validates exact value match.

---

### 6. Date/Time Types

```elixir
field :birth_date, :date,
  # Range validation
  after: ~D[1900-01-01],            # must be after this date
  before: ~D[2024-12-31],           # must be before this date
  after: {:today, days: -1},        # relative to today
  before: {:today, days: 0},        # must be before or equal to today

  # Named constraints
  past: true,                       # must be in the past
  future: true,                     # must be in the future

  # Common options
  required: false,
  cast: true

field :appointment_time, :utc_datetime_usec,
  # Time range
  after: ~U[2024-01-01 00:00:00Z],
  before: ~U[2025-12-31 23:59:59Z],

  # Relative time
  after: {:now, seconds: -3600},    # within last hour
  before: {:now, days: 7},          # within next 7 days

  # Auto-timestamps
  autogenerate: true,               # Ecto native (for inserted_at)

  # Common options
  required: false,
  cast: true
```

**Custom validation needed:**
- Date/time comparisons require custom validators
- Relative time calculation helper functions

---

### 7. Binary Types (`:binary`, `:binary_id`)

```elixir
field :file_data, :binary,
  # Size validation
  min_size: 100,                    # minimum bytes
  max_size: 10_485_760,            # maximum bytes (10MB)

  # Format validation (for binary_id)
  format: :uuid,                    # validate as UUID

  # Common options
  required: false,
  cast: true

field :user_id, :binary_id,
  # References
  foreign_key: true,                # mark as foreign key
  references: User,                 # reference to User schema

  # UUID validation
  format: :uuid_v4,                 # UUIDv4 format
  format: :uuid_v7,                 # UUIDv7 format

  # Common options
  required: false,
  cast: true
```

---

### 8. Enum Types (`Ecto.Enum`)

`Ecto.Enum` is a parameterized type that maps atoms to strings or integers. It provides type-safe enum handling with compile-time validation.

```elixir
# String-backed enum (stored as varchar/text)
field :status, Ecto.Enum,
  values: [:draft, :published, :archived],
  default: :draft,
  required: true,
  cast: true

# Integer-backed enum (stored as integer)
field :priority, Ecto.Enum,
  values: [low: 1, medium: 2, high: 3, urgent: 4],
  default: :medium,
  required: true

# Array of enums (multiple selection)
field :roles, {:array, Ecto.Enum},
  values: [:user, :moderator, :admin],
  default: [:user],
  min_length: 1,                    # must have at least one role
  max_length: 3,                    # max 3 roles
  unique_items: true                # no duplicate roles

# Embed customization
field :embedded_status, Ecto.Enum,
  values: [active: 1, inactive: 0],
  embed_as: :dumped                 # save as integer (1/0) in embeds
  # embed_as: :values               # save as atom (:active/:inactive) - default
```

**Key Features:**
- Atoms are automatically converted to strings/integers on save
- Database values are converted back to atoms on load
- Invalid values raise errors (type safety)
- Works with migrations (use `:string` or `:integer` type)
- Can use PostgreSQL ENUM types for additional DB-level validation

**Helper Functions:**
```elixir
# In application code
Ecto.Enum.values(User, :status)           # [:draft, :published, :archived]
Ecto.Enum.dump_values(User, :status)      # ["draft", "published", "archived"]
Ecto.Enum.mappings(User, :status)         # [draft: "draft", published: "published", archived: "archived"]
```

**Enhanced Field Options for Ecto.Enum:**
```elixir
field :status, Ecto.Enum,
  values: [:active, :inactive, :pending],

  # Validation options (same as string :in validation)
  required: true,
  default: :pending,

  # Custom error messages
  message: "must be active, inactive, or pending",
  messages: %{
    cast: "is not a valid status",
    required: "status is required"
  }
```

**Migration:**
```elixir
# For string-backed enum
add :status, :string

# For integer-backed enum
add :priority, :integer

# For PostgreSQL native ENUM (optional)
execute "CREATE TYPE user_status AS ENUM ('draft', 'published', 'archived')"
add :status, :user_status
```

---

### 9. Association-Related Validations

```elixir
# In the schema
belongs_to :user, User,
  required: true,                   # association must exist
  validate_exists: true             # validate FK exists in DB

has_many :posts, Post,
  validate_count: [min: 1, max: 100], # validate collection size
  validate_each: &MyModule.validate_post/1  # validate each item
```

---

## Cross-Field Validations

```elixir
defmodule MyApp.User do
  use Events.Schema

  schema "users" do
    field :password, :string, required: true, min_length: 8
    field :password_confirmation, :string, virtual: true
    field :email, :string, required: true
    field :backup_email, :string

    # Cross-field validation via validate option
    validate: [
      # Password confirmation
      {:confirmation, :password, match: :password_confirmation},

      # Conditional requirement
      {:require_if, :backup_email, when: {:field, :email, equals: nil}},

      # Mutual exclusivity
      {:one_of, [:email, :phone_number]},

      # Dependency
      {:requires, :country, when: {:field, :state, is_set: true}}
    ]
  end
end
```

---

## Comprehensive Error Message System

### Per-Validation Error Messages

You can customize error messages at different levels of granularity:

```elixir
field :email, :string,
  # Single message for all validations
  message: "must be a valid email address",

  # Specific messages per validation type
  messages: %{
    required: "email cannot be blank",
    format: "must be a valid email format",
    length: "must be between %{min} and %{max} characters",
    unique: "has already been taken"
  },

  # Inline validation with message
  min_length: {5, message: "is too short (minimum is 5 characters)"},
  max_length: {255, message: "is too long (maximum is 255 characters)"},
  format: {~r/@/, message: "must contain an @ symbol"}
```

### Message Interpolation

Error messages support variable interpolation:

```elixir
field :age, :integer,
  min: 18,
  max: 120,
  messages: %{
    number: "must be between %{min} and %{max}",
    greater_than_or_equal_to: "must be at least %{number}",
    less_than_or_equal_to: "cannot exceed %{number}"
  }

# Variables available for interpolation:
# - %{count} - for length validations
# - %{min}, %{max} - for range validations
# - %{number} - for numeric comparisons
# - %{value} - the actual value that failed
# - %{field} - the field name
# - %{type} - the field type
```

### Global Default Messages

Configure default messages at the schema or application level:

```elixir
# In config/config.exs
config :events, Events.Schema,
  error_messages: %{
    required: "is required",
    format: "has invalid format",
    length: "should be %{count} character(s)",
    min_length: "should be at least %{count} character(s)",
    max_length: "should be at most %{count} character(s)",
    number: "must be %{comparison} %{number}",
    inclusion: "is not included in the list",
    exclusion: "is reserved",
    subset: "has an invalid entry",
    acceptance: "must be accepted",
    confirmation: "does not match %{field}",
    unique: "has already been taken"
  }

# In your schema
defmodule MyApp.User do
  use Events.Schema,
    error_messages: %{
      required: "cannot be empty",
      unique: "is already in use"
    }

  schema "users" do
    field :email, :string, required: true, unique: true
  end
end
```

### Field-Level Message Override

```elixir
field :password, :string,
  required: true,
  min_length: 8,
  format: ~r/[A-Z]/,

  # Override all messages for this field
  messages: %{
    required: "Please enter a password",
    too_short: "Password must be at least 8 characters",
    format: "Password must contain at least one uppercase letter"
  }
```

### Validation-Specific Messages

```elixir
field :username, :string,
  required: {true, message: "Username is required"},
  min_length: {3, message: "Username too short (min 3 chars)"},
  max_length: {20, message: "Username too long (max 20 chars)"},
  format: {~r/^[a-zA-Z0-9_]+$/, message: "Username can only contain letters, numbers, and underscores"}
```

### Message Functions

For dynamic messages based on context:

```elixir
field :price, :decimal,
  min: 0,
  message: fn
    %{validation: :number, kind: :greater_than_or_equal_to} ->
      "Price must be a positive number"
    %{validation: :required} ->
      "Please specify a price"
    _ ->
      "Invalid price"
  end
```

### Localization Support

```elixir
field :title, :string,
  required: true,
  messages: %{
    required: &MyApp.Gettext.dgettext("errors", "title.required"),
    too_long: &MyApp.Gettext.dgettext("errors", "title.too_long")
  }
```

---

## Global Options (All Field Types)

```elixir
field :any_field, :any_type,
  # Casting & Requirements
  cast: true,                       # include in changeset cast (default: true)
  required: false,                  # must be present (default: false)
  null: true,                       # allow nil/null values (default: true if not required)
                                    # Note: required: true implies null: false

  # Ecto native options
  default: value,                   # default value
  virtual: false,                   # virtual field (not persisted)
  source: :db_column_name,         # different DB column name
  autogenerate: {M, :f, []},       # auto-generate value
  read_after_writes: true,          # read back from DB after insert/update
  primary_key: false,               # mark as primary key
  redact: false,                    # redact in inspect

  # Validation options
  allow_nil: false,                 # allow nil even if required (alias for null: true)
  allow_blank: false,               # allow empty string/collection

  # Error messages
  message: "custom error",          # single error message for all validations
  messages: %{},                    # map of validation => message

  # Conditional validation
  validate_if: &MyModule.should_validate?/1,
  validate_unless: &MyModule.skip_validation?/1,

  # Database constraints (generates validation)
  unique: true,                     # unique constraint
  unique: [:email, :tenant_id],     # composite unique
  foreign_key: true,                # foreign key constraint
  check: "length(email) > 0",      # check constraint

  # Custom validation function
  validate: &MyModule.custom_validator/1
```

**Note on `required` vs `null`:**
- `required: true` → field must be present in changeset params (not nil/missing)
- `null: false` → field cannot be nil in the database (NOT NULL constraint)
- When `required: true`, `null` defaults to `false`
- When `required: false`, `null` defaults to `true`
- You can explicitly set both: `required: false, null: false` (must be in params when updating, but optional on create)

---

## Slugify Implementation Details

### Default Slugify Behavior

The `:slugify` normalizer converts text to URL-friendly slugs:

```elixir
# Default slugify (like Medium.com)
field :slug, :string,
  normalize: :slugify
  # "Hello World!" → "hello-world"
  # "café résumé" → "cafe-resume"
  # "Hello   World" → "hello-world"
```

**Default behavior:**
1. Converts to lowercase
2. Replaces accented characters (café → cafe)
3. Removes special characters (keeps alphanumeric + separators)
4. Replaces spaces with hyphens
5. Collapses multiple separators into one
6. Trims leading/trailing separators

### Slugify with Uniqueness (Medium.com style)

```elixir
field :slug, :string,
  normalize: {:slugify, uniquify: true}
  # "Hello World" → "hello-world-k3x9m2"
  # "Hello World" → "hello-world-p7q2n5" (different run)

  # Custom suffix length
  normalize: {:slugify, uniquify: 8}
  # "Hello World" → "hello-world-a1b2c3d4"
```

**Uniqueness suffix:**
- Generates random alphanumeric string (lowercase letters + numbers)
- Appended after final separator
- Ensures globally unique slugs (like Medium article URLs)
- Default length: 6 characters
- Character set: `a-z0-9` (36 possible characters per position)

### Slugify Options

```elixir
field :slug, :string,
  normalize: {:slugify, [
    separator: "_",          # Use underscore instead of hyphen
    lowercase: false,        # Keep original casing
    uniquify: true,          # Add random suffix
    uniquify: 8,            # Custom suffix length
    ascii: true,            # Transliterate to ASCII (default: true)
    allowed_chars: ~r/[^a-z0-9-]/, # Custom allowed character pattern
    truncate: 50            # Truncate to max length (before uniquify suffix)
  ]}
```

### Custom Slugify Module

If you have your own slugify implementation:

```elixir
defmodule MyApp.Slugify do
  def slugify(text) do
    # Your custom implementation
    text
    |> String.downcase()
    |> String.replace(~r/[^\w-]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  # Optional: support options
  def slugify(text, opts) do
    slug = slugify(text)

    if opts[:uniquify] do
      suffix_length = if is_integer(opts[:uniquify]), do: opts[:uniquify], else: 6
      "#{slug}-#{generate_suffix(suffix_length)}"
    else
      slug
    end
  end

  defp generate_suffix(length) do
    # Your unique suffix generation logic
  end
end

# Use in schema
field :slug, :string,
  normalize: {:slugify, MyApp.Slugify}
```

### Automatic Slug Generation from Another Field

```elixir
schema "posts" do
  field :title, :string, required: true

  field :slug, :string,
    normalize: {:slugify, uniquify: true},
    autogenerate: {__MODULE__, :generate_slug_from_title, []}
end

def generate_slug_from_title(changeset) do
  case get_change(changeset, :title) do
    nil -> nil
    title -> title  # Will be slugified by normalize option
  end
end
```

### Fallback Slugify (Built-in Implementation)

If no custom module is provided, the built-in slugify function is used:

```elixir
defmodule Events.Schema.Slugify do
  @moduledoc """
  Default slugify implementation for Events.Schema.
  Converts text to URL-friendly slugs.
  """

  def slugify(text, opts \\ []) do
    separator = Keyword.get(opts, :separator, "-")
    lowercase = Keyword.get(opts, :lowercase, true)
    ascii = Keyword.get(opts, :ascii, true)
    uniquify = Keyword.get(opts, :uniquify, false)
    truncate = Keyword.get(opts, :truncate)

    slug =
      text
      |> maybe_transliterate(ascii)
      |> maybe_downcase(lowercase)
      |> remove_special_chars(separator)
      |> collapse_separators(separator)
      |> trim_separators(separator)
      |> maybe_truncate(truncate)

    if uniquify do
      suffix_length = if is_integer(uniquify), do: uniquify, else: 6
      "#{slug}#{separator}#{generate_suffix(suffix_length)}"
    else
      slug
    end
  end

  defp maybe_transliterate(text, true) do
    # Convert accented characters to ASCII equivalents
    # é → e, ñ → n, etc.
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
  end
  defp maybe_transliterate(text, false), do: text

  defp maybe_downcase(text, true), do: String.downcase(text)
  defp maybe_downcase(text, false), do: text

  defp remove_special_chars(text, separator) do
    String.replace(text, ~r/[^\w#{Regex.escape(separator)}]+/u, separator)
  end

  defp collapse_separators(text, separator) do
    String.replace(text, ~r/#{Regex.escape(separator)}+/, separator)
  end

  defp trim_separators(text, separator) do
    String.trim(text, separator)
  end

  defp maybe_truncate(text, nil), do: text
  defp maybe_truncate(text, max_length) do
    String.slice(text, 0, max_length) |> String.trim("-") |> String.trim("_")
  end

  defp generate_suffix(length) do
    # Generate random alphanumeric suffix
    chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    1..length
    |> Enum.map(fn _ -> String.at(chars, :rand.uniform(36) - 1) end)
    |> Enum.join()
  end
end
```

---

## Built-in Format Validators

For convenience, support named format validators:

```elixir
field :email, :string, format: :email
field :url, :string, format: :url
field :uuid, :string, format: :uuid
field :slug, :string, format: :slug
field :hex_color, :string, format: :hex_color
field :ip, :string, format: :ip
field :ip, :string, format: :ipv4
field :ip, :string, format: :ipv6
field :credit_card, :string, format: :credit_card
field :phone, :string, format: :phone
field :postal_code, :string, format: :postal_code
field :ssn, :string, format: :ssn
```

---

## Shorthand Aliases

To reduce verbosity:

```elixir
# Instead of greater_than_or_equal_to: 0
field :count, :integer, min: 0, max: 100

# Instead of format: ~r/@/
field :email, :string, format: :email

# Instead of validate_acceptance
field :terms, :boolean, acceptance: true

# Instead of validate_inclusion
field :status, :string, in: ["active", "inactive"]
```

---

## Implementation Strategy

### Phase 1: Core Infrastructure
1. Override `schema` macro (rename `events_schema` → `schema`)
2. Override `field` macro with validation option extraction
3. Store validation metadata in module attributes
4. Generate helper functions: `__cast_fields__/0`, `__required_fields__/0`

### Phase 2: Basic Validations
1. String: min_length, max_length, format, in
2. Number: min, max, positive, in
3. Boolean: acceptance
4. Common: required, cast defaults

### Phase 3: Advanced Validations
1. Map structure validation
2. Array item validation
3. Date/time relative validation
4. Cross-field validation

### Phase 4: Conveniences
1. Auto-trim strings
2. Built-in format validators
3. Auto-generate validation functions
4. Error message customization

---

## Example Usage

```elixir
defmodule MyApp.Accounts.User do
  use Events.Schema

  schema "users" do
    # String with comprehensive validation
    field :email, :string,
      required: true,
      format: :email,
      max_length: 255,
      unique: true,
      trim: true,
      normalize: :downcase

    # Integer with range
    field :age, :integer,
      min: 18,
      max: 120,
      message: "must be between 18 and 120"

    # Enum field
    field :status, :string,
      required: true,
      in: ["active", "inactive", "suspended"],
      default: "active"

    # Map with structure
    field :preferences, :map,
      default: %{},
      required_keys: [:theme],
      optional_keys: [:language, :timezone],
      max_keys: 10

    # Array with validation
    field :tags, {:array, :string},
      max_length: 5,
      item_format: ~r/^[a-z0-9_]+$/,
      unique_items: true

    # Decimal with precision
    field :balance, :decimal,
      non_negative: true,
      precision: 10,
      scale: 2

    # Date in past
    field :birth_date, :date,
      required: true,
      past: true,
      after: ~D[1900-01-01]

    # Boolean with acceptance
    field :terms_accepted, :boolean,
      acceptance: true,
      required: true
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, __cast_fields__())
    |> validate_required(__required_fields__())
    |> __apply_field_validations__()
    |> custom_business_logic()
  end
end
```

---

## Sources

- [Ecto.Schema Documentation](https://hexdocs.pm/ecto/Ecto.Schema.html)
- [Ecto.Type Documentation](https://hexdocs.pm/ecto/Ecto.Type.html)
- [Rails Active Record Validations](https://edgeguides.rubyonrails.org/active_record_validations.html)
- [Django Validators](https://docs.djangoproject.com/en/5.1/ref/validators/)
- [Zod TypeScript Validation](https://zod.dev)
- [Valibot Modular Validation](https://valibot.dev)
