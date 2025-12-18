defmodule Events.Core.Repo.Retry do
  @moduledoc """
  Retry helpers for Repo operations with transient error handling.

  Delegates to `FnTypes.Retry` for core retry logic while providing
  Repo-specific convenience functions.

  ## Usage

      alias Events.Core.Repo.Retry

      # Simple query with retry
      Retry.with_retry(fn -> Repo.get(User, id) end)

      # Transaction with retry
      Retry.transaction_with_retry(fn ->
        user = Repo.get!(User, id)
        Repo.update(User.changeset(user, %{name: "new"}))
      end)

      # Multi with retry
      Retry.multi_with_retry(multi)

  ## Configuration

  - `:max_attempts` - Maximum number of attempts (default: 3)
  - `:base_delay` - Base delay in milliseconds (default: 100)
  - `:max_delay` - Maximum delay cap (default: 5000)
  - `:backoff` - Backoff strategy (default: :exponential)
  - `:on_retry` - Callback for retry events `(error, attempt, delay) -> any`

  See `FnTypes.Retry` for full options and backoff strategies.
  """

  alias FnTypes.Retry

  @type opts :: Retry.opts()

  @doc """
  Executes a function with automatic retry on transient database errors.

  Delegates to `FnTypes.Retry.execute/2`.

  ## Examples

      Retry.with_retry(fn -> Repo.get(User, id) end)

      Retry.with_retry(fn -> Repo.all(query) end,
        max_attempts: 5,
        on_retry: fn error, attempt, delay ->
          Logger.warning("Retrying after \#{inspect(error)}, attempt \#{attempt}")
        end
      )
  """
  @spec with_retry((-> term()), opts()) :: term()
  defdelegate with_retry(fun, opts \\ []), to: Retry, as: :execute

  @doc """
  Executes a transaction with automatic retry on transient errors.

  ## Examples

      Retry.transaction_with_retry(fn ->
        user = Repo.get!(User, id)
        Repo.update!(User.changeset(user, %{balance: user.balance - 100}))
      end)

      Retry.transaction_with_retry(fn -> ... end,
        max_attempts: 5,
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

    Retry.transaction(fun, Keyword.merge(retry_opts, [
      repo: Events.Core.Repo,
      transaction_opts: transaction_opts
    ]))
  end

  @doc """
  Executes a Multi with automatic retry on transient errors.

  ## Examples

      multi =
        Multi.new()
        |> Multi.insert(:user, user_changeset)
        |> Multi.insert(:profile, fn %{user: user} ->
          Profile.changeset(%Profile{}, %{user_id: user.id})
        end)

      Retry.multi_with_retry(multi)

      Retry.multi_with_retry(multi,
        retry_opts: [max_attempts: 5],
        transaction_opts: [timeout: 60_000]
      )
  """
  @spec multi_with_retry(Ecto.Multi.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def multi_with_retry(%Ecto.Multi{} = multi, opts \\ []) do
    retry_opts = Keyword.get(opts, :retry_opts, [])
    transaction_opts = Keyword.get(opts, :transaction_opts, [])

    Retry.execute(
      fn -> Events.Core.Repo.transaction(multi, transaction_opts) end,
      retry_opts
    )
  end

  @doc """
  Wraps a Repo operation to return `{:ok, result}` or `{:error, reason}`.

  Useful for operations that raise on failure (like `Repo.get!`).

  ## Examples

      Retry.safe(fn -> Repo.get!(User, id) end)
      #=> {:ok, %User{}} | {:error, %Ecto.NoResultsError{}}
  """
  @spec safe((-> term())) :: {:ok, term()} | {:error, term()}
  def safe(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    error -> {:error, error}
  end

  @doc """
  Executes a Repo operation safely with automatic retry.

  Combines `safe/1` with `with_retry/2`.

  ## Examples

      Retry.safe_with_retry(fn -> Repo.get!(User, id) end)
      #=> {:ok, %User{}} | {:error, reason}
  """
  @spec safe_with_retry((-> term()), opts()) :: {:ok, term()} | {:error, term()}
  def safe_with_retry(fun, opts \\ []) when is_function(fun, 0) do
    Retry.execute(fn -> safe(fun) end, opts)
  end

  @doc """
  Checks if an error is a database deadlock.

  ## Examples

      Retry.deadlock?(%DBConnection.ConnectionError{reason: :deadlock})
      #=> true
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
end
