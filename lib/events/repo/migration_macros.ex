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
  - `:except` - Exclude specific field groups (list of: `:name`, `:slug`, `:status`, `:description`, `:type_fields`, `:metadata`, `:audit_fields`, `:timestamps`)
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

      # Exclude multiple field groups
      create table(:simple_logs) do
        standard_entity_fields(except: [:slug, :description, :type_fields, :audit_fields])
        add :message, :text
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
      except_fields = List.wrap(Keyword.get(opts, :except, []))
      status_default = Keyword.get(opts, :status_default, "active")
      type_default = Keyword.get(opts, :type_default)

      # Name field
      cond do
        include_name and :name not in except_fields ->
          add(:name, :citext, null: false)

        true ->
          :ok
      end

      # Slug field
      cond do
        include_slug and :slug not in except_fields ->
          add(:slug, :citext, null: false)

        true ->
          :ok
      end

      # Status field
      cond do
        :status in except_fields ->
          :ok

        true ->
          add(:status, :citext, default: status_default, null: false)
      end

      # Description field
      cond do
        include_description and :description not in except_fields ->
          add(:description, :text)

        true ->
          :ok
      end

      # Type classification
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

      # Metadata
      cond do
        :metadata in except_fields ->
          :ok

        true ->
          metadata_field()
      end

      # Audit tracking
      cond do
        :audit_fields in except_fields ->
          :ok

        true ->
          audit_fields(Keyword.take(opts, [:null, :references, :on_delete]))
      end

      # Timestamps
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
  Creates indexes for type classification fields.

  ## Options

  - `:only` - Index only specific field (`:type` or `:subtype`)
  - `:except` - Skip indexing specific field
  - `:where` - Partial index condition
  - `:name` - Custom index name
  - `:unique` - Create unique index (default: false)
  - `:concurrently` - Create concurrently (default: false)
  - `:composite` - Create single composite index on `[:type, :subtype]` (default: false)

  ## Examples

      type_indexes(:products)
      # => create index(:products, [:type])
      # => create index(:products, [:subtype])

      type_indexes(:products, only: :type, where: "deleted_at IS NULL")
      # => create index(:products, [:type], where: "deleted_at IS NULL")

      type_indexes(:products, composite: true)
      # => create index(:products, [:type, :subtype])
  """
  defmacro type_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:type, :subtype])

      composite = Keyword.get(opts, :composite, false)
      unique = Keyword.get(opts, :unique, false)
      index_opts = Events.Repo.MigrationMacros.__build_index_opts__(opts)

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
  - `:where` - Partial index condition
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently

  ## Examples

      audit_indexes(:products)
      # => create index(:products, [:created_by_urm_id])
      # => create index(:products, [:updated_by_urm_id])

      audit_indexes(:products, only: :created_by_urm_id)
      # => create index(:products, [:created_by_urm_id])

      audit_indexes(:products, where: "deleted_at IS NULL", concurrently: true)
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

      index_opts = Events.Repo.MigrationMacros.__build_index_opts__(opts)

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
  - `:where` - Partial index condition
  - `:name` - Custom index name
  - `:concurrently` - Create concurrently
  - `:composite_with` - List of other fields to include in composite index

  ## Examples

      timestamp_indexes(:products)
      # => create index(:products, [:inserted_at])
      # => create index(:products, [:updated_at])

      timestamp_indexes(:products, only: :updated_at)
      # => create index(:products, [:updated_at])

      timestamp_indexes(:products, only: :updated_at, composite_with: [:status])
      # => create index(:products, [:status, :updated_at])
  """
  defmacro timestamp_indexes(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      Events.Repo.MigrationMacros.__validate_only_except__(opts, [:inserted_at, :updated_at])

      {add_inserted?, add_updated?} =
        Events.Repo.MigrationMacros.__determine_fields_to_add__(opts, [:inserted_at, :updated_at])

      composite_with = Keyword.get(opts, :composite_with)
      index_opts = Events.Repo.MigrationMacros.__build_index_opts__(opts)

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

  - `:name` - Custom index name
  - `:concurrently` - Create concurrently (recommended for large tables)
  - `:json_path` - Index specific JSON key instead of entire field
  - `:using` - Index method (default: :gin)

  ## Examples

      metadata_index(:products)
      # => create index(:products, [:metadata], using: :gin)

      metadata_index(:products, json_path: "status")
      # => create index(:products, [fragment("(metadata->>'status')")])

      metadata_index(:products, concurrently: true)
  """
  defmacro metadata_index(table_name, opts \\ []) do
    quote bind_quoted: [table_name: table_name, opts: opts] do
      json_path = Keyword.get(opts, :json_path)
      using = Keyword.get(opts, :using, :gin)
      base_opts = Events.Repo.MigrationMacros.__build_index_opts__(opts)

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

  defp __valid_field?(field, valid) when is_atom(field), do: field in valid
  defp __valid_field?(fields, valid) when is_list(fields), do: Enum.all?(fields, &(&1 in valid))
end
