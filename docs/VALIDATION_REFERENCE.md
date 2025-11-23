# Validation Reference

Comprehensive validation guide for the Events schema system.

> **Note:** Validations are declared directly in schema field definitions. See [SCHEMA_REFERENCE.md](./SCHEMA_REFERENCE.md) for complete validation options.

## Quick Reference

```elixir
defmodule MyApp.User do
  use Events.Schema

  schema "users" do
    # String validations
    field :email, :string, required: true, format: :email, normalize: :downcase
    field :username, :string, min_length: 3, max_length: 30
    
    # Numeric validations
    field :age, :integer, gte: 13, lte: 120
    field :price, :float, gt: 0
    field :percentage, :float, in: 0..100
    
    # Date validations
    field :birth_date, :date, past: true
    field :event_date, :date, future: true
    
    timestamps()
  end
end
```

## Validation Types

### String Validations

| Validation | Description | Example |
|------------|-------------|---------|
| `required` | Field must be present | `required: true` |
| `min_length` | Minimum string length | `min_length: 3` |
| `max_length` | Maximum string length | `max_length: 255` |
| `length` | Exact string length | `length: 10` |
| `format` | Regex or built-in format | `format: :email` |
| `in` | Must be in list | `in: ["S", "M", "L"]` |
| `not_in` | Must not be in list | `not_in: ["admin", "root"]` |
| `normalize` | Transform value | `normalize: :downcase` |
| `trim` | Enable/disable auto-trim | `trim: false` |

**Built-in Formats:**
- `:email` - Email address
- `:url` - URL format
- `:slug` - URL-safe slug
- `:username` - Alphanumeric + underscore
- `:hex_color` - Hex color code (#RRGGBB)

### Numeric Validations

| Validation | Description | Example |
|------------|-------------|---------|
| `gt` | Greater than | `gt: 0` |
| `gte` | Greater than or equal | `gte: 0` |
| `lt` | Less than | `lt: 100` |
| `lte` | Less than or equal | `lte: 100` |
| `eq` | Equal to | `eq: 0` |
| `in` | Range validation | `in: 0..100` |
| `min` | Alias for `gte` | `min: 0` |
| `max` | Alias for `lte` | `max: 100` |
| `positive` | > 0 | `positive: true` |
| `non_negative` | >= 0 | `non_negative: true` |
| `negative` | < 0 | `negative: true` |
| `non_positive` | <= 0 | `non_positive: true` |

### Date/DateTime Validations

| Validation | Description | Example |
|------------|-------------|---------|
| `past` | Must be in past | `past: true` |
| `future` | Must be in future | `future: true` |
| `before` | Before date/field | `before: ~D[2025-12-31]` |
| `after` | After date/field | `after: ~D[2025-01-01]` |

### Boolean Validations

| Validation | Description | Example |
|------------|-------------|---------|
| `acceptance` | Must be true | `acceptance: true` |

### Array Validations

| Validation | Description | Example |
|------------|-------------|---------|
| `min_length` | Minimum array length | `min_length: 1` |
| `max_length` | Maximum array length | `max_length: 10` |
| `unique_items` | Items must be unique | `unique_items: true` |

## Validation Pipeline Order

Validations execute in this order:

1. **Normalization** - Transform values (trim, downcase, etc.)
2. **Casting** - Convert to field type
3. **Required Check** - Validate required fields
4. **Type Validation** - Ensure correct type
5. **Format Validation** - Check regex/format
6. **Length Validation** - String/array length
7. **Number Validation** - Numeric ranges
8. **Inclusion Validation** - Check in/not_in
9. **Date/Time Validation** - Temporal constraints
10. **Custom Validation** - User-defined validators

## Custom Error Messages

### Inline Messages

```elixir
# Simple message
field :email, :string, required: true, message: "is required"

# Tuple format for specific validations
field :age, :integer, gt: {18, message: "must be 18 or older"}

# Multiple validations with messages
field :score, :integer,
  gte: {0, message: "cannot be negative"},
  lte: {100, message: "cannot exceed 100"}
```

### Message Map

```elixir
field :email, :string, 
  required: true,
  format: :email,
  messages: %{
    required: "email address is required",
    format: "must be a valid email address"
  }
```

## Conditional Validation

```elixir
# Validate if condition is true
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

## Custom Validations

### In Changeset

```elixir
def changeset(user, attrs) do
  user
  |> Ecto.Changeset.cast(attrs, __cast_fields__())
  |> Ecto.Changeset.validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> validate_password_strength()
  |> validate_email_uniqueness()
end

defp validate_password_strength(changeset) do
  password = Ecto.Changeset.get_change(changeset, :password)
  
  if password && !strong_password?(password) do
    Ecto.Changeset.add_error(changeset, :password, 
      "must contain uppercase, lowercase, and number")
  else
    changeset
  end
end

defp validate_email_uniqueness(changeset) do
  Ecto.Changeset.unsafe_validate_unique(changeset, :email, MyApp.Repo)
end
```

### Reusable Validators

```elixir
defmodule MyApp.Validators do
  import Ecto.Changeset

  def validate_slug_format(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if String.match?(value, ~r/^[a-z0-9-]+$/) do
        []
      else
        [{field, "must be lowercase alphanumeric with hyphens"}]
      end
    end)
  end

  def validate_future_date(changeset, field, min_days \\ 1) do
    validate_change(changeset, field, fn ^field, date ->
      min_date = Date.add(Date.utc_today(), min_days)
      
      if Date.compare(date, min_date) == :gt do
        []
      else
        [{field, "must be at least #{min_days} days in the future"}]
      end
    end)
  end
  
  def validate_price_range(changeset, min_field, max_field) do
    min_price = get_field(changeset, min_field)
    max_price = get_field(changeset, max_field)
    
    if min_price && max_price && Decimal.compare(min_price, max_price) == :gt do
      add_error(changeset, min_field, "must be less than maximum price")
    else
      changeset
    end
  end
end

# Usage
def changeset(product, attrs) do
  product
  |> cast(attrs, __cast_fields__())
  |> validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> MyApp.Validators.validate_slug_format(:slug)
  |> MyApp.Validators.validate_price_range(:min_price, :max_price)
end
```

## Common Validation Patterns

### User Registration

```elixir
schema "users" do
  field :email, :string, 
    required: true,
    format: :email,
    normalize: :downcase,
    message: "valid email is required"
  
  field :password, :string,
    required: true,
    min_length: 8,
    max_length: 128,
    trim: false
  
  field :username, :string,
    required: true,
    min_length: 3,
    max_length: 30,
    format: ~r/^[a-z0-9_]+$/,
    normalize: :downcase
  
  field :age, :integer,
    required: true,
    gte: {13, message: "must be 13 or older"}
  
  field :terms_accepted, :boolean,
    acceptance: true
end

def registration_changeset(user, attrs) do
  user
  |> cast(attrs, __cast_fields__())
  |> validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> validate_password_confirmation()
  |> validate_email_uniqueness()
  |> hash_password()
end
```

### Product/E-commerce

```elixir
schema "products" do
  field :name, :string,
    required: true,
    min_length: 3,
    max_length: 200
  
  field :sku, :string,
    required: true,
    format: ~r/^[A-Z]{3}-\d{4}$/,
    normalize: :upcase
  
  field :price, :decimal,
    required: true,
    gt: {0, message: "must be greater than zero"}
  
  field :sale_price, :decimal,
    required: false,
    gt: 0
  
  field :stock_count, :integer,
    required: true,
    in: 0..10000
  
  field :weight, :float,
    required: false,
    gte: 0
  
  field :status, :citext,
    required: true,
    in: ["draft", "active", "archived"],
    default: "draft"
end

def changeset(product, attrs) do
  product
  |> cast(attrs, __cast_fields__())
  |> validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> validate_sale_price_less_than_price()
  |> validate_sku_uniqueness()
end
```

### Event/Booking

```elixir
schema "events" do
  field :title, :string,
    required: true,
    min_length: 3,
    max_length: 255
  
  field :event_date, :date,
    required: true,
    future: true
  
  field :starts_at, :utc_datetime_usec,
    required: true
  
  field :ends_at, :utc_datetime_usec,
    required: true
  
  field :max_attendees, :integer,
    required: true,
    gte: {1, message: "must have at least one attendee"}
  
  field :ticket_price, :decimal,
    required: true,
    gte: 0
  
  field :status, :citext,
    in: ["draft", "published", "cancelled"],
    default: "draft"
end

def changeset(event, attrs) do
  event
  |> cast(attrs, __cast_fields__())
  |> validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> validate_ends_after_starts()
end

defp validate_ends_after_starts(changeset) do
  starts_at = get_field(changeset, :starts_at)
  ends_at = get_field(changeset, :ends_at)
  
  if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
    add_error(changeset, :ends_at, "must be after start time")
  else
    changeset
  end
end
```

## Testing Validations

```elixir
defmodule MyApp.UserTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.User
  
  describe "changeset/2" do
    test "valid with all required fields" do
      attrs = %{
        email: "user@example.com",
        password: "SecurePass123",
        username: "john_doe",
        age: 25
      }
      
      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
    end
    
    test "requires email" do
      changeset = User.changeset(%User{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end
    
    test "validates email format" do
      attrs = %{email: "invalid-email"}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end
    
    test "normalizes email to lowercase" do
      attrs = %{email: "User@EXAMPLE.COM", password: "pass123", username: "user", age: 25}
      changeset = User.changeset(%User{}, attrs)
      
      assert changeset.changes.email == "user@example.com"
    end
    
    test "validates minimum age" do
      attrs = %{email: "user@example.com", age: 12}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "must be 13 or older" in errors_on(changeset).age
    end
    
    test "validates password length" do
      attrs = %{password: "short"}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end
  end
end
```

## Performance Tips

### 1. Order Validations by Cost

```elixir
# Good - cheap validations first
field :email, :string,
  required: true,      # Fast
  format: :email       # Moderate

# Then in changeset
|> validate_email_uniqueness()  # Expensive (DB query)

# Bad - expensive validation in field
field :email, :string, unique: true, required: true
```

### 2. Use Database Constraints

```elixir
# Migration
create table(:users) do
  add :email, :citext, null: false
  add :username, :string, null: false
end

create unique_index(:users, [:email])
create unique_index(:users, [:username])

# Schema validation (fast fail) + DB constraint (data integrity)
field :email, :string, required: true, format: :email
field :username, :string, required: true, min_length: 3
```

### 3. Conditional Expensive Validations

```elixir
def changeset(user, attrs) do
  user
  |> cast(attrs, __cast_fields__())
  |> validate_required(__required_fields__())
  |> __apply_field_validations__()
  |> maybe_validate_uniqueness()
end

defp maybe_validate_uniqueness(changeset) do
  # Only check uniqueness if email changed and basic validations passed
  if changeset.valid? && get_change(changeset, :email) do
    unsafe_validate_unique(changeset, :email, MyApp.Repo)
  else
    changeset
  end
end
```

## Error Handling

### Extracting Errors

```elixir
changeset = User.changeset(%User{}, %{})

# Get all errors
changeset.errors
# [{:email, {"can't be blank", [validation: :required]}}]

# Get specific field errors
Keyword.get_values(changeset.errors, :email)

# Format errors for display
Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
  Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
    opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
  end)
end)
```

### Returning Errors

```elixir
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
  |> case do
    {:ok, user} ->
      {:ok, user}
    
    {:error, changeset} ->
      {:error, format_errors(changeset)}
  end
end

defp format_errors(changeset) do
  Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end)
end
```

## See Also

- [SCHEMA_REFERENCE.md](./SCHEMA_REFERENCE.md) - Complete schema and validation options
- [MIGRATION_REFERENCE.md](./MIGRATION_REFERENCE.md) - Database migrations
- [Ecto.Changeset documentation](https://hexdocs.pm/ecto/Ecto.Changeset.html)
