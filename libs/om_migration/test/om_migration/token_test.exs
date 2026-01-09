defmodule OmMigration.TokenTest do
  @moduledoc """
  Tests for OmMigration.Token - Migration building blocks.

  Token represents a pending migration operation (table, index, constraint),
  enabling functional composition and validation before execution.

  ## Use Cases

  - **Table creation**: Define fields, indexes, constraints before running
  - **Index creation**: Build complex indexes with conditions and methods
  - **Alter operations**: Modify existing tables safely
  - **Validation**: Catch errors before migration runs

  ## Pattern: Token-Based Migrations

      # Build a table token
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false, unique: true)
        |> Token.add_field(:name, :string)
        |> Token.add_index(:users_email_index, [:email], unique: true)
        |> Token.add_constraint(:email_format, :check, check: "email LIKE '%@%'")

      # Validate before execution
      {:ok, token} = Token.validate(token)

      # Query the token
      Token.has_field?(token, :email)         # true
      Token.unique_fields(token)              # [:email]
      Token.required_fields(token)            # [:email]

  Tokens enable introspection and composition before committing changes.
  """

  use ExUnit.Case, async: true

  alias OmMigration.Token

  # ============================================
  # Token Creation
  # ============================================

  describe "Token.new/3" do
    test "creates a table token with defaults" do
      token = Token.new(:table, :users)

      assert token.type == :table
      assert token.name == :users
      assert token.fields == []
      assert token.indexes == []
      assert token.constraints == []
      assert token.options == []
      assert is_map(token.meta)
      assert Map.has_key?(token.meta, :created_at)
    end

    test "creates a table token with options" do
      token = Token.new(:table, :users, primary_key: false)

      assert token.options == [primary_key: false]
    end

    test "creates an index token with columns" do
      token = Token.new(:index, :users, columns: [:email])

      assert token.type == :index
      assert token.name == :users
      assert token.options[:columns] == [:email]
    end

    test "creates different token types" do
      assert Token.new(:table, :users).type == :table
      assert Token.new(:index, :users).type == :index
      assert Token.new(:constraint, :users).type == :constraint
      assert Token.new(:alter, :users).type == :alter
    end
  end

  # ============================================
  # Field Operations
  # ============================================

  describe "Token.add_field/4" do
    test "adds a single field" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)

      assert length(token.fields) == 1
      assert {:email, :string, [null: false]} in token.fields
    end

    test "adds multiple fields sequentially" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)
        |> Token.add_field(:age, :integer)

      assert length(token.fields) == 2
      assert {:name, :string, []} in token.fields
      assert {:age, :integer, []} in token.fields
    end

    test "preserves field order" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:first, :string)
        |> Token.add_field(:second, :integer)
        |> Token.add_field(:third, :boolean)

      field_names = Enum.map(token.fields, fn {name, _, _} -> name end)
      assert field_names == [:first, :second, :third]
    end
  end

  describe "Token.add_fields/2" do
    test "adds multiple fields at once" do
      fields = [
        {:name, :string, [null: false]},
        {:email, :string, [unique: true]},
        {:age, :integer, []}
      ]

      token =
        Token.new(:table, :users)
        |> Token.add_fields(fields)

      assert length(token.fields) == 3
    end
  end

  # ============================================
  # Index Operations
  # ============================================

  describe "Token.add_index/4" do
    test "adds an index" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:users_email_index, [:email], unique: true)

      assert length(token.indexes) == 1
      assert {:users_email_index, [:email], [unique: true]} in token.indexes
    end

    test "adds multiple indexes" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:idx_email, [:email], unique: true)
        |> Token.add_index(:idx_name, [:name], [])

      assert length(token.indexes) == 2
    end
  end

  # ============================================
  # Constraint Operations
  # ============================================

  describe "Token.add_constraint/4" do
    test "adds a constraint" do
      token =
        Token.new(:table, :users)
        |> Token.add_constraint(:age_positive, :check, check: "age > 0")

      assert length(token.constraints) == 1
      assert {:age_positive, :check, [check: "age > 0"]} in token.constraints
    end
  end

  # ============================================
  # Option Operations
  # ============================================

  describe "Token.put_option/3" do
    test "adds an option" do
      token =
        Token.new(:table, :users)
        |> Token.put_option(:primary_key, false)

      assert token.options[:primary_key] == false
    end

    test "overwrites existing option" do
      token =
        Token.new(:table, :users, primary_key: true)
        |> Token.put_option(:primary_key, false)

      assert token.options[:primary_key] == false
    end
  end

  describe "Token.merge_options/2" do
    test "merges multiple options" do
      token =
        Token.new(:table, :users)
        |> Token.merge_options(primary_key: false, engine: "InnoDB")

      assert token.options[:primary_key] == false
      assert token.options[:engine] == "InnoDB"
    end
  end

  # ============================================
  # Metadata Operations
  # ============================================

  describe "Token.put_meta/3" do
    test "adds metadata" do
      token =
        Token.new(:table, :users)
        |> Token.put_meta(:author, "test")

      assert token.meta[:author] == "test"
    end

    test "preserves created_at in meta" do
      token =
        Token.new(:table, :users)
        |> Token.put_meta(:custom, "value")

      assert Map.has_key?(token.meta, :created_at)
      assert token.meta[:custom] == "value"
    end
  end

  # ============================================
  # Validation
  # ============================================

  describe "Token.validate/1" do
    test "returns error for table with no fields" do
      token = Token.new(:table, :users)

      assert {:error, message} = Token.validate(token)
      assert message =~ "no fields"
    end

    test "returns error for table with no primary key" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:name, :string)

      assert {:error, message} = Token.validate(token)
      assert message =~ "no primary key"
    end

    test "returns ok for valid table with implicit primary key" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert {:ok, ^token} = Token.validate(token)
    end

    test "returns ok for valid table with explicit primary key" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:id, :binary_id, primary_key: true)
        |> Token.add_field(:name, :string)

      assert {:ok, ^token} = Token.validate(token)
    end

    test "returns error for index with no columns" do
      token = Token.new(:index, :users_email_index)

      assert {:error, message} = Token.validate(token)
      assert message =~ "no columns"
    end

    test "returns ok for valid index" do
      token = Token.new(:index, :users, columns: [:email])

      assert {:ok, ^token} = Token.validate(token)
    end
  end

  describe "Token.validate!/1" do
    test "returns token when valid" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert Token.validate!(token) == token
    end

    test "raises ArgumentError when invalid" do
      token = Token.new(:table, :users)

      assert_raise ArgumentError, ~r/no fields/, fn ->
        Token.validate!(token)
      end
    end
  end

  # ============================================
  # Query Functions
  # ============================================

  describe "Token.has_primary_key?/1" do
    test "returns true when primary_key option is not false" do
      token = Token.new(:table, :users)
      assert Token.has_primary_key?(token) == true
    end

    test "returns false when primary_key option is false and no pk field" do
      token = Token.new(:table, :users, primary_key: false)
      assert Token.has_primary_key?(token) == false
    end

    test "returns true when field has primary_key: true" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:id, :binary_id, primary_key: true)

      assert Token.has_primary_key?(token) == true
    end
  end

  describe "Token.field_names/1" do
    test "returns empty list for token with no fields" do
      token = Token.new(:table, :users)
      assert Token.field_names(token) == []
    end

    test "returns field names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)
        |> Token.add_field(:email, :string)

      assert Token.field_names(token) == [:name, :email]
    end
  end

  describe "Token.has_field?/2" do
    test "returns true when field exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string)

      assert Token.has_field?(token, :email) == true
    end

    test "returns false when field does not exist" do
      token = Token.new(:table, :users)
      assert Token.has_field?(token, :email) == false
    end
  end

  describe "Token.get_field/2" do
    test "returns field when exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)

      assert Token.get_field(token, :email) == {:email, :string, [null: false]}
    end

    test "returns nil when field does not exist" do
      token = Token.new(:table, :users)
      assert Token.get_field(token, :email) == nil
    end
  end

  describe "Token.index_names/1" do
    test "returns index names" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:idx_email, [:email], [])
        |> Token.add_index(:idx_name, [:name], [])

      assert Token.index_names(token) == [:idx_email, :idx_name]
    end
  end

  describe "Token.has_index?/2" do
    test "returns true when index exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:idx_email, [:email], [])

      assert Token.has_index?(token, :idx_email) == true
    end

    test "returns false when index does not exist" do
      token = Token.new(:table, :users)
      assert Token.has_index?(token, :idx_email) == false
    end
  end

  describe "Token.get_index/2" do
    test "returns index when exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:idx_email, [:email], unique: true)

      assert Token.get_index(token, :idx_email) == {:idx_email, [:email], [unique: true]}
    end
  end

  describe "Token.constraint_names/1" do
    test "returns constraint names" do
      token =
        Token.new(:table, :users)
        |> Token.add_constraint(:age_positive, :check, check: "age > 0")

      assert Token.constraint_names(token) == [:age_positive]
    end
  end

  describe "Token.has_constraint?/2" do
    test "returns true when constraint exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_constraint(:age_positive, :check, check: "age > 0")

      assert Token.has_constraint?(token, :age_positive) == true
    end
  end

  describe "Token.get_constraint/2" do
    test "returns constraint when exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_constraint(:age_positive, :check, check: "age > 0")

      assert Token.get_constraint(token, :age_positive) == {:age_positive, :check, [check: "age > 0"]}
    end
  end

  # ============================================
  # Foreign Keys
  # ============================================

  describe "Token.foreign_keys/1" do
    test "returns empty list when no foreign keys" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:title, :string)

      assert Token.foreign_keys(token) == []
    end

    test "returns foreign key fields" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:user_id, {:references, :users, [type: :binary_id]}, [])

      fks = Token.foreign_keys(token)
      assert length(fks) == 1
      assert {:user_id, {:references, :users, [type: :binary_id]}, []} in fks
    end
  end

  describe "Token.referenced_tables/1" do
    test "returns referenced table names" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:user_id, {:references, :users, []}, [])
        |> Token.add_field(:category_id, {:references, :categories, []}, [])

      tables = Token.referenced_tables(token)
      assert :users in tables
      assert :categories in tables
    end

    test "returns unique table names" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:author_id, {:references, :users, []}, [])
        |> Token.add_field(:editor_id, {:references, :users, []}, [])

      assert Token.referenced_tables(token) == [:users]
    end
  end

  # ============================================
  # Unique Fields
  # ============================================

  describe "Token.unique_fields/1" do
    test "returns fields with unique: true option" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, unique: true)
        |> Token.add_field(:name, :string)

      assert Token.unique_fields(token) == [:email]
    end

    test "returns single-column unique indexes" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string)
        |> Token.add_index(:idx_email, [:email], unique: true)

      assert Token.unique_fields(token) == [:email]
    end

    test "does not include multi-column unique indexes" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:first_name, :string)
        |> Token.add_field(:last_name, :string)
        |> Token.add_index(:idx_name, [:first_name, :last_name], unique: true)

      assert Token.unique_fields(token) == []
    end
  end

  # ============================================
  # Required Fields
  # ============================================

  describe "Token.required_fields/1" do
    test "returns fields with null: false" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)
        |> Token.add_field(:name, :string)
        |> Token.add_field(:age, :integer, null: false)

      required = Token.required_fields(token)
      assert :email in required
      assert :age in required
      refute :name in required
    end
  end

  # ============================================
  # Fields with Defaults
  # ============================================

  describe "Token.fields_with_defaults/1" do
    test "returns fields with default values" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:status, :string, default: "active")
        |> Token.add_field(:count, :integer, default: 0)
        |> Token.add_field(:name, :string)

      defaults = Token.fields_with_defaults(token)
      assert {:status, "active"} in defaults
      assert {:count, 0} in defaults
      assert length(defaults) == 2
    end
  end

  # ============================================
  # Summary
  # ============================================

  describe "Token.summary/1" do
    test "returns summary map" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false, unique: true)
        |> Token.add_field(:name, :string)
        |> Token.add_index(:idx_email, [:email], unique: true)
        |> Token.add_constraint(:email_format, :check, check: "email LIKE '%@%'")

      summary = Token.summary(token)

      assert summary.type == :table
      assert summary.name == :users
      assert summary.field_count == 2
      assert :email in summary.fields
      assert :name in summary.fields
      assert summary.index_count == 1
      assert :idx_email in summary.indexes
      assert summary.constraint_count == 1
      assert :email_format in summary.constraints
      assert summary.has_primary_key == true
      assert :email in summary.unique_fields
      assert :email in summary.required_fields
    end
  end

  # ============================================
  # Schema Generation
  # ============================================

  describe "Token.to_schema_fields/1" do
    test "generates schema field definitions" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)
        |> Token.add_field(:age, :integer, default: 0)

      fields = Token.to_schema_fields(token)

      assert "field :email, :string, null: false" in fields
      assert "field :age, :integer, default: 0" in fields
    end

    test "handles array types" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:tags, {:array, :string})

      fields = Token.to_schema_fields(token)
      assert "field :tags, {:array, :string}" in fields
    end

    test "handles references" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:user_id, {:references, :users, []})

      fields = Token.to_schema_fields(token)
      assert "field :user_id, references(:users)" in fields
    end
  end
end
