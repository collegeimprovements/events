defmodule OmMigration.FieldBuilders.Timestamps do
  @moduledoc """
  Builds timestamp fields for migrations.

  ## Options

  - `:only` - List of fields to include (default: `[:inserted_at, :updated_at]`)
  - `:except` - List of fields to exclude
  - `:type` - Timestamp type (default: `:utc_datetime_usec`)
  - `:null` - Whether fields can be null (default: `false`)
  - `:with_deleted` - Include `deleted_at` field (default: `false`)
  - `:with_lifecycle` - Include lifecycle timestamps (default: `false`)

  ## Examples

      create_table(:users)
      |> with_timestamps()
      |> with_timestamps(only: [:inserted_at])
      |> with_timestamps(with_deleted: true)
      |> with_timestamps(with_lifecycle: true)
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @base_fields [:inserted_at, :updated_at]
  @lifecycle_fields [:published_at, :archived_at, :expires_at]

  @impl true
  def default_config do
    %{
      type: :utc_datetime_usec,
      null: false,
      with_deleted: false,
      with_lifecycle: false,
      fields: @base_fields
    }
  end

  @impl true
  def build(token, config) do
    token
    |> add_base_timestamps(config)
    |> maybe_add_deleted(config)
    |> maybe_add_lifecycle(config)
  end

  @impl true
  def indexes(config) do
    config.fields
    |> Enum.map(fn field -> {:"#{field}_index", [field], []} end)
    |> maybe_add_deleted_indexes(config)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp add_base_timestamps(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_name, acc ->
      Token.add_field(acc, field_name, config.type,
        null: config.null,
        comment: "Timestamp: #{field_name}"
      )
    end)
  end

  defp maybe_add_deleted(token, %{with_deleted: false}), do: token

  defp maybe_add_deleted(token, %{with_deleted: true, type: type}) do
    Token.add_field(token, :deleted_at, type,
      null: true,
      comment: "Soft delete timestamp"
    )
  end

  defp maybe_add_lifecycle(token, %{with_lifecycle: false}), do: token

  defp maybe_add_lifecycle(token, %{with_lifecycle: true, type: type}) do
    @lifecycle_fields
    |> Enum.reduce(token, fn field, acc ->
      Token.add_field(acc, field, type,
        null: true,
        comment: "Lifecycle timestamp: #{field}"
      )
    end)
  end

  defp maybe_add_deleted_indexes(indexes, %{with_deleted: false}), do: indexes

  defp maybe_add_deleted_indexes(indexes, %{with_deleted: true}) do
    [
      {:deleted_at_index, [:deleted_at], []},
      {:active_records_index, [:id], [where: "deleted_at IS NULL"]}
      | indexes
    ]
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds timestamp fields to a migration token.

  This is a convenience wrapper around `FieldBuilder.apply/3`.
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
