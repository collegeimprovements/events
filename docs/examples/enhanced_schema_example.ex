defmodule Examples.EnhancedSchema do
  @moduledoc """
  Example showcasing all the Events.Core.Schema enhancements.
  """

  use Events.Core.Schema
  import Events.Core.Schema.Presets

  # Enable telemetry for this schema
  # Application.put_env(:events, :validation_telemetry, true)

  schema "users" do
    # Using presets for common field patterns
    field :email, :string, email()
    field :username, :string, username(min_length: 3)
    field :website, :string, url(required: false)
    field :phone, :string, phone()

    # Password with custom settings
    field :password, :string, password(min_length: 10)
    field :password_confirmation, :string, trim: false

    # Using standard validations
    field :age, :integer, positive_integer(max: 120)
    field :balance, :decimal, money()
    field :discount_percentage, :integer, percentage()

    # Enum field
    field :status, :string, enum(in: ["active", "inactive", "suspended"])

    # Array field with item validations
    field :tags, {:array, :string}, tags(max_length: 10)

    # Map field with key validations
    field :preferences, :map,
      required_keys: [:theme, :language],
      max_keys: 20,
      default: %{}

    # Date fields with relative validation
    field :birth_date, :date,
      past: true,
      required: true

    field :trial_ends_at, :utc_datetime,
      future: true,
      after: {:now, days: 7}

    # Slug field with uniqueness
    field :slug, :string, slug()

    # Conditional validation
    field :referral_code, :string,
      min_length: 6,
      validate_if: {__MODULE__, :is_referred_user?}

    field :is_referred, :boolean, default: false

    # Field with custom validation
    field :custom_field, :string,
      validate: {__MODULE__, :validate_custom}
  end

  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, __cast_fields__())
    |> Ecto.Changeset.validate_required(__required_fields__())
    |> __apply_field_validations__()
    |> apply_cross_validations()
  end

  # Cross-field validations
  defp apply_cross_validations(changeset) do
    Events.Core.Schema.Validators.CrossField.validate(changeset, [
      {:confirmation, :password, match: :password_confirmation},
      {:one_of, [:email, :phone]}
    ])
  end

  # Conditional validation callback
  def is_referred_user?(changeset) do
    Ecto.Changeset.get_field(changeset, :is_referred) == true
  end

  # Custom validation
  def validate_custom(value) do
    if String.length(value) > 5 do
      :ok
    else
      {:error, "must be longer than 5 characters"}
    end
  end
end

defmodule Examples.UsingEnhancedSchema do
  @moduledoc """
  Examples of using the enhanced schema features.
  """

  alias Examples.EnhancedSchema

  def demo do
    IO.puts("=== Events.Core.Schema Enhanced Features Demo ===\n")

    # 1. Introspection
    demo_introspection()

    # 2. Validation with errors
    demo_validation()

    # 3. Error prioritization
    demo_error_prioritization()

    # 4. Test helpers
    demo_test_helpers()

    # 5. Telemetry
    demo_telemetry()
  end

  defp demo_introspection do
    IO.puts("1. Schema Introspection")
    IO.puts("----------------------")

    # Get all field specs
    specs = Events.Core.Schema.Introspection.inspect_schema(EnhancedSchema)
    IO.puts("Total fields: #{length(specs)}")

    # Get required fields
    required = Events.Core.Schema.Introspection.required_fields(EnhancedSchema)
    IO.puts("Required fields: #{inspect(required)}")

    # Check specific field
    email_spec = Events.Core.Schema.Introspection.inspect_field(EnhancedSchema, :email)
    IO.puts("Email field spec: #{inspect(email_spec, pretty: true, limit: :infinity)}")

    # Generate JSON schema
    json_schema = Events.Core.Schema.Introspection.to_json_schema(EnhancedSchema)
    IO.puts("JSON Schema properties: #{map_size(json_schema.properties)}")

    IO.puts("")
  end

  defp demo_validation do
    IO.puts("2. Validation with Enhanced Errors")
    IO.puts("-----------------------------------")

    # Invalid data to trigger multiple errors
    invalid_attrs = %{
      email: "not-an-email",
      username: "ab",  # too short
      age: -5,  # not positive
      status: "invalid",  # not in enum
      preferences: %{theme: "dark"}  # missing required key
    }

    changeset = EnhancedSchema.changeset(%EnhancedSchema{}, invalid_attrs)

    # Get errors as simple map
    errors = Events.Core.Schema.Errors.to_simple_map(changeset)
    IO.puts("Validation errors: #{inspect(errors, pretty: true)}")

    # Get formatted message
    message = Events.Core.Schema.Errors.to_message(changeset)
    IO.puts("\nFormatted message:")
    IO.puts(message)

    IO.puts("")
  end

  defp demo_error_prioritization do
    IO.puts("3. Error Prioritization")
    IO.puts("-----------------------")

    # Create changeset with multiple errors
    changeset = EnhancedSchema.changeset(%EnhancedSchema{}, %{
      email: "x",  # too short AND invalid format
      age: -5,     # negative
      status: "x"  # not in enum
    })

    # Group by priority
    prioritized = Events.Core.Schema.Errors.group_by_priority(changeset)

    IO.puts("High priority errors: #{inspect(prioritized.high)}")
    IO.puts("Medium priority errors: #{inspect(prioritized.medium)}")
    IO.puts("Low priority errors: #{inspect(prioritized.low)}")

    # Get highest priority per field
    highest = Events.Core.Schema.Errors.highest_priority_per_field(changeset)
    IO.puts("\nHighest priority error per field: #{inspect(highest, pretty: true)}")

    IO.puts("")
  end

  defp demo_test_helpers do
    IO.puts("4. Test Helpers")
    IO.puts("---------------")

    import Events.Core.Schema.TestHelpers

    # Test string validation
    IO.puts("Testing email validation:")
    try do
      assert_valid("test@example.com", :string, format: :email)
      IO.puts("  ✓ Valid email accepted")
    rescue
      _ -> IO.puts("  ✗ Valid email rejected")
    end

    try do
      assert_invalid("not-an-email", :string, format: :email)
      IO.puts("  ✓ Invalid email rejected")
    rescue
      _ -> IO.puts("  ✗ Invalid email accepted")
    end

    # Test normalization
    normalized = test_normalization("  Hello World  ", normalize: [:trim, :downcase, :slugify])
    IO.puts("\nNormalization test:")
    IO.puts("  Input: '  Hello World  '")
    IO.puts("  Output: '#{normalized}'")

    # Test cross-field validation
    cross_changeset = test_cross_field(
      %{password: "secret", password_confirmation: "different"},
      [{:confirmation, :password, match: :password_confirmation}]
    )
    IO.puts("\nCross-field validation: #{if cross_changeset.valid?, do: "✓", else: "✗"}")

    IO.puts("")
  end

  defp demo_telemetry do
    IO.puts("5. Telemetry Integration")
    IO.puts("------------------------")

    # Enable telemetry
    Application.put_env(:events, :validation_telemetry, true)

    # Attach handlers
    Events.Core.Schema.Telemetry.attach_default_handlers()

    IO.puts("Telemetry enabled and handlers attached")
    IO.puts("Validation events will be logged during validation")

    # Clean up
    Application.put_env(:events, :validation_telemetry, false)
    :telemetry.detach("events-schema-validation")

    IO.puts("")
  end
end

# Run the demo
# Examples.UsingEnhancedSchema.demo()