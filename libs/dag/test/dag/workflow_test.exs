defmodule Dag.WorkflowTest do
  use ExUnit.Case, async: true

  alias Dag.{Workflow, Fact, Context, Runnable}
  alias Dag.Components.{Step, Rule, Accumulator, Branch, Saga}

  # ============================================
  # Fact
  # ============================================

  describe "Fact" do
    test "new/2 creates a fact with defaults" do
      fact = Fact.new("hello")
      assert fact.value == "hello"
      assert fact.source == nil
      assert fact.type == nil
      assert is_reference(fact.id)
      assert is_integer(fact.timestamp)
    end

    test "new/2 with options" do
      fact = Fact.new(42, source: :step_a, type: :count, metadata: %{debug: true})
      assert fact.value == 42
      assert fact.source == :step_a
      assert fact.type == :count
      assert fact.metadata == %{debug: true}
    end

    test "from_output/3 tags source" do
      fact = Fact.from_output(:tokenizer, ["a", "b"])
      assert fact.source == :tokenizer
      assert fact.value == ["a", "b"]
    end

    test "from_output/3 with type" do
      fact = Fact.from_output(:branch, :high, type: :high)
      assert fact.type == :high
    end

    test "value/1 extracts value" do
      assert Fact.value(Fact.new(99)) == 99
    end

    test "type?/2 checks type" do
      fact = Fact.new("x", type: :string)
      assert Fact.type?(fact, :string)
      refute Fact.type?(fact, :integer)
    end
  end

  # ============================================
  # Context
  # ============================================

  describe "Context" do
    test "resolve priority: scoped > global > default" do
      ctx =
        Context.new()
        |> Context.put_default(:key, :from_default)
        |> Context.put_global(:key, :from_global)
        |> Context.put_scoped(:step_a, :key, :from_scoped)

      assert Context.resolve(ctx, :step_a, :key) == :from_scoped
      assert Context.resolve(ctx, :step_b, :key) == :from_global
    end

    test "resolve falls back to default" do
      ctx = Context.new() |> Context.put_default(:timeout, 5000)
      assert Context.resolve(ctx, :any_step, :timeout) == 5000
    end

    test "resolve returns nil for missing keys" do
      ctx = Context.new()
      assert Context.resolve(ctx, :step, :missing) == nil
      assert Context.resolve(ctx, :step, :missing, :fallback) == :fallback
    end

    test "resolve_all merges all levels" do
      ctx =
        Context.new()
        |> Context.put_default(:a, 1)
        |> Context.put_global(:b, 2)
        |> Context.put_scoped(:step, :c, 3)
        |> Context.put_scoped(:step, :a, 99)

      resolved = Context.resolve_all(ctx, :step)
      assert resolved == %{a: 99, b: 2, c: 3}
    end

    test "from_map/1 with _global key" do
      ctx = Context.from_map(%{_global: %{url: "https://..."}, step_a: %{key: "val"}})
      assert Context.resolve(ctx, :step_a, :key) == "val"
      assert Context.resolve(ctx, :any, :url) == "https://..."
    end

    test "merge/2 with ctx2 precedence" do
      ctx1 = Context.new() |> Context.put_global(:key, :old)
      ctx2 = Context.new() |> Context.put_global(:key, :new)
      merged = Context.merge(ctx1, ctx2)
      assert Context.resolve(merged, :any, :key) == :new
    end
  end

  # ============================================
  # Runnable
  # ============================================

  describe "Runnable" do
    test "execute/1 returns {id, {:ok, value}}" do
      r = Runnable.new(:step_a, fn _inputs, _ctx -> {:ok, 42} end, %{})
      assert {:step_a, {:ok, 42}} = Runnable.execute(r)
    end

    test "execute/1 wraps non-tuple returns" do
      r = Runnable.new(:step_a, fn _inputs, _ctx -> 42 end, %{})
      assert {:step_a, {:ok, 42}} = Runnable.execute(r)
    end

    test "execute/1 passes through errors" do
      r = Runnable.new(:step_a, fn _inputs, _ctx -> {:error, :boom} end, %{})
      assert {:step_a, {:error, :boom}} = Runnable.execute(r)
    end

    test "execute/1 rescues exceptions" do
      r = Runnable.new(:step_a, fn _inputs, _ctx -> raise "kaboom" end, %{})
      assert {:step_a, {:error, {%RuntimeError{message: "kaboom"}, _stack}}} = Runnable.execute(r)
    end

    test "execute/1 passes inputs and context" do
      r = Runnable.new(:s, fn inputs, ctx -> {:ok, {inputs.x, ctx[:y]}} end, %{x: 1}, context: %{y: 2})
      assert {:s, {:ok, {1, 2}}} = Runnable.execute(r)
    end
  end

  # ============================================
  # Step Component
  # ============================================

  describe "Step" do
    test "validates correctly" do
      assert :ok = Dag.Component.validate(Step.new(:a, fn _, _ -> {:ok, 1} end))
      assert {:error, :missing_function} = Dag.Component.validate(%Step{id: :a, function: nil})
      assert {:error, :missing_id} = Dag.Component.validate(%Step{id: nil, function: fn _, _ -> :ok end})
    end

    test "inspect" do
      assert inspect(Step.new(:process, fn _, _ -> :ok end, name: "Process")) =~ "#Step<Process>"
    end
  end

  # ============================================
  # Rule Component
  # ============================================

  describe "Rule" do
    test "activates only when condition is true" do
      rule = Rule.new(:r,
        condition: fn inputs, _ctx -> inputs[:__input__] > 10 end,
        action: fn inputs, _ctx -> {:ok, inputs[:__input__] * 2} end
      )

      high_facts = %{__input__: [Fact.new(20)]}
      low_facts = %{__input__: [Fact.new(5)]}

      assert Dag.Invokable.activates?(rule, high_facts, %{})
      refute Dag.Invokable.activates?(rule, low_facts, %{})
    end
  end

  # ============================================
  # Accumulator Component
  # ============================================

  describe "Accumulator" do
    test "validates" do
      assert :ok = Dag.Component.validate(Accumulator.new(:a, reducer: &+/2, initial: 0))
      assert {:error, :missing_reducer} = Dag.Component.validate(%Accumulator{id: :a, reducer: nil})
    end
  end

  # ============================================
  # Branch Component
  # ============================================

  describe "Branch" do
    test "validates" do
      assert :ok = Dag.Component.validate(Branch.new(:b, condition: fn _, _ -> :ok end))
    end
  end

  # ============================================
  # Saga Component
  # ============================================

  describe "Saga" do
    test "compensatable?/1" do
      with_comp = Saga.new(:s, execute: fn _, _ -> {:ok, 1} end, compensate: fn _, _, _ -> :ok end)
      without = Saga.new(:s, execute: fn _, _ -> {:ok, 1} end)

      assert Saga.compensatable?(with_comp)
      refute Saga.compensatable?(without)
    end
  end

  # ============================================
  # Workflow Construction
  # ============================================

  describe "construction" do
    test "new/1 creates empty workflow" do
      w = Workflow.new(:test)
      assert w.name == :test
      assert w.state == :pending
      assert w.components == %{}
    end

    test "add/3 registers component and builds DAG" do
      w =
        Workflow.new(:test)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end), after: :a)

      assert Map.has_key?(w.components, :a)
      assert Map.has_key?(w.components, :b)
      assert Dag.has_edge?(w.dag, :a, :b)
    end

    test "add/3 with groups" do
      w =
        Workflow.new(:test)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end), group: :parallel)
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end), group: :parallel)

      assert Dag.get_group(w.dag, :parallel) |> Enum.sort() == [:a, :b]
    end

    test "validate/1" do
      w =
        Workflow.new(:test)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))

      assert :ok = Workflow.validate(w)
    end

    test "add/3 raises on duplicate component ID" do
      assert_raise ArgumentError, ~r/already exists/, fn ->
        Workflow.new(:dup)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 2} end))
      end
    end

    test "to_dag/1 returns underlying DAG" do
      w = Workflow.new(:test) |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
      dag = Workflow.to_dag(w)
      assert Dag.has_node?(dag, :a)
    end

    test "merge/2 combines workflows" do
      w1 = Workflow.new(:w1) |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
      w2 = Workflow.new(:w2) |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end))

      merged = Workflow.merge(w1, w2)
      assert Map.has_key?(merged.components, :a)
      assert Map.has_key?(merged.components, :b)
      assert merged.name == :w2
    end
  end

  # ============================================
  # Linear Workflow
  # ============================================

  describe "linear workflow (a -> b -> c)" do
    test "executes in order" do
      w =
        Workflow.new(:linear)
        |> Workflow.add(Step.new(:a, fn inputs, _ctx ->
          {:ok, String.upcase(inputs[:__input__])}
        end))
        |> Workflow.add(Step.new(:b, fn inputs, _ctx ->
          {:ok, inputs.a <> "!"}
        end), after: :a)
        |> Workflow.add(Step.new(:c, fn inputs, _ctx ->
          {:ok, String.length(inputs.b)}
        end), after: :b)
        |> Workflow.react_until_satisfied("hello")

      assert w.state == :satisfied
      prods = Workflow.raw_productions(w)
      assert prods.a == "HELLO"
      assert prods.b == "HELLO!"
      assert prods.c == 6
    end

    test "all components marked completed" do
      w =
        Workflow.new(:linear)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end), after: :a)
        |> Workflow.react_until_satisfied(:input)

      assert Workflow.status(w, :a) == :completed
      assert Workflow.status(w, :b) == :completed
    end
  end

  # ============================================
  # Diamond / Shared Computation
  # ============================================

  describe "diamond pattern (shared computation)" do
    test "tokenize runs once, feeds both count and first_word" do
      w =
        Workflow.new(:diamond)
        |> Workflow.add(Step.new(:tokenize, fn inputs, _ctx ->
          {:ok, String.split(inputs[:__input__])}
        end))
        |> Workflow.add(Step.new(:count, fn inputs, _ctx ->
          {:ok, length(inputs.tokenize)}
        end), after: :tokenize)
        |> Workflow.add(Step.new(:first_word, fn inputs, _ctx ->
          {:ok, List.first(inputs.tokenize)}
        end), after: :tokenize)
        |> Workflow.react_until_satisfied("hello world foo")

      prods = Workflow.raw_productions(w)
      assert prods.tokenize == ["hello", "world", "foo"]
      assert prods.count == 3
      assert prods.first_word == "hello"
    end
  end

  # ============================================
  # Fan-in with Accumulator
  # ============================================

  describe "fan-in pattern" do
    test "accumulator merges parallel results" do
      w =
        Workflow.new(:fanin)
        |> Workflow.add(Step.new(:fetch_a, fn _, _ -> {:ok, 10} end))
        |> Workflow.add(Step.new(:fetch_b, fn _, _ -> {:ok, 20} end))
        |> Workflow.add(
          Accumulator.new(:total,
            reducer: fn val, acc -> acc + val end,
            initial: 0
          ),
          after: [:fetch_a, :fetch_b]
        )
        |> Workflow.react_until_satisfied(:go)

      prods = Workflow.raw_productions(w)
      assert prods.total == 30
    end
  end

  # ============================================
  # Async Parallel Execution
  # ============================================

  describe "async execution" do
    test "react_until_satisfied with async: true" do
      w =
        Workflow.new(:async)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end))
        |> Workflow.add(Step.new(:c, fn inputs, _ ->
          {:ok, (inputs[:a] || 0) + (inputs[:b] || 0)}
        end), after: [:a, :b])
        |> Workflow.react_until_satisfied(:go, async: true, max_concurrency: 4)

      assert w.state == :satisfied
      prods = Workflow.raw_productions(w)
      assert prods.a == 1
      assert prods.b == 2
      assert prods.c == 3
    end
  end

  # ============================================
  # Three-Phase Dispatch
  # ============================================

  describe "prepare/execute/apply (three-phase)" do
    test "manual dispatch cycle" do
      w =
        Workflow.new(:dispatch)
        |> Workflow.add(Step.new(:a, fn inputs, _ctx ->
          {:ok, inputs[:__input__] * 2}
        end))
        |> Workflow.add(Step.new(:b, fn inputs, _ctx ->
          {:ok, inputs.a + 1}
        end), after: :a)

      # Phase 1: prepare first batch (roots)
      {w, runnables} = Workflow.prepare_for_dispatch(w, 5)
      assert length(runnables) == 1
      assert hd(runnables).component_id == :a

      # Phase 2: execute externally
      results = Enum.map(runnables, &Runnable.execute/1)
      assert [{:a, {:ok, 10}}] = results

      # Phase 3: apply results
      w = Enum.reduce(results, w, fn {id, result}, acc ->
        Workflow.apply_result(acc, id, result)
      end)

      assert Workflow.status(w, :a) == :completed
      assert Workflow.raw_productions(w).a == 10

      # Next dispatch cycle for :b
      {w, runnables} = Workflow.prepare_for_dispatch(w)
      assert length(runnables) == 1
      assert hd(runnables).component_id == :b

      results = Enum.map(runnables, &Runnable.execute/1)
      w = Enum.reduce(results, w, fn {id, result}, acc ->
        Workflow.apply_result(acc, id, result)
      end)

      assert Workflow.raw_productions(w).b == 11
    end
  end

  # ============================================
  # Scoped Context
  # ============================================

  describe "scoped context" do
    test "different context per component" do
      w =
        Workflow.new(:ctx)
        |> Workflow.add(Step.new(:step_a, fn _inputs, ctx ->
          {:ok, ctx[:secret]}
        end))
        |> Workflow.add(Step.new(:step_b, fn _inputs, ctx ->
          {:ok, ctx[:secret]}
        end))
        |> Workflow.put_context(:scoped, :step_a, :secret, "alpha")
        |> Workflow.put_context(:scoped, :step_b, :secret, "beta")
        |> Workflow.react_until_satisfied(:go)

      prods = Workflow.raw_productions(w)
      assert prods.step_a == "alpha"
      assert prods.step_b == "beta"
    end

    test "put_run_context/2 bulk context" do
      w =
        Workflow.new(:ctx)
        |> Workflow.add(Step.new(:s, fn _inputs, ctx ->
          {:ok, {ctx[:global_val], ctx[:local_val]}}
        end))
        |> Workflow.put_run_context(%{
          _global: %{global_val: "G"},
          s: %{local_val: "L"}
        })
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.raw_productions(w).s == {"G", "L"}
    end
  end

  # ============================================
  # Conditional Routing (Branch)
  # ============================================

  describe "conditional routing" do
    test "branch routes to correct downstream" do
      w =
        Workflow.new(:routing)
        |> Workflow.add(Branch.new(:check,
          condition: fn inputs, _ctx ->
            if inputs[:__input__] > 100, do: :high, else: :low
          end
        ))
        |> Workflow.add(Step.new(:high_handler, fn _inputs, _ctx ->
          {:ok, :handled_high}
        end), after: :check, edge: %{when: :high})
        |> Workflow.add(Step.new(:low_handler, fn _inputs, _ctx ->
          {:ok, :handled_low}
        end), after: :check, edge: %{when: :low})
        |> Workflow.react_until_satisfied(200)

      prods = Workflow.raw_productions(w)
      assert prods.high_handler == :handled_high
      assert Workflow.status(w, :high_handler) == :completed
      # low_handler should be skipped since branch tag was :high
      assert Workflow.status(w, :low_handler) == :skipped
    end

    test "branch routes low path" do
      w =
        Workflow.new(:routing)
        |> Workflow.add(Branch.new(:check,
          condition: fn inputs, _ctx ->
            if inputs[:__input__] > 100, do: :high, else: :low
          end
        ))
        |> Workflow.add(Step.new(:high_handler, fn _inputs, _ctx ->
          {:ok, :handled_high}
        end), after: :check, edge: %{when: :high})
        |> Workflow.add(Step.new(:low_handler, fn _inputs, _ctx ->
          {:ok, :handled_low}
        end), after: :check, edge: %{when: :low})
        |> Workflow.react_until_satisfied(50)

      prods = Workflow.raw_productions(w)
      assert prods.low_handler == :handled_low
      assert Workflow.status(w, :low_handler) == :completed
      assert Workflow.status(w, :high_handler) == :skipped
    end
  end

  # ============================================
  # Rule-based activation
  # ============================================

  describe "rule-based activation" do
    test "rule fires when condition met" do
      w =
        Workflow.new(:rules)
        |> Workflow.add(Rule.new(:guard,
          condition: fn inputs, _ctx -> inputs[:__input__] > 0 end,
          action: fn inputs, _ctx -> {:ok, inputs[:__input__] * 10} end
        ))
        |> Workflow.react_until_satisfied(5)

      assert Workflow.raw_productions(w).guard == 50
    end

    test "rule does not fire when condition not met" do
      w =
        Workflow.new(:rules)
        |> Workflow.add(Rule.new(:guard,
          condition: fn inputs, _ctx -> inputs[:__input__] > 100 end,
          action: fn inputs, _ctx -> {:ok, inputs[:__input__] * 10} end
        ))
        |> Workflow.react_until_satisfied(5)

      assert Workflow.status(w, :guard) == :not_activated
      assert w.state == :satisfied
    end
  end

  # ============================================
  # Error Handling
  # ============================================

  describe "error handling" do
    test "step failure marks component as failed" do
      w =
        Workflow.new(:errors)
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :boom} end))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :fail) == :failed
      assert w.state == :failed
    end

    test "failure propagates to downstream components" do
      w =
        Workflow.new(:errors)
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :boom} end))
        |> Workflow.add(Step.new(:after_fail, fn _, _ -> {:ok, :never} end), after: :fail)
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :fail) == :failed
      assert Workflow.status(w, :after_fail) == :failed
      assert Workflow.error(w, :after_fail) == :upstream_failure
    end

    test "error reason is stored and retrievable" do
      w =
        Workflow.new(:errors)
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :specific_reason} end))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.error(w, :fail) == :specific_reason
    end

    test "failure with alternative path - non-failed predecessor keeps component alive" do
      w =
        Workflow.new(:errors)
        |> Workflow.add(Step.new(:ok_path, fn _, _ -> {:ok, :good} end))
        |> Workflow.add(Step.new(:fail_path, fn _, _ -> {:error, :bad} end))
        |> Workflow.add(Step.new(:merge, fn inputs, _ ->
          {:ok, inputs[:ok_path]}
        end), after: [:ok_path, :fail_path])
        |> Workflow.react_until_satisfied(:go)

      # merge should still fire because ok_path succeeded
      assert Workflow.status(w, :merge) == :completed
      assert Workflow.raw_productions(w).merge == :good
    end

    test "execution log records timing" do
      w =
        Workflow.new(:errors)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.react_until_satisfied(:go)

      log = Workflow.execution_log(w)
      assert length(log) == 1
      assert hd(log).component_id == :a
      assert hd(log).status == :completed
      assert is_integer(hd(log).duration_us)
    end
  end

  # ============================================
  # Saga Compensation
  # ============================================

  describe "saga compensation" do
    test "root saga compensation receives input values" do
      test_pid = self()

      w =
        Workflow.new(:root_saga)
        |> Workflow.add(Saga.new(:only_saga,
          execute: fn _, _ -> {:ok, :executed} end,
          compensate: fn inputs, result, _ctx ->
            send(test_pid, {:compensated, inputs, result})
            :ok
          end
        ))
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :boom} end), after: :only_saga)
        |> Workflow.react_until_satisfied(:my_input)

      assert Workflow.status(w, :only_saga) == :completed
      assert Workflow.status(w, :fail) == :failed

      _w = Workflow.compensate(w)

      assert_received {:compensated, inputs, :executed}
      assert inputs == %{__input__: :my_input}
    end

    test "compensate runs in reverse order" do
      test_pid = self()

      w =
        Workflow.new(:sagas)
        |> Workflow.add(Saga.new(:step1,
          execute: fn _, _ -> {:ok, :result1} end,
          compensate: fn _, _, _ ->
            send(test_pid, {:compensated, :step1})
            :ok
          end
        ))
        |> Workflow.add(Saga.new(:step2,
          execute: fn _, _ -> {:ok, :result2} end,
          compensate: fn _, _, _ ->
            send(test_pid, {:compensated, :step2})
            :ok
          end
        ), after: :step1)
        |> Workflow.add(Step.new(:step3, fn _, _ -> {:error, :boom} end), after: :step2)
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :step1) == :completed
      assert Workflow.status(w, :step2) == :completed
      assert Workflow.status(w, :step3) == :failed

      # Run compensation
      w = Workflow.compensate(w)

      assert_received {:compensated, :step2}
      assert_received {:compensated, :step1}

      assert Workflow.status(w, :step1) == :compensated
      assert Workflow.status(w, :step2) == :compensated
    end
  end

  # ============================================
  # React Single Pass
  # ============================================

  describe "react/2 single pass" do
    test "executes one level at a time" do
      w =
        Workflow.new(:single)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end), after: :a)

      w = Workflow.react(w, :input)

      # After one pass, :a should be completed but :b still pending
      assert Workflow.status(w, :a) == :completed
      assert Workflow.status(w, :b) == :pending

      # Second pass
      w = Workflow.react(w, :input)
      assert Workflow.status(w, :b) == :completed
    end
  end

  # ============================================
  # Productions and Lineage
  # ============================================

  describe "productions" do
    test "productions/1 returns facts by component" do
      w =
        Workflow.new(:prods)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 42} end))
        |> Workflow.react_until_satisfied(:go)

      prods = Workflow.productions(w)
      assert [%Fact{value: 42, source: :a}] = prods.a
    end

    test "production/2 returns facts for specific component" do
      w =
        Workflow.new(:prods)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 42} end))
        |> Workflow.react_until_satisfied(:go)

      assert [%Fact{value: 42}] = Workflow.production(w, :a)
      assert [] = Workflow.production(w, :nonexistent)
    end

    test "lineage traces back to input" do
      w =
        Workflow.new(:lineage)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 2} end), after: :a)
        |> Workflow.react_until_satisfied(:input)

      [fact_b] = Workflow.production(w, :b)
      lineage = Workflow.lineage(w, fact_b.id)

      # Should trace: input_fact -> fact_a -> fact_b
      assert length(lineage) >= 2
      assert List.last(lineage).value == 2
    end
  end

  # ============================================
  # Inspect
  # ============================================

  describe "inspect" do
    test "workflow inspect" do
      w =
        Workflow.new(:test)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))

      inspected = inspect(w)
      assert inspected =~ "#Workflow<"
      assert inspected =~ "name: :test"
    end
  end

  # ============================================
  # Complex: Multi-level Diamond with Context
  # ============================================

  describe "complex workflow" do
    test "multi-level diamond with scoped context" do
      w =
        Workflow.new(:complex)
        |> Workflow.add(Step.new(:parse, fn inputs, _ctx ->
          {:ok, String.to_integer(inputs[:__input__])}
        end))
        |> Workflow.add(Step.new(:double, fn inputs, ctx ->
          {:ok, inputs.parse * ctx[:multiplier]}
        end), after: :parse)
        |> Workflow.add(Step.new(:negate, fn inputs, _ctx ->
          {:ok, -inputs.parse}
        end), after: :parse)
        |> Workflow.add(Step.new(:combine, fn inputs, _ctx ->
          {:ok, inputs.double + inputs.negate}
        end), after: [:double, :negate])
        |> Workflow.put_context(:scoped, :double, :multiplier, 3)
        |> Workflow.react_until_satisfied("10")

      prods = Workflow.raw_productions(w)
      assert prods.parse == 10
      assert prods.double == 30
      assert prods.negate == -10
      assert prods.combine == 20
    end
  end

  # ============================================
  # Accumulator: correct reduction semantics
  # ============================================

  describe "accumulator reduction semantics" do
    test "reduces one value per predecessor, not flattening lists" do
      w =
        Workflow.new(:acc_test)
        |> Workflow.add(Step.new(:list_producer, fn _, _ -> {:ok, [1, 2, 3]} end))
        |> Workflow.add(Step.new(:scalar_producer, fn _, _ -> {:ok, [4, 5, 6]} end))
        |> Workflow.add(
          Accumulator.new(:collect,
            reducer: fn value, acc -> [value | acc] end,
            initial: []
          ),
          after: [:list_producer, :scalar_producer]
        )
        |> Workflow.react_until_satisfied(:go)

      result = Workflow.raw_productions(w).collect
      # Should have 2 elements (one per predecessor), not 6 individual numbers
      assert length(result) == 2
      assert Enum.sort(result) == [[1, 2, 3], [4, 5, 6]]
    end

    test "custom emit_when receives actual accumulated value" do
      w =
        Workflow.new(:emit_acc)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 10} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 20} end))
        |> Workflow.add(
          Accumulator.new(:threshold,
            reducer: fn value, acc -> [value | acc] end,
            initial: [],
            emit_when: fn acc, _received, _expected -> length(acc) >= 2 end
          ),
          after: [:a, :b]
        )
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :threshold) == :completed
      result = Workflow.raw_productions(w).threshold
      assert length(result) == 2
    end

    test "custom emit_when controls activation" do
      w =
        Workflow.new(:emit_test)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 10} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 20} end))
        |> Workflow.add(
          Accumulator.new(:early,
            reducer: fn value, acc -> acc + value end,
            initial: 0,
            emit_when: fn _acc, received, _expected -> received >= 1 end
          ),
          after: [:a, :b]
        )
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :early) == :completed
      assert Workflow.raw_productions(w).early == 30
    end
  end

  # ============================================
  # Timeout Support
  # ============================================

  describe "timeout support" do
    test "step with timeout that completes in time" do
      w =
        Workflow.new(:timeout)
        |> Workflow.add(Step.new(:fast, fn _, _ -> {:ok, :done} end, timeout: 5000))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :fast) == :completed
    end

    test "step with timeout that exceeds limit" do
      w =
        Workflow.new(:timeout)
        |> Workflow.add(Step.new(:slow, fn _, _ ->
          Process.sleep(500)
          {:ok, :done}
        end, timeout: 50))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :slow) == :failed
      assert Workflow.error(w, :slow) == :timeout
    end
  end

  # ============================================
  # Validation: DAG/component sync
  # ============================================

  describe "validation sync" do
    test "detects orphan DAG nodes without components" do
      w = Workflow.new(:test)
      # Manually add a node to the DAG without a component
      w = %{w | dag: Dag.add_node(w.dag, :orphan)}

      assert {:error, {:nodes_without_components, [:orphan]}} = Workflow.validate(w)
    end
  end

  # ============================================
  # Failure Propagation Chain
  # ============================================

  describe "failure propagation chain" do
    test "cascading failure through deep chain" do
      w =
        Workflow.new(:chain)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:error, :root_cause} end))
        |> Workflow.add(Step.new(:b, fn _, _ -> {:ok, 1} end), after: :a)
        |> Workflow.add(Step.new(:c, fn _, _ -> {:ok, 2} end), after: :b)
        |> Workflow.add(Step.new(:d, fn _, _ -> {:ok, 3} end), after: :c)
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :a) == :failed
      assert Workflow.status(w, :b) == :failed
      assert Workflow.status(w, :c) == :failed
      assert Workflow.status(w, :d) == :failed

      assert Workflow.error(w, :a) == :root_cause
      assert Workflow.error(w, :b) == :upstream_failure
    end
  end

  # ============================================
  # 1-arity Step functions
  # ============================================

  describe "1-arity step functions" do
    test "root step receives raw input" do
      w =
        Workflow.new(:simple)
        |> Workflow.add(Step.new(:upcase, fn text -> {:ok, String.upcase(text)} end))
        |> Workflow.react_until_satisfied("hello")

      assert Workflow.raw_productions(w).upcase == "HELLO"
    end

    test "non-root step receives predecessor output" do
      w =
        Workflow.new(:simple)
        |> Workflow.add(Step.new(:double, fn x -> {:ok, x * 2} end))
        |> Workflow.add(Step.new(:add_one, fn x -> {:ok, x + 1} end), after: :double)
        |> Workflow.react_until_satisfied(5)

      assert Workflow.raw_productions(w).double == 10
      assert Workflow.raw_productions(w).add_one == 11
    end

    test "1-arity mixed with 2-arity" do
      w =
        Workflow.new(:mixed)
        |> Workflow.add(Step.new(:parse, fn text -> {:ok, String.to_integer(text)} end))
        |> Workflow.add(Step.new(:multiply, fn inputs, ctx ->
          {:ok, inputs.parse * ctx[:factor]}
        end), after: :parse)
        |> Workflow.put_context(:scoped, :multiply, :factor, 3)
        |> Workflow.react_until_satisfied("7")

      assert Workflow.raw_productions(w).parse == 7
      assert Workflow.raw_productions(w).multiply == 21
    end
  end

  # ============================================
  # Rules terminal state
  # ============================================

  describe "rules terminal state" do
    test "rule that never fires gets :not_activated" do
      w =
        Workflow.new(:rules)
        |> Workflow.add(Rule.new(:guard,
          condition: fn inputs, _ctx -> inputs[:__input__] > 100 end,
          action: fn inputs, _ctx -> {:ok, inputs[:__input__] * 10} end
        ))
        |> Workflow.react_until_satisfied(5)

      assert Workflow.status(w, :guard) == :not_activated
      assert w.state == :satisfied
    end
  end

  # ============================================
  # Re-react guard
  # ============================================

  describe "re-react guard" do
    test "react_until_satisfied on completed workflow is a no-op" do
      w =
        Workflow.new(:guard)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end))
        |> Workflow.react_until_satisfied(:first)

      assert w.state == :satisfied
      prods1 = Workflow.raw_productions(w)

      # Re-reacting should be a no-op
      w2 = Workflow.react_until_satisfied(w, :second)
      assert w2.state == :satisfied
      assert Workflow.raw_productions(w2) == prods1
    end
  end

  # ============================================
  # Workflow.reset/1
  # ============================================

  describe "reset/1" do
    test "clears state for re-execution" do
      w =
        Workflow.new(:reset)
        |> Workflow.add(Step.new(:a, fn x -> {:ok, x * 2} end))
        |> Workflow.react_until_satisfied(5)

      assert Workflow.raw_productions(w).a == 10
      assert w.state == :satisfied

      # Reset and re-run with different input
      w2 =
        w
        |> Workflow.reset()
        |> Workflow.react_until_satisfied(100)

      assert Workflow.raw_productions(w2).a == 200
      assert w2.state == :satisfied
    end
  end

  # ============================================
  # max_iterations :halted state
  # ============================================

  describe "max_iterations" do
    test "hitting iteration limit produces :halted state" do
      w =
        Workflow.new(:halted)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end))
        |> Workflow.react_until_satisfied(:go, max_iterations: 0)

      assert w.state == :halted
    end
  end

  # ============================================
  # Finalization chain (map-order-independent)
  # ============================================

  describe "finalization chain" do
    test "inactive rule propagates :not_activated through dependent chain" do
      # Use atom names that force reverse-topological map iteration
      w =
        Workflow.new(:finalize)
        |> Workflow.add(Rule.new(:aaa_rule,
          condition: fn _, _ -> false end,
          action: fn _, _ -> {:ok, :never} end
        ))
        |> Workflow.add(Step.new(:mmm_step, fn _ -> {:ok, 1} end), after: :aaa_rule)
        |> Workflow.add(Step.new(:zzz_step, fn _ -> {:ok, 2} end), after: :mmm_step)
        |> Workflow.react_until_satisfied(:go)

      # All must be :not_activated regardless of map iteration order
      assert Workflow.status(w, :aaa_rule) == :not_activated
      assert Workflow.status(w, :mmm_step) == :not_activated
      assert Workflow.status(w, :zzz_step) == :not_activated
    end
  end

  # ============================================
  # Workflow.pipe/3
  # ============================================

  describe "pipe/3 linear composition" do
    test "chains steps automatically" do
      w =
        Workflow.new(:pipeline)
        |> Workflow.pipe(:parse, fn text -> {:ok, String.to_integer(text)} end)
        |> Workflow.pipe(:double, fn n -> {:ok, n * 2} end)
        |> Workflow.pipe(:format, fn n -> {:ok, "Result: #{n}"} end)
        |> Workflow.react_until_satisfied("5")

      prods = Workflow.raw_productions(w)
      assert prods.parse == 5
      assert prods.double == 10
      assert prods.format == "Result: 10"
    end

    test "pipe after fan-out creates fan-in" do
      w =
        Workflow.new(:fanin)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 10} end))
        |> Workflow.add(Step.new(:b, fn _ -> {:ok, 20} end))
        # pipe should chain after both leaves [:a, :b]
        |> Workflow.pipe(:merge, fn inputs, _ctx ->
          {:ok, inputs.a + inputs.b}
        end)
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.raw_productions(w).merge == 30
    end
  end

  # ============================================
  # Workflow.to_mermaid/2
  # ============================================

  describe "to_mermaid/2" do
    test "generates status-aware mermaid diagram" do
      w =
        Workflow.new(:viz)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end, name: "Start"))
        |> Workflow.add(Step.new(:b, fn _ -> {:error, :boom} end), after: :a)
        |> Workflow.react_until_satisfied(:go)

      mermaid = Workflow.to_mermaid(w)
      assert mermaid =~ "graph TD"
      assert mermaid =~ "completed"
      assert mermaid =~ "failed"
      assert mermaid =~ "fill:#90EE90"
    end
  end

  # ============================================
  # 1-arity for Rule, Branch, Saga (Feature 0)
  # ============================================

  describe "1-arity functions for all components" do
    test "Rule with 1-arity condition and action" do
      w =
        Workflow.new(:rule_1arity)
        |> Workflow.add(Rule.new(:guard,
          condition: fn value -> value > 0 end,
          action: fn value -> {:ok, value * 10} end
        ))
        |> Workflow.react_until_satisfied(5)

      assert Workflow.raw_productions(w).guard == 50
    end

    test "Rule 1-arity condition that rejects" do
      w =
        Workflow.new(:rule_1arity)
        |> Workflow.add(Rule.new(:guard,
          condition: fn value -> value > 100 end,
          action: fn value -> {:ok, value * 10} end
        ))
        |> Workflow.react_until_satisfied(5)

      assert Workflow.status(w, :guard) == :not_activated
    end

    test "Branch with 1-arity condition" do
      w =
        Workflow.new(:branch_1arity)
        |> Workflow.add(Branch.new(:check,
          condition: fn value -> if value > 100, do: :high, else: :low end
        ))
        |> Workflow.add(Step.new(:high_handler, fn _ -> {:ok, :high_path} end),
          after: :check, edge: %{when: :high}
        )
        |> Workflow.add(Step.new(:low_handler, fn _ -> {:ok, :low_path} end),
          after: :check, edge: %{when: :low}
        )
        |> Workflow.react_until_satisfied(200)

      assert Workflow.raw_productions(w).high_handler == :high_path
      assert Workflow.status(w, :low_handler) == :skipped
    end

    test "Saga with 1-arity execute" do
      test_pid = self()

      w =
        Workflow.new(:saga_1arity)
        |> Workflow.add(Saga.new(:action,
          execute: fn value -> {:ok, value * 2} end,
          compensate: fn _inputs, result, _ctx ->
            send(test_pid, {:compensated, result})
            :ok
          end
        ))
        |> Workflow.react_until_satisfied(21)

      assert Workflow.raw_productions(w).action == 42
    end

    test "Rule 1-arity with multiple predecessors receives inputs map" do
      w =
        Workflow.new(:multi_pred_rule)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 10} end))
        |> Workflow.add(Step.new(:b, fn _ -> {:ok, 20} end))
        |> Workflow.add(Rule.new(:check,
          condition: fn inputs -> inputs.a + inputs.b > 15 end,
          action: fn inputs -> {:ok, inputs.a + inputs.b} end
        ), after: [:a, :b])
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.raw_productions(w).check == 30
    end

    test "Branch 1-arity with multiple predecessors receives inputs map" do
      w =
        Workflow.new(:multi_pred_branch)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 50} end))
        |> Workflow.add(Step.new(:b, fn _ -> {:ok, 60} end))
        |> Workflow.add(Branch.new(:route,
          condition: fn inputs -> if inputs.a + inputs.b > 100, do: :big, else: :small end
        ), after: [:a, :b])
        |> Workflow.add(Step.new(:big_handler, fn _ -> {:ok, :big_path} end),
          after: :route, edge: %{when: :big}
        )
        |> Workflow.add(Step.new(:small_handler, fn _ -> {:ok, :small_path} end),
          after: :route, edge: %{when: :small}
        )
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.raw_productions(w).big_handler == :big_path
      assert Workflow.status(w, :small_handler) == :skipped
    end

    test "mixed 1-arity and 2-arity Rule" do
      w =
        Workflow.new(:mixed_rule)
        |> Workflow.add(Step.new(:setup, fn _ -> {:ok, 42} end))
        |> Workflow.add(Rule.new(:check,
          condition: fn value -> value > 10 end,
          action: fn inputs, _ctx -> {:ok, inputs.setup + 1} end
        ), after: :setup)
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.raw_productions(w).check == 43
    end
  end

  # ============================================
  # Retry with Backoff (Feature 1)
  # ============================================

  describe "retry with backoff" do
    test "step retries and eventually succeeds" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry)
        |> Workflow.add(Step.new(:flaky, fn _, _ ->
          n = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)
          if n < 2, do: {:error, :transient}, else: {:ok, :success}
        end, retries: 3, retry_delay: 10))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :flaky) == :completed
      assert Workflow.raw_productions(w).flaky == :success
    end

    test "step exhausts all retries and fails" do
      w =
        Workflow.new(:retry)
        |> Workflow.add(Step.new(:always_fail, fn _, _ ->
          {:error, :permanent}
        end, retries: 2, retry_delay: 10))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :always_fail) == :failed
      assert Workflow.error(w, :always_fail) == :permanent
    end

    test "retry with exponential backoff" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry)
        |> Workflow.add(Step.new(:exp, fn _, _ ->
          n = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)
          if n < 1, do: {:error, :transient}, else: {:ok, :done}
        end, retries: 3, retry_delay: 10, retry_backoff: :exponential))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :exp) == :completed
    end

    test "retry with linear backoff" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry)
        |> Workflow.add(Step.new(:lin, fn _, _ ->
          n = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)
          if n < 1, do: {:error, :transient}, else: {:ok, :done}
        end, retries: 2, retry_delay: 10, retry_backoff: :linear))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :lin) == :completed
    end

    test "step without retries fails immediately" do
      w =
        Workflow.new(:no_retry)
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :boom} end))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :fail) == :failed
    end

    test "retry works in async mode" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry_async)
        |> Workflow.add(Step.new(:flaky, fn _, _ ->
          n = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)
          if n < 1, do: {:error, :transient}, else: {:ok, :async_success}
        end, retries: 2, retry_delay: 10))
        |> Workflow.react_until_satisfied(:go, async: true)

      assert Workflow.status(w, :flaky) == :completed
      assert Workflow.raw_productions(w).flaky == :async_success
    end

    test "retry works on Saga component" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry_saga)
        |> Workflow.add(Saga.new(:flaky_saga,
          execute: fn _, _ ->
            n = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)
            if n < 1, do: {:error, :transient}, else: {:ok, :saga_ok}
          end,
          compensate: fn _, _, _ -> :ok end,
          retries: 2, retry_delay: 10
        ))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :flaky_saga) == :completed
      assert Workflow.raw_productions(w).flaky_saga == :saga_ok
    end

    test "retry works on Rule component" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry_rule)
        |> Workflow.add(Rule.new(:flaky_rule,
          condition: fn _, _ -> true end,
          action: fn _, _ ->
            n = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)
            if n < 1, do: {:error, :transient}, else: {:ok, :rule_ok}
          end,
          retries: 2, retry_delay: 10
        ))
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :flaky_rule) == :completed
      assert Workflow.raw_productions(w).flaky_rule == :rule_ok
    end

    test "retry with react_once" do
      counter = :counters.new(1, [:atomics])

      w =
        Workflow.new(:retry_once)
        |> Workflow.add(Step.new(:flaky, fn _, _ ->
          n = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)
          if n < 1, do: {:error, :transient}, else: {:ok, :once_success}
        end, retries: 2, retry_delay: 10))

      w = Workflow.react(w, :go)

      assert Workflow.status(w, :flaky) == :completed
      assert Workflow.raw_productions(w).flaky == :once_success
    end
  end

  # ============================================
  # Graft + Continue (Feature 2)
  # ============================================

  describe "graft and continue" do
    test "graft a step onto a satisfied workflow and continue" do
      w =
        Workflow.new(:graft)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 10} end))
        |> Workflow.react_until_satisfied(:go)

      assert w.state == :satisfied
      assert Workflow.raw_productions(w).a == 10

      w =
        w
        |> Workflow.graft(Step.new(:b, fn inputs, _ -> {:ok, inputs.a * 2} end), after: :a)
        |> Workflow.continue()

      assert w.state == :satisfied
      assert Workflow.raw_productions(w).b == 20
    end

    test "graft multiple steps and continue" do
      w =
        Workflow.new(:graft_multi)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 5} end))
        |> Workflow.react_until_satisfied(:go)

      w =
        w
        |> Workflow.graft(Step.new(:b, fn inputs, _ -> {:ok, inputs.a + 1} end), after: :a)
        |> Workflow.graft(Step.new(:c, fn inputs, _ -> {:ok, inputs.b + 1} end), after: :b)
        |> Workflow.continue()

      assert Workflow.raw_productions(w).b == 6
      assert Workflow.raw_productions(w).c == 7
    end

    test "graft preserves original productions" do
      w =
        Workflow.new(:graft_preserve)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, :original} end))
        |> Workflow.react_until_satisfied(:go)

      w =
        w
        |> Workflow.graft(Step.new(:b, fn _, _ -> {:ok, :grafted} end), after: :a)
        |> Workflow.continue()

      assert Workflow.raw_productions(w).a == :original
      assert Workflow.raw_productions(w).b == :grafted
    end

    test "continue on a pending workflow is a no-op" do
      w = Workflow.new(:pending) |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end))
      w2 = Workflow.continue(w)
      assert w2.state == :pending
    end

    test "graft with duplicate ID raises" do
      w =
        Workflow.new(:dup)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end))
        |> Workflow.react_until_satisfied(:go)

      assert_raise ArgumentError, ~r/already exists/, fn ->
        Workflow.graft(w, Step.new(:a, fn _ -> {:ok, 2} end))
      end
    end
  end

  # ============================================
  # Checkpoint / Restore (Feature 3)
  # ============================================

  describe "checkpoint and restore" do
    test "checkpoint round-trip preserves productions" do
      w =
        Workflow.new(:ckpt)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 42} end))
        |> Workflow.add(Step.new(:b, fn inputs, _ -> {:ok, inputs.a + 1} end), after: :a)
        |> Workflow.react_until_satisfied(:go)

      checkpoint = Workflow.checkpoint(w)

      {:ok, restored} =
        Workflow.restore(checkpoint, %{
          a: Step.new(:a, fn _ -> {:ok, 42} end),
          b: Step.new(:b, fn inputs, _ -> {:ok, inputs.a + 1} end)
        })

      assert restored.name == :ckpt
      assert restored.state == :satisfied
      assert Workflow.raw_productions(restored) == Workflow.raw_productions(w)
      assert restored.activations == w.activations
    end

    test "checkpoint serializes with term_to_binary" do
      w =
        Workflow.new(:ckpt)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end))
        |> Workflow.react_until_satisfied(:go)

      checkpoint = Workflow.checkpoint(w)
      binary = :erlang.term_to_binary(checkpoint)
      restored_checkpoint = :erlang.binary_to_term(binary)

      assert restored_checkpoint.name == :ckpt
      assert restored_checkpoint.state == :satisfied
    end

    test "restore then continue execution with grafted step" do
      w =
        Workflow.new(:ckpt)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 10} end))
        |> Workflow.react_until_satisfied(:go)

      checkpoint = Workflow.checkpoint(w)

      step_a = Step.new(:a, fn _ -> {:ok, 10} end)
      step_b = Step.new(:b, fn inputs, _ -> {:ok, inputs.a * 3} end)

      {:ok, restored} = Workflow.restore(checkpoint, %{a: step_a})

      w2 =
        restored
        |> Workflow.graft(step_b, after: :a)
        |> Workflow.continue()

      assert Workflow.raw_productions(w2).a == 10
      assert Workflow.raw_productions(w2).b == 30
    end

    test "restore with missing components returns error" do
      w =
        Workflow.new(:ckpt)
        |> Workflow.add(Step.new(:a, fn _ -> {:ok, 1} end))
        |> Workflow.add(Step.new(:b, fn _ -> {:ok, 2} end), after: :a)
        |> Workflow.react_until_satisfied(:go)

      checkpoint = Workflow.checkpoint(w)

      # Only provide :a, missing :b
      assert {:error, {:missing_components, missing}} =
               Workflow.restore(checkpoint, %{a: Step.new(:a, fn _ -> {:ok, 1} end)})

      assert :b in missing
    end

    test "checkpoint preserves context" do
      w =
        Workflow.new(:ckpt)
        |> Workflow.add(Step.new(:a, fn _, ctx -> {:ok, ctx[:secret]} end))
        |> Workflow.put_context(:scoped, :a, :secret, "hidden")
        |> Workflow.react_until_satisfied(:go)

      checkpoint = Workflow.checkpoint(w)
      {:ok, restored} = Workflow.restore(checkpoint, %{a: Step.new(:a, fn _, ctx -> {:ok, ctx[:secret]} end)})

      assert restored.context.scoped == w.context.scoped
    end
  end

  # ============================================
  # Async crash safety
  # ============================================

  describe "async crash safety" do
    test "task exit is caught and reported as error" do
      w =
        Workflow.new(:crash)
        |> Workflow.add(Step.new(:crasher, fn _, _ ->
          exit(:boom)
        end))
        |> Workflow.react_until_satisfied(:go, async: true)

      assert Workflow.status(w, :crasher) == :failed
    end
  end

  # ============================================
  # Crash safety: activates? and compensate
  # ============================================

  describe "crash safety" do
    test "Rule condition crash in activates? doesn't kill engine" do
      w =
        Workflow.new(:crash_safe)
        |> Workflow.add(Rule.new(:crasher,
          condition: fn _, _ -> raise "boom in condition" end,
          action: fn _, _ -> {:ok, :never} end
        ))
        |> Workflow.add(Step.new(:safe, fn _ -> {:ok, :ok} end))
        |> Workflow.react_until_satisfied(:go)

      # crasher should be :not_activated (condition raised, treated as false)
      assert Workflow.status(w, :crasher) == :not_activated
      # safe step should still complete
      assert Workflow.status(w, :safe) == :completed
      assert w.state == :satisfied
    end

    test "Accumulator custom emit_when crash doesn't kill engine" do
      w =
        Workflow.new(:crash_safe)
        |> Workflow.add(Step.new(:a, fn _, _ -> {:ok, 1} end))
        |> Workflow.add(
          Accumulator.new(:crasher,
            reducer: fn v, acc -> acc + v end,
            initial: 0,
            emit_when: fn _, _, _ -> raise "boom in emit_when" end
          ),
          after: :a
        )
        |> Workflow.react_until_satisfied(:go)

      assert Workflow.status(w, :crasher) == :not_activated
      assert w.state == :satisfied
    end

    test "saga compensation crash marks compensation_failed, doesn't abort" do
      test_pid = self()

      w =
        Workflow.new(:comp_crash)
        |> Workflow.add(Saga.new(:saga1,
          execute: fn _, _ -> {:ok, :r1} end,
          compensate: fn _, _, _ ->
            send(test_pid, {:compensated, :saga1})
            :ok
          end
        ))
        |> Workflow.add(Saga.new(:saga2,
          execute: fn _, _ -> {:ok, :r2} end,
          compensate: fn _, _, _ -> raise "compensation boom" end
        ), after: :saga1)
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :boom} end), after: :saga2)
        |> Workflow.react_until_satisfied(:go)

      w = Workflow.compensate(w)

      # saga2 compensation crashed — should be :compensation_failed
      assert Workflow.status(w, :saga2) == :compensation_failed
      # saga1 compensation should still run (reverse order: saga2 first, then saga1)
      assert_received {:compensated, :saga1}
      assert Workflow.status(w, :saga1) == :compensated
    end

    test "graft onto failed workflow — grafted step stays not_activated" do
      w =
        Workflow.new(:fail_graft)
        |> Workflow.add(Step.new(:fail, fn _, _ -> {:error, :boom} end))
        |> Workflow.react_until_satisfied(:go)

      assert w.state == :failed

      w =
        w
        |> Workflow.graft(Step.new(:after_fail, fn _, _ -> {:ok, :never} end), after: :fail)
        |> Workflow.continue()

      # after_fail can't run because its only predecessor failed
      assert Workflow.status(w, :after_fail) == :failed
      assert Workflow.error(w, :after_fail) == :upstream_failure
    end
  end
end
