defmodule Events.Infra.KillSwitch.Cache do
  @moduledoc """
  Cache service wrapper with kill switch support for Events.

  Thin wrapper around `OmKillSwitch.Services.Cache` configured to use
  `Events.Core.Cache` as the cache module.

  See `OmKillSwitch.Services.Cache` for full documentation.
  """

  alias Events.Core.Cache

  @cache_opts [cache: Cache]

  # Status functions (no cache needed)
  defdelegate enabled?, to: OmKillSwitch.Services.Cache
  defdelegate check, to: OmKillSwitch.Services.Cache
  defdelegate status, to: OmKillSwitch.Services.Cache
  defdelegate disable(opts \\ []), to: OmKillSwitch.Services.Cache
  defdelegate enable, to: OmKillSwitch.Services.Cache

  # Cache operations with Events.Core.Cache
  def get(key, opts \\ []) do
    OmKillSwitch.Services.Cache.get(key, Keyword.merge(@cache_opts, opts))
  end

  def put(key, value, opts \\ []) do
    OmKillSwitch.Services.Cache.put(key, value, Keyword.merge(@cache_opts, opts))
  end

  def delete(key, opts \\ []) do
    OmKillSwitch.Services.Cache.delete(key, Keyword.merge(@cache_opts, opts))
  end

  def get_all(keys, opts \\ []) when is_list(keys) do
    OmKillSwitch.Services.Cache.get_all(keys, Keyword.merge(@cache_opts, opts))
  end

  def has_key?(key, opts \\ []) do
    OmKillSwitch.Services.Cache.has_key?(key, Keyword.merge(@cache_opts, opts))
  end

  def fetch(key, func, opts \\ []) when is_function(func, 0) do
    OmKillSwitch.Services.Cache.fetch(key, func, Keyword.merge(@cache_opts, opts))
  end

  defdelegate with_cache(func, opts \\ []), to: OmKillSwitch.Services.Cache
end
