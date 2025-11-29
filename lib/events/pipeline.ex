defmodule Events.Pipeline do
  @moduledoc """
  Composable multi-step pipelines with context accumulation.

  A Pipeline chains result-returning operations while accumulating context,
  supporting branching, checkpoints, rollback, and telemetry integration.

  ## Design Philosophy

  - **Context accumulation**: Each step can read from and write to shared context
  - **Early termination**: Pipeline stops on first error
  - **Composability**: Pipelines can be nested and combined
  - **Observability**: Built-in telemetry and logging hooks
  - **Recovery**: Support for rollback and compensation logic

  ## Basic Usage

      Pipeline.new(%{user_id: 123})
      |> Pipeline.step(:fetch_user, fn ctx ->
        case Repo.get(User, ctx.user_id) do
          nil -> {:error, :not_found}
          user -> {:ok, %{user: user}}
        end
      end)
      |> Pipeline.step(:validate, fn ctx ->
        case validate_user(ctx.user) do
          :ok -> {:ok, %{}}
          {:error, _} = err -> err
        end
      end)
      |> Pipeline.step(:send_email, fn ctx ->
        Mailer.send_welcome(ctx.user)
      end)
      |> Pipeline.run()
      #=> {:ok, %{user_id: 123, user: %User{}, ...}}
      #   | {:error, {:step_failed, :fetch_user, :not_found}}

  ## Branching

      Pipeline.new(params)
      |> Pipeline.step(:determine_type, fn ctx -> {:ok, %{type: :premium}} end)
      |> Pipeline.branch(:type, %{
        premium: fn pipeline ->
          pipeline
          |> Pipeline.step(:apply_discount, &apply_premium_discount/1)
        end,
        standard: fn pipeline ->
          pipeline
          |> Pipeline.step(:apply_standard, &apply_standard_rate/1)
        end
      })
      |> Pipeline.run()

  ## Error Recovery

      Pipeline.new(data)
      |> Pipeline.step(:risky_operation, &do_risky/1, rollback: &undo_risky/1)
      |> Pipeline.step(:another_step, &do_another/1, rollback: &undo_another/1)
      |> Pipeline.run_with_rollback()

  ## Parallel Steps

      Pipeline.new(ctx)
      |> Pipeline.parallel([
        {:fetch_profile, &fetch_profile/1},
        {:fetch_preferences, &fetch_preferences/1},
        {:fetch_notifications, &fetch_notifications/1}
      ])
      |> Pipeline.run()
  """

  alias Events.{Result, AsyncResult}

  # ============================================
  # Types
  # ============================================

  @type context :: map()
  @type step_name :: atom()
  @type step_result :: {:ok, map()} | {:error, term()}
  @type step_fun :: (context() -> step_result())
  @type rollback_fun :: (context() -> :ok | {:error, term()})
  @type branch_key :: term()
  @type branch_map :: %{branch_key() => (t() -> t())}

  @type step :: %{
          name: step_name(),
          fun: step_fun(),
          rollback: rollback_fun() | nil,
          opts: keyword()
        }

  @type t :: %__MODULE__{
          context: context(),
          steps: [step()],
          completed: [step_name()],
          current_step: step_name() | nil,
          halted: boolean(),
          error: term() | nil,
          telemetry_prefix: [atom()] | nil,
          metadata: map()
        }

  defstruct context: %{},
            steps: [],
            completed: [],
            current_step: nil,
            halted: false,
            error: nil,
            telemetry_prefix: nil,
            metadata: %{}

  # ============================================
  # Creation
  # ============================================

  @doc """
  Creates a new pipeline with initial context.

  ## Examples

      Pipeline.new(%{user_id: 123})
      Pipeline.new(%{request: request}, telemetry_prefix: [:my_app, :signup])
  """
  @spec new(context(), keyword()) :: t()
  def new(initial_context \\ %{}, opts \\ []) when is_map(initial_context) do
    %__MODULE__{
      context: initial_context,
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a pipeline from an existing result.

  If error, creates a halted pipeline.

  ## Examples

      {:ok, user}
      |> Pipeline.from_result(:user)
      |> Pipeline.step(:send_email, ...)
  """
  @spec from_result(Result.t(), step_name()) :: t()
  def from_result({:ok, value}, key) when is_atom(key) do
    new(%{key => value})
  end

  def from_result({:error, reason}, _key) do
    %__MODULE__{halted: true, error: reason}
  end

  # ============================================
  # Steps
  # ============================================

  @doc """
  Adds a step to the pipeline.

  The step function receives the current context and should return:
  - `{:ok, additions}` - Merges additions into context
  - `{:error, reason}` - Halts pipeline with error

  ## Options

  - `:rollback` - Function to call on error (receives context)
  - `:timeout` - Step timeout in ms
  - `:condition` - Only run if condition returns true

  ## Examples

      Pipeline.step(pipeline, :fetch_user, fn ctx ->
        case Repo.get(User, ctx.user_id) do
          nil -> {:error, :not_found}
          user -> {:ok, %{user: user}}
        end
      end)

      Pipeline.step(pipeline, :send_email, &send_welcome/1,
        rollback: &unsend_email/1,
        condition: fn ctx -> ctx.user.confirmed end
      )
  """
  @spec step(t(), step_name(), step_fun(), keyword()) :: t()
  def step(pipeline, name, fun, opts \\ [])

  def step(%__MODULE__{halted: true} = pipeline, _name, _fun, _opts), do: pipeline

  def step(%__MODULE__{} = pipeline, name, fun, opts)
      when is_atom(name) and is_function(fun, 1) do
    step = %{
      name: name,
      fun: fun,
      rollback: Keyword.get(opts, :rollback),
      opts: opts
    }

    %{pipeline | steps: pipeline.steps ++ [step]}
  end

  @doc """
  Adds a step that transforms a specific key in context.

  ## Examples

      Pipeline.transform(pipeline, :user, :formatted_name, fn user ->
        {:ok, "\#{user.first_name} \#{user.last_name}"}
      end)
  """
  @spec transform(t(), atom(), atom(), (term() -> Result.t(term()))) :: t()
  def transform(%__MODULE__{} = pipeline, source_key, target_key, fun)
      when is_atom(source_key) and is_atom(target_key) and is_function(fun, 1) do
    step(pipeline, target_key, fn ctx ->
      case Map.fetch(ctx, source_key) do
        {:ok, value} ->
          case fun.(value) do
            {:ok, result} -> {:ok, %{target_key => result}}
            {:error, _} = error -> error
          end

        :error ->
          {:error, {:missing_key, source_key}}
      end
    end)
  end

  @doc """
  Adds a step that assigns a value to context.

  ## Examples

      Pipeline.assign(pipeline, :timestamp, DateTime.utc_now())
      Pipeline.assign(pipeline, :config, fn ctx -> ctx.env.config end)
  """
  @spec assign(t(), atom(), term() | (context() -> term())) :: t()
  def assign(%__MODULE__{} = pipeline, key, value) when is_atom(key) and not is_function(value) do
    step(pipeline, key, fn _ctx -> {:ok, %{key => value}} end)
  end

  def assign(%__MODULE__{} = pipeline, key, fun) when is_atom(key) and is_function(fun, 1) do
    step(pipeline, key, fn ctx -> {:ok, %{key => fun.(ctx)}} end)
  end

  @doc """
  Adds a step that runs only if condition is met.

  ## Examples

      Pipeline.step_if(pipeline, :send_notification,
        fn ctx -> ctx.user.notifications_enabled end,
        &send_notification/1
      )
  """
  @spec step_if(t(), step_name(), (context() -> boolean()), step_fun(), keyword()) :: t()
  def step_if(%__MODULE__{} = pipeline, name, condition, fun, opts \\ [])
      when is_function(condition, 1) and is_function(fun, 1) do
    wrapped_fun = fn ctx ->
      case condition.(ctx) do
        true -> fun.(ctx)
        false -> {:ok, %{}}
      end
    end

    step(pipeline, name, wrapped_fun, opts)
  end

  @doc """
  Adds a step that validates context against a function.

  ## Examples

      Pipeline.validate(pipeline, :user_valid, fn ctx ->
        case User.valid?(ctx.user) do
          true -> :ok
          false -> {:error, :invalid_user}
        end
      end)
  """
  @spec validate(t(), step_name(), (context() -> :ok | {:error, term()})) :: t()
  def validate(%__MODULE__{} = pipeline, name, validator) when is_function(validator, 1) do
    step(pipeline, name, fn ctx ->
      case validator.(ctx) do
        :ok -> {:ok, %{}}
        {:error, _} = error -> error
      end
    end)
  end

  # ============================================
  # Branching
  # ============================================

  @doc """
  Branches pipeline based on a context value.

  ## Examples

      Pipeline.branch(pipeline, :account_type, %{
        :premium => fn p -> Pipeline.step(p, :premium_flow, &premium/1) end,
        :standard => fn p -> Pipeline.step(p, :standard_flow, &standard/1) end
      })

      # With default branch
      Pipeline.branch(pipeline, :account_type, %{
        :premium => &premium_flow/1
      }, default: &standard_flow/1)
  """
  @spec branch(t(), atom(), branch_map(), keyword()) :: t()
  def branch(pipeline, key, branches, opts \\ [])

  def branch(%__MODULE__{halted: true} = pipeline, _key, _branches, _opts), do: pipeline

  def branch(%__MODULE__{} = pipeline, key, branches, opts)
      when is_atom(key) and is_map(branches) do
    default = Keyword.get(opts, :default)

    step(pipeline, :"branch_#{key}", fn ctx ->
      branch_value = Map.get(ctx, key)
      branch_fun = Map.get(branches, branch_value, default)

      case branch_fun do
        nil ->
          {:error, {:no_branch_for, key, branch_value}}

        fun when is_function(fun, 1) ->
          # Execute the branch pipeline
          branch_pipeline = fun.(new(ctx))

          case run(branch_pipeline) do
            {:ok, result_ctx} -> {:ok, result_ctx}
            {:error, _} = error -> error
          end
      end
    end)
  end

  @doc """
  Conditionally modifies the pipeline.

  ## Examples

      Pipeline.when_true(pipeline, ctx.admin?, fn p ->
        Pipeline.step(p, :admin_setup, &setup_admin/1)
      end)
  """
  @spec when_true(t(), boolean() | (context() -> boolean()), (t() -> t())) :: t()
  def when_true(%__MODULE__{halted: true} = pipeline, _condition, _fun), do: pipeline

  def when_true(%__MODULE__{} = pipeline, condition, fun)
      when is_boolean(condition) and is_function(fun, 1) do
    case condition do
      true -> fun.(pipeline)
      false -> pipeline
    end
  end

  def when_true(%__MODULE__{} = pipeline, condition, fun)
      when is_function(condition, 1) and is_function(fun, 1) do
    case condition.(pipeline.context) do
      true -> fun.(pipeline)
      false -> pipeline
    end
  end

  # ============================================
  # Parallel Steps
  # ============================================

  @doc """
  Executes multiple steps in parallel.

  All steps receive the same context snapshot.
  Results are merged into context.

  ## Examples

      Pipeline.parallel(pipeline, [
        {:fetch_profile, &fetch_profile/1},
        {:fetch_settings, &fetch_settings/1},
        {:fetch_notifications, &fetch_notifications/1}
      ])

      # With options
      Pipeline.parallel(pipeline, steps, max_concurrency: 5, timeout: 10_000)
  """
  @spec parallel(t(), [{step_name(), step_fun()}], keyword()) :: t()
  def parallel(pipeline, parallel_steps, opts \\ [])

  def parallel(%__MODULE__{halted: true} = pipeline, _steps, _opts), do: pipeline

  def parallel(%__MODULE__{} = pipeline, parallel_steps, opts) when is_list(parallel_steps) do
    step(pipeline, :parallel, fn ctx ->
      tasks =
        Enum.map(parallel_steps, fn {_name, fun} ->
          fn -> fun.(ctx) end
        end)

      case AsyncResult.parallel(tasks, opts) do
        {:ok, results} ->
          merged =
            parallel_steps
            |> Enum.zip(results)
            |> Enum.reduce(%{}, fn {{name, _fun}, result}, acc ->
              case result do
                %{} = map -> Map.merge(acc, map)
                _ -> Map.put(acc, name, result)
              end
            end)

          {:ok, merged}

        {:error, reason} ->
          {:error, {:parallel_failed, reason}}
      end
    end)
  end

  # ============================================
  # Side Effects
  # ============================================

  @doc """
  Adds a step for side effects that doesn't modify context.

  ## Examples

      Pipeline.tap(pipeline, :log, fn ctx ->
        Logger.info("Processing user \#{ctx.user.id}")
        :ok
      end)
  """
  @spec tap(t(), step_name(), (context() -> :ok | {:error, term()})) :: t()
  def tap(%__MODULE__{} = pipeline, name, fun) when is_function(fun, 1) do
    step(pipeline, name, fn ctx ->
      case fun.(ctx) do
        :ok -> {:ok, %{}}
        {:error, _} = error -> error
      end
    end)
  end

  @doc """
  Adds a step that always succeeds (for logging, metrics, etc.)

  ## Examples

      Pipeline.tap_always(pipeline, :metrics, fn ctx ->
        Metrics.increment("users.created", tags: [type: ctx.user.type])
      end)
  """
  @spec tap_always(t(), step_name(), (context() -> any())) :: t()
  def tap_always(%__MODULE__{} = pipeline, name, fun) when is_function(fun, 1) do
    step(pipeline, name, fn ctx ->
      fun.(ctx)
      {:ok, %{}}
    end)
  end

  # ============================================
  # Execution
  # ============================================

  @doc """
  Runs the pipeline, returning final context or error.

  ## Examples

      case Pipeline.run(pipeline) do
        {:ok, ctx} -> {:ok, ctx.result}
        {:error, {:step_failed, step, reason}} -> handle_error(step, reason)
      end
  """
  @spec run(t()) :: {:ok, context()} | {:error, {:step_failed, step_name(), term()}}
  def run(%__MODULE__{halted: true, error: error, current_step: step}) do
    {:error, {:step_failed, step, error}}
  end

  def run(%__MODULE__{steps: []} = pipeline) do
    {:ok, pipeline.context}
  end

  def run(%__MODULE__{} = pipeline) do
    emit_telemetry_start(pipeline)

    result =
      Enum.reduce_while(pipeline.steps, pipeline, fn step, acc_pipeline ->
        execute_step(step, acc_pipeline)
      end)

    emit_telemetry_stop(pipeline, result)

    case result do
      %__MODULE__{halted: true, error: error, current_step: step} ->
        {:error, {:step_failed, step, error}}

      %__MODULE__{} = final_pipeline ->
        {:ok, final_pipeline.context}
    end
  end

  @doc """
  Runs pipeline with automatic rollback on failure.

  Executes rollback functions in reverse order for completed steps.

  ## Examples

      Pipeline.run_with_rollback(pipeline)
      #=> {:ok, ctx} | {:error, {:step_failed, step, reason, rollback_errors}}
  """
  @spec run_with_rollback(t()) :: {:ok, context()} | {:error, term()}
  def run_with_rollback(%__MODULE__{} = pipeline) do
    case run(pipeline) do
      {:ok, _} = success ->
        success

      {:error, {:step_failed, failed_step, reason}} ->
        rollback_errors = execute_rollbacks(pipeline, failed_step)

        case rollback_errors do
          [] -> {:error, {:step_failed, failed_step, reason}}
          errors -> {:error, {:step_failed, failed_step, reason, rollback_errors: errors}}
        end
    end
  end

  @doc """
  Runs pipeline and unwraps result, raising on error.

  ## Examples

      ctx = Pipeline.run!(pipeline)
  """
  @spec run!(t()) :: context() | no_return()
  def run!(%__MODULE__{} = pipeline) do
    case run(pipeline) do
      {:ok, ctx} -> ctx
      {:error, error} -> raise "Pipeline failed: #{inspect(error)}"
    end
  end

  # ============================================
  # Composition
  # ============================================

  @doc """
  Composes two pipelines.

  ## Examples

      full_pipeline =
        Pipeline.compose(
          user_pipeline,
          notification_pipeline
        )
  """
  @spec compose(t(), t()) :: t()
  def compose(%__MODULE__{} = pipeline1, %__MODULE__{} = pipeline2) do
    %{pipeline1 | steps: pipeline1.steps ++ pipeline2.steps}
  end

  @doc """
  Creates a reusable pipeline segment.

  ## Examples

      validation_segment = Pipeline.segment([
        {:validate_email, &validate_email/1},
        {:validate_password, &validate_password/1}
      ])

      pipeline
      |> Pipeline.include(validation_segment)
  """
  @spec segment([{step_name(), step_fun()}]) :: t()
  def segment(steps) when is_list(steps) do
    Enum.reduce(steps, new(), fn {name, fun}, pipeline ->
      step(pipeline, name, fun)
    end)
  end

  @doc """
  Includes a pipeline segment.

  ## Examples

      Pipeline.include(pipeline, validation_segment)
  """
  @spec include(t(), t()) :: t()
  def include(%__MODULE__{} = pipeline, %__MODULE__{} = segment) do
    compose(pipeline, segment)
  end

  # ============================================
  # Inspection
  # ============================================

  @doc """
  Returns the current context.

  ## Examples

      Pipeline.context(pipeline)
      #=> %{user_id: 123, user: %User{}}
  """
  @spec context(t()) :: context()
  def context(%__MODULE__{context: ctx}), do: ctx

  @doc """
  Returns completed step names.

  ## Examples

      Pipeline.completed_steps(pipeline)
      #=> [:fetch_user, :validate]
  """
  @spec completed_steps(t()) :: [step_name()]
  def completed_steps(%__MODULE__{completed: completed}), do: Enum.reverse(completed)

  @doc """
  Returns pending step names.

  ## Examples

      Pipeline.pending_steps(pipeline)
      #=> [:send_email, :log]
  """
  @spec pending_steps(t()) :: [step_name()]
  def pending_steps(%__MODULE__{steps: steps, completed: completed}) do
    completed_set = MapSet.new(completed)

    steps
    |> Enum.map(& &1.name)
    |> Enum.reject(&MapSet.member?(completed_set, &1))
  end

  @doc """
  Checks if pipeline has halted.

  ## Examples

      Pipeline.halted?(pipeline)
      #=> false
  """
  @spec halted?(t()) :: boolean()
  def halted?(%__MODULE__{halted: halted}), do: halted

  @doc """
  Gets the error if pipeline halted.

  ## Examples

      Pipeline.error(pipeline)
      #=> nil | {:step_failed, :fetch_user, :not_found}
  """
  @spec error(t()) :: term() | nil
  def error(%__MODULE__{error: error}), do: error

  # ============================================
  # Private Helpers
  # ============================================

  defp execute_step(step, pipeline) do
    pipeline = %{pipeline | current_step: step.name}
    condition = Keyword.get(step.opts, :condition, fn _ -> true end)

    case condition.(pipeline.context) do
      false ->
        {:cont, pipeline}

      true ->
        emit_step_start(pipeline, step)

        case step.fun.(pipeline.context) do
          {:ok, additions} when is_map(additions) ->
            new_context = Map.merge(pipeline.context, additions)

            updated =
              %{pipeline | context: new_context, completed: [step.name | pipeline.completed]}

            emit_step_stop(pipeline, step, :ok)
            {:cont, updated}

          {:error, reason} ->
            emit_step_stop(pipeline, step, {:error, reason})
            {:halt, %{pipeline | halted: true, error: reason}}
        end
    end
  end

  defp execute_rollbacks(pipeline, failed_step) do
    # Get steps that completed before failure
    failed_index = Enum.find_index(pipeline.steps, fn s -> s.name == failed_step end) || 0
    steps_to_rollback = Enum.take(pipeline.steps, failed_index)

    # Execute rollbacks in reverse order
    steps_to_rollback
    |> Enum.reverse()
    |> Enum.filter(fn step -> step.rollback != nil end)
    |> Enum.reduce([], fn step, errors ->
      case step.rollback.(pipeline.context) do
        :ok -> errors
        {:error, reason} -> [{step.name, reason} | errors]
      end
    end)
    |> Enum.reverse()
  end

  defp emit_telemetry_start(%{telemetry_prefix: nil}), do: :ok

  defp emit_telemetry_start(%{telemetry_prefix: prefix} = pipeline) do
    :telemetry.execute(
      prefix ++ [:pipeline, :start],
      %{system_time: System.system_time()},
      %{pipeline: pipeline.metadata, step_count: length(pipeline.steps)}
    )
  end

  defp emit_telemetry_stop(%{telemetry_prefix: nil}, _result), do: :ok

  defp emit_telemetry_stop(%{telemetry_prefix: prefix} = pipeline, result) do
    status =
      case result do
        %{halted: true} -> :error
        _ -> :ok
      end

    :telemetry.execute(
      prefix ++ [:pipeline, :stop],
      %{duration: System.monotonic_time(:microsecond)},
      %{pipeline: pipeline.metadata, status: status}
    )
  end

  defp emit_step_start(%{telemetry_prefix: nil}, _step), do: :ok

  defp emit_step_start(%{telemetry_prefix: prefix} = pipeline, step) do
    :telemetry.execute(
      prefix ++ [:step, :start],
      %{system_time: System.system_time()},
      %{pipeline: pipeline.metadata, step: step.name}
    )
  end

  defp emit_step_stop(%{telemetry_prefix: nil}, _step, _status), do: :ok

  defp emit_step_stop(%{telemetry_prefix: prefix} = pipeline, step, status) do
    :telemetry.execute(
      prefix ++ [:step, :stop],
      %{duration: System.monotonic_time(:microsecond)},
      %{pipeline: pipeline.metadata, step: step.name, status: status}
    )
  end
end
