# Implementations for Ecto-related errors

# Ecto.StaleEntryError - Optimistic locking failure
if Code.ensure_loaded?(Ecto.StaleEntryError) do
  defimpl Events.Recoverable, for: Ecto.StaleEntryError do
    @moduledoc """
    Recoverable implementation for Ecto stale entry errors.

    Stale entry errors occur with optimistic locking when the record
    has been modified by another process. These should NOT be auto-retried
    as the application needs to handle the conflict explicitly.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end

# Ecto.NoResultsError - Record not found
if Code.ensure_loaded?(Ecto.NoResultsError) do
  defimpl Events.Recoverable, for: Ecto.NoResultsError do
    @moduledoc """
    Recoverable implementation for Ecto no results errors.

    These errors indicate the requested record doesn't exist.
    Not recoverable - the record either exists or it doesn't.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end

# Ecto.MultipleResultsError - More than one record found
if Code.ensure_loaded?(Ecto.MultipleResultsError) do
  defimpl Events.Recoverable, for: Ecto.MultipleResultsError do
    @moduledoc """
    Recoverable implementation for Ecto multiple results errors.

    These indicate a data integrity issue - not recoverable by retry.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end

# Ecto.ConstraintError - Database constraint violation
if Code.ensure_loaded?(Ecto.ConstraintError) do
  defimpl Events.Recoverable, for: Ecto.ConstraintError do
    @moduledoc """
    Recoverable implementation for Ecto constraint errors.

    Constraint violations are typically permanent - the data violates
    a database rule and retrying won't help.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end

# Ecto.InvalidChangesetError
if Code.ensure_loaded?(Ecto.InvalidChangesetError) do
  defimpl Events.Recoverable, for: Ecto.InvalidChangesetError do
    @moduledoc """
    Recoverable implementation for invalid changeset errors.

    Validation failures are permanent - the input is invalid.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end

# Ecto.Query.CastError
if Code.ensure_loaded?(Ecto.Query.CastError) do
  defimpl Events.Recoverable, for: Ecto.Query.CastError do
    @moduledoc """
    Recoverable implementation for query cast errors.

    Type casting failures are permanent - the input type is wrong.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end

# Ecto.QueryError
if Code.ensure_loaded?(Ecto.QueryError) do
  defimpl Events.Recoverable, for: Ecto.QueryError do
    @moduledoc """
    Recoverable implementation for query errors.

    Query construction errors are permanent - the query is malformed.
    """

    @impl true
    def recoverable?(_), do: false

    @impl true
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(_, _), do: 0

    @impl true
    def max_attempts(_), do: 1

    @impl true
    def trips_circuit?(_), do: false

    @impl true
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end
