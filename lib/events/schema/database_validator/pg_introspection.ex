defmodule Events.Schema.DatabaseValidator.PgIntrospection do
  @moduledoc """
  PostgreSQL database introspection for schema validation.

  Provides functions to query PostgreSQL system catalogs and information_schema
  to retrieve metadata about tables, columns, constraints, and indexes.

  ## Atom Safety

  This module converts database identifiers (column names, constraint names, etc.)
  to atoms for easier comparison with Ecto schema definitions. This is safe because:

  1. The set of identifiers is bounded by your application's own database schema
  2. The `safe_to_atom/1` function first tries to use existing atoms (from Ecto schemas)
  3. New atoms are only created for identifiers that match your database schema

  If you have concerns about atom table pollution, consider running this module
  only in development/test environments or on a limited set of tables.

  ## Usage

      alias Events.Schema.DatabaseValidator.PgIntrospection

      # Get all columns for a table
      columns = PgIntrospection.columns(Events.Repo, "users")

      # Get all constraints
      constraints = PgIntrospection.constraints(Events.Repo, "users")

      # Get foreign key details
      fks = PgIntrospection.foreign_keys(Events.Repo, "users")

      # Check if specific constraint exists
      PgIntrospection.constraint_exists?(Events.Repo, "users", "users_pkey")
  """

  # Safe atom conversion - tries existing atoms first, falls back to creating new ones
  # This is bounded by the user's database schema, so atom table pollution is limited
  @doc false
  @spec safe_to_atom(String.t()) :: atom()
  def safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
      # Atom doesn't exist yet - create it (bounded by database schema)
      String.to_atom(string)
  end

  @doc """
  Get all columns for a table with type and nullability information.

  Returns a list of maps with keys:
    - `:name` - Column name as atom
    - `:data_type` - PostgreSQL data type
    - `:udt_name` - Underlying data type name
    - `:is_nullable` - Boolean
    - `:column_default` - Default value expression or nil
    - `:ordinal_position` - Column position
  """
  @spec columns(module(), String.t(), String.t()) :: [map()]
  def columns(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      column_name,
      data_type,
      udt_name,
      is_nullable,
      column_default,
      ordinal_position
    FROM information_schema.columns
    WHERE table_schema = $1 AND table_name = $2
    ORDER BY ordinal_position
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(cols)
          |> Map.new(fn {value, col} -> {col, value} end)
          |> normalize_column()
        end)

      {:error, _} ->
        []
    end
  end

  defp normalize_column(row) do
    %{
      name: safe_to_atom(row["column_name"]),
      data_type: row["data_type"],
      udt_name: row["udt_name"],
      is_nullable: row["is_nullable"] == "YES",
      column_default: row["column_default"],
      ordinal_position: row["ordinal_position"]
    }
  end

  @doc """
  Get all constraints for a table.

  Returns a list of maps with keys:
    - `:name` - Constraint name as atom
    - `:type` - Constraint type: `:primary_key`, `:unique`, `:foreign_key`, `:check`, `:exclude`
    - `:columns` - List of column names as atoms
    - `:definition` - Raw constraint definition
  """
  @spec constraints(module(), String.t(), String.t()) :: [map()]
  def constraints(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      con.conname AS name,
      con.contype AS type,
      pg_get_constraintdef(con.oid) AS definition,
      ARRAY_AGG(att.attname ORDER BY array_position(con.conkey, att.attnum)) AS columns
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    LEFT JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE nsp.nspname = $1 AND rel.relname = $2
    GROUP BY con.conname, con.contype, con.oid
    ORDER BY con.conname
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(cols)
          |> Map.new(fn {value, col} -> {col, value} end)
          |> normalize_constraint()
        end)

      {:error, _} ->
        []
    end
  end

  defp normalize_constraint(row) do
    %{
      name: safe_to_atom(row["name"]),
      type: constraint_type(row["type"]),
      columns: normalize_columns(row["columns"]),
      definition: row["definition"]
    }
  end

  defp constraint_type("p"), do: :primary_key
  defp constraint_type("u"), do: :unique
  defp constraint_type("f"), do: :foreign_key
  defp constraint_type("c"), do: :check
  defp constraint_type("x"), do: :exclude
  defp constraint_type(_), do: :unknown

  defp normalize_columns(nil), do: []
  defp normalize_columns(cols), do: Enum.map(cols, &safe_to_atom/1)

  @doc """
  Get foreign key constraints with full details.

  Returns a list of maps with keys:
    - `:name` - Constraint name as atom
    - `:column` - Local column name as atom
    - `:references_table` - Referenced table name
    - `:references_column` - Referenced column name as atom
    - `:on_delete` - Delete action: `:nothing`, `:cascade`, `:restrict`, `:set_null`, `:set_default`
    - `:on_update` - Update action (same options)
    - `:deferrable` - Boolean
    - `:initially_deferred` - Boolean
  """
  @spec foreign_keys(module(), String.t(), String.t()) :: [map()]
  def foreign_keys(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      tc.constraint_name,
      kcu.column_name,
      ccu.table_name AS references_table,
      ccu.column_name AS references_column,
      rc.delete_rule,
      rc.update_rule,
      tc.is_deferrable,
      tc.initially_deferred
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.referential_constraints rc
      ON tc.constraint_name = rc.constraint_name
      AND tc.table_schema = rc.constraint_schema
    JOIN information_schema.constraint_column_usage ccu
      ON rc.unique_constraint_name = ccu.constraint_name
      AND rc.unique_constraint_schema = ccu.constraint_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = $1
      AND tc.table_name = $2
    ORDER BY tc.constraint_name
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(cols)
          |> Map.new(fn {value, col} -> {col, value} end)
          |> normalize_foreign_key()
        end)

      {:error, _} ->
        []
    end
  end

  defp normalize_foreign_key(row) do
    %{
      name: safe_to_atom(row["constraint_name"]),
      column: safe_to_atom(row["column_name"]),
      references_table: row["references_table"],
      references_column: safe_to_atom(row["references_column"]),
      on_delete: normalize_fk_action(row["delete_rule"]),
      on_update: normalize_fk_action(row["update_rule"]),
      deferrable: row["is_deferrable"] == "YES",
      initially_deferred: row["initially_deferred"] == "YES"
    }
  end

  defp normalize_fk_action("NO ACTION"), do: :nothing
  defp normalize_fk_action("CASCADE"), do: :cascade
  defp normalize_fk_action("RESTRICT"), do: :restrict
  defp normalize_fk_action("SET NULL"), do: :set_null
  defp normalize_fk_action("SET DEFAULT"), do: :set_default
  defp normalize_fk_action(_), do: :nothing

  @doc """
  Get all indexes for a table.

  Returns a list of maps with keys:
    - `:name` - Index name as atom
    - `:columns` - List of column names as atoms
    - `:unique` - Boolean
    - `:where` - Partial index predicate or nil
    - `:definition` - Full index definition
  """
  @spec indexes(module(), String.t(), String.t()) :: [map()]
  def indexes(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      i.relname AS index_name,
      pg_get_indexdef(i.oid) AS definition,
      ix.indisunique AS is_unique,
      pg_get_expr(ix.indpred, ix.indrelid) AS where_clause,
      ARRAY(
        SELECT pg_get_indexdef(ix.indexrelid, k + 1, true)
        FROM generate_subscripts(ix.indkey, 1) AS k
        ORDER BY k
      ) AS columns
    FROM pg_index ix
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = $1
      AND t.relname = $2
      AND NOT ix.indisprimary  -- Exclude primary key indexes
    ORDER BY i.relname
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(cols)
          |> Map.new(fn {value, col} -> {col, value} end)
          |> normalize_index()
        end)

      {:error, _} ->
        []
    end
  end

  defp normalize_index(row) do
    %{
      name: safe_to_atom(row["index_name"]),
      columns: normalize_columns(row["columns"]),
      unique: row["is_unique"],
      where: row["where_clause"],
      definition: row["definition"]
    }
  end

  @doc """
  Check if a specific constraint exists on a table.
  """
  @spec constraint_exists?(module(), String.t(), atom() | String.t(), String.t()) :: boolean()
  def constraint_exists?(repo, table_name, constraint_name, schema \\ "public") do
    constraint_name = to_string(constraint_name)

    query = """
    SELECT EXISTS(
      SELECT 1
      FROM pg_constraint con
      JOIN pg_class rel ON rel.oid = con.conrelid
      JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
      WHERE nsp.nspname = $1
        AND rel.relname = $2
        AND con.conname = $3
    )
    """

    case repo.query(query, [schema, table_name, constraint_name]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  @doc """
  Check if a specific index exists on a table.
  """
  @spec index_exists?(module(), String.t(), atom() | String.t(), String.t()) :: boolean()
  def index_exists?(repo, table_name, index_name, schema \\ "public") do
    index_name = to_string(index_name)

    query = """
    SELECT EXISTS(
      SELECT 1
      FROM pg_indexes
      WHERE schemaname = $1
        AND tablename = $2
        AND indexname = $3
    )
    """

    case repo.query(query, [schema, table_name, index_name]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  @doc """
  Check if a table exists in the database.
  """
  @spec table_exists?(module(), String.t(), String.t()) :: boolean()
  def table_exists?(repo, table_name, schema \\ "public") do
    query = """
    SELECT EXISTS(
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = $1
        AND table_name = $2
    )
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  @doc """
  Get primary key columns for a table.
  """
  @spec primary_key(module(), String.t(), String.t()) :: [atom()]
  def primary_key(repo, table_name, schema \\ "public") do
    query = """
    SELECT a.attname
    FROM pg_index ix
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    WHERE n.nspname = $1
      AND t.relname = $2
      AND ix.indisprimary
    ORDER BY array_position(ix.indkey, a.attnum)
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [col] -> safe_to_atom(col) end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Get check constraints with their expressions.
  """
  @spec check_constraints(module(), String.t(), String.t()) :: [map()]
  def check_constraints(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      con.conname AS name,
      pg_get_constraintdef(con.oid) AS definition
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE con.contype = 'c'
      AND nsp.nspname = $1
      AND rel.relname = $2
    ORDER BY con.conname
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(cols)
          |> Map.new(fn {value, col} -> {col, value} end)
          |> normalize_check_constraint()
        end)

      {:error, _} ->
        []
    end
  end

  defp normalize_check_constraint(row) do
    %{
      name: safe_to_atom(row["name"]),
      definition: row["definition"]
    }
  end

  @doc """
  Get unique constraints (not including primary key).
  """
  @spec unique_constraints(module(), String.t(), String.t()) :: [map()]
  def unique_constraints(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      con.conname AS name,
      ARRAY_AGG(att.attname ORDER BY array_position(con.conkey, att.attnum)) AS columns
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.contype = 'u'
      AND nsp.nspname = $1
      AND rel.relname = $2
    GROUP BY con.conname
    ORDER BY con.conname
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, %{rows: rows, columns: cols}} ->
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(cols)
          |> Map.new(fn {value, col} -> {col, value} end)
          |> normalize_unique_constraint()
        end)

      {:error, _} ->
        []
    end
  end

  defp normalize_unique_constraint(row) do
    %{
      name: safe_to_atom(row["name"]),
      columns: normalize_columns(row["columns"])
    }
  end
end
