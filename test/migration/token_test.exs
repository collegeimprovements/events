defmodule Events.Migration.TokenTest do
  use ExUnit.Case, async: true

  alias Events.Migration.Token

  describe "Token.new/3" do
    test "creates a table token with name" do
      token = Token.new(:table, :users)

      assert token.type == :table
      assert token.name == :users
      assert token.fields == []
      assert token.indexes == []
      assert token.constraints == []
      assert is_map(token.meta)
    end

    test "creates an index token with options" do
      token = Token.new(:index, :users_email_index, columns: [:email])

      assert token.type == :index
      assert token.name == :users_email_index
      assert token.options[:columns] == [:email]
    end

    test "includes creation timestamp in meta" do
      token = Token.new(:table, :users)

      assert %DateTime{} = token.meta[:created_at]
    end
  end

  describe "Token.add_field/4" do
    test "adds a field to the token" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)

      assert [{:email, :string, [null: false]}] = token.fields
    end

    test "appends fields in order" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string, [])
        |> Token.add_field(:email, :string, [])
        |> Token.add_field(:age, :integer, [])

      assert [
               {:name, :string, []},
               {:email, :string, []},
               {:age, :integer, []}
             ] = token.fields
    end
  end

  describe "Token.add_fields/2" do
    test "adds multiple fields at once" do
      fields = [
        {:name, :string, []},
        {:email, :string, [null: false]},
        {:age, :integer, []}
      ]

      token =
        Token.new(:table, :users)
        |> Token.add_fields(fields)

      assert token.fields == fields
    end
  end

  describe "Token.add_index/4" do
    test "adds an index to the token" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:users_email_index, [:email], unique: true)

      assert [{:users_email_index, [:email], [unique: true]}] = token.indexes
    end

    test "supports composite indexes" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:users_name_email_index, [:name, :email], [])

      [{name, columns, _opts}] = token.indexes
      assert name == :users_name_email_index
      assert columns == [:name, :email]
    end
  end

  describe "Token.add_constraint/4" do
    test "adds a constraint to the token" do
      token =
        Token.new(:table, :users)
        |> Token.add_constraint(:age_positive, :check, expr: "age >= 0")

      assert [{:age_positive, :check, [expr: "age >= 0"]}] = token.constraints
    end
  end

  describe "Token.validate/1" do
    test "returns error for table with no fields" do
      token = Token.new(:table, :users)

      assert {:error, "Table users has no fields defined"} = Token.validate(token)
    end

    test "returns error for table with no primary key" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:email, :string, [])

      assert {:error, "Table users has no primary key defined"} = Token.validate(token)
    end

    test "returns ok for table with implicit primary key" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      assert {:ok, ^token} = Token.validate(token)
    end

    test "returns ok for table with explicit primary key field" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:id, :uuid, primary_key: true)
        |> Token.add_field(:email, :string, [])

      assert {:ok, ^token} = Token.validate(token)
    end

    test "returns error for index with no columns" do
      token = Token.new(:index, :users_email_index)

      assert {:error, "Index users_email_index has no columns defined"} = Token.validate(token)
    end

    test "returns ok for index with columns" do
      token = Token.new(:index, :users_email_index, columns: [:email])

      assert {:ok, ^token} = Token.validate(token)
    end
  end

  describe "Token.validate!/1" do
    test "returns token when valid" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      assert ^token = Token.validate!(token)
    end

    test "raises ArgumentError when invalid" do
      token = Token.new(:table, :users)

      assert_raise ArgumentError, ~r/has no fields defined/, fn ->
        Token.validate!(token)
      end
    end
  end

  describe "introspection - field_names/1" do
    test "returns list of field names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string, [])
        |> Token.add_field(:email, :string, [])
        |> Token.add_field(:age, :integer, [])

      assert [:name, :email, :age] = Token.field_names(token)
    end

    test "returns empty list when no fields" do
      token = Token.new(:table, :users)

      assert [] = Token.field_names(token)
    end
  end

  describe "introspection - has_field?/2" do
    test "returns true when field exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      assert Token.has_field?(token, :email)
    end

    test "returns false when field doesn't exist" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      refute Token.has_field?(token, :name)
    end
  end

  describe "introspection - get_field/2" do
    test "returns field definition when exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)

      assert {:email, :string, [null: false]} = Token.get_field(token, :email)
    end

    test "returns nil when field doesn't exist" do
      token = Token.new(:table, :users)

      assert nil == Token.get_field(token, :email)
    end
  end

  describe "introspection - index_names/1" do
    test "returns list of index names" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:idx_email, [:email], [])
        |> Token.add_index(:idx_name, [:name], [])

      assert [:idx_email, :idx_name] = Token.index_names(token)
    end
  end

  describe "introspection - has_index?/2" do
    test "returns true when index exists" do
      token =
        Token.new(:table, :users)
        |> Token.add_index(:idx_email, [:email], [])

      assert Token.has_index?(token, :idx_email)
    end

    test "returns false when index doesn't exist" do
      token = Token.new(:table, :users)

      refute Token.has_index?(token, :idx_email)
    end
  end

  describe "introspection - foreign_keys/1" do
    test "returns foreign key fields" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:title, :string, [])
        |> Token.add_field(:user_id, {:references, :users, type: :uuid}, [])
        |> Token.add_field(:category_id, {:references, :categories, type: :bigint}, [])

      fks = Token.foreign_keys(token)

      assert length(fks) == 2
      assert {:user_id, {:references, :users, type: :uuid}, []} in fks
      assert {:category_id, {:references, :categories, type: :bigint}, []} in fks
    end

    test "returns empty list when no foreign keys" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      assert [] = Token.foreign_keys(token)
    end
  end

  describe "introspection - referenced_tables/1" do
    test "returns unique referenced table names" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:user_id, {:references, :users, []}, [])
        |> Token.add_field(:author_id, {:references, :users, []}, [])
        |> Token.add_field(:category_id, {:references, :categories, []}, [])

      refs = Token.referenced_tables(token)
      assert :users in refs
      assert :categories in refs
      assert length(refs) == 2
    end
  end

  describe "introspection - unique_fields/1" do
    test "returns fields with unique option" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, unique: true)
        |> Token.add_field(:name, :string, [])

      assert [:email] = Token.unique_fields(token)
    end

    test "includes fields from unique indexes" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        |> Token.add_field(:name, :string, unique: true)
        |> Token.add_index(:idx_email, [:email], unique: true)

      unique = Token.unique_fields(token)
      assert :email in unique
      assert :name in unique
    end
  end

  describe "introspection - required_fields/1" do
    test "returns fields with null: false" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, null: false)
        |> Token.add_field(:name, :string, [])
        |> Token.add_field(:age, :integer, null: false)

      assert Enum.sort(Token.required_fields(token)) == [:age, :email]
    end
  end

  describe "introspection - fields_with_defaults/1" do
    test "returns fields with default values" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:role, :string, default: "user")
        |> Token.add_field(:active, :boolean, default: true)
        |> Token.add_field(:name, :string, [])

      defaults = Token.fields_with_defaults(token)

      assert {:role, "user"} in defaults
      assert {:active, true} in defaults
      assert length(defaults) == 2
    end
  end

  describe "introspection - summary/1" do
    test "returns comprehensive summary" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:id, :uuid, primary_key: true)
        |> Token.add_field(:email, :string, null: false, unique: true)
        |> Token.add_field(:name, :string, [])
        |> Token.add_index(:idx_email, [:email], unique: true)

      summary = Token.summary(token)

      assert summary.type == :table
      assert summary.name == :users
      assert summary.field_count == 3
      assert :email in summary.fields
      assert summary.has_primary_key == true
    end
  end

  describe "introspection - to_schema_fields/1" do
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
        Token.new(:table, :users)
        |> Token.add_field(:tags, {:array, :string}, [])

      [field] = Token.to_schema_fields(token)

      assert field == "field :tags, {:array, :string}"
    end
  end
end
