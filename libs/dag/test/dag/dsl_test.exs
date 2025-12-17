defmodule Dag.DSLTest do
  use ExUnit.Case, async: true

  # Required for inline build macro
  require Dag.DSL

  describe "module-based DSL" do
    defmodule SimpleWorkflow do
      use Dag.DSL

      step :start, label: "Begin"
      step :process, label: "Process", after: :start
      step :complete, label: "Done", after: :process
    end

    test "creates DAG with steps" do
      dag = SimpleWorkflow.dag()

      assert Dag.node_count(dag) == 3
      assert Dag.has_node?(dag, :start)
      assert Dag.has_node?(dag, :process)
      assert Dag.has_node?(dag, :complete)
    end

    test "creates edges from after: option" do
      dag = SimpleWorkflow.dag()

      assert Dag.has_edge?(dag, :start, :process)
      assert Dag.has_edge?(dag, :process, :complete)
    end

    test "stores step data" do
      dag = SimpleWorkflow.dag()

      assert {:ok, %{label: "Begin"}} = Dag.get_node(dag, :start)
      assert {:ok, %{label: "Process"}} = Dag.get_node(dag, :process)
    end

    test "steps/0 returns step list" do
      assert SimpleWorkflow.steps() == [:start, :process, :complete]
    end

    test "edges/0 returns edge list" do
      edges = SimpleWorkflow.edges()

      assert length(edges) == 2
      assert {:start, :process, %{}} in edges
      assert {:process, :complete, %{}} in edges
    end

    test "validate!/0 succeeds for valid DAG" do
      assert :ok = SimpleWorkflow.validate!()
    end
  end

  describe "multiple dependencies" do
    defmodule FanInWorkflow do
      use Dag.DSL

      step :a, label: "A"
      step :b, label: "B"
      step :c, label: "C", after: [:a, :b]
    end

    test "creates multiple incoming edges" do
      dag = FanInWorkflow.dag()

      assert Dag.has_edge?(dag, :a, :c)
      assert Dag.has_edge?(dag, :b, :c)
      assert Dag.in_degree(dag, :c) == 2
    end
  end

  describe "edge data" do
    defmodule WeightedWorkflow do
      use Dag.DSL

      step :a
      step :b, after: :a, edge: %{weight: 10, label: "heavy"}
      step :c, after: :a, edge: %{weight: 1}
    end

    test "stores edge data" do
      dag = WeightedWorkflow.dag()

      assert {:ok, %{weight: 10, label: "heavy"}} = Dag.get_edge(dag, :a, :b)
      assert {:ok, %{weight: 1}} = Dag.get_edge(dag, :a, :c)
    end
  end

  describe "conditional edges" do
    defmodule ConditionalWorkflow do
      use Dag.DSL

      step :check
      step :success, after: :check, when: :success?
      step :failure, after: :check, when: :failure?
    end

    test "stores condition in edge data" do
      dag = ConditionalWorkflow.dag()

      assert {:ok, %{when: :success?}} = Dag.get_edge(dag, :check, :success)
      assert {:ok, %{when: :failure?}} = Dag.get_edge(dag, :check, :failure)
    end
  end

  describe "parallel blocks" do
    defmodule ParallelWorkflow do
      use Dag.DSL

      step :fetch, label: "Fetch Data"

      parallel :processing, after: :fetch do
        step :process_a, label: "Process A"
        step :process_b, label: "Process B"
        step :process_c, label: "Process C"
      end

      step :merge, label: "Merge", after: [:process_a, :process_b, :process_c]
    end

    test "creates parallel steps with dependencies" do
      dag = ParallelWorkflow.dag()

      assert Dag.has_edge?(dag, :fetch, :process_a)
      assert Dag.has_edge?(dag, :fetch, :process_b)
      assert Dag.has_edge?(dag, :fetch, :process_c)
    end

    test "adds steps to group" do
      groups = ParallelWorkflow.groups()

      assert Map.has_key?(groups, :processing)
      assert :process_a in groups[:processing]
      assert :process_b in groups[:processing]
      assert :process_c in groups[:processing]
    end

    test "fan-in works correctly" do
      dag = ParallelWorkflow.dag()

      assert Dag.in_degree(dag, :merge) == 3
    end
  end

  describe "explicit edges" do
    defmodule ExplicitEdgeWorkflow do
      use Dag.DSL

      step :a
      step :b
      step :c

      edge :a, :b
      edge :b, :c, %{label: "next"}
    end

    test "creates explicit edges" do
      dag = ExplicitEdgeWorkflow.dag()

      assert Dag.has_edge?(dag, :a, :b)
      assert Dag.has_edge?(dag, :b, :c)
    end

    test "stores explicit edge data" do
      dag = ExplicitEdgeWorkflow.dag()

      assert {:ok, %{label: "next"}} = Dag.get_edge(dag, :b, :c)
    end
  end

  describe "step groups" do
    defmodule GroupedWorkflow do
      use Dag.DSL

      step :a, group: :phase1
      step :b, group: :phase1
      step :c, group: :phase2, after: [:a, :b]
    end

    test "adds steps to explicit groups" do
      groups = GroupedWorkflow.groups()

      assert :a in groups[:phase1]
      assert :b in groups[:phase1]
      assert :c in groups[:phase2]
    end
  end

  describe "metadata" do
    defmodule MetadataWorkflow do
      use Dag.DSL, metadata: %{name: :my_workflow, version: 1}

      step :start
      step :end_step, after: :start
    end

    test "stores metadata in DAG" do
      dag = MetadataWorkflow.dag()

      assert dag.metadata == %{name: :my_workflow, version: 1}
    end
  end

  describe "inline DSL with build/2" do
    test "builds DAG inline" do
      dag =
        Dag.DSL.build do
          step :a, label: "Start"
          step :b, label: "Middle", after: :a
          step :c, label: "End", after: :b
        end

      assert Dag.node_count(dag) == 3
      assert Dag.has_edge?(dag, :a, :b)
      assert Dag.has_edge?(dag, :b, :c)
      assert {:ok, %{label: "Start"}} = Dag.get_node(dag, :a)
    end

    test "builds DAG with metadata" do
      dag =
        Dag.DSL.build metadata: %{name: :inline} do
          step :x
          step :y, after: :x
        end

      assert dag.metadata == %{name: :inline}
    end

    test "builds DAG with explicit edges" do
      dag =
        Dag.DSL.build do
          step :a
          step :b
          edge :a, :b, %{weight: 5}
        end

      assert {:ok, %{weight: 5}} = Dag.get_edge(dag, :a, :b)
    end

    test "builds DAG with multiple dependencies" do
      dag =
        Dag.DSL.build do
          step :a
          step :b
          step :c, after: [:a, :b]
        end

      assert Dag.has_edge?(dag, :a, :c)
      assert Dag.has_edge?(dag, :b, :c)
    end
  end

  describe "complex workflow" do
    defmodule OrderWorkflow do
      use Dag.DSL, metadata: %{name: :order_processing}

      step :receive_order, label: "Receive Order"
      step :validate, label: "Validate Order", after: :receive_order

      parallel :fulfillment, after: :validate do
        step :reserve_inventory, label: "Reserve Inventory"
        step :process_payment, label: "Process Payment"
        step :notify_warehouse, label: "Notify Warehouse"
      end

      step :confirm, label: "Confirm Order", after: [:reserve_inventory, :process_payment]
      step :ship, label: "Ship Order", after: [:confirm, :notify_warehouse]
      step :complete, label: "Order Complete", after: :ship
    end

    test "creates valid workflow DAG" do
      dag = OrderWorkflow.dag()

      # Check structure
      assert Dag.node_count(dag) == 8
      assert :ok = Dag.validate(dag)

      # Check topological order is valid
      {:ok, sorted} = Dag.topological_sort(dag)
      assert hd(sorted) == :receive_order
      assert List.last(sorted) == :complete

      # Check parallel group
      groups = OrderWorkflow.groups()
      assert length(groups[:fulfillment]) == 3
    end

    test "supports critical path analysis" do
      dag = OrderWorkflow.dag()

      # Add weights for critical path
      dag =
        dag
        |> Dag.update_edge(:receive_order, :validate, fn _ -> %{duration: 1} end)
        |> Dag.update_edge(:validate, :reserve_inventory, fn _ -> %{duration: 5} end)
        |> Dag.update_edge(:validate, :process_payment, fn _ -> %{duration: 3} end)
        |> Dag.update_edge(:validate, :notify_warehouse, fn _ -> %{duration: 1} end)
        |> Dag.update_edge(:reserve_inventory, :confirm, fn _ -> %{duration: 2} end)
        |> Dag.update_edge(:process_payment, :confirm, fn _ -> %{duration: 1} end)
        |> Dag.update_edge(:confirm, :ship, fn _ -> %{duration: 2} end)
        |> Dag.update_edge(:notify_warehouse, :ship, fn _ -> %{duration: 1} end)
        |> Dag.update_edge(:ship, :complete, fn _ -> %{duration: 1} end)

      {total, path} = Dag.critical_path(dag, fn data -> data[:duration] || 0 end)

      assert total > 0
      assert :receive_order in path
      assert :complete in path
    end
  end

  describe "validation" do
    defmodule CyclicWorkflow do
      use Dag.DSL

      step :a
      step :b, after: :a

      # This creates a cycle via explicit edge
      edge :b, :a
    end

    test "validate! raises on cyclic DAG" do
      assert_raise Dag.Error.CycleDetected, fn ->
        CyclicWorkflow.validate!()
      end
    end
  end
end
