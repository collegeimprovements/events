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
          |> run()
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
      # Import DSL for alter, drop, rename macros
      import OmMigration.DSL
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
      |> run()
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
      |> run()
  """
  def create_index(table, columns, opts \\ []) do
    Token.new(:index, table, Keyword.put(opts, :columns, columns))
  end

  @doc """
  Executes the migration token pipeline.

  Named `run/1` to avoid conflict with `Ecto.Migration.execute/1`.
  """
  defdelegate run(token), to: Executor, as: :execute

  # ============================================
  # Alter Table
  # ============================================

  @doc """
  Creates an alter table token to modify an existing table.

  ## Examples

      alter_table(:users)
      |> add_field(:phone, :string)
      |> remove_field(:legacy_column)
      |> modify_field(:status, :string, null: false)
      |> run()
  """
  def alter_table(name, opts \\ []) do
    Token.new(:alter, name, opts)
  end

  @doc """
  Adds a field to an alter token. Use with `alter_table/2`.

  ## Examples

      alter_table(:users)
      |> add_field(:phone, :string, null: true)
      |> run()
  """
  def add_field(token, name, type, opts \\ []) do
    Token.add_field(token, name, type, opts)
  end

  @doc """
  Removes a field from a table. Use with `alter_table/2`.

  ## Examples

      alter_table(:users)
      |> remove_field(:deprecated_column)
      |> run()
  """
  def remove_field(token, name) do
    Token.remove_field(token, name)
  end

  @doc """
  Modifies an existing field. Use with `alter_table/2`.

  ## Examples

      alter_table(:users)
      |> modify_field(:status, :string, null: false, default: "active")
      |> run()
  """
  def modify_field(token, name, type, opts \\ []) do
    Token.modify_field(token, name, type, opts)
  end

  # ============================================
  # Drop Operations
  # ============================================

  @doc """
  Creates a drop table token.

  ## Options

  - `:if_exists` - Only drop if table exists (default: false)
  - `:prefix` - Schema prefix for multi-tenant setups

  ## Examples

      # In down/0 function
      drop_table(:users)
      |> run()

      # With options
      drop_table(:users, if_exists: true)
      |> run()
  """
  def drop_table(name, opts \\ []) do
    Token.new(:drop_table, name, opts)
  end

  @doc """
  Creates a drop index token.

  ## Examples

      # In down/0 function
      drop_index(:users, :users_email_index)
      |> run()
  """
  def drop_index(table, index_name, opts \\ []) do
    Token.new(:drop_index, table, Keyword.put(opts, :index_name, index_name))
  end

  @doc """
  Creates a drop constraint token.

  ## Examples

      drop_constraint(:orders, :orders_amount_positive)
      |> run()
  """
  def drop_constraint(table, constraint_name, opts \\ []) do
    Token.new(:drop_constraint, table, Keyword.put(opts, :constraint_name, constraint_name))
  end

  # ============================================
  # Rename Operations
  # ============================================

  @doc """
  Creates a rename table token.

  ## Examples

      rename_table(:users, to: :accounts)
      |> run()
  """
  def rename_table(name, opts) do
    Token.new(:rename_table, name, opts)
  end

  @doc """
  Creates a rename column token.

  ## Examples

      rename_column(:users, from: :email, to: :email_address)
      |> run()
  """
  def rename_column(table, opts) do
    Token.new(:rename_column, table, opts)
  end
end
