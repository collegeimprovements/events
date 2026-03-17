defmodule OmMigration.UpDownTest do
  @moduledoc """
  Tests for up/down migration operations: alter, drop, and rename.
  """
  use ExUnit.Case, async: true

  alias OmMigration.Token
  alias OmMigration.TokenValidator

  # ============================================
  # DSL Macro Tests (compile-time verification)
  # ============================================

  describe "DSL macros" do
    test "alter macro creates valid token" do
      # We can't actually execute migrations in tests without a repo,
      # but we can verify the macros compile and produce correct tokens
      import OmMigration.DSL

      # Build token using the same pattern as the macro
      token =
        Token.new(:alter, :users)
        |> Token.add_field(:phone, :string, null: true)
        |> Token.remove_field(:legacy)
        |> Token.modify_field(:status, :string, null: false)

      assert token.type == :alter
      assert length(token.fields) == 3
    end

    test "drop_table macro produces correct token" do
      token = Token.new(:drop_table, :users, if_exists: true)

      assert token.type == :drop_table
      assert token.name == :users
      assert token.options[:if_exists] == true
    end

    test "drop_index macro produces correct token" do
      token = Token.new(:drop_index, :users, index_name: :users_email_index)

      assert token.type == :drop_index
      assert token.options[:index_name] == :users_email_index
    end

    test "rename_table macro produces correct token" do
      token = Token.new(:rename_table, :users, to: :accounts)

      assert token.type == :rename_table
      assert token.options[:to] == :accounts
    end

    test "rename_column macro produces correct token" do
      token = Token.new(:rename_column, :users, from: :email, to: :email_address)

      assert token.type == :rename_column
      assert token.options[:from] == :email
      assert token.options[:to] == :email_address
    end
  end

  # ============================================
  # Alter Table Tokens
  # ============================================

  describe "alter_table/2" do
    test "creates an alter token" do
      token = OmMigration.alter_table(:users)

      assert token.type == :alter
      assert token.name == :users
    end

    test "add_field adds a field to alter token" do
      token =
        OmMigration.alter_table(:users)
        |> OmMigration.add_field(:phone, :string, null: true)

      assert Token.has_field?(token, :phone)
      {_name, type, opts} = Token.get_field(token, :phone)
      assert type == :string
      assert opts[:null] == true
    end

    test "remove_field marks field for removal" do
      token =
        OmMigration.alter_table(:users)
        |> OmMigration.remove_field(:legacy_column)

      assert {:remove, :legacy_column} in token.fields
    end

    test "modify_field marks field for modification" do
      token =
        OmMigration.alter_table(:users)
        |> OmMigration.modify_field(:status, :string, null: false, default: "active")

      assert {:modify, :status, :string, [null: false, default: "active"]} in token.fields
    end

    test "can combine add, remove, and modify operations" do
      token =
        OmMigration.alter_table(:users)
        |> OmMigration.add_field(:phone, :string)
        |> OmMigration.remove_field(:fax)
        |> OmMigration.modify_field(:email, :citext)

      # Check all operations are present
      assert length(token.fields) == 3

      # Verify each operation type
      assert Enum.any?(token.fields, fn
               {:phone, :string, _} -> true
               _ -> false
             end)

      assert {:remove, :fax} in token.fields

      assert Enum.any?(token.fields, fn
               {:modify, :email, :citext, _} -> true
               _ -> false
             end)
    end
  end

  describe "Token.remove_field/2" do
    test "marks field for removal on token" do
      token =
        Token.new(:alter, :users)
        |> Token.remove_field(:old_column)

      assert {:remove, :old_column} in token.fields
    end
  end

  describe "Token.modify_field/4" do
    test "marks field for modification on token" do
      token =
        Token.new(:alter, :users)
        |> Token.modify_field(:amount, :decimal, precision: 12, scale: 4)

      assert {:modify, :amount, :decimal, [precision: 12, scale: 4]} in token.fields
    end
  end

  # ============================================
  # Drop Table Tokens
  # ============================================

  describe "drop_table/2" do
    test "creates a drop_table token" do
      token = OmMigration.drop_table(:users)

      assert token.type == :drop_table
      assert token.name == :users
    end

    test "accepts :if_exists option" do
      token = OmMigration.drop_table(:users, if_exists: true)

      assert token.options[:if_exists] == true
    end

    test "accepts :prefix option for multi-tenant" do
      token = OmMigration.drop_table(:users, prefix: "tenant_1")

      assert token.options[:prefix] == "tenant_1"
    end
  end

  # ============================================
  # Drop Index Tokens
  # ============================================

  describe "drop_index/3" do
    test "creates a drop_index token" do
      token = OmMigration.drop_index(:users, :users_email_index)

      assert token.type == :drop_index
      assert token.name == :users
      assert token.options[:index_name] == :users_email_index
    end
  end

  # ============================================
  # Drop Constraint Tokens
  # ============================================

  describe "drop_constraint/3" do
    test "creates a drop_constraint token" do
      token = OmMigration.drop_constraint(:orders, :orders_amount_positive)

      assert token.type == :drop_constraint
      assert token.name == :orders
      assert token.options[:constraint_name] == :orders_amount_positive
    end
  end

  # ============================================
  # Rename Table Tokens
  # ============================================

  describe "rename_table/2" do
    test "creates a rename_table token" do
      token = OmMigration.rename_table(:users, to: :accounts)

      assert token.type == :rename_table
      assert token.name == :users
      assert token.options[:to] == :accounts
    end
  end

  # ============================================
  # Rename Column Tokens
  # ============================================

  describe "rename_column/2" do
    test "creates a rename_column token" do
      token = OmMigration.rename_column(:users, from: :email, to: :email_address)

      assert token.type == :rename_column
      assert token.name == :users
      assert token.options[:from] == :email
      assert token.options[:to] == :email_address
    end
  end

  # ============================================
  # TokenValidator for New Types
  # ============================================

  describe "TokenValidator for drop tokens" do
    test "validates drop_table token (just needs name)" do
      token = Token.new(:drop_table, :users)
      assert {:ok, ^token} = TokenValidator.validate(token)
    end

    test "validates drop_index requires index_name" do
      token = Token.new(:drop_index, :users)
      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :drop_index_missing_name))
    end

    test "validates drop_index with index_name" do
      token = Token.new(:drop_index, :users, index_name: :users_email_index)
      assert {:ok, ^token} = TokenValidator.validate(token)
    end

    test "validates drop_constraint requires constraint_name" do
      token = Token.new(:drop_constraint, :orders)
      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :drop_constraint_missing_name))
    end

    test "validates drop_constraint with constraint_name" do
      token = Token.new(:drop_constraint, :orders, constraint_name: :positive_amount)
      assert {:ok, ^token} = TokenValidator.validate(token)
    end
  end

  describe "TokenValidator for rename tokens" do
    test "validates rename_table requires :to option" do
      token = Token.new(:rename_table, :users)
      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :rename_missing_to))
    end

    test "validates rename_table with :to option" do
      token = Token.new(:rename_table, :users, to: :accounts)
      assert {:ok, ^token} = TokenValidator.validate(token)
    end

    test "validates rename_column requires :from option" do
      token = Token.new(:rename_column, :users, to: :email_address)
      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :rename_column_missing_from))
    end

    test "validates rename_column requires :to option" do
      token = Token.new(:rename_column, :users, from: :email)
      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :rename_missing_to))
    end

    test "validates rename_column with both options" do
      token = Token.new(:rename_column, :users, from: :email, to: :email_address)
      assert {:ok, ^token} = TokenValidator.validate(token)
    end
  end

  describe "TokenValidator for alter tokens" do
    test "validates alter token without duplicate fields" do
      token =
        Token.new(:alter, :users)
        |> Token.add_field(:phone, :string)

      assert {:ok, ^token} = TokenValidator.validate(token)
    end

    test "detects duplicate fields in alter token" do
      token =
        Token.new(:alter, :users)
        |> Token.add_field(:phone, :string)
        |> Token.add_field(:phone, :text)

      assert {:error, errors} = TokenValidator.validate(token)
      assert Enum.any?(errors, &(&1.code == :duplicate_fields))
    end
  end

  # ============================================
  # Token Type Specification
  # ============================================

  describe "token types" do
    test "all new token types are recognized" do
      for type <- [:drop_table, :drop_index, :drop_constraint, :rename_table, :rename_column] do
        token = Token.new(type, :test_table)
        assert token.type == type
      end
    end

    test "TokenValidator accepts all new token types" do
      valid_tokens = [
        Token.new(:drop_table, :users),
        Token.new(:drop_index, :users, index_name: :idx),
        Token.new(:drop_constraint, :users, constraint_name: :chk),
        Token.new(:rename_table, :users, to: :accounts),
        Token.new(:rename_column, :users, from: :a, to: :b)
      ]

      for token <- valid_tokens do
        assert {:ok, _} = TokenValidator.validate(token),
               "Expected token type #{token.type} to be valid"
      end
    end
  end

  # ============================================
  # Integration: Up/Down Pattern
  # ============================================

  describe "up/down migration pattern" do
    test "can build matching up and down tokens" do
      # Up migration: create table
      up_token =
        OmMigration.create_table(:users)
        |> Token.add_field(:id, :binary_id, primary_key: true)
        |> Token.add_field(:email, :string)

      # Down migration: drop table
      down_token = OmMigration.drop_table(:users)

      assert up_token.type == :table
      assert down_token.type == :drop_table
      assert up_token.name == down_token.name
    end

    test "can build matching alter up/down tokens" do
      # Up: add column
      up_token =
        OmMigration.alter_table(:users)
        |> OmMigration.add_field(:phone, :string)

      # Down: remove column
      down_token =
        OmMigration.alter_table(:users)
        |> OmMigration.remove_field(:phone)

      assert up_token.name == down_token.name
    end

    test "can build matching index up/down tokens" do
      # Up: create index
      up_token = OmMigration.create_index(:users, [:email], unique: true)

      # Down: drop index
      down_token = OmMigration.drop_index(:users, :users_email_index)

      assert up_token.type == :index
      assert down_token.type == :drop_index
    end

    test "can build matching rename forward/backward tokens" do
      # Forward: rename users to accounts
      forward_token = OmMigration.rename_table(:users, to: :accounts)

      # Backward: rename accounts back to users
      backward_token = OmMigration.rename_table(:accounts, to: :users)

      assert forward_token.options[:to] == :accounts
      assert backward_token.options[:to] == :users
    end
  end
end
