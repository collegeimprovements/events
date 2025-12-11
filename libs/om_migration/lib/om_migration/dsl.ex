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
end
