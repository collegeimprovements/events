# OmSchema

Enhanced Ecto schema with inline validations, presets, field groups, and constraint declarations.

## Installation

```elixir
def deps do
  [{:om_schema, "~> 0.1.0"}]
end
```

## Why OmSchema?

OmSchema eliminates the disconnect between schema definitions and changesets:

```
Traditional Ecto                         OmSchema
───────────────────────────────          ──────────────────────────────
defmodule User do                        defmodule User do
  use Ecto.Schema                          use OmSchema

  schema "users" do                        schema "users" do
    field :email, :string                    field :email, :string,
    field :name, :string                       preset: email()
    field :age, :integer                     field :name, :string,
    field :status, :string                     required: true,
    # No validation hints                      min_length: 2,
                                               max_length: 100
    timestamps()                             field :age, :integer,
  end                                          min: 0, max: 150
                                             status_fields(values: [:active, :inactive])
  def changeset(user, attrs) do              timestamps()
    user                                   end
    |> cast(attrs, [:email, :name,
                    :age, :status])        def changeset(user, attrs) do
    |> validate_required([:email,            base_changeset(user, attrs)
                          :name])            |> unique_constraint(:email)
    |> validate_format(:email,             end
         ~r/^[^\s]+@[^\s]+$/)            end
    |> validate_length(:name,
         min: 2, max: 100)               # Field validations are:
    |> validate_number(:age,             # - Declared at definition
         min: 0, max: 150)               # - Auto-applied via base_changeset
    |> validate_inclusion(:status,       # - Introspectable at runtime
         [:active, :inactive])
    |> unique_constraint(:email)
  end
end
```

**Key Benefits:**
- **Self-documenting schemas** - Validation rules live with field definitions
- **Automatic changeset helpers** - `base_changeset/2` applies all validations
- **Field introspection** - Query required, immutable, sensitive fields at runtime
- **Presets** - Reusable validation patterns (email, slug, URL, etc.)
- **Constraint declarations** - Database constraints as schema metadata
- **Soft delete** - Built-in support with query helpers

---

## Quick Start

```elixir
defmodule MyApp.User do
  use OmSchema
  import OmSchema.Presets

  schema "users" do
    # Presets for common patterns
    field :email, :string, preset: email()
    field :username, :string, preset: username()
    field :password, :string, preset: password(), virtual: true

    # Inline validations
    field :name, :string, required: true, min_length: 2, max_length: 100
    field :age, :integer, min: 0, max: 150
    field :bio, :string, max_length: 1000

    # Behavioral options
    field :account_id, :binary_id, required: true, immutable: true
    field :api_key, :string, sensitive: true

    # Relationships with FK constraints
    belongs_to :organization, Organization, on_delete: :cascade

    # Field groups
    type_fields()
    status_fields(values: [:active, :suspended, :deleted], default: :active)
    audit_fields()
    soft_delete_field()
    timestamps()

    # Constraint declarations
    constraints do
      unique [:organization_id, :email], name: :users_org_email_idx
      check :valid_age, expr: "age >= 0 AND age <= 150"
    end
  end

  def changeset(user, attrs) do
    user
    |> base_changeset(attrs)
    |> unique_constraint(:email)
    |> unique_constraint([:organization_id, :email], name: :users_org_email_idx)
  end
end
```

---

## Enhanced Field Macro

### Validation Options

```elixir
field :email, :string,
  required: true,              # Adds to required fields list
  format: :email,              # Email format validation
  min_length: 5,               # Minimum string length
  max_length: 255,             # Maximum string length
  unique: true                 # Unique constraint

field :age, :integer,
  required: true,
  min: 0,                      # Minimum value
  max: 150,                    # Maximum value
  positive: true,              # Greater than 0
  non_negative: true           # Greater than or equal to 0

field :status, Ecto.Enum,
  values: [:active, :inactive],
  default: :active,
  required: true

field :tags, {:array, :string},
  min_length: 0,               # Minimum array length
  max_length: 20,              # Maximum array length
  unique_items: true           # No duplicates

field :metadata, :map,
  default: %{},
  max_keys: 100,               # Maximum map size
  required_keys: [:version],   # Keys that must be present
  forbidden_keys: [:internal]  # Keys that cannot be present
```

### Behavioral Options

```elixir
# Immutable - can be set on creation but not modified
field :account_id, :binary_id, required: true, immutable: true

# Sensitive - auto-redacted in logs, excluded from JSON
field :api_key, :string, sensitive: true
field :password_hash, :string, sensitive: true

# Documentation
field :email, :string,
  doc: "Primary contact email for the user",
  example: "user@example.com"

# Conditional required
field :phone, :string, required_when: [contact_method: :phone]
field :reason, :string, required_when: {:discount_percent, :gt, 0}
```

### Mappers (Transformations)

```elixir
# Transform values before validation
field :email, :string, mappers: [:trim, :downcase]
field :name, :string, mappers: [:trim, :titlecase]
field :slug, :string, mappers: [:trim, :slugify]
field :username, :string, mappers: [:trim, :downcase, :alphanumeric_only]
```

**Available Mappers:**
- `:trim` - Remove leading/trailing whitespace
- `:downcase` - Convert to lowercase
- `:upcase` - Convert to uppercase
- `:capitalize` - Capitalize first letter
- `:titlecase` - Title Case Each Word
- `:squish` - Collapse multiple spaces to single space
- `:slugify` - Convert to URL-safe slug
- `:digits_only` - Remove non-digit characters
- `:alphanumeric_only` - Remove non-alphanumeric characters
- `:strip_html` - Remove HTML tags

---

## Presets

Reusable validation patterns for common field types:

```elixir
import OmSchema.Presets

# String presets
field :email, :string, preset: email()
field :username, :string, preset: username()
field :password, :string, preset: password()
field :slug, :string, preset: slug()
field :phone, :string, preset: phone()
field :url, :string, preset: url()

# Number presets
field :quantity, :integer, preset: positive_integer()
field :price, :decimal, preset: money()
field :discount, :integer, preset: percentage()
field :age, :integer, preset: age()
field :rating, :integer, preset: rating()

# Location presets
field :lat, :float, preset: latitude()
field :lng, :float, preset: longitude()
field :country, :string, preset: country_code()
field :timezone, :string, preset: timezone()

# Network presets
field :ip, :string, preset: ipv4()
field :mac, :string, preset: mac_address()
field :domain, :string, preset: domain()

# Format presets
field :uuid, :string, preset: uuid()
field :color, :string, preset: hex_color()
field :version, :string, preset: semver()
field :mime, :string, preset: mime_type()
field :jwt, :string, preset: jwt()

# Financial presets
field :iban, :string, preset: iban()
field :btc, :string, preset: bitcoin_address()
field :eth, :string, preset: ethereum_address()
field :card, :string, preset: credit_card()
```

### Customizing Presets

```elixir
# Override preset defaults
field :username, :string, preset: username(min_length: 3, max_length: 20)

# Make preset optional
field :website, :string, preset: url(required: false)

# Add to preset
field :email, :string, preset: email(), unique: true
```

### All Available Presets

| Preset | Validations | Use Case |
|--------|-------------|----------|
| `email()` | format, max: 255, normalize | Email addresses |
| `username()` | min: 4, max: 30, alphanumeric | User handles |
| `password()` | min: 8, max: 128, no trim | Passwords |
| `slug()` | format, slugify | URL slugs |
| `phone()` | format, min: 10, max: 20 | Phone numbers |
| `url()` | format, max: 2048 | URLs |
| `uuid()` | format, normalize | UUID strings |
| `positive_integer()` | > 0, default: 0 | Counts, quantities |
| `money()` | >= 0, max: 999_999_999.99 | Prices, amounts |
| `percentage()` | 0-100 | Percentages |
| `age()` | 0-150, non-negative | Human ages |
| `rating()` | 1-5 | Star ratings |
| `latitude()` | -90 to 90 | Geographic lat |
| `longitude()` | -180 to 180 | Geographic lng |
| `country_code()` | 2-char uppercase | ISO 3166-1 |
| `language_code()` | format, 2-5 chars | ISO 639-1 |
| `currency_code()` | 3-char uppercase | ISO 4217 |
| `timezone()` | format, max: 50 | Timezone IDs |
| `ipv4()` | IP format | IPv4 addresses |
| `ipv6()` | IP format | IPv6 addresses |
| `mac_address()` | MAC format | Network MACs |
| `domain()` | domain format | Domain names |
| `hex_color()` | #RRGGBB format | Colors |
| `rgb_color()` | rgb() format | Colors |
| `semver()` | version format | Semantic versions |
| `jwt()` | JWT format | JSON Web Tokens |
| `base64()` | base64 format | Encoded data |
| `iban()` | IBAN format | Bank accounts |
| `bitcoin_address()` | BTC format | Crypto addresses |
| `ethereum_address()` | ETH format | Crypto addresses |
| `credit_card()` | card format | Credit cards |
| `ssn()` | SSN format | US SSN |
| `isbn()` | ISBN format | Book numbers |
| `social_handle()` | @handle format | Twitter/Instagram |
| `hashtag()` | #tag format | Hashtags |
| `file_path()` | path format | File paths |

---

## Field Groups

Commonly used field combinations with configurable options:

### `type_fields/1`

```elixir
# Add type and subtype fields
type_fields()

# Customize
type_fields(only: [:type])
type_fields(type: [required: true])
type_fields(type: [required: true], subtype: [cast: false])
```

### `status_fields/1`

```elixir
# Add status enum field
status_fields(values: [:active, :inactive], default: :active)

# Required status
status_fields(values: [:draft, :published, :archived], required: true)

# Non-castable (set programmatically)
status_fields(values: [:pending, :approved], cast: false)
```

### `audit_fields/1`

```elixir
# Add created_by_urm_id and updated_by_urm_id
audit_fields()

# Only track creation
audit_fields(only: [:created_by_urm_id])

# Required fields
audit_fields(created_by_urm_id: [required: true])
```

### `timestamps/1`

```elixir
# Add inserted_at and updated_at
timestamps()

# Only one timestamp
timestamps(only: [:updated_at])

# Custom type
timestamps(type: :naive_datetime)
```

### `metadata_field/1`

```elixir
# Add metadata JSONB field
metadata_field()

# With default
metadata_field(default: %{version: 1})
```

### `soft_delete_field/1`

```elixir
# Add deleted_at field
soft_delete_field()

# With deletion tracking (who deleted)
soft_delete_field(track_urm: true)
```

### `standard_fields/2` - All at Once

```elixir
# Add all standard fields
standard_fields(
  status: [values: [:active, :archived], default: :active]
)

# Select specific groups
standard_fields([:type, :status, :timestamps],
  status: [values: [:active, :inactive]]
)

# Exclude specific groups
standard_fields(except: [:audit])
```

---

## Changeset Helpers

### `base_changeset/3`

```elixir
def changeset(user, attrs) do
  user
  |> base_changeset(attrs)
  |> unique_constraint(:email)
end

# With options
base_changeset(user, attrs, also_required: [:password])
base_changeset(user, attrs, skip_required: [:email])
base_changeset(user, attrs, only_cast: [:name, :avatar])
base_changeset(user, attrs, check_immutable: true)
```

### Action-Specific Changesets

```elixir
@changeset_actions %{
  create: [also_required: [:password]],
  update: [skip_required: [:password], skip_cast: [:email]],
  profile: [only_cast: [:name, :avatar], only_required: []]
}

def changeset(user, attrs, action \\ :default) do
  base_changeset(user, attrs, action: action)
end

# Usage
User.changeset(user, attrs, :create)   # Requires password
User.changeset(user, attrs, :update)   # Skips password, can't change email
User.changeset(user, attrs, :profile)  # Only name and avatar
```

### Batch Constraints

```elixir
def changeset(user, attrs) do
  user
  |> base_changeset(attrs)
  |> unique_constraints([
    {:email, []},
    {:username, message: "is taken"},
    {[:org_id, :slug], name: :users_org_slug_idx}
  ])
  |> foreign_key_constraints([
    {:account_id, []},
    {:role_id, message: "invalid role"}
  ])
  |> check_constraints([
    {:age, name: :users_age_positive}
  ])
end
```

---

## Field Introspection

```elixir
# Lists of fields by category
User.cast_fields()            # Fields with cast: true
User.required_fields()        # Fields with required: true
User.immutable_fields()       # Fields with immutable: true
User.sensitive_fields()       # Fields with sensitive: true

# All field validations
User.field_validations()
# => [{:email, :string, [required: true, format: :email, ...]}, ...]

# Field documentation
User.field_docs()
# => %{email: %{doc: "Primary contact...", example: "user@example.com"}}

# Conditional required
User.conditional_required_fields()
# => [{:phone, [contact_method: :phone]}]
```

---

## Immutable Fields

```elixir
schema "users" do
  # Can be set on creation but not modified
  field :account_id, :binary_id, required: true, immutable: true
  field :created_at, :utc_datetime, immutable: true
end

def changeset(user, attrs) do
  user
  |> base_changeset(attrs, check_immutable: true)  # Enable check
end

# Or validate manually
def update_changeset(user, attrs) do
  user
  |> base_changeset(attrs)
  |> validate_immutable()  # Adds errors if immutable fields changed
end
```

---

## Conditional Required

```elixir
schema "orders" do
  field :contact_method, Ecto.Enum, values: [:email, :phone, :sms]

  # Required when contact_method is :phone
  field :phone, :string, required_when: [contact_method: :phone]

  # Required when discount > 0
  field :reason, :string, required_when: {:discount_percent, :gt, 0}

  # Complex condition with AND
  field :address, :map, required_when: [
    [type: :physical], :and, {:needs_shipping, :truthy}
  ]

  # Complex condition with OR
  field :notification_target, :string, required_when: [
    [notify_sms: true], :or, [notify_call: true]
  ]

  # Negation
  field :explanation, :string, required_when: {:not, [status: :approved]}
end

def changeset(order, attrs) do
  order
  |> base_changeset(attrs, check_conditional_required: true)
end
```

### Conditional DSL Reference

| Syntax | Meaning |
|--------|---------|
| `[field: value]` | field equals value |
| `{:field, :gt, value}` | field > value |
| `{:field, :gte, value}` | field >= value |
| `{:field, :lt, value}` | field < value |
| `{:field, :lte, value}` | field <= value |
| `{:field, :in, [values]}` | field in list |
| `{:field, :truthy}` | field is truthy |
| `{:field, :blank}` | field is nil or "" |
| `[[a], :and, [b]]` | a AND b |
| `[[a], :or, [b]]` | a OR b |
| `{:not, [condition]}` | NOT condition |

---

## Status Transitions

```elixir
@status_transitions %{
  active: [:suspended, :deleted],
  suspended: [:active, :deleted],
  deleted: []  # terminal - no transitions
}

def changeset(user, attrs) do
  user
  |> base_changeset(attrs)
  |> validate_transition(:status, @status_transitions)
end

# With custom message
|> validate_transition(:status, @status_transitions,
     message: "cannot change from %{from} to %{to}")

# Multiple transition fields
@order_transitions %{
  pending: [:processing, :cancelled],
  processing: [:shipped, :cancelled],
  shipped: [:delivered, :returned],
  delivered: [],
  cancelled: [],
  returned: :any  # can go to any state
}

def changeset(order, attrs) do
  order
  |> base_changeset(attrs)
  |> validate_transition(:order_status, @order_transitions)
end
```

---

## Slug Generation

```elixir
def changeset(post, attrs) do
  post
  |> base_changeset(attrs)
  |> maybe_put_slug(from: :title)
  |> unique_constraint(:slug)
end

# Custom target field
|> maybe_put_slug(from: :name, to: :url_slug)

# With uniqueness suffix (Medium-style)
|> maybe_put_slug(from: :title, uniquify: true)
# "my-post" -> "my-post-a1b2c3d4"
```

---

## Soft Delete

When using `soft_delete_field()`, these helpers are auto-generated:

```elixir
schema "users" do
  # ...
  soft_delete_field(track_urm: true)
end

# Check if deleted
User.deleted?(user)
# => true/false

# Soft delete
user
|> User.soft_delete_changeset()
|> Repo.update()

# With who deleted
user
|> User.soft_delete_changeset(deleted_by_urm_id: admin.id)
|> Repo.update()

# Restore
user
|> User.restore_changeset()
|> Repo.update()

# Query helpers
User.not_deleted()           # Excludes deleted (default)
User.only_deleted()          # Only deleted
User.with_deleted()          # All records

# Combine with queries
from(u in User, where: u.status == :active)
|> User.not_deleted()
|> Repo.all()
```

---

## Constraint Declarations

### In Schema Block

```elixir
schema "users" do
  field :email, :string, unique: true
  belongs_to :account, Account, on_delete: :cascade

  constraints do
    # Composite unique
    unique [:account_id, :email], name: :users_account_email_idx

    # Check constraints
    check :valid_age, expr: "age >= 0 AND age <= 150"
    check :email_format, expr: "email LIKE '%@%'"

    # Exclusion constraints
    exclude :no_overlapping_ranges,
      using: :gist,
      elements: [{"daterange(start_date, end_date)", "&&"}]
  end
end
```

### Constraint Introspection

```elixir
User.__constraints__()
# %{
#   unique: [%{name: :users_email_key, fields: [:email], ...}],
#   foreign_key: [%{name: :users_account_id_fkey, field: :account_id, ...}],
#   check: [%{name: :users_valid_age, expr: "age >= 0 AND age <= 150"}],
#   exclude: [...],
#   primary_key: %{fields: [:id], name: :users_pkey}
# }

User.__indexes__()
# [%{name: :users_email_key, fields: [:email], unique: true}, ...]

User.unique_constraints()
User.foreign_keys()
User.check_constraints()
```

---

## Associations with FK Tracking

```elixir
schema "memberships" do
  # FK with cascade delete
  belongs_to :account, Account, on_delete: :cascade

  # Full constraint options
  belongs_to :user, User,
    constraint: [
      on_delete: :nilify_all,
      deferrable: :initially_deferred
    ]

  # Skip FK validation (polymorphic)
  belongs_to :commentable, Commentable, constraint: false
end

# has_many with FK expectations
schema "accounts" do
  has_many :memberships, Membership

  # Expect specific on_delete behavior
  has_many :roles, Role, expect_on_delete: :cascade

  # Skip FK validation (through associations)
  has_many :users, through: [:memberships, :user]
end

# Introspect FK expectations
Account.has_many_expectations()
# [%{assoc_name: :roles, related: Role, expect_on_delete: :cascade}, ...]
```

---

## Deletion Impact Preview

Before deleting a record, preview what will be affected:

```elixir
# Count immediate associations
impact = OmSchema.deletion_impact(account)
# %{"memberships" => 5, "roles" => 3}

# Traverse deeper
impact = OmSchema.deletion_impact(account, depth: 2)
# %{
#   "memberships" => 5,
#   "roles" => 3,
#   "roles.permissions" => 12
# }

# Format for display
OmSchema.format_deletion_impact(impact)
# => "3 roles, 5 memberships, 12 roles.permissions"

# Usage in controller
def delete(conn, %{"id" => id}) do
  account = Accounts.get!(id)
  impact = OmSchema.deletion_impact(account, repo: Repo, depth: 2)

  if map_size(impact) > 0 do
    render(conn, "confirm_delete.html",
      account: account,
      impact: OmSchema.format_deletion_impact(impact)
    )
  else
    Accounts.delete!(account)
    redirect(conn, to: ~p"/accounts")
  end
end
```

---

## Real-World Examples

### User Schema

```elixir
defmodule MyApp.Accounts.User do
  use OmSchema
  import OmSchema.Presets

  @status_transitions %{
    active: [:suspended, :deleted],
    suspended: [:active, :deleted],
    deleted: []
  }

  schema "users" do
    field :email, :string, preset: email(), unique: true
    field :username, :string, preset: username(), unique: true
    field :password, :string, preset: password(), virtual: true
    field :password_hash, :string, sensitive: true

    field :name, :string, required: true, min_length: 2, max_length: 100
    field :bio, :string, max_length: 1000
    field :phone, :string, preset: phone(required: false)

    belongs_to :organization, Organization, on_delete: :nilify_all
    has_many :posts, Post
    has_many :comments, Comment

    status_fields(values: [:active, :suspended, :deleted], default: :active)
    audit_fields()
    soft_delete_field(track_urm: true)
    timestamps()

    constraints do
      unique [:organization_id, :email], name: :users_org_email_idx
    end
  end

  @changeset_actions %{
    create: [also_required: [:password]],
    update: [skip_cast: [:email, :password]],
    profile: [only_cast: [:name, :bio, :phone], only_required: []]
  }

  def changeset(user, attrs, action \\ :default) do
    user
    |> base_changeset(attrs, action: action, check_immutable: true)
    |> maybe_hash_password()
    |> validate_transition(:status, @status_transitions)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint([:organization_id, :email], name: :users_org_email_idx)
  end

  defp maybe_hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end
end
```

### Order Schema

```elixir
defmodule MyApp.Commerce.Order do
  use OmSchema
  import OmSchema.Presets

  @order_transitions %{
    pending: [:processing, :cancelled],
    processing: [:shipped, :cancelled],
    shipped: [:delivered, :returned],
    delivered: [:returned],
    cancelled: [],
    returned: []
  }

  schema "orders" do
    field :order_number, :string, required: true, unique: true
    field :total_amount, :decimal, preset: money()
    field :discount_percent, :integer, preset: percentage()
    field :discount_reason, :string, required_when: {:discount_percent, :gt, 0}

    field :contact_method, Ecto.Enum, values: [:email, :phone, :sms]
    field :phone, :string, preset: phone(required: false),
      required_when: [[contact_method: :phone], :or, [contact_method: :sms]]

    field :notes, :string, max_length: 2000
    field :metadata, :map, default: %{}

    belongs_to :customer, Customer
    belongs_to :shipping_address, Address, on_delete: :nothing
    has_many :line_items, LineItem, on_delete: :delete_all

    field :order_status, Ecto.Enum,
      values: [:pending, :processing, :shipped, :delivered, :cancelled, :returned],
      default: :pending

    type_fields(only: [:type])
    audit_fields()
    soft_delete_field()
    timestamps()
  end

  def changeset(order, attrs) do
    order
    |> base_changeset(attrs, check_conditional_required: true)
    |> validate_transition(:order_status, @order_transitions)
    |> unique_constraint(:order_number)
    |> foreign_key_constraint(:customer_id)
  end

  def cancel_changeset(order) do
    order
    |> change(order_status: :cancelled)
    |> validate_transition(:order_status, @order_transitions)
  end
end
```

### Post with Slug

```elixir
defmodule MyApp.Blog.Post do
  use OmSchema

  schema "posts" do
    field :title, :string, required: true, min_length: 3, max_length: 200
    field :slug, :string, required: true, unique: true, format: :slug
    field :body, :string, required: true, min_length: 100
    field :excerpt, :string, max_length: 300
    field :published_at, :utc_datetime

    field :tags, {:array, :string},
      default: [],
      max_length: 10,
      unique_items: true

    belongs_to :author, User

    status_fields(values: [:draft, :published, :archived], default: :draft)
    metadata_field()
    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> base_changeset(attrs)
    |> maybe_put_slug(from: :title, uniquify: true)
    |> maybe_set_published_at()
    |> unique_constraint(:slug)
  end

  defp maybe_set_published_at(changeset) do
    if get_change(changeset, :status) == :published do
      put_change(changeset, :published_at, DateTime.utc_now())
    else
      changeset
    end
  end
end
```

---

## Configuration

```elixir
# config/config.exs
config :om_schema,
  default_repo: MyApp.Repo
```

---

## Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:om_schema, :changeset, :start]` | `%{system_time: ...}` | `%{schema: ..., action: ...}` |
| `[:om_schema, :changeset, :stop]` | `%{duration: ...}` | `%{schema: ..., valid: bool}` |
| `[:om_schema, :validation, :error]` | `%{count: ...}` | `%{schema: ..., errors: ...}` |

---

## Best Practices

### 1. Use Presets for Common Patterns

```elixir
# Good - clear intent
field :email, :string, preset: email()

# Less clear
field :email, :string, required: true, format: ~r/.../, max_length: 255
```

### 2. Declare Validations at Definition

```elixir
# Good - self-documenting
field :age, :integer, min: 0, max: 150

# Less discoverable
def changeset(user, attrs) do
  # ... validation hidden here
  |> validate_number(:age, greater_than_or_equal_to: 0)
end
```

### 3. Use Action-Specific Changesets

```elixir
# Good - explicit actions
@changeset_actions %{
  create: [also_required: [:password]],
  update: [skip_required: [:password]]
}

# Less clear - multiple changeset functions
def create_changeset(...), do: ...
def update_changeset(...), do: ...
```

### 4. Declare Constraints in Schema

```elixir
# Good - constraints visible with schema
constraints do
  unique [:org_id, :email], name: :users_org_email_idx
end

# Less visible - scattered in changeset
|> unique_constraint([:org_id, :email], name: :users_org_email_idx)
```

### 5. Use Immutable for Key Fields

```elixir
# Good - prevent accidental changes
field :account_id, :binary_id, required: true, immutable: true
field :created_at, :utc_datetime, immutable: true
```

---

## License

MIT
