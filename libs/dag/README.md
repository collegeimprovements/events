# Dag

A comprehensive Directed Acyclic Graph (DAG) library for Elixir with algorithms, visualization, and protocol implementations.

## Installation

```elixir
def deps do
  [{:dag, "~> 0.1.0"}]
end
```

## Why Dag?

DAGs are fundamental data structures for dependency management:

```
Manual Graph Handling                  Dag Library
─────────────────────────────────────────────────────────────────────
deps = %{                              dag = Dag.new()
  a: [:b, :c],                             |> Dag.add_edges([
  b: [:d],                                   {:a, :b},
  c: [:d]                                    {:a, :c},
}                                            {:b, :d},
                                             {:c, :d}
# Manual cycle detection?                  ])
# Manual topological sort?
# Manual path finding?                 {:ok, sorted} = Dag.topological_sort(dag)
# Manual visualization?                Dag.to_mermaid(dag)
```

**Features:**
- **Immutable** - All operations return new DAGs
- **Rich Algorithms** - Topological sort, cycle detection, paths, critical path
- **Visualization** - Mermaid, DOT/Graphviz, ASCII
- **Groups** - Organize nodes for parallel patterns
- **Protocol Support** - Enumerable, Collectable, Inspect
- **Weighted Paths** - Dijkstra's algorithm, critical path analysis

---

## Quick Start

```elixir
# Create a DAG
dag = Dag.new()
      |> Dag.add_node(:a, %{label: "Step A"})
      |> Dag.add_node(:b, %{label: "Step B"})
      |> Dag.add_node(:c, %{label: "Step C"})
      |> Dag.add_edge(:a, :b)  # b depends on a
      |> Dag.add_edge(:b, :c)  # c depends on b

# Validate
:ok = Dag.validate(dag)

# Sort topologically
{:ok, [:a, :b, :c]} = Dag.topological_sort(dag)

# Visualize
Dag.to_mermaid(dag)
#=> "graph TD\n  a[Step A]\n  b[Step B]\n  c[Step C]\n  a --> b\n  b --> c"
```

---

## Construction

### Empty DAG

```elixir
dag = Dag.new()
dag = Dag.new(metadata: %{name: :my_workflow, version: 1})
```

### From Definition

```elixir
{:ok, dag} = Dag.from_definition(
  nodes: [
    {:a, %{label: "Task A", timeout: 5000}},
    {:b, %{label: "Task B"}},
    :c  # Node with empty data
  ],
  edges: [
    {:a, :b},
    {:b, :c, %{weight: 10}}  # Edge with metadata
  ],
  metadata: %{workflow: :data_pipeline}
)

# Raising version
dag = Dag.from_definition!(nodes: [...], edges: [...])
```

---

## Node Operations

### Adding Nodes

```elixir
# Single node
dag = Dag.add_node(dag, :task_1)
dag = Dag.add_node(dag, :task_2, %{label: "Process Data", timeout: 5000})

# Multiple nodes
dag = Dag.add_nodes(dag, [:a, :b, :c])
dag = Dag.add_nodes(dag, [
  {:a, %{label: "A"}},
  {:b, %{label: "B"}},
  :c
])
```

### Querying Nodes

```elixir
# Get node data
{:ok, %{label: "Task A"}} = Dag.get_node(dag, :a)
{:error, :not_found} = Dag.get_node(dag, :unknown)

# Bang version
%{label: "Task A"} = Dag.get_node!(dag, :a)

# Check existence
Dag.has_node?(dag, :a)  #=> true

# List all nodes
Dag.node_ids(dag)  #=> [:a, :b, :c]

# Count
Dag.node_count(dag)  #=> 3
```

### Updating Nodes

```elixir
dag = Dag.update_node(dag, :a, fn data ->
  Map.put(data, :visited, true)
end)
```

### Removing Nodes

```elixir
# Removes node and all connected edges
dag = Dag.remove_node(dag, :a)
```

---

## Edge Operations

### Adding Edges

```elixir
# Edge direction: from -> to (to depends on from)
dag = Dag.add_edge(dag, :a, :b)           # b depends on a
dag = Dag.add_edge(dag, :a, :b, %{weight: 10, label: "heavy"})

# Multiple edges
dag = Dag.add_edges(dag, [
  {:a, :b},
  {:b, :c},
  {:a, :c, %{weight: 5}}
])
```

### Querying Edges

```elixir
# Check edge
Dag.has_edge?(dag, :a, :b)  #=> true

# Get edge data
{:ok, %{weight: 10}} = Dag.get_edge(dag, :a, :b)

# Bang version
%{weight: 10} = Dag.get_edge!(dag, :a, :b)

# All edges
Dag.edges(dag)
#=> [{:a, :b, %{weight: 10}}, {:b, :c, %{}}]

# Edge count
Dag.edge_count(dag)  #=> 2
```

### Neighbors

```elixir
# Nodes that depend on :a (outgoing edges)
Dag.successors(dag, :a)  #=> [:b, :c]

# Nodes that :c depends on (incoming edges)
Dag.predecessors(dag, :c)  #=> [:a, :b]

# In-degree (incoming edge count)
Dag.in_degree(dag, :c)  #=> 2

# Out-degree (outgoing edge count)
Dag.out_degree(dag, :a)  #=> 2
```

### Updating Edges

```elixir
dag = Dag.update_edge(dag, :a, :b, fn data ->
  Map.put(data, :traversed, true)
end)
```

### Removing Edges

```elixir
dag = Dag.remove_edge(dag, :a, :b)
```

---

## Groups

Groups organize nodes for parallel execution patterns:

```elixir
# Add nodes to a group
dag = Dag.add_to_group(dag, :parallel_tasks, [:task_a, :task_b, :task_c])

# Get group members
Dag.get_group(dag, :parallel_tasks)
#=> [:task_a, :task_b, :task_c]

# Remove from group
dag = Dag.remove_from_group(dag, :parallel_tasks, :task_a)

# Visualize with groups
Dag.to_mermaid(dag, show_groups: true)
```

---

## Algorithms

### Topological Sort

Returns nodes in dependency order (Kahn's algorithm):

```elixir
{:ok, sorted} = Dag.topological_sort(dag)
#=> {:ok, [:a, :b, :c, :d]}

# Raises on cycle
sorted = Dag.topological_sort!(dag)
```

### Cycle Detection

```elixir
# Returns nil if no cycle, or the cycle path
nil = Dag.detect_cycle(dag)
[:a, :b, :c, :a] = Dag.detect_cycle(cyclic_dag)
```

### Validation

```elixir
:ok = Dag.validate(dag)

# Possible errors
{:error, {:cycle_detected, [:a, :b, :a]}} = Dag.validate(cyclic)
{:error, {:missing_nodes, [:unknown]}} = Dag.validate(invalid)

# Raising version
:ok = Dag.validate!(dag)
```

### Roots and Leaves

```elixir
# Entry points (no predecessors)
Dag.roots(dag)  #=> [:a]

# Exit points (no successors)
Dag.leaves(dag)  #=> [:d, :e]
```

### Ancestors and Descendants

```elixir
# All transitive predecessors
Dag.ancestors(dag, :d)  #=> [:a, :b, :c]

# All transitive successors
Dag.descendants(dag, :a)  #=> [:b, :c, :d, :e]
```

### Path Operations

```elixir
# Check if path exists
Dag.path_exists?(dag, :a, :d)  #=> true
Dag.path_exists?(dag, :d, :a)  #=> false (DAG is directed)

# Shortest path (by hop count)
{:ok, [:a, :b, :d]} = Dag.shortest_path(dag, :a, :d)
{:error, :no_path} = Dag.shortest_path(dag, :d, :a)

# Bang version
[:a, :b, :d] = Dag.shortest_path!(dag, :a, :d)

# All paths
Dag.all_paths(dag, :a, :d)
#=> [[:a, :b, :d], [:a, :c, :d]]

# Distance (hop count)
{:ok, 2} = Dag.distance(dag, :a, :d)
2 = Dag.distance!(dag, :a, :d)
```

### Levels (Depth Analysis)

```elixir
# Longest path from roots to each node
Dag.longest_paths(dag)
#=> %{a: 0, b: 1, c: 1, d: 2}

# Nodes at specific depth
Dag.nodes_at_level(dag, 0)  #=> [:a]
Dag.nodes_at_level(dag, 1)  #=> [:b, :c]

# Maximum depth
Dag.Algorithms.max_depth(dag)  #=> 2

# All levels
Dag.Algorithms.levels(dag)
#=> %{0 => [:a], 1 => [:b, :c], 2 => [:d]}
```

### Weighted Algorithms

```elixir
# Critical path (longest weighted path through DAG)
{total_weight, path} = Dag.critical_path(dag, fn edge_data ->
  edge_data[:duration] || 1
end)
#=> {15, [:a, :b, :d]}

# Shortest weighted path (Dijkstra's)
{:ok, {weight, path}} = Dag.shortest_weighted_path(dag, :a, :d, fn edge_data ->
  edge_data[:cost] || 1
end)
#=> {:ok, {5, [:a, :c, :d]}}

# Bang version
{weight, path} = Dag.shortest_weighted_path!(dag, :a, :d, &weight_fn/1)
```

---

## Graph Transformations

### Transitive Reduction

Removes redundant edges while maintaining reachability:

```elixir
# Given: a→b, b→c, a→c (a→c is redundant)
# Result: a→b, b→c
reduced = Dag.transitive_reduction(dag)
```

### Reverse

Reverses all edge directions:

```elixir
# Given: a→b→c
# Result: c→b→a
reversed = Dag.reverse(dag)
```

### Subgraph

Extracts induced subgraph:

```elixir
# Keep only specified nodes and edges between them
subgraph = Dag.subgraph(dag, [:a, :b, :c])
```

### Filter Nodes

```elixir
# Keep only completed nodes
completed = Dag.filter_nodes(dag, fn _id, data ->
  data[:status] == :completed
end)
```

### Merge

Combines two DAGs:

```elixir
merged = Dag.merge(dag1, dag2)
# Nodes with same ID: dag2 data takes precedence
# All edges from both included
```

### Concat

Chains DAGs by connecting leaves to roots:

```elixir
# dag1: a→b, dag2: c→d
# Result: a→b→c→d
chained = Dag.concat(dag1, dag2)
```

---

## Graph Properties

```elixir
# Is it a tree? (single root, each node has at most one parent)
Dag.is_tree?(dag)  #=> true

# Is it a forest? (each node has at most one parent)
Dag.is_forest?(dag)  #=> true

# Weakly connected components
Dag.connected_components(dag)
#=> [[:a, :b, :c], [:d, :e]]  # Two separate subgraphs
```

---

## Visualization

### Mermaid

```elixir
# Basic
Dag.to_mermaid(dag)
#=> "graph TD\n  a[A]\n  b[B]\n  a --> b"

# With options
Dag.to_mermaid(dag,
  direction: "LR",
  title: "My Workflow",
  node_label: fn id, data -> data[:label] || to_string(id) end,
  node_style: fn _id, data ->
    case data[:status] do
      :completed -> "completed"
      :failed -> "failed"
      _ -> nil
    end
  end,
  show_groups: true,
  styles: %{
    completed: "fill:#90EE90,stroke:#228B22",
    failed: "fill:#FF6B6B,stroke:#DC143C"
  }
)
```

**Direction options:** `"TD"` (top-down), `"LR"` (left-right), `"BT"` (bottom-top), `"RL"` (right-left)

### DOT (Graphviz)

```elixir
# Basic
Dag.to_dot(dag)
#=> "digraph G {\n  rankdir=TB;\n  a -> b;\n}"

# With options
Dag.to_dot(dag,
  rankdir: "LR",
  name: "MyGraph",
  node_label: fn id, data -> data[:label] || to_string(id) end,
  node_attrs: fn _id, data ->
    case data[:status] do
      :completed -> "fillcolor=green, style=filled"
      :failed -> "fillcolor=red, style=filled"
      _ -> ""
    end
  end,
  edge_attrs: fn _from, _to, edge_data ->
    if edge_data[:critical], do: "color=red, penwidth=2", else: ""
  end,
  graph_attrs: [fontname: "Helvetica"],
  node_defaults: "shape=box, style=rounded"
)
```

**Render with Graphviz:**
```bash
echo "$DOT_OUTPUT" | dot -Tpng -o graph.png
```

### ASCII

```elixir
# Levels (default)
Dag.to_ascii(dag)
#=> "Level 0: A\nLevel 1: B, C\nLevel 2: D"

# Ordered list with dependencies
Dag.to_ascii(dag, style: :list)
#=> "1. A\n2. B (after: A)\n3. C (after: A)\n4. D (after: B, C)"

# Tree structure
Dag.to_ascii(dag, style: :tree)
#=> "└── A\n    ├── B\n    │   └── D\n    └── C"
```

---

## Serialization

```elixir
# To map
map = Dag.to_map(dag)
#=> %{
#     nodes: [%{id: :a, data: %{label: "A"}}, ...],
#     edges: [%{from: :a, to: :b, data: %{}}],
#     groups: %{parallel: [:a, :b]},
#     metadata: %{name: :workflow}
#   }

# From map
{:ok, dag} = Dag.from_map(map)
dag = Dag.from_map!(map)
```

---

## Protocol Implementations

### Enumerable

DAGs are enumerable in topological order:

```elixir
# Iterate over {id, data} tuples
for {id, data} <- dag do
  IO.puts("#{id}: #{data[:label]}")
end

# Count
Enum.count(dag)  #=> 4

# Member check
Enum.member?(dag, :a)  #=> true
```

### Collectable

Build DAGs with `Enum.into/2`:

```elixir
dag = [
  {:node, :a, %{label: "A"}},
  {:node, :b, %{label: "B"}},
  {:edge, :a, :b}
] |> Enum.into(Dag.new())
```

### Inspect

Pretty printing in IEx:

```elixir
#Dag<[nodes: 4, edges: 5, roots: [:a], leaves: [:d, :e]]>
```

---

## Real-World Examples

### Workflow Engine

```elixir
defmodule MyApp.Workflow do
  def build_order_pipeline do
    Dag.new(metadata: %{name: :order_processing})
    |> Dag.add_node(:validate, %{
      label: "Validate Order",
      handler: &validate_order/1
    })
    |> Dag.add_node(:check_inventory, %{
      label: "Check Inventory",
      handler: &check_inventory/1,
      retries: 3
    })
    |> Dag.add_node(:reserve_inventory, %{
      label: "Reserve Inventory",
      handler: &reserve_inventory/1,
      rollback: &release_inventory/1
    })
    |> Dag.add_node(:charge_payment, %{
      label: "Charge Payment",
      handler: &charge_payment/1,
      rollback: &refund_payment/1
    })
    |> Dag.add_node(:send_confirmation, %{
      label: "Send Confirmation",
      handler: &send_confirmation/1
    })
    |> Dag.add_edges([
      {:validate, :check_inventory},
      {:check_inventory, :reserve_inventory},
      {:reserve_inventory, :charge_payment},
      {:charge_payment, :send_confirmation}
    ])
  end

  def execute(dag, context) do
    {:ok, sorted} = Dag.topological_sort(dag)

    Enum.reduce_while(sorted, {:ok, context}, fn step, {:ok, ctx} ->
      {:ok, data} = Dag.get_node(dag, step)

      case data.handler.(ctx) do
        {:ok, new_ctx} -> {:cont, {:ok, new_ctx}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
```

### Build System

```elixir
defmodule MyApp.BuildSystem do
  def create_build_graph(project) do
    dag = Dag.new()

    # Add source files as nodes
    dag = Enum.reduce(project.source_files, dag, fn file, acc ->
      Dag.add_node(acc, file.path, %{
        type: :source,
        modified_at: file.modified_at
      })
    end)

    # Add edges for dependencies
    dag = Enum.reduce(project.dependencies, dag, fn {file, deps}, acc ->
      Enum.reduce(deps, acc, fn dep, inner_acc ->
        Dag.add_edge(inner_acc, dep, file)
      end)
    end)

    dag
  end

  def build_order(dag) do
    {:ok, sorted} = Dag.topological_sort(dag)
    sorted
  end

  def parallel_groups(dag) do
    # Group files by level for parallel compilation
    Dag.Algorithms.levels(dag)
    |> Enum.sort_by(fn {level, _} -> level end)
    |> Enum.map(fn {_level, files} -> files end)
  end

  def needs_rebuild?(dag, file, last_build_time) do
    {:ok, data} = Dag.get_node(dag, file)

    # Check if file or any ancestor was modified
    files_to_check = [file | Dag.ancestors(dag, file)]

    Enum.any?(files_to_check, fn f ->
      {:ok, d} = Dag.get_node(dag, f)
      d.modified_at > last_build_time
    end)
  end
end
```

### CI/CD Pipeline

```elixir
defmodule MyApp.Pipeline do
  def create_pipeline do
    Dag.new()
    |> Dag.add_nodes([
      {:checkout, %{label: "Checkout", duration: 10}},
      {:deps, %{label: "Install Dependencies", duration: 60}},
      {:compile, %{label: "Compile", duration: 120}},
      {:lint, %{label: "Lint", duration: 30}},
      {:test_unit, %{label: "Unit Tests", duration: 180}},
      {:test_integration, %{label: "Integration Tests", duration: 300}},
      {:build_image, %{label: "Build Docker Image", duration: 120}},
      {:deploy_staging, %{label: "Deploy to Staging", duration: 60}},
      {:smoke_test, %{label: "Smoke Tests", duration: 60}},
      {:deploy_prod, %{label: "Deploy to Production", duration: 60}}
    ])
    |> Dag.add_edges([
      {:checkout, :deps},
      {:deps, :compile},
      {:compile, :lint},
      {:compile, :test_unit},
      {:compile, :test_integration},
      {:lint, :build_image},
      {:test_unit, :build_image},
      {:test_integration, :build_image},
      {:build_image, :deploy_staging},
      {:deploy_staging, :smoke_test},
      {:smoke_test, :deploy_prod}
    ])
    # Group parallel tasks
    |> Dag.add_to_group(:parallel_tests, [:lint, :test_unit, :test_integration])
  end

  def critical_path(dag) do
    Dag.critical_path(dag, fn data -> data[:duration] || 1 end)
  end

  def estimated_duration(dag) do
    {total, _path} = critical_path(dag)
    total
  end

  def visualize(dag) do
    Dag.to_mermaid(dag,
      direction: "LR",
      show_groups: true,
      node_label: fn _id, data -> data[:label] end
    )
  end
end
```

---

## Error Handling

The library provides specific error types:

```elixir
# Cycle detected
try do
  Dag.topological_sort!(cyclic_dag)
rescue
  e in Dag.Error.CycleDetected ->
    IO.puts("Cycle: #{inspect(e.path)}")
end

# Node not found
try do
  Dag.get_node!(dag, :unknown)
rescue
  e in Dag.Error.NodeNotFound ->
    IO.puts("Node not found: #{e.node}")
end

# No path
try do
  Dag.shortest_path!(dag, :d, :a)
rescue
  e in Dag.Error.NoPath ->
    IO.puts("No path from #{e.from} to #{e.to}")
end
```

---

## Best Practices

### 1. Validate After Complex Changes

```elixir
dag = build_complex_dag(data)

case Dag.validate(dag) do
  :ok -> execute(dag)
  {:error, reason} -> handle_error(reason)
end
```

### 2. Use Groups for Parallel Execution

```elixir
dag = dag
  |> Dag.add_to_group(:level_1, [:a, :b, :c])
  |> Dag.add_to_group(:level_2, [:d, :e])

# Execute each group in parallel
for {_level, nodes} <- Dag.Algorithms.levels(dag) do
  Task.async_stream(nodes, &execute_node/1)
  |> Enum.to_list()
end
```

### 3. Store Metadata on Nodes

```elixir
Dag.add_node(dag, :process_data, %{
  handler: &process/1,
  timeout: 30_000,
  retries: 3,
  rollback: &rollback/1
})
```

### 4. Use Weighted Algorithms for Scheduling

```elixir
# Find the critical path (bottleneck)
{total_time, critical} = Dag.critical_path(dag, &(&1[:duration]))

# Prioritize critical path tasks
```

### 5. Leverage Protocol Implementations

```elixir
# Enumerable for iteration
completed = Enum.filter(dag, fn {_id, data} ->
  data[:status] == :completed
end)

# Collectable for building
dag = Stream.map(steps, &to_dag_entry/1)
      |> Enum.into(Dag.new())
```

---

## Use Cases

| Domain | Application |
|--------|-------------|
| **Workflow Engines** | Step-based orchestration with dependencies |
| **Build Systems** | Compile order, incremental builds |
| **CI/CD** | Pipeline stages, parallel jobs |
| **Task Scheduling** | Job queues with prerequisites |
| **Data Pipelines** | ETL dependencies, data lineage |
| **Package Management** | Dependency resolution |
| **Project Management** | Task dependencies, critical path |
| **UI Rendering** | Component dependency trees |

## License

MIT
