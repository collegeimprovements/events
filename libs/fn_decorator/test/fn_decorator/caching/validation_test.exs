defmodule FnDecorator.Caching.ValidationTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Caching.Validation

  describe "validate/1 - required fields" do
    test "returns error when store.cache is missing" do
      opts = [store: [key: :test, ttl: 5000]]
      assert {:error, "store.cache is required"} = Validation.validate(opts)
    end

    test "returns error when store.key is missing" do
      opts = [store: [cache: MyCache, ttl: 5000]]
      assert {:error, "store.key is required"} = Validation.validate(opts)
    end

    test "returns error when store.ttl is missing" do
      opts = [store: [cache: MyCache, key: :test]]
      assert {:error, "store.ttl is required"} = Validation.validate(opts)
    end

    test "returns :ok when all required fields present" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000]]
      assert :ok = Validation.validate(opts)
    end
  end

  describe "validate/1 - type validation" do
    test "returns error when ttl is not positive integer" do
      opts = [store: [cache: MyCache, key: :test, ttl: -1]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "store.ttl must be a positive integer"
    end

    test "returns error when ttl is zero" do
      opts = [store: [cache: MyCache, key: :test, ttl: 0]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "store.ttl must be a positive integer"
    end

    test "returns error when only_if is not a function" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000, only_if: :not_a_function]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "store.only_if must be a function"
    end

    test "returns error when refresh.retries is negative" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], refresh: [retries: -1]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "refresh.retries must be a positive integer"
    end

    test "returns error for invalid trigger" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], refresh: [on: :invalid_trigger]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "invalid trigger"
    end

    test "accepts valid triggers" do
      valid_triggers = [
        :stale_access,
        :immediately_when_expired,
        :when_expired,
        :on_expiry,
        {:every, 5000},
        {:every, 5000, only_if_stale: true},
        {:cron, "* * * * *"},
        {:cron, "0 * * * *", only_if_stale: true}
      ]

      # Triggers that require serve_stale
      requires_serve_stale = [:stale_access, {:every, 5000, only_if_stale: true}, {:cron, "0 * * * *", only_if_stale: true}]

      for trigger <- valid_triggers do
        base_opts = [store: [cache: MyCache, key: :test, ttl: 5000], refresh: [on: trigger]]

        opts =
          if trigger in requires_serve_stale do
            Keyword.put(base_opts, :serve_stale, ttl: 10000)
          else
            base_opts
          end

        result = Validation.validate(opts)
        assert result == :ok or match?({:ok, _}, result), "Expected ok for trigger: #{inspect(trigger)}"
      end
    end

    test "returns error for invalid cron expression" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], refresh: [on: {:cron, "invalid"}]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "invalid cron expression"
    end
  end

  describe "validate/1 - dependency validation" do
    test "returns error when :stale_access trigger without serve_stale" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], refresh: [on: :stale_access]]
      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ ":stale_access trigger requires serve_stale"
    end

    test "accepts :stale_access trigger with serve_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        refresh: [on: :stale_access],
        serve_stale: [ttl: 10000]
      ]

      assert :ok = Validation.validate(opts)
    end

    test "returns error when only_if_stale without serve_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        refresh: [on: {:cron, "* * * * *", only_if_stale: true}]
      ]

      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "only_if_stale: true option requires serve_stale"
    end
  end

  describe "validate/1 - logical constraints" do
    test "returns error when serve_stale.ttl <= store.ttl" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: :timer.hours(1)],
        serve_stale: [ttl: :timer.minutes(30)]
      ]

      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "serve_stale.ttl"
      assert msg =~ "must be greater than"
    end

    test "accepts serve_stale.ttl > store.ttl" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: :timer.minutes(5)],
        serve_stale: [ttl: :timer.hours(1)]
      ]

      assert :ok = Validation.validate(opts)
    end

    test "returns error when interval < ttl without only_if_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: :timer.minutes(5)],
        refresh: [on: {:every, :timer.seconds(30)}]
      ]

      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "refresh interval is shorter than store.ttl"
    end

    test "accepts interval < ttl with only_if_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: :timer.minutes(5)],
        refresh: [on: {:every, :timer.seconds(30), only_if_stale: true}],
        serve_stale: [ttl: :timer.hours(1)]
      ]

      assert :ok = Validation.validate(opts)
    end
  end

  describe "validate/1 - warnings" do
    test "returns warning when lock_timeout < max_wait" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        prevent_thunder_herd: [max_wait: 30_000, lock_timeout: 10_000]
      ]

      assert {:ok, warnings} = Validation.validate(opts)
      assert length(warnings) == 1
      [{:warning, msg}] = warnings
      assert msg =~ "lock_timeout"
      assert msg =~ "less than"
      assert msg =~ "max_wait"
    end

    test "no warning when lock_timeout >= max_wait" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        prevent_thunder_herd: [max_wait: 5_000, lock_timeout: 30_000]
      ]

      assert :ok = Validation.validate(opts)
    end
  end

  describe "validate!/1" do
    test "returns opts when valid" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000]]
      assert ^opts = Validation.validate!(opts)
    end

    test "raises CompileError when invalid" do
      opts = [store: [key: :test, ttl: 5000]]

      assert_raise CompileError, ~r/store.cache is required/, fn ->
        Validation.validate!(opts)
      end
    end
  end

  describe "validate/1 - thunder herd validation" do
    test "accepts boolean thunder_herd" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], prevent_thunder_herd: true]
      assert :ok = Validation.validate(opts)
    end

    test "accepts false thunder_herd" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], prevent_thunder_herd: false]
      assert :ok = Validation.validate(opts)
    end

    test "accepts timeout thunder_herd" do
      opts = [store: [cache: MyCache, key: :test, ttl: 5000], prevent_thunder_herd: 10_000]
      assert :ok = Validation.validate(opts)
    end

    test "accepts keyword list thunder_herd" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        prevent_thunder_herd: [max_wait: 5000, retries: 3]
      ]

      assert :ok = Validation.validate(opts)
    end

    test "returns error for invalid on_timeout" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        prevent_thunder_herd: [on_timeout: :invalid]
      ]

      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "on_timeout must be"
    end

    test "accepts valid on_timeout values" do
      valid_on_timeout = [
        :serve_stale,
        :error,
        {:call, fn -> :ok end},
        {:value, :default}
      ]

      for on_timeout <- valid_on_timeout do
        # :serve_stale requires serve_stale to be configured
        base_opts = [
          store: [cache: MyCache, key: :test, ttl: 5000],
          prevent_thunder_herd: [on_timeout: on_timeout]
        ]

        opts =
          if on_timeout == :serve_stale do
            Keyword.put(base_opts, :serve_stale, ttl: 10000)
          else
            base_opts
          end

        result = Validation.validate(opts)
        assert result == :ok or match?({:ok, _}, result), "Expected ok for on_timeout: #{inspect(on_timeout)}"
      end
    end
  end

  describe "validate/1 - fallback validation" do
    test "accepts valid fallback actions" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        serve_stale: [ttl: 10000],
        fallback: [
          on_refresh_failure: :serve_stale,
          on_cache_unavailable: {:call, fn -> :ok end}
        ]
      ]

      assert :ok = Validation.validate(opts)
    end

    test "returns error for invalid fallback action" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        fallback: [on_refresh_failure: :invalid]
      ]

      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "on_refresh_failure must be"
    end

    test "returns error when on_refresh_failure: :serve_stale without serve_stale" do
      opts = [
        store: [cache: MyCache, key: :test, ttl: 5000],
        fallback: [on_refresh_failure: :serve_stale]
      ]

      assert {:error, msg} = Validation.validate(opts)
      assert msg =~ "on_refresh_failure: :serve_stale requires serve_stale"
    end
  end
end
