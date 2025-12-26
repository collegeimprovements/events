defmodule OmScheduler.Middleware do
  @moduledoc ~S"""
  Middleware chain for job lifecycle interception.

  Middleware allows cross-cutting concerns like logging, metrics,
  error handling, and custom logic to be applied to all jobs.

  ## Configuration

      config :om_scheduler,
        middleware: [
          OmScheduler.Middleware.Logging,
          OmScheduler.Middleware.Metrics,
          {MyApp.Middleware.Sentry, capture_errors: true}
        ]

  ## Implementing Middleware

      defmodule MyApp.Middleware.Timing do
        @behaviour OmScheduler.Middleware

        @impl true
        def before_execute(job, context) do
          {:ok, Map.put(context, :started_at, System.monotonic_time())}
        end

        @impl true
        def after_execute(job, result, context) do
          duration = System.monotonic_time() - context.started_at
          Logger.info("Job #{job.name} took #{duration}ns")
          {:ok, result}
        end

        @impl true
        def on_error(job, error, context) do
          Logger.error("Job #{job.name} failed: #{inspect(error)}")
          {:ok, error}
        end
      end

  ## Lifecycle Hooks

  - `before_execute/2` - Before job execution starts
  - `after_execute/3` - After successful execution
  - `on_error/3` - When job raises or returns error
  - `on_complete/3` - Always called (success or failure)

  ## Context

  Middleware can store data in context that's passed to subsequent hooks:

      def before_execute(job, context) do
        {:ok, Map.put(context, :my_data, "value")}
      end

      def after_execute(job, result, context) do
        my_data = context.my_data  # Access stored data
        {:ok, result}
      end
  """

  alias OmScheduler.Job

  @type context :: map()
  @type result :: {:ok, term()} | {:error, term()} | {:retry, term()}

  # ============================================
  # Behaviour
  # ============================================

  @doc """
  Called before job execution starts.

  Return `{:ok, context}` to continue, or `{:halt, reason}` to stop execution.
  """
  @callback before_execute(Job.t(), context()) ::
              {:ok, context()} | {:halt, term()}

  @doc """
  Called after successful job execution.

  Can transform the result or perform side effects.
  """
  @callback after_execute(Job.t(), result(), context()) ::
              {:ok, result()} | {:error, term()}

  @doc """
  Called when job execution fails.

  Can transform the error, trigger recovery, or perform logging.
  """
  @callback on_error(Job.t(), term(), context()) ::
              {:ok, term()} | {:retry, term()} | {:ignore, term()}

  @doc """
  Called after job completes (success or failure).

  Useful for cleanup, metrics, or resource release.
  """
  @callback on_complete(Job.t(), result(), context()) :: :ok

  @optional_callbacks [on_complete: 3]

  # ============================================
  # Chain Execution
  # ============================================

  @doc """
  Runs the before_execute hooks for all middleware in order.

  Returns `{:ok, context}` if all pass, or `{:halt, reason}` if any halts.
  """
  @spec run_before(Job.t(), [module() | {module(), keyword()}], context()) ::
          {:ok, context()} | {:halt, term()}
  def run_before(job, middleware, context) do
    middleware
    |> normalize_middleware()
    |> Enum.reduce_while({:ok, context}, fn {mod, _opts}, {:ok, ctx} ->
      case safe_call(mod, :before_execute, [job, ctx]) do
        {:ok, new_ctx} -> {:cont, {:ok, new_ctx}}
        {:halt, reason} -> {:halt, {:halt, reason}}
        :ok -> {:cont, {:ok, ctx}}
      end
    end)
  end

  @doc """
  Runs the after_execute hooks for all middleware in reverse order.

  Returns the (possibly transformed) result.
  """
  @spec run_after(Job.t(), result(), [module() | {module(), keyword()}], context()) ::
          {:ok, result()} | {:error, term()}
  def run_after(job, result, middleware, context) do
    middleware
    |> normalize_middleware()
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, result}, fn {mod, _opts}, {:ok, res} ->
      case safe_call(mod, :after_execute, [job, res, context]) do
        {:ok, new_result} -> {:cont, {:ok, new_result}}
        {:error, reason} -> {:halt, {:error, reason}}
        :ok -> {:cont, {:ok, res}}
      end
    end)
  end

  @doc """
  Runs the on_error hooks for all middleware in order.

  Returns the (possibly transformed) error or recovery action.
  """
  @spec run_error(Job.t(), term(), [module() | {module(), keyword()}], context()) ::
          {:ok, term()} | {:retry, term()} | {:ignore, term()}
  def run_error(job, error, middleware, context) do
    middleware
    |> normalize_middleware()
    |> Enum.reduce_while({:ok, error}, fn {mod, _opts}, {:ok, err} ->
      case safe_call(mod, :on_error, [job, err, context]) do
        {:ok, new_error} -> {:cont, {:ok, new_error}}
        {:retry, reason} -> {:halt, {:retry, reason}}
        {:ignore, reason} -> {:halt, {:ignore, reason}}
        :ok -> {:cont, {:ok, err}}
      end
    end)
  end

  @doc """
  Runs the on_complete hooks for all middleware.

  Called for both success and failure. Does not transform results.
  """
  @spec run_complete(Job.t(), result(), [module() | {module(), keyword()}], context()) :: :ok
  def run_complete(job, result, middleware, context) do
    middleware
    |> normalize_middleware()
    |> Enum.each(fn {mod, _opts} ->
      safe_call(mod, :on_complete, [job, result, context])
    end)

    :ok
  end

  @doc """
  Wraps job execution with middleware chain.

  Handles the full lifecycle: before -> execute -> after/error -> complete
  """
  @spec wrap(Job.t(), [module() | {module(), keyword()}], (-> result())) :: result()
  def wrap(job, middleware, execute_fn) do
    initial_context = %{
      job: job,
      started_at: System.monotonic_time(),
      attempt: 1
    }

    case run_before(job, middleware, initial_context) do
      {:ok, context} ->
        result =
          try do
            execute_fn.()
          rescue
            e ->
              handle_execution_error(job, e, middleware, context, __STACKTRACE__)
          catch
            kind, reason ->
              handle_execution_error(job, {kind, reason}, middleware, context, __STACKTRACE__)
          end

        finalize_execution(job, result, middleware, context)

      {:halt, reason} ->
        {:error, {:middleware_halt, reason}}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_middleware(middleware) do
    Enum.map(middleware, fn
      {mod, opts} when is_atom(mod) and is_list(opts) -> {mod, opts}
      mod when is_atom(mod) -> {mod, []}
    end)
  end

  defp safe_call(mod, fun, args) do
    if function_exported?(mod, fun, length(args)) do
      apply(mod, fun, args)
    else
      :ok
    end
  rescue
    e ->
      require Logger
      Logger.warning("[Scheduler.Middleware] Error in #{mod}.#{fun}: #{inspect(e)}")
      :ok
  end

  defp handle_execution_error(job, error, middleware, context, _stacktrace) do
    case run_error(job, error, middleware, context) do
      {:ok, err} -> {:error, err}
      {:retry, reason} -> {:retry, reason}
      {:ignore, _reason} -> {:ok, :ignored}
    end
  end

  defp finalize_execution(job, result, middleware, context) do
    final_result =
      case result do
        {:ok, _} = success ->
          case run_after(job, success, middleware, context) do
            {:ok, res} -> res
            {:error, reason} -> {:error, reason}
          end

        {:error, _} = error ->
          error

        {:retry, _} = retry ->
          retry
      end

    run_complete(job, final_result, middleware, context)
    final_result
  end
end
