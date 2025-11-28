defmodule Events.Migration.PipelineTest do
  use Events.TestCase, async: true

  alias Events.Migration.Pipeline
  alias Events.Migration.Token

  # Helper to create a table token
  defp create_table(name, opts \\ []) do
    Token.new(:table, name, opts)
  end

  describe "Primary Key Pipelines" do
    test "with_uuid_primary_key/1 adds UUIDv7 primary key" do
      token =
        create_table(:users)
        |> Pipeline.with_uuid_primary_key()

      assert Token.has_field?(token, :id)
      {:id, type, opts} = Token.get_field(token, :id)
      assert type == :binary_id
      assert opts[:primary_key] == true
      assert opts[:default] == {:fragment, "uuidv7()"}
    end

    test "with_uuid_primary_key/2 with custom name" do
      token =
        create_table(:users)
        |> Pipeline.with_uuid_primary_key(name: :uuid)

      assert Token.has_field?(token, :uuid)
      refute Token.has_field?(token, :id)
    end

    test "with_uuid_primary_key/2 with uuidv4 type" do
      token =
        create_table(:users)
        |> Pipeline.with_uuid_primary_key(type: :uuidv4)

      {:id, _type, opts} = Token.get_field(token, :id)
      assert opts[:default] == {:fragment, "uuid_generate_v4()"}
    end

    test "with_uuid_v4_primary_key/1 adds legacy UUID v4 primary key" do
      token =
        create_table(:users)
        |> Pipeline.with_uuid_v4_primary_key()

      assert Token.has_field?(token, :id)
      {:id, type, opts} = Token.get_field(token, :id)
      assert type == :binary_id
      assert opts[:default] == {:fragment, "uuid_generate_v4()"}
    end
  end

  describe "Identity Pipelines" do
    test "with_identity/2 adds single identity field" do
      token =
        create_table(:users)
        |> Pipeline.with_identity(:email)

      assert Token.has_field?(token, :email)
      assert Token.has_index?(token, :users_email_index)
    end

    test "with_identity/2 with :name adds name fields" do
      token =
        create_table(:users)
        |> Pipeline.with_identity(:name)

      # Name fields come from Fields.name_fields()
      assert Token.has_field?(token, :first_name) or Token.has_field?(token, :name)
    end

    test "with_identity/2 with :phone adds phone field" do
      token =
        create_table(:users)
        |> Pipeline.with_identity(:phone)

      assert Token.has_field?(token, :phone)
    end

    test "with_identity/2 with :username adds username field with unique index" do
      token =
        create_table(:users)
        |> Pipeline.with_identity(:username)

      assert Token.has_field?(token, :username)
      assert Token.has_index?(token, :users_username_index)
    end

    test "with_identity/2 with list adds multiple identity fields" do
      token =
        create_table(:users)
        |> Pipeline.with_identity([:email, :phone])

      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :phone)
    end
  end

  describe "Authentication Pipelines" do
    test "with_authentication/1 adds password auth fields by default" do
      token =
        create_table(:users)
        |> Pipeline.with_authentication()

      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :confirmed_at)
      assert Token.has_field?(token, :confirmation_token)
      assert Token.has_field?(token, :reset_password_token)
      assert Token.has_field?(token, :failed_attempts)
      assert Token.has_field?(token, :locked_at)
    end

    test "with_authentication/2 with :oauth type adds OAuth fields" do
      token =
        create_table(:users)
        |> Pipeline.with_authentication(type: :oauth)

      assert Token.has_field?(token, :provider)
      assert Token.has_field?(token, :provider_id)
      assert Token.has_field?(token, :provider_token)
      assert Token.has_field?(token, :provider_refresh_token)
      assert Token.has_index?(token, :users_provider_index)
    end

    test "with_authentication/2 with :magic_link type adds magic link fields" do
      token =
        create_table(:users)
        |> Pipeline.with_authentication(type: :magic_link)

      assert Token.has_field?(token, :magic_token)
      assert Token.has_field?(token, :magic_token_sent_at)
      assert Token.has_field?(token, :magic_token_expires_at)
      assert Token.has_index?(token, :users_magic_token_index)
    end
  end

  describe "Profile Pipelines" do
    test "with_profile/2 adds bio field" do
      token =
        create_table(:users)
        |> Pipeline.with_profile(:bio)

      assert Token.has_field?(token, :bio)
    end

    test "with_profile/2 adds avatar fields" do
      token =
        create_table(:users)
        |> Pipeline.with_profile(:avatar)

      assert Token.has_field?(token, :avatar_url)
      assert Token.has_field?(token, :avatar_thumbnail_url)
    end

    test "with_profile/2 with list adds multiple profile fields" do
      token =
        create_table(:users)
        |> Pipeline.with_profile([:bio, :avatar])

      assert Token.has_field?(token, :bio)
      assert Token.has_field?(token, :avatar_url)
    end
  end

  describe "Business Pipelines" do
    test "with_money/2 adds single money field" do
      token =
        create_table(:invoices)
        |> Pipeline.with_money(:amount)

      assert Token.has_field?(token, :amount)
      {:amount, :decimal, opts} = Token.get_field(token, :amount)
      assert opts[:precision] == 10
      assert opts[:scale] == 2
    end

    test "with_money/2 adds multiple money fields" do
      token =
        create_table(:invoices)
        |> Pipeline.with_money([:subtotal, :tax, :total])

      assert Token.has_field?(token, :subtotal)
      assert Token.has_field?(token, :tax)
      assert Token.has_field?(token, :total)
    end

    test "with_status/1 adds status field with default" do
      token =
        create_table(:orders)
        |> Pipeline.with_status()

      assert Token.has_field?(token, :status)
      {:status, :string, opts} = Token.get_field(token, :status)
      assert opts[:default] == "draft"
      assert opts[:null] == false
    end

    test "with_status/2 with custom values and default" do
      token =
        create_table(:orders)
        |> Pipeline.with_status(values: ["pending", "shipped"], default: "pending")

      {:status, :string, opts} = Token.get_field(token, :status)
      assert opts[:default] == "pending"
    end
  end

  describe "Metadata Pipelines" do
    test "with_metadata/1 adds JSONB metadata field" do
      token =
        create_table(:products)
        |> Pipeline.with_metadata()

      assert Token.has_field?(token, :metadata)
      {:metadata, :jsonb, opts} = Token.get_field(token, :metadata)
      assert opts[:default] == %{}
      assert opts[:null] == false
    end

    test "with_metadata/2 with custom name" do
      token =
        create_table(:products)
        |> Pipeline.with_metadata(name: :properties)

      assert Token.has_field?(token, :properties)
      refute Token.has_field?(token, :metadata)
    end

    test "with_tags/1 adds tags array field" do
      token =
        create_table(:articles)
        |> Pipeline.with_tags()

      assert Token.has_field?(token, :tags)
      {:tags, {:array, :string}, opts} = Token.get_field(token, :tags)
      assert opts[:default] == []
    end

    test "with_settings/1 adds settings JSONB field" do
      token =
        create_table(:users)
        |> Pipeline.with_settings()

      assert Token.has_field?(token, :settings)
    end
  end

  describe "Soft Delete Pipeline" do
    test "with_soft_delete/1 adds soft delete fields" do
      token =
        create_table(:users)
        |> Pipeline.with_soft_delete()

      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deleted_by_urm_id)
      assert Token.has_index?(token, :deleted_at_index)
      assert Token.has_index?(token, :active_records_index)
    end

    test "with_soft_delete/2 with track_urm: false" do
      token =
        create_table(:users)
        |> Pipeline.with_soft_delete(track_urm: false)

      assert Token.has_field?(token, :deleted_at)
      refute Token.has_field?(token, :deleted_by_urm_id)
    end

    test "with_soft_delete/2 with track_user: true" do
      token =
        create_table(:users)
        |> Pipeline.with_soft_delete(track_user: true)

      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :deleted_by_user_id)
    end

    test "with_soft_delete/2 with track_reason: true" do
      token =
        create_table(:users)
        |> Pipeline.with_soft_delete(track_reason: true)

      assert Token.has_field?(token, :deletion_reason)
    end
  end

  describe "Index Pipelines" do
    test "unique/1 makes index unique" do
      token =
        Token.new(:index, :users_email_index, columns: [:email])
        |> Pipeline.unique()

      assert token.options[:unique] == true
    end

    test "where/2 adds WHERE clause to index" do
      token =
        Token.new(:index, :active_users_index, columns: [:id])
        |> Pipeline.where("deleted_at IS NULL")

      assert token.options[:where] == "deleted_at IS NULL"
    end

    test "using/2 sets index method" do
      token =
        Token.new(:index, :tags_index, columns: [:tags])
        |> Pipeline.using(:gin)

      assert token.options[:using] == :gin
    end
  end

  describe "Composition Helpers" do
    test "maybe/3 applies function when condition is truthy" do
      token =
        create_table(:users)
        |> Pipeline.maybe(&Pipeline.with_soft_delete/1, true)

      assert Token.has_field?(token, :deleted_at)
    end

    test "maybe/3 skips function when condition is false" do
      token =
        create_table(:users)
        |> Pipeline.maybe(&Pipeline.with_soft_delete/1, false)

      refute Token.has_field?(token, :deleted_at)
    end

    test "maybe/3 skips function when condition is nil" do
      token =
        create_table(:users)
        |> Pipeline.maybe(&Pipeline.with_soft_delete/1, nil)

      refute Token.has_field?(token, :deleted_at)
    end

    test "validate!/1 returns token when valid" do
      token =
        create_table(:users)
        |> Token.add_field(:email, :string, [])

      assert ^token = Pipeline.validate!(token)
    end

    test "validate!/1 raises when invalid" do
      token = create_table(:users)

      assert_raise ArgumentError, fn ->
        Pipeline.validate!(token)
      end
    end
  end

  describe "Pipeline Composition" do
    test "full user table pipeline" do
      token =
        create_table(:users)
        |> Pipeline.with_uuid_primary_key()
        |> Pipeline.with_identity(:email)
        |> Pipeline.with_authentication()
        |> Pipeline.with_soft_delete()
        |> Pipeline.with_timestamps()

      # Verify all expected fields
      assert Token.has_field?(token, :id)
      assert Token.has_field?(token, :email)
      assert Token.has_field?(token, :password_hash)
      assert Token.has_field?(token, :deleted_at)
      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)

      # Should be valid
      assert {:ok, _} = Token.validate(token)
    end

    test "full order table pipeline" do
      token =
        create_table(:orders)
        |> Pipeline.with_uuid_primary_key()
        |> Pipeline.with_status(values: ["pending", "processing", "shipped", "delivered"])
        |> Pipeline.with_money([:subtotal, :tax, :total])
        |> Pipeline.with_metadata()
        |> Pipeline.with_timestamps()

      assert Token.has_field?(token, :id)
      assert Token.has_field?(token, :status)
      assert Token.has_field?(token, :subtotal)
      assert Token.has_field?(token, :tax)
      assert Token.has_field?(token, :total)
      assert Token.has_field?(token, :metadata)

      assert {:ok, _} = Token.validate(token)
    end
  end
end
