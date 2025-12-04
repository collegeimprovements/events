defmodule Events.Support.Middleware do
  @moduledoc """
  Unified middleware abstraction for composable processing pipelines.

  Provides a consistent pattern for middleware chains across the codebase,
  whether for job scheduling, API clients, or custom processing pipelines.

  ## Design Principles

  - **Composable** - Chain multiple middleware together
  - **Lifecycle-aware** - Hooks for before, after, error, and complete
  - **Context-passing** - Middleware can share state through context
  - **Safe execution** - Errors in middleware don't crash the chain

  ## Quick Reference

  | Function | Use Case |
  |----------|----------|
  | `wrap/3` | Execute function with full middleware chain |
  | `run_before/2` | Run only before hooks |
  | `run_after/3` | Run only after hooks |
  | `run_error/3` | Run only error hooks |
  | `pipe/2` | Build a middleware pipeline |

  ## Usage

  ### Implementing Middleware

      defmodule MyApp.TimingMiddleware do
        use Events.Support.Middleware

        @impl true
        def before_execute(context) do
          {:ok, Map.put(context, :started_at, System.monotonic_time())}
        end

        @impl true
        def after_execute(result, context) do
          elapsed = System.monotonic_time() - context.started_at
          Logger.info("Operation took \#{elapsed}ns")
          {:ok, result}
        end
      end

  ### Using Middleware Chain

      alias Events.Support.Middleware

      middleware = [
        MyApp.TimingMiddleware,
        {MyApp.LoggingMiddleware, level: :info}
      ]

      Middleware.wrap(middleware, %{user_id: 123}, fn ->
        do_expensive_operation()
      end)

  ## Lifecycle Hooks

  - `before_execute/1` - Before operation starts, can modify context
  - `after_execute/2` - After successful operation, can transform result
  - `on_error/2` - When operation fails, can recover or transform error
  - `on_complete/2` - Always called (success or failure), for cleanup

  ## Return Values

  | Hook | Success | Halt/Skip |
  |------|---------|-----------|
  | `before_execute` | `{:ok, context}` | `{:halt, reason}` |
  | `after_execute` | `{:ok, result}` | `{:error, reason}` |
  | `on_error` | `{:ok, error}` | `{:retry, reason}` or `{:ignore, reason}` |
  | `on_complete` | `:ok` | — |
  """

  @type context :: map()
  @type result :: {:ok, term()} | {:error, term()} | {:retry, term()}
  @type middleware_spec :: module() | {module(), keyword()}

  # ============================================
  # Behaviour
  # ============================================

  @doc """
  Called before operation execution starts.

  Return `{:ok, context}` to continue with potentially modified context,
  or `{:halt, reason}` to stop the middleware chain.

  ## Example

      def before_execute(context) do
        if authorized?(context) do
          {:ok, Map.put(context, :auth_checked, true)}
        else
          {:halt, :unauthorized}
        end
      end
  """
  @callback before_execute(context()) :: {:ok, context()} | {:halt, term()}

  @doc """
  Called after successful operation execution.

  Can transform the result or perform side effects.

  ## Example

      def after_execute({:ok, data} = result, context) do
        Logger.info("Operation succeeded for user \#{context.user_id}")
        {:ok, result}
      end
  """
  @callback after_execute(result(), context()) :: {:ok, result()} | {:error, term()}

  @doc """
  Called when operation execution fails.

  Can transform the error, trigger recovery, or mark for retry.

  ## Example

      def on_error(error, context) do
        if retryable?(error) do
          {:retry, error}
        else
          {:ok, error}
        end
      end
  """
  @callback on_error(term(), context()) :: {:ok, term()} | {:retry, term()} | {:ignore, term()}

  @doc """
  Called after operation completes (success or failure).

  Useful for cleanup, metrics, or resource release.

  ## Example

      def on_complete(result, context) do
        Metrics.record(:operation_complete, context.operation_name)
        :ok
      end
  """
  @callback on_complete(result(), context()) :: :ok

  @optional_callbacks [
    before_execute: 1,
    after_execute: 2,
    on_error: 2,
    on_complete: 2
  ]

  # ============================================
  # Using Macro
  # ============================================

  @doc """
  Sets up a module as middleware.

  Provides default implementations for all callbacks that simply pass through.

  ## Example

      defmodule MyMiddleware do
        use Events.Support.Middleware

        @impl true
        def before_execute(context) do
          # Only implement what you need
          {:ok, context}
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Events.Support.Middleware

      @impl true
      def before_execute(context), do: {:ok, context}

      @impl true
      def after_execute(result, _context), do: {:ok, result}

      @impl true
      def on_error(error, _context), do: {:ok, error}

      @impl true
      def on_complete(_result, _context), do: :ok

      defoverridable before_execute: 1, after_execute: 2, on_error: 2, on_complete: 2
    end
  end

  # ============================================
  # Chain Execution
  # ============================================

  @doc """
  Wraps a function execution with middleware chain.

  Handles the full lifecycle: before -> execute -> after/error -> complete

  ## Parameters

  - `middleware` - List of middleware modules or {module, opts} tuples
  - `context` - Initial context map
  - `fun` - Function to execute

  ## Examples

      Middleware.wrap([TimingMiddleware, LoggingMiddleware], %{}, fn ->
        expensive_operation()
      end)

      Middleware.wrap(
        [{RateLimiter, bucket: "api"}],
        %{user_id: 123},
        fn -> api_call() end
      )
  """
  @spec wrap([middleware_spec()], context(), (-> term())) :: result()
  def wrap(middleware, context, fun) when is_list(middleware) and is_function(fun, 0) do
    initial_context =
      context
      |> Map.put_new(:started_at, System.monotonic_time())
      |> Map.put_new(:middleware_chain, middleware)

    case run_before(middleware, initial_context) do
      {:ok, ctx} ->
        result =
          try do
            case fun.() do
              {:ok, _} = success -> success
              {:error, _} = error -> error
              other -> {:ok, other}
            end
          rescue
            e ->
              handle_execution_error(e, middleware, ctx, __STACKTRACE__)
          catch
            kind, reason ->
              handle_execution_error({kind, reason}, middleware, ctx, __STACKTRACE__)
          end

        finalize_execution(result, middleware, ctx)

      {:halt, reason} ->
        {:error, {:middleware_halt, reason}}
    end
  end

  @doc """
  Runs before_execute hooks for all middleware in order.

  Returns `{:ok, context}` if all pass, or `{:halt, reason}` if any halts.

  ## Examples

      {:ok, context} = Middleware.run_before([Auth, Logging], %{user_id: 1})
      {:halt, :unauthorized} = Middleware.run_before([Auth], %{})
  """
  @spec run_before([middleware_spec()], context()) :: {:ok, context()} | {:halt, term()}
  def run_before(middleware, context) do
    middleware
    |> normalize()
    |> Enum.reduce_while({:ok, context}, fn {mod, opts}, {:ok, ctx} ->
      ctx_with_opts = Map.put(ctx, :middleware_opts, opts)

      case safe_call(mod, :before_execute, [ctx_with_opts]) do
        {:ok, new_ctx} -> {:cont, {:ok, new_ctx}}
        {:halt, reason} -> {:halt, {:halt, reason}}
        :ok -> {:cont, {:ok, ctx}}
      end
    end)
  end

  @doc """
  Runs after_execute hooks for all middleware in reverse order.

  Returns the (possibly transformed) result.

  ## Examples

      {:ok, result} = Middleware.run_after([Transform, Log], {:ok, data}, %{})
  """
  @spec run_after([middleware_spec()], result(), context()) ::
          {:ok, result()} | {:error, term()}
  def run_after(middleware, result, context) do
    middleware
    |> normalize()
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, result}, fn {mod, opts}, {:ok, res} ->
      ctx_with_opts = Map.put(context, :middleware_opts, opts)

      case safe_call(mod, :after_execute, [res, ctx_with_opts]) do
        {:ok, new_result} -> {:cont, {:ok, new_result}}
        {:error, reason} -> {:halt, {:error, reason}}
        :ok -> {:cont, {:ok, res}}
      end
    end)
  end

  @doc """
  Runs on_error hooks for all middleware in order.

  Returns the (possibly transformed) error or recovery action.

  ## Examples

      {:retry, error} = Middleware.run_error([RetryPolicy], error, %{})
      {:ignore, _} = Middleware.run_error([IgnorePolicy], error, %{})
  """
  @spec run_error([middleware_spec()], term(), context()) ::
          {:ok, term()} | {:retry, term()} | {:ignore, term()}
  def run_error(middleware, error, context) do
    middleware
    |> normalize()
    |> Enum.reduce_while({:ok, error}, fn {mod, opts}, {:ok, err} ->
      ctx_with_opts = Map.put(context, :middleware_opts, opts)

      case safe_call(mod, :on_error, [err, ctx_with_opts]) do
        {:ok, new_error} -> {:cont, {:ok, new_error}}
        {:retry, reason} -> {:halt, {:retry, reason}}
        {:ignore, reason} -> {:halt, {:ignore, reason}}
        :ok -> {:cont, {:ok, err}}
      end
    end)
  end

  @doc """
  Runs on_complete hooks for all middleware.

  Called for both success and failure. Does not transform results.

  ## Examples

      :ok = Middleware.run_complete([Metrics, Cleanup], {:ok, result}, %{})
  """
  @spec run_complete([middleware_spec()], result(), context()) :: :ok
  def run_complete(middleware, result, context) do
    middleware
    |> normalize()
    |> Enum.each(fn {mod, opts} ->
      ctx_with_opts = Map.put(context, :middleware_opts, opts)
      safe_call(mod, :on_complete, [result, ctx_with_opts])
    end)

    :ok
  end

  @doc """
  Creates a middleware pipeline function.

  Returns a function that wraps any operation with the middleware chain.

  ## Examples

      pipeline = Middleware.pipe([Auth, Logging, Metrics])

      # Later, use the pipeline
      pipeline.(%{user_id: 1}, fn -> do_work() end)
  """
  @spec pipe([middleware_spec()]) :: (context(), (-> term()) -> result())
  def pipe(middleware) when is_list(middleware) do
    fn context, fun ->
      wrap(middleware, context, fun)
    end
  end

  @doc """
  Creates a composed middleware from multiple middleware.

  Useful for creating reusable middleware groups.

  ## Examples

      standard_middleware = Middleware.compose([
        Auth,
        {RateLimit, bucket: "default"},
        Logging
      ])

      # Use as single middleware
      Middleware.wrap([standard_middleware, CustomMiddleware], ctx, fun)
  """
  @spec compose([middleware_spec()]) :: module()
  def compose(middleware) when is_list(middleware) do
    # Create a dynamic module that delegates to the middleware chain
    # For now, we return a tuple that wrap/3 can handle
    {:composed, middleware}
  end

  # ============================================
  # Helpers
  # ============================================

  @doc """
  Normalizes middleware specification to {module, opts} tuples.

  ## Examples

      Middleware.normalize([MyModule, {OtherModule, key: :val}])
      #=> [{MyModule, []}, {OtherModule, [key: :val]}]
  """
  @spec normalize([middleware_spec()]) :: [{module(), keyword()}]
  def normalize(middleware) do
    Enum.flat_map(middleware, fn
      {:composed, inner} -> normalize(inner)
      {mod, opts} when is_atom(mod) and is_list(opts) -> [{mod, opts}]
      mod when is_atom(mod) -> [{mod, []}]
    end)
  end

  # ============================================
  # Private
  # ============================================

  defp safe_call(mod, fun, args) do
    if function_exported?(mod, fun, length(args)) do
      apply(mod, fun, args)
    else
      :ok
    end
  rescue
    e ->
      require Logger
      Logger.warning("[Middleware] Error in #{mod}.#{fun}: #{Exception.message(e)}")
      :ok
  end

  defp handle_execution_error(error, middleware, context, _stacktrace) do
    case run_error(middleware, error, context) do
      {:ok, err} -> {:error, err}
      {:retry, reason} -> {:retry, reason}
      {:ignore, _reason} -> {:ok, :ignored}
    end
  end

  defp finalize_execution(result, middleware, context) do
    final_result =
      case result do
        {:ok, _} = success ->
          case run_after(middleware, success, context) do
            {:ok, res} -> res
            {:error, reason} -> {:error, reason}
          end

        {:error, _} = error ->
          error

        {:retry, _} = retry ->
          retry
      end

    run_complete(middleware, final_result, context)
    final_result
  end
end
