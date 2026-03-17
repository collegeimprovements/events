defmodule OmMigration.DSLTest do
  @moduledoc """
  Tests for OmMigration.DSL - Declarative migration syntax.

  These tests verify macro expansion and token construction
  without actually executing migrations (which requires a database).

  The DSL provides a declarative syntax that ultimately builds tokens
  and passes them to the Executor.
  """

  use ExUnit.Case, async: true

  alias OmMigration.{Token, Pipeline}
  alias OmMigration.Helpers

  # ============================================
  # Token Building Tests (equivalent to DSL macros)
  # ============================================

  # Since DSL macros build tokens, we test the token construction
  # that the DSL would produce

  describe "DSL field macro equivalents" do
    test "field adds field to token" do
      # DSL: field :email, :citext, unique: true
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :citext, unique: true)

      assert Token.has_field?(token, :email)
      {:email, :citext, opts} = Token.get_field(token, :email)
      assert opts[:unique] == true
    end

    test "fields adds multiple fields" do
      # DSL: fields [...]
      fields = [
        {:name, :string, [null: false]},
        {:email, :citext, [unique: true]}
      ]

      token =
        Token.new(:table, :users)
        |> Token.add_fields(fields)

      assert Token.has_field?(token, :name)
      assert Token.has_field?(token, :email)
    end
  end

  describe "DSL uuid_primary_key equivalent" do
    test "adds uuid primary key and disables auto pk" do
      # DSL: uuid_primary_key()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_uuid_primary_key()

      assert token.options[:primary_key] == false
      assert Token.has_field?(token, :id)

      {:id, :binary_id, opts} = Token.get_field(token, :id)
      assert opts[:primary_key] == true
    end
  end

  describe "DSL has_authentication equivalent" do
    test "adds password auth fields" do
      # DSL: has_authentication()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_authentication()

      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :confirmed_at)
      assert Token.has_field?(token, :confirmation_token)
    end

    test "adds oauth auth fields" do
      # DSL: has_authentication(type: :oauth)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_authentication(type: :oauth)

      assert Token.has_field?(token, :provider)
      assert Token.has_field?(token, :provider_id)
    end

    test "adds magic link auth fields" do
      # DSL: has_authentication(type: :magic_link)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_authentication(type: :magic_link)

      assert Token.has_field?(token, :magic_token)
      assert Token.has_field?(token, :magic_token_sent_at)
    end
  end

  describe "DSL has_profile equivalent" do
    test "adds bio profile field" do
      # DSL: has_profile(:bio)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_profile(:bio)

      assert Token.has_field?(token, :bio)
    end

    test "adds avatar profile fields" do
      # DSL: has_profile(:avatar)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_profile(:avatar)

      assert Token.has_field?(token, :avatar_url)
      assert Token.has_field?(token, :avatar_thumbnail_url)
    end

    test "adds multiple profile fields" do
      # DSL: has_profile([:bio, :avatar])
      token =
        Token.new(:table, :users)
        |> Pipeline.with_profile([:bio, :avatar])

      assert Token.has_field?(token, :bio)
      assert Token.has_field?(token, :avatar_url)
    end
  end

  describe "DSL has_audit equivalent" do
    test "adds audit fields" do
      # DSL: has_audit()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_audit()

      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :updated_by_urm_id)
    end

    test "adds audit fields with user tracking" do
      # DSL: has_audit(track_user: true)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_audit(track_user: true)

      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :created_by_user_id)
    end
  end

  describe "DSL has_soft_delete equivalent" do
    test "adds soft delete fields" do
      # DSL: has_soft_delete()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_soft_delete()

      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deleted_by_urm_id)
    end

    test "adds soft delete with reason tracking" do
      # DSL: has_soft_delete(track_reason: true)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_soft_delete(track_reason: true)

      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deletion_reason)
    end
  end

  describe "DSL timestamps equivalent" do
    test "adds timestamp fields" do
      # DSL: timestamps()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_timestamps()

      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)
    end
  end

  describe "DSL has_metadata equivalent" do
    test "adds metadata field" do
      # DSL: has_metadata()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_metadata()

      assert Token.has_field?(token, :metadata)
      {:metadata, :jsonb, _opts} = Token.get_field(token, :metadata)
    end

    test "adds metadata field with custom name" do
      # DSL: has_metadata(name: :properties)
      token =
        Token.new(:table, :users)
        |> Pipeline.with_metadata(name: :properties)

      assert Token.has_field?(token, :properties)
    end
  end

  describe "DSL has_tags equivalent" do
    test "adds tags field" do
      # DSL: has_tags()
      token =
        Token.new(:table, :posts)
        |> Pipeline.with_tags()

      assert Token.has_field?(token, :tags)
      {:tags, {:array, :string}, _opts} = Token.get_field(token, :tags)
    end
  end

  describe "DSL has_settings equivalent" do
    test "adds settings field" do
      # DSL: has_settings()
      token =
        Token.new(:table, :users)
        |> Pipeline.with_settings()

      assert Token.has_field?(token, :settings)
    end
  end

  describe "DSL has_status equivalent" do
    test "adds status field with constraint" do
      # DSL: has_status()
      token =
        Token.new(:table, :orders)
        |> Pipeline.with_status()

      assert Token.has_field?(token, :status)
      assert Token.has_constraint?(token, :status_check)
    end

    test "adds status field with custom values" do
      # DSL: has_status(values: ["pending", "shipped"])
      token =
        Token.new(:table, :orders)
        |> Pipeline.with_status(values: ["pending", "shipped"], default: "pending")

      {:status, :string, opts} = Token.get_field(token, :status)
      assert opts[:default] == "pending"
    end
  end

  describe "DSL has_money equivalent" do
    test "adds money field" do
      # DSL: has_money(:amount)
      token =
        Token.new(:table, :invoices)
        |> Pipeline.with_money(:amount)

      assert Token.has_field?(token, :amount)
      {:amount, :decimal, opts} = Token.get_field(token, :amount)
      assert opts[:precision] == 10
      assert opts[:scale] == 2
    end

    test "adds multiple money fields" do
      # DSL: has_money([:subtotal, :tax, :total])
      token =
        Token.new(:table, :invoices)
        |> Pipeline.with_money([:subtotal, :tax, :total])

      assert Token.has_field?(token, :subtotal)
      assert Token.has_field?(token, :tax)
      assert Token.has_field?(token, :total)
    end
  end

  describe "DSL index equivalent" do
    test "adds index to token" do
      # DSL: index [:email], unique: true
      table_name = :users
      columns = [:email]
      index_name = Helpers.index_name(table_name, columns)

      token =
        Token.new(:table, table_name)
        |> Token.add_field(:email, :string)
        |> Token.add_index(index_name, columns, unique: true)

      assert Token.has_index?(token, :users_email_index)
    end
  end

  describe "DSL unique_index equivalent" do
    test "adds unique index" do
      # DSL: unique_index [:email]
      table_name = :users
      columns = [:email]
      index_name = Helpers.unique_index_name(table_name, columns)

      token =
        Token.new(:table, table_name)
        |> Token.add_field(:email, :string)
        |> Token.add_index(index_name, columns, unique: true)

      # unique_index_name generates :users_email_unique (not _index suffix)
      assert Token.has_index?(token, :users_email_unique)

      {^index_name, ^columns, opts} = Token.get_index(token, index_name)
      assert opts[:unique] == true
    end
  end

  describe "DSL constraint equivalent" do
    test "adds constraint to token" do
      # DSL: constraint :age_positive, :check, check: "age > 0"
      token =
        Token.new(:table, :users)
        |> Token.add_field(:age, :integer)
        |> Token.add_constraint(:age_positive, :check, check: "age > 0")

      assert Token.has_constraint?(token, :age_positive)
    end
  end

  describe "DSL check_constraint equivalent" do
    test "adds check constraint" do
      # DSL: check_constraint :email_format, "email LIKE '%@%'"
      token =
        Token.new(:table, :users)
        |> Token.add_field(:email, :string)
        |> Token.add_constraint(:email_format, :check, check: "email LIKE '%@%'")

      assert Token.has_constraint?(token, :email_format)
    end
  end

  describe "DSL belongs_to equivalent" do
    test "adds foreign key field and index" do
      # DSL: belongs_to :user, :users
      field_name = :user_id
      table_name = :posts
      ref_table = :users

      token =
        Token.new(:table, table_name)
        |> Token.add_field(field_name, {:references, ref_table, [type: :binary_id]}, [])
        |> Token.add_index(:"#{table_name}_#{field_name}_index", [field_name], [])

      assert Token.has_field?(token, :user_id)

      fks = Token.foreign_keys(token)
      assert length(fks) == 1

      assert Token.has_index?(token, :posts_user_id_index)
    end
  end

  # ============================================
  # Full Table Integration Tests
  # ============================================

  describe "complete table construction" do
    test "builds complete user table" do
      # Equivalent to DSL:
      # table :users do
      #   uuid_primary_key()
      #   field :email, :citext, unique: true
      #   field :username, :citext
      #   has_authentication()
      #   has_profile([:bio, :avatar])
      #   has_audit()
      #   has_soft_delete()
      #   timestamps()
      # end

      token =
        Token.new(:table, :users)
        |> Pipeline.with_uuid_primary_key()
        |> Token.add_field(:email, :citext, unique: true)
        |> Token.add_field(:username, :citext)
        |> Pipeline.with_authentication()
        |> Pipeline.with_profile([:bio, :avatar])
        |> Pipeline.with_audit()
        |> Pipeline.with_soft_delete()
        |> Pipeline.with_timestamps()

      # Verify all fields exist
      assert Token.has_field?(token, :id)
      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :username)
      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :bio)
      assert Token.has_field?(token, :avatar_url)
      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)

      # Verify token validates
      assert {:ok, _} = Token.validate(token)
    end

    test "builds complete product table" do
      # Equivalent to DSL:
      # table :products do
      #   uuid_primary_key()
      #   belongs_to :category, :categories
      #   field :name, :string, null: false
      #   field :price, :decimal
      #   has_status(values: ["draft", "active", "archived"])
      #   has_metadata()
      #   has_tags()
      #   timestamps()
      # end

      token =
        Token.new(:table, :products)
        |> Pipeline.with_uuid_primary_key()
        |> Token.add_field(:category_id, {:references, :categories, [type: :binary_id]}, [])
        |> Token.add_field(:name, :string, null: false)
        |> Pipeline.with_money(:price)
        |> Pipeline.with_status(values: ["draft", "active", "archived"])
        |> Pipeline.with_metadata()
        |> Pipeline.with_tags()
        |> Pipeline.with_timestamps()

      assert Token.has_field?(token, :id)
      assert Token.has_field?(token, :category_id)
      assert Token.has_field?(token, :name)
      assert Token.has_field?(token, :price)
      assert Token.has_field?(token, :status)
      assert Token.has_field?(token, :metadata)
      assert Token.has_field?(token, :tags)
      assert Token.has_field?(token, :inserted_at)

      # Verify foreign keys
      fks = Token.foreign_keys(token)
      assert length(fks) == 1

      # Verify constraints
      assert Token.has_constraint?(token, :status_check)

      # Verify token validates
      assert {:ok, _} = Token.validate(token)
    end
  end
end
