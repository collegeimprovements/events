defmodule Dag.ErrorTest do
  use ExUnit.Case, async: true

  alias Dag.Error.{
    CycleDetected,
    NoPath,
    NodeNotFound,
    EdgeNotFound,
    InvalidDefinition,
    MissingNodes,
    DeserializationFailed
  }

  describe "CycleDetected" do
    test "creates error with path" do
      error = CycleDetected.exception(path: [:a, :b, :c, :a])

      assert error.path == [:a, :b, :c, :a]
      assert error.message =~ "Cycle detected"
      assert error.message =~ "a -> b -> c -> a"
    end

    test "can be raised" do
      assert_raise CycleDetected, ~r/Cycle detected/, fn ->
        raise CycleDetected, path: [:x, :y, :x]
      end
    end
  end

  describe "NoPath" do
    test "creates error with from and to" do
      error = NoPath.exception(from: :a, to: :z)

      assert error.from == :a
      assert error.to == :z
      assert error.message =~ "No path exists"
      assert error.message =~ ":a"
      assert error.message =~ ":z"
    end

    test "can be raised" do
      assert_raise NoPath, ~r/No path exists/, fn ->
        raise NoPath, from: :start, to: :end
      end
    end
  end

  describe "NodeNotFound" do
    test "creates error with node" do
      error = NodeNotFound.exception(node: :missing)

      assert error.node == :missing
      assert error.message =~ "not found"
      assert error.message =~ ":missing"
    end

    test "can be raised" do
      assert_raise NodeNotFound, ~r/not found/, fn ->
        raise NodeNotFound, node: :unknown
      end
    end
  end

  describe "EdgeNotFound" do
    test "creates error with from and to" do
      error = EdgeNotFound.exception(from: :a, to: :b)

      assert error.from == :a
      assert error.to == :b
      assert error.message =~ "not found"
    end

    test "can be raised" do
      assert_raise EdgeNotFound, ~r/not found/, fn ->
        raise EdgeNotFound, from: :x, to: :y
      end
    end
  end

  describe "InvalidDefinition" do
    test "creates error with reason" do
      error = InvalidDefinition.exception(reason: :invalid_structure)

      assert error.reason == :invalid_structure
      assert error.message =~ "Invalid DAG"
    end

    test "creates error with reason and details" do
      error = InvalidDefinition.exception(reason: :missing_field, details: [:name])

      assert error.reason == :missing_field
      assert error.details == [:name]
      assert error.message =~ "missing_field"
    end
  end

  describe "MissingNodes" do
    test "creates error with nodes list" do
      error = MissingNodes.exception(nodes: [:x, :y, :z])

      assert error.nodes == [:x, :y, :z]
      assert error.message =~ "missing nodes"
    end
  end

  describe "DeserializationFailed" do
    test "creates error with reason" do
      error = DeserializationFailed.exception(reason: "invalid JSON")

      assert error.reason == "invalid JSON"
      assert error.message =~ "deserialize"
    end
  end

  describe "from_tuple/1" do
    test "converts cycle_detected tuple" do
      error = Dag.Error.from_tuple({:error, {:cycle_detected, [:a, :b, :a]}})

      assert %CycleDetected{} = error
      assert error.path == [:a, :b, :a]
    end

    test "converts no_path tuple" do
      error = Dag.Error.from_tuple({:error, :no_path})

      assert %NoPath{} = error
    end

    test "converts not_found tuple" do
      error = Dag.Error.from_tuple({:error, :not_found})

      assert %NodeNotFound{} = error
    end

    test "converts missing_nodes tuple" do
      error = Dag.Error.from_tuple({:error, {:missing_nodes, [:x]}})

      assert %MissingNodes{} = error
      assert error.nodes == [:x]
    end
  end

  describe "to_tuple/1" do
    test "converts CycleDetected to tuple" do
      error = CycleDetected.exception(path: [:a, :b, :a])

      assert {:error, {:cycle_detected, [:a, :b, :a]}} = Dag.Error.to_tuple(error)
    end

    test "converts NoPath to tuple" do
      error = NoPath.exception(from: :a, to: :z)

      assert {:error, {:no_path, {:a, :z}}} = Dag.Error.to_tuple(error)
    end
  end

  # ============================================
  # Integration with Dag bang functions
  # ============================================

  describe "bang function integration" do
    test "topological_sort! raises CycleDetected" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :a)

      assert_raise CycleDetected, fn ->
        Dag.topological_sort!(dag)
      end
    end

    test "shortest_path! raises NoPath" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert_raise NoPath, fn ->
        Dag.shortest_path!(dag, :b, :a)
      end
    end

    test "distance! raises NoPath" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert_raise NoPath, fn ->
        Dag.distance!(dag, :b, :a)
      end
    end

    test "get_node! raises NodeNotFound" do
      dag = Dag.new()

      assert_raise NodeNotFound, fn ->
        Dag.get_node!(dag, :missing)
      end
    end

    test "get_edge! raises EdgeNotFound" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)
        |> Dag.add_node(:b)

      assert_raise EdgeNotFound, fn ->
        Dag.get_edge!(dag, :a, :b)
      end
    end

    test "validate! raises CycleDetected" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :a)

      assert_raise CycleDetected, fn ->
        Dag.validate!(dag)
      end
    end

    test "bang functions return values on success" do
      dag =
        Dag.new()
        |> Dag.add_node(:a, %{label: "A"})
        |> Dag.add_node(:b, %{label: "B"})
        |> Dag.add_edge(:a, :b, %{weight: 10})

      assert [:a, :b] = Dag.topological_sort!(dag)
      assert [:a, :b] = Dag.shortest_path!(dag, :a, :b)
      assert 1 = Dag.distance!(dag, :a, :b)
      assert %{label: "A"} = Dag.get_node!(dag, :a)
      assert %{weight: 10} = Dag.get_edge!(dag, :a, :b)
      assert :ok = Dag.validate!(dag)
    end
  end
end
