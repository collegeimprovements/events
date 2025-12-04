defmodule Events.Infra.Scheduler.Workflow.Introspection.Dot do
  @moduledoc """
  Generates Graphviz DOT diagrams from workflows.
  """

  alias Events.Infra.Scheduler.Workflow

  @doc """
  Generates a DOT diagram for a workflow.

  ## Options

  - `:execution_id` - Show execution state coloring
  - `:rankdir` - Graph direction (TB, LR, etc.)
  """
  @spec to_dot(atom() | Workflow.t(), keyword()) :: String.t()
  def to_dot(workflow_name, opts \\ [])

  def to_dot(workflow_name, opts) when is_atom(workflow_name) do
    case get_workflow(workflow_name) do
      {:ok, workflow} -> to_dot(workflow, opts)
      _ -> "digraph workflow { error [label=\"Workflow not found\"]; }"
    end
  end

  def to_dot(%Workflow{} = workflow, opts) do
    rankdir = Keyword.get(opts, :rankdir, "TB")
    execution_id = Keyword.get(opts, :execution_id)

    step_states = get_step_states(execution_id)

    lines = [
      "digraph #{workflow.name} {",
      "  rankdir=#{rankdir};",
      "  node [shape=box, style=rounded];",
      ""
    ]

    # Add nodes
    nodes = generate_nodes(workflow, step_states)
    lines = lines ++ nodes ++ [""]

    # Add edges
    edges = generate_edges(workflow)
    lines = lines ++ edges

    # Add cluster for groups
    groups = generate_clusters(workflow)
    lines = lines ++ groups

    lines = lines ++ ["}"]

    Enum.join(lines, "\n")
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp get_workflow(name) do
    alias Events.Infra.Scheduler.Config
    store = Config.get_store_module(Config.get())
    store.get_workflow(name)
  end

  defp get_step_states(nil), do: %{}

  defp get_step_states(execution_id) do
    alias Events.Infra.Scheduler.Workflow.Engine

    case Engine.get_state(execution_id) do
      {:ok, state} -> Map.get(state, :step_states, %{})
      _ -> %{}
    end
  end

  defp generate_nodes(workflow, step_states) do
    Enum.map(workflow.steps, fn {name, step} ->
      label = format_label(name, step)
      attrs = node_attributes(name, step, step_states)
      "  #{name} [label=\"#{label}\"#{attrs}];"
    end)
  end

  defp generate_edges(workflow) do
    workflow.steps
    |> Enum.flat_map(fn {name, step} ->
      deps = step.depends_on ++ step.depends_on_any

      adj_deps =
        Map.get(workflow.adjacency, name, [])
        |> Enum.filter(fn
          {:group, _} -> false
          {:graft, _} -> false
          _ -> true
        end)

      all_deps = Enum.uniq(deps ++ adj_deps)

      Enum.map(all_deps, fn dep ->
        "  #{dep} -> #{name};"
      end)
    end)
    |> Enum.uniq()
  end

  defp generate_clusters(workflow) do
    workflow.groups
    |> Enum.flat_map(fn {group_name, members} ->
      [
        "",
        "  subgraph cluster_#{group_name} {",
        "    label=\"#{humanize(group_name)}\";",
        "    style=dashed;",
        "    color=blue;"
      ] ++
        Enum.map(members, fn member -> "    #{member};" end) ++
        ["  }"]
    end)
  end

  defp node_attributes(name, step, step_states) do
    attrs = []

    # Add color based on state
    attrs =
      case Map.get(step_states, name) do
        :completed -> [", fillcolor=\"#90EE90\", style=\"filled,rounded\"" | attrs]
        :running -> [", fillcolor=\"#FFD700\", style=\"filled,rounded\"" | attrs]
        :failed -> [", fillcolor=\"#FF6B6B\", style=\"filled,rounded\"" | attrs]
        :skipped -> [", fillcolor=\"#E6E6FA\", style=\"filled,rounded\"" | attrs]
        :awaiting -> [", fillcolor=\"#87CEEB\", style=\"filled,rounded\"" | attrs]
        _ -> attrs
      end

    # Add shape for special steps
    attrs =
      cond do
        step.rollback != nil -> [", peripheries=2" | attrs]
        step.condition != nil -> [", shape=diamond" | attrs]
        true -> attrs
      end

    Enum.join(attrs)
  end

  defp format_label(name, step) do
    label = humanize(name)

    cond do
      step.await_approval -> "#{label}\\n(awaiting)"
      true -> label
    end
  end

  defp humanize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
