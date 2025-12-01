defmodule Events.Accounts.UserRoleMapping do
  @moduledoc """
  Schema for user role mappings (URM).

  This is the central table for RBAC - it assigns roles to users within accounts.
  The URM ID is used throughout the system for audit fields (created_by_urm_id,
  updated_by_urm_id) to track which user+role+account context performed an action.
  """

  @derive {Events.Identifiable, type: :user_role_mapping}

  use Events.Schema

  @types [:permanent, :temporary]
  @subtypes [:direct, :inherited]

  schema "user_role_mappings" do
    type_fields()
    metadata_field()
    assets_field()
    audit_fields()
    timestamps()

    belongs_to :user, Events.Accounts.User, on_delete: :cascade
    belongs_to :role, Events.Accounts.Role, on_delete: :cascade
    belongs_to :account, Events.Accounts.Account, on_delete: :cascade

    constraints do
      unique([:user_id, :role_id, :account_id],
        name: :user_role_mappings_user_id_role_id_account_id_index
      )
    end
  end

  @doc """
  Creates a changeset for a user role mapping.
  """
  def changeset(urm, attrs) do
    urm
    |> base_changeset(attrs,
      also_cast: [:user_id, :role_id, :account_id],
      also_required: [:user_id, :role_id, :account_id]
    )
    |> foreign_key_constraints([{:user_id, []}, {:role_id, []}, {:account_id, []}])
    |> unique_constraints([{[:user_id, :role_id, :account_id], []}])
  end

  @doc "Returns the list of valid types."
  def types, do: @types

  @doc "Returns the list of valid subtypes."
  def subtypes, do: @subtypes
end
