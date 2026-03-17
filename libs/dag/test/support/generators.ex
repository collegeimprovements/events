defmodule Dag.Generators do
  @moduledoc false
  # StreamData generators for DAG and Workflow property tests.

  import StreamData

  alias Dag.{Workflow, Components.Step}

  @doc """
  Generates a random valid acyclic graph of configurable size.

  Edges only connect lower-indexed nodes to higher-indexed nodes,
  guaranteeing acyclicity.
  """
  def random_dag(opts \\ []) do
    min_nodes = Keyword.get(opts, :min_nodes, 2)
    max_nodes = Keyword.get(opts, :max_nodes, 10)

    bind(integer(min_nodes..max_nodes), fn node_count ->
      nodes = for i <- 1..node_count, do: :"node_#{i}"

      possible_edges =
        for i <- 0..(node_count - 2),
            j <- (i + 1)..(node_count - 1),
            do: {i, j}

      edge_booleans =
        case possible_edges do
          [] -> constant([])
          _ -> list_of(boolean(), length: length(possible_edges))
        end

      map(edge_booleans, fn bools ->
        edges =
          Enum.zip(possible_edges, bools)
          |> Enum.filter(fn {_, include?} -> include? end)
          |> Enum.map(fn {{i, j}, _} -> {Enum.at(nodes, i), Enum.at(nodes, j)} end)

        dag = Enum.reduce(nodes, Dag.new(), &Dag.add_node(&2, &1))
        Enum.reduce(edges, dag, fn {from, to}, d -> Dag.add_edge(d, from, to) end)
      end)
    end)
  end

  @doc """
  Generates a workflow with simple deterministic step functions.

  Each step returns `{:ok, node_id}` so results are deterministic.
  """
  def random_step_workflow(opts \\ []) do
    min_nodes = Keyword.get(opts, :min_nodes, 2)
    max_nodes = Keyword.get(opts, :max_nodes, 8)

    bind(integer(min_nodes..max_nodes), fn node_count ->
      nodes = for i <- 1..node_count, do: :"step_#{i}"

      possible_edges =
        for i <- 0..(node_count - 2),
            j <- (i + 1)..(node_count - 1),
            do: {i, j}

      edge_booleans =
        case possible_edges do
          [] -> constant([])
          _ -> list_of(boolean(), length: length(possible_edges))
        end

      map(edge_booleans, fn bools ->
        edges =
          Enum.zip(possible_edges, bools)
          |> Enum.filter(fn {_, include?} -> include? end)
          |> Enum.map(fn {{i, j}, _} -> {Enum.at(nodes, i), Enum.at(nodes, j)} end)

        predecessors_map =
          Enum.reduce(edges, %{}, fn {from, to}, acc ->
            Map.update(acc, to, [from], &[from | &1])
          end)

        Enum.reduce(nodes, Workflow.new(:random), fn node_id, w ->
          step = Step.new(node_id, fn _inputs, _ctx -> {:ok, node_id} end)
          preds = Map.get(predecessors_map, node_id, [])
          Workflow.add(w, step, after: preds)
        end)
      end)
    end)
  end
end
