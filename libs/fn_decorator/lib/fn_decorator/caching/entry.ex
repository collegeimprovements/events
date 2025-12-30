defmodule FnDecorator.Caching.Entry do
  @moduledoc """
  Cache entry with metadata for freshness tracking.

  Every cached value is wrapped in an Entry that tracks:
  - When it was cached
  - When it becomes stale (fresh TTL expired)
  - When it expires completely (stale TTL expired)

  ## Entry States

  ```
  ┌─────────────────┬────────────────────┬─────────────────┐
  │     FRESH       │       STALE        │    EXPIRED      │
  │  (return now)   │ (return + refresh) │  (cache miss)   │
  └─────────────────┴────────────────────┴─────────────────┘
  0            fresh_until           stale_until          ∞
  ```

  - **Fresh**: Value is within TTL, return immediately
  - **Stale**: TTL expired but within stale_ttl, return and optionally refresh
  - **Expired**: Beyond stale_ttl, treat as cache miss

  ## Storage Format

  Entries are stored as tagged tuples for efficiency and unambiguous parsing:

      {:fn_cache, version, value, cached_at, fresh_until, stale_until}

  This format:
  - Is easily distinguishable from user data
  - Supports versioning for future changes
  - Is compact and fast to pattern match
  """

  @type t :: %__MODULE__{
          value: term(),
          cached_at: integer(),
          fresh_until: integer(),
          stale_until: integer() | nil
        }

  @type status :: :fresh | :stale | :expired

  @enforce_keys [:value, :cached_at, :fresh_until]
  defstruct [:value, :cached_at, :fresh_until, :stale_until]

  @tag :fn_cache
  @version 1

  # ============================================
  # Construction
  # ============================================

  @doc """
  Create a new cache entry.

  ## Parameters

  - `value` - The value to cache
  - `ttl` - Time-to-live in milliseconds (fresh period)
  - `stale_ttl` - Extended TTL for stale serving (must be > ttl), or nil

  ## Examples

      iex> entry = Entry.new("hello", 5_000)
      iex> entry.value
      "hello"

      iex> entry = Entry.new("hello", 5_000, 60_000)
      iex> entry.stale_until > entry.fresh_until
      true
  """
  @spec new(term(), pos_integer(), pos_integer() | nil) :: t()
  def new(value, ttl, stale_ttl \\ nil)
      when is_integer(ttl) and ttl > 0 and
             (is_nil(stale_ttl) or (is_integer(stale_ttl) and stale_ttl > ttl)) do
    now = monotonic_now()

    %__MODULE__{
      value: value,
      cached_at: now,
      fresh_until: now + ttl,
      stale_until: if(stale_ttl, do: now + stale_ttl, else: nil)
    }
  end

  # ============================================
  # Serialization
  # ============================================

  @doc """
  Convert entry to storable tuple format.

  The tuple format is compact and unambiguous:

      {:fn_cache, 1, value, cached_at, fresh_until, stale_until}
  """
  @spec to_tuple(t()) :: tuple()
  def to_tuple(%__MODULE__{} = entry) do
    {@tag, @version, entry.value, entry.cached_at, entry.fresh_until, entry.stale_until}
  end

  @doc """
  Parse a value from cache into an Entry.

  Returns `nil` for cache miss, Entry for valid cached data.

  ## Examples

      iex> Entry.from_cache(nil)
      nil

      iex> entry = Entry.new("test", 5000)
      iex> Entry.from_cache(Entry.to_tuple(entry))
      entry
  """
  @spec from_cache(term()) :: t() | nil
  def from_cache(nil), do: nil

  def from_cache({@tag, @version, value, cached_at, fresh_until, stale_until}) do
    %__MODULE__{
      value: value,
      cached_at: cached_at,
      fresh_until: fresh_until,
      stale_until: stale_until
    }
  end

  # Unknown format - treat as cache miss (data corruption or version mismatch)
  def from_cache(_other), do: nil

  # ============================================
  # Status Checks
  # ============================================

  @doc """
  Get the current status of an entry.

  Returns `:fresh`, `:stale`, or `:expired`.
  """
  @spec status(t()) :: status()
  def status(%__MODULE__{} = entry) do
    now = monotonic_now()

    cond do
      now < entry.fresh_until -> :fresh
      entry.stale_until != nil and now < entry.stale_until -> :stale
      true -> :expired
    end
  end

  @doc """
  Check if entry is fresh (within TTL).
  """
  @spec fresh?(t()) :: boolean()
  def fresh?(%__MODULE__{} = entry) do
    monotonic_now() < entry.fresh_until
  end

  @doc """
  Check if entry is stale but still servable.
  """
  @spec stale?(t()) :: boolean()
  def stale?(%__MODULE__{stale_until: nil}), do: false

  def stale?(%__MODULE__{} = entry) do
    now = monotonic_now()
    now >= entry.fresh_until and now < entry.stale_until
  end

  @doc """
  Check if entry is completely expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{stale_until: nil} = entry) do
    monotonic_now() >= entry.fresh_until
  end

  def expired?(%__MODULE__{stale_until: stale_until}) do
    monotonic_now() >= stale_until
  end

  # ============================================
  # Value Access
  # ============================================

  @doc """
  Extract the cached value.
  """
  @spec value(t()) :: term()
  def value(%__MODULE__{value: value}), do: value

  @doc """
  Get milliseconds remaining until entry becomes stale.

  Returns 0 if already stale or expired.
  """
  @spec ttl_remaining(t()) :: non_neg_integer()
  def ttl_remaining(%__MODULE__{fresh_until: fresh_until}) do
    max(0, fresh_until - monotonic_now())
  end

  @doc """
  Get milliseconds remaining until entry expires completely.

  Returns 0 if already expired.
  """
  @spec time_to_expiry(t()) :: non_neg_integer()
  def time_to_expiry(%__MODULE__{stale_until: nil, fresh_until: fresh_until}) do
    max(0, fresh_until - monotonic_now())
  end

  def time_to_expiry(%__MODULE__{stale_until: stale_until}) do
    max(0, stale_until - monotonic_now())
  end

  @doc """
  Get the age of the entry in milliseconds.
  """
  @spec age(t()) :: non_neg_integer()
  def age(%__MODULE__{cached_at: cached_at}) do
    monotonic_now() - cached_at
  end

  # ============================================
  # Private
  # ============================================

  defp monotonic_now do
    System.monotonic_time(:millisecond)
  end
end
