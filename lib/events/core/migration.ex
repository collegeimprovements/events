defmodule Events.Core.Migration do
  @moduledoc """
  Events-specific migration wrapper over OmMigration.

  This module provides a thin wrapper that delegates to `OmMigration`.

  ## Usage

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Events.Core.Migration

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

  ## Submodules

  - `OmMigration.Pipeline` - Pipeline functions
  - `OmMigration.DSLEnhanced` - Enhanced DSL
  - `OmMigration.Token` - Migration token

  ## Help

  Run `Events.Core.Migration.help()` for available commands and patterns.

  See `OmMigration` for full documentation.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Migration
      import Events.Core.Migration
      import OmMigration.Pipeline
      # Don't import timestamps - use Ecto's version
      import OmMigration.DSLEnhanced, except: [timestamps: 0, timestamps: 1]
    end
  end

  @doc """
  Displays comprehensive help for the migration system.

  ## Examples

      Events.Core.Migration.help()           # General help
      Events.Core.Migration.help(:fields)    # Field helpers
      Events.Core.Migration.help(:indexes)   # Index helpers
      Events.Core.Migration.help(:examples)  # Complete examples
  """
  defdelegate help(topic \\ :general), to: OmMigration.Help, as: :show

  @doc """
  Creates a new table token to start the pipeline.

  ## Examples

      create_table(:users)
      |> with_uuid_primary_key()
      |> with_fields(...)
      |> execute()
  """
  defdelegate create_table(name, opts \\ []), to: OmMigration

  @doc """
  Creates an index token.

  ## Examples

      create_index(:users, [:email])
      |> unique()
      |> where("deleted_at IS NULL")
      |> execute()
  """
  defdelegate create_index(table, columns, opts \\ []), to: OmMigration

  @doc """
  Executes the migration token pipeline.
  """
  defdelegate execute(token), to: OmMigration
end
