defmodule OmMigration.Pipeline do
  @moduledoc """
  Beautiful pipeline functions for composing migrations.

  Each function takes a token and returns a modified token,
  allowing elegant composition with the pipe operator.
  """

  alias OmMigration.Token
  alias OmMigration.Fields
  alias OmMigration.FieldMacros

  # ============================================
  # Primary Key Pipelines
  # ============================================

  @doc """
  Adds UUIDv7 primary key (PostgreSQL 18+).

  ## Examples

      create_table(:users)
      |> with_uuid_primary_key()
  """
  defdelegate with_uuid_primary_key(token, opts \\ []), to: FieldMacros

  @doc """
  Adds legacy UUID v4 primary key.
  """
  def with_uuid_v4_primary_key(%Token{} = token) do
    token
    |> Token.put_option(:primary_key, false)
    |> Token.add_field(:id, :binary_id,
      primary_key: true,
      default: {:fragment, "uuid_generate_v4()"}
    )
  end

  # ============================================
  # Identity Pipelines
  # ============================================

  @doc """
  Adds identity fields (name, email, etc.).

  ## Examples

      create_table(:users)
      |> with_identity(:name, :email)
      |> with_identity(:name, :email, :phone)
  """
  def with_identity(%Token{} = token, fields) when is_list(fields) do
    Enum.reduce(fields, token, &add_identity_field(&2, &1))
  end

  def with_identity(%Token{} = token, field) do
    add_identity_field(token, field)
  end

  defp add_identity_field(token, :name) do
    token
    |> Token.add_fields(Fields.name_fields())
  end

  defp add_identity_field(token, :email) do
    token
    |> Token.add_field(:email, :citext, null: false)
    |> Token.add_index(:users_email_index, [:email], unique: true)
  end

  defp add_identity_field(token, :phone) do
    token
    |> Token.add_field(:phone, :string, null: true)
  end

  defp add_identity_field(token, :username) do
    token
    |> Token.add_field(:username, :citext, null: false)
    |> Token.add_index(:users_username_index, [:username], unique: true)
  end

  # ============================================
  # Authentication Pipelines
  # ============================================

  @doc """
  Adds authentication fields.

  ## Examples

      create_table(:users)
      |> with_authentication()
      |> with_authentication(type: :oauth)
  """
  def with_authentication(%Token{} = token, opts \\ []) do
    type = Keyword.get(opts, :type, :password)

    case type do
      :password -> add_password_auth_fields(token)
      :oauth -> add_oauth_fields(token)
      :magic_link -> add_magic_link_fields(token)
      _ -> token
    end
  end

  defp add_password_auth_fields(token) do
    token
    |> Token.add_field(:password_hash, :string, null: false)
    |> Token.add_field(:confirmed_at, :utc_datetime)
    |> Token.add_field(:confirmation_token, :string)
    |> Token.add_field(:confirmation_sent_at, :utc_datetime)
    |> Token.add_field(:reset_password_token, :string)
    |> Token.add_field(:reset_password_sent_at, :utc_datetime)
    |> Token.add_field(:failed_attempts, :integer, default: 0)
    |> Token.add_field(:locked_at, :utc_datetime)
    |> Token.add_index(:users_confirmation_token_index, [:confirmation_token], unique: true)
    |> Token.add_index(:users_reset_password_token_index, [:reset_password_token], unique: true)
  end

  defp add_oauth_fields(token) do
    token
    |> Token.add_field(:provider, :string)
    |> Token.add_field(:provider_id, :string)
    |> Token.add_field(:provider_token, :text)
    |> Token.add_field(:provider_refresh_token, :text)
    |> Token.add_field(:provider_token_expires_at, :utc_datetime)
    |> Token.add_index(:users_provider_index, [:provider, :provider_id], unique: true)
  end

  defp add_magic_link_fields(token) do
    token
    |> Token.add_field(:magic_token, :string)
    |> Token.add_field(:magic_token_sent_at, :utc_datetime)
    |> Token.add_field(:magic_token_expires_at, :utc_datetime)
    |> Token.add_index(:users_magic_token_index, [:magic_token], unique: true)
  end

  # ============================================
  # Profile Pipelines
  # ============================================

  @doc """
  Adds profile fields.

  ## Examples

      create_table(:users)
      |> with_profile(:bio, :avatar, :location)
  """
  def with_profile(%Token{} = token, fields) when is_list(fields) do
    Enum.reduce(fields, token, &add_profile_field(&2, &1))
  end

  def with_profile(%Token{} = token, field) do
    add_profile_field(token, field)
  end

  defp add_profile_field(token, :bio) do
    Token.add_field(token, :bio, :text)
  end

  defp add_profile_field(token, :avatar) do
    token
    |> Token.add_field(:avatar_url, :string)
    |> Token.add_field(:avatar_thumbnail_url, :string)
  end

  defp add_profile_field(token, :location) do
    token
    |> Token.add_fields(Fields.address_fields())
    |> Token.add_fields(Fields.geo_fields())
  end

  # ============================================
  # Business Pipelines
  # ============================================

  @doc """
  Adds business/financial fields.

  ## Examples

      create_table(:invoices)
      |> with_money(:amount, :tax, :total)
      |> with_status()
  """
  def with_money(%Token{} = token, fields) when is_list(fields) do
    Enum.reduce(fields, token, fn field, acc ->
      Token.add_field(acc, field, :decimal, precision: 10, scale: 2)
    end)
  end

  def with_money(%Token{} = token, field) do
    Token.add_field(token, field, :decimal, precision: 10, scale: 2)
  end

  @doc """
  Adds status field with enum constraint.
  """
  def with_status(%Token{} = token, opts \\ []) do
    values = Keyword.get(opts, :values, ["draft", "active", "archived"])
    default = Keyword.get(opts, :default, "draft")

    token
    |> Token.add_field(:status, :string, null: false, default: default)
    |> Token.add_constraint(:status_check, :check,
      check: "status IN (#{values |> Enum.map(&"'#{&1}'") |> Enum.join(", ")})"
    )
    |> Token.add_index(:status_index, [:status])
  end

  # ============================================
  # Metadata Pipelines
  # ============================================

  @doc """
  Adds JSONB metadata field.

  ## Examples

      create_table(:products)
      |> with_metadata()
      |> with_metadata(name: :properties)
  """
  def with_metadata(%Token{} = token, opts \\ []) do
    name = Keyword.get(opts, :name, :metadata)
    default = Keyword.get(opts, :default, %{})

    token
    |> Token.add_field(name, :jsonb, default: default, null: false)
    |> Token.add_index(:"#{token.name}_#{name}_gin_index", [name], using: :gin)
  end

  @doc """
  Adds tags array field.
  """
  def with_tags(%Token{} = token, opts \\ []) do
    name = Keyword.get(opts, :name, :tags)

    token
    |> Token.add_field(name, {:array, :string}, default: [], null: false)
    |> Token.add_index(:"#{token.name}_#{name}_gin_index", [name], using: :gin)
  end

  @doc """
  Adds settings JSONB field.
  """
  def with_settings(%Token{} = token, opts \\ []) do
    with_metadata(token, Keyword.put(opts, :name, :settings))
  end

  # ============================================
  # Type and Status Field Pipelines
  # ============================================

  @doc """
  Adds type classification fields (citext by default).

  ## Examples

      create_table(:products)
      |> with_type_fields()
      |> with_type_fields(only: [:type, :subtype])
  """
  defdelegate with_type_fields(token, opts \\ []), to: FieldMacros

  @doc """
  Adds status tracking fields (citext by default).

  ## Examples

      create_table(:orders)
      |> with_status_fields()
      |> with_status_fields(with_transition: true)
  """
  defdelegate with_status_fields(token, opts \\ []), to: FieldMacros

  # ============================================
  # Audit Pipelines
  # ============================================

  @doc """
  Adds audit tracking fields.

  ## Examples

      create_table(:products)
      |> with_audit()
      |> with_audit(track_user: true)
  """
  defdelegate with_audit_fields(token, opts \\ []), to: FieldMacros

  # Backward compatibility alias
  def with_audit(token, opts \\ []), do: with_audit_fields(token, opts)

  # ============================================
  # Soft Delete Pipelines
  # ============================================

  @doc """
  Adds soft delete fields.

  ## Options
  - `:track_urm` - Include deleted_by_urm_id (default: true)
  - `:track_user` - Include deleted_by_user_id (default: false)
  - `:track_reason` - Include deletion_reason (default: false)

  ## Examples

      create_table(:users)
      |> with_soft_delete()
      |> with_soft_delete(track_user: true, track_reason: true)
      |> with_soft_delete(track_urm: false)
  """
  def with_soft_delete(%Token{} = token, opts \\ []) do
    track_urm = Keyword.get(opts, :track_urm, true)
    track_user = Keyword.get(opts, :track_user, false)
    track_reason = Keyword.get(opts, :track_reason, false)

    token
    |> Token.add_field(:deleted_at, :utc_datetime_usec)
    |> maybe_add_urm_tracking(track_urm)
    |> maybe_add_deletion_user(track_user)
    |> maybe_add_deletion_reason(track_reason)
    |> Token.add_index(:deleted_at_index, [:deleted_at])
    |> Token.add_index(:active_records_index, [:id], where: "deleted_at IS NULL")
  end

  defp maybe_add_urm_tracking(token, false), do: token

  defp maybe_add_urm_tracking(token, true) do
    Token.add_field(token, :deleted_by_urm_id, :binary_id)
  end

  defp maybe_add_deletion_user(token, false), do: token

  defp maybe_add_deletion_user(token, true) do
    Token.add_field(token, :deleted_by_user_id, :binary_id)
  end

  defp maybe_add_deletion_reason(token, false), do: token

  defp maybe_add_deletion_reason(token, true) do
    Token.add_field(token, :deletion_reason, :text)
  end

  # ============================================
  # Timestamp Pipelines
  # ============================================

  @doc """
  Adds timestamp fields (utc_datetime_usec by default).

  ## Examples

      create_table(:articles)
      |> with_timestamps()
      |> with_timestamps(only: [:inserted_at])
      |> with_timestamps(with_deleted: true)
  """
  defdelegate with_timestamps(token, opts \\ []), to: FieldMacros

  # ============================================
  # Index Pipelines
  # ============================================

  @doc """
  Makes an index unique.

  ## Examples

      create_index(:users, [:email])
      |> unique()
  """
  def unique(%Token{type: :index} = token) do
    Token.put_option(token, :unique, true)
  end

  @doc """
  Adds a WHERE clause to an index.

  ## Examples

      create_index(:users, [:email])
      |> where("deleted_at IS NULL")
  """
  def where(%Token{type: :index} = token, condition) do
    Token.put_option(token, :where, condition)
  end

  @doc """
  Sets the index method.

  ## Examples

      create_index(:products, [:tags])
      |> using(:gin)
  """
  def using(%Token{type: :index} = token, method) do
    Token.put_option(token, :using, method)
  end

  # ============================================
  # Composition Helpers
  # ============================================

  @doc """
  Applies a function to the token if condition is true.

  ## Examples

      create_table(:users)
      |> with_uuid_primary_key()
      |> maybe(&with_soft_delete/1, opts[:soft_delete])
  """
  def maybe(token, _fun, false), do: token
  def maybe(token, _fun, nil), do: token
  def maybe(token, fun, _truthy) when is_function(fun, 1), do: fun.(token)

  @doc """
  Taps into the pipeline for debugging.

  ## Examples

      create_table(:users)
      |> tap_inspect("After adding fields")
      |> with_timestamps()
  """
  def tap_inspect(token, label \\ "") do
    IO.inspect(token, label: label)
    token
  end

  @doc """
  Validates the token in the pipeline.

  ## Examples

      create_table(:users)
      |> with_fields(...)
      |> validate!()
      |> execute()
  """
  def validate!(%Token{} = token) do
    case Token.validate(token) do
      {:ok, token} -> token
      {:error, message} -> raise ArgumentError, message
    end
  end
end
