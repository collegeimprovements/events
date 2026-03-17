defmodule OmMigration.FieldBuilders.Metadata do
  @moduledoc """
  Builds metadata and settings fields for migrations.

  Metadata fields are JSONB fields for storing flexible, schema-less data.
  Includes GIN indexes for efficient querying.

  ## Options

  - `:name` - Field name (default: :metadata)
  - `:default` - Default value (default: %{})
  - `:nullable` - Allow null values (default: false)

  ## Examples

      create_table(:products)
      |> Metadata.add()                              # :metadata field
      |> Metadata.add(name: :properties)             # Custom name
      |> Metadata.add(name: :settings, default: %{theme: "light"})
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @impl true
  def default_config do
    %{
      name: :metadata,
      default: %{},
      nullable: false
    }
  end

  @impl true
  def build(token, config) do
    Token.add_field(token, config.name, :jsonb,
      default: config.default,
      null: config.nullable,
      comment: "JSONB metadata field: #{config.name}"
    )
  end

  @impl true
  def indexes(config) do
    [{:"#{config.name}_gin_index", [config.name], [using: :gin]}]
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds metadata JSONB field to a migration token.

  ## Options

  - `:name` - Field name (default: :metadata)
  - `:default` - Default value (default: %{})
  - `:nullable` - Allow null values (default: false)

  ## Examples

      Metadata.add(token)
      Metadata.add(token, name: :properties)
      Metadata.add(token, name: :settings, default: %{theme: "light"})
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
