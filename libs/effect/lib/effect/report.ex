defmodule Effect.Report do
  @moduledoc """
  Execution report for an Effect run.

  Contains timing information, step statuses, and any errors that occurred.
  Generated when running an effect with `report: true` option.
  """

  alias Effect.Error

  @type step_entry :: %{
          name: atom(),
          status: :ok | :error | :skipped | :rolled_back,
          duration_ms: non_neg_integer(),
          attempts: pos_integer(),
          added_keys: [atom()],
          reason: term() | nil,
          rollback_status: :ok | :error | nil
        }

  @type t :: %__MODULE__{
          effect_name: atom(),
          execution_id: String.t(),
          status: :ok | :error | :halted,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          total_duration_ms: non_neg_integer(),
          steps_completed: non_neg_integer(),
          steps_skipped: non_neg_integer(),
          error: Error.t() | nil,
          halt_reason: term() | nil,
          steps: [step_entry()]
        }

  defstruct [
    :effect_name,
    :execution_id,
    status: :ok,
    started_at: nil,
    completed_at: nil,
    total_duration_ms: 0,
    steps_completed: 0,
    steps_skipped: 0,
    error: nil,
    halt_reason: nil,
    steps: []
  ]

  @doc """
  Creates a new report for an effect execution.
  """
  @spec new(atom(), String.t()) :: t()
  def new(effect_name, execution_id) do
    %__MODULE__{
      effect_name: effect_name,
      execution_id: execution_id,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Records a completed step in the report.
  """
  @spec add_step(t(), atom(), :ok | :error | :skipped, keyword()) :: t()
  def add_step(%__MODULE__{steps: steps, steps_completed: completed} = report, name, status, opts \\ []) do
    entry = %{
      name: name,
      status: status,
      duration_ms: Keyword.get(opts, :duration_ms, 0),
      attempts: Keyword.get(opts, :attempts, 1),
      added_keys: Keyword.get(opts, :added_keys, []),
      reason: Keyword.get(opts, :reason),
      rollback_status: Keyword.get(opts, :rollback_status)
    }

    new_completed =
      case status do
        :ok -> completed + 1
        _ -> completed
      end

    new_skipped =
      case status do
        :skipped -> report.steps_skipped + 1
        _ -> report.steps_skipped
      end

    %{report | steps: steps ++ [entry], steps_completed: new_completed, steps_skipped: new_skipped}
  end

  @doc """
  Marks a step as rolled back.
  """
  @spec mark_rolled_back(t(), atom(), :ok | :error) :: t()
  def mark_rolled_back(%__MODULE__{steps: steps} = report, step_name, rollback_status) do
    updated_steps =
      Enum.map(steps, fn
        %{name: ^step_name} = entry -> %{entry | rollback_status: rollback_status}
        entry -> entry
      end)

    %{report | steps: updated_steps}
  end

  @doc """
  Completes the report with final status.
  """
  @spec complete(t(), :ok | :error | :halted, keyword()) :: t()
  def complete(%__MODULE__{started_at: started} = report, status, opts \\ []) do
    completed_at = DateTime.utc_now()
    duration = DateTime.diff(completed_at, started, :millisecond)

    %{
      report
      | status: status,
        completed_at: completed_at,
        total_duration_ms: duration,
        error: Keyword.get(opts, :error),
        halt_reason: Keyword.get(opts, :halt_reason)
    }
  end

  @doc """
  Returns timing breakdown by step.
  """
  @spec timing_breakdown(t()) :: %{atom() => non_neg_integer()}
  def timing_breakdown(%__MODULE__{steps: steps}) do
    Map.new(steps, fn %{name: name, duration_ms: ms} -> {name, ms} end)
  end

  @doc """
  Returns list of step names that were executed (not skipped).
  """
  @spec executed_steps(t()) :: [atom()]
  def executed_steps(%__MODULE__{steps: steps}) do
    steps
    |> Enum.filter(fn %{status: status} -> status == :ok end)
    |> Enum.map(fn %{name: name} -> name end)
  end

  @doc """
  Returns list of step names that were skipped.
  """
  @spec skipped_steps(t()) :: [atom()]
  def skipped_steps(%__MODULE__{steps: steps}) do
    steps
    |> Enum.filter(fn %{status: status} -> status == :skipped end)
    |> Enum.map(fn %{name: name} -> name end)
  end
end

defimpl Inspect, for: Effect.Report do
  import Inspect.Algebra

  def inspect(%Effect.Report{} = report, opts) do
    fields = [
      effect: report.effect_name,
      status: report.status,
      duration_ms: report.total_duration_ms,
      steps: report.steps_completed,
      skipped: report.steps_skipped
    ]

    concat(["#Effect.Report<", to_doc(fields, opts), ">"])
  end
end
