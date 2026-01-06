defmodule Events.Domains.Accounts.User do
  @moduledoc """
  Schema for users.

  Users are not account-scoped - they can belong to multiple accounts
  via memberships (GitHub org model).

  ## Security Features

  - **Login tracking**: `last_login_at`, `last_login_ip`, `login_count`
  - **Account lockout**: After 5 failed attempts, account locks for 30 minutes
  - **Audit fields**: `password_changed_at` tracks password changes

  ## User Defaults

  Users can set a preferred account and role via `default_account_id` and
  `default_role_id`. These are used when the user logs in without specifying
  a context.
  """

  @derive {FnTypes.Protocols.Identifiable, type: :user}

  use OmSchema

  @types [:human, :system, :service]
  @subtypes [:standard, :admin, :bot, :sso]
  @statuses [:active, :suspended, :deleted]

  # Security constants
  @max_failed_attempts 5
  @lockout_duration_minutes 30

  @typedoc "User struct type"
  @type t :: %__MODULE__{}

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

    # Security audit fields
    field :last_login_at, :utc_datetime_usec
    field :last_login_ip, :string
    field :login_count, :integer, default: 0
    field :failed_login_attempts, :integer, default: 0
    field :locked_at, :utc_datetime_usec
    field :lock_reason, :string
    field :password_changed_at, :utc_datetime_usec

    type_fields()
    status_fields(values: @statuses, default: :active)
    metadata_field()
    assets_field()
    audit_fields()
    timestamps()

    # User defaults
    belongs_to :default_account, Events.Domains.Accounts.Account,
      foreign_key: :default_account_id,
      on_replace: :nilify

    belongs_to :default_role, Events.Domains.Accounts.Role,
      foreign_key: :default_role_id,
      on_replace: :nilify

    has_many :memberships, Events.Domains.Accounts.Membership, expect_on_delete: :cascade
    has_many :accounts, through: [:memberships, :account]

    has_many :user_role_mappings, Events.Domains.Accounts.UserRoleMapping,
      expect_on_delete: :cascade

    has_many :roles, through: [:user_role_mappings, :role]
    has_many :tokens, Events.Domains.Accounts.UserToken, expect_on_delete: :cascade
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
      |> unsafe_validate_unique(:email, Events.Data.Repo)
      |> unsafe_validate_unique(:username, Events.Data.Repo)
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

  # ===========================================================================
  # Security Changesets
  # ===========================================================================

  @doc """
  Creates a changeset for recording a successful login.

  Updates login tracking fields and clears any lockout state.
  """
  @spec login_success_changeset(t(), String.t() | nil) :: Ecto.Changeset.t()
  def login_success_changeset(user, ip_address \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    user
    |> change()
    |> put_change(:last_login_at, now)
    |> put_change(:last_login_ip, ip_address)
    |> put_change(:login_count, (user.login_count || 0) + 1)
    |> put_change(:failed_login_attempts, 0)
    |> put_change(:locked_at, nil)
    |> put_change(:lock_reason, nil)
  end

  @doc """
  Creates a changeset for recording a failed login attempt.

  Increments failed attempts counter and locks account after #{@max_failed_attempts} failures.
  """
  @spec login_failure_changeset(t()) :: Ecto.Changeset.t()
  def login_failure_changeset(user) do
    attempts = (user.failed_login_attempts || 0) + 1
    changeset = change(user, failed_login_attempts: attempts)

    if attempts >= @max_failed_attempts do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      changeset
      |> put_change(:locked_at, now)
      |> put_change(:lock_reason, "too_many_failed_attempts")
    else
      changeset
    end
  end

  @doc """
  Creates a changeset for unlocking a user account.
  """
  @spec unlock_changeset(t()) :: Ecto.Changeset.t()
  def unlock_changeset(user) do
    change(user,
      locked_at: nil,
      lock_reason: nil,
      failed_login_attempts: 0
    )
  end

  @doc """
  Creates a changeset for updating user defaults (account and role).
  """
  @spec defaults_changeset(t(), map()) :: Ecto.Changeset.t()
  def defaults_changeset(user, attrs) do
    user
    |> cast(attrs, [:default_account_id, :default_role_id])
    |> foreign_key_constraint(:default_account_id)
    |> foreign_key_constraint(:default_role_id)
  end

  # ===========================================================================
  # Security Predicates
  # ===========================================================================

  @doc """
  Checks if the user account is currently locked.

  Returns `true` if locked within the #{@lockout_duration_minutes}-minute window.
  """
  @spec locked?(t()) :: boolean()
  def locked?(%__MODULE__{locked_at: nil}), do: false

  def locked?(%__MODULE__{locked_at: locked_at}) do
    lockout_expires = DateTime.add(locked_at, @lockout_duration_minutes, :minute)
    DateTime.compare(DateTime.utc_now(), lockout_expires) == :lt
  end

  @doc """
  Returns the number of remaining lockout minutes, or 0 if not locked.
  """
  @spec lockout_remaining_minutes(t()) :: non_neg_integer()
  def lockout_remaining_minutes(%__MODULE__{locked_at: nil}), do: 0

  def lockout_remaining_minutes(%__MODULE__{locked_at: locked_at}) do
    lockout_expires = DateTime.add(locked_at, @lockout_duration_minutes, :minute)
    diff = DateTime.diff(lockout_expires, DateTime.utc_now(), :minute)
    max(0, diff)
  end

  @doc """
  Returns the maximum number of failed login attempts before lockout.
  """
  @spec max_failed_attempts() :: pos_integer()
  def max_failed_attempts, do: @max_failed_attempts

  @doc """
  Returns the lockout duration in minutes.
  """
  @spec lockout_duration_minutes() :: pos_integer()
  def lockout_duration_minutes, do: @lockout_duration_minutes

  # ===========================================================================
  # Type Helpers
  # ===========================================================================

  @doc "Returns the list of valid types."
  def types, do: @types

  @doc "Returns the list of valid subtypes."
  def subtypes, do: @subtypes

  @doc "Returns the list of valid statuses."
  def statuses, do: @statuses
end
