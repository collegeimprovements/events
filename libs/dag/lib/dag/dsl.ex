defmodule Dag.DSL do
  @moduledoc """
  A declarative DSL for defining DAGs and workflows.

  ## Basic Usage

      defmodule MyWorkflow do
        use Dag.DSL

        step :start, label: "Begin"
        step :validate, label: "Validate Input", after: :start
        step :process, label: "Process Data", after: :validate
        step :complete, label: "Done", after: :process
      end

      # Get the DAG
      dag = MyWorkflow.dag()

      # Get step info
      MyWorkflow.steps()  #=> [:start, :validate, :process, :complete]

  ## Parallel Steps

      defmodule ParallelWorkflow do
        use Dag.DSL

        step :fetch, label: "Fetch Data"

        parallel :processing, after: :fetch do
          step :process_a, label: "Process A"
          step :process_b, label: "Process B"
          step :process_c, label: "Process C"
        end

        step :merge, label: "Merge Results", after: :processing
        step :complete, after: :merge
      end

  ## Conditional Edges

      defmodule ConditionalWorkflow do
        use Dag.DSL

        step :check, label: "Check Status"
        step :success, label: "Handle Success", after: :check, when: :success?
        step :failure, label: "Handle Failure", after: :check, when: :failure?
        step :complete, label: "Done", after: [:success, :failure]
      end

  ## Edge Data

      defmodule WeightedWorkflow do
        use Dag.DSL

        step :a
        step :b, after: :a, edge: %{weight: 10, label: "heavy"}
        step :c, after: :a, edge: %{weight: 1, label: "light"}
      end

  ## Multiple Dependencies

      defmodule FanInWorkflow do
        use Dag.DSL

        step :a
        step :b
        step :c, after: [:a, :b]  # Fan-in: c depends on both a and b
      end

  ## Inline DAG Building

      # For one-off DAGs without a module
      dag = Dag.DSL.build do
        step :a, label: "Start"
        step :b, label: "Middle", after: :a
        step :c, label: "End", after: :b
      end

  ## Module Callbacks

  When using `use Dag.DSL`, the following functions are generated:

  - `dag/0` - Returns the compiled DAG
  - `steps/0` - Returns list of step IDs (nodes)
  - `edges/0` - Returns list of edge tuples
  - `groups/0` - Returns map of group name to step IDs
  - `validate!/0` - Validates the DAG, raises on error
  """

  @doc false
  defmacro __using__(opts) do
    quote do
      import Dag.DSL, only: [step: 1, step: 2, edge: 2, edge: 3, parallel: 2, parallel: 3]

      Module.register_attribute(__MODULE__, :dag_nodes, accumulate: true)
      Module.register_attribute(__MODULE__, :dag_edges, accumulate: true)
      Module.register_attribute(__MODULE__, :dag_groups, accumulate: true)
      Module.put_attribute(__MODULE__, :dag_metadata, Keyword.get(unquote(opts), :metadata, %{}))

      @before_compile Dag.DSL
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    nodes = Module.get_attribute(env.module, :dag_nodes) |> Enum.reverse()
    edges = Module.get_attribute(env.module, :dag_edges) |> Enum.reverse()
    groups = Module.get_attribute(env.module, :dag_groups) |> Enum.reverse()
    metadata = Module.get_attribute(env.module, :dag_metadata)

    quote do
      @doc "Returns the compiled DAG"
      @spec dag() :: Dag.t()
      def dag do
        unquote(Macro.escape(build_dag(nodes, edges, groups, metadata)))
      end

      @doc "Returns the list of step IDs (nodes)"
      @spec steps() :: [atom()]
      def steps do
        unquote(Enum.map(nodes, fn {id, _} -> id end))
      end

      @doc "Returns the list of edges as `{from, to, data}` tuples"
      @spec edges() :: [{atom(), atom(), map()}]
      def edges do
        unquote(Macro.escape(edges))
      end

      @doc "Returns the groups map"
      @spec groups() :: %{atom() => [atom()]}
      def groups do
        unquote(Macro.escape(build_groups_map(groups)))
      end

      @doc "Validates the DAG, raises on error"
      @spec validate!() :: :ok
      def validate! do
        case Dag.validate(dag()) do
          :ok -> :ok
          {:error, reason} -> raise Dag.Error.from_tuple({:error, reason})
        end
      end
    end
  end

  # ============================================
  # DSL Macros
  # ============================================

  @doc """
  Defines a step (node) in the DAG.

  ## Options

  - `:label` - Human-readable label for the step
  - `:after` - Step(s) this step depends on (single atom or list)
  - `:edge` - Edge data for incoming edges (map)
  - `:when` - Condition atom for conditional edges
  - `:group` - Add step to a named group
  - Any other key-value pairs are stored as step data

  ## Examples

      step :start
      step :validate, label: "Validate Input"
      step :process, after: :validate, timeout: 5000
      step :merge, after: [:branch_a, :branch_b]
      step :conditional, after: :check, when: :success?
      step :weighted, after: :start, edge: %{weight: 10}
  """
  defmacro step(id, opts \\ []) do
    quote do
      Dag.DSL.__define_node__(__MODULE__, unquote(id), unquote(opts))
    end
  end

  @doc """
  Defines an explicit edge between nodes.

  ## Examples

      edge :a, :b
      edge :a, :b, %{weight: 10}
  """
  defmacro edge(from, to, data \\ quote(do: %{})) do
    quote do
      Dag.DSL.__define_edge__(__MODULE__, unquote(from), unquote(to), unquote(data))
    end
  end

  @doc """
  Defines a group of parallel steps.

  All steps defined within the block are added to a named group and
  automatically connected to the specified predecessor.

  ## Options

  - `:after` - Step(s) that must complete before this parallel group

  ## Examples

      parallel :processing, after: :fetch do
        step :process_a
        step :process_b
        step :process_c
      end

      # Creates steps process_a, process_b, process_c
      # All depend on :fetch
      # All are in group :processing
  """
  defmacro parallel(group_name, opts \\ [], do: block) do
    quote do
      Dag.DSL.__start_parallel__(__MODULE__, unquote(group_name), unquote(opts))
      unquote(block)
      Dag.DSL.__end_parallel__(__MODULE__, unquote(group_name))
    end
  end

  # ============================================
  # Internal Functions
  # ============================================

  @doc false
  def __define_node__(module, id, opts) do
    {after_nodes, opts} = Keyword.pop(opts, :after, [])
    {edge_data, opts} = Keyword.pop(opts, :edge, %{})
    {condition, opts} = Keyword.pop(opts, :when)
    {group, opts} = Keyword.pop(opts, :group)

    after_nodes = List.wrap(after_nodes)
    node_data = Map.new(opts)

    Module.put_attribute(module, :dag_nodes, {id, node_data})

    edge_data = add_condition_to_edge(edge_data, condition)

    for dep <- after_nodes do
      Module.put_attribute(module, :dag_edges, {dep, id, edge_data})
    end

    handle_parallel_context(module, id, after_nodes, edge_data)
    register_group_membership(module, group, id)

    :ok
  end

  defp add_condition_to_edge(edge_data, nil), do: edge_data
  defp add_condition_to_edge(edge_data, condition), do: Map.put(edge_data, :when, condition)

  defp handle_parallel_context(module, id, after_nodes, edge_data) do
    case Module.get_attribute(module, :current_parallel) do
      nil ->
        :ok

      {parallel_group, parallel_after} ->
        Module.put_attribute(module, :dag_groups, {parallel_group, id})
        register_parallel_edges(module, id, after_nodes, parallel_after, edge_data)
    end
  end

  defp register_parallel_edges(_module, _id, after_nodes, _parallel_after, _edge_data)
       when after_nodes != [],
       do: :ok

  defp register_parallel_edges(module, id, [], parallel_after, edge_data) do
    for dep <- List.wrap(parallel_after) do
      Module.put_attribute(module, :dag_edges, {dep, id, edge_data})
    end
  end

  defp register_group_membership(_module, nil, _id), do: :ok

  defp register_group_membership(module, group, id) do
    Module.put_attribute(module, :dag_groups, {group, id})
  end

  @doc false
  def __define_edge__(module, from, to, data) do
    Module.put_attribute(module, :dag_edges, {from, to, data})
    :ok
  end

  @doc false
  def __start_parallel__(module, group_name, opts) do
    after_nodes = Keyword.get(opts, :after, [])
    Module.put_attribute(module, :current_parallel, {group_name, after_nodes})
    :ok
  end

  @doc false
  def __end_parallel__(module, _group_name) do
    Module.delete_attribute(module, :current_parallel)
    :ok
  end

  # ============================================
  # Build Functions
  # ============================================

  @doc false
  def build_dag(nodes, edges, groups, metadata) do
    dag = Dag.new(metadata: metadata)

    # Add nodes
    dag =
      Enum.reduce(nodes, dag, fn {id, data}, acc ->
        Dag.add_node(acc, id, data)
      end)

    # Add edges
    dag =
      Enum.reduce(edges, dag, fn {from, to, data}, acc ->
        Dag.add_edge(acc, from, to, data)
      end)

    # Add groups
    groups_map = build_groups_map(groups)

    Enum.reduce(groups_map, dag, fn {group_name, node_ids}, acc ->
      Dag.add_to_group(acc, group_name, node_ids)
    end)
  end

  @doc false
  def build_groups_map(groups) do
    Enum.group_by(groups, fn {group, _node} -> group end, fn {_group, node} -> node end)
  end

  @doc """
  Builds a DAG inline using the DSL.

  ## Examples

      dag = Dag.DSL.build do
        step :a, label: "Start"
        step :b, after: :a
        step :c, after: :b
      end

      dag = Dag.DSL.build metadata: %{name: :my_dag} do
        step :x
        step :y, after: :x
      end
  """
  defmacro build(opts \\ [], do: block) do
    # Transform the block to use fully qualified function calls
    transformed_block = Macro.prewalk(block, fn
      {:step, meta, args} -> {{:., meta, [{:__aliases__, meta, [:Dag, :DSL, :Inline]}, :step]}, meta, args}
      {:edge, meta, args} -> {{:., meta, [{:__aliases__, meta, [:Dag, :DSL, :Inline]}, :edge]}, meta, args}
      {:parallel, meta, args} -> {{:., meta, [{:__aliases__, meta, [:Dag, :DSL, :Inline]}, :parallel]}, meta, args}
      other -> other
    end)

    quote do
      # Get metadata at runtime
      metadata = Keyword.get(unquote(opts), :metadata, %{})

      # Create a temporary agent to collect definitions
      {:ok, agent} = Agent.start_link(fn -> %{nodes: [], edges: [], groups: []} end)

      try do
        # Store agent in process dictionary for inline functions
        Process.put(:dag_dsl_agent, agent)

        unquote(transformed_block)

        # Get collected definitions
        %{nodes: nodes, edges: edges, groups: groups} = Agent.get(agent, & &1)

        # Build the DAG
        Dag.DSL.build_dag(
          Enum.reverse(nodes),
          Enum.reverse(edges),
          Enum.reverse(groups),
          metadata
        )
      after
        Process.delete(:dag_dsl_agent)
        Agent.stop(agent)
      end
    end
  end
end

defmodule Dag.DSL.Inline do
  @moduledoc false
  # Inline versions of DSL functions for use with Dag.DSL.build/2

  def step(id, opts \\ []) do
    agent = Process.get(:dag_dsl_agent)

    {after_nodes, opts} = Keyword.pop(opts, :after, [])
    {edge_data, opts} = Keyword.pop(opts, :edge, %{})
    {condition, opts} = Keyword.pop(opts, :when)
    {group, opts} = Keyword.pop(opts, :group)

    after_nodes = List.wrap(after_nodes)
    node_data = Map.new(opts)
    edge_data = add_condition(edge_data, condition)

    Agent.update(agent, fn state ->
      state = add_node_to_state(state, id, node_data)
      state = add_edges_to_state(state, id, after_nodes, edge_data)
      groups = add_to_group(state.groups, group, id)
      groups = handle_inline_parallel(groups, id, after_nodes, edge_data, agent, state)

      %{state | groups: groups}
    end)

    :ok
  end

  defp add_condition(edge_data, nil), do: edge_data
  defp add_condition(edge_data, condition), do: Map.put(edge_data, :when, condition)

  defp add_node_to_state(state, id, node_data) do
    %{state | nodes: [{id, node_data} | state.nodes]}
  end

  defp add_edges_to_state(state, id, after_nodes, edge_data) do
    edges =
      Enum.reduce(after_nodes, state.edges, fn dep, acc ->
        [{dep, id, edge_data} | acc]
      end)

    %{state | edges: edges}
  end

  defp add_to_group(groups, nil, _id), do: groups
  defp add_to_group(groups, group, id), do: [{group, id} | groups]

  defp handle_inline_parallel(groups, id, after_nodes, edge_data, agent, state) do
    case Process.get(:dag_dsl_parallel) do
      nil ->
        groups

      {parallel_group, parallel_after} ->
        groups = [{parallel_group, id} | groups]
        add_parallel_edges(after_nodes, parallel_after, edge_data, id, agent, state)
        groups
    end
  end

  defp add_parallel_edges(after_nodes, _parallel_after, _edge_data, _id, _agent, _state)
       when after_nodes != [],
       do: :ok

  defp add_parallel_edges([], parallel_after, edge_data, id, agent, state) do
    edges =
      Enum.reduce(List.wrap(parallel_after), state.edges, fn dep, acc ->
        [{dep, id, edge_data} | acc]
      end)

    Agent.update(agent, fn s -> %{s | edges: edges} end)
  end

  def edge(from, to, data \\ %{}) do
    agent = Process.get(:dag_dsl_agent)

    Agent.update(agent, fn state ->
      %{state | edges: [{from, to, data} | state.edges]}
    end)

    :ok
  end

  def parallel(group_name, opts \\ [], do: block) do
    after_nodes = Keyword.get(opts, :after, [])
    Process.put(:dag_dsl_parallel, {group_name, after_nodes})

    try do
      block.()
    after
      Process.delete(:dag_dsl_parallel)
    end

    :ok
  end
end
