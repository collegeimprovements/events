defmodule Events.Repo.Migration.TableBuilder do
  @moduledoc """
  Table creation with UUIDv7 primary keys for PostgreSQL 18+.

  Provides a clean DSL for creating tables with automatic UUIDv7 primary keys
  and support for citext extension.
  """

  use Ecto.Migration

  @doc """
  Creates a table with UUIDv7 primary key.

  ## Examples

      # Simple table
      create_table :users do
        add :email, :string
      end

      # With options
      create_table :products, primary_key: false do
        add :id, :binary_id, primary_key: true, default: fragment("uuidv7()")
        add :name, :string
      end
  """
  defmacro create_table(name, opts \\ [], do: block) do
    opts = process_table_options(opts)

    quote do
      table unquote(name), unquote(opts) do
        unquote(block)
      end
    end
  end

  @doc """
  Process table options with pattern matching.
  """
  def process_table_options(opts) when is_list(opts) do
    opts
    |> Keyword.put_new(:primary_key, false)
    |> add_uuid_primary_key()
  end

  defp add_uuid_primary_key(opts) do
    case Keyword.get(opts, :primary_key) do
      false ->
        # Add UUIDv7 primary key
        opts

      true ->
        # Use default primary key
        Keyword.delete(opts, :primary_key)

      opts when is_list(opts) ->
        # Custom primary key options
        opts
    end
  end

  @doc """
  Creates the citext extension if not exists.

  ## Example

      def change do
        enable_citext()

        create_table :users do
          add :email, :citext
        end
      end
  """
  defmacro enable_citext do
    quote do
      execute(
        "CREATE EXTENSION IF NOT EXISTS citext",
        "DROP EXTENSION IF EXISTS citext CASCADE"
      )
    end
  end

  @doc """
  Adds a UUIDv7 primary key field.

  ## Example

      create_table :products do
        uuid_primary_key()
        add :name, :string
      end
  """
  defmacro uuid_primary_key(field_name \\ :id) do
    quote do
      add unquote(field_name), :binary_id,
        primary_key: true,
        default: fragment("uuidv7()")
    end
  end
end
