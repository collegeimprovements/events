# Configure test caches with local adapter
Application.put_env(:om_cache, OmCache.TestCache,
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  stats: true
)

Application.put_env(:om_cache, OmCache.TestL1Cache,
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  stats: true
)

Application.put_env(:om_cache, OmCache.TestL2Cache,
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  stats: true
)

# Start test caches
{:ok, _} = OmCache.TestCache.start_link()
{:ok, _} = OmCache.TestL1Cache.start_link()
{:ok, _} = OmCache.TestL2Cache.start_link()

ExUnit.start()
