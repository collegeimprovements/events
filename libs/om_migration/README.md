# OmMigration

Pipeline-based Ecto migrations with composable field helpers.

## Installation

```elixir
def deps do
  [{:om_migration, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use OmMigration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_fields(
      email: :string,
      name: :string,
      age: :integer
    )
    |> with_authentication()      # password_hash, confirmed_at, etc.
    |> with_audit()               # created_by_id, updated_by_id
    |> with_soft_delete()         # deleted_at
    |> with_timestamps()
    |> with_index(:email, unique: true)
    |> execute()
  end
end
```

## Pipeline API

### Table Creation

```elixir
create_table(:users)
|> with_uuid_primary_key()        # UUIDv7 primary key
|> with_bigint_primary_key()      # Bigint primary key
```

### Field Helpers

```elixir
|> with_fields(email: :string, age: :integer)
|> with_identity(:name, :email)   # Identity fields
|> with_profile(:bio, :avatar)    # Profile fields
```

### Common Patterns

```elixir
|> with_authentication()          # password_hash, confirmed_at, remember_token
|> with_oauth()                   # provider, provider_id, access_token
|> with_audit()                   # created_by_id, updated_by_id
|> with_soft_delete()             # deleted_at
|> with_type_fields()             # type, subtype
|> with_status_field()            # status
|> with_metadata()                # metadata :map
|> with_timestamps()              # inserted_at, updated_at
```

### Indexes

```elixir
|> with_index(:email)
|> with_index(:email, unique: true)
|> with_index([:org_id, :name], unique: true)
|> with_index(:status, where: "deleted_at IS NULL")
```

### Foreign Keys

```elixir
|> with_belongs_to(:organization)
|> with_belongs_to(:user, :owner)  # Custom column name
```

## DSL Enhanced

For more control, use the enhanced DSL directly:

```elixir
defmodule MyApp.Repo.Migrations.CreatePosts do
  use OmMigration

  def change do
    create table(:posts, primary_key: false) do
      uuid_primary_key()

      field :title, :string, null: false
      field :body, :text
      field :published_at, :utc_datetime

      belongs_to :author, :users, type: :binary_id

      type_fields()
      status_field(values: [:draft, :published])
      soft_delete()
      timestamps()
    end

    unique_index(:posts, [:author_id, :title], where: "deleted_at IS NULL")
  end
end
```

## Help

```elixir
OmMigration.Help.show()           # General help
OmMigration.Help.show(:fields)    # Field helpers
OmMigration.Help.show(:examples)  # Complete examples
```

## License

MIT
