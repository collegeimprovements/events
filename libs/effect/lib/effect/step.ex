defmodule Effect.Step do
  @moduledoc """
  Represents a single step in an Effect workflow.

  A step contains a function to execute along with configuration for:
  - Dependencies (which steps must run first)
  - Timing (timeout per attempt)
  - Retry behavior (backoff strategies)
  - Conditional execution (when to skip)
  - Error handling (catch, fallback)
  - Saga rollback
  """

  @type step_fun :: (map() -> result()) | (map(), map() -> result())
  @type result :: {:ok, map()} | {:error, term()} | {:halt, term()}

  @type retry_opts :: [
          max: pos_integer(),
          delay: pos_integer(),
          backoff: :fixed | :linear | :exponential | :decorrelated_jitter,
          max_delay: pos_integer(),
          jitter: float(),
          when: (term() -> boolean())
        ]

  @type step_type ::
          :step
          | :parallel
          | :branch
          | :embed
          | :each
          | :race
          | :using
          | :require
          | :validate
          | :tap
          | :assign

  @type t :: %__MODULE__{
          name: atom(),
          fun: step_fun() | nil,
          arity: 1 | 2,
          type: step_type(),
          after: atom() | [atom()] | nil,
          timeout: pos_integer() | nil,
          retry: retry_opts() | nil,
          when: (map() -> boolean()) | nil,
          catch: (term(), map() -> result()) | nil,
          fallback: term() | nil,
          fallback_when: [atom()] | nil,
          rollback: (map() -> :ok | {:error, term()}) | nil,
          meta: map()
        }

  defstruct [
    :name,
    :fun,
    :after,
    :timeout,
    :retry,
    :when,
    :catch,
    :fallback,
    :fallback_when,
    :rollback,
    arity: 1,
    type: :step,
    meta: %{}
  ]

  @doc """
  Creates a new step with the given name, function, and options.

  ## Options

  - `:after` - Step(s) that must complete before this one
  - `:timeout` - Per-attempt timeout in milliseconds
  - `:retry` - Retry configuration (see `t:retry_opts/0`)
  - `:when` - Condition function; step skipped if returns false
  - `:catch` - Error handler `fn reason, ctx -> {:ok, map} | {:error, term} end`
  - `:fallback` - Default value map on error (e.g., `%{data: nil}`)
  - `:fallback_when` - Only use fallback for these error reasons
  - `:rollback` - Rollback function for saga pattern
  - `:meta` - Arbitrary metadata

  ## Examples

      Step.new(:fetch_user, &fetch_user/1)
      Step.new(:charge, &charge/1, timeout: 5_000, retry: [max: 3])
      Step.new(:notify, &notify/1, after: :charge, rollback: &refund/1)
  """
  @spec new(atom(), step_fun(), keyword()) :: t()
  def new(name, fun, opts \\ []) when is_atom(name) do
    arity = determine_arity(fun)

    %__MODULE__{
      name: name,
      fun: fun,
      arity: arity,
      type: Keyword.get(opts, :type, :step),
      after: Keyword.get(opts, :after),
      timeout: Keyword.get(opts, :timeout),
      retry: Keyword.get(opts, :retry),
      when: Keyword.get(opts, :when),
      catch: Keyword.get(opts, :catch),
      fallback: Keyword.get(opts, :fallback),
      fallback_when: Keyword.get(opts, :fallback_when),
      rollback: Keyword.get(opts, :rollback),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @doc """
  Determines if a step should be skipped based on its `when` condition.
  """
  @spec should_skip?(t(), map()) :: boolean()
  def should_skip?(%__MODULE__{when: nil}, _ctx), do: false
  def should_skip?(%__MODULE__{when: condition}, ctx), do: not condition.(ctx)

  @doc """
  Returns the dependencies of this step.
  """
  @spec dependencies(t()) :: [atom()]
  def dependencies(%__MODULE__{after: nil}), do: []
  def dependencies(%__MODULE__{after: dep}) when is_atom(dep), do: [dep]
  def dependencies(%__MODULE__{after: deps}) when is_list(deps), do: deps

  # Determine function arity by checking if it's 1 or 2 args
  defp determine_arity(fun) when is_function(fun, 1), do: 1
  defp determine_arity(fun) when is_function(fun, 2), do: 2
  defp determine_arity(nil), do: 1  # nil is valid for special step types (parallel, branch, etc.)

  defp determine_arity(other) do
    raise ArgumentError,
      "expected step function with arity 1 or 2, got: #{inspect(other)}"
  end
end
