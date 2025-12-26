defmodule Events.Core.Migration.TokenValidatorTest do
  use Events.TestCase, async: true

  alias OmMigration.Token
  alias OmMigration.TokenValidator
  alias OmMigration.ValidationError

  describe "TokenValidator.validate/1" do
    test "returns ok for valid table token" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:id, :uuid, primary_key: true)
        |> Token.add_field(:email, :string, null: false)

      assert {:ok, ^token} = TokenValidator.validate(token)
    end

    test "returns all errors found, not just the first" do
      # Create a token with multiple issues
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:email, :string, [])
        # duplicate
        |> Token.add_field(:email, :string, [])
        |> Token.add_index(:idx_missing, [:nonexistent], [])

      assert {:error, errors} = TokenValidator.validate(token)
      # At least duplicate fields and missing index columns
      assert length(errors) >= 2
    end
  end

  describe "TokenValidator.validate!/1" do
    test "returns token when valid" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      assert ^token = TokenValidator.validate!(token)
    end

    test "raises ValidationError with details when invalid" do
      token = Token.new(:table, :users)

      assert_raise ValidationError, fn ->
        TokenValidator.validate!(token)
      end
    end

    test "error includes all validation errors" do
      token = Token.new(:table, :users)

      error = catch_error(TokenValidator.validate!(token))

      assert error.errors != []
      assert is_list(error.errors)
    end
  end

  describe "TokenValidator.valid?/1" do
    test "returns true for valid token" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])

      assert TokenValidator.valid?(token)
    end

    test "returns false for invalid token" do
      token = Token.new(:table, :users)

      refute TokenValidator.valid?(token)
    end
  end

  describe "validation - token type" do
    test "validates token type is valid" do
      token = %Token{
        type: :invalid_type,
        name: :test,
        fields: [],
        indexes: [],
        constraints: [],
        options: [],
        meta: %{}
      }

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :invalid_token_type))
    end

    test "accepts table token type" do
      token =
        Token.new(:table, :test)
        |> Token.add_field(:id, :uuid, primary_key: true)

      result = TokenValidator.validate(token)
      refute match?({:error, [%{code: :invalid_token_type} | _]}, result)
    end

    test "accepts index token type" do
      token = Token.new(:index, :test, columns: [:id])

      result = TokenValidator.validate(token)
      refute match?({:error, [%{code: :invalid_token_type} | _]}, result)
    end

    test "accepts constraint token type" do
      token = Token.new(:constraint, :test)

      result = TokenValidator.validate(token)
      refute match?({:error, [%{code: :invalid_token_type} | _]}, result)
    end

    test "accepts alter token type" do
      token = Token.new(:alter, :test)

      result = TokenValidator.validate(token)
      refute match?({:error, [%{code: :invalid_token_type} | _]}, result)
    end
  end

  describe "validation - duplicate fields" do
    test "detects duplicate field names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        |> Token.add_field(:email, :string, [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :duplicate_fields))

      error = Enum.find(errors, &(&1.code == :duplicate_fields))
      assert [:email] = error.details.duplicates
    end

    test "allows unique field names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        |> Token.add_field(:name, :string, [])

      assert {:ok, _} = TokenValidator.validate(token)
    end
  end

  describe "validation - index columns" do
    test "detects index referencing non-existent fields" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        # name field doesn't exist
        |> Token.add_index(:idx_name, [:name], [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :index_missing_columns))

      error = Enum.find(errors, &(&1.code == :index_missing_columns))
      assert [:name] = error.details.missing_columns
    end

    test "allows index on existing fields" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        |> Token.add_index(:idx_email, [:email], [])

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "detects partial missing columns in composite index" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        |> Token.add_index(:idx_composite, [:email, :name, :age], [])

      assert {:error, errors} = TokenValidator.validate(token)

      error = Enum.find(errors, &(&1.code == :index_missing_columns))
      assert :name in error.details.missing_columns
      assert :age in error.details.missing_columns
      refute :email in error.details.missing_columns
    end
  end

  describe "validation - foreign key types" do
    test "accepts valid reference types" do
      for type <- [:uuid, :binary_id, :bigint, :integer, :id] do
        token =
          Token.new(:table, :posts)
          |> Token.add_field(:id, :uuid, primary_key: true)
          |> Token.add_field(:user_id, {:references, :users, type: type}, [])

        assert {:ok, _} = TokenValidator.validate(token),
               "Reference type #{type} should be valid"
      end
    end

    test "rejects invalid reference types" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:id, :uuid, primary_key: true)
        |> Token.add_field(:user_id, {:references, :users, type: :invalid}, [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :invalid_reference_type))
    end
  end

  describe "validation - check constraints" do
    test "detects check constraint without expression" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer, [])
        # missing expr
        |> Token.add_constraint(:age_positive, :check, [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :missing_constraint_expression))
    end

    test "accepts check constraint with expr option" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer, [])
        |> Token.add_constraint(:age_positive, :check, expr: "age >= 0")

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "accepts check constraint with expression option" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer, [])
        |> Token.add_constraint(:age_positive, :check, expression: "age >= 0")

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "ignores non-check constraints" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string, [])
        # no expr needed
        |> Token.add_constraint(:email_unique, :unique, [])

      assert {:ok, _} = TokenValidator.validate(token)
    end
  end

  describe "validation - index tokens" do
    test "detects index with no columns" do
      token = Token.new(:index, :idx_test)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :index_no_columns))
    end

    test "accepts index with columns" do
      token = Token.new(:index, :idx_test, columns: [:email])

      assert {:ok, _} = TokenValidator.validate(token)
    end
  end

  describe "error formatting" do
    test "error messages include table name" do
      token = Token.new(:table, :my_special_table)

      error = catch_error(TokenValidator.validate!(token))

      assert error.message =~ "my_special_table"
    end

    test "error contains structured error list" do
      token = Token.new(:table, :users)

      error = catch_error(TokenValidator.validate!(token))

      assert is_list(error.errors)

      assert Enum.all?(error.errors, fn e ->
               is_map(e) and Map.has_key?(e, :code) and Map.has_key?(e, :message)
             end)
    end
  end
end
