defmodule FnDecorator.Caching.Presets do
  @moduledoc """
  Built-in cache presets for common use cases.

  Presets are just keyword lists - compose them freely with your own options.

  ## Usage

      alias FnDecorator.Caching.Presets

      @decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
      def get_user(id), do: Repo.get(User, id)

  ## Creating Custom Presets

  Presets are plain keyword lists. Create your own:

      defmodule MyApp.CachePresets do
        alias FnDecorator.Caching.Presets

        def api_client(opts) do
          Presets.merge([
            store: [ttl: :timer.minutes(15)],
            serve_stale: [ttl: :timer.hours(4)],
            prevent_thunder_herd: [max_wait: :timer.seconds(30)]
          ], opts)
        end
      end

  See `merge/2` for composing presets.
  """

  # ============================================
  # Built-in Presets
  # ============================================

  @doc """
  High availability - prioritizes returning data over freshness.

  - Serves stale data for 24 hours while refreshing
  - Refreshes on stale access and immediately when expired
  - 5 retry attempts
  - Patient thunder herd protection (10s wait)

  Best for: User-facing reads where some staleness is acceptable.

  ## Options

  All standard `@cacheable` options, plus:
  - `:cache` - Required. Cache module
  - `:key` - Required. Cache key
  - `:ttl` - Override default 5 minute TTL

  ## Examples

      @decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
      def get_user(id), do: Repo.get(User, id)

      # With custom TTL
      @decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}, ttl: :timer.minutes(10)))
      def get_user(id), do: Repo.get(User, id)
  """
  @spec high_availability(keyword()) :: keyword()
  def high_availability(opts \\ []) do
    merge(
      [
        store: [ttl: :timer.minutes(5)],
        refresh: [on: [:stale_access, :immediately_when_expired], retries: 5],
        serve_stale: [ttl: :timer.hours(24)],
        prevent_thunder_herd: [max_wait: :timer.seconds(10)]
      ],
      opts
    )
  end

  @doc """
  Always fresh - critical data that must be current.

  - Short TTL (30 seconds)
  - Proactive refresh on expiry
  - 10 retry attempts
  - No stale serving

  Best for: Feature flags, permissions, critical config.

  ## Examples

      @decorate cacheable(Presets.always_fresh(cache: MyApp.Cache, key: :feature_flags))
      def get_flags, do: ConfigService.fetch()
  """
  @spec always_fresh(keyword()) :: keyword()
  def always_fresh(opts \\ []) do
    merge(
      [
        store: [ttl: :timer.seconds(30)],
        refresh: [on: :immediately_when_expired, retries: 10],
        prevent_thunder_herd: [max_wait: :timer.seconds(15)]
      ],
      opts
    )
  end

  @doc """
  External API - resilient caching for third-party APIs.

  - 15 minute TTL
  - Cron-based refresh every 15 minutes
  - Serves stale for 4 hours (survives API outages)
  - Long lock timeout for slow APIs

  Best for: Weather APIs, external services, rate-limited endpoints.

  ## Examples

      @decorate cacheable(Presets.external_api(cache: MyApp.Cache, key: {:weather, city}))
      def get_weather(city), do: WeatherAPI.fetch(city)
  """
  @spec external_api(keyword()) :: keyword()
  def external_api(opts \\ []) do
    merge(
      [
        store: [ttl: :timer.minutes(15)],
        refresh: [on: {:cron, "*/15 * * * *"}, retries: 3],
        serve_stale: [ttl: :timer.hours(4)],
        prevent_thunder_herd: [max_wait: :timer.seconds(30), lock_timeout: :timer.minutes(2)]
      ],
      opts
    )
  end

  @doc """
  Expensive computation - long-lived cache for costly operations.

  - 6 hour TTL
  - Cron-based refresh
  - Serves stale for 7 days
  - Very patient lock (handles long computations)

  Best for: Reports, aggregations, ML model results.

  ## Examples

      @decorate cacheable(Presets.expensive(cache: MyApp.Cache, key: {:report, date}))
      def generate_report(date), do: Reports.compute(date)
  """
  @spec expensive(keyword()) :: keyword()
  def expensive(opts \\ []) do
    merge(
      [
        store: [ttl: :timer.hours(6)],
        refresh: [on: {:cron, "0 */6 * * *"}, retries: 3],
        serve_stale: [ttl: :timer.hours(24 * 7)],
        prevent_thunder_herd: [max_wait: :timer.minutes(2), lock_timeout: :timer.minutes(10)]
      ],
      opts
    )
  end

  @doc """
  Session data - short-lived user session caching.

  - 30 minute TTL
  - No stale serving (sessions should be current)
  - Quick thunder herd protection

  Best for: Session data, user preferences, shopping carts.

  ## Examples

      @decorate cacheable(Presets.session(cache: MyApp.Cache, key: {:session, session_id}))
      def get_session(session_id), do: Sessions.fetch(session_id)
  """
  @spec session(keyword()) :: keyword()
  def session(opts \\ []) do
    merge(
      [
        store: [ttl: :timer.minutes(30)],
        prevent_thunder_herd: [max_wait: :timer.seconds(2)]
      ],
      opts
    )
  end

  @doc """
  Read-through database - standard DB query caching.

  - 5 minute TTL
  - Refresh on stale access
  - 1 hour stale window
  - Standard thunder herd protection

  Best for: Database reads, entity lookups.

  ## Examples

      @decorate cacheable(Presets.database(cache: MyApp.Cache, key: {User, id}))
      def get_user(id), do: Repo.get(User, id)
  """
  @spec database(keyword()) :: keyword()
  def database(opts \\ []) do
    merge(
      [
        store: [ttl: :timer.minutes(5)],
        refresh: [on: :stale_access],
        serve_stale: [ttl: :timer.hours(1)],
        prevent_thunder_herd: true
      ],
      opts
    )
  end

  @doc """
  Minimal - just caching with defaults, no bells and whistles.

  - TTL only (you specify)
  - Thunder herd protection ON
  - No stale serving, no refresh

  Best for: Simple caching needs.

  ## Examples

      @decorate cacheable(Presets.minimal(cache: MyApp.Cache, key: {Item, id}, ttl: :timer.minutes(10)))
      def get_item(id), do: Repo.get(Item, id)
  """
  @spec minimal(keyword()) :: keyword()
  def minimal(opts \\ []) do
    merge([prevent_thunder_herd: true], opts)
  end

  # ============================================
  # Composition Helpers
  # ============================================

  @doc """
  Deep merges two option lists. Right side wins on conflicts.

  Handles nested keyword lists (like `store`, `refresh`, etc.) by merging
  them recursively rather than replacing.

  ## Examples

      Presets.merge(Presets.high_availability(), [store: [ttl: :timer.minutes(10)]])
      # => [..., store: [ttl: 600000, ...], ...]

      # Override specific nested values
      Presets.merge(
        Presets.database(),
        [store: [cache: MyApp.Cache, key: {User, id}]]
      )
  """
  @spec merge(keyword(), keyword()) :: keyword()
  def merge(base, override) do
    deep_merge(base, normalize_opts(override))
  end

  @doc """
  Composes multiple presets. Later presets override earlier ones.

  ## Examples

      Presets.compose([
        Presets.high_availability(),
        [store: [cache: MyApp.Cache, key: {User, id}]]
      ])

      # Multiple presets
      Presets.compose([
        Presets.database(),
        [refresh: [retries: 10]],
        [store: [cache: MyApp.Cache, key: {User, id}]]
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

  # Normalize shorthand options to full structure
  defp normalize_opts(opts) do
    opts
    |> normalize_store_opts()
    |> normalize_thunder_herd_opts()
  end

  # Allow top-level cache, key, ttl to be moved into store
  defp normalize_store_opts(opts) do
    {cache, opts} = Keyword.pop(opts, :cache)
    {key, opts} = Keyword.pop(opts, :key)
    {ttl, opts} = Keyword.pop(opts, :ttl)

    store_additions =
      [cache: cache, key: key, ttl: ttl]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    if store_additions == [] do
      opts
    else
      existing_store = Keyword.get(opts, :store, [])
      merged_store = Keyword.merge(existing_store, store_additions)
      Keyword.put(opts, :store, merged_store)
    end
  end

  # Allow boolean or timeout shorthand for prevent_thunder_herd
  defp normalize_thunder_herd_opts(opts) do
    case Keyword.get(opts, :prevent_thunder_herd) do
      true ->
        Keyword.put(opts, :prevent_thunder_herd, default_thunder_herd_opts())

      false ->
        opts

      timeout when is_integer(timeout) ->
        Keyword.put(opts, :prevent_thunder_herd, Keyword.put(default_thunder_herd_opts(), :max_wait, timeout))

      _ ->
        opts
    end
  end

  defp default_thunder_herd_opts do
    [
      max_wait: :timer.seconds(5),
      retries: 3,
      lock_timeout: :timer.seconds(30),
      on_timeout: :serve_stale
    ]
  end
end
