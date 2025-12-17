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

    lines = []

    # Add title if provided
    lines =
      if title do
        ["---", "title: #{title}", "---" | lines]
      else
        lines
      end

    lines = lines ++ ["graph #{direction}"]

    # Add nodes
    nodes = generate_mermaid_nodes(dag, node_label_fn, node_style_fn)
    lines = lines ++ nodes

    # Add edges
    edges = generate_mermaid_edges(dag)
    lines = lines ++ edges

    # Add subgraphs for groups
    lines =
      if show_groups and map_size(dag.groups) > 0 do
        lines ++ generate_mermaid_subgraphs(dag)
      else
        lines
      end

    # Add style definitions
    lines =
      if map_size(styles) > 0 do
        style_defs =
          Enum.map(styles, fn {class, style} ->
            "  classDef #{class} #{style}"
          end)

        lines ++ style_defs
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  defp generate_mermaid_nodes(dag, label_fn, style_fn) do
    dag.nodes
    |> Enum.map(fn {id, data} ->
      label = label_fn.(id, data)
      node_str = "  #{id}[#{escape_mermaid(label)}]"

      if style_fn do
        case style_fn.(id, data) do
          nil -> node_str
          style -> "#{node_str}:::#{style}"
        end
      else
        node_str
      end
    end)
  end

  defp generate_mermaid_edges(dag) do
    dag.edges
    |> Enum.flat_map(fn {from, targets} ->
      Enum.map(targets, fn {to, edge_data} ->
        label = Map.get(edge_data, :label)

        if label do
          "  #{from} -->|#{escape_mermaid(label)}| #{to}"
        else
          "  #{from} --> #{to}"
        end
      end)
    end)
  end

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

    lines = ["digraph #{name} {"]

    # Graph attributes
    lines = lines ++ ["  rankdir=#{rankdir};"]

    lines =
      lines ++
        Enum.map(graph_attrs, fn {key, value} ->
          "  #{key}=#{escape_dot_value(value)};"
        end)

    # Node defaults
    lines =
      if node_defaults do
        lines ++ ["  node [#{node_defaults}];"]
      else
        lines
      end

    # Edge defaults
    lines =
      if edge_defaults do
        lines ++ ["  edge [#{edge_defaults}];"]
      else
        lines
      end

    lines = lines ++ [""]

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
    dag.nodes
    |> Enum.map(fn {id, data} ->
      label = label_fn.(id, data)
      attrs = ["label=#{escape_dot_value(label)}"]

      attrs =
        if attrs_fn do
          case attrs_fn.(id, data) do
            nil -> attrs
            "" -> attrs
            extra -> attrs ++ [extra]
          end
        else
          attrs
        end

      "  #{id} [#{Enum.join(attrs, ", ")}];"
    end)
  end

  defp generate_dot_edges(dag, attrs_fn) do
    dag.edges
    |> Enum.flat_map(fn {from, targets} ->
      Enum.map(targets, fn {to, edge_data} ->
        base = "  #{from} -> #{to}"

        attrs = []

        attrs =
          case Map.get(edge_data, :label) do
            nil -> attrs
            label -> ["label=#{escape_dot_value(label)}" | attrs]
          end

        attrs =
          if attrs_fn do
            case attrs_fn.(from, to, edge_data) do
              nil -> attrs
              "" -> attrs
              extra -> [extra | attrs]
            end
          else
            attrs
          end

        case attrs do
          [] -> "#{base};"
          _ -> "#{base} [#{Enum.join(attrs, ", ")}];"
        end
      end)
    end)
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

    connector = if is_last, do: "└── ", else: "├── "
    line = "#{prefix}#{connector}#{label}"

    successors = Dag.successors(dag, id)

    child_prefix =
      if is_last do
        prefix <> indent
      else
        prefix <> "│" <> String.slice(indent, 1..-1//1)
      end

    child_lines =
      successors
      |> Enum.with_index()
      |> Enum.map(fn {child, idx} ->
        is_last_child = idx == length(successors) - 1
        render_tree_node(dag, child, label_fn, indent, child_prefix, is_last_child)
      end)
      |> Enum.join("\n")

    if child_lines == "" do
      line
    else
      "#{line}\n#{child_lines}"
    end
  end

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
