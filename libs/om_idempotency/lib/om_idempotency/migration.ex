defmodule OmIdempotency.Migration do
  @moduledoc """
  Migration helpers for OmIdempotency.

  ## Usage

  Create a migration:

      mix ecto.gen.migration add_idempotency_records

  Then use the helper:

      defmodule MyApp.Repo.Migrations.AddIdempotencyRecords do
        use Ecto.Migration

        def change do
          OmIdempotency.Migration.create_table()
        end
      end
  """

  use Ecto.Migration

  @doc """
  Creates the idempotency_records table with all required columns and indexes.
  """
  def create_table(opts \\ []) do
    table_name = Keyword.get(opts, :table, :idempotency_records)

    create table(table_name, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :scope, :string

      add :state, :string, null: false, default: "pending"
      add :version, :integer, null: false, default: 1

      add :response, :map
      add :error, :map
      add :metadata, :map, default: %{}

      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :locked_until, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint on key + scope
    create unique_index(table_name, [:key, :scope], name: :idempotency_records_key_scope_index)

    # Index for cleanup queries
    create index(table_name, [:expires_at])

    # Index for recovery queries
    create index(table_name, [:state, :locked_until])
  end

  @doc """
  Drops the idempotency_records table.
  """
  def drop_table(opts \\ []) do
    table_name = Keyword.get(opts, :table, :idempotency_records)
    drop table(table_name)
  end
end
