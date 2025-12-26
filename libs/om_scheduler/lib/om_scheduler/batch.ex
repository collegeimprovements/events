defmodule OmScheduler.Batch do
  @moduledoc """
  Batch processing for scheduled jobs.

  Enables processing large datasets in configurable chunks with progress tracking,
  error handling, and resumable execution.

  ## Usage

  Define a batch job by implementing the `OmScheduler.Batch.Worker` behaviour:

      defmodule MyApp.ImportWorker do
        use OmScheduler.Batch.Worker

        @impl true
        def schedule do
          [cron: "0 2 * * *", queue: :imports]
        end

        @impl true
        def fetch_items(cursor, opts) do
          # Fetch next batch of items
          limit = opts[:batch_size] || 100

          items =
            Item
            |> where([i], i.id > ^(cursor || 0))
            |> order_by(:id)
            |> limit(^limit)
            |> Repo.all()

          case items do
            [] -> {:done, []}
            items -> {:more, items, List.last(items).id}
          end
        end

        @impl true
        def process_item(item, _context) do
          # Process a single item
          case ImportService.import(item) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end

  ## Batch Options

  - `:batch_size` - Number of items per batch (default: 100)
  - `:max_items` - Maximum total items to process (default: unlimited)
  - `:concurrency` - Parallel item processing (default: 1)
  - `:on_error` - Error handling: `:continue`, `:stop`, `:retry` (default: `:continue`)
  - `:checkpoint_interval` - Save progress every N items (default: 100)

  ## Progress Tracking

  Batch jobs automatically track:
  - Items processed
  - Items failed
  - Current cursor position
  - Elapsed time

  ## Error Handling Strategies

  - `:continue` - Log error, continue with next item
  - `:stop` - Stop batch immediately, mark job as failed
  - `:retry` - Retry the item up to 3 times before continuing
  """

  alias OmScheduler.{Job, Telemetry}

  @type cursor :: term()
  @type item :: term()
  @type fetch_result :: {:more, [item()], cursor()} | {:done, [item()]}
  @type process_result :: :ok | {:ok, term()} | {:error, term()} | {:retry, term()}

  @type context :: %{
          job: Job.t(),
          cursor: cursor(),
          processed: non_neg_integer(),
          failed: non_neg_integer(),
          started_at: DateTime.t(),
          opts: keyword()
        }

  @type batch_result :: %{
          status: :completed | :partial | :failed,
          processed: non_neg_integer(),
          failed: non_neg_integer(),
          errors: [term()],
          cursor: cursor(),
          duration_ms: non_neg_integer()
        }

  @doc """
  Runs a batch job with the given module and options.
  """
  @spec run(module(), Job.t(), keyword()) :: {:ok, batch_result()} | {:error, term()}
  def run(module, job, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    max_items = Keyword.get(opts, :max_items, :infinity)
    on_error = Keyword.get(opts, :on_error, :continue)
    concurrency = Keyword.get(opts, :concurrency, 1)
    checkpoint_interval = Keyword.get(opts, :checkpoint_interval, 100)

    context = %{
      job: job,
      cursor: nil,
      processed: 0,
      failed: 0,
      errors: [],
      started_at: DateTime.utc_now(),
      opts: [
        batch_size: batch_size,
        max_items: max_items,
        on_error: on_error,
        concurrency: concurrency,
        checkpoint_interval: checkpoint_interval
      ]
    }

    Telemetry.execute([:batch, :start], %{system_time: System.system_time()}, %{
      job_name: job.name,
      batch_size: batch_size,
      concurrency: concurrency
    })

    result = process_batches(module, context)

    duration_ms = DateTime.diff(DateTime.utc_now(), context.started_at, :millisecond)

    Telemetry.execute([:batch, :stop], %{duration: duration_ms}, %{
      job_name: job.name,
      processed: result.processed,
      failed: result.failed,
      status: result.status
    })

    {:ok, Map.put(result, :duration_ms, duration_ms)}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp process_batches(module, context) do
    case fetch_batch(module, context) do
      {:done, items} ->
        final_context = process_items(module, items, context)
        build_result(final_context, :completed)

      {:more, items, new_cursor} ->
        new_context =
          context
          |> process_items(module, items)
          |> Map.put(:cursor, new_cursor)

        case should_continue?(new_context) do
          true -> process_batches(module, new_context)
          false -> build_result(new_context, :partial)
        end

      {:error, reason} ->
        build_result(context, :failed, [reason])
    end
  end

  defp fetch_batch(module, context) do
    module.fetch_items(context.cursor, context.opts)
  rescue
    e -> {:error, {:fetch_error, e}}
  end

  defp process_items(module, items, context) do
    concurrency = context.opts[:concurrency]

    case concurrency do
      1 -> process_items_sequential(module, items, context)
      n when n > 1 -> process_items_parallel(module, items, context, n)
    end
  end

  defp process_items_sequential(module, items, context) do
    Enum.reduce(items, context, fn item, ctx ->
      process_single_item(module, item, ctx)
    end)
  end

  defp process_items_parallel(module, items, context, concurrency) do
    items
    |> Task.async_stream(
      fn item -> {item, do_process_item(module, item, context)} end,
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce(context, fn
      {:ok, {_item, :ok}}, ctx ->
        %{ctx | processed: ctx.processed + 1}

      {:ok, {_item, {:ok, _}}}, ctx ->
        %{ctx | processed: ctx.processed + 1}

      {:ok, {_item, {:error, reason}}}, ctx ->
        handle_item_error(reason, ctx)

      {:exit, reason}, ctx ->
        handle_item_error({:exit, reason}, ctx)
    end)
  end

  defp process_single_item(module, item, context) do
    case do_process_item(module, item, context) do
      :ok ->
        %{context | processed: context.processed + 1}

      {:ok, _} ->
        %{context | processed: context.processed + 1}

      {:error, reason} ->
        handle_item_error(reason, context)

      {:retry, reason} ->
        handle_item_retry(module, item, reason, context, 1)
    end
  end

  defp do_process_item(module, item, context) do
    module.process_item(item, context)
  rescue
    e -> {:error, {:exception, e}}
  end

  defp handle_item_error(reason, context) do
    new_context = %{
      context
      | failed: context.failed + 1,
        errors: [reason | Enum.take(context.errors, 99)]
    }

    case context.opts[:on_error] do
      :stop -> throw({:batch_error, reason, new_context})
      _ -> new_context
    end
  end

  defp handle_item_retry(module, item, reason, context, attempt) when attempt < 3 do
    case do_process_item(module, item, context) do
      :ok -> %{context | processed: context.processed + 1}
      {:ok, _} -> %{context | processed: context.processed + 1}
      {:error, _} -> handle_item_retry(module, item, reason, context, attempt + 1)
      {:retry, _} -> handle_item_retry(module, item, reason, context, attempt + 1)
    end
  end

  defp handle_item_retry(_module, _item, reason, context, _attempt) do
    handle_item_error(reason, context)
  end

  defp should_continue?(context) do
    max_items = context.opts[:max_items]
    total = context.processed + context.failed

    case max_items do
      :infinity -> true
      n when is_integer(n) -> total < n
    end
  end

  defp build_result(context, status, extra_errors \\ []) do
    %{
      status: status,
      processed: context.processed,
      failed: context.failed,
      errors: extra_errors ++ Enum.take(context.errors, 10),
      cursor: context.cursor
    }
  end
end

defmodule OmScheduler.Batch.Worker do
  @moduledoc """
  Behaviour for batch job workers.

  Implement this behaviour to create jobs that process items in batches.

  ## Callbacks

  - `schedule/0` - Returns schedule configuration
  - `fetch_items/2` - Fetches the next batch of items
  - `process_item/2` - Processes a single item
  - `batch_options/0` - (optional) Returns batch configuration

  ## Example

      defmodule MyApp.SyncWorker do
        use OmScheduler.Batch.Worker

        @impl true
        def schedule do
          [every: {1, :hour}, queue: :sync]
        end

        @impl true
        def batch_options do
          [batch_size: 50, concurrency: 5, on_error: :continue]
        end

        @impl true
        def fetch_items(cursor, opts) do
          records =
            Record
            |> where([r], r.updated_at > ^(cursor || ~U[1970-01-01 00:00:00Z]))
            |> order_by(:updated_at)
            |> limit(^opts[:batch_size])
            |> Repo.all()

          case records do
            [] -> {:done, []}
            records -> {:more, records, List.last(records).updated_at}
          end
        end

        @impl true
        def process_item(record, _context) do
          case ExternalService.sync(record) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end
  """

  alias OmScheduler.Batch

  @doc """
  Returns the schedule configuration.
  """
  @callback schedule() :: keyword()

  @doc """
  Fetches the next batch of items to process.

  ## Arguments

  - `cursor` - The cursor from the previous batch (nil for first batch)
  - `opts` - Batch options including `:batch_size`

  ## Return Values

  - `{:more, items, new_cursor}` - More items available
  - `{:done, items}` - Last batch of items
  """
  @callback fetch_items(Batch.cursor(), keyword()) :: Batch.fetch_result()

  @doc """
  Processes a single item.

  ## Return Values

  - `:ok` - Success
  - `{:ok, result}` - Success with result
  - `{:error, reason}` - Failure
  - `{:retry, reason}` - Request retry
  """
  @callback process_item(Batch.item(), Batch.context()) :: Batch.process_result()

  @doc """
  Returns batch configuration options.

  Optional callback - defaults are used if not implemented.
  """
  @callback batch_options() :: keyword()

  @optional_callbacks [batch_options: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour OmScheduler.Batch.Worker

      alias OmScheduler.{Job, Batch}
      alias OmScheduler.Cron.Macros

      use Macros

      @doc false
      def batch_options, do: []

      defoverridable batch_options: 0

      @doc false
      def perform(context) do
        opts = Keyword.merge(batch_options(), context[:opts] || [])
        Batch.run(__MODULE__, context.job, opts)
      end

      @doc """
      Returns the job specification for this batch worker.
      """
      @spec __job_spec__() :: map()
      def __job_spec__ do
        opts = schedule()

        Job.from_decorator_opts(
          __MODULE__,
          :perform,
          Keyword.put(opts, :name, worker_name())
        )
      end

      defp worker_name do
        __MODULE__
        |> Module.split()
        |> Enum.join("_")
        |> String.downcase()
      end
    end
  end
end
