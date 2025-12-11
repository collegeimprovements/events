defmodule OmSchema.Constraints do
  @moduledoc """
  DSL for declaring database constraints in Ecto schemas.

  This module provides macros to declare unique constraints, foreign keys,
  check constraints, and indexes directly in your schema definition. These
  declarations are used by `OmSchema.DatabaseValidator` to validate
  that your schemas match the actual database structure.

  ## Usage

  ### Field-Level Constraints (Simple Cases)

  ```elixir
  schema "users" do
    field :email, :string, unique: true
    field :username, :string, unique: :users_username_index
    field :age, :integer, check: :users_age_positive
  end
  ```

  ### Constraints Block (Complex Cases)

  ```elixir
  schema "user_role_mappings" do
    belongs_to :user, User
    belongs_to :role, Role
    belongs_to :account, Account

    constraints do
      # Composite unique
      unique [:user_id, :role_id, :account_id],
        name: :user_role_mappings_user_role_account_idx

      # Foreign keys with options
      foreign_key :user_id,
        references: :users,
        on_delete: :cascade

      # Check constraint with expression
      check :valid_dates,
        expr: "started_at IS NULL OR ended_at IS NULL OR started_at < ended_at"
    end
  end
  ```

  ## Constraint Types

  ### Unique Constraints

  - Field-level: `field :email, :string, unique: true`
  - Field-level with name: `field :email, :string, unique: :custom_index_name`
  - Field-level with options: `field :email, :string, unique: [name: :idx, where: "..."]`
  - Block-level composite: `unique [:field1, :field2], name: :composite_idx`

  ### Foreign Key Constraints

  Enhanced `belongs_to` captures FK metadata:

  ```elixir
  belongs_to :account, Account,
    constraint: [on_delete: :cascade, deferrable: :initially_deferred]
  ```

  Or declare explicitly in constraints block:

  ```elixir
  constraints do
    foreign_key :account_id, references: :accounts, on_delete: :cascade
  end
  ```

  ### Check Constraints

  - Field-level: `field :age, :integer, check: :users_age_positive`
  - Block-level: `check :valid_dates, expr: "start < end"`

  ## Introspection

  After schema compilation, the following functions are generated:

  - `__constraints__/0` - Returns all constraint metadata
  - `__indexes__/0` - Returns all index metadata
  - `constraints/0` - Public alias for `__constraints__/0`
  - `indexes/0` - Public alias for `__indexes__/0`
  - `foreign_keys/0` - Returns FK constraint details
  - `unique_constraints/0` - Returns unique constraint details
  - `check_constraints/0` - Returns check constraint details
  """

  @doc """
  Defines a constraints block for complex constraint declarations.

  Use this for composite unique constraints, explicit foreign key options,
  check constraints with expressions, and indexes.

  ## Example

      constraints do
        unique [:user_id, :role_id], name: :user_role_unique_idx
        foreign_key :account_id, references: :accounts, on_delete: :cascade
        check :positive_balance, expr: "balance >= 0"
      end
  """
  defmacro constraints(do: block) do
    quote do
      # Initialize constraint accumulators if not present
      unless Module.has_attribute?(__MODULE__, :constraint_unique) do
        Module.register_attribute(__MODULE__, :constraint_unique, accumulate: true)
      end

      unless Module.has_attribute?(__MODULE__, :constraint_foreign_key) do
        Module.register_attribute(__MODULE__, :constraint_foreign_key, accumulate: true)
      end

      unless Module.has_attribute?(__MODULE__, :constraint_check) do
        Module.register_attribute(__MODULE__, :constraint_check, accumulate: true)
      end

      unless Module.has_attribute?(__MODULE__, :constraint_index) do
        Module.register_attribute(__MODULE__, :constraint_index, accumulate: true)
      end

      unless Module.has_attribute?(__MODULE__, :constraint_exclude) do
        Module.register_attribute(__MODULE__, :constraint_exclude, accumulate: true)
      end

      # Import constraint macros for the block
      import OmSchema.Constraints,
        only: [unique: 2, foreign_key: 2, check: 1, check: 2, index: 1, index: 2, exclude: 2]

      unquote(block)
    end
  end

  @doc """
  Declares a unique constraint within a constraints block.

  ## Examples

      # Single field unique (alternative to field-level)
      unique :email, name: :users_email_index

      # Composite unique
      unique [:user_id, :role_id], name: :user_role_unique_idx

      # Partial unique
      unique :slug, name: :users_slug_active_idx, where: "deleted_at IS NULL"
  """
  defmacro unique(fields, opts) do
    fields = List.wrap(fields)

    quote bind_quoted: [fields: fields, opts: opts] do
      name = Keyword.get(opts, :name)
      where = Keyword.get(opts, :where)

      constraint = %{
        fields: fields,
        name: name,
        where: where
      }

      Module.put_attribute(__MODULE__, :constraint_unique, constraint)
    end
  end

  @doc """
  Declares a foreign key constraint within a constraints block.

  Use this when you need explicit control over FK options beyond what
  `belongs_to` provides.

  ## Options

    * `:references` - The table being referenced (required)
    * `:column` - The column in the referenced table (default: `:id`)
    * `:on_delete` - Action on delete: `:nothing`, `:delete_all`, `:nilify_all`, `:restrict`, `:cascade`
    * `:on_update` - Action on update (same options as on_delete)
    * `:deferrable` - `:initially_immediate` or `:initially_deferred`
    * `:name` - Custom constraint name

  ## Examples

      foreign_key :user_id,
        references: :users,
        on_delete: :cascade

      foreign_key :account_id,
        references: :accounts,
        on_delete: :cascade,
        deferrable: :initially_deferred
  """
  defmacro foreign_key(field, opts) do
    quote bind_quoted: [field: field, opts: opts] do
      references = Keyword.fetch!(opts, :references)

      constraint = %{
        field: field,
        references: references,
        column: Keyword.get(opts, :column, :id),
        on_delete: Keyword.get(opts, :on_delete, :nothing),
        on_update: Keyword.get(opts, :on_update, :nothing),
        deferrable: Keyword.get(opts, :deferrable),
        name: Keyword.get(opts, :name)
      }

      Module.put_attribute(__MODULE__, :constraint_foreign_key, constraint)
    end
  end

  @doc """
  Declares a check constraint within a constraints block.

  ## Examples

      # Reference by name only (expression in migration)
      check :users_age_positive

      # With expression (for documentation/validation)
      check :valid_dates, expr: "started_at < ended_at"
  """
  defmacro check(name) when is_atom(name) do
    quote bind_quoted: [name: name] do
      constraint = %{
        name: name,
        expr: nil,
        field: nil
      }

      Module.put_attribute(__MODULE__, :constraint_check, constraint)
    end
  end

  defmacro check(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      constraint = %{
        name: name,
        expr: Keyword.get(opts, :expr),
        field: Keyword.get(opts, :field)
      }

      Module.put_attribute(__MODULE__, :constraint_check, constraint)
    end
  end

  @doc """
  Declares a non-unique index within a constraints block.

  Indexes are primarily for performance and are validated as warnings
  (not errors) by default.

  ## Examples

      index :status, name: :users_status_idx
      index [:user_id, :account_id], name: :memberships_user_account_idx
      index :email, name: :users_email_active_idx, where: "status = 'active'"
  """
  defmacro index(fields, opts \\ []) do
    fields = List.wrap(fields)

    quote bind_quoted: [fields: fields, opts: opts] do
      idx = %{
        fields: fields,
        name: Keyword.get(opts, :name),
        where: Keyword.get(opts, :where),
        unique: false
      }

      Module.put_attribute(__MODULE__, :constraint_index, idx)
    end
  end

  @doc """
  Declares an exclusion constraint (PostgreSQL-specific).

  ## Examples

      exclude :no_overlap,
        using: :gist,
        expr: "room_id WITH =, tsrange(start_at, end_at) WITH &&"
  """
  defmacro exclude(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      constraint = %{
        name: name,
        using: Keyword.get(opts, :using, :gist),
        expr: Keyword.fetch!(opts, :expr)
      }

      Module.put_attribute(__MODULE__, :constraint_exclude, constraint)
    end
  end

  # ===========================================================================
  # Helper Functions for Field-Level Constraints
  # ===========================================================================

  @doc """
  Normalizes field-level unique option to constraint metadata.

  ## Examples

      normalize_unique_option(true, :users, :email)
      # => %{fields: [:email], name: :users_email_index, where: nil}

      normalize_unique_option(:custom_idx, :users, :email)
      # => %{fields: [:email], name: :custom_idx, where: nil}

      normalize_unique_option([name: :idx, where: "active"], :users, :email)
      # => %{fields: [:email], name: :idx, where: "active"}
  """
  def normalize_unique_option(true, table, field) do
    %{
      fields: [field],
      name: :"#{table}_#{field}_index",
      where: nil
    }
  end

  def normalize_unique_option(name, _table, field) when is_atom(name) do
    %{
      fields: [field],
      name: name,
      where: nil
    }
  end

  def normalize_unique_option(opts, table, field) when is_list(opts) do
    %{
      fields: [field],
      name: Keyword.get(opts, :name) || :"#{table}_#{field}_index",
      where: Keyword.get(opts, :where)
    }
  end

  @doc """
  Normalizes field-level check option to constraint metadata.
  """
  def normalize_check_option(name, _table, field) when is_atom(name) do
    %{
      name: name,
      expr: nil,
      field: field
    }
  end

  @doc """
  Normalizes belongs_to constraint option to FK metadata.

  ## Examples

      normalize_belongs_to_constraint([on_delete: :cascade], :users, :account_id, :accounts)
      # => %{field: :account_id, references: :accounts, on_delete: :cascade, ...}
  """
  def normalize_belongs_to_constraint(opts, table, field, references_table) when is_list(opts) do
    %{
      field: field,
      references: references_table,
      column: Keyword.get(opts, :column, :id),
      on_delete: Keyword.get(opts, :on_delete, :nothing),
      on_update: Keyword.get(opts, :on_update, :nothing),
      deferrable: Keyword.get(opts, :deferrable),
      name: Keyword.get(opts, :name) || :"#{table}_#{field}_fkey"
    }
  end

  def normalize_belongs_to_constraint(false, _table, _field, _references) do
    nil
  end

  def normalize_belongs_to_constraint(nil, table, field, references_table) do
    # Default FK constraint
    %{
      field: field,
      references: references_table,
      column: :id,
      on_delete: :nothing,
      on_update: :nothing,
      deferrable: nil,
      name: :"#{table}_#{field}_fkey"
    }
  end

  # ===========================================================================
  # Introspection Generation
  # ===========================================================================

  @doc """
  Generates constraint introspection functions for a module.

  Called during schema compilation to generate `__constraints__/0`, `__indexes__/0`,
  and public wrapper functions.
  """
  defmacro __generate_constraint_helpers__(table_name) do
    quote do
      # Collect accumulated constraints
      @unique_constraints_computed Module.get_attribute(__MODULE__, :constraint_unique) || []
      @foreign_key_constraints_computed Module.get_attribute(__MODULE__, :constraint_foreign_key) ||
                                          []
      @check_constraints_computed Module.get_attribute(__MODULE__, :constraint_check) || []
      @indexes_computed Module.get_attribute(__MODULE__, :constraint_index) || []
      @exclude_constraints_computed Module.get_attribute(__MODULE__, :constraint_exclude) || []

      # Collect field-level constraints from field_validations
      @field_unique_constraints @field_validations
                                |> Enum.filter(fn {_name, _type, opts} ->
                                  Keyword.has_key?(opts, :unique)
                                end)
                                |> Enum.map(fn {name, _type, opts} ->
                                  OmSchema.Constraints.normalize_unique_option(
                                    opts[:unique],
                                    unquote(table_name),
                                    name
                                  )
                                end)

      @field_check_constraints @field_validations
                               |> Enum.filter(fn {_name, _type, opts} ->
                                 Keyword.has_key?(opts, :check)
                               end)
                               |> Enum.map(fn {name, _type, opts} ->
                                 OmSchema.Constraints.normalize_check_option(
                                   opts[:check],
                                   unquote(table_name),
                                   name
                                 )
                               end)

      @all_unique_constraints @unique_constraints_computed ++ @field_unique_constraints
      @all_check_constraints @check_constraints_computed ++ @field_check_constraints

      # Collect FK constraints from belongs_to associations
      @belongs_to_constraints (if function_exported?(__MODULE__, :__schema__, 1) do
                                 __MODULE__.__schema__(:associations)
                                 |> Enum.map(&__MODULE__.__schema__(:association, &1))
                                 |> Enum.filter(
                                   &(&1.relationship == :parent && &1.cardinality == :one)
                                 )
                                 |> Enum.map(fn assoc ->
                                   # Get constraint options from module attribute if set
                                   constraint_opts =
                                     Module.get_attribute(__MODULE__, :"#{assoc.field}_constraint") ||
                                       nil

                                   OmSchema.Constraints.normalize_belongs_to_constraint(
                                     constraint_opts,
                                     unquote(table_name),
                                     assoc.owner_key,
                                     assoc.related.__schema__(:source)
                                   )
                                 end)
                                 |> Enum.reject(&is_nil/1)
                               else
                                 []
                               end)

      @all_foreign_key_constraints @foreign_key_constraints_computed ++ @belongs_to_constraints

      @doc """
      Returns all declared constraint metadata.

      Includes unique constraints, foreign keys, check constraints, and exclusion constraints.
      """
      def __constraints__ do
        %{
          unique: @all_unique_constraints,
          foreign_key: @all_foreign_key_constraints,
          check: @all_check_constraints,
          exclude: @exclude_constraints_computed,
          primary_key: %{fields: [:id], name: :"#{unquote(table_name)}_pkey"}
        }
      end

      @doc """
      Returns all declared index metadata.
      """
      def __indexes__ do
        # Include unique constraints as indexes
        unique_as_indexes =
          Enum.map(@all_unique_constraints, fn uc ->
            %{
              name: uc.name,
              fields: uc.fields,
              unique: true,
              where: uc.where
            }
          end)

        unique_as_indexes ++ @indexes_computed
      end

      # Public wrapper functions
      @doc "Returns all constraint metadata."
      def constraints, do: __constraints__()

      @doc "Returns all index metadata."
      def indexes, do: __indexes__()

      @doc "Returns foreign key constraint details."
      def foreign_keys, do: __constraints__().foreign_key

      @doc "Returns unique constraint details."
      def unique_constraints, do: __constraints__().unique

      @doc "Returns check constraint details."
      def check_constraints, do: __constraints__().check
    end
  end
end
