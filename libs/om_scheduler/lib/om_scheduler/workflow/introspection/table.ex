defmodule OmScheduler.Workflow.Introspection.Table do
  @moduledoc """
  Generates ASCII table representation of workflows.
  """

  alias OmScheduler.Workflow

  @doc """
  Generates an ASCII table for a workflow.

  ## Options

  - `:execution_id` - Show execution state
  """
  @spec to_table(atom() | Workflow.t(), keyword()) :: String.t()
  def to_table(workflow_name, opts \\ [])

  def to_table(workflow_name, opts) when is_atom(workflow_name) do
    case get_workflow(workflow_name) do
      {:ok, workflow} -> to_table(workflow, opts)
      _ -> "Workflow not found: #{workflow_name}"
    end
  end

  def to_table(%Workflow{} = workflow, opts) do
    execution_id = Keyword.get(opts, :execution_id)
    step_states = get_step_states(execution_id)

    # Build rows
    rows =
      workflow.execution_order
      |> Enum.map(fn name ->
        step = Map.get(workflow.steps, name)
        state = Map.get(step_states, name)
        build_row(name, step, state)
      end)

    # Define columns
    columns =
      if execution_id do
        [:step, :depends_on, :timeout, :retries, :rollback, :state]
      else
        [:step, :depends_on, :timeout, :retries, :rollback]
      end

    # Build table
    header = build_header(columns)
    separator = build_separator(columns)
    body = Enum.map(rows, &build_row_string(&1, columns))

    ([
       separator,
       header,
       separator
     ] ++ body ++ [separator])
    |> Enum.join("\n")
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp get_workflow(name) do
    alias OmScheduler.Config
    store = Config.get_store_module(Config.get())
    store.get_workflow(name)
  end

  defp get_step_states(nil), do: %{}

  defp get_step_states(execution_id) do
    alias OmScheduler.Workflow.Engine

    case Engine.get_state(execution_id) do
      {:ok, state} -> Map.get(state, :step_states, %{})
      _ -> %{}
    end
  end

  defp build_row(name, step, state) do
    %{
      step: Atom.to_string(name),
      depends_on: format_deps(step),
      timeout: format_timeout(step.timeout),
      retries: "#{step.max_retries}",
      rollback: if(step.rollback, do: "✓", else: "✗"),
      state: format_state(state)
    }
  end

  defp format_deps(step) do
    deps = step.depends_on ++ step.depends_on_any

    case deps do
      [] -> "-"
      _ -> Enum.map_join(deps, ", ", &Atom.to_string/1)
    end
  end

  defp format_timeout(:infinity), do: "∞"
  defp format_timeout(ms) when ms < 1000, do: "#{ms}ms"
  defp format_timeout(ms) when ms < 60_000, do: "#{div(ms, 1000)}s"
  defp format_timeout(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)}m"
  defp format_timeout(ms), do: "#{div(ms, 3_600_000)}h"

  defp format_state(nil), do: "-"
  defp format_state(:pending), do: "⏳"
  defp format_state(:ready), do: "🔜"
  defp format_state(:running), do: "▶️"
  defp format_state(:completed), do: "✅"
  defp format_state(:failed), do: "❌"
  defp format_state(:skipped), do: "⏭️"
  defp format_state(:cancelled), do: "🚫"
  defp format_state(:awaiting), do: "⏸️"
  defp format_state(other), do: Atom.to_string(other)

  defp column_width(:step), do: 20
  defp column_width(:depends_on), do: 20
  defp column_width(:timeout), do: 10
  defp column_width(:retries), do: 8
  defp column_width(:rollback), do: 10
  defp column_width(:state), do: 10

  defp column_header(:step), do: "Step"
  defp column_header(:depends_on), do: "Depends On"
  defp column_header(:timeout), do: "Timeout"
  defp column_header(:retries), do: "Retries"
  defp column_header(:rollback), do: "Rollback"
  defp column_header(:state), do: "State"

  defp build_header(columns) do
    cells =
      Enum.map(columns, fn col ->
        header = column_header(col)
        width = column_width(col)
        String.pad_trailing(header, width)
      end)

    "│ " <> Enum.join(cells, " │ ") <> " │"
  end

  defp build_separator(columns) do
    cells =
      Enum.map(columns, fn col ->
        width = column_width(col)
        String.duplicate("─", width)
      end)

    "├─" <> Enum.join(cells, "─┼─") <> "─┤"
  end

  defp build_row_string(row, columns) do
    cells =
      Enum.map(columns, fn col ->
        value = Map.get(row, col, "-")
        width = column_width(col)
        truncate_and_pad(value, width)
      end)

    "│ " <> Enum.join(cells, " │ ") <> " │"
  end

  defp truncate_and_pad(value, width) do
    str = to_string(value)

    if String.length(str) > width do
      String.slice(str, 0, width - 3) <> "..."
    else
      String.pad_trailing(str, width)
    end
  end
end
