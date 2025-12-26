if Code.ensure_loaded?(Postgrex.Error) do
  defimpl FnTypes.Protocols.Normalizable, for: Postgrex.Error do
  @moduledoc """
  Normalizable implementation for Postgrex.Error.

  Handles PostgreSQL-specific errors including:
  - Integrity constraint violations (Class 23)
  - Transaction errors (Class 40)
  - Insufficient resources (Class 53)
  - Operator intervention (Class 57)
  - Connection exceptions (Class 08)

  See: https://www.postgresql.org/docs/current/errcodes-appendix.html
  """

  alias FnTypes.Error

  def normalize(%Postgrex.Error{postgres: %{code: code} = postgres}, opts) do
    {type, error_code, message, recoverable} = map_postgres_code(code)

    Error.new(type, error_code,
      message: message,
      source: Postgrex,
      recoverable: recoverable,
      details: %{
        postgres_code: code,
        constraint: postgres[:constraint],
        table: postgres[:table],
        column: postgres[:column],
        schema: postgres[:schema],
        detail: postgres[:detail],
        hint: postgres[:hint]
      },
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  def normalize(%Postgrex.Error{} = error, opts) do
    # Connection or protocol error (no postgres map)
    Error.new(:external, :database_error,
      message: Exception.message(error),
      source: Postgrex,
      recoverable: true,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Integrity Constraint Violations (Class 23)
  defp map_postgres_code("23505"),
    do: {:conflict, :unique_violation, "Duplicate key value violates unique constraint", false}

  defp map_postgres_code("23503"),
    do: {:unprocessable, :foreign_key_violation, "Foreign key constraint violated", false}

  defp map_postgres_code("23502"),
    do:
      {:validation, :not_null_violation, "Null value in column violates not-null constraint", false}

  defp map_postgres_code("23514"),
    do: {:validation, :check_violation, "Check constraint violated", false}

  defp map_postgres_code("23P01"),
    do: {:conflict, :exclusion_violation, "Exclusion constraint violated", false}

  # Transaction Errors (Class 40)
  defp map_postgres_code("40001"),
    do:
      {:conflict, :serialization_failure, "Could not serialize access due to concurrent update",
       true}

  defp map_postgres_code("40P01"),
    do: {:conflict, :deadlock_detected, "Deadlock detected", true}

  defp map_postgres_code("40003"),
    do: {:conflict, :statement_completion_unknown, "Statement completion unknown", true}

  # Insufficient Resources (Class 53)
  defp map_postgres_code("53100"),
    do: {:external, :disk_full, "Disk full", false}

  defp map_postgres_code("53200"),
    do: {:external, :out_of_memory, "Out of memory", false}

  defp map_postgres_code("53300"),
    do: {:external, :too_many_connections, "Too many connections", true}

  # Operator Intervention (Class 57)
  defp map_postgres_code("57014"),
    do: {:timeout, :query_canceled, "Query was canceled", false}

  defp map_postgres_code("57P01"),
    do: {:external, :admin_shutdown, "Terminating connection due to administrator command", true}

  defp map_postgres_code("57P02"),
    do: {:external, :crash_shutdown, "Terminating connection due to crash", true}

  defp map_postgres_code("57P03"),
    do: {:external, :cannot_connect_now, "Cannot connect now", true}

  # Connection Exception (Class 08)
  defp map_postgres_code("08000"),
    do: {:network, :connection_exception, "Connection error", true}

  defp map_postgres_code("08003"),
    do: {:network, :connection_does_not_exist, "Connection does not exist", true}

  defp map_postgres_code("08006"),
    do: {:network, :connection_failure, "Connection failure", true}

  defp map_postgres_code("08001"),
    do: {:network, :sqlclient_unable_to_establish, "Unable to establish connection", true}

  defp map_postgres_code("08004"),
    do: {:unauthorized, :sqlserver_rejected, "Server rejected connection", false}

  defp map_postgres_code("08P01"),
    do: {:internal, :protocol_violation, "Protocol violation", false}

  # Syntax Error or Access Rule Violation (Class 42)
  defp map_postgres_code("42501"),
    do: {:forbidden, :insufficient_privilege, "Insufficient privilege", false}

  defp map_postgres_code("42601"),
    do: {:internal, :syntax_error, "SQL syntax error", false}

  defp map_postgres_code("42P01"),
    do: {:not_found, :undefined_table, "Table does not exist", false}

  defp map_postgres_code("42703"),
    do: {:internal, :undefined_column, "Column does not exist", false}

  defp map_postgres_code("42P02"),
    do: {:internal, :undefined_parameter, "Parameter does not exist", false}

  # Invalid Transaction State (Class 25)
  defp map_postgres_code("25001"),
    do: {:conflict, :active_sql_transaction, "Active SQL transaction", false}

  defp map_postgres_code("25002"),
    do: {:conflict, :branch_transaction_already_active, "Branch transaction already active", false}

  defp map_postgres_code("25P02"),
    do: {:conflict, :in_failed_sql_transaction, "Transaction is aborted", false}

  # Data Exception (Class 22)
  defp map_postgres_code("22001"),
    do: {:validation, :string_data_right_truncation, "String data too long", false}

  defp map_postgres_code("22003"),
    do: {:validation, :numeric_value_out_of_range, "Numeric value out of range", false}

  defp map_postgres_code("22007"),
    do: {:validation, :invalid_datetime_format, "Invalid datetime format", false}

  defp map_postgres_code("22008"),
    do: {:validation, :datetime_field_overflow, "Datetime field overflow", false}

  defp map_postgres_code("22012"),
    do: {:validation, :division_by_zero, "Division by zero", false}

  defp map_postgres_code("22P02"),
    do: {:validation, :invalid_text_representation, "Invalid input syntax", false}

  # Fallback for connection-class errors
  defp map_postgres_code("08" <> _),
    do: {:network, :connection_error, "Database connection error", true}

  # Fallback for constraint-class errors
  defp map_postgres_code("23" <> _),
    do: {:conflict, :constraint_violation, "Database constraint violation", false}

  # Generic fallback
  defp map_postgres_code(code),
    do: {:external, :database_error, "Database error (#{code})", false}
  end
end
