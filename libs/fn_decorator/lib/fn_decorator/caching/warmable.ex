defmodule FnDecorator.Caching.Warmable do
  @moduledoc """
  Behaviour for cache warmers.

  Implement this behaviour to define reusable cache warming logic that can be
  used with `Cache.warm/2` or configured in a cache's `warmers` option.

  ## Usage

      defmodule MyApp.UserWarmer do
        @behaviour FnDecorator.Caching.Warmable

        @impl true
        def entries do
          MyApp.Users.list_popular(limit: 1000)
          |> Enum.map(fn user ->
            {{:user, user.id}, user}
          end)
        end

        @impl true
        def opts do
          [ttl: :timer.hours(1)]
        end
      end

      # Then use it:
      MyApp.Cache.warm(MyApp.UserWarmer)

      # Or configure in cache:
      defmodule MyApp.Cache do
        use FnDecorator.Caching.Adapters.ETS,
          table: :my_cache,
          warmers: [MyApp.UserWarmer]
      end

  ## Entries Format

  The `entries/0` callback can return:
  - `[{key, value}]` - Simple key-value pairs
  - `[{key, value, opts}]` - Entries with per-entry options (TTL, tags)

  ## Examples

      # Simple warmer
      defmodule PopularUsersWarmer do
        @behaviour FnDecorator.Caching.Warmable

        @impl true
        def entries do
          Repo.all(from u in User, order_by: [desc: u.views], limit: 100)
          |> Enum.map(&{{:user, &1.id}, &1})
        end

        @impl true
        def opts, do: [ttl: :timer.hours(1)]
      end

      # Warmer with tags and per-entry TTL
      defmodule ConfigWarmer do
        @behaviour FnDecorator.Caching.Warmable

        @impl true
        def entries do
          Config.list_all()
          |> Enum.map(fn config ->
            ttl = if config.volatile, do: :timer.minutes(5), else: :timer.hours(24)
            {{:config, config.key}, config.value, ttl: ttl, tags: [:config]}
          end)
        end

        @impl true
        def opts, do: []  # Per-entry opts take precedence
      end

      # Conditional warmer
      defmodule PremiumUsersWarmer do
        @behaviour FnDecorator.Caching.Warmable

        @impl true
        def entries do
          if should_warm?() do
            fetch_premium_users()
          else
            []  # Return empty to skip warming
          end
        end

        @impl true
        def opts, do: [ttl: :timer.hours(2), tags: [:users, :premium]]

        defp should_warm? do
          # Only warm during off-peak hours
          hour = DateTime.utc_now().hour
          hour < 6 or hour > 22
        end

        defp fetch_premium_users do
          Repo.all(from u in User, where: u.premium == true)
          |> Enum.map(&{{:user, &1.id}, &1})
        end
      end
  """

  @type key :: term()
  @type value :: term()
  @type entry :: {key(), value()} | {key(), value(), keyword()}
  @type opts :: keyword()

  @doc """
  Returns a list of entries to warm the cache with.

  Can return:
  - `[{key, value}]` - Simple entries
  - `[{key, value, opts}]` - Entries with per-entry options

  Return an empty list to skip warming.
  """
  @callback entries() :: [entry()]

  @doc """
  Returns default options for all entries.

  These options are used as defaults and can be overridden per-entry.
  Common options: `:ttl`, `:tags`.
  """
  @callback opts() :: opts()

  @optional_callbacks [opts: 0]

  @doc """
  Default implementation helper for opts/0.

  Use this in your module if you don't need custom options:

      defmodule MyWarmer do
        @behaviour FnDecorator.Caching.Warmable
        use FnDecorator.Caching.Warmable  # Provides default opts/0

        @impl true
        def entries, do: [...]
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour FnDecorator.Caching.Warmable

      @impl FnDecorator.Caching.Warmable
      def opts, do: []

      defoverridable opts: 0
    end
  end
end
