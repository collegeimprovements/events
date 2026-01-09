defmodule Dag.Visualization do
  @moduledoc """
  Visualization utilities for DAGs.

  Generates diagrams in various formats:
  - Mermaid (for documentation and GitHub)
  - DOT/Graphviz (for high-quality rendering)
  - ASCII (for terminal output)
  """

  alias Dag
  alias Dag.Algorithms

  @type node_id :: Dag.node_id()

  # ============================================
  # Mermaid
  # ============================================

  @doc """
  Generates a Mermaid diagram string.

  ## Options

  - `:direction` - Graph direction: "TD" (top-down), "LR" (left-right),
                   "BT" (bottom-top), "RL" (right-left). Default: "TD"
  - `:node_label` - Function `(node_id, node_data) -> String.t()` to generate labels
  - `:node_style` - Function `(node_id, node_data) -> String.t() | nil` to generate style class
  - `:show_groups` - Include subgraphs for groups. Default: false
  - `:styles` - Map of style class definitions
  - `:title` - Optional title for the diagram

  ## Examples

      Dag.to_mermaid(dag)
      #=> "graph TD\\n  a[A]\\n  b[B]\\n  a --> b"

      Dag.to_mermaid(dag,
        direction: "LR",
        node_label: fn id, data -> data[:label] || humanize(id) end,
        styles: %{
          completed: "fill:#90EE90,stroke:#228B22",
          failed: "fill:#FF6B6B,stroke:#DC143C"
        }
      )
  """
  @spec to_mermaid(Dag.t(), keyword()) :: String.t()
  def to_mermaid(%Dag{} = dag, opts \\ []) do
    direction = Keyword.get(opts, :direction, "TD")
    node_label_fn = Keyword.get(opts, :node_label, &default_label/2)
    node_style_fn = Keyword.get(opts, :node_style)
    show_groups = Keyword.get(opts, :show_groups, false)
    styles = Keyword.get(opts, :styles, %{})
    title = Keyword.get(opts, :title)

    lines = build_title_lines(title) ++ ["graph #{direction}"]

    # Add nodes
    nodes = generate_mermaid_nodes(dag, node_label_fn, node_style_fn)
    lines = lines ++ nodes

    # Add edges
    edges = generate_mermaid_edges(dag)
    lines = lines ++ edges

    lines = lines ++ build_subgraph_lines(dag, show_groups)
    lines = lines ++ build_style_lines(styles)

    Enum.join(lines, "\n")
  end

  defp build_title_lines(nil), do: []
  defp build_title_lines(title), do: ["---", "title: #{title}", "---"]

  defp build_subgraph_lines(%Dag{groups: groups}, true) when map_size(groups) > 0 do
    generate_mermaid_subgraphs(%Dag{groups: groups})
  end

  defp build_subgraph_lines(_dag, _show_groups), do: []

  defp build_style_lines(styles) when map_size(styles) > 0 do
    Enum.map(styles, fn {class, style} -> "  classDef #{class} #{style}" end)
  end

  defp build_style_lines(_styles), do: []

  defp generate_mermaid_nodes(dag, label_fn, style_fn) do
    Enum.map(dag.nodes, fn {id, data} ->
      label = label_fn.(id, data)
      node_str = "  #{id}[#{escape_mermaid(label)}]"
      apply_node_style(node_str, id, data, style_fn)
    end)
  end

  defp apply_node_style(node_str, _id, _data, nil), do: node_str

  defp apply_node_style(node_str, id, data, style_fn) do
    case style_fn.(id, data) do
      nil -> node_str
      style -> "#{node_str}:::#{style}"
    end
  end

  defp generate_mermaid_edges(dag) do
    Enum.flat_map(dag.edges, fn {from, targets} ->
      Enum.map(targets, fn {to, edge_data} ->
        format_mermaid_edge(from, to, Map.get(edge_data, :label))
      end)
    end)
  end

  defp format_mermaid_edge(from, to, nil), do: "  #{from} --> #{to}"
  defp format_mermaid_edge(from, to, label), do: "  #{from} -->|#{escape_mermaid(label)}| #{to}"

  defp build_defaults_line(_type, nil), do: []
  defp build_defaults_line(type, defaults), do: ["  #{type} [#{defaults}];"]

  defp generate_mermaid_subgraphs(dag) do
    Enum.flat_map(dag.groups, fn {group_name, members} ->
      [
        "  subgraph #{group_name}[#{humanize(group_name)}]"
      ] ++
        Enum.map(members, fn member -> "    #{member}" end) ++
        ["  end"]
    end)
  end

  defp escape_mermaid(str) when is_binary(str) do
    str
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_mermaid(other), do: to_string(other)

  # ============================================
  # DOT / Graphviz
  # ============================================

  @doc """
  Generates a Graphviz DOT diagram string.

  ## Options

  - `:rankdir` - Graph direction: "TB", "LR", "BT", "RL". Default: "TB"
  - `:name` - Graph name. Default: "G"
  - `:node_label` - Function to generate node label
  - `:node_attrs` - Function `(node_id, node_data) -> String.t()` for extra attributes
  - `:edge_attrs` - Function `(from, to, edge_data) -> String.t()` for edge attributes
  - `:graph_attrs` - Additional graph attributes as keyword list
  - `:node_defaults` - Default node attributes
  - `:edge_defaults` - Default edge attributes

  ## Examples

      Dag.to_dot(dag)
      #=> "digraph G {\\n  rankdir=TB;\\n  a -> b;\\n}"

      Dag.to_dot(dag,
        rankdir: "LR",
        node_attrs: fn id, data ->
          case data[:status] do
            :completed -> "fillcolor=green, style=filled"
            :failed -> "fillcolor=red, style=filled"
            _ -> ""
          end
        end
      )
  """
  @spec to_dot(Dag.t(), keyword()) :: String.t()
  def to_dot(%Dag{} = dag, opts \\ []) do
    rankdir = Keyword.get(opts, :rankdir, "TB")
    name = Keyword.get(opts, :name, "G")
    node_label_fn = Keyword.get(opts, :node_label, &default_label/2)
    node_attrs_fn = Keyword.get(opts, :node_attrs)
    edge_attrs_fn = Keyword.get(opts, :edge_attrs)
    graph_attrs = Keyword.get(opts, :graph_attrs, [])
    node_defaults = Keyword.get(opts, :node_defaults, "shape=box, style=rounded")
    edge_defaults = Keyword.get(opts, :edge_defaults)

    graph_attr_lines = Enum.map(graph_attrs, fn {key, value} ->
      "  #{key}=#{escape_dot_value(value)};"
    end)

    lines =
      ["digraph #{name} {", "  rankdir=#{rankdir};"] ++
        graph_attr_lines ++
        build_defaults_line("node", node_defaults) ++
        build_defaults_line("edge", edge_defaults) ++
        [""]

    # Nodes
    nodes = generate_dot_nodes(dag, node_label_fn, node_attrs_fn)
    lines = lines ++ nodes ++ [""]

    # Edges
    edges = generate_dot_edges(dag, edge_attrs_fn)
    lines = lines ++ edges

    # Clusters for groups
    clusters = generate_dot_clusters(dag)
    lines = lines ++ clusters

    lines = lines ++ ["}"]

    Enum.join(lines, "\n")
  end

  defp generate_dot_nodes(dag, label_fn, attrs_fn) do
    Enum.map(dag.nodes, fn {id, data} ->
      label = label_fn.(id, data)
      base_attrs = ["label=#{escape_dot_value(label)}"]
      attrs = base_attrs ++ collect_extra_attrs(attrs_fn, id, data)

      "  #{id} [#{Enum.join(attrs, ", ")}];"
    end)
  end

  defp collect_extra_attrs(nil, _id, _data), do: []

  defp collect_extra_attrs(attrs_fn, id, data) do
    case attrs_fn.(id, data) do
      nil -> []
      "" -> []
      extra -> [extra]
    end
  end

  defp generate_dot_edges(dag, attrs_fn) do
    Enum.flat_map(dag.edges, fn {from, targets} ->
      Enum.map(targets, fn {to, edge_data} ->
        format_dot_edge(from, to, edge_data, attrs_fn)
      end)
    end)
  end

  defp format_dot_edge(from, to, edge_data, attrs_fn) do
    label_attrs = build_label_attr(Map.get(edge_data, :label))
    extra_attrs = collect_edge_extra_attrs(attrs_fn, from, to, edge_data)
    attrs = label_attrs ++ extra_attrs

    case attrs do
      [] -> "  #{from} -> #{to};"
      _ -> "  #{from} -> #{to} [#{Enum.join(attrs, ", ")}];"
    end
  end

  defp build_label_attr(nil), do: []
  defp build_label_attr(label), do: ["label=#{escape_dot_value(label)}"]

  defp collect_edge_extra_attrs(nil, _from, _to, _edge_data), do: []

  defp collect_edge_extra_attrs(attrs_fn, from, to, edge_data) do
    case attrs_fn.(from, to, edge_data) do
      nil -> []
      "" -> []
      extra -> [extra]
    end
  end

  defp generate_dot_clusters(dag) do
    dag.groups
    |> Enum.flat_map(fn {group_name, members} ->
      [
        "",
        "  subgraph cluster_#{group_name} {",
        "    label=#{escape_dot_value(humanize(group_name))};",
        "    style=dashed;",
        "    color=blue;"
      ] ++
        Enum.map(members, fn member -> "    #{member};" end) ++
        ["  }"]
    end)
  end

  defp escape_dot_value(value) when is_binary(value) do
    "\"#{String.replace(value, "\"", "\\\"")}\""
  end

  defp escape_dot_value(value), do: escape_dot_value(to_string(value))

  # ============================================
  # ASCII
  # ============================================

  @doc """
  Generates an ASCII representation of the DAG.

  ## Options

  - `:style` - Output style: :tree, :list, :levels. Default: :levels
  - `:node_label` - Function to generate node label
  - `:indent` - Indentation string. Default: "  "

  ## Examples

      Dag.to_ascii(dag)
      #=> "Level 0: a\\nLevel 1: b, c\\nLevel 2: d"

      Dag.to_ascii(dag, style: :tree)
      #=> "a\\n├── b\\n│   └── d\\n└── c"
  """
  @spec to_ascii(Dag.t(), keyword()) :: String.t()
  def to_ascii(%Dag{} = dag, opts \\ []) do
    style = Keyword.get(opts, :style, :levels)
    node_label_fn = Keyword.get(opts, :node_label, &default_label/2)

    case style do
      :levels -> to_ascii_levels(dag, node_label_fn)
      :list -> to_ascii_list(dag, node_label_fn)
      :tree -> to_ascii_tree(dag, node_label_fn, opts)
    end
  end

  defp to_ascii_levels(dag, label_fn) do
    levels = Algorithms.levels(dag)

    levels
    |> Enum.sort_by(fn {level, _} -> level end)
    |> Enum.map(fn {level, nodes} ->
      labels =
        nodes
        |> Enum.map(fn id ->
          {:ok, data} = Dag.get_node(dag, id)
          label_fn.(id, data)
        end)
        |> Enum.join(", ")

      "Level #{level}: #{labels}"
    end)
    |> Enum.join("\n")
  end

  defp to_ascii_list(dag, label_fn) do
    case Algorithms.topological_sort(dag) do
      {:ok, sorted} ->
        sorted
        |> Enum.with_index(1)
        |> Enum.map(fn {id, idx} ->
          {:ok, data} = Dag.get_node(dag, id)
          deps = Dag.predecessors(dag, id)

          dep_str =
            case deps do
              [] -> ""
              _ -> " (after: #{Enum.join(deps, ", ")})"
            end

          "#{idx}. #{label_fn.(id, data)}#{dep_str}"
        end)
        |> Enum.join("\n")

      {:error, _} ->
        "Error: DAG contains cycles"
    end
  end

  defp to_ascii_tree(dag, label_fn, opts) do
    indent = Keyword.get(opts, :indent, "  ")
    roots = Algorithms.roots(dag)

    roots
    |> Enum.map(fn root ->
      render_tree_node(dag, root, label_fn, indent, "", true)
    end)
    |> Enum.join("\n")
  end

  defp render_tree_node(dag, id, label_fn, indent, prefix, is_last) do
    {:ok, data} = Dag.get_node(dag, id)
    label = label_fn.(id, data)

    connector = tree_connector(is_last)
    line = "#{prefix}#{connector}#{label}"

    successors = Dag.successors(dag, id)
    child_prefix = build_child_prefix(prefix, indent, is_last)

    child_lines =
      successors
      |> Enum.with_index()
      |> Enum.map(fn {child, idx} ->
        is_last_child = idx == length(successors) - 1
        render_tree_node(dag, child, label_fn, indent, child_prefix, is_last_child)
      end)
      |> Enum.join("\n")

    join_tree_lines(line, child_lines)
  end

  defp tree_connector(true), do: "└── "
  defp tree_connector(false), do: "├── "

  defp build_child_prefix(prefix, indent, true), do: prefix <> indent
  defp build_child_prefix(prefix, indent, false), do: prefix <> "│" <> String.slice(indent, 1..-1//1)

  defp join_tree_lines(line, ""), do: line
  defp join_tree_lines(line, child_lines), do: "#{line}\n#{child_lines}"

  # ============================================
  # Helpers
  # ============================================

  defp default_label(id, data) do
    Map.get(data, :label) || humanize(id)
  end

  defp humanize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> humanize()
  end

  defp humanize(string) when is_binary(string) do
    string
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
