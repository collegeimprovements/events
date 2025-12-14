defmodule Events.Domains.Accounts.Membership do
  @moduledoc """
  Schema for memberships (account-user join table).

  Memberships link users to accounts in the multi-tenant system.
  A user can belong to multiple accounts (GitHub org model).
  """

  @derive {FnTypes.Protocols.Identifiable, type: :membership}

  use Events.Core.Schema

  @types [:owner, :member, :guest]
  @subtypes [:invited, :requested, :direct]
  @statuses [:active, :suspended, :removed]

  schema "memberships" do
    field :joined_at, :utc_datetime_usec

    type_fields()
    status_fields(values: @statuses, default: :active)
    metadata_field()
    assets_field()
    audit_fields()
    timestamps()

    belongs_to :account, Events.Domains.Accounts.Account, on_delete: :cascade
    belongs_to :user, Events.Domains.Accounts.User, on_delete: :cascade

    constraints do
      unique([:account_id, :user_id], name: :memberships_account_id_user_id_index)
    end
  end

  @doc """
  Creates a changeset for a membership.
  """
  def changeset(membership, attrs) do
    membership
    |> base_changeset(attrs,
      also_cast: [:account_id, :user_id],
      also_required: [:account_id, :user_id]
    )
    |> foreign_key_constraints([{:account_id, []}, {:user_id, []}])
    |> unique_constraints([{[:account_id, :user_id], []}])
    |> maybe_set_joined_at()
  end

  defp maybe_set_joined_at(changeset) do
    case get_field(changeset, :joined_at) do
      nil ->
        put_change(changeset, :joined_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))

      _existing ->
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
