defmodule Events.Dev.IExHelpers do
  @moduledoc """
  Convenience helpers that are automatically imported inside `.iex.exs`.
  """

  alias Events.Data.{Repo, Cache}
  alias Events.Observability.SystemHealth

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
    #{IO.ANSI.cyan()}System Health#{IO.ANSI.reset()}
      - health()       : Display system health status
      - health_data()  : Get raw health data
      - db_check()     : Quick database check
      - cache_check()  : Quick cache check
      - redis_check()  : Quick Redis check
      - proxy_check()  : Show proxy configuration
      - mise_check()   : Show mise environment

    #{IO.ANSI.cyan()}Migration & Schema#{IO.ANSI.reset()}
      - migration_help()           : Migration system overview
      - migration_help(:fields)    : Field macros reference
      - migration_help(:indexes)   : Index creation helpers
      - migration_help(:examples)  : Complete migration examples
      - schema_help()              : Schema system overview
      - schema_help(:validation)   : All validation types & options
      - schema_help(:pipeline)     : Validation pipeline patterns

    #{IO.ANSI.cyan()}Functional Types#{IO.ANSI.reset()}
      - functional_help()          : Functional modules overview
      - functional_help(:result)   : Result type reference
      - functional_help(:maybe)    : Maybe type reference
      - functional_help(:pipeline) : Pipeline patterns
      - functional_help(:async)    : AsyncResult reference
      - functional_help(:guards)   : Guards and pattern matching

    #{IO.ANSI.cyan()}CRUD System#{IO.ANSI.reset()}
      - crud_help()                : CRUD system overview
      - crud_help(:basic)          : Basic operations
      - crud_help(:multi)          : Multi (transactions)
      - crud_help(:merge)          : Merge (upserts)
      - crud_help(:options)        : Common options
      - crud_help(:examples)       : Real-world examples

    #{IO.ANSI.cyan()}Workflow System#{IO.ANSI.reset()}
      - workflow_help()            : Workflow system overview
      - workflow_help(:quickstart) : Quick start guide
      - workflow_help(:steps)      : Step configuration
      - workflow_help(:decorator)  : Decorator API
      - workflow_help(:rollback)   : Saga pattern rollbacks

    #{IO.ANSI.cyan()}Decorator System#{IO.ANSI.reset()}
      - decorator_help()           : Decorator system overview
      - decorator_help(:cache)     : Cache decorators
      - decorator_help(:telemetry) : Telemetry decorators
      - decorator_help(:types)     : Type decorators

    #{IO.ANSI.cyan()}IEx Examples#{IO.ANSI.reset()}
      - examples()                 : Show practical IEx examples
      - examples(:result)          : Result examples
      - examples(:crud)            : CRUD examples
      - examples(:workflow)        : Workflow examples

    #{IO.ANSI.cyan()}Common Aliases Loaded#{IO.ANSI.reset()}
      - Repo, Cache, Query, Crud, Multi, Merge
      - Result, Maybe, Pipeline, AsyncResult, Guards
      - Workflow, Decorator, SystemHealth, S3
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
  Quick Redis connectivity via RateLimiter.
  """
  def redis_check do
    alias Events.Services.RateLimiter

    case RateLimiter.check("iex_check", 60_000, 1) do
      {:allow, _} -> IO.puts("✓ RateLimiter connected")
      {:deny, _} -> IO.puts("✓ RateLimiter connected (rate limited)")
    end
  rescue
    e -> IO.puts("✗ RateLimiter error: #{Exception.message(e)}")
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
      |> Events.Core.Migration.Executor.execute()

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
      audit_fields()                         # created_by_urm_id, updated_by_urm_id
      audit_fields(track_urm: false)         # No URM fields
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
        use OmSchema

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
        use OmSchema

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
        use OmSchema

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
        use OmSchema

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

  # ============================================
  # Functional Types Documentation Helpers
  # ============================================

  @doc """
  Display functional types help.

  ## Topics
  - `:result` - Result type for error handling
  - `:maybe` - Maybe type for optional values
  - `:pipeline` - Pipeline for multi-step workflows
  - `:async` - AsyncResult for concurrent operations
  - `:guards` - Guards and pattern matching
  """
  def functional_help(topic \\ :general)

  def functional_help(:general) do
    IO.puts("""
    #{header("Functional Types System")}

    #{subsection("Core Modules")}

      alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Guards}

    #{subsection("Result - Error Handling")}

      {:ok, user}
      |> Result.and_then(&validate/1)
      |> Result.and_then(&save/1)
      |> Result.map(&format/1)
      |> Result.unwrap_or(default_user())

    #{subsection("Maybe - Optional Values")}

      Maybe.from_nilable(user)
      |> Maybe.map(&format/1)
      |> Maybe.unwrap_or("Unknown")

    #{subsection("Pipeline - Multi-Step Workflows")}

      Pipeline.new(%{user_id: 123})
      |> Pipeline.step(:fetch, &fetch_user/1)
      |> Pipeline.step(:validate, &validate/1)
      |> Pipeline.run()

    #{subsection("AsyncResult - Concurrent Operations")}

      AsyncResult.parallel([
        fn -> fetch_user(id) end,
        fn -> fetch_orders(id) end
      ])

    #{subsection("Available Topics")}

    functional_help(:result)   - Result type reference
    functional_help(:maybe)    - Maybe type reference
    functional_help(:pipeline) - Pipeline patterns
    functional_help(:async)    - AsyncResult reference
    functional_help(:guards)   - Guards and patterns
    """)
  end

  def functional_help(:result) do
    IO.puts("""
    #{header("Result Type")}

    #{subsection("Basic Usage")}

      alias FnTypes.Result

      # Chain operations
      {:ok, user}
      |> Result.and_then(&validate_user/1)
      |> Result.and_then(&save_user/1)
      |> Result.map(&format_response/1)

      # Unwrap with default
      Result.unwrap_or(result, default_value)

      # Collect multiple results
      Result.collect([{:ok, 1}, {:ok, 2}])  # {:ok, [1, 2]}

      # Safe exception handling
      Result.try_with(fn -> risky_operation() end)

    #{subsection("Common Functions")}

      Result.ok(value)          # Create {:ok, value}
      Result.error(reason)      # Create {:error, reason}
      Result.map(result, fn)    # Transform ok value
      Result.and_then(result, fn) # Chain fallible operations
      Result.or_else(result, fn)  # Provide fallback
      Result.unwrap!(result)    # Unwrap or raise
      Result.collect(results)   # Combine multiple results

    For more: functional_help(:pipeline)
    """)
  end

  def functional_help(:maybe) do
    IO.puts("""
    #{header("Maybe Type")}

    #{subsection("Basic Usage")}

      alias FnTypes.Maybe

      # From nilable value
      Maybe.from_nilable(nil)    # :none
      Maybe.from_nilable("val")  # {:some, "val"}

      # Safe nested access
      user
      |> Maybe.from_nilable()
      |> Maybe.and_then(&Maybe.from_nilable(&1.address))
      |> Maybe.and_then(&Maybe.from_nilable(&1.city))
      |> Maybe.unwrap_or("Unknown")

      # Map over value
      {:some, "hello"}
      |> Maybe.map(&String.upcase/1)  # {:some, "HELLO"}

    #{subsection("Common Functions")}

      Maybe.some(value)         # Create {:some, value}
      Maybe.none()              # Create :none
      Maybe.map(maybe, fn)      # Transform some value
      Maybe.and_then(maybe, fn) # Chain operations
      Maybe.filter(maybe, fn)   # Filter by predicate
      Maybe.unwrap_or(maybe, default) # Get value or default

    For more: functional_help(:guards)
    """)
  end

  def functional_help(:pipeline) do
    IO.puts("""
    #{header("Pipeline")}

    #{subsection("Basic Pipeline")}

      alias FnTypes.Pipeline

      Pipeline.new(%{user_id: 123})
      |> Pipeline.step(:fetch_user, fn ctx ->
        case Repo.get(User, ctx.user_id) do
          nil -> {:error, :not_found}
          user -> {:ok, %{user: user}}
        end
      end)
      |> Pipeline.step(:validate, &validate_user/1)
      |> Pipeline.step(:send_email, &send_welcome/1)
      |> Pipeline.run()

    #{subsection("With Rollback")}

      Pipeline.new(%{})
      |> Pipeline.step(:reserve, &reserve/1, rollback: &release/1)
      |> Pipeline.step(:charge, &charge/1, rollback: &refund/1)
      |> Pipeline.run_with_rollback()

    #{subsection("Parallel Steps")}

      Pipeline.parallel(pipeline, [
        {:fetch_profile, &fetch_profile/1},
        {:fetch_settings, &fetch_settings/1}
      ])

    #{subsection("Common Functions")}

      Pipeline.new(context)     # Create new pipeline
      Pipeline.step(p, name, fn) # Add step
      Pipeline.step_if(p, name, cond, fn) # Conditional step
      Pipeline.parallel(p, steps) # Parallel execution
      Pipeline.run(p)           # Execute pipeline
      Pipeline.run_with_rollback(p) # Execute with saga pattern

    For more: functional_help(:async)
    """)
  end

  def functional_help(:async) do
    IO.puts("""
    #{header("AsyncResult")}

    #{subsection("Parallel Execution")}

      alias FnTypes.AsyncResult

      AsyncResult.parallel([
        fn -> fetch_user(id) end,
        fn -> fetch_orders(id) end
      ])
      # {:ok, [user, orders]} or {:error, first_error}

    #{subsection("Parallel Map")}

      AsyncResult.parallel_map(user_ids, &fetch_user/1,
        max_concurrency: 10
      )

    #{subsection("Race - First Wins")}

      AsyncResult.race([
        fn -> fetch_from_cache() end,
        fn -> fetch_from_db() end
      ])

    #{subsection("Retry with Backoff")}

      AsyncResult.retry(fn -> api_call() end,
        max_attempts: 3,
        initial_delay: 100,
        max_delay: 5000
      )

    #{subsection("Common Functions")}

      AsyncResult.parallel(tasks)     # Run all, fail-fast
      AsyncResult.parallel_settle(tasks) # Collect all results
      AsyncResult.parallel_map(enum, fn) # Map with concurrency
      AsyncResult.race(tasks)         # First to complete wins
      AsyncResult.retry(fn, opts)     # Retry with backoff
      AsyncResult.async(fn)           # Create task handle
      AsyncResult.await(handle)       # Wait for result

    For more: examples(:async)
    """)
  end

  def functional_help(:guards) do
    IO.puts("""
    #{header("Guards and Pattern Matching")}

    #{subsection("Import Guards")}

      import FnTypes.Guards

    #{subsection("Guard Macros")}

      def handle(result) when is_ok(result), do: :success
      def handle(result) when is_error(result), do: :failure

      def process(maybe) when is_some(maybe), do: :present
      def process(maybe) when is_none(maybe), do: :absent

      def validate(s) when is_non_empty_string(s), do: :valid
      def check(list) when is_non_empty_list(list), do: :has_items

    #{subsection("Pattern Matching Macros")}

      case fetch_user(id) do
        ok(user) -> process(user)
        error(reason) -> handle_error(reason)
      end

      case get_optional_value() do
        some(value) -> use(value)
        none() -> use_default()
      end

    #{subsection("Available Guards")}

      is_ok(term)           # {:ok, _}
      is_error(term)        # {:error, _}
      is_result(term)       # {:ok, _} | {:error, _}
      is_some(term)         # {:some, _}
      is_none(term)         # :none
      is_maybe(term)        # {:some, _} | :none
      is_non_empty_string(s)
      is_non_empty_list(list)
      is_positive_integer(n)

    For more: examples(:result)
    """)
  end

  def functional_help(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :result, :maybe, :pipeline, :async, :guards
    """)
  end

  # ============================================
  # CRUD System Documentation Helpers
  # ============================================

  @doc """
  Display CRUD system help.

  ## Topics
  - `:basic` - Basic CRUD operations
  - `:multi` - Multi (transactions)
  - `:merge` - Merge (upserts)
  - `:options` - Common options
  - `:examples` - Real-world examples
  """
  def crud_help(topic \\ :general)

  def crud_help(:general) do
    IO.puts("""
    #{header("CRUD System")}

    #{subsection("Core Modules")}

      alias OmCrud
      alias OmCrud.{Multi, Merge}

    #{subsection("Basic Operations")}

      OmCrud.create(User, %{email: "test@example.com"})
      OmCrud.fetch(User, id)
      OmCrud.update(user, %{name: "Updated"})
      OmCrud.delete(user)

    #{subsection("Transactions (Multi)")}

      Multi.new()
      |> Multi.create(:user, User, user_attrs)
      |> Multi.create(:account, Account, account_attrs)
      |> OmOmCrud.run()

    #{subsection("Upserts (Merge)")}

      User
      |> Merge.new(users_data)
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update)
      |> Merge.when_not_matched(:insert)
      |> OmOmCrud.run()

    #{subsection("Available Topics")}

    crud_help(:basic)    - Basic CRUD operations
    crud_help(:multi)    - Multi (transactions)
    crud_help(:merge)    - Merge (upserts)
    crud_help(:options)  - Common options
    crud_help(:examples) - Real-world examples
    """)
  end

  def crud_help(:basic) do
    IO.puts("""
    #{header("Basic CRUD Operations")}

    #{subsection("Create")}

      {:ok, user} = OmCrud.create(User, %{email: "test@example.com"})
      {:ok, user} = OmCrud.create(User, attrs, changeset: :admin_changeset)

    #{subsection("Read")}

      {:ok, user} = OmCrud.fetch(User, id)
      {:ok, user} = OmCrud.fetch(User, id, preload: [:account])
      user = Crud.get(User, id)  # Returns nil if not found
      true = Crud.exists?(User, id)

    #{subsection("Update")}

      {:ok, user} = OmCrud.update(user, %{name: "Updated"})
      {:ok, user} = OmCrud.update(User, id, attrs)

    #{subsection("Delete")}

      {:ok, user} = OmCrud.delete(user)
      {:ok, user} = OmCrud.delete(User, id)

    #{subsection("Bulk Operations")}

      {:ok, users} = OmCrud.create_all(User, [
        %{email: "a@test.com"},
        %{email: "b@test.com"}
      ])

      {:ok, count} = User
      |> Query.new()
      |> Query.filter(:status, :eq, :inactive)
      |> OmCrud.delete_all()

    For more: crud_help(:multi)
    """)
  end

  def crud_help(:multi) do
    IO.puts("""
    #{header("Multi - Transactions")}

    #{subsection("Basic Transaction")}

      alias OmCrud.Multi

      Multi.new()
      |> Multi.create(:user, User, %{email: "test@example.com"})
      |> Multi.create(:account, Account, fn %{user: u} ->
        %{owner_id: u.id}
      end)
      |> OmCrud.run()
      # => {:ok, %{user: %User{}, account: %Account{}}}

    #{subsection("Dynamic Attributes")}

      Multi.new()
      |> Multi.create(:user, User, user_attrs)
      |> Multi.create(:membership, Membership, fn %{user: u} ->
        %{user_id: u.id, role: :owner}
      end)
      |> OmCrud.run()

    #{subsection("Custom Operations")}

      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Multi.run(:send_email, fn %{user: user} ->
        Mailer.send_welcome(user)
        {:ok, :sent}
      end)
      |> OmCrud.run()

    #{subsection("Conditional Operations")}

      Multi.new()
      |> Multi.create(:order, Order, order_attrs)
      |> Multi.when_ok(:premium, fn %{order: order} ->
        if order.total > 100 do
          Multi.new()
          |> Multi.create(:reward, Reward, %{order_id: order.id})
        else
          Multi.new()
        end
      end)
      |> OmCrud.run()

    For more: crud_help(:merge)
    """)
  end

  def crud_help(:merge) do
    IO.puts("""
    #{header("Merge - PostgreSQL MERGE")}

    #{subsection("Simple Upsert")}

      alias OmCrud.Merge

      User
      |> Merge.new(%{email: "test@example.com", name: "Test"})
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update, [:name, :updated_at])
      |> Merge.when_not_matched(:insert)
      |> OmCrud.run()

    #{subsection("Bulk Sync")}

      User
      |> Merge.new(external_users)
      |> Merge.match_on(:external_id)
      |> Merge.when_matched(:update, [:name, :email])
      |> Merge.when_not_matched(:insert, %{status: :pending})
      |> Merge.returning(true)
      |> OmCrud.run()

    #{subsection("Composite Keys")}

      User
      |> Merge.new(users_data)
      |> Merge.match_on([:org_id, :email])
      |> Merge.when_matched(:update)
      |> Merge.when_not_matched(:insert)
      |> OmCrud.run()

    #{subsection("Common Options")}

      when_matched(:update)        # Update all fields
      when_matched(:update, [:name]) # Update specific fields
      when_matched(:delete)        # Delete matched rows
      when_matched(:nothing)       # Do nothing on match
      when_not_matched(:insert)    # Insert new rows
      when_not_matched(:nothing)   # Ignore new rows

    For more: crud_help(:examples)
    """)
  end

  def crud_help(:options) do
    IO.puts("""
    #{header("CRUD Options")}

    #{subsection("Common Options (All Operations)")}

      repo: MyApp.ReadOnlyRepo    # Custom repo
      prefix: "tenant_123"        # Multi-tenant schema
      timeout: 30_000             # Timeout in ms
      log: :debug                 # Logging level or false

    #{subsection("Read Options")}

      preload: [:account, :memberships]  # Preload associations

    #{subsection("Write Options")}

      changeset: :admin_changeset  # Custom changeset function
      returning: true              # Return all fields
      returning: [:id, :email]     # Return specific fields

    #{subsection("Bulk Insert Options")}

      placeholders: %{now: DateTime.utc_now(), org_id: org_id}

    #{subsection("Usage Examples")}

      # Custom repo
      OmCrud.fetch(User, id, repo: MyApp.ReadOnlyRepo)

      # Custom timeout for large operation
      OmCrud.create_all(User, data, timeout: 120_000)

      # Placeholders for bulk insert
      placeholders = %{now: DateTime.utc_now()}
      entries = Enum.map(data, &Map.put(&1, :inserted_at, {:placeholder, :now}))
      OmCrud.create_all(User, entries, placeholders: placeholders)

    For more: crud_help(:examples)
    """)
  end

  def crud_help(:examples) do
    IO.puts("""
    #{header("CRUD Examples")}

    #{subsection("User Registration with Account")}

      Multi.new()
      |> Multi.create(:user, User, user_attrs)
      |> Multi.create(:account, Account, account_attrs)
      |> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
        %{user_id: u.id, account_id: a.id, type: :owner}
      end)
      |> Multi.run(:welcome, fn %{user: u} ->
        Mailer.send_welcome(u)
        {:ok, :sent}
      end)
      |> OmCrud.run()

    #{subsection("Bulk User Import")}

      User
      |> Merge.new(csv_users)
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update, [:name, :phone])
      |> Merge.when_not_matched(:insert, %{status: :pending})
      |> Merge.returning([:id, :email])
      |> OmCrud.run(timeout: 120_000)

    #{subsection("Soft Delete with Cascade")}

      now = DateTime.utc_now()

      Multi.new()
      |> Multi.update(:account, account, %{deleted_at: now})
      |> Multi.update_all(:memberships,
        from(m in Membership, where: m.account_id == ^account.id),
        set: [deleted_at: now]
      )
      |> OmCrud.run()

    For more: examples(:crud)
    """)
  end

  def crud_help(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :basic, :multi, :merge, :options, :examples
    """)
  end

  # ============================================
  # Workflow System Documentation Helpers
  # ============================================

  @doc """
  Display workflow system help.

  ## Topics
  - `:quickstart` - Quick start guide
  - `:steps` - Step configuration
  - `:decorator` - Decorator API
  - `:rollback` - Saga pattern rollbacks
  """
  def workflow_help(topic \\ :general)

  def workflow_help(:general) do
    IO.puts("""
    #{header("Workflow System")}

    DAG-based workflow orchestration with dependencies, rollbacks, and scheduling.

    #{subsection("Quick Example")}

      defmodule MyApp.UserOnboarding do
        use OmScheduler.Workflow, name: :user_onboarding

        @decorate step()
        def create_account(ctx) do
          user = Users.create!(ctx.email)
          {:ok, %{user_id: user.id}}
        end

        @decorate step(after: :create_account)
        def send_welcome(ctx) do
          Mailer.send_welcome(ctx.user_id)
          :ok
        end
      end

      # Start workflow
      {:ok, execution_id} = OmScheduler.Workflow.start(:user_onboarding, %{
        email: "alice@example.com"
      })

    #{subsection("Available Topics")}

    workflow_help(:quickstart) - Quick start guide
    workflow_help(:steps)      - Step configuration
    workflow_help(:decorator)  - Decorator API
    workflow_help(:rollback)   - Saga pattern rollbacks
    """)
  end

  def workflow_help(:quickstart) do
    IO.puts("""
    #{header("Workflow Quick Start")}

    #{subsection("1. Define Workflow Module")}

      defmodule MyApp.OrderProcessing do
        use OmScheduler.Workflow,
          name: :order_processing,
          timeout: {30, :minutes}

        @decorate step()
        def validate_order(ctx) do
          order = Orders.get!(ctx.order_id)
          {:ok, %{order: order}}
        end

        @decorate step(after: :validate_order, rollback: :release_inventory)
        def reserve_inventory(ctx) do
          reservation = Inventory.reserve(ctx.order.items)
          {:ok, %{reservation_id: reservation.id}}
        end

        @decorate step(after: :reserve_inventory, rollback: :refund)
        def charge_payment(ctx) do
          payment = Payments.charge(ctx.order)
          {:ok, %{payment_id: payment.id}}
        end

        @decorate step(after: :charge_payment)
        def ship_order(ctx) do
          Shipping.create(ctx.order)
          :ok
        end

        def release_inventory(ctx), do: Inventory.release(ctx.reservation_id)
        def refund(ctx), do: Payments.refund(ctx.payment_id)
      end

    #{subsection("2. Start Workflow")}

      {:ok, execution_id} = OmScheduler.Workflow.start(:order_processing, %{
        order_id: 123
      })

    #{subsection("3. Monitor Execution")}

      {:ok, state} = OmScheduler.Workflow.get_state(execution_id)

    For more: workflow_help(:steps)
    """)
  end

  def workflow_help(:steps) do
    IO.puts("""
    #{header("Step Configuration")}

    #{subsection("Basic Step")}

      @decorate step()
      def my_step(ctx) do
        {:ok, %{result: "value"}}
      end

    #{subsection("With Dependencies")}

      @decorate step(after: :previous_step)
      def my_step(ctx), do: ...

      @decorate step(after: [:step_a, :step_b])  # Wait for both
      def my_step(ctx), do: ...

      @decorate step(after_any: [:step_a, :step_b])  # Wait for first
      def my_step(ctx), do: ...

    #{subsection("Parallel Groups")}

      # All steps in same group run in parallel
      @decorate step(after: :prepare, group: :uploads)
      def upload_s3(ctx), do: ...

      @decorate step(after: :prepare, group: :uploads)
      def upload_gcs(ctx), do: ...

      # Wait for entire group
      @decorate step(after_group: :uploads)
      def notify_complete(ctx), do: ...

    #{subsection("With Timeout & Retries")}

      @decorate step(
        timeout: {5, :minutes},
        max_retries: 3,
        retry_delay: {1, :second},
        retry_backoff: :exponential
      )
      def my_step(ctx), do: ...

    #{subsection("Conditional Execution")}

      @decorate step(
        after: :check,
        when: &(&1.should_run)
      )
      def conditional_step(ctx), do: ...

    #{subsection("Step Return Values")}

      {:ok, map}        # Success, merge map into context
      :ok               # Success, no context changes
      {:error, reason}  # Failure
      {:skip, reason}   # Skip step
      {:await, opts}    # Pause for approval

    For more: workflow_help(:rollback)
    """)
  end

  def workflow_help(:decorator) do
    IO.puts("""
    #{header("Decorator API")}

    #{subsection("Available Decorators")}

      @decorate step(opts)       # Regular step
      @decorate graft(opts)      # Dynamic expansion
      @decorate workflow(name)   # Nested workflow

    #{subsection("Step Options")}

      after: :step_name          # Single dependency
      after: [:a, :b]            # Multiple dependencies
      after_any: [:a, :b]        # First to complete
      after_group: :group_name   # Wait for parallel group
      after_graft: :graft_name   # Wait for dynamic steps

      group: :parallel_group     # Add to parallel group

      when: &(&1.condition)      # Conditional execution

      timeout: {5, :minutes}
      max_retries: 3
      retry_delay: {1, :second}
      retry_backoff: :exponential  # :fixed | :linear | :exponential

      on_error: :fail            # :fail | :skip | :continue
      rollback: :rollback_fn     # Compensation function

      await_approval: true       # Human-in-the-loop

    For more: workflow_help(:rollback)
    """)
  end

  def workflow_help(:rollback) do
    IO.puts("""
    #{header("Saga Pattern Rollbacks")}

    #{subsection("With Rollback Functions")}

      @decorate step(rollback: :release_inventory)
      def reserve_inventory(ctx) do
        reservation = Inventory.reserve(ctx.items)
        {:ok, %{reservation_id: reservation.id}}
      end

      @decorate step(after: :reserve_inventory, rollback: :refund)
      def charge_payment(ctx) do
        payment = Payments.charge(ctx.amount)
        {:ok, %{payment_id: payment.id}}
      end

      @decorate step(after: :charge_payment)
      def ship_order(ctx) do
        Shipping.create(ctx.order)
        :ok
      end

      # Rollback functions (called in reverse order)
      def refund(ctx), do: Payments.refund(ctx.payment_id)
      def release_inventory(ctx), do: Inventory.release(ctx.reservation_id)

    #{subsection("Rollback Execution")}

      If ship_order fails:
      1. refund is called
      2. release_inventory is called
      3. on_failure handler is called

    #{subsection("Cancel with Rollback")}

      OmScheduler.Workflow.cancel(execution_id, rollback: true)

    For more: examples(:workflow)
    """)
  end

  def workflow_help(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :quickstart, :steps, :decorator, :rollback
    """)
  end

  # ============================================
  # Decorator System Documentation Helpers
  # ============================================

  @doc """
  Display decorator system help.

  ## Topics
  - `:cache` - Cache decorators
  - `:telemetry` - Telemetry decorators
  - `:types` - Type decorators
  """
  def decorator_help(topic \\ :general)

  def decorator_help(:general) do
    IO.puts("""
    #{header("Decorator System")}

    #{subsection("Enable in Module")}

      use FnDecorator

    #{subsection("Common Decorators")}

      @decorate returns_result(ok: User.t(), error: :atom)
      @decorate cacheable(key: "user:\#{id}", ttl: {5, :minutes})
      @decorate telemetry_span([:app, :users, :get])
      @decorate log_call()

    #{subsection("Available Topics")}

    decorator_help(:cache)     - Cache decorators
    decorator_help(:telemetry) - Telemetry decorators
    decorator_help(:types)     - Type decorators
    """)
  end

  def decorator_help(:cache) do
    IO.puts("""
    #{header("Cache Decorators")}

    #{subsection("Cacheable")}

      @decorate cacheable(key: "user:\#{id}", ttl: {5, :minutes})
      def get_user(id) do
        Repo.get(User, id)
      end

    #{subsection("Cache Put")}

      @decorate cache_put(key: "user:\#{user.id}")
      def update_user(user, attrs) do
        Repo.update(user, attrs)
      end

    #{subsection("Cache Evict")}

      @decorate cache_evict(key: "user:\#{id}")
      def delete_user(id) do
        Repo.delete(User, id)
      end

    For more: decorator_help(:telemetry)
    """)
  end

  def decorator_help(:telemetry) do
    IO.puts("""
    #{header("Telemetry Decorators")}

    #{subsection("Telemetry Span")}

      @decorate telemetry_span([:app, :users, :create])
      def create_user(attrs) do
        Repo.insert(User, attrs)
      end

    #{subsection("Log Call")}

      @decorate log_call()
      def expensive_operation(data) do
        process(data)
      end

    #{subsection("Log if Slow")}

      @decorate log_if_slow(threshold: 1000)
      def might_be_slow(data) do
        process(data)
      end

    For more: decorator_help(:types)
    """)
  end

  def decorator_help(:types) do
    IO.puts("""
    #{header("Type Decorators")}

    #{subsection("Returns Result")}

      @decorate returns_result(ok: User.t(), error: :atom)
      def get_user(id) do
        case Repo.get(User, id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end
      end

    #{subsection("Returns Maybe")}

      @decorate returns_maybe(some: User.t())
      def find_user(email) do
        case Repo.get_by(User, email: email) do
          nil -> :none
          user -> {:some, user}
        end
      end

    #{subsection("Normalize Result")}

      @decorate normalize_result()
      def risky_operation() do
        # Catches exceptions and returns {:error, reason}
        do_risky_thing()
      end

    For more: examples(:decorators)
    """)
  end

  def decorator_help(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :cache, :telemetry, :types
    """)
  end

  # ============================================
  # Practical IEx Examples
  # ============================================

  @doc """
  Show practical IEx examples.

  ## Topics
  - `:result` - Result examples
  - `:crud` - CRUD examples
  - `:workflow` - Workflow examples
  """
  def examples(topic \\ :general)

  def examples(:general) do
    IO.puts("""
    #{header("Practical IEx Examples")}

    #{subsection("Available Examples")}

    examples(:result)   - Result type examples
    examples(:crud)     - CRUD operation examples
    examples(:workflow) - Workflow examples

    Try them in IEx to see how they work!
    """)
  end

  def examples(:result) do
    IO.puts("""
    #{header("Result Examples")}

    #{subsection("Basic Error Handling")}

      # Chain operations
      {:ok, 5}
      |> Result.map(&(&1 * 2))
      |> Result.and_then(fn x -> {:ok, x + 3} end)
      # => {:ok, 13}

      # Handle errors
      {:error, :not_found}
      |> Result.or_else(fn _ -> {:ok, "default"} end)
      # => {:ok, "default"}

      # Unwrap with default
      {:error, :oops} |> Result.unwrap_or("fallback")
      # => "fallback"

    #{subsection("Collect Multiple Results")}

      Result.collect([
        {:ok, 1},
        {:ok, 2},
        {:ok, 3}
      ])
      # => {:ok, [1, 2, 3]}

      Result.collect([
        {:ok, 1},
        {:error, :bad},
        {:ok, 3}
      ])
      # => {:error, :bad}

    #{subsection("Safe Exception Handling")}

      Result.try_with(fn -> 1 / 0 end)
      # => {:error, %ArithmeticError{}}

      Result.try_with(fn -> 10 / 2 end)
      # => {:ok, 5.0}

    Try: examples(:crud)
    """)
  end

  def examples(:crud) do
    IO.puts("""
    #{header("CRUD Examples")}

    #{subsection("Warning")}

    These examples use your actual database!
    Modify schema names as needed.

    #{subsection("Basic Operations (Try in IEx)")}

      # Fetch a record (returns {:ok, record} or {:error, :not_found})
      # OmCrud.fetch(YourSchema, id)

      # Get a record (returns record or nil)
      # Crud.get(YourSchema, id)

      # Check existence
      # Crud.exists?(YourSchema, id)

    #{subsection("Transaction Example")}

      # Multi.new()
      # |> Multi.run(:validate, fn _ -> {:ok, :valid} end)
      # |> Multi.run(:log, fn _ ->
      #   IO.puts("Transaction running!")
      #   {:ok, :logged}
      # end)
      # |> OmCrud.run()
      # => {:ok, %{validate: :valid, log: :logged}}

    #{subsection("Dry Run (Safe to Try)")}

      # Build a Multi without executing
      multi = Multi.new()
      |> Multi.run(:step1, fn _ -> {:ok, "first"} end)
      |> Multi.run(:step2, fn %{step1: val} -> {:ok, val <> " second"} end)

      # Check the operations
      Multi.names(multi)
      # => [:step1, :step2]

      # Execute it
      OmCrud.run(multi)
      # => {:ok, %{step1: "first", step2: "first second"}}

    Try: examples(:workflow)
    """)
  end

  def examples(:workflow) do
    IO.puts("""
    #{header("Workflow Examples")}

    #{subsection("Simple Workflow (Safe to Try)")}

      # This is a complete workflow definition you can paste in IEx:

      defmodule IExExample do
        use OmScheduler.Workflow, name: :iex_example

        @decorate step()
        def step_one(ctx) do
          IO.puts("Step 1: \#{inspect(ctx)}")
          {:ok, %{step1_result: "done"}}
        end

        @decorate step(after: :step_one)
        def step_two(ctx) do
          IO.puts("Step 2: \#{inspect(ctx)}")
          {:ok, %{step2_result: "also done"}}
        end

        @decorate step(after: :step_two)
        def step_three(ctx) do
          IO.puts("Step 3: \#{inspect(ctx)}")
          :ok
        end
      end

      # Start the workflow
      {:ok, execution_id} = OmScheduler.Workflow.start(:iex_example, %{input: "test"})

      # Check the state
      OmScheduler.Workflow.get_state(execution_id)

    #{subsection("Workflow Introspection")}

      # List all registered workflows
      OmScheduler.Workflow.list_all()

      # Get workflow summary
      OmScheduler.Workflow.summary(:iex_example)

      # Generate Mermaid diagram
      OmScheduler.Workflow.to_mermaid(:iex_example)

    Try these examples in your IEx session!
    """)
  end

  def examples(unknown) do
    IO.puts("""
    #{IO.ANSI.red()}Unknown topic: #{inspect(unknown)}#{IO.ANSI.reset()}

    Available topics:
    - :result, :crud, :workflow
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
