defmodule Events.IExHelpers do
  @moduledoc """
  Convenience helpers that are automatically imported inside `.iex.exs`.
  """

  alias Events.{Repo, Cache, SystemHealth}

  @doc """
  Runs when IEx boots so we can show the health dashboard and helper list.
  """
  def on_startup do
    if Code.ensure_loaded?(SystemHealth) do
      Process.sleep(500)
      SystemHealth.display()
    end

    print_available_helpers()
  end

  @doc """
  Prints the helper overview banner.
  """
  def print_available_helpers do
    IO.puts("""
    Available helpers:
      - health()       : Display system health status
      - health_data()  : Get raw health data
      - db_check()     : Quick database check
      - cache_check()  : Quick cache check
      - redis_check()  : Quick Redis check
      - proxy_check()  : Show proxy configuration
      - mise_check()   : Show mise environment

    Migration & Schema Helpers:
      - migration_help()           : Migration system overview
      - migration_help(:fields)    : Field macros reference
      - migration_help(:indexes)   : Index creation helpers
      - migration_help(:examples)  : Complete migration examples
      - schema_help()              : Schema system overview
      - schema_help(:validation)   : All validation types & options
      - schema_help(:pipeline)     : Validation pipeline patterns

    Common aliases loaded:
      - Repo, Cache, SystemHealth
      - Endpoint, Router
    """)
  end

  @doc """
  Display system health status.
  """
  def health do
    SystemHealth.display()
  end

  @doc """
  Get raw system health data.
  """
  def health_data do
    SystemHealth.check_all()
  end

  @doc """
  Quick database connectivity check.
  """
  def db_check do
    case Repo.query("SELECT version()", []) do
      {:ok, result} ->
        version = result.rows |> List.first() |> List.first()
        IO.puts("✓ PostgreSQL connected: #{version}")

      {:error, error} ->
        IO.puts("✗ Database error: #{inspect(error)}")
    end
  end

  @doc """
  Quick cache health check.
  """
  def cache_check do
    try do
      Cache.put(:test, "hello", ttl: :timer.seconds(5))
      value = Cache.get(:test)
      Cache.delete(:test)

      if value == "hello" do
        IO.puts("✓ Cache operational")
      else
        IO.puts("✗ Cache returned unexpected value: #{inspect(value)}")
      end
    rescue
      e -> IO.puts("✗ Cache error: #{Exception.message(e)}")
    end
  end

  @doc """
  Quick Redis connectivity via Hammer.
  """
  def redis_check do
    case Hammer.check_rate("iex_check", 60_000, 1) do
      {:allow, _} -> IO.puts("✓ Redis connected via Hammer")
      {:deny, _} -> IO.puts("✓ Redis connected (rate limited)")
      {:error, reason} -> IO.puts("✗ Redis error: #{inspect(reason)}")
    end
  rescue
    e -> IO.puts("✗ Redis error: #{Exception.message(e)}")
  end

  @doc """
  Show proxy configuration summary.
  """
  def proxy_check do
    proxy_info = SystemHealth.proxy_config()

    IO.puts("\nProxy Configuration:")
    IO.puts("══════════════════════════════════════════════════════════")

    print_proxy_line("HTTP_PROXY", proxy_info.http_proxy)
    print_proxy_line("HTTPS_PROXY", proxy_info.https_proxy)
    print_proxy_line("NO_PROXY", proxy_info.no_proxy, allow_empty?: true)

    IO.puts("")

    if proxy_info.http_proxy || proxy_info.https_proxy do
      IO.puts("#{IO.ANSI.cyan()}Services Using Proxy:#{IO.ANSI.reset()}")

      Enum.each(proxy_info.services_using_proxy, fn service ->
        IO.puts("  • #{service}")
      end)

      IO.puts("")

      IO.puts(
        "#{IO.ANSI.light_black()}Note: PostgreSQL and Redis do not use HTTP proxies#{IO.ANSI.reset()}"
      )
    else
      IO.puts("#{IO.ANSI.yellow()}No proxy configured#{IO.ANSI.reset()}")
      IO.puts("All HTTP/HTTPS requests go directly to their destinations.\n")
    end
  end

  defp print_proxy_line(label, value, opts \\ [])

  defp print_proxy_line(label, nil, _opts) do
    IO.puts("  #{label}: #{IO.ANSI.light_black()}(not set)#{IO.ANSI.reset()}")
  end

  defp print_proxy_line(label, value, _opts) do
    IO.puts("  #{label}: #{IO.ANSI.green()}SET#{IO.ANSI.reset()}")
    IO.puts("             #{value}")
  end

  @doc """
  Show mise environment status.
  """
  def mise_check do
    mise_info = SystemHealth.mise_info()

    if mise_info.active do
      IO.puts("\n#{IO.ANSI.magenta()}Mise Environment#{IO.ANSI.reset()}")
      IO.puts("══════════════════════════════════════════════════════════")
      IO.puts("  Shell: #{IO.ANSI.cyan()}#{mise_info.shell}#{IO.ANSI.reset()}")

      if length(mise_info.tools) > 0 do
        IO.puts("")
        IO.puts("  #{IO.ANSI.cyan()}Managed Tools:#{IO.ANSI.reset()}")

        Enum.each(mise_info.tools, fn {tool, version} ->
          IO.puts("    • #{tool}: #{IO.ANSI.green()}#{version}#{IO.ANSI.reset()}")
        end)
      end

      if length(mise_info.env_vars) > 0 do
        IO.puts("")
        IO.puts("  #{IO.ANSI.cyan()}Environment Variables#{IO.ANSI.reset()}")

        Enum.each(mise_info.env_vars, fn {label, key, value} ->
          display_value =
            if String.contains?(String.downcase(label), ["secret", "key", "api"]) do
              "********"
            else
              value
            end

          IO.puts("    • #{key}: #{display_value}")
        end)
      end

      IO.puts("")
    else
      IO.puts("\n#{IO.ANSI.yellow()}Mise not detected#{IO.ANSI.reset()}")
      IO.puts("Mise environment manager is not active in this session.\n")
    end
  end

  # ============================================
  # Migration & Schema Documentation Helpers
  # ============================================

  @doc """
  Display migration system help.

  ## Topics
  - `:fields` - All field macros (type, status, audit, timestamps)
  - `:indexes` - Index creation helpers
  - `:examples` - Complete migration examples
  - `:soft_delete` - Soft delete patterns
  - `:types` - Field types reference
  - `:best_practices` - Migration best practices
  """
  def migration_help(topic \\ :general)

  def migration_help(:general) do
    IO.puts("""
    #{header("Events Migration System")}

    Two DSL styles available:
    1. Direct DSL - Call macros directly in create table blocks
    2. Pipeline DSL - Use token pattern for complex logic

    #{subsection("Quick Start - Direct DSL")}

      create table(:products, primary_key: false) do
        uuid_primary_key()
        add :name, :string, null: false
        type_fields(only: [:type])
        status_fields(only: [:status])
        soft_delete_fields()  # Includes deleted_by_user_role_mapping_id
        timestamps(type: :utc_datetime_usec)
      end

      type_field_indexes(:products)
      status_field_indexes(:products)

    #{subsection("Quick Start - Pipeline DSL")}

      create_table(:products)
      |> with_uuid_primary_key()
      |> with_type_fields(only: [:type])
      |> with_soft_delete()
      |> with_timestamps()
      |> Events.Migration.Executor.execute()

    #{subsection("Available Topics")}

    migration_help(:fields)         - Field macros
    migration_help(:indexes)        - Index helpers
    migration_help(:examples)       - Examples
    migration_help(:soft_delete)    - Soft delete
    migration_help(:types)          - Type reference
    migration_help(:best_practices) - Best practices
    """)
  end

  def migration_help(:fields) do
    IO.puts("""
    #{header("Field Macros")}

    #{subsection("Type Fields (citext)")}
      type_fields()                    # All: type, subtype, kind, category, variant
      type_fields(only: [:type])
      type_fields(except: [:variant])

    #{subsection("Status Fields (citext)")}
      status_fields()                  # All: status, substatus, state, etc.
      status_fields(only: [:status])
      status_fields(with_transition: true)  # Adds transition tracking

    #{subsection("Soft Delete (NEW DEFAULT!)")}
      soft_delete_fields()
      # Creates:
      #   - deleted_at (utc_datetime_usec)
      #   - deleted_by_user_role_mapping_id (uuid) ← ENABLED BY DEFAULT

      soft_delete_fields(track_user: true)      # Also adds deleted_by_user_id
      soft_delete_fields(track_reason: true)    # Also adds deletion_reason

    #{subsection("Audit Fields")}
      audit_fields()                         # created_by, updated_by
      audit_fields(track_user: true)         # Adds user IDs
      audit_fields(track_ip: true)           # Adds IP tracking
      audit_fields(track_changes: true)      # Adds change history

    #{subsection("Timestamps")}
      timestamps(type: :utc_datetime_usec)   # Use Ecto's with our type

    #{subsection("Others")}
      metadata_field()              # JSONB field
      tags_field()                  # String array
      money_field(:price)           # Decimal(10,2)
      belongs_to_field(:user)       # Foreign key

    For more: migration_help(:indexes)
    """)
  end

  def migration_help(:indexes) do
    IO.puts("""
    #{header("Index Helpers")}

    #{subsection("Field Macro Indexes")}
      type_field_indexes(:table)
      type_field_indexes(:table, only: [:type])

      status_field_indexes(:table)
      timestamp_indexes(:table)
      timestamp_indexes(:table, with_deleted: true)

      audit_field_indexes(:table, track_user: true)

    #{subsection("Special Indexes")}
      metadata_index(:table, :metadata)      # GIN for JSONB
      tags_index(:table, :tags)              # GIN for arrays
      foreign_key_index(:table, :user_id)

    #{subsection("Create All")}
      create_standard_indexes(:table)        # All standard indexes

    For more: migration_help(:examples)
    """)
  end

  def migration_help(:examples) do
    IO.puts("""
    #{header("Migration Examples")}

    #{subsection("E-commerce Product")}

      create table(:products, primary_key: false) do
        uuid_primary_key()
        add :name, :string, null: false
        add :sku, :string, null: false
        money_field(:price)

        type_fields(only: [:type, :category])
        status_fields(only: [:status])
        metadata_field(:attributes)
        tags_field()
        timestamps(type: :utc_datetime_usec)
      end

      create unique_index(:products, [:sku])
      create_standard_indexes(:products)

    #{subsection("User with Soft Delete")}

      create table(:users, primary_key: false) do
        uuid_primary_key()
        add :email, :citext, null: false

        status_fields(only: [:status])
        audit_fields(track_user: true)
        soft_delete_fields(track_reason: true)
        timestamps(type: :utc_datetime_usec)
      end

      create unique_index(:users, [:email])
      timestamp_indexes(:users, with_deleted: true)

    For more: migration_help(:soft_delete)
    """)
  end

  def migration_help(:soft_delete) do
    IO.puts("""
    #{header("Soft Delete Patterns")}

    #{subsection("NEW Default Behavior")}

      soft_delete_fields()
      # Creates:
      #   - deleted_at (utc_datetime_usec)
      #   - deleted_by_user_role_mapping_id (uuid) ← ENABLED BY DEFAULT

    #{subsection("Why User Role Mapping?")}

    Tracks which role performed the deletion:
    - Accurate role context at deletion time
    - Better audit trail
    - Security compliance

    #{subsection("Options")}

      soft_delete_fields(track_user: true)
      # Also adds: deleted_by_user_id

      soft_delete_fields(track_reason: true)
      # Also adds: deletion_reason (text)

      soft_delete_fields(track_role_mapping: false)
      # Opt-out of role mapping

    For more: migration_help(:types)
    """)
  end

  def migration_help(:types) do
    IO.puts("""
    #{header("Field Types")}

    Primary Keys:    :binary_id with uuidv7()
    Enums:           :citext (case-insensitive)
    Timestamps:      :utc_datetime_usec
    Text:            :string (varchar), :text
    Numbers:         :integer, :decimal
    JSON:            :jsonb (with GIN indexes)
    Arrays:          {:array, :string}
    Network:         :inet (IP addresses)

    For more: migration_help(:best_practices)
    """)
  end

  def migration_help(:best_practices) do
    IO.puts("""
    #{header("Best Practices")}

    ✅ DO:
    - Use uuid_primary_key() (UUIDv7)
    - Use citext for enums
    - Use utc_datetime_usec for timestamps
    - Add indexes for foreign keys
    - Use soft_delete_fields() for soft deletes

    ❌ DON'T:
    - Use NaiveDateTime (use DateTime/Date)
    - Use :string for enums (use :citext)
    - Forget to create indexes

    For full docs: migration_help()
    """)
  end

  def migration_help(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :fields, :indexes, :examples
    - :soft_delete, :types, :best_practices
    """)
  end

  @doc """
  Display schema system help.
  """
  def schema_help(topic \\ :general)

  def schema_help(:general) do
    IO.puts("""
    #{header("Events Schema System")}

    #{subsection("Basic Usage")}

      defmodule MyApp.Product do
        use Events.Schema
        import Events.Schema.FieldMacros

        schema "products" do
          field :name, :string

          type_fields(only: [:type])
          status_fields(only: [:status])
          soft_delete_fields()
          timestamps()
        end

        def changeset(product, attrs) do
          product
          |> cast(attrs, [:name, :type, :status])
          |> validate(:name, :required)
          |> validate(:type, :in, value: ["physical", "digital"])
          |> apply()
        end
      end

    #{subsection("Available Topics")}

    schema_help(:fields)      - Field macros reference
    schema_help(:validation)  - All validation types and options
    schema_help(:examples)    - Complete schema examples
    schema_help(:pipeline)    - Validation pipeline patterns
    """)
  end

  def schema_help(:fields) do
    IO.puts("""
    #{header("Schema Field Macros")}

      type_fields(only: [:type])
      status_fields(only: [:status])
      audit_fields()
      soft_delete_fields()  # Includes deleted_by_user_role_mapping_id
      metadata_field()
      tags_field()
    """)
  end

  def schema_help(:validation) do
    IO.puts("""
    #{header("Validation Reference")}

    #{subsection("String Validations")}
      validate(:field, :required)
      validate(:field, :email)
      validate(:field, :url)
      validate(:field, :uuid)
      validate(:field, :slug)
      validate(:field, :phone)
      validate(:field, :format, value: ~r/pattern/)
      validate(:field, :string, min_length: 3, max_length: 100)
      validate(:field, :string, format: ~r//, auto_trim: true)

      # Extended validators:
      validate_email(changeset, :email, required: true, unique: true)
      validate_url(changeset, :url, required: true)
      validate_slug(changeset, :slug, required: true)
      validate_phone(changeset, :phone, required: true)

    #{subsection("Number Validations")}
      validate(:field, :required)
      validate(:field, :number, min: 0, max: 100)
      validate(:field, :number, gt: 0, lt: 100)
      validate(:field, :positive)
      validate(:field, :non_negative)
      validate(:field, :min, value: 0)
      validate(:field, :max, value: 100)
      validate(:field, :in, value: [1, 2, 3])

      # Extended validators:
      validate_field(changeset, :age, gte: 18, lte: 120)
      validate_money(changeset, :price, min: 0, max: 999999.99)
      validate_percentage(changeset, :discount, min: 0, max: 100)

    #{subsection("Decimal Validations")}
      validate(:field, :decimal, min: 0, max: 1000)
      validate(:field, :decimal, precision: 10, scale: 2)
      validate_money(changeset, :amount, non_negative: true)

    #{subsection("Boolean Validations")}
      validate(:field, :boolean, acceptance: true)
      validate(:field, :acceptance)
      validate_boolean(changeset, :terms, acceptance: true)

    #{subsection("DateTime Validations")}
      validate(:field, :datetime, past: true)
      validate(:field, :datetime, future: true)
      validate(:field, :past)
      validate(:field, :future)
      validate(:field, :datetime, after: ~U[2024-01-01 00:00:00Z])
      validate(:field, :datetime, before: ~U[2024-12-31 23:59:59Z])

    #{subsection("Array Validations")}
      validate(:field, :array, min_length: 1, max_length: 10)
      validate(:field, :array, unique_items: true)
      validate_array(changeset, :tags, min_length: 1, unique_items: true)

    #{subsection("Map/JSON Validations")}
      validate(:field, :map, required_keys: [:key1, :key2])
      validate(:field, :map, forbidden_keys: [:admin])
      validate(:field, :map, min_keys: 1, max_keys: 10)
      validate_json(changeset, :metadata, required_keys: ["name"])

    #{subsection("Inclusion/Exclusion")}
      validate(:field, :inclusion, in: ["active", "pending"])
      validate(:field, :exclusion, not_in: ["deleted", "banned"])
      validate(:field, :in, value: ["option1", "option2"])
      validate_enum(changeset, :status, ["active", "pending", "archived"])

    #{subsection("Length Validations")}
      validate(:field, :min_length, value: 3)
      validate(:field, :max_length, value: 100)
      validate(:field, :length, value: 10)

    #{subsection("Unique Constraints")}
      validate(:field, :unique, value: true)
      validate_field(changeset, :email, unique: true)

    #{subsection("Cross-Field Validations")}
      validate(:field, :confirmation)  # Checks field_confirmation
      validate(:field, :comparison, operator: :>=, other_field: :end_date)
      validate_confirmation(changeset, :password, :password_confirmation)
      validate_comparison(changeset, :start_date, :<=, :end_date)
      validate_exclusive(changeset, [:email, :phone], at_least_one: true)

    #{subsection("Conditional Validations")}
      validate_if(changeset, :phone, :required, fn cs ->
        get_field(cs, :email) == nil
      end)

      validate_unless(changeset, :optional_field, :required, fn cs ->
        get_field(cs, :other_field) != nil
      end)

    #{subsection("Pipeline Style")}
      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email, :age, :status])
        |> validate(:email, :required, :email)
        |> validate(:age, :number, min: 18, max: 120)
        |> validate(:status, :in, value: ["active", "pending"])
        |> apply()
      end

    #{subsection("Extended Validation Style")}
      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email, :age, :price])
        |> validate_email(:email, required: true, unique: true)
        |> validate_field(:age, required: true, gte: 18, lte: 120)
        |> validate_money(:price, min: 0, positive: true)
      end

    For more: schema_help(:examples)
    """)
  end

  def schema_help(:examples) do
    IO.puts("""
    #{header("Schema Examples")}

    #{subsection("User Schema with Validations")}

      defmodule MyApp.User do
        use Events.Schema
        import Events.Schema.FieldMacros

        schema "users" do
          field :email, :string
          field :age, :integer
          field :phone, :string

          type_fields(only: [:type])
          status_fields(only: [:status])
          soft_delete_fields(track_reason: true)
          timestamps()
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs, [:email, :age, :phone, :type, :status])
          |> validate(:email, :required, :email)
          |> validate(:age, :number, min: 18, max: 120)
          |> validate(:phone, :phone)
          |> validate(:type, :in, value: ["admin", "user", "guest"])
          |> validate(:email, :unique, value: true)
          |> apply()
        end
      end

    #{subsection("Product Schema with Money Fields")}

      defmodule MyApp.Product do
        use Events.Schema
        import Events.Schema.FieldMacros

        schema "products" do
          field :name, :string
          field :sku, :string
          field :price, :decimal
          field :description, :string

          type_fields(only: [:type, :category])
          status_fields(only: [:status])
          metadata_field(:attributes)
          tags_field()
          soft_delete_fields()
          timestamps()
        end

        def changeset(product, attrs) do
          product
          |> cast(attrs, [:name, :sku, :price, :description, :type, :status])
          |> validate(:name, :required)
          |> validate(:sku, :required, :unique)
          |> validate(:price, :decimal, min: 0)
          |> validate(:description, :string, max_length: 500)
          |> validate(:type, :in, value: ["physical", "digital", "service"])
          |> apply()
        end
      end

    #{subsection("Order Schema with Cross-Field Validations")}

      defmodule MyApp.Order do
        use Events.Schema
        import Events.Schema.FieldMacros

        schema "orders" do
          field :order_number, :string
          field :start_date, :utc_datetime_usec
          field :end_date, :utc_datetime_usec
          field :total_amount, :decimal

          belongs_to :user, MyApp.User

          status_fields(only: [:status], with_transition: true)
          audit_fields(track_user: true)
          timestamps()
        end

        def changeset(order, attrs) do
          order
          |> cast(attrs, [:order_number, :start_date, :end_date, :total_amount, :status])
          |> validate(:order_number, :required, :unique)
          |> validate(:total_amount, :decimal, min: 0, precision: 10, scale: 2)
          |> validate(:start_date, :datetime, past: false)
          |> validate(:end_date, :datetime, future: true)
          |> validate(:start_date, :comparison, operator: :<=, other_field: :end_date)
          |> apply()
        end
      end

    For more: schema_help(:validation), schema_help(:pipeline)
    """)
  end

  def schema_help(:pipeline) do
    IO.puts("""
    #{header("Validation Pipeline Patterns")}

    #{subsection("Basic Pipeline")}

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email, :name])
        |> validate(:email, :required, :email)
        |> validate(:name, :required)
        |> apply()
      end

    #{subsection("Multiple Validations per Field")}

      def changeset(product, attrs) do
        product
        |> cast(attrs, [:name, :sku, :price])
        |> validate(:name, :required)
        |> validate(:name, :string, min_length: 3, max_length: 100)
        |> validate(:sku, :required)
        |> validate(:sku, :unique, value: true)
        |> validate(:price, :decimal, min: 0, max: 999999.99)
        |> apply()
      end

    #{subsection("Conditional Validations")}

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email, :phone, :type])
        |> validate(:email, :email)
        |> validate_exclusive([:email, :phone], at_least_one: true)
        |> validate_if(:phone, :required, fn cs ->
             get_field(cs, :type) == "sms_only"
           end)
        |> apply()
      end

    #{subsection("Cross-Field Validations")}

      def changeset(booking, attrs) do
        booking
        |> cast(attrs, [:start_date, :end_date, :password, :password_confirmation])
        |> validate(:start_date, :required, :datetime)
        |> validate(:end_date, :required, :datetime)
        |> validate(:start_date, :comparison, operator: :<=, other_field: :end_date)
        |> validate(:password, :confirmation)
        |> apply()
      end

    #{subsection("Extended Validators")}

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email, :phone, :website, :age, :discount])
        |> validate_email(:email, required: true, unique: true)
        |> validate_phone(:phone, required: false)
        |> validate_url(:website, required: false)
        |> validate_field(:age, gte: 18, lte: 120)
        |> validate_percentage(:discount, min: 0, max: 100)
      end

    #{subsection("Array and JSON Validations")}

      def changeset(article, attrs) do
        article
        |> cast(attrs, [:tags, :metadata])
        |> validate(:tags, :array, min_length: 1, max_length: 10, unique_items: true)
        |> validate(:metadata, :map, required_keys: [:author, :category])
        |> apply()
      end

    #{subsection("Global Validations")}

      def changeset(settings, attrs) do
        settings
        |> cast(attrs, [:email_notifications, :sms_notifications, :push_notifications])
        |> validate(:_global, :exclusive,
             fields: [:email_notifications, :sms_notifications],
             at_least_one: true)
        |> apply()
      end

    For more: schema_help(:validation), schema_help(:examples)
    """)
  end

  def schema_help(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :fields      - Field macros reference
    - :validation  - All validation types and options
    - :examples    - Complete schema examples
    - :pipeline    - Validation pipeline patterns
    """)
  end

  # Helper functions for formatting

  defp header(text) do
    "\n#{IO.ANSI.cyan()}#{IO.ANSI.bright()}#{text}#{IO.ANSI.reset()}\n#{String.duplicate("=", String.length(text))}\n"
  end

  defp subsection(text) do
    "\n#{IO.ANSI.yellow()}#{text}:#{IO.ANSI.reset()}"
  end
end
