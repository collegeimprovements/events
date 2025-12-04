defmodule Events.Infra.Scheduler.Worker do
  @moduledoc """
  Behaviour for scheduled job workers.

  Implement this behaviour for complex jobs that need custom scheduling,
  retry logic, or state management.

  ## Example

      defmodule MyApp.DataExportWorker do
        use Events.Infra.Scheduler.Worker

        @impl true
        def schedule do
          [
            cron: "0 3 * * *",           # 3 AM daily
            zone: "UTC",
            timeout: {2, :hours},
            max_retries: 3,
            queue: :exports
          ]
        end

        @impl true
        def perform(%{attempt: attempt} = context) do
          with {:ok, data} <- fetch_data(),
               {:ok, file} <- generate_file(data),
               {:ok, _} <- upload(file) do
            {:ok, %{records: length(data)}}
          else
            {:error, :unavailable} when attempt < 3 ->
              {:retry, :unavailable}
            {:error, reason} ->
              {:error, reason}
          end
        end

        # Optional: custom backoff
        @impl true
        def backoff(attempt) do
          min(:timer.minutes(attempt * attempt), :timer.minutes(15))
        end
      end

  ## Callbacks

  - `schedule/0` - Returns schedule configuration
  - `perform/1` - Executes the job, receives context map
  - `backoff/1` - (optional) Custom backoff calculation
  - `timeout/1` - (optional) Dynamic timeout based on context

  ## Context Map

  The `perform/1` callback receives a context map with:

  - `:attempt` - Current attempt number (1-based)
  - `:job` - The Job struct
  - `:scheduled_at` - When the job was scheduled
  - `:meta` - Additional metadata

  ## Return Values

  - `{:ok, result}` - Success
  - `{:error, reason}` - Failure (may retry)
  - `{:retry, reason}` - Explicit retry request
  - `:ok` - Success (no result)
  """

  @doc """
  Returns schedule configuration.

  ## Options

  - `:cron` - Cron expression(s) or macro
  - `:every` - Interval for repeated execution
  - `:zone` - Timezone (default: "Etc/UTC")
  - `:queue` - Queue name (default: :default)
  - `:timeout` - Execution timeout
  - `:max_retries` - Maximum retry attempts
  - `:unique` - Prevent overlapping executions
  - `:tags` - Tags for filtering

  ## Examples

      def schedule do
        [cron: "0 6 * * *", zone: "America/New_York"]
      end

      def schedule do
        [every: {5, :minutes}, unique: true]
      end
  """
  @callback schedule() :: keyword()

  @doc """
  Executes the scheduled job.

  ## Context

  - `:attempt` - Current attempt (1-based)
  - `:job` - The Job struct
  - `:scheduled_at` - Original scheduled time
  - `:meta` - Additional metadata

  ## Return Values

  - `{:ok, result}` - Success, optionally with result data
  - `{:error, reason}` - Failure, may retry based on max_retries
  - `{:retry, reason}` - Explicit request to retry
  - `:ok` - Simple success
  """
  @callback perform(context :: map()) ::
              {:ok, term()} | {:error, term()} | {:retry, term()} | :ok

  @doc """
  Calculates retry backoff delay in milliseconds.

  Default implementation uses exponential backoff.
  """
  @callback backoff(attempt :: pos_integer()) :: pos_integer()

  @doc """
  Returns dynamic timeout based on context.

  Default returns the configured timeout.
  """
  @callback timeout(context :: map()) :: pos_integer()

  @optional_callbacks [backoff: 1, timeout: 1]

  @doc """
  Sets up the worker module with default implementations.

  ## Usage

      defmodule MyWorker do
        use Events.Infra.Scheduler.Worker
        # ...
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Events.Infra.Scheduler.Worker

      alias Events.Infra.Scheduler.{Job, Config}
      alias Events.Infra.Scheduler.Cron.Macros

      # Import cron macros
      use Macros

      @doc false
      def backoff(attempt) do
        # Default exponential backoff: 1s, 2s, 4s, 8s, ...
        min(:timer.seconds(round(:math.pow(2, attempt - 1))), :timer.minutes(15))
      end

      @doc false
      def timeout(_context) do
        schedule()[:timeout] || 60_000
      end

      defoverridable backoff: 1, timeout: 1

      @doc """
      Returns the job specification for this worker.
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
