defmodule Dag.Algorithms do
  @moduledoc """
  Graph algorithms for DAG operations.

  This module provides core algorithms:
  - Topological sorting (Kahn's algorithm)
  - Cycle detection (DFS-based)
  - Reachability (ancestors/descendants)
  - Path analysis (longest paths, levels)
  """

  alias Dag

  @type node_id :: Dag.node_id()

  # ============================================
  # Topological Sort
  # ============================================

  @doc """
  Performs topological sort using Kahn's algorithm.

  Returns nodes in an order where dependencies come before dependents.
  """
  @spec topological_sort(Dag.t()) :: {:ok, [node_id()]} | {:error, :cycle_detected}
  def topological_sort(%Dag{} = dag) do
    node_ids = Dag.node_ids(dag)

    # Calculate in-degree for each node
    in_degree =
      Enum.reduce(node_ids, %{}, fn id, acc ->
        Map.put(acc, id, length(Dag.predecessors(dag, id)))
      end)

    # Start with nodes that have no dependencies (in-degree = 0)
    queue =
      in_degree
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _} -> id end)

    do_topological_sort(queue, dag, in_degree, [])
  end

  defp do_topological_sort([], _dag, in_degree, result) do
    # Check if all nodes were processed
    remaining = Enum.filter(in_degree, fn {_id, degree} -> degree > 0 end)

    case remaining do
      [] -> {:ok, Enum.reverse(result)}
      _ -> {:error, :cycle_detected}
    end
  end

  defp do_topological_sort([node | rest], dag, in_degree, result) do
    dependents = Dag.successors(dag, node)

    {new_queue, new_in_degree} =
      Enum.reduce(dependents, {rest, in_degree}, fn dep, {q, deg} ->
        new_deg = Map.update!(deg, dep, &(&1 - 1))

        case new_deg[dep] do
          0 -> {[dep | q], new_deg}
          _ -> {q, new_deg}
        end
      end)

    do_topological_sort(new_queue, dag, Map.delete(new_in_degree, node), [node | result])
  end

  # ============================================
  # Cycle Detection
  # ============================================

  @doc """
  Detects cycles in the DAG using DFS.

  Returns `nil` if no cycle exists, or the cycle path if found.
  """
  @spec detect_cycle(Dag.t()) :: [node_id()] | nil
  def detect_cycle(%Dag{} = dag) do
    node_ids = Dag.node_ids(dag)

    result =
      Enum.reduce_while(node_ids, {MapSet.new(), MapSet.new(), nil}, fn node, {visited, stack, _} ->
        case dfs_cycle(node, dag, visited, stack, []) do
          {:cycle, path} -> {:halt, {visited, stack, path}}
          {:ok, new_visited} -> {:cont, {new_visited, stack, nil}}
        end
      end)

    elem(result, 2)
  end

  defp dfs_cycle(node, dag, visited, stack, path) do
    cond do
      # Found a cycle - node is in current recursion stack
      MapSet.member?(stack, node) ->
        {:cycle, Enum.reverse([node | path])}

      # Already visited in a previous DFS - no cycle through this path
      MapSet.member?(visited, node) ->
        {:ok, visited}

      # Explore this node
      true ->
        new_stack = MapSet.put(stack, node)
        new_path = [node | path]

        # Visit all successors (nodes that depend on this one)
        successors = Dag.successors(dag, node)

        result =
          Enum.reduce_while(successors, {:ok, visited}, fn succ, {:ok, v} ->
            case dfs_cycle(succ, dag, v, new_stack, new_path) do
              {:cycle, _} = cycle -> {:halt, cycle}
              {:ok, new_v} -> {:cont, {:ok, new_v}}
            end
          end)

        case result do
          {:cycle, _} = cycle -> cycle
          {:ok, new_visited} -> {:ok, MapSet.put(new_visited, node)}
        end
    end
  end

  # ============================================
  # Validation
  # ============================================

  @doc """
  Validates the DAG structure.

  Checks for:
  - Cycles
  - Edges referencing non-existent nodes
  """
  @spec validate(Dag.t()) :: :ok | {:error, term()}
  def validate(%Dag{} = dag) do
    with :ok <- validate_no_cycles(dag),
         :ok <- validate_edges_reference_existing_nodes(dag) do
      :ok
    end
  end

  defp validate_no_cycles(dag) do
    case detect_cycle(dag) do
      nil -> :ok
      cycle -> {:error, {:cycle_detected, cycle}}
    end
  end

  defp validate_edges_reference_existing_nodes(dag) do
    node_set = MapSet.new(Dag.node_ids(dag))

    missing =
      dag.edges
      |> Enum.flat_map(fn {from, targets} ->
        missing_from =
          case MapSet.member?(node_set, from) do
            true -> []
            false -> [from]
          end

        missing_to =
          targets
          |> Enum.map(fn {to, _} -> to end)
          |> Enum.reject(&MapSet.member?(node_set, &1))

        missing_from ++ missing_to
      end)
      |> Enum.uniq()

    case missing do
      [] -> :ok
      nodes -> {:error, {:missing_nodes, nodes}}
    end
  end

  # ============================================
  # Reachability
  # ============================================

  @doc """
  Returns all nodes with no predecessors (entry points/roots).
  """
  @spec roots(Dag.t()) :: [node_id()]
  def roots(%Dag{} = dag) do
    dag
    |> Dag.node_ids()
    |> Enum.filter(fn id -> Dag.predecessors(dag, id) == [] end)
  end

  @doc """
  Returns all nodes with no successors (exit points/leaves).
  """
  @spec leaves(Dag.t()) :: [node_id()]
  def leaves(%Dag{} = dag) do
    dag
    |> Dag.node_ids()
    |> Enum.filter(fn id -> Dag.successors(dag, id) == [] end)
  end

  @doc """
  Returns all ancestors of a node (transitive predecessors).
  """
  @spec ancestors(Dag.t(), node_id()) :: [node_id()]
  def ancestors(%Dag{} = dag, id) do
    do_traverse(dag, id, &Dag.predecessors/2, MapSet.new())
    |> MapSet.to_list()
  end

  @doc """
  Returns all descendants of a node (transitive successors).
  """
  @spec descendants(Dag.t(), node_id()) :: [node_id()]
  def descendants(%Dag{} = dag, id) do
    do_traverse(dag, id, &Dag.successors/2, MapSet.new())
    |> MapSet.to_list()
  end

  defp do_traverse(dag, id, get_neighbors, visited) do
    neighbors = get_neighbors.(dag, id)

    Enum.reduce(neighbors, visited, fn neighbor, acc ->
      case MapSet.member?(acc, neighbor) do
        true ->
          acc

        false ->
          acc
          |> MapSet.put(neighbor)
          |> then(&do_traverse(dag, neighbor, get_neighbors, &1))
      end
    end)
  end

  # ============================================
  # Path Analysis
  # ============================================

  @doc """
  Computes the longest path from roots to each node.

  This is useful for determining the "level" of each node in the DAG,
  which can be used for visualization or parallel scheduling.
  """
  @spec longest_paths(Dag.t()) :: %{node_id() => non_neg_integer()}
  def longest_paths(%Dag{} = dag) do
    case topological_sort(dag) do
      {:ok, sorted} ->
        Enum.reduce(sorted, %{}, fn node, distances ->
          # Distance is max of all predecessors + 1, or 0 if no predecessors
          predecessors = Dag.predecessors(dag, node)

          distance =
            case predecessors do
              [] ->
                0

              preds ->
                preds
                |> Enum.map(&Map.get(distances, &1, 0))
                |> Enum.max()
                |> Kernel.+(1)
            end

          Map.put(distances, node, distance)
        end)

      {:error, _} ->
        %{}
    end
  end

  @doc """
  Returns all nodes at a specific depth level.
  """
  @spec nodes_at_level(Dag.t(), non_neg_integer()) :: [node_id()]
  def nodes_at_level(%Dag{} = dag, level) do
    paths = longest_paths(dag)

    paths
    |> Enum.filter(fn {_node, lvl} -> lvl == level end)
    |> Enum.map(fn {node, _} -> node end)
  end

  @doc """
  Returns the maximum depth (longest path length) in the DAG.
  """
  @spec max_depth(Dag.t()) :: non_neg_integer()
  def max_depth(%Dag{} = dag) do
    paths = longest_paths(dag)

    case Map.values(paths) do
      [] -> 0
      values -> Enum.max(values)
    end
  end

  @doc """
  Returns nodes grouped by their level.
  """
  @spec levels(Dag.t()) :: %{non_neg_integer() => [node_id()]}
  def levels(%Dag{} = dag) do
    paths = longest_paths(dag)

    Enum.group_by(
      Map.keys(paths),
      fn node -> Map.get(paths, node) end
    )
  end

  # ============================================
  # Path Operations
  # ============================================

  @doc """
  Checks if a path exists between two nodes.

  ## Examples

      Dag.path_exists?(dag, :a, :c) #=> true
      Dag.path_exists?(dag, :c, :a) #=> false
  """
  @spec path_exists?(Dag.t(), node_id(), node_id()) :: boolean()
  def path_exists?(%Dag{} = dag, from, to) do
    from == to or to in descendants(dag, from)
  end

  @doc """
  Finds the shortest path between two nodes (by hop count).

  Returns `{:ok, path}` where path is a list of node IDs from source to target,
  or `{:error, :no_path}` if no path exists.

  ## Examples

      {:ok, [:a, :b, :c]} = Dag.shortest_path(dag, :a, :c)
      {:error, :no_path} = Dag.shortest_path(dag, :c, :a)
  """
  @spec shortest_path(Dag.t(), node_id(), node_id()) :: {:ok, [node_id()]} | {:error, :no_path}
  def shortest_path(%Dag{}, from, from), do: {:ok, [from]}
  def shortest_path(%Dag{} = dag, from, to), do: bfs_shortest_path(dag, from, to)

  defp bfs_shortest_path(dag, from, to) do
    # BFS to find shortest path
    # Queue contains {node, path_to_node}
    queue = :queue.from_list([{from, [from]}])
    visited = MapSet.new([from])

    do_bfs_shortest_path(dag, to, queue, visited)
  end

  defp do_bfs_shortest_path(dag, target, queue, visited) do
    case :queue.out(queue) do
      {:empty, _} ->
        {:error, :no_path}

      {{:value, {current, path}}, rest_queue} ->
        successors = Dag.successors(dag, current)

        case target in successors do
          true ->
            {:ok, path ++ [target]}

          false ->
            {new_queue, new_visited} =
              Enum.reduce(successors, {rest_queue, visited}, fn succ, {q, v} ->
                case MapSet.member?(v, succ) do
                  true -> {q, v}
                  false -> {:queue.in({succ, path ++ [succ]}, q), MapSet.put(v, succ)}
                end
              end)

            do_bfs_shortest_path(dag, target, new_queue, new_visited)
        end
    end
  end

  @doc """
  Finds all paths between two nodes.

  Returns a list of paths, where each path is a list of node IDs.
  For large graphs with many paths, consider using `shortest_path/3` instead.

  ## Examples

      Dag.all_paths(dag, :a, :d)
      #=> [[:a, :b, :d], [:a, :c, :d]]
  """
  @spec all_paths(Dag.t(), node_id(), node_id()) :: [[node_id()]]
  def all_paths(%Dag{}, from, from), do: [[from]]
  def all_paths(%Dag{} = dag, from, to), do: do_all_paths(dag, from, to, [from], MapSet.new([from]))

  defp do_all_paths(dag, current, target, path, visited) do
    dag
    |> Dag.successors(current)
    |> Enum.flat_map(&find_paths_through(&1, dag, target, path, visited))
  end

  defp find_paths_through(target, _dag, target, path, _visited), do: [path ++ [target]]

  defp find_paths_through(succ, dag, target, path, visited) do
    case MapSet.member?(visited, succ) do
      true -> []
      false -> do_all_paths(dag, succ, target, path ++ [succ], MapSet.put(visited, succ))
    end
  end

  @doc """
  Returns the distance (hop count) between two nodes.

  Returns `{:ok, distance}` or `{:error, :no_path}`.

  ## Examples

      {:ok, 2} = Dag.distance(dag, :a, :c)
      {:error, :no_path} = Dag.distance(dag, :c, :a)
  """
  @spec distance(Dag.t(), node_id(), node_id()) :: {:ok, non_neg_integer()} | {:error, :no_path}
  def distance(%Dag{} = dag, from, to) do
    case shortest_path(dag, from, to) do
      {:ok, path} -> {:ok, length(path) - 1}
      {:error, _} = error -> error
    end
  end

  # ============================================
  # Graph Transformations
  # ============================================

  @doc """
  Computes the transitive reduction of the DAG.

  Removes redundant edges while maintaining reachability.
  An edge A→C is redundant if there exists a path A→B→...→C.

  ## Examples

      # Given: a→b, b→c, a→c (redundant)
      # Result: a→b, b→c
      reduced = Dag.transitive_reduction(dag)
  """
  @spec transitive_reduction(Dag.t()) :: Dag.t()
  def transitive_reduction(%Dag{} = dag) do
    # For each edge (u, v), check if there's another path from u to v
    edges_to_remove =
      dag.edges
      |> Enum.flat_map(fn {from, targets} ->
        Enum.filter(targets, fn {to, _data} ->
          # Remove this edge temporarily and check if path still exists
          other_successors = Enum.reject(Dag.successors(dag, from), &(&1 == to))

          Enum.any?(other_successors, fn intermediate ->
            path_exists?(dag, intermediate, to)
          end)
        end)
        |> Enum.map(fn {to, _} -> {from, to} end)
      end)

    Enum.reduce(edges_to_remove, dag, fn {from, to}, acc ->
      Dag.remove_edge(acc, from, to)
    end)
  end

  @doc """
  Reverses all edge directions in the DAG.

  ## Examples

      # Given: a→b→c
      # Result: c→b→a
      reversed = Dag.reverse(dag)
  """
  @spec reverse(Dag.t()) :: Dag.t()
  def reverse(%Dag{} = dag) do
    # Start with nodes only
    reversed = %Dag{
      nodes: dag.nodes,
      edges: %{},
      reverse_edges: %{},
      groups: dag.groups,
      metadata: dag.metadata
    }

    # Add reversed edges
    Enum.reduce(dag.edges, reversed, fn {from, targets}, acc ->
      Enum.reduce(targets, acc, fn {to, data}, inner_acc ->
        Dag.add_edge(inner_acc, to, from, data)
      end)
    end)
  end

  @doc """
  Extracts an induced subgraph containing only the specified nodes.

  Edges between the specified nodes are preserved.

  ## Examples

      subgraph = Dag.subgraph(dag, [:a, :b, :c])
  """
  @spec subgraph(Dag.t(), [node_id()]) :: Dag.t()
  def subgraph(%Dag{} = dag, node_ids) do
    node_set = MapSet.new(node_ids)

    # Filter nodes
    nodes =
      dag.nodes
      |> Enum.filter(fn {id, _} -> MapSet.member?(node_set, id) end)
      |> Map.new()

    # Filter edges - keep only edges where both endpoints are in the subgraph
    edges =
      dag.edges
      |> Enum.filter(fn {from, _} -> MapSet.member?(node_set, from) end)
      |> Enum.map(fn {from, targets} ->
        filtered_targets =
          Enum.filter(targets, fn {to, _} -> MapSet.member?(node_set, to) end)

        {from, filtered_targets}
      end)
      |> Enum.reject(fn {_, targets} -> targets == [] end)
      |> Map.new()

    # Filter reverse edges
    reverse_edges =
      dag.reverse_edges
      |> Enum.filter(fn {to, _} -> MapSet.member?(node_set, to) end)
      |> Enum.map(fn {to, sources} ->
        filtered_sources = Enum.filter(sources, &MapSet.member?(node_set, &1))
        {to, filtered_sources}
      end)
      |> Enum.reject(fn {_, sources} -> sources == [] end)
      |> Map.new()

    # Filter groups
    groups =
      dag.groups
      |> Enum.map(fn {group, members} ->
        {group, Enum.filter(members, &MapSet.member?(node_set, &1))}
      end)
      |> Enum.reject(fn {_, members} -> members == [] end)
      |> Map.new()

    %Dag{
      nodes: nodes,
      edges: edges,
      reverse_edges: reverse_edges,
      groups: groups,
      metadata: dag.metadata
    }
  end

  @doc """
  Filters nodes by a predicate function.

  Returns a new DAG containing only nodes for which the predicate returns true.

  ## Examples

      # Keep only nodes with status == :completed
      filtered = Dag.filter_nodes(dag, fn _id, data -> data[:status] == :completed end)
  """
  @spec filter_nodes(Dag.t(), (node_id(), map() -> boolean())) :: Dag.t()
  def filter_nodes(%Dag{} = dag, predicate) when is_function(predicate, 2) do
    matching_ids =
      dag.nodes
      |> Enum.filter(fn {id, data} -> predicate.(id, data) end)
      |> Enum.map(fn {id, _} -> id end)

    subgraph(dag, matching_ids)
  end

  # ============================================
  # Node/Edge Introspection
  # ============================================

  @doc """
  Returns the in-degree of a node (number of incoming edges).

  ## Examples

      Dag.in_degree(dag, :c) #=> 2
  """
  @spec in_degree(Dag.t(), node_id()) :: non_neg_integer()
  def in_degree(%Dag{} = dag, id) do
    dag.reverse_edges
    |> Map.get(id, [])
    |> length()
  end

  @doc """
  Returns the out-degree of a node (number of outgoing edges).

  ## Examples

      Dag.out_degree(dag, :a) #=> 2
  """
  @spec out_degree(Dag.t(), node_id()) :: non_neg_integer()
  def out_degree(%Dag{} = dag, id) do
    dag.edges
    |> Map.get(id, [])
    |> length()
  end

  @doc """
  Gets the data associated with an edge.

  ## Examples

      {:ok, %{weight: 10}} = Dag.get_edge(dag, :a, :b)
      {:error, :not_found} = Dag.get_edge(dag, :a, :unknown)
  """
  @spec get_edge(Dag.t(), node_id(), node_id()) :: {:ok, map()} | {:error, :not_found}
  def get_edge(%Dag{} = dag, from, to) do
    dag.edges
    |> Map.get(from, [])
    |> Enum.find(fn {target, _} -> target == to end)
    |> case do
      nil -> {:error, :not_found}
      {_, data} -> {:ok, data}
    end
  end

  @doc """
  Updates the data for an edge.

  ## Examples

      dag = Dag.update_edge(dag, :a, :b, fn data -> Map.put(data, :visited, true) end)
  """
  @spec update_edge(Dag.t(), node_id(), node_id(), (map() -> map())) :: Dag.t()
  def update_edge(%Dag{} = dag, from, to, fun) when is_function(fun, 1) do
    edges =
      Map.update(dag.edges, from, [], fn targets ->
        Enum.map(targets, fn
          {^to, data} -> {to, fun.(data)}
          other -> other
        end)
      end)

    %{dag | edges: edges}
  end

  @doc """
  Returns all edges as a list of tuples.

  ## Examples

      Dag.edges(dag)
      #=> [{:a, :b, %{weight: 10}}, {:b, :c, %{}}]
  """
  @spec edges(Dag.t()) :: [{node_id(), node_id(), map()}]
  def edges(%Dag{} = dag) do
    dag.edges
    |> Enum.flat_map(fn {from, targets} ->
      Enum.map(targets, fn {to, data} -> {from, to, data} end)
    end)
  end

  # ============================================
  # Graph Composition
  # ============================================

  @doc """
  Merges two DAGs together.

  Nodes with the same ID have their data merged (dag2 takes precedence).
  All edges from both DAGs are included.

  ## Examples

      merged = Dag.merge(dag1, dag2)
  """
  @spec merge(Dag.t(), Dag.t()) :: Dag.t()
  def merge(%Dag{} = dag1, %Dag{} = dag2) do
    # Merge nodes (dag2 takes precedence)
    nodes = Map.merge(dag1.nodes, dag2.nodes)

    # Merge edges
    edges =
      Map.merge(dag1.edges, dag2.edges, fn _key, targets1, targets2 ->
        # Combine and deduplicate by target
        all_targets = targets1 ++ targets2

        all_targets
        |> Enum.group_by(fn {to, _} -> to end)
        |> Enum.map(fn {to, list} ->
          # Take the last data (from dag2 if duplicate)
          {_, data} = List.last(list)
          {to, data}
        end)
      end)

    # Merge reverse edges
    reverse_edges =
      Map.merge(dag1.reverse_edges, dag2.reverse_edges, fn _key, sources1, sources2 ->
        Enum.uniq(sources1 ++ sources2)
      end)

    # Merge groups
    groups =
      Map.merge(dag1.groups, dag2.groups, fn _key, members1, members2 ->
        Enum.uniq(members1 ++ members2)
      end)

    # Merge metadata
    metadata = Map.merge(dag1.metadata, dag2.metadata)

    %Dag{
      nodes: nodes,
      edges: edges,
      reverse_edges: reverse_edges,
      groups: groups,
      metadata: metadata
    }
  end

  @doc """
  Concatenates two DAGs by connecting leaves of dag1 to roots of dag2.

  ## Examples

      # dag1: a→b, dag2: c→d
      # Result: a→b→c→d (b connected to c)
      chained = Dag.concat(dag1, dag2)
  """
  @spec concat(Dag.t(), Dag.t()) :: Dag.t()
  def concat(%Dag{} = dag1, %Dag{} = dag2) do
    # First merge the DAGs
    merged = merge(dag1, dag2)

    # Find leaves of dag1 and roots of dag2
    dag1_leaves = leaves(dag1)
    dag2_roots = roots(dag2)

    # Connect each leaf to each root
    Enum.reduce(dag1_leaves, merged, fn leaf, acc ->
      Enum.reduce(dag2_roots, acc, fn root, inner_acc ->
        Dag.add_edge(inner_acc, leaf, root)
      end)
    end)
  end

  # ============================================
  # Serialization
  # ============================================

  @doc """
  Serializes the DAG to a map.

  ## Examples

      map = Dag.to_map(dag)
      #=> %{nodes: [...], edges: [...], groups: %{}, metadata: %{}}
  """
  @spec to_map(Dag.t()) :: map()
  def to_map(%Dag{} = dag) do
    %{
      nodes: Enum.map(dag.nodes, fn {id, data} -> %{id: id, data: data} end),
      edges: edges(dag) |> Enum.map(fn {from, to, data} -> %{from: from, to: to, data: data} end),
      groups: dag.groups,
      metadata: dag.metadata
    }
  end

  @doc """
  Deserializes a DAG from a map.

  ## Examples

      {:ok, dag} = Dag.from_map(map)
  """
  @spec from_map(map()) :: {:ok, Dag.t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    try do
      nodes = Map.get(map, :nodes, Map.get(map, "nodes", []))
      edges = Map.get(map, :edges, Map.get(map, "edges", []))
      groups = Map.get(map, :groups, Map.get(map, "groups", %{}))
      metadata = Map.get(map, :metadata, Map.get(map, "metadata", %{}))

      dag = Dag.new(metadata: metadata)

      # Add nodes
      dag =
        Enum.reduce(nodes, dag, fn node, acc ->
          id = Map.get(node, :id, Map.get(node, "id"))
          data = Map.get(node, :data, Map.get(node, "data", %{}))
          Dag.add_node(acc, id, data)
        end)

      # Add edges
      dag =
        Enum.reduce(edges, dag, fn edge, acc ->
          from = Map.get(edge, :from, Map.get(edge, "from"))
          to = Map.get(edge, :to, Map.get(edge, "to"))
          data = Map.get(edge, :data, Map.get(edge, "data", %{}))
          Dag.add_edge(acc, from, to, data)
        end)

      # Add groups
      dag =
        Enum.reduce(groups, dag, fn {group_name, members}, acc ->
          group_atom = to_atom(group_name)
          Dag.add_to_group(acc, group_atom, members)
        end)

      case validate(dag) do
        :ok -> {:ok, dag}
        error -> error
      end
    rescue
      e -> {:error, {:deserialization_failed, Exception.message(e)}}
    end
  end

  # ============================================
  # Weight-Based Algorithms
  # ============================================

  @doc """
  Computes the critical path (longest weighted path) through the DAG.

  The weight function extracts a numeric weight from edge data.
  Returns `{total_weight, path}` for the critical path.

  ## Examples

      # With edge weights stored as %{duration: N}
      {total, path} = Dag.critical_path(dag, fn edge_data -> edge_data[:duration] || 1 end)
  """
  @spec critical_path(Dag.t(), (map() -> number())) :: {number(), [node_id()]}
  def critical_path(%Dag{} = dag, weight_fn) when is_function(weight_fn, 1) do
    case topological_sort(dag) do
      {:error, _} ->
        {0, []}

      {:ok, sorted} ->
        # distances[node] = {max_distance_to_node, predecessor}
        distances =
          Enum.reduce(sorted, %{}, fn node, acc ->
            predecessors = Dag.predecessors(dag, node)

            case predecessors do
              [] ->
                Map.put(acc, node, {0, nil})

              preds ->
                {max_dist, best_pred} =
                  Enum.reduce(preds, {0, nil}, fn pred, {best_dist, best_p} ->
                    {pred_dist, _} = Map.get(acc, pred, {0, nil})
                    {:ok, edge_data} = get_edge(dag, pred, node)
                    edge_weight = weight_fn.(edge_data)
                    new_dist = pred_dist + edge_weight

                    case new_dist > best_dist do
                      true -> {new_dist, pred}
                      false -> {best_dist, best_p}
                    end
                  end)

                Map.put(acc, node, {max_dist, best_pred})
            end
          end)

        # Find the node with maximum distance (end of critical path)
        {end_node, {max_weight, _}} =
          distances
          |> Enum.max_by(fn {_, {dist, _}} -> dist end, fn -> {nil, {0, nil}} end)

        # Reconstruct path
        path = reconstruct_path(distances, end_node, [])

        {max_weight, path}
    end
  end

  defp reconstruct_path(_distances, nil, acc), do: acc

  defp reconstruct_path(distances, node, acc) do
    {_, pred} = Map.get(distances, node, {0, nil})
    reconstruct_path(distances, pred, [node | acc])
  end

  @doc """
  Finds the shortest weighted path between two nodes (Dijkstra's algorithm).

  Returns `{:ok, {total_weight, path}}` or `{:error, :no_path}`.

  ## Examples

      {:ok, {weight, path}} = Dag.shortest_weighted_path(dag, :a, :d, fn data -> data[:cost] || 1 end)
  """
  @spec shortest_weighted_path(Dag.t(), node_id(), node_id(), (map() -> number())) ::
          {:ok, {number(), [node_id()]}} | {:error, :no_path}
  def shortest_weighted_path(%Dag{}, from, from, _weight_fn), do: {:ok, {0, [from]}}

  def shortest_weighted_path(%Dag{} = dag, from, to, weight_fn) when is_function(weight_fn, 1) do
    dijkstra(dag, from, to, weight_fn)
  end

  defp dijkstra(dag, from, to, weight_fn) do
    # distances[node] = {distance, predecessor}
    distances = %{from => {0, nil}}

    # Priority queue as a sorted list of {distance, node}
    # In production, use a proper heap
    queue = [{0, from}]
    visited = MapSet.new()

    do_dijkstra(dag, to, weight_fn, queue, distances, visited)
  end

  defp do_dijkstra(_dag, _to, _weight_fn, [], _distances, _visited) do
    {:error, :no_path}
  end

  defp do_dijkstra(dag, to, weight_fn, [{current_dist, current} | rest], distances, visited) do
    case {current == to, MapSet.member?(visited, current)} do
      {true, _} ->
        path = reconstruct_path(distances, to, [])
        {:ok, {current_dist, path}}

      {false, true} ->
        do_dijkstra(dag, to, weight_fn, rest, distances, visited)

      {false, false} ->
        new_visited = MapSet.put(visited, current)
        successors = Dag.successors(dag, current)

        {new_queue, new_distances} =
          Enum.reduce(successors, {rest, distances}, fn succ, {q, d} ->
            {:ok, edge_data} = get_edge(dag, current, succ)
            edge_weight = weight_fn.(edge_data)
            new_dist = current_dist + edge_weight
            current_best = d |> Map.get(succ, {Float.max_finite(), nil}) |> elem(0)

            case new_dist < current_best do
              true ->
                new_d = Map.put(d, succ, {new_dist, current})
                new_q = insert_sorted(q, {new_dist, succ})
                {new_q, new_d}

              false ->
                {q, d}
            end
          end)

        do_dijkstra(dag, to, weight_fn, new_queue, new_distances, new_visited)
    end
  end

  defp insert_sorted([], item), do: [item]

  defp insert_sorted([{d, _} = head | tail], {new_d, _} = item) when new_d <= d do
    [item, head | tail]
  end

  defp insert_sorted([head | tail], item) do
    [head | insert_sorted(tail, item)]
  end

  # ============================================
  # Validation Enhancements
  # ============================================

  @doc """
  Checks if the DAG is a tree (single root, no node has multiple parents).

  ## Examples

      Dag.is_tree?(dag) #=> true
  """
  @spec is_tree?(Dag.t()) :: boolean()
  def is_tree?(%Dag{} = dag) do
    case roots(dag) do
      [_single_root] -> all_nodes_have_at_most_one_parent?(dag)
      _ -> false
    end
  end

  defp all_nodes_have_at_most_one_parent?(%Dag{nodes: nodes} = dag) do
    nodes
    |> Map.keys()
    |> Enum.all?(fn id ->
      case Dag.predecessors(dag, id) do
        [] -> true
        [_single] -> true
        _ -> false
      end
    end)
  end

  @doc """
  Checks if the DAG is a forest (collection of trees, no node has multiple parents).

  ## Examples

      Dag.is_forest?(dag) #=> true
  """
  @spec is_forest?(Dag.t()) :: boolean()
  def is_forest?(%Dag{} = dag), do: all_nodes_have_at_most_one_parent?(dag)

  @doc """
  Returns the weakly connected components of the DAG.

  Each component is a list of node IDs that are connected
  (ignoring edge direction).

  ## Examples

      Dag.connected_components(dag)
      #=> [[:a, :b, :c], [:d, :e]]
  """
  @spec connected_components(Dag.t()) :: [[node_id()]]
  def connected_components(%Dag{} = dag) do
    {components, _} =
      dag
      |> Dag.node_ids()
      |> Enum.reduce({[], MapSet.new()}, fn node, {comps, visited} ->
        case MapSet.member?(visited, node) do
          true ->
            {comps, visited}

          false ->
            component = flood_fill_component(dag, node, MapSet.new())
            new_visited = MapSet.union(visited, component)
            {[MapSet.to_list(component) | comps], new_visited}
        end
      end)

    components
  end

  defp flood_fill_component(dag, node, visited) do
    case MapSet.member?(visited, node) do
      true ->
        visited

      false ->
        visited = MapSet.put(visited, node)
        neighbors = Dag.successors(dag, node) ++ Dag.predecessors(dag, node)

        Enum.reduce(neighbors, visited, fn neighbor, acc ->
          flood_fill_component(dag, neighbor, acc)
        end)
    end
  end

  defp to_atom(name) when is_binary(name), do: String.to_existing_atom(name)
  defp to_atom(name) when is_atom(name), do: name
end
