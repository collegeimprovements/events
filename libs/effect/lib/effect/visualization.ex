defmodule Effect.Visualization do
  @moduledoc """
  Visualization utilities for Effect workflows.

  Generates ASCII diagrams and Mermaid flowcharts for effects,
  delegating to the DAG library's visualization capabilities.

  ## ASCII Diagram

      Effect.new(:order)
      |> Effect.step(:validate, &validate/1)
      |> Effect.step(:charge, &charge/1, after: :validate)
      |> Effect.step(:fulfill, &fulfill/1, after: :charge)
      |> Effect.Visualization.to_ascii()

      # Output:
      # order
      # ├── validate
      # │   └── charge
      # │       └── fulfill

  ## Mermaid Flowchart

      Effect.new(:order)
      |> Effect.step(:validate, &validate/1)
      |> Effect.step(:charge, &charge/1, after: :validate)
      |> Effect.Visualization.to_mermaid()

      # Output:
      # graph TD
      #     validate --> charge

  """

  alias Effect.Builder

  @doc """
  Generates an ASCII tree representation of the effect's step dependencies.

  ## Options

  - `:title` - Include effect name as title (default: true)
  - `:indent` - Base indentation (default: 0)

  ## Examples

      Effect.new(:workflow)
      |> Effect.step(:a, &fun/1)
      |> Effect.step(:b, &fun/1, after: :a)
      |> Effect.Visualization.to_ascii()
  """
  @spec to_ascii(Builder.t(), keyword()) :: String.t()
  def to_ascii(%Builder{} = effect, opts \\ []) do
    show_title = Keyword.get(opts, :title, true)

    case Builder.build_dag(effect) do
      {:ok, dag} ->
        ascii = Dag.Visualization.to_ascii(dag, opts)
        format_with_title(ascii, effect.name, show_title)

      {:error, reason} ->
        "Error building DAG: #{inspect(reason)}"
    end
  end

  @doc """
  Generates a Mermaid flowchart diagram of the effect's step dependencies.

  ## Options

  - `:direction` - Flow direction: "TD" (top-down), "LR" (left-right), etc. (default: "TD")
  - `:title` - Include effect name as subgraph title (default: false)

  ## Examples

      Effect.new(:workflow)
      |> Effect.step(:a, &fun/1)
      |> Effect.step(:b, &fun/1, after: :a)
      |> Effect.Visualization.to_mermaid()

      # Returns:
      # graph TD
      #     a --> b
  """
  @spec to_mermaid(Builder.t(), keyword()) :: String.t()
  def to_mermaid(%Builder{} = effect, opts \\ []) do
    case Builder.build_dag(effect) do
      {:ok, dag} ->
        Dag.Visualization.to_mermaid(dag, opts)

      {:error, reason} ->
        "%% Error building DAG: #{inspect(reason)}"
    end
  end

  @doc """
  Generates a DOT graph representation for Graphviz.

  ## Options

  - `:rankdir` - Graph direction: "TB", "LR", "BT", "RL" (default: "TB")
  - `:shape` - Node shape (default: "box")

  ## Examples

      Effect.new(:workflow)
      |> Effect.step(:a, &fun/1)
      |> Effect.step(:b, &fun/1, after: :a)
      |> Effect.Visualization.to_dot()
  """
  @spec to_dot(Builder.t(), keyword()) :: String.t()
  def to_dot(%Builder{} = effect, opts \\ []) do
    rankdir = Keyword.get(opts, :rankdir, "TB")
    shape = Keyword.get(opts, :shape, "box")

    case Builder.build_dag(effect) do
      {:ok, dag} ->
        node_lines =
          Enum.map(dag.nodes, fn {name, _data} ->
            label = format_node_label(name, effect)
            "    #{name} [label=\"#{label}\", shape=#{shape}];"
          end)

        edge_lines =
          Enum.flat_map(dag.edges, fn {from, targets} ->
            Enum.map(targets, fn {to, _edge_data} ->
              "    #{from} -> #{to};"
            end)
          end)

        """
        digraph #{effect.name} {
            rankdir=#{rankdir};
        #{Enum.join(node_lines, "\n")}
        #{Enum.join(edge_lines, "\n")}
        }
        """
        |> String.trim()

      {:error, reason} ->
        "// Error building DAG: #{inspect(reason)}"
    end
  end

  @doc """
  Prints the ASCII visualization to stdout.
  """
  @spec print(Builder.t(), keyword()) :: :ok
  def print(%Builder{} = effect, opts \\ []) do
    effect
    |> to_ascii(opts)
    |> IO.puts()
  end

  @doc """
  Returns a summary of the effect structure.

  ## Examples

      Effect.new(:workflow)
      |> Effect.step(:a, &fun/1)
      |> Effect.step(:b, &fun/1, after: :a)
      |> Effect.Visualization.summary()

      # Returns:
      # %{
      #   name: :workflow,
      #   step_count: 2,
      #   steps: [:a, :b],
      #   has_parallel: false,
      #   has_branches: false,
      #   max_depth: 2
      # }
  """
  @spec summary(Builder.t()) :: map()
  def summary(%Builder{} = effect) do
    steps = Builder.step_names(effect)
    step_types = MapSet.new(effect.steps, & &1.type)

    %{
      name: effect.name,
      step_count: length(steps),
      steps: steps,
      has_parallel: MapSet.member?(step_types, :parallel),
      has_branches: MapSet.member?(step_types, :branch),
      has_each: MapSet.member?(step_types, :each),
      has_race: MapSet.member?(step_types, :race),
      has_embed: MapSet.member?(step_types, :embed),
      middleware_count: length(effect.middleware),
      has_ensure: effect.ensure_fns != []
    }
  end

  # Format a node label with step type info
  defp format_node_label(name, effect) do
    step = Enum.find(effect.steps, fn s -> s.name == name end)
    format_step_label(name, step)
  end

  defp format_step_label(name, %{type: type}) when type in [:parallel, :branch, :each, :race, :embed] do
    "#{name}\\n[#{type}]"
  end

  defp format_step_label(name, _step), do: to_string(name)

  defp format_with_title(content, _name, false), do: content
  defp format_with_title(content, name, true), do: "#{name}\n#{content}"
end
