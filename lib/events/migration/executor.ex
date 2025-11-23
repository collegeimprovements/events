defmodule Events.Migration.Executor do
  @moduledoc """
  Executes migration tokens by translating them to Ecto.Migration commands.

  This module handles the final step in the pipeline, converting our
  clean token representation into actual database changes.
  """

  alias Events.Migration.Token
  import Ecto.Migration

  @doc """
  Executes a migration token.

  Validates the token and translates it into Ecto.Migration commands.
  """
  @spec execute(Token.t()) :: any()
  def execute(%Token{} = token) do
    case Token.validate(token) do
      {:ok, valid_token} -> do_execute(valid_token)
      {:error, message} -> raise ArgumentError, message
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
  # Field Handling
  # ============================================

  defp maybe_add_primary_key(%Token{options: opts}) do
    unless Keyword.get(opts, :primary_key, true) == false do
      # Default primary key is handled by Ecto
      :ok
    end
  end

  defp add_field({name, {:references, table, opts}, field_opts}) do
    merged_opts = Keyword.merge(opts, field_opts)
    add name, references(table, merged_opts)
  end

  defp add_field({name, {:array, type}, opts}) do
    add name, {:array, type}, opts
  end

  defp add_field({name, :jsonb, opts}) do
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
end
