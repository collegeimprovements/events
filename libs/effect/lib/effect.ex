defmodule Effect do
  @moduledoc """
  Composable, resumable workflow orchestration for Elixir.

  Effect follows the **Req/Plug middleware pattern**:
  - **Build phase**: Accumulate steps, configuration, middleware (no execution)
  - **Run phase**: Execute only when `Effect.run/2` is called
  - **Composable**: Effects can be merged, nested, and reused

  ## Quick Start

      Effect.new(:order)
      |> Effect.step(:validate, &validate/1)
      |> Effect.step(:charge, &charge/1, retry: [max: 3])
      |> Effect.step(:fulfill, &fulfill/1, rollback: &refund/1)
      |> Effect.run(context)

  ## Step Return Values

  Steps must return one of:
  - `{:ok, map}` - Continue, merge map into context
  - `{:error, term}` - Stop, trigger rollbacks
  - `{:halt, term}` - Stop gracefully, run ensure, NO rollback

  ## Step Function Signatures

  - 1-arity: `fn ctx -> result end` (no services needed)
  - 2-arity: `fn ctx, services -> result end` (explicit service access)

  ## Features

  - DAG-based step execution with dependencies
  - Saga pattern with automatic rollback
  - Retry with configurable backoff strategies
  - Parallel, branch, race, each primitives
  - Middleware for cross-cutting concerns
  - Checkpoint/resume for long workflows
  - Zero-cost build phase (pure data transformations)
  """

  alias Effect.{Builder, Runtime, Step, Error, Report}

  @type t :: Builder.t()

  # ============================================
  # Creation
  # ============================================

  @doc """
  Creates a new Effect with the given name.

  ## Options

  - `:label` - Human-readable description
  - `:tags` - Categorization tags
  - `:metadata` - Arbitrary metadata carried through execution
  - `:services` - Map of service name to module (for DI)
  - `:telemetry` - Telemetry event prefix

  ## Examples

      Effect.new(:order_processing)
      Effect.new(:order, label: "Order Processing", tags: [:critical])
      Effect.new(:order, services: %{payment: StripeGateway})
  """
  @spec new(atom(), keyword()) :: t()
  defdelegate new(name, opts \\ []), to: Builder

  # ============================================
  # Step Building
  # ============================================

  @doc """
  Adds a step to the effect.

  ## Options

  - `:after` - Step(s) that must complete before this one
  - `:timeout` - Per-attempt timeout in milliseconds
  - `:retry` - Retry configuration
  - `:when` - Condition function; step skipped if returns false
  - `:rollback` - Rollback function for saga pattern
  - `:catch` - Error handler function
  - `:fallback` - Default value on error
  - `:meta` - Arbitrary metadata

  ## Examples

      effect
      |> Effect.step(:validate, &validate/1)
      |> Effect.step(:charge, &charge/1, after: :validate, retry: [max: 3])
  """
  @spec step(t(), atom(), Step.step_fun(), keyword()) :: t()
  defdelegate step(effect, name, fun, opts \\ []), to: Builder

  @doc """
  Assigns a value to the context.

  ## Examples

      effect
      |> Effect.assign(:timestamp, DateTime.utc_now())
      |> Effect.assign(:config, fn ctx -> load_config(ctx.env) end)
  """
  @spec assign(t(), atom(), term() | (map() -> term())) :: t()
  defdelegate assign(effect, key, value), to: Builder

  @doc """
  Adds a tap step for side effects (doesn't modify context).

  ## Examples

      Effect.tap(effect, :log, fn ctx -> Logger.info("Order: \#{ctx.id}") end)
  """
  @spec tap(t(), atom(), (map() -> any()), keyword()) :: t()
  defdelegate tap(effect, name, fun, opts \\ []), to: Builder

  @doc """
  Adds a precondition that must be true to continue.

  ## Examples

      Effect.require(effect, :auth, & &1.user.admin?, :unauthorized)
  """
  @spec require(t(), atom(), (map() -> boolean()), term(), keyword()) :: t()
  defdelegate require(effect, name, condition, error, opts \\ []), to: Builder

  @doc """
  Adds a validation step.

  ## Examples

      Effect.validate(effect, :amount, fn ctx ->
        if ctx.amount > 0, do: :ok, else: {:error, :invalid_amount}
      end)
  """
  @spec validate(t(), atom(), (map() -> :ok | {:error, term()}), keyword()) :: t()
  defdelegate validate(effect, name, validator, opts \\ []), to: Builder

  @doc """
  Adds a group of steps that execute in parallel.

  ## Options

  - `:after` - Step(s) that must complete before this parallel group
  - `:on_error` - `:fail_fast` (default) or `:continue`
  - `:timeout` - Per-step timeout in milliseconds

  ## Examples

      effect
      |> Effect.parallel(:checks, [
        {:fraud, &check_fraud/1},
        {:inventory, &check_inventory/1}
      ], after: :validate)
  """
  @spec parallel(t(), atom(), [{atom(), Step.step_fun()}], keyword()) :: t()
  defdelegate parallel(effect, name, steps, opts \\ []), to: Builder

  @doc """
  Adds a conditional branch that selects a path based on context.

  ## Options

  - `:after` - Step(s) that must complete before this branch
  - `:default` - Default route if no match

  ## Examples

      effect
      |> Effect.branch(:fulfill, & &1.order_type, %{
        digital: fn ctx -> {:ok, %{fulfilled: :digital}} end,
        physical: fn ctx -> {:ok, %{fulfilled: :physical}} end
      }, after: :validate)
  """
  @spec branch(t(), atom(), (map() -> term()), map(), keyword()) :: t()
  defdelegate branch(effect, name, selector, routes, opts \\ []), to: Builder

  @doc """
  Embeds a nested effect into the parent effect.

  ## Options

  - `:after` - Step(s) that must complete before this embedded effect
  - `:context` - Function to transform parent context for nested effect

  ## Examples

      effect
      |> Effect.embed(:payment, PaymentFlow.build(), after: :validate)
  """
  @spec embed(t(), atom(), t(), keyword()) :: t()
  defdelegate embed(effect, name, nested_effect, opts \\ []), to: Builder

  @doc """
  Iterates over a collection, executing a nested effect for each item.

  ## Options

  - `:after` - Step(s) that must complete before iteration
  - `:concurrency` - Number of concurrent iterations (default: 1)
  - `:as` - Key to use for current item in context (default: :item)
  - `:collect` - Key to collect results into

  ## Examples

      effect
      |> Effect.each(:process_items, & &1.items, ItemProcessor.build())
  """
  @spec each(t(), atom(), (map() -> list()), t(), keyword()) :: t()
  defdelegate each(effect, name, extractor, item_effect, opts \\ []), to: Builder

  @doc """
  Races multiple effects, returning the first successful result.

  ## Options

  - `:after` - Step(s) that must complete before the race
  - `:timeout` - Overall race timeout in milliseconds

  ## Examples

      effect
      |> Effect.race(:fetch_data, [CacheEffect.build(), DbEffect.build()])
  """
  @spec race(t(), atom(), [t()], keyword()) :: t()
  defdelegate race(effect, name, contestants, opts \\ []), to: Builder

  @doc """
  Manages a resource with acquire/use/release lifecycle.

  ## Options

  - `:after` - Step(s) that must complete before resource acquisition
  - `:as` - Key to store the acquired resource in context

  ## Examples

      effect
      |> Effect.using(:conn, [
        acquire: fn ctx -> {:ok, %{conn: DB.checkout()}} end,
        release: fn ctx, _result -> DB.checkin(ctx.conn) end,
        body: DatabaseOps.build()
      ])
  """
  @spec using(t(), atom(), keyword()) :: t()
  defdelegate using(effect, name, opts), to: Builder

  @doc """
  Adds a checkpoint for pausing and resuming long-running workflows.

  ## Options

  - `:after` - Step(s) that must complete before this checkpoint
  - `:store` - Function to persist checkpoint state
  - `:load` - Function to load checkpoint state

  ## Examples

      effect
      |> Effect.checkpoint(:await_approval,
        store: &MyStore.save/2,
        load: &MyStore.load/1
      )

  ## Returns

  When execution reaches a checkpoint:
  - `{:checkpoint, execution_id, checkpoint_name, context}`

  Resume later with `Effect.resume/2`.
  """
  @spec checkpoint(t(), atom(), keyword()) :: t()
  defdelegate checkpoint(effect, name, opts \\ []), to: Builder

  @doc """
  Resumes execution from a checkpoint.

  ## Examples

      {:ok, ctx} = Effect.resume(effect, "execution_id_123")
  """
  @spec resume(t(), String.t(), keyword()) :: term()
  defdelegate resume(effect, execution_id, opts \\ []), to: Runtime

  # ============================================
  # Middleware & Hooks
  # ============================================

  @doc """
  Adds middleware that wraps every step execution.

  ## Examples

      Effect.middleware(effect, fn step, ctx, next ->
        start = System.monotonic_time(:millisecond)
        result = next.()
        IO.puts("[\#{step}] completed in \#{System.monotonic_time(:millisecond) - start}ms")
        result
      end)
  """
  @spec middleware(t(), Builder.middleware_fun()) :: t()
  defdelegate middleware(effect, fun), to: Builder

  @doc "Adds a hook that runs on effect start."
  @spec on_start(t(), Builder.hook_fun()) :: t()
  defdelegate on_start(effect, fun), to: Builder

  @doc "Adds a hook that runs on effect completion."
  @spec on_complete(t(), Builder.hook_fun()) :: t()
  defdelegate on_complete(effect, fun), to: Builder

  @doc "Adds a hook that runs on step error."
  @spec on_error(t(), (atom(), term(), map() -> any())) :: t()
  defdelegate on_error(effect, fun), to: Builder

  @doc "Adds a hook that runs on rollback."
  @spec on_rollback(t(), Builder.hook_fun()) :: t()
  defdelegate on_rollback(effect, fun), to: Builder

  @doc "Adds cleanup that always runs (like try/after)."
  @spec ensure(t(), atom(), Builder.cleanup_fun()) :: t()
  defdelegate ensure(effect, name, fun), to: Builder

  # ============================================
  # Inspection
  # ============================================

  @doc "Returns list of step names in definition order."
  @spec step_names(t()) :: [atom()]
  defdelegate step_names(effect), to: Builder

  @doc "Returns information about a specific step."
  @spec step_info(t(), atom()) :: {:ok, Step.t()} | {:error, :not_found}
  defdelegate step_info(effect, name), to: Builder

  @doc """
  Validates the effect structure.

  Checks for:
  - Cycles in step dependencies
  - Missing dependency references
  - Duplicate step names

  ## Examples

      case Effect.validate(effect) do
        :ok -> :proceed
        {:error, {:cycle_detected, path}} -> handle_cycle(path)
      end
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%Builder{} = effect) do
    case Builder.build_dag(effect) do
      {:ok, _dag} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================
  # Execution
  # ============================================

  @doc """
  Executes the effect with the given initial context.

  ## Options

  - `:timeout` - Total execution timeout in milliseconds
  - `:report` - If true, returns `{result, Report.t()}`
  - `:debug` - If true, logs step execution
  - `:services` - Override services from effect definition

  ## Returns

  - `{:ok, context}` - Completed successfully
  - `{:error, Error.t()}` - Failed, rollbacks executed
  - `{:halted, reason}` - Halted early via `{:halt, reason}`

  ## Examples

      {:ok, result} = Effect.run(effect, %{order_id: 123})
      {:ok, result, report} = Effect.run(effect, ctx, report: true)
  """
  @spec run(t(), map(), keyword()) ::
          {:ok, map()}
          | {:error, Error.t()}
          | {:halted, term()}
          | {{:ok, map()}, Report.t()}
          | {{:error, Error.t()}, Report.t()}
          | {{:halted, term()}, Report.t()}
  defdelegate run(effect, ctx, opts \\ []), to: Runtime

  @doc """
  Executes the effect, raising on error.

  ## Examples

      result = Effect.run!(effect, context)
  """
  @spec run!(t(), map(), keyword()) :: map() | no_return()
  def run!(%Builder{} = effect, ctx, opts \\ []) do
    case Runtime.run(effect, ctx, opts) do
      {:ok, result} -> result
      {:error, error} -> raise Error.message(error)
      {:halted, reason} -> raise "Effect halted: #{inspect(reason)}"
    end
  end

  # ============================================
  # Visualization
  # ============================================

  @doc """
  Generates an ASCII representation of the effect structure.

  ## Examples

      effect |> Effect.to_ascii() |> IO.puts()
  """
  @spec to_ascii(t(), keyword()) :: String.t()
  defdelegate to_ascii(effect, opts \\ []), to: Effect.Visualization

  @doc """
  Generates a Mermaid flowchart of the effect structure.

  ## Examples

      effect |> Effect.to_mermaid() |> IO.puts()
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  defdelegate to_mermaid(effect, opts \\ []), to: Effect.Visualization

  @doc """
  Returns a summary of the effect structure.

  ## Examples

      Effect.summary(effect)
      #=> %{name: :order, step_count: 3, ...}
  """
  @spec summary(t()) :: map()
  defdelegate summary(effect), to: Effect.Visualization
end
