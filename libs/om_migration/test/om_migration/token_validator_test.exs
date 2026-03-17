defmodule OmMigration.TokenValidatorTest do
  @moduledoc """
  Tests for OmMigration.TokenValidator - Comprehensive token validation.

  TokenValidator performs detailed validation of migration tokens before execution,
  providing comprehensive error messages to help developers fix issues quickly.

  ## Validations Tested

  - Token type validity
  - Token name format (atom or string)
  - Table tokens: fields, primary key, duplicates, indexes, foreign keys, constraints
  - Index tokens: columns specification
  """

  use ExUnit.Case, async: true

  alias OmMigration.{Token, TokenValidator}

  # ============================================
  # Core Validations
  # ============================================

  describe "validate/1 - token type" do
    test "accepts valid token types" do
      # Table token
      table_token = Token.new(:table, :test) |> Token.add_field(:name, :string)
      assert {:ok, _} = TokenValidator.validate(table_token)

      # Index token needs columns
      index_token = Token.new(:index, :test, columns: [:name])
      assert {:ok, _} = TokenValidator.validate(index_token)

      # Constraint and alter tokens
      constraint_token = Token.new(:constraint, :test) |> Token.add_field(:name, :string)
      assert {:ok, _} = TokenValidator.validate(constraint_token)

      alter_token = Token.new(:alter, :test) |> Token.add_field(:name, :string)
      assert {:ok, _} = TokenValidator.validate(alter_token)
    end

    test "rejects invalid token type" do
      token = %Token{
        type: :invalid_type,
        name: :test,
        fields: [{:name, :string, []}],
        indexes: [],
        constraints: [],
        options: [],
        meta: %{}
      }

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :invalid_token_type))
    end
  end

  describe "validate/1 - token name" do
    test "accepts atom name" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "accepts string name" do
      token =
        Token.new(:table, "users")
        |> Token.add_field(:name, :string)

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "rejects invalid name type" do
      token = %Token{
        type: :table,
        name: 123,
        fields: [{:name, :string, []}],
        indexes: [],
        constraints: [],
        options: [],
        meta: %{}
      }

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :invalid_token_name))
    end
  end

  # ============================================
  # Table Validations
  # ============================================

  describe "validate/1 - table fields" do
    test "rejects table with no fields" do
      token = Token.new(:table, :users)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :no_fields))
    end

    test "accepts table with fields" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert {:ok, _} = TokenValidator.validate(token)
    end
  end

  describe "validate/1 - duplicate fields" do
    test "rejects table with duplicate field names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string)
        |> Token.add_field(:email, :citext)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :duplicate_fields))
    end

    test "accepts table with unique field names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string)
        |> Token.add_field(:name, :string)

      assert {:ok, _} = TokenValidator.validate(token)
    end
  end

  describe "validate/1 - primary key" do
    test "accepts table with implicit primary key" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "accepts table with explicit primary key field" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:id, :binary_id, primary_key: true)
        |> Token.add_field(:name, :string)

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "rejects table without primary key when disabled" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:name, :string)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :no_primary_key))
    end
  end

  describe "validate/1 - index columns exist" do
    test "accepts index referencing existing fields" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string)
        |> Token.add_index(:users_email_index, [:email], unique: true)

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "rejects index referencing non-existent fields" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)
        |> Token.add_index(:users_email_index, [:email], unique: true)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :index_missing_columns))

      error = Enum.find(errors, &(&1.code == :index_missing_columns))
      assert error.details.missing_columns == [:email]
    end

    test "rejects index with multiple non-existent fields" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)
        |> Token.add_index(:users_composite_index, [:email, :phone], [])

      assert {:error, errors} = TokenValidator.validate(token)
      error = Enum.find(errors, &(&1.code == :index_missing_columns))
      assert :email in error.details.missing_columns
      assert :phone in error.details.missing_columns
    end
  end

  describe "validate/1 - foreign key types" do
    test "accepts valid reference types" do
      for type <- [:uuid, :binary_id, :bigint, :integer, :id] do
        token =
          Token.new(:table, :posts)
          |> Token.add_field(:user_id, {:references, :users, [type: type]}, [])

        assert {:ok, _} = TokenValidator.validate(token)
      end
    end

    test "rejects invalid reference type" do
      token =
        Token.new(:table, :posts)
        |> Token.add_field(:user_id, {:references, :users, [type: :invalid_type]}, [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :invalid_reference_type))
    end
  end

  describe "validate/1 - constraint expressions" do
    test "accepts check constraint with expression" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer)
        |> Token.add_constraint(:age_positive, :check, expr: "age > 0")

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "accepts check constraint with expression key" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer)
        |> Token.add_constraint(:age_positive, :check, expression: "age > 0")

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "rejects check constraint without expression" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer)
        |> Token.add_constraint(:age_positive, :check, [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :missing_constraint_expression))
    end
  end

  # ============================================
  # Index Validations
  # ============================================

  describe "validate/1 - index tokens" do
    test "accepts index with columns" do
      token = Token.new(:index, :users_email_index, columns: [:email])

      assert {:ok, _} = TokenValidator.validate(token)
    end

    test "rejects index without columns" do
      token = Token.new(:index, :users_email_index)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :index_no_columns))
    end

    test "rejects index with empty columns" do
      token = Token.new(:index, :users_email_index, columns: [])

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :index_no_columns))
    end
  end

  # ============================================
  # validate!/1 Tests
  # ============================================

  describe "validate!/1" do
    test "returns token when valid" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert TokenValidator.validate!(token) == token
    end

    test "raises OmMigration.ValidationError when invalid" do
      token = Token.new(:table, :users)

      assert_raise OmMigration.ValidationError, fn ->
        TokenValidator.validate!(token)
      end
    end

    test "error message contains helpful information" do
      token = Token.new(:table, :users)

      error =
        assert_raise OmMigration.ValidationError, fn ->
          TokenValidator.validate!(token)
        end

      assert error.message =~ "users"
      assert error.message =~ "no fields"
    end
  end

  # ============================================
  # valid?/1 Tests
  # ============================================

  describe "valid?/1" do
    test "returns true for valid token" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert TokenValidator.valid?(token) == true
    end

    test "returns false for invalid token" do
      token = Token.new(:table, :users)

      assert TokenValidator.valid?(token) == false
    end
  end

  # ============================================
  # Multiple Errors
  # ============================================

  describe "multiple validation errors" do
    test "returns all errors found" do
      token =
        Token.new(:table, :users, primary_key: false)
        |> Token.add_field(:email, :string)
        |> Token.add_field(:email, :citext)
        |> Token.add_index(:users_phone_index, [:phone], [])
        |> Token.add_constraint(:age_check, :check, [])

      assert {:error, errors} = TokenValidator.validate(token)

      # Should have multiple errors
      assert length(errors) >= 3

      error_codes = Enum.map(errors, & &1.code)
      assert :no_primary_key in error_codes
      assert :duplicate_fields in error_codes
      assert :index_missing_columns in error_codes
      assert :missing_constraint_expression in error_codes
    end
  end

  # ============================================
  # Error Details
  # ============================================

  describe "error details" do
    test "error includes code, message, field, and details" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)
        |> Token.add_index(:users_email_index, [:email], [])

      assert {:error, [error]} = TokenValidator.validate(token)

      assert is_atom(error.code)
      assert is_binary(error.message)
      assert Map.has_key?(error, :field)
      assert is_map(error.details)
    end

    test "missing column error includes column names" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)
        |> Token.add_index(:idx, [:missing1, :missing2], [])

      assert {:error, errors} = TokenValidator.validate(token)
      error = Enum.find(errors, &(&1.code == :index_missing_columns))

      assert :missing1 in error.details.missing_columns
      assert :missing2 in error.details.missing_columns
    end
  end
end
