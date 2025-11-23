defmodule Events.Repo.Migration do
  @moduledoc """
  Enhanced migration DSL for Events application.

  This module provides a clean, modular architecture for database migrations
  with PostgreSQL 18 UUIDv7 support, using pattern matching and pipelines
  throughout.

  ## Architecture

  The migration system is organized into focused modules:
  - `TableBuilder` - Table creation with UUIDv7 primary keys
  - `FieldSets` - Common field set macros (name, title, status, etc.)
  - `Indexes` - Index creation with automatic naming
  - `Helpers` - Utility functions using pattern matching

  ## Usage

      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Events.Repo.Migration

        def change do
          # Enable extensions
          enable_citext()

          # Create table with UUIDv7 primary key
          create_table :users do
            # Add field sets
            name_fields(type: :citext, unique: true)
            email_field(unique: true)
            status_field()
            metadata_field()
            audit_fields(with_user: true)
            deleted_fields()
            timestamps()
          end

          # Create indexes
          name_indexes(:users)
          status_indexes(:users, partial: "deleted_at IS NULL")
          timestamp_indexes(:users, order: :desc)
          deleted_indexes(:users, active_index: true)
        end
      end

  ## Features

  - **UUIDv7 Primary Keys**: Automatic generation for PostgreSQL 18+
  - **Field Sets**: Predefined field combinations for common patterns
  - **Smart Indexes**: Automatic index creation with naming conventions
  - **Pattern Matching**: Clean option handling throughout
  - **Pipelines**: Functional composition for transformations
  - **Modular Design**: Organized into focused, reusable modules
  """

  @doc """
  Use this module to access all migration helpers.

  ## Options
  - `:only` - Import only specific modules
  - `:except` - Exclude specific modules

  ## Examples

      # Import everything
      use Events.Repo.Migration

      # Import only specific modules
      use Events.Repo.Migration, only: [:table_builder, :field_sets]

      # Exclude specific modules
      use Events.Repo.Migration, except: [:indexes]
  """
  defmacro __using__(opts \\ []) do
    modules = get_modules_to_import(opts)

    imports =
      Enum.map(modules, fn module ->
        quote do
          import unquote(module)
        end
      end)

    quote do
      use Ecto.Migration
      unquote_splicing(imports)
    end
  end

  defp get_modules_to_import(opts) do
    all_modules = [
      Events.Repo.Migration.TableBuilder,
      Events.Repo.Migration.FieldSets,
      Events.Repo.Migration.Indexes,
      Events.Repo.Migration.Helpers
    ]

    case {Keyword.get(opts, :only), Keyword.get(opts, :except)} do
      {nil, nil} ->
        all_modules

      {only, nil} when is_list(only) ->
        only
        |> Enum.map(&module_from_atom/1)
        |> Enum.filter(&(&1 in all_modules))

      {nil, except} when is_list(except) ->
        except_modules = Enum.map(except, &module_from_atom/1)
        Enum.reject(all_modules, &(&1 in except_modules))

      _ ->
        all_modules
    end
  end

  defp module_from_atom(:table_builder), do: Events.Repo.Migration.TableBuilder
  defp module_from_atom(:field_sets), do: Events.Repo.Migration.FieldSets
  defp module_from_atom(:indexes), do: Events.Repo.Migration.Indexes
  defp module_from_atom(:helpers), do: Events.Repo.Migration.Helpers
  defp module_from_atom(_), do: nil

  @doc """
  Common field macros available through FieldSets module.

  ## Field Set Macros

  - `name_fields/1` - First name, last name, display name, full name
  - `title_fields/1` - Title, subtitle, short title (with translations)
  - `status_field/1` - Status with enum values
  - `type_fields/1` - Type categorization fields
  - `metadata_field/1` - JSONB metadata storage
  - `audit_fields/1` - Created/updated by tracking
  - `deleted_fields/1` - Soft delete fields
  - `timestamps/0` - Created/updated at timestamps

  ## Examples

      # Name fields with case-insensitive text
      name_fields(type: :citext, unique: true)

      # Title with translations
      title_fields(with_translations: true, languages: [:es, :fr])

      # Status with custom values
      status_field(values: ["pending", "active", "inactive"])

      # Audit with user tracking
      audit_fields(with_user: true, with_role: true)
  """
  def field_sets_documentation, do: :ok

  @doc """
  Index creation macros with automatic naming.

  ## Index Macros

  - `name_indexes/2` - Indexes for name fields
  - `title_indexes/2` - Indexes for title fields
  - `status_indexes/2` - Indexes for status field
  - `type_indexes/2` - Indexes for type fields
  - `timestamp_indexes/2` - Indexes for timestamps
  - `deleted_indexes/2` - Indexes for soft delete
  - `metadata_index/2` - GIN index for JSONB
  - `unique_index/3` - Custom unique indexes

  ## Examples

      # Name field indexes
      name_indexes(:users, unique: true, fulltext: true)

      # Status with partial index
      status_indexes(:orders, partial: "status != 'deleted'")

      # Timestamps with descending order
      timestamp_indexes(:events, order: :desc)

      # Metadata GIN index
      metadata_index(:products, paths: ["tags", "categories"])
  """
  def indexes_documentation, do: :ok
end
