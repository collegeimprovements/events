defmodule OmBehaviours.Worker do
  @moduledoc """
  Base behaviour for background job execution.

  Workers define units of work that can be performed asynchronously, on a schedule,
  or in response to events. They provide a consistent interface for job execution
  with optional scheduling, backoff, and timeout configuration.

  ## Design Principles

  - **Single Task**: Each worker handles one type of job
  - **Idempotent**: Jobs should be safe to retry
  - **Result Tuples**: Return `{:ok, result}` or `{:error, reason}`
  - **Configurable**: Override backoff, timeout, and schedule per worker

  ## Example

      defmodule MyApp.Workers.SendEmail do
        use OmBehaviours.Worker

        @impl true
        def perform(%{to: to, subject: subject, body: body}) do
          case Mailer.deliver(to, subject, body) do
            {:ok, _} -> {:ok, :sent}
            {:error, reason} -> {:error, reason}
          end
        end
      end

      # With schedule and custom backoff
      defmodule MyApp.Workers.DailyCleanup do
        use OmBehaviours.Worker

        @impl true
        def perform(_args) do
          deleted = Repo.delete_all(expired_query())
          {:ok, %{deleted: deleted}}
        end

        @impl true
        def schedule, do: "0 3 * * *"

        @impl true
        def backoff(attempt), do: min(1000 * :math.pow(2, attempt) |> trunc(), 30_000)

        @impl true
        def timeout, do: :timer.minutes(10)
      end
  """

  @doc """
  Executes the worker's job with the given arguments.

  This is the only required callback. It receives the job arguments
  and should return a result tuple.

  ## Parameters

  - `args` - Job arguments (typically a map)

  ## Returns

  - `{:ok, result}` — Job completed successfully
  - `{:error, reason}` — Job failed

  ## Examples

      @impl true
      def perform(%{user_id: user_id}) do
        case Users.send_welcome_email(user_id) do
          {:ok, _} -> {:ok, :sent}
          {:error, reason} -> {:error, reason}
        end
      end
  """
  @callback perform(args :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Returns a cron expression for scheduled execution.

  Optional. When implemented, the worker will run on the defined schedule.
  Return `nil` for workers that are only triggered manually.

  ## Examples

      # Every day at 3 AM
      def schedule, do: "0 3 * * *"

      # Every 5 minutes
      def schedule, do: "*/5 * * * *"

      # No schedule (manual only)
      def schedule, do: nil
  """
  @callback schedule() :: String.t() | nil

  @doc """
  Calculates the backoff delay in milliseconds for a given retry attempt.

  Optional. Override to customize retry behavior. The default implementation
  uses exponential backoff: `min(1000 * 2^attempt, 30_000)`.

  ## Parameters

  - `attempt` - The retry attempt number (0-indexed)

  ## Returns

  Delay in milliseconds before the next retry.

  ## Examples

      # Linear backoff
      def backoff(attempt), do: 1000 * (attempt + 1)

      # Fixed delay
      def backoff(_attempt), do: 5_000
  """
  @callback backoff(attempt :: non_neg_integer()) :: non_neg_integer()

  @doc """
  Returns the maximum execution time in milliseconds.

  Optional. Override to set a custom timeout. The default is 60 seconds.

  ## Examples

      # 10 minute timeout for heavy jobs
      def timeout, do: :timer.minutes(10)

      # 5 second timeout for quick jobs
      def timeout, do: 5_000
  """
  @callback timeout() :: non_neg_integer()

  @doc """
  Sets up a module as a Worker with sensible defaults.

  Provides default implementations for optional callbacks:
  - `schedule/0` → `nil` (no schedule)
  - `backoff/1` → exponential backoff capped at 30s
  - `timeout/0` → 60 seconds

  Only `perform/1` must be implemented.

  ## Example

      defmodule MyApp.Workers.ProcessOrder do
        use OmBehaviours.Worker

        @impl true
        def perform(%{order_id: order_id}) do
          order_id |> Orders.get!() |> Orders.process()
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour OmBehaviours.Worker

      @doc false
      @impl OmBehaviours.Worker
      def schedule, do: nil

      @doc false
      @impl OmBehaviours.Worker
      def backoff(attempt) do
        delay = 1000 * :math.pow(2, attempt) |> trunc()
        min(delay, 30_000)
      end

      @doc false
      @impl OmBehaviours.Worker
      def timeout, do: 60_000

      defoverridable schedule: 0, backoff: 1, timeout: 0
    end
  end

  @doc """
  Checks if a module implements the Worker behaviour.

  ## Examples

      iex> OmBehaviours.Worker.implements?(MyApp.Workers.SendEmail)
      true

      iex> OmBehaviours.Worker.implements?(SomeOtherModule)
      false
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    OmBehaviours.implements?(module, __MODULE__)
  end
end
