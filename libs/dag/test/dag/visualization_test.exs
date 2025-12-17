defmodule Dag.VisualizationTest do
  use ExUnit.Case, async: true

  setup do
    dag =
      Dag.new()
      |> Dag.add_node(:a, %{label: "Step A"})
      |> Dag.add_node(:b, %{label: "Step B"})
      |> Dag.add_node(:c, %{label: "Step C"})
      |> Dag.add_edge(:a, :b)
      |> Dag.add_edge(:b, :c)

    {:ok, dag: dag}
  end

  describe "to_mermaid/2" do
    test "generates basic mermaid diagram", %{dag: dag} do
      result = Dag.to_mermaid(dag)

      assert result =~ "graph TD"
      assert result =~ "a[Step A]"
      assert result =~ "b[Step B]"
      assert result =~ "c[Step C]"
      assert result =~ "a --> b"
      assert result =~ "b --> c"
    end

    test "supports custom direction", %{dag: dag} do
      result = Dag.to_mermaid(dag, direction: "LR")
      assert result =~ "graph LR"
    end

    test "supports custom node labels", %{dag: dag} do
      result =
        Dag.to_mermaid(dag,
          node_label: fn id, _data -> "Node: #{id}" end
        )

      assert result =~ "a[Node: a]"
    end

    test "supports node styles", %{dag: dag} do
      dag = Dag.update_node(dag, :a, fn data -> Map.put(data, :status, :completed) end)

      result =
        Dag.to_mermaid(dag,
          node_style: fn _id, data ->
            case Map.get(data, :status) do
              :completed -> "completed"
              _ -> nil
            end
          end,
          styles: %{
            completed: "fill:#90EE90"
          }
        )

      assert result =~ "a[Step A]:::completed"
      assert result =~ "classDef completed fill:#90EE90"
    end

    test "supports subgraphs for groups" do
      dag =
        Dag.new()
        |> Dag.add_nodes([:a, :b, :c])
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_to_group(:parallel, [:b, :c])

      result = Dag.to_mermaid(dag, show_groups: true)

      assert result =~ "subgraph parallel"
      assert result =~ "end"
    end

    test "supports edge labels" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{label: "depends on"})

      result = Dag.to_mermaid(dag)
      assert result =~ "a -->|depends on| b"
    end

    test "supports title" do
      dag = Dag.new() |> Dag.add_node(:a)

      result = Dag.to_mermaid(dag, title: "My Workflow")
      assert result =~ "title: My Workflow"
    end
  end

  describe "to_dot/2" do
    test "generates basic DOT diagram", %{dag: dag} do
      result = Dag.to_dot(dag)

      assert result =~ "digraph G {"
      assert result =~ "rankdir=TB"
      assert result =~ ~s(a [label="Step A"])
      assert result =~ "a -> b;"
      assert result =~ "b -> c;"
      assert result =~ "}"
    end

    test "supports custom direction", %{dag: dag} do
      result = Dag.to_dot(dag, rankdir: "LR")
      assert result =~ "rankdir=LR"
    end

    test "supports custom graph name", %{dag: dag} do
      result = Dag.to_dot(dag, name: "MyWorkflow")
      assert result =~ "digraph MyWorkflow {"
    end

    test "supports node attributes", %{dag: dag} do
      dag = Dag.update_node(dag, :a, fn data -> Map.put(data, :status, :completed) end)

      result =
        Dag.to_dot(dag,
          node_attrs: fn _id, data ->
            case Map.get(data, :status) do
              :completed -> "fillcolor=green, style=filled"
              _ -> nil
            end
          end
        )

      assert result =~ "fillcolor=green"
    end

    test "supports clusters for groups" do
      dag =
        Dag.new()
        |> Dag.add_nodes([:a, :b, :c])
        |> Dag.add_to_group(:parallel, [:b, :c])

      result = Dag.to_dot(dag)

      assert result =~ "subgraph cluster_parallel"
      assert result =~ "style=dashed"
    end
  end

  describe "to_ascii/2" do
    test "generates levels view by default", %{dag: dag} do
      result = Dag.to_ascii(dag)

      assert result =~ "Level 0: Step A"
      assert result =~ "Level 1: Step B"
      assert result =~ "Level 2: Step C"
    end

    test "generates list view", %{dag: dag} do
      result = Dag.to_ascii(dag, style: :list)

      assert result =~ "1. Step A"
      assert result =~ "2. Step B (after: a)"
      assert result =~ "3. Step C (after: b)"
    end

    test "generates tree view", %{dag: dag} do
      result = Dag.to_ascii(dag, style: :tree)

      # Tree structure should show hierarchy
      assert result =~ "Step A"
      assert result =~ "Step B"
      assert result =~ "Step C"
    end

    test "supports custom labels", %{dag: dag} do
      result =
        Dag.to_ascii(dag,
          node_label: fn id, _data -> "Node #{id}" end
        )

      assert result =~ "Node a"
    end
  end
end
