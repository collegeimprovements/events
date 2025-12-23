defmodule Events.Domains.Accounts.CrudExample do
  @moduledoc """
  Reference example showing how to use the Crud system in a context.

  This module demonstrates the patterns for using OmCrud (from libs/om_crud)
  to reduce boilerplate while maintaining explicit control.

  ## Quick Start

  ```elixir
  # Option 1: Use the Context macro for simple cases
  defmodule MyApp.Accounts do
    use OmCrud.Context

    crud User                                    # All CRUD functions
    crud Role, only: [:create, :fetch, :list]   # Specific functions
    crud Membership, as: :member                 # Custom resource name
  end

  # Generated functions:
  Accounts.fetch_user(id)
  Accounts.create_user(attrs)
  Accounts.list_users()
  Accounts.create_role(attrs)
  Accounts.fetch_member(id)
  ```

  ## Manual Usage

  For more control, use OmCrud functions directly:

  ```elixir
  alias OmCrud
  alias OmCrud.{Multi, Merge}

  # Simple CRUD
  OmCrud.fetch(User, id)
  OmCrud.create(User, attrs)
  OmCrud.update(user, attrs)
  OmCrud.delete(user)

  # With options
  OmCrud.create(User, attrs, changeset: :registration_changeset)
  OmCrud.fetch(User, id, preload: [:account, :memberships])

  # Transactions with Multi
  Multi.new()
  |> Multi.create(:user, User, user_attrs)
  |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
  |> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
       %{user_id: u.id, account_id: a.id, role: :owner}
     end)
  |> OmOmCrud.run()

  # PostgreSQL MERGE for upserts
  User
  |> Merge.new(users_data)
  |> Merge.match_on(:email)
  |> Merge.when_matched(:update, [:name, :updated_at])
  |> Merge.when_not_matched(:insert)
  |> OmOmCrud.run()
  ```
  """

  use OmCrud.Context

  alias Events.Domains.Accounts.{Account, User, Membership, Role}
  alias OmCrud
  alias OmCrud.{Multi, Merge}

  # ─────────────────────────────────────────────────────────────
  # Generated CRUD functions via macro
  # ─────────────────────────────────────────────────────────────

  # This generates: fetch_account/2, get_account/2, list_accounts/1,
  # account_exists?/1, create_account/2, update_account/3, delete_account/2,
  # create_all_accounts/2, update_all_accounts/3, delete_all_accounts/2
  crud(Account)

  # This generates only the specified functions
  crud(Role, only: [:create, :fetch, :list, :update, :delete])

  # ─────────────────────────────────────────────────────────────
  # Custom business logic functions
  # ─────────────────────────────────────────────────────────────

  @doc """
  Register a new user with their account.

  This is a good example of when to use Multi for
  atomic multi-step operations.
  """
  @spec register_user_with_account(map(), map()) ::
          {:ok, %{user: User.t(), account: Account.t(), membership: Membership.t()}}
          | {:error, atom(), any(), map()}
  def register_user_with_account(user_attrs, account_attrs) do
    Multi.new()
    |> Multi.create(:user, User, user_attrs, changeset: :registration_changeset)
    |> Multi.create(:account, Account, fn _results ->
      account_attrs
    end)
    |> Multi.create(:membership, Membership, fn %{user: user, account: account} ->
      %{
        user_id: user.id,
        account_id: account.id,
        type: :owner
      }
    end)
    |> OmCrud.run()
  end

  @doc """
  Deactivate a user and revoke all tokens.

  Shows Multi with mixed operations (update + delete).
  """
  @spec deactivate_user(User.t()) ::
          {:ok, %{user: User.t()}} | {:error, atom(), any(), map()}
  def deactivate_user(%User{} = user) do
    Multi.new()
    |> Multi.update(:user, user, %{status: :inactive, deactivated_at: DateTime.utc_now()})
    |> Multi.delete_all(:tokens, fn _results ->
      # This would be the query for deleting all user tokens
      import Ecto.Query
      from(t in Events.Domains.Accounts.UserToken, where: t.user_id == ^user.id)
    end)
    |> OmCrud.run()
  end

  @doc """
  Bulk upsert users by email.

  Shows Merge for PostgreSQL 15+ MERGE operations.
  """
  @spec upsert_users([map()]) :: {:ok, [User.t()]} | {:error, any()}
  def upsert_users(users_data) do
    User
    |> Merge.new(users_data)
    |> Merge.match_on(:email)
    |> Merge.when_matched(:update, [:name, :updated_at])
    |> Merge.when_not_matched(:insert)
    |> Merge.returning(true)
    |> OmCrud.run()
  end

  @doc """
  Transfer account ownership.

  Shows Multi with conditional operations.
  """
  @spec transfer_ownership(Account.t(), User.t(), User.t()) ::
          {:ok, map()} | {:error, atom(), any(), map()}
  def transfer_ownership(%Account{} = account, %User{} = from_user, %User{} = to_user) do
    Multi.new()
    # Update the old owner's membership
    |> Multi.run(:old_membership, fn _repo, _results ->
      case find_membership(account.id, from_user.id) do
        nil -> {:error, :old_owner_not_found}
        membership -> {:ok, membership}
      end
    end)
    # Demote old owner to member
    |> Multi.update(:demote, fn %{old_membership: m} -> m end, %{type: :member})
    # Find or create new owner's membership
    |> Multi.run(:new_membership, fn _repo, _results ->
      case find_membership(account.id, to_user.id) do
        nil ->
          # Create new membership - note: this is simplified for example
          # In practice you might use Crud.create here
          {:ok, %{user_id: to_user.id, account_id: account.id, type: :owner}}

        membership ->
          {:ok, membership}
      end
    end)
    # Promote new owner
    |> Multi.update(:promote, fn %{new_membership: m} -> m end, %{type: :owner})
    |> OmCrud.run()
  end

  defp find_membership(account_id, user_id) do
    import Ecto.Query

    from(m in Membership, where: m.account_id == ^account_id and m.user_id == ^user_id)
    |> Events.Core.Repo.one()
  end

  # ─────────────────────────────────────────────────────────────
  # Query-based operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Find users by criteria using Query tokens.

  Shows integration with Events.Core.Query.
  """
  @spec find_users(keyword()) :: {:ok, [User.t()]} | {:error, any()}
  def find_users(criteria) do
    alias Events.Core.Query

    query =
      User
      |> Query.new()
      |> maybe_filter_status(criteria[:status])
      |> maybe_filter_account(criteria[:account_id])
      |> Query.order_by(:inserted_at, :desc)
      |> Query.limit(criteria[:limit] || 50)

    OmCrud.run(query)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    Events.Core.Query.filter(query, :status, :eq, status)
  end

  defp maybe_filter_account(query, nil), do: query

  defp maybe_filter_account(query, account_id) do
    Events.Core.Query.filter(query, :account_id, :eq, account_id)
  end
end
