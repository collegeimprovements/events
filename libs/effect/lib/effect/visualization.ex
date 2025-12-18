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

        if show_title do
          "#{effect.name}\n#{ascii}"
        else
          ascii
        end

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

    has_parallel =
      Enum.any?(effect.steps, fn step -> step.type == :parallel end)

    has_branches =
      Enum.any?(effect.steps, fn step -> step.type == :branch end)

    has_each =
      Enum.any?(effect.steps, fn step -> step.type == :each end)

    has_race =
      Enum.any?(effect.steps, fn step -> step.type == :race end)

    has_embed =
      Enum.any?(effect.steps, fn step -> step.type == :embed end)

    %{
      name: effect.name,
      step_count: length(steps),
      steps: steps,
      has_parallel: has_parallel,
      has_branches: has_branches,
      has_each: has_each,
      has_race: has_race,
      has_embed: has_embed,
      middleware_count: length(effect.middleware),
      has_ensure: length(effect.ensure_fns) > 0
    }
  end

  # Format a node label with step type info
  defp format_node_label(name, effect) do
    step = Enum.find(effect.steps, fn s -> s.name == name end)

    case step do
      nil ->
        to_string(name)

      %{type: :parallel} ->
        "#{name}\\n[parallel]"

      %{type: :branch} ->
        "#{name}\\n[branch]"

      %{type: :each} ->
        "#{name}\\n[each]"

      %{type: :race} ->
        "#{name}\\n[race]"

      %{type: :embed} ->
        "#{name}\\n[embed]"

      _ ->
        to_string(name)
    end
  end
end
