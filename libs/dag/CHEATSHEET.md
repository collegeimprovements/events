# Dag Cheatsheet

> Directed Acyclic Graph library with algorithms and visualization. For full docs, see `README.md`.

## Construction

```elixir
# Empty
dag = Dag.new()

# From definition
{:ok, dag} = Dag.from_definition(
  nodes: [{:a, %{label: "A"}}, {:b, %{label: "B"}}, :c],
  edges: [{:a, :b}, {:b, :c, %{weight: 10}}]
)
dag = Dag.from_definition!(nodes: [...], edges: [...])
```

---

## Nodes

```elixir
# Add
dag = Dag.add_node(dag, :task_1)
dag = Dag.add_node(dag, :task_2, %{label: "Process", timeout: 5000})
dag = Dag.add_nodes(dag, [:a, :b, :c])

# Query
{:ok, data} = Dag.get_node(dag, :a)
data = Dag.get_node!(dag, :a)
Dag.has_node?(dag, :a)                            #=> true
Dag.node_ids(dag)                                  #=> [:a, :b, :c]
Dag.node_count(dag)                                #=> 3

# Update / Remove
dag = Dag.update_node(dag, :a, &Map.put(&1, :visited, true))
dag = Dag.remove_node(dag, :a)                     # removes connected edges too
```

---

## Edges

```elixir
# Add (from -> to: "to depends on from")
dag = Dag.add_edge(dag, :a, :b)
dag = Dag.add_edge(dag, :a, :b, %{weight: 10})
dag = Dag.add_edges(dag, [{:a, :b}, {:b, :c}, {:a, :c, %{weight: 5}}])

# Query
Dag.has_edge?(dag, :a, :b)                        #=> true
{:ok, %{weight: 10}} = Dag.get_edge(dag, :a, :b)
Dag.edges(dag)                                     #=> [{:a, :b, %{}}, ...]
Dag.edge_count(dag)                                #=> 2

# Neighbors
Dag.successors(dag, :a)                            #=> [:b, :c]  (depends on a)
Dag.predecessors(dag, :c)                          #=> [:a, :b]  (c depends on)
Dag.in_degree(dag, :c)                             #=> 2
Dag.out_degree(dag, :a)                            #=> 2
```

---

## Algorithms

```elixir
# Validation
:ok = Dag.validate(dag)
{:error, {:cycle, [...]}} = Dag.validate(cyclic_dag)

# Topological sort
{:ok, sorted} = Dag.topological_sort(dag)          #=> [:a, :b, :c, :d]

# Roots & leaves
Dag.roots(dag)                                     #=> [:a]  (no predecessors)
Dag.leaves(dag)                                    #=> [:d]  (no successors)

# Paths
{:ok, path} = Dag.shortest_path(dag, :a, :d)      #=> [:a, :b, :d]
{:ok, paths} = Dag.all_paths(dag, :a, :d)
Dag.path_exists?(dag, :a, :d)                      #=> true

# Depth
Dag.depth(dag, :a)                                 #=> 0 (root)
Dag.depth(dag, :d)                                 #=> 2

# Subgraph
sub = Dag.subgraph(dag, [:a, :b])                  # only these nodes + edges

# Transitive reduction
reduced = Dag.transitive_reduction(dag)            # remove redundant edges

# Critical path (weighted)
{total_weight, path} = Dag.critical_path(dag)

# Parallel levels (for scheduling)
{:ok, levels} = Dag.parallel_levels(dag)
#=> [[:a], [:b, :c], [:d]]                         # can run each level in parallel
```

---

## Groups

```elixir
dag = Dag.add_to_group(dag, :transforms, [:to_json, :to_csv, :to_xml])
Dag.groups(dag)                                    #=> %{transforms: [:to_json, ...]}
Dag.get_group(dag, :transforms)                    #=> [:to_json, :to_csv, :to_xml]
```

---

## Visualization

```elixir
# Mermaid
Dag.to_mermaid(dag)
#=> "graph TD\n  a[Step A] --> b[Step B]\n  ..."

# DOT (Graphviz)
Dag.to_dot(dag)
#=> "digraph {\n  a -> b;\n  ..."

# ASCII
Dag.to_ascii(dag)
```

---

## Protocols

```elixir
# Enumerable (iterate nodes)
Enum.map(dag, fn {id, data} -> {id, data.label} end)
Enum.count(dag)

# Collectable
dag = Enum.into([{:a, %{}}, {:b, %{}}], Dag.new())

# Inspect
IO.inspect(dag)                                    # pretty-printed
```
