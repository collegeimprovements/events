defmodule MyApp.Context.SchemaName do
  @moduledoc """
  Schema for [describe what this schema represents].

  ## Fields
  - `field_name` - Description of what this field stores
  - ...

  ## Validations
  - Describe key validation rules
  - ...

  ## Business Rules
  - Any important business logic
  - ...
  """

  # IMPORTANT: Always use OmSchema, never Ecto.Schema
  use OmSchema

  # Import presets for common field validations
  import OmSchema.Presets

  @doc """
  Schema definition with inline validations.

  All field validations are defined directly in the schema for clarity and maintainability.
  """
  schema "table_name" do
    # ========================================
    # Primary Keys and References
    # ========================================
    # Primary key is auto-generated as binary_id (UUIDv7)

    # belongs_to :user, MyApp.Accounts.User
    # belongs_to :organization, MyApp.Organizations.Organization

    # ========================================
    # Required Fields (Core Business Data)
    # ========================================

    # Example: Required string with validation
    field :name, :string,
      required: true,
      min_length: 2,
      max_length: 100,
      normalize: :titlecase

    # Example: Required email (using preset)
    field :email, :string, email()

    # Example: Required enum field
    field :status, :string,
      required: true,
      in: ["draft", "pending", "active", "archived"],
      default: "draft"

    # ========================================
    # Optional Fields (Extended Data)
    # ========================================

    # Example: Optional string with format
    field :phone, :string, phone(required: false)

    # Example: Optional URL
    field :website, :string, url(required: false)

    # Example: Optional text with length limit
    field :description, :string,
      max_length: 1000,
      normalize: [:trim, :squish]

    # ========================================
    # Numeric Fields
    # ========================================

    # Example: Positive integer
    field :quantity, :integer, positive_integer()

    # Example: Money field
    field :price, :decimal, money()

    # Example: Percentage
    field :discount, :integer, percentage()

    # Example: Rating
    field :rating, :integer, rating()

    # ========================================
    # Date and Time Fields
    # ========================================

    # Example: Date in the past
    field :birth_date, :date,
      past: true,
      after: ~D[1900-01-01]

    # Example: Future datetime
    field :scheduled_at, :utc_datetime,
      future: true,
      after: {:now, hours: 1}

    # Example: Date range
    field :start_date, :date, required: true
    field :end_date, :date,
      required: true,
      after: {:field, :start_date}

    # ========================================
    # Boolean Flags
    # ========================================

    field :active, :boolean, default: true
    field :featured, :boolean, default: false
    field :verified, :boolean, default: false
    field :terms_accepted, :boolean, acceptance: true

    # ========================================
    # Arrays and Collections
    # ========================================

    # Example: Tags array
    field :tags, {:array, :string}, tags(max_length: 10)

    # Example: Array with custom validation
    field :categories, {:array, :string},
      min_length: 1,
      max_length: 5,
      unique_items: true,
      in: ["tech", "business", "lifestyle", "health", "education"]

    # ========================================
    # JSON/Map Fields
    # ========================================

    # Example: Metadata with constraints
    field :metadata, :map, metadata(max_keys: 50)

    # Example: Settings with required keys
    field :settings, :map,
      default: %{},
      required_keys: ["theme", "language"],
      max_keys: 20

    # ========================================
    # Virtual Fields (not persisted)
    # ========================================

    field :password_confirmation, :string, virtual: true
    field :current_password, :string, virtual: true

    # ========================================
    # Computed/Derived Fields
    # ========================================

    field :slug, :string, slug()
    field :search_vector, :string
    field :full_text, :string

    # ========================================
    # Audit Fields
    # ========================================

    field :created_by_id, :binary_id
    field :updated_by_id, :binary_id
    field :deleted_at, :utc_datetime
    field :locked_at, :utc_datetime
    field :archived_at, :utc_datetime

    # Automatic timestamps (created_at, updated_at)
    timestamps()
  end

  @doc """
  Builds a changeset for creating a new record.
  """
  def create_changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, __cast_fields__())
    |> validate_required(required_fields())
    |> __apply_field_validations__()
    |> apply_business_rules()
    |> prepare_changes(&before_insert/1)
  end

  @doc """
  Builds a changeset for updating an existing record.
  """
  def update_changeset(schema, attrs) do
    schema
    |> cast(attrs, __cast_fields__() -- [:email])  # Example: email cannot be changed
    |> __apply_field_validations__()
    |> apply_business_rules()
    |> prepare_changes(&before_update/1)
  end

  @doc """
  Returns list of required fields for this schema.
  """
  defp required_fields do
    [:name, :email, :status]  # Adjust based on your requirements
  end

  @doc """
  Apply custom business rules and cross-field validations.
  """
  defp apply_business_rules(changeset) do
    changeset
    |> validate_date_range()
    |> validate_price_logic()
    |> maybe_generate_slug()
    |> ensure_defaults()
  end

  # Example: Validate date range
  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(start_date, end_date) == :gt do
      add_error(changeset, :end_date, "must be after or equal to start date")
    else
      changeset
    end
  end

  # Example: Price validation logic
  defp validate_price_logic(changeset) do
    price = get_field(changeset, :price)
    discount = get_field(changeset, :discount)

    if price && discount && discount > 100 do
      add_error(changeset, :discount, "cannot exceed 100%")
    else
      changeset
    end
  end

  # Example: Generate slug if not provided
  defp maybe_generate_slug(changeset) do
    if get_field(changeset, :slug) do
      changeset
    else
      case get_change(changeset, :name) do
        nil -> changeset
        name -> put_change(changeset, :slug, OmSchema.Slugify.slugify(name))
      end
    end
  end

  # Example: Ensure defaults
  defp ensure_defaults(changeset) do
    changeset
    |> put_new_change(:status, "draft")
    |> put_new_change(:active, true)
  end

  # Hooks
  defp before_insert(changeset) do
    changeset
    |> put_change(:search_vector, build_search_vector(changeset))
  end

  defp before_update(changeset) do
    changeset
    |> put_change(:search_vector, build_search_vector(changeset))
  end

  defp build_search_vector(changeset) do
    # Example: Combine fields for full-text search
    [
      get_field(changeset, :name),
      get_field(changeset, :description),
      get_field(changeset, :tags) |> List.to_string()
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  # Helper to put change only if not already set
  defp put_new_change(changeset, key, value) do
    if get_field(changeset, key) do
      changeset
    else
      put_change(changeset, key, value)
    end
  end
end

# ============================================
# MIGRATION TEMPLATE
# ============================================
#
# defmodule MyApp.Repo.Migrations.CreateSchemaName do
#   use Ecto.Migration
#
#   def change do
#     create table(:table_name) do
#       # Foreign keys
#       add :user_id, references(:users, type: :binary_id, on_delete: :cascade)
#
#       # Required fields
#       add :name, :string, null: false
#       add :email, :string, null: false
#       add :status, :string, null: false, default: "draft"
#
#       # Optional fields
#       add :phone, :string
#       add :website, :string
#       add :description, :text
#
#       # Numeric fields
#       add :quantity, :integer, default: 0
#       add :price, :decimal, precision: 10, scale: 2
#
#       # Boolean fields
#       add :active, :boolean, default: true, null: false
#       add :verified, :boolean, default: false, null: false
#
#       # JSON fields
#       add :metadata, :jsonb, default: "{}"
#       add :settings, :jsonb, default: "{}"
#
#       # Array fields
#       add :tags, {:array, :string}, default: []
#
#       # Audit fields
#       add :deleted_at, :utc_datetime
#
#       timestamps()
#     end
#
#     # Indexes for performance
#     create index(:table_name, [:status])
#     create index(:table_name, [:active])
#     create index(:table_name, [:created_at])
#
#     # Unique constraints
#     create unique_index(:table_name, [:email])
#     create unique_index(:table_name, [:slug])
#
#     # Check constraints (matching validations)
#     create constraint(:table_name, :price_must_be_positive, check: "price >= 0")
#     create constraint(:table_name, :discount_must_be_valid, check: "discount >= 0 AND discount <= 100")
#   end
# end