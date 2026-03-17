defmodule OmMigration.FieldBuilders.Tags do
  @moduledoc """
  Builds tags/categories array fields for migrations.

  Tags fields are string arrays with GIN indexes for efficient array operations.

  ## Options

  - `:name` - Field name (default: :tags)
  - `:default` - Default value (default: [])
  - `:nullable` - Allow null values (default: false)

  ## Examples

      create_table(:posts)
      |> Tags.add()                        # :tags field
      |> Tags.add(name: :categories)       # Custom name
      |> Tags.add(name: :labels, default: ["unlabeled"])
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @impl true
  def default_config do
    %{
      name: :tags,
      default: [],
      nullable: false
    }
  end

  @impl true
  def build(token, config) do
    Token.add_field(token, config.name, {:array, :string},
      default: config.default,
      null: config.nullable,
      comment: "Tags array field: #{config.name}"
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
  Adds tags array field to a migration token.

  ## Options

  - `:name` - Field name (default: :tags)
  - `:default` - Default value (default: [])
  - `:nullable` - Allow null values (default: false)

  ## Examples

      Tags.add(token)
      Tags.add(token, name: :categories)
      Tags.add(token, name: :labels, default: ["unlabeled"])
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
