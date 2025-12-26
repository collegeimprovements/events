defmodule OmScheduler.Workflow.Introspection.Mermaid do
  @moduledoc """
  Generates Mermaid diagrams from workflows.
  """

  alias OmScheduler.Workflow

  @doc """
  Generates a Mermaid diagram for a workflow.

  ## Options

  - `:execution_id` - Show execution state coloring
  - `:show_groups` - Highlight parallel groups with subgraphs
  - `:direction` - Graph direction (TD, LR, etc.)
  """
  @spec to_mermaid(atom() | Workflow.t(), keyword()) :: String.t()
  def to_mermaid(workflow_name, opts \\ [])

  def to_mermaid(workflow_name, opts) when is_atom(workflow_name) do
    case get_workflow(workflow_name) do
      {:ok, workflow} -> to_mermaid(workflow, opts)
      _ -> "graph TD\n  error[Workflow not found]"
    end
  end

  def to_mermaid(%Workflow{} = workflow, opts) do
    direction = Keyword.get(opts, :direction, "TD")
    show_groups = Keyword.get(opts, :show_groups, false)
    execution_id = Keyword.get(opts, :execution_id)

    step_states = get_step_states(execution_id)

    lines = ["graph #{direction}"]

    # Add nodes
    nodes = generate_nodes(workflow, step_states)
    lines = lines ++ nodes

    # Add edges
    edges = generate_edges(workflow)
    lines = lines ++ edges

    # Add subgraphs for groups if enabled
    lines =
      if show_groups and map_size(workflow.groups) > 0 do
        lines ++ generate_subgraphs(workflow)
      else
        lines
      end

    # Add style classes for execution states
    lines =
      if execution_id do
        lines ++ generate_style_classes()
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  @doc """
  Renders diagram to file (placeholder for future implementation).
  """
  @spec render_diagram(atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render_diagram(workflow_name, opts \\ []) do
    mermaid = to_mermaid(workflow_name, opts)
    output = Keyword.get(opts, :output, "workflow.mmd")

    case File.write(output, mermaid) do
      :ok -> {:ok, output}
      error -> error
    end
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

  defp generate_nodes(workflow, step_states) do
    Enum.map(workflow.steps, fn {name, step} ->
      label = format_label(name, step)
      state_class = get_state_class(name, step_states)

      if state_class do
        "  #{name}[#{label}]:::#{state_class}"
      else
        "  #{name}[#{label}]"
      end
    end)
  end

  defp generate_edges(workflow) do
    workflow.steps
    |> Enum.flat_map(fn {name, step} ->
      # Direct dependencies
      deps = step.depends_on ++ step.depends_on_any

      # Adjacency list dependencies
      adj_deps =
        Map.get(workflow.adjacency, name, [])
        |> Enum.filter(fn
          {:group, _} -> false
          {:graft, _} -> false
          _ -> true
        end)

      all_deps = Enum.uniq(deps ++ adj_deps)

      Enum.map(all_deps, fn dep ->
        "  #{dep} --> #{name}"
      end)
    end)
    |> Enum.uniq()
  end

  defp generate_subgraphs(workflow) do
    Enum.flat_map(workflow.groups, fn {group_name, members} ->
      [
        "  subgraph #{group_name}[#{humanize(group_name)}]"
      ] ++
        Enum.map(members, fn member -> "    #{member}" end) ++
        ["  end"]
    end)
  end

  defp generate_style_classes do
    [
      "  classDef completed fill:#90EE90,stroke:#228B22",
      "  classDef running fill:#FFD700,stroke:#DAA520",
      "  classDef pending fill:#D3D3D3,stroke:#808080",
      "  classDef failed fill:#FF6B6B,stroke:#DC143C",
      "  classDef skipped fill:#E6E6FA,stroke:#9370DB",
      "  classDef awaiting fill:#87CEEB,stroke:#4169E1"
    ]
  end

  defp format_label(name, step) do
    label = humanize(name)

    cond do
      step.rollback != nil -> "#{label} ↩"
      step.condition != nil -> "#{label} ?"
      step.await_approval -> "#{label} ⏸"
      true -> label
    end
  end

  defp get_state_class(name, step_states) do
    case Map.get(step_states, name) do
      :completed -> "completed"
      :running -> "running"
      :pending -> "pending"
      :failed -> "failed"
      :skipped -> "skipped"
      :awaiting -> "awaiting"
      _ -> nil
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
