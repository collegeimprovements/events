# Schema Reference

Complete guide to the Events schema system with enhanced field macros, validations, presets, and helpers.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Field Types](#field-types)
3. [Validation Options](#validation-options)
4. [String Validations](#string-validations)
5. [Numeric Validations](#numeric-validations)
6. [Date/DateTime Validations](#datetime-validations)
7. [Normalization](#normalization)
8. [Presets](#presets)
9. [Field Helpers](#field-helpers)
10. [Complete Examples](#complete-examples)

---

## Quick Start

```elixir
defmodule MyApp.User do
  use Events.Schema

  schema "users" do
    # Simple field with validation
    field :email, :string, required: true, format: :email, normalize: :downcase

    # Using presets
    field :first_name, :string, preset: name()

    # Using field helpers
    email_field :email
    name_field :first_name
    birth_date_field :birth_date

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, __cast_fields__())
    |> Ecto.Changeset.validate_required(__required_fields__())
    |> __apply_field_validations__()
  end
end
```

---

## Field Types

### String Types
- `:string` - Variable-length string
- `:text` - Long text content
- `:citext` - Case-insensitive text (PostgreSQL)

### Numeric Types
- `:integer` - Whole numbers
- `:float` - Floating-point numbers
- `:decimal` - Precise decimal numbers

### Date/Time Types
- `:date` - Date only
- `:time` - Time only
- `:utc_datetime` - UTC datetime (seconds)
- `:utc_datetime_usec` - UTC datetime (microseconds)
- `:naive_datetime` - Datetime without timezone

### Other Types
- `:boolean` - True/false
- `:uuid` - UUID values
- `{:array, type}` - Arrays
- `:map` - JSON/map data
- `Ecto.Enum` - Enum values

---

## Validation Options

### Common Options

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `required` | boolean | Field is required | `required: true` |
| `null` | boolean | Allow nil after cast | `null: false` |
| `cast` | boolean | Include in casting | `cast: true` |
| `message` | string | Custom error message | `message: "is required"` |
| `preset` | keyword | Apply preset options | `preset: email()` |

### Conditional Validation

```elixir
# Validate only if condition is true
field :backup_email, :string,
  validate_if: fn changeset ->
    Ecto.Changeset.get_field(changeset, :email_verified) == false
  end

# Validate unless condition is true
field :phone, :string,
  validate_unless: fn changeset ->
    Ecto.Changeset.get_field(changeset, :email) != nil
  end
```

---

## String Validations

### Length Validation

```elixir
# Minimum length
field :username, :string, min_length: 3

# Maximum length
field :title, :string, max_length: 255

# Exact length
field :zip_code, :string, length: 5

# Range
field :password, :string, min_length: 8, max_length: 128
```

### Format Validation

```elixir
# Built-in formats
field :email, :string, format: :email
field :url, :string, format: :url
field :slug, :string, format: :slug
field :username, :string, format: :username
field :color, :string, format: :hex_color

# Custom regex
field :code, :string, format: ~r/^[A-Z0-9]{6}$/

# Custom with message
field :phone, :string,
  format: {~r/^\d{10}$/, message: "must be 10 digits"}
```

### Inclusion/Exclusion

```elixir
# Must be in list
field :size, :string, in: ["S", "M", "L", "XL"]

# Must not be in list
field :username, :string, not_in: ["admin", "root", "system"]
```

---

## Numeric Validations

### Comparison Operators

```elixir
# Greater than
field :price, :float, gt: 0

# Greater than or equal to
field :quantity, :integer, gte: 0

# Less than
field :discount, :float, lt: 1

# Less than or equal to
field :rating, :float, lte: 5

# Equal to
field :balance, :float, eq: 0

# Full names also work
field :age, :integer, greater_than: 0
field :score, :integer, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
```

### Range Validation

```elixir
# Simple range
field :percentage, :float, in: 0..100

# Range in list
field :stock, :integer, in: [0..1000]

# Old way (still works)
field :percentage, :float, min: 0, max: 100
```

### Custom Messages with Tuples

```elixir
field :age, :integer, gt: {0, message: "must be positive"}

field :score, :integer,
  gte: {0, message: "cannot be negative"},
  lte: {100, message: "cannot exceed 100"}
```

### Shortcut Options

```elixir
# Positive (> 0)
field :price, :float, positive: true

# Non-negative (>= 0)
field :quantity, :integer, non_negative: true

# Negative (< 0)
field :debt, :float, negative: true

# Non-positive (<= 0)
field :refund, :float, non_positive: true
```

---

## Date/DateTime Validations

### Past/Future

```elixir
# Must be in the past
field :birth_date, :date, past: true

# Must be in the future
field :event_date, :date, future: true
```

### Before/After

```elixir
# Before a specific date
field :start_date, :date, before: ~D[2025-12-31]

# After a specific date
field :end_date, :date, after: ~D[2025-01-01]

# Before another field
field :start_date, :date
field :end_date, :date, after: :start_date
```

---

## Normalization

Auto-trim is enabled by default for all string fields. Disable with `trim: false`.

### Built-in Normalizers

```elixir
# Single normalizer
field :email, :string, normalize: :downcase

# Multiple normalizers (applied in order)
field :name, :string, normalize: [:trim, :titlecase]

# Available normalizers:
# - :trim - Remove leading/trailing whitespace
# - :downcase - Convert to lowercase
# - :upcase - Convert to uppercase
# - :capitalize - Capitalize first letter
# - :titlecase - Capitalize each word
# - :squish - Collapse multiple spaces
# - :slugify - Convert to URL-safe slug
# - :alphanumeric_only - Remove non-alphanumeric
# - :digits_only - Remove non-digits
```

### Slugify Options

```elixir
# Basic slugify
field :slug, :string, normalize: :slugify

# With uniqueness suffix
field :slug, :string, normalize: {:slugify, uniquify: true}
# "My Title" + random → "my-title-a3x9m2"

# Custom separator
field :slug, :string, normalize: {:slugify, separator: "_"}
# "My Title" → "my_title"
```

### Mappers (Advanced)

```elixir
# Using atom shortcuts
field :code, :string, mappers: [:trim, :upcase, :alphanumeric_only]

# Using functions
field :custom, :string, mappers: [&String.trim/1, &String.upcase/1]

# With options
field :slug, :string, mappers: [{:slugify, uniquify: true}]

# Custom function
field :processed, :string,
  mappers: [fn val -> String.replace(val, " ", "-") end]
```

### Disable Auto-trim

```elixir
# Password fields should not be trimmed
field :password, :string, trim: false

# Preserve exact whitespace
field :code_snippet, :text, trim: false
```

---

## Presets

Presets are pre-configured option sets for common field patterns.

### String Presets

```elixir
import Events.Core.Schema.Presets.Strings

# Name fields (titlecase, 2-100 chars)
field :first_name, :string, preset: name()
field :last_name, :string, preset: name()

# Full name (space normalization, 2-200 chars)
field :full_name, :string, preset: full_name()

# Title (3-255 chars)
field :title, :string, preset: title()

# Text fields
field :bio, :string, preset: short_text()        # max 500
field :description, :string, preset: medium_text()  # max 2000
field :article, :string, preset: long_text()     # max 50,000

# Search term (1-255 chars)
field :query, :string, preset: search_term()

# Display name (3-50 chars)
field :username, :string, preset: display_name()

# Tag (lowercase, slug format, 2-50 chars)
field :tag, :string, preset: tag()

# Code (uppercase, alphanumeric, 4-20 chars)
field :promo_code, :string, preset: code()

# Address fields
field :street, :string, preset: address_line()
field :city, :string, preset: city()
field :postal_code, :string, preset: postal_code()

# Color hex (#RRGGBB)
field :color, :string, preset: color_hex()

# Notes (max 5000)
field :notes, :string, preset: notes()
```

### Date/DateTime Presets

```elixir
import Events.Core.Schema.Presets.Dates

# Past dates
field :birth_date, :date, preset: past_date()

# Future dates
field :event_date, :date, preset: future_date()

# Birth date with age validation (13-120 years)
field :birth_date, :date, preset: birth_date()

# Adult birth date (18+ years)
field :dob, :date, preset: adult_birth_date()

# Expiration date (must be future)
field :expires_at, :date, preset: expiration_date()

# Timestamps
field :created_at, :utc_datetime_usec, preset: timestamp()

# Past datetime
field :completed_at, :utc_datetime_usec, preset: past_datetime()

# Future datetime
field :scheduled_at, :utc_datetime_usec, preset: future_datetime()

# Scheduled (at least 1 hour in future)
field :publish_at, :utc_datetime_usec, preset: scheduled_datetime()

# Recent (within last N days, default 30)
field :last_active, :utc_datetime_usec, preset: recent_datetime()
field :last_login, :utc_datetime_usec, preset: recent_datetime(within_days: 7)

# Date ranges
field :start_date, :date, preset: date_range_start()
field :end_date, :date, preset: date_range_end()
```

### Customizing Presets

```elixir
# Override preset defaults
field :first_name, :string, preset: name(max_length: 50, required: false)

# Merge with custom options
field :bio, :string, preset: short_text(), max_length: 300
```

---

## Field Helpers

Field helpers are macro shortcuts that combine field type, preset, and common options.

### String Field Helpers

```elixir
import Events.Core.Schema.FieldHelpers

# Email (lowercase, email format, required)
email_field :email
email_field :backup_email, required: false

# Name (titlecase, 2-100 chars)
name_field :first_name
name_field :last_name

# Full name (space normalization)
full_name_field :display_name

# Title (3-255 chars)
title_field :post_title

# Text (short/medium/long)
text_field :bio                          # short_text preset
text_field :description, max_length: 1000

# Slug (lowercase, url-safe)
slug_field :slug
slug_field :slug, uniquify: true

# Username (3-30 chars, alphanumeric)
username_field :username

# Phone (digits only)
phone_field :phone
phone_field :mobile, required: false

# URL (url format)
url_field :website
url_field :blog_url, required: false

# Code (uppercase, alphanumeric)
code_field :verification_code
code_field :promo_code

# Address fields
address_field :street_address
city_field :city
postal_code_field :zip

# Color (hex format)
color_field :primary_color
color_field :theme_color, required: false
```

### Date/DateTime Field Helpers

```elixir
# Generic date
date_field :event_date
date_field :reminder_date, required: false

# Birth date (13+ years)
birth_date_field :birth_date

# Generic datetime
datetime_field :scheduled_at
datetime_field :published_at, required: false

# Timestamp (for created_at/updated_at)
timestamp_field :created_at
timestamp_field :updated_at
```

### Password Field Helper

```elixir
# Password (trim: false, min 8 chars)
password_field :password
password_field :password_confirmation
```

---

## Complete Examples

### User Schema

```elixir
defmodule MyApp.User do
  use Events.Schema
  import Events.Core.Schema.FieldHelpers

  schema "users" do
    # Using field helpers (most concise)
    email_field :email
    password_field :password
    name_field :first_name
    name_field :last_name
    birth_date_field :birth_date

    # Optional fields
    phone_field :phone, required: false
    url_field :website, required: false
    text_field :bio, required: false

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, __cast_fields__())
    |> Ecto.Changeset.validate_required(__required_fields__())
    |> __apply_field_validations__()
  end
end
```

### Product Schema

```elixir
defmodule MyApp.Product do
  use Events.Schema
  import Events.Core.Schema.FieldHelpers
  import Events.Core.Schema.Presets.Strings

  schema "products" do
    # Title and description
    title_field :name
    text_field :description, max_length: 2000
    slug_field :slug, uniquify: true

    # Pricing and inventory
    field :price, :float, gt: 0, required: true
    field :compare_at_price, :float, gt: 0, required: false
    field :stock_count, :integer, in: 0..10000, required: true

    # Product details
    field :sku, :string, preset: code()
    field :weight, :float, gte: 0, required: false
    field :tags, {:array, :string}, required: false

    # Status
    field :status, :citext, in: ["draft", "active", "archived"]
    field :published_at, :utc_datetime_usec, required: false

    timestamps()
  end
end
```

### Event Schema

```elixir
defmodule MyApp.Event do
  use Events.Schema
  import Events.Core.Schema.Presets.Dates
  import Events.Core.Schema.FieldHelpers

  schema "events" do
    # Basic info
    title_field :title
    text_field :description
    slug_field :slug, uniquify: true

    # Event timing (must be in future)
    field :event_date, :date, preset: future_date()
    field :starts_at, :utc_datetime_usec, preset: scheduled_datetime()
    field :ends_at, :utc_datetime_usec, preset: future_datetime()

    # Tickets
    field :ticket_price, :float, gte: 0
    field :max_attendees, :integer, gte: 1
    field :registration_ends, :date, preset: expiration_date()

    # Location
    address_field :venue_address
    city_field :city
    postal_code_field :postal_code

    # Status
    field :status, :citext, in: ["draft", "published", "cancelled"]

    timestamps()
  end
end
```

### Account Schema with Validations

```elixir
defmodule MyApp.Account do
  use Events.Schema

  schema "accounts" do
    # Account details
    field :account_number, :string,
      required: true,
      format: ~r/^[A-Z]{2}\d{8}$/,
      message: "must be 2 letters followed by 8 digits"

    # Balance and limits
    field :balance, :decimal,
      required: true,
      gte: {0, message: "cannot be negative"},
      default: Decimal.new(0)

    field :credit_limit, :decimal,
      gt: {0, message: "must be positive"},
      required: true

    field :withdrawal_limit, :decimal,
      in: Decimal.new(0)..Decimal.new(10000),
      required: true

    # Account status
    field :status, :citext,
      in: ["active", "suspended", "closed"],
      required: true,
      default: "active"

    field :verified_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> Ecto.Changeset.cast(attrs, __cast_fields__())
    |> Ecto.Changeset.validate_required(__required_fields__())
    |> __apply_field_validations__()
    |> validate_credit_limit()
  end

  defp validate_credit_limit(changeset) do
    balance = Ecto.Changeset.get_field(changeset, :balance)
    credit_limit = Ecto.Changeset.get_field(changeset, :credit_limit)

    if balance && credit_limit && Decimal.gt?(balance, credit_limit) do
      Ecto.Changeset.add_error(changeset, :balance,
        "cannot exceed credit limit")
    else
      changeset
    end
  end
end
```

---

## Validation Pipeline

The validation pipeline executes in this order:

1. **Normalize** - Apply normalization transformations
2. **Cast** - Convert input types
3. **Required** - Check required fields
4. **Type** - Validate field types
5. **Format** - Check format/regex
6. **Length** - Validate string length
7. **Number** - Validate numeric ranges
8. **Inclusion** - Check in/not_in lists
9. **Date/Time** - Validate temporal constraints
10. **Custom** - User-defined validations

---

## Helper Functions

### Generated Functions

When using `use Events.Core.Schema`, these functions are automatically generated:

```elixir
# List of all castable fields
__cast_fields__()

# List of required fields
__required_fields__()

# Field validation metadata
__field_validations__()

# Apply all field validations
__apply_field_validations__(changeset)
```

### Usage in Changesets

```elixir
def changeset(struct, attrs) do
  struct
  |> Ecto.Changeset.cast(attrs, __cast_fields__())
  |> Ecto.Changeset.validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> custom_validations()
end

defp custom_validations(changeset) do
  changeset
  |> validate_email_uniqueness()
  |> validate_password_confirmation()
end
```

---

## Tips and Best Practices

### 1. Use Field Helpers for Common Patterns

```elixir
# Instead of:
field :email, :string, required: true, format: :email, normalize: :downcase

# Use:
email_field :email
```

### 2. Leverage Presets for Consistency

```elixir
# Define common patterns once
import Events.Core.Schema.Presets.Strings

field :first_name, :string, preset: name()
field :last_name, :string, preset: name()
```

### 3. Combine Shortcuts with Custom Options

```elixir
# Presets can be customized
email_field :backup_email, required: false

# Field helpers can be extended
name_field :nickname, max_length: 30
```

### 4. Use Range Syntax for Numeric Bounds

```elixir
# More intuitive than min/max
field :percentage, :float, in: 0..100
field :age, :integer, in: 18..120
```

### 5. Add Custom Messages for Better UX

```elixir
field :age, :integer,
  gte: {18, message: "must be 18 or older to register"}
```

### 6. Disable Auto-trim for Sensitive Fields

```elixir
# Preserve exact input for passwords
password_field :password  # Already has trim: false

# Or manually
field :api_key, :string, trim: false
```

---

## Summary

**String Enhancements:**
- ✅ Auto-trim by default (disable with `trim: false`)
- ✅ 15+ string presets (name, email, title, etc.)
- ✅ 13+ field helpers for common patterns
- ✅ Advanced normalization with mappers
- ✅ Slugify with uniqueness support

**Numeric Enhancements:**
- ✅ Shortcut syntax (`:gt`, `:gte`, `:lt`, `:lte`, `:eq`)
- ✅ Range syntax (`in: 0..100`)
- ✅ Custom messages with tuples
- ✅ Preset shortcuts (`:positive`, `:non_negative`)

**Date/DateTime Enhancements:**
- ✅ 12+ date/time presets
- ✅ Age validations (birth_date, adult_birth_date)
- ✅ Future/past validations
- ✅ Scheduled datetime (minimum 1 hour in future)

**All 171 tests passing** ✅
