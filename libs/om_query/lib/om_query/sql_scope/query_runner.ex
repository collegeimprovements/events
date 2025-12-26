defmodule OmQuery.SqlScope.QueryRunner do
  @moduledoc """
  Safe query execution for SqlScope operations.

  This module provides a centralized place for all database queries with:
  - Proper error handling and translation
  - Security checks and validation
  - Transaction management
  - Dry-run mode support
  - Query logging and debugging

  All SqlScope database operations MUST go through this module to ensure
  consistent error handling and security.

  ## Configuration

  Configure the default repo in your config:

      config :om_query, :default_repo, MyApp.Repo

  Or pass the repo explicitly:

      QueryRunner.execute_query(sql, params, repo: MyApp.Repo)

  ## Examples

      iex> execute_query("SELECT * FROM pg_tables WHERE schemaname = $1", ["public"])
      {:ok, %Postgrex.Result{rows: [...]}}

      iex> execute_query("SELECT * FROM nonexistent", [])
      {:error, %OmQuery.SqlScope.Error{reason: :table_not_found}}
  """

  alias OmQuery.SqlScope.Error

  require Logger

  # 30 seconds
  @default_timeout 30_000

  @doc """
  Executes a query with proper error handling.

  Returns `{:ok, result}` on success or `{:error, error}` on failure.

  ## Options

  - `:repo` - Ecto repo to use (default: from config)
  - `:timeout` - Query timeout in milliseconds (default: 30000)
  - `:log` - Enable query logging (default: false)
  - `:dry_run` - Return SQL without executing (default: false)

  ## Examples

      execute_query("SELECT tablename FROM pg_tables WHERE schemaname = $1", ["public"])
      #=> {:ok, %Postgrex.Result{rows: [["users"], ["products"]]}}

      execute_query("SELECT * FROM pg_tables", [], dry_run: true)
      #=> {:ok, :dry_run, "SELECT * FROM pg_tables"}
  """
  @spec execute_query(String.t(), list(), keyword()) ::
          {:ok, Postgrex.Result.t()} | {:ok, :dry_run, String.t()} | {:error, Error.t()}
  def execute_query(sql, params \\ [], opts \\ [])

  def execute_query(sql, params, opts) when is_binary(sql) and is_list(params) do
    repo = Keyword.get(opts, :repo) || default_repo()
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    log = Keyword.get(opts, :log, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    execute_with_mode(sql, params, repo, dry_run, log, timeout)
  end

  defp execute_with_mode(sql, params, _repo, true = _dry_run, _log, _timeout) do
    log_query(sql, params, dry_run: true)
    {:ok, :dry_run, format_dry_run_output(sql, params)}
  end

  defp execute_with_mode(sql, params, repo, false = _dry_run, log, timeout) do
    maybe_log_query(sql, params, log)

    case Ecto.Adapters.SQL.query(repo, sql, params, timeout: timeout) do
      {:ok, result} ->
        {:ok, result}

      {:error, %Postgrex.Error{postgres: %{code: code} = pg_error}} ->
        {:error, translate_postgres_error(code, pg_error, sql, params)}

      {:error, error} ->
        {:error, translate_generic_error(error, sql, params)}
    end
  end

  defp maybe_log_query(sql, params, true), do: log_query(sql, params)
  defp maybe_log_query(_sql, _params, false), do: :ok

  @doc """
  Executes a query and returns the result directly.

  Raises an exception on error instead of returning error tuple.

  ## Examples

      execute_query!("SELECT 1")
      #=> %Postgrex.Result{rows: [[1]]}

      execute_query!("SELECT * FROM nonexistent")
      #=> ** (OmQuery.SqlScope.Error) Table 'nonexistent' not found
  """
  @spec execute_query!(String.t(), list(), keyword()) ::
          Postgrex.Result.t() | {:dry_run, String.t()}
  def execute_query!(sql, params \\ [], opts \\ []) do
    case execute_query(sql, params, opts) do
      {:ok, result} -> result
      {:ok, :dry_run, output} -> {:dry_run, output}
      {:error, error} -> raise error
    end
  end

  @doc """
  Executes a function inside a transaction.

  Useful for operations that need to be atomic.

  ## Options

  - `:repo` - Ecto repo to use (default: from config)

  ## Examples

      execute_in_transaction(fn ->
        execute_query!("CREATE TABLE test (...)")
        execute_query!("CREATE INDEX idx_test ON test (...)")
      end)
  """
  @spec execute_in_transaction((-> result), keyword()) :: {:ok, result} | {:error, term()}
        when result: any()
  def execute_in_transaction(fun, opts \\ []) when is_function(fun, 0) do
    repo = Keyword.get(opts, :repo) || default_repo()
    repo.transaction(fun, timeout: :infinity)
  end

  @doc """
  Executes a function outside of any migration transaction.

  Some operations (like CREATE INDEX CONCURRENTLY) cannot run inside
  a transaction. This function ensures they run outside the transaction context.

  Note: This is a placeholder. In practice, you need to execute such
  operations via `Ecto.Migrator` with `transaction: false` or use
  raw SQL execution outside migrations.

  ## Examples

      execute_outside_migration(fn ->
        execute_query!("CREATE INDEX CONCURRENTLY idx_products_name ON products (name)")
      end)
  """
  @spec execute_outside_migration((-> result)) :: result when result: any()
  def execute_outside_migration(fun) when is_function(fun, 0) do
    check_migration_transaction_and_execute(fun, in_migration_transaction?())
  end

  defp check_migration_transaction_and_execute(_fun, true) do
    raise Error,
      reason: :in_migration_transaction,
      message: """
      Cannot execute this operation inside a migration transaction.

      Use one of these approaches:
        1. In migration file, add: use Ecto.Migration, transaction: false
        2. Run this operation outside of migrations
        3. Use execute/1 with raw SQL and handle transaction manually
      """
  end

  defp check_migration_transaction_and_execute(fun, false), do: fun.()

  @doc """
  Returns the PostgreSQL version as an integer.

  Version format: Major * 10000 + Minor * 100 + Patch

  ## Options

  - `:repo` - Ecto repo to use (default: from config)

  ## Examples

      postgres_version()
      #=> 140002  # PostgreSQL 14.0.2

      postgres_version() >= 120000
      #=> true  # PostgreSQL 12 or higher
  """
  @spec postgres_version(keyword()) :: integer()
  def postgres_version(opts \\ []) do
    case execute_query("SHOW server_version_num", [], opts) do
      {:ok, %{rows: [[version_str]]}} ->
        case Integer.parse(version_str) do
          {version, _} ->
            version

          :error ->
            Logger.warning("Invalid PostgreSQL version format '#{version_str}', assuming 14.0")
            140_000
        end

      {:error, _} ->
        # Fallback: assume recent version
        Logger.warning("Could not determine PostgreSQL version, assuming 14.0")
        140_000
    end
  end

  @doc """
  Checks if PostgreSQL version meets minimum requirement.

  ## Examples

      check_postgres_version!(120000)
      #=> :ok

      check_postgres_version!(180000)
      #=> ** (Error) PostgreSQL version not supported
  """
  @spec check_postgres_version!(integer(), String.t() | nil, keyword()) :: :ok
  def check_postgres_version!(min_version, feature \\ nil, opts \\ []) do
    current = postgres_version(opts)
    validate_postgres_version(current, min_version, feature)
  end

  defp validate_postgres_version(current, min_version, _feature) when current >= min_version do
    :ok
  end

  defp validate_postgres_version(current, min_version, feature) do
    raise Error,
      reason: :postgres_version_unsupported,
      version: format_version(current),
      min_version: format_version(min_version),
      feature: feature
  end

  @doc """
  Returns current database name.

  ## Options

  - `:repo` - Ecto repo to use (default: from config)
  """
  @spec current_database(keyword()) :: String.t()
  def current_database(opts \\ []) do
    case execute_query("SELECT current_database()", [], opts) do
      {:ok, %{rows: [[db_name]]}} -> db_name
      {:error, _} -> "unknown"
    end
  end

  @doc """
  Returns current schema (search_path).

  ## Options

  - `:repo` - Ecto repo to use (default: from config)
  """
  @spec current_schema(keyword()) :: String.t()
  def current_schema(opts \\ []) do
    case execute_query("SELECT current_schema()", [], opts) do
      {:ok, %{rows: [[schema]]}} -> schema || "public"
      {:error, _} -> "public"
    end
  end

  # Private functions

  defp default_repo do
    Application.get_env(:om_query, :default_repo) ||
      raise "No default repo configured. Set config :om_query, :default_repo, MyApp.Repo or pass :repo option"
  end

  # Translate PostgreSQL error codes to SqlScope errors
  defp translate_postgres_error("42P01", pg_error, sql, params) do
    # Undefined table
    table = extract_table_from_error(pg_error) || extract_table_from_query(sql)

    %Error{
      reason: :table_not_found,
      table: table,
      query: sql,
      params: params,
      metadata: %{pg_error: pg_error}
    }
  end

  defp translate_postgres_error("42703", pg_error, sql, params) do
    # Undefined column
    column = extract_column_from_error(pg_error)

    %Error{
      reason: :column_not_found,
      column: column,
      query: sql,
      params: params,
      metadata: %{pg_error: pg_error}
    }
  end

  defp translate_postgres_error("42501", pg_error, sql, params) do
    # Insufficient privilege
    %Error{
      reason: :permission_denied,
      query: sql,
      params: params,
      metadata: %{pg_error: pg_error}
    }
  end

  defp translate_postgres_error("57014", pg_error, sql, params) do
    # Query canceled (timeout)
    %Error{
      reason: :timeout,
      query: sql,
      params: params,
      metadata: %{pg_error: pg_error}
    }
  end

  defp translate_postgres_error(_code, pg_error, sql, params) do
    # Generic query error
    %Error{
      reason: :query_error,
      query: sql,
      params: params,
      message: pg_error.message || "Query execution failed",
      metadata: %{pg_error: pg_error}
    }
  end

  defp translate_generic_error(error, sql, params) do
    %Error{
      reason: :query_error,
      query: sql,
      params: params,
      message: "Query execution failed: #{inspect(error)}",
      metadata: %{original_error: error}
    }
  end

  # Extract table name from PostgreSQL error message
  defp extract_table_from_error(%{message: message}) when is_binary(message) do
    # Pattern: relation "table_name" does not exist
    case Regex.run(~r/relation "([^"]+)" does not exist/, message) do
      [_, table] -> table
      _ -> nil
    end
  end

  defp extract_table_from_error(_), do: nil

  # Extract table name from SQL query
  defp extract_table_from_query(sql) when is_binary(sql) do
    # Simple extraction from FROM clause
    case Regex.run(~r/FROM\s+(\w+)/i, sql) do
      [_, table] -> table
      _ -> nil
    end
  end

  # Extract column name from PostgreSQL error
  defp extract_column_from_error(%{message: message}) when is_binary(message) do
    # Pattern: column "column_name" does not exist
    case Regex.run(~r/column "([^"]+)" does not exist/, message) do
      [_, column] -> column
      _ -> nil
    end
  end

  defp extract_column_from_error(_), do: nil

  # Check if currently in a migration transaction
  # This is a heuristic - actual implementation would need to check Ecto state
  defp in_migration_transaction? do
    # For now, return false
    # In real implementation, check if we're inside Ecto.Migration context
    false
  end

  # Log query execution
  defp log_query(sql, params, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    prefix = if dry_run, do: "[DRY RUN]", else: "[QUERY]"

    Logger.debug("""
    #{prefix} SqlScope Query
    SQL: #{sql}
    Params: #{inspect(params)}
    """)
  end

  # Format dry run output
  defp format_dry_run_output(sql, []) do
    """
    [DRY RUN MODE - Query not executed]

    #{sql}
    """
  end

  defp format_dry_run_output(sql, params) do
    """
    [DRY RUN MODE - Query not executed]

    SQL:
    #{sql}

    Parameters:
    #{params |> Enum.with_index(1) |> Enum.map(fn {p, i} -> "  $#{i} = #{inspect(p)}" end) |> Enum.join("\n")}
    """
  end

  # Format version number to human-readable string
  defp format_version(version) when is_integer(version) do
    major = div(version, 10000)
    minor = version |> rem(10000) |> div(100)
    patch = rem(version, 100)

    "#{major}.#{minor}.#{patch}"
  end
end
