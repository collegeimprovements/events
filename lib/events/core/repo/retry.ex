defmodule Events.Core.Repo.Retry do
  @moduledoc """
  Retry helpers for Repo operations with transient error handling.

  Provides automatic retry logic for database operations that may fail
  due to transient conditions like deadlocks, connection timeouts, or
  temporary unavailability.

  ## Usage

      alias Events.Core.Repo.Retry

      # Simple query with retry
      Retry.with_retry(fn ->
        Repo.get(User, id)
      end)

      # Transaction with retry
      Retry.transaction_with_retry(fn ->
        user = Repo.get!(User, id)
        Repo.update(User.changeset(user, %{name: "new"}))
      end)

      # Custom retry options
      Retry.with_retry(fn -> Repo.all(User) end,
        max_attempts: 5,
        base_delay: 100
      )

  ## Configuration

  - `:max_attempts` - Maximum number of attempts (default: 3)
  - `:base_delay` - Base delay in milliseconds (default: 100)
  - `:max_delay` - Maximum delay cap (default: 5000)
  - `:on_retry` - Callback for retry events `(error, attempt, delay) -> any`

  ## Retried Errors

  The following transient errors trigger automatic retry:

  - `DBConnection.ConnectionError` with reason `:deadlock`
  - `DBConnection.ConnectionError` with pool timeout
  - `Postgrex.Error` with deadlock or serialization failure
  - Connection reset/refused errors
  """

  require Logger

  alias FnTypes.Protocols.Recoverable
  alias FnTypes.Protocols.Recoverable.Helpers

  @type opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          on_retry: (term(), pos_integer(), pos_integer() -> any())
        ]

  @default_max_attempts 3
  @default_base_delay 100
  @default_max_delay 5_000

  @doc """
  Executes a function with automatic retry on transient database errors.

  ## Examples

      # Basic usage
      Retry.with_retry(fn -> Repo.get(User, id) end)

      # With options
      Retry.with_retry(fn -> Repo.all(query) end,
        max_attempts: 5,
        on_retry: fn error, attempt, delay ->
          Logger.warning("Retrying after \#{inspect(error)}, attempt \#{attempt}")
        end
      )

  ## Return Values

  - Returns the result of the function on success
  - Returns `{:error, error}` after all retries exhausted
  - Non-recoverable errors are returned immediately without retry
  """
  @spec with_retry((-> term()), opts()) :: term()
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    on_retry = Keyword.get(opts, :on_retry)

    do_with_retry(fun, 1, max_attempts, base_delay, max_delay, on_retry)
  end

  @doc """
  Executes a transaction with automatic retry on transient errors.

  Wraps `Repo.transaction/2` with retry logic. The entire transaction
  is retried if a transient error occurs.

  ## Examples

      Retry.transaction_with_retry(fn ->
        user = Repo.get!(User, id)
        changeset = User.changeset(user, %{balance: user.balance - 100})
        Repo.update!(changeset)
      end)

      # With transaction options
      Retry.transaction_with_retry(
        fn -> ... end,
        retry_opts: [max_attempts: 5],
        transaction_opts: [timeout: 30_000]
      )

  ## Options

  - `:retry_opts` - Options for retry logic (see `with_retry/2`)
  - `:transaction_opts` - Options passed to `Repo.transaction/2`
  """
  @spec transaction_with_retry((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction_with_retry(fun, opts \\ []) when is_function(fun, 0) do
    retry_opts = Keyword.get(opts, :retry_opts, [])
    transaction_opts = Keyword.get(opts, :transaction_opts, [])

    with_retry(
      fn ->
        Events.Core.Repo.transaction(fun, transaction_opts)
      end,
      retry_opts
    )
  end

  @doc """
  Executes a Multi with automatic retry on transient errors.

  Wraps `Repo.transaction/2` for Multi operations with retry logic.

  ## Examples

      multi =
        Multi.new()
        |> Multi.insert(:user, user_changeset)
        |> Multi.insert(:profile, fn %{user: user} ->
          Profile.changeset(%Profile{}, %{user_id: user.id})
        end)

      Retry.multi_with_retry(multi)

      # With options
      Retry.multi_with_retry(multi,
        retry_opts: [max_attempts: 5],
        transaction_opts: [timeout: 60_000]
      )
  """
  @spec multi_with_retry(Ecto.Multi.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def multi_with_retry(%Ecto.Multi{} = multi, opts \\ []) do
    retry_opts = Keyword.get(opts, :retry_opts, [])
    transaction_opts = Keyword.get(opts, :transaction_opts, [])

    with_retry(
      fn ->
        Events.Core.Repo.transaction(multi, transaction_opts)
      end,
      retry_opts
    )
  end

  @doc """
  Wraps a Repo operation to return `{:ok, result}` or `{:error, reason}`.

  Useful for operations that raise on failure (like `Repo.get!`).

  ## Examples

      Retry.safe(fn -> Repo.get!(User, id) end)
      #=> {:ok, %User{}} | {:error, %Ecto.NoResultsError{}}

      Retry.safe(fn -> Repo.insert!(changeset) end)
      #=> {:ok, %User{}} | {:error, %Ecto.InvalidChangesetError{}}
  """
  @spec safe((-> term())) :: {:ok, term()} | {:error, term()}
  def safe(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    error -> {:error, error}
  end

  @doc """
  Executes a Repo operation safely with automatic retry.

  Combines `safe/1` and `with_retry/2`.

  ## Examples

      Retry.safe_with_retry(fn -> Repo.get!(User, id) end)
      #=> {:ok, %User{}} | {:error, reason}
  """
  @spec safe_with_retry((-> term()), opts()) :: {:ok, term()} | {:error, term()}
  def safe_with_retry(fun, opts \\ []) when is_function(fun, 0) do
    with_retry(fn -> safe(fun) end, opts)
  end

  @doc """
  Checks if an error is a database deadlock.

  ## Examples

      Retry.deadlock?(%DBConnection.ConnectionError{reason: :deadlock})
      #=> true

      Retry.deadlock?(%Ecto.NoResultsError{})
      #=> false
  """
  @spec deadlock?(term()) :: boolean()
  def deadlock?(%DBConnection.ConnectionError{message: message}) do
    String.contains?(message, "deadlock")
  end

  def deadlock?(%Postgrex.Error{postgres: %{code: code}}) do
    code in [:deadlock_detected, :serialization_failure]
  end

  def deadlock?(_), do: false

  @doc """
  Checks if an error is a connection pool timeout.

  ## Examples

      Retry.pool_timeout?(%DBConnection.ConnectionError{...})
      #=> true | false
  """
  @spec pool_timeout?(term()) :: boolean()
  def pool_timeout?(%DBConnection.ConnectionError{message: message}) do
    String.contains?(message, "timeout") or String.contains?(message, "pool")
  end

  def pool_timeout?(_), do: false

  # ============================================
  # Private Implementation
  # ============================================

  defp do_with_retry(fun, attempt, max_attempts, base_delay, max_delay, on_retry) do
    try do
      case fun.() do
        {:error, error} = result ->
          handle_error(error, result, fun, attempt, max_attempts, base_delay, max_delay, on_retry)

        result ->
          result
      end
    rescue
      error ->
        handle_error(
          error,
          {:error, error},
          fun,
          attempt,
          max_attempts,
          base_delay,
          max_delay,
          on_retry
        )
    catch
      :exit, reason ->
        handle_error(
          {:exit, reason},
          {:error, {:exit, reason}},
          fun,
          attempt,
          max_attempts,
          base_delay,
          max_delay,
          on_retry
        )
    end
  end

  defp handle_error(error, result, fun, attempt, max_attempts, base_delay, max_delay, on_retry) do
    cond do
      attempt >= max_attempts ->
        log_exhausted(error, attempt)
        result

      not Recoverable.recoverable?(error) ->
        log_not_recoverable(error)
        result

      true ->
        delay = calculate_delay(error, attempt, base_delay, max_delay)
        maybe_call_on_retry(on_retry, error, attempt, delay)
        log_retry(error, attempt, delay)
        Process.sleep(delay)
        do_with_retry(fun, attempt + 1, max_attempts, base_delay, max_delay, on_retry)
    end
  end

  defp calculate_delay(error, attempt, base_delay, max_delay) do
    # Use protocol delay if available, otherwise calculate
    protocol_delay = Recoverable.retry_delay(error, attempt)

    delay =
      if protocol_delay > 0 do
        protocol_delay
      else
        FnTypes.Protocols.Recoverable.Backoff.exponential(attempt, base: base_delay, max: max_delay)
      end

    min(delay, max_delay)
  end

  defp maybe_call_on_retry(nil, _error, _attempt, _delay), do: :ok

  defp maybe_call_on_retry(callback, error, attempt, delay) when is_function(callback, 3) do
    callback.(error, attempt, delay)
  end

  defp log_retry(error, attempt, delay) do
    Logger.debug(fn ->
      "[Repo.Retry] Retrying after #{inspect(error.__struct__)}, attempt #{attempt}, delay #{delay}ms"
    end)

    Helpers.emit_telemetry(error, %{
      attempt: attempt,
      delay: delay,
      action: :retry
    })
  end

  defp log_exhausted(error, attempts) do
    Logger.warning(fn ->
      "[Repo.Retry] Max attempts (#{attempts}) exhausted for #{inspect(error.__struct__)}"
    end)

    Helpers.emit_telemetry(error, %{
      attempts: attempts,
      action: :exhausted
    })
  end

  defp log_not_recoverable(error) do
    Logger.debug(fn ->
      "[Repo.Retry] Non-recoverable error: #{inspect(error.__struct__)}"
    end)
  end
end
