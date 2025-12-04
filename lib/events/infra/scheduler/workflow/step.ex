defmodule Events.Infra.Scheduler.Workflow.Step do
  @moduledoc """
  Step definition for workflow execution.

  A step represents a single unit of work within a workflow, with its own
  timeout, retry configuration, dependencies, and optional rollback logic.

  ## Step Types

  - **Function**: Anonymous function `fn ctx -> result end`
  - **Module**: Worker module implementing `perform/1`
  - **MFA**: `{Module, :function, []}` tuple
  - **Workflow**: Nested workflow `{:workflow, :workflow_name}`

  ## Return Values

  Steps must return one of:
  - `{:ok, map}` - Success, merge map into context
  - `:ok` - Success, no context changes
  - `{:error, reason}` - Failure (triggers retry or error handling)
  - `{:skip, reason}` - Skip step, continue workflow
  - `{:await, opts}` - Pause for human approval
  - `{:expand, steps}` - Graft expansion (from graft steps only)
  - `{:snooze, duration}` - Pause and retry after duration
  """

  alias Events.Infra.Scheduler.Config

  @type state ::
          :pending | :ready | :running | :completed | :failed | :skipped | :cancelled | :awaiting
  @type on_error :: :fail | :skip | :continue
  @type backoff :: :fixed | :exponential | :linear | (pos_integer(), pos_integer() -> pos_integer())
  @type job_spec ::
          function()
          | module()
          | {module(), atom()}
          | {module(), atom(), list()}
          | {:workflow, atom()}

  @type t :: %__MODULE__{
          name: atom(),
          job: job_spec(),
          depends_on: [atom()],
          depends_on_any: [atom()],
          depends_on_group: atom() | nil,
          depends_on_graft: atom() | nil,
          group: atom() | nil,
          condition: (map() -> boolean()) | nil,
          timeout: pos_integer() | :infinity | (map() -> pos_integer()),
          max_retries: non_neg_integer(),
          retry_delay: pos_integer(),
          retry_backoff: backoff(),
          retry_max_delay: pos_integer() | nil,
          retry_jitter: boolean(),
          retry_on: [atom() | tuple()] | nil,
          no_retry_on: [atom() | tuple()] | nil,
          state: state(),
          result: term() | nil,
          error: term() | nil,
          attempt: non_neg_integer(),
          context_key: atom(),
          rollback: atom() | function() | nil,
          on_error: on_error(),
          await_approval: boolean(),
          cancellable: boolean(),
          circuit_breaker: atom() | nil,
          circuit_breaker_opts: keyword(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: non_neg_integer() | nil,
          metadata: map()
        }

  defstruct [
    :name,
    :job,
    :depends_on_group,
    :depends_on_graft,
    :group,
    :condition,
    :result,
    :error,
    :rollback,
    :circuit_breaker,
    :started_at,
    :completed_at,
    :duration_ms,
    :retry_max_delay,
    :retry_on,
    :no_retry_on,
    depends_on: [],
    depends_on_any: [],
    timeout: :timer.minutes(5),
    max_retries: 3,
    retry_delay: :timer.seconds(1),
    retry_backoff: :exponential,
    retry_jitter: false,
    state: :pending,
    attempt: 0,
    context_key: nil,
    on_error: :fail,
    await_approval: false,
    cancellable: true,
    circuit_breaker_opts: [],
    metadata: %{}
  ]

  @doc """
  Creates a new step.

  ## Options

  - `:after` - Step(s) this depends on (all must complete)
  - `:after_any` - Step(s) where any completing triggers this step
  - `:after_group` - Wait for all steps in a parallel group
  - `:after_graft` - Wait for graft expansion to complete
  - `:group` - Add to a parallel group
  - `:when` - Condition function `(ctx -> boolean)`
  - `:rollback` - Rollback function for saga pattern
  - `:timeout` - Step timeout (default: 5 minutes)
  - `:max_retries` - Max retries (default: 3)
  - `:retry_delay` - Retry delay (default: 1 second)
  - `:retry_backoff` - Backoff strategy (default: :exponential)
  - `:retry_max_delay` - Maximum delay for exponential backoff
  - `:retry_jitter` - Add jitter to retry delays
  - `:retry_on` - Error types to retry on
  - `:no_retry_on` - Error types to never retry
  - `:on_error` - `:fail`, `:skip`, or `:continue` (default: :fail)
  - `:await_approval` - Pause for human approval
  - `:cancellable` - Can be cancelled (default: true)
  - `:context_key` - Key to store result (defaults to step name)
  - `:circuit_breaker` - Circuit breaker name
  - `:circuit_breaker_opts` - Circuit breaker options
  """
  @spec new(atom(), job_spec(), keyword()) :: t()
  def new(name, job, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      job: job,
      depends_on: normalize_deps(Keyword.get(opts, :after, [])),
      depends_on_any: normalize_deps(Keyword.get(opts, :after_any, [])),
      depends_on_group: Keyword.get(opts, :after_group),
      depends_on_graft: Keyword.get(opts, :after_graft),
      group: Keyword.get(opts, :group),
      condition: Keyword.get(opts, :when),
      timeout: normalize_timeout(Keyword.get(opts, :timeout, :timer.minutes(5))),
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_delay: normalize_timeout(Keyword.get(opts, :retry_delay, :timer.seconds(1))),
      retry_backoff: Keyword.get(opts, :retry_backoff, :exponential),
      retry_max_delay: normalize_timeout(Keyword.get(opts, :retry_max_delay)),
      retry_jitter: Keyword.get(opts, :retry_jitter, false),
      retry_on: Keyword.get(opts, :retry_on),
      no_retry_on: Keyword.get(opts, :no_retry_on),
      on_error: Keyword.get(opts, :on_error, :fail),
      await_approval: Keyword.get(opts, :await_approval, false),
      cancellable: Keyword.get(opts, :cancellable, true),
      context_key: Keyword.get(opts, :context_key, name),
      rollback: Keyword.get(opts, :rollback),
      circuit_breaker: Keyword.get(opts, :circuit_breaker),
      circuit_breaker_opts: Keyword.get(opts, :circuit_breaker_opts, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Checks if a step is ready to execute based on dependencies and completed steps.
  """
  @spec ready?(t(), MapSet.t(), map()) :: boolean()
  def ready?(%__MODULE__{} = step, completed_steps, groups_completed) do
    step.state == :pending and
      all_deps_satisfied?(step, completed_steps) and
      any_deps_satisfied?(step, completed_steps) and
      group_deps_satisfied?(step, groups_completed) and
      graft_deps_satisfied?(step, completed_steps)
  end

  @doc """
  Checks if a step's condition is satisfied.
  """
  @spec condition_satisfied?(t(), map()) :: boolean()
  def condition_satisfied?(%__MODULE__{condition: nil}, _ctx), do: true

  def condition_satisfied?(%__MODULE__{condition: condition}, ctx) when is_function(condition, 1) do
    try do
      condition.(ctx)
    rescue
      _ -> false
    end
  end

  @doc """
  Transitions step to a new state.
  """
  @spec transition(t(), state()) :: t()
  def transition(%__MODULE__{} = step, new_state) do
    %{step | state: new_state}
  end

  @doc """
  Marks step as running.
  """
  @spec start(t()) :: t()
  def start(%__MODULE__{} = step) do
    %{step | state: :running, started_at: DateTime.utc_now(), attempt: step.attempt + 1}
  end

  @doc """
  Marks step as completed with result.
  """
  @spec complete(t(), term()) :: t()
  def complete(%__MODULE__{} = step, result) do
    now = DateTime.utc_now()
    duration = if step.started_at, do: DateTime.diff(now, step.started_at, :millisecond), else: 0

    %{step | state: :completed, result: result, completed_at: now, duration_ms: duration}
  end

  @doc """
  Marks step as failed with error.
  """
  @spec fail(t(), term()) :: t()
  def fail(%__MODULE__{} = step, error) do
    now = DateTime.utc_now()
    duration = if step.started_at, do: DateTime.diff(now, step.started_at, :millisecond), else: 0

    %{step | state: :failed, error: error, completed_at: now, duration_ms: duration}
  end

  @doc """
  Marks step as skipped.
  """
  @spec skip(t(), term()) :: t()
  def skip(%__MODULE__{} = step, reason \\ nil) do
    %{step | state: :skipped, result: {:skipped, reason}}
  end

  @doc """
  Marks step as awaiting human approval.
  """
  @spec await(t(), keyword()) :: t()
  def await(%__MODULE__{} = step, opts \\ []) do
    %{step | state: :awaiting, metadata: Map.put(step.metadata, :await_opts, opts)}
  end

  @doc """
  Marks step as cancelled.
  """
  @spec cancel(t()) :: t()
  def cancel(%__MODULE__{} = step) do
    %{step | state: :cancelled}
  end

  @doc """
  Resets step for retry.
  """
  @spec reset_for_retry(t()) :: t()
  def reset_for_retry(%__MODULE__{} = step) do
    %{step | state: :pending, started_at: nil, completed_at: nil, duration_ms: nil, error: nil}
  end

  @doc """
  Checks if step can be retried.
  """
  @spec can_retry?(t()) :: boolean()
  def can_retry?(%__MODULE__{} = step) do
    step.attempt < step.max_retries
  end

  @doc """
  Checks if an error should trigger a retry based on retry_on/no_retry_on config.
  """
  @spec should_retry_error?(t(), term()) :: boolean()
  def should_retry_error?(%__MODULE__{} = step, error) do
    # First check no_retry_on (takes precedence)
    if step.no_retry_on && matches_error?(error, step.no_retry_on) do
      false
    else
      # If retry_on is specified, error must match; otherwise retry all
      case step.retry_on do
        nil -> true
        patterns -> matches_error?(error, patterns)
      end
    end
  end

  @doc """
  Calculates retry delay with backoff and jitter.
  """
  @spec calculate_retry_delay(t()) :: pos_integer()
  def calculate_retry_delay(%__MODULE__{} = step) do
    base_delay = step.retry_delay
    attempt = step.attempt

    delay =
      case step.retry_backoff do
        :fixed ->
          base_delay

        :exponential ->
          round(base_delay * :math.pow(2, attempt - 1))

        :linear ->
          base_delay * attempt

        fun when is_function(fun, 2) ->
          fun.(attempt, base_delay)
      end

    # Apply max delay cap
    delay =
      case step.retry_max_delay do
        nil -> delay
        max -> min(delay, max)
      end

    # Apply jitter if enabled
    if step.retry_jitter do
      jitter = :rand.uniform() * delay * 0.1
      round(delay + jitter)
    else
      delay
    end
  end

  @doc """
  Gets the timeout value, evaluating dynamic timeout if needed.
  """
  @spec get_timeout(t(), map()) :: pos_integer() | :infinity
  def get_timeout(%__MODULE__{timeout: timeout}, ctx) when is_function(timeout, 1) do
    normalize_timeout(timeout.(ctx))
  end

  def get_timeout(%__MODULE__{timeout: timeout}, _ctx), do: timeout

  @doc """
  Checks if step has a rollback function.
  """
  @spec has_rollback?(t()) :: boolean()
  def has_rollback?(%__MODULE__{rollback: nil}), do: false
  def has_rollback?(%__MODULE__{rollback: _}), do: true

  @doc """
  Checks if step is in a terminal state.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}) do
    state in [:completed, :failed, :skipped, :cancelled]
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_deps(nil), do: []
  defp normalize_deps(dep) when is_atom(dep), do: [dep]
  defp normalize_deps(deps) when is_list(deps), do: deps

  defp normalize_timeout(nil), do: nil
  defp normalize_timeout(:infinity), do: :infinity
  defp normalize_timeout(ms) when is_integer(ms), do: ms
  defp normalize_timeout({n, unit}), do: Config.to_ms({n, unit})
  defp normalize_timeout(fun) when is_function(fun, 1), do: fun

  defp all_deps_satisfied?(%__MODULE__{depends_on: []}, _completed), do: true

  defp all_deps_satisfied?(%__MODULE__{depends_on: deps}, completed) do
    Enum.all?(deps, &MapSet.member?(completed, &1))
  end

  defp any_deps_satisfied?(%__MODULE__{depends_on_any: []}, _completed), do: true

  defp any_deps_satisfied?(%__MODULE__{depends_on_any: deps}, completed) do
    Enum.any?(deps, &MapSet.member?(completed, &1))
  end

  defp group_deps_satisfied?(%__MODULE__{depends_on_group: nil}, _groups), do: true

  defp group_deps_satisfied?(%__MODULE__{depends_on_group: group}, groups) do
    Map.get(groups, group, false)
  end

  defp graft_deps_satisfied?(%__MODULE__{depends_on_graft: nil}, _completed), do: true

  defp graft_deps_satisfied?(%__MODULE__{depends_on_graft: graft}, completed) do
    MapSet.member?(completed, {:graft, graft})
  end

  defp matches_error?(error, patterns) when is_list(patterns) do
    Enum.any?(patterns, &matches_error_pattern?(error, &1))
  end

  defp matches_error_pattern?(error, pattern) when is_atom(pattern) do
    case error do
      ^pattern -> true
      {^pattern, _} -> true
      %{__struct__: ^pattern} -> true
      _ -> false
    end
  end

  defp matches_error_pattern?(error, {type, subtype}) do
    error == {type, subtype}
  end

  defp matches_error_pattern?(error, pattern) do
    error == pattern
  end
end
