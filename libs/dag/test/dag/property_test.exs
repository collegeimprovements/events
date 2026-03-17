defmodule Dag.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Dag.{Workflow, Components.Step}

  # ============================================
  # Invariant 1: Topological ordering
  # ============================================

  property "no component fires before its predecessors complete" do
    check all w <- Dag.Generators.random_step_workflow(), max_runs: 50 do
      w = Workflow.react_until_satisfied(w, :test_input)
      log = Workflow.execution_log(w)
      completed_ids = Enum.map(log, & &1.component_id)

      Enum.each(log, fn entry ->
        predecessors = Dag.predecessors(w.dag, entry.component_id)
        my_pos = Enum.find_index(completed_ids, &(&1 == entry.component_id))

        Enum.each(predecessors, fn pred ->
          pred_pos = Enum.find_index(completed_ids, &(&1 == pred))

          if pred_pos != nil and my_pos != nil do
            assert pred_pos < my_pos,
                   "#{entry.component_id} (pos #{my_pos}) fired before predecessor #{pred} (pos #{pred_pos})"
          end
        end)
      end)
    end
  end

  # ============================================
  # Invariant 2: Fact conservation
  # ============================================

  property "every completed component produces at least one fact" do
    check all w <- Dag.Generators.random_step_workflow(), max_runs: 50 do
      w = Workflow.react_until_satisfied(w, :test_input)

      Enum.each(w.activations, fn {id, status} ->
        if status == :completed do
          facts = Workflow.production(w, id)

          assert length(facts) > 0,
                 "Completed component #{id} produced no facts"
        end
      end)
    end
  end

  # ============================================
  # Invariant 3: Failure propagation
  # ============================================

  property "dead-end descendants of failed components are failed or not_activated" do
    check all w <- Dag.Generators.random_step_workflow(min_nodes: 3), max_runs: 50 do
      roots = Dag.roots(w.dag)

      if roots != [] do
        root = hd(roots)
        failing_step = Step.new(root, fn _, _ -> {:error, :intentional} end)
        w = %{w | components: Map.put(w.components, root, failing_step)}

        w = Workflow.react_until_satisfied(w, :test_input)

        descendants = Dag.descendants(w.dag, root)

        Enum.each(descendants, fn desc ->
          predecessors = Dag.predecessors(w.dag, desc)

          all_dead =
            Enum.all?(predecessors, fn p ->
              Map.get(w.activations, p) in [:failed, :skipped]
            end)

          if all_dead do
            status = Map.get(w.activations, desc)

            assert status in [:failed, :not_activated],
                   "Descendant #{desc} should be failed/not_activated but is #{status}"
          end
        end)
      end
    end
  end

  # ============================================
  # Invariant 4: Determinism
  # ============================================

  property "same input produces same raw_productions" do
    check all w <- Dag.Generators.random_step_workflow(), max_runs: 50 do
      w1 = Workflow.react_until_satisfied(w, :deterministic_input)
      w2 = Workflow.react_until_satisfied(w, :deterministic_input)

      assert Workflow.raw_productions(w1) == Workflow.raw_productions(w2)
    end
  end

  # ============================================
  # Invariant 5: Reset idempotence
  # ============================================

  property "reset + re-execute produces same results" do
    check all w <- Dag.Generators.random_step_workflow(), max_runs: 50 do
      w1 = Workflow.react_until_satisfied(w, :reset_input)
      prods1 = Workflow.raw_productions(w1)

      w2 = w1 |> Workflow.reset() |> Workflow.react_until_satisfied(:reset_input)
      prods2 = Workflow.raw_productions(w2)

      assert prods1 == prods2
    end
  end

  # ============================================
  # Invariant 6: Checkpoint round-trip
  # ============================================

  property "checkpoint -> restore -> same state" do
    check all w <- Dag.Generators.random_step_workflow(), max_runs: 50 do
      w = Workflow.react_until_satisfied(w, :checkpoint_input)

      checkpoint = Workflow.checkpoint(w)
      {:ok, restored} = Workflow.restore(checkpoint, w.components)

      assert restored.name == w.name
      assert restored.state == w.state
      assert restored.activations == w.activations
      assert Workflow.raw_productions(restored) == Workflow.raw_productions(w)
    end
  end
end
