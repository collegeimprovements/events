defmodule Effect.Error do
  @moduledoc """
  Structured error type for Effect failures.

  Contains comprehensive information about what went wrong:
  - Which step failed
  - The original error reason
  - Context at time of failure
  - Retry attempts made
  - Any rollback errors that occurred
  - Execution metadata
  """

  @type rollback_error :: %{step: atom(), error: term()}

  @type t :: %__MODULE__{
          step: atom(),
          reason: term(),
          tag: atom() | nil,
          context: map(),
          stacktrace: list() | nil,
          attempts: pos_integer(),
          duration_ms: non_neg_integer(),
          rollback_errors: [rollback_error()],
          execution_id: String.t(),
          effect_name: atom(),
          metadata: map()
        }

  defstruct [
    :step,
    :reason,
    :tag,
    context: %{},
    stacktrace: nil,
    attempts: 1,
    duration_ms: 0,
    rollback_errors: [],
    execution_id: "",
    effect_name: nil,
    metadata: %{}
  ]

  @doc """
  Creates a new error for a failed step.

  ## Options

  - `:tag` - Error classification atom
  - `:context` - Context map at failure time
  - `:stacktrace` - Elixir stacktrace
  - `:attempts` - Number of attempts made
  - `:duration_ms` - Time spent before failure
  - `:execution_id` - Unique execution identifier
  - `:effect_name` - Name of the effect that failed
  - `:metadata` - Additional metadata

  ## Examples

      Error.new(:charge, :insufficient_funds)
      Error.new(:api_call, %{status: 500}, tag: :server_error, attempts: 3)
  """
  @spec new(atom(), term(), keyword()) :: t()
  def new(step, reason, opts \\ []) do
    %__MODULE__{
      step: step,
      reason: reason,
      tag: Keyword.get(opts, :tag),
      context: Keyword.get(opts, :context, %{}),
      stacktrace: Keyword.get(opts, :stacktrace),
      attempts: Keyword.get(opts, :attempts, 1),
      duration_ms: Keyword.get(opts, :duration_ms, 0),
      rollback_errors: Keyword.get(opts, :rollback_errors, []),
      execution_id: Keyword.get(opts, :execution_id, ""),
      effect_name: Keyword.get(opts, :effect_name),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Returns a new error with updated context.
  """
  @spec with_context(t(), map()) :: t()
  def with_context(%__MODULE__{} = error, context) do
    %{error | context: context}
  end

  @doc """
  Adds a rollback error to the error struct.

  Called when a rollback fails during saga compensation.
  """
  @spec add_rollback_error(t(), atom(), term()) :: t()
  def add_rollback_error(%__MODULE__{rollback_errors: errors} = error, step, err) do
    %{error | rollback_errors: errors ++ [%{step: step, error: err}]}
  end

  @recoverable_tags [:timeout, :rate_limited, :transient]

  @doc """
  Checks if the error is recoverable using the Recoverable protocol.

  Falls back to checking if the error has specific tags or properties
  that indicate recoverability.
  """
  @spec recoverable?(t()) :: boolean()
  def recoverable?(%__MODULE__{tag: tag}) when tag in @recoverable_tags, do: true

  def recoverable?(%__MODULE__{reason: reason}) do
    check_recoverable_protocol(reason)
  end

  defp check_recoverable_protocol(reason) do
    Code.ensure_loaded?(FnTypes.Protocols.Recoverable) and
      safe_recoverable?(reason)
  end

  defp safe_recoverable?(reason) do
    FnTypes.Protocols.Recoverable.recoverable?(reason)
  rescue
    _ -> false
  end

  @doc """
  Returns a human-readable message for the error.
  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{step: step, reason: reason, tag: nil}) do
    "Step :#{step} failed: #{inspect(reason)}"
  end

  def message(%__MODULE__{step: step, reason: reason, tag: tag}) do
    "Step :#{step} failed (#{tag}): #{inspect(reason)}"
  end
end

defimpl Inspect, for: Effect.Error do
  import Inspect.Algebra

  def inspect(%Effect.Error{} = error, opts) do
    fields = [
      step: error.step,
      reason: error.reason,
      tag: error.tag,
      attempts: error.attempts
    ]

    fields = maybe_add_rollback_count(fields, error.rollback_errors)

    concat(["#Effect.Error<", to_doc(fields, opts), ">"])
  end

  defp maybe_add_rollback_count(fields, []), do: fields
  defp maybe_add_rollback_count(fields, errors), do: fields ++ [rollback_errors: length(errors)]
end
