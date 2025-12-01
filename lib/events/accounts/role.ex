defmodule Events.Accounts.Role do
  @moduledoc """
  Schema for roles.

  Roles can be:
  - Account-specific (account_id set) - custom roles for an account
  - Global (account_id nil) - available across all accounts

  System roles (is_system: true) cannot be deleted.
  """

  @derive {Events.Protocols.Identifiable, type: :role}

  use Events.Core.Schema

  @types [:system, :custom]
  @subtypes [:global, :account_specific]
  @statuses [:active, :disabled]

  schema "roles" do
    field :name, :string, required: true
    field :slug, :string, required: true, format: :slug, unique: :roles_slug_index
    field :description, :string
    field :permissions, :map, default: %{}
    field :is_system, :boolean, default: false

    type_fields()
    status_fields(values: @statuses, default: :active)
    metadata_field()
    assets_field()
    audit_fields()
    timestamps()

    belongs_to :account, Events.Accounts.Account, on_delete: :cascade
    has_many :user_role_mappings, Events.Accounts.UserRoleMapping, expect_on_delete: :cascade

    constraints do
      unique([:account_id, :name], name: :roles_account_id_name_index)
    end
  end

  @doc """
  Creates a changeset for a role.
  """
  def changeset(role, attrs) do
    role
    |> base_changeset(attrs, also_cast: [:account_id])
    |> foreign_key_constraints([{:account_id, []}])
    |> unique_constraints([{:slug, []}, {[:account_id, :name], []}])
  end

  @doc "Returns the list of valid types."
  def types, do: @types

  @doc "Returns the list of valid subtypes."
  def subtypes, do: @subtypes

  @doc "Returns the list of valid statuses."
  def statuses, do: @statuses
end
