# Events.Schema System Guide

## Overview

The Events.Schema system is an enhanced Ecto schema system that provides powerful field-level validations directly in the schema definition. This guide provides comprehensive examples and patterns for creating schemas with built-in validations.

## Table of Contents
- [Basic Schema Structure](#basic-schema-structure)
- [Field Types](#field-types)
- [Validation Options](#validation-options)
- [Normalization Options](#normalization-options)
- [Validation Presets](#validation-presets)
- [Complete Examples](#complete-examples)
- [Advanced Patterns](#advanced-patterns)

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

## Migration Examples with Constraints

When creating migrations, include the database constraints:

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :username, :string, null: false
      add :age, :integer
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    # Unique constraints
    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    # Check constraints for validations
    create constraint(:users, :age_must_be_positive, check: "age >= 0")
    create constraint(:users, :age_must_be_reasonable, check: "age <= 150")
    create constraint(:users, :status_must_be_valid,
      check: "status IN ('active', 'pending', 'suspended')")
  end
end
```

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