defmodule OmMigration.Help do
  @moduledoc """
  Interactive help system for migrations with live documentation.

  Provides comprehensive help, examples, and patterns for using
  the migration system effectively.
  """

  @topics %{
    general: :general_help,
    pipeline: :pipeline_help,
    fields: :fields_help,
    indexes: :indexes_help,
    dsl: :dsl_help,
    examples: :examples_help,
    patterns: :patterns_help
  }

  @doc """
  Shows help for the specified topic.

  ## Available Topics
  - `:general` - Overview and philosophy
  - `:pipeline` - Pipeline functions
  - `:fields` - Field helpers
  - `:indexes` - Index creation
  - `:dsl` - DSL syntax
  - `:examples` - Complete examples
  - `:patterns` - Common patterns
  """
  def show(topic \\ :general) do
    case Map.get(@topics, topic) do
      nil ->
        IO.puts("Unknown topic: #{topic}")
        IO.puts("\nAvailable topics:")
        list_topics()

      func_name ->
        apply(__MODULE__, func_name, [])
    end
  end

  @doc """
  Lists all available help topics.
  """
  def list_topics do
    IO.puts("""

    Available Help Topics
    =====================

    OmMigration.help(:general)   - Overview and philosophy
    OmMigration.help(:pipeline)  - Pipeline functions
    OmMigration.help(:fields)    - Field helpers
    OmMigration.help(:indexes)   - Index creation
    OmMigration.help(:dsl)       - DSL syntax
    OmMigration.help(:examples)  - Complete examples
    OmMigration.help(:patterns)  - Common patterns
    """)
  end

  # ============================================
  # Help Content
  # ============================================

  def general_help do
    IO.puts("""

    Events Migration System
    =======================

    A clean, composable migration system using token patterns and pipelines.

    ## Philosophy

    Migrations flow through pipelines, with each function adding or modifying
    the migration token. This creates a composable, testable system.

    ## Basic Usage

    ### Pipeline Style

        create_table(:users)
        |> with_uuid_primary_key()
        |> with_identity([:name, :email])
        |> with_authentication()
        |> with_timestamps()
        |> execute()

    ### DSL Style

        table :users do
          uuid_primary_key()

          field :email, :citext, unique: true
          field :username, :citext, unique: true

          has_authentication()
          has_timestamps()
        end

    ## Key Concepts

    1. **Token Pattern**: Migrations are tokens that flow through pipelines
    2. **Composition**: Build complex migrations from simple functions
    3. **Pattern Matching**: Clean handling of options and configurations
    4. **Type Safety**: Tokens are validated before execution

    ## Getting Started

    1. Add `use OmMigration` to your migration module
    2. Choose pipeline or DSL style
    3. Compose your migration using available functions
    4. Execute the migration

    For more help: OmMigration.help(:examples)
    """)
  end

  def pipeline_help do
    IO.puts("""

    Pipeline Functions
    ==================

    Functions that transform migration tokens in a pipeline.

    ## Primary Keys

        with_uuid_primary_key()     - UUIDv7 (PostgreSQL 18+)
        with_uuid_v4_primary_key()  - Legacy UUID v4

    ## Identity & Authentication

        with_identity(fields)        - Name, email, username, phone
        with_authentication()        - Password-based auth
        with_authentication(type: :oauth)  - OAuth fields
        with_authentication(type: :magic_link)  - Magic link auth

    ## Profile & Content

        with_profile(fields)         - Bio, avatar, location
        with_metadata()              - JSONB metadata field
        with_tags()                  - Array of tags
        with_settings()              - JSONB settings

    ## Business Fields

        with_money(fields)           - Decimal money fields
        with_status()                - Status with constraints
        with_status(values: [...])  - Custom status values

    ## Tracking & Audit

        with_audit()                 - Created/updated by
        with_audit(track_user: true) - With user references
        with_soft_delete()           - Soft delete capability
        with_timestamps()            - Created/updated at

    ## Index Modifiers

        unique()                     - Make index unique
        where("condition")           - Partial index
        using(:gin)                  - Index method

    ## Composition Helpers

        maybe(fun, condition)        - Conditional application
        tap_inspect(label)           - Debug pipeline
        validate!()                  - Validate token

    ## Examples

        create_table(:products)
        |> with_uuid_primary_key()
        |> with_money([:price, :cost, :tax])
        |> with_status(values: ["draft", "published", "archived"])
        |> with_metadata(name: :specifications)
        |> with_audit(track_user: true)
        |> maybe(&with_soft_delete/1, opts[:soft_delete])
        |> with_timestamps()
        |> execute()
    """)
  end

  def fields_help do
    IO.puts("""

    Field Helpers
    =============

    Functions for generating common field sets.

    ## Name Fields

        Fields.name_fields()
        Fields.name_fields(type: :citext, required: true)

        Generates:
        - first_name
        - last_name
        - display_name
        - full_name

    ## Address Fields

        Fields.address_fields()
        Fields.address_fields(prefix: :billing)

        Generates:
        - street, street2
        - city, state
        - postal_code, country

    ## Geolocation Fields

        Fields.geo_fields()
        Fields.geo_fields(with_altitude: true)
        Fields.geo_fields(prefix: :venue)

        Generates:
        - latitude, longitude
        - altitude (optional)
        - accuracy (optional)

    ## Contact Fields

        Fields.contact_fields()
        Fields.contact_fields(prefix: :primary)

        Generates:
        - email, phone
        - mobile, fax

    ## Social Media Fields

        Fields.social_fields()

        Generates:
        - website, twitter
        - facebook, instagram
        - linkedin, github, youtube

    ## SEO Fields

        Fields.seo_fields()

        Generates:
        - meta_title, meta_description
        - meta_keywords, canonical_url
        - og_title, og_description, og_image

    ## File Attachment Fields

        Fields.file_fields(:avatar)
        Fields.file_fields(:document, with_metadata: true)

        Generates:
        - {name}_url, {name}_key
        - {name}_name, {name}_size (with metadata)
        - {name}_content_type, {name}_uploaded_at

    ## Counter Fields

        Fields.counter_fields([:views, :likes])
        Fields.counter_field(:stock_quantity)

        Generates integer fields with default: 0

    ## Money Fields

        Fields.money_fields([:price, :tax, :total])
        Fields.money_fields([:amount], precision: 12, scale: 4)

        Generates decimal fields with precision
    """)
  end

  def indexes_help do
    IO.puts("""

    Index Creation
    ==============

    Creating and configuring indexes.

    ## Basic Indexes

        create_index(:users, [:email])
        create_index(:products, [:category, :status])

    ## Unique Indexes

        create_index(:users, [:email])
        |> unique()

    ## Partial Indexes

        create_index(:users, [:email])
        |> where("deleted_at IS NULL")

    ## GIN Indexes (for JSONB/Arrays)

        create_index(:products, [:metadata])
        |> using(:gin)

    ## Composite Patterns

        # Unique active records
        create_index(:users, [:email])
        |> unique()
        |> where("deleted_at IS NULL")

        # GIN index for tags
        create_index(:articles, [:tags])
        |> using(:gin)

    ## In DSL

        table :users do
          field :email, :citext

          index [:email], unique: true
          index [:status], where: "deleted_at IS NULL"
          unique_index [:username]
        end

    ## Common Patterns

        # Foreign key index
        belongs_to :user, :users  # Creates index automatically

        # Soft delete active records
        index [:id], where: "deleted_at IS NULL"

        # Status filtering
        index [:status], where: "status IN ('active', 'published')"

        # Timestamp ordering
        index [:created_at], order: :desc

        # Full-text search
        index [:title, :content], using: :gin
    """)
  end

  def dsl_help do
    IO.puts("""

    DSL Syntax
    ==========

    Declarative syntax for defining migrations.

    ## Table Definition

        table :users do
          uuid_primary_key()

          field :email, :citext, null: false
          field :username, :citext, null: false

          has_authentication()
          has_profile()
          has_audit(track_user: true)
          has_soft_delete()
          timestamps()

          index [:email], unique: true
          unique_index [:username]
        end

    ## Available Macros

        # Primary Key
        uuid_primary_key()

        # Field Definition
        field :name, :type, options
        fields [list_of_field_tuples]

        # Relationships
        belongs_to :user, :users
        belongs_to :org, :organizations, on_delete: :cascade

        # Feature Sets
        has_authentication(type: :password)
        has_profile([:bio, :avatar, :location])
        has_audit(track_user: true, track_role: true)
        has_soft_delete(track_reason: true)
        has_metadata(name: :properties)
        has_tags()
        has_settings()
        has_status(values: [...])
        has_money([:price, :tax, :total])

        # Timestamps
        timestamps()
        timestamps(type: :utc_datetime_usec)

        # Indexes
        index [:field1, :field2], options
        unique_index [:field]

        # Constraints
        check_constraint :age_check, "age >= 18"
        constraint :name, :type, options

    ## Complete Example

        table :products do
          uuid_primary_key()

          # Identity
          field :sku, :string, null: false
          field :name, :string, null: false
          field :slug, :string

          # Relationships
          belongs_to :category, :categories
          belongs_to :vendor, :vendors

          # Business fields
          has_money([:cost, :price, :sale_price])
          has_status(values: ["draft", "active", "discontinued"])

          # Metadata
          has_metadata(name: :specifications)
          has_tags()

          # Tracking
          has_audit(track_user: true)
          has_soft_delete()
          timestamps()

          # Indexes
          unique_index [:sku]
          unique_index [:slug]
          index [:category_id, :status]
          index [:status], where: "deleted_at IS NULL"
        end
    """)
  end

  def examples_help do
    IO.puts("""

    Complete Examples
    =================

    Real-world migration examples.

    ## User Table

        defmodule CreateUsers do
          use OmMigration

          def change do
            create_table(:users)
            |> with_uuid_primary_key()
            |> with_identity([:name, :email, :username])
            |> with_authentication()
            |> with_profile([:bio, :avatar])
            |> with_settings()
            |> with_audit()
            |> with_soft_delete()
            |> with_timestamps()
            |> execute()
          end
        end

    ## Product Table (DSL)

        defmodule CreateProducts do
          use OmMigration

          def change do
            table :products do
              uuid_primary_key()

              field :sku, :string, null: false
              field :name, :string, null: false
              field :description, :text

              belongs_to :category, :categories

              has_money([:cost, :price])
              has_status(values: ["draft", "published", "archived"])
              has_metadata(name: :attributes)
              has_tags()

              has_audit(track_user: true)
              timestamps()

              unique_index [:sku]
              index [:category_id, :status]
            end
          end
        end

    ## Order Table (Pipeline)

        defmodule CreateOrders do
          use OmMigration

          def change do
            create_table(:orders)
            |> with_uuid_primary_key()
            |> Token.add_field(:order_number, :string, null: false)
            |> Token.add_field(:customer_id, :binary_id, null: false)
            |> Token.add_field(:shipping_address_id, :binary_id)
            |> with_status(values: [
                "pending", "confirmed", "processing",
                "shipped", "delivered", "cancelled"
              ])
            |> Token.add_field(:placed_at, :utc_datetime, null: false)
            |> Token.add_field(:shipped_at, :utc_datetime)
            |> Token.add_field(:delivered_at, :utc_datetime)
            |> with_money([:subtotal, :tax, :shipping, :total])
            |> with_metadata(name: :line_items)
            |> with_settings(name: :customer_notes)
            |> with_audit(track_user: true)
            |> with_timestamps()
            |> Token.add_index(:orders_number_unique, [:order_number], unique: true)
            |> Token.add_index(:orders_customer_idx, [:customer_id])
            |> Token.add_index(:orders_status_idx, [:status])
            |> execute()
          end
        end

    ## Multi-tenant Table

        defmodule CreateTenantData do
          use OmMigration

          def change do
            table :projects do
              uuid_primary_key()

              belongs_to :tenant, :tenants, null: false
              belongs_to :owner, :users, null: false

              field :name, :string, null: false
              field :slug, :string, null: false

              has_status()
              has_metadata()
              has_settings()
              has_audit(track_user: true)
              has_soft_delete()
              timestamps()

              # Multi-tenant indexes
              unique_index [:tenant_id, :slug]
              index [:tenant_id, :status]
              index [:tenant_id, :owner_id]
              index [:tenant_id, :deleted_at]
            end
          end
        end
    """)
  end

  def patterns_help do
    IO.puts("""

    Common Patterns
    ===============

    Best practices and patterns for migrations.

    ## PostgreSQL 18 with UUIDv7

        # Enable in first migration
        execute "CREATE EXTENSION IF NOT EXISTS citext"

        # Use UUIDv7 for all tables
        with_uuid_primary_key()  # Uses uuidv7()

    ## Soft Delete Pattern

        # In migration
        with_soft_delete(track_user: true, track_reason: true)

        # Active records index
        Token.add_index(:active_idx, [:id], where: "deleted_at IS NULL")

    ## Multi-tenant Pattern

        table :tenant_resources do
          belongs_to :tenant, :tenants, null: false

          # All indexes include tenant_id
          index [:tenant_id, :status]
          index [:tenant_id, :created_at]
          unique_index [:tenant_id, :slug]
        end

    ## Audit Trail Pattern

        with_audit(track_user: true, track_role: true)

        # Consider adding
        Token.add_field(:ip_address, :inet)
        Token.add_field(:user_agent, :string)
        Token.add_field(:action, :string)

    ## Hierarchical Data

        table :categories do
          uuid_primary_key()

          field :name, :string, null: false
          field :slug, :string, null: false

          belongs_to :parent, :categories
          field :path, :string  # Materialized path
          field :depth, :integer, default: 0
          field :position, :integer, default: 0

          index [:parent_id]
          index [:path]
          unique_index [:parent_id, :slug]
        end

    ## Event Sourcing

        table :events do
          uuid_primary_key()

          field :aggregate_id, :binary_id, null: false
          field :aggregate_type, :string, null: false
          field :event_type, :string, null: false
          field :event_version, :integer, null: false
          field :event_data, :jsonb, null: false
          field :event_metadata, :jsonb, default: %{}
          field :occurred_at, :utc_datetime_usec, null: false

          timestamps(updated_at: false)  # Events are immutable

          index [:aggregate_id, :event_version]
          index [:aggregate_type, :aggregate_id]
          index [:event_type]
          index [:occurred_at]
        end

    ## Search Optimization

        # Full-text search
        Token.add_field(:search_vector, :tsvector)
        Token.add_index(:search_idx, [:search_vector], using: :gin)

        # Create trigger for updating search vector
        execute \"\"\"
        CREATE TRIGGER update_search_vector
        BEFORE INSERT OR UPDATE ON table_name
        FOR EACH ROW EXECUTE FUNCTION
        tsvector_update_trigger(search_vector, 'pg_catalog.english', title, content);
        \"\"\"

    ## Performance Tips

    1. Index foreign keys
    2. Use partial indexes for filtered queries
    3. Use GIN for JSONB/array columns
    4. Consider composite indexes for common query patterns
    5. Add indexes after inserting seed data
    """)
  end
end
