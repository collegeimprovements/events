defmodule OmCrud.Atomic do
  @moduledoc """
  Atomic operations helper for executing multiple CRUD operations in a transaction.

  Provides a clean, functional approach to atomic operations with automatic
  error handling and rollback.

  ## Basic Usage

      import OmCrud.Atomic

      atomic fn ->
        with {:ok, user} <- OmCrud.create(User, user_attrs),
             {:ok, account} <- OmCrud.create(Account, %{user_id: user.id}) do
          {:ok, %{user: user, account: account}}
        end
      end

  ## With Step Functions

  Use `step!/1` or `step!/2` for cleaner code that raises on error:

      atomic fn ->
        user = step!(OmCrud.create(User, user_attrs))
        account = step!(OmCrud.create(Account, %{user_id: user.id}))
        settings = step!(OmCrud.create(Settings, %{user_id: user.id}))

        {:ok, %{user: user, account: account, settings: settings}}
      end

  ## Named Steps

  For better error reporting, use named steps:

      atomic fn ->
        user = step!(:create_user, OmCrud.create(User, user_attrs))
        account = step!(:create_account, OmCrud.create(Account, %{user_id: user.id}))

        {:ok, %{user: user, account: account}}
      end

  On error, returns `{:error, %OmCrud.Error{step: :create_account, ...}}`.

  ## Optional Steps

  Use `optional_step!/2` for steps that may return `:not_found`:

      atomic fn ->
        user = step!(:create_user, OmCrud.create(User, attrs))
        # Returns nil if org not found, doesn't fail
        org = optional_step!(:fetch_org, OmCrud.fetch(Org, org_id))

        {:ok, %{user: user, org: org}}
      end

  ## With Context

  Use `atomic_with_context/2` to pass initial context:

      atomic_with_context(%{org_id: org_id}, fn ctx ->
        user = step!(OmCrud.create(User, Map.put(user_attrs, :org_id, ctx.org_id)))
        {:ok, user}
      end)

  ## Options

  - `:repo` - The repo to use for the transaction (default: from config)
  - `:timeout` - Transaction timeout in milliseconds (default: 15_000)
  - `:mode` - Transaction mode (PostgreSQL): `:default` | `:read_only` | `:read_write`
  - `:telemetry_prefix` - Custom telemetry prefix (default: `[:om_crud, :atomic]`)

  ## Telemetry

  Atomic operations emit telemetry events:

  - `[:om_crud, :atomic, :start]` - When transaction starts
  - `[:om_crud, :atomic, :stop]` - When transaction completes (success or rollback)
  - `[:om_crud, :atomic, :exception]` - When an exception occurs

  Metadata includes: `:repo`, `:timeout`, `:result` (on stop)
  """

  alias OmCrud.Error

  require Logger

  @type atomic_result :: {:ok, term()} | {:error, Error.t() | term()}

  @default_timeout 15_000
  @default_telemetry_prefix [:om_crud, :atomic]

  @doc """
  Executes a function atomically in a database transaction.

  The function should return `{:ok, result}` on success or `{:error, reason}` on failure.
  Any exception raised will cause a rollback.

  ## Examples

      atomic(fn ->
        with {:ok, user} <- OmCrud.create(User, attrs) do
          {:ok, user}
        end
      end)

      # With options
      atomic([repo: MyApp.Repo, timeout: 30_000], fn ->
        # ...
      end)
  """
  @spec atomic(keyword() | function(), function() | nil) :: atomic_result()
  def atomic(opts_or_fun, fun \\ nil)

  def atomic(fun, nil) when is_function(fun, 0) do
    atomic([], fun)
  end

  def atomic(opts, fun) when is_list(opts) and is_function(fun, 0) do
    repo = Keyword.get_lazy(opts, :repo, &default_repo/0)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    mode = Keyword.get(opts, :mode)
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix, @default_telemetry_prefix)

    meta = %{repo: repo, timeout: timeout, mode: mode}
    start_time = System.monotonic_time()

    :telemetry.execute(telemetry_prefix ++ [:start], %{system_time: System.system_time()}, meta)

    try do
      transaction_opts = build_transaction_opts(timeout, mode)

      result =
        repo.transaction(
          fn ->
            case fun.() do
              {:ok, result} ->
                result

              {:error, reason} ->
                repo.rollback(reason)

              other ->
                Logger.warning(
                  "[OmCrud.Atomic] Unexpected return value from atomic function: #{inspect(other)}. " <>
                    "Expected {:ok, result} or {:error, reason}. Treating as success."
                )

                other
            end
          end,
          transaction_opts
        )
        |> normalize_result()

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        telemetry_prefix ++ [:stop],
        %{duration: duration, duration_ms: System.convert_time_unit(duration, :native, :millisecond)},
        Map.put(meta, :result, result_type(result))
      )

      result
    rescue
      e in [__MODULE__.StepError] ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          telemetry_prefix ++ [:stop],
          %{duration: duration, duration_ms: System.convert_time_unit(duration, :native, :millisecond)},
          Map.merge(meta, %{result: :error, step: e.error.step})
        )

        {:error, e.error}

      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          telemetry_prefix ++ [:exception],
          %{duration: duration, duration_ms: System.convert_time_unit(duration, :native, :millisecond)},
          Map.merge(meta, %{exception: e.__struct__, message: Exception.message(e)})
        )

        {:error,
         Error.transaction_error(e,
           operation: :atomic,
           metadata: %{exception: e.__struct__, message: Exception.message(e)}
         )}
    end
  end

  @doc """
  Executes an atomic operation with initial context.

  ## Examples

      atomic_with_context(%{org_id: 123}, fn ctx ->
        user = step!(OmCrud.create(User, %{org_id: ctx.org_id, name: "Test"}))
        {:ok, user}
      end)

      atomic_with_context(%{org_id: 123}, [timeout: 30_000], fn ctx ->
        user = step!(OmCrud.create(User, %{org_id: ctx.org_id, name: "Test"}))
        {:ok, user}
      end)
  """
  @spec atomic_with_context(map(), function()) :: atomic_result()
  def atomic_with_context(context, fun) when is_map(context) and is_function(fun, 1) do
    atomic([], fn -> fun.(context) end)
  end

  @spec atomic_with_context(map(), keyword(), function()) :: atomic_result()
  def atomic_with_context(context, opts, fun)
      when is_map(context) and is_list(opts) and is_function(fun, 1) do
    atomic(opts, fn -> fun.(context) end)
  end

  # ─────────────────────────────────────────────────────────────
  # Raising Step Functions
  # ─────────────────────────────────────────────────────────────

  @doc """
  Unwraps a result tuple, raising `StepError` on error.

  Use inside `atomic/1` for cleaner code:

      atomic fn ->
        user = step!(OmCrud.create(User, attrs))
        account = step!(OmCrud.create(Account, %{user_id: user.id}))
        {:ok, %{user: user, account: account}}
      end

  ## Examples

      step!({:ok, value})
      #=> value

      step!({:error, reason})
      #=> raises StepError
  """
  @spec step!(atomic_result()) :: term()
  def step!({:ok, value}), do: value

  def step!({:error, %Error{} = error}) do
    raise __MODULE__.StepError, error: error
  end

  def step!({:error, %Ecto.Changeset{} = changeset}) do
    error = Error.from_changeset(changeset)
    raise __MODULE__.StepError, error: error
  end

  def step!({:error, reason}) do
    error = Error.wrap(reason, operation: :step)
    raise __MODULE__.StepError, error: error
  end

  @doc """
  Unwraps a result tuple with a named step, raising `StepError` on error.

  The step name is included in the error for better debugging:

      atomic fn ->
        user = step!(:create_user, OmCrud.create(User, attrs))
        account = step!(:create_account, OmCrud.create(Account, %{user_id: user.id}))
        {:ok, %{user: user, account: account}}
      end

  ## Examples

      step!(:fetch_user, {:ok, user})
      #=> user

      step!(:fetch_user, {:error, :not_found})
      #=> raises StepError with step: :fetch_user
  """
  @spec step!(atom(), atomic_result()) :: term()
  def step!(step_name, {:ok, value}) when is_atom(step_name), do: value

  def step!(step_name, {:error, reason}) when is_atom(step_name) do
    error = Error.step_failed(step_name, {:error, reason})
    raise __MODULE__.StepError, error: error
  end

  @doc """
  Unwraps a result, returning `nil` for `:not_found` errors instead of raising.

  Useful for optional fetches that shouldn't fail the transaction:

      atomic fn ->
        user = step!(:create_user, OmCrud.create(User, attrs))
        # Returns nil if not found, doesn't fail the transaction
        existing_org = optional_step!(:fetch_org, OmCrud.fetch(Org, org_id))

        org = existing_org || step!(:create_org, OmCrud.create(Org, %{owner_id: user.id}))
        {:ok, %{user: user, org: org}}
      end

  ## Examples

      optional_step!(:fetch, {:ok, value})
      #=> value

      optional_step!(:fetch, {:error, :not_found})
      #=> nil

      optional_step!(:fetch, {:error, %OmCrud.Error{type: :not_found}})
      #=> nil

      optional_step!(:fetch, {:error, :database_error})
      #=> raises StepError (non-not_found errors still raise)
  """
  @spec optional_step!(atom(), atomic_result()) :: term() | nil
  def optional_step!(step_name, {:ok, value}) when is_atom(step_name), do: value

  def optional_step!(step_name, {:error, :not_found}) when is_atom(step_name), do: nil

  def optional_step!(step_name, {:error, %Error{type: :not_found}}) when is_atom(step_name),
    do: nil

  def optional_step!(step_name, {:error, reason}) when is_atom(step_name) do
    error = Error.step_failed(step_name, {:error, reason})
    raise __MODULE__.StepError, error: error
  end

  # ─────────────────────────────────────────────────────────────
  # Non-Raising Step Functions
  # ─────────────────────────────────────────────────────────────

  @doc """
  Evaluates a result and returns it with step context, without raising.

  Unlike `step!/2`, this returns the result tuple, allowing you to handle
  errors inline:

      atomic fn ->
        case step(:fetch_user, OmCrud.fetch(User, id)) do
          {:ok, user} ->
            do_something(user)
          {:error, %Error{type: :not_found}} ->
            create_default_user()
          {:error, error} ->
            {:error, error}
        end
      end

  ## Examples

      step(:fetch, {:ok, user})
      #=> {:ok, user}

      step(:fetch, {:error, :not_found})
      #=> {:error, %OmCrud.Error{type: :step_failed, step: :fetch, ...}}
  """
  @spec step(atom(), atomic_result()) :: atomic_result()
  def step(step_name, {:ok, value}) when is_atom(step_name), do: {:ok, value}

  def step(step_name, {:error, reason}) when is_atom(step_name) do
    {:error, Error.step_failed(step_name, {:error, reason})}
  end

  @doc """
  Executes a step function, returning the result or an error tuple.

  Similar to `step/2` but takes a function instead of a result:

      atomic fn ->
        case run_step(:fetch_user, fn -> OmCrud.fetch(User, id) end) do
          {:ok, user} -> do_something(user)
          {:error, %Error{type: :not_found}} -> create_default_user()
          {:error, error} -> {:error, error}
        end
      end
  """
  @spec run_step(atom(), function()) :: atomic_result()
  def run_step(step_name, fun) when is_atom(step_name) and is_function(fun, 0) do
    step(step_name, fun.())
  end

  # ─────────────────────────────────────────────────────────────
  # Accumulator Pattern
  # ─────────────────────────────────────────────────────────────

  @doc """
  Accumulates results from multiple steps into a map.

  Useful for building up context across steps:

      atomic fn ->
        %{}
        |> accumulate(:user, fn -> OmCrud.create(User, user_attrs) end)
        |> accumulate(:account, fn ctx -> OmCrud.create(Account, %{user_id: ctx.user.id}) end)
        |> accumulate(:settings, fn ctx -> OmCrud.create(Settings, %{user_id: ctx.user.id}) end)
        |> finalize()
      end
  """
  @spec accumulate(map(), atom(), (map() -> atomic_result())) :: map()
  def accumulate(context, step_name, fun) when is_map(context) and is_function(fun, 1) do
    result = step!(step_name, fun.(context))
    Map.put(context, step_name, result)
  end

  @spec accumulate(map(), atom(), (-> atomic_result())) :: map()
  def accumulate(context, step_name, fun) when is_map(context) and is_function(fun, 0) do
    result = step!(step_name, fun.())
    Map.put(context, step_name, result)
  end

  @doc """
  Accumulates an optional step, storing `nil` if not found.

      atomic fn ->
        %{}
        |> accumulate(:user, fn -> OmCrud.create(User, attrs) end)
        |> accumulate_optional(:org, fn ctx -> OmCrud.fetch(Org, ctx.user.org_id) end)
        |> finalize()
      end
      # Returns {:ok, %{user: user, org: nil}} if org not found
  """
  @spec accumulate_optional(map(), atom(), (map() -> atomic_result())) :: map()
  def accumulate_optional(context, step_name, fun) when is_map(context) and is_function(fun, 1) do
    result = optional_step!(step_name, fun.(context))
    Map.put(context, step_name, result)
  end

  @spec accumulate_optional(map(), atom(), (-> atomic_result())) :: map()
  def accumulate_optional(context, step_name, fun) when is_map(context) and is_function(fun, 0) do
    result = optional_step!(step_name, fun.())
    Map.put(context, step_name, result)
  end

  @doc """
  Finalizes an accumulated context into a success tuple.

  ## Examples

      %{user: user, account: account}
      |> finalize()
      #=> {:ok, %{user: user, account: account}}

      %{user: user}
      |> finalize(:user)
      #=> {:ok, user}
  """
  @spec finalize(map()) :: {:ok, map()}
  def finalize(context) when is_map(context), do: {:ok, context}

  @spec finalize(map(), atom()) :: {:ok, term()}
  def finalize(context, key) when is_map(context) and is_atom(key) do
    {:ok, Map.fetch!(context, key)}
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp build_transaction_opts(timeout, nil), do: [timeout: timeout]

  defp build_transaction_opts(timeout, :read_only),
    do: [timeout: timeout, mode: :transaction, isolation_level: :read_committed]

  defp build_transaction_opts(timeout, :read_write),
    do: [timeout: timeout, mode: :transaction]

  defp build_transaction_opts(timeout, _), do: [timeout: timeout]

  defp normalize_result({:ok, result}), do: {:ok, result}

  defp normalize_result({:error, %Error{} = error}), do: {:error, error}

  defp normalize_result({:error, %Ecto.Changeset{} = changeset}) do
    {:error, Error.from_changeset(changeset)}
  end

  defp normalize_result({:error, reason}) do
    {:error, Error.wrap(reason, operation: :atomic)}
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:error, _}), do: :error

  defp default_repo do
    Application.get_env(:om_crud, :default_repo) ||
      raise "No default repo configured. Set :om_crud, :default_repo or pass :repo option."
  end
end

defmodule OmCrud.Atomic.StepError do
  @moduledoc """
  Exception raised when a step fails inside an atomic block.

  This is an internal exception used to trigger transaction rollback.
  It is caught by `atomic/1` and converted to an error tuple.
  """

  defexception [:error]

  @impl true
  def message(%{error: error}) do
    "Atomic step failed: #{OmCrud.Error.message(error)}"
  end
end
