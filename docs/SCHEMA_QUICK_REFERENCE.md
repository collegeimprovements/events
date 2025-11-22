# Events.Schema Quick Reference

## Essential Setup

```elixir
defmodule MyApp.MySchema do
  use Events.Schema                    # ALWAYS use Events.Schema, NOT Ecto.Schema
  import Events.Schema.Presets         # Optional: for presets

  schema "table_name" do
    field :name, :type, options        # Field with validations
    timestamps()                        # Adds created_at, updated_at
  end
end
```

## Common Field Patterns

### Basic Fields
```elixir
# Required string with length limits
field :name, :string, required: true, min_length: 2, max_length: 100

# Optional string with format
field :email, :string, format: :email, normalize: [:trim, :downcase]

# Number with range
field :age, :integer, min: 18, max: 120

# Boolean with default
field :active, :boolean, default: true

# Enum field
field :status, :string, in: ["pending", "active", "archived"]
```

### Using Presets (Recommended)
```elixir
field :email, :string, email()
field :username, :string, username(min_length: 3)
field :password, :string, password(min_length: 8)
field :website, :string, url(required: false)
field :age, :integer, age()
field :price, :decimal, money()
field :rating, :integer, rating()
field :tags, {:array, :string}, tags()
```

## Validation Options Reference

### String Validations
| Option | Example | Description |
|--------|---------|-------------|
| `required: true` | | Field must be present |
| `min_length: n` | `min_length: 3` | Minimum length |
| `max_length: n` | `max_length: 100` | Maximum length |
| `length: n` | `length: 10` | Exact length |
| `format: regex` | `format: ~r/^[A-Z]+$/` | Regex pattern |
| `format: :type` | `format: :email` | Named format |
| `in: [...]` | `in: ["a", "b"]` | Must be in list |
| `not_in: [...]` | `not_in: ["admin"]` | Cannot be in list |
| `normalize: atom/list` | `normalize: [:trim, :downcase]` | Transform value |
| `unique: true` | | Database unique |

### Number Validations
| Option | Example | Description |
|--------|---------|-------------|
| `min: n` | `min: 0` | Minimum value (inclusive) |
| `max: n` | `max: 100` | Maximum value (inclusive) |
| `greater_than: n` | `greater_than: 0` | Must be > n |
| `less_than: n` | `less_than: 100` | Must be < n |
| `positive: true` | | Must be > 0 |
| `non_negative: true` | | Must be >= 0 |
| `in: [...]` | `in: [10, 20, 30]` | Must be in list |

### Date/Time Validations
| Option | Example | Description |
|--------|---------|-------------|
| `past: true` | | Must be in past |
| `future: true` | | Must be in future |
| `after: date` | `after: ~D[2020-01-01]` | After specific date |
| `before: date` | `before: ~D[2030-01-01]` | Before specific date |
| `after: {:now, hours: 24}` | | After relative time |
| `before: {:field, :end_date}` | | Before other field |

### Array Validations
| Option | Example | Description |
|--------|---------|-------------|
| `min_length: n` | `min_length: 1` | Min array size |
| `max_length: n` | `max_length: 10` | Max array size |
| `unique_items: true` | | No duplicates |
| `in: [...]` | `in: ["a", "b", "c"]` | Items subset of list |
| `item_format: regex` | `item_format: ~r/^[a-z]+$/` | Format each item |

### Map Validations
| Option | Example | Description |
|--------|---------|-------------|
| `required_keys: [...]` | `required_keys: ["name"]` | Required keys |
| `forbidden_keys: [...]` | `forbidden_keys: ["pwd"]` | Forbidden keys |
| `min_keys: n` | `min_keys: 1` | Min key count |
| `max_keys: n` | `max_keys: 20` | Max key count |

## Named Formats
- `:email` - Email address
- `:url` - HTTP/HTTPS URL
- `:uuid` - UUID format
- `:slug` - URL-safe slug
- `:hex_color` - Hex color (#RRGGBB)
- `:ip` - IP address

## Normalization Options
- `:trim` - Remove leading/trailing spaces
- `:squish` - Collapse multiple spaces
- `:downcase` - Convert to lowercase
- `:upcase` - Convert to uppercase
- `:capitalize` - Capitalize first letter
- `:titlecase` - Capitalize each word
- `:slugify` - Convert to slug
- `{:slugify, uniquify: true}` - Slug with random suffix

## Available Presets (44 Total)

### Basic
`email()`, `username()`, `password()`, `url()`, `phone()`, `uuid()`, `slug()`

### Numbers
`age()`, `rating()`, `percentage()`, `money()`, `positive_integer()`

### Location
`country_code()`, `zip_code()`, `latitude()`, `longitude()`, `timezone()`

### Financial
`credit_card()`, `iban()`, `bitcoin_address()`, `ethereum_address()`, `currency_code()`

### Network
`ipv4()`, `ipv6()`, `mac_address()`, `domain()`

### Development
`semver()`, `jwt()`, `base64()`, `mime_type()`, `file_path()`

### Social
`social_handle()`, `hashtag()`

### Other
`hex_color()`, `rgb_color()`, `language_code()`, `ssn()`, `isbn()`

## Custom Validation

```elixir
# Inline function
field :code, :string,
  validate: fn value ->
    if valid?(value), do: :ok, else: {:error, "Invalid code"}
  end

# Module function
field :email, :string,
  validate: {MyModule, :validate_email}

# Conditional validation
field :tax_id, :string,
  validate_if: fn changeset ->
    get_field(changeset, :type) == "business"
  end,
  format: ~r/^\d{9}$/
```

## Cross-Field Validation

```elixir
validate: [
  confirm: {:password, :password_confirmation},
  compare: {:start_date, :<=, :end_date},
  dependent: {:notifications, requires: :email},
  exclusive: {[:phone, :email]}
]
```

## Custom Error Messages

```elixir
# Inline message
field :age, :integer,
  min: {18, message: "Must be an adult"}

# Format with message
field :email, :string,
  format: {:email, message: "Invalid email format"}
```

## Complete Example

```elixir
defmodule MyApp.User do
  use Events.Schema
  import Events.Schema.Presets

  schema "users" do
    # Use presets for common fields
    field :email, :string, email()
    field :username, :string, username(min_length: 3, max_length: 20)
    field :password, :string, password(min_length: 8)

    # Custom validation for specific needs
    field :age, :integer, age()
    field :bio, :string, max_length: 500
    field :website, :string, url(required: false)
    field :role, :string, enum(in: ["admin", "user", "guest"])
    field :tags, {:array, :string}, tags(max_length: 5)
    field :settings, :map, metadata()

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, __cast_fields__())           # Auto-generated
    |> validate_required([:email, :username])
    |> __apply_field_validations__()            # Auto-generated
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end
end
```

## Key Points to Remember

1. **ALWAYS use `use Events.Schema`** - Never use `use Ecto.Schema`
2. **Import presets**: `import Events.Schema.Presets` when using presets
3. **Defaults**: `cast: true`, `required: false`, `trim: true` (for strings)
4. **Auto-generated helpers**: `__cast_fields__()`, `__apply_field_validations__()`
5. **Normalization before validation**: Transforms happen first
6. **Password fields**: Always use `trim: false` or `password()` preset
7. **Email fields**: Always normalize with `:downcase` or use `email()` preset
8. **Validation order**: Required → Type → Format → Range → Custom
9. **Virtual fields**: Use `virtual: true` for non-persisted fields
10. **Timestamps**: Use `timestamps()` for created_at/updated_at