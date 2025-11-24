defmodule Events.CRUD.Config do
  @moduledoc """
  Configuration for CRUD operations.
  Optional features are disabled by default.
  """

  # Core settings
  @spec default_pagination_limit() :: pos_integer()
  def default_pagination_limit(), do: get_env(:default_limit, 20)

  @spec max_pagination_limit() :: pos_integer()
  def max_pagination_limit(), do: get_env(:max_limit, 1000)

  @spec query_timeout() :: pos_integer()
  def query_timeout(), do: get_env(:timeout, 30_000)

  # Optional features (disabled by default)
  @spec enable_optimization?() :: boolean()
  def enable_optimization?(), do: get_env(:optimization, true)

  @spec enable_caching?() :: boolean()
  # Disabled
  def enable_caching?(), do: get_env(:caching, false)

  @spec enable_observability?() :: boolean()
  # Disabled
  def enable_observability?(), do: get_env(:observability, false)

  @spec enable_timing?() :: boolean()
  # Disabled
  def enable_timing?(), do: get_env(:timing, false)

  # OpenTelemetry (future)
  @spec enable_opentelemetry?() :: boolean()
  # Disabled
  def enable_opentelemetry?(), do: get_env(:opentelemetry, false)

  # Generic config access
  @spec config(atom()) :: term()
  def config(key), do: get_env(key, nil)

  # Helper
  defp get_env(key, default), do: Application.get_env(:events, :"crud_#{key}", default)
end
