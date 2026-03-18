# OmSchema Cheatsheet

> Enhanced Ecto schema with inline validations, presets, and field groups. For full docs, see `README.md`.

## Setup

```elixir
defmodule MyApp.User do
  use OmSchema
  import OmSchema.Presets
  import OmSchema.FieldHelpers
end
```

---

## Schema Definition

```elixir
defmodule MyApp.User do
  use OmSchema
  import OmSchema.Presets
  import OmSchema.FieldHelpers

  schema "users" do
    # Inline validation via options
    field :name, :string, required: true, min_length: 2, max_length: 100
    field :email, :string, required: true, format: :email, unique: true
    field :age, :integer, min: 0, max: 150
    field :role, :string, in: ["admin", "user", "mod"]

    # Presets (pre-configured validation bundles)
    field :username, :string, preset: username()
    field :website, :string, preset: url()
    field :phone_number, :string, preset: phone()
    field :api_key, :string, sensitive: true

    # Immutable (cannot change after create)
    field :account_id, :binary_id, required: true, immutable: true

    # Mappers (normalize on cast)
    field :slug, :string, mappers: [:trim, :downcase, :slugify]
    field :display_name, :string, normalize: :squish

    # Relationships
    belongs_to :organization, Organization
    has_many :posts, Post

    # Field groups
    type_fields()
    status_fields(values: [:active, :suspended, :deleted], default: :active)
    audit_fields()
    soft_delete_field()
    timestamps()
    metadata_field()
  end

  constraints do
    unique [:organization_id, :email], name: :users_org_email_idx
    check :valid_age, expr: "age >= 0 AND age <= 150"
    foreign_key :organization_id, references: :organizations
  end
end
```

---

## Field Options

| Option | Type | Effect |
|--------|------|--------|
| `required: true` | boolean | Required in changeset |
| `format: :email` | atom/regex | Format validation |
| `min_length: n` | integer | Minimum string length |
| `max_length: n` | integer | Maximum string length |
| `length: n` | integer | Exact length |
| `min: n` | number | Minimum numeric value |
| `max: n` | number | Maximum numeric value |
| `positive: true` | boolean | Must be > 0 |
| `non_negative: true` | boolean | Must be >= 0 |
| `in: [...]` | list | Inclusion validation |
| `not_in: [...]` | list | Exclusion validation |
| `unique: true` | boolean | Unique constraint |
| `immutable: true` | boolean | Cannot change after create |
| `sensitive: true` | boolean | Redacted in logs/inspect |
| `mappers: [...]` | list | Normalization pipeline |
| `normalize: :trim` | atom/list | Alias for mappers |
| `preset: email()` | preset | Pre-configured validation |
| `doc: "..."` | string | Field documentation |
| `example: "..."` | string | Example value |
| `required_when: ...` | DSL | Conditional requirement |

---

## Presets

```elixir
import OmSchema.Presets

# String presets
email()           # format: :email
username()        # alphanumeric 3-30
password()        # min 8 chars
slug()            # URL-safe
phone()           # phone format
url()             # URL format
uuid()            # UUID format
social_handle()   # @handle format
hashtag()         # #tag format
file_path()       # file path format

# Location presets
latitude()        # -90..90
longitude()       # -180..180
country_code()    # ISO 3166 alpha-2
language_code()   # ISO 639
timezone()        # IANA timezone

# Financial presets
money()           # decimal, non-negative
percentage()      # 0..100
positive_integer()
credit_card()
iban()

# Format presets
hex_color()       # #RRGGBB
semver()          # 1.2.3
mime_type()       # type/subtype
jwt()             # JSON Web Token
base64()

# Specialized
age()             # 0..150
rating()          # 1..5
zip_code()
tags()            # list of strings
metadata()        # JSONB map
timestamp()       # UTC datetime
```

---

## Field Helpers (Macros)

```elixir
import OmSchema.FieldHelpers

email_field :email, unique: true
name_field :name, required: true
full_name_field :full_name
title_field :title, max_length: 200
text_field :bio, max_length: 500
slug_field :slug
username_field :username
phone_field :phone
url_field :website
date_field :start_date
birth_date_field :dob
datetime_field :published_at
timestamp_field :expires_at
```

---

## Field Groups

```elixir
# Type & status
type_fields()                                    # type, subtype
status_fields(values: [:active, :pending], default: :active)

# Audit trail
audit_fields()                                   # created_by, updated_by
audit_fields(track_urm: true, track_ip: true)

# Timestamps
timestamps()                                     # inserted_at, updated_at
timestamps(type: :utc_datetime)

# Extras
metadata_field()                                 # JSONB metadata
soft_delete_field()                              # deleted_at
soft_delete_field(track_urm: true, track_reason: true)

# All at once
standard_fields([:type, :status, :audit, :timestamps, :metadata])
standard_fields([:timestamps, :audit], except: [:metadata])
```

---

## Changesets

```elixir
# Base changeset (auto-casts, validates, applies mappers)
def changeset(struct, attrs) do
  base_changeset(struct, attrs)
end

# Action-specific
@changeset_actions %{
  create: [also_required: [:password]],
  update: [skip_cast: [:email], skip_required: [:password]],
  profile: [only_cast: [:name, :bio], only_required: []]
}

def changeset(struct, attrs, action \\ :default) do
  base_changeset(struct, attrs, action: action)
end

# Options
base_changeset(struct, attrs,
  action: :create,           # action-specific rules
  also_required: [:field],   # add to required
  skip_required: [:field],   # remove from required
  only_cast: [:field],       # cast only these
  skip_cast: [:field],       # skip casting these
  only_required: [:field],   # only these required
  check_immutable: true,     # validate immutable fields
  check_conditional_required: true
)
```

---

## Mappers

```elixir
# Applied during cast via mappers: option
field :name, :string, mappers: [:trim, :squish]
field :email, :string, mappers: [:trim, :downcase]
field :slug, :string, mappers: [:trim, :downcase, :slugify]
field :code, :string, mappers: [:trim, :upcase, :digits_only]

# Available mappers
:trim              # remove whitespace
:downcase          # lowercase
:upcase            # uppercase
:capitalize        # capitalize first
:titlecase         # capitalize each word
:squish            # trim + collapse spaces
:slugify           # URL-safe slug
:digits_only       # remove non-digits
:alphanumeric_only # remove non-alphanumeric
```

---

## Conditional Required

```elixir
# Simple equality
field :phone, :string, required_when: [contact_method: :phone]

# Comparison
field :reason, :string, required_when: {:discount_percent, :gt, 0}

# AND / OR
field :address, :map,
  required_when: [[type: :physical], :and, {:needs_shipping, :truthy}]

field :target, :string,
  required_when: [[notify_sms: true], :or, [notify_call: true]]

# Negation
field :explanation, :string, required_when: {:not, [status: :approved]}

# Operators: :gt, :gte, :lt, :lte, :in, :not_in, :truthy, :falsy, :present, :blank
```

---

## Constraints

```elixir
constraints do
  unique [:email], name: :users_email_idx
  unique [:org_id, :email], name: :users_org_email_idx, where: "deleted_at IS NULL"
  foreign_key :org_id, references: :organizations, on_delete: :restrict
  check :valid_age, expr: "age >= 0 AND age <= 150"
  index [:status, :inserted_at]
  exclude [:date_range], using: :gist
end
```

---

## Status Transitions

```elixir
@status_transitions %{
  active: [:suspended, :deleted],
  suspended: [:active, :deleted],
  deleted: []                        # terminal state
}

def changeset(record, attrs) do
  record
  |> base_changeset(attrs)
  |> validate_transition(:status, @status_transitions)
end
```

---

## Slug Generation

```elixir
def changeset(post, attrs) do
  post
  |> base_changeset(attrs)
  |> maybe_put_slug(from: :title)
  |> maybe_put_slug(from: :title, to: :url_slug)
  |> maybe_put_slug(from: :title, uniquify: true)
  |> unique_constraint(:slug)
end
```

---

## Soft Delete

```elixir
# Auto-generated when using soft_delete_field()
User.deleted?(user)                              #=> true/false
User.soft_delete_changeset(user)
User.soft_delete_changeset(user, deleted_by_urm_id: admin_id)
User.restore_changeset(user)

# Query helpers
User.not_deleted()                               # exclude deleted
User.only_deleted()                              # only deleted
User.with_deleted()                              # all records
```

---

## Cross-Field Validation

```elixir
alias OmSchema.Validation

changeset
|> Validation.validate_comparison(:start_date, :<=, :end_date)
|> Validation.validate_exclusive([:email, :phone], at_least_one: true)
|> Validation.validate_confirmation(:password, :password_confirmation)
|> Validation.validate_if(:backup_email, :email, &use_backup?/1)
|> Validation.validate_unless(:password, :required, &oauth_user?/1)
```

---

## Introspection

```elixir
User.cast_fields()                               # castable fields
User.required_fields()                           # required fields
User.immutable_fields()                          # immutable fields
User.sensitive_fields()                          # sensitive fields
User.field_validations()                         # all field specs
User.field_docs()                                # documentation map
User.__constraints__()                           # constraint metadata
```

---

## Error Formatting

```elixir
alias OmSchema.Errors

Errors.prioritize(changeset)                     # sorted by severity
Errors.to_simple_map(changeset)                  #=> %{email: ["invalid"]}
Errors.to_flat_list(changeset)                   #=> ["Email: invalid"]
Errors.to_message(changeset)                     # user-friendly string
Errors.for_field(changeset, :email)              # errors for field
Errors.has_error?(changeset, :email, :format)    # check specific error
Errors.count_errors(changeset)                   # total count
```

---

## OpenAPI / JSON Schema

```elixir
OmSchema.OpenAPI.to_schema(User)                 # OpenAPI 3.x schema
OmSchema.OpenAPI.to_components([User, Account])   # multiple schemas
OmSchema.Introspection.to_json_schema(User)       # JSON Schema
OmSchema.Introspection.inspect_schema(User)       # detailed inspection
```

---

## Deletion Impact

```elixir
impact = OmSchema.deletion_impact(account)
#=> %{"memberships" => 5, "roles" => 3}

impact = OmSchema.deletion_impact(account, depth: 2)
OmSchema.format_deletion_impact(impact)
#=> "5 memberships, 3 roles, 12 roles.permissions"
```
