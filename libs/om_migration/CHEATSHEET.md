# OmMigration Cheatsheet

> Pipeline-based Ecto migrations with composable field helpers. For full docs, see `README.md`.

## Quick Start

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use OmMigration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_identity([:name, :email])
    |> with_authentication()
    |> with_audit()
    |> with_soft_delete()
    |> with_timestamps()
    |> with_index(:email, unique: true)
    |> run()
  end
end
```

---

## Primary Keys

```elixir
|> with_uuid_primary_key()           # UUIDv7 (recommended)
|> with_uuid_v4_primary_key()        # UUID v4 (legacy)
|> with_bigint_primary_key()         # auto-increment
```

---

## Fields

```elixir
|> with_fields(
  name: :string,
  description: :text,
  price: :decimal,
  quantity: :integer,
  active: :boolean,
  published_at: :utc_datetime
)
```

---

## Identity

```elixir
|> with_identity(:name)              # first_name, last_name, display_name, full_name
|> with_identity(:email)             # email (citext, unique index)
|> with_identity(:username)          # username (citext, unique index)
|> with_identity(:phone)             # phone
|> with_identity([:name, :email, :phone])  # multiple
```

---

## Authentication

```elixir
|> with_authentication()             # password (default)
|> with_authentication(type: :oauth) # OAuth provider fields
|> with_authentication(type: :magic_link)
```

| Type | Fields |
|------|--------|
| `:password` | `password_hash`, `confirmed_at`, tokens, `failed_attempts`, `locked_at` |
| `:oauth` | `provider`, `provider_id`, tokens, `provider_token_expires_at` |
| `:magic_link` | `magic_token`, `magic_token_sent_at`, `magic_token_expires_at` |

---

## Field Groups

```elixir
|> with_type_fields()                # type, subtype
|> with_status_fields()              # status, substatus
|> with_status(values: ["draft", "active"], default: "draft")  # with CHECK constraint
|> with_status_fields(with_transition: true)  # + previous_status, status_changed_at
|> with_audit()                      # created_by_urm_id, updated_by_urm_id
|> with_audit(track_user: true, track_ip: true)
|> with_soft_delete()                # deleted_at
|> with_soft_delete(track_reason: true, track_user: true)
|> with_timestamps()                 # inserted_at, updated_at
|> with_timestamps(with_lifecycle: true)  # + published_at, archived_at, expires_at
|> with_metadata()                   # JSONB metadata field + GIN index
|> with_metadata(name: :properties)  # custom name
|> with_settings()                   # alias for metadata(name: :settings)
|> with_tags()                       # array field + GIN index
```

---

## Profile

```elixir
|> with_profile(:bio)                # bio (text)
|> with_profile(:avatar)             # avatar_url, avatar_thumbnail_url
|> with_profile(:location)           # address + geo fields
|> with_profile([:bio, :avatar, :location])
```

---

## Money

```elixir
|> with_money(:total)                # decimal(10, 2)
|> with_money([:subtotal, :tax, :shipping, :total])
```

---

## Relationships

```elixir
|> with_belongs_to(:user)            # user_id + FK index
|> with_belongs_to(:category)
|> with_belongs_to(:user, :author)   # author_id -> users
```

---

## Indexes

```elixir
|> with_index(:email)
|> with_index(:email, unique: true)
|> with_index([:org_id, :name], unique: true)
|> with_index(:status, where: "deleted_at IS NULL")  # partial
|> with_index(:metadata, using: :gin)
```

### Standalone Index

```elixir
create_index(:users, [:email])
|> unique()
|> where("deleted_at IS NULL")
|> run()
```

---

## Pre-built Field Sets

```elixir
Fields.address_fields()              # street, city, state, postal_code, country
Fields.address_fields(prefix: :billing)
Fields.geo_fields()                  # latitude, longitude
Fields.contact_fields()              # email, phone, mobile, fax
Fields.social_fields()               # website, twitter, facebook, etc.
Fields.seo_fields()                  # meta_title, meta_description, og_*
Fields.file_fields(:avatar)          # avatar_url, avatar_key
Fields.file_fields(:doc, with_metadata: true)  # + name, size, content_type
Fields.counter_fields([:views_count, :likes_count])  # integer, default: 0
Fields.money_fields([:price, :tax])  # decimal(10, 2)
```

---

## Full Examples

### E-commerce Order

```elixir
create_table(:orders)
|> with_uuid_primary_key()
|> with_belongs_to(:user)
|> with_fields(order_number: :string, currency: :string)
|> with_money([:subtotal, :tax, :shipping, :total])
|> with_status(values: ["pending", "confirmed", "shipped", "delivered", "cancelled"])
|> with_status_fields(with_transition: true)
|> with_metadata()
|> with_audit()
|> with_soft_delete()
|> with_timestamps()
|> with_index(:order_number, unique: true)
|> with_index([:user_id, :status])
|> run()
```

### CMS Article

```elixir
create_table(:articles)
|> with_uuid_primary_key()
|> with_belongs_to(:author)
|> with_belongs_to(:category)
|> with_fields(title: :string, slug: :string, body: :text, published_at: :utc_datetime)
|> with_tags()
|> with_status(values: ["draft", "review", "published", "archived"])
|> with_metadata()
|> with_audit()
|> with_soft_delete()
|> with_timestamps()
|> with_index(:slug, unique: true)
|> with_index(:published_at)
|> run()
```

---

## Utilities

```elixir
|> maybe(&with_soft_delete/1, opts[:soft_delete])  # conditional
|> tap_inspect("After PK")                         # debug
|> validate!()                                      # raises if invalid
```
