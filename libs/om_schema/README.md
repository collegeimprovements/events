# OmSchema

Enhanced Ecto schema with inline validations, presets, and field groups.

## Installation

```elixir
def deps do
  [{:om_schema, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.User do
  use OmSchema

  schema "users" do
    # Enhanced fields with inline validations
    field :email, :string, required: true, format: :email, max_length: 255
    field :name, :string, required: true, min_length: 2, max_length: 100
    field :age, :integer, min: 0, max: 150

    # Presets for common patterns
    field :username, :string, preset: username()
    field :password, :string, preset: password(), virtual: true
    field :slug, :string, preset: slug()

    # Field groups
    type_fields()                                    # :type, :subtype
    status_fields(values: [:active, :inactive])     # :status enum
    audit_fields()                                   # :created_by_id, :updated_by_id
    timestamps()                                     # :inserted_at, :updated_at
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, __cast_fields__())
    |> validate_required(__required_fields__())
    |> __apply_field_validations__()
    |> unique_constraint(:email)
  end
end
```

## Features

### Enhanced Field Options

```elixir
field :email, :string,
  required: true,           # Auto-adds to required fields
  format: :email,           # Email format validation
  max_length: 255,          # Max length validation
  mappers: [:trim, :downcase]  # Transform before validation
```

### Presets

```elixir
field :email, :string, preset: email()              # Email with format/length
field :username, :string, preset: username()        # Alphanumeric 3-30 chars
field :password, :string, preset: password()        # Min 8 chars, virtual
field :slug, :string, preset: slug()                # URL-safe format
field :phone, :string, preset: phone()              # Phone number format
field :url, :string, preset: url()                  # URL format
```

### Field Groups

```elixir
# Type classification
type_fields()                    # Adds :type and :subtype

# Status with enum
status_fields(values: [:draft, :published, :archived])

# Audit tracking
audit_fields()                   # Adds :created_by_id, :updated_by_id

# Metadata
metadata_field()                 # Adds :metadata as :map

# Soft delete
soft_delete_field()              # Adds :deleted_at
```

### Auto-generated Functions

```elixir
__cast_fields__()           # All castable fields
__required_fields__()       # Fields marked required: true
__apply_field_validations__()  # Apply all inline validations
```

## Mappers

Transform values before validation:

```elixir
field :email, :string, mappers: [:trim, :downcase]
field :name, :string, mappers: [:trim, :titlecase]
field :slug, :string, mappers: [:trim, :slugify]
```

Available: `:trim`, `:downcase`, `:upcase`, `:titlecase`, `:slugify`, `:strip_html`

## License

MIT
