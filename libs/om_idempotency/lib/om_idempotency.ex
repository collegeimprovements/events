defmodule OmIdempotency do
  @moduledoc """
  Database-backed idempotency key management for safe API retries.

  Provides deduplication for external API calls, ensuring that retried requests
  don't cause duplicate side effects.

  ## How It Works

  1. Before making an API call, check if the idempotency key exists
  2. If it exists and is completed, return the cached response
  3. If it exists and is processing, wait or return conflict
  4. If it doesn't exist, create a record and proceed with the call
  5. After the call, update the record with the response

  ## Setup

  Add the idempotency_records table to your database:

      mix ecto.gen.migration add_idempotency_records

  Then use the migration helper:

      defmodule MyApp.Repo.Migrations.AddIdempotencyRecords do
        use Ecto.Migration

        def change do
          OmIdempotency.Migration.create_table()
        end
      end

  Configure your repo:

      config :om_idempotency, repo: MyApp.Repo

  ## Usage

  ### Basic Usage

      # Generate a key for an operation
      key = OmIdempotency.generate_key(:create_customer, user_id: 123)

      # Execute with idempotency protection
      OmIdempotency.execute(key, fn ->
        StripeClient.create_customer(%{email: "user@example.com"})
      end)

  ### Manual Control

      # Check if already executed
      case OmIdempotency.get(key) do
        {:ok, %{state: :completed, response: response}} ->
          {:ok, response}

        {:ok, %{state: :processing}} ->
          {:error, :in_progress}

        {:error, :not_found} ->
          # Safe to execute
          with {:ok, record} <- OmIdempotency.create(key, scope: "stripe"),
               {:ok, response} <- make_api_call(),
               {:ok, _} <- OmIdempotency.complete(record, response) do
            {:ok, response}
          end
      end

  ## States

  Idempotency records go through these states:

      pending -> processing -> completed
                     |
                     +------> failed
                     |
                     +------> expired

  ## Configuration

      config :om_idempotency,
        repo: MyApp.Repo,
        ttl: {24, :hours},
        lock_timeout: {30, :seconds},
        telemetry_prefix: [:my_app, :idempotency]
  """

  require Logger

  alias OmIdempotency.Record

  import Ecto.Query

  @default_ttl_ms 24 * 60 * 60 * 1000
  @default_lock_timeout_ms 30 * 1000

  @type key :: String.t()
  @type scope :: String.t() | nil
  @type state :: :pending | :processing | :completed | :failed | :expired

  @type execute_opts :: [
          scope: String.t(),
          ttl: pos_integer(),
          on_duplicate: :return | :wait | :error,
          metadata: map(),
          repo: module()
        ]

  # ============================================
  # Configuration
  # ============================================

  @doc false
  def repo(opts \\ []) do
    Keyword.get_lazy(opts, :repo, fn ->
      Application.get_env(:om_idempotency, :repo) ||
        raise ArgumentError, """
        No repo configured for OmIdempotency.

        Configure in your config:

            config :om_idempotency, repo: MyApp.Repo

        Or pass :repo option to functions:

            OmIdempotency.execute(key, fun, repo: MyApp.Repo)
        """
    end)
  end

  defp telemetry_prefix do
    Application.get_env(:om_idempotency, :telemetry_prefix, [:om_idempotency])
  end

  # ============================================
  # Key Generation
  # ============================================

  @doc """
  Generates an idempotency key.

  ## Options

  - `:scope` - Prefix for the key (e.g., "stripe", "sendgrid")

  ## Examples

      # UUIDv7 key
      OmIdempotency.generate_key()
      #=> "01913a77-7e30-7f4a-8c1e-b5f3c8d9e0f1"

      # From operation and params
      OmIdempotency.generate_key(:create_customer, user_id: 123)
      #=> "create_customer:user_id=123"

      # With scope
      OmIdempotency.generate_key(:charge, order_id: 456, scope: "stripe")
      #=> "stripe:charge:order_id=456"
  """
  @spec generate_key() :: key()
  def generate_key do
    Ecto.UUID.generate()
  end

  @spec generate_key(atom(), keyword()) :: key()
  def generate_key(operation, params \\ []) when is_atom(operation) do
    {scope, params} = Keyword.pop(params, :scope)

    base_key =
      params
      |> Keyword.delete(:scope)
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> case do
        [] -> Atom.to_string(operation)
        parts -> "#{operation}:" <> Enum.join(parts, ":")
      end

    case scope do
      nil -> base_key
      s -> "#{s}:#{base_key}"
    end
  end

  @doc """
  Generates a deterministic key by hashing the operation and parameters.

  Useful when parameters are complex or contain sensitive data.

  ## Examples

      OmIdempotency.hash_key(:create_customer, %{email: "user@example.com", name: "Jane"})
      #=> "create_customer:a1b2c3d4e5f6..."
  """
  @spec hash_key(atom(), term(), keyword()) :: key()
  def hash_key(operation, params, opts \\ []) do
    scope = Keyword.get(opts, :scope)

    hash =
      :crypto.hash(:sha256, :erlang.term_to_binary({operation, params}))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)

    base_key = "#{operation}:#{hash}"

    case scope do
      nil -> base_key
      s -> "#{s}:#{base_key}"
    end
  end

  # ============================================
  # Core Operations
  # ============================================

  @doc """
  Executes a function with idempotency protection.

  If the key has already been used successfully, returns the cached response.
  If the key is currently being processed, handles according to `:on_duplicate`.
  If the key is new, executes the function and caches the response.

  ## Options

  - `:scope` - Scope for the key (default: nil)
  - `:ttl` - Time-to-live in milliseconds (default: 24 hours)
  - `:on_duplicate` - How to handle in-progress duplicates:
    - `:return` - Return the existing record (default)
    - `:wait` - Wait for completion
    - `:error` - Return error immediately
  - `:metadata` - Additional metadata to store
  - `:repo` - Ecto repo module (default: configured repo)

  ## Examples

      OmIdempotency.execute("order_123_charge", fn ->
        Stripe.create_charge(%{amount: 1000})
      end)

      OmIdempotency.execute("order_123_charge", fn ->
        Stripe.create_charge(%{amount: 1000})
      end, scope: "stripe", on_duplicate: :wait)
  """
  @spec execute(key(), (-> {:ok, term()} | {:error, term()}), execute_opts()) ::
          {:ok, term()} | {:error, term()}
  def execute(key, fun, opts \\ []) when is_binary(key) and is_function(fun, 0) do
    scope = Keyword.get(opts, :scope)
    on_duplicate = Keyword.get(opts, :on_duplicate, :return)
    metadata = Keyword.get(opts, :metadata, %{})

    start_time = System.monotonic_time()
    emit_telemetry(:start, key, scope, %{})

    result =
      case get(key, scope, opts) do
        {:ok, %Record{state: :completed, response: response}} ->
          Logger.debug("[OmIdempotency] Cache hit for key=#{key}")
          emit_telemetry(:cache_hit, key, scope, %{})
          deserialize_response(response)

        {:ok, %Record{state: :failed, error: error}} ->
          Logger.debug("[OmIdempotency] Previous failure for key=#{key}")
          emit_telemetry(:cache_hit_failed, key, scope, %{})
          {:error, error}

        {:ok, %Record{state: :processing} = record} ->
          handle_in_progress(record, fun, on_duplicate, opts)

        {:ok, %Record{state: :pending} = record} ->
          execute_with_record(record, fun, opts)

        {:error, :not_found} ->
          execute_new(key, scope, metadata, fun, opts)
      end

    duration = System.monotonic_time() - start_time
    emit_telemetry(:stop, key, scope, %{duration: duration})

    result
  end

  @doc """
  Gets an idempotency record by key.

  ## Examples

      OmIdempotency.get("order_123_charge")
      #=> {:ok, %Record{state: :completed, ...}}

      OmIdempotency.get("unknown_key")
      #=> {:error, :not_found}
  """
  @spec get(key(), scope(), keyword()) :: {:ok, Record.t()} | {:error, :not_found}
  def get(key, scope \\ nil, opts \\ []) do
    query =
      from(r in Record,
        where: r.key == ^key,
        where: r.scope == ^scope or (is_nil(r.scope) and is_nil(^scope))
      )

    case repo(opts).one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Creates a new idempotency record in pending state.

  ## Examples

      OmIdempotency.create("order_123_charge", scope: "stripe")
      #=> {:ok, %Record{state: :pending, ...}}
  """
  @spec create(key(), keyword()) ::
          {:ok, Record.t()} | {:error, :already_exists | Ecto.Changeset.t()}
  def create(key, opts \\ []) do
    scope = Keyword.get(opts, :scope)
    metadata = Keyword.get(opts, :metadata, %{})
    ttl = Keyword.get(opts, :ttl, @default_ttl_ms)

    attrs = %{
      key: key,
      scope: scope,
      state: :pending,
      metadata: metadata,
      expires_at: DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    }

    %Record{}
    |> Record.changeset(attrs)
    |> repo(opts).insert()
    |> case do
      {:ok, record} ->
        {:ok, record}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :key) do
          {:error, :already_exists}
        else
          error
        end
    end
  end

  @doc """
  Transitions a record to processing state.

  Uses optimistic locking to prevent race conditions.
  """
  @spec start_processing(Record.t(), keyword()) ::
          {:ok, Record.t()} | {:error, :already_processing | :stale}
  def start_processing(%Record{id: id, state: current_state, version: version} = record, opts \\ []) do
    now = DateTime.utc_now()
    lock_until = DateTime.add(now, @default_lock_timeout_ms, :millisecond)

    query =
      from(r in Record,
        where: r.id == ^id,
        where: r.version == ^version,
        where: r.state in [:pending, :processing]
      )

    case repo(opts).update_all(query,
           set: [
             state: :processing,
             started_at: now,
             locked_until: lock_until,
             version: version + 1,
             updated_at: now
           ]
         ) do
      {1, _} ->
        {:ok,
         %Record{
           record
           | state: :processing,
             started_at: now,
             locked_until: lock_until,
             version: version + 1,
             updated_at: now
         }}

      {0, _} ->
        if current_state == :processing do
          {:error, :already_processing}
        else
          {:error, :stale}
        end
    end
  end

  @doc """
  Marks a record as completed with the response.
  """
  @spec complete(Record.t(), term(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def complete(%Record{} = record, response, opts \\ []) do
    record
    |> Record.complete_changeset(%{
      state: :completed,
      response: serialize_response(response),
      completed_at: DateTime.utc_now()
    })
    |> repo(opts).update()
  end

  @doc """
  Marks a record as failed with the error.
  """
  @spec fail(Record.t(), term(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def fail(%Record{} = record, error, opts \\ []) do
    record
    |> Record.fail_changeset(%{
      state: :failed,
      error: serialize_error(error),
      completed_at: DateTime.utc_now()
    })
    |> repo(opts).update()
  end

  @doc """
  Releases a processing lock, returning to pending state.
  """
  @spec release(Record.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def release(%Record{} = record, opts \\ []) do
    record
    |> Record.release_changeset(%{
      state: :pending,
      locked_until: nil,
      started_at: nil
    })
    |> repo(opts).update()
  end

  @doc """
  Deletes expired idempotency records.

  Returns the number of deleted records.
  """
  @spec cleanup_expired(keyword()) :: {:ok, non_neg_integer()}
  def cleanup_expired(opts \\ []) do
    now = DateTime.utc_now()

    query =
      from(r in Record,
        where: r.expires_at < ^now
      )

    {count, _} = repo(opts).delete_all(query)
    Logger.info("[OmIdempotency] Cleaned up #{count} expired records")
    {:ok, count}
  end

  @doc """
  Finds and releases stale processing records.

  Records that have been processing longer than the lock timeout
  are returned to pending state for retry.
  """
  @spec recover_stale(keyword()) :: {:ok, non_neg_integer()}
  def recover_stale(opts \\ []) do
    now = DateTime.utc_now()

    query =
      from(r in Record,
        where: r.state == :processing,
        where: r.locked_until < ^now
      )

    {count, _} =
      repo(opts).update_all(query,
        set: [
          state: :pending,
          locked_until: nil,
          updated_at: now
        ]
      )

    if count > 0 do
      Logger.warning("[OmIdempotency] Recovered #{count} stale processing records")
    end

    {:ok, count}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp execute_new(key, scope, metadata, fun, opts) do
    case create(key,
           scope: scope,
           metadata: metadata,
           ttl: Keyword.get(opts, :ttl, @default_ttl_ms),
           repo: Keyword.get(opts, :repo)
         ) do
      {:ok, record} ->
        execute_with_record(record, fun, opts)

      {:error, :already_exists} ->
        case get(key, scope, opts) do
          {:ok, record} ->
            handle_existing_record(record, fun, opts)

          {:error, :not_found} ->
            {:error, :idempotency_conflict}
        end

      {:error, _} = error ->
        error
    end
  end

  defp execute_with_record(%Record{} = record, fun, opts) do
    case start_processing(record, opts) do
      {:ok, processing_record} ->
        execute_and_store(processing_record, fun, opts)

      {:error, :already_processing} ->
        {:error, :in_progress}

      {:error, :stale} ->
        case get(record.key, record.scope, opts) do
          {:ok, fresh_record} ->
            handle_existing_record(fresh_record, fun, opts)

          {:error, :not_found} ->
            {:error, :idempotency_conflict}
        end
    end
  end

  defp execute_and_store(%Record{} = record, fun, opts) do
    try do
      case fun.() do
        {:ok, response} = result ->
          complete(record, response, opts)
          emit_telemetry(:completed, record.key, record.scope, %{})
          result

        {:error, error} = result ->
          if permanent_failure?(error) do
            fail(record, error, opts)
            emit_telemetry(:failed, record.key, record.scope, %{})
          else
            release(record, opts)
            emit_telemetry(:released, record.key, record.scope, %{})
          end

          result
      end
    rescue
      error ->
        release(record, opts)
        emit_telemetry(:error, record.key, record.scope, %{})
        reraise error, __STACKTRACE__
    end
  end

  defp handle_existing_record(%Record{state: :completed, response: response}, _fun, _opts) do
    deserialize_response(response)
  end

  defp handle_existing_record(%Record{state: :failed, error: error}, _fun, _opts) do
    {:error, error}
  end

  defp handle_existing_record(%Record{state: state} = record, fun, opts)
       when state in [:pending, :processing] do
    handle_in_progress(record, fun, Keyword.get(opts, :on_duplicate, :return), opts)
  end

  defp handle_in_progress(%Record{} = record, _fun, :return, _opts) do
    {:error, {:in_progress, record}}
  end

  defp handle_in_progress(%Record{}, _fun, :error, _opts) do
    {:error, :in_progress}
  end

  defp handle_in_progress(%Record{} = record, fun, :wait, opts) do
    wait_timeout = Keyword.get(opts, :wait_timeout, 5_000)
    wait_for_completion(record, fun, wait_timeout, opts)
  end

  defp wait_for_completion(%Record{key: key, scope: scope}, fun, timeout, opts)
       when timeout > 0 do
    Process.sleep(100)

    case get(key, scope, opts) do
      {:ok, %Record{state: :completed, response: response}} ->
        deserialize_response(response)

      {:ok, %Record{state: :failed, error: error}} ->
        {:error, error}

      {:ok, %Record{state: state}} when state in [:pending, :processing] ->
        wait_for_completion(%Record{key: key, scope: scope}, fun, timeout - 100, opts)

      {:error, :not_found} ->
        execute_new(key, scope, %{}, fun, opts)
    end
  end

  defp wait_for_completion(_record, _fun, _timeout, _opts) do
    {:error, :wait_timeout}
  end

  defp permanent_failure?(error) do
    # Check if error implements a recoverable? function
    case error do
      %{__struct__: module} = struct ->
        if function_exported?(module, :recoverable?, 1) do
          not module.recoverable?(struct)
        else
          false
        end

      _ ->
        false
    end
  end

  defp serialize_response({:ok, data}), do: %{ok: data}
  defp serialize_response(data), do: data

  defp deserialize_response(%{ok: data}), do: {:ok, data}
  defp deserialize_response(data), do: {:ok, data}

  defp serialize_error(%{__struct__: module} = error) do
    %{
      type: Kernel.inspect(module),
      message: Exception.message(error),
      details: Map.from_struct(error)
    }
  end

  defp serialize_error(error) when is_atom(error),
    do: %{type: "atom", message: Atom.to_string(error)}

  defp serialize_error(error) when is_binary(error), do: %{type: "string", message: error}
  defp serialize_error(error), do: %{type: "unknown", message: Kernel.inspect(error)}

  defp emit_telemetry(event, key, scope, measurements) do
    :telemetry.execute(
      telemetry_prefix() ++ [event],
      Map.merge(%{count: 1}, measurements),
      %{key: key, scope: scope}
    )
  end
end
