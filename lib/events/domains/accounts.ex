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

  Returns `nil` if not found. For result tuple, use `fetch_account/1`.
  """
  def get_account(id), do: Repo.get(Account, id)

  @doc """
  Fetches a single account by ID.

  Returns `{:ok, account}` if found, `{:error, :not_found}` otherwise.
  """
  @spec fetch_account(binary()) :: {:ok, Account.t()} | {:error, :not_found}
  def fetch_account(id) do
    case Repo.get(Account, id) do
      %Account{} = account -> {:ok, account}
      nil -> {:error, :not_found}
    end
  end

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
    get_account(Events.Constants.default_account_id())
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

  Returns `nil` if not found. For result tuple, use `fetch_user/1`.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Fetches a single user by ID.

  Returns `{:ok, user}` if found, `{:error, :not_found}` otherwise.
  """
  @spec fetch_user(binary()) :: {:ok, User.t()} | {:error, :not_found}
  def fetch_user(id) do
    case Repo.get(User, id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

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

  Returns `{:ok, user}` if found and password is valid, `{:error, :invalid_credentials}` otherwise.
  """
  @spec get_user_by_email_and_password(binary(), binary()) ::
          {:ok, User.t()} | {:error, :invalid_credentials}
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    with %User{} = user <- get_user_by_email(email),
         true <- User.valid_password?(user, password) do
      {:ok, user}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  @doc """
  Gets the system user.
  """
  def get_system_user do
    get_user(Events.Constants.system_user_id())
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

  Returns `{:ok, user}` if token is valid, `{:error, :invalid_token}` otherwise.
  """
  @spec get_user_by_reset_password_token(binary()) :: {:ok, User.t()} | {:error, :invalid_token}
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
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
  # Security & Login Tracking
  # ===========================================================================

  @doc """
  Authenticates a user with lockout protection.

  Checks if user is locked, verifies password, and records success/failure.
  Returns `{:ok, user}` on success with updated login tracking fields.

  ## Options

  - `:ip_address` - IP address of the login attempt (stored on success)

  ## Return Values

  - `{:ok, user}` - Successful login, user returned with updated tracking
  - `{:error, :account_locked}` - Account is locked due to failed attempts
  - `{:error, :invalid_credentials}` - Email not found or password incorrect
  """
  @spec authenticate_user(String.t(), String.t(), keyword()) ::
          {:ok, User.t()} | {:error, :account_locked | :invalid_credentials}
  def authenticate_user(email, password, opts \\ []) when is_binary(email) and is_binary(password) do
    ip_address = Keyword.get(opts, :ip_address)

    case get_user_by_email(email) do
      nil ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      %User{} = user ->
        do_authenticate_user(user, password, ip_address)
    end
  end

  defp do_authenticate_user(user, password, ip_address) do
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

  @doc """
  Records a successful login attempt.

  Updates login tracking fields and clears any lockout state.
  """
  @spec record_login_success(User.t(), String.t() | nil) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def record_login_success(user, ip_address \\ nil) do
    user
    |> User.login_success_changeset(ip_address)
    |> Repo.update()
  end

  @doc """
  Records a failed login attempt.

  Increments failed attempts counter and may lock the account.
  """
  @spec record_login_failure(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def record_login_failure(user) do
    user
    |> User.login_failure_changeset()
    |> Repo.update()
  end

  @doc """
  Manually unlocks a user account.
  """
  @spec unlock_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def unlock_user(user) do
    user
    |> User.unlock_changeset()
    |> Repo.update()
  end

  @doc """
  Checks if a user account is currently locked.
  """
  @spec user_locked?(User.t()) :: boolean()
  def user_locked?(user), do: User.locked?(user)

  # ===========================================================================
  # User Defaults
  # ===========================================================================

  @doc """
  Sets the user's default account and role.

  ## Examples

      set_user_defaults(user, account_id, role_id)
      set_user_defaults(user, account_id, nil)  # Only set account
  """
  @spec set_user_defaults(User.t(), binary() | nil, binary() | nil) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def set_user_defaults(user, account_id, role_id) do
    user
    |> User.defaults_changeset(%{default_account_id: account_id, default_role_id: role_id})
    |> Repo.update()
  end

  @doc """
  Gets the user's default account and role with preloads.

  Returns a map with `:account` and `:role` keys, each may be `nil`.
  """
  @spec get_user_defaults(User.t()) :: %{account: Account.t() | nil, role: Role.t() | nil}
  def get_user_defaults(user) do
    user = Repo.preload(user, [:default_account, :default_role])
    %{account: user.default_account, role: user.default_role}
  end

  @doc """
  Gets a user with their defaults preloaded.
  """
  @spec get_user_with_defaults(binary()) :: User.t() | nil
  def get_user_with_defaults(id) do
    User
    |> Repo.get(id)
    |> Repo.preload([:default_account, :default_role])
  end

  @doc """
  Fetches a user with their defaults preloaded.

  Returns `{:ok, user}` if found, `{:error, :not_found}` otherwise.
  """
  @spec fetch_user_with_defaults(binary()) :: {:ok, User.t()} | {:error, :not_found}
  def fetch_user_with_defaults(id) do
    case get_user_with_defaults(id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
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

  Returns `nil` if not found. For result tuple, use `fetch_membership/1`.
  """
  def get_membership(id), do: Repo.get(Membership, id)

  @doc """
  Fetches a single membership by ID.

  Returns `{:ok, membership}` if found, `{:error, :not_found}` otherwise.
  """
  @spec fetch_membership(binary()) :: {:ok, Membership.t()} | {:error, :not_found}
  def fetch_membership(id) do
    case Repo.get(Membership, id) do
      %Membership{} = membership -> {:ok, membership}
      nil -> {:error, :not_found}
    end
  end

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

  Returns `nil` if not found. For result tuple, use `fetch_role/1`.
  """
  def get_role(id), do: Repo.get(Role, id)

  @doc """
  Fetches a single role by ID.

  Returns `{:ok, role}` if found, `{:error, :not_found}` otherwise.
  """
  @spec fetch_role(binary()) :: {:ok, Role.t()} | {:error, :not_found}
  def fetch_role(id) do
    case Repo.get(Role, id) do
      %Role{} = role -> {:ok, role}
      nil -> {:error, :not_found}
    end
  end

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
    get_role(Events.Constants.system_role_id())
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

  Returns `nil` if not found. For result tuple, use `fetch_urm/1`.
  """
  def get_urm(id), do: Repo.get(UserRoleMapping, id)

  @doc """
  Fetches a single user role mapping by ID.

  Returns `{:ok, urm}` if found, `{:error, :not_found}` otherwise.
  """
  @spec fetch_urm(binary()) :: {:ok, UserRoleMapping.t()} | {:error, :not_found}
  def fetch_urm(id) do
    case Repo.get(UserRoleMapping, id) do
      %UserRoleMapping{} = urm -> {:ok, urm}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a single user role mapping by ID.

  Raises `Ecto.NoResultsError` if the URM does not exist.
  """
  def get_urm!(id), do: Repo.get!(UserRoleMapping, id)

  @doc """
  Gets the system URM.
  """
  def get_system_urm do
    get_urm(Events.Constants.system_urm_id())
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
