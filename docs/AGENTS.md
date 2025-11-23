# Events System Guide

## Overview

The Events system provides enhanced Ecto functionality with two powerful subsystems:

1. **Events.Schema** - Enhanced schema system with field-level validations
2. **Events.Repo.Migration** - Modular migration DSL with PostgreSQL 18 UUIDv7 support

This guide provides comprehensive examples and patterns for both systems.

## Table of Contents

### Schema System
- [Basic Schema Structure](#basic-schema-structure)
- [Field Types](#field-types)
- [Validation Options](#validation-options)
- [Normalization Options](#normalization-options)
- [Validation Presets](#validation-presets)
- [Schema Examples](#schema-examples)

### Migration System
- [Migration Architecture](#migration-architecture)
- [Table Creation](#table-creation)
- [Field Sets](#field-sets)
- [Index Creation](#index-creation)
- [Migration Examples](#migration-examples)
- [Migration Best Practices](#migration-best-practices)

## Basic Schema Structure

All schemas in this project use `Events.Schema` instead of `Ecto.Schema`:

```elixir
defmodule MyApp.User do
  use Events.Schema  # NOT use Ecto.Schema
  import Events.Schema.Presets  # Optional: for using presets

  schema "users" do
    field :email, :string, required: true, format: :email, normalize: [:trim, :downcase]
    field :age, :integer, min: 18, max: 120
    timestamps()  # Adds created_at and updated_at
  end
end
```

## Field Types

### Supported Field Types
- `:string` - Text fields
- `:citext` - Case-insensitive text
- `:integer` - Whole numbers
- `:float` - Decimal numbers
- `:decimal` - Precise decimal numbers
- `:boolean` - True/false values
- `:date` - Date only
- `:time` - Time only
- `:naive_datetime` - DateTime without timezone
- `:utc_datetime` - DateTime with UTC timezone
- `{:array, type}` - Arrays of any type
- `:map` - JSON/Map fields
- `{:map, type}` - Typed map fields
- `:binary_id` - UUID fields

## Validation Options

### String Validations

```elixir
field :username, :string,
  required: true,                    # Field must be present
  min_length: 3,                     # Minimum string length
  max_length: 30,                    # Maximum string length
  length: 10,                        # Exact length
  format: ~r/^[a-zA-Z0-9_]+$/,      # Regex format
  format: :email,                    # Named format (email, url, uuid, slug, hex_color, ip)
  in: ["admin", "user", "guest"],   # Must be one of these values
  not_in: ["root", "superuser"],    # Cannot be these values
  normalize: [:trim, :downcase],    # Normalization pipeline
  unique: true,                      # Database unique constraint
  message: "custom error message"    # Custom validation message

# Format with custom message
field :email, :string,
  format: {:email, message: "Please enter a valid email address"}

# Length with custom message
field :bio, :string,
  max_length: {500, message: "Bio cannot exceed 500 characters"}
```

### Number Validations

```elixir
field :age, :integer,
  required: true,
  min: 18,                           # Minimum value (inclusive)
  max: 120,                          # Maximum value (inclusive)
  greater_than: 0,                   # Must be greater than
  greater_than_or_equal_to: 0,       # Must be >=
  less_than: 100,                    # Must be less than
  less_than_or_equal_to: 100,        # Must be <=
  equal_to: 50,                      # Must equal exactly
  not_equal_to: 0,                   # Cannot equal
  positive: true,                    # Must be > 0
  non_negative: true,                # Must be >= 0
  negative: true,                    # Must be < 0
  non_positive: true,                # Must be <= 0
  in: [10, 20, 30, 40, 50]          # Must be one of these values

# With custom messages
field :price, :decimal,
  min: {0, message: "Price cannot be negative"},
  max: {999999.99, message: "Price too high"}
```

### Boolean Validations

```elixir
field :terms_accepted, :boolean,
  acceptance: true,                  # Must be true
  required: true
```

### Date/Time Validations

```elixir
field :birth_date, :date,
  past: true,                        # Must be in the past
  future: false,                     # Cannot be in future
  before: ~D[2000-01-01],           # Must be before date
  after: ~D[1900-01-01]            # Must be after date

field :appointment, :utc_datetime,
  future: true,                      # Must be in future
  after: {:now, hours: 24},         # At least 24 hours from now
  before: {:now, days: 90}          # Within 90 days

field :event_date, :date,
  after: {:field, :start_date},     # After another field
  before: {:field, :end_date}       # Before another field
```

### Array Validations

```elixir
field :tags, {:array, :string},
  min_length: 1,                     # Minimum array length
  max_length: 10,                    # Maximum array length
  unique_items: true,                # No duplicate items
  in: ["red", "blue", "green"],     # Array items must be subset of these
  item_format: ~r/^[a-z0-9-]+$/,    # Format for each item
  item_min: 3,                       # Min value for each item
  item_max: 50                       # Max value for each item

# Tags with all validations
field :tags, {:array, :string},
  required: true,
  min_length: 1,
  max_length: 5,
  unique_items: true,
  item_format: ~r/^[a-z][a-z0-9-]{2,19}$/,
  message: "Each tag must be lowercase with hyphens only"
```

### Map Validations

```elixir
field :metadata, :map,
  required_keys: ["version", "type"],   # Keys that must exist
  forbidden_keys: ["password"],         # Keys that cannot exist
  min_keys: 1,                          # Minimum number of keys
  max_keys: 50                           # Maximum number of keys

field :settings, :map,
  default: %{},
  required_keys: ["theme", "language"],
  max_keys: 20
```

### Cross-Field Validations

```elixir
# Password confirmation
field :password, :string, required: true, min_length: 8
field :password_confirmation, :string, required: true

# In changeset function:
validate: [
  confirm: {:password, :password_confirmation, message: "Passwords don't match"},
  compare: {:start_date, :<=, :end_date, message: "Start must be before end"},
  dependent: {:email_notifications, requires: :email},
  exclusive: {[:phone, :email], message: "Provide either phone or email, not both"}
]
```

### Conditional Validations

```elixir
# Validate only if condition is met
field :tax_id, :string,
  validate_if: {MyModule, :is_business_account, []},
  format: ~r/^\d{9}$/

field :company_name, :string,
  validate_if: fn changeset ->
    get_field(changeset, :account_type) == "business"
  end,
  required: true

# Skip validation if condition is met
field :optional_code, :string,
  validate_unless: fn changeset ->
    get_field(changeset, :skip_validation) == true
  end,
  format: ~r/^[A-Z0-9]{6}$/
```

### Database Constraints

```elixir
field :email, :string,
  unique: true,                      # Unique constraint
  foreign_key: {:users, :id},        # Foreign key reference
  check: "age >= 18"                 # Check constraint

# Composite unique constraint
field :slug, :string,
  unique: [:account_id, :slug]      # Unique within account
```

## Normalization Options

Normalization is applied before validation:

```elixir
field :email, :string,
  normalize: :downcase               # Single normalization

field :username, :string,
  normalize: [:trim, :downcase]      # Multiple (applied in order)

field :title, :string,
  normalize: :titlecase              # Capitalize each word

field :slug, :string,
  normalize: {:slugify, uniquify: true}  # Slugify with uniqueness

# Available normalizations:
# :trim        - Remove leading/trailing whitespace
# :squish      - Collapse multiple spaces into one
# :downcase    - Convert to lowercase
# :upcase      - Convert to uppercase
# :capitalize  - Capitalize first letter
# :titlecase   - Capitalize each word
# :slugify     - Convert to URL-safe slug
# {:slugify, uniquify: true} - Add random suffix for uniqueness
# Custom function

# Custom normalization function
field :phone, :string,
  normalize: fn value ->
    value
    |> String.replace(~r/[^0-9]/, "")
    |> String.slice(0, 10)
  end
```

## Validation Presets

The system includes 44 built-in presets for common field types:

```elixir
defmodule MyApp.User do
  use Events.Schema
  import Events.Schema.Presets

  schema "users" do
    # Basic presets
    field :email, :string, email()
    field :username, :string, username(min_length: 3)
    field :password, :string, password(min_length: 12)
    field :website, :string, url(required: false)
    field :phone, :string, phone()
    field :age, :integer, age()
    field :bio, :string, max_length: 500

    # Location presets
    field :country, :string, country_code()
    field :zip_code, :string, zip_code()
    field :latitude, :float, latitude()
    field :longitude, :float, longitude()
    field :timezone, :string, timezone()

    # Financial presets
    field :price, :decimal, money()
    field :credit_card, :string, credit_card()
    field :iban, :string, iban()
    field :bitcoin_address, :string, bitcoin_address()
    field :ethereum_address, :string, ethereum_address()
    field :currency, :string, currency_code()

    # Network presets
    field :ip_address, :string, ipv4()
    field :ipv6_address, :string, ipv6()
    field :mac_address, :string, mac_address()
    field :domain, :string, domain()

    # Development presets
    field :api_key, :string, uuid()
    field :version, :string, semver()
    field :token, :string, jwt()
    field :base64_data, :string, base64()
    field :mime_type, :string, mime_type()

    # Social presets
    field :twitter_handle, :string, social_handle()
    field :hashtag, :string, hashtag()

    # Other presets
    field :color, :string, hex_color()
    field :slug, :string, slug()
    field :rating, :integer, rating()  # 1-5 stars
    field :percentage, :integer, percentage()  # 0-100
    field :priority, :integer, positive_integer(max: 10)
    field :tags, {:array, :string}, tags()
    field :metadata, :map, metadata()
    field :status, :string, enum(in: ["active", "pending", "inactive"])

    timestamps()
  end
end
```

### Available Presets Reference

| Preset | Description | Options Applied |
|--------|-------------|-----------------|
| `email()` | Email validation | `format: :email, normalize: [:trim, :downcase], max_length: 255` |
| `username()` | Username field | `min_length: 4, max_length: 30, format: ~r/^[a-zA-Z0-9_-]+$/` |
| `password()` | Password field | `min_length: 8, max_length: 128, trim: false` |
| `url()` | URL validation | `format: :url, max_length: 2048` |
| `phone()` | Phone number | `format: ~r/^[+]?[0-9\s\-().]+$/`, min_length: 10` |
| `uuid()` | UUID field | `format: :uuid, normalize: [:trim, :downcase]` |
| `slug()` | URL slug | `format: :slug, normalize: {:slugify, uniquify: true}` |
| `age()` | Age field | `min: 0, max: 150, non_negative: true` |
| `rating()` | 1-5 rating | `min: 1, max: 5` |
| `percentage()` | 0-100 range | `min: 0, max: 100` |
| `money()` | Currency amount | `non_negative: true, max: 999_999_999.99` |
| `positive_integer()` | Count/quantity | `positive: true, default: 0` |
| `country_code()` | ISO country | `format: ~r/^[A-Z]{2}$/`, length: 2` |
| `language_code()` | ISO language | `format: ~r/^[a-z]{2}(-[A-Z]{2})?$/` |
| `currency_code()` | ISO currency | `format: ~r/^[A-Z]{3}$/`, length: 3` |
| `zip_code()` | US postal code | `format: ~r/^[0-9]{5}(-[0-9]{4})?$/` |
| `ipv4()` | IPv4 address | Complex regex with octet validation |
| `ipv6()` | IPv6 address | Complex regex for IPv6 format |
| `mac_address()` | MAC address | `format: ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/` |
| `credit_card()` | Card number | `min_length: 13, max_length: 19` |
| `iban()` | Bank account | `min_length: 15, max_length: 34` |
| `social_handle()` | @username | Removes @, validates format |
| `tags()` | Tag array | `unique_items: true, item_format: ~r/^[a-z0-9-]+$/` |
| `metadata()` | JSON field | `default: %{}, max_keys: 100` |

## Complete Examples

### User Registration Schema

```elixir
defmodule MyApp.Accounts.User do
  use Events.Schema
  import Events.Schema.Presets

  schema "users" do
    # Basic Information
    field :email, :string, email()
    field :username, :string, username(min_length: 3, max_length: 20)
    field :password, :string, password(min_length: 8)
    field :password_confirmation, :string, virtual: true

    # Profile
    field :full_name, :string, required: true, min_length: 2, max_length: 100
    field :bio, :string, max_length: 500
    field :avatar_url, :string, url(required: false)
    field :birth_date, :date, past: true, after: ~D[1900-01-01]
    field :phone, :string, phone(required: false)

    # Settings
    field :timezone, :string, timezone()
    field :language, :string, language_code()
    field :theme, :string, enum(in: ["light", "dark", "auto"])
    field :email_notifications, :boolean, default: true
    field :sms_notifications, :boolean, default: false

    # Metadata
    field :tags, {:array, :string}, tags(max_length: 5)
    field :metadata, :map, metadata()
    field :last_login_at, :utc_datetime
    field :email_verified_at, :utc_datetime
    field :locked_at, :utc_datetime

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, __cast_fields__())
    |> validate_required([:email, :username, :password, :full_name])
    |> __apply_field_validations__()
    |> validate_confirmation(:password)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> hash_password()
  end
end
```

### E-commerce Product Schema

```elixir
defmodule MyApp.Catalog.Product do
  use Events.Schema
  import Events.Schema.Presets

  schema "products" do
    # Basic Info
    field :sku, :string, required: true, format: ~r/^[A-Z0-9-]+$/, unique: true
    field :name, :string, required: true, min_length: 3, max_length: 200
    field :slug, :string, slug()
    field :description, :string, max_length: 5000

    # Pricing
    field :price, :decimal, money()
    field :compare_at_price, :decimal, money()
    field :cost, :decimal, money()
    field :tax_rate, :integer, percentage()
    field :currency, :string, currency_code()

    # Inventory
    field :quantity, :integer, non_negative: true, default: 0
    field :track_inventory, :boolean, default: true
    field :allow_backorder, :boolean, default: false
    field :low_stock_threshold, :integer, positive_integer(max: 100)

    # Attributes
    field :weight, :float, non_negative: true
    field :length, :float, positive: true
    field :width, :float, positive: true
    field :height, :float, positive: true
    field :color, :string, hex_color()
    field :size, :string, in: ["XS", "S", "M", "L", "XL", "XXL"]

    # Organization
    field :category_id, :binary_id
    field :brand_id, :binary_id
    field :tags, {:array, :string}, tags()
    field :status, :string, enum(in: ["draft", "active", "archived"])

    # Media
    field :images, {:array, :string}, max_length: 10, item_format: :url
    field :video_url, :string, url(required: false)

    # SEO
    field :meta_title, :string, max_length: 60
    field :meta_description, :string, max_length: 160
    field :meta_keywords, {:array, :string}, max_length: 10

    # Reviews
    field :rating, :float, min: 0.0, max: 5.0
    field :review_count, :integer, non_negative: true, default: 0

    # Dates
    field :published_at, :utc_datetime
    field :sale_starts_at, :utc_datetime
    field :sale_ends_at, :utc_datetime

    timestamps()
  end
end
```

### Blog Post Schema

```elixir
defmodule MyApp.Blog.Post do
  use Events.Schema
  import Events.Schema.Presets

  schema "posts" do
    # Content
    field :title, :string,
      required: true,
      min_length: 10,
      max_length: 200,
      normalize: :titlecase

    field :slug, :string, slug()
    field :excerpt, :string, max_length: 300
    field :content, :string, required: true, min_length: 100
    field :content_format, :string, enum(in: ["markdown", "html", "plain"])

    # Author
    field :author_id, :binary_id, required: true
    field :editor_id, :binary_id

    # Categorization
    field :category, :string, required: true, in: [
      "technology", "business", "lifestyle", "travel", "food"
    ]
    field :tags, {:array, :string}, tags(max_length: 10)
    field :featured, :boolean, default: false

    # Publishing
    field :status, :string, enum(in: ["draft", "review", "published", "archived"])
    field :published_at, :utc_datetime, future: false
    field :scheduled_for, :utc_datetime, future: true

    # Engagement
    field :view_count, :integer, non_negative: true, default: 0
    field :like_count, :integer, non_negative: true, default: 0
    field :comment_count, :integer, non_negative: true, default: 0
    field :reading_time, :integer, positive: true  # in minutes

    # SEO
    field :meta_description, :string, max_length: 160
    field :canonical_url, :string, url(required: false)
    field :keywords, {:array, :string}, max_length: 10

    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, __cast_fields__())
    |> validate_required([:title, :content, :author_id, :category])
    |> __apply_field_validations__()
    |> maybe_generate_slug()
    |> calculate_reading_time()
  end
end
```

### Payment Transaction Schema

```elixir
defmodule MyApp.Payments.Transaction do
  use Events.Schema
  import Events.Schema.Presets

  schema "transactions" do
    # Transaction Info
    field :transaction_id, :string, uuid()
    field :type, :string, enum(in: ["payment", "refund", "adjustment"])
    field :status, :string, enum(in: ["pending", "processing", "completed", "failed"])

    # Amount
    field :amount, :decimal, money()
    field :currency, :string, currency_code()
    field :fee, :decimal, money()
    field :tax, :decimal, money()
    field :net_amount, :decimal, money()

    # Payment Method
    field :payment_method, :string, in: ["card", "bank", "paypal", "crypto"]
    field :card_last_four, :string,
      length: 4,
      format: ~r/^\d{4}$/,
      validate_if: fn changeset ->
        get_field(changeset, :payment_method) == "card"
      end

    field :card_brand, :string,
      in: ["visa", "mastercard", "amex", "discover"],
      validate_if: fn changeset ->
        get_field(changeset, :payment_method) == "card"
      end

    # Bank Details (conditional)
    field :iban, :string,
      iban(),
      validate_if: fn changeset ->
        get_field(changeset, :payment_method) == "bank"
      end

    # Crypto (conditional)
    field :bitcoin_address, :string,
      bitcoin_address(),
      validate_if: fn changeset ->
        get_field(changeset, :payment_method) == "crypto"
      end

    field :ethereum_address, :string,
      ethereum_address(),
      validate_if: fn changeset ->
        get_field(changeset, :payment_method) == "crypto"
      end

    # References
    field :order_id, :binary_id, required: true
    field :customer_id, :binary_id, required: true
    field :merchant_id, :binary_id

    # Risk Assessment
    field :risk_score, :integer, min: 0, max: 100
    field :ip_address, :string, ipv4()
    field :user_agent, :string, max_length: 500

    # Metadata
    field :metadata, :map, metadata()
    field :processed_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :refunded_at, :utc_datetime

    timestamps()
  end
end
```

### API Configuration Schema

```elixir
defmodule MyApp.API.Configuration do
  use Events.Schema
  import Events.Schema.Presets

  schema "api_configurations" do
    # Identity
    field :name, :string, required: true, min_length: 3, max_length: 50
    field :client_id, :string, uuid()
    field :client_secret, :string, password(min_length: 32)

    # Authentication
    field :api_key, :string, uuid()
    field :access_token, :string, jwt()
    field :refresh_token, :string, jwt()
    field :token_expires_at, :utc_datetime, future: true

    # Endpoints
    field :base_url, :string, url()
    field :webhook_url, :string, url(required: false)
    field :callback_url, :string, url(required: false)

    # Rate Limiting
    field :rate_limit, :integer, positive_integer(max: 10000)
    field :rate_limit_window, :integer, positive_integer(max: 3600)
    field :burst_limit, :integer, positive_integer(max: 100)

    # Security
    field :allowed_ips, {:array, :string},
      item_format: ~r/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/,
      max_length: 100

    field :allowed_origins, {:array, :string},
      item_format: :url,
      max_length: 50

    field :headers, :map,
      max_keys: 20,
      forbidden_keys: ["Authorization", "X-API-Key"]

    # Configuration
    field :timeout, :integer, positive_integer(max: 60000)  # milliseconds
    field :retry_attempts, :integer, min: 0, max: 5
    field :retry_delay, :integer, positive_integer(max: 30000)
    field :version, :string, semver()

    # Features
    field :features, {:array, :string},
      in: ["webhooks", "batch", "async", "compression", "encryption"]

    field :compression, :string,
      enum(in: ["none", "gzip", "deflate"]),
      default: "none"

    field :environment, :string,
      enum(in: ["development", "staging", "production"])

    # Status
    field :active, :boolean, default: true
    field :verified, :boolean, default: false
    field :last_used_at, :utc_datetime
    field :expires_at, :date, future: true

    timestamps()
  end
end
```

## Advanced Patterns

### Custom Validation Functions

```elixir
defmodule MyApp.CustomValidations do
  def validate_business_email(email) do
    if String.ends_with?(email, "@company.com") do
      :ok
    else
      {:error, "Must be a company email address"}
    end
  end

  def validate_working_hours(datetime) do
    hour = DateTime.to_time(datetime).hour
    if hour >= 9 and hour <= 17 do
      :ok
    else
      {:error, "Must be during working hours (9 AM - 5 PM)"}
    end
  end
end

# Usage in schema
field :corporate_email, :string,
  validate: {MyApp.CustomValidations, :validate_business_email}

field :appointment_time, :utc_datetime,
  validate: {MyApp.CustomValidations, :validate_working_hours}
```

### Dynamic Validation Messages

```elixir
field :age, :integer,
  min: {18, message: fn value -> "You must be 18 or older (you entered #{value})" end},
  max: {120, message: "Please enter a valid age"}

field :username, :string,
  format: {~r/^[a-z0-9_]+$/, message: "Only lowercase letters, numbers and underscores allowed"}
```

### Complex Cross-Field Validation

```elixir
defmodule MyApp.Event do
  use Events.Schema

  schema "events" do
    field :start_date, :date, required: true
    field :end_date, :date, required: true
    field :early_bird_date, :date
    field :regular_price, :decimal, money()
    field :early_bird_price, :decimal, money()
    field :capacity, :integer, positive: true
    field :min_attendees, :integer, positive: true
    field :max_attendees, :integer, positive: true

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, __cast_fields__())
    |> validate_required([:start_date, :end_date, :regular_price, :capacity])
    |> __apply_field_validations__()
    |> validate_date_order()
    |> validate_price_order()
    |> validate_capacity_order()
  end

  defp validate_date_order(changeset) do
    changeset
    |> validate_compare(:start_date, :<=, :end_date, message: "Start date must be before end date")
    |> validate_compare(:early_bird_date, :<=, :start_date, message: "Early bird must be before event start")
  end

  defp validate_price_order(changeset) do
    if get_field(changeset, :early_bird_price) && get_field(changeset, :regular_price) do
      validate_compare(changeset, :early_bird_price, :<, :regular_price,
        message: "Early bird price must be less than regular price")
    else
      changeset
    end
  end

  defp validate_capacity_order(changeset) do
    changeset
    |> validate_compare(:min_attendees, :<=, :capacity, message: "Minimum cannot exceed capacity")
    |> validate_compare(:max_attendees, :<=, :capacity, message: "Maximum cannot exceed capacity")
    |> validate_compare(:min_attendees, :<=, :max_attendees, message: "Min must be less than max")
  end
end
```

### Schema Composition with Embedded Schemas

```elixir
defmodule MyApp.Address do
  use Events.Schema
  import Events.Schema.Presets

  embedded_schema do
    field :street, :string, required: true, min_length: 5
    field :city, :string, required: true, min_length: 2
    field :state, :string, length: 2, format: ~r/^[A-Z]{2}$/
    field :zip, :string, zip_code()
    field :country, :string, country_code()
    field :latitude, :float, latitude()
    field :longitude, :float, longitude()
  end
end

defmodule MyApp.Company do
  use Events.Schema
  import Events.Schema.Presets

  schema "companies" do
    field :name, :string, required: true, min_length: 2, max_length: 100
    field :tax_id, :string, format: ~r/^\d{9}$/
    field :website, :string, url()
    field :email, :string, email()
    field :phone, :string, phone()

    # Embedded address
    embeds_one :headquarters, MyApp.Address
    embeds_many :locations, MyApp.Address

    # Other fields
    field :employee_count, :integer, positive_integer()
    field :revenue, :decimal, money()
    field :founded_year, :integer, min: 1800, max: Date.utc_today().year
    field :industry, :string, in: ["tech", "finance", "retail", "healthcare"]
    field :tags, {:array, :string}, tags()

    timestamps()
  end
end
```

---

# Migration System

## Migration Architecture

The migration system is organized into focused modules using pattern matching and pipelines:

```
lib/events/repo/
├── migration.ex              # Main module with use macro
├── migration/
│   ├── table_builder.ex      # Table creation with UUIDv7
│   ├── field_sets.ex         # Common field combinations
│   ├── field_macros.ex       # Specialized field types
│   ├── indexes.ex            # Index creation helpers
│   └── helpers.ex            # Utility functions
```

## Table Creation

### Basic Table with UUIDv7

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Repo.Migration

  def change do
    # Enable extensions
    enable_citext()

    # Table with automatic UUIDv7 primary key
    create_table :users do
      # Fields go here
    end
  end
end
```

## Field Sets

### Name Fields

```elixir
create_table :users do
  # Adds first_name, last_name, display_name, full_name
  name_fields(type: :citext, required: true)
end
```

### Title Fields with Translations

```elixir
create_table :articles do
  # Adds title, subtitle, short_title with translations
  title_fields(
    with_translations: true,
    languages: [:es, :fr, :de]
  )
end
```

### Status Field

```elixir
create_table :orders do
  # Status with custom values
  status_field(
    values: ["pending", "processing", "shipped", "delivered"],
    default: "pending"
  )
end
```

### Audit Fields

```elixir
create_table :products do
  # Track who created/updated records
  audit_fields(with_user: true, with_role: true)
end
```

### Soft Delete Fields

```elixir
create_table :users do
  # Soft delete with tracking
  deleted_fields(with_user: true, with_reason: true)
end
```

## Specialized Field Macros

### Contact Fields

```elixir
create_table :contacts do
  email_field(type: :citext, unique: true)
  phone_field(name: :mobile)
  url_field(name: :website)
end
```

### Address Fields

```elixir
create_table :companies do
  # Billing address fields
  address_fields(prefix: :billing)
  # Shipping address fields
  address_fields(prefix: :shipping)
end
```

### Financial Fields

```elixir
create_table :invoices do
  money_field(:subtotal)
  money_field(:tax)
  money_field(:total, required: true)
  percentage_field(:discount)
end
```

### Location Fields

```elixir
create_table :stores do
  geo_fields(with_altitude: true, with_accuracy: true)
end
```

## Index Creation

### Smart Index Creation

```elixir
def change do
  create_table :products do
    # ... fields ...
  end

  # Name field indexes with fulltext
  name_indexes(:products, fulltext: true)

  # Status indexes with partial condition
  status_indexes(:products, partial: "deleted_at IS NULL")

  # Timestamp indexes with order
  timestamp_indexes(:products, order: :desc)

  # Soft delete indexes
  deleted_indexes(:products, active_index: true)

  # JSONB metadata index
  metadata_index(:products, field: :attributes)
end
```

## Migration Examples

### Complete User Table

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Repo.Migration

  def change do
    enable_citext()

    create_table :users do
      # Identity
      name_fields(type: :citext, required: true)
      email_field(type: :citext, unique: true)
      phone_field()

      # Authentication
      add :password_hash, :string, null: false
      add :confirmed_at, :utc_datetime
      add :locked_at, :utc_datetime

      # Profile
      url_field(name: :website)
      add :bio, :text
      file_fields(:avatar, with_metadata: true)

      # Settings
      settings_field(name: :preferences)
      tags_field(name: :interests)

      # Status
      status_field()
      deleted_fields(with_reason: true)

      # Timestamps
      timestamps()
    end

    # Create indexes
    name_indexes(:users, fulltext: true)
    status_indexes(:users, partial: "deleted_at IS NULL")
    deleted_indexes(:users, active_index: true)
  end
end
```

### E-commerce Product Table

```elixir
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Events.Repo.Migration

  def change do
    create_table :products do
      # Identity
      add :sku, :string, null: false
      title_fields(with_translations: true, languages: [:es, :fr])
      slug_field()

      # Categorization
      type_fields(primary: :category, secondary: :subcategory)
      tags_field()

      # Pricing
      money_field(:cost)
      money_field(:price, required: true)
      percentage_field(:discount)

      # Inventory
      counter_field(:stock_quantity)
      counter_field(:reserved_quantity)

      # Media
      file_fields(:main_image, with_metadata: true)
      add :gallery_urls, {:array, :string}, default: []

      # Metadata
      metadata_field(name: :specifications)

      # Publishing
      status_field(values: ["draft", "published", "discontinued"])
      add :published_at, :utc_datetime

      # Audit
      audit_fields(with_user: true)
      timestamps()
    end

    # Indexes
    create unique_index(:products, [:sku])
    slug_field(:products)
    type_indexes(:products)
    status_indexes(:products, partial: "status = 'published'")
    metadata_index(:products, field: :specifications)
  end
end
```

### Multi-tenant Organization Table

```elixir
defmodule MyApp.Repo.Migrations.CreateOrganizations do
  use Events.Repo.Migration

  def change do
    enable_citext()

    create_table :organizations do
      # Identity
      add :name, :citext, null: false
      slug_field()

      # Contact
      email_field(name: :primary_email, unique: true)
      phone_field(name: :primary_phone)
      url_field(name: :website)

      # Addresses
      address_fields(prefix: :billing)
      address_fields(prefix: :shipping)

      # Subscription
      add :plan, :string, null: false, default: "free"
      add :trial_ends_at, :utc_datetime
      counter_field(:api_calls_count)

      # Settings
      settings_field(name: :feature_flags)
      metadata_field(name: :internal_notes)

      # Status
      status_field(values: ["pending", "active", "suspended", "cancelled"])

      # Audit
      audit_fields(with_user: true)
      deleted_fields(with_user: true, with_reason: true)
      timestamps()
    end

    # Indexes
    create unique_index(:organizations, [:slug])
    name_indexes(:organizations, fulltext: true)
    status_indexes(:organizations, partial: "status = 'active'")
    metadata_index(:organizations, field: :internal_notes)
  end
end
```

### Event Management Table

```elixir
defmodule MyApp.Repo.Migrations.CreateEvents do
  use Events.Repo.Migration

  def change do
    create_table :events do
      # Event info
      title_fields(required: true)
      slug_field()
      add :description, :text

      # Scheduling
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false
      add :timezone, :string, null: false

      # Location
      add :venue_name, :string
      address_fields(prefix: :venue)
      geo_fields(prefix: :venue, with_accuracy: true)

      # Capacity
      counter_field(:max_attendees)
      counter_field(:registered_count)

      # Organizer
      add :organizer_id, references(:users, type: :binary_id)

      # Categorization
      type_fields(primary: :event_type)
      tags_field(name: :topics)

      # Pricing
      money_field(:price)
      money_field(:early_bird_price)

      # Status
      status_field(values: ["draft", "published", "sold_out", "completed"])

      # Audit
      audit_fields(with_user: true)
      timestamps()
    end

    # Time-based indexes
    create index(:events, [:start_time])
    create index(:events, [:end_time])

    # Location indexes
    create index(:events, [:venue_latitude, :venue_longitude])

    # Status and search
    status_indexes(:events, partial: "status = 'published'")
    title_indexes(:events, fulltext: true)
  end
end
```

## Migration Best Practices

### 1. Use Field Sets for Consistency

```elixir
# Good - consistent across tables
name_fields(type: :citext)
audit_fields(with_user: true)

# Avoid - manual and error-prone
add :first_name, :citext
add :last_name, :citext
add :created_by_user_id, references(:users)
```

### 2. Create Appropriate Indexes

```elixir
# Partial indexes for active records
status_indexes(:users, partial: "deleted_at IS NULL")

# Composite indexes for common queries
create index(:orders, [:customer_id, :status])

# GIN indexes for JSONB/arrays
metadata_index(:products)
tags_field(:articles)  # Creates GIN index automatically
```

### 3. Use Soft Deletes

```elixir
# Add soft delete capability
deleted_fields(with_user: true, with_reason: true)

# Create active record index
deleted_indexes(:users, active_index: true)
```

### 4. Leverage Type Safety

```elixir
# Money fields with precision
money_field(:price, precision: 10, scale: 2)

# Counters with non-negative constraint
counter_field(:quantity)

# Percentages with range validation
percentage_field(:discount)
```

### 5. Pattern: Multi-tenant Tables

```elixir
create_table :tenant_data do
  add :tenant_id, references(:tenants, type: :binary_id), null: false
  # ... other fields ...
end

create index(:tenant_data, [:tenant_id])
# Add tenant_id to other indexes for performance
create index(:tenant_data, [:tenant_id, :status])
```

### 6. Pattern: Hierarchical Data

```elixir
create_table :categories do
  title_fields()
  slug_field()
  add :parent_id, references(:categories, type: :binary_id)
  add :path, :string  # Materialized path
  add :depth, :integer, default: 0
  timestamps()
end

create index(:categories, [:parent_id])
create index(:categories, [:path])
```

## Important Migration Notes

1. **Always use `Events.Repo.Migration`** for enhanced functionality
2. **UUIDv7 requires PostgreSQL 18+** - Falls back to uuid_generate_v4() if needed
3. **Enable citext** for case-insensitive text fields
4. **Field sets** ensure consistency across tables
5. **Smart indexes** have automatic naming conventions
6. **Pattern matching** throughout for clean option handling
7. **Pipelines** for functional composition

## Testing Schemas

```elixir
defmodule MyApp.UserTest do
  use ExUnit.Case
  import Events.Schema.TestHelpers

  describe "email validation" do
    test "accepts valid emails" do
      assert_valid("user@example.com", :string, email())
      assert_valid("user+tag@example.co.uk", :string, email())
    end

    test "rejects invalid emails" do
      assert_invalid("notanemail", :string, email())
      assert_invalid("@example.com", :string, email())
      assert_invalid("user@", :string, email())
    end
  end

  describe "age validation" do
    test "accepts valid ages" do
      assert_valid(25, :integer, age())
      assert_valid(0, :integer, age())
      assert_valid(150, :integer, age())
    end

    test "rejects invalid ages" do
      assert_invalid(-1, :integer, age())
      assert_invalid(151, :integer, age())
    end
  end

  test "full user changeset" do
    valid_attrs = %{
      email: "test@example.com",
      username: "testuser",
      password: "SecurePass123",
      full_name: "Test User",
      age: 25
    }

    changeset = User.changeset(%User{}, valid_attrs)
    assert changeset.valid?

    invalid_attrs = %{
      email: "invalid",
      username: "x",  # too short
      password: "123",  # too short
      age: -5  # negative
    }

    changeset = User.changeset(%User{}, invalid_attrs)
    refute changeset.valid?
    assert length(changeset.errors) >= 4
  end
end
```

## Important Notes

1. **Always use `Events.Schema`** instead of `Ecto.Schema`
2. **Import presets** when you want to use them: `import Events.Schema.Presets`
3. **Default values**:
   - `cast: true` (default) - Set `cast: false` to exclude from casting
   - `required: false` (default) - Set `required: true` for mandatory fields
   - `trim: true` (default for strings) - Set `trim: false` to preserve spaces (e.g., passwords)
4. **Normalization happens before validation** - Important for format checks
5. **Use presets for common fields** - They include best practices
6. **Custom messages** support both strings and functions
7. **Virtual fields** use `virtual: true` and are not persisted
8. **Changesets** automatically get `__apply_field_validations__()` function

## Telemetry and Monitoring

Enable validation telemetry for performance monitoring:

```elixir
# In config/config.exs
config :events, :validation_telemetry, true

# Attach handlers in application.ex
Events.Schema.Telemetry.attach_default_handlers()
```

## Compile-Time Warnings

Enable warnings for common mistakes:

```elixir
# In config/config.exs
config :events, :schema_warnings, true
```

This will warn about:
- Email fields without `normalize: :downcase`
- Password fields without `trim: false`
- Conflicting options (`required: true` with `null: true`)
- Performance issues (large composite constraints)
- Type mismatches (string validations on numbers)

---

This comprehensive guide ensures that any schema created in the Events project uses the full power of the validation system. Always refer to this guide when creating new schemas or modifying existing ones.