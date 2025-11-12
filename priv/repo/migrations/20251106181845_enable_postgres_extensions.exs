defmodule Events.Repo.Migrations.EnablePostgresExtensions do
  use Ecto.Migration

  def up do
    # Enable CITEXT extension for case-insensitive text
    # Useful for emails, usernames, status fields, etc.
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    # Enable pg_trgm for fuzzy text search and similarity
    # Enables LIKE, ILIKE, regex performance and similarity queries
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Enable btree_gin for composite indexes with JSONB
    # Allows efficient indexes combining JSONB with other types
    execute "CREATE EXTENSION IF NOT EXISTS btree_gin"

    # Note: PostgreSQL 18+ has native gen_random_uuid(), uuidv4(), and uuidv7() functions
    # No need for uuid-ossp extension or custom UUIDv7 implementation
    # Use uuidv7() for time-ordered UUIDs, gen_random_uuid() or uuidv4() for random UUIDs
  end

  def down do
    execute "DROP EXTENSION IF EXISTS btree_gin"
    execute "DROP EXTENSION IF EXISTS pg_trgm"
    execute "DROP EXTENSION IF EXISTS citext"
  end
end
