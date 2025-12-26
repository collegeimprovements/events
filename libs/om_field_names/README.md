# OmFieldNames

Generate consistent field name atoms at compile time.

## Installation

```elixir
def deps do
  [{:om_field_names, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.Fields do
  use OmFieldNames

  # Define field groups
  fields :user, [:id, :name, :email, :role]
  fields :order, [:id, :total, :status, :user_id]
end

# Generated functions
MyApp.Fields.user_fields()
# => [:id, :name, :email, :role]

MyApp.Fields.order_fields()
# => [:id, :total, :status, :user_id]

# Check membership
MyApp.Fields.user_field?(:email)  # => true
MyApp.Fields.user_field?(:foo)    # => false
```

## Use Cases

### Schema Fields

```elixir
defmodule MyApp.User do
  use Ecto.Schema
  import MyApp.Fields

  @cast_fields user_fields() -- [:id]
  @required_fields [:name, :email]

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
  end
end
```

### API Responses

```elixir
def render_user(user) do
  Map.take(user, MyApp.Fields.user_fields())
end
```

## License

MIT
