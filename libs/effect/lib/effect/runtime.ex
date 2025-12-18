defmodule Effect.Runtime do
  @moduledoc """
  Execution engine for Effects.

  Handles:
  - DAG-based step ordering via topological sort
  - Sequential step execution
  - Context accumulation
  - Conditional execution (when: conditions)
  - Error handling and rollback triggering
  - Middleware execution
  - Hook invocation
  - Report generation
  """

  require Logger

  alias Effect.{Builder, Context, Error, Parallel, Report, Retry, Step}

  @type run_result :: {:ok, map()} | {:error, Error.t()} | {:halted, term()}

  @doc """
  Executes an effect with the given initial context.

  ## Options

  - `:timeout` - Total execution timeout in milliseconds
  - `:report` - If true, returns `{result, Report.t()}`
  - `:debug` - If true, logs step execution
  - `:services` - Override services from effect definition
  - `:metadata` - Additional metadata merged with effect metadata

  ## Returns

  - `{:ok, context}` - Completed successfully
  - `{:error, Error.t()}` - Failed, rollbacks executed
  - `{:halted, reason}` - Halted early via `{:halt, reason}`

  With `report: true`:
  - `{{:ok, context}, Report.t()}`
  - `{{:error, Error.t()}, Report.t()}`
  - `{{:halted, reason}, Report.t()}`
  """
  @spec run(Builder.t(), map(), keyword()) :: run_result() | {run_result(), Report.t()}
  def run(%Builder{} = effect, initial_ctx, opts \\ []) do
    execution_id = generate_execution_id()
    report_enabled = Keyword.get(opts, :report, false)
    debug = Keyword.get(opts, :debug, false)
    services = merge_services(effect.services, Keyword.get(opts, :services, %{}))

    # Build DAG and get execution order
    case Builder.build_dag(effect) do
      {:ok, dag} ->
        case Dag.Algorithms.topological_sort(dag) do
          {:ok, order} ->
            report = if report_enabled, do: Report.new(effect.name, execution_id), else: nil

            # Run hooks
            run_hooks(effect.hooks.on_start, effect.name, initial_ctx)

            # Execute steps
            result =
              execute_steps(
                order,
                effect,
                Context.new(initial_ctx),
                services,
                execution_id,
                report,
                debug
              )

            # Run completion hooks
            case result do
              {:ok, ctx, report} ->
                run_hooks(effect.hooks.on_complete, effect.name, ctx)
                run_ensure_fns(effect.ensure_fns, ctx, :ok)
                finalize_result({:ok, ctx}, report, report_enabled)

              {:error, error, ctx, report} ->
                run_hooks(effect.hooks.on_complete, effect.name, ctx)
                run_ensure_fns(effect.ensure_fns, ctx, {:error, error})
                finalize_result({:error, error}, report, report_enabled)

              {:halted, reason, ctx, report} ->
                run_hooks(effect.hooks.on_complete, effect.name, ctx)
                run_ensure_fns(effect.ensure_fns, ctx, {:halted, reason})
                finalize_result({:halted, reason}, report, report_enabled)

              {:checkpoint, exec_id, checkpoint_name, ctx, report} ->
                # Checkpoint pauses execution - don't run completion hooks yet
                finalize_result({:checkpoint, exec_id, checkpoint_name, ctx}, report, report_enabled)
            end

          {:error, {:cycle_detected, path}} ->
            error = Error.new(:dag, {:cycle_detected, path}, effect_name: effect.name)
            finalize_result({:error, error}, nil, report_enabled)
        end

      {:error, reason} ->
        error = Error.new(:dag, reason, effect_name: effect.name)
        finalize_result({:error, error}, nil, report_enabled)
    end
  end

  # Execute steps in topological order
  defp execute_steps(order, effect, ctx, services, execution_id, report, debug) do
    steps_map = Map.new(effect.steps, fn s -> {s.name, s} end)
    completed = []

    do_execute_steps(order, steps_map, effect, ctx, services, execution_id, report, debug, completed)
  end

  defp do_execute_steps([], _steps_map, _effect, ctx, _services, _execution_id, report, _debug, _completed) do
    {:ok, ctx, report}
  end

  defp do_execute_steps([name | rest], steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    step = Map.fetch!(steps_map, name)

    # Check if step should be skipped
    if Step.should_skip?(step, ctx) do
      if debug, do: log_step(effect.name, name, :skipped)
      report = if report, do: Report.add_step(report, name, :skipped, reason: :when_false), else: nil
      do_execute_steps(rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)
    else
      # Handle special step types
      case step.type do
        :parallel ->
          execute_parallel_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        :branch ->
          execute_branch_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        :embed ->
          execute_embed_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        :each ->
          execute_each_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        :race ->
          execute_race_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        :using ->
          execute_using_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        :checkpoint ->
          execute_checkpoint_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)

        _ ->
          execute_regular_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed)
      end
    end
  end

  # Execute a regular (non-parallel) step
  defp execute_regular_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    {result, attempts} =
      try do
        execute_step_with_middleware(step, ctx, services, effect.middleware)
      rescue
        e ->
          {{:error, e}, 1}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
        {:ok, step_result} when is_map(step_result) ->
          if debug, do: log_step(effect.name, name, :ok, duration, attempts)

          new_ctx = Context.merge(ctx, step_result)
          added_keys = Context.added_keys(ctx, new_ctx)

          report =
            if report do
              Report.add_step(report, name, :ok, duration_ms: duration, added_keys: added_keys, attempts: attempts)
            else
              nil
            end

          do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

        {:error, reason} ->
          if debug, do: log_step(effect.name, name, :error, duration, attempts)

          # Run error hooks
          run_error_hooks(effect.hooks.on_error, name, reason, ctx)

          error =
            Error.new(name, reason,
              context: ctx,
              execution_id: execution_id,
              effect_name: effect.name,
              duration_ms: duration,
              attempts: attempts
            )

          # Trigger rollbacks for completed steps (completed is already in reverse order)
          {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)

          report = if report, do: Report.add_step(report, name, :error, duration_ms: duration, reason: reason, attempts: attempts), else: nil
          report = if report, do: Report.complete(report, :error, error: error), else: nil

          {:error, error, ctx, report}

        {:halt, reason} ->
          if debug, do: log_step(effect.name, name, :halted, duration, attempts)

          report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, attempts: attempts), else: nil
          report = if report, do: Report.complete(report, :halted, halt_reason: reason), else: nil

          {:halted, reason, ctx, report}

        nil ->
          # Treat nil as {:ok, %{}}
          if debug, do: log_step(effect.name, name, :ok, duration, attempts)
          report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, attempts: attempts), else: nil
          do_execute_steps(rest, steps_map, effect, ctx, services, execution_id, report, debug, [name | completed])

        other ->
          error = Error.new(name, {:invalid_step_return, other}, context: ctx, effect_name: effect.name)
          {:error, error, ctx, report}
      end
  end

  # Execute a parallel step (multiple substeps concurrently)
  defp execute_parallel_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    # Get parallel configuration from step metadata
    parallel_steps = step.meta.parallel_steps
    parallel_opts = step.meta.parallel_opts

    result =
      try do
        Parallel.execute(parallel_steps, ctx, services, parallel_opts)
      rescue
        e ->
          {:error, name, e, []}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, merged_result, _step_results} ->
        if debug, do: log_step(effect.name, name, :ok, duration)

        new_ctx = Context.merge(ctx, merged_result)
        added_keys = Context.added_keys(ctx, new_ctx)

        report =
          if report do
            Report.add_step(report, name, :ok, duration_ms: duration, added_keys: added_keys, parallel: true)
          else
            nil
          end

        do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

      {:error, failed_step, reason, _completed_steps} ->
        if debug, do: log_step(effect.name, name, :error, duration)

        # Run error hooks
        run_error_hooks(effect.hooks.on_error, failed_step, reason, ctx)

        error =
          Error.new(failed_step, reason,
            context: ctx,
            execution_id: execution_id,
            effect_name: effect.name,
            duration_ms: duration,
            metadata: %{parallel_group: name}
          )

        # Trigger rollbacks for completed steps
        {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)

        report = if report, do: Report.add_step(report, name, :error, duration_ms: duration, reason: reason), else: nil
        report = if report, do: Report.complete(report, :error, error: error), else: nil

        {:error, error, ctx, report}
    end
  end

  # Execute a branch step (conditional routing)
  defp execute_branch_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    # Get branch configuration
    selector = step.meta.selector
    routes = step.meta.routes
    default = step.meta.default

    # Run selector to get the route key
    route_key =
      try do
        selector.(ctx)
      rescue
        e -> {:error, e}
      end

    # Handle selector errors
    case route_key do
      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        error = Error.new(name, {:selector_error, reason}, context: ctx, effect_name: effect.name)
        {:error, error, ctx, report}

      key ->
        # Find the matching route
        route = Map.get(routes, key) || default

        case route do
          nil ->
            duration = System.monotonic_time(:millisecond) - start_time
            if debug, do: log_step(effect.name, name, :error, duration)
            error = Error.new(name, {:no_matching_branch, key}, context: ctx, effect_name: effect.name)
            {:error, error, ctx, report}

          route_fn when is_function(route_fn) ->
            # Execute route function
            result =
              try do
                if is_function(route_fn, 1), do: route_fn.(ctx), else: route_fn.(ctx, services)
              rescue
                e -> {:error, e}
              end

            duration = System.monotonic_time(:millisecond) - start_time
            handle_branch_result(result, name, key, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed, duration)

          %Builder{} = nested_effect ->
            # Execute nested effect
            case run(nested_effect, ctx, []) do
              {:ok, nested_ctx} ->
                duration = System.monotonic_time(:millisecond) - start_time
                if debug, do: log_step(effect.name, name, :ok, duration)

                new_ctx = Context.merge(ctx, nested_ctx)
                report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, branch: key), else: nil
                do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

              {:error, nested_error} ->
                duration = System.monotonic_time(:millisecond) - start_time
                if debug, do: log_step(effect.name, name, :error, duration)

                error = Error.new(name, {:nested_effect_failed, nested_error.reason},
                  context: ctx,
                  effect_name: effect.name,
                  metadata: %{branch: key, nested_error: nested_error}
                )
                {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
                {:error, error, ctx, report}

              {:halted, reason} ->
                _duration = System.monotonic_time(:millisecond) - start_time
                {:halted, reason, ctx, report}
            end
        end
    end
  end

  defp handle_branch_result({:ok, result}, name, key, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed, duration) when is_map(result) do
    if debug, do: log_step(effect.name, name, :ok, duration)

    new_ctx = Context.merge(ctx, result)
    report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, branch: key), else: nil
    do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])
  end

  defp handle_branch_result({:error, reason}, name, _key, _rest, steps_map, effect, ctx, _services, execution_id, report, debug, completed, duration) do
    if debug, do: log_step(effect.name, name, :error, duration)

    error = Error.new(name, reason, context: ctx, execution_id: execution_id, effect_name: effect.name)
    {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
    {:error, error, ctx, report}
  end

  defp handle_branch_result({:halt, reason}, _name, _key, _rest, _steps_map, _effect, ctx, _services, _execution_id, report, _debug, _completed, _duration) do
    {:halted, reason, ctx, report}
  end

  defp handle_branch_result(nil, name, key, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed, duration) do
    handle_branch_result({:ok, %{}}, name, key, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed, duration)
  end

  # Execute an embed step (nested effect)
  defp execute_embed_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    nested_effect = step.meta.nested_effect
    context_fn = step.meta.context_fn

    # Transform context for nested effect
    nested_ctx =
      try do
        context_fn.(ctx)
      rescue
        e -> {:error, e}
      end

    case nested_ctx do
      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        error = Error.new(name, {:context_transform_error, reason}, context: ctx, effect_name: effect.name)
        {:error, error, ctx, report}

      nested_ctx when is_map(nested_ctx) ->
        # Execute nested effect
        case run(nested_effect, nested_ctx, []) do
          {:ok, result_ctx} ->
            duration = System.monotonic_time(:millisecond) - start_time
            if debug, do: log_step(effect.name, name, :ok, duration)

            new_ctx = Context.merge(ctx, result_ctx)
            report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, embedded: nested_effect.name), else: nil
            do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

          {:error, nested_error} ->
            duration = System.monotonic_time(:millisecond) - start_time
            if debug, do: log_step(effect.name, name, :error, duration)

            error = Error.new(name, {:nested_effect_failed, nested_error.reason},
              context: ctx,
              effect_name: effect.name,
              metadata: %{nested_effect: nested_effect.name, nested_error: nested_error}
            )
            {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
            {:error, error, ctx, report}

          {:halted, reason} ->
            _duration = System.monotonic_time(:millisecond) - start_time
            {:halted, reason, ctx, report}
        end
    end
  end

  # Execute an each step (iteration over collection)
  defp execute_each_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    extractor = step.meta.extractor
    item_effect = step.meta.item_effect
    concurrency = step.meta.concurrency
    as_key = step.meta.as
    collect_key = step.meta.collect

    # Extract collection
    items =
      try do
        extractor.(ctx)
      rescue
        e -> {:error, e}
      end

    case items do
      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        error = Error.new(name, {:extractor_error, reason}, context: ctx, effect_name: effect.name)
        {:error, error, ctx, report}

      [] ->
        # Empty collection - nothing to do
        duration = System.monotonic_time(:millisecond) - start_time
        if debug, do: log_step(effect.name, name, :ok, duration)

        new_ctx = Map.put(ctx, collect_key, [])
        report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, items: 0), else: nil
        do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

      items when is_list(items) ->
        # Process items (sequentially or concurrently)
        results =
          if concurrency == 1 do
            process_items_sequential(items, item_effect, ctx, as_key)
          else
            process_items_concurrent(items, item_effect, ctx, as_key, concurrency)
          end

        duration = System.monotonic_time(:millisecond) - start_time

        case results do
          {:ok, collected} ->
            if debug, do: log_step(effect.name, name, :ok, duration)

            new_ctx = Map.put(ctx, collect_key, collected)
            report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, items: length(items)), else: nil
            do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

          {:error, index, reason} ->
            if debug, do: log_step(effect.name, name, :error, duration)

            error = Error.new(name, {:iteration_failed, index, reason},
              context: ctx,
              effect_name: effect.name
            )
            {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
            {:error, error, ctx, report}
        end
    end
  end

  defp process_items_sequential(items, item_effect, ctx, as_key) do
    parent_keys = Map.keys(ctx)

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      item_ctx = Map.put(ctx, as_key, item)
      case run(item_effect, item_ctx, []) do
        {:ok, result} ->
          # Only collect keys added by nested effect (exclude item key and parent keys)
          collected = Map.drop(result, parent_keys ++ [as_key])
          {:cont, {:ok, acc ++ [collected]}}
        {:error, error} -> {:halt, {:error, index, error.reason}}
        {:halted, reason} -> {:halt, {:error, index, {:halted, reason}}}
      end
    end)
  end

  defp process_items_concurrent(items, item_effect, ctx, as_key, concurrency) do
    parent_keys = Map.keys(ctx)

    results =
      items
      |> Enum.with_index()
      |> Task.async_stream(
        fn {item, index} ->
          item_ctx = Map.put(ctx, as_key, item)
          case run(item_effect, item_ctx, []) do
            {:ok, result} ->
              # Only collect keys added by nested effect (exclude item key and parent keys)
              collected = Map.drop(result, parent_keys ++ [as_key])
              {:ok, index, collected}
            {:error, error} -> {:error, index, error.reason}
            {:halted, reason} -> {:error, index, {:halted, reason}}
          end
        end,
        max_concurrency: concurrency,
        ordered: true
      )
      |> Enum.to_list()

    # Check for errors
    error = Enum.find(results, fn
      {:ok, {:error, _, _}} -> true
      {:exit, _} -> true
      _ -> false
    end)

    case error do
      nil ->
        collected = Enum.map(results, fn {:ok, {:ok, _index, result}} -> result end)
        {:ok, collected}

      {:ok, {:error, index, reason}} ->
        {:error, index, reason}

      {:exit, reason} ->
        {:error, 0, {:task_exit, reason}}
    end
  end

  # Execute a race step (first wins)
  defp execute_race_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    contestants = step.meta.contestants
    timeout = step.meta.timeout

    # Start all contestants concurrently
    tasks =
      contestants
      |> Enum.with_index()
      |> Enum.map(fn {contestant, index} ->
        Task.async(fn ->
          case run(contestant, ctx, []) do
            {:ok, result} -> {:ok, index, result}
            {:error, error} -> {:error, index, error.reason}
            {:halted, reason} -> {:error, index, {:halted, reason}}
          end
        end)
      end)

    # Wait for first success or all failures
    result = await_race(tasks, [], timeout)

    # Kill remaining tasks
    Enum.each(tasks, fn task ->
      Task.shutdown(task, :brutal_kill)
    end)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _index, winner_ctx} ->
        if debug, do: log_step(effect.name, name, :ok, duration)

        new_ctx = Context.merge(ctx, winner_ctx)
        report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration), else: nil
        do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

      {:all_failed, failures} ->
        if debug, do: log_step(effect.name, name, :error, duration)

        error = Error.new(name, {:race_all_failed, failures},
          context: ctx,
          effect_name: effect.name
        )
        {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
        {:error, error, ctx, report}

      {:timeout, failures} ->
        if debug, do: log_step(effect.name, name, :error, duration)

        error = Error.new(name, {:race_timeout, failures},
          context: ctx,
          effect_name: effect.name
        )
        {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
        {:error, error, ctx, report}
    end
  end

  defp await_race([], failures, _timeout) do
    {:all_failed, Enum.reverse(failures)}
  end

  defp await_race(tasks, failures, timeout) do
    receive do
      {ref, {:ok, index, result}} ->
        # Clean up the DOWN message
        Process.demonitor(ref, [:flush])
        {:ok, index, result}

      {ref, {:error, index, reason}} ->
        Process.demonitor(ref, [:flush])
        remaining = Enum.reject(tasks, &(&1.ref == ref))
        await_race(remaining, [{index, reason} | failures], timeout)

      {:DOWN, ref, :process, _pid, reason} ->
        remaining = Enum.reject(tasks, &(&1.ref == ref))
        await_race(remaining, [{:unknown, reason} | failures], timeout)
    after
      timeout ->
        {:timeout, Enum.reverse(failures)}
    end
  end

  # Execute a using step (resource lifecycle: acquire/use/release)
  defp execute_using_step(step, rest, steps_map, effect, ctx, services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    acquire = step.meta.acquire
    release = step.meta.release
    body = step.meta.body
    as_key = step.meta.as

    # Phase 1: Acquire resource
    acquire_result =
      try do
        if is_function(acquire, 1), do: acquire.(ctx), else: acquire.(ctx, services)
      rescue
        e -> {:error, {:acquire_error, e}}
      end

    case acquire_result do
      {:ok, acquired_data} when is_map(acquired_data) ->
        # Merge acquired resource into context
        resource_ctx = Context.merge(ctx, acquired_data)

        # Phase 2: Execute body effect
        body_result =
          try do
            run(body, resource_ctx, [])
          rescue
            e -> {:error, Error.new(name, {:body_error, e}, context: resource_ctx, effect_name: effect.name)}
          end

        # Phase 3: Always release (like try/after)
        release_result =
          try do
            release.(resource_ctx, body_result)
            :ok
          rescue
            e -> {:error, {:release_error, e}}
          end

        duration = System.monotonic_time(:millisecond) - start_time

        case {body_result, release_result} do
          {{:ok, body_ctx}, :ok} ->
            if debug, do: log_step(effect.name, name, :ok, duration)

            new_ctx = Context.merge(ctx, body_ctx)
            report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration, resource: as_key), else: nil
            do_execute_steps(rest, steps_map, effect, new_ctx, services, execution_id, report, debug, [name | completed])

          {{:ok, _body_ctx}, {:error, release_error}} ->
            if debug, do: log_step(effect.name, name, :error, duration)

            error = Error.new(name, {:release_failed, release_error},
              context: ctx,
              effect_name: effect.name
            )
            {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
            {:error, error, ctx, report}

          {{:error, body_error}, _release_result} ->
            if debug, do: log_step(effect.name, name, :error, duration)

            error =
              if is_struct(body_error, Error) do
                body_error
              else
                Error.new(name, {:body_failed, body_error.reason},
                  context: ctx,
                  effect_name: effect.name
                )
              end

            {error, report} = execute_rollbacks(completed, steps_map, effect, ctx, error, report)
            {:error, error, ctx, report}

          {{:halted, reason}, _release_result} ->
            {:halted, reason, ctx, report}
        end

      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        error = Error.new(name, {:acquire_failed, reason}, context: ctx, effect_name: effect.name)
        {:error, error, ctx, report}
    end
  end

  # Execute a checkpoint step (pause for resume)
  defp execute_checkpoint_step(step, _rest, _steps_map, effect, ctx, _services, execution_id, report, debug, completed) do
    name = step.name
    start_time = System.monotonic_time(:millisecond)

    store_fn = step.meta.store

    # Create checkpoint state
    checkpoint_state = Effect.Checkpoint.create_state(
      execution_id,
      effect.name,
      name,
      ctx,
      completed
    )

    # Store the checkpoint
    case store_fn.(execution_id, checkpoint_state) do
      :ok ->
        duration = System.monotonic_time(:millisecond) - start_time
        if debug, do: log_step(effect.name, name, :checkpoint, duration)

        report = if report, do: Report.add_step(report, name, :ok, duration_ms: duration), else: nil
        {:checkpoint, execution_id, name, ctx, report}

      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start_time
        error = Error.new(name, {:checkpoint_store_failed, reason}, context: ctx, effect_name: effect.name)
        {:error, error, ctx, report}
    end
  end

  @doc """
  Resumes execution from a checkpoint.

  Loads the checkpoint state and continues execution from where it left off.

  ## Options

  - `:report` - If true, returns report with result
  - `:debug` - If true, logs step execution

  ## Returns

  - `{:ok, context}` - Completed successfully
  - `{:error, Error.t()}` - Failed
  - `{:checkpoint, execution_id, checkpoint_name}` - Hit another checkpoint
  - `{:halted, reason}` - Halted early
  """
  @spec resume(Builder.t(), String.t(), keyword()) :: term()
  def resume(%Builder{} = effect, execution_id, opts \\ []) do
    # Find the checkpoint that was hit (need to load state to know which one)
    # We'll try each checkpoint's load function until we find one that works
    checkpoint_configs = effect.checkpoints

    load_result =
      Enum.find_value(checkpoint_configs, {:error, :not_found}, fn {_name, config} ->
        case config.load.(execution_id) do
          {:ok, state} -> {:ok, state}
          {:error, _} -> nil
        end
      end)

    case load_result do
      {:ok, checkpoint_state} ->
        # Validate state matches effect
        case Effect.Checkpoint.validate_state(checkpoint_state, effect.name) do
          :ok ->
            resume_from_state(effect, checkpoint_state, opts)

          {:error, reason} ->
            {:error, Error.new(:resume, {:invalid_checkpoint_state, reason},
              context: %{},
              effect_name: effect.name
            )}
        end

      {:error, :not_found} ->
        {:error, Error.new(:resume, {:checkpoint_not_found, execution_id},
          context: %{},
          effect_name: effect.name
        )}
    end
  end

  defp resume_from_state(effect, checkpoint_state, opts) do
    debug = Keyword.get(opts, :debug, false)
    want_report = Keyword.get(opts, :report, false)
    services = Keyword.get(opts, :services, effect.services)

    # Build DAG and get execution order
    case Builder.build_dag(effect) do
      {:ok, dag} ->
        {:ok, sorted} = Dag.Algorithms.topological_sort(dag)
        steps_map = build_steps_map(effect)

        # Find steps after checkpoint
        checkpoint_name = checkpoint_state.checkpoint
        completed = checkpoint_state.completed_steps
        ctx = checkpoint_state.context
        execution_id = checkpoint_state.execution_id

        # Find index of checkpoint and get remaining steps
        checkpoint_idx = Enum.find_index(sorted, &(&1 == checkpoint_name))
        remaining_steps = Enum.drop(sorted, checkpoint_idx + 1)

        report = if want_report, do: Report.new(effect.name, execution_id), else: nil

        if debug, do: Logger.debug("[Effect] Resuming #{effect.name} from #{checkpoint_name}")

        # Continue execution from where we left off
        result = do_execute_steps(remaining_steps, steps_map, effect, ctx, services, execution_id, report, debug, [checkpoint_name | completed])

        # Process result like main run function
        case result do
          {:ok, final_ctx, report} ->
            finalize_result({:ok, final_ctx}, report, want_report)

          {:error, error, _ctx, report} ->
            finalize_result({:error, error}, report, want_report)

          {:halted, reason, _ctx, report} ->
            finalize_result({:halted, reason}, report, want_report)

          {:checkpoint, exec_id, cp_name, cp_ctx, report} ->
            finalize_result({:checkpoint, exec_id, cp_name, cp_ctx}, report, want_report)
        end

      {:error, reason} ->
        {:error, Error.new(:build_dag, reason, context: %{}, effect_name: effect.name)}
    end
  end

  # Execute step with middleware chain and optional retry
  defp execute_step_with_middleware(step, ctx, services, middleware) do
    # Build the middleware chain
    base_fn = fn -> call_step_function(step, ctx, services) end

    wrapped =
      Enum.reduce(Enum.reverse(middleware), base_fn, fn mw, next ->
        fn -> mw.(step.name, ctx, next) end
      end)

    # Apply retry if configured
    case step.retry do
      nil ->
        {wrapped.(), 1}

      retry_opts when is_list(retry_opts) ->
        case Retry.execute(wrapped, retry_opts) do
          # Retry returns {:ok, full_step_result, attempts} where full_step_result is {:ok, map}
          {:ok, step_result, attempts} -> {step_result, attempts}
          {:error, reason, attempts} -> {{:error, reason}, attempts}
        end
    end
  end

  # Call the step function with appropriate arity
  defp call_step_function(%Step{fun: fun, arity: 1}, ctx, _services), do: fun.(ctx)
  defp call_step_function(%Step{fun: fun, arity: 2}, ctx, services), do: fun.(ctx, services)

  # Execute rollbacks in reverse completion order
  defp execute_rollbacks([], _steps_map, _effect, _ctx, error, report) do
    {error, report}
  end

  defp execute_rollbacks([name | rest], steps_map, effect, ctx, error, report) do
    step = Map.fetch!(steps_map, name)

    case step.rollback do
      nil ->
        execute_rollbacks(rest, steps_map, effect, ctx, error, report)

      rollback_fn ->
        # Run rollback hooks
        run_hooks(effect.hooks.on_rollback, name, ctx)

        result =
          try do
            rollback_fn.(ctx)
          rescue
            e -> {:error, e}
          end

        case result do
          :ok ->
            report = if report, do: Report.mark_rolled_back(report, name, :ok), else: nil
            execute_rollbacks(rest, steps_map, effect, ctx, error, report)

          {:ok, _} ->
            report = if report, do: Report.mark_rolled_back(report, name, :ok), else: nil
            execute_rollbacks(rest, steps_map, effect, ctx, error, report)

          {:error, rollback_error} ->
            report = if report, do: Report.mark_rolled_back(report, name, :error), else: nil
            error = Error.add_rollback_error(error, name, rollback_error)
            execute_rollbacks(rest, steps_map, effect, ctx, error, report)
        end
    end
  end

  # Finalize result with or without report
  defp finalize_result(result, nil, false), do: result
  defp finalize_result(result, nil, true), do: {result, nil}
  defp finalize_result(result, _report, false), do: result

  defp finalize_result(result, report, true) do
    report =
      case result do
        {:ok, _} -> Report.complete(report, :ok)
        {:error, error} -> Report.complete(report, :error, error: error)
        {:halted, reason} -> Report.complete(report, :halted, halt_reason: reason)
        {:checkpoint, _, _, _} -> Report.complete(report, :ok)
      end

    {result, report}
  end

  # Helper functions
  defp generate_execution_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp merge_services(effect_services, run_services) do
    Map.merge(effect_services, run_services)
  end

  defp run_hooks(hooks, name, ctx) do
    Enum.each(hooks, fn hook -> hook.(name, ctx) end)
  end

  defp run_error_hooks(hooks, step, error, ctx) do
    Enum.each(hooks, fn hook -> hook.(step, error, ctx) end)
  end

  defp run_ensure_fns(fns, ctx, result) do
    Enum.each(fns, fn {_name, fun} ->
      try do
        fun.(ctx, result)
      rescue
        _ -> :ok
      end
    end)
  end

  defp build_steps_map(effect) do
    Map.new(effect.steps, fn s -> {s.name, s} end)
  end

  defp log_step(effect_name, step_name, status, duration \\ nil, attempts \\ 1) do
    duration_str = if duration, do: " in #{duration}ms", else: ""
    attempts_str = if attempts > 1, do: " (#{attempts} attempts)", else: ""
    IO.puts("[Effect :#{effect_name}] Step :#{step_name} #{status}#{duration_str}#{attempts_str}")
  end
end
