# Events System Documentation

Welcome to the Events system documentation. This system provides comprehensive database migrations, schema definitions, and validation for Elixir/Phoenix applications.

## 📚 Quick Navigation

| Document | Description |
|----------|-------------|
| **[Quick Start](./QUICK_START.md)** | Get up and running in 5 minutes |
| **[Migration Reference](./MIGRATION_REFERENCE.md)** | Complete migration system guide |
| **[Schema Reference](./SCHEMA_REFERENCE.md)** | Complete schema and validation guide |
| **[Validation Reference](./VALIDATION_REFERENCE.md)** | Validation patterns and testing |
| **[Query API](./QUERY_API.md)** | Query and data access patterns |

## 🚀 Key Features

### Smart Defaults
- **UUIDv7** primary keys (PostgreSQL 18+)
- **citext** for case-insensitive fields
- **utc_datetime_usec** for precise timestamps
- **jsonb** for flexible metadata
- **Auto-trim** for all string fields

### Enhanced Field Macros

```elixir
defmodule MyApp.User do
  use Events.Schema
  import OmSchema.FieldHelpers

  schema "users" do
    # Concise field helpers
    email_field :email
    name_field :first_name
    name_field :last_name
    birth_date_field :birth_date
    password_field :password

    timestamps()
  end
end
```

### Intuitive Validations

```elixir
schema "products" do
  # String validations
  field :name, :string, required: true, min_length: 3, max_length: 200

  # Numeric shortcuts and ranges
  field :price, :float, gt: 0
  field :stock, :integer, in: 0..10000
  field :percentage, :float, in: 0..100

  # Date validations
  field :event_date, :date, future: true
  field :birth_date, :date, past: true
end
```

### Migration Pipeline

```elixir
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Events.Migration

  def change do
    create_table(:products)
    |> with_uuid_primary_key()
    |> with_field(:name, :string, null: false)
    |> with_field(:price, :decimal, precision: 10, scale: 2)
    |> with_type_fields()
    |> with_status_fields()
    |> with_timestamps()
    |> with_metadata()
    |> execute()
  end
end
```

## 📖 Documentation Highlights

### For Beginners

Start with **[Quick Start](./QUICK_START.md)** to:
- Set up your first schema
- Create migrations
- Understand the basic patterns

### For Schema Development

See **[Schema Reference](./SCHEMA_REFERENCE.md)** for:
- Complete field type reference
- All validation options
- String, numeric, and date validations
- Presets and field helpers
- Normalization and mappers
- Real-world examples

### For Migrations

See **[Migration Reference](./MIGRATION_REFERENCE.md)** for:
- Pipeline-based migrations
- Field macros and helpers
- Index creation patterns
- Common migration scenarios

### For Validation

See **[Validation Reference](./VALIDATION_REFERENCE.md)** for:
- Validation patterns
- Custom validators
- Error handling
- Testing strategies

## 🎯 Common Tasks

### Create a New Schema

```elixir
defmodule MyApp.Product do
  use Events.Schema
  import OmSchema.FieldHelpers

  schema "products" do
    title_field :name
    text_field :description
    slug_field :slug, uniquify: true

    field :price, :float, gt: 0, required: true
    field :stock, :integer, in: 0..10000

    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> Ecto.Changeset.cast(attrs, __cast_fields__())
    |> Ecto.Changeset.validate_required(__required_fields__())
    |> __apply_field_validations__()
  end
end
```

### Create a Migration

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Events.Migration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_citext_field(:email, null: false)
    |> with_string_field(:username, null: false)
    |> with_text_field(:bio)
    |> with_status_fields()
    |> with_timestamps()
    |> with_unique_index([:email])
    |> with_unique_index([:username])
    |> execute()
  end
end
```

### Add Validations

```elixir
# Using field helpers (recommended)
email_field :email
name_field :first_name
birth_date_field :birth_date

# Using presets
import OmSchema.Presets.Strings
field :first_name, :string, preset: name()

# Manual validations
field :age, :integer, gte: 13, lte: 120
field :price, :float, gt: 0
field :percentage, :float, in: 0..100
```

## ✨ Recent Enhancements

### String Enhancements
- ✅ Auto-trim by default (disable with `trim: false`)
- ✅ 15+ string presets (name, email, title, code, etc.)
- ✅ 13+ field helpers for common patterns
- ✅ Advanced normalization with mappers
- ✅ Slugify with uniqueness support

### Numeric Enhancements
- ✅ Shortcut syntax (`:gt`, `:gte`, `:lt`, `:lte`, `:eq`)
- ✅ Range syntax (`in: 0..100`)
- ✅ Custom messages with tuples
- ✅ Preset shortcuts (`:positive`, `:non_negative`)

### Date/DateTime Enhancements
- ✅ 12+ date/time presets
- ✅ Age validations (birth_date, adult_birth_date)
- ✅ Future/past validations
- ✅ Scheduled datetime (minimum 1 hour in future)

## 🔍 Examples by Use Case

### User Management

```elixir
schema "users" do
  email_field :email
  password_field :password
  name_field :first_name
  name_field :last_name
  birth_date_field :birth_date

  phone_field :phone, required: false
  url_field :website, required: false
  text_field :bio, required: false

  timestamps()
end
```

### E-commerce Product

```elixir
schema "products" do
  title_field :name
  text_field :description
  slug_field :slug, uniquify: true

  field :price, :float, gt: 0, required: true
  field :stock_count, :integer, in: 0..10000
  field :sku, :string, format: ~r/^[A-Z]{3}-\d{4}$/

  field :status, :citext, in: ["draft", "active", "archived"]

  timestamps()
end
```

### Event/Booking System

```elixir
schema "events" do
  title_field :title
  text_field :description
  slug_field :slug, uniquify: true

  field :event_date, :date, future: true
  field :starts_at, :utc_datetime_usec, future: true
  field :max_attendees, :integer, gte: 1
  field :ticket_price, :decimal, gte: 0

  address_field :venue_address
  city_field :city
  postal_code_field :postal_code

  timestamps()
end
```

## 🛠️ Development Workflow

### 1. Define Schema

```elixir
# lib/my_app/product.ex
defmodule MyApp.Product do
  use Events.Schema
  # ... schema definition
end
```

### 2. Create Migration

```bash
mix ecto.gen.migration create_products
```

```elixir
# priv/repo/migrations/xxx_create_products.exs
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Events.Migration
  # ... migration definition
end
```

### 3. Run Migration

```bash
mix ecto.migrate
```

### 4. Test Validations

```elixir
# test/my_app/product_test.exs
test "validates required fields" do
  changeset = Product.changeset(%Product{}, %{})
  refute changeset.valid?
end
```

## 🧪 Testing

All features are thoroughly tested:
- **171 tests passing** ✅
- Unit tests for all validators
- Integration tests for field helpers
- Edge case coverage

## 📝 Best Practices

### 1. Use Field Helpers

```elixir
# Instead of:
field :email, :string, required: true, format: :email, normalize: :downcase

# Use:
email_field :email
```

### 2. Leverage Presets

```elixir
import OmSchema.Presets.Strings

field :first_name, :string, preset: name()
field :last_name, :string, preset: name()
```

### 3. Use Range Syntax

```elixir
# More intuitive
field :percentage, :float, in: 0..100

# Than this
field :percentage, :float, min: 0, max: 100
```

### 4. Add Custom Messages

```elixir
field :age, :integer, gte: {18, message: "must be 18 or older"}
```

### 5. Disable Auto-trim for Sensitive Fields

```elixir
password_field :password  # Already has trim: false
field :api_key, :string, trim: false
```

## 🚦 Support & Contributing

- Report issues on GitHub
- Read the full documentation for each feature
- Follow the patterns in existing schemas
- Test your changes thoroughly

## 📚 Additional Resources

- [Ecto Documentation](https://hexdocs.pm/ecto)
- [Phoenix Framework](https://hexdocs.pm/phoenix)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

**Last Updated:** 2025-11-23

**Documentation Version:** 2.0.0
