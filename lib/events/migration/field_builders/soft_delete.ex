defmodule Events.Migration.FieldBuilders.SoftDelete do
  @moduledoc """
  Builds soft delete fields for migrations.

  Soft delete allows marking records as deleted without physically removing them.

  ## Options

  - `:track_user` - Include `deleted_by_user_id` (default: `false`)
  - `:track_role_mapping` - Include `deleted_by_user_role_mapping_id` (default: `true`)
  - `:track_reason` - Include `deletion_reason` (default: `false`)

  ## Fields

  - `:deleted_at` - Timestamp when soft deleted (always included)
  - `:deleted_by_user_role_mapping_id` - Who deleted it (when `track_role_mapping: true`)
  - `:deleted_by_user_id` - User who deleted (when `track_user: true`)
  - `:deletion_reason` - Reason for deletion (when `track_reason: true`)

  ## Examples

      create_table(:users)
      |> with_soft_delete()
      |> with_soft_delete(track_user: true, track_reason: true)
      |> with_soft_delete(track_role_mapping: false)
  """

  @behaviour Events.Migration.Behaviours.FieldBuilder

  alias Events.Migration.Token
  alias Events.Migration.Behaviours.FieldBuilder

  @impl true
  def default_config do
    %{
      track_user: false,
      track_role_mapping: true,
      track_reason: false
    }
  end

  @impl true
  def build(token, config) do
    token
    |> add_deleted_at()
    |> maybe_add_role_mapping(config)
    |> maybe_add_user_tracking(config)
    |> maybe_add_reason(config)
  end

  @impl true
  def indexes(_config) do
    [
      {:deleted_at_index, [:deleted_at], []},
      {:active_records_index, [:id], [where: "deleted_at IS NULL"]}
    ]
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp add_deleted_at(token) do
    Token.add_field(token, :deleted_at, :utc_datetime_usec,
      null: true,
      comment: "Soft delete timestamp"
    )
  end

  defp maybe_add_role_mapping(token, %{track_role_mapping: false}), do: token

  defp maybe_add_role_mapping(token, %{track_role_mapping: true}) do
    Token.add_field(token, :deleted_by_user_role_mapping_id, :binary_id,
      null: true,
      comment: "Role mapping who deleted"
    )
  end

  defp maybe_add_user_tracking(token, %{track_user: false}), do: token

  defp maybe_add_user_tracking(token, %{track_user: true}) do
    Token.add_field(token, :deleted_by_user_id, :binary_id,
      null: true,
      comment: "User who deleted"
    )
  end

  defp maybe_add_reason(token, %{track_reason: false}), do: token

  defp maybe_add_reason(token, %{track_reason: true}) do
    Token.add_field(token, :deletion_reason, :text,
      null: true,
      comment: "Reason for deletion"
    )
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds soft delete fields to a migration token.
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
