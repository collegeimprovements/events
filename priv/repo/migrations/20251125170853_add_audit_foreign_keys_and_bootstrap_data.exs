defmodule Events.Repo.Migrations.AddAuditForeignKeysAndBootstrapData do
  use Events.Migration

  alias Events.Repo.MigrationConstants, as: C

  def up do
    # Step 1: Insert bootstrap data in dependency order
    # All inserts use the system URM ID for audit fields (self-referencing is OK since FK doesn't exist yet)

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

    # 1. Default Account
    execute """
    INSERT INTO accounts (id, name, slug, status, metadata, assets, created_by_urm_id, updated_by_urm_id, inserted_at, updated_at)
    VALUES (
      '#{C.default_account_id()}',
      'Default',
      'default',
      'active',
      '{}',
      '{}',
      '#{C.system_urm_id()}',
      '#{C.system_urm_id()}',
      '#{now}',
      '#{now}'
    )
    ON CONFLICT (id) DO NOTHING
    """

    # 2. System User (no password - cannot login)
    execute """
    INSERT INTO users (id, email, username, status, metadata, assets, created_by_urm_id, updated_by_urm_id, inserted_at, updated_at)
    VALUES (
      '#{C.system_user_id()}',
      'system@localhost',
      'system',
      'active',
      '{}',
      '{}',
      '#{C.system_urm_id()}',
      '#{C.system_urm_id()}',
      '#{now}',
      '#{now}'
    )
    ON CONFLICT (id) DO NOTHING
    """

    # 3. System Membership (links system user to default account)
    execute """
    INSERT INTO memberships (id, account_id, user_id, status, joined_at, metadata, assets, created_by_urm_id, updated_by_urm_id, inserted_at, updated_at)
    VALUES (
      uuidv7(),
      '#{C.default_account_id()}',
      '#{C.system_user_id()}',
      'active',
      '#{now}',
      '{}',
      '{}',
      '#{C.system_urm_id()}',
      '#{C.system_urm_id()}',
      '#{now}',
      '#{now}'
    )
    ON CONFLICT (account_id, user_id) DO NOTHING
    """

    # 4. System Role (super_admin)
    execute """
    INSERT INTO roles (id, account_id, name, slug, description, permissions, status, is_system, metadata, assets, created_by_urm_id, updated_by_urm_id, inserted_at, updated_at)
    VALUES (
      '#{C.system_role_id()}',
      '#{C.default_account_id()}',
      'Super Admin',
      'super_admin',
      'System administrator with full access',
      '{"*": true}',
      'active',
      true,
      '{}',
      '{}',
      '#{C.system_urm_id()}',
      '#{C.system_urm_id()}',
      '#{now}',
      '#{now}'
    )
    ON CONFLICT (id) DO NOTHING
    """

    # 5. System URM (the key reference for all audit fields)
    execute """
    INSERT INTO user_role_mappings (id, user_id, role_id, account_id, metadata, assets, created_by_urm_id, updated_by_urm_id, inserted_at, updated_at)
    VALUES (
      '#{C.system_urm_id()}',
      '#{C.system_user_id()}',
      '#{C.system_role_id()}',
      '#{C.default_account_id()}',
      '{}',
      '{}',
      '#{C.system_urm_id()}',
      '#{C.system_urm_id()}',
      '#{now}',
      '#{now}'
    )
    ON CONFLICT (id) DO NOTHING
    """

    # Step 2: Add FK constraints for audit fields (now that bootstrap data exists)
    # Using DEFERRABLE INITIALLY DEFERRED allows batch inserts within transactions

    # accounts.created_by_urm_id -> user_role_mappings
    execute """
    ALTER TABLE accounts
    ADD CONSTRAINT accounts_created_by_urm_id_fkey
    FOREIGN KEY (created_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    execute """
    ALTER TABLE accounts
    ADD CONSTRAINT accounts_updated_by_urm_id_fkey
    FOREIGN KEY (updated_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    # users.created_by_urm_id -> user_role_mappings
    execute """
    ALTER TABLE users
    ADD CONSTRAINT users_created_by_urm_id_fkey
    FOREIGN KEY (created_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    execute """
    ALTER TABLE users
    ADD CONSTRAINT users_updated_by_urm_id_fkey
    FOREIGN KEY (updated_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    # memberships.created_by_urm_id -> user_role_mappings
    execute """
    ALTER TABLE memberships
    ADD CONSTRAINT memberships_created_by_urm_id_fkey
    FOREIGN KEY (created_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    execute """
    ALTER TABLE memberships
    ADD CONSTRAINT memberships_updated_by_urm_id_fkey
    FOREIGN KEY (updated_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    # roles.created_by_urm_id -> user_role_mappings
    execute """
    ALTER TABLE roles
    ADD CONSTRAINT roles_created_by_urm_id_fkey
    FOREIGN KEY (created_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    execute """
    ALTER TABLE roles
    ADD CONSTRAINT roles_updated_by_urm_id_fkey
    FOREIGN KEY (updated_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    # user_role_mappings.created_by_urm_id -> user_role_mappings (self-referencing)
    execute """
    ALTER TABLE user_role_mappings
    ADD CONSTRAINT user_role_mappings_created_by_urm_id_fkey
    FOREIGN KEY (created_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    execute """
    ALTER TABLE user_role_mappings
    ADD CONSTRAINT user_role_mappings_updated_by_urm_id_fkey
    FOREIGN KEY (updated_by_urm_id) REFERENCES user_role_mappings(id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
    """

    # errors table audit fields (if it exists and has these columns)
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'errors' AND column_name = 'created_by_urm_id') THEN
        ALTER TABLE errors
        ADD CONSTRAINT errors_created_by_urm_id_fkey
        FOREIGN KEY (created_by_urm_id) REFERENCES user_role_mappings(id)
        ON DELETE SET NULL
        DEFERRABLE INITIALLY DEFERRED;
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'errors' AND column_name = 'updated_by_urm_id') THEN
        ALTER TABLE errors
        ADD CONSTRAINT errors_updated_by_urm_id_fkey
        FOREIGN KEY (updated_by_urm_id) REFERENCES user_role_mappings(id)
        ON DELETE SET NULL
        DEFERRABLE INITIALLY DEFERRED;
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'errors' AND column_name = 'resolved_by_urm_id') THEN
        ALTER TABLE errors
        ADD CONSTRAINT errors_resolved_by_urm_id_fkey
        FOREIGN KEY (resolved_by_urm_id) REFERENCES user_role_mappings(id)
        ON DELETE SET NULL
        DEFERRABLE INITIALLY DEFERRED;
      END IF;
    END $$;
    """
  end

  def down do
    # Step 1: Drop FK constraints first

    execute "ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_created_by_urm_id_fkey"
    execute "ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_updated_by_urm_id_fkey"
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_created_by_urm_id_fkey"
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_updated_by_urm_id_fkey"
    execute "ALTER TABLE memberships DROP CONSTRAINT IF EXISTS memberships_created_by_urm_id_fkey"
    execute "ALTER TABLE memberships DROP CONSTRAINT IF EXISTS memberships_updated_by_urm_id_fkey"
    execute "ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_created_by_urm_id_fkey"
    execute "ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_updated_by_urm_id_fkey"

    execute "ALTER TABLE user_role_mappings DROP CONSTRAINT IF EXISTS user_role_mappings_created_by_urm_id_fkey"

    execute "ALTER TABLE user_role_mappings DROP CONSTRAINT IF EXISTS user_role_mappings_updated_by_urm_id_fkey"

    execute "ALTER TABLE errors DROP CONSTRAINT IF EXISTS errors_created_by_urm_id_fkey"
    execute "ALTER TABLE errors DROP CONSTRAINT IF EXISTS errors_updated_by_urm_id_fkey"
    execute "ALTER TABLE errors DROP CONSTRAINT IF EXISTS errors_resolved_by_urm_id_fkey"

    # Step 2: Delete bootstrap data in reverse dependency order
    execute "DELETE FROM user_role_mappings WHERE id = '#{C.system_urm_id()}'"
    execute "DELETE FROM roles WHERE id = '#{C.system_role_id()}'"

    execute "DELETE FROM memberships WHERE account_id = '#{C.default_account_id()}' AND user_id = '#{C.system_user_id()}'"

    execute "DELETE FROM users WHERE id = '#{C.system_user_id()}'"
    execute "DELETE FROM accounts WHERE id = '#{C.default_account_id()}'"
  end
end
