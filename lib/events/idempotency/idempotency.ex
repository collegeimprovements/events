defmodule Events.Idempotency do
  @moduledoc """
  Idempotency key management for safe API retries.

  Provides database-backed deduplication for external API calls, ensuring that
  retried requests don't cause duplicate side effects.

  ## How It Works

  1. Before making an API call, check if the idempotency key exists
  2. If it exists and is completed, return the cached response
  3. If it exists and is processing, wait or return conflict
  4. If it doesn't exist, create a record and proceed with the call
  5. After the call, update the record with the response

  ## Usage

  ### Basic Usage

      # Generate a key for an operation
      key = Idempotency.generate_key(:create_customer, user_id: 123)

      # Execute with idempotency protection
      Idempotency.execute(key, fn ->
        StripeClient.create_customer(%{email: "user@example.com"})
      end)

  ### With API Client Pipeline

      Request.new(config)
      |> Request.idempotency_key(Idempotency.generate_key(:create_charge, order_id: order.id))
      |> Request.json(%{amount: 1000})
      |> Stripe.create_charge()

  ### Manual Control

      # Check if already executed
      case Idempotency.get(key) do
        {:ok, %{state: :completed, response: response}} ->
          {:ok, response}

        {:ok, %{state: :processing}} ->
          {:error, :in_progress}

        {:error, :not_found} ->
          # Safe to execute
          with {:ok, record} <- Idempotency.create(key, scope: "stripe"),
               {:ok, response} <- make_api_call(),
               {:ok, _} <- Idempotency.complete(record, response) do
            {:ok, response}
          end
      end

  ## Key Generation

  Keys can be generated from:
  - Operation name + parameters (deterministic)
  - UUIDv7 (time-ordered, good for debugging)
  - Custom strings

      # Deterministic key from operation
      Idempotency.generate_key(:create_order, user_id: 123, cart_id: 456)
      #=> "create_order:user_id=123:cart_id=456"

      # UUIDv7 key
      Idempotency.generate_key()
      #=> "01913a77-7e30-7f4a-8c1e-b5f3c8d9e0f1"

      # Scoped key
      Idempotency.generate_key(:charge, order_id: 123, scope: "stripe")
      #=> "stripe:charge:order_id=123"

  ## States

  Idempotency records go through these states:

      pending -> processing -> completed
                     |
                     +------> failed
                     |
                     +------> expired

  - `pending` - Record created, not yet processing
  - `processing` - API call in progress
  - `completed` - API call succeeded, response cached
  - `failed` - API call failed permanently
  - `expired` - Record expired (cleanup)

  ## Configuration

      config :events, Events.Idempotency,
        ttl: {24, :hours},           # How long to keep records
        lock_timeout: {30, :seconds}, # Max time in processing state
        cleanup_interval: {1, :hour}  # How often to clean expired records

  ## Recovery

  The recovery scheduler finds stuck records in `processing` state:

      # In your application supervisor
      children = [
        {Events.Idempotency.Recovery, interval: {5, :minutes}}
      ]
  """

  use Events.Decorator

  require Logger

  alias Events.Idempotency.Record
  alias Events.Repo

  import Ecto.Query

  @type key :: String.t()
  @type scope :: String.t() | nil
  @type state :: :pending | :processing | :completed | :failed | :expired

  @type execute_opts :: [
          scope: String.t(),
          ttl: pos_integer(),
          on_duplicate: :return | :wait | :error,
          metadata: map()
        ]

  @default_ttl_ms 24 * 60 * 60 * 1000
  @default_lock_timeout_ms 30 * 1000

  # ============================================
  # Key Generation
  # ============================================

  @doc """
  Generates an idempotency key.

  ## Options

  - `:scope` - Prefix for the key (e.g., "stripe", "sendgrid")

  ## Examples

      # UUIDv7 key
      Idempotency.generate_key()
      #=> "01913a77-7e30-7f4a-8c1e-b5f3c8d9e0f1"

      # From operation and params
      Idempotency.generate_key(:create_customer, user_id: 123)
      #=> "create_customer:user_id=123"

      # With scope
      Idempotency.generate_key(:charge, order_id: 456, scope: "stripe")
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

      Idempotency.hash_key(:create_customer, %{email: "user@example.com", name: "Jane"})
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

  ## Examples

      Idempotency.execute("order_123_charge", fn ->
        Stripe.create_charge(%{amount: 1000})
      end)

      Idempotency.execute("order_123_charge", fn ->
        Stripe.create_charge(%{amount: 1000})
      end, scope: "stripe", on_duplicate: :wait)
  """
  @spec execute(key(), (-> {:ok, term()} | {:error, term()}), execute_opts()) ::
          {:ok, term()} | {:error, term()}
  @decorate telemetry_span([:events, :idempotency, :execute])
  def execute(key, fun, opts \\ []) when is_binary(key) and is_function(fun, 0) do
    scope = Keyword.get(opts, :scope)
    on_duplicate = Keyword.get(opts, :on_duplicate, :return)
    metadata = Keyword.get(opts, :metadata, %{})

    case get(key, scope) do
      {:ok, %Record{state: :completed, response: response}} ->
        Logger.debug("[Idempotency] Cache hit for key=#{key}")
        emit_telemetry(:cache_hit, key, scope)
        deserialize_response(response)

      {:ok, %Record{state: :failed, error: error}} ->
        Logger.debug("[Idempotency] Previous failure for key=#{key}")
        emit_telemetry(:cache_hit_failed, key, scope)
        {:error, error}

      {:ok, %Record{state: :processing} = record} ->
        handle_in_progress(record, fun, on_duplicate, opts)

      {:ok, %Record{state: :pending} = record} ->
        # Stale pending record, try to claim it
        execute_with_record(record, fun, opts)

      {:error, :not_found} ->
        # Create new record and execute
        execute_new(key, scope, metadata, fun, opts)
    end
  end

  @doc """
  Gets an idempotency record by key.

  ## Examples

      Idempotency.get("order_123_charge")
      #=> {:ok, %Record{state: :completed, ...}}

      Idempotency.get("unknown_key")
      #=> {:error, :not_found}
  """
  @spec get(key(), scope()) :: {:ok, Record.t()} | {:error, :not_found}
  def get(key, scope \\ nil) do
    query =
      from(r in Record,
        where: r.key == ^key,
        where: r.scope == ^scope or (is_nil(r.scope) and is_nil(^scope))
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Creates a new idempotency record in pending state.

  ## Examples

      Idempotency.create("order_123_charge", scope: "stripe")
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
    |> Repo.insert()
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

  ## Examples

      Idempotency.start_processing(record)
      #=> {:ok, %Record{state: :processing, ...}}

      Idempotency.start_processing(stale_record)
      #=> {:error, :already_processing}
  """
  @spec start_processing(Record.t()) :: {:ok, Record.t()} | {:error, :already_processing | :stale}
  def start_processing(%Record{id: id, state: current_state, version: version}) do
    now = DateTime.utc_now()
    lock_until = DateTime.add(now, @default_lock_timeout_ms, :millisecond)

    query =
      from(r in Record,
        where: r.id == ^id,
        where: r.version == ^version,
        where: r.state in [:pending, :processing]
      )

    case Repo.update_all(query,
           set: [
             state: :processing,
             started_at: now,
             locked_until: lock_until,
             version: version + 1,
             updated_at: now
           ]
         ) do
      {1, _} ->
        {:ok, %Record{id: id, state: :processing, version: version + 1}}

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

  ## Examples

      Idempotency.complete(record, %{id: "cus_123", email: "user@example.com"})
      #=> {:ok, %Record{state: :completed, ...}}
  """
  @spec complete(Record.t(), term()) :: {:ok, Record.t()} | {:error, term()}
  def complete(%Record{} = record, response) do
    record
    |> Record.complete_changeset(%{
      state: :completed,
      response: serialize_response(response),
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Marks a record as failed with the error.

  ## Examples

      Idempotency.fail(record, %{code: "card_declined", message: "Card was declined"})
      #=> {:ok, %Record{state: :failed, ...}}
  """
  @spec fail(Record.t(), term()) :: {:ok, Record.t()} | {:error, term()}
  def fail(%Record{} = record, error) do
    record
    |> Record.fail_changeset(%{
      state: :failed,
      error: serialize_error(error),
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Releases a processing lock, returning to pending state.

  Used when a request times out but the operation may not have completed.

  ## Examples

      Idempotency.release(record)
      #=> {:ok, %Record{state: :pending, ...}}
  """
  @spec release(Record.t()) :: {:ok, Record.t()} | {:error, term()}
  def release(%Record{} = record) do
    record
    |> Record.release_changeset(%{
      state: :pending,
      locked_until: nil,
      started_at: nil
    })
    |> Repo.update()
  end

  @doc """
  Deletes expired idempotency records.

  Returns the number of deleted records.

  ## Examples

      Idempotency.cleanup_expired()
      #=> {:ok, 42}
  """
  @spec cleanup_expired() :: {:ok, non_neg_integer()}
  def cleanup_expired do
    now = DateTime.utc_now()

    query =
      from(r in Record,
        where: r.expires_at < ^now
      )

    {count, _} = Repo.delete_all(query)
    Logger.info("[Idempotency] Cleaned up #{count} expired records")
    {:ok, count}
  end

  @doc """
  Finds and releases stale processing records.

  Records that have been processing longer than the lock timeout
  are returned to pending state for retry.

  ## Examples

      Idempotency.recover_stale()
      #=> {:ok, 5}
  """
  @spec recover_stale() :: {:ok, non_neg_integer()}
  def recover_stale do
    now = DateTime.utc_now()

    query =
      from(r in Record,
        where: r.state == :processing,
        where: r.locked_until < ^now
      )

    {count, _} =
      Repo.update_all(query,
        set: [
          state: :pending,
          locked_until: nil,
          updated_at: now
        ]
      )

    if count > 0 do
      Logger.warning("[Idempotency] Recovered #{count} stale processing records")
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
           ttl: Keyword.get(opts, :ttl, @default_ttl_ms)
         ) do
      {:ok, record} ->
        execute_with_record(record, fun, opts)

      {:error, :already_exists} ->
        # Race condition - another process created it first
        # Retry the get
        case get(key, scope) do
          {:ok, record} ->
            handle_existing_record(record, fun, opts)

          {:error, :not_found} ->
            # Very rare - record was created and deleted
            {:error, :idempotency_conflict}
        end

      {:error, _} = error ->
        error
    end
  end

  defp execute_with_record(%Record{} = record, fun, _opts) do
    case start_processing(record) do
      {:ok, processing_record} ->
        execute_and_store(processing_record, fun)

      {:error, :already_processing} ->
        {:error, :in_progress}

      {:error, :stale} ->
        # Another process claimed it, get fresh state
        case get(record.key, record.scope) do
          {:ok, fresh_record} ->
            handle_existing_record(fresh_record, fun, [])

          {:error, :not_found} ->
            {:error, :idempotency_conflict}
        end
    end
  end

  defp execute_and_store(%Record{} = record, fun) do
    try do
      case fun.() do
        {:ok, response} = result ->
          complete(record, response)
          emit_telemetry(:completed, record.key, record.scope)
          result

        {:error, error} = result ->
          # Determine if this is a permanent failure
          if permanent_failure?(error) do
            fail(record, error)
            emit_telemetry(:failed, record.key, record.scope)
          else
            # Transient failure - release the lock for retry
            release(record)
            emit_telemetry(:released, record.key, record.scope)
          end

          result
      end
    rescue
      error ->
        # Unexpected error - release for retry
        release(record)
        emit_telemetry(:error, record.key, record.scope)
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

    case get(key, scope) do
      {:ok, %Record{state: :completed, response: response}} ->
        deserialize_response(response)

      {:ok, %Record{state: :failed, error: error}} ->
        {:error, error}

      {:ok, %Record{state: state}} when state in [:pending, :processing] ->
        wait_for_completion(%Record{key: key, scope: scope}, fun, timeout - 100, opts)

      {:error, :not_found} ->
        # Record was deleted, try to execute
        execute_new(key, scope, %{}, fun, opts)
    end
  end

  defp wait_for_completion(_record, _fun, _timeout, _opts) do
    {:error, :wait_timeout}
  end

  defp permanent_failure?(error) do
    # Use Recoverable protocol if available
    case error do
      %{__struct__: _} = struct ->
        not Events.Recoverable.recoverable?(struct)

      _ ->
        # Unknown error type - assume transient
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

  defp emit_telemetry(event, key, scope) do
    :telemetry.execute(
      [:events, :idempotency, event],
      %{count: 1},
      %{key: key, scope: scope}
    )
  end
end
