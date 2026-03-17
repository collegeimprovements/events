defmodule OmSchema.OpenAPITest do
  @moduledoc """
  Tests for OmSchema.OpenAPI - OpenAPI 3.x schema generation from OmSchema.

  Validates that OmSchema field definitions, validations, and constraints
  are correctly converted to OpenAPI schema format.
  """

  use ExUnit.Case, async: true

  alias OmSchema.OpenAPI

  # Test schemas using OmSchema
  defmodule TestUser do
    use OmSchema

    schema "test_users" do
      field :email, :string, required: true, format: :email, max_length: 255
      field :name, :string, max_length: 100, doc: "User's full name"
      field :age, :integer, min: 0, max: 150
      field :is_admin, :boolean, default: false
      field :role, Ecto.Enum, values: [:user, :moderator, :admin], required: true
      field :tags, {:array, :string}
      field :metadata, :map
      field :password_hash, :string, sensitive: true
      field :account_id, :binary_id, immutable: true
      field :created_at, :utc_datetime
    end
  end

  defmodule TestAccount do
    use OmSchema

    schema "test_accounts" do
      field :name, :string, required: true, min_length: 2, max_length: 100
      field :slug, :string, required: true, format: :slug
      field :website, :string, format: :url
    end
  end

  # ============================================
  # Basic Schema Generation
  # ============================================

  describe "to_schema/2" do
    test "generates OpenAPI schema object" do
      schema = OpenAPI.to_schema(TestUser)

      assert schema[:type] == "object"
      assert is_map(schema[:properties])
    end

    test "includes required fields" do
      schema = OpenAPI.to_schema(TestUser)

      assert :email in schema[:required]
      assert :role in schema[:required]
      refute :name in (schema[:required] || [])
    end

    test "maps string type correctly" do
      schema = OpenAPI.to_schema(TestUser)

      email_schema = schema.properties.email
      assert email_schema.type == "string"
    end

    test "maps integer type correctly" do
      schema = OpenAPI.to_schema(TestUser)

      age_schema = schema.properties.age
      assert age_schema.type == ["integer", "null"]
    end

    test "maps boolean type correctly" do
      schema = OpenAPI.to_schema(TestUser)

      is_admin_schema = schema.properties.is_admin
      assert is_admin_schema.type == ["boolean", "null"]
      assert is_admin_schema.default == false
    end

    test "maps array type correctly" do
      schema = OpenAPI.to_schema(TestUser)

      tags_schema = schema.properties.tags
      assert tags_schema.type == ["array", "null"]
    end

    test "maps map type correctly" do
      schema = OpenAPI.to_schema(TestUser)

      metadata_schema = schema.properties.metadata
      assert metadata_schema.type == ["object", "null"]
    end

    test "maps datetime type correctly" do
      schema = OpenAPI.to_schema(TestUser)

      created_at_schema = schema.properties.created_at
      assert created_at_schema.format == "date-time"
    end

    test "includes id field by default" do
      schema = OpenAPI.to_schema(TestUser)

      assert Map.has_key?(schema.properties, :id)
      id_schema = schema.properties.id
      assert id_schema.format == "uuid"
    end

    test "excludes id field when include_id: false" do
      schema = OpenAPI.to_schema(TestUser, include_id: false)

      refute Map.has_key?(schema.properties, :id)
    end
  end

  # ============================================
  # Validation Constraints
  # ============================================

  describe "to_schema/2 constraints" do
    test "includes min_length constraint" do
      schema = OpenAPI.to_schema(TestAccount)

      name_schema = schema.properties.name
      assert name_schema.minLength == 2
    end

    test "includes max_length constraint" do
      schema = OpenAPI.to_schema(TestUser)

      email_schema = schema.properties.email
      assert email_schema.maxLength == 255
    end

    test "includes minimum constraint" do
      schema = OpenAPI.to_schema(TestUser)

      age_schema = schema.properties.age
      assert age_schema.minimum == 0
    end

    test "includes maximum constraint" do
      schema = OpenAPI.to_schema(TestUser)

      age_schema = schema.properties.age
      assert age_schema.maximum == 150
    end
  end

  # ============================================
  # Formats
  # ============================================

  describe "to_schema/2 formats" do
    test "includes email format" do
      schema = OpenAPI.to_schema(TestUser)

      email_schema = schema.properties.email
      assert email_schema.format == "email"
    end

    test "includes url format as uri" do
      schema = OpenAPI.to_schema(TestAccount)

      website_schema = schema.properties.website
      assert website_schema.format == "uri"
    end

    test "includes uuid format for binary_id" do
      schema = OpenAPI.to_schema(TestUser)

      account_id_schema = schema.properties.account_id
      assert account_id_schema.format == "uuid"
    end
  end

  # ============================================
  # Enum Support
  # ============================================

  describe "to_schema/2 enums" do
    test "includes enum values for Ecto.Enum" do
      schema = OpenAPI.to_schema(TestUser)

      role_schema = schema.properties.role
      assert role_schema.enum == [:user, :moderator, :admin]
    end
  end

  # ============================================
  # Documentation
  # ============================================

  describe "to_schema/2 documentation" do
    test "includes description from doc option" do
      schema = OpenAPI.to_schema(TestUser)

      name_schema = schema.properties.name
      assert name_schema.description == "User's full name"
    end
  end

  # ============================================
  # Special Properties
  # ============================================

  describe "to_schema/2 special properties" do
    test "marks sensitive fields as writeOnly" do
      schema = OpenAPI.to_schema(TestUser)

      password_schema = schema.properties.password_hash
      assert password_schema.writeOnly == true
    end

    test "marks immutable fields as readOnly" do
      schema = OpenAPI.to_schema(TestUser)

      account_id_schema = schema.properties.account_id
      assert account_id_schema.readOnly == true
    end
  end

  # ============================================
  # Nullable Styles
  # ============================================

  describe "to_schema/2 nullable_style" do
    test "uses type array for nullable by default (OpenAPI 3.1)" do
      schema = OpenAPI.to_schema(TestUser)

      # name is optional (nullable)
      name_schema = schema.properties.name
      assert name_schema.type == ["string", "null"]
    end

    test "uses nullable property when nullable_style: :nullable_property (OpenAPI 3.0)" do
      schema = OpenAPI.to_schema(TestUser, nullable_style: :nullable_property)

      # name is optional (nullable)
      name_schema = schema.properties.name
      assert name_schema.type == "string"
      assert name_schema.nullable == true
    end

    test "does not add nullable for required fields" do
      schema = OpenAPI.to_schema(TestUser)

      # email is required (not nullable)
      email_schema = schema.properties.email
      assert email_schema.type == "string"
    end
  end

  # ============================================
  # Components Generation
  # ============================================

  describe "to_components/2" do
    test "generates components for multiple schemas" do
      components = OpenAPI.to_components([TestUser, TestAccount])

      assert Map.has_key?(components, "TestUser")
      assert Map.has_key?(components, "TestAccount")
    end

    test "each component is a valid schema" do
      components = OpenAPI.to_components([TestUser, TestAccount])

      assert components["TestUser"].type == "object"
      assert components["TestAccount"].type == "object"
    end

    test "respects options for all schemas" do
      components = OpenAPI.to_components([TestUser, TestAccount], include_id: false)

      refute Map.has_key?(components["TestUser"].properties, :id)
      refute Map.has_key?(components["TestAccount"].properties, :id)
    end
  end

  # ============================================
  # Paths Generation
  # ============================================

  describe "to_paths/2" do
    test "generates collection and resource paths" do
      paths = OpenAPI.to_paths(TestUser, base_path: "/users")

      assert Map.has_key?(paths, "/users")
      assert Map.has_key?(paths, "/users/{id}")
    end

    test "includes CRUD operations" do
      paths = OpenAPI.to_paths(TestUser, base_path: "/users")

      collection = paths["/users"]
      assert Map.has_key?(collection, :get)
      assert Map.has_key?(collection, :post)

      resource = paths["/users/{id}"]
      assert Map.has_key?(resource, :get)
      assert Map.has_key?(resource, :put)
      assert Map.has_key?(resource, :delete)
    end

    test "respects operations option" do
      paths = OpenAPI.to_paths(TestUser, base_path: "/users", operations: [:list, :get])

      assert Map.has_key?(paths["/users"], :get)
      refute Map.has_key?(paths["/users"], :post)

      assert Map.has_key?(paths["/users/{id}"], :get)
      refute Map.has_key?(paths["/users/{id}"], :put)
      refute Map.has_key?(paths["/users/{id}"], :delete)
    end

    test "includes tags" do
      paths = OpenAPI.to_paths(TestUser, base_path: "/users", tags: ["Users"])

      list_op = paths["/users"].get
      assert list_op.tags == ["Users"]
    end
  end

  # ============================================
  # Full Document Generation
  # ============================================

  describe "to_document/2" do
    test "generates complete OpenAPI document" do
      doc = OpenAPI.to_document([TestUser, TestAccount],
        title: "Test API",
        version: "2.0.0"
      )

      assert doc.openapi == "3.1.0"
      assert doc.info.title == "Test API"
      assert doc.info.version == "2.0.0"
      assert is_map(doc.paths)
      assert is_map(doc.components.schemas)
    end

    test "includes schemas in components" do
      doc = OpenAPI.to_document([TestUser, TestAccount])

      assert Map.has_key?(doc.components.schemas, "TestUser")
      assert Map.has_key?(doc.components.schemas, "TestAccount")
    end
  end

  # ============================================
  # Introspection Delegation
  # ============================================

  describe "OmSchema.Introspection.to_openapi_schema/2" do
    test "delegates to OpenAPI.to_schema" do
      schema1 = OmSchema.Introspection.to_openapi_schema(TestUser)
      schema2 = OpenAPI.to_schema(TestUser)

      assert schema1 == schema2
    end
  end
end
