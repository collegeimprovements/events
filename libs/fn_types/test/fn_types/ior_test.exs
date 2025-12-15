defmodule FnTypes.IorTest do
  use ExUnit.Case, async: true

  alias FnTypes.Ior

  describe "construction" do
    test "right/1 creates pure success" do
      assert Ior.success(42) == {:success, 42}
      assert Ior.success(%{data: "value"}) == {:success, %{data: "value"}}
    end

    test "left/1 creates failure with single error" do
      assert Ior.failure(:not_found) == {:failure, [:not_found]}
    end

    test "left/1 creates failure with multiple errors" do
      assert Ior.failure([:error1, :error2]) == {:failure, [:error1, :error2]}
    end

    test "both/2 creates success with warnings" do
      assert Ior.partial(:deprecated, 42) == {:partial, [:deprecated], 42}
      assert Ior.partial([:warn1, :warn2], "value") == {:partial, [:warn1, :warn2], "value"}
    end
  end

  describe "type checking" do
    test "right?/1 detects right values" do
      assert Ior.right?(Ior.success(42))
      refute Ior.right?(Ior.partial(:warn, 42))
      refute Ior.right?(Ior.failure(:error))
    end

    test "left?/1 detects left values" do
      assert Ior.left?(Ior.failure(:error))
      refute Ior.left?(Ior.success(42))
      refute Ior.left?(Ior.partial(:warn, 42))
    end

    test "both?/1 detects both values" do
      assert Ior.both?(Ior.partial(:warn, 42))
      refute Ior.both?(Ior.success(42))
      refute Ior.both?(Ior.failure(:error))
    end

    test "has_value?/1 detects presence of value" do
      assert Ior.has_value?(Ior.success(42))
      assert Ior.has_value?(Ior.partial(:warn, 42))
      refute Ior.has_value?(Ior.failure(:error))
    end

    test "has_errors?/1 detects presence of errors" do
      assert Ior.has_errors?(Ior.failure(:error))
      assert Ior.has_errors?(Ior.partial(:warn, 42))
      refute Ior.has_errors?(Ior.success(42))
    end
  end

  describe "map/2" do
    test "maps over right value" do
      assert Ior.map(Ior.success(5), &(&1 * 2)) == {:success, 10}
    end

    test "maps over both value, preserving warnings" do
      assert Ior.map(Ior.partial(:warn, 5), &(&1 * 2)) == {:partial, [:warn], 10}
    end

    test "does not map over left" do
      assert Ior.map(Ior.failure(:error), &(&1 * 2)) == {:failure, [:error]}
    end
  end

  describe "map_left/2" do
    test "maps over left errors" do
      assert Ior.map_failure(Ior.failure(:error), &Atom.to_string/1) == {:failure, ["error"]}
    end

    test "maps over both errors" do
      assert Ior.map_failure(Ior.partial(:warn, 42), &Atom.to_string/1) == {:partial, ["warn"], 42}
    end

    test "does not affect right" do
      assert Ior.map_failure(Ior.success(42), &Atom.to_string/1) == {:success, 42}
    end
  end

  describe "bimap/2" do
    test "maps success value with on_success function" do
      result = Ior.bimap(Ior.success(5), on_success: &(&1 * 2), on_failure: &Atom.to_string/1)
      assert result == {:success, 10}
    end

    test "maps partial value and warnings with both functions" do
      result = Ior.bimap(Ior.partial(:warn, 5), on_success: &(&1 * 2), on_failure: &Atom.to_string/1)
      assert result == {:partial, ["warn"], 10}
    end

    test "maps failure errors with on_failure function" do
      result = Ior.bimap(Ior.failure(:error), on_success: &(&1 * 2), on_failure: &Atom.to_string/1)
      assert result == {:failure, ["error"]}
    end

    test "transforms only success when on_failure omitted" do
      assert Ior.bimap(Ior.success(5), on_success: &(&1 * 2)) == {:success, 10}
      assert Ior.bimap(Ior.partial(:warn, 5), on_success: &(&1 * 2)) == {:partial, [:warn], 10}
    end

    test "transforms only failure when on_success omitted" do
      assert Ior.bimap(Ior.failure(:error), on_failure: &Atom.to_string/1) == {:failure, ["error"]}
      assert Ior.bimap(Ior.partial(:warn, 5), on_failure: &Atom.to_string/1) == {:partial, ["warn"], 5}
    end
  end

  describe "and_then/2" do
    test "chains right to right" do
      result =
        Ior.success(5)
        |> Ior.and_then(fn x -> Ior.success(x * 2) end)

      assert result == {:success, 10}
    end

    test "chains right to both" do
      result =
        Ior.success(5)
        |> Ior.and_then(fn x -> Ior.partial(:computed, x * 2) end)

      assert result == {:partial, [:computed], 10}
    end

    test "chains both to right, preserving errors" do
      result =
        Ior.partial(:input_warn, 5)
        |> Ior.and_then(fn x -> Ior.success(x * 2) end)

      assert result == {:partial, [:input_warn], 10}
    end

    test "chains both to both, accumulating errors" do
      result =
        Ior.partial(:input_warn, 5)
        |> Ior.and_then(fn x -> Ior.partial(:computed, x * 2) end)

      assert result == {:partial, [:input_warn, :computed], 10}
    end

    test "chains both to left, accumulating errors" do
      result =
        Ior.partial(:warn, 5)
        |> Ior.and_then(fn _ -> Ior.failure(:failed) end)

      assert result == {:failure, [:warn, :failed]}
    end

    test "left short-circuits" do
      result =
        Ior.failure(:error)
        |> Ior.and_then(fn x -> Ior.success(x * 2) end)

      assert result == {:failure, [:error]}
    end
  end

  describe "flatten/1" do
    test "flattens nested right" do
      assert Ior.flatten(Ior.success(Ior.success(42))) == {:success, 42}
    end

    test "flattens right containing both" do
      assert Ior.flatten(Ior.success(Ior.partial(:inner, 42))) == {:partial, [:inner], 42}
    end

    test "flattens both containing right" do
      assert Ior.flatten(Ior.partial(:outer, Ior.success(42))) == {:partial, [:outer], 42}
    end

    test "flattens both containing both, accumulating errors" do
      assert Ior.flatten(Ior.partial(:outer, Ior.partial(:inner, 42))) == {:partial, [:outer, :inner], 42}
    end

    test "flattens both containing left" do
      assert Ior.flatten(Ior.partial(:outer, Ior.failure(:inner))) == {:failure, [:outer, :inner]}
    end
  end

  describe "map2/3" do
    test "combines two rights" do
      assert Ior.map2(Ior.success(1), Ior.success(2), &+/2) == {:success, 3}
    end

    test "combines right and both" do
      assert Ior.map2(Ior.success(1), Ior.partial(:b, 2), &+/2) == {:partial, [:b], 3}
    end

    test "combines two boths, accumulating errors" do
      assert Ior.map2(Ior.partial(:a, 1), Ior.partial(:b, 2), &+/2) == {:partial, [:a, :b], 3}
    end

    test "combines both and left, returning left" do
      assert Ior.map2(Ior.partial(:a, 1), Ior.failure(:b), &+/2) == {:failure, [:a, :b]}
    end

    test "combines two lefts" do
      assert Ior.map2(Ior.failure(:a), Ior.failure(:b), &+/2) == {:failure, [:a, :b]}
    end
  end

  describe "map3/4" do
    test "combines three rights" do
      result = Ior.map3(Ior.success(1), Ior.success(2), Ior.success(3), fn a, b, c -> a + b + c end)
      assert result == {:success, 6}
    end

    test "combines mixed, accumulating errors" do
      result =
        Ior.map3(
          Ior.partial(:a, 1),
          Ior.partial(:b, 2),
          Ior.success(3),
          fn a, b, c -> a + b + c end
        )

      assert result == {:partial, [:a, :b], 6}
    end
  end

  describe "all/1" do
    test "collects all rights" do
      result = Ior.all([Ior.success(1), Ior.success(2), Ior.success(3)])
      assert result == {:success, [1, 2, 3]}
    end

    test "collects with warnings" do
      result = Ior.all([Ior.success(1), Ior.partial(:warn, 2), Ior.success(3)])
      assert result == {:partial, [:warn], [1, 2, 3]}
    end

    test "accumulates all errors when any is left" do
      result = Ior.all([Ior.success(1), Ior.failure(:error), Ior.partial(:warn, 3)])
      assert result == {:failure, [:error, :warn]}
    end

    test "handles empty list" do
      assert Ior.all([]) == {:success, []}
    end
  end

  describe "traverse/2" do
    test "traverses with all rights" do
      result = Ior.traverse([1, 2, 3], fn x -> Ior.success(x * 2) end)
      assert result == {:success, [2, 4, 6]}
    end

    test "traverses with some warnings" do
      result =
        Ior.traverse([1, 2, 3], fn
          2 -> Ior.partial(:warn_on_2, 4)
          x -> Ior.success(x * 2)
        end)

      assert result == {:partial, [:warn_on_2], [2, 4, 6]}
    end
  end

  describe "partition/1" do
    test "partitions iors into categories" do
      result =
        Ior.partition([
          Ior.success(1),
          Ior.failure(:a),
          Ior.partial(:b, 2),
          Ior.success(3)
        ])

      assert result == %{successes: [1, 3], failures: [[:a]], partials: [{[:b], 2}]}
    end
  end

  describe "add_error/2 and add_errors/2" do
    test "add_error converts right to both" do
      assert Ior.add_warning(Ior.success(42), :warning) == {:partial, [:warning], 42}
    end

    test "add_error appends to existing errors" do
      assert Ior.add_warning(Ior.partial(:existing, 42), :new) == {:partial, [:existing, :new], 42}
      assert Ior.add_warning(Ior.failure(:existing), :new) == {:failure, [:existing, :new]}
    end

    test "add_errors adds multiple" do
      assert Ior.add_warnings(Ior.success(42), [:a, :b]) == {:partial, [:a, :b], 42}
    end

    test "add_errors with empty list is no-op" do
      assert Ior.add_warnings(Ior.success(42), []) == {:success, 42}
    end
  end

  describe "clear_errors/1" do
    test "converts both to right" do
      assert Ior.clear_warnings(Ior.partial(:warn, 42)) == {:success, 42}
    end

    test "keeps right as is" do
      assert Ior.clear_warnings(Ior.success(42)) == {:success, 42}
    end

    test "converts left to right with nil" do
      assert Ior.clear_warnings(Ior.failure(:error)) == {:success, nil}
    end
  end

  describe "warn_if/3" do
    test "adds warning when condition is true" do
      assert Ior.warn_if(Ior.success(42), true, :warned) == {:partial, [:warned], 42}
    end

    test "does not add warning when condition is false" do
      assert Ior.warn_if(Ior.success(42), false, :warned) == {:success, 42}
    end

    test "evaluates predicate function on value" do
      assert Ior.warn_if(Ior.success(42), &(&1 > 40), :value_high) == {:partial, [:value_high], 42}
      assert Ior.warn_if(Ior.success(5), &(&1 > 40), :value_high) == {:success, 5}
    end
  end

  describe "fail_if_error/2" do
    test "converts both to left if predicate matches any error" do
      result = Ior.fail_if_warning(Ior.partial(:critical, 42), &(&1 == :critical))
      assert result == {:failure, [:critical]}
    end

    test "keeps both if predicate doesn't match" do
      result = Ior.fail_if_warning(Ior.partial(:minor, 42), &(&1 == :critical))
      assert result == {:partial, [:minor], 42}
    end
  end

  describe "extraction" do
    test "unwrap!/1 extracts value from right" do
      assert Ior.unwrap!(Ior.success(42)) == 42
    end

    test "unwrap!/1 extracts value from both" do
      assert Ior.unwrap!(Ior.partial(:warn, 42)) == 42
    end

    test "unwrap!/1 raises on left" do
      assert_raise ArgumentError, fn -> Ior.unwrap!(Ior.failure(:error)) end
    end

    test "unwrap_or/2 returns default for left" do
      assert Ior.unwrap_or(Ior.success(42), 0) == 42
      assert Ior.unwrap_or(Ior.partial(:warn, 42), 0) == 42
      assert Ior.unwrap_or(Ior.failure(:error), 0) == 0
    end

    test "unwrap_or_else/2 computes default from errors" do
      result = Ior.unwrap_or_else(Ior.failure([:a, :b]), fn errors -> length(errors) end)
      assert result == 2
    end

    test "errors/1 returns errors" do
      assert Ior.warnings(Ior.success(42)) == []
      assert Ior.warnings(Ior.partial([:warn], 42)) == [:warn]
      assert Ior.warnings(Ior.failure([:a, :b])) == [:a, :b]
    end

    test "value/1 returns value as Maybe" do
      assert Ior.value(Ior.success(42)) == {:some, 42}
      assert Ior.value(Ior.partial(:warn, 42)) == {:some, 42}
      assert Ior.value(Ior.failure(:error)) == :none
    end
  end

  describe "recovery" do
    test "or_else/2 recovers from left" do
      result = Ior.or_else(Ior.failure(:error), fn _ -> Ior.success(0) end)
      assert result == {:success, 0}
    end

    test "or_else/2 does not affect right or both" do
      assert Ior.or_else(Ior.success(42), fn _ -> Ior.success(0) end) == {:success, 42}
      assert Ior.or_else(Ior.partial(:warn, 42), fn _ -> Ior.success(0) end) == {:partial, [:warn], 42}
    end

    test "recover/2 provides default for left" do
      assert Ior.recover(Ior.failure(:error), 0) == {:success, 0}
      assert Ior.recover(Ior.success(42), 0) == {:success, 42}
    end

    test "recover_with_warning/3 provides default with warning" do
      result = Ior.recover_with_warning(Ior.failure(:error), 0, :used_default)
      assert result == {:partial, [:used_default], 0}
    end
  end

  describe "conversion" do
    test "to_result/1 converts to Result" do
      assert Ior.to_result(Ior.success(42)) == {:ok, 42}
      assert Ior.to_result(Ior.partial(:warn, 42)) == {:ok, 42}
      assert Ior.to_result(Ior.failure(:error)) == {:error, [:error]}
    end

    test "to_result_with_warnings/1 preserves warnings" do
      assert Ior.to_result_with_warnings(Ior.success(42)) == {:ok, {42, []}}
      assert Ior.to_result_with_warnings(Ior.partial(:warn, 42)) == {:ok, {42, [:warn]}}
      assert Ior.to_result_with_warnings(Ior.failure(:error)) == {:error, [:error]}
    end

    test "from_result/1 converts from Result" do
      assert Ior.from_result({:ok, 42}) == {:success, 42}
      assert Ior.from_result({:error, :not_found}) == {:failure, [:not_found]}
      assert Ior.from_result({:error, [:a, :b]}) == {:failure, [:a, :b]}
    end

    test "to_maybe/1 converts to Maybe" do
      assert Ior.to_maybe(Ior.success(42)) == {:some, 42}
      assert Ior.to_maybe(Ior.partial(:warn, 42)) == {:some, 42}
      assert Ior.to_maybe(Ior.failure(:error)) == :none
    end

    test "from_maybe/2 converts from Maybe" do
      assert Ior.from_maybe({:some, 42}, :was_none) == {:success, 42}
      assert Ior.from_maybe(:none, :was_none) == {:failure, [:was_none]}
    end

    test "to_tuple/1 converts to tuple format" do
      assert Ior.to_tuple(Ior.success(42)) == {:success, 42, []}
      assert Ior.to_tuple(Ior.partial(:warn, 42)) == {:partial, 42, [:warn]}
      assert Ior.to_tuple(Ior.failure(:error)) == {:failure, nil, [:error]}
    end
  end

  describe "utilities" do
    test "tap/2 executes side effect on value" do
      test_pid = self()

      Ior.success(42)
      |> Ior.tap(fn v -> send(test_pid, {:value, v}) end)

      assert_receive {:value, 42}
    end

    test "tap/2 does not execute on left" do
      test_pid = self()

      Ior.failure(:error)
      |> Ior.tap(fn v -> send(test_pid, {:value, v}) end)

      refute_receive {:value, _}
    end

    test "tap_warnings/2 executes side effect on errors" do
      test_pid = self()

      Ior.partial(:warn, 42)
      |> Ior.tap_warnings(fn errs -> send(test_pid, {:errors, errs}) end)

      assert_receive {:errors, [:warn]}
    end

    test "swap/1 swaps left and right" do
      assert Ior.swap(Ior.success(42)) == {:failure, [42]}
      assert Ior.swap(Ior.failure(:error)) == {:success, [:error]}
      assert Ior.swap(Ior.partial([:warn], 42)) == {:partial, [42], [:warn]}
    end

    test "filter/3 converts to left when predicate fails" do
      assert Ior.filter(Ior.success(42), &(&1 > 0), :must_be_positive) == {:success, 42}
      assert Ior.filter(Ior.success(-1), &(&1 > 0), :must_be_positive) == {:failure, [:must_be_positive]}
      assert Ior.filter(Ior.partial(:warn, 42), &(&1 > 0), :must_be_positive) == {:partial, [:warn], 42}
    end

    test "ensure/3 adds warning when predicate fails" do
      assert Ior.ensure(Ior.success(42), &(&1 < 100), :value_high) == {:success, 42}
      assert Ior.ensure(Ior.success(150), &(&1 < 100), :value_high) == {:partial, [:value_high], 150}
    end
  end

  describe "real-world example: config parsing" do
    test "parses config with deprecation warnings" do
      result =
        Ior.success(%{})
        |> Ior.and_then(fn config ->
          # Deprecated field
          Ior.partial(:deprecated_old_format, Map.put(config, :version, 2))
        end)
        |> Ior.and_then(fn config ->
          # Normal field
          Ior.success(Map.put(config, :timeout, 5000))
        end)
        |> Ior.and_then(fn config ->
          # Another warning
          Ior.partial(:missing_optional_field, Map.put(config, :retries, 3))
        end)

      assert result ==
               {:partial, [:deprecated_old_format, :missing_optional_field],
                %{version: 2, timeout: 5000, retries: 3}}
    end

    test "fails when critical error occurs" do
      result =
        Ior.success(%{})
        |> Ior.and_then(fn config ->
          Ior.partial(:deprecated_field, Map.put(config, :version, 2))
        end)
        |> Ior.and_then(fn _config ->
          Ior.failure(:invalid_api_key)
        end)

      assert result == {:failure, [:deprecated_field, :invalid_api_key]}
    end
  end

  describe "apply/2" do
    test "applies wrapped function to wrapped value" do
      result = Ior.apply(Ior.success(&String.upcase/1), Ior.success("hello"))
      assert result == {:success, "HELLO"}
    end

    test "accumulates errors from function and value" do
      result = Ior.apply(Ior.partial(:fn_warn, &String.upcase/1), Ior.partial(:val_warn, "hello"))
      assert result == {:partial, [:fn_warn, :val_warn], "HELLO"}
    end
  end
end
