defmodule Dag do
  @moduledoc """
  A generic Directed Acyclic Graph (DAG) library.

  Provides a composable, immutable DAG data structure with:
  - Node and edge management
  - Topological sorting (Kahn's algorithm)
  - Cycle detection (DFS-based)
  - Dependency validation
  - Visualization (Mermaid, DOT/Graphviz)

  ## Quick Start

      # Create a DAG
      dag = Dag.new()
            |> Dag.add_node(:a, %{label: "Step A"})
            |> Dag.add_node(:b, %{label: "Step B"})
            |> Dag.add_node(:c, %{label: "Step C"})
            |> Dag.add_edge(:a, :b)  # a -> b (b depends on a)
            |> Dag.add_edge(:b, :c)  # b -> c (c depends on b)

      # Validate and sort
      {:ok, sorted} = Dag.topological_sort(dag)
      #=> [:a, :b, :c]

      # Visualize
      Dag.to_mermaid(dag)
      #=> "graph TD\\n  a --> b\\n  b --> c"

  ## Node Data

  Nodes can store arbitrary metadata:

      dag = Dag.new()
            |> Dag.add_node(:task1, %{
                 label: "Process Data",
                 timeout: 5000,
                 retries: 3
               })

      {:ok, data} = Dag.get_node(dag, :task1)
      data.label #=> "Process Data"

  ## Edge Data

  Edges can also store metadata:

      dag = Dag.add_edge(dag, :a, :b, %{weight: 10, condition: :always})

  ## Groups

  Nodes can be organized into groups for parallel execution patterns:

      dag = Dag.new()
            |> Dag.add_node(:fetch, %{})
            |> Dag.add_node(:process_a, %{})
            |> Dag.add_node(:process_b, %{})
            |> Dag.add_to_group(:parallel_processing, [:process_a, :process_b])

  ## Validation

      case Dag.validate(dag) do
        :ok -> # DAG is valid
        {:error, {:cycle_detected, path}} -> # Has cycle
        {:error, {:missing_node, node}} -> # Edge references missing node
      end
  """

  alias Dag.{Algorithms, Visualization}

  @type node_id :: atom() | String.t()
  @type node_data :: map()
  @type edge_data :: map()

  @type t :: %__MODULE__{
          nodes: %{node_id() => node_data()},
          edges: %{node_id() => [{node_id(), edge_data()}]},
          reverse_edges: %{node_id() => [node_id()]},
          groups: %{atom() => [node_id()]},
          metadata: map()
        }

  defstruct nodes: %{},
            edges: %{},
            reverse_edges: %{},
            groups: %{},
            metadata: %{}

  # ============================================
  # Construction
  # ============================================

  @doc """
  Creates a new empty DAG.

  ## Options

  - `:metadata` - Arbitrary metadata to attach to the DAG

  ## Examples

      Dag.new()
      Dag.new(metadata: %{name: :my_workflow, version: 1})
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a DAG from a list of nodes and edges.

  ## Examples

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
  """
  @spec from_definition(keyword()) :: {:ok, t()} | {:error, term()}
  def from_definition(opts) do
    nodes = Keyword.get(opts, :nodes, [])
    edges = Keyword.get(opts, :edges, [])
    metadata = Keyword.get(opts, :metadata, %{})

    dag = new(metadata: metadata)

    # Add nodes
    dag =
      Enum.reduce(nodes, dag, fn
        {id, data}, acc -> add_node(acc, id, data)
        id, acc when is_atom(id) or is_binary(id) -> add_node(acc, id)
      end)

    # Add edges
    dag =
      Enum.reduce(edges, dag, fn
        {from, to, data}, acc -> add_edge(acc, from, to, data)
        {from, to}, acc -> add_edge(acc, from, to)
      end)

    case validate(dag) do
      :ok -> {:ok, dag}
      error -> error
    end
  end

  @doc """
  Creates a DAG from a definition, raising on error.
  """
  @spec from_definition!(keyword()) :: t()
  def from_definition!(opts) do
    case from_definition(opts) do
      {:ok, dag} -> dag
      {:error, reason} -> raise ArgumentError, "Invalid DAG: #{inspect(reason)}"
    end
  end

  # ============================================
  # Node Operations
  # ============================================

  @doc """
  Adds a node to the DAG.

  If the node already exists, its data is updated.

  ## Examples

      dag = Dag.new()
            |> Dag.add_node(:a)
            |> Dag.add_node(:b, %{label: "Node B", weight: 10})
  """
  @spec add_node(t(), node_id(), node_data()) :: t()
  def add_node(%__MODULE__{} = dag, id, data \\ %{}) do
    %{dag | nodes: Map.put(dag.nodes, id, data)}
  end

  @doc """
  Adds multiple nodes to the DAG.

  ## Examples

      dag = Dag.add_nodes(dag, [:a, :b, :c])
      dag = Dag.add_nodes(dag, [a: %{label: "A"}, b: %{label: "B"}])
  """
  @spec add_nodes(t(), [node_id() | {node_id(), node_data()}]) :: t()
  def add_nodes(%__MODULE__{} = dag, nodes) do
    Enum.reduce(nodes, dag, fn
      {id, data}, acc -> add_node(acc, id, data)
      id, acc -> add_node(acc, id)
    end)
  end

  @doc """
  Removes a node and all its connected edges from the DAG.

  ## Examples

      dag = Dag.remove_node(dag, :a)
  """
  @spec remove_node(t(), node_id()) :: t()
  def remove_node(%__MODULE__{} = dag, id) do
    # Remove the node
    nodes = Map.delete(dag.nodes, id)

    # Remove outgoing edges from this node
    edges = Map.delete(dag.edges, id)

    # Remove incoming edges to this node
    edges =
      Map.new(edges, fn {from, targets} ->
        {from, Enum.reject(targets, fn {to, _} -> to == id end)}
      end)

    # Update reverse edges
    reverse_edges = Map.delete(dag.reverse_edges, id)

    reverse_edges =
      Map.new(reverse_edges, fn {to, sources} ->
        {to, Enum.reject(sources, &(&1 == id))}
      end)

    # Remove from groups
    groups =
      Map.new(dag.groups, fn {group, members} ->
        {group, Enum.reject(members, &(&1 == id))}
      end)

    %{dag | nodes: nodes, edges: edges, reverse_edges: reverse_edges, groups: groups}
  end

  @doc """
  Gets the data associated with a node.

  ## Examples

      {:ok, %{label: "A"}} = Dag.get_node(dag, :a)
      {:error, :not_found} = Dag.get_node(dag, :unknown)
  """
  @spec get_node(t(), node_id()) :: {:ok, node_data()} | {:error, :not_found}
  def get_node(%__MODULE__{} = dag, id) do
    case Map.fetch(dag.nodes, id) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Updates the data for a node.

  ## Examples

      dag = Dag.update_node(dag, :a, fn data -> Map.put(data, :visited, true) end)
  """
  @spec update_node(t(), node_id(), (node_data() -> node_data())) :: t()
  def update_node(%__MODULE__{} = dag, id, fun) when is_function(fun, 1) do
    case Map.fetch(dag.nodes, id) do
      {:ok, data} -> %{dag | nodes: Map.put(dag.nodes, id, fun.(data))}
      :error -> dag
    end
  end

  @doc """
  Checks if a node exists in the DAG.

  ## Examples

      Dag.has_node?(dag, :a) #=> true
      Dag.has_node?(dag, :unknown) #=> false
  """
  @spec has_node?(t(), node_id()) :: boolean()
  def has_node?(%__MODULE__{} = dag, id) do
    Map.has_key?(dag.nodes, id)
  end

  @doc """
  Returns all node IDs in the DAG.

  ## Examples

      Dag.node_ids(dag) #=> [:a, :b, :c]
  """
  @spec node_ids(t()) :: [node_id()]
  def node_ids(%__MODULE__{} = dag) do
    Map.keys(dag.nodes)
  end

  @doc """
  Returns the number of nodes in the DAG.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{} = dag) do
    map_size(dag.nodes)
  end

  # ============================================
  # Edge Operations
  # ============================================

  @doc """
  Adds a directed edge from one node to another.

  The edge represents a dependency: `from -> to` means `to` depends on `from`,
  i.e., `from` must complete before `to` can start.

  Missing nodes are automatically created with empty data.

  ## Examples

      # b depends on a (a must complete first)
      dag = Dag.add_edge(dag, :a, :b)

      # With edge metadata
      dag = Dag.add_edge(dag, :a, :b, %{weight: 10})
  """
  @spec add_edge(t(), node_id(), node_id(), edge_data()) :: t()
  def add_edge(%__MODULE__{} = dag, from, to, data \\ %{}) do
    # Ensure both nodes exist
    dag =
      dag
      |> ensure_node(from)
      |> ensure_node(to)

    # Add forward edge (from -> to)
    edges = Map.update(dag.edges, from, [{to, data}], &[{to, data} | &1])

    # Add reverse edge (for efficient lookup)
    reverse_edges = Map.update(dag.reverse_edges, to, [from], &[from | &1])

    %{dag | edges: edges, reverse_edges: reverse_edges}
  end

  @doc """
  Adds multiple edges to the DAG.

  ## Examples

      dag = Dag.add_edges(dag, [
        {:a, :b},
        {:b, :c},
        {:a, :c, %{weight: 5}}
      ])
  """
  @spec add_edges(t(), [{node_id(), node_id()} | {node_id(), node_id(), edge_data()}]) :: t()
  def add_edges(%__MODULE__{} = dag, edges) do
    Enum.reduce(edges, dag, fn
      {from, to, data}, acc -> add_edge(acc, from, to, data)
      {from, to}, acc -> add_edge(acc, from, to)
    end)
  end

  @doc """
  Removes an edge from the DAG.

  ## Examples

      dag = Dag.remove_edge(dag, :a, :b)
  """
  @spec remove_edge(t(), node_id(), node_id()) :: t()
  def remove_edge(%__MODULE__{} = dag, from, to) do
    edges =
      Map.update(dag.edges, from, [], fn targets ->
        Enum.reject(targets, fn {target, _} -> target == to end)
      end)

    reverse_edges =
      Map.update(dag.reverse_edges, to, [], fn sources ->
        Enum.reject(sources, &(&1 == from))
      end)

    %{dag | edges: edges, reverse_edges: reverse_edges}
  end

  @doc """
  Checks if an edge exists between two nodes.

  ## Examples

      Dag.has_edge?(dag, :a, :b) #=> true
  """
  @spec has_edge?(t(), node_id(), node_id()) :: boolean()
  def has_edge?(%__MODULE__{} = dag, from, to) do
    dag.edges
    |> Map.get(from, [])
    |> Enum.any?(fn {target, _} -> target == to end)
  end

  @doc """
  Gets all outgoing edges from a node (nodes that depend on this node).

  ## Examples

      Dag.successors(dag, :a) #=> [:b, :c]
  """
  @spec successors(t(), node_id()) :: [node_id()]
  def successors(%__MODULE__{} = dag, id) do
    dag.edges
    |> Map.get(id, [])
    |> Enum.map(fn {to, _} -> to end)
  end

  @doc """
  Gets all incoming edges to a node (nodes this node depends on).

  ## Examples

      Dag.predecessors(dag, :c) #=> [:a, :b]
  """
  @spec predecessors(t(), node_id()) :: [node_id()]
  def predecessors(%__MODULE__{} = dag, id) do
    Map.get(dag.reverse_edges, id, [])
  end

  @doc """
  Returns the number of edges in the DAG.
  """
  @spec edge_count(t()) :: non_neg_integer()
  def edge_count(%__MODULE__{} = dag) do
    dag.edges
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  # ============================================
  # Group Operations
  # ============================================

  @doc """
  Adds nodes to a group.

  Groups are used for organizing parallel execution patterns.

  ## Examples

      dag = Dag.add_to_group(dag, :parallel_tasks, [:task_a, :task_b, :task_c])
  """
  @spec add_to_group(t(), atom(), [node_id()]) :: t()
  def add_to_group(%__MODULE__{} = dag, group_name, node_ids) when is_atom(group_name) do
    current = Map.get(dag.groups, group_name, [])
    %{dag | groups: Map.put(dag.groups, group_name, Enum.uniq(node_ids ++ current))}
  end

  @doc """
  Removes a node from a group.
  """
  @spec remove_from_group(t(), atom(), node_id()) :: t()
  def remove_from_group(%__MODULE__{} = dag, group_name, node_id) do
    groups =
      Map.update(dag.groups, group_name, [], fn members ->
        Enum.reject(members, &(&1 == node_id))
      end)

    %{dag | groups: groups}
  end

  @doc """
  Gets all nodes in a group.

  ## Examples

      Dag.get_group(dag, :parallel_tasks) #=> [:task_a, :task_b]
  """
  @spec get_group(t(), atom()) :: [node_id()]
  def get_group(%__MODULE__{} = dag, group_name) do
    Map.get(dag.groups, group_name, [])
  end

  # ============================================
  # Algorithms (delegated)
  # ============================================

  @doc """
  Performs topological sort on the DAG.

  Returns nodes in an order where each node comes before all nodes that depend on it.

  ## Examples

      {:ok, [:a, :b, :c]} = Dag.topological_sort(dag)
      {:error, :cycle_detected} = Dag.topological_sort(cyclic_dag)
  """
  @spec topological_sort(t()) :: {:ok, [node_id()]} | {:error, :cycle_detected}
  defdelegate topological_sort(dag), to: Algorithms

  @doc """
  Detects if the graph contains a cycle.

  Returns `nil` if no cycle exists, or the cycle path if one is found.

  ## Examples

      nil = Dag.detect_cycle(dag)
      [:a, :b, :a] = Dag.detect_cycle(cyclic_dag)
  """
  @spec detect_cycle(t()) :: [node_id()] | nil
  defdelegate detect_cycle(dag), to: Algorithms

  @doc """
  Validates the DAG structure.

  Checks for:
  - Cycles
  - Edges referencing non-existent nodes

  ## Examples

      :ok = Dag.validate(dag)
      {:error, {:cycle_detected, [:a, :b, :a]}} = Dag.validate(cyclic_dag)
  """
  @spec validate(t()) :: :ok | {:error, term()}
  defdelegate validate(dag), to: Algorithms

  @doc """
  Returns all nodes that have no predecessors (entry points).

  ## Examples

      Dag.roots(dag) #=> [:a]
  """
  @spec roots(t()) :: [node_id()]
  defdelegate roots(dag), to: Algorithms

  @doc """
  Returns all nodes that have no successors (exit points).

  ## Examples

      Dag.leaves(dag) #=> [:c, :d]
  """
  @spec leaves(t()) :: [node_id()]
  defdelegate leaves(dag), to: Algorithms

  @doc """
  Returns all ancestors of a node (transitive predecessors).

  ## Examples

      Dag.ancestors(dag, :c) #=> [:a, :b]
  """
  @spec ancestors(t(), node_id()) :: [node_id()]
  defdelegate ancestors(dag, id), to: Algorithms

  @doc """
  Returns all descendants of a node (transitive successors).

  ## Examples

      Dag.descendants(dag, :a) #=> [:b, :c, :d]
  """
  @spec descendants(t(), node_id()) :: [node_id()]
  defdelegate descendants(dag, id), to: Algorithms

  @doc """
  Computes the longest path from roots to each node (critical path).

  ## Examples

      Dag.longest_paths(dag) #=> %{a: 0, b: 1, c: 2, d: 2}
  """
  @spec longest_paths(t()) :: %{node_id() => non_neg_integer()}
  defdelegate longest_paths(dag), to: Algorithms

  @doc """
  Returns nodes at a specific depth level.

  ## Examples

      Dag.nodes_at_level(dag, 0) #=> [:a]  # roots
      Dag.nodes_at_level(dag, 1) #=> [:b, :c]
  """
  @spec nodes_at_level(t(), non_neg_integer()) :: [node_id()]
  defdelegate nodes_at_level(dag, level), to: Algorithms

  # ============================================
  # Path Operations (delegated)
  # ============================================

  @doc """
  Checks if a path exists between two nodes.

  ## Examples

      Dag.path_exists?(dag, :a, :c) #=> true
      Dag.path_exists?(dag, :c, :a) #=> false
  """
  @spec path_exists?(t(), node_id(), node_id()) :: boolean()
  defdelegate path_exists?(dag, from, to), to: Algorithms

  @doc """
  Finds the shortest path between two nodes (by hop count).

  Returns `{:ok, path}` where path is a list of node IDs from source to target,
  or `{:error, :no_path}` if no path exists.

  ## Examples

      {:ok, [:a, :b, :c]} = Dag.shortest_path(dag, :a, :c)
      {:error, :no_path} = Dag.shortest_path(dag, :c, :a)
  """
  @spec shortest_path(t(), node_id(), node_id()) :: {:ok, [node_id()]} | {:error, :no_path}
  defdelegate shortest_path(dag, from, to), to: Algorithms

  @doc """
  Finds all paths between two nodes.

  Returns a list of paths, where each path is a list of node IDs.
  For large graphs with many paths, consider using `shortest_path/3` instead.

  ## Examples

      Dag.all_paths(dag, :a, :d)
      #=> [[:a, :b, :d], [:a, :c, :d]]
  """
  @spec all_paths(t(), node_id(), node_id()) :: [[node_id()]]
  defdelegate all_paths(dag, from, to), to: Algorithms

  @doc """
  Returns the distance (hop count) between two nodes.

  Returns `{:ok, distance}` or `{:error, :no_path}`.

  ## Examples

      {:ok, 2} = Dag.distance(dag, :a, :c)
      {:error, :no_path} = Dag.distance(dag, :c, :a)
  """
  @spec distance(t(), node_id(), node_id()) :: {:ok, non_neg_integer()} | {:error, :no_path}
  defdelegate distance(dag, from, to), to: Algorithms

  # ============================================
  # Graph Transformations (delegated)
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
  @spec transitive_reduction(t()) :: t()
  defdelegate transitive_reduction(dag), to: Algorithms

  @doc """
  Reverses all edge directions in the DAG.

  ## Examples

      # Given: a→b→c
      # Result: c→b→a
      reversed = Dag.reverse(dag)
  """
  @spec reverse(t()) :: t()
  defdelegate reverse(dag), to: Algorithms

  @doc """
  Extracts an induced subgraph containing only the specified nodes.

  Edges between the specified nodes are preserved.

  ## Examples

      subgraph = Dag.subgraph(dag, [:a, :b, :c])
  """
  @spec subgraph(t(), [node_id()]) :: t()
  defdelegate subgraph(dag, node_ids), to: Algorithms

  @doc """
  Filters nodes by a predicate function.

  Returns a new DAG containing only nodes for which the predicate returns true.

  ## Examples

      # Keep only nodes with status == :completed
      filtered = Dag.filter_nodes(dag, fn _id, data -> data[:status] == :completed end)
  """
  @spec filter_nodes(t(), (node_id(), map() -> boolean())) :: t()
  defdelegate filter_nodes(dag, predicate), to: Algorithms

  # ============================================
  # Node/Edge Introspection (delegated)
  # ============================================

  @doc """
  Returns the in-degree of a node (number of incoming edges).

  ## Examples

      Dag.in_degree(dag, :c) #=> 2
  """
  @spec in_degree(t(), node_id()) :: non_neg_integer()
  defdelegate in_degree(dag, id), to: Algorithms

  @doc """
  Returns the out-degree of a node (number of outgoing edges).

  ## Examples

      Dag.out_degree(dag, :a) #=> 2
  """
  @spec out_degree(t(), node_id()) :: non_neg_integer()
  defdelegate out_degree(dag, id), to: Algorithms

  @doc """
  Gets the data associated with an edge.

  ## Examples

      {:ok, %{weight: 10}} = Dag.get_edge(dag, :a, :b)
      {:error, :not_found} = Dag.get_edge(dag, :a, :unknown)
  """
  @spec get_edge(t(), node_id(), node_id()) :: {:ok, map()} | {:error, :not_found}
  defdelegate get_edge(dag, from, to), to: Algorithms

  @doc """
  Updates the data for an edge.

  ## Examples

      dag = Dag.update_edge(dag, :a, :b, fn data -> Map.put(data, :visited, true) end)
  """
  @spec update_edge(t(), node_id(), node_id(), (map() -> map())) :: t()
  defdelegate update_edge(dag, from, to, fun), to: Algorithms

  @doc """
  Returns all edges as a list of tuples.

  ## Examples

      Dag.edges(dag)
      #=> [{:a, :b, %{weight: 10}}, {:b, :c, %{}}]
  """
  @spec edges(t()) :: [{node_id(), node_id(), map()}]
  defdelegate edges(dag), to: Algorithms

  # ============================================
  # Graph Composition (delegated)
  # ============================================

  @doc """
  Merges two DAGs together.

  Nodes with the same ID have their data merged (dag2 takes precedence).
  All edges from both DAGs are included.

  ## Examples

      merged = Dag.merge(dag1, dag2)
  """
  @spec merge(t(), t()) :: t()
  defdelegate merge(dag1, dag2), to: Algorithms

  @doc """
  Concatenates two DAGs by connecting leaves of dag1 to roots of dag2.

  ## Examples

      # dag1: a→b, dag2: c→d
      # Result: a→b→c→d (b connected to c)
      chained = Dag.concat(dag1, dag2)
  """
  @spec concat(t(), t()) :: t()
  defdelegate concat(dag1, dag2), to: Algorithms

  # ============================================
  # Serialization (delegated)
  # ============================================

  @doc """
  Serializes the DAG to a map.

  ## Examples

      map = Dag.to_map(dag)
      #=> %{nodes: [...], edges: [...], groups: %{}, metadata: %{}}
  """
  @spec to_map(t()) :: map()
  defdelegate to_map(dag), to: Algorithms

  @doc """
  Deserializes a DAG from a map.

  ## Examples

      {:ok, dag} = Dag.from_map(map)
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  defdelegate from_map(map), to: Algorithms

  # ============================================
  # Weight-Based Algorithms (delegated)
  # ============================================

  @doc """
  Computes the critical path (longest weighted path) through the DAG.

  The weight function extracts a numeric weight from edge data.
  Returns `{total_weight, path}` for the critical path.

  ## Examples

      # With edge weights stored as %{duration: N}
      {total, path} = Dag.critical_path(dag, fn edge_data -> edge_data[:duration] || 1 end)
  """
  @spec critical_path(t(), (map() -> number())) :: {number(), [node_id()]}
  defdelegate critical_path(dag, weight_fn), to: Algorithms

  @doc """
  Finds the shortest weighted path between two nodes (Dijkstra's algorithm).

  Returns `{:ok, {total_weight, path}}` or `{:error, :no_path}`.

  ## Examples

      {:ok, {weight, path}} = Dag.shortest_weighted_path(dag, :a, :d, fn data -> data[:cost] || 1 end)
  """
  @spec shortest_weighted_path(t(), node_id(), node_id(), (map() -> number())) ::
          {:ok, {number(), [node_id()]}} | {:error, :no_path}
  defdelegate shortest_weighted_path(dag, from, to, weight_fn), to: Algorithms

  # ============================================
  # Validation Enhancements (delegated)
  # ============================================

  @doc """
  Checks if the DAG is a tree (single root, no node has multiple parents).

  ## Examples

      Dag.is_tree?(dag) #=> true
  """
  @spec is_tree?(t()) :: boolean()
  defdelegate is_tree?(dag), to: Algorithms

  @doc """
  Checks if the DAG is a forest (collection of trees, no node has multiple parents).

  ## Examples

      Dag.is_forest?(dag) #=> true
  """
  @spec is_forest?(t()) :: boolean()
  defdelegate is_forest?(dag), to: Algorithms

  @doc """
  Returns the weakly connected components of the DAG.

  Each component is a list of node IDs that are connected
  (ignoring edge direction).

  ## Examples

      Dag.connected_components(dag)
      #=> [[:a, :b, :c], [:d, :e]]
  """
  @spec connected_components(t()) :: [[node_id()]]
  defdelegate connected_components(dag), to: Algorithms

  # ============================================
  # Visualization (delegated)
  # ============================================

  @doc """
  Generates a Mermaid diagram string.

  ## Options

  - `:direction` - Graph direction: "TD" (top-down), "LR" (left-right), etc.
  - `:node_label` - Function to generate node label: `(node_id, node_data) -> String.t()`
  - `:node_style` - Function to generate node style class: `(node_id, node_data) -> String.t() | nil`
  - `:show_groups` - Include subgraphs for groups (default: false)
  - `:styles` - Map of style class definitions

  ## Examples

      Dag.to_mermaid(dag)
      #=> "graph TD\\n  a[A]\\n  b[B]\\n  a --> b"

      Dag.to_mermaid(dag,
        direction: "LR",
        node_label: fn id, data -> data[:label] || to_string(id) end
      )
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  defdelegate to_mermaid(dag, opts \\ []), to: Visualization

  @doc """
  Generates a Graphviz DOT diagram string.

  ## Options

  - `:rankdir` - Graph direction: "TB", "LR", etc.
  - `:node_label` - Function to generate node label
  - `:node_attrs` - Function to generate node attributes
  - `:graph_attrs` - Additional graph attributes

  ## Examples

      Dag.to_dot(dag)
      #=> "digraph G {\\n  a -> b;\\n}"
  """
  @spec to_dot(t(), keyword()) :: String.t()
  defdelegate to_dot(dag, opts \\ []), to: Visualization

  @doc """
  Generates an ASCII representation of the DAG.

  ## Examples

      Dag.to_ascii(dag)
      #=> "a -> b -> c"
  """
  @spec to_ascii(t(), keyword()) :: String.t()
  defdelegate to_ascii(dag, opts \\ []), to: Visualization

  # ============================================
  # Bang Variants (raise on error)
  # ============================================

  @doc """
  Like `topological_sort/1` but raises on error.

  ## Examples

      [:a, :b, :c] = Dag.topological_sort!(dag)

  Raises `Dag.Error.CycleDetected` if the DAG contains a cycle.
  """
  @spec topological_sort!(t()) :: [node_id()]
  def topological_sort!(%__MODULE__{} = dag) do
    case topological_sort(dag) do
      {:ok, sorted} -> sorted
      {:error, :cycle_detected} -> raise Dag.Error.CycleDetected, path: detect_cycle(dag) || []
    end
  end

  @doc """
  Like `shortest_path/3` but raises on error.

  ## Examples

      [:a, :b, :c] = Dag.shortest_path!(dag, :a, :c)

  Raises `Dag.Error.NoPath` if no path exists.
  """
  @spec shortest_path!(t(), node_id(), node_id()) :: [node_id()]
  def shortest_path!(%__MODULE__{} = dag, from, to) do
    case shortest_path(dag, from, to) do
      {:ok, path} -> path
      {:error, :no_path} -> raise Dag.Error.NoPath, from: from, to: to
    end
  end

  @doc """
  Like `distance/3` but raises on error.

  ## Examples

      2 = Dag.distance!(dag, :a, :c)

  Raises `Dag.Error.NoPath` if no path exists.
  """
  @spec distance!(t(), node_id(), node_id()) :: non_neg_integer()
  def distance!(%__MODULE__{} = dag, from, to) do
    case distance(dag, from, to) do
      {:ok, dist} -> dist
      {:error, :no_path} -> raise Dag.Error.NoPath, from: from, to: to
    end
  end

  @doc """
  Like `get_node/2` but raises on error.

  ## Examples

      %{label: "A"} = Dag.get_node!(dag, :a)

  Raises `Dag.Error.NodeNotFound` if node doesn't exist.
  """
  @spec get_node!(t(), node_id()) :: node_data()
  def get_node!(%__MODULE__{} = dag, id) do
    case get_node(dag, id) do
      {:ok, data} -> data
      {:error, :not_found} -> raise Dag.Error.NodeNotFound, node: id
    end
  end

  @doc """
  Like `get_edge/3` but raises on error.

  ## Examples

      %{weight: 10} = Dag.get_edge!(dag, :a, :b)

  Raises `Dag.Error.EdgeNotFound` if edge doesn't exist.
  """
  @spec get_edge!(t(), node_id(), node_id()) :: edge_data()
  def get_edge!(%__MODULE__{} = dag, from, to) do
    case get_edge(dag, from, to) do
      {:ok, data} -> data
      {:error, :not_found} -> raise Dag.Error.EdgeNotFound, from: from, to: to
    end
  end

  @doc """
  Like `validate/1` but raises on error.

  ## Examples

      :ok = Dag.validate!(dag)

  Raises appropriate error struct on validation failure.
  """
  @spec validate!(t()) :: :ok
  def validate!(%__MODULE__{} = dag) do
    case validate(dag) do
      :ok ->
        :ok

      {:error, {:cycle_detected, path}} ->
        raise Dag.Error.CycleDetected, path: path

      {:error, {:missing_nodes, nodes}} ->
        raise Dag.Error.MissingNodes, nodes: nodes

      {:error, reason} ->
        raise Dag.Error.InvalidDefinition, reason: reason
    end
  end

  @doc """
  Like `from_map/1` but raises on error.

  ## Examples

      dag = Dag.from_map!(map)

  Raises appropriate error struct on failure.
  """
  @spec from_map!(map()) :: t()
  def from_map!(map) do
    case from_map(map) do
      {:ok, dag} ->
        dag

      {:error, {:cycle_detected, path}} ->
        raise Dag.Error.CycleDetected, path: path

      {:error, {:deserialization_failed, reason}} ->
        raise Dag.Error.DeserializationFailed, reason: reason

      {:error, reason} ->
        raise Dag.Error.InvalidDefinition, reason: reason
    end
  end

  @doc """
  Like `shortest_weighted_path/4` but raises on error.

  ## Examples

      {weight, path} = Dag.shortest_weighted_path!(dag, :a, :d, &weight_fn/1)

  Raises `Dag.Error.NoPath` if no path exists.
  """
  @spec shortest_weighted_path!(t(), node_id(), node_id(), (map() -> number())) ::
          {number(), [node_id()]}
  def shortest_weighted_path!(%__MODULE__{} = dag, from, to, weight_fn) do
    case shortest_weighted_path(dag, from, to, weight_fn) do
      {:ok, result} -> result
      {:error, :no_path} -> raise Dag.Error.NoPath, from: from, to: to
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp ensure_node(%__MODULE__{nodes: nodes} = dag, id) do
    case Map.has_key?(nodes, id) do
      true -> dag
      false -> add_node(dag, id)
    end
  end
end

# ============================================
# Protocol Implementations
# ============================================

defimpl Inspect, for: Dag do
  import Inspect.Algebra

  def inspect(%Dag{} = dag, opts) do
    node_count = Dag.node_count(dag)
    edge_count = Dag.edge_count(dag)
    roots = Dag.roots(dag)
    leaves = Dag.leaves(dag)

    info = [
      nodes: node_count,
      edges: edge_count,
      roots: truncate_list(roots, 5),
      leaves: truncate_list(leaves, 5)
    ]

    concat(["#Dag<", to_doc(info, opts), ">"])
  end

  defp truncate_list(list, max) when length(list) <= max, do: list
  defp truncate_list(list, max), do: Enum.take(list, max) ++ [:"..."]
end

defimpl Enumerable, for: Dag do
  @doc """
  Enumerates nodes in topological order.
  """
  def count(%Dag{} = dag) do
    {:ok, Dag.node_count(dag)}
  end

  def member?(%Dag{} = dag, {id, _data}) do
    {:ok, Dag.has_node?(dag, id)}
  end

  def member?(%Dag{} = dag, id) do
    {:ok, Dag.has_node?(dag, id)}
  end

  def slice(%Dag{} = dag) do
    node_count = Dag.node_count(dag)

    {:ok, node_count,
     fn start, length ->
       dag
       |> to_node_list()
       |> Enum.slice(start, length)
     end}
  end

  def reduce(%Dag{} = dag, acc, fun) do
    node_list = to_node_list(dag)
    Enumerable.List.reduce(node_list, acc, fun)
  end

  # Returns nodes as {id, data} tuples in topological order (or by node_ids if cycle)
  defp to_node_list(%Dag{} = dag) do
    ordered_ids =
      case Dag.topological_sort(dag) do
        {:ok, sorted} -> sorted
        {:error, _} -> Dag.node_ids(dag)
      end

    Enum.map(ordered_ids, fn id ->
      {:ok, data} = Dag.get_node(dag, id)
      {id, data}
    end)
  end
end

defimpl Collectable, for: Dag do
  @doc """
  Allows building a DAG using `Enum.into/2`.

  Accepts:
  - `{:node, id}` - adds a node with empty data
  - `{:node, id, data}` - adds a node with data
  - `{:edge, from, to}` - adds an edge
  - `{:edge, from, to, data}` - adds an edge with data
  """
  def into(%Dag{} = dag) do
    collector_fun = fn
      dag_acc, {:cont, {:node, id}} ->
        Dag.add_node(dag_acc, id)

      dag_acc, {:cont, {:node, id, data}} ->
        Dag.add_node(dag_acc, id, data)

      dag_acc, {:cont, {:edge, from, to}} ->
        Dag.add_edge(dag_acc, from, to)

      dag_acc, {:cont, {:edge, from, to, data}} ->
        Dag.add_edge(dag_acc, from, to, data)

      dag_acc, :done ->
        dag_acc

      _dag_acc, :halt ->
        :ok
    end

    {dag, collector_fun}
  end
end
