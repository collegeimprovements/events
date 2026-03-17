defmodule OmMigration.FieldBuildersTest do
  @moduledoc """
  Tests for OmMigration.FieldBuilders - Behavior-based field generation.

  FieldBuilders provide consistent, testable field generation following
  the FieldBuilder behaviour pattern.
  """

  use ExUnit.Case, async: true

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  alias OmMigration.FieldBuilders.{
    AuditFields,
    SoftDelete,
    TypeFields,
    StatusFields,
    Timestamps,
    Identity,
    Authentication,
    Profile,
    Money,
    Metadata,
    Tags
  }

  # ============================================
  # FieldBuilder Behaviour Tests
  # ============================================

  describe "FieldBuilder.merge_config/2" do
    test "merges user options with defaults" do
      defaults = %{type: :string, null: true, fields: [:a, :b, :c]}
      config = FieldBuilder.merge_config(defaults, type: :citext, null: false)

      assert config.type == :citext
      assert config.null == false
      assert config.fields == [:a, :b, :c]
    end

    test "applies :only filter to fields" do
      defaults = %{type: :string, fields: [:a, :b, :c, :d]}
      config = FieldBuilder.merge_config(defaults, only: [:a, :c])

      assert config.fields == [:a, :c]
    end

    test "applies :except filter to fields" do
      defaults = %{type: :string, fields: [:a, :b, :c, :d]}
      config = FieldBuilder.merge_config(defaults, except: [:b, :d])

      assert config.fields == [:a, :c]
    end
  end

  describe "FieldBuilder.filter_fields/2" do
    test "returns all fields when no filter" do
      fields = FieldBuilder.filter_fields([:a, :b, :c], [])
      assert fields == [:a, :b, :c]
    end

    test "filters by :only" do
      fields = FieldBuilder.filter_fields([:a, :b, :c], only: [:a, :b])
      assert fields == [:a, :b]
    end

    test "filters by :except" do
      fields = FieldBuilder.filter_fields([:a, :b, :c], except: [:c])
      assert fields == [:a, :b]
    end

    test "raises when no fields selected" do
      assert_raise ArgumentError, ~r/No fields selected/, fn ->
        FieldBuilder.filter_fields([:a, :b], only: [:x, :y])
      end
    end
  end

  describe "FieldBuilder.apply/3" do
    test "applies builder module to token" do
      token =
        Token.new(:table, :users)
        |> FieldBuilder.apply(SoftDelete, [])

      assert Token.has_field?(token, :deleted_at)
    end

    test "passes options to builder" do
      token =
        Token.new(:table, :users)
        |> FieldBuilder.apply(SoftDelete, track_user: true)

      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deleted_by_user_id)
    end

    test "adds indexes from builder" do
      token =
        Token.new(:table, :users)
        |> FieldBuilder.apply(SoftDelete, [])

      assert Token.has_index?(token, :deleted_at_index)
      assert Token.has_index?(token, :active_records_index)
    end
  end

  # ============================================
  # AuditFields Tests
  # ============================================

  describe "AuditFields" do
    test "default_config returns expected structure" do
      config = AuditFields.default_config()

      assert is_map(config)
      assert config.track_user == false
      assert config.track_ip == false
      assert config.track_session == false
      assert config.track_changes == false
      assert is_list(config.fields)
    end

    test "adds base audit fields" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add()

      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :updated_by_urm_id)
    end

    test "adds user tracking when enabled" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add(track_user: true)

      assert Token.has_field?(token, :created_by_user_id)
      assert Token.has_field?(token, :updated_by_user_id)
    end

    test "does not add user tracking when disabled" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add(track_user: false)

      refute Token.has_field?(token, :created_by_user_id)
      refute Token.has_field?(token, :updated_by_user_id)
    end

    test "adds IP tracking when enabled" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add(track_ip: true)

      assert Token.has_field?(token, :created_from_ip)
      assert Token.has_field?(token, :updated_from_ip)
    end

    test "adds session tracking when enabled" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add(track_session: true)

      assert Token.has_field?(token, :created_session_id)
      assert Token.has_field?(token, :updated_session_id)
    end

    test "adds change tracking when enabled" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add(track_changes: true)

      assert Token.has_field?(token, :change_history)
      assert Token.has_field?(token, :version)

      {:change_history, :jsonb, opts} = Token.get_field(token, :change_history)
      assert opts[:default] == []
      assert opts[:null] == false
    end

    test "adds user indexes when user tracking enabled" do
      token =
        Token.new(:table, :documents)
        |> AuditFields.add(track_user: true)

      assert Token.has_index?(token, :created_by_user_index)
      assert Token.has_index?(token, :updated_by_user_index)
    end
  end

  # ============================================
  # SoftDelete Tests
  # ============================================

  describe "SoftDelete" do
    test "default_config returns expected structure" do
      config = SoftDelete.default_config()

      assert config.track_urm == true
      assert config.track_user == false
      assert config.track_reason == false
    end

    test "adds deleted_at field" do
      token =
        Token.new(:table, :users)
        |> SoftDelete.add()

      assert Token.has_field?(token, :deleted_at)

      {:deleted_at, :utc_datetime_usec, opts} = Token.get_field(token, :deleted_at)
      assert opts[:null] == true
    end

    test "adds URM tracking by default" do
      token =
        Token.new(:table, :users)
        |> SoftDelete.add()

      assert Token.has_field?(token, :deleted_by_urm_id)
    end

    test "skips URM tracking when disabled" do
      token =
        Token.new(:table, :users)
        |> SoftDelete.add(track_urm: false)

      assert Token.has_field?(token, :deleted_at)
      refute Token.has_field?(token, :deleted_by_urm_id)
    end

    test "adds user tracking when enabled" do
      token =
        Token.new(:table, :users)
        |> SoftDelete.add(track_user: true)

      assert Token.has_field?(token, :deleted_by_user_id)
    end

    test "adds deletion reason when enabled" do
      token =
        Token.new(:table, :users)
        |> SoftDelete.add(track_reason: true)

      assert Token.has_field?(token, :deletion_reason)

      {:deletion_reason, :text, _opts} = Token.get_field(token, :deletion_reason)
    end

    test "adds soft delete indexes" do
      token =
        Token.new(:table, :users)
        |> SoftDelete.add()

      assert Token.has_index?(token, :deleted_at_index)
      assert Token.has_index?(token, :active_records_index)

      # Check active records index has partial where clause
      {:active_records_index, [:id], opts} = Token.get_index(token, :active_records_index)
      assert opts[:where] == "deleted_at IS NULL"
    end
  end

  # ============================================
  # TypeFields Tests
  # ============================================

  describe "TypeFields" do
    test "default_config returns expected structure" do
      config = TypeFields.default_config()

      assert is_map(config)
      assert is_list(config.fields)
      assert :type in config.fields
    end

    test "adds type classification fields" do
      token =
        Token.new(:table, :products)
        |> TypeFields.add()

      assert Token.has_field?(token, :type)
      assert Token.has_field?(token, :subtype)
    end

    test "respects :only option" do
      token =
        Token.new(:table, :products)
        |> TypeFields.add(only: [:type])

      assert Token.has_field?(token, :type)
      refute Token.has_field?(token, :subtype)
    end

    test "respects :except option" do
      token =
        Token.new(:table, :products)
        |> TypeFields.add(except: [:subtype, :kind, :category, :variant])

      assert Token.has_field?(token, :type)
      refute Token.has_field?(token, :subtype)
    end
  end

  # ============================================
  # StatusFields Tests
  # ============================================

  describe "StatusFields" do
    test "default_config returns expected structure" do
      config = StatusFields.default_config()

      assert is_map(config)
      assert is_list(config.fields)
      assert :status in config.fields
    end

    test "adds status fields" do
      token =
        Token.new(:table, :orders)
        |> StatusFields.add()

      assert Token.has_field?(token, :status)
    end

    test "respects :only option" do
      token =
        Token.new(:table, :orders)
        |> StatusFields.add(only: [:status])

      assert Token.has_field?(token, :status)
      refute Token.has_field?(token, :substatus)
    end
  end

  # ============================================
  # Timestamps Tests
  # ============================================

  describe "Timestamps" do
    test "default_config returns expected structure" do
      config = Timestamps.default_config()

      assert is_map(config)
      assert config.type == :utc_datetime_usec
    end

    test "adds timestamp fields" do
      token =
        Token.new(:table, :users)
        |> Timestamps.add()

      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)
    end

    test "uses correct timestamp type" do
      token =
        Token.new(:table, :users)
        |> Timestamps.add()

      {:inserted_at, type, _opts} = Token.get_field(token, :inserted_at)
      assert type == :utc_datetime_usec
    end
  end

  # ============================================
  # Identity Tests
  # ============================================

  describe "Identity" do
    test "default_config returns expected structure" do
      config = Identity.default_config()

      assert is_map(config)
      assert is_list(config.fields)
      assert :email in config.fields
      assert :username in config.fields
    end

    test "adds all identity fields by default" do
      token =
        Token.new(:table, :users)
        |> Identity.add()

      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :username)
      assert Token.has_field?(token, :phone)
      assert Token.has_field?(token, :first_name)
    end

    test "respects :only option" do
      token =
        Token.new(:table, :users)
        |> Identity.add(only: [:email, :username])

      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :username)
      refute Token.has_field?(token, :phone)
      refute Token.has_field?(token, :first_name)
    end

    test "adds unique indexes for email and username" do
      token =
        Token.new(:table, :users)
        |> Identity.add(only: [:email, :username])

      assert Token.has_index?(token, :email_unique_index)
      assert Token.has_index?(token, :username_unique_index)
    end
  end

  # ============================================
  # Authentication Tests
  # ============================================

  describe "Authentication" do
    test "default_config returns expected structure" do
      config = Authentication.default_config()

      assert config.type == :password
      assert config.with_lockout == true
      assert config.with_confirmation == true
    end

    test "adds password auth fields by default" do
      token =
        Token.new(:table, :users)
        |> Authentication.add()

      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :confirmed_at)
      assert Token.has_field?(token, :confirmation_token)
      assert Token.has_field?(token, :failed_attempts)
      assert Token.has_field?(token, :locked_at)
    end

    test "adds oauth fields when type: :oauth" do
      token =
        Token.new(:table, :users)
        |> Authentication.add(type: :oauth)

      assert Token.has_field?(token, :provider)
      assert Token.has_field?(token, :provider_id)
      assert Token.has_field?(token, :provider_token)
      refute Token.has_field?(token, :password_hash)
    end

    test "adds magic link fields when type: :magic_link" do
      token =
        Token.new(:table, :users)
        |> Authentication.add(type: :magic_link)

      assert Token.has_field?(token, :magic_token)
      assert Token.has_field?(token, :magic_token_sent_at)
      assert Token.has_field?(token, :magic_token_expires_at)
      refute Token.has_field?(token, :password_hash)
    end

    test "skips lockout fields when disabled" do
      token =
        Token.new(:table, :users)
        |> Authentication.add(with_lockout: false)

      assert Token.has_field?(token, :password_hash)
      refute Token.has_field?(token, :failed_attempts)
      refute Token.has_field?(token, :locked_at)
    end
  end

  # ============================================
  # Profile Tests
  # ============================================

  describe "Profile" do
    test "default_config returns expected structure" do
      config = Profile.default_config()

      assert is_map(config)
      assert is_list(config.fields)
      assert :bio in config.fields
      assert :avatar in config.fields
    end

    test "adds bio field" do
      token =
        Token.new(:table, :users)
        |> Profile.add(only: [:bio])

      assert Token.has_field?(token, :bio)
      {:bio, :text, _opts} = Token.get_field(token, :bio)
    end

    test "adds avatar fields" do
      token =
        Token.new(:table, :users)
        |> Profile.add(only: [:avatar])

      assert Token.has_field?(token, :avatar_url)
      assert Token.has_field?(token, :avatar_thumbnail_url)
    end

    test "adds location fields" do
      token =
        Token.new(:table, :users)
        |> Profile.add(only: [:location])

      assert Token.has_field?(token, :street_address)
      assert Token.has_field?(token, :city)
      assert Token.has_field?(token, :latitude)
      assert Token.has_field?(token, :longitude)
    end

    test "adds social fields" do
      token =
        Token.new(:table, :users)
        |> Profile.add(only: [:social])

      assert Token.has_field?(token, :website_url)
      assert Token.has_field?(token, :twitter_handle)
      assert Token.has_field?(token, :github_username)
    end
  end

  # ============================================
  # Money Tests
  # ============================================

  describe "Money" do
    test "default_config returns expected structure" do
      config = Money.default_config()

      assert config.fields == [:amount]
      assert config.precision == 10
      assert config.scale == 2
    end

    test "adds money field with default precision" do
      token =
        Token.new(:table, :invoices)
        |> Money.add()

      assert Token.has_field?(token, :amount)

      {:amount, :decimal, opts} = Token.get_field(token, :amount)
      assert opts[:precision] == 10
      assert opts[:scale] == 2
    end

    test "adds multiple money fields" do
      token =
        Token.new(:table, :invoices)
        |> Money.add(fields: [:subtotal, :tax, :total])

      assert Token.has_field?(token, :subtotal)
      assert Token.has_field?(token, :tax)
      assert Token.has_field?(token, :total)
    end

    test "adds currency field when enabled" do
      token =
        Token.new(:table, :invoices)
        |> Money.add(currency_field: true)

      assert Token.has_field?(token, :amount)
      assert Token.has_field?(token, :currency)
    end
  end

  # ============================================
  # Metadata Tests
  # ============================================

  describe "Metadata" do
    test "default_config returns expected structure" do
      config = Metadata.default_config()

      assert config.name == :metadata
      assert config.default == %{}
      assert config.nullable == false
    end

    test "adds metadata jsonb field" do
      token =
        Token.new(:table, :products)
        |> Metadata.add()

      assert Token.has_field?(token, :metadata)

      {:metadata, :jsonb, opts} = Token.get_field(token, :metadata)
      assert opts[:default] == %{}
      assert opts[:null] == false
    end

    test "adds custom named metadata field" do
      token =
        Token.new(:table, :products)
        |> Metadata.add(name: :properties)

      assert Token.has_field?(token, :properties)
      refute Token.has_field?(token, :metadata)
    end

    test "adds GIN index for metadata" do
      token =
        Token.new(:table, :products)
        |> Metadata.add()

      assert Token.has_index?(token, :metadata_gin_index)
    end
  end

  # ============================================
  # Tags Tests
  # ============================================

  describe "Tags" do
    test "default_config returns expected structure" do
      config = Tags.default_config()

      assert config.name == :tags
      assert config.default == []
      assert config.nullable == false
    end

    test "adds tags array field" do
      token =
        Token.new(:table, :posts)
        |> Tags.add()

      assert Token.has_field?(token, :tags)

      {:tags, {:array, :string}, opts} = Token.get_field(token, :tags)
      assert opts[:default] == []
      assert opts[:null] == false
    end

    test "adds custom named tags field" do
      token =
        Token.new(:table, :posts)
        |> Tags.add(name: :categories)

      assert Token.has_field?(token, :categories)
      refute Token.has_field?(token, :tags)
    end

    test "adds GIN index for tags" do
      token =
        Token.new(:table, :posts)
        |> Tags.add()

      assert Token.has_index?(token, :tags_gin_index)
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "composing multiple builders" do
    test "builds complete table with all builders" do
      token =
        Token.new(:table, :documents)
        |> TypeFields.add(only: [:type])
        |> StatusFields.add(only: [:status])
        |> AuditFields.add(track_user: true)
        |> SoftDelete.add(track_reason: true)
        |> Timestamps.add()

      # Type fields
      assert Token.has_field?(token, :type)

      # Status fields
      assert Token.has_field?(token, :status)

      # Audit fields
      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :updated_by_urm_id)
      assert Token.has_field?(token, :created_by_user_id)

      # Soft delete fields
      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deletion_reason)

      # Timestamps
      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)

      # Verify token is valid
      assert {:ok, _} = Token.validate(token)
    end

    test "builds complete user table with new builders" do
      token =
        Token.new(:table, :users)
        |> Identity.add(only: [:email, :username])
        |> Authentication.add()
        |> Profile.add(only: [:bio, :avatar])
        |> Metadata.add(name: :settings)
        |> Tags.add(name: :roles)
        |> Timestamps.add()

      # Identity
      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :username)

      # Authentication
      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :confirmed_at)

      # Profile
      assert Token.has_field?(token, :bio)
      assert Token.has_field?(token, :avatar_url)

      # Metadata
      assert Token.has_field?(token, :settings)

      # Tags
      assert Token.has_field?(token, :roles)

      # Timestamps
      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)

      # Verify token is valid
      assert {:ok, _} = Token.validate(token)
    end
  end
end
