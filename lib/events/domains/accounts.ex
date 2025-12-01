defmodule Events.Domains.Accounts do
  @moduledoc """
  Context module for managing accounts, users, memberships, roles, and user role mappings.

  This is the core RBAC context that handles:
  - Account (tenant) management
  - User authentication (phx.gen.auth pattern)
  - Memberships (account ↔ user associations)
  - Roles (global and per-account)
  - User role mappings (assigns roles to users within accounts)

  All public functions return result tuples `{:ok, result} | {:error, reason}` unless
  explicitly documented otherwise (e.g., bang variants, boolean predicates).
  """

  use Events.Infra.Decorator

  import Ecto.Query
  alias Events.Core.Repo

  alias Events.Domains.Accounts.{
    Account,
    User,
    UserToken,
    Membership,
    Role,
    UserRoleMapping
  }

  # ===========================================================================
  # Accounts
  # ===========================================================================

  @doc """
  Returns the list of accounts.
  """
  def list_accounts do
    Repo.all(Account)
  end

  @doc """
  Gets a single account by ID.
  """
  def get_account(id), do: Repo.get(Account, id)

  @doc """
  Gets a single account by ID.

  Raises `Ecto.NoResultsError` if the account does not exist.
  """
  def get_account!(id), do: Repo.get!(Account, id)

  @doc """
  Gets an account by slug.
  """
  def get_account_by_slug(slug) do
    Repo.get_by(Account, slug: slug)
  end

  @doc """
  Gets the default account.
  """
  def get_default_account do
    get_account(Events.Support.Constants.default_account_id())
  end

  @doc """
  Creates an account.
  """
  def create_account(attrs \\ %{}) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an account.
  """
  def update_account(%Account{} = account, attrs) do
    account
    |> Account.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an account.
  """
  def delete_account(%Account{} = account) do
    Repo.delete(account)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking account changes.
  """
  def change_account(%Account{} = account, attrs \\ %{}) do
    Account.changeset(account, attrs)
  end

  @doc """
  Lists accounts for a user (via memberships).
  """
  def list_accounts_for_user(user_id) do
    from(a in Account,
      join: m in assoc(a, :memberships),
      where: m.user_id == ^user_id and m.status == :active,
      select: a
    )
    |> Repo.all()
  end

  # ===========================================================================
  # Users
  # ===========================================================================

  @doc """
  Returns the list of users.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user by ID.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a single user by ID.

  Raises `Ecto.NoResultsError` if the user does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by email and password.

  Returns the user if found and password is valid, `nil` otherwise.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    email
    |> get_user_by_email()
    |> validate_user_password(password)
  end

  defp validate_user_password(nil, _password), do: nil

  defp validate_user_password(%User{} = user, password) do
    case User.valid_password?(user, password) do
      true -> user
      false -> nil
    end
  end

  @doc """
  Gets the system user.
  """
  def get_system_user do
    get_user(Events.Support.Constants.system_user_id())
  end

  @doc """
  Registers a user.
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Updates the user email using the given token.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset = user |> User.email_changeset(%{email: email}) |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.
  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  # Session management

  @doc """
  Generates a session token.

  Returns `{:ok, token}` on success, `{:error, changeset}` on failure.
  """
  @spec generate_user_session_token(User.t()) :: {:ok, binary()} | {:error, Ecto.Changeset.t()}
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)

    case Repo.insert(user_token) do
      {:ok, _} -> {:ok, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  # Email confirmation

  @doc """
  Delivers the confirmation email instructions to the given user.

  Returns `{:ok, encoded_token}` on success, `{:error, reason}` on failure.
  """
  @spec deliver_user_confirmation_instructions(User.t(), (binary() -> binary())) ::
          {:ok, binary()} | {:error, :already_confirmed | Ecto.Changeset.t()}
  def deliver_user_confirmation_instructions(
        %User{confirmed_at: confirmed_at},
        _confirmation_url_fun
      )
      when not is_nil(confirmed_at) do
    {:error, :already_confirmed}
  end

  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")

    case Repo.insert(user_token) do
      {:ok, _} -> {:ok, encoded_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Confirms a user by the given token.
  """
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

  # Password reset

  @doc """
  Delivers the reset password email to the given user.

  Returns `{:ok, encoded_token}` on success, `{:error, changeset}` on failure.
  """
  @spec deliver_user_reset_password_instructions(User.t(), (binary() -> binary())) ::
          {:ok, binary()} | {:error, Ecto.Changeset.t()}
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

    case Repo.insert(user_token) do
      {:ok, _} -> {:ok, encoded_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets the user by reset password token.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.
  """
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

  @doc """
  Returns the list of memberships.
  """
  def list_memberships do
    Repo.all(Membership)
  end

  @doc """
  Lists memberships for an account.
  """
  def list_memberships_for_account(account_id) do
    from(m in Membership,
      where: m.account_id == ^account_id,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Lists memberships for a user.
  """
  def list_memberships_for_user(user_id) do
    from(m in Membership,
      where: m.user_id == ^user_id,
      preload: [:account]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single membership by ID.
  """
  def get_membership(id), do: Repo.get(Membership, id)

  @doc """
  Gets a single membership by ID.

  Raises `Ecto.NoResultsError` if the membership does not exist.
  """
  def get_membership!(id), do: Repo.get!(Membership, id)

  @doc """
  Gets a membership by account and user.
  """
  def get_membership_by_account_and_user(account_id, user_id) do
    Repo.get_by(Membership, account_id: account_id, user_id: user_id)
  end

  @doc """
  Creates a membership.
  """
  def create_membership(attrs \\ %{}) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds a user to an account.
  """
  def add_user_to_account(account_id, user_id, attrs \\ %{}) do
    attrs
    |> Map.put(:account_id, account_id)
    |> Map.put(:user_id, user_id)
    |> create_membership()
  end

  @doc """
  Updates a membership.
  """
  def update_membership(%Membership{} = membership, attrs) do
    membership
    |> Membership.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a membership.
  """
  def delete_membership(%Membership{} = membership) do
    Repo.delete(membership)
  end

  @doc """
  Removes a user from an account.

  Returns `{:ok, membership}` on success, `{:error, :not_found}` if no membership exists.
  """
  @spec remove_user_from_account(binary(), binary()) ::
          {:ok, Membership.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def remove_user_from_account(account_id, user_id) do
    account_id
    |> get_membership_by_account_and_user(user_id)
    |> do_delete_membership()
  end

  defp do_delete_membership(nil), do: {:error, :not_found}
  defp do_delete_membership(%Membership{} = membership), do: delete_membership(membership)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking membership changes.
  """
  def change_membership(%Membership{} = membership, attrs \\ %{}) do
    Membership.changeset(membership, attrs)
  end

  @doc """
  Checks if a user is a member of an account.
  """
  def member?(account_id, user_id) do
    from(m in Membership,
      where: m.account_id == ^account_id and m.user_id == ^user_id and m.status == :active
    )
    |> Repo.exists?()
  end

  # ===========================================================================
  # Roles
  # ===========================================================================

  @doc """
  Returns the list of roles.
  """
  def list_roles do
    Repo.all(Role)
  end

  @doc """
  Lists roles for an account (including global roles where account_id is nil).
  """
  def list_roles_for_account(account_id) do
    from(r in Role,
      where: r.account_id == ^account_id or is_nil(r.account_id),
      where: r.status == :active
    )
    |> Repo.all()
  end

  @doc """
  Lists global roles (account_id is nil).
  """
  def list_global_roles do
    from(r in Role, where: is_nil(r.account_id))
    |> Repo.all()
  end

  @doc """
  Gets a single role by ID.
  """
  def get_role(id), do: Repo.get(Role, id)

  @doc """
  Gets a single role by ID.

  Raises `Ecto.NoResultsError` if the role does not exist.
  """
  def get_role!(id), do: Repo.get!(Role, id)

  @doc """
  Gets a role by slug.
  """
  def get_role_by_slug(slug) do
    Repo.get_by(Role, slug: slug)
  end

  @doc """
  Gets the system role (super_admin).
  """
  def get_system_role do
    get_role(Events.Support.Constants.system_role_id())
  end

  @doc """
  Creates a role.
  """
  def create_role(attrs \\ %{}) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a role.
  """
  def update_role(%Role{} = role, attrs) do
    role
    |> Role.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a role.

  System roles cannot be deleted.
  """
  def delete_role(%Role{is_system: true}), do: {:error, :system_role}

  def delete_role(%Role{} = role) do
    Repo.delete(role)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking role changes.
  """
  def change_role(%Role{} = role, attrs \\ %{}) do
    Role.changeset(role, attrs)
  end

  # ===========================================================================
  # User Role Mappings (URM)
  # ===========================================================================

  @doc """
  Returns the list of user role mappings.
  """
  def list_user_role_mappings do
    Repo.all(UserRoleMapping)
  end

  @doc """
  Lists user role mappings for a user.
  """
  def list_urms_for_user(user_id) do
    from(urm in UserRoleMapping,
      where: urm.user_id == ^user_id,
      preload: [:role, :account]
    )
    |> Repo.all()
  end

  @doc """
  Lists user role mappings for a user in a specific account.
  """
  def list_urms_for_user_in_account(user_id, account_id) do
    from(urm in UserRoleMapping,
      where: urm.user_id == ^user_id and urm.account_id == ^account_id,
      preload: [:role]
    )
    |> Repo.all()
  end

  @doc """
  Lists user role mappings for an account.
  """
  def list_urms_for_account(account_id) do
    from(urm in UserRoleMapping,
      where: urm.account_id == ^account_id,
      preload: [:user, :role]
    )
    |> Repo.all()
  end

  @doc """
  Lists users with a specific role in an account.
  """
  def list_users_with_role(role_id, account_id) do
    from(urm in UserRoleMapping,
      where: urm.role_id == ^role_id and urm.account_id == ^account_id,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.map(& &1.user)
  end

  @doc """
  Gets a single user role mapping by ID.
  """
  def get_urm(id), do: Repo.get(UserRoleMapping, id)

  @doc """
  Gets a single user role mapping by ID.

  Raises `Ecto.NoResultsError` if the URM does not exist.
  """
  def get_urm!(id), do: Repo.get!(UserRoleMapping, id)

  @doc """
  Gets the system URM.
  """
  def get_system_urm do
    get_urm(Events.Support.Constants.system_urm_id())
  end

  @doc """
  Gets a URM by user, role, and account.
  """
  def get_urm_by_user_role_account(user_id, role_id, account_id) do
    Repo.get_by(UserRoleMapping,
      user_id: user_id,
      role_id: role_id,
      account_id: account_id
    )
  end

  @doc """
  Creates a user role mapping.
  """
  def create_urm(attrs \\ %{}) do
    %UserRoleMapping{}
    |> UserRoleMapping.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Assigns a role to a user in an account.
  """
  def assign_role(user_id, role_id, account_id, attrs \\ %{}) do
    attrs
    |> Map.put(:user_id, user_id)
    |> Map.put(:role_id, role_id)
    |> Map.put(:account_id, account_id)
    |> create_urm()
  end

  @doc """
  Updates a user role mapping.
  """
  def update_urm(%UserRoleMapping{} = urm, attrs) do
    urm
    |> UserRoleMapping.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user role mapping.
  """
  def delete_urm(%UserRoleMapping{} = urm) do
    Repo.delete(urm)
  end

  @doc """
  Removes a role from a user in an account.

  Returns `{:ok, urm}` on success, `{:error, :not_found}` if no mapping exists.
  """
  @spec remove_role(binary(), binary(), binary()) ::
          {:ok, UserRoleMapping.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def remove_role(user_id, role_id, account_id) do
    user_id
    |> get_urm_by_user_role_account(role_id, account_id)
    |> do_delete_urm()
  end

  defp do_delete_urm(nil), do: {:error, :not_found}
  defp do_delete_urm(%UserRoleMapping{} = urm), do: delete_urm(urm)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking URM changes.
  """
  def change_urm(%UserRoleMapping{} = urm, attrs \\ %{}) do
    UserRoleMapping.changeset(urm, attrs)
  end

  @doc """
  Checks if a user has a specific role in an account.
  """
  def has_role?(user_id, role_id, account_id) do
    from(urm in UserRoleMapping,
      where:
        urm.user_id == ^user_id and
          urm.role_id == ^role_id and
          urm.account_id == ^account_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets the roles a user has in an account.
  """
  def get_user_roles(user_id, account_id) do
    from(urm in UserRoleMapping,
      where: urm.user_id == ^user_id and urm.account_id == ^account_id,
      join: r in assoc(urm, :role),
      select: r
    )
    |> Repo.all()
  end
end
