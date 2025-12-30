defmodule FnDecorator.Caching.PresetsTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Caching.Presets

  describe "high_availability/1" do
    test "returns preset with default values" do
      opts = Presets.high_availability()

      assert opts[:store][:ttl] == :timer.minutes(5)
      assert opts[:refresh][:on] == [:stale_access, :immediately_when_expired]
      assert opts[:refresh][:retries] == 5
      assert opts[:serve_stale][:ttl] == :timer.hours(24)
      assert opts[:prevent_thunder_herd][:max_wait] == :timer.seconds(10)
    end

    test "merges user options" do
      opts = Presets.high_availability(cache: MyCache, key: {User, 1}, ttl: :timer.minutes(10))

      assert opts[:store][:cache] == MyCache
      assert opts[:store][:key] == {User, 1}
      assert opts[:store][:ttl] == :timer.minutes(10)
    end

    test "user options override preset defaults" do
      opts = Presets.high_availability(store: [ttl: :timer.hours(1)])

      # User TTL overrides preset TTL
      assert opts[:store][:ttl] == :timer.hours(1)
      # Other preset values remain
      assert opts[:refresh][:retries] == 5
    end
  end

  describe "always_fresh/1" do
    test "returns preset with short TTL" do
      opts = Presets.always_fresh()

      assert opts[:store][:ttl] == :timer.seconds(30)
      assert opts[:refresh][:on] == :immediately_when_expired
      assert opts[:refresh][:retries] == 10
      refute Keyword.has_key?(opts, :serve_stale)
    end
  end

  describe "external_api/1" do
    test "returns preset with cron refresh" do
      opts = Presets.external_api()

      assert opts[:store][:ttl] == :timer.minutes(15)
      assert opts[:refresh][:on] == {:cron, "*/15 * * * *"}
      assert opts[:serve_stale][:ttl] == :timer.hours(4)
      assert opts[:prevent_thunder_herd][:lock_timeout] == :timer.minutes(2)
    end
  end

  describe "expensive/1" do
    test "returns preset with long TTL and cron" do
      opts = Presets.expensive()

      assert opts[:store][:ttl] == :timer.hours(6)
      assert opts[:refresh][:on] == {:cron, "0 */6 * * *"}
      assert opts[:serve_stale][:ttl] == :timer.hours(24 * 7)
      assert opts[:prevent_thunder_herd][:max_wait] == :timer.minutes(2)
    end
  end

  describe "session/1" do
    test "returns preset without stale serving" do
      opts = Presets.session()

      assert opts[:store][:ttl] == :timer.minutes(30)
      assert opts[:prevent_thunder_herd][:max_wait] == :timer.seconds(2)
      refute Keyword.has_key?(opts, :serve_stale)
      refute Keyword.has_key?(opts, :refresh)
    end
  end

  describe "database/1" do
    test "returns standard DB caching preset" do
      opts = Presets.database()

      assert opts[:store][:ttl] == :timer.minutes(5)
      assert opts[:refresh][:on] == :stale_access
      assert opts[:serve_stale][:ttl] == :timer.hours(1)
    end
  end

  describe "minimal/1" do
    test "returns minimal preset with thunder herd only" do
      opts = Presets.minimal()

      assert opts[:prevent_thunder_herd] == true
      refute Keyword.has_key?(opts, :store)
      refute Keyword.has_key?(opts, :refresh)
      refute Keyword.has_key?(opts, :serve_stale)
    end

    test "accepts user TTL" do
      opts = Presets.minimal(cache: MyCache, key: :test, ttl: :timer.minutes(5))

      assert opts[:store][:cache] == MyCache
      assert opts[:store][:key] == :test
      assert opts[:store][:ttl] == :timer.minutes(5)
    end
  end

  describe "merge/2" do
    test "deep merges nested keyword lists" do
      base = [store: [ttl: 1000, cache: MyCache], refresh: [retries: 3]]
      override = [store: [ttl: 2000], refresh: [on: :stale_access]]

      result = Presets.merge(base, override)

      assert result[:store][:ttl] == 2000
      assert result[:store][:cache] == MyCache
      assert result[:refresh][:retries] == 3
      assert result[:refresh][:on] == :stale_access
    end

    test "normalizes top-level cache, key, ttl into store" do
      base = [store: [cache: OldCache]]
      override = [cache: NewCache, key: :new_key, ttl: 5000]

      result = Presets.merge(base, override)

      assert result[:store][:cache] == NewCache
      assert result[:store][:key] == :new_key
      assert result[:store][:ttl] == 5000
    end

    test "normalizes boolean prevent_thunder_herd" do
      result = Presets.merge([], prevent_thunder_herd: true)

      assert is_list(result[:prevent_thunder_herd])
      assert result[:prevent_thunder_herd][:max_wait] == :timer.seconds(5)
    end

    test "normalizes timeout prevent_thunder_herd" do
      result = Presets.merge([], prevent_thunder_herd: :timer.seconds(10))

      assert result[:prevent_thunder_herd][:max_wait] == :timer.seconds(10)
      assert result[:prevent_thunder_herd][:retries] == 3
    end
  end

  describe "compose/1" do
    test "composes multiple presets" do
      presets = [
        [store: [ttl: 1000]],
        [store: [cache: MyCache]],
        [refresh: [on: :stale_access]]
      ]

      result = Presets.compose(presets)

      assert result[:store][:ttl] == 1000
      assert result[:store][:cache] == MyCache
      assert result[:refresh][:on] == :stale_access
    end

    test "later presets override earlier ones" do
      presets = [
        [store: [ttl: 1000]],
        [store: [ttl: 2000]]
      ]

      result = Presets.compose(presets)

      assert result[:store][:ttl] == 2000
    end

    test "composes preset functions with custom options" do
      presets = [
        Presets.high_availability(),
        [store: [cache: MyCache, key: {User, 1}]]
      ]

      result = Presets.compose(presets)

      assert result[:store][:cache] == MyCache
      assert result[:store][:key] == {User, 1}
      assert result[:store][:ttl] == :timer.minutes(5)
      assert result[:refresh][:retries] == 5
    end
  end
end
