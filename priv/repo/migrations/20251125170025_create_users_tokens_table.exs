defmodule Events.Repo.Migrations.CreateUsersTokensTable do
  use OmMigration

  def change do
    create table(:users_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      # Only inserted_at - tokens are immutable
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # FK index
    create index(:users_tokens, [:user_id])

    # Token lookup
    create unique_index(:users_tokens, [:token, :context])

    # Additional indexes
    create index(:users_tokens, [:context])
    create index(:users_tokens, [:user_id, :context])
  end
end
