defmodule Events.Repo.MigrationMacros do
  @moduledoc """
  Reusable macros for standardized database migrations with UUIDv7 primary keys.

  This module provides a consistent API for adding common field patterns to database tables,
  with PostgreSQL 18's native UUIDv7 support for time-ordered, indexable primary keys.

  ## Quick Start

      defmodule Events.Repo.Migrations.CreateProducts do
        use Ecto.Migration
        import Events.Repo.MigrationMacros

        def change do
          create table(:products) do
            add :name, :citext, null: false
            add :price, :decimal, null: false

            type_fields()
            metadata_field()
            audit_fields()
            timestamps()
          end

          create unique_index(:products, [:slug])
        end
      end

  **Note**: Requires citext extension. Run this migration first:

      defmodule Events.Repo.Migrations.EnableCitext do
        use Ecto.Migration

        def up do
          execute "CREATE EXTENSION IF NOT EXISTS citext"
        end

        def down do
          execute "DROP EXTENSION IF EXISTS citext"
        end
      end

  ## Architecture Overview

  ### UUIDv7 by Default
  All tables automatically use UUIDv7 primary keys unless explicitly opted out:
  - **Time-ordered**: UUIDs are sortable by creation time
  - **Index-friendly**: Better B-tree performance than UUIDv4
  - **PostgreSQL 18**: Uses native `uuidv7()` function

  ### Field Categories
  1. **Type Classification**: `type` and `subtype` for polymorphic entities
  2. **Metadata Storage**: JSONB field for flexible schema extensions
  3. **Audit Tracking**: References to user_role_mappings for change tracking
  4. **Soft Delete**: `deleted_at` and `deleted_by_urm_id` for paranoid deletion
  5. **Timestamps**: UTC microsecond precision with PostgreSQL defaults

  ## Available Macros

  | Macro | Purpose | Example |
  |-------|---------|---------|
  | `table/2` | Override Ecto's table with UUIDv7 | `create table(:users) do ... end` |
  | `type_fields/0, type_fields/1` | Add type/subtype columns | `type_fields(null: false)` |
  | `metadata_field/0, metadata_field/1` | Add JSONB metadata | `metadata_field(default: fragment("'{}'"))` |
  | `audit_fields/0, audit_fields/1` | Add created_by/updated_by | `audit_fields()` |
  | `deleted_fields/0, deleted_fields/1` | Add soft delete fields | `deleted_fields()` |
  | `timestamps/0` | Add inserted_at/updated_at | `timestamps()` |
  | `standard_entity_fields/0, standard_entity_fields/1` | All-in-one standard fields | `standard_entity_fields()` |

  ## Design Patterns

  ### Pattern 1: Simple Entity
      create table(:categories) do
        add :name, :citext, null: false
        add :slug, :citext, null: false

        timestamps()
      end

  ### Pattern 2: Typed Entity with Metadata
      create table(:events) do
        add :title, :citext, null: false

        type_fields(type_default: "conference")
        metadata_field()
        timestamps()
      end

  ### Pattern 3: Full Audited Entity
      create table(:accounts) do
        standard_entity_fields(status_default: "pending")

        add :balance, :decimal
        add :currency, :string, default: "USD"
      end

  ### Pattern 4: Legacy Integer Primary Keys
      create table(:legacy_data, primary_key: true) do
        add :value, :string
        timestamps()
      end

  ### Pattern 5: Join Table (No Primary Key)
      create table(:users_roles, primary_key: false) do
        add :user_id, references(:users, type: :uuid), null: false
        add :role_id, references(:roles, type: :uuid), null: false

        audit_fields()
        timestamps()
      end

  ### Pattern 6: Entity with Soft Delete
      create table(:documents) do
        add :title, :citext, null: false
        add :content, :text

        type_fields()
        metadata_field()
        audit_fields()
        deleted_fields()  # Soft delete support
        timestamps()
      end

      # Indexes for soft delete queries
      create index(:documents, [:deleted_at])
      create index(:documents, [:status], where: "deleted_at IS NULL")

  ## Migration Dependencies

  ### Phase 1: Core Tables (Without Audit FK Constraints)
      # Create user_role_mappings first without audit fields to avoid circular dependency
      create table(:user_role_mappings) do
        add :user_id, references(:users, type: :uuid)
        add :role_id, references(:roles, type: :uuid)
        timestamps()
      end

  ### Phase 2: Tables with Audit References
      # Now can reference user_role_mappings (default behavior)
      create table(:products) do
        audit_fields()  # Includes FK constraints by default
      end

  ### Phase 3: Special Cases Needing references: false
      # Only use when table needs to be created before user_role_mappings
      create table(:special_table) do
        audit_fields(references: false)  # No FK constraints
      end

  ## Best Practices

  1. **Always add indexes** for foreign keys and frequently queried fields
  2. **Use unique constraints** for business keys like slugs
  3. **Consider partial indexes** for status fields
  4. **Add check constraints** for business rules
  5. **Use meaningful defaults** aligned with your domain

  ## Examples

      # Comprehensive entity with all features
      create table(:subscriptions) do
        add :user_id, references(:users, type: :uuid), null: false

        type_fields(type_default: "monthly", null: false)
        metadata_field()
        audit_fields(null: false)  # FK references are default
        timestamps()

        add :status, :string, default: "active", null: false
        add :expires_at, :utc_datetime_usec
      end

      create index(:subscriptions, [:user_id])
      create index(:subscriptions, [:type])
      create index(:subscriptions, [:status])
      create index(:subscriptions, [:expires_at], where: "status = 'active'")
  """

  # ==============================================================================
  # PUBLIC API - Table Definition
  # ==============================================================================

  @doc """
  Creates a table with UUIDv7 primary key by default.

  This macro overrides Ecto's `table/2` to automatically configure PostgreSQL 18's
  native `uuidv7()` function for primary keys, providing time-ordered UUIDs with
  better index performance.

  ## Options

  All standard Ecto.Migration.table/2 options are supported, plus:
  - `:primary_key` - Primary key configuration (see below)

  ## Primary Key Behavior

  | Value | Behavior |
  |-------|----------|
  | `nil` (default) | UUIDv7 primary key named `:id` |
  | `:uuid_v7` | Explicitly request UUIDv7 |
  | `false` | No primary key (for join tables) |
  | `true` | Integer primary key (Ecto default) |
  | `{:id, :uuid, ...}` | Custom UUID config |

  ## Examples

      # Default: UUIDv7 primary key
      create table(:products) do
        add :name, :citext
      end
      # Equivalent to: id uuid PRIMARY KEY DEFAULT uuidv7()

      # Explicit UUIDv7
      create table(:categories, primary_key: :uuid_v7) do
        add :name, :citext
      end

      # No primary key (join tables)
      create table(:products_categories, primary_key: false) do
        add :product_id, references(:products, type: :uuid)
        add :category_id, references(:categories, type: :uuid)
      end

      # Integer primary key (legacy)
      create table(:legacy_data, primary_key: true) do
        add :value, :string
      end

      # Custom UUID config
      create table(:special, primary_key: {:uuid, :binary_id, autogenerate: true}) do
        add :data, :text
      end

  ## Technical Details

  UUIDv7 format (RFC 9562):
  - 48 bits: Unix timestamp (milliseconds)
  - 12 bits: Random sequence
  - 62 bits: Random data
  - Total: 128 bits (standard UUID size)

  Benefits:
  - Chronologically sortable
  - Better B-tree index clustering
  - Globally unique without coordination
  - Compatible with all UUID tooling
  """
  defmacro table(name, opts \\ [])

  # Pattern 1: table/2 with keyword list options
  defmacro table(name, opts) when is_list(opts) do
    quote do
      opts = unquote(opts)
      final_opts = Events.Repo.MigrationMacros.resolve_primary_key_opts(opts)
      Ecto.Migration.table(unquote(name), final_opts)
    end
  end

  # Pattern 2: table/2 with do-block
  defmacro table(name, do: block) do
    quote do
      Ecto.Migration.table unquote(name),
        primary_key: {:id, :uuid, default: {:fragment, "uuidv7()"}} do
        unquote(block)
      end
    end
  end

  @doc false
  def resolve_primary_key_opts(opts) do
    case Keyword.get(opts, :primary_key) do
      # Not specified - use UUIDv7 default
      nil ->
        Keyword.put(opts, :primary_key, {:id, :uuid, default: {:fragment, "uuidv7()"}})

      # Explicitly requested UUIDv7
      :uuid_v7 ->
        opts
        |> Keyword.delete(:primary_key)
        |> Keyword.put(:primary_key, {:id, :uuid, default: {:fragment, "uuidv7()"}})

      # User specified something else (false, true, or custom tuple) - respect it
      _other ->
        opts
    end
  end

  # ==============================================================================
  # PUBLIC API - Name and Title Fields
  # ==============================================================================

  @doc """
  Adds standard name-based identification fields for entities.

  Use this for entities identified by a name (e.g., Products, Categories,
  Organizations, Users). For content-based entities like articles or events,
  use `title_fields/1` instead.

  **Important**: Requires PostgreSQL citext extension. Enable it with:
  `execute "CREATE EXTENSION IF NOT EXISTS citext"`

  ## Fields Added

  | Field | Type | Nullable | Description |
  |-------|------|----------|-------------|
  | `name` | citext | NO | Entity display name (case-insensitive) |
  | `slug` | citext | NO | URL-friendly identifier (case-insensitive) |
  | `description` | text | YES | Long-form description |

  ## Options

  - `:only` - Add only specific field (`:name`, `:slug`, or `:description`)
  - `:except` - Exclude specific field (`:name`, `:slug`, or `:description`)
  - `:name_default` - Default value for name field
  - `:slug_default` - Default value for slug field
  - `:description_default` - Default value for description field
  - `:null` - Override NULL constraints (default: name/slug NOT NULL, description NULL)

  **Note**: `:only` and `:except` are mutually exclusive.

  ## Examples

      # All three fields (default)
      name_fields()
      # => add :name, :citext, null: false
      # => add :slug, :citext, null: false
      # => add :description, :text, null: true

      # Only name and slug (no description)
      name_fields(except: :description)

      # Only name
      name_fields(only: :name)

      # With defaults
      name_fields(name_default: "Untitled", slug_default: "untitled")

      # Allow NULL name (unusual)
      name_fields(null: true)

  ## Common Patterns

      # Product catalog
      create table(:products) do
        name_fields()
        add :price, :decimal, null: false
        add :sku, :string
        timestamps()
      end

      # Categories (no description needed)
      create table(:categories) do
        name_fields(except: :description)
        add :parent_id, references(:categories, type: :uuid)
        timestamps()
      end

      # Organizations
      create table(:organizations) do
        name_fields()
        status_field()
        type_fields(only: :type, type_default: "standard")
        metadata_field()
        audit_fields()
        timestamps()
      end

  ## Recommended Indexes

      name_indexes(:products, scope: :active, slug_index: :unique)
      # Creates:
      #   - CREATE UNIQUE INDEX ON products (slug) WHERE deleted_at IS NULL
      #   - CREATE INDEX ON products (name) WHERE deleted_at IS NULL
  """
  defmacro name_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:name, :slug, :description])

      only = Keyword.get(opts, :only)
      except = Keyword.get(opts, :except)

      name_default = Keyword.get(opts, :name_default)
      slug_default = Keyword.get(opts, :slug_default)
      description_default = Keyword.get(opts, :description_default)

      # For name/slug, default is NOT NULL unless overridden
      # For description, default is NULL
      null_override = Keyword.get(opts, :null)

      should_add_name? =
        Events.Repo.MigrationMacros.__should_add_field__(:name, only, except)
      should_add_slug? =
        Events.Repo.MigrationMacros.__should_add_field__(:slug, only, except)
      should_add_description? =
        Events.Repo.MigrationMacros.__should_add_field__(:description, only, except)

      if should_add_name? do
        name_null = if is_nil(null_override), do: false, else: null_override
        add(:name, :citext, default: name_default, null: name_null)
      end

      if should_add_slug? do
        slug_null = if is_nil(null_override), do: false, else: null_override
        add(:slug, :citext, default: slug_default, null: slug_null)
      end

      if should_add_description? do
        desc_null = if is_nil(null_override), do: true, else: null_override
        add(:description, :text, default: description_default, null: desc_null)
      end
    end
  end

  @doc """
  Adds standard title-based identification fields for content entities.

  Use this for content-based entities like articles, blog posts, events,
  and documents. For entities identified by a name (e.g., Products, Categories),
  use `name_fields/1` instead.

  **Important**: Requires PostgreSQL citext extension. Enable it with:
  `execute "CREATE EXTENSION IF NOT EXISTS citext"`

  ## Fields Added

  | Field | Type | Nullable | Description |
  |-------|------|----------|-------------|
  | `title` | citext | NO | Primary heading (case-insensitive) |
  | `subtitle` | citext | YES | Secondary heading (case-insensitive) |
  | `description` | text | YES | Long-form description/summary |
  | `slug` | citext | NO | URL-friendly identifier (case-insensitive) |

  ## Options

  - `:only` - Add only specific field (`:title`, `:subtitle`, `:description`, or `:slug`)
  - `:except` - Exclude specific field
  - `:title_default` - Default value for title field
  - `:subtitle_default` - Default value for subtitle field
  - `:description_default` - Default value for description field
  - `:slug_default` - Default value for slug field
  - `:null` - Override NULL constraints (default: title/slug NOT NULL, subtitle/description NULL)

  **Note**: `:only` and `:except` are mutually exclusive.

  ## Examples

      # All four fields (default)
      title_fields()
      # => add :title, :citext, null: false
      # => add :subtitle, :citext, null: true
      # => add :description, :text, null: true
      # => add :slug, :citext, null: false

      # Without subtitle
      title_fields(except: :subtitle)

      # Only title and slug
      title_fields(only: [:title, :slug])

      # With defaults
      title_fields(title_default: "Untitled", slug_default: "untitled")

  ## Common Patterns

      # Blog posts
      create table(:posts) do
        title_fields()
        add :content, :text, null: false
        add :published_at, :utc_datetime_usec
        status_field(default: "draft")
        type_fields(only: :type, type_default: "article")
        audit_fields()
        timestamps()
      end

      # Events
      create table(:events) do
        title_fields()
        add :starts_at, :utc_datetime_usec, null: false
        add :ends_at, :utc_datetime_usec
        add :location, :string
        status_field(default: "draft")
        type_fields(type_default: "conference")
        metadata_field()
        audit_fields()
        deleted_fields()
        timestamps()
      end

      # Documentation pages (no subtitle)
      create table(:docs) do
        title_fields(except: :subtitle)
        add :content, :text, null: false
        add :version, :string
        timestamps()
      end

  ## Recommended Indexes

      title_indexes(:posts, scope: :active, slug_index: :unique)
      # Creates:
      #   - CREATE UNIQUE INDEX ON posts (slug) WHERE deleted_at IS NULL
      #   - CREATE INDEX ON posts (title) WHERE deleted_at IS NULL
  """
  defmacro title_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(
        opts,
        [:title, :subtitle, :description, :slug]
      )

      only = Keyword.get(opts, :only)
      except = Keyword.get(opts, :except)

      title_default = Keyword.get(opts, :title_default)
      subtitle_default = Keyword.get(opts, :subtitle_default)
      description_default = Keyword.get(opts, :description_default)
      slug_default = Keyword.get(opts, :slug_default)

      null_override = Keyword.get(opts, :null)

      should_add_title? =
        Events.Repo.MigrationMacros.__should_add_field__(:title, only, except)
      should_add_subtitle? =
        Events.Repo.MigrationMacros.__should_add_field__(:subtitle, only, except)
      should_add_description? =
        Events.Repo.MigrationMacros.__should_add_field__(:description, only, except)
      should_add_slug? =
        Events.Repo.MigrationMacros.__should_add_field__(:slug, only, except)

      if should_add_title? do
        title_null = if is_nil(null_override), do: false, else: null_override
        add(:title, :citext, default: title_default, null: title_null)
      end

      if should_add_subtitle? do
        subtitle_null = if is_nil(null_override), do: true, else: null_override
        add(:subtitle, :citext, default: subtitle_default, null: subtitle_null)
      end

      if should_add_description? do
        desc_null = if is_nil(null_override), do: true, else: null_override
        add(:description, :text, default: description_default, null: desc_null)
      end

      if should_add_slug? do
        slug_null = if is_nil(null_override), do: false, else: null_override
        add(:slug, :citext, default: slug_default, null: slug_null)
      end
    end
  end

  # ==============================================================================
  # PUBLIC API - Status Field
  # ==============================================================================

  @doc """
  Adds a status field for entity lifecycle management.

  Use this for tracking entity states like active/inactive, draft/published,
  pending/approved, etc. The field uses citext for case-insensitive matching.

  **Important**: Requires PostgreSQL citext extension. Enable it with:
  `execute "CREATE EXTENSION IF NOT EXISTS citext"`

  ## Field Added

  | Field | Type | Default | Nullable | Description |
  |-------|------|---------|----------|-------------|
  | `status` | citext | "active" | NO | Entity lifecycle state (case-insensitive) |

  ## Options

  - `:default` - Default status value (default: `"active"`)
  - `:null` - Allow NULL values (default: `false`)
  - `:values` - List of valid values for check constraint (optional)

  ## Examples

      # Standard usage (default: "active")
      status_field()
      # => add :status, :citext, default: "active", null: false

      # Custom default
      status_field(default: "draft")

      # Allow NULL
      status_field(null: true, default: nil)

      # With check constraint
      create table(:posts) do
        title_fields()
        status_field(default: "draft", values: ["draft", "published", "archived"])
      end

      create constraint(:posts, :valid_status,
        check: "status IN ('draft', 'published', 'archived')")

  ## Common Status Values

      # Simple active/inactive
      status_field(default: "active")
      # Values: "active", "inactive"

      # Content workflow
      status_field(default: "draft")
      # Values: "draft", "pending", "published", "archived"

      # Approval workflow
      status_field(default: "pending")
      # Values: "pending", "approved", "rejected"

      # E-commerce orders
      status_field(default: "pending")
      # Values: "pending", "processing", "shipped", "delivered", "cancelled"

  ## Recommended Indexes

      status_indexes(:products, scope: :active)
      # Creates:
      #   - CREATE INDEX ON products (status) WHERE deleted_at IS NULL
  """
  defmacro status_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      default_value = Keyword.get(opts, :default, "active")
      null_allowed = Keyword.get(opts, :null, false)

      add(:status, :citext, default: default_value, null: null_allowed)
    end
  end

  # ==============================================================================
  # PUBLIC API - Type Classification Fields
  # ==============================================================================

  @doc """
  Adds type classification fields for polymorphic entities.

  Useful for implementing single-table inheritance or entity categorization.
  Both fields use citext (case-insensitive text) for consistent classification
  without manual lowercasing.

  **Important**: Requires PostgreSQL citext extension. Enable it with:
  `execute "CREATE EXTENSION IF NOT EXISTS citext"`

  ## Options

  - `:only` - Add only specific field (`:type` or `:subtype`)
  - `:except` - Exclude specific field (`:type` or `:subtype`)
  - `:type_default` - Default value for type field
  - `:subtype_default` - Default value for subtype field
  - `:null` - Allow NULL values (default: `true`)

  **Note**: `:only` and `:except` are mutually exclusive.

  ## Examples

      # Both fields with defaults
      type_fields()
      # => add :type, :citext, null: true
      # => add :subtype, :citext, null: true

      # With default values
      type_fields(type_default: "standard", subtype_default: "basic")

      # Only type field
      type_fields(only: :type, type_default: "event")

      # Exclude subtype field
      type_fields(except: :subtype, type_default: "event")

      # Required fields
      type_fields(null: false)

  ## Common Patterns

      # Events system
      type_fields(type_default: "conference", null: false)
      # type: "conference", "workshop", "webinar"
      # subtype: "technical", "business", "social"

      # Product catalog
      type_fields(type_default: "physical")
      # type: "physical", "digital", "service"
      # subtype: "subscription", "one-time", "bundle"

      # User accounts
      type_fields(only: :type, type_default: "individual", null: false)
      # type: "individual", "business", "enterprise"
  """
  defmacro type_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:type, :subtype])

      {add_type?, add_subtype?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(opts, [:type, :subtype])

      null_default = Keyword.get(opts, :null, true)
      type_default = Keyword.get(opts, :type_default)
      subtype_default = Keyword.get(opts, :subtype_default)

      cond do
        add_type? and add_subtype? ->
          add(:type, :citext, default: type_default, null: null_default)
          add(:subtype, :citext, default: subtype_default, null: null_default)

        add_type? ->
          add(:type, :citext, default: type_default, null: null_default)

        add_subtype? ->
          add(:subtype, :citext, default: subtype_default, null: null_default)

        true ->
          :ok
      end
    end
  end

  # ==============================================================================
  # PUBLIC API - Metadata Field
  # ==============================================================================

  @doc """
  Adds a JSONB metadata field for flexible schema extensions.

  Use this for storing semi-structured data that doesn't warrant separate columns,
  configuration data, or fields that vary by type. JSONB provides indexing and
  querying capabilities while maintaining schema flexibility.

  ## Options

  - `:null` - Allow NULL values (default: `false`)
  - `:default` - Default value (default: `fragment("'{}'")` - empty JSON object)

  ## Examples

      # Standard usage (empty object default, NOT NULL)
      metadata_field()
      # => add :metadata, :jsonb, default: fragment("'{}'"), null: false

      # Allow NULL
      metadata_field(null: true)

      # Custom default with version
      metadata_field(default: fragment("'{\"version\": 1}'"))

      # Nullable with no default
      metadata_field(null: true, default: nil)

  ## Query Examples

      # Schema definition
      field :metadata, :map

      # Querying JSON fields
      from p in Product,
        where: fragment("? ->> ? = ?", p.metadata, "status", "active")

      from p in Product,
        where: fragment("? @> ?", p.metadata, ~s({"featured": true}))

  ## Indexing Examples

      # GIN index for full JSONB querying
      create index(:products, [:metadata], using: :gin)

      # Index specific JSON key
      create index(:products, [fragment("metadata->>'status'")])

  ## Common Patterns

      # Feature flags
      %{enabled_features: ["analytics", "export"]}

      # Display preferences
      %{theme: "dark", language: "en", timezone: "UTC"}

      # Versioned data
      %{version: 2, deprecated_field: "old_value", migration_status: "pending"}

      # External integrations
      %{stripe_customer_id: "cus_123", last_sync: "2024-01-01T00:00:00Z"}
  """
  defmacro metadata_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      null_value = Keyword.get(opts, :null, false)
      default_value = Keyword.get(opts, :default, fragment("'{}'"))

      add(:metadata, :jsonb, default: default_value, null: null_value)
    end
  end

  # ==============================================================================
  # PUBLIC API - Audit Fields
  # ==============================================================================

  @doc """
  Adds audit tracking fields referencing user_role_mappings.

  Tracks who created and last updated each record via UUIDs referencing the
  user_role_mappings table. This enables multi-role auditing where users can
  perform actions in different organizational contexts.

  ## Options

  - `:only` - Add only specific field (`:created_by_urm_id` or `:updated_by_urm_id`)
  - `:except` - Exclude specific field (`:created_by_urm_id` or `:updated_by_urm_id`)
  - `:references` - Add foreign key constraints (default: `true`)
  - `:on_delete` - FK behavior when referenced record deleted (default: `:nilify_all`)
  - `:null` - Allow NULL values (default: `true`)

  **Note**: `:only` and `:except` are mutually exclusive.

  ## Examples

      # Standard usage with FK constraints (default)
      audit_fields()
      # => add :created_by_urm_id, references(:user_role_mappings, ...), null: true
      # => add :updated_by_urm_id, references(:user_role_mappings, ...), null: true

      # Without FK constraints (for initial table creation before user_role_mappings exists)
      audit_fields(references: false)
      # => add :created_by_urm_id, :uuid, null: true
      # => add :updated_by_urm_id, :uuid, null: true

      # Required audit trail
      audit_fields(null: false)

      # Only track creator
      audit_fields(only: :created_by_urm_id)

      # Exclude updater tracking
      audit_fields(except: :updated_by_urm_id)

      # Restrict deletion if referenced
      audit_fields(on_delete: :restrict)

  ## Migration Phases

      # Phase 1: Create user_role_mappings table (without audit fields to avoid circular dependency)
      create table(:user_role_mappings) do
        add :user_id, references(:users, type: :uuid)
        add :role_id, references(:roles, type: :uuid)
        timestamps()
      end

      # Phase 2: Create other tables with audit fields (default behavior includes FK constraints)
      create table(:products) do
        add :name, :string
        audit_fields()  # Automatically includes FK references
        timestamps()
      end

      # Phase 3: If you need to add audit fields to user_role_mappings later
      alter table(:user_role_mappings) do
        add :created_by_urm_id, :uuid
        add :updated_by_urm_id, :uuid
      end

      # Add FK constraints separately to avoid self-referential issues during creation
      alter table(:user_role_mappings) do
        modify :created_by_urm_id, references(:user_role_mappings, type: :uuid, on_delete: :nilify_all)
        modify :updated_by_urm_id, references(:user_role_mappings, type: :uuid, on_delete: :nilify_all)
      end

  ## Foreign Key Options

  `:on_delete` behavior:
  - `:nothing` - Do nothing (will fail if referenced records exist)
  - `:delete_all` - Delete this record when referenced record deleted
  - `:nilify_all` - Set field to NULL (default, safest for audit trails)
  - `:restrict` - Prevent deletion of referenced record

  ## Schema Definitions

      schema "products" do
        field :name, :string

        belongs_to :created_by_urm, UserRoleMapping, foreign_key: :created_by_urm_id
        belongs_to :updated_by_urm, UserRoleMapping, foreign_key: :updated_by_urm_id

        timestamps()
      end

  ## Query Examples

      # Preload creator information
      from p in Product,
        preload: [created_by_urm: [:user, :role]]

      # Filter by creator's role
      from p in Product,
        join: urm in assoc(p, :created_by_urm),
        join: r in assoc(urm, :role),
        where: r.name == "admin"
  """
  defmacro audit_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(
        opts,
        [:created_by_urm_id, :updated_by_urm_id]
      )

      {add_created?, add_updated?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(
          opts,
          [:created_by_urm_id, :updated_by_urm_id]
        )

      add_references = Keyword.get(opts, :references, true)
      on_delete_action = Keyword.get(opts, :on_delete, :nilify_all)
      null_allowed = Keyword.get(opts, :null, true)

      cond do
        add_created? and add_updated? ->
          Events.Repo.MigrationMacros.__add_audit_field__(
            :created_by_urm_id,
            add_references,
            on_delete_action,
            null_allowed
          )

          Events.Repo.MigrationMacros.__add_audit_field__(
            :updated_by_urm_id,
            add_references,
            on_delete_action,
            null_allowed
          )

        add_created? ->
          Events.Repo.MigrationMacros.__add_audit_field__(
            :created_by_urm_id,
            add_references,
            on_delete_action,
            null_allowed
          )

        add_updated? ->
          Events.Repo.MigrationMacros.__add_audit_field__(
            :updated_by_urm_id,
            add_references,
            on_delete_action,
            null_allowed
          )

        true ->
          :ok
      end
    end
  end

  # ==============================================================================
  # PUBLIC API - Soft Delete Fields
  # ==============================================================================

  @doc """
  Adds soft delete tracking fields for paranoid deletion.

  Enables soft delete functionality by tracking when a record was deleted
  and optionally who deleted it. Use these fields in queries to filter out
  deleted records while maintaining data history.

  ## Options

  - `:only` - Add only specific field (`:deleted_at` or `:deleted_by_urm_id`)
  - `:except` - Exclude specific field (`:deleted_at` or `:deleted_by_urm_id`)
  - `:references` - Add FK constraint for deleted_by_urm_id (default: `true`)
  - `:on_delete` - FK behavior when referenced record deleted (default: `:nilify_all`)
  - `:null` - Allow NULL values (default: `true` - records start undeleted)

  **Note**: `:only` and `:except` are mutually exclusive.

  ## Examples

      # Both fields (timestamp + who deleted)
      deleted_fields()
      # => add :deleted_at, :utc_datetime_usec, null: true
      # => add :deleted_by_urm_id, references(:user_role_mappings, ...), null: true

      # Only timestamp (no audit tracking)
      deleted_fields(only: :deleted_at)

      # Only who deleted (unusual, but supported)
      deleted_fields(only: :deleted_by_urm_id)

      # Exclude who deleted, only track when
      deleted_fields(except: :deleted_by_urm_id)

      # Without FK constraint (for tables created before user_role_mappings)
      deleted_fields(references: false)

  ## Query Patterns

      # Filter out deleted records (default scope)
      from p in Product,
        where: is_nil(p.deleted_at)

      # Include deleted records (admin view)
      from p in Product  # No where clause

      # Only deleted records (trash/recycle bin)
      from p in Product,
        where: not is_nil(p.deleted_at)

      # Deleted in last 30 days (recoverable)
      thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
      from p in Product,
        where: not is_nil(p.deleted_at),
        where: p.deleted_at >= ^thirty_days_ago

  ## Schema Definition

      defmodule MyApp.Catalog.Product do
        use Ecto.Schema
        import Ecto.Query

        schema "products" do
          field :name, :string
          field :deleted_at, :utc_datetime_usec

          belongs_to :deleted_by_urm, MyApp.Accounts.UserRoleMapping,
            foreign_key: :deleted_by_urm_id

          timestamps(type: :utc_datetime_usec)
        end

        # Default scope to exclude deleted
        def not_deleted(query \\\\ __MODULE__) do
          from q in query, where: is_nil(q.deleted_at)
        end

        # Soft delete implementation
        def soft_delete(product, deleted_by_urm_id) do
          product
          |> Ecto.Changeset.change(%{
            deleted_at: DateTime.utc_now(),
            deleted_by_urm_id: deleted_by_urm_id
          })
          |> Repo.update()
        end

        # Restore deleted record
        def restore(product) do
          product
          |> Ecto.Changeset.change(%{
            deleted_at: nil,
            deleted_by_urm_id: nil
          })
          |> Repo.update()
        end
      end

  ## Usage in Context

      defmodule MyApp.Catalog do
        import Ecto.Query

        # List active (non-deleted) products
        def list_products do
          Product
          |> where([p], is_nil(p.deleted_at))
          |> Repo.all()
        end

        # Delete product (soft delete)
        def delete_product(product, deleted_by_urm_id) do
          product
          |> Ecto.Changeset.change(%{
            deleted_at: DateTime.utc_now(),
            deleted_by_urm_id: deleted_by_urm_id
          })
          |> Repo.update()
        end

        # Permanently delete old records (hard delete)
        def purge_deleted_products(days_old) do
          cutoff = DateTime.utc_now() |> DateTime.add(-days_old, :day)

          from(p in Product,
            where: not is_nil(p.deleted_at),
            where: p.deleted_at < ^cutoff
          )
          |> Repo.delete_all()
        end
      end

  ## Best Practices

  1. **Always filter deleted records** in default queries
  2. **Use database views** for common non-deleted scopes
  3. **Implement restore functionality** for accidental deletions
  4. **Purge old deleted records** periodically to prevent bloat
  5. **Add indexes** on deleted_at for query performance
  6. **Consider partial indexes**: `WHERE deleted_at IS NULL` for active records

  ## Index Recommendations

      # Partial index for active records only
      create index(:products, [:status], where: "deleted_at IS NULL")

      # Composite index for filtered queries
      create index(:products, [:deleted_at, :updated_at])

      # Index on deleted_by for audit queries
      create index(:products, [:deleted_by_urm_id])

  ## Migration Example

      create table(:products) do
        add :name, :citext, null: false
        add :price, :decimal, null: false

        metadata_field()
        audit_fields()
        deleted_fields()  # Soft delete support
        timestamps()
      end

      # Indexes for soft delete
      create index(:products, [:deleted_at])
      create index(:products, [:deleted_by_urm_id])
      create index(:products, [:status], where: "deleted_at IS NULL")
  """
  defmacro deleted_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(
        opts,
        [:deleted_at, :deleted_by_urm_id]
      )

      {add_deleted_at?, add_deleted_by?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(
          opts,
          [:deleted_at, :deleted_by_urm_id]
        )

      add_references = Keyword.get(opts, :references, true)
      on_delete_action = Keyword.get(opts, :on_delete, :nilify_all)
      null_allowed = Keyword.get(opts, :null, true)

      cond do
        add_deleted_at? and add_deleted_by? ->
          add(:deleted_at, :utc_datetime_usec, null: null_allowed)

          Events.Repo.MigrationMacros.__add_audit_field__(
            :deleted_by_urm_id,
            add_references,
            on_delete_action,
            null_allowed
          )

        add_deleted_at? ->
          add(:deleted_at, :utc_datetime_usec, null: null_allowed)

        add_deleted_by? ->
          Events.Repo.MigrationMacros.__add_audit_field__(
            :deleted_by_urm_id,
            add_references,
            on_delete_action,
            null_allowed
          )

        true ->
          :ok
      end
    end
  end

  # ==============================================================================
  # PUBLIC API - Timestamps
  # ==============================================================================

  @doc """
  Adds standard timestamp fields with PostgreSQL defaults.

  Creates `inserted_at` and `updated_at` fields using UTC microsecond precision
  with PostgreSQL's `CURRENT_TIMESTAMP` for automatic population.

  ## Field Specifications

  - **Type**: `:utc_datetime_usec` (microsecond precision)
  - **NULL**: NOT NULL (always required)
  - **Default**: PostgreSQL `CURRENT_TIMESTAMP`

  ## Options

  - `:only` - Add only specific field (`:inserted_at` or `:updated_at`)
  - `:except` - Exclude specific field (`:inserted_at` or `:updated_at`)

  **Note**: `:only` and `:except` are mutually exclusive.

  ## Examples

      # Both fields (default)
      timestamps()
      # => add :inserted_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
      # => add :updated_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")

      # Only inserted_at
      timestamps(only: :inserted_at)

      # Exclude updated_at
      timestamps(except: :updated_at)

  ## Database Behavior

      # On INSERT: Both fields set to current time
      INSERT INTO products (name, inserted_at, updated_at)
      VALUES ('Widget', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

      # On UPDATE: updated_at should be updated via trigger or application
      UPDATE products
      SET name = 'New Widget', updated_at = CURRENT_TIMESTAMP
      WHERE id = '...';

  ## Trigger for Auto-Update

      # Consider adding a trigger to automatically update updated_at:
      CREATE OR REPLACE FUNCTION update_updated_at()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER products_updated_at
        BEFORE UPDATE ON products
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at();

  ## Schema Definition

      schema "products" do
        field :name, :string

        timestamps(type: :utc_datetime_usec)
        # Ecto automatically maps inserted_at/updated_at
      end

  ## Query Examples

      # Filter by creation date
      from p in Product,
        where: p.inserted_at >= ^seven_days_ago

      # Order by most recently updated
      from p in Product,
        order_by: [desc: p.updated_at]

      # Find stale records
      from p in Product,
        where: p.updated_at < ^thirty_days_ago,
        where: p.status == "active"
  """
  defmacro timestamps(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:inserted_at, :updated_at])

      {add_inserted?, add_updated?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(opts, [:inserted_at, :updated_at])

      cond do
        add_inserted? and add_updated? ->
          add(:inserted_at, :utc_datetime_usec,
            null: false,
            default: fragment("CURRENT_TIMESTAMP")
          )

          add(:updated_at, :utc_datetime_usec,
            null: false,
            default: fragment("CURRENT_TIMESTAMP")
          )

        add_inserted? ->
          add(:inserted_at, :utc_datetime_usec,
            null: false,
            default: fragment("CURRENT_TIMESTAMP")
          )

        add_updated? ->
          add(:updated_at, :utc_datetime_usec,
            null: false,
            default: fragment("CURRENT_TIMESTAMP")
          )

        true ->
          :ok
      end
    end
  end

  # ==============================================================================
  # PUBLIC API - Standard Entity Fields
  # ==============================================================================

  @doc """
  Adds a complete set of standard fields for typical business entities.

  **DEPRECATED**: This macro is maintained for backward compatibility.
  For new code, use explicit field macros for better clarity and control:

      create table(:products) do
        name_fields()              # name, slug, description
        status_field()             # status
        type_fields()              # type, subtype
        metadata_field()           # metadata
        audit_fields()             # created_by_urm_id, updated_by_urm_id
        timestamps()               # inserted_at, updated_at
      end

  **Important**: Requires PostgreSQL citext extension for case-insensitive fields.
  Enable with: `execute "CREATE EXTENSION IF NOT EXISTS citext"`

  ## Fields Added

  | Field | Type | Options | Description |
  |-------|------|---------|-------------|
  | `name` | citext | null: false | Entity display name (via `name_fields/1`) |
  | `slug` | citext | null: false | URL-friendly identifier (via `name_fields/1`) |
  | `description` | text | null: true | Long-form description (via `name_fields/1`) |
  | `status` | citext | default: "active", null: false | Entity lifecycle state (via `status_field/1`) |
  | `type` | citext | null: true | Primary classification (via `type_fields/1`) |
  | `subtype` | citext | null: true | Secondary classification (via `type_fields/1`) |
  | `metadata` | jsonb | default: {} | Flexible attributes (via `metadata_field/1`) |
  | `created_by_urm_id` | uuid | null: true | Creator reference (via `audit_fields/1`) |
  | `updated_by_urm_id` | uuid | null: true | Last updater reference (via `audit_fields/1`) |
  | `inserted_at` | timestamp | null: false | Creation timestamp (via `timestamps/0`) |
  | `updated_at` | timestamp | null: false | Update timestamp (via `timestamps/0`) |

  **Note**: Does NOT add `id` field - use `table()` macro which automatically
  adds UUIDv7 primary key.

  ## Options

  - `:except` - Exclude specific field groups (list of: `:name_fields`, `:status_field`, `:type_fields`, `:metadata`, `:audit_fields`, `:timestamps`)
  - `:status_default` - Default status value (default: `"active"`)
  - `:type_default` - Default type value (default: `nil`)
  - `:null` - Allow NULL for audit fields (default: `true`)
  - `:references` - Add FK constraints for audit fields (default: `true`)

  ## Examples

      # Full standard entity (all fields)
      create table(:products) do
        standard_entity_fields()
        add :price, :decimal, null: false
      end

      # With custom status
      create table(:accounts) do
        standard_entity_fields(status_default: "pending")
        add :balance, :decimal
      end

      # Exclude some field groups
      create table(:simple_logs) do
        standard_entity_fields(except: [:type_fields, :audit_fields])
        add :message, :text
      end

  ## Recommended Approach (More Explicit)

  Instead of using this macro, consider using the individual field macros:

      # Better approach - explicit and clear
      create table(:products) do
        name_fields()              # name, slug, description
        status_field()             # status (default: "active")
        type_fields()              # type, subtype
        metadata_field()           # metadata (JSONB)
        audit_fields()             # created_by_urm_id, updated_by_urm_id
        timestamps()               # inserted_at, updated_at
      end

      # For title-based entities (blogs, articles, events)
      create table(:posts) do
        title_fields()             # title, subtitle, description, slug
        status_field(default: "draft")
        type_fields(only: :type)
        metadata_field()
        audit_fields()
        deleted_fields()           # Soft delete support
        timestamps()
      end

  ## Schema Definition

      defmodule Events.Catalog.Product do
        use Ecto.Schema

        schema "products" do
          field :name, :string
          field :slug, :string
          field :description, :string
          field :status, :string
          field :type, :string
          field :subtype, :string
          field :metadata, :map

          belongs_to :created_by_urm, Events.Accounts.UserRoleMapping,
            foreign_key: :created_by_urm_id
          belongs_to :updated_by_urm, Events.Accounts.UserRoleMapping,
            foreign_key: :updated_by_urm_id

          timestamps(type: :utc_datetime_usec)
        end
      end
  """
  defmacro standard_entity_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      except_fields = List.wrap(Keyword.get(opts, :except, []))
      status_default = Keyword.get(opts, :status_default, "active")
      type_default = Keyword.get(opts, :type_default)

      # Name, slug, description fields (via name_fields macro)
      cond do
        :name_fields in except_fields ->
          :ok

        true ->
          name_fields()
      end

      # Status field (via status_field macro)
      cond do
        :status_field in except_fields ->
          :ok

        true ->
          status_field(default: status_default)
      end

      # Type classification (via type_fields macro)
      cond do
        :type_fields in except_fields ->
          :ok

        true ->
          type_opts =
            case type_default do
              nil -> []
              val -> [type_default: val]
            end

          type_fields(type_opts)
      end

      # Metadata (via metadata_field macro)
      cond do
        :metadata in except_fields ->
          :ok

        true ->
          metadata_field()
      end

      # Audit tracking (via audit_fields macro)
      cond do
        :audit_fields in except_fields ->
          :ok

        true ->
          audit_fields(Keyword.take(opts, [:null, :references, :on_delete]))
      end

      # Timestamps (via timestamps macro)
      cond do
        :timestamps in except_fields ->
          :ok

        true ->
          timestamps()
      end
    end
  end

  # ==============================================================================
  # PUBLIC API - Index Helper Macros
  # ==============================================================================

  @doc """
  Creates indexes for name-based entity fields.

  Automatically creates indexes for fields added by `name_fields/1`.
  By default, creates a unique index on `slug` and standard indexes on `name`
  and `description`.

  ## Options

  - `:only` - Index only specific field (`:name`, `:slug`, or `:description`)
  - `:except` - Skip indexing specific field
  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:slug_index` - Control slug indexing (`:unique` (default), `:standard`, or `false` to skip)
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently (default: false)

  ## Scope Values

  - `:all` or `nil` - No WHERE clause (indexes everything)
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - e.g., `"status = 'published'"`

  ## Examples

      # Standard usage (unique slug index)
      name_indexes(:products)
      # => create unique_index(:products, [:slug])
      # => create index(:products, [:name])

      # With soft delete filtering
      name_indexes(:products, scope: :active)
      # => create unique_index(:products, [:slug], where: "deleted_at IS NULL")
      # => create index(:products, [:name], where: "deleted_at IS NULL")

      # Only slug index
      name_indexes(:products, only: :slug, scope: :active)
      # => create unique_index(:products, [:slug], where: "deleted_at IS NULL")

      # Non-unique slug (unusual)
      name_indexes(:products, slug_index: :standard)
      # => create index(:products, [:slug])

      # Skip slug index entirely
      name_indexes(:products, slug_index: false)
      # => create index(:products, [:name])

      # Custom scope
      name_indexes(:products, scope: "status = 'published'")
      # => create unique_index(:products, [:slug], where: "status = 'published'")
      # => create index(:products, [:name], where: "status = 'published'")

  ## Common Patterns

      # Active products only
      name_indexes(:products, scope: :active)

      # Skip description index
      name_indexes(:products, except: :description, scope: :active)

      # Concurrent creation (large tables)
      name_indexes(:products, scope: :active, concurrently: true)
  """
  defmacro name_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(
        opts,
        [:name, :slug, :description]
      )

      only = Keyword.get(opts, :only)
      except = Keyword.get(opts, :except)
      slug_index = Keyword.get(opts, :slug_index, :unique)
      scope = Keyword.get(opts, :scope)

      # Resolve scope to WHERE clause
      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      # Build base index options (exclude scope, slug_index, only, except)
      base_opts =
        opts
        |> Keyword.drop([:scope, :slug_index, :only, :except])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      should_add_name? =
        Events.Repo.MigrationMacros.__should_add_field__(:name, only, except)
      should_add_slug? =
        Events.Repo.MigrationMacros.__should_add_field__(:slug, only, except)
      should_add_description? =
        Events.Repo.MigrationMacros.__should_add_field__(:description, only, except)

      # Create slug index (unique by default)
      if should_add_slug? and slug_index != false do
        case slug_index do
          :unique ->
            create unique_index(table_name, [:slug], base_opts)

          :standard ->
            create index(table_name, [:slug], base_opts)

          false ->
            :ok

          _ ->
            raise ArgumentError,
                  "invalid :slug_index value #{inspect(slug_index)}. Expected :unique, :standard, or false"
        end
      end

      # Create name index
      if should_add_name? do
        create index(table_name, [:name], base_opts)
      end

      # Create description index (optional - usually not needed)
      if should_add_description? do
        create index(table_name, [:description], base_opts)
      end
    end
  end

  @doc """
  Creates indexes for title-based entity fields.

  Automatically creates indexes for fields added by `title_fields/1`.
  By default, creates a unique index on `slug` and standard indexes on `title`.

  ## Options

  - `:only` - Index only specific field (`:title`, `:subtitle`, `:description`, or `:slug`)
  - `:except` - Skip indexing specific field
  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:slug_index` - Control slug indexing (`:unique` (default), `:standard`, or `false` to skip)
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently (default: false)

  ## Scope Values

  - `:all` or `nil` - No WHERE clause (indexes everything)
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - e.g., `"status = 'published'"`

  ## Examples

      # Standard usage (unique slug index)
      title_indexes(:posts)
      # => create unique_index(:posts, [:slug])
      # => create index(:posts, [:title])

      # With soft delete filtering
      title_indexes(:posts, scope: :active)
      # => create unique_index(:posts, [:slug], where: "deleted_at IS NULL")
      # => create index(:posts, [:title], where: "deleted_at IS NULL")

      # Only slug and title
      title_indexes(:posts, except: [:subtitle, :description], scope: :active)

      # Custom scope for published content
      title_indexes(:posts, scope: "status = 'published' AND deleted_at IS NULL")

  ## Common Patterns

      # Blog posts (active only)
      title_indexes(:posts, scope: :active)

      # Events (minimal indexes)
      title_indexes(:events, only: [:slug, :title], scope: :active)

      # Concurrent creation
      title_indexes(:articles, scope: :active, concurrently: true)
  """
  defmacro title_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(
        opts,
        [:title, :subtitle, :description, :slug]
      )

      only = Keyword.get(opts, :only)
      except = Keyword.get(opts, :except)
      slug_index = Keyword.get(opts, :slug_index, :unique)
      scope = Keyword.get(opts, :scope)

      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      base_opts =
        opts
        |> Keyword.drop([:scope, :slug_index, :only, :except])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      should_add_title? =
        Events.Repo.MigrationMacros.__should_add_field__(:title, only, except)
      should_add_subtitle? =
        Events.Repo.MigrationMacros.__should_add_field__(:subtitle, only, except)
      should_add_description? =
        Events.Repo.MigrationMacros.__should_add_field__(:description, only, except)
      should_add_slug? =
        Events.Repo.MigrationMacros.__should_add_field__(:slug, only, except)

      # Create slug index (unique by default)
      if should_add_slug? and slug_index != false do
        case slug_index do
          :unique ->
            create unique_index(table_name, [:slug], base_opts)

          :standard ->
            create index(table_name, [:slug], base_opts)

          false ->
            :ok

          _ ->
            raise ArgumentError,
                  "invalid :slug_index value #{inspect(slug_index)}. Expected :unique, :standard, or false"
        end
      end

      # Create title index
      if should_add_title? do
        create index(table_name, [:title], base_opts)
      end

      # Create subtitle index (usually not needed)
      if should_add_subtitle? do
        create index(table_name, [:subtitle], base_opts)
      end

      # Create description index (usually not needed)
      if should_add_description? do
        create index(table_name, [:description], base_opts)
      end
    end
  end

  @doc """
  Creates index for status field.

  By default, creates a standard index on the `status` column.
  Use `scope` option to add partial index filtering.

  ## Options

  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:unique` - Create unique index (default: false)
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently (default: false)

  ## Scope Values

  - `:all` or `nil` - No WHERE clause
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - e.g., `"type = 'premium'"`

  ## Examples

      # Standard usage
      status_indexes(:products)
      # => create index(:products, [:status])

      # Active records only
      status_indexes(:products, scope: :active)
      # => create index(:products, [:status], where: "deleted_at IS NULL")

      # Unique status (unusual but possible)
      status_indexes(:singleton_settings, unique: true)
      # => create unique_index(:singleton_settings, [:status])

      # Custom scope
      status_indexes(:products, scope: "type = 'premium'")
      # => create index(:products, [:status], where: "type = 'premium'")

  ## Common Patterns

      # Standard with soft delete
      status_indexes(:products, scope: :active)

      # Concurrent creation
      status_indexes(:products, scope: :active, concurrently: true)
  """
  defmacro status_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      scope = Keyword.get(opts, :scope)
      unique = Keyword.get(opts, :unique, false)

      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      index_opts =
        opts
        |> Keyword.drop([:scope, :unique])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      Events.Repo.MigrationMacros.__create_index__(
        table_name,
        [:status],
        unique,
        index_opts
      )
    end
  end

  @doc """
  Creates indexes for type classification fields.

  ## Options

  - `:only` - Index only specific field (`:type` or `:subtype`)
  - `:except` - Skip indexing specific field
  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:where` - Partial index condition (deprecated - use `:scope` instead)
  - `:name` - Custom index name
  - `:unique` - Create unique index (default: false)
  - `:concurrently` - Create concurrently (default: false)
  - `:composite` - Create single composite index on `[:type, :subtype]` (default: false)

  ## Scope Values

  - `:all` or `nil` - No WHERE clause
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - e.g., `"category = 'premium'"`

  ## Examples

      type_indexes(:products)
      # => create index(:products, [:type])
      # => create index(:products, [:subtype])

      type_indexes(:products, only: :type, scope: :active)
      # => create index(:products, [:type], where: "deleted_at IS NULL")

      type_indexes(:products, composite: true, scope: :active)
      # => create index(:products, [:type, :subtype], where: "deleted_at IS NULL")

      type_indexes(:products, unique: true, scope: :active)
      # => create unique_index(:products, [:type], where: "deleted_at IS NULL")
      # => create unique_index(:products, [:subtype], where: "deleted_at IS NULL")
  """
  defmacro type_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:type, :subtype])

      composite = Keyword.get(opts, :composite, false)
      unique = Keyword.get(opts, :unique, false)
      scope = Keyword.get(opts, :scope)

      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      index_opts =
        opts
        |> Keyword.drop([:scope, :composite, :unique])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      case composite do
        true ->
          Events.Repo.MigrationMacros.__create_index__(
            table_name,
            [:type, :subtype],
            unique,
            index_opts
          )

        false ->
          {add_type?, add_subtype?} =
            Events.Repo.MigrationMacros.__determine_fields_to_add__(opts, [:type, :subtype])

          cond do
            add_type? and add_subtype? ->
              Events.Repo.MigrationMacros.__create_index__(
                table_name,
                [:type],
                unique,
                index_opts
              )

              Events.Repo.MigrationMacros.__create_index__(
                table_name,
                [:subtype],
                unique,
                index_opts
              )

            add_type? ->
              Events.Repo.MigrationMacros.__create_index__(
                table_name,
                [:type],
                unique,
                index_opts
              )

            add_subtype? ->
              Events.Repo.MigrationMacros.__create_index__(
                table_name,
                [:subtype],
                unique,
                index_opts
              )

            true ->
              :ok
          end
      end
    end
  end

  @doc """
  Creates indexes for audit tracking fields.

  ## Options

  - `:only` - Index only specific field (`:created_by_urm_id` or `:updated_by_urm_id`)
  - `:except` - Skip indexing specific field
  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:where` - Partial index condition (deprecated - use `:scope` instead)
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently

  ## Scope Values

  - `:all` or `nil` - No WHERE clause
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - Custom WHERE clause

  ## Examples

      audit_indexes(:products)
      # => create index(:products, [:created_by_urm_id])
      # => create index(:products, [:updated_by_urm_id])

      audit_indexes(:products, only: :created_by_urm_id)
      # => create index(:products, [:created_by_urm_id])

      audit_indexes(:products, scope: :active, concurrently: true)
      # => create index(:products, [:created_by_urm_id], where: "deleted_at IS NULL", concurrently: true)
      # => create index(:products, [:updated_by_urm_id], where: "deleted_at IS NULL", concurrently: true)
  """
  defmacro audit_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(
        opts,
        [:created_by_urm_id, :updated_by_urm_id]
      )

      {add_created?, add_updated?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(
          opts,
          [:created_by_urm_id, :updated_by_urm_id]
        )

      scope = Keyword.get(opts, :scope)
      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      index_opts =
        opts
        |> Keyword.drop([:scope])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      cond do
        add_created? and add_updated? ->
          create index(table_name, [:created_by_urm_id], index_opts)
          create index(table_name, [:updated_by_urm_id], index_opts)

        add_created? ->
          create index(table_name, [:created_by_urm_id], index_opts)

        add_updated? ->
          create index(table_name, [:updated_by_urm_id], index_opts)

        true ->
          :ok
      end
    end
  end

  @doc """
  Creates indexes for soft delete fields.

  ## Options

  - `:only` - Index only specific field (`:deleted_at` or `:deleted_by_urm_id`)
  - `:except` - Skip indexing specific field
  - `:where` - Partial index condition
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently

  ## Examples

      deleted_indexes(:documents)
      # => create index(:documents, [:deleted_at])
      # => create index(:documents, [:deleted_by_urm_id])

      deleted_indexes(:documents, only: :deleted_at)
      # => create index(:documents, [:deleted_at])
  """
  defmacro deleted_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:deleted_at, :deleted_by_urm_id])

      {add_deleted_at?, add_deleted_by?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(
          opts,
          [:deleted_at, :deleted_by_urm_id]
        )

      index_opts = Events.Repo.MigrationMacros.__build_index_opts__(opts)

      cond do
        add_deleted_at? and add_deleted_by? ->
          create index(table_name, [:deleted_at], index_opts)
          create index(table_name, [:deleted_by_urm_id], index_opts)

        add_deleted_at? ->
          create index(table_name, [:deleted_at], index_opts)

        add_deleted_by? ->
          create index(table_name, [:deleted_by_urm_id], index_opts)

        true ->
          :ok
      end
    end
  end

  @doc """
  Creates indexes for timestamp fields.

  ## Options

  - `:only` - Index only specific field (`:inserted_at` or `:updated_at`)
  - `:except` - Skip indexing specific field
  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:where` - Partial index condition (deprecated - use `:scope` instead)
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently
  - `:composite_with` - List of other fields to include in composite index

  ## Scope Values

  - `:all` or `nil` - No WHERE clause
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - Custom WHERE clause

  ## Examples

      timestamp_indexes(:products)
      # => create index(:products, [:inserted_at])
      # => create index(:products, [:updated_at])

      timestamp_indexes(:products, only: :updated_at)
      # => create index(:products, [:updated_at])

      timestamp_indexes(:products, only: :updated_at, composite_with: [:status])
      # => create index(:products, [:status, :updated_at])

      timestamp_indexes(:products, scope: :active)
      # => create index(:products, [:inserted_at], where: "deleted_at IS NULL")
      # => create index(:products, [:updated_at], where: "deleted_at IS NULL")
  """
  defmacro timestamp_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:inserted_at, :updated_at])

      {add_inserted?, add_updated?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(opts, [:inserted_at, :updated_at])

      composite_with = Keyword.get(opts, :composite_with)
      scope = Keyword.get(opts, :scope)
      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      index_opts =
        opts
        |> Keyword.drop([:scope, :composite_with])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      fields_fn = fn field ->
        case {composite_with, is_list(composite_with)} do
          {list, true} -> list ++ [field]
          _ -> [field]
        end
      end

      cond do
        add_inserted? and add_updated? ->
          create index(table_name, fields_fn.(:inserted_at), index_opts)
          create index(table_name, fields_fn.(:updated_at), index_opts)

        add_inserted? ->
          create index(table_name, fields_fn.(:inserted_at), index_opts)

        add_updated? ->
          create index(table_name, fields_fn.(:updated_at), index_opts)

        true ->
          :ok
      end
    end
  end

  @doc """
  Creates a GIN index on the metadata JSONB field for efficient querying.

  **Performance Note**: GIN indexes on JSONB are expensive to maintain.
  Only create if you frequently query JSON keys.

  ## Options

  - `:scope` - Partial index scope (`:all`, `:active`, `:non_deleted`, `:exclude_deleted`, `:deleted`, or custom string)
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently (recommended for large tables)
  - `:json_path` - Index specific JSON key instead of entire field
  - `:using` - Index method (default: :gin)

  ## Scope Values

  - `:all` or `nil` - No WHERE clause
  - `:active`, `:non_deleted`, `:exclude_deleted` - WHERE deleted_at IS NULL
  - `:deleted` - WHERE deleted_at IS NOT NULL
  - Custom string - Custom WHERE clause

  ## Examples

      metadata_index(:products)
      # => create index(:products, [:metadata], using: :gin)

      metadata_index(:products, json_path: "status")
      # => create index(:products, [fragment("(metadata->>'status')")])

      metadata_index(:products, concurrently: true, scope: :active)
      # => create index(:products, [:metadata], using: :gin, where: "deleted_at IS NULL", concurrently: true)
  """
  defmacro metadata_index(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      json_path = Keyword.get(opts, :json_path)
      using = Keyword.get(opts, :using, :gin)
      scope = Keyword.get(opts, :scope)
      where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

      base_opts =
        opts
        |> Keyword.drop([:scope, :json_path, :using])
        |> Events.Repo.MigrationMacros.__build_index_opts__()
        |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

      case json_path do
        nil ->
          index_opts = Keyword.put(base_opts, :using, using)
          create index(table_name, [:metadata], index_opts)

        path ->
          create index(table_name, [fragment("(metadata->>'#{path}')")], base_opts)
      end
    end
  end

  @doc """
  Creates recommended indexes for standard entity fields.

  This is a convenience macro that creates indexes based on which fields
  were added to the table. Use the `:has` option to specify what fields exist.

  ## Default Behavior

  When `has: :all` (default), assumes `standard_entity_fields()` was used and creates:
  - Unique index on `:slug`
  - Partial index on `:status` (WHERE deleted_at IS NULL)
  - Standard indexes on `:type`, `:subtype`
  - Standard indexes on `:created_by_urm_id`, `:updated_by_urm_id`

  ## Options

  - `:has` - What fields exist (`:all` or list of field groups)
  - `:only` - Create indexes only for specific field groups
  - `:except` - Skip indexes for specific field groups
  - `:slug_unique` - Make slug index unique (default: true)
  - `:status_where` - Custom WHERE clause for status (default: `"deleted_at IS NULL"`)
  - `:concurrently` - Create all indexes concurrently
  - `:composite` - Additional composite indexes (list of field lists)

  Field groups: `:slug`, `:status`, `:type_fields`, `:audit_fields`, `:deleted_fields`, `:timestamps`, `:metadata`

  ## Examples

      # Full standard entity
      create table(:products) do
        standard_entity_fields()
      end
      standard_indexes(:products)
      # Creates: slug (unique), status, type, subtype, created_by_urm_id, updated_by_urm_id

      # Partial fields - be explicit
      create table(:categories) do
        standard_entity_fields(except: [:slug, :audit_fields])
      end
      standard_indexes(:categories, has: [:status, :type_fields])
      # Creates only: status, type, subtype

      # Custom field setup
      create table(:logs) do
        add :name, :citext
        type_fields(only: :type)
        timestamps()
      end
      standard_indexes(:logs, has: [:type_fields], only: :type_fields)
      # Creates only: type, subtype
  """
  defmacro standard_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      field_groups =
        case Keyword.get(opts, :has, :all) do
          :all -> [:slug, :status, :type_fields, :audit_fields]
          list when is_list(list) -> list
          _ -> []
        end

      only_groups = List.wrap(Keyword.get(opts, :only, []))
      except_groups = List.wrap(Keyword.get(opts, :except, []))

      should_index? =
        Events.Repo.MigrationMacros.__should_index_group__(
          field_groups,
          only_groups,
          except_groups
        )

      base_index_opts = Events.Repo.MigrationMacros.__build_index_opts__(opts)

      # Slug - unique index
      cond do
        should_index?.(:slug) ->
          slug_unique = Keyword.get(opts, :slug_unique, true)

          Events.Repo.MigrationMacros.__create_index__(
            table_name,
            [:slug],
            slug_unique,
            base_index_opts
          )

        true ->
          :ok
      end

      # Status - partial index
      cond do
        should_index?.(:status) ->
          status_where = Keyword.get(opts, :status_where, "deleted_at IS NULL")

          status_opts =
            Events.Repo.MigrationMacros.__maybe_add_where__(base_index_opts, status_where)

          create index(table_name, [:status], status_opts)

        true ->
          :ok
      end

      # Type fields
      cond do
        should_index?.(:type_fields) ->
          type_indexes(table_name, base_index_opts)

        true ->
          :ok
      end

      # Audit fields
      cond do
        should_index?.(:audit_fields) ->
          audit_indexes(table_name, base_index_opts)

        true ->
          :ok
      end

      # Deleted fields
      cond do
        should_index?.(:deleted_fields) ->
          deleted_indexes(table_name, base_index_opts)

        true ->
          :ok
      end

      # Metadata GIN index
      cond do
        should_index?.(:metadata) ->
          metadata_index(table_name, base_index_opts)

        true ->
          :ok
      end

      # Timestamp indexes
      cond do
        should_index?.(:timestamps) ->
          timestamp_indexes(table_name, base_index_opts)

        true ->
          :ok
      end

      # Additional composite indexes
      for fields <- Keyword.get(opts, :composite, []) do
        create index(table_name, fields, base_index_opts)
      end
    end
  end

  # ==============================================================================
  # HELPER FUNCTIONS
  # ==============================================================================

  @doc false
  def __validate_only_except__(opts, valid_fields) do
    case {Keyword.get(opts, :only), Keyword.get(opts, :except)} do
      {only, except} when not is_nil(only) and not is_nil(except) ->
        raise ArgumentError,
              "cannot specify both :only and :except options. Please use one or the other."

      {only, _} when not is_nil(only) ->
        if !__valid_field?(only, valid_fields) do
          raise ArgumentError,
                "invalid :only value #{inspect(only)}. Expected one of: #{inspect(valid_fields)}"
        end

      {_, except} when not is_nil(except) ->
        if !__valid_field?(except, valid_fields) do
          raise ArgumentError,
                "invalid :except value #{inspect(except)}. Expected one of: #{inspect(valid_fields)}"
        end

      _ ->
        :ok
    end
  end

  @doc false
  def __determine_fields_to_add__(opts, [field1, field2]) do
    case {Keyword.get(opts, :only), Keyword.get(opts, :except)} do
      {^field1, _} -> {true, false}
      {^field2, _} -> {false, true}
      {nil, ^field1} -> {false, true}
      {nil, ^field2} -> {true, false}
      _ -> {true, true}
    end
  end

  @doc false
  defmacro __add_audit_field__(field_name, add_references, on_delete, null_allowed) do
    quote do
      field = unquote(field_name)

      if unquote(add_references) do
        add(
          field,
          references(:user_role_mappings, type: :uuid, on_delete: unquote(on_delete)),
          null: unquote(null_allowed)
        )
      else
        add(field, :uuid, null: unquote(null_allowed))
      end
    end
  end

  @doc false
  defmacro __create_index__(table_name, fields, unique, opts) do
    quote do
      if unquote(unique) do
        create unique_index(unquote(table_name), unquote(fields), unquote(opts))
      else
        create index(unquote(table_name), unquote(fields), unquote(opts))
      end
    end
  end

  @doc false
  def __build_index_opts__(opts) do
    [
      name: Keyword.get(opts, :name),
      where: Keyword.get(opts, :where),
      unique: Keyword.get(opts, :unique),
      concurrently: Keyword.get(opts, :concurrently),
      using: Keyword.get(opts, :using),
      prefix: Keyword.get(opts, :prefix),
      include: Keyword.get(opts, :include)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc false
  def __should_index_group__(field_groups, only_groups, except_groups) do
    fn group ->
      group_exists? = group in field_groups

      case {only_groups, except_groups} do
        {[], []} -> group_exists?
        {only, []} when only != [] -> group in only and group_exists?
        {[], except} when except != [] -> group not in except and group_exists?
        _ -> group_exists?
      end
    end
  end

  @doc false
  def __maybe_add_where__(opts, nil), do: opts
  def __maybe_add_where__(opts, where), do: Keyword.put(opts, :where, where)

  @doc false
  def __should_add_field__(field, only, except) do
    cond do
      is_list(only) -> field in only
      is_atom(only) and not is_nil(only) -> field == only
      is_list(except) -> field not in except
      is_atom(except) and not is_nil(except) -> field != except
      true -> true
    end
  end

  @doc false
  def __resolve_scope__(scope_option) do
    case scope_option do
      nil -> nil
      :all -> nil
      :active -> "deleted_at IS NULL"
      :non_deleted -> "deleted_at IS NULL"
      :exclude_deleted -> "deleted_at IS NULL"
      :deleted -> "deleted_at IS NOT NULL"
      custom when is_binary(custom) -> custom
      _ -> raise ArgumentError, "invalid :scope value #{inspect(scope_option)}. Expected :all, :active, :non_deleted, :exclude_deleted, :deleted, or a custom string"
    end
  end

  defp __valid_field?(field, valid) when is_atom(field), do: field in valid
  defp __valid_field?(fields, valid) when is_list(fields), do: Enum.all?(fields, &(&1 in valid))
end
