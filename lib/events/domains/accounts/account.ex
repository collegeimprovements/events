defmodule Events.Domains.Accounts.Account do
  @moduledoc """
  Schema for accounts (tenants).

  Accounts represent organizations/tenants in the multi-tenant system.
  A default account is seeded for single-tenant deployments.
  """

  @derive {Events.Protocols.Identifiable, type: :account}

  use Events.Core.Schema

  @types [:personal, :organization, :enterprise]
  @subtypes [:free, :pro, :business]
  @statuses [:active, :suspended, :deleted]

  schema "accounts" do
    field :name, :string, required: true
    field :slug, :string, required: true, format: :slug, unique: :accounts_slug_index

    type_fields()
    status_fields(values: @statuses, default: :active)
    metadata_field()
    assets_field()
    audit_fields()
    timestamps()

    has_many :memberships, Events.Domains.Accounts.Membership, expect_on_delete: :cascade
    has_many :users, through: [:memberships, :user]
    has_many :roles, Events.Domains.Accounts.Role, expect_on_delete: :cascade

    has_many :user_role_mappings, Events.Domains.Accounts.UserRoleMapping,
      expect_on_delete: :cascade
  end

  @doc """
  Creates a changeset for an account.
  """
  def changeset(account, attrs) do
    account
    |> base_changeset(attrs)
    |> unique_constraints([{:slug, []}])
  end

  @doc "Returns the list of valid types."
  def types, do: @types

  @doc "Returns the list of valid subtypes."
  def subtypes, do: @subtypes

  @doc "Returns the list of valid statuses."
  def statuses, do: @statuses
end
