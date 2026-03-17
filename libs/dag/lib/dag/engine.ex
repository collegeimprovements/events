defmodule Dag.Engine do
  @moduledoc """
  Execution engine for DAG workflows.

  Drives the three-phase execution model:
  1. **Find ready** - Identify components whose inputs are satisfied
  2. **Prepare** - Create Runnables from ready components
  3. **Execute** - Run runnables (sync or async)
  4. **Apply** - Convert results to facts and propagate

  ## Execution Modes

  | Mode | Function | Use Case |
  |------|----------|----------|
  | Single pass | `react_once/1` | Step-by-step control |
  | Iterative | `react_until_satisfied/2` | Run to completion |
  | Async | `react_until_satisfied(w, async: true)` | Parallel execution |
  | External | `prepare_dispatch/1` + `apply_result/3` | Job queues, distributed |

  ## Failure Propagation

  When a component fails, all downstream components that depend exclusively
  on the failed path are marked `:failed`. Components with alternative
  (non-failed) predecessors remain eligible.

  ## Execution Log

  Every component execution is recorded in `workflow.metadata.log` as:

      %{component_id: id, status: :completed | :failed, duration_us: μs, timestamp: mono_time}
  """

  require Logger

  alias Dag.{Context, Fact, Invokable, Runnable, Workflow}

  # ============================================
  # Public API
  # ============================================

  @doc """
  Performs a single execution pass.

  Finds ready components, prepares runnables, executes them synchronously,
  and applies results. Returns the updated workflow.
  """
  @spec react_once(Workflow.t()) :: Workflow.t()
  def react_once(%Workflow{} = w) do
    case find_ready(w) do
      [] ->
        mark_satisfied(w)

      component_ids ->
        {runnables, w} = prepare_components(w, component_ids)
        results = execute_sync(runnables, w.components)
        apply_results(w, results)
    end
  end

  @doc """
  Iteratively reacts until no more components can fire.

  ## Options

  - `:async` - Run ready components in parallel (default: false)
  - `:max_concurrency` - Maximum parallel tasks (default: `System.schedulers_online()`)
  - `:max_iterations` - Safety limit (default: 1000)
  - `:on_complete` - Callback `fn component_id, result, workflow -> :ok` (optional)
  """
  @spec react_until_satisfied(Workflow.t(), keyword()) :: Workflow.t()
  def react_until_satisfied(%Workflow{} = w, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    max_iterations = Keyword.get(opts, :max_iterations, 1000)

    do_react_loop(w, async, max_concurrency, max_iterations, 0, opts)
  end

  @doc """
  Finds components whose inputs are all satisfied and can activate.
  """
  @spec find_ready(Workflow.t()) :: [Dag.node_id()]
  def find_ready(%Workflow{} = w) do
    w.components
    |> Enum.filter(fn {id, _} -> w.activations[id] == :pending end)
    |> Enum.filter(fn {id, component} ->
      predecessors = Dag.predecessors(w.dag, id)

      inputs_satisfied?(w, predecessors) and
        component_can_activate?(w, id, component, predecessors)
    end)
    |> Enum.map(fn {id, _} -> id end)
  end

  @doc """
  Prepares ready components for external dispatch.

  Returns `{workflow, [Runnable.t()]}`. The workflow has components
  marked as `:running`. Execute the runnables however you want, then
  call `apply_result/3` for each.
  """
  @spec prepare_dispatch(Workflow.t()) :: {Workflow.t(), [Runnable.t()]}
  def prepare_dispatch(%Workflow{} = w) do
    {runnables, w} = prepare_components(w, find_ready(w))
    {w, runnables}
  end

  @doc """
  Applies a single component result back to the workflow.
  """
  @spec apply_result(Workflow.t(), Dag.node_id(), Dag.Runnable.result()) :: Workflow.t()
  def apply_result(%Workflow{} = w, component_id, result) do
    apply_result(w, component_id, result, [])
  end

  @doc false
  def apply_result(%Workflow{} = w, component_id, result, opts) do
    component = Map.fetch!(w.components, component_id)
    start_time = System.monotonic_time(:microsecond)

    case Invokable.apply_result(component, result) do
      {:ok, facts} ->
        duration = System.monotonic_time(:microsecond) - start_time

        w
        |> store_facts(component_id, facts)
        |> mark_completed(component_id)
        |> log_execution(component_id, :completed, duration)
        |> update_conditional_routing(component_id, facts)
        |> fire_callback(opts, component_id, result)

      {:error, reason} ->
        duration = System.monotonic_time(:microsecond) - start_time

        w
        |> mark_failed(component_id, reason)
        |> log_execution(component_id, :failed, duration)
        |> propagate_failure(component_id)
        |> fire_callback(opts, component_id, {:error, reason})
    end
  end

  @doc """
  Runs saga compensation in reverse order for completed sagas.

  Called when a workflow fails and needs to roll back.
  """
  @spec compensate(Workflow.t()) :: Workflow.t()
  def compensate(%Workflow{} = w) do
    completed_sagas =
      w.components
      |> Enum.filter(fn {id, component} ->
        is_struct(component, Dag.Components.Saga) and
          w.activations[id] == :completed and
          Dag.Components.Saga.compensatable?(component)
      end)
      |> Enum.sort_by(fn {id, _} -> completion_order(w, id) end, :desc)

    Enum.reduce(completed_sagas, w, fn {id, saga}, acc ->
      inputs = gather_input_values(acc, id)
      result_value = get_production_value(acc, id)
      context = Context.resolve_all(acc.context, id)

      try do
        case saga.compensate.(inputs, result_value, context) do
          :ok -> mark_compensated(acc, id)
          {:error, _reason} -> mark_compensation_failed(acc, id)
        end
      rescue
        e ->
          Logger.warning(
            "compensate raised for #{id}: #{Exception.message(e)}"
          )

          mark_compensation_failed(acc, id)
      end
    end)
  end

  # ============================================
  # Private - Execution Loop
  # ============================================

  defp do_react_loop(%Workflow{} = w, _async, _max_concurrency, max_iterations, iteration, _opts)
       when iteration >= max_iterations do
    w
    |> finalize_pending_components()
    |> Map.put(:state, :halted)
    |> Map.put(:metadata, Map.put(w.metadata, :iterations, iteration))
  end

  defp do_react_loop(%Workflow{} = w, async, max_concurrency, max_iterations, iteration, opts) do
    case find_ready(w) do
      [] ->
        w = finalize_pending_components(w)
        state = if has_failures?(w), do: :failed, else: :satisfied
        %{w | state: state, metadata: Map.put(w.metadata, :iterations, iteration + 1)}

      component_ids ->
        {runnables, w} = prepare_components(w, component_ids)

        results =
          case async do
            true -> execute_async(runnables, max_concurrency, w.components)
            false -> execute_sync(runnables, w.components)
          end

        w = apply_results_with_opts(w, results, opts)
        do_react_loop(w, async, max_concurrency, max_iterations, iteration + 1, opts)
    end
  end

  # ============================================
  # Private - Readiness Checks
  # ============================================

  defp inputs_satisfied?(%Workflow{} = w, []) do
    w.input_facts != []
  end

  defp inputs_satisfied?(%Workflow{} = w, predecessors) do
    Enum.all?(predecessors, fn pred_id ->
      Map.get(w.activations, pred_id) in [:completed, :failed, :skipped]
    end)
  end

  defp component_can_activate?(%Workflow{} = w, id, component, predecessors) do
    # If ALL predecessors failed, this component cannot activate
    case all_predecessors_failed_or_skipped?(w, predecessors) do
      true ->
        false

      false ->
        available_facts = gather_input_facts(w, id, predecessors)
        context = Context.resolve_all(w.context, id)

        case available_facts do
          empty when map_size(empty) == 0 and predecessors != [] ->
            false

          facts ->
            try do
              Invokable.activates?(component, facts, context)
            rescue
              e ->
                Logger.warning(
                  "activates? raised for #{id}: #{Exception.message(e)}"
                )

                false
            end
        end
    end
  end

  defp all_predecessors_failed_or_skipped?(_w, []), do: false

  defp all_predecessors_failed_or_skipped?(w, predecessors) do
    Enum.all?(predecessors, fn pred_id ->
      Map.get(w.activations, pred_id) in [:failed, :skipped]
    end)
  end

  # ============================================
  # Private - Prepare
  # ============================================

  defp prepare_components(%Workflow{} = w, component_ids) do
    Enum.map_reduce(component_ids, w, fn id, acc ->
      component = Map.fetch!(acc.components, id)
      predecessors = Dag.predecessors(acc.dag, id)
      inputs = gather_input_facts(acc, id, predecessors)
      context = Context.resolve_all(acc.context, id)

      runnable = Invokable.prepare(component, inputs, context)
      acc = %{acc | activations: Map.put(acc.activations, id, :running)}

      {runnable, acc}
    end)
  end

  defp gather_input_facts(%Workflow{} = w, _id, []) do
    case w.input_facts do
      [] -> %{}
      facts -> %{__input__: facts}
    end
  end

  defp gather_input_facts(%Workflow{} = w, id, predecessors) do
    Enum.reduce(predecessors, %{}, fn pred_id, acc ->
      # Skip failed/skipped predecessors — don't block on them
      pred_status = Map.get(w.activations, pred_id)

      case pred_status do
        status when status in [:failed, :skipped] ->
          acc

        _ ->
          edge_data = get_edge_data(w, pred_id, id)
          pred_facts = get_predecessor_facts(w, pred_id)

          case {Map.get(edge_data, :when), pred_facts} do
            {_, []} ->
              acc

            {nil, facts} ->
              Map.put(acc, pred_id, facts)

            {condition, facts} ->
              matching = Enum.filter(facts, &matches_condition?(&1, condition))

              case matching do
                [] -> acc
                matched -> Map.put(acc, pred_id, matched)
              end
          end
      end
    end)
  end

  defp get_edge_data(%Workflow{} = w, from, to) do
    case Dag.get_edge(w.dag, from, to) do
      {:ok, data} -> data
      {:error, _} -> %{}
    end
  end

  defp get_predecessor_facts(%Workflow{} = w, pred_id) do
    w.productions
    |> Map.get(pred_id, [])
    |> Enum.map(&Map.fetch!(w.facts, &1))
  end

  # Match on type tag first (set by Branch via Fact.from_output with type:)
  defp matches_condition?(%Fact{type: type}, condition) when is_atom(condition) and not is_nil(type) do
    type == condition
  end

  # Fallback: check branch tag in value
  defp matches_condition?(%Fact{value: %{branch: tag}}, condition) when is_atom(condition) do
    tag == condition
  end

  # No condition or non-atom condition: always matches
  defp matches_condition?(_fact, _condition), do: true

  # ============================================
  # Private - Execute
  # ============================================

  defp execute_sync(runnables, components) do
    Enum.map(runnables, fn runnable ->
      execute_one(runnable, components)
    end)
  end

  defp execute_async(runnables, max_concurrency, components) do
    runnables
    |> Task.async_stream(
      fn runnable ->
        execute_one(runnable, components)
      end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.zip(runnables)
    |> Enum.map(fn
      {{:ok, result}, _runnable} ->
        result

      {{:exit, reason}, runnable} ->
        {runnable.component_id, {:error, {:exit, reason}}}
    end)
  end

  defp execute_one(runnable, components) do
    component = Map.get(components, runnable.component_id)
    timeout = Map.get(runnable.metadata, :timeout)

    case retry_config(component) do
      nil -> execute_with_timeout(runnable, timeout)
      config -> execute_with_retry(runnable, timeout, config)
    end
  end

  # ============================================
  # Private - Retry
  # ============================================

  defp retry_config(%{opts: opts}) when is_map(opts) do
    case Map.get(opts, :retries) do
      n when is_integer(n) and n > 0 ->
        %{
          max_retries: n,
          delay: Map.get(opts, :retry_delay, 100),
          backoff: Map.get(opts, :retry_backoff, :fixed),
          max_delay: Map.get(opts, :max_delay, 30_000)
        }

      _ ->
        nil
    end
  end

  defp retry_config(_), do: nil

  defp execute_with_retry(runnable, timeout, config) do
    do_retry_loop(runnable, timeout, config, 0)
  end

  defp do_retry_loop(runnable, timeout, %{max_retries: max} = config, attempt) do
    case execute_with_timeout(runnable, timeout) do
      {_id, {:ok, _}} = success ->
        success

      {id, {:error, _reason}} = error ->
        if attempt < max do
          sleep_ms = compute_backoff(config.delay, config.backoff, attempt, config.max_delay)

          Logger.debug(
            "Retrying #{id} (attempt #{attempt + 1}/#{max}) after #{sleep_ms}ms"
          )

          Process.sleep(sleep_ms)
          do_retry_loop(runnable, timeout, config, attempt + 1)
        else
          error
        end
    end
  end

  defp compute_backoff(base, :fixed, _attempt, _max), do: base
  defp compute_backoff(base, :linear, attempt, max), do: min(base * (attempt + 1), max)

  defp compute_backoff(base, :exponential, attempt, max) do
    min(round(base * :math.pow(2, attempt)), max)
  end

  defp execute_with_timeout(runnable, nil), do: Runnable.execute(runnable)

  defp execute_with_timeout(runnable, timeout) when is_integer(timeout) do
    task = Task.async(fn -> Runnable.execute(runnable) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {runnable.component_id, {:error, :timeout}}
    end
  end

  # ============================================
  # Private - Apply
  # ============================================

  defp apply_results(%Workflow{} = w, results) do
    apply_results_with_opts(w, results, [])
  end

  defp apply_results_with_opts(%Workflow{} = w, results, opts) do
    Enum.reduce(results, w, fn {component_id, result}, acc ->
      apply_result(acc, component_id, result, opts)
    end)
  end

  defp store_facts(%Workflow{} = w, component_id, facts) do
    {new_facts, fact_ids} =
      Enum.reduce(facts, {w.facts, []}, fn fact, {fmap, ids} ->
        {Map.put(fmap, fact.id, fact), [fact.id | ids]}
      end)

    existing = Map.get(w.productions, component_id, [])

    %{w |
      facts: new_facts,
      productions: Map.put(w.productions, component_id, existing ++ Enum.reverse(fact_ids))
    }
  end

  defp mark_completed(%Workflow{} = w, component_id) do
    %{w | activations: Map.put(w.activations, component_id, :completed)}
  end

  defp mark_failed(%Workflow{} = w, component_id, reason) do
    errors = Map.get(w.metadata, :errors, %{})
    metadata = Map.put(w.metadata, :errors, Map.put(errors, component_id, reason))
    %{w | activations: Map.put(w.activations, component_id, :failed), metadata: metadata}
  end

  defp mark_satisfied(%Workflow{} = w) do
    w = finalize_pending_components(w)
    state = if has_failures?(w), do: :failed, else: :satisfied
    %{w | state: state}
  end

  @terminal_statuses [:completed, :failed, :skipped, :not_activated]

  # After the react loop terminates, mark pending components whose
  # predecessors are all terminal but that never activated (e.g. Rules
  # whose condition was never true) as :not_activated.
  # Iterates until stable because map ordering may process children before parents.
  defp finalize_pending_components(%Workflow{} = w) do
    do_finalize(w)
  end

  defp do_finalize(%Workflow{} = w) do
    {w, changed} =
      Enum.reduce(w.activations, {w, false}, fn
        {id, :pending}, {acc, changed} ->
          predecessors = Dag.predecessors(acc.dag, id)

          all_terminal =
            predecessors == [] or
              Enum.all?(predecessors, fn pred ->
                Map.get(acc.activations, pred) in @terminal_statuses
              end)

          case all_terminal do
            true ->
              # If all predecessors are dead (failed/skipped), this is a failure
              # propagation. Otherwise it's a component that never activated
              # (e.g. Rule whose condition was never true).
              all_dead =
                predecessors != [] and
                  Enum.all?(predecessors, fn pred ->
                    Map.get(acc.activations, pred) in [:failed, :skipped]
                  end)

              acc =
                if all_dead do
                  mark_failed(acc, id, :upstream_failure)
                else
                  %{acc | activations: Map.put(acc.activations, id, :not_activated)}
                end

              {acc, true}

            false ->
              {acc, changed}
          end

        _, {acc, changed} ->
          {acc, changed}
      end)

    # Keep iterating until no more changes (handles dependency chains)
    case changed do
      true -> do_finalize(w)
      false -> w
    end
  end

  defp mark_compensated(%Workflow{} = w, component_id) do
    %{w | activations: Map.put(w.activations, component_id, :compensated)}
  end

  defp mark_compensation_failed(%Workflow{} = w, component_id) do
    %{w | activations: Map.put(w.activations, component_id, :compensation_failed)}
  end

  defp has_failures?(%Workflow{} = w) do
    Enum.any?(w.activations, fn {_id, status} -> status == :failed end)
  end

  # ============================================
  # Private - Failure Propagation
  # ============================================

  defp propagate_failure(%Workflow{} = w, failed_id) do
    # Find all descendants and mark those with no viable path as :failed
    descendants = Dag.descendants(w.dag, failed_id)

    Enum.reduce(descendants, w, fn desc_id, acc ->
      case Map.get(acc.activations, desc_id) do
        :pending -> maybe_fail_descendant(acc, desc_id)
        _ -> acc
      end
    end)
  end

  defp maybe_fail_descendant(%Workflow{} = w, component_id) do
    predecessors = Dag.predecessors(w.dag, component_id)

    # If ALL predecessors are failed/skipped, this component is dead
    all_dead =
      Enum.all?(predecessors, fn pred_id ->
        Map.get(w.activations, pred_id) in [:failed, :skipped]
      end)

    case all_dead do
      true ->
        w
        |> mark_failed(component_id, :upstream_failure)
        |> propagate_failure(component_id)

      false ->
        w
    end
  end

  # ============================================
  # Private - Conditional Routing
  # ============================================

  defp update_conditional_routing(%Workflow{} = w, component_id, facts) do
    successors = Dag.successors(w.dag, component_id)

    Enum.reduce(successors, w, fn succ_id, acc ->
      edge_data = get_edge_data(acc, component_id, succ_id)

      case Map.get(edge_data, :when) do
        nil ->
          acc

        condition ->
          has_match = Enum.any?(facts, &matches_condition?(&1, condition))

          case has_match do
            true -> acc
            false -> maybe_skip_component(acc, succ_id)
          end
      end
    end)
  end

  defp maybe_skip_component(%Workflow{} = w, component_id) do
    all_preds = Dag.predecessors(w.dag, component_id)

    all_preds_done =
      Enum.all?(all_preds, fn pred ->
        Map.get(w.activations, pred) in [:completed, :failed, :skipped]
      end)

    case all_preds_done do
      false ->
        w

      true ->
        any_match =
          Enum.any?(all_preds, fn pred ->
            pred_facts = get_predecessor_facts(w, pred)
            edge_data = get_edge_data(w, pred, component_id)
            condition = Map.get(edge_data, :when)

            condition == nil or Enum.any?(pred_facts, &matches_condition?(&1, condition))
          end)

        case any_match do
          true -> w
          false -> %{w | activations: Map.put(w.activations, component_id, :skipped)}
        end
    end
  end

  # ============================================
  # Private - Execution Log
  # ============================================

  defp log_execution(%Workflow{} = w, component_id, status, duration_us) do
    entry = %{
      component_id: component_id,
      status: status,
      duration_us: duration_us,
      timestamp: System.monotonic_time()
    }

    # Prepend for O(1) — reversed on read by Workflow.execution_log/1
    log = Map.get(w.metadata, :log, [])
    %{w | metadata: Map.put(w.metadata, :log, [entry | log])}
  end

  defp fire_callback(w, opts, component_id, result) do
    case Keyword.get(opts, :on_complete) do
      nil ->
        w

      callback ->
        try do
          callback.(component_id, result, w)
        rescue
          _ -> :ok
        end

        w
    end
  end

  # ============================================
  # Private - Saga Support
  # ============================================

  defp completion_order(%Workflow{} = w, component_id) do
    w.productions
    |> Map.get(component_id, [])
    |> Enum.map(fn fid -> Map.fetch!(w.facts, fid).timestamp end)
    |> Enum.min(fn -> 0 end)
  end

  defp gather_input_values(%Workflow{} = w, component_id) do
    predecessors = Dag.predecessors(w.dag, component_id)

    case predecessors do
      [] ->
        # Root node — return input facts like execution does
        case w.input_facts do
          [] ->
            %{}

          facts ->
            values = Enum.map(facts, & &1.value)

            case values do
              [single] -> %{__input__: single}
              multiple -> %{__input__: multiple}
            end
        end

      _ ->
        Enum.reduce(predecessors, %{}, fn pred_id, acc ->
          facts = get_predecessor_facts(w, pred_id)
          values = Enum.map(facts, & &1.value)

          case values do
            [single] -> Map.put(acc, pred_id, single)
            multiple -> Map.put(acc, pred_id, multiple)
          end
        end)
    end
  end

  defp get_production_value(%Workflow{} = w, component_id) do
    w.productions
    |> Map.get(component_id, [])
    |> Enum.map(fn fid -> Map.fetch!(w.facts, fid).value end)
    |> case do
      [single] -> single
      multiple -> multiple
    end
  end
end
