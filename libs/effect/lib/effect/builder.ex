defmodule Effect.Builder do
  @moduledoc """
  Builder module for constructing Effect workflows.

  Effects are built lazily - no execution happens until `Effect.run/2` is called.
  This follows the Req/Plug pattern of accumulating configuration.

  ## Example

      Effect.new(:order)
      |> Effect.step(:validate, &validate/1)
      |> Effect.step(:charge, &charge/1, retry: [max: 3])
      |> Effect.step(:fulfill, &fulfill/1, rollback: &refund/1)
      |> Effect.run(context)
  """

  alias Effect.Step

  @type hook_fun :: (atom(), map() -> any())
  @type middleware_fun :: (atom(), map(), (-> term()) -> term())
  @type cleanup_fun :: (map(), term() -> any())

  @type t :: %__MODULE__{
          name: atom(),
          steps: [Step.t()],
          dag: Dag.t() | nil,
          middleware: [middleware_fun()],
          hooks: %{
            on_start: [hook_fun()],
            on_complete: [hook_fun()],
            on_error: [hook_fun()],
            on_rollback: [hook_fun()]
          },
          services: %{atom() => module()},
          metadata: map(),
          label: String.t() | nil,
          tags: [atom()],
          telemetry_prefix: [atom()] | nil,
          checkpoints: %{atom() => map()},
          ensure_fns: [{atom(), cleanup_fun()}]
        }

  defstruct name: nil,
            steps: [],
            dag: nil,
            middleware: [],
            hooks: %{on_start: [], on_complete: [], on_error: [], on_rollback: []},
            services: %{},
            metadata: %{},
            label: nil,
            tags: [],
            telemetry_prefix: nil,
            checkpoints: %{},
            ensure_fns: []

  @doc """
  Creates a new Effect with the given name.

  ## Options

  - `:label` - Human-readable description
  - `:tags` - Categorization tags
  - `:metadata` - Arbitrary metadata carried through execution
  - `:services` - Map of service name to module (for dependency injection)
  - `:telemetry` - Telemetry event prefix

  ## Examples

      Effect.new(:order_processing)
      Effect.new(:order, label: "Order Processing", tags: [:critical, :payment])
      Effect.new(:order, services: %{payment: StripeGateway})
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      label: Keyword.get(opts, :label),
      tags: Keyword.get(opts, :tags, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      services: Keyword.get(opts, :services, %{}),
      telemetry_prefix: Keyword.get(opts, :telemetry)
    }
  end

  @doc """
  Adds a step to the effect.

  ## Arguments

  - `effect` - The effect to add the step to
  - `name` - Unique atom identifier for the step
  - `fun` - Function to execute (1-arity or 2-arity for services)
  - `opts` - Step options (see `Effect.Step` for full list)

  ## Examples

      effect
      |> Effect.step(:validate, &validate/1)
      |> Effect.step(:charge, &charge/1, after: :validate, retry: [max: 3])
      |> Effect.step(:notify, fn ctx, services -> services.mailer.send(ctx) end)
  """
  @spec step(t(), atom(), Step.step_fun(), keyword()) :: t()
  def step(%__MODULE__{steps: steps} = effect, name, fun, opts \\ []) do
    step = Step.new(name, fun, opts)
    %{effect | steps: steps ++ [step]}
  end

  @doc """
  Assigns a static or computed value to the context.

  ## Examples

      effect
      |> Effect.assign(:timestamp, DateTime.utc_now())
      |> Effect.assign(:config, fn ctx -> load_config(ctx.env) end)
  """
  @spec assign(t(), atom(), term() | (map() -> term())) :: t()
  def assign(%__MODULE__{} = effect, key, value) when is_function(value, 1) do
    step(effect, key, fn ctx -> {:ok, %{key => value.(ctx)}} end, type: :assign)
  end

  def assign(%__MODULE__{} = effect, key, value) do
    step(effect, key, fn _ctx -> {:ok, %{key => value}} end, type: :assign)
  end

  @doc """
  Adds a tap step that executes a side effect without modifying context.

  The function's return value is ignored. Useful for logging, metrics, etc.

  ## Examples

      effect
      |> Effect.tap(:log, fn ctx -> Logger.info("Processing order \#{ctx.order_id}") end)
  """
  @spec tap(t(), atom(), (map() -> any()), keyword()) :: t()
  def tap(%__MODULE__{} = effect, name, fun, opts \\ []) do
    wrapped = fn ctx ->
      fun.(ctx)
      {:ok, %{}}
    end

    step(effect, name, wrapped, Keyword.put(opts, :type, :tap))
  end

  @doc """
  Adds a precondition gate that halts with error if condition is false.

  Unlike `validate`, require steps don't produce output - they just assert invariants.

  ## Examples

      effect
      |> Effect.require(:authorized, & &1.user.admin?, :unauthorized)
      |> Effect.require(:has_items, fn ctx -> length(ctx.items) > 0 end, :empty_order)
  """
  @spec require(t(), atom(), (map() -> boolean()), term(), keyword()) :: t()
  def require(%__MODULE__{} = effect, name, condition, error_reason, opts \\ []) do
    wrapped = fn ctx ->
      if condition.(ctx) do
        {:ok, %{}}
      else
        {:error, error_reason}
      end
    end

    step(effect, name, wrapped, Keyword.put(opts, :type, :require))
  end

  @doc """
  Adds a validation step that returns :ok or {:error, reason}.

  ## Examples

      effect
      |> Effect.validate(:check_amount, fn ctx ->
        if ctx.amount > 0, do: :ok, else: {:error, :invalid_amount}
      end)
  """
  @spec validate(t(), atom(), (map() -> :ok | {:error, term()}), keyword()) :: t()
  def validate(%__MODULE__{} = effect, name, validator, opts \\ []) do
    wrapped = fn ctx ->
      case validator.(ctx) do
        :ok -> {:ok, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

    step(effect, name, wrapped, Keyword.put(opts, :type, :validate))
  end

  @doc """
  Adds a group of steps that execute in parallel.

  All steps in the group receive the same context snapshot (taken before
  parallel execution begins). Results are merged left-to-right by declaration
  order (last writer wins for duplicate keys).

  ## Options

  - `:after` - Step(s) that must complete before this parallel group
  - `:on_error` - `:fail_fast` (default) or `:continue`
  - `:timeout` - Per-step timeout in milliseconds (default: 30_000)
  - `:max_concurrency` - Max concurrent tasks

  ## Examples

      effect
      |> Effect.parallel(:checks, [
        {:fraud, &check_fraud/1},
        {:inventory, &check_inventory/1}
      ], after: :validate)

      # With continue mode - run all steps even if one fails
      effect
      |> Effect.parallel(:validations, [
        {:email, &validate_email/1},
        {:phone, &validate_phone/1}
      ], on_error: :continue)
  """
  @spec parallel(t(), atom(), [{atom(), Step.step_fun()}], keyword()) :: t()
  def parallel(%__MODULE__{} = effect, name, steps, opts \\ []) when is_atom(name) and is_list(steps) do
    # Store parallel steps configuration in step metadata
    parallel_opts = Keyword.take(opts, [:on_error, :timeout, :max_concurrency])
    step_opts = Keyword.drop(opts, [:on_error, :timeout, :max_concurrency])

    meta = %{
      parallel_steps: steps,
      parallel_opts: parallel_opts
    }

    # Create a placeholder step that will be handled specially by the runtime
    step(effect, name, nil, Keyword.merge(step_opts, type: :parallel, meta: meta))
  end

  @doc """
  Adds a conditional branch that selects a path based on context.

  The selector function receives the context and returns a key. The key is used
  to look up which route to execute. Routes can be step functions or nested Effects.

  ## Options

  - `:after` - Step(s) that must complete before this branch
  - `:default` - Default route if no match (or use `:default` key in routes)

  ## Examples

      # Branch based on order type
      effect
      |> Effect.branch(:fulfill, & &1.order_type, %{
        digital: fn ctx -> {:ok, %{fulfilled: send_download_link(ctx)}} end,
        physical: fn ctx -> {:ok, %{fulfilled: create_shipment(ctx)}} end,
        default: fn ctx -> {:ok, %{fulfilled: :pending_review}} end
      }, after: :payment)

      # With nested effects as routes
      effect
      |> Effect.branch(:process, & &1.type, %{
        premium: PremiumFlow.build(),
        standard: StandardFlow.build()
      })
  """
  @spec branch(t(), atom(), (map() -> term()), map(), keyword()) :: t()
  def branch(%__MODULE__{} = effect, name, selector, routes, opts \\ [])
      when is_atom(name) and is_function(selector, 1) and is_map(routes) do
    step_opts = Keyword.drop(opts, [:default])
    default_route = Keyword.get(opts, :default) || Map.get(routes, :default)

    meta = %{
      selector: selector,
      routes: routes,
      default: default_route
    }

    step(effect, name, nil, Keyword.merge(step_opts, type: :branch, meta: meta))
  end

  @doc """
  Embeds a nested effect into the parent effect.

  The nested effect's steps are executed as a single unit. Results from the
  nested effect are merged into the parent context.

  ## Options

  - `:after` - Step(s) that must complete before this embedded effect
  - `:context` - Function to transform parent context for nested effect

  ## Examples

      effect
      |> Effect.embed(:payment, PaymentFlow.build(), after: :validate)

      # With context transformation
      effect
      |> Effect.embed(:notify, NotificationFlow.build(),
        context: fn ctx -> %{user: ctx.user, message: ctx.confirmation} end
      )
  """
  @spec embed(t(), atom(), t(), keyword()) :: t()
  def embed(%__MODULE__{} = effect, name, nested_effect, opts \\ [])
      when is_atom(name) and is_struct(nested_effect, __MODULE__) do
    step_opts = Keyword.drop(opts, [:context])
    context_fn = Keyword.get(opts, :context, fn ctx -> ctx end)

    meta = %{
      nested_effect: nested_effect,
      context_fn: context_fn
    }

    step(effect, name, nil, Keyword.merge(step_opts, type: :embed, meta: meta))
  end

  @doc """
  Iterates over a collection, executing a nested effect for each item.

  The extractor function pulls the collection from context. For each item,
  the item_effect is executed with the item added to context.

  ## Options

  - `:after` - Step(s) that must complete before iteration
  - `:concurrency` - Number of concurrent iterations (default: 1 = sequential)
  - `:as` - Key to use for current item in context (default: :item)
  - `:collect` - Key to collect results into (default: step name)

  ## Examples

      effect
      |> Effect.each(:process_items, & &1.items, ItemProcessor.build(),
        as: :current_item,
        collect: :processed_items
      )

      # Concurrent processing
      effect
      |> Effect.each(:send_notifications, & &1.recipients, Notifier.build(),
        concurrency: 5
      )
  """
  @spec each(t(), atom(), (map() -> list()), t(), keyword()) :: t()
  def each(%__MODULE__{} = effect, name, extractor, item_effect, opts \\ [])
      when is_atom(name) and is_function(extractor, 1) and is_struct(item_effect, __MODULE__) do
    step_opts = Keyword.drop(opts, [:concurrency, :as, :collect])

    meta = %{
      extractor: extractor,
      item_effect: item_effect,
      concurrency: Keyword.get(opts, :concurrency, 1),
      as: Keyword.get(opts, :as, :item),
      collect: Keyword.get(opts, :collect, name)
    }

    step(effect, name, nil, Keyword.merge(step_opts, type: :each, meta: meta))
  end

  @doc """
  Races multiple effects, returning the first successful result.

  All effects start concurrently. The first to succeed wins and others are
  cancelled. If all fail, returns an error with all failures.

  ## Options

  - `:after` - Step(s) that must complete before the race
  - `:timeout` - Overall race timeout in milliseconds

  ## Examples

      effect
      |> Effect.race(:fetch_data, [
        CacheEffect.build(),
        DatabaseEffect.build(),
        ApiEffect.build()
      ])
  """
  @spec race(t(), atom(), [t()], keyword()) :: t()
  def race(%__MODULE__{} = effect, name, contestants, opts \\ [])
      when is_atom(name) and is_list(contestants) do
    step_opts = Keyword.drop(opts, [:timeout])

    meta = %{
      contestants: contestants,
      timeout: Keyword.get(opts, :timeout, 30_000)
    }

    step(effect, name, nil, Keyword.merge(step_opts, type: :race, meta: meta))
  end

  @doc """
  Manages a resource with acquire/use/release lifecycle.

  The acquire function runs first, then the body effect, and release
  always runs (even on error), similar to try/after.

  ## Options

  - `:after` - Step(s) that must complete before resource acquisition
  - `:as` - Key to store the acquired resource in context (default: step name)

  ## Examples

      # Database connection
      effect
      |> Effect.using(:db_conn, [
        acquire: fn ctx -> {:ok, %{conn: DB.checkout()}} end,
        release: fn ctx, _result -> DB.checkin(ctx.db_conn) end,
        body: DbOperations.build()
      ])

      # File handle
      effect
      |> Effect.using(:file, [
        acquire: fn ctx -> {:ok, %{handle: File.open!(ctx.path)}} end,
        release: fn ctx, _result -> File.close(ctx.handle) end,
        body: FileProcessor.build()
      ])
  """
  @spec using(t(), atom(), keyword()) :: t()
  def using(%__MODULE__{} = effect, name, resource_opts) when is_atom(name) do
    acquire = Keyword.fetch!(resource_opts, :acquire)
    release = Keyword.fetch!(resource_opts, :release)
    body = Keyword.fetch!(resource_opts, :body)

    step_opts = Keyword.drop(resource_opts, [:acquire, :release, :body, :as])
    as_key = Keyword.get(resource_opts, :as, name)

    meta = %{
      acquire: acquire,
      release: release,
      body: body,
      as: as_key
    }

    step(effect, name, nil, Keyword.merge(step_opts, type: :using, meta: meta))
  end

  @doc """
  Adds a checkpoint for pausing and resuming long-running workflows.

  When execution reaches a checkpoint, the state is persisted and execution
  returns `{:checkpoint, execution_id, checkpoint_name}`. The workflow can
  later be resumed with `Effect.resume/2`.

  ## Options

  - `:after` - Step(s) that must complete before this checkpoint
  - `:store` - Function `(execution_id, state) -> :ok | {:error, term}`
  - `:load` - Function `(execution_id) -> {:ok, state} | {:error, term}`

  ## Examples

      effect
      |> Effect.checkpoint(:await_approval,
        store: &MyStore.save/2,
        load: &MyStore.load/1
      )

      # For testing, use the in-memory store:
      effect
      |> Effect.checkpoint(:pause,
        store: &Effect.Checkpoint.InMemory.store/2,
        load: &Effect.Checkpoint.InMemory.load/1
      )
  """
  @spec checkpoint(t(), atom(), keyword()) :: t()
  def checkpoint(%__MODULE__{} = effect, name, opts \\ []) when is_atom(name) do
    store = Keyword.fetch!(opts, :store)
    load = Keyword.fetch!(opts, :load)
    step_opts = Keyword.drop(opts, [:store, :load])

    meta = %{
      store: store,
      load: load
    }

    # Track checkpoint config in effect
    checkpoints = Map.put(effect.checkpoints, name, %{store: store, load: load})

    effect = %{effect | checkpoints: checkpoints}
    step(effect, name, nil, Keyword.merge(step_opts, type: :checkpoint, meta: meta))
  end

  @doc """
  Adds middleware that wraps every step execution.

  Middleware is executed in onion order - first added is outermost.

  ## Examples

      effect
      |> Effect.middleware(fn step, ctx, next ->
        start = System.monotonic_time(:millisecond)
        result = next.()
        duration = System.monotonic_time(:millisecond) - start
        Logger.debug("[Effect] \#{step} completed in \#{duration}ms")
        result
      end)
  """
  @spec middleware(t(), middleware_fun()) :: t()
  def middleware(%__MODULE__{middleware: mw} = effect, fun) do
    %{effect | middleware: mw ++ [fun]}
  end

  @doc """
  Adds a hook that runs on effect start.
  """
  @spec on_start(t(), hook_fun()) :: t()
  def on_start(%__MODULE__{hooks: hooks} = effect, fun) do
    %{effect | hooks: %{hooks | on_start: hooks.on_start ++ [fun]}}
  end

  @doc """
  Adds a hook that runs on effect completion.
  """
  @spec on_complete(t(), hook_fun()) :: t()
  def on_complete(%__MODULE__{hooks: hooks} = effect, fun) do
    %{effect | hooks: %{hooks | on_complete: hooks.on_complete ++ [fun]}}
  end

  @doc """
  Adds a hook that runs on step error.
  """
  @spec on_error(t(), (atom(), term(), map() -> any())) :: t()
  def on_error(%__MODULE__{hooks: hooks} = effect, fun) do
    %{effect | hooks: %{hooks | on_error: hooks.on_error ++ [fun]}}
  end

  @doc """
  Adds a hook that runs on rollback.
  """
  @spec on_rollback(t(), hook_fun()) :: t()
  def on_rollback(%__MODULE__{hooks: hooks} = effect, fun) do
    %{effect | hooks: %{hooks | on_rollback: hooks.on_rollback ++ [fun]}}
  end

  @doc """
  Adds cleanup function that always runs (like try/after).
  """
  @spec ensure(t(), atom(), cleanup_fun()) :: t()
  def ensure(%__MODULE__{ensure_fns: fns} = effect, name, fun) do
    %{effect | ensure_fns: fns ++ [{name, fun}]}
  end

  @doc """
  Returns the list of step names in definition order.
  """
  @spec step_names(t()) :: [atom()]
  def step_names(%__MODULE__{steps: steps}) do
    Enum.map(steps, & &1.name)
  end

  @doc """
  Returns information about a specific step.
  """
  @spec step_info(t(), atom()) :: {:ok, Step.t()} | {:error, :not_found}
  def step_info(%__MODULE__{steps: steps}, name) do
    case Enum.find(steps, fn s -> s.name == name end) do
      nil -> {:error, :not_found}
      step -> {:ok, step}
    end
  end

  @doc """
  Builds the DAG from steps (called internally before execution).

  Steps without explicit `after:` dependencies are executed in definition order
  by adding implicit sequential dependencies.
  """
  @spec build_dag(t()) :: {:ok, Dag.t()} | {:error, term()}
  def build_dag(%__MODULE__{steps: steps, name: name}) do
    # Build the DAG with implicit sequential dependencies for steps without explicit deps
    {dag, _prev} =
      Enum.reduce(steps, {Dag.new(name: name), nil}, fn step, {dag, prev_name} ->
        dag = Dag.add_node(dag, step.name, %{step: step})

        # Add explicit dependencies
        dag =
          Enum.reduce(Step.dependencies(step), dag, fn dep, dag ->
            Dag.add_edge(dag, dep, step.name)
          end)

        # Add implicit sequential dependency if no explicit deps and not first step
        dag =
          if prev_name != nil && Step.dependencies(step) == [] do
            Dag.add_edge(dag, prev_name, step.name)
          else
            dag
          end

        {dag, step.name}
      end)

    case Dag.Algorithms.validate(dag) do
      :ok -> {:ok, dag}
      {:error, reason} -> {:error, reason}
    end
  end
end

defimpl Inspect, for: Effect.Builder do
  import Inspect.Algebra

  def inspect(%Effect.Builder{} = effect, opts) do
    step_count = length(effect.steps)

    fields =
      [name: effect.name, steps: step_count] ++
        if(effect.label, do: [label: effect.label], else: []) ++
        if(effect.tags != [], do: [tags: effect.tags], else: [])

    concat(["#Effect<", to_doc(fields, opts), ">"])
  end
end
