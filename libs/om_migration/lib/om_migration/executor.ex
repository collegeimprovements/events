defmodule OmMigration.Executor do
  @moduledoc """
  Executes migration tokens by translating them to Ecto.Migration commands.

  This module handles the final step in the pipeline, converting our
  clean token representation into actual database changes.

  ## Validation

  All tokens are validated using `OmMigration.TokenValidator` before execution.
  Invalid tokens will raise `OmMigration.ValidationError` with detailed error information.

  ## Options

  - `:skip_validation` - Skip validation before execution (default: `false`).
    Use with caution, primarily for performance in trusted contexts.
  """

  alias OmMigration.{Token, TokenValidator}
  import Ecto.Migration

  @doc """
  Executes a migration token.

  Validates the token using `TokenValidator` and translates it into Ecto.Migration commands.

  ## Options

  - `:skip_validation` - Skip validation before execution (default: `false`)

  ## Examples

      # Normal execution with validation
      Executor.execute(token)

      # Skip validation (use with caution)
      Executor.execute(token, skip_validation: true)

  Raises `OmMigration.ValidationError` if validation fails.
  """
  @spec execute(Token.t(), keyword()) :: any()
  def execute(%Token{} = token, opts \\ []) do
    skip_validation = Keyword.get(opts, :skip_validation, false)

    if skip_validation do
      do_execute(token)
    else
      # Use TokenValidator for comprehensive validation
      valid_token = TokenValidator.validate!(token)
      do_execute(valid_token)
    end
  end

  # ============================================
  # Table Execution
  # ============================================

  defp do_execute(%Token{type: :table} = token) do
    create table(token.name, token.options) do
      # Add primary key if needed
      maybe_add_primary_key(token)

      # Add all fields
      Enum.each(token.fields, &add_field/1)
    end

    # Create indexes
    Enum.each(token.indexes, &create_index_from_spec(token.name, &1))

    # Create constraints
    Enum.each(token.constraints, &create_constraint_from_spec(token.name, &1))
  end

  # ============================================
  # Index Execution
  # ============================================

  defp do_execute(%Token{type: :index} = token) do
    columns = Keyword.fetch!(token.options, :columns)
    opts = Keyword.delete(token.options, :columns)

    create index(token.name, columns, opts)
  end

  # ============================================
  # Alter Table Execution
  # ============================================

  defp do_execute(%Token{type: :alter} = token) do
    alter table(token.name, token.options) do
      # Handle field additions
      token.fields
      |> Enum.filter(&field_is_add?/1)
      |> Enum.each(&add_field/1)

      # Handle field removals
      token.fields
      |> Enum.filter(&field_is_remove?/1)
      |> Enum.each(&remove_field/1)

      # Handle field modifications
      token.fields
      |> Enum.filter(&field_is_modify?/1)
      |> Enum.each(&modify_field/1)
    end

    # Handle index operations
    Enum.each(token.indexes, fn
      {:add, name, columns, opts} ->
        create index(token.name, columns, Keyword.put(opts, :name, name))

      {:remove, name, _columns, _opts} ->
        drop index(token.name, name: name)

      # Default: add index
      {name, columns, opts} ->
        create index(token.name, columns, Keyword.put(opts, :name, name))
    end)

    # Handle constraint operations
    Enum.each(token.constraints, fn
      {:add, name, type, opts} ->
        create_constraint_from_spec(token.name, {name, type, opts})

      {:remove, name, _type, _opts} ->
        drop constraint(token.name, name)

      # Default: add constraint
      {name, type, opts} ->
        create_constraint_from_spec(token.name, {name, type, opts})
    end)
  end

  # ============================================
  # Drop Operations
  # ============================================

  defp do_execute(%Token{type: :drop_table} = token) do
    opts = drop_table_opts(token.options)
    drop table(token.name, opts)
  end

  defp do_execute(%Token{type: :drop_index} = token) do
    index_name = Keyword.fetch!(token.options, :index_name)
    opts = Keyword.delete(token.options, :index_name)
    drop index(token.name, [name: index_name] ++ opts)
  end

  defp do_execute(%Token{type: :drop_constraint} = token) do
    constraint_name = Keyword.fetch!(token.options, :constraint_name)
    drop constraint(token.name, constraint_name)
  end

  # ============================================
  # Rename Operations
  # ============================================

  defp do_execute(%Token{type: :rename_table} = token) do
    new_name = Keyword.fetch!(token.options, :to)
    rename table(token.name), to: table(new_name)
  end

  defp do_execute(%Token{type: :rename_column} = token) do
    from_column = Keyword.fetch!(token.options, :from)
    to_column = Keyword.fetch!(token.options, :to)
    rename table(token.name), from_column, to: to_column
  end

  # ============================================
  # Field Handling
  # ============================================

  defp maybe_add_primary_key(%Token{options: opts}) do
    unless Keyword.get(opts, :primary_key, true) == false do
      # Default primary key is handled by Ecto
      :ok
    end
  end

  # Add field handling for alter - extract from marker tuple (must be first)
  defp add_field({:add, name, type, opts}) do
    add_field({name, type, opts})
  end

  defp add_field({name, {:references, table, ref_opts}, field_opts}) do
    {column_opts, extra_ref_opts} = Keyword.split(field_opts, [:null, :default, :comment])
    merged_ref_opts = Keyword.merge(ref_opts, extra_ref_opts)

    case column_opts do
      [] -> add name, references(table, merged_ref_opts)
      _ -> add name, references(table, merged_ref_opts), column_opts
    end
  end

  defp add_field({name, {:array, type}, opts}) do
    add name, {:array, type}, opts
  end

  defp add_field({name, :jsonb, opts}) do
    opts = transform_defaults(opts)
    add name, :jsonb, opts
  end

  defp add_field({name, type, opts}) when type in [:citext] do
    # Ensure citext extension is available
    add name, type, opts
  end

  defp add_field({name, type, opts}) when is_atom(type) do
    # Handle special default values
    opts = transform_defaults(opts)
    add name, type, opts
  end

  defp transform_defaults(opts) do
    case Keyword.get(opts, :default) do
      {:fragment, sql} ->
        Keyword.put(opts, :default, fragment(sql))

      val when is_map(val) and val == %{} ->
        Keyword.put(opts, :default, fragment("'{}'"))

      _ ->
        opts
    end
  end

  # ============================================
  # Index Creation
  # ============================================

  defp create_index_from_spec(table_name, {index_name, columns, opts}) do
    create index(table_name, columns, Keyword.put(opts, :name, index_name))
  end

  # ============================================
  # Constraint Creation
  # ============================================

  defp create_constraint_from_spec(table_name, {name, :check, opts}) do
    check = Keyword.fetch!(opts, :check)
    create constraint(table_name, name, check: check)
  end

  defp create_constraint_from_spec(table_name, {name, :exclude, opts}) do
    create constraint(table_name, name, exclude: opts[:exclude])
  end

  defp create_constraint_from_spec(table_name, {name, type, opts}) do
    create constraint(table_name, name, [{type, opts}])
  end

  # ============================================
  # Alter Table Helpers
  # ============================================

  # Field operation markers for alter table
  # Fields can be marked as {:add, name, type, opts}, {:remove, name}, or {:modify, name, type, opts}
  defp field_is_add?({:add, _name, _type, _opts}), do: true
  defp field_is_add?({_name, _type, _opts}), do: true
  defp field_is_add?(_), do: false

  defp field_is_remove?({:remove, _name}), do: true
  defp field_is_remove?({:remove, _name, _opts}), do: true
  defp field_is_remove?(_), do: false

  defp field_is_modify?({:modify, _name, _type, _opts}), do: true
  defp field_is_modify?(_), do: false

  defp remove_field({:remove, name}), do: remove(name)
  defp remove_field({:remove, name, _opts}), do: remove(name)

  defp modify_field({:modify, name, type, opts}) do
    opts = transform_defaults(opts)
    modify(name, type, opts)
  end

  # ============================================
  # Drop Table Helpers
  # ============================================

  defp drop_table_opts(opts) do
    # Extract valid Ecto.Migration drop table options
    opts
    |> Keyword.take([:prefix, :if_exists])
  end
end
