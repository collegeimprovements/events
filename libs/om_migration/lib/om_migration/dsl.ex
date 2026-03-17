defmodule OmMigration.DSL do
  @moduledoc """
  Clean DSL for migrations with pattern matching and guards.

  Provides a declarative syntax for defining migrations that
  reads like natural language.

  > #### Prefer FieldBuilders {: .info}
  >
  > For new code, consider using the behavior-based FieldBuilders in
  > `OmMigration.FieldBuilders.*` which provide better consistency
  > and reference `OmMigration.FieldDefinitions` for type definitions.
  """

  alias OmMigration.{Token, Pipeline}

  # ============================================
  # Table DSL
  # ============================================

  @doc """
  Defines a table with a clean DSL.

  ## Examples

      table :users do
        uuid_primary_key()

        field :email, :citext, unique: true
        field :username, :citext, unique: true

        has_authentication()
        has_profile()
        has_audit()
        has_soft_delete()

        timestamps()
      end
  """
  defmacro table(name, do: block) do
    quote do
      token = Token.new(:table, unquote(name))

      # Execute the block in the context of the token
      var!(current_token, OmMigration.DSL) = token
      unquote(block)
      token = var!(current_token, OmMigration.DSL)

      # Execute the migration
      OmMigration.Executor.execute(token)
    end
  end

  @doc """
  Adds a field to the current table.
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.add_field(
          var!(current_token, OmMigration.DSL),
          unquote(name),
          unquote(type),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds fields to the current table.
  """
  defmacro fields(field_list) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.add_fields(
          var!(current_token, OmMigration.DSL),
          unquote(field_list)
        )
    end
  end

  @doc """
  Adds UUIDv7 primary key.
  """
  defmacro uuid_primary_key do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_uuid_primary_key(var!(current_token, OmMigration.DSL))
    end
  end

  @doc """
  Adds authentication fields.
  """
  defmacro has_authentication(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_authentication(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds profile fields.
  """
  defmacro has_profile(fields \\ [:bio, :avatar]) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_profile(
          var!(current_token, OmMigration.DSL),
          unquote(fields)
        )
    end
  end

  @doc """
  Adds audit fields.
  """
  defmacro has_audit(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_audit(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds soft delete fields.
  """
  defmacro has_soft_delete(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_soft_delete(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds timestamps.
  """
  defmacro timestamps(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_timestamps(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds metadata field.
  """
  defmacro has_metadata(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_metadata(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds tags field.
  """
  defmacro has_tags(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_tags(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds settings field.
  """
  defmacro has_settings(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_settings(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds status field.
  """
  defmacro has_status(opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_status(
          var!(current_token, OmMigration.DSL),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds money fields.
  """
  defmacro has_money(fields) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Pipeline.with_money(
          var!(current_token, OmMigration.DSL),
          unquote(fields)
        )
    end
  end

  @doc """
  Creates an index with a clean syntax.
  """
  defmacro index(columns, opts \\ []) do
    quote do
      table_name = var!(current_token, OmMigration.DSL).name
      index_name = OmMigration.Helpers.index_name(table_name, unquote(columns))

      var!(current_token, OmMigration.DSL) =
        Token.add_index(
          var!(current_token, OmMigration.DSL),
          index_name,
          unquote(columns),
          unquote(opts)
        )
    end
  end

  @doc """
  Creates a unique index.
  """
  defmacro unique_index(columns) do
    quote do
      table_name = var!(current_token, OmMigration.DSL).name
      index_name = OmMigration.Helpers.unique_index_name(table_name, unquote(columns))

      var!(current_token, OmMigration.DSL) =
        Token.add_index(
          var!(current_token, OmMigration.DSL),
          index_name,
          unquote(columns),
          unique: true
        )
    end
  end

  @doc """
  Adds a constraint.
  """
  defmacro constraint(name, type, opts) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.add_constraint(
          var!(current_token, OmMigration.DSL),
          unquote(name),
          unquote(type),
          unquote(opts)
        )
    end
  end

  @doc """
  Adds a check constraint.
  """
  defmacro check_constraint(name, check) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.add_constraint(
          var!(current_token, OmMigration.DSL),
          unquote(name),
          :check,
          check: unquote(check)
        )
    end
  end

  @doc """
  Adds a foreign key reference.
  """
  defmacro references(table, opts \\ []) do
    quote do
      opts = Keyword.merge([type: :binary_id], unquote(opts))
      {:references, unquote(table), opts}
    end
  end

  @doc """
  Belongs to relationship.
  """
  defmacro belongs_to(name, table, opts \\ []) do
    quote do
      field_name = :"#{unquote(name)}_id"
      ref_opts = Keyword.merge([type: :binary_id], unquote(opts))

      var!(current_token, OmMigration.DSL) =
        Token.add_field(
          var!(current_token, OmMigration.DSL),
          field_name,
          {:references, unquote(table), ref_opts},
          []
        )

      # Add index for the foreign key
      var!(current_token, OmMigration.DSL) =
        Token.add_index(
          var!(current_token, OmMigration.DSL),
          :"#{var!(current_token, OmMigration.DSL).name}_#{field_name}_index",
          [field_name],
          []
        )
    end
  end

  # ============================================
  # Alter Table DSL
  # ============================================

  @doc """
  Alters an existing table with a clean DSL.

  ## Examples

      # In up/0
      alter :users do
        add :phone, :string
        add :verified_at, :utc_datetime
        remove :legacy_field
        modify :status, :string, null: false, default: "active"
      end

      # In down/0
      alter :users do
        remove :phone
        remove :verified_at
        add :legacy_field, :string
        modify :status, :string, null: true, default: nil
      end
  """
  defmacro alter(name, do: block) do
    quote do
      token = Token.new(:alter, unquote(name))

      var!(current_token, OmMigration.DSL) = token
      unquote(block)
      token = var!(current_token, OmMigration.DSL)

      OmMigration.Executor.execute(token)
    end
  end

  @doc """
  Adds a field in an alter block.

  ## Examples

      alter :users do
        add :phone, :string, null: true
        add :role, :string, default: "user"
      end
  """
  defmacro add(name, type, opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.add_field(
          var!(current_token, OmMigration.DSL),
          unquote(name),
          unquote(type),
          unquote(opts)
        )
    end
  end

  @doc """
  Removes a field in an alter block.

  ## Examples

      alter :users do
        remove :deprecated_column
        remove :old_field
      end
  """
  defmacro remove(name) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.remove_field(
          var!(current_token, OmMigration.DSL),
          unquote(name)
        )
    end
  end

  @doc """
  Modifies an existing field in an alter block.

  ## Examples

      alter :users do
        modify :status, :string, null: false, default: "active"
        modify :amount, :decimal, precision: 12, scale: 4
      end
  """
  defmacro modify(name, type, opts \\ []) do
    quote do
      var!(current_token, OmMigration.DSL) =
        Token.modify_field(
          var!(current_token, OmMigration.DSL),
          unquote(name),
          unquote(type),
          unquote(opts)
        )
    end
  end

  # ============================================
  # Drop DSL
  # ============================================

  @doc """
  Drops a table.

  ## Options

  - `:if_exists` - Only drop if table exists (default: false)
  - `:prefix` - Schema prefix for multi-tenant setups

  ## Examples

      # Simple drop
      drop_table :users

      # With options
      drop_table :users, if_exists: true
      drop_table :users, prefix: "tenant_1"
  """
  defmacro drop_table(name, opts \\ []) do
    quote do
      token = Token.new(:drop_table, unquote(name), unquote(opts))
      OmMigration.Executor.execute(token)
    end
  end

  @doc """
  Drops an index.

  ## Examples

      drop_index :users, :users_email_index
      drop_index :users, :users_email_unique
  """
  defmacro drop_index(table, index_name, opts \\ []) do
    quote do
      token = Token.new(:drop_index, unquote(table), [{:index_name, unquote(index_name)} | unquote(opts)])
      OmMigration.Executor.execute(token)
    end
  end

  @doc """
  Drops a constraint.

  ## Examples

      drop_constraint :orders, :orders_amount_positive
      drop_constraint :users, :users_email_format
  """
  defmacro drop_constraint(table, constraint_name, opts \\ []) do
    quote do
      token = Token.new(:drop_constraint, unquote(table), [{:constraint_name, unquote(constraint_name)} | unquote(opts)])
      OmMigration.Executor.execute(token)
    end
  end

  # ============================================
  # Rename DSL
  # ============================================

  @doc """
  Renames a table.

  ## Examples

      rename_table :users, to: :accounts
      rename_table :old_name, to: :new_name
  """
  defmacro rename_table(name, opts) do
    quote do
      token = Token.new(:rename_table, unquote(name), unquote(opts))
      OmMigration.Executor.execute(token)
    end
  end

  @doc """
  Renames a column in a table.

  ## Examples

      rename_column :users, :email, to: :email_address
      rename_column :orders, :amount, to: :total_amount
  """
  defmacro rename_column(table, from, opts) do
    quote do
      token = Token.new(:rename_column, unquote(table), [{:from, unquote(from)} | unquote(opts)])
      OmMigration.Executor.execute(token)
    end
  end
end
