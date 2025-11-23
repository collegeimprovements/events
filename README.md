# Events

A Phoenix application with an enhanced schema and migration system providing comprehensive database migrations, validations, and data modeling patterns.

## 🚀 Quick Start

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server

# Or in interactive mode
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

## 📚 Documentation

Comprehensive documentation is available in the [`docs/`](./docs/) directory:

| Document | Description |
|----------|-------------|
| **[Quick Start](./docs/QUICK_START.md)** | Get started in 5 minutes |
| **[Schema Reference](./docs/SCHEMA_REFERENCE.md)** | Complete schema and validation guide |
| **[Validation Reference](./docs/VALIDATION_REFERENCE.md)** | Validation patterns and testing |
| **[Migration Reference](./docs/MIGRATION_REFERENCE.md)** | Database migration system |
| **[Query API](./docs/QUERY_API.md)** | Query and data access patterns |

### For Developers

Additional development documentation:
- [Architecture](./docs/development/ARCHITECTURE.md)
- [Agents System](./docs/development/AGENTS.md)
- [S3 Cheatsheet](./docs/development/S3_CHEATSHEET.md)

## ✨ Key Features

### Enhanced Schema System
- Auto-trim for all string fields
- 15+ string presets (name, email, title, etc.)
- 20+ field helper macros
- Advanced normalization with mappers
- Slugify with uniqueness support

### Intuitive Validations
- Shortcut syntax (`:gt`, `:gte`, `:lt`, `:lte`, `:eq`)
- Range syntax (`in: 0..100`)
- Custom messages with tuples
- Date/time presets and validations

### Pipeline-Based Migrations
- Composable field macros
- Smart defaults (UUIDv7, citext, timestamps)
- Index creation helpers

## 📖 Example

```elixir
defmodule MyApp.User do
  use Events.Schema
  import Events.Schema.FieldHelpers

  schema "users" do
    email_field :email
    password_field :password
    name_field :first_name
    name_field :last_name
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

## 🧪 Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover
```

## 🔧 Development

```bash
# Create a migration
mix ecto.gen.migration create_users

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback

# Database reset
mix ecto.reset
```

## 📦 Production

Ready to run in production? Check the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## 🔗 Resources

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Phoenix Docs](https://hexdocs.pm/phoenix)
- [Ecto Documentation](https://hexdocs.pm/ecto)
- [Elixir Forum](https://elixirforum.com/c/phoenix-forum)

## 📄 License

Copyright © 2024
