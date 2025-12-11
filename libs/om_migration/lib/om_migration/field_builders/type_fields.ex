defmodule OmMigration.FieldBuilders.TypeFields do
  @moduledoc """
  Builds type classification fields for migrations.

  Type fields are used for categorizing records with hierarchical classifications.

  ## Options

  - `:only` - List of fields to include
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: `:citext`)
  - `:null` - Whether fields can be null (default: `true`)

  ## Available Fields

  - `:type` - Primary type classification
  - `:subtype` - Secondary type classification
  - `:kind` - Alternative categorization
  - `:category` - Category classification
  - `:variant` - Variant classification

  ## Examples

      create_table(:products)
      |> with_type_fields()
      |> with_type_fields(only: [:type, :subtype])
      |> with_type_fields(type: :string, null: false)
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @all_fields [:type, :subtype, :kind, :category, :variant]

  @impl true
  def default_config do
    %{
      type: :citext,
      null: true,
      fields: @all_fields
    }
  end

  @impl true
  def build(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_name, acc ->
      Token.add_field(acc, field_name, config.type,
        null: config.null,
        comment: "Type classification: #{field_name}"
      )
    end)
  end

  @impl true
  def indexes(config) do
    config.fields
    |> Enum.map(fn field -> {:"#{field}_index", [field], []} end)
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds type classification fields to a migration token.
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
