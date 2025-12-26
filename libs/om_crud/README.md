# OmCrud

CRUD operations for Ecto with Multi transactions and PostgreSQL MERGE support.

## Installation

```elixir
def deps do
  [{:om_crud, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
alias OmCrud
alias OmCrud.{Multi, Merge}

# Simple CRUD
{:ok, user} = OmCrud.create(User, %{name: "John", email: "john@example.com"})
{:ok, user} = OmCrud.fetch(User, user.id)
{:ok, user} = OmCrud.update(user, %{name: "Jane"})
:ok = OmCrud.delete(user)
```

## Features

### Basic Operations

```elixir
OmCrud.create(User, attrs)
OmCrud.create(User, attrs, changeset: :admin_changeset)

OmCrud.fetch(User, id)
OmCrud.fetch(User, id, preload: [:posts])

OmCrud.update(user, attrs)
OmCrud.update(user, attrs, force: [:updated_at])

OmCrud.delete(user)
```

### Bulk Operations

```elixir
OmCrud.create_all(User, [%{name: "A"}, %{name: "B"}])
OmCrud.update_all(User, [set: [status: :active]], where: [role: :guest])
OmCrud.delete_all(User, where: [status: :inactive])
```

### Multi Transactions

```elixir
Multi.new()
|> Multi.create(:user, User, user_attrs)
|> Multi.create(:account, Account, fn %{user: user} ->
     %{owner_id: user.id}
   end)
|> Multi.update(:profile, fn %{user: user} ->
     {user.profile, %{setup_complete: true}}
   end)
|> OmCrud.run()
```

### PostgreSQL MERGE (Upserts)

```elixir
User
|> Merge.new(users_data)
|> Merge.match_on(:email)
|> Merge.when_matched(:update, [:name, :updated_at])
|> Merge.when_not_matched(:insert)
|> OmCrud.run()
```

### Context Module

Generate CRUD functions for your context:

```elixir
defmodule MyApp.Accounts do
  use OmCrud.Context

  crud User                           # All CRUD functions
  crud Role, only: [:create, :fetch]  # Specific functions
end

# Generated functions:
MyApp.Accounts.create_user(attrs)
MyApp.Accounts.fetch_user(id)
MyApp.Accounts.update_user(user, attrs)
MyApp.Accounts.delete_user(user)
MyApp.Accounts.list_users(opts)
```

## Options

### Common Options

- `:repo` - Repository module (default: configured repo)
- `:prefix` - Schema prefix for multi-tenancy
- `:timeout` - Query timeout (default: 15_000ms)

### Write Options

- `:changeset` - Changeset function name (default: `:changeset`)
- `:returning` - Return inserted/updated record

### Bulk Options

- `:on_conflict` - Conflict handling (`:nothing`, `:replace_all`, etc.)
- `:conflict_target` - Columns for conflict detection
- `:placeholders` - Reduce data transfer for repeated values

```elixir
placeholders = %{now: DateTime.utc_now()}
entries = Enum.map(data, &Map.put(&1, :inserted_at, {:placeholder, :now}))
OmCrud.create_all(User, entries, placeholders: placeholders)
```

## Configuration

```elixir
# config/config.exs
config :om_crud,
  repo: MyApp.Repo,
  timeout: 30_000
```

## License

MIT
