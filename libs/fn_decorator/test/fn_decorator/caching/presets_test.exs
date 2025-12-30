defmodule FnDecorator.Caching.PresetsTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Caching.Presets

  describe "minimal/1" do
    test "returns minimal preset with thunder herd only" do
      opts = Presets.minimal([])

      assert opts[:prevent_thunder_herd] == true
      refute Keyword.has_key?(opts, :store)
      refute Keyword.has_key?(opts, :refresh)
      refute Keyword.has_key?(opts, :serve_stale)
    end

    test "accepts user store options" do
      opts = Presets.minimal(store: [cache: MyCache, key: :test, ttl: :timer.minutes(5)])

      assert opts[:store][:cache] == MyCache
      assert opts[:store][:key] == :test
      assert opts[:store][:ttl] == :timer.minutes(5)
    end
  end

  describe "database/1" do
    test "returns preset with short TTL for frequent changes" do
      opts = Presets.database([])

      assert opts[:store][:ttl] == :timer.seconds(30)
      assert opts[:serve_stale][:ttl] == :timer.minutes(5)
      assert opts[:refresh][:on] == :stale_access
      assert opts[:prevent_thunder_herd][:max_wait] == 2_000
      assert opts[:prevent_thunder_herd][:lock_ttl] == 10_000
    end

    test "merges user options" do
      opts = Presets.database(store: [cache: MyCache, key: {User, 1}])

      assert opts[:store][:cache] == MyCache
      assert opts[:store][:key] == {User, 1}
      assert opts[:store][:ttl] == :timer.seconds(30)
    end
  end

  describe "session/1" do
    test "returns preset without stale serving" do
      opts = Presets.session([])

      assert opts[:store][:ttl] == :timer.minutes(1)
      assert opts[:prevent_thunder_herd][:max_wait] == 1_000
      assert opts[:prevent_thunder_herd][:lock_ttl] == 5_000
      assert opts[:prevent_thunder_herd][:on_timeout] == :error
      refute Keyword.has_key?(opts, :serve_stale)
      refute Keyword.has_key?(opts, :refresh)
    end
  end

  describe "high_availability/1" do
    test "returns preset with stale fallbacks" do
      opts = Presets.high_availability([])

      assert opts[:store][:ttl] == :timer.minutes(1)
      assert opts[:serve_stale][:ttl] == :timer.hours(1)
      assert opts[:refresh][:on] == :stale_access
      assert opts[:prevent_thunder_herd][:max_wait] == 5_000
      assert opts[:prevent_thunder_herd][:on_timeout] == :serve_stale
      assert opts[:fallback][:on_error] == :serve_stale
    end

    test "user options override preset defaults" do
      opts = Presets.high_availability(store: [ttl: :timer.minutes(2)])

      # User TTL overrides preset TTL
      assert opts[:store][:ttl] == :timer.minutes(2)
      # Other preset values remain
      assert opts[:serve_stale][:ttl] == :timer.hours(1)
    end
  end

  describe "always_fresh/1" do
    test "returns preset with very short TTL" do
      opts = Presets.always_fresh([])

      assert opts[:store][:ttl] == :timer.seconds(10)
      assert opts[:prevent_thunder_herd][:max_wait] == 5_000
      assert opts[:prevent_thunder_herd][:on_timeout] == :error
      refute Keyword.has_key?(opts, :serve_stale)
      refute Keyword.has_key?(opts, :refresh)
    end
  end

  describe "external_api/1" do
    test "returns preset with stale serving for resilience" do
      opts = Presets.external_api([])

      assert opts[:store][:ttl] == :timer.minutes(5)
      assert opts[:serve_stale][:ttl] == :timer.hours(1)
      assert opts[:refresh][:on] == :stale_access
      assert opts[:prevent_thunder_herd][:max_wait] == 30_000
      assert opts[:prevent_thunder_herd][:lock_ttl] == 60_000
      assert opts[:prevent_thunder_herd][:on_timeout] == :serve_stale
      assert opts[:fallback][:on_error] == :serve_stale
    end
  end

  describe "expensive/1" do
    test "returns preset with long TTL" do
      opts = Presets.expensive([])

      assert opts[:store][:ttl] == :timer.hours(1)
      assert opts[:serve_stale][:ttl] == :timer.hours(24)
      assert opts[:refresh][:on] == :stale_access
      assert opts[:prevent_thunder_herd][:max_wait] == 60_000
      assert opts[:prevent_thunder_herd][:lock_ttl] == 300_000
      assert opts[:prevent_thunder_herd][:on_timeout] == :serve_stale
      assert opts[:fallback][:on_error] == :serve_stale
    end
  end

  describe "reference_data/1" do
    test "returns preset for static data" do
      opts = Presets.reference_data([])

      assert opts[:store][:ttl] == :timer.hours(1)
      assert opts[:serve_stale][:ttl] == :timer.hours(24)
      assert opts[:refresh][:on] == :stale_access
      assert opts[:prevent_thunder_herd] == true
    end

    test "merges user options" do
      opts = Presets.reference_data(store: [cache: MyCache, key: :countries])

      assert opts[:store][:cache] == MyCache
      assert opts[:store][:key] == :countries
      assert opts[:store][:ttl] == :timer.hours(1)
    end
  end

  describe "merge/2" do
    test "deep merges nested keyword lists" do
      base = [store: [ttl: 1000, cache: MyCache], refresh: [on: :stale_access]]
      override = [store: [ttl: 2000]]

      result = Presets.merge(base, override)

      assert result[:store][:ttl] == 2000
      assert result[:store][:cache] == MyCache
      assert result[:refresh][:on] == :stale_access
    end

    test "override completely replaces non-keyword values" do
      base = [prevent_thunder_herd: true]
      override = [prevent_thunder_herd: [max_wait: 10_000]]

      result = Presets.merge(base, override)

      assert result[:prevent_thunder_herd][:max_wait] == 10_000
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
        Presets.high_availability([]),
        [store: [cache: MyCache, key: {User, 1}]]
      ]

      result = Presets.compose(presets)

      assert result[:store][:cache] == MyCache
      assert result[:store][:key] == {User, 1}
      assert result[:store][:ttl] == :timer.minutes(1)
      assert result[:serve_stale][:ttl] == :timer.hours(1)
    end
  end
end
