defmodule FnTypes.IorTest do
  use ExUnit.Case, async: true

  alias FnTypes.Ior

  describe "construction" do
    test "right/1 creates pure success" do
      assert Ior.right(42) == {:right, 42}
      assert Ior.right(%{data: "value"}) == {:right, %{data: "value"}}
    end

    test "left/1 creates failure with single error" do
      assert Ior.left(:not_found) == {:left, [:not_found]}
    end

    test "left/1 creates failure with multiple errors" do
      assert Ior.left([:error1, :error2]) == {:left, [:error1, :error2]}
    end

    test "both/2 creates success with warnings" do
      assert Ior.both(:deprecated, 42) == {:both, [:deprecated], 42}
      assert Ior.both([:warn1, :warn2], "value") == {:both, [:warn1, :warn2], "value"}
    end
  end

  describe "type checking" do
    test "right?/1 detects right values" do
      assert Ior.right?(Ior.right(42))
      refute Ior.right?(Ior.both(:warn, 42))
      refute Ior.right?(Ior.left(:error))
    end

    test "left?/1 detects left values" do
      assert Ior.left?(Ior.left(:error))
      refute Ior.left?(Ior.right(42))
      refute Ior.left?(Ior.both(:warn, 42))
    end

    test "both?/1 detects both values" do
      assert Ior.both?(Ior.both(:warn, 42))
      refute Ior.both?(Ior.right(42))
      refute Ior.both?(Ior.left(:error))
    end

    test "has_value?/1 detects presence of value" do
      assert Ior.has_value?(Ior.right(42))
      assert Ior.has_value?(Ior.both(:warn, 42))
      refute Ior.has_value?(Ior.left(:error))
    end

    test "has_errors?/1 detects presence of errors" do
      assert Ior.has_errors?(Ior.left(:error))
      assert Ior.has_errors?(Ior.both(:warn, 42))
      refute Ior.has_errors?(Ior.right(42))
    end
  end

  describe "map/2" do
    test "maps over right value" do
      assert Ior.map(Ior.right(5), &(&1 * 2)) == {:right, 10}
    end

    test "maps over both value, preserving warnings" do
      assert Ior.map(Ior.both(:warn, 5), &(&1 * 2)) == {:both, [:warn], 10}
    end

    test "does not map over left" do
      assert Ior.map(Ior.left(:error), &(&1 * 2)) == {:left, [:error]}
    end
  end

  describe "map_left/2" do
    test "maps over left errors" do
      assert Ior.map_left(Ior.left(:error), &Atom.to_string/1) == {:left, ["error"]}
    end

    test "maps over both errors" do
      assert Ior.map_left(Ior.both(:warn, 42), &Atom.to_string/1) == {:both, ["warn"], 42}
    end

    test "does not affect right" do
      assert Ior.map_left(Ior.right(42), &Atom.to_string/1) == {:right, 42}
    end
  end

  describe "bimap/3" do
    test "maps both value and errors" do
      assert Ior.bimap(Ior.right(5), &(&1 * 2), &Atom.to_string/1) == {:right, 10}
      assert Ior.bimap(Ior.both(:warn, 5), &(&1 * 2), &Atom.to_string/1) == {:both, ["warn"], 10}
      assert Ior.bimap(Ior.left(:error), &(&1 * 2), &Atom.to_string/1) == {:left, ["error"]}
    end
  end

  describe "and_then/2" do
    test "chains right to right" do
      result =
        Ior.right(5)
        |> Ior.and_then(fn x -> Ior.right(x * 2) end)

      assert result == {:right, 10}
    end

    test "chains right to both" do
      result =
        Ior.right(5)
        |> Ior.and_then(fn x -> Ior.both(:computed, x * 2) end)

      assert result == {:both, [:computed], 10}
    end

    test "chains both to right, preserving errors" do
      result =
        Ior.both(:input_warn, 5)
        |> Ior.and_then(fn x -> Ior.right(x * 2) end)

      assert result == {:both, [:input_warn], 10}
    end

    test "chains both to both, accumulating errors" do
      result =
        Ior.both(:input_warn, 5)
        |> Ior.and_then(fn x -> Ior.both(:computed, x * 2) end)

      assert result == {:both, [:input_warn, :computed], 10}
    end

    test "chains both to left, accumulating errors" do
      result =
        Ior.both(:warn, 5)
        |> Ior.and_then(fn _ -> Ior.left(:failed) end)

      assert result == {:left, [:warn, :failed]}
    end

    test "left short-circuits" do
      result =
        Ior.left(:error)
        |> Ior.and_then(fn x -> Ior.right(x * 2) end)

      assert result == {:left, [:error]}
    end
  end

  describe "flatten/1" do
    test "flattens nested right" do
      assert Ior.flatten(Ior.right(Ior.right(42))) == {:right, 42}
    end

    test "flattens right containing both" do
      assert Ior.flatten(Ior.right(Ior.both(:inner, 42))) == {:both, [:inner], 42}
    end

    test "flattens both containing right" do
      assert Ior.flatten(Ior.both(:outer, Ior.right(42))) == {:both, [:outer], 42}
    end

    test "flattens both containing both, accumulating errors" do
      assert Ior.flatten(Ior.both(:outer, Ior.both(:inner, 42))) == {:both, [:outer, :inner], 42}
    end

    test "flattens both containing left" do
      assert Ior.flatten(Ior.both(:outer, Ior.left(:inner))) == {:left, [:outer, :inner]}
    end
  end

  describe "map2/3" do
    test "combines two rights" do
      assert Ior.map2(Ior.right(1), Ior.right(2), &+/2) == {:right, 3}
    end

    test "combines right and both" do
      assert Ior.map2(Ior.right(1), Ior.both(:b, 2), &+/2) == {:both, [:b], 3}
    end

    test "combines two boths, accumulating errors" do
      assert Ior.map2(Ior.both(:a, 1), Ior.both(:b, 2), &+/2) == {:both, [:a, :b], 3}
    end

    test "combines both and left, returning left" do
      assert Ior.map2(Ior.both(:a, 1), Ior.left(:b), &+/2) == {:left, [:a, :b]}
    end

    test "combines two lefts" do
      assert Ior.map2(Ior.left(:a), Ior.left(:b), &+/2) == {:left, [:a, :b]}
    end
  end

  describe "map3/4" do
    test "combines three rights" do
      result = Ior.map3(Ior.right(1), Ior.right(2), Ior.right(3), fn a, b, c -> a + b + c end)
      assert result == {:right, 6}
    end

    test "combines mixed, accumulating errors" do
      result =
        Ior.map3(
          Ior.both(:a, 1),
          Ior.both(:b, 2),
          Ior.right(3),
          fn a, b, c -> a + b + c end
        )

      assert result == {:both, [:a, :b], 6}
    end
  end

  describe "all/1" do
    test "collects all rights" do
      result = Ior.all([Ior.right(1), Ior.right(2), Ior.right(3)])
      assert result == {:right, [1, 2, 3]}
    end

    test "collects with warnings" do
      result = Ior.all([Ior.right(1), Ior.both(:warn, 2), Ior.right(3)])
      assert result == {:both, [:warn], [1, 2, 3]}
    end

    test "accumulates all errors when any is left" do
      result = Ior.all([Ior.right(1), Ior.left(:error), Ior.both(:warn, 3)])
      assert result == {:left, [:error, :warn]}
    end

    test "handles empty list" do
      assert Ior.all([]) == {:right, []}
    end
  end

  describe "traverse/2" do
    test "traverses with all rights" do
      result = Ior.traverse([1, 2, 3], fn x -> Ior.right(x * 2) end)
      assert result == {:right, [2, 4, 6]}
    end

    test "traverses with some warnings" do
      result =
        Ior.traverse([1, 2, 3], fn
          2 -> Ior.both(:warn_on_2, 4)
          x -> Ior.right(x * 2)
        end)

      assert result == {:both, [:warn_on_2], [2, 4, 6]}
    end
  end

  describe "partition/1" do
    test "partitions iors into categories" do
      result =
        Ior.partition([
          Ior.right(1),
          Ior.left(:a),
          Ior.both(:b, 2),
          Ior.right(3)
        ])

      assert result == %{rights: [1, 3], lefts: [[:a]], boths: [{[:b], 2}]}
    end
  end

  describe "add_error/2 and add_errors/2" do
    test "add_error converts right to both" do
      assert Ior.add_error(Ior.right(42), :warning) == {:both, [:warning], 42}
    end

    test "add_error appends to existing errors" do
      assert Ior.add_error(Ior.both(:existing, 42), :new) == {:both, [:existing, :new], 42}
      assert Ior.add_error(Ior.left(:existing), :new) == {:left, [:existing, :new]}
    end

    test "add_errors adds multiple" do
      assert Ior.add_errors(Ior.right(42), [:a, :b]) == {:both, [:a, :b], 42}
    end

    test "add_errors with empty list is no-op" do
      assert Ior.add_errors(Ior.right(42), []) == {:right, 42}
    end
  end

  describe "clear_errors/1" do
    test "converts both to right" do
      assert Ior.clear_errors(Ior.both(:warn, 42)) == {:right, 42}
    end

    test "keeps right as is" do
      assert Ior.clear_errors(Ior.right(42)) == {:right, 42}
    end

    test "converts left to right with nil" do
      assert Ior.clear_errors(Ior.left(:error)) == {:right, nil}
    end
  end

  describe "warn_if/3" do
    test "adds warning when condition is true" do
      assert Ior.warn_if(Ior.right(42), true, :warned) == {:both, [:warned], 42}
    end

    test "does not add warning when condition is false" do
      assert Ior.warn_if(Ior.right(42), false, :warned) == {:right, 42}
    end

    test "evaluates predicate function on value" do
      assert Ior.warn_if(Ior.right(42), &(&1 > 40), :value_high) == {:both, [:value_high], 42}
      assert Ior.warn_if(Ior.right(5), &(&1 > 40), :value_high) == {:right, 5}
    end
  end

  describe "fail_if_error/2" do
    test "converts both to left if predicate matches any error" do
      result = Ior.fail_if_error(Ior.both(:critical, 42), &(&1 == :critical))
      assert result == {:left, [:critical]}
    end

    test "keeps both if predicate doesn't match" do
      result = Ior.fail_if_error(Ior.both(:minor, 42), &(&1 == :critical))
      assert result == {:both, [:minor], 42}
    end
  end

  describe "extraction" do
    test "unwrap!/1 extracts value from right" do
      assert Ior.unwrap!(Ior.right(42)) == 42
    end

    test "unwrap!/1 extracts value from both" do
      assert Ior.unwrap!(Ior.both(:warn, 42)) == 42
    end

    test "unwrap!/1 raises on left" do
      assert_raise ArgumentError, fn -> Ior.unwrap!(Ior.left(:error)) end
    end

    test "unwrap_or/2 returns default for left" do
      assert Ior.unwrap_or(Ior.right(42), 0) == 42
      assert Ior.unwrap_or(Ior.both(:warn, 42), 0) == 42
      assert Ior.unwrap_or(Ior.left(:error), 0) == 0
    end

    test "unwrap_or_else/2 computes default from errors" do
      result = Ior.unwrap_or_else(Ior.left([:a, :b]), fn errors -> length(errors) end)
      assert result == 2
    end

    test "errors/1 returns errors" do
      assert Ior.errors(Ior.right(42)) == []
      assert Ior.errors(Ior.both([:warn], 42)) == [:warn]
      assert Ior.errors(Ior.left([:a, :b])) == [:a, :b]
    end

    test "value/1 returns value as Maybe" do
      assert Ior.value(Ior.right(42)) == {:some, 42}
      assert Ior.value(Ior.both(:warn, 42)) == {:some, 42}
      assert Ior.value(Ior.left(:error)) == :none
    end
  end

  describe "recovery" do
    test "or_else/2 recovers from left" do
      result = Ior.or_else(Ior.left(:error), fn _ -> Ior.right(0) end)
      assert result == {:right, 0}
    end

    test "or_else/2 does not affect right or both" do
      assert Ior.or_else(Ior.right(42), fn _ -> Ior.right(0) end) == {:right, 42}
      assert Ior.or_else(Ior.both(:warn, 42), fn _ -> Ior.right(0) end) == {:both, [:warn], 42}
    end

    test "recover/2 provides default for left" do
      assert Ior.recover(Ior.left(:error), 0) == {:right, 0}
      assert Ior.recover(Ior.right(42), 0) == {:right, 42}
    end

    test "recover_with_warning/3 provides default with warning" do
      result = Ior.recover_with_warning(Ior.left(:error), 0, :used_default)
      assert result == {:both, [:used_default], 0}
    end
  end

  describe "conversion" do
    test "to_result/1 converts to Result" do
      assert Ior.to_result(Ior.right(42)) == {:ok, 42}
      assert Ior.to_result(Ior.both(:warn, 42)) == {:ok, 42}
      assert Ior.to_result(Ior.left(:error)) == {:error, [:error]}
    end

    test "to_result_with_warnings/1 preserves warnings" do
      assert Ior.to_result_with_warnings(Ior.right(42)) == {:ok, {42, []}}
      assert Ior.to_result_with_warnings(Ior.both(:warn, 42)) == {:ok, {42, [:warn]}}
      assert Ior.to_result_with_warnings(Ior.left(:error)) == {:error, [:error]}
    end

    test "from_result/1 converts from Result" do
      assert Ior.from_result({:ok, 42}) == {:right, 42}
      assert Ior.from_result({:error, :not_found}) == {:left, [:not_found]}
      assert Ior.from_result({:error, [:a, :b]}) == {:left, [:a, :b]}
    end

    test "to_maybe/1 converts to Maybe" do
      assert Ior.to_maybe(Ior.right(42)) == {:some, 42}
      assert Ior.to_maybe(Ior.both(:warn, 42)) == {:some, 42}
      assert Ior.to_maybe(Ior.left(:error)) == :none
    end

    test "from_maybe/2 converts from Maybe" do
      assert Ior.from_maybe({:some, 42}, :was_none) == {:right, 42}
      assert Ior.from_maybe(:none, :was_none) == {:left, [:was_none]}
    end

    test "to_tuple/1 converts to tuple format" do
      assert Ior.to_tuple(Ior.right(42)) == {:right, 42, []}
      assert Ior.to_tuple(Ior.both(:warn, 42)) == {:both, 42, [:warn]}
      assert Ior.to_tuple(Ior.left(:error)) == {:left, nil, [:error]}
    end
  end

  describe "utilities" do
    test "tap/2 executes side effect on value" do
      test_pid = self()

      Ior.right(42)
      |> Ior.tap(fn v -> send(test_pid, {:value, v}) end)

      assert_receive {:value, 42}
    end

    test "tap/2 does not execute on left" do
      test_pid = self()

      Ior.left(:error)
      |> Ior.tap(fn v -> send(test_pid, {:value, v}) end)

      refute_receive {:value, _}
    end

    test "tap_left/2 executes side effect on errors" do
      test_pid = self()

      Ior.both(:warn, 42)
      |> Ior.tap_left(fn errs -> send(test_pid, {:errors, errs}) end)

      assert_receive {:errors, [:warn]}
    end

    test "swap/1 swaps left and right" do
      assert Ior.swap(Ior.right(42)) == {:left, [42]}
      assert Ior.swap(Ior.left(:error)) == {:right, [:error]}
      assert Ior.swap(Ior.both([:warn], 42)) == {:both, [42], [:warn]}
    end

    test "filter/3 converts to left when predicate fails" do
      assert Ior.filter(Ior.right(42), &(&1 > 0), :must_be_positive) == {:right, 42}
      assert Ior.filter(Ior.right(-1), &(&1 > 0), :must_be_positive) == {:left, [:must_be_positive]}
      assert Ior.filter(Ior.both(:warn, 42), &(&1 > 0), :must_be_positive) == {:both, [:warn], 42}
    end

    test "ensure/3 adds warning when predicate fails" do
      assert Ior.ensure(Ior.right(42), &(&1 < 100), :value_high) == {:right, 42}
      assert Ior.ensure(Ior.right(150), &(&1 < 100), :value_high) == {:both, [:value_high], 150}
    end
  end

  describe "real-world example: config parsing" do
    test "parses config with deprecation warnings" do
      result =
        Ior.right(%{})
        |> Ior.and_then(fn config ->
          # Deprecated field
          Ior.both(:deprecated_old_format, Map.put(config, :version, 2))
        end)
        |> Ior.and_then(fn config ->
          # Normal field
          Ior.right(Map.put(config, :timeout, 5000))
        end)
        |> Ior.and_then(fn config ->
          # Another warning
          Ior.both(:missing_optional_field, Map.put(config, :retries, 3))
        end)

      assert result ==
               {:both, [:deprecated_old_format, :missing_optional_field],
                %{version: 2, timeout: 5000, retries: 3}}
    end

    test "fails when critical error occurs" do
      result =
        Ior.right(%{})
        |> Ior.and_then(fn config ->
          Ior.both(:deprecated_field, Map.put(config, :version, 2))
        end)
        |> Ior.and_then(fn _config ->
          Ior.left(:invalid_api_key)
        end)

      assert result == {:left, [:deprecated_field, :invalid_api_key]}
    end
  end

  describe "apply/2" do
    test "applies wrapped function to wrapped value" do
      result = Ior.apply(Ior.right(&String.upcase/1), Ior.right("hello"))
      assert result == {:right, "HELLO"}
    end

    test "accumulates errors from function and value" do
      result = Ior.apply(Ior.both(:fn_warn, &String.upcase/1), Ior.both(:val_warn, "hello"))
      assert result == {:both, [:fn_warn, :val_warn], "HELLO"}
    end
  end
end
