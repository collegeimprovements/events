defmodule FnDecorator.Caching.ValidationTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Caching.Validation

  describe "validate/1 - required fields" do
    test "returns error when store.cache is missing" do
      opts = [store: [key: :test, ttl: 5000]]
      assert {:error, %NimbleOptions.ValidationError{}} = Validation.validate(opts)
    end

    test "returns error when store.key is missing" do
      opts = [store: [cache: MyCache, ttl: 5000]]
      assert {:error, %NimbleOptions.ValidationError{}} = Validation.validate(opts)
    end

    test "returns error when store.ttl is missing" do
      opts = [store: [cache: MyCache, key: :test]]
      assert {:error, %NimbleOptions.ValidationError{}} = Validation.validate(opts)
    end

    test "returns ok when all required fields present" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000]]
      assert {:ok, _validated} = Validation.validate(opts)
    end
  end

  describe "validate/1 - type validation" do
    test "returns error when ttl is not positive integer" do
      opts = [store: [cache: MyCache, key: :test, ttl: -1]]
      assert {:error, %NimbleOptions.ValidationError{}} = Validation.validate(opts)
    end

    test "returns error when ttl is zero" do
      opts = [store: [cache: MyCache, key: :test, ttl: 0]]
      assert {:error, %NimbleOptions.ValidationError{}} = Validation.validate(opts)
    end

    test "accepts any value for only_if (validated at runtime)" do
      # only_if type is :any at compile time because functions arrive as AST
      # Runtime will validate the function is callable
      opts = [store: [cache: MyCache, key: :test, ttl: 5000, only_if: :not_a_function]]
      assert {:ok, _validated} = Validation.validate(opts)
    end

    test "accepts valid only_if function" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000, only_if: &match?({:ok, _}, &1)]]
      assert {:ok, _validated} = Validation.validate(opts)
    end
  end

  describe "validate/1 - dependency validation" do
    test "returns error when :stale_access trigger without serve_stale" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], refresh: [on: :stale_access]]
      assert {:error, error} = Validation.validate(opts)
      assert error.message =~ "stale_access"
      assert error.message =~ "serve_stale"
    end

    test "accepts :stale_access trigger with serve_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        refresh: [on: :stale_access],
        serve_stale: [ttl: 10000]
      ]

      assert {:ok, _validated} = Validation.validate(opts)
    end
  end

  describe "validate/1 - logical constraints" do
    test "returns error when serve_stale.ttl <= store.ttl" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: :timer.hours(1)],
        serve_stale: [ttl: :timer.minutes(30)]
      ]

      assert {:error, error} = Validation.validate(opts)
      assert error.message =~ "serve_stale.ttl"
      assert error.message =~ "must be greater than"
    end

    test "accepts serve_stale.ttl > store.ttl" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: :timer.minutes(5)],
        serve_stale: [ttl: :timer.hours(1)]
      ]

      assert {:ok, _validated} = Validation.validate(opts)
    end
  end

  describe "validate!/1" do
    test "returns validated opts when valid" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000]]
      validated = Validation.validate!(opts)
      assert validated[:store][:cache] == MyCache
    end

    test "raises when invalid" do
      opts = [store: [key: :test, ttl: 5000]]

      assert_raise NimbleOptions.ValidationError, fn ->
        Validation.validate!(opts)
      end
    end
  end

  describe "validate/1 - thunder herd validation" do
    test "accepts boolean thunder_herd" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], prevent_thunder_herd: true]
      assert {:ok, _validated} = Validation.validate(opts)
    end

    test "accepts false thunder_herd" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], prevent_thunder_herd: false]
      assert {:ok, _validated} = Validation.validate(opts)
    end

    test "accepts keyword list thunder_herd" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        serve_stale: [ttl: 10000],
        prevent_thunder_herd: [max_wait: 5000, lock_ttl: 30000]
      ]

      assert {:ok, _validated} = Validation.validate(opts)
    end

    test "returns error when lock_ttl < max_wait" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        serve_stale: [ttl: 10000],
        prevent_thunder_herd: [max_wait: 30_000, lock_ttl: 10_000]
      ]

      assert {:error, error} = Validation.validate(opts)
      assert error.message =~ "lock_ttl"
      assert error.message =~ "max_wait"
    end

    test "returns error when on_timeout: :serve_stale without serve_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        prevent_thunder_herd: [on_timeout: :serve_stale]
      ]

      assert {:error, error} = Validation.validate(opts)
      assert error.message =~ "on_timeout"
      assert error.message =~ "serve_stale"
    end

    test "accepts valid on_timeout values" do
      base_opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        serve_stale: [ttl: 10000]
      ]

      valid_on_timeout = [
        :serve_stale,
        :error,
        :proceed,
        {:call, fn -> :ok end},
        {:value, :default}
      ]

      for on_timeout <- valid_on_timeout do
        opts = Keyword.put(base_opts, :prevent_thunder_herd, [on_timeout: on_timeout])
        assert {:ok, _validated} = Validation.validate(opts), "Expected ok for on_timeout: #{inspect(on_timeout)}"
      end
    end
  end

  describe "validate/1 - fallback validation" do
    test "accepts valid fallback on_error" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        serve_stale: [ttl: 10000],
        fallback: [on_error: :serve_stale]
      ]

      assert {:ok, _validated} = Validation.validate(opts)
    end

    test "returns error when on_error: :serve_stale without serve_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        fallback: [on_error: :serve_stale]
      ]

      assert {:error, error} = Validation.validate(opts)
      assert error.message =~ "on_error"
      assert error.message =~ "serve_stale"
    end

    test "accepts {:call, fun} fallback" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        fallback: [on_error: {:call, fn _error -> :fallback end}]
      ]

      assert {:ok, _validated} = Validation.validate(opts)
    end

    test "accepts {:value, term} fallback" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        fallback: [on_error: {:value, :default}]
      ]

      assert {:ok, _validated} = Validation.validate(opts)
    end
  end

  describe "validate_cache_put!/1" do
    test "validates cache_put options" do
      opts = [cache: MyCache, keys: [{User, 1}], ttl: 5000]
      validated = Validation.validate_cache_put!(opts)
      assert validated[:cache] == MyCache
    end

    test "raises when cache missing" do
      opts = [keys: [{User, 1}]]

      assert_raise NimbleOptions.ValidationError, fn ->
        Validation.validate_cache_put!(opts)
      end
    end
  end

  describe "validate_cache_evict!/1" do
    test "validates cache_evict with keys" do
      opts = [cache: MyCache, keys: [{User, 1}]]
      validated = Validation.validate_cache_evict!(opts)
      assert validated[:cache] == MyCache
      assert validated[:keys] == [{User, 1}]
    end

    test "validates cache_evict with match pattern" do
      opts = [cache: MyCache, match: {User, :_}]
      validated = Validation.validate_cache_evict!(opts)
      assert validated[:cache] == MyCache
      assert validated[:match] == {User, :_}
    end

    test "validates cache_evict with all_entries" do
      opts = [cache: MyCache, all_entries: true]
      validated = Validation.validate_cache_evict!(opts)
      assert validated[:all_entries] == true
    end

    test "accepts before_invocation option" do
      opts = [cache: MyCache, keys: [{User, 1}], before_invocation: true]
      validated = Validation.validate_cache_evict!(opts)
      assert validated[:before_invocation] == true
    end

    test "accepts only_if option" do
      opts = [cache: MyCache, keys: [{User, 1}], only_if: &match?({:ok, _}, &1)]
      validated = Validation.validate_cache_evict!(opts)
      assert is_function(validated[:only_if], 1)
    end

    test "accepts both keys and match" do
      opts = [cache: MyCache, keys: [{User, 1}], match: {:user_list, :_}]
      validated = Validation.validate_cache_evict!(opts)
      assert validated[:keys] == [{User, 1}]
      assert validated[:match] == {:user_list, :_}
    end

    test "raises when no eviction target provided" do
      opts = [cache: MyCache]

      assert_raise NimbleOptions.ValidationError, ~r/requires at least one of/, fn ->
        Validation.validate_cache_evict!(opts)
      end
    end

    test "raises when only empty keys provided" do
      opts = [cache: MyCache, keys: []]

      assert_raise NimbleOptions.ValidationError, ~r/requires at least one of/, fn ->
        Validation.validate_cache_evict!(opts)
      end
    end
  end
end
