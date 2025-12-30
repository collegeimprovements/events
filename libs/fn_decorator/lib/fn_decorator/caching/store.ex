defmodule FnDecorator.Caching.Store do
  @moduledoc """
  Behaviour for cache store implementations.

  Provides an Ecto-inspired interface for cache operations. Explicit,
  composable, and predictable.

  ## Patterns

  Bulk operations accept patterns as the first argument (like Ecto queryables):

      :all              # Match all entries
      {User, :_}        # Match {User, 1}, {User, 2}, etc.
      {:_, :profile}    # Match {User, :profile}, {Admin, :profile}
      {User, :_, :meta} # Match {User, 1, :meta}, {User, 2, :meta}

  ## Examples

      # Single operations
      Cache.get({User, 123})
      Cache.put({User, 123}, user, ttl: :timer.minutes(5))
      Cache.delete({User, 123})

      # Bulk by pattern
      Cache.all({User, :_})             # Get all User entries
      Cache.keys({User, :_})            # Get all User keys
      Cache.delete_all({User, :_})      # Delete all Users
      Cache.count({User, :_})           # Count Users

      # Bulk by explicit keys
      Cache.get_all([{User, 1}, {User, 2}])
      Cache.delete_all([{User, 1}, {User, 2}])

      # Everything
      Cache.all(:all)                   # All entries
      Cache.count(:all)                 # Total count
      Cache.clear()                     # Delete everything

  ## Implementing a Store

      defmodule MyApp.Cache do
        @behaviour FnDecorator.Caching.Store

        # Required
        def get(key), do: ...
        def put(key, value, opts), do: ...
        def delete(key), do: ...

        # Optional - implement for better performance
        def all(pattern), do: ...
        def delete_all(pattern), do: ...
      end
  """

  @type key :: term()
  @type value :: term()
  @type entry :: {key(), value()}
  @type pattern :: :all | tuple() | [key()]
  @type tag :: atom() | String.t()
  @type opts :: keyword()
  @type count :: non_neg_integer()

  # ============================================
  # Required Callbacks (3)
  # ============================================

  @doc """
  Retrieve a cached value.

  Returns `nil` if the key doesn't exist or has expired.

  ## Examples

      Cache.get({User, 123})
      # => %User{id: 123, name: "Alice"}

      Cache.get({User, 999})
      # => nil
  """
  @callback get(key()) :: value() | nil

  @doc """
  Store a value in the cache.

  ## Options

    * `:ttl` - Time-to-live in milliseconds
    * `:tags` - List of tags to associate with this entry

  ## Examples

      Cache.put({User, 123}, user, ttl: :timer.minutes(5))
      # => :ok

      Cache.put({User, 123}, user, ttl: :timer.minutes(5), tags: [:users, "org:acme"])
      # => :ok
  """
  @callback put(key(), value(), opts()) :: :ok

  @doc """
  Delete a cached value.

  Returns `:ok` regardless of whether the key existed.

  ## Examples

      Cache.delete({User, 123})
      # => :ok
  """
  @callback delete(key()) :: :ok

  # ============================================
  # Optional Callbacks - Single Key
  # ============================================

  @doc """
  Retrieve a cached value, raising if not found.

  ## Examples

      Cache.get!({User, 123})
      # => %User{id: 123}

      Cache.get!({User, 999})
      # ** (KeyError) key not found: {User, 999}
  """
  @callback get!(key()) :: value()

  @doc """
  Check if a key exists in the cache.

  ## Examples

      Cache.exists?({User, 123})
      # => true
  """
  @callback exists?(key()) :: boolean()

  @doc """
  Update the TTL of an existing entry without changing its value.

  ## Examples

      Cache.touch({User, 123}, ttl: :timer.hours(1))
      # => :ok

      Cache.touch({User, 999}, ttl: :timer.hours(1))
      # => {:error, :not_found}
  """
  @callback touch(key(), opts()) :: :ok | {:error, :not_found}

  # ============================================
  # Optional Callbacks - Bulk by Pattern
  # ============================================

  @doc """
  Get all entries matching a pattern.

  Like `Repo.all/1` - returns a list of `{key, value}` tuples.

  ## Examples

      Cache.all(:all)
      # => [{{User, 1}, %User{}}, {{User, 2}, %User{}}, ...]

      Cache.all({User, :_})
      # => [{{User, 1}, %User{}}, {{User, 2}, %User{}}, ...]
  """
  @callback all(pattern()) :: [entry()]

  @doc """
  Get all keys matching a pattern.

  ## Examples

      Cache.keys(:all)
      # => [{User, 1}, {User, 2}, {:session, "abc"}, ...]

      Cache.keys({User, :_})
      # => [{User, 1}, {User, 2}, {User, 3}]
  """
  @callback keys(pattern()) :: [key()]

  @doc """
  Get all values matching a pattern.

  ## Examples

      Cache.values({User, :_})
      # => [%User{id: 1}, %User{id: 2}, ...]
  """
  @callback values(pattern()) :: [value()]

  @doc """
  Count entries matching a pattern.

  ## Examples

      Cache.count(:all)
      # => 1234

      Cache.count({User, :_})
      # => 42
  """
  @callback count(pattern()) :: count()

  @doc """
  Delete all entries matching a pattern.

  Like `Repo.delete_all/1` - returns the count of deleted entries.

  ## Examples

      Cache.delete_all({User, :_})
      # => {:ok, 42}

      Cache.delete_all(:all)
      # => {:ok, 1234}
  """
  @callback delete_all(pattern()) :: {:ok, count()}

  # ============================================
  # Optional Callbacks - Bulk by Keys
  # ============================================

  @doc """
  Get multiple values by explicit keys.

  Returns a map of found entries. Missing keys are omitted.

  ## Examples

      Cache.get_all([{User, 1}, {User, 2}, {User, 999}])
      # => %{{User, 1} => %User{}, {User, 2} => %User{}}
  """
  @callback get_all([key()]) :: %{key() => value()}

  @doc """
  Store multiple entries at once.

  ## Examples

      Cache.put_all([
        {{User, 1}, user1},
        {{User, 2}, user2}
      ], ttl: :timer.minutes(5))
      # => :ok
  """
  @callback put_all([entry()], opts()) :: :ok

  # ============================================
  # Optional Callbacks - Maintenance
  # ============================================

  @doc """
  Delete all entries from the cache.

  ## Examples

      Cache.clear()
      # => :ok
  """
  @callback clear() :: :ok

  @doc """
  Stream entries matching a pattern.

  Memory-efficient iteration for large datasets.

  ## Examples

      Cache.stream({User, :_})
      |> Stream.filter(fn {_k, v} -> v.active end)
      |> Enum.take(10)
  """
  @callback stream(pattern()) :: Enumerable.t()

  # ============================================
  # Optional Callbacks - Health & Stats
  # ============================================

  @doc """
  Check if the cache backend is reachable.

  Returns `:pong` if healthy, `{:error, reason}` otherwise.

  ## Examples

      Cache.ping()
      # => :pong

      Cache.ping()
      # => {:error, :connection_refused}
  """
  @callback ping() :: :pong | {:error, term()}

  @doc """
  Check if the cache is healthy (convenience wrapper).

  ## Examples

      Cache.healthy?()
      # => true
  """
  @callback healthy?() :: boolean()

  @doc """
  Get cache statistics.

  Returns a map with stats like hit/miss counts, memory usage, etc.

  ## Examples

      Cache.stats()
      # => %{
      #   hits: 1234,
      #   misses: 56,
      #   hit_rate: 0.956,
      #   keys: 42,
      #   memory_bytes: 102400,
      #   uptime_ms: 3600000
      # }
  """
  @callback stats() :: %{
              hits: non_neg_integer(),
              misses: non_neg_integer(),
              hit_rate: float(),
              keys: non_neg_integer(),
              memory_bytes: non_neg_integer() | nil,
              uptime_ms: non_neg_integer() | nil
            }

  @doc """
  Get detailed information about a cached key.

  Returns metadata including TTL, status, age, etc.

  ## Examples

      Cache.info({User, 123})
      # => %{
      #   status: :fresh,
      #   value: %User{},
      #   cached_at: ~U[2024-01-15 10:00:00Z],
      #   fresh_until: ~U[2024-01-15 10:05:00Z],
      #   stale_until: ~U[2024-01-15 11:00:00Z],
      #   ttl_remaining_ms: 180000,
      #   expires_in_ms: 3300000,
      #   age_ms: 120000
      # }

      Cache.info({User, 999})
      # => nil
  """
  @callback info(key()) :: %{
              status: :fresh | :stale | :expired,
              value: term(),
              cached_at: DateTime.t() | integer(),
              fresh_until: DateTime.t() | integer(),
              stale_until: DateTime.t() | integer() | nil,
              ttl_remaining_ms: non_neg_integer(),
              expires_in_ms: non_neg_integer(),
              age_ms: non_neg_integer()
            } | nil

  # ============================================
  # Optional Callbacks - Conditional Operations
  # ============================================

  @doc """
  Store a value only if the key doesn't exist.

  Returns `{:ok, :stored}` if stored, `{:ok, :exists}` if key already exists.

  ## Examples

      Cache.put_new({User, 123}, user, ttl: 5000)
      # => {:ok, :stored}

      Cache.put_new({User, 123}, other_user, ttl: 5000)
      # => {:ok, :exists}
  """
  @callback put_new(key(), value(), opts()) :: {:ok, :stored | :exists}

  # ============================================
  # Optional Callbacks - Tags
  # ============================================

  @doc """
  Get all tags associated with a key.

  ## Examples

      Cache.tags({User, 123})
      # => [:users, "org:acme"]

      Cache.tags({User, 999})
      # => []
  """
  @callback tags(key()) :: [tag()]

  @doc """
  Get all keys associated with a tag.

  ## Examples

      Cache.keys_by_tag(:users)
      # => [{User, 1}, {User, 2}, {User, 3}]

      Cache.keys_by_tag("org:acme")
      # => [{User, 1}, {:settings, "acme"}]
  """
  @callback keys_by_tag(tag()) :: [key()]

  @doc """
  Count entries with a specific tag.

  ## Examples

      Cache.count_by_tag(:users)
      # => 42
  """
  @callback count_by_tag(tag()) :: count()

  @doc """
  Invalidate all entries with a specific tag.

  Returns the count of invalidated entries.

  ## Examples

      Cache.invalidate_tag(:users)
      # => {:ok, 42}

      Cache.invalidate_tag("org:acme")
      # => {:ok, 5}
  """
  @callback invalidate_tag(tag()) :: {:ok, count()}

  @doc """
  Invalidate all entries matching any of the given tags.

  ## Examples

      Cache.invalidate_tags([:premium_users, :trial_users])
      # => {:ok, 156}
  """
  @callback invalidate_tags([tag()]) :: {:ok, count()}

  # ============================================
  # Optional Callbacks - Warming
  # ============================================

  @doc """
  Pre-populate the cache with entries.

  Accepts:
  - A list of `{key, value}` tuples
  - A list of `{key, value, opts}` tuples (per-entry options)
  - A 0-arity function returning entries
  - A module implementing `FnDecorator.Caching.Warmable`

  ## Options

    * `:ttl` - Default TTL for all entries (can be overridden per-entry)
    * `:batch_size` - Number of entries to insert at once (default: 100)
    * `:on_progress` - Callback `fn done, total -> ... end`

  ## Examples

      # List of entries
      Cache.warm([
        {{:user, 1}, user1},
        {{:user, 2}, user2}
      ], ttl: :timer.hours(1))

      # With per-entry options
      Cache.warm([
        {{:user, 1}, user1, ttl: :timer.hours(1)},
        {{:user, 2}, user2, ttl: :timer.minutes(30)}
      ])

      # From a function
      Cache.warm(fn ->
        Users.list_popular()
        |> Enum.map(&{{:user, &1.id}, &1})
      end, ttl: :timer.hours(1))

      # From a Warmable module
      Cache.warm(MyApp.UserWarmer)
  """
  @callback warm(
              entries_or_fun_or_module ::
                [entry()]
                | [{key(), value(), opts()}]
                | (-> [entry()])
                | module(),
              opts()
            ) :: :ok | {:error, term()}

  @optional_callbacks [
    get!: 1,
    exists?: 1,
    touch: 2,
    all: 1,
    keys: 1,
    values: 1,
    count: 1,
    delete_all: 1,
    get_all: 1,
    put_all: 2,
    clear: 0,
    stream: 1,
    # Health & Stats
    ping: 0,
    healthy?: 0,
    stats: 0,
    info: 1,
    # Conditional
    put_new: 3,
    # Tags
    tags: 1,
    keys_by_tag: 1,
    count_by_tag: 1,
    invalidate_tag: 1,
    invalidate_tags: 1,
    # Warming
    warm: 2
  ]

  # ============================================
  # Default Implementations
  # ============================================

  @doc """
  Use this module to get default implementations for optional callbacks.

      defmodule MyApp.Cache do
        @behaviour FnDecorator.Caching.Store
        use FnDecorator.Caching.Store

        # Only implement required callbacks
        def get(key), do: ...
        def put(key, value, opts), do: ...
        def delete(key), do: ...

        # Optional callbacks have defaults via __using__
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour FnDecorator.Caching.Store

      def get!(key) do
        case get(key) do
          nil -> raise KeyError, key: key, term: __MODULE__
          value -> value
        end
      end

      def exists?(key), do: get(key) != nil

      defoverridable get!: 1, exists?: 1
    end
  end
end
