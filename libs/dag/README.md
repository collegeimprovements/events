# Dag

A generic Directed Acyclic Graph (DAG) library for Elixir.

## Features

- **Core Operations**: Add/remove nodes and edges with metadata
- **Algorithms**: Topological sort, cycle detection, reachability
- **Visualization**: Mermaid, DOT/Graphviz, ASCII output
- **Groups**: Organize nodes into groups for parallel patterns
- **Validation**: Detect cycles and missing dependencies

## Installation

Add to your `mix.exs`:

```elixir
{:dag, path: "libs/dag"}
```

## Quick Start

```elixir
# Create a DAG
dag = Dag.new()
      |> Dag.add_node(:a, %{label: "Step A"})
      |> Dag.add_node(:b, %{label: "Step B"})
      |> Dag.add_node(:c, %{label: "Step C"})
      |> Dag.add_edge(:a, :b)  # b depends on a
      |> Dag.add_edge(:b, :c)  # c depends on b

# Validate and sort
{:ok, sorted} = Dag.topological_sort(dag)
#=> [:a, :b, :c]

# Check for cycles
nil = Dag.detect_cycle(dag)

# Visualize
Dag.to_mermaid(dag)
#=> "graph TD\n  a[Step A]\n  b[Step B]\n  c[Step C]\n  a --> b\n  b --> c"
```

## API Reference

### Construction

```elixir
Dag.new(metadata: %{name: :my_dag})

Dag.from_definition(
  nodes: [{:a, %{label: "A"}}, :b, :c],
  edges: [{:a, :b}, {:b, :c}]
)
```

### Node Operations

```elixir
Dag.add_node(dag, :id, %{data: "value"})
Dag.add_nodes(dag, [:a, :b, c: %{label: "C"}])
Dag.remove_node(dag, :id)
Dag.get_node(dag, :id)  #=> {:ok, data} | {:error, :not_found}
Dag.has_node?(dag, :id)
Dag.node_ids(dag)
Dag.node_count(dag)
```

### Edge Operations

```elixir
Dag.add_edge(dag, :from, :to, %{weight: 10})
Dag.add_edges(dag, [{:a, :b}, {:b, :c, %{label: "depends"}}])
Dag.remove_edge(dag, :from, :to)
Dag.has_edge?(dag, :from, :to)
Dag.successors(dag, :id)    # nodes that depend on this
Dag.predecessors(dag, :id)  # nodes this depends on
Dag.edge_count(dag)
```

### Groups

```elixir
Dag.add_to_group(dag, :parallel_tasks, [:a, :b, :c])
Dag.get_group(dag, :parallel_tasks)
Dag.remove_from_group(dag, :parallel_tasks, :a)
```

### Algorithms

```elixir
Dag.topological_sort(dag)   #=> {:ok, [sorted]} | {:error, :cycle_detected}
Dag.detect_cycle(dag)       #=> nil | [cycle_path]
Dag.validate(dag)           #=> :ok | {:error, reason}
Dag.roots(dag)              # nodes with no predecessors
Dag.leaves(dag)             # nodes with no successors
Dag.ancestors(dag, :id)     # all transitive predecessors
Dag.descendants(dag, :id)   # all transitive successors
Dag.longest_paths(dag)      #=> %{node => level}
Dag.nodes_at_level(dag, 0)  # nodes at depth 0
```

### Visualization

```elixir
# Mermaid (for docs/GitHub)
Dag.to_mermaid(dag,
  direction: "LR",
  show_groups: true,
  node_label: fn id, data -> data[:label] || to_string(id) end,
  node_style: fn _id, data -> data[:status] end,
  styles: %{completed: "fill:#90EE90"}
)

# DOT/Graphviz
Dag.to_dot(dag,
  rankdir: "TB",
  node_attrs: fn _id, data -> "fillcolor=green" end
)

# ASCII
Dag.to_ascii(dag, style: :levels)  # Level 0: a\nLevel 1: b, c
Dag.to_ascii(dag, style: :list)    # 1. a\n2. b (after: a)
Dag.to_ascii(dag, style: :tree)    # Tree structure
```

## Use Cases

- **Effect System**: Step-based workflow execution
- **Workflow Engine**: Job orchestration with dependencies
- **Task Scheduling**: Build systems, CI/CD pipelines
- **Data Pipelines**: ETL dependency management
