defmodule OmQuery.SqlScope.Error do
  @moduledoc """
  Custom exception for SqlScope operations.

  This exception provides rich error information including:
  - Reason code for programmatic error handling
  - User-friendly error message
  - Optional query and parameters that caused the error
  - Suggestions for how to fix the error

  ## Reason Codes

  - `:table_not_found` - Referenced table doesn't exist
  - `:column_not_found` - Referenced column doesn't exist
  - `:index_not_found` - Referenced index doesn't exist
  - `:constraint_not_found` - Referenced constraint doesn't exist
  - `:permission_denied` - Insufficient database permissions
  - `:timeout` - Query execution timed out
  - `:invalid_identifier` - Identifier contains invalid characters
  - `:sql_injection_detected` - Potential SQL injection attempt blocked
  - `:postgres_version_unsupported` - PostgreSQL version not supported
  - `:in_migration_transaction` - Operation cannot run inside migration transaction
  - `:invalid_option` - Invalid option provided to function
  - `:dry_run_mode` - Operation blocked because dry_run is enabled
  - `:query_error` - General query execution error

  ## Examples

      iex> raise OmQuery.SqlScope.Error, reason: :table_not_found, table: :products
      ** (OmQuery.SqlScope.Error) Table 'products' not found

      iex> raise OmQuery.SqlScope.Error,
      ...>   reason: :permission_denied,
      ...>   query: "SELECT * FROM pg_indexes"
      ** (OmQuery.SqlScope.Error) Permission denied
  """

  defexception [:message, :reason, :query, :params, :table, :column, :metadata]

  @type t :: %__MODULE__{
          message: String.t(),
          reason: reason(),
          query: String.t() | nil,
          params: list() | nil,
          table: atom() | String.t() | nil,
          column: atom() | String.t() | nil,
          metadata: map() | nil
        }

  @type reason ::
          :table_not_found
          | :column_not_found
          | :index_not_found
          | :constraint_not_found
          | :permission_denied
          | :timeout
          | :invalid_identifier
          | :sql_injection_detected
          | :postgres_version_unsupported
          | :in_migration_transaction
          | :invalid_option
          | :dry_run_mode
          | :query_error

  @impl true
  def exception(opts) when is_list(opts) do
    reason = Keyword.get(opts, :reason)
    message = Keyword.get(opts, :message) || build_message(reason, opts)

    %__MODULE__{
      message: message,
      reason: reason,
      query: Keyword.get(opts, :query),
      params: Keyword.get(opts, :params),
      table: Keyword.get(opts, :table),
      column: Keyword.get(opts, :column),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @impl true
  def exception(message) when is_binary(message) do
    %__MODULE__{message: message, reason: :query_error}
  end

  # Build user-friendly error messages based on reason code
  defp build_message(:table_not_found, opts) do
    table = Keyword.get(opts, :table)
    available = Keyword.get(opts, :available_tables)

    base = "Table #{inspect(table)} not found."

    suggestion =
      cond do
        available && is_list(available) && available != [] ->
          "\n\nAvailable tables:\n" <>
            (available
             |> Enum.map(&"  - #{inspect(&1)}")
             |> Enum.join("\n"))

        available && is_list(available) && available == [] ->
          "\n\nNo tables found in database. Have you run migrations?"

        true ->
          "\n\nUse SqlScope.list_tables() to see available tables."
      end

    # Check for common typos
    typo_suggestion =
      if available && is_list(available) && table do
        table_str = to_string(table)

        similar =
          Enum.find(available, fn t ->
            t_str = to_string(t)
            String.jaro_distance(table_str, t_str) > 0.8
          end)

        if similar do
          "\n\nDid you mean #{inspect(similar)}?"
        else
          ""
        end
      else
        ""
      end

    base <> suggestion <> typo_suggestion
  end

  defp build_message(:column_not_found, opts) do
    table = Keyword.get(opts, :table)
    column = Keyword.get(opts, :column)
    available = Keyword.get(opts, :available_columns)

    base = "Column #{inspect(column)} not found"

    table_info = if table, do: " in table #{inspect(table)}", else: ""

    suggestion =
      if available && is_list(available) && available != [] do
        "\n\nAvailable columns:\n" <>
          (available
           |> Enum.map(&"  - #{inspect(&1)}")
           |> Enum.join("\n"))
      else
        ""
      end

    base <> table_info <> "." <> suggestion
  end

  defp build_message(:index_not_found, opts) do
    index = Keyword.get(opts, :index)
    table = Keyword.get(opts, :table)

    base = "Index #{inspect(index)} not found"
    table_info = if table, do: " on table #{inspect(table)}", else: ""

    suggestion = "\n\nUse SqlScope.list_indexes(#{inspect(table)}) to see available indexes."

    base <> table_info <> "." <> suggestion
  end

  defp build_message(:constraint_not_found, opts) do
    constraint = Keyword.get(opts, :constraint)
    table = Keyword.get(opts, :table)

    base = "Constraint #{inspect(constraint)} not found"
    table_info = if table, do: " on table #{inspect(table)}", else: ""

    suggestion =
      "\n\nUse SqlScope.list_constraints(#{inspect(table)}) to see available constraints."

    base <> table_info <> "." <> suggestion
  end

  defp build_message(:permission_denied, opts) do
    query = Keyword.get(opts, :query)
    required_role = Keyword.get(opts, :required_role)

    base = "Permission denied."

    query_info =
      if query do
        "\n\nAttempted query:\n#{query}"
      else
        ""
      end

    role_info =
      if required_role do
        "\n\nThis operation requires the '#{required_role}' role.\n" <>
          "Grant with: GRANT #{required_role} TO your_user;"
      else
        "\n\nThis operation requires elevated database permissions.\n" <>
          "Some SqlScope operations require 'pg_monitor' role or superuser access."
      end

    base <> query_info <> role_info
  end

  defp build_message(:timeout, opts) do
    query = Keyword.get(opts, :query)
    timeout = Keyword.get(opts, :timeout)

    base = "Query execution timed out"

    timeout_info = if timeout, do: " after #{timeout}ms", else: ""

    query_info =
      if query do
        "\n\nQuery:\n#{String.slice(query, 0, 200)}..."
      else
        ""
      end

    suggestion =
      "\n\nTry:\n" <>
        "  - Adding pagination (limit/offset options)\n" <>
        "  - Filtering to a specific table\n" <>
        "  - Increasing timeout in options"

    base <> timeout_info <> "." <> query_info <> suggestion
  end

  defp build_message(:invalid_identifier, opts) do
    identifier = Keyword.get(opts, :identifier)

    """
    Invalid identifier: #{inspect(identifier)}

    Identifiers can only contain:
    - Letters (a-z, A-Z)
    - Numbers (0-9)
    - Underscores (_)
    - Must start with a letter or underscore
    - Maximum 63 characters (PostgreSQL limit)

    Examples of valid identifiers:
    - users
    - user_id
    - UserAccount
    - _private
    """
  end

  defp build_message(:sql_injection_detected, opts) do
    input = Keyword.get(opts, :input)

    """
    SQL injection attempt detected: #{inspect(input)}

    This input contains patterns commonly used in SQL injection attacks.

    If this is legitimate input, use parameterized queries with bindings
    instead of raw SQL fragments.

    Example:
      # Instead of:
      SqlScope.scope_custom("status = '\#{user_input}'")

      # Use:
      SqlScope.Scope.new() |> SqlScope.Scope.eq(:status, user_input)
    """
  end

  defp build_message(:postgres_version_unsupported, opts) do
    version = Keyword.get(opts, :version)
    min_version = Keyword.get(opts, :min_version, "12.0")
    feature = Keyword.get(opts, :feature)

    base = "PostgreSQL version #{version} is not supported."

    feature_info =
      if feature do
        "\n\nFeature '#{feature}' requires PostgreSQL #{min_version} or higher."
      else
        "\n\nSqlScope requires PostgreSQL #{min_version} or higher."
      end

    suggestion = "\n\nPlease upgrade your PostgreSQL installation."

    base <> feature_info <> suggestion
  end

  defp build_message(:in_migration_transaction, _opts) do
    """
    This operation cannot run inside a migration transaction.

    Some operations (like CREATE INDEX CONCURRENTLY) cannot be executed
    within a transaction block.

    Use one of these approaches:
      1. Run outside migration: Ecto.Adapters.SQL.query(Repo, sql)
      2. Disable transaction for migration: use Ecto.Migration, transaction: false
      3. Use SqlScope.execute_outside_migration(fn -> ... end)
    """
  end

  defp build_message(:invalid_option, opts) do
    option = Keyword.get(opts, :option)
    valid_options = Keyword.get(opts, :valid_options, [])

    base = "Invalid option: #{inspect(option)}"

    valid_info =
      if valid_options != [] do
        "\n\nValid options:\n" <>
          (valid_options
           |> Enum.map(&"  - #{inspect(&1)}")
           |> Enum.join("\n"))
      else
        ""
      end

    base <> valid_info
  end

  defp build_message(:dry_run_mode, _opts) do
    """
    Operation blocked by dry_run mode.

    This destructive operation was not executed because dry_run: true
    was specified.

    To execute for real, call again with dry_run: false or omit the option.
    """
  end

  defp build_message(:query_error, opts) do
    query = Keyword.get(opts, :query)
    pg_error = Keyword.get(opts, :pg_error)

    base = "Query execution failed."

    query_info =
      if query do
        "\n\nQuery:\n#{query}"
      else
        ""
      end

    pg_info =
      if pg_error do
        "\n\nPostgreSQL error: #{inspect(pg_error)}"
      else
        ""
      end

    base <> query_info <> pg_info
  end

  defp build_message(nil, opts) do
    Keyword.get(opts, :message, "SqlScope error occurred")
  end

  defp build_message(reason, _opts) when is_atom(reason) do
    "SqlScope error: #{reason}"
  end
end

defmodule OmQuery.SqlScope.SecurityError do
  @moduledoc """
  Exception raised when a security violation is detected.

  This is a specialized error for security-related issues like:
  - SQL injection attempts
  - Invalid identifiers
  - Dangerous SQL fragments
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end
