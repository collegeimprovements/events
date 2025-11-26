defmodule Events.SchemaFieldOverrideTest do
  @moduledoc """
  Test to verify if overriding Ecto's field macro works correctly.
  """
  use ExUnit.Case

  # Define CustomField first before using it
  defmodule CustomField do
    @moduledoc """
    Custom field macro that shadows Ecto.Schema.field
    """
    defmacro field(name, type, opts \\ []) do
      # Split validation options from Ecto options
      {validation_opts, ecto_opts} =
        Keyword.split(opts, [:min, :max, :format, :required, :in, :cast])

      quote do
        # Store validation metadata in module attribute
        Module.put_attribute(
          __MODULE__,
          :field_validations,
          {unquote(name), unquote(validation_opts)}
        )

        # Call Ecto's original field macro via __field__
        Ecto.Schema.__field__(__MODULE__, unquote(name), unquote(type), unquote(ecto_opts))
      end
    end
  end

  # Test 1: Basic field override in schema context
  defmodule TestSchema1 do
    use Ecto.Schema

    schema "test_table" do
      # Import our custom field macro which shadows Ecto.Schema.field
      import Ecto.Schema, except: [field: 3]
      import Events.SchemaFieldOverrideTest.CustomField

      field(:name, :string, min: 2, max: 100)
      field(:age, :integer, min: 0, max: 150)
    end
  end

  # Test 2: Check if Ecto.Schema functions still work
  test "schema with overridden field macro creates proper struct" do
    schema = %TestSchema1{}
    assert Map.has_key?(schema, :name)
    assert Map.has_key?(schema, :age)
    assert Map.has_key?(schema, :id)
  end

  test "schema reflection functions work" do
    # Ecto's __schema__/1 should still work
    assert :name in TestSchema1.__schema__(:fields)
    assert :age in TestSchema1.__schema__(:fields)
    assert TestSchema1.__schema__(:type, :name) == :string
    assert TestSchema1.__schema__(:type, :age) == :integer
  end

  test "changeset fields are properly registered" do
    # Ecto's __changeset__/0 should include our fields
    changeset_fields = TestSchema1.__changeset__()
    assert changeset_fields[:name] == :string
    assert changeset_fields[:age] == :integer
  end

  # Test 4: Check if associations still work with overridden field
  defmodule ParentSchema do
    use Ecto.Schema

    schema "parents" do
      import Ecto.Schema, except: [field: 3]
      import Events.SchemaFieldOverrideTest.CustomField

      field(:title, :string, min: 1, max: 255)
      has_many :children, Events.SchemaFieldOverrideTest.ChildSchema
    end
  end

  defmodule ChildSchema do
    use Ecto.Schema

    schema "children" do
      field(:description, :string)
      belongs_to :parent, Events.SchemaFieldOverrideTest.ParentSchema
    end
  end

  test "associations work with custom field macro" do
    assert :children in ParentSchema.__schema__(:associations)
    assert :parent in ChildSchema.__schema__(:associations)
  end

  # Test 5: Verify validation metadata is captured
  defmodule SchemaWithValidations do
    use Ecto.Schema

    Module.register_attribute(__MODULE__, :field_validations, accumulate: true)

    schema "validated_table" do
      import Ecto.Schema, except: [field: 3]
      import Events.SchemaFieldOverrideTest.CustomField

      field(:email, :string, format: ~r/@/, required: true, cast: true)
      field(:age, :integer, min: 0, max: 150, required: true)
      field(:status, :string, in: ["active", "inactive"], cast: false)
    end

    def validations do
      @field_validations
    end
  end

  test "validation metadata is properly captured" do
    validations = SchemaWithValidations.validations()

    # Find validations for specific fields
    email_validations = Keyword.get(validations, :email)
    age_validations = Keyword.get(validations, :age)
    status_validations = Keyword.get(validations, :status)

    assert email_validations[:required] == true
    assert email_validations[:cast] == true
    assert age_validations[:min] == 0
    assert age_validations[:max] == 150
    assert status_validations[:cast] == false
  end

  # Test 6: Virtual fields with custom macro
  defmodule VirtualFieldSchema do
    use Ecto.Schema

    schema "virtual_test" do
      # Exclude Ecto's field and import our custom one
      import Kernel, except: []
      import Ecto.Schema, only: []
      import Events.SchemaFieldOverrideTest.CustomField

      field(:real_field, :string, min: 1)
      field(:virtual_field, :string, virtual: true, min: 1)
    end
  end

  test "virtual fields work with custom field macro" do
    assert :real_field in VirtualFieldSchema.__schema__(:fields)
    # Virtual fields are stored separately
    assert :virtual_field in VirtualFieldSchema.__schema__(:virtual_fields)
  end
end
