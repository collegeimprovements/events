defmodule Events.Schema.Help do
  @moduledoc """
  Interactive help system for schemas with live documentation.

  Provides comprehensive help, examples, and patterns for using
  the schema validation system effectively.
  """

  @topics %{
    general: :general_help,
    validators: :validators_help,
    pipelines: :pipelines_help,
    patterns: :patterns_help,
    examples: :examples_help
  }

  @doc """
  Shows help for the specified topic.

  ## Available Topics
  - `:general` - Overview and philosophy
  - `:validators` - Available validators
  - `:pipelines` - Pipeline patterns
  - `:patterns` - Common patterns
  - `:examples` - Complete examples
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

    Events.Schema.help(:general)    - Overview and philosophy
    Events.Schema.help(:validators) - Available validators
    Events.Schema.help(:pipelines)  - Pipeline patterns
    Events.Schema.help(:patterns)   - Common patterns
    Events.Schema.help(:examples)   - Complete examples
    """)
  end

  # ============================================
  # Help Content
  # ============================================

  def general_help do
    IO.puts("""

    Events Schema System
    ====================

    A clean, composable validation system using pipelines and pattern matching.

    ## Philosophy

    Validations flow through pipelines, with each validator transforming
    or validating the changeset. This creates a composable, testable system.

    ## Basic Usage

        defmodule MyApp.User do
          use Events.Schema

          schema "users" do
            field :email, :string
            field :age, :integer
            field :status, :string
          end

          def changeset(user, attrs) do
            user
            |> cast(attrs)
            |> validate(:email, :required, :email)
            |> validate(:age, :required, min: 18, max: 120)
            |> validate(:status, in: ["active", "pending"])
            |> apply()
          end
        end

    ## Key Concepts

    1. **Token Pattern**: Validations accumulate in a token
    2. **Pipeline Composition**: Chain validators elegantly
    3. **Pattern Matching**: Clean validation dispatch
    4. **Pure Functions**: All validators are pure functions

    ## Getting Started

    1. Add `use Events.Schema` to your schema module
    2. Define your schema fields
    3. Create a changeset function with validation pipeline
    4. Apply the validations with `apply()`

    For more help: Events.Schema.help(:examples)
    """)
  end

  def validators_help do
    IO.puts("""

    Available Validators
    ====================

    All validators can be used with the `validate/3` function.

    ## Basic Validators

        validate(:field, :required)           # Field must be present
        validate(:field, :unique)             # Database unique constraint

    ## String Validators

        validate(:email, :email)              # Valid email format
        validate(:url, :url)                  # Valid URL format
        validate(:uuid, :uuid)                # Valid UUID format
        validate(:slug, :slug)                # Valid slug format
        validate(:phone, :phone)              # Valid phone number

        # Length validators
        validate(:name, min_length: 2)
        validate(:name, max_length: 100)
        validate(:code, length: 6)

        # Format validators
        validate(:username, format: ~r/^[a-z0-9_]+$/)

        # Inclusion/Exclusion
        validate(:status, in: ["active", "pending"])
        validate(:username, not_in: ["admin", "root"])

    ## Number Validators

        validate(:age, min: 18)               # Minimum value
        validate(:age, max: 120)              # Maximum value
        validate(:quantity, positive: true)   # Must be > 0
        validate(:stock, non_negative: true)  # Must be >= 0

        # Comparisons
        validate(:price, greater_than: 0)
        validate(:score, less_than_or_equal_to: 100)

    ## Boolean Validators

        validate(:terms, acceptance: true)    # Must be true

    ## Date/Time Validators

        validate(:birth_date, past: true)     # Must be in past
        validate(:event_date, future: true)   # Must be in future

        # Range validators
        validate(:date, after: ~D[2020-01-01])
        validate(:date, before: ~D[2030-01-01])

    ## Array Validators

        validate(:tags, min_length: 1)        # Minimum items
        validate(:tags, max_length: 10)       # Maximum items
        validate(:tags, unique_items: true)   # No duplicates

    ## Map/JSON Validators

        validate(:metadata, required_keys: ["type", "version"])
        validate(:settings, forbidden_keys: ["password"])
        validate(:config, min_keys: 1)
        validate(:config, max_keys: 20)

    ## Cross-field Validators

        # Confirmation
        validate_confirmation(:password, :password_confirmation)

        # Comparison
        validate_comparison(:start_date, :<=, :end_date)
        validate_comparison(:min_price, :<, :max_price)

        # Exclusive fields
        validate_exclusive([:email, :phone], at_least_one: true)

    ## Conditional Validators

        # Apply only if condition is met
        validate_if(:promo_code, :required, fn attrs ->
          attrs["has_discount"] == true
        end)

        # Apply unless condition is met
        validate_unless(:email, :required, fn attrs ->
          attrs["login_type"] == "oauth"
        end)
    """)
  end

  def pipelines_help do
    IO.puts("""

    Pipeline Patterns
    =================

    Elegant patterns for composing validations.

    ## Basic Pipeline

        user
        |> cast(attrs)
        |> validate(:email, :required, :email)
        |> validate(:age, :required, min: 18)
        |> apply()

    ## Grouped Validations

        user
        |> cast(attrs)
        # Required fields
        |> validate(:email, :required)
        |> validate(:username, :required)
        # Format validations
        |> validate(:email, :email)
        |> validate(:username, format: ~r/^[a-z0-9_]+$/)
        # Business rules
        |> validate(:age, min: 18, max: 120)
        |> validate(:terms, acceptance: true)
        |> apply()

    ## Helper Functions

        # String validation
        |> validate_string(:username, :required, min: 3, max: 30)

        # Number validation
        |> validate_number(:age, :required, min: 18)

        # Email validation
        |> validate_email(:email)

        # URL validation
        |> validate_url(:website, required: false)

        # UUID validation
        |> validate_uuid(:user_id, :required)

        # Slug validation
        |> validate_slug(:slug, unique: true)

        # Money validation
        |> validate_money(:price, :required, min: 0)

        # Percentage validation
        |> validate_percentage(:discount, max: 100)

        # Phone validation
        |> validate_phone(:phone)

        # Boolean validation
        |> validate_boolean(:active, acceptance: true)

        # Enum validation
        |> validate_enum(:status, in: ["active", "pending"])

        # JSON validation
        |> validate_json(:metadata, required_keys: ["version"])

        # Array validation
        |> validate_array(:tags, min_length: 1, max_length: 10)

    ## Conditional Pipelines

        user
        |> cast(attrs)
        |> validate(:email, :required)
        |> validate_if(:phone, :required, fn attrs ->
          is_nil(attrs["email"])
        end)
        |> validate_unless(:password, :required, fn attrs ->
          attrs["login_type"] == "oauth"
        end)
        |> apply()

    ## Debugging Pipelines

        user
        |> cast(attrs)
        |> tap_inspect("After cast")
        |> validate(:email, :required, :email)
        |> tap_inspect("After email validation")
        |> apply()

    ## Composition with Functions

        def base_validations(token) do
          token
          |> validate(:email, :required, :email)
          |> validate(:username, :required)
        end

        def profile_validations(token) do
          token
          |> validate(:bio, max_length: 500)
          |> validate(:website, :url)
        end

        user
        |> cast(attrs)
        |> base_validations()
        |> profile_validations()
        |> apply()
    """)
  end

  def patterns_help do
    IO.puts("""

    Common Patterns
    ===============

    Best practices and patterns for schema validation.

    ## User Registration

        def registration_changeset(user, attrs) do
          user
          |> cast(attrs)
          # Identity
          |> validate(:email, :required, :email, unique: true)
          |> validate(:username, :required, min: 3, max: 30, unique: true)
          # Password
          |> validate(:password, :required, min: 8)
          |> validate_confirmation(:password, :password_confirmation)
          # Terms
          |> validate(:terms_accepted, acceptance: true)
          |> apply()
        end

    ## User Login

        def login_changeset(attrs) do
          %User{}
          |> cast(attrs)
          |> validate_if(:email, :required, :email, fn attrs ->
            attrs["login_type"] == "email"
          end)
          |> validate_if(:username, :required, fn attrs ->
            attrs["login_type"] == "username"
          end)
          |> validate(:password, :required)
          |> apply()
        end

    ## Product Creation

        def product_changeset(product, attrs) do
          product
          |> cast(attrs)
          # Identity
          |> validate(:sku, :required, unique: true)
          |> validate(:name, :required, min: 2, max: 200)
          |> validate_slug(:slug, unique: true)
          # Pricing
          |> validate_money(:price, :required, min: 0)
          |> validate_money(:cost, min: 0)
          |> validate_percentage(:discount, max: 100)
          # Inventory
          |> validate_number(:stock_quantity, non_negative: true)
          # Categorization
          |> validate(:category, :required)
          |> validate_array(:tags, max_length: 10)
          # Status
          |> validate_enum(:status, in: ["draft", "published", "archived"])
          |> apply()
        end

    ## Order Validation

        def order_changeset(order, attrs) do
          order
          |> cast(attrs)
          # Customer
          |> validate(:customer_id, :required, :uuid)
          # Items
          |> validate(:line_items, :required, min_length: 1)
          # Pricing
          |> validate_money(:subtotal, :required, min: 0)
          |> validate_money(:tax, min: 0)
          |> validate_money(:total, :required, min: 0)
          # Dates
          |> validate(:placed_at, :required)
          |> validate_comparison(:shipped_at, :>=, :placed_at)
          |> validate_comparison(:delivered_at, :>=, :shipped_at)
          # Status
          |> validate_enum(:status, in: [
              "pending", "confirmed", "processing",
              "shipped", "delivered", "cancelled"
            ])
          |> apply()
        end

    ## Multi-step Form

        def step_1_changeset(data, attrs) do
          data
          |> cast(attrs)
          |> validate(:email, :required, :email)
          |> validate(:name, :required)
          |> apply()
        end

        def step_2_changeset(data, attrs) do
          data
          |> cast(attrs)
          |> validate(:address, :required)
          |> validate(:city, :required)
          |> validate(:postal_code, :required)
          |> apply()
        end

        def step_3_changeset(data, attrs) do
          data
          |> cast(attrs)
          |> validate(:payment_method, :required)
          |> validate_if(:card_number, :required, fn attrs ->
            attrs["payment_method"] == "card"
          end)
          |> apply()
        end

    ## API Input Validation

        def api_changeset(attrs) do
          %Request{}
          |> cast(attrs)
          # Required fields
          |> validate(:api_key, :required, :uuid)
          |> validate(:endpoint, :required, :url)
          |> validate(:method, :required, in: ["GET", "POST", "PUT", "DELETE"])
          # Optional fields
          |> validate_json(:headers)
          |> validate_json(:body, max_keys: 100)
          # Rate limiting
          |> validate_number(:retry_count, max: 3)
          |> validate_number(:timeout, min: 1, max: 30)
          |> apply()
        end

    ## Settings Validation

        def settings_changeset(settings, attrs) do
          settings
          |> cast(attrs)
          # Theme settings
          |> validate_enum(:theme, in: ["light", "dark", "auto"])
          |> validate(:primary_color, :required, format: ~r/^#[0-9a-f]{6}$/i)
          # Notification settings
          |> validate_boolean(:email_notifications)
          |> validate_boolean(:push_notifications)
          # Privacy settings
          |> validate_enum(:profile_visibility, in: ["public", "friends", "private"])
          |> validate_boolean(:show_online_status)
          # Localization
          |> validate_enum(:language, in: ["en", "es", "fr", "de"])
          |> validate(:timezone, :required)
          |> apply()
        end
    """)
  end

  def examples_help do
    IO.puts("""

    Complete Examples
    =================

    Full schema examples with validation pipelines.

    ## User Schema

        defmodule MyApp.User do
          use Events.Schema

          schema "users" do
            field :email, :string
            field :username, :string
            field :password, :string, virtual: true
            field :password_hash, :string
            field :first_name, :string
            field :last_name, :string
            field :age, :integer
            field :bio, :string
            field :website, :string
            field :status, :string
            field :role, :string
            field :confirmed_at, :utc_datetime
            field :locked_at, :utc_datetime
            field :deleted_at, :utc_datetime
            timestamps()
          end

          def changeset(user, attrs) do
            user
            |> cast(attrs)
            # Identity
            |> validate(:email, :required, :email, unique: true)
            |> validate(:username, :required, min: 3, max: 30, unique: true)
            # Name
            |> validate_string(:first_name, min: 2, max: 50)
            |> validate_string(:last_name, min: 2, max: 50)
            # Profile
            |> validate_number(:age, min: 13, max: 120)
            |> validate_string(:bio, max: 500)
            |> validate_url(:website)
            # Status
            |> validate_enum(:status, in: ["active", "pending", "suspended"])
            |> validate_enum(:role, in: ["admin", "moderator", "user"])
            |> apply()
          end

          def registration_changeset(user, attrs) do
            user
            |> changeset(attrs)
            |> validate(:password, :required, min: 8)
            |> validate_confirmation(:password, :password_confirmation)
            |> hash_password()
          end

          defp hash_password(changeset) do
            if password = get_change(changeset, :password) do
              put_change(changeset, :password_hash, hash(password))
            else
              changeset
            end
          end
        end

    ## Product Schema

        defmodule MyApp.Product do
          use Events.Schema

          schema "products" do
            field :sku, :string
            field :name, :string
            field :description, :string
            field :slug, :string
            field :category, :string
            field :tags, {:array, :string}
            field :price, :decimal
            field :cost, :decimal
            field :discount_percentage, :integer
            field :stock_quantity, :integer
            field :min_order_quantity, :integer
            field :max_order_quantity, :integer
            field :weight, :decimal
            field :dimensions, :map
            field :metadata, :map
            field :status, :string
            field :published_at, :utc_datetime
            field :discontinued_at, :utc_datetime
            timestamps()
          end

          def changeset(product, attrs) do
            product
            |> cast(attrs)
            # Identity
            |> validate(:sku, :required, unique: true)
            |> validate(:name, :required, min: 2, max: 200)
            |> validate_slug(:slug, unique: true)
            # Categorization
            |> validate(:category, :required)
            |> validate_array(:tags, max_length: 10, unique_items: true)
            # Pricing
            |> validate_money(:price, :required, min: 0)
            |> validate_money(:cost, min: 0)
            |> validate_percentage(:discount_percentage)
            |> validate_price_consistency()
            # Inventory
            |> validate_number(:stock_quantity, :required, non_negative: true)
            |> validate_number(:min_order_quantity, min: 1)
            |> validate_number(:max_order_quantity, min: 1)
            |> validate_order_quantity_consistency()
            # Physical attributes
            |> validate_number(:weight, positive: true)
            |> validate_json(:dimensions, required_keys: ["length", "width", "height"])
            # Metadata
            |> validate_json(:metadata, max_keys: 50)
            # Status
            |> validate_enum(:status, in: ["draft", "published", "archived"])
            |> apply()
          end

          defp validate_price_consistency(changeset) do
            price = get_field(changeset, :price)
            cost = get_field(changeset, :cost)

            if price && cost && Decimal.lt?(price, cost) do
              add_error(changeset, :price, "cannot be less than cost")
            else
              changeset
            end
          end

          defp validate_order_quantity_consistency(changeset) do
            min_qty = get_field(changeset, :min_order_quantity)
            max_qty = get_field(changeset, :max_order_quantity)

            if min_qty && max_qty && min_qty > max_qty do
              add_error(changeset, :max_order_quantity,
                "must be greater than or equal to minimum order quantity")
            else
              changeset
            end
          end
        end

    ## Event Schema

        defmodule MyApp.Event do
          use Events.Schema

          schema "events" do
            field :title, :string
            field :description, :string
            field :slug, :string
            field :start_time, :utc_datetime
            field :end_time, :utc_datetime
            field :timezone, :string
            field :location_type, :string
            field :venue_name, :string
            field :venue_address, :string
            field :online_url, :string
            field :max_attendees, :integer
            field :registration_required, :boolean
            field :registration_deadline, :utc_datetime
            field :price, :decimal
            field :currency, :string
            field :tags, {:array, :string}
            field :status, :string
            field :cancelled_at, :utc_datetime
            field :cancellation_reason, :string
            timestamps()
          end

          def changeset(event, attrs) do
            event
            |> cast(attrs)
            # Basic info
            |> validate(:title, :required, min: 5, max: 200)
            |> validate_string(:description, max: 2000)
            |> validate_slug(:slug, unique: true)
            # Schedule
            |> validate(:start_time, :required, future: true)
            |> validate(:end_time, :required)
            |> validate_comparison(:end_time, :>, :start_time)
            |> validate(:timezone, :required)
            # Location
            |> validate_enum(:location_type, in: ["online", "physical", "hybrid"])
            |> validate_location_fields()
            # Capacity
            |> validate_number(:max_attendees, positive: true)
            |> validate_boolean(:registration_required)
            |> validate_registration_deadline()
            # Pricing
            |> validate_money(:price, min: 0)
            |> validate_if(:currency, :required, fn attrs ->
              attrs["price"] && attrs["price"] > 0
            end)
            # Metadata
            |> validate_array(:tags, max_length: 10)
            # Status
            |> validate_enum(:status, in: [
                "draft", "published", "registration_open",
                "sold_out", "ongoing", "completed", "cancelled"
              ])
            |> apply()
          end

          defp validate_location_fields(changeset) do
            location_type = get_field(changeset, :location_type)

            case location_type do
              "online" ->
                validate(changeset, :online_url, :required, :url)

              "physical" ->
                changeset
                |> validate(:venue_name, :required)
                |> validate(:venue_address, :required)

              "hybrid" ->
                changeset
                |> validate(:venue_name, :required)
                |> validate(:venue_address, :required)
                |> validate(:online_url, :required, :url)

              _ ->
                changeset
            end
          end

          defp validate_registration_deadline(changeset) do
            if get_field(changeset, :registration_required) do
              changeset
              |> validate(:registration_deadline, :required)
              |> validate_comparison(:registration_deadline, :<, :start_time)
            else
              changeset
            end
          end
        end
    """)
  end
end
