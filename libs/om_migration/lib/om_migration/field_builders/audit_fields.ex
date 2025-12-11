defmodule OmMigration.FieldBuilders.AuditFields do
  @moduledoc """
  Builds audit tracking fields for migrations.

  Audit fields track who created and modified records via User Role Mapping IDs.

  ## Options

  - `:only` - List of fields to include
  - `:except` - List of fields to exclude
  - `:track_user` - Include direct user ID tracking (default: `false`)
  - `:track_ip` - Include IP address tracking (default: `false`)
  - `:track_session` - Include session tracking (default: `false`)
  - `:track_changes` - Include change history (default: `false`)

  ## Base Fields (always added)

  - `:created_by_urm_id` - Creator via user role mapping (binary_id)
  - `:updated_by_urm_id` - Last updater via user role mapping (binary_id)

  ## User Tracking Fields (when `track_user: true`)

  - `:created_by_user_id` - Creator user UUID
  - `:updated_by_user_id` - Last updater user UUID

  ## IP Tracking Fields (when `track_ip: true`)

  - `:created_from_ip` - IP address at creation
  - `:updated_from_ip` - IP address at last update

  ## Session Tracking Fields (when `track_session: true`)

  - `:created_session_id` - Session ID at creation
  - `:updated_session_id` - Session ID at last update

  ## Change Tracking Fields (when `track_changes: true`)

  - `:change_history` - JSONB array of changes
  - `:version` - Version counter

  ## Examples

      create_table(:documents)
      |> with_audit_fields()
      |> with_audit_fields(track_user: true, track_ip: true)
      |> with_audit_fields(track_changes: true)
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder
  alias OmFieldNames

  @impl true
  def default_config do
    %{
      track_user: false,
      track_ip: false,
      track_session: false,
      track_changes: false,
      fields: OmFieldNames.audit_fields()
    }
  end

  @impl true
  def build(token, config) do
    token
    |> add_base_fields(config)
    |> maybe_add_user_tracking(config)
    |> maybe_add_ip_tracking(config)
    |> maybe_add_session_tracking(config)
    |> maybe_add_change_tracking(config)
  end

  @impl true
  def indexes(config) do
    []
    |> maybe_add_user_indexes(config)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp add_base_fields(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_name, acc ->
      Token.add_field(acc, field_name, :binary_id,
        null: true,
        comment: "Audit: #{field_name}"
      )
    end)
  end

  defp maybe_add_user_tracking(token, %{track_user: false}), do: token

  defp maybe_add_user_tracking(token, %{track_user: true}) do
    token
    |> Token.add_field(:created_by_user_id, :binary_id, null: true, comment: "Creator user ID")
    |> Token.add_field(:updated_by_user_id, :binary_id, null: true, comment: "Last updater user ID")
  end

  defp maybe_add_ip_tracking(token, %{track_ip: false}), do: token

  defp maybe_add_ip_tracking(token, %{track_ip: true}) do
    token
    |> Token.add_field(:created_from_ip, :inet, null: true, comment: "IP at creation")
    |> Token.add_field(:updated_from_ip, :inet, null: true, comment: "IP at last update")
  end

  defp maybe_add_session_tracking(token, %{track_session: false}), do: token

  defp maybe_add_session_tracking(token, %{track_session: true}) do
    token
    |> Token.add_field(:created_session_id, :string, null: true, comment: "Session ID at creation")
    |> Token.add_field(:updated_session_id, :string,
      null: true,
      comment: "Session ID at last update"
    )
  end

  defp maybe_add_change_tracking(token, %{track_changes: false}), do: token

  defp maybe_add_change_tracking(token, %{track_changes: true}) do
    token
    |> Token.add_field(:change_history, :jsonb,
      default: [],
      null: false,
      comment: "History of changes"
    )
    |> Token.add_field(:version, :integer,
      default: 1,
      null: false,
      comment: "Version counter"
    )
  end

  defp maybe_add_user_indexes(indexes, %{track_user: false}), do: indexes

  defp maybe_add_user_indexes(indexes, %{track_user: true}) do
    [
      {:created_by_user_index, [:created_by_user_id], []},
      {:updated_by_user_index, [:updated_by_user_id], []}
      | indexes
    ]
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds audit tracking fields to a migration token.
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
