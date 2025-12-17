defmodule DagTest do
  use ExUnit.Case, async: true

  doctest Dag

  describe "new/1" do
    test "creates empty DAG" do
      dag = Dag.new()
      assert dag.nodes == %{}
      assert dag.edges == %{}
      assert dag.groups == %{}
    end

    test "creates DAG with metadata" do
      dag = Dag.new(metadata: %{name: :test, version: 1})
      assert dag.metadata == %{name: :test, version: 1}
    end
  end

  describe "from_definition/1" do
    test "creates DAG from definition" do
      {:ok, dag} =
        Dag.from_definition(
          nodes: [
            {:a, %{label: "A"}},
            {:b, %{label: "B"}},
            {:c, %{label: "C"}}
          ],
          edges: [
            {:a, :b},
            {:b, :c}
          ]
        )

      assert Dag.node_count(dag) == 3
      assert Dag.edge_count(dag) == 2
    end

    test "returns error for cyclic definition" do
      {:error, {:cycle_detected, _}} =
        Dag.from_definition(
          nodes: [:a, :b],
          edges: [
            {:a, :b},
            {:b, :a}
          ]
        )
    end
  end

  describe "add_node/3" do
    test "adds node with data" do
      dag =
        Dag.new()
        |> Dag.add_node(:a, %{label: "Node A"})

      assert {:ok, %{label: "Node A"}} = Dag.get_node(dag, :a)
    end

    test "adds node without data" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)

      assert {:ok, %{}} = Dag.get_node(dag, :a)
    end

    test "updates existing node data" do
      dag =
        Dag.new()
        |> Dag.add_node(:a, %{label: "Original"})
        |> Dag.add_node(:a, %{label: "Updated"})

      assert {:ok, %{label: "Updated"}} = Dag.get_node(dag, :a)
    end
  end

  describe "add_nodes/2" do
    test "adds multiple nodes" do
      dag =
        Dag.new()
        |> Dag.add_nodes([:a, :b, :c])

      assert Dag.node_count(dag) == 3
    end

    test "adds multiple nodes with data" do
      dag =
        Dag.new()
        |> Dag.add_nodes(a: %{label: "A"}, b: %{label: "B"})

      assert {:ok, %{label: "A"}} = Dag.get_node(dag, :a)
      assert {:ok, %{label: "B"}} = Dag.get_node(dag, :b)
    end
  end

  describe "remove_node/2" do
    test "removes node and its edges" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)
        |> Dag.add_node(:b)
        |> Dag.add_node(:c)
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.remove_node(:b)

      assert Dag.node_count(dag) == 2
      refute Dag.has_node?(dag, :b)
      refute Dag.has_edge?(dag, :a, :b)
      refute Dag.has_edge?(dag, :b, :c)
    end

    test "removes node from groups" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)
        |> Dag.add_node(:b)
        |> Dag.add_to_group(:group1, [:a, :b])
        |> Dag.remove_node(:a)

      assert Dag.get_group(dag, :group1) == [:b]
    end
  end

  describe "add_edge/4" do
    test "adds edge between nodes" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)
        |> Dag.add_node(:b)
        |> Dag.add_edge(:a, :b)

      assert Dag.has_edge?(dag, :a, :b)
      assert Dag.successors(dag, :a) == [:b]
      assert Dag.predecessors(dag, :b) == [:a]
    end

    test "adds edge with data" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{weight: 10})

      assert Dag.has_edge?(dag, :a, :b)
    end

    test "auto-creates missing nodes" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert Dag.has_node?(dag, :a)
      assert Dag.has_node?(dag, :b)
    end
  end

  describe "remove_edge/3" do
    test "removes edge between nodes" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.remove_edge(:a, :b)

      refute Dag.has_edge?(dag, :a, :b)
      # Nodes should still exist
      assert Dag.has_node?(dag, :a)
      assert Dag.has_node?(dag, :b)
    end
  end

  describe "groups" do
    test "adds nodes to group" do
      dag =
        Dag.new()
        |> Dag.add_nodes([:a, :b, :c])
        |> Dag.add_to_group(:parallel, [:a, :b])

      assert Dag.get_group(dag, :parallel) == [:a, :b]
    end

    test "removes node from group" do
      dag =
        Dag.new()
        |> Dag.add_nodes([:a, :b])
        |> Dag.add_to_group(:parallel, [:a, :b])
        |> Dag.remove_from_group(:parallel, :a)

      assert Dag.get_group(dag, :parallel) == [:b]
    end
  end

  describe "topological_sort/1" do
    test "sorts simple linear DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      {:ok, sorted} = Dag.topological_sort(dag)
      assert sorted == [:a, :b, :c]
    end

    test "sorts diamond DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)
        |> Dag.add_edge(:c, :d)

      {:ok, sorted} = Dag.topological_sort(dag)

      # a must come first
      assert hd(sorted) == :a
      # d must come last
      assert List.last(sorted) == :d
      # b and c must come after a and before d
      a_idx = Enum.find_index(sorted, &(&1 == :a))
      b_idx = Enum.find_index(sorted, &(&1 == :b))
      c_idx = Enum.find_index(sorted, &(&1 == :c))
      d_idx = Enum.find_index(sorted, &(&1 == :d))

      assert a_idx < b_idx
      assert a_idx < c_idx
      assert b_idx < d_idx
      assert c_idx < d_idx
    end

    test "returns error for cyclic graph" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:c, :a)

      assert {:error, :cycle_detected} = Dag.topological_sort(dag)
    end
  end

  describe "detect_cycle/1" do
    test "returns nil for acyclic graph" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      assert nil == Dag.detect_cycle(dag)
    end

    test "returns cycle path for cyclic graph" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:c, :a)

      cycle = Dag.detect_cycle(dag)
      assert is_list(cycle)
      assert length(cycle) > 0
    end

    test "detects self-loop" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :a)

      cycle = Dag.detect_cycle(dag)
      assert cycle != nil
    end
  end

  describe "validate/1" do
    test "returns :ok for valid DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      assert :ok = Dag.validate(dag)
    end

    test "returns error for cyclic DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :a)

      assert {:error, {:cycle_detected, _}} = Dag.validate(dag)
    end
  end

  describe "roots/1 and leaves/1" do
    test "returns roots (nodes with no predecessors)" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:c, :d)

      roots = Dag.roots(dag)
      assert Enum.sort(roots) == [:a, :b]
    end

    test "returns leaves (nodes with no successors)" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)

      leaves = Dag.leaves(dag)
      assert Enum.sort(leaves) == [:b, :c]
    end
  end

  describe "ancestors/2 and descendants/2" do
    test "returns all ancestors" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:a, :c)

      ancestors = Dag.ancestors(dag, :c)
      assert Enum.sort(ancestors) == [:a, :b]
    end

    test "returns all descendants" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:b, :d)

      descendants = Dag.descendants(dag, :a)
      assert Enum.sort(descendants) == [:b, :c, :d]
    end
  end

  describe "longest_paths/1" do
    test "computes correct levels" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      paths = Dag.longest_paths(dag)
      assert paths[:a] == 0
      assert paths[:b] == 1
      assert paths[:c] == 2
    end

    test "handles diamond pattern" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)
        |> Dag.add_edge(:c, :d)

      paths = Dag.longest_paths(dag)
      assert paths[:a] == 0
      assert paths[:b] == 1
      assert paths[:c] == 1
      assert paths[:d] == 2
    end
  end

  describe "nodes_at_level/2" do
    test "returns nodes at specific level" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)
        |> Dag.add_edge(:c, :d)

      assert Dag.nodes_at_level(dag, 0) == [:a]
      assert Enum.sort(Dag.nodes_at_level(dag, 1)) == [:b, :c]
      assert Dag.nodes_at_level(dag, 2) == [:d]
    end
  end

  # ============================================
  # Path Operations
  # ============================================

  describe "path_exists?/3" do
    test "returns true when path exists" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      assert Dag.path_exists?(dag, :a, :c)
      assert Dag.path_exists?(dag, :a, :b)
      assert Dag.path_exists?(dag, :b, :c)
    end

    test "returns false when no path exists" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      refute Dag.path_exists?(dag, :c, :a)
      refute Dag.path_exists?(dag, :b, :a)
    end

    test "returns true for same node" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)

      assert Dag.path_exists?(dag, :a, :a)
    end
  end

  describe "shortest_path/3" do
    test "finds shortest path in linear DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      assert {:ok, [:a, :b, :c]} = Dag.shortest_path(dag, :a, :c)
    end

    test "finds shortest path in diamond DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)
        |> Dag.add_edge(:c, :d)

      {:ok, path} = Dag.shortest_path(dag, :a, :d)
      # Should be length 3 (either a->b->d or a->c->d)
      assert length(path) == 3
      assert hd(path) == :a
      assert List.last(path) == :d
    end

    test "returns error when no path exists" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert {:error, :no_path} = Dag.shortest_path(dag, :b, :a)
    end

    test "returns single node path for same source and target" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)

      assert {:ok, [:a]} = Dag.shortest_path(dag, :a, :a)
    end
  end

  describe "all_paths/3" do
    test "finds all paths in diamond DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)
        |> Dag.add_edge(:c, :d)

      paths = Dag.all_paths(dag, :a, :d)
      assert length(paths) == 2
      assert [:a, :b, :d] in paths
      assert [:a, :c, :d] in paths
    end

    test "returns single path for linear DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      assert [[:a, :b, :c]] = Dag.all_paths(dag, :a, :c)
    end

    test "returns empty list when no path exists" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert [] = Dag.all_paths(dag, :b, :a)
    end
  end

  describe "distance/3" do
    test "returns correct distance" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      assert {:ok, 0} = Dag.distance(dag, :a, :a)
      assert {:ok, 1} = Dag.distance(dag, :a, :b)
      assert {:ok, 2} = Dag.distance(dag, :a, :c)
    end

    test "returns error when no path exists" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert {:error, :no_path} = Dag.distance(dag, :b, :a)
    end
  end

  # ============================================
  # Graph Transformations
  # ============================================

  describe "transitive_reduction/1" do
    test "removes redundant edges" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:a, :c)

      reduced = Dag.transitive_reduction(dag)

      assert Dag.has_edge?(reduced, :a, :b)
      assert Dag.has_edge?(reduced, :b, :c)
      refute Dag.has_edge?(reduced, :a, :c)
    end

    test "preserves necessary edges" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      reduced = Dag.transitive_reduction(dag)

      assert Dag.edge_count(reduced) == 2
    end
  end

  describe "reverse/1" do
    test "reverses all edge directions" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      reversed = Dag.reverse(dag)

      assert Dag.has_edge?(reversed, :b, :a)
      assert Dag.has_edge?(reversed, :c, :b)
      refute Dag.has_edge?(reversed, :a, :b)
      refute Dag.has_edge?(reversed, :b, :c)
    end

    test "preserves node data" do
      dag =
        Dag.new()
        |> Dag.add_node(:a, %{label: "A"})
        |> Dag.add_node(:b, %{label: "B"})
        |> Dag.add_edge(:a, :b)

      reversed = Dag.reverse(dag)

      assert {:ok, %{label: "A"}} = Dag.get_node(reversed, :a)
      assert {:ok, %{label: "B"}} = Dag.get_node(reversed, :b)
    end
  end

  describe "subgraph/2" do
    test "extracts induced subgraph" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)
        |> Dag.add_edge(:c, :d)

      sub = Dag.subgraph(dag, [:a, :b, :c])

      assert Dag.node_count(sub) == 3
      assert Dag.has_edge?(sub, :a, :b)
      assert Dag.has_edge?(sub, :b, :c)
      refute Dag.has_node?(sub, :d)
    end

    test "removes edges to excluded nodes" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)

      sub = Dag.subgraph(dag, [:a, :b])

      assert Dag.has_edge?(sub, :a, :b)
      refute Dag.has_edge?(sub, :a, :c)
    end
  end

  describe "filter_nodes/2" do
    test "filters nodes by predicate" do
      dag =
        Dag.new()
        |> Dag.add_node(:a, %{status: :completed})
        |> Dag.add_node(:b, %{status: :pending})
        |> Dag.add_node(:c, %{status: :completed})
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      filtered = Dag.filter_nodes(dag, fn _id, data -> data[:status] == :completed end)

      assert Dag.node_count(filtered) == 2
      assert Dag.has_node?(filtered, :a)
      assert Dag.has_node?(filtered, :c)
      refute Dag.has_node?(filtered, :b)
    end
  end

  # ============================================
  # Node/Edge Introspection
  # ============================================

  describe "in_degree/2" do
    test "returns correct in-degree" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :c)

      assert Dag.in_degree(dag, :a) == 0
      assert Dag.in_degree(dag, :b) == 0
      assert Dag.in_degree(dag, :c) == 2
    end
  end

  describe "out_degree/2" do
    test "returns correct out-degree" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)

      assert Dag.out_degree(dag, :a) == 2
      assert Dag.out_degree(dag, :b) == 0
      assert Dag.out_degree(dag, :c) == 0
    end
  end

  describe "get_edge/3" do
    test "returns edge data" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{weight: 10})

      assert {:ok, %{weight: 10}} = Dag.get_edge(dag, :a, :b)
    end

    test "returns error for non-existent edge" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)
        |> Dag.add_node(:b)

      assert {:error, :not_found} = Dag.get_edge(dag, :a, :b)
    end
  end

  describe "update_edge/4" do
    test "updates edge data" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{weight: 10})
        |> Dag.update_edge(:a, :b, fn data -> Map.put(data, :weight, 20) end)

      assert {:ok, %{weight: 20}} = Dag.get_edge(dag, :a, :b)
    end
  end

  describe "edges/1" do
    test "returns all edges as list" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{w: 1})
        |> Dag.add_edge(:b, :c, %{w: 2})

      edges = Dag.edges(dag)

      assert length(edges) == 2
      assert {:a, :b, %{w: 1}} in edges
      assert {:b, :c, %{w: 2}} in edges
    end
  end

  # ============================================
  # Graph Composition
  # ============================================

  describe "merge/2" do
    test "merges two DAGs" do
      dag1 =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      dag2 =
        Dag.new()
        |> Dag.add_edge(:c, :d)

      merged = Dag.merge(dag1, dag2)

      assert Dag.node_count(merged) == 4
      assert Dag.has_edge?(merged, :a, :b)
      assert Dag.has_edge?(merged, :c, :d)
    end

    test "dag2 takes precedence for node data" do
      dag1 =
        Dag.new()
        |> Dag.add_node(:a, %{label: "Original"})

      dag2 =
        Dag.new()
        |> Dag.add_node(:a, %{label: "Updated"})

      merged = Dag.merge(dag1, dag2)

      assert {:ok, %{label: "Updated"}} = Dag.get_node(merged, :a)
    end
  end

  describe "concat/2" do
    test "chains DAGs together" do
      dag1 =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      dag2 =
        Dag.new()
        |> Dag.add_edge(:c, :d)

      chained = Dag.concat(dag1, dag2)

      assert Dag.has_edge?(chained, :a, :b)
      assert Dag.has_edge?(chained, :c, :d)
      assert Dag.has_edge?(chained, :b, :c)
    end
  end

  # ============================================
  # Serialization
  # ============================================

  describe "to_map/1 and from_map/1" do
    test "round-trip serialization" do
      dag =
        Dag.new(metadata: %{name: :test})
        |> Dag.add_node(:a, %{label: "A"})
        |> Dag.add_node(:b, %{label: "B"})
        |> Dag.add_edge(:a, :b, %{weight: 10})

      map = Dag.to_map(dag)
      {:ok, restored} = Dag.from_map(map)

      assert Dag.node_count(restored) == 2
      assert Dag.edge_count(restored) == 1
      assert {:ok, %{label: "A"}} = Dag.get_node(restored, :a)
      assert {:ok, %{weight: 10}} = Dag.get_edge(restored, :a, :b)
    end

    test "from_map returns error for cyclic DAG" do
      map = %{
        nodes: [%{id: :a, data: %{}}, %{id: :b, data: %{}}],
        edges: [%{from: :a, to: :b, data: %{}}, %{from: :b, to: :a, data: %{}}]
      }

      assert {:error, {:cycle_detected, _}} = Dag.from_map(map)
    end
  end

  # ============================================
  # Weight-Based Algorithms
  # ============================================

  describe "critical_path/2" do
    test "finds critical path with weights" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{duration: 5})
        |> Dag.add_edge(:a, :c, %{duration: 2})
        |> Dag.add_edge(:b, :d, %{duration: 3})
        |> Dag.add_edge(:c, :d, %{duration: 1})

      {total, path} = Dag.critical_path(dag, fn data -> data[:duration] || 1 end)

      assert total == 8
      assert path == [:a, :b, :d]
    end

    test "handles single node" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)

      {total, path} = Dag.critical_path(dag, fn _ -> 1 end)

      assert total == 0
      assert path == [:a]
    end
  end

  describe "shortest_weighted_path/4" do
    test "finds shortest weighted path" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b, %{cost: 1})
        |> Dag.add_edge(:a, :c, %{cost: 5})
        |> Dag.add_edge(:b, :d, %{cost: 1})
        |> Dag.add_edge(:c, :d, %{cost: 1})

      {:ok, {weight, path}} = Dag.shortest_weighted_path(dag, :a, :d, fn data -> data[:cost] || 1 end)

      assert weight == 2
      assert path == [:a, :b, :d]
    end

    test "returns error when no path exists" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)

      assert {:error, :no_path} = Dag.shortest_weighted_path(dag, :b, :a, fn _ -> 1 end)
    end
  end

  # ============================================
  # Validation Enhancements
  # ============================================

  describe "is_tree?/1" do
    test "returns true for tree structure" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)

      assert Dag.is_tree?(dag)
    end

    test "returns false when node has multiple parents" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :c)

      refute Dag.is_tree?(dag)
    end

    test "returns false for multiple roots" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :d)

      refute Dag.is_tree?(dag)
    end
  end

  describe "is_forest?/1" do
    test "returns true for forest structure" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:c, :d)

      assert Dag.is_forest?(dag)
    end

    test "returns false when node has multiple parents" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :c)
        |> Dag.add_edge(:b, :c)

      refute Dag.is_forest?(dag)
    end
  end

  describe "connected_components/1" do
    test "finds disconnected components" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:c, :d)

      components = Dag.connected_components(dag)

      assert length(components) == 2
      component_sets = Enum.map(components, &MapSet.new/1)
      assert MapSet.new([:a, :b]) in component_sets
      assert MapSet.new([:c, :d]) in component_sets
    end

    test "returns single component for connected DAG" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      components = Dag.connected_components(dag)

      assert length(components) == 1
      assert MapSet.new(hd(components)) == MapSet.new([:a, :b, :c])
    end
  end

  # ============================================
  # Protocol Implementations
  # ============================================

  describe "Inspect protocol" do
    test "provides useful inspect output" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      output = inspect(dag)

      assert output =~ "#Dag<"
      assert output =~ "nodes: 3"
      assert output =~ "edges: 2"
    end
  end

  describe "Enumerable protocol" do
    test "allows Enum.count" do
      dag =
        Dag.new()
        |> Dag.add_nodes([:a, :b, :c])

      assert Enum.count(dag) == 3
    end

    test "allows Enum.map in topological order" do
      dag =
        Dag.new()
        |> Dag.add_edge(:a, :b)
        |> Dag.add_edge(:b, :c)

      ids = Enum.map(dag, fn {id, _data} -> id end)

      assert ids == [:a, :b, :c]
    end

    test "allows Enum.member?" do
      dag =
        Dag.new()
        |> Dag.add_node(:a)

      assert Enum.member?(dag, :a)
      refute Enum.member?(dag, :b)
    end
  end

  describe "Collectable protocol" do
    test "allows building DAG with Enum.into" do
      elements = [
        {:node, :a, %{label: "A"}},
        {:node, :b, %{label: "B"}},
        {:edge, :a, :b}
      ]

      dag = Enum.into(elements, Dag.new())

      assert Dag.node_count(dag) == 2
      assert Dag.has_edge?(dag, :a, :b)
      assert {:ok, %{label: "A"}} = Dag.get_node(dag, :a)
    end
  end
end
