defmodule OmCrud.Batch do
  @moduledoc """
  Batch processing utilities for large datasets.

  Provides functions for processing records in chunks with configurable
  batch sizes, concurrency, and error handling strategies.

  ## Basic Usage

      alias OmCrud.Batch

      # Process users in batches of 100
      Batch.each(User, fn batch ->
        Enum.each(batch, &send_email/1)
      end)

      # Update in batches with transformation
      Batch.update(User, fn user ->
        %{points: user.points + 10}
      end, batch_size: 500)

  ## Chunked Inserts

      # Insert large dataset in chunks
      Batch.create_all(User, large_list_of_attrs, batch_size: 1000)

  ## Streaming

      # Stream records for memory-efficient processing
      User
      |> Batch.stream(batch_size: 100)
      |> Stream.map(&process/1)
      |> Stream.run()

  ## Configuration

      config :om_crud, OmCrud.Batch,
        default_batch_size: 500,
        default_timeout: 30_000
  """

  alias OmCrud.{Error, Options}

  @default_batch_size 500
  @default_timeout 30_000

  @type batch_opts :: [
          batch_size: pos_integer(),
          timeout: pos_integer(),
          repo: module(),
          on_error: :halt | :continue | :collect,
          order_by: atom() | [atom()],
          where: keyword()
        ]

  @type batch_result ::
          {:ok, %{processed: non_neg_integer(), errors: [Error.t()]}}
          | {:error, Error.t()}

  # ─────────────────────────────────────────────────────────────
  # Batch Processing
  # ─────────────────────────────────────────────────────────────

  @doc """
  Process records in batches, calling a function for each batch.

  ## Options

  - `:batch_size` - Number of records per batch (default: 500)
  - `:timeout` - Timeout per batch in milliseconds (default: 30_000)
  - `:repo` - Repo to use
  - `:order_by` - Field(s) to order by for consistent batching (default: :id)
  - `:where` - Filter conditions as keyword list

  ## Examples

      # Process all users
      Batch.each(User, fn batch ->
        Enum.each(batch, &send_notification/1)
      end)

      # With filters and options
      Batch.each(User, fn batch ->
        # process batch
        :ok
      end, where: [status: :active], batch_size: 100)
  """
  @spec each(module(), (list() -> any()), batch_opts()) :: :ok
  def each(schema, fun, opts \\ []) when is_atom(schema) and is_function(fun, 1) do
    OmCrud.Telemetry.span(:batch_each, %{schema: schema}, fn ->
      repo = Options.repo(opts)
      batch_size = Keyword.get(opts, :batch_size, default_batch_size())
      timeout = Keyword.get(opts, :timeout, default_timeout())
      order_by = Keyword.get(opts, :order_by, :id)
      where_conditions = Keyword.get(opts, :where, [])

      repo.transaction(
        fn ->
          schema
          |> build_query(where_conditions, order_by)
          |> repo.stream(max_rows: batch_size)
          |> Stream.chunk_every(batch_size)
          |> Enum.each(fun)
        end,
        timeout: timeout
      )

      :ok
    end)
  end

  @doc """
  Process records in batches with result tracking.

  Returns counts of processed records and any errors encountered.

  ## Options

  - `:batch_size` - Number of records per batch
  - `:on_error` - Error handling strategy:
    - `:halt` - Stop on first error (default)
    - `:continue` - Skip errors and continue
    - `:collect` - Collect errors and continue
  - `:repo` - Repo to use

  ## Examples

      {:ok, %{processed: 1000, errors: []}} = Batch.process(User, fn batch ->
        {:ok, Enum.count(batch)}
      end)

      # With error collection
      {:ok, %{processed: 950, errors: errors}} = Batch.process(User, fn batch ->
        case process_batch(batch) do
          {:ok, count} -> {:ok, count}
          {:error, reason} -> {:error, reason}
        end
      end, on_error: :collect)
  """
  @spec process(module(), (list() -> {:ok, non_neg_integer()} | {:error, term()}), batch_opts()) ::
          batch_result()
  def process(schema, fun, opts \\ []) when is_atom(schema) and is_function(fun, 1) do
    OmCrud.Telemetry.span(:batch_process, %{schema: schema}, fn ->
      repo = Options.repo(opts)
      batch_size = Keyword.get(opts, :batch_size, default_batch_size())
      timeout = Keyword.get(opts, :timeout, default_timeout())
      on_error = Keyword.get(opts, :on_error, :halt)
      order_by = Keyword.get(opts, :order_by, :id)
      where_conditions = Keyword.get(opts, :where, [])

      initial_state = %{processed: 0, errors: [], halted: false}

      {:ok, result} =
        repo.transaction(
          fn ->
            schema
            |> build_query(where_conditions, order_by)
            |> repo.stream(max_rows: batch_size)
            |> Stream.chunk_every(batch_size)
            |> Enum.reduce_while(initial_state, fn batch, state ->
              if state.halted do
                {:halt, state}
              else
                case fun.(batch) do
                  {:ok, count} ->
                    {:cont, %{state | processed: state.processed + count}}

                  {:error, reason} ->
                    error = wrap_error(reason, schema)
                    handle_batch_error(state, error, on_error)
                end
              end
            end)
          end,
          timeout: timeout
        )

      {:ok, Map.delete(result, :halted)}
    end)
  end

  @doc """
  Update records in batches using a transformation function.

  ## Options

  - `:batch_size` - Number of records per batch
  - `:changeset` - Changeset function to use
  - `:repo` - Repo to use
  - `:on_error` - Error handling strategy

  ## Examples

      # Add points to all users
      {:ok, %{processed: count}} = Batch.update(User, fn user ->
        %{points: user.points + 10}
      end)

      # With custom changeset
      {:ok, _} = Batch.update(User, fn user ->
        %{status: :archived}
      end, changeset: :admin_changeset, where: [inactive_for: 90])
  """
  @spec update(module(), (struct() -> map()), batch_opts()) :: batch_result()
  def update(schema, transform_fn, opts \\ [])
      when is_atom(schema) and is_function(transform_fn, 1) do
    repo = Options.repo(opts)
    changeset_fn = Keyword.get(opts, :changeset, :changeset)

    process(
      schema,
      fn batch ->
        results =
          Enum.map(batch, fn record ->
            attrs = transform_fn.(record)
            changeset = apply(schema, changeset_fn, [record, attrs])
            repo.update(changeset)
          end)

        errors = Enum.filter(results, &match?({:error, _}, &1))

        if Enum.empty?(errors) do
          {:ok, length(results)}
        else
          {:error, {:batch_update_failed, length(errors)}}
        end
      end,
      opts
    )
  end

  @doc """
  Delete records in batches.

  ## Options

  - `:batch_size` - Number of records per batch
  - `:repo` - Repo to use
  - `:where` - Filter conditions

  ## Examples

      # Delete all inactive users
      {:ok, %{processed: count}} = Batch.delete(User, where: [status: :inactive])
  """
  @spec delete(module(), batch_opts()) :: batch_result()
  def delete(schema, opts \\ []) when is_atom(schema) do
    repo = Options.repo(opts)

    process(
      schema,
      fn batch ->
        ids = Enum.map(batch, & &1.id)

        import Ecto.Query
        query = from(r in schema, where: r.id in ^ids)

        {count, _} = repo.delete_all(query)
        {:ok, count}
      end,
      opts
    )
  end

  # ─────────────────────────────────────────────────────────────
  # Chunked Inserts
  # ─────────────────────────────────────────────────────────────

  @doc """
  Insert a large list of records in batches.

  ## Options

  - `:batch_size` - Number of records per batch (default: 500)
  - `:timeout` - Timeout per batch
  - `:repo` - Repo to use
  - `:on_conflict` - Conflict handling for upserts
  - `:conflict_target` - Conflict target for upserts
  - `:returning` - Fields to return

  ## Examples

      # Insert 10,000 users in batches of 1,000
      {:ok, %{processed: 10000}} = Batch.create_all(User, users_data, batch_size: 1000)

      # Upsert in batches
      {:ok, _} = Batch.create_all(User, users_data,
        batch_size: 500,
        conflict_target: :email,
        on_conflict: :replace_all
      )
  """
  @spec create_all(module(), [map()], batch_opts()) :: batch_result()
  def create_all(schema, list_of_attrs, opts \\ [])
      when is_atom(schema) and is_list(list_of_attrs) do
    OmCrud.Telemetry.span(:batch_create_all, %{schema: schema, count: length(list_of_attrs)}, fn ->
      repo = Options.repo(opts)
      batch_size = Keyword.get(opts, :batch_size, default_batch_size())
      timeout = Keyword.get(opts, :timeout, default_timeout())
      on_error = Keyword.get(opts, :on_error, :halt)

      # Extract insert options
      insert_opts =
        opts
        |> Keyword.take([:on_conflict, :conflict_target, :returning, :placeholders])
        |> Keyword.put(:timeout, timeout)

      initial_state = %{processed: 0, errors: [], halted: false}

      result =
        list_of_attrs
        |> Stream.chunk_every(batch_size)
        |> Enum.reduce_while(initial_state, fn batch, state ->
          if state.halted do
            {:halt, state}
          else
            try do
              {count, _returned} = repo.insert_all(schema, batch, insert_opts)
              {:cont, %{state | processed: state.processed + count}}
            rescue
              e ->
                error = wrap_error(e, schema)
                handle_batch_error(state, error, on_error)
            end
          end
        end)

      {:ok, Map.delete(result, :halted)}
    end)
  end

  @doc """
  Upsert a large list of records in batches.

  Convenience wrapper around `create_all/3` with upsert options.

  ## Options

  - `:conflict_target` - Column(s) for conflict detection (required)
  - `:on_conflict` - Action on conflict
  - `:batch_size` - Number of records per batch

  ## Examples

      {:ok, %{processed: count}} = Batch.upsert_all(User, users_data,
        conflict_target: :email,
        on_conflict: {:replace, [:name, :updated_at]}
      )
  """
  @spec upsert_all(module(), [map()], batch_opts()) :: batch_result()
  def upsert_all(schema, list_of_attrs, opts) when is_atom(schema) and is_list(list_of_attrs) do
    unless Keyword.has_key?(opts, :conflict_target) do
      raise ArgumentError, "upsert_all/3 requires :conflict_target option"
    end

    opts = Keyword.put_new(opts, :on_conflict, :replace_all)
    create_all(schema, list_of_attrs, opts)
  end

  # ─────────────────────────────────────────────────────────────
  # Streaming
  # ─────────────────────────────────────────────────────────────

  @doc """
  Stream records in batches for memory-efficient processing.

  **Important:** `Repo.stream` requires a transaction context. This function
  returns a stream that must be consumed inside a transaction, or use
  `stream_in_transaction/2` for automatic transaction wrapping.

  Returns a Stream that yields individual records but fetches in batches.

  ## Options

  - `:batch_size` - Number of records to fetch per database query
  - `:repo` - Repo to use
  - `:order_by` - Field to order by

  ## Examples

      # Inside an existing transaction
      repo.transaction(fn ->
        User
        |> Batch.stream(batch_size: 100)
        |> Stream.map(&process_user/1)
        |> Stream.run()
      end)

      # Or use stream_in_transaction/2 for auto-wrapping
      Batch.stream_in_transaction(User, batch_size: 100, fun: &process_user/1)

      # Stream with filtering
      repo.transaction(fn ->
        User
        |> Batch.stream(where: [status: :active])
        |> Enum.to_list()
      end)
  """
  @spec stream(module(), batch_opts()) :: Enumerable.t()
  def stream(schema, opts \\ []) when is_atom(schema) do
    repo = Options.repo(opts)
    batch_size = Keyword.get(opts, :batch_size, default_batch_size())
    order_by = Keyword.get(opts, :order_by, :id)
    where_conditions = Keyword.get(opts, :where, [])

    schema
    |> build_query(where_conditions, order_by)
    |> repo.stream(max_rows: batch_size)
  end

  @doc """
  Stream records inside an automatically managed transaction.

  Unlike `stream/2`, this wraps the stream consumption in a transaction,
  making it safe to use without an existing transaction context.

  ## Options

  Same as `stream/2` plus:
  - `:timeout` - Transaction timeout (default: 30_000)

  ## Examples

      # Collect all active users
      {:ok, users} = Batch.stream_in_transaction(User,
        where: [status: :active],
        batch_size: 100
      )

      # Process with a custom function
      Batch.stream_in_transaction(User, batch_size: 100, map: &process_user/1)
  """
  @spec stream_in_transaction(module(), batch_opts()) :: {:ok, [struct()]} | {:error, term()}
  def stream_in_transaction(schema, opts \\ []) when is_atom(schema) do
    repo = Options.repo(opts)
    timeout = Keyword.get(opts, :timeout, default_timeout())
    map_fn = Keyword.get(opts, :map)

    repo.transaction(
      fn ->
        s = stream(schema, opts)

        if map_fn do
          s |> Stream.map(map_fn) |> Enum.to_list()
        else
          Enum.to_list(s)
        end
      end,
      timeout: timeout
    )
  end

  @doc """
  Stream records in chunks (batches as lists).

  Unlike `stream/2`, this yields batches as lists, not individual records.

  **Important:** Must be consumed inside a transaction context.
  See `stream/2` documentation.

  ## Examples

      repo.transaction(fn ->
        User
        |> Batch.stream_chunks(batch_size: 100)
        |> Stream.map(fn batch ->
          # Process entire batch at once
          process_batch(batch)
        end)
        |> Stream.run()
      end)
  """
  @spec stream_chunks(module(), batch_opts()) :: Enumerable.t()
  def stream_chunks(schema, opts \\ []) when is_atom(schema) do
    batch_size = Keyword.get(opts, :batch_size, default_batch_size())

    schema
    |> stream(opts)
    |> Stream.chunk_every(batch_size)
  end

  # ─────────────────────────────────────────────────────────────
  # Concurrent Processing
  # ─────────────────────────────────────────────────────────────

  @doc """
  Process records in batches with concurrent batch processing.

  Each batch is processed in a separate task for parallelism.

  ## Options

  - `:batch_size` - Number of records per batch
  - `:max_concurrency` - Maximum concurrent batches (default: System.schedulers_online())
  - `:timeout` - Timeout per batch task

  ## Examples

      {:ok, results} = Batch.parallel(User, fn batch ->
        # Heavy processing
        Enum.map(batch, &expensive_operation/1)
      end, max_concurrency: 4)
  """
  @spec parallel(module(), (list() -> term()), batch_opts()) ::
          {:ok, [term()]} | {:error, Error.t()}
  def parallel(schema, fun, opts \\ []) when is_atom(schema) and is_function(fun, 1) do
    OmCrud.Telemetry.span(:batch_parallel, %{schema: schema}, fn ->
      repo = Options.repo(opts)
    batch_size = Keyword.get(opts, :batch_size, default_batch_size())
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, default_timeout())
    order_by = Keyword.get(opts, :order_by, :id)
    where_conditions = Keyword.get(opts, :where, [])

    # Collect batches inside a transaction (repo.stream requires it),
    # then process them in parallel outside the transaction.
    {:ok, batches} =
      repo.transaction(
        fn ->
          schema
          |> build_query(where_conditions, order_by)
          |> repo.stream(max_rows: batch_size)
          |> Stream.chunk_every(batch_size)
          |> Enum.to_list()
        end,
        timeout: timeout
      )

    results =
      batches
      |> Task.async_stream(fun, max_concurrency: max_concurrency, timeout: timeout)
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, reason}
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, results}
    else
      {:error, Error.wrap({:parallel_batch_errors, errors}, operation: :parallel_batch)}
    end
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp build_query(schema, where_conditions, order_by) do
    import Ecto.Query

    query = from(r in schema, order_by: ^List.wrap(order_by))

    Enum.reduce(where_conditions, query, fn {field, value}, q ->
      where(q, [r], field(r, ^field) == ^value)
    end)
  end

  defp handle_batch_error(state, error, :halt) do
    {:halt, %{state | errors: [error | state.errors], halted: true}}
  end

  defp handle_batch_error(state, _error, :continue) do
    {:cont, state}
  end

  defp handle_batch_error(state, error, :collect) do
    {:cont, %{state | errors: [error | state.errors]}}
  end

  defp wrap_error(%Error{} = error, _schema), do: error
  defp wrap_error(reason, schema), do: Error.wrap(reason, schema: schema, operation: :batch)

  defp default_batch_size do
    Application.get_env(:om_crud, __MODULE__)[:default_batch_size] || @default_batch_size
  end

  defp default_timeout do
    Application.get_env(:om_crud, __MODULE__)[:default_timeout] || @default_timeout
  end
end
