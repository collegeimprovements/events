defmodule OmMigration do
  @moduledoc """
  Elegant migration DSL with token pattern, pipelines, and pattern matching.

  ## Philosophy

  Migrations flow through a pipeline of transformations, each adding or modifying
  the migration token. This creates a composable, testable, and elegant system.

  ## Usage

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use OmMigration

        def change do
          create_table(:users)
          |> with_identity(:name, :email)
          |> with_authentication()
          |> with_profile(:bio, :avatar)
          |> with_audit()
          |> with_soft_delete()
          |> with_timestamps()
          |> execute()
        end
      end

  ## Help

  Run `OmMigration.help()` for available commands and patterns.
  """

  alias OmMigration.{Token, Help, Executor}

  defmacro __using__(_opts) do
    quote do
      use Ecto.Migration
      import OmMigration
      import OmMigration.Pipeline
      # Don't import timestamps - use Ecto's version
      import OmMigration.DSLEnhanced, except: [timestamps: 0, timestamps: 1]
    end
  end

  @doc """
  Displays comprehensive help for the migration system.

  ## Examples

      OmMigration.help()           # General help
      OmMigration.help(:fields)    # Field helpers
      OmMigration.help(:indexes)   # Index helpers
      OmMigration.help(:examples)  # Complete examples
  """
  defdelegate help(topic \\ :general), to: Help, as: :show

  @doc """
  Creates a new table token to start the pipeline.

  ## Examples

      create_table(:users)
      |> with_uuid_primary_key()
      |> with_fields(...)
      |> execute()
  """
  def create_table(name, opts \\ []) do
    Token.new(:table, name, opts)
  end

  @doc """
  Creates an index token.

  ## Examples

      create_index(:users, [:email])
      |> unique()
      |> where("deleted_at IS NULL")
      |> execute()
  """
  def create_index(table, columns, opts \\ []) do
    Token.new(:index, table, Keyword.put(opts, :columns, columns))
  end

  @doc """
  Executes the migration token pipeline.
  """
  defdelegate execute(token), to: Executor
end
