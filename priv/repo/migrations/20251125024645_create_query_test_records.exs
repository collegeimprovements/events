defmodule Events.Repo.Migrations.CreateQueryTestRecords do
  use Ecto.Migration

  @doc """
  Creates a simple test table for Query execution tests.
  This table is used only for testing query execution, pagination,
  streaming, and batch operations.
  """
  def change do
    create table(:query_test_records, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :priority, :integer, null: false, default: 0
      add :score, :float
      add :active, :boolean, default: true
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:query_test_records, [:status])
    create index(:query_test_records, [:priority])
    create index(:query_test_records, [:inserted_at])
    create index(:query_test_records, [:status, :priority])
  end
end
