defmodule FnDecorator.ComposeTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Compose

  describe "merge/1" do
    test "merges multiple decorator lists" do
      list1 = [{:cacheable, [cache: MyCache]}, {:telemetry_span, [[:app, :op]]}]
      list2 = [{:log_if_slow, [threshold: 1000]}]

      result = Compose.merge([list1, list2])

      assert length(result) == 3
      assert {:cacheable, [cache: MyCache]} in result
      assert {:telemetry_span, [[:app, :op]]} in result
      assert {:log_if_slow, [threshold: 1000]} in result
    end

    test "handles single decorator tuples" do
      result = Compose.merge([{:cacheable, [cache: MyCache]}, {:log_call, [level: :info]}])

      assert length(result) == 2
    end

    test "handles atom decorators" do
      result = Compose.merge([:cacheable, :log_call])

      assert result == [:cacheable, :log_call]
    end

    test "handles mixed formats" do
      list1 = [{:cacheable, [cache: MyCache]}]

      result = Compose.merge([list1, {:log_call, []}, :pure])

      assert length(result) == 3
    end
  end

  describe "when_env/2" do
    test "returns decorators when environment matches" do
      # In test environment
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_env(:test, decorators)

      assert result == decorators
    end

    test "returns empty list when environment does not match" do
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_env(:prod, decorators)

      assert result == []
    end

    test "accepts list of environments" do
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_env([:dev, :test], decorators)

      assert result == decorators
    end

    test "wraps single decorator in list" do
      result = Compose.when_env(:test, {:debug, [label: "test"]})

      assert result == [{:debug, [label: "test"]}]
    end
  end

  describe "unless_env/2" do
    test "returns empty list when environment matches" do
      decorators = [{:cacheable, [cache: MyCache]}]

      result = Compose.unless_env(:test, decorators)

      assert result == []
    end

    test "returns decorators when environment does not match" do
      decorators = [{:cacheable, [cache: MyCache]}]

      result = Compose.unless_env(:prod, decorators)

      assert result == decorators
    end

    test "accepts list of environments" do
      decorators = [{:cacheable, [cache: MyCache]}]

      result = Compose.unless_env([:dev, :test], decorators)

      assert result == []
    end
  end

  describe "when_true/2" do
    test "returns decorators when condition is true" do
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_true(true, decorators)

      assert result == decorators
    end

    test "returns empty list when condition is false" do
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_true(false, decorators)

      assert result == []
    end

    test "accepts function condition" do
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_true(fn -> 1 + 1 == 2 end, decorators)

      assert result == decorators
    end

    test "evaluates function that returns false" do
      decorators = [{:debug, [label: "test"]}]

      result = Compose.when_true(fn -> 1 + 1 == 3 end, decorators)

      assert result == []
    end
  end

  describe "with_metadata/2" do
    test "adds metadata to decorators with keyword opts" do
      decorators = [{:telemetry_span, [event: [:app, :op]]}]

      result = Compose.with_metadata(decorators, feature: :users, version: "1.0")

      [{:telemetry_span, opts}] = result
      assert opts[:metadata] == %{feature: :users, version: "1.0"}
    end

    test "adds metadata to atom decorators" do
      decorators = [:cacheable]

      result = Compose.with_metadata(decorators, feature: :cache)

      [{:cacheable, opts}] = result
      assert opts[:metadata] == %{feature: :cache}
    end
  end

  describe "build/1" do
    test "combines base and environment-specific decorators" do
      result =
        Compose.build(
          base: [{:telemetry_span, [[:app, :op]]}],
          test_only: [{:debug, [label: "test"]}]
        )

      # In test environment, should include both
      assert length(result) == 2
    end

    test "applies metadata to all decorators" do
      result =
        Compose.build(
          base: [{:telemetry_span, [[:app, :op]]}],
          metadata: [feature: :core]
        )

      [{:telemetry_span, opts}] = result
      assert opts[:metadata] == %{feature: :core}
    end

    test "skips prod_only in test environment" do
      result =
        Compose.build(
          base: [{:telemetry_span, [[:app, :op]]}],
          prod_only: [{:capture_errors, [reporter: Sentry]}]
        )

      # In test environment, prod_only should not be included
      assert length(result) == 1
    end
  end

  describe "wrap/2" do
    test "creates decorator with hooks" do
      result =
        Compose.wrap(:cacheable,
          before: fn _opts, _ctx -> :ok end,
          opts: [cache: MyCache]
        )

      {name, opts} = result
      assert name == :cacheable
      assert opts[:cache] == MyCache
      assert is_function(opts[:before_hook])
    end

    test "creates decorator without hooks" do
      result = Compose.wrap(:cacheable, opts: [cache: MyCache])

      {name, opts} = result
      assert name == :cacheable
      assert opts[:cache] == MyCache
      refute Keyword.has_key?(opts, :before_hook)
      refute Keyword.has_key?(opts, :after_hook)
    end
  end

  describe "describe/1" do
    test "formats decorator list as string" do
      decorators = [
        {:cacheable, [cache: MyCache, ttl: 3600]},
        {:telemetry_span, [[:app, :users, :get]]}
      ]

      result = Compose.describe(decorators)

      assert result =~ "cacheable"
      assert result =~ "telemetry_span"
      assert result =~ "->"
    end

    test "handles atom decorators" do
      decorators = [:cacheable, :log_call]

      result = Compose.describe(decorators)

      assert result == "cacheable() -> log_call()"
    end
  end

  describe "defpreset macro" do
    defmodule TestPresets do
      use FnDecorator.Compose

      defpreset :monitored do
        [
          {:telemetry_span, [[:test, :operation]]},
          {:log_if_slow, [threshold: 1000]}
        ]
      end

      defpreset :cached, opts do
        cache = Keyword.fetch!(opts, :cache)
        [{:cacheable, [cache: cache]}]
      end
    end

    test "creates zero-argument preset" do
      result = TestPresets.monitored()

      assert length(result) == 2
      assert {:telemetry_span, [[:test, :operation]]} in result
      assert {:log_if_slow, [threshold: 1000]} in result
    end

    test "creates parameterized preset" do
      result = TestPresets.cached(cache: MyCache)

      assert result == [{:cacheable, [cache: MyCache]}]
    end
  end

  describe "define_bundle macro" do
    test "creates a bundle module" do
      require FnDecorator.Compose

      FnDecorator.Compose.define_bundle(FnDecorator.ComposeTest.TestBundle, [
        {:telemetry_span, [[:app, :op]]},
        {:log_if_slow, [threshold: 500]}
      ])

      assert Code.ensure_loaded?(FnDecorator.ComposeTest.TestBundle)
      result = FnDecorator.ComposeTest.TestBundle.decorators()
      assert length(result) == 2
    end
  end
end
