defmodule Dag.Workflow do
  @moduledoc """
  A composable dataflow workflow built on a DAG.

  Combines a DAG structure with typed components, fact-based data flow,
  scoped runtime context, and a three-phase execution model.

  ## Quick Start

      alias Dag.{Workflow, Components.Step}

      workflow =
        Workflow.new(:text_analysis)
        |> Workflow.add(Step.new(:tokenize, fn inputs, _ctx ->
          {:ok, String.split(inputs[:__input__], " ")}
        end))
        |> Workflow.add(Step.new(:count, fn inputs, _ctx ->
          {:ok, length(inputs.tokenize)}
        end), after: :tokenize)
        |> Workflow.add(Step.new(:first, fn inputs, _ctx ->
          {:ok, List.first(inputs.tokenize)}
        end), after: :tokenize)

      # Shared computation: tokenize runs ONCE, feeds both count and first
      workflow = Workflow.react_until_satisfied(workflow, "hello world")

      Workflow.raw_productions(workflow)
      #=> %{tokenize: ["hello", "world"], count: 2, first: "hello"}

  ## Three-Phase Execution (External Dispatch)

      {workflow, runnables} = Workflow.prepare_for_dispatch(workflow)

      # Execute anywhere - local, worker pool, Oban, distributed
      results = Enum.map(runnables, &Dag.Runnable.execute/1)

      workflow = Enum.reduce(results, workflow, fn {id, result}, w ->
        Workflow.apply_result(w, id, result)
      end)

  ## Scoped Runtime Context

      workflow =
        Workflow.new(:api_pipeline)
        |> Workflow.put_run_context(%{
          _global: %{api_url: "https://api.example.com"},
          auth_step: %{api_key: "sk-..."}
        })
  """

  alias Dag.{Context, Engine, Fact, Runnable}

  @type component_status ::
          :pending | :running | :completed | :failed | :skipped
          | :not_activated | :compensated | :compensation_failed

  @type t :: %__MODULE__{
          name: atom(),
          dag: Dag.t(),
          components: %{Dag.node_id() => struct()},
          facts: %{reference() => Fact.t()},
          productions: %{Dag.node_id() => [reference()]},
          activations: %{Dag.node_id() => component_status()},
          context: Context.t(),
          state: :pending | :running | :satisfied | :failed | :halted,
          input_facts: [Fact.t()],
          metadata: map()
        }

  defstruct [
    :name,
    dag: %Dag{},
    components: %{},
    facts: %{},
    productions: %{},
    activations: %{},
    context: %Context{},
    state: :pending,
    input_facts: [],
    metadata: %{}
  ]

  # ============================================
  # Construction
  # ============================================

  @doc """
  Creates a new workflow.

  ## Options

  - `:context` - Initial `Dag.Context.t()`
  - `:metadata` - Arbitrary metadata
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      context: Keyword.get(opts, :context, %Context{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Adds a component to the workflow.

  ## Options

  - `:after` - Component(s) this depends on (atom or list)
  - `:edge` - Edge data for incoming edges (e.g., `%{when: :high}`)
  - `:group` - Add to a named group

  ## Examples

      workflow
      |> Workflow.add(Step.new(:a, &fun/2))
      |> Workflow.add(Step.new(:b, &fun/2), after: :a)
      |> Workflow.add(Step.new(:c, &fun/2), after: [:a, :b])
      |> Workflow.add(Step.new(:d, &fun/2), after: :branch, edge: %{when: :high})
  """
  @spec add(t(), struct(), keyword()) :: t()
  def add(%__MODULE__{} = workflow, component, opts \\ []) do
    id = Dag.Component.id(component)

    if Map.has_key?(workflow.components, id) do
      raise ArgumentError,
        "component #{inspect(id)} already exists in workflow; " <>
          "use Workflow.reset/1 to start fresh or choose a unique ID"
    end

    after_nodes = opts |> Keyword.get(:after, []) |> List.wrap()
    edge_data = Keyword.get(opts, :edge, %{})
    group = Keyword.get(opts, :group)

    dag = Dag.add_node(workflow.dag, id, %{component_type: component.__struct__})

    dag =
      Enum.reduce(after_nodes, dag, fn dep, d ->
        Dag.add_edge(d, dep, id, edge_data)
      end)

    dag =
      case group do
        nil -> dag
        g -> Dag.add_to_group(dag, g, [id])
      end

    %{workflow |
      dag: dag,
      components: Map.put(workflow.components, id, component),
      activations: Map.put(workflow.activations, id, :pending)
    }
  end

  @doc """
  Adds a step and chains it after the last-added component.

  Shortcut for common linear pipelines. Equivalent to:

      Workflow.add(w, Step.new(id, fun, opts), after: <previous>)

  ## Examples

      Workflow.new(:pipeline)
      |> Workflow.pipe(:parse, fn text -> {:ok, String.to_integer(text)} end)
      |> Workflow.pipe(:double, fn n -> {:ok, n * 2} end)
      |> Workflow.pipe(:format, fn n -> {:ok, to_string(n)} end)
  """
  @spec pipe(t(), Dag.node_id(), function(), keyword()) :: t()
  def pipe(%__MODULE__{} = workflow, id, function, opts \\ []) do
    step = Dag.Components.Step.new(id, function, opts)

    after_node =
      case last_component_id(workflow) do
        nil -> []
        prev -> prev
      end

    add(workflow, step, after: after_node)
  end

  defp last_component_id(%__MODULE__{dag: dag, components: components}) do
    case Dag.leaves(dag) do
      [] ->
        # No edges yet — find the most recently added component
        case Map.keys(components) do
          [] -> nil
          keys -> List.last(keys)
        end

      [single] ->
        single

      leaves ->
        # Multiple leaves — return as list so all become predecessors (fan-in)
        leaves
    end
  end

  @doc """
  Merges two workflows. w2 takes precedence on conflicts.
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = w1, %__MODULE__{} = w2) do
    %__MODULE__{
      name: w2.name || w1.name,
      dag: Dag.merge(w1.dag, w2.dag),
      components: Map.merge(w1.components, w2.components),
      facts: Map.merge(w1.facts, w2.facts),
      productions: Map.merge(w1.productions, w2.productions),
      activations: Map.merge(w1.activations, w2.activations),
      context: Context.merge(w1.context, w2.context),
      state: :pending,
      metadata: Map.merge(w1.metadata, w2.metadata)
    }
  end

  # ============================================
  # Context
  # ============================================

  @doc """
  Puts a context value.

  ## Examples

      Workflow.put_context(w, :global, :api_url, "https://...")
      Workflow.put_context(w, :scoped, :my_step, :key, "value")
      Workflow.put_context(w, :default, :timeout, 5000)
  """
  @spec put_context(t(), :global | :default, atom(), term()) :: t()
  def put_context(%__MODULE__{} = w, :global, key, value) do
    %{w | context: Context.put_global(w.context, key, value)}
  end

  def put_context(%__MODULE__{} = w, :default, key, value) do
    %{w | context: Context.put_default(w.context, key, value)}
  end

  @spec put_context(t(), :scoped, Dag.node_id(), atom(), term()) :: t()
  def put_context(%__MODULE__{} = w, :scoped, component_id, key, value) do
    %{w | context: Context.put_scoped(w.context, component_id, key, value)}
  end

  @doc """
  Sets runtime context in bulk, Runic-style.

  Use `:_global` key for values available to all components.
  Other keys are component IDs with scoped values.

  ## Examples

      Workflow.put_run_context(workflow, %{
        _global: %{workspace_id: "ws1"},
        call_llm: %{api_key: "sk-...", model: "claude-4"},
        fetch_data: %{timeout: 30_000}
      })
  """
  @spec put_run_context(t(), map()) :: t()
  def put_run_context(%__MODULE__{} = w, context_map) when is_map(context_map) do
    Enum.reduce(context_map, w, fn
      {:_global, values}, acc ->
        Enum.reduce(values, acc, fn {k, v}, a -> put_context(a, :global, k, v) end)

      {component_id, values}, acc ->
        Enum.reduce(values, acc, fn {k, v}, a -> put_context(a, :scoped, component_id, k, v) end)
    end)
  end

  # ============================================
  # Execution
  # ============================================

  @doc """
  Performs a single reaction pass.

  Finds ready components, executes them, and applies results.
  """
  @spec react(t(), term()) :: t()
  def react(%__MODULE__{state: :pending} = w, input) do
    w
    |> inject_input(input)
    |> Map.put(:state, :running)
    |> Engine.react_once()
  end

  def react(%__MODULE__{} = w, _input), do: Engine.react_once(w)

  @doc """
  Reacts iteratively until no more components can fire.

  ## Options

  - `:async` - Run ready components in parallel (default: false)
  - `:max_concurrency` - Max parallel tasks (default: `System.schedulers_online()`)
  - `:max_iterations` - Safety limit (default: 1000)
  """
  @spec react_until_satisfied(t(), term(), keyword()) :: t()
  def react_until_satisfied(workflow, input, opts \\ [])

  def react_until_satisfied(%__MODULE__{state: state} = w, _input, _opts)
      when state in [:satisfied, :halted] do
    w
  end

  def react_until_satisfied(%__MODULE__{} = w, input, opts) do
    w
    |> inject_input(input)
    |> Map.put(:state, :running)
    |> Engine.react_until_satisfied(opts)
  end

  @doc """
  Prepares ready components for external dispatch.

  Returns `{workflow, [Runnable.t()]}`.
  """
  @spec prepare_for_dispatch(t()) :: {t(), [Runnable.t()]}
  def prepare_for_dispatch(%__MODULE__{state: :pending} = w) do
    # Cannot dispatch without input - return empty
    {w, []}
  end

  def prepare_for_dispatch(%__MODULE__{} = w) do
    Engine.prepare_dispatch(w)
  end

  @doc """
  Prepares ready components for dispatch after injecting input.
  """
  @spec prepare_for_dispatch(t(), term()) :: {t(), [Runnable.t()]}
  def prepare_for_dispatch(%__MODULE__{} = w, input) do
    w
    |> inject_input(input)
    |> Map.put(:state, :running)
    |> Engine.prepare_dispatch()
  end

  @doc """
  Applies an execution result back to the workflow.
  """
  @spec apply_result(t(), Dag.node_id(), Dag.Runnable.result()) :: t()
  def apply_result(%__MODULE__{} = w, component_id, result) do
    Engine.apply_result(w, component_id, result)
  end

  @doc """
  Runs saga compensation for completed sagas (reverse order).
  """
  @spec compensate(t()) :: t()
  def compensate(%__MODULE__{} = w), do: Engine.compensate(w)

  # ============================================
  # Graft + Continue
  # ============================================

  @doc """
  Grafts a component onto a running or completed workflow.

  Like `add/3` but works on non-pending workflows. After grafting,
  call `continue/2` to resume execution.

  ## Options

  Same as `add/3`: `:after`, `:edge`, `:group`

  ## Examples

      w = Workflow.react_until_satisfied(w, input)
      w =
        w
        |> Workflow.graft(Step.new(:extra, &process/2), after: :check)
        |> Workflow.graft(Step.new(:extra2, &process2/2), after: :extra)
        |> Workflow.continue()
  """
  @spec graft(t(), struct(), keyword()) :: t()
  def graft(%__MODULE__{} = workflow, component, opts \\ []) do
    workflow
    |> add(component, opts)
    |> Map.put(:state, :running)
  end

  @doc """
  Resumes execution from current state without injecting new input.

  Use after `graft/3` to execute newly added components.

  ## Options

  Same as `react_until_satisfied/3`: `:async`, `:max_concurrency`, `:max_iterations`
  """
  @spec continue(t(), keyword()) :: t()
  def continue(workflow, opts \\ [])

  def continue(%__MODULE__{state: :pending} = w, _opts), do: w

  def continue(%__MODULE__{} = w, opts) do
    w
    |> Map.put(:state, :running)
    |> Engine.react_until_satisfied(opts)
  end

  # ============================================
  # Checkpoint / Restore
  # ============================================

  @doc """
  Creates a serializable checkpoint of the workflow state.

  The checkpoint includes all execution state (DAG, activations, facts,
  productions, context, metadata) but not component functions. Use
  `:erlang.term_to_binary/1` to serialize the result.

  ## Examples

      checkpoint = Workflow.checkpoint(w)
      binary = :erlang.term_to_binary(checkpoint)
  """
  @spec checkpoint(t()) :: map()
  def checkpoint(%__MODULE__{} = w) do
    %{
      name: w.name,
      dag: Dag.to_map(w.dag),
      activations: w.activations,
      facts: w.facts,
      productions: w.productions,
      context: %{
        global: w.context.global,
        scoped: w.context.scoped,
        defaults: w.context.defaults
      },
      metadata: w.metadata,
      state: w.state,
      input_facts: w.input_facts
    }
  end

  @doc """
  Restores a workflow from a checkpoint and a component map.

  The component map provides the functions that were stripped during
  checkpointing. Keys are component IDs, values are component structs.

  ## Examples

      checkpoint = :erlang.binary_to_term(binary)
      w = Workflow.restore(checkpoint, %{
        step_a: Step.new(:step_a, &MyModule.step_a/2),
        step_b: Step.new(:step_b, &MyModule.step_b/2)
      })
  """
  @spec restore(map(), %{Dag.node_id() => struct()}) :: {:ok, t()} | {:error, term()}
  def restore(checkpoint, components) when is_map(checkpoint) and is_map(components) do
    {:ok, dag} = Dag.from_map(checkpoint.dag)
    dag_ids = MapSet.new(Dag.node_ids(dag))
    comp_ids = MapSet.new(Map.keys(components))
    missing = MapSet.difference(dag_ids, comp_ids)

    case MapSet.size(missing) do
      0 ->
        {:ok,
         %__MODULE__{
           name: checkpoint.name,
           dag: dag,
           components: components,
           facts: checkpoint.facts,
           productions: checkpoint.productions,
           activations: checkpoint.activations,
           context: %Context{
             global: checkpoint.context.global,
             scoped: checkpoint.context.scoped,
             defaults: checkpoint.context.defaults
           },
           metadata: checkpoint.metadata,
           state: checkpoint.state,
           input_facts: checkpoint.input_facts
         }}

      _ ->
        {:error, {:missing_components, MapSet.to_list(missing)}}
    end
  end

  # ============================================
  # Inspection
  # ============================================

  @doc "Returns components that are ready to fire."
  @spec ready_components(t()) :: [Dag.node_id()]
  def ready_components(%__MODULE__{} = w), do: Engine.find_ready(w)

  @doc "Returns all produced facts grouped by component."
  @spec productions(t()) :: %{Dag.node_id() => [Fact.t()]}
  def productions(%__MODULE__{} = w) do
    Map.new(w.productions, fn {component_id, fact_ids} ->
      facts = Enum.map(fact_ids, &Map.fetch!(w.facts, &1))
      {component_id, facts}
    end)
  end

  @doc "Returns facts produced by a specific component."
  @spec production(t(), Dag.node_id()) :: [Fact.t()]
  def production(%__MODULE__{} = w, component_id) do
    w.productions
    |> Map.get(component_id, [])
    |> Enum.map(&Map.fetch!(w.facts, &1))
  end

  @doc "Returns raw output values by component (unwrapped from Facts)."
  @spec raw_productions(t()) :: %{Dag.node_id() => term()}
  def raw_productions(%__MODULE__{} = w) do
    w.productions
    |> Enum.reject(fn {id, _} -> id == :__input__ end)
    |> Map.new(fn {component_id, fact_ids} ->
      values = Enum.map(fact_ids, fn fid -> Map.fetch!(w.facts, fid).value end)

      value =
        case values do
          [single] -> single
          multiple -> multiple
        end

      {component_id, value}
    end)
  end

  @doc "Returns the activation status of a component."
  @spec status(t(), Dag.node_id()) :: component_status()
  def status(%__MODULE__{} = w, component_id) do
    Map.get(w.activations, component_id, :pending)
  end

  @doc """
  Traces the lineage of a fact back through the DAG to input.

  Returns a list of facts in causal order (earliest first).
  """
  @spec lineage(t(), reference()) :: [Fact.t()]
  def lineage(%__MODULE__{} = w, fact_id) do
    do_lineage(w, fact_id, MapSet.new())
  end

  defp do_lineage(w, fact_id, visited) do
    case {Map.fetch(w.facts, fact_id), MapSet.member?(visited, fact_id)} do
      {_, true} ->
        []

      {{:ok, %Fact{source: :__input__} = fact}, false} ->
        [fact]

      {{:ok, fact}, false} ->
        visited = MapSet.put(visited, fact_id)
        # Trace through DAG predecessors of the producing component
        predecessors = Dag.predecessors(w.dag, fact.source)

        predecessor_facts =
          Enum.flat_map(predecessors, fn pred_id ->
            find_source_facts(w, pred_id)
          end)

        # Also include input facts if this is a root component
        predecessor_facts =
          case predecessors do
            [] -> find_source_facts(w, :__input__)
            _ -> predecessor_facts
          end

        source_lineages =
          Enum.flat_map(predecessor_facts, fn sf -> do_lineage(w, sf.id, visited) end)

        source_lineages ++ [fact]

      {:error, _} ->
        []
    end
  end

  @doc "Validates the workflow structure, component configs, and DAG/component sync."
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = w) do
    with :ok <- Dag.validate(w.dag),
         :ok <- validate_components(w),
         :ok <- validate_sync(w) do
      :ok
    end
  end

  @doc "Returns the error reason for a failed component, or nil."
  @spec error(t(), Dag.node_id()) :: term() | nil
  def error(%__MODULE__{} = w, component_id) do
    w.metadata |> Map.get(:errors, %{}) |> Map.get(component_id)
  end

  @doc "Returns the execution log entries in chronological order."
  @spec execution_log(t()) :: [map()]
  def execution_log(%__MODULE__{} = w) do
    w.metadata |> Map.get(:log, []) |> Enum.reverse()
  end

  @doc """
  Resets a workflow for re-execution with new input.

  Clears all facts, productions, activations, and execution state
  while preserving components, DAG structure, and context.
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = w) do
    activations = Map.new(w.components, fn {id, _} -> {id, :pending} end)

    %{w |
      facts: %{},
      productions: %{},
      activations: activations,
      state: :pending,
      input_facts: [],
      metadata: Map.drop(w.metadata, [:log, :errors, :iterations])
    }
  end

  @doc """
  Generates a Mermaid diagram with component statuses color-coded.

  ## Options

  Accepts all options from `Dag.to_mermaid/2` plus:
  - `:show_status` - Color nodes by activation status (default: true)
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = w, opts \\ []) do
    show_status = Keyword.get(opts, :show_status, true)

    opts =
      if show_status do
        opts
        |> Keyword.put(:node_label, fn id, _data ->
          component = Map.get(w.components, id)
          name = if component, do: Dag.Component.name(component), else: to_string(id)
          status = Map.get(w.activations, id)

          case status do
            nil -> name
            :pending -> name
            status -> "#{name} [#{status}]"
          end
        end)
        |> Keyword.put(:node_style, fn id, _data ->
          case Map.get(w.activations, id) do
            :completed -> "completed"
            :failed -> "failed"
            :running -> "running"
            :skipped -> "skipped"
            :not_activated -> "skipped"
            _ -> nil
          end
        end)
        |> Keyword.put(:styles, %{
          completed: "fill:#90EE90,stroke:#228B22",
          failed: "fill:#FF6B6B,stroke:#DC143C",
          running: "fill:#87CEEB,stroke:#4682B4",
          skipped: "fill:#D3D3D3,stroke:#808080"
        })
      else
        opts
      end

    Dag.to_mermaid(w.dag, opts)
  end

  @doc "Returns the underlying DAG for visualization."
  @spec to_dag(t()) :: Dag.t()
  def to_dag(%__MODULE__{dag: dag}), do: dag

  # ============================================
  # Private
  # ============================================

  defp inject_input(%__MODULE__{} = w, input) do
    fact = Fact.new(input, source: :__input__, type: :input)

    %{w |
      facts: Map.put(w.facts, fact.id, fact),
      productions: Map.put(w.productions, :__input__, [fact.id]),
      input_facts: [fact]
    }
  end

  defp find_source_facts(%__MODULE__{} = w, source_id) do
    w.productions
    |> Map.get(source_id, [])
    |> Enum.map(&Map.fetch!(w.facts, &1))
  end

  defp validate_components(%__MODULE__{components: components}) do
    errors =
      Enum.reduce(components, [], fn {id, component}, acc ->
        case Dag.Component.validate(component) do
          :ok -> acc
          {:error, reason} -> [{id, reason} | acc]
        end
      end)

    case errors do
      [] -> :ok
      errs -> {:error, {:invalid_components, errs}}
    end
  end

  defp validate_sync(%__MODULE__{dag: dag, components: components}) do
    dag_ids = MapSet.new(Dag.node_ids(dag))
    comp_ids = MapSet.new(Map.keys(components))

    orphan_components = MapSet.difference(comp_ids, dag_ids)
    orphan_nodes = MapSet.difference(dag_ids, comp_ids)

    cond do
      MapSet.size(orphan_components) > 0 ->
        {:error, {:components_without_nodes, MapSet.to_list(orphan_components)}}

      MapSet.size(orphan_nodes) > 0 ->
        {:error, {:nodes_without_components, MapSet.to_list(orphan_nodes)}}

      true ->
        :ok
    end
  end
end

defimpl Inspect, for: Dag.Workflow do
  import Inspect.Algebra

  def inspect(%Dag.Workflow{} = w, opts) do
    completed =
      Enum.count(w.activations, fn {_, s} -> s == :completed end)

    total = map_size(w.components)

    info = [
      name: w.name,
      state: w.state,
      components: "#{completed}/#{total}",
      facts: map_size(w.facts)
    ]

    concat(["#Workflow<", to_doc(info, opts), ">"])
  end
end
