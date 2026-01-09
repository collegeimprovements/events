defmodule OmMigration.PipelineTest do
  @moduledoc """
  Tests for OmMigration.Pipeline - Composable migration patterns.

  Pipeline provides pre-built migration patterns that combine multiple fields,
  indexes, and constraints into reusable, domain-specific building blocks.

  ## Use Cases

  - **User tables**: Identity fields, authentication, profiles, soft deletes
  - **Business entities**: Money fields, status with constraints, metadata
  - **Content tables**: Tags, settings, slugs, full-text search
  - **Infrastructure**: UUID primary keys, timestamps, version tracking

  ## Pattern: Pipeline Composition

      Token.new(:table, :users)
      |> Pipeline.with_uuid_primary_key()
      |> Pipeline.with_identity([:email, :username])
      |> Pipeline.with_authentication()
      |> Pipeline.with_profile([:bio, :avatar])
      |> Pipeline.with_soft_delete()
      |> Pipeline.with_timestamps()

  Pipelines encapsulate common patterns, ensuring consistency across tables.
  """

  use ExUnit.Case, async: true

  alias OmMigration.{Token, Pipeline}

  # ============================================
  # Primary Key Pipelines
  # ============================================

  describe "with_uuid_primary_key/1" do
    test "adds uuid primary key and disables auto pk" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_uuid_primary_key()

      assert token.options[:primary_key] == false
      assert Token.has_field?(token, :id)

      {:id, type, opts} = Token.get_field(token, :id)
      assert type == :binary_id
      assert opts[:primary_key] == true
    end
  end

  describe "with_uuid_v4_primary_key/1" do
    test "adds uuid v4 primary key" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_uuid_v4_primary_key()

      assert token.options[:primary_key] == false
      assert Token.has_field?(token, :id)

      {:id, :binary_id, opts} = Token.get_field(token, :id)
      assert opts[:primary_key] == true
      assert opts[:default] == {:fragment, "uuid_generate_v4()"}
    end
  end

  # ============================================
  # Identity Pipelines
  # ============================================

  describe "with_identity/2" do
    test "adds email identity field" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_identity(:email)

      assert Token.has_field?(token, :email)
      {:email, :citext, opts} = Token.get_field(token, :email)
      assert opts[:null] == false
      assert Token.has_index?(token, :users_email_index)
    end

    test "adds username identity field" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_identity(:username)

      assert Token.has_field?(token, :username)
      {:username, :citext, opts} = Token.get_field(token, :username)
      assert opts[:null] == false
      assert Token.has_index?(token, :users_username_index)
    end

    test "adds phone identity field" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_identity(:phone)

      assert Token.has_field?(token, :phone)
      {:phone, :string, opts} = Token.get_field(token, :phone)
      assert opts[:null] == true
    end

    test "adds multiple identity fields from list" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_identity([:email, :phone])

      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :phone)
    end
  end

  # ============================================
  # Authentication Pipelines
  # ============================================

  describe "with_authentication/2" do
    test "adds password auth fields by default" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_authentication()

      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :confirmed_at)
      assert Token.has_field?(token, :confirmation_token)
      assert Token.has_field?(token, :reset_password_token)
      assert Token.has_field?(token, :failed_attempts)
      assert Token.has_field?(token, :locked_at)
      assert Token.has_index?(token, :users_confirmation_token_index)
      assert Token.has_index?(token, :users_reset_password_token_index)
    end

    test "adds oauth fields when type: :oauth" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_authentication(type: :oauth)

      assert Token.has_field?(token, :provider)
      assert Token.has_field?(token, :provider_id)
      assert Token.has_field?(token, :provider_token)
      assert Token.has_field?(token, :provider_refresh_token)
      assert Token.has_index?(token, :users_provider_index)
    end

    test "adds magic link fields when type: :magic_link" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_authentication(type: :magic_link)

      assert Token.has_field?(token, :magic_token)
      assert Token.has_field?(token, :magic_token_sent_at)
      assert Token.has_field?(token, :magic_token_expires_at)
      assert Token.has_index?(token, :users_magic_token_index)
    end
  end

  # ============================================
  # Profile Pipelines
  # ============================================

  describe "with_profile/2" do
    test "adds bio profile field" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_profile(:bio)

      assert Token.has_field?(token, :bio)
      {:bio, :text, _opts} = Token.get_field(token, :bio)
    end

    test "adds avatar profile fields" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_profile(:avatar)

      assert Token.has_field?(token, :avatar_url)
      assert Token.has_field?(token, :avatar_thumbnail_url)
    end

    test "adds multiple profile fields from list" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_profile([:bio, :avatar])

      assert Token.has_field?(token, :bio)
      assert Token.has_field?(token, :avatar_url)
    end
  end

  # ============================================
  # Business Pipelines
  # ============================================

  describe "with_money/2" do
    test "adds money field with decimal type" do
      token =
        Token.new(:table, :invoices)
        |> Pipeline.with_money(:amount)

      assert Token.has_field?(token, :amount)
      {:amount, :decimal, opts} = Token.get_field(token, :amount)
      assert opts[:precision] == 10
      assert opts[:scale] == 2
    end

    test "adds multiple money fields from list" do
      token =
        Token.new(:table, :invoices)
        |> Pipeline.with_money([:amount, :tax, :total])

      assert Token.has_field?(token, :amount)
      assert Token.has_field?(token, :tax)
      assert Token.has_field?(token, :total)
    end
  end

  describe "with_status/2" do
    test "adds status field with defaults" do
      token =
        Token.new(:table, :orders)
        |> Pipeline.with_status()

      assert Token.has_field?(token, :status)
      {:status, :string, opts} = Token.get_field(token, :status)
      assert opts[:null] == false
      assert opts[:default] == "draft"
      assert Token.has_constraint?(token, :status_check)
      assert Token.has_index?(token, :status_index)
    end

    test "adds status field with custom values" do
      token =
        Token.new(:table, :orders)
        |> Pipeline.with_status(values: ["pending", "shipped", "delivered"], default: "pending")

      {:status, :string, opts} = Token.get_field(token, :status)
      assert opts[:default] == "pending"
    end
  end

  # ============================================
  # Metadata Pipelines
  # ============================================

  describe "with_metadata/2" do
    test "adds metadata jsonb field" do
      token =
        Token.new(:table, :products)
        |> Pipeline.with_metadata()

      assert Token.has_field?(token, :metadata)
      {:metadata, :jsonb, opts} = Token.get_field(token, :metadata)
      assert opts[:default] == %{}
      assert opts[:null] == false
      assert Token.has_index?(token, :products_metadata_gin_index)
    end

    test "adds metadata field with custom name" do
      token =
        Token.new(:table, :products)
        |> Pipeline.with_metadata(name: :properties)

      assert Token.has_field?(token, :properties)
      assert Token.has_index?(token, :products_properties_gin_index)
    end
  end

  describe "with_tags/2" do
    test "adds tags array field" do
      token =
        Token.new(:table, :posts)
        |> Pipeline.with_tags()

      assert Token.has_field?(token, :tags)
      {:tags, {:array, :string}, opts} = Token.get_field(token, :tags)
      assert opts[:default] == []
      assert opts[:null] == false
      assert Token.has_index?(token, :posts_tags_gin_index)
    end

    test "adds tags field with custom name" do
      token =
        Token.new(:table, :posts)
        |> Pipeline.with_tags(name: :categories)

      assert Token.has_field?(token, :categories)
    end
  end

  describe "with_settings/2" do
    test "adds settings jsonb field (alias for metadata)" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_settings()

      assert Token.has_field?(token, :settings)
      {:settings, :jsonb, _opts} = Token.get_field(token, :settings)
    end
  end

  # ============================================
  # Soft Delete Pipelines
  # ============================================

  describe "with_soft_delete/2" do
    test "adds soft delete fields with defaults" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_soft_delete()

      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deleted_by_urm_id)
      assert Token.has_index?(token, :deleted_at_index)
      assert Token.has_index?(token, :active_records_index)
    end

    test "adds soft delete without urm tracking" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_soft_delete(track_urm: false)

      assert Token.has_field?(token, :deleted_at)
      refute Token.has_field?(token, :deleted_by_urm_id)
    end

    test "adds soft delete with user tracking" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_soft_delete(track_user: true)

      assert Token.has_field?(token, :deleted_by_user_id)
    end

    test "adds soft delete with reason tracking" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_soft_delete(track_reason: true)

      assert Token.has_field?(token, :deletion_reason)
    end
  end

  # ============================================
  # Index Pipelines
  # ============================================

  describe "unique/1" do
    test "makes index unique" do
      token =
        Token.new(:index, :users, columns: [:email])
        |> Pipeline.unique()

      assert token.options[:unique] == true
    end
  end

  describe "where/2" do
    test "adds where clause to index" do
      token =
        Token.new(:index, :users, columns: [:email])
        |> Pipeline.where("deleted_at IS NULL")

      assert token.options[:where] == "deleted_at IS NULL"
    end
  end

  describe "using/2" do
    test "sets index method" do
      token =
        Token.new(:index, :products, columns: [:tags])
        |> Pipeline.using(:gin)

      assert token.options[:using] == :gin
    end
  end

  # ============================================
  # Composition Helpers
  # ============================================

  describe "maybe/3" do
    test "applies function when condition is truthy" do
      token =
        Token.new(:table, :users)
        |> Pipeline.maybe(&Pipeline.with_soft_delete/1, true)

      assert Token.has_field?(token, :deleted_at)
    end

    test "does not apply function when condition is false" do
      token =
        Token.new(:table, :users)
        |> Pipeline.maybe(&Pipeline.with_soft_delete/1, false)

      refute Token.has_field?(token, :deleted_at)
    end

    test "does not apply function when condition is nil" do
      token =
        Token.new(:table, :users)
        |> Pipeline.maybe(&Pipeline.with_soft_delete/1, nil)

      refute Token.has_field?(token, :deleted_at)
    end
  end

  describe "validate!/1" do
    test "returns token when valid" do
      token =
        Token.new(:table, :users)
        |> Token.add_field(:name, :string)

      assert Pipeline.validate!(token) == token
    end

    test "raises when invalid" do
      token = Token.new(:table, :users)

      assert_raise ArgumentError, fn ->
        Pipeline.validate!(token)
      end
    end
  end

  # ============================================
  # Full Pipeline Integration
  # ============================================

  describe "full pipeline composition" do
    test "builds complete user table" do
      token =
        Token.new(:table, :users)
        |> Pipeline.with_uuid_primary_key()
        |> Pipeline.with_identity([:email, :username])
        |> Pipeline.with_authentication()
        |> Pipeline.with_profile([:bio, :avatar])
        |> Pipeline.with_soft_delete()
        |> Pipeline.with_timestamps()

      # Check primary key
      assert Token.has_field?(token, :id)

      # Check identity fields
      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :username)

      # Check auth fields
      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :confirmed_at)

      # Check profile fields
      assert Token.has_field?(token, :bio)
      assert Token.has_field?(token, :avatar_url)

      # Check soft delete
      assert Token.has_field?(token, :deleted_at)

      # Check timestamps
      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)

      # Validate the token
      assert {:ok, _} = Token.validate(token)
    end

    test "builds invoice table with money fields" do
      token =
        Token.new(:table, :invoices)
        |> Pipeline.with_uuid_primary_key()
        |> Pipeline.with_money([:subtotal, :tax, :total])
        |> Pipeline.with_status(values: ["draft", "sent", "paid", "cancelled"])
        |> Pipeline.with_metadata()
        |> Pipeline.with_timestamps()

      assert Token.has_field?(token, :subtotal)
      assert Token.has_field?(token, :tax)
      assert Token.has_field?(token, :total)
      assert Token.has_field?(token, :status)
      assert Token.has_field?(token, :metadata)
      assert Token.has_constraint?(token, :status_check)
    end
  end
end
