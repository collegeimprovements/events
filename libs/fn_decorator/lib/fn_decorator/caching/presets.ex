defmodule FnDecorator.Caching.Presets do
  @moduledoc """
  Built-in cache configuration presets for common use cases.

  Presets provide sensible defaults for typical caching scenarios. Each preset
  returns a keyword list that can be merged with your specific options.

  ## Usage

      alias FnDecorator.Caching.Presets

      @decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
      def get_user(id), do: Repo.get(User, id)

  ## Custom Presets

  Create your own presets by composing existing ones:

      defmodule MyApp.CachePresets do
        alias FnDecorator.Caching.Presets

        def api_client(opts) do
          Presets.merge(
            Presets.external_api([]),
            opts
          )
        end
      end

  ## Available Presets

  | Preset | Fresh | Stale | max_wait | on_timeout | Use Case |
  |--------|-------|-------|----------|------------|----------|
  | `minimal/1` | - | - | default | - | Full control |
  | `database/1` | 30s | 5m | 2s | stale | CRUD reads |
  | `session/1` | 1m | - | 1s | error | Auth/session |
  | `high_availability/1` | 1m | 1h | 5s | stale | User-facing |
  | `always_fresh/1` | 10s | - | 5s | error | Feature flags |
  | `external_api/1` | 5m | 1h | 30s | stale | Third-party APIs |
  | `expensive/1` | 1h | 24h | 60s | stale | Reports |
  | `reference_data/1` | 1h | 24h | default | - | Static data |
  """

  # ============================================
  # Core Presets
  # ============================================

  @doc """
  Minimal preset - just thunder herd protection.

  No TTL, no stale serving, no refresh. You must provide all store options.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ..., ttl: ...]`

  ## Examples

      @decorate cacheable(Presets.minimal(store: [cache: MyCache, key: {Item, id}, ttl: :timer.minutes(10)]))
      def get_item(id), do: Repo.get(Item, id)
  """
  @spec minimal(keyword()) :: keyword()
  def minimal(opts) do
    merge([prevent_thunder_herd: true], opts)
  end

  @doc """
  Database preset - standard DB query caching.

  - 30 second fresh TTL (data changes frequently)
  - 5 minute stale window (brief buffer for spikes)
  - Refresh on stale access
  - Quick thunder herd protection (2s wait)

  Best for: Database reads, entity lookups, CRUD operations.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
      def get_user(id), do: Repo.get(User, id)
  """
  @spec database(keyword()) :: keyword()
  def database(opts) do
    merge(
      [
        store: [ttl: :timer.seconds(30)],
        serve_stale: [ttl: :timer.minutes(5)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: [max_wait: 2_000, lock_ttl: 10_000]
      ],
      opts
    )
  end

  @doc """
  Session preset - user session and auth data caching.

  - 1 minute TTL (sessions need to reflect current auth state)
  - No stale serving (auth data must be current)
  - Very quick thunder herd protection (1s wait, error on timeout)

  Best for: Session data, auth tokens, user permissions, shopping carts.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.session(store: [cache: MyCache, key: {:session, session_id}]))
      def get_session(session_id), do: Sessions.fetch(session_id)
  """
  @spec session(keyword()) :: keyword()
  def session(opts) do
    merge(
      [
        store: [ttl: :timer.minutes(1)],
        prevent_thunder_herd: [max_wait: 1_000, lock_ttl: 5_000, on_timeout: :error]
      ],
      opts
    )
  end

  @doc """
  High availability preset - prioritizes returning data over freshness.

  - 1 minute fresh TTL
  - 1 hour stale window (survive brief outages)
  - Refresh on stale access
  - Patient thunder herd protection (5s wait, serve stale on timeout)
  - Falls back to stale data on errors

  Best for: User-facing reads where some staleness is acceptable.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.high_availability(store: [cache: MyCache, key: {User, id}]))
      def get_user(id), do: Repo.get(User, id)
  """
  @spec high_availability(keyword()) :: keyword()
  def high_availability(opts) do
    merge(
      [
        store: [ttl: :timer.minutes(1)],
        serve_stale: [ttl: :timer.hours(1)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: [max_wait: 5_000, lock_ttl: 15_000, on_timeout: :serve_stale],
        fallback: [on_error: :serve_stale]
      ],
      opts
    )
  end

  @doc """
  Always fresh preset - critical data with minimal caching.

  - 10 second TTL (very short, just for thunder herd protection)
  - No stale serving (stale config = bugs)
  - Error on timeout (don't serve old data)

  Best for: Feature flags, permissions, critical configuration.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.always_fresh(store: [cache: MyCache, key: :feature_flags]))
      def get_flags, do: ConfigService.fetch()
  """
  @spec always_fresh(keyword()) :: keyword()
  def always_fresh(opts) do
    merge(
      [
        store: [ttl: :timer.seconds(10)],
        prevent_thunder_herd: [max_wait: 5_000, lock_ttl: 15_000, on_timeout: :error]
      ],
      opts
    )
  end

  @doc """
  External API preset - resilient caching for third-party APIs.

  - 5 minute TTL (respect rate limits)
  - 1 hour stale window (survive API outages)
  - Refresh on stale access
  - Long wait for slow APIs (30s)
  - Falls back to stale data on errors

  Best for: Weather APIs, payment gateways, rate-limited endpoints.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.external_api(store: [cache: MyCache, key: {:weather, city}]))
      def get_weather(city), do: WeatherAPI.fetch(city)
  """
  @spec external_api(keyword()) :: keyword()
  def external_api(opts) do
    merge(
      [
        store: [ttl: :timer.minutes(5)],
        serve_stale: [ttl: :timer.hours(1)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: [max_wait: 30_000, lock_ttl: 60_000, on_timeout: :serve_stale],
        fallback: [on_error: :serve_stale]
      ],
      opts
    )
  end

  @doc """
  Expensive computation preset - long-lived cache for costly operations.

  - 1 hour TTL
  - 24 hour stale window
  - Refresh on stale access
  - Very patient lock (60s wait, handles long computations)
  - Falls back to stale data on errors

  Best for: Reports, aggregations, ML model results, analytics.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.expensive(store: [cache: MyCache, key: {:report, date}]))
      def generate_report(date), do: Reports.compute(date)
  """
  @spec expensive(keyword()) :: keyword()
  def expensive(opts) do
    merge(
      [
        store: [ttl: :timer.hours(1)],
        serve_stale: [ttl: :timer.hours(24)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: [max_wait: 60_000, lock_ttl: 300_000, on_timeout: :serve_stale],
        fallback: [on_error: :serve_stale]
      ],
      opts
    )
  end

  @doc """
  Reference data preset - static or slow-changing data.

  - 1 hour TTL
  - 24 hour stale window
  - Refresh on stale access
  - Standard thunder herd protection

  Best for: Countries, currencies, timezones, app config, lookup tables.

  ## Options

  Required:
  - `store: [cache: MyCache, key: ...]`

  ## Examples

      @decorate cacheable(Presets.reference_data(store: [cache: MyCache, key: :countries]))
      def list_countries, do: Repo.all(Country)

      @decorate cacheable(Presets.reference_data(store: [cache: MyCache, key: {:currency, code}]))
      def get_currency(code), do: Repo.get_by(Currency, code: code)
  """
  @spec reference_data(keyword()) :: keyword()
  def reference_data(opts) do
    merge(
      [
        store: [ttl: :timer.hours(1)],
        serve_stale: [ttl: :timer.hours(24)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: true
      ],
      opts
    )
  end

  # ============================================
  # Composition Helpers
  # ============================================

  @doc """
  Deep merges two option lists. Right side wins on conflicts.

  Handles nested keyword lists (like `store`, `refresh`, etc.) by merging
  them recursively rather than replacing.

  ## Examples

      Presets.merge(Presets.database([]), [store: [ttl: :timer.minutes(1)]])
      # => [store: [ttl: 60000, ...], serve_stale: [...], ...]
  """
  @spec merge(keyword(), keyword()) :: keyword()
  def merge(base, override) do
    deep_merge(base, override)
  end

  @doc """
  Composes multiple option lists. Later lists override earlier ones.

  ## Examples

      Presets.compose([
        Presets.database([]),
        [store: [cache: MyCache, key: {User, id}]],
        [store: [ttl: :timer.minutes(1)]]
      ])
  """
  @spec compose([keyword()]) :: keyword()
  def compose(presets) when is_list(presets) do
    Enum.reduce(presets, [], &deep_merge(&2, &1))
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp deep_merge(left, right) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      Keyword.merge(left, right, fn
        _key, left_val, right_val when is_list(left_val) and is_list(right_val) ->
          deep_merge(left_val, right_val)

        _key, _left_val, right_val ->
          right_val
      end)
    else
      right
    end
  end

  defp deep_merge(_left, right), do: right
end
