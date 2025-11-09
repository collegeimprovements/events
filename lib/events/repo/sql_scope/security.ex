defmodule Events.Repo.SqlScope.Security do
  @moduledoc """
  Security utilities for SqlScope to prevent SQL injection and validate inputs.

  All database identifiers (table names, column names, index names, constraint names)
  MUST be validated through this module before being used in SQL queries.

  ## SQL Injection Prevention

  This module provides functions to:
  - Validate identifiers against a strict regex pattern
  - Quote identifiers safely for PostgreSQL
  - Sanitize SQL fragments
  - Detect potential injection attempts

  ## Examples

      iex> validate_identifier!(:users)
      "users"

      iex> validate_identifier!("user_id")
      "user_id"

      iex> validate_identifier!("'; DROP TABLE users; --")
      ** (Events.Repo.SqlScope.SecurityError) SQL injection detected
  """

  alias Events.Repo.SqlScope.SecurityError

  @identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
  @max_identifier_length 63  # PostgreSQL limit

  @doc """
  Validates an identifier (table, column, index, constraint name).

  Identifiers must:
  - Start with a letter (a-z, A-Z) or underscore
  - Contain only letters, numbers, and underscores
  - Be 63 characters or less (PostgreSQL limit)

  Returns the identifier as a string if valid, raises SecurityError if invalid.

  ## Examples

      iex> validate_identifier!(:products)
      "products"

      iex> validate_identifier!("user_id")
      "user_id"

      iex> validate_identifier!("123invalid")
      ** (Events.Repo.SqlScope.SecurityError) Invalid identifier

      iex> validate_identifier!("drop; --")
      ** (Events.Repo.SqlScope.SecurityError) SQL injection detected
  """
  @spec validate_identifier!(atom() | String.t()) :: String.t()
  def validate_identifier!(identifier) when is_atom(identifier) do
    identifier
    |> Atom.to_string()
    |> validate_identifier!()
  end

  def validate_identifier!(identifier) when is_binary(identifier) do
    cond do
      byte_size(identifier) == 0 ->
        raise SecurityError, """
        Empty identifier not allowed.

        Identifiers must be at least 1 character long.
        """

      byte_size(identifier) > @max_identifier_length ->
        raise SecurityError, """
        Identifier too long: #{byte_size(identifier)} characters.

        PostgreSQL identifiers must be #{@max_identifier_length} characters or less.
        Provided: #{String.slice(identifier, 0, 50)}...
        """

      not String.match?(identifier, @identifier_regex) ->
        # Check for common SQL injection patterns
        if contains_sql_keywords?(identifier) or contains_dangerous_chars?(identifier) do
          raise SecurityError, """
          SQL injection detected in identifier: #{inspect(identifier)}

          Identifiers can only contain:
          - Letters (a-z, A-Z)
          - Numbers (0-9)
          - Underscores (_)
          - Must start with a letter or underscore

          This looks like a SQL injection attempt.
          """
        else
          raise SecurityError, """
          Invalid identifier: #{inspect(identifier)}

          Identifiers can only contain:
          - Letters (a-z, A-Z)
          - Numbers (0-9)
          - Underscores (_)
          - Must start with a letter or underscore

          Examples of valid identifiers:
          - users
          - user_id
          - UserAccount
          - _private
          """
        end

      true ->
        identifier
    end
  end

  def validate_identifier!(other) do
    raise SecurityError, """
    Invalid identifier type: #{inspect(other)}

    Expected atom or string, got: #{inspect(other.__struct__)}
    """
  end

  @doc """
  Validates multiple identifiers at once.

  Returns list of validated identifier strings if all are valid.
  Raises SecurityError if any identifier is invalid.

  ## Examples

      iex> validate_identifiers!([:users, :id, :email])
      ["users", "id", "email"]

      iex> validate_identifiers!(["products", "price", "'; DROP"])
      ** (Events.Repo.SqlScope.SecurityError) SQL injection detected
  """
  @spec validate_identifiers!([atom() | String.t()]) :: [String.t()]
  def validate_identifiers!(identifiers) when is_list(identifiers) do
    Enum.map(identifiers, &validate_identifier!/1)
  end

  @doc """
  Safely quotes an identifier for use in PostgreSQL queries.

  This wraps the identifier in double quotes and escapes any internal quotes.
  Use this when you need to preserve case sensitivity or use reserved keywords.

  ## Examples

      iex> quote_identifier("users")
      "\\"users\\""

      iex> quote_identifier("User")
      "\\"User\\""

      iex> quote_identifier("table\"name")
      "\\"table\\"\\\"name\\""
  """
  @spec quote_identifier(String.t()) :: String.t()
  def quote_identifier(identifier) when is_binary(identifier) do
    # PostgreSQL doubles quotes to escape them
    escaped = String.replace(identifier, "\"", "\"\"")
    "\"#{escaped}\""
  end

  @doc """
  Validates a schema-qualified identifier (e.g., "public.users").

  Returns tuple {schema, table} if valid.
  Raises SecurityError if invalid.

  ## Examples

      iex> validate_qualified_identifier!("public.users")
      {"public", "users"}

      iex> validate_qualified_identifier!("users")
      {"public", "users"}

      iex> validate_qualified_identifier!("schema.table.extra")
      ** (Events.Repo.SqlScope.SecurityError) Invalid qualified identifier
  """
  @spec validate_qualified_identifier!(String.t()) :: {String.t(), String.t()}
  def validate_qualified_identifier!(identifier) when is_binary(identifier) do
    case String.split(identifier, ".") do
      [table] ->
        {"public", validate_identifier!(table)}

      [schema, table] ->
        {validate_identifier!(schema), validate_identifier!(table)}

      _other ->
        raise SecurityError, """
        Invalid qualified identifier: #{inspect(identifier)}

        Expected format: "schema.table" or "table"
        Got: #{inspect(identifier)}
        """
    end
  end

  @doc """
  Validates a SQL scope/WHERE clause fragment.

  This performs basic validation to prevent obvious SQL injection.
  For complete safety, use parameterized queries with bindings.

  Returns the fragment if it appears safe.
  Raises SecurityError if dangerous patterns detected.

  ## Examples

      iex> validate_sql_fragment!("status = 'active'")
      "status = 'active'"

      iex> validate_sql_fragment!("deleted_at IS NULL")
      "deleted_at IS NULL"

      iex> validate_sql_fragment!("1=1; DROP TABLE users; --")
      ** (Events.Repo.SqlScope.SecurityError) Dangerous SQL fragment detected
  """
  @spec validate_sql_fragment!(String.t()) :: String.t()
  def validate_sql_fragment!(fragment) when is_binary(fragment) do
    # Check for dangerous patterns
    dangerous_patterns = [
      ~r/;\s*(DROP|DELETE|UPDATE|INSERT|CREATE|ALTER|TRUNCATE)/i,
      ~r/--/,  # SQL comments
      ~r/\/\*/,  # Multi-line comments
      ~r/xp_/i,  # SQL Server extended procedures
      ~r/(exec|execute)\s+/i,  # Execute commands
      ~r/\bUNION\b/i,  # UNION-based injection
      ~r/\bINTO\s+OUTFILE\b/i,  # File operations
      ~r/\bLOAD_FILE\b/i  # MySQL file reading
    ]

    if Enum.any?(dangerous_patterns, &String.match?(fragment, &1)) do
      raise SecurityError, """
      Dangerous SQL fragment detected: #{inspect(fragment)}

      This fragment contains patterns commonly used in SQL injection attacks.

      If this is a legitimate WHERE clause, please use parameterized queries
      with bindings instead of raw SQL fragments.

      Example:
        # Instead of:
        SqlScope.scope_custom("status = '\#{user_input}'")

        # Use:
        SqlScope.Scope.new() |> SqlScope.Scope.eq(:status, user_input)
      """
    end

    # Warn if fragment is very long (possible injection)
    if byte_size(fragment) > 1000 do
      raise SecurityError, """
      SQL fragment too long: #{byte_size(fragment)} characters.

      Maximum allowed: 1000 characters.

      Long SQL fragments are often used in injection attacks.
      If you need complex WHERE clauses, use the Scope builder instead.
      """
    end

    fragment
  end

  @doc """
  Validates an option keyword list for a SqlScope function.

  Checks that all keys are known/allowed and values are of correct type.

  Returns :ok if valid, raises SecurityError if invalid options detected.

  ## Examples

      iex> validate_options!([limit: 100, offset: 0], [:limit, :offset, :format])
      :ok

      iex> validate_options!([unknown: true], [:limit, :offset])
      ** (Events.Repo.SqlScope.SecurityError) Unknown option
  """
  @spec validate_options!(keyword(), [atom()]) :: :ok
  def validate_options!(opts, allowed_keys) when is_list(opts) and is_list(allowed_keys) do
    provided_keys = Keyword.keys(opts)
    unknown_keys = provided_keys -- allowed_keys

    if unknown_keys != [] do
      raise SecurityError, """
      Unknown options: #{inspect(unknown_keys)}

      Allowed options: #{inspect(allowed_keys)}
      Provided options: #{inspect(provided_keys)}
      """
    end

    :ok
  end

  # Private helper: check for SQL keywords in identifier
  defp contains_sql_keywords?(identifier) do
    dangerous_keywords = ~w[
      DROP DELETE UPDATE INSERT CREATE ALTER TRUNCATE
      EXEC EXECUTE UNION SELECT WHERE FROM
      TABLE DATABASE SCHEMA INDEX CONSTRAINT
      GRANT REVOKE ROLE USER
      ;
    ]

    String.upcase(identifier) in dangerous_keywords or
      Enum.any?(dangerous_keywords, fn keyword ->
        String.contains?(String.upcase(identifier), keyword)
      end)
  end

  # Private helper: check for dangerous characters
  defp contains_dangerous_chars?(identifier) do
    dangerous_chars = [";", "--", "/*", "*/", "'", "\"", "\\", "\n", "\r", "\t"]

    Enum.any?(dangerous_chars, fn char ->
      String.contains?(identifier, char)
    end)
  end
end
