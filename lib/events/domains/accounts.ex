defmodule Events.Domains.Accounts do
  @moduledoc """
  Context for accounts, users, memberships, roles, and user role mappings.

  Handles:
  - Account (tenant) management
  - User authentication (phx.gen.auth pattern)
  - Memberships (account <-> user associations)
  - Roles (global and per-account)
  - User role mappings (RBAC)
  """

  use OmCrud.Context
  use Events.Extensions.Decorator

  import Ecto.Query
  alias Events.Data.Repo

  alias Events.Domains.Accounts.{
    Account,
    User,
    UserToken,
    Membership,
    Role,
    UserRoleMapping
  }

  # ===========================================================================
  # Generated CRUD
  # ===========================================================================
  # Each schema gets: fetch_*, get_*, list_*, filter_*, count_*, first_*, last_*,
  # stream_*, *_exists?, create_*, update_*, delete_*, create_all_*, update_all_*,
  # delete_all_* (plus bang variants)

  crud(Account, order_by: [asc: :name])
  crud(User, order_by: [desc: :inserted_at, asc: :id])
  crud(Membership, order_by: [desc: :joined_at])
  crud(Role, order_by: [asc: :name])
  crud(UserRoleMapping, as: :urm, order_by: [desc: :inserted_at])

  # ===========================================================================
  # Accounts
  # ===========================================================================

  def get_account_by_slug(slug), do: Repo.get_by(Account, slug: slug)

  def get_default_account, do: Repo.get(Account, Events.Constants.default_account_id())

  def change_account(account, attrs \\ %{}), do: Account.changeset(account, attrs)

  def list_accounts_for_user(user_id) do
    Account
    |> join(:inner, [a], m in Membership, on: m.account_id == a.id)
    |> where([_, m], m.user_id == ^user_id and m.status == :active)
    |> Repo.all()
  end

  # ===========================================================================
  # Users
  # ===========================================================================

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def get_user_by_username(username), do: Repo.get_by(User, username: username)

  def get_system_user, do: Repo.get(User, Events.Constants.system_user_id())

  @decorate telemetry_span([:events, :accounts, :register])
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  # ===========================================================================
  # User Defaults
  # ===========================================================================

  def set_user_defaults(user, account_id, role_id) do
    user
    |> User.defaults_changeset(%{default_account_id: account_id, default_role_id: role_id})
    |> Repo.update()
  end

  def get_user_with_defaults(id) do
    case Repo.get(User, id) do
      nil -> nil
      user -> Repo.preload(user, [:default_account, :default_role])
    end
  end

  # ===========================================================================
  # Authentication
  # ===========================================================================

  @doc """
  Authenticates user with lockout protection.

  Returns `{:ok, user}` on success, `{:error, reason}` on failure.
  Reasons: `:invalid_credentials`, `:account_locked`
  """
  @decorate telemetry_span([:events, :accounts, :authenticate])
  def authenticate_user(email, password, opts \\ []) do
    case get_user_by_email(email) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        authenticate_user_with_password(user, password, opts[:ip_address])
    end
  end

  defp authenticate_user_with_password(user, password, ip_address) do
    cond do
      User.locked?(user) ->
        {:error, :account_locked}

      User.valid_password?(user, password) ->
        record_login_success(user, ip_address)

      true ->
        record_login_failure(user)
        {:error, :invalid_credentials}
    end
  end

  def record_login_success(user, ip_address \\ nil) do
    user |> User.login_success_changeset(ip_address) |> Repo.update()
  end

  def record_login_failure(user) do
    user |> User.login_failure_changeset() |> Repo.update()
  end

  def unlock_user(user) do
    user |> User.unlock_changeset() |> Repo.update()
  end

  def user_locked?(user), do: User.locked?(user)

  # ===========================================================================
  # Sessions
  # ===========================================================================

  @decorate telemetry_span([:events, :accounts, :session, :generate])
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)

    case Repo.insert(user_token) do
      {:ok, _} -> {:ok, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @decorate telemetry_span([:events, :accounts, :session, :verify])
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @decorate telemetry_span([:events, :accounts, :session, :delete])
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  # ===========================================================================
  # Email Confirmation
  # ===========================================================================

  def deliver_user_confirmation_instructions(%User{confirmed_at: confirmed_at}, _)
      when not is_nil(confirmed_at),
      do: {:error, :already_confirmed}

  def deliver_user_confirmation_instructions(user, _confirmation_url_fun) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")

    case Repo.insert(user_token) do
      {:ok, _} -> {:ok, encoded_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @decorate telemetry_span([:events, :accounts, :confirm])
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  # ===========================================================================
  # Password Management
  # ===========================================================================

  @decorate telemetry_span([:events, :accounts, :update_email])
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(update_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp update_email_multi(user, email, context) do
    changeset = user |> User.email_changeset(%{email: email}) |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @decorate telemetry_span([:events, :accounts, :update_password])
  def update_user_password(user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(current_password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def deliver_user_reset_password_instructions(user, _reset_password_url_fun) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

    case Repo.insert(user_token) do
      {:ok, _} -> {:ok, encoded_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  @decorate telemetry_span([:events, :accounts, :reset_password])
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  # ===========================================================================
  # Memberships
  # ===========================================================================

  def list_memberships_for_account(account_id) do
    Membership
    |> where(account_id: ^account_id)
    |> preload(:user)
    |> Repo.all()
  end

  def list_memberships_for_user(user_id) do
    Membership
    |> where(user_id: ^user_id)
    |> preload(:account)
    |> Repo.all()
  end

  def get_membership_by(clauses), do: Repo.get_by(Membership, clauses)

  @decorate telemetry_span([:events, :accounts, :add_member])
  def add_user_to_account(account_id, user_id, attrs \\ %{}) do
    attrs
    |> Map.merge(%{account_id: account_id, user_id: user_id})
    |> create_membership()
  end

  @decorate telemetry_span([:events, :accounts, :remove_member])
  def remove_user_from_account(account_id, user_id) do
    case get_membership_by(account_id: account_id, user_id: user_id) do
      nil -> {:error, :not_found}
      membership -> delete_membership(membership)
    end
  end

  def change_membership(membership, attrs \\ %{}), do: Membership.changeset(membership, attrs)

  def member?(account_id, user_id) do
    Membership
    |> where(account_id: ^account_id, user_id: ^user_id, status: :active)
    |> Repo.exists?()
  end

  # ===========================================================================
  # Roles
  # ===========================================================================

  def list_roles_for_account(account_id) do
    Role
    |> where([r], r.account_id == ^account_id or is_nil(r.account_id))
    |> where(status: :active)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  def list_global_roles do
    Role
    |> where([r], is_nil(r.account_id))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  def get_role_by_slug(slug), do: Repo.get_by(Role, slug: slug)

  def get_system_role, do: Repo.get(Role, Events.Constants.system_role_id())

  def change_role(role, attrs \\ %{}), do: Role.changeset(role, attrs)

  # Override generated delete_role to protect system roles
  def delete_role(role, opts \\ [])
  def delete_role(%Role{is_system: true}, _opts), do: {:error, :system_role}
  def delete_role(role, opts), do: OmCrud.delete(role, opts)

  # ===========================================================================
  # User Role Mappings
  # ===========================================================================

  def list_urms_for_user(user_id) do
    UserRoleMapping
    |> where(user_id: ^user_id)
    |> preload([:role, :account])
    |> Repo.all()
  end

  def list_urms_for_user_in_account(user_id, account_id) do
    UserRoleMapping
    |> where(user_id: ^user_id, account_id: ^account_id)
    |> preload(:role)
    |> Repo.all()
  end

  def list_urms_for_account(account_id) do
    UserRoleMapping
    |> where(account_id: ^account_id)
    |> preload([:user, :role])
    |> Repo.all()
  end

  def list_users_with_role(role_id, account_id) do
    User
    |> join(:inner, [u], urm in UserRoleMapping, on: urm.user_id == u.id)
    |> where([_, urm], urm.role_id == ^role_id and urm.account_id == ^account_id)
    |> Repo.all()
  end

  def get_system_urm, do: Repo.get(UserRoleMapping, Events.Constants.system_urm_id())

  def get_urm_by(clauses), do: Repo.get_by(UserRoleMapping, clauses)

  @decorate telemetry_span([:events, :accounts, :assign_role])
  def assign_role(user_id, role_id, account_id, attrs \\ %{}) do
    attrs
    |> Map.merge(%{user_id: user_id, role_id: role_id, account_id: account_id})
    |> create_urm()
  end

  @decorate telemetry_span([:events, :accounts, :remove_role])
  def remove_role(user_id, role_id, account_id) do
    case get_urm_by(user_id: user_id, role_id: role_id, account_id: account_id) do
      nil -> {:error, :not_found}
      urm -> delete_urm(urm)
    end
  end

  def change_urm(urm, attrs \\ %{}), do: UserRoleMapping.changeset(urm, attrs)

  def has_role?(user_id, role_id, account_id) do
    UserRoleMapping
    |> where(user_id: ^user_id, role_id: ^role_id, account_id: ^account_id)
    |> Repo.exists?()
  end

  def get_user_roles(user_id, account_id) do
    Role
    |> join(:inner, [r], urm in UserRoleMapping, on: urm.role_id == r.id)
    |> where([_, urm], urm.user_id == ^user_id and urm.account_id == ^account_id)
    |> Repo.all()
  end
end
