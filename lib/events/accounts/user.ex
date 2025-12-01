defmodule Events.Accounts.User do
  @moduledoc """
  Schema for users.

  Users are not account-scoped - they can belong to multiple accounts
  via memberships (GitHub org model).
  """

  @derive {Events.Protocols.Identifiable, type: :user}

  use Events.Core.Schema

  @types [:human, :system, :service]
  @subtypes [:standard, :admin, :bot]
  @statuses [:active, :suspended, :deleted]

  schema "users" do
    field :email, :string,
      required: true,
      max_length: 160,
      mappers: [:trim, :downcase],
      format: :email,
      unique: :users_email_index

    field :username, :string,
      min_length: 3,
      max_length: 30,
      format: ~r/^[a-zA-Z0-9_]+$/,
      unique: :users_username_index

    field :hashed_password, :string, redact: true, cast: false, trim: false
    field :confirmed_at, :utc_datetime_usec

    field :password, :string,
      virtual: true,
      redact: true,
      trim: false,
      min_length: 12,
      max_length: 72

    type_fields()
    status_fields(values: @statuses, default: :active)
    metadata_field()
    assets_field()
    audit_fields()
    timestamps()

    has_many :memberships, Events.Accounts.Membership, expect_on_delete: :cascade
    has_many :accounts, through: [:memberships, :account]
    has_many :user_role_mappings, Events.Accounts.UserRoleMapping, expect_on_delete: :cascade
    has_many :roles, through: [:user_role_mappings, :role]
    has_many :tokens, Events.Accounts.UserToken, expect_on_delete: :cascade
  end

  @doc """
  Creates a changeset for user registration.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> base_changeset(attrs, cast: [:password], required: [:password])
    |> maybe_validate_unique(opts)
    |> maybe_hash_password(opts)
  end

  @doc """
  Creates a changeset for updating user email.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> base_changeset(attrs, only_cast: [:email], only_required: [:email])
    |> maybe_validate_unique(opts)
  end

  @doc """
  Creates a changeset for updating user password.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> base_changeset(attrs, only_cast: [:password], only_required: [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> maybe_hash_password(opts)
  end

  @doc """
  Creates a changeset for confirming email.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(user, confirmed_at: now)
  end

  @doc """
  Validates the current password for sensitive operations.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  Verifies the password against the hashed password.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _), do: Bcrypt.no_user_verify()

  # Private helpers

  defp maybe_validate_unique(changeset, opts) do
    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Events.Core.Repo)
      |> unsafe_validate_unique(:username, Events.Core.Repo)
      |> unique_constraints([{:email, []}, {:username, []}])
    else
      changeset
    end
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc "Returns the list of valid types."
  def types, do: @types

  @doc "Returns the list of valid subtypes."
  def subtypes, do: @subtypes

  @doc "Returns the list of valid statuses."
  def statuses, do: @statuses
end
