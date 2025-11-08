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
  - `:type_default` - Default value for type field
  - `:subtype_default` - Default value for subtype field
  - `:null` - Allow NULL values (default: `true`)

  ## Examples

      # Both fields with defaults
      type_fields()
      # => add :type, :citext, null: true
      # => add :subtype, :citext, null: true

      # With default values
      type_fields(type_default: "standard", subtype_default: "basic")

      # Only type field
      type_fields(only: :type, type_default: "event")

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
      null_default = Keyword.get(opts, :null, true)
      only_field = Keyword.get(opts, :only)
      type_default = Keyword.get(opts, :type_default)
      subtype_default = Keyword.get(opts, :subtype_default)

      case only_field do
        :type ->
          add(:type, :citext, default: type_default, null: null_default)

        :subtype ->
          add(:subtype, :citext, default: subtype_default, null: null_default)

        nil ->
          add(:type, :citext, default: type_default, null: null_default)
          add(:subtype, :citext, default: subtype_default, null: null_default)
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
  - `:references` - Add foreign key constraints (default: `true`)
  - `:on_delete` - FK behavior when referenced record deleted (default: `:nilify_all`)
  - `:null` - Allow NULL values (default: `true`)

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
      only_field = Keyword.get(opts, :only)
      add_references = Keyword.get(opts, :references, true)
      on_delete_action = Keyword.get(opts, :on_delete, :nilify_all)
      null_allowed = Keyword.get(opts, :null, true)

      case {add_references, only_field} do
        # With foreign key constraints
        {true, :created_by_urm_id} ->
          add(
            :created_by_urm_id,
            references(:user_role_mappings, type: :uuid, on_delete: on_delete_action),
            null: null_allowed
          )

        {true, :updated_by_urm_id} ->
          add(
            :updated_by_urm_id,
            references(:user_role_mappings, type: :uuid, on_delete: on_delete_action),
            null: null_allowed
          )

        {true, nil} ->
          add(
            :created_by_urm_id,
            references(:user_role_mappings, type: :uuid, on_delete: on_delete_action),
            null: null_allowed
          )

          add(
            :updated_by_urm_id,
            references(:user_role_mappings, type: :uuid, on_delete: on_delete_action),
            null: null_allowed
          )

        # Without foreign key constraints
        {false, :created_by_urm_id} ->
          add(:created_by_urm_id, :uuid, null: null_allowed)

        {false, :updated_by_urm_id} ->
          add(:updated_by_urm_id, :uuid, null: null_allowed)

        {false, nil} ->
          add(:created_by_urm_id, :uuid, null: null_allowed)
          add(:updated_by_urm_id, :uuid, null: null_allowed)
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
  - `:references` - Add FK constraint for deleted_by_urm_id (default: `true`)
  - `:on_delete` - FK behavior when referenced record deleted (default: `:nilify_all`)
  - `:null` - Allow NULL values (default: `true` - records start undeleted)

  ## Examples

      # Both fields (timestamp + who deleted)
      deleted_fields()
      # => add :deleted_at, :utc_datetime_usec, null: true
      # => add :deleted_by_urm_id, references(:user_role_mappings, ...), null: true

      # Only timestamp (no audit tracking)
      deleted_fields(only: :deleted_at)

      # Only who deleted (unusual, but supported)
      deleted_fields(only: :deleted_by_urm_id)

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
      only_field = Keyword.get(opts, :only)
      add_references = Keyword.get(opts, :references, true)
      on_delete_action = Keyword.get(opts, :on_delete, :nilify_all)
      null_allowed = Keyword.get(opts, :null, true)

      case {only_field, add_references} do
        # Only deleted_at
        {:deleted_at, _} ->
          add(:deleted_at, :utc_datetime_usec, null: null_allowed)

        # Only deleted_by_urm_id with FK
        {:deleted_by_urm_id, true} ->
          add(
            :deleted_by_urm_id,
            references(:user_role_mappings, type: :uuid, on_delete: on_delete_action),
            null: null_allowed
          )

        # Only deleted_by_urm_id without FK
        {:deleted_by_urm_id, false} ->
          add(:deleted_by_urm_id, :uuid, null: null_allowed)

        # Both fields with FK
        {nil, true} ->
          add(:deleted_at, :utc_datetime_usec, null: null_allowed)

          add(
            :deleted_by_urm_id,
            references(:user_role_mappings, type: :uuid, on_delete: on_delete_action),
            null: null_allowed
          )

        # Both fields without FK
        {nil, false} ->
          add(:deleted_at, :utc_datetime_usec, null: null_allowed)
          add(:deleted_by_urm_id, :uuid, null: null_allowed)
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

  ## Examples

      timestamps()
      # => add :inserted_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
      # => add :updated_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")

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
  defmacro timestamps do
    quote do
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP"))
    end
  end

  # ==============================================================================
  # PUBLIC API - Standard Entity Fields
  # ==============================================================================

  @doc """
  Adds a complete set of standard fields for typical business entities.

  Combines common field patterns into a single macro for consistent entity
  definitions across the application. Includes name, slug, status, description,
  type classification, metadata, audit tracking, and timestamps.

  **Important**: Requires PostgreSQL citext extension for case-insensitive fields.
  Enable with: `execute "CREATE EXTENSION IF NOT EXISTS citext"`

  ## Fields Added

  | Field | Type | Options | Description |
  |-------|------|---------|-------------|
  | `name` | citext | null: false | Entity display name (case-insensitive) |
  | `slug` | citext | null: false | URL-friendly identifier (case-insensitive) |
  | `status` | citext | default: "active", null: false | Entity lifecycle state |
  | `description` | text | null: true | Long-form description |
  | `type` | citext | null: true | Primary classification |
  | `subtype` | citext | null: true | Secondary classification |
  | `metadata` | jsonb | default: {} | Flexible attributes |
  | `created_by_urm_id` | uuid | null: true | Creator reference |
  | `updated_by_urm_id` | uuid | null: true | Last updater reference |
  | `inserted_at` | timestamp | null: false | Creation timestamp |
  | `updated_at` | timestamp | null: false | Update timestamp |

  **Note**: Does NOT add `id` field - use `table()` macro which automatically
  adds UUIDv7 primary key.

  ## Options

  - `:include_name` - Add name field (default: `true`)
  - `:include_slug` - Add slug field (default: `true`)
  - `:include_description` - Add description field (default: `true`)
  - `:status_default` - Default status value (default: `"active"`)
  - `:type_default` - Default type value (default: `nil`)
  - `:null` - Allow NULL for audit fields (default: `true`)
  - `:references` - Add FK constraints for audit fields (default: `true`)

  ## Examples

      # Full standard entity
      create table(:products) do
        standard_entity_fields()
        add :price, :decimal, null: false
      end

      # Without slug (simple lookup tables)
      create table(:categories) do
        standard_entity_fields(include_slug: false)
        add :parent_id, references(:categories, type: :uuid)
      end

      # With custom status
      create table(:accounts) do
        standard_entity_fields(status_default: "pending")
        add :balance, :decimal
      end

      # With required audit trail
      create table(:transactions) do
        standard_entity_fields(null: false)  # FK references are default
        add :amount, :decimal, null: false
      end

      # Minimal entity (no name/slug)
      create table(:events) do
        standard_entity_fields(include_name: false, include_slug: false)
        add :title, :string, null: false
        add :starts_at, :utc_datetime_usec
      end

  ## Typical Indexes

      # Always index slugs (if included)
      create unique_index(:products, [:slug])

      # Common query patterns
      create index(:products, [:status])
      create index(:products, [:type])
      create index(:products, [:created_by_urm_id])

      # Composite indexes for filtered queries
      create index(:products, [:type, :status])
      create index(:products, [:status, :updated_at])

  ## Schema Definition

      defmodule Events.Catalog.Product do
        use Ecto.Schema

        schema "products" do
          field :name, :string
          field :slug, :string
          field :status, :string
          field :description, :string
          field :type, :string
          field :subtype, :string
          field :metadata, :map

          field :price, :decimal

          belongs_to :created_by_urm, Events.Accounts.UserRoleMapping,
            foreign_key: :created_by_urm_id
          belongs_to :updated_by_urm, Events.Accounts.UserRoleMapping,
            foreign_key: :updated_by_urm_id

          timestamps(type: :utc_datetime_usec)
        end
      end

  ## Customization After Generation

      create table(:products) do
        # Use standard fields
        standard_entity_fields()

        # Add domain-specific fields
        add :price, :decimal, null: false
        add :sku, :string
        add :inventory_count, :integer, default: 0

        # Override status constraint
        # ALTER TABLE products ADD CONSTRAINT ...
      end

      # Add constraints
      create constraint(:products, :price_must_be_positive, check: "price > 0")
      create constraint(:products, :valid_status,
        check: "status IN ('draft', 'active', 'archived')")
  """
  defmacro standard_entity_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      include_name = Keyword.get(opts, :include_name, true)
      include_slug = Keyword.get(opts, :include_slug, true)
      include_description = Keyword.get(opts, :include_description, true)
      status_default = Keyword.get(opts, :status_default, "active")
      type_default = Keyword.get(opts, :type_default)

      # Name and slug fields (case-insensitive)
      if include_name, do: add(:name, :citext, null: false)
      if include_slug, do: add(:slug, :citext, null: false)

      # Status and description
      add(:status, :citext, default: status_default, null: false)
      if include_description, do: add(:description, :text)

      # Type classification
      type_opts = if type_default, do: [type_default: type_default], else: []
      type_fields(type_opts)

      # Metadata
      metadata_field()

      # Audit tracking (pass through null and references options)
      audit_fields(Keyword.take(opts, [:null, :references, :on_delete]))

      # Timestamps
      timestamps()
    end
  end
end
