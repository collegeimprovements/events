defmodule FnDecorator.Caching.Adapters.ETS do
  @moduledoc """
  ETS-based cache store implementation.

  A reference implementation of `FnDecorator.Caching.Store` using ETS tables.
  Suitable for single-node caching with high read throughput.

  ## Usage

      # Define your cache
      defmodule MyApp.Cache do
        use FnDecorator.Caching.Adapters.ETS, table: :my_cache
      end

      # Start it (in your supervision tree)
      MyApp.Cache.start_link()

      # Use it
      MyApp.Cache.put({User, 123}, user, ttl: :timer.minutes(5))
      MyApp.Cache.get({User, 123})

  ## Options

    * `:table` - ETS table name (required)
    * `:read_concurrency` - Enable read concurrency (default: true)
    * `:write_concurrency` - Enable write concurrency (default: true)
    * `:telemetry` - Enable telemetry events (default: true)
    * `:warmers` - List of modules implementing `FnDecorator.Caching.Warmable` (optional)

  ## Entry Format

  Entries are stored as `{key, value, cached_at, fresh_until, stale_until, tags}` tuples.

  ## Tags

  Entries can be tagged for bulk invalidation:

      Cache.put({:user, 1}, user, tags: [:users, "org:acme"])
      Cache.invalidate_tag(:users)  # Invalidates all entries tagged :users

  ## Telemetry

  When enabled, emits events under `[:fn_decorator, :cache, ...]`.
  See `FnDecorator.Caching.Telemetry` for available events.
  """

  alias FnDecorator.Caching.Pattern
  alias FnDecorator.Caching.Telemetry

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    read_concurrency = Keyword.get(opts, :read_concurrency, true)
    write_concurrency = Keyword.get(opts, :write_concurrency, true)
    telemetry_enabled = Keyword.get(opts, :telemetry, true)
    warmers = Keyword.get(opts, :warmers, [])

    quote do
      @behaviour FnDecorator.Caching.Store

      @table unquote(table)
      @tags_table :"#{unquote(table)}_tags"
      @cache_name unquote(table)
      @telemetry_enabled unquote(telemetry_enabled)
      @warmers unquote(warmers)
      @ets_opts [
        :set,
        :public,
        :named_table,
        read_concurrency: unquote(read_concurrency),
        write_concurrency: unquote(write_concurrency)
      ]
      @tags_ets_opts [
        :bag,
        :public,
        :named_table,
        read_concurrency: unquote(read_concurrency),
        write_concurrency: unquote(write_concurrency)
      ]

      # ============================================
      # Lifecycle
      # ============================================

      @doc "Start the cache (creates ETS table and runs warmers)"
      def start_link(_opts \\ []) do
        :ok = init()
        run_warmers()
        {:ok, self()}
      end

      @doc "Initialize the ETS tables"
      def init do
        # Main cache table
        case :ets.whereis(@table) do
          :undefined ->
            :ets.new(@table, @ets_opts)
            if @telemetry_enabled, do: Telemetry.init_stats(@cache_name)

          _ref ->
            :ok
        end

        # Tags table (bag for multiple keys per tag)
        case :ets.whereis(@tags_table) do
          :undefined ->
            :ets.new(@tags_table, @tags_ets_opts)

          _ref ->
            :ok
        end

        :ok
      end

      defp run_warmers do
        Enum.each(@warmers, fn warmer ->
          warm(warmer)
        end)
      end

      # ============================================
      # Health Checks
      # ============================================

      @impl true
      def ping do
        init()

        case :ets.whereis(@table) do
          :undefined -> {:error, :table_not_found}
          _ref -> :pong
        end
      end

      @impl true
      def healthy? do
        ping() == :pong
      end

      # ============================================
      # Stats
      # ============================================

      @impl true
      def stats do
        init()

        base_stats =
          if @telemetry_enabled do
            Telemetry.get_stats(@cache_name)
          else
            %{hits: 0, misses: 0, hit_rate: 0.0, uptime_ms: nil}
          end

        memory_bytes =
          case :ets.info(@table, :memory) do
            :undefined -> nil
            words -> words * :erlang.system_info(:wordsize)
          end

        key_count = count(:all)

        Map.merge(base_stats, %{
          keys: key_count,
          memory_bytes: memory_bytes
        })
      end

      # ============================================
      # Key Info
      # ============================================

      @impl true
      def info(key) do
        init()

        case :ets.lookup(@table, key) do
          [{^key, value, cached_at, fresh_until, stale_until, entry_tags}] ->
            # New format with tags (6-tuple)
            build_info(key, value, cached_at, fresh_until, stale_until, entry_tags)

          [{^key, value, cached_at, fresh_until, stale_until}] ->
            # Format without tags (5-tuple)
            build_info(key, value, cached_at, fresh_until, stale_until, [])

          # Legacy format without metadata (3-tuple)
          [{^key, value, expires_at}] ->
            now = System.monotonic_time(:millisecond)

            if expires_at != nil and now >= expires_at do
              nil
            else
              ttl_remaining = if expires_at, do: max(0, expires_at - now), else: nil

              %{
                status: :fresh,
                value: value,
                cached_at: nil,
                fresh_until: expires_at,
                stale_until: nil,
                ttl_remaining_ms: ttl_remaining,
                expires_in_ms: ttl_remaining,
                age_ms: nil,
                tags: []
              }
            end

          [] ->
            nil
        end
      end

      defp build_info(_key, value, cached_at, fresh_until, stale_until, entry_tags) do
        now = System.monotonic_time(:millisecond)

        status =
          cond do
            fresh_until == nil -> :fresh
            now < fresh_until -> :fresh
            stale_until != nil and now < stale_until -> :stale
            true -> :expired
          end

        # Don't return expired entries
        if status == :expired do
          nil
        else
          ttl_remaining = if fresh_until, do: max(0, fresh_until - now), else: nil

          %{
            status: status,
            value: value,
            cached_at: cached_at,
            fresh_until: fresh_until,
            stale_until: stale_until,
            ttl_remaining_ms: ttl_remaining,
            expires_in_ms: if(stale_until, do: max(0, stale_until - now), else: ttl_remaining),
            age_ms: if(cached_at, do: now - cached_at, else: nil),
            tags: entry_tags
          }
        end
      end

      # ============================================
      # Required: get/1, put/3, delete/1
      # ============================================

      @impl true
      def get(key) do
        init()
        start = if @telemetry_enabled, do: System.monotonic_time(), else: nil

        result =
          case :ets.lookup(@table, key) do
            [{^key, value, _cached_at, fresh_until, stale_until, _tags}] ->
              # New format with tags (6-tuple)
              now = System.monotonic_time(:millisecond)

              cond do
                fresh_until == nil ->
                  {:hit, :fresh, value}

                now < fresh_until ->
                  {:hit, :fresh, value}

                stale_until != nil and now < stale_until ->
                  {:hit, :stale, value}

                true ->
                  delete(key)
                  :miss
              end

            [{^key, value, _cached_at, fresh_until, stale_until}] ->
              # Format without tags (5-tuple)
              now = System.monotonic_time(:millisecond)

              cond do
                fresh_until == nil ->
                  {:hit, :fresh, value}

                now < fresh_until ->
                  {:hit, :fresh, value}

                stale_until != nil and now < stale_until ->
                  {:hit, :stale, value}

                true ->
                  :ets.delete(@table, key)
                  :miss
              end

            [{^key, value, expires_at}] ->
              # Legacy format (3-tuple)
              if expired?(expires_at) do
                :ets.delete(@table, key)
                :miss
              else
                {:hit, :fresh, value}
              end

            [] ->
              :miss
          end

        if @telemetry_enabled do
          duration = System.monotonic_time() - start

          case result do
            {:hit, status, _} ->
              Telemetry.record_hit(@cache_name)
              Telemetry.emit_get(key, status, duration)

            :miss ->
              Telemetry.record_miss(@cache_name)
              Telemetry.emit_get(key, :miss, duration)
          end
        end

        case result do
          {:hit, _, value} -> value
          :miss -> nil
        end
      end

      @impl true
      def put(key, value, opts \\ []) do
        init()
        start = if @telemetry_enabled, do: System.monotonic_time(), else: nil

        ttl = Keyword.get(opts, :ttl)
        stale_ttl = Keyword.get(opts, :stale_ttl)
        entry_tags = Keyword.get(opts, :tags, [])
        now = System.monotonic_time(:millisecond)

        fresh_until = if ttl, do: now + ttl, else: nil
        stale_until = if stale_ttl, do: now + stale_ttl, else: nil

        # Remove old tag mappings for this key
        remove_key_from_tags(key)

        # Insert the entry with tags
        :ets.insert(@table, {key, value, now, fresh_until, stale_until, entry_tags})

        # Add new tag mappings
        Enum.each(entry_tags, fn tag ->
          :ets.insert(@tags_table, {tag, key})
        end)

        if @telemetry_enabled do
          duration = System.monotonic_time() - start
          Telemetry.emit_put(key, ttl, duration)
        end

        :ok
      end

      @impl true
      def delete(key) do
        init()
        start = if @telemetry_enabled, do: System.monotonic_time(), else: nil

        # Remove tag mappings first
        remove_key_from_tags(key)

        # Delete the entry
        :ets.delete(@table, key)

        if @telemetry_enabled do
          duration = System.monotonic_time() - start
          Telemetry.emit_delete(key, duration)
        end

        :ok
      end

      # ============================================
      # Conditional Operations
      # ============================================

      @impl true
      def put_new(key, value, opts \\ []) do
        init()

        case get(key) do
          nil ->
            put(key, value, opts)
            {:ok, :stored}

          _existing ->
            {:ok, :exists}
        end
      end

      # ============================================
      # Optional: Single Key
      # ============================================

      @impl true
      def get!(key) do
        case get(key) do
          nil -> raise KeyError, key: key, term: __MODULE__
          value -> value
        end
      end

      @impl true
      def exists?(key) do
        init()

        case :ets.lookup(@table, key) do
          [{^key, _value, _cached_at, fresh_until, stale_until, _tags}] ->
            not entry_expired?(fresh_until, stale_until)

          [{^key, _value, _cached_at, fresh_until, stale_until}] ->
            not entry_expired?(fresh_until, stale_until)

          [{^key, _value, expires_at}] ->
            not expired?(expires_at)

          [] ->
            false
        end
      end

      @impl true
      def touch(key, opts) do
        init()
        ttl = Keyword.get(opts, :ttl)
        stale_ttl = Keyword.get(opts, :stale_ttl)
        now = System.monotonic_time(:millisecond)

        case :ets.lookup(@table, key) do
          [{^key, value, cached_at, old_fresh_until, old_stale_until, entry_tags}] ->
            # New format with tags (6-tuple)
            if entry_expired?(old_fresh_until, old_stale_until) do
              delete(key)
              {:error, :not_found}
            else
              new_fresh_until = if ttl, do: now + ttl, else: old_fresh_until
              new_stale_until = if stale_ttl, do: now + stale_ttl, else: old_stale_until

              :ets.insert(@table, {key, value, cached_at, new_fresh_until, new_stale_until, entry_tags})
              :ok
            end

          [{^key, value, cached_at, old_fresh_until, old_stale_until}] ->
            # Format without tags (5-tuple)
            if entry_expired?(old_fresh_until, old_stale_until) do
              :ets.delete(@table, key)
              {:error, :not_found}
            else
              new_fresh_until = if ttl, do: now + ttl, else: old_fresh_until
              new_stale_until = if stale_ttl, do: now + stale_ttl, else: old_stale_until

              :ets.insert(@table, {key, value, cached_at, new_fresh_until, new_stale_until})
              :ok
            end

          [{^key, value, old_expires_at}] ->
            # Legacy format (3-tuple)
            if expired?(old_expires_at) do
              :ets.delete(@table, key)
              {:error, :not_found}
            else
              new_expires_at = if ttl, do: now + ttl, else: old_expires_at
              :ets.insert(@table, {key, value, new_expires_at})
              :ok
            end

          [] ->
            {:error, :not_found}
        end
      end

      # ============================================
      # Optional: Bulk by Pattern
      # ============================================

      @impl true
      def all(pattern) do
        init()
        now = System.monotonic_time(:millisecond)

        select_all()
        |> Enum.filter(&entry_matches?(pattern, &1, now))
        |> Enum.map(&entry_to_kv/1)
      end

      @impl true
      def keys(pattern) do
        init()
        now = System.monotonic_time(:millisecond)

        select_all()
        |> Enum.filter(&entry_matches?(pattern, &1, now))
        |> Enum.map(&elem(&1, 0))
      end

      @impl true
      def values(pattern) do
        init()
        now = System.monotonic_time(:millisecond)

        select_all()
        |> Enum.filter(&entry_matches?(pattern, &1, now))
        |> Enum.map(&elem(&1, 1))
      end

      @impl true
      def count(pattern) do
        init()
        now = System.monotonic_time(:millisecond)

        select_all()
        |> Enum.count(&entry_matches?(pattern, &1, now))
      end

      @impl true
      def delete_all(pattern) do
        init()
        start = if @telemetry_enabled, do: System.monotonic_time(), else: nil
        now = System.monotonic_time(:millisecond)

        keys_to_delete =
          select_all()
          |> Enum.filter(&entry_matches?(pattern, &1, now))
          |> Enum.map(&elem(&1, 0))

        # Use delete/1 to also clean up tag mappings
        Enum.each(keys_to_delete, &delete/1)
        count = length(keys_to_delete)

        if @telemetry_enabled do
          duration = System.monotonic_time() - start
          Telemetry.emit_delete_all(pattern, count, duration)
        end

        {:ok, count}
      end

      # ============================================
      # Optional: Bulk by Keys
      # ============================================

      @impl true
      def get_all(keys) when is_list(keys) do
        init()

        keys
        |> Enum.reduce(%{}, fn key, acc ->
          case get(key) do
            nil -> acc
            value -> Map.put(acc, key, value)
          end
        end)
      end

      @impl true
      def put_all(entries, opts \\ []) when is_list(entries) do
        init()
        default_ttl = Keyword.get(opts, :ttl)
        default_stale_ttl = Keyword.get(opts, :stale_ttl)
        default_tags = Keyword.get(opts, :tags, [])
        now = System.monotonic_time(:millisecond)

        # Use put/3 for each entry to properly handle tags
        Enum.each(entries, fn entry ->
          {key, value, entry_opts} = normalize_entry(entry)
          merged_opts = Keyword.merge([ttl: default_ttl, stale_ttl: default_stale_ttl, tags: default_tags], entry_opts)
          put(key, value, merged_opts)
        end)

        :ok
      end

      defp normalize_entry({key, value}), do: {key, value, []}
      defp normalize_entry({key, value, opts}) when is_list(opts), do: {key, value, opts}

      # ============================================
      # Optional: Maintenance
      # ============================================

      @impl true
      def clear do
        init()
        :ets.delete_all_objects(@table)
        :ets.delete_all_objects(@tags_table)

        if @telemetry_enabled do
          Telemetry.init_stats(@cache_name)
        end

        :ok
      end

      @impl true
      def stream(pattern) do
        init()
        now = System.monotonic_time(:millisecond)

        Stream.resource(
          fn -> :ets.first(@table) end,
          fn
            :"$end_of_table" ->
              {:halt, nil}

            key ->
              next_key = :ets.next(@table, key)

              case :ets.lookup(@table, key) do
                [{^key, value, _cached_at, fresh_until, stale_until, _tags}] ->
                  # New format with tags (6-tuple)
                  if Pattern.matches?(pattern, key) and not entry_expired?(fresh_until, stale_until, now) do
                    {[{key, value}], next_key}
                  else
                    {[], next_key}
                  end

                [{^key, value, _cached_at, fresh_until, stale_until}] ->
                  # Format without tags (5-tuple)
                  if Pattern.matches?(pattern, key) and not entry_expired?(fresh_until, stale_until, now) do
                    {[{key, value}], next_key}
                  else
                    {[], next_key}
                  end

                [{^key, value, expires_at}] ->
                  # Legacy format (3-tuple)
                  if Pattern.matches?(pattern, key) and not expired?(expires_at, now) do
                    {[{key, value}], next_key}
                  else
                    {[], next_key}
                  end

                [] ->
                  {[], next_key}
              end
          end,
          fn _ -> :ok end
        )
      end

      # ============================================
      # Private Helpers
      # ============================================

      defp select_all do
        :ets.tab2list(@table)
      end

      # Check if entry matches pattern and is not expired
      # Handles 6-tuple (with tags), 5-tuple (without tags), and 3-tuple (legacy) formats
      defp entry_matches?(pattern, {key, _value, _cached_at, fresh_until, stale_until, _tags}, now) do
        Pattern.matches?(pattern, key) and not entry_expired?(fresh_until, stale_until, now)
      end

      defp entry_matches?(pattern, {key, _value, _cached_at, fresh_until, stale_until}, now) do
        Pattern.matches?(pattern, key) and not entry_expired?(fresh_until, stale_until, now)
      end

      defp entry_matches?(pattern, {key, _value, expires_at}, now) do
        Pattern.matches?(pattern, key) and not expired?(expires_at, now)
      end

      # Extract {key, value} from entry
      defp entry_to_kv({key, value, _cached_at, _fresh_until, _stale_until, _tags}), do: {key, value}
      defp entry_to_kv({key, value, _cached_at, _fresh_until, _stale_until}), do: {key, value}
      defp entry_to_kv({key, value, _expires_at}), do: {key, value}

      # Check if 5-tuple entry is expired
      defp entry_expired?(fresh_until, stale_until) do
        entry_expired?(fresh_until, stale_until, System.monotonic_time(:millisecond))
      end

      defp entry_expired?(nil, nil, _now), do: false
      defp entry_expired?(fresh_until, nil, now), do: now >= fresh_until
      defp entry_expired?(_fresh_until, stale_until, now), do: now >= stale_until

      # Check if 3-tuple entry is expired (legacy)
      defp expired?(nil), do: false
      defp expired?(nil, _now), do: false

      defp expired?(expires_at) do
        System.monotonic_time(:millisecond) > expires_at
      end

      defp expired?(expires_at, now) do
        now > expires_at
      end

      # Remove a key from all its tag mappings
      defp remove_key_from_tags(key) do
        # Get all tags for this key from the main table
        case :ets.lookup(@table, key) do
          [{^key, _value, _cached_at, _fresh_until, _stale_until, entry_tags}] ->
            Enum.each(entry_tags, fn tag ->
              :ets.delete_object(@tags_table, {tag, key})
            end)

          _ ->
            :ok
        end
      end

      # ============================================
      # Tags
      # ============================================

      @impl true
      def tags(key) do
        init()

        case :ets.lookup(@table, key) do
          [{^key, _value, _cached_at, fresh_until, stale_until, entry_tags}] ->
            if entry_expired?(fresh_until, stale_until) do
              []
            else
              entry_tags
            end

          _ ->
            []
        end
      end

      @impl true
      def keys_by_tag(tag) do
        init()

        :ets.lookup(@tags_table, tag)
        |> Enum.map(fn {_tag, key} -> key end)
        |> Enum.filter(&exists?/1)
      end

      @impl true
      def count_by_tag(tag) do
        keys_by_tag(tag) |> length()
      end

      @impl true
      def invalidate_tag(tag) do
        init()

        keys = keys_by_tag(tag)
        Enum.each(keys, &delete/1)
        {:ok, length(keys)}
      end

      @impl true
      def invalidate_tags(tags_list) when is_list(tags_list) do
        init()

        # Collect all keys matching any of the tags
        keys =
          tags_list
          |> Enum.flat_map(&keys_by_tag/1)
          |> Enum.uniq()

        Enum.each(keys, &delete/1)
        {:ok, length(keys)}
      end

      # ============================================
      # Warming
      # ============================================

      @impl true
      def warm(source, opts \\ [])

      def warm(module, opts) when is_atom(module) do
        # Module implementing Warmable behaviour
        entries = module.entries()
        warmer_opts = if function_exported?(module, :opts, 0), do: module.opts(), else: []
        merged_opts = Keyword.merge(warmer_opts, opts)
        do_warm(entries, merged_opts)
      end

      def warm(fun, opts) when is_function(fun, 0) do
        entries = fun.()
        do_warm(entries, opts)
      end

      def warm(entries, opts) when is_list(entries) do
        do_warm(entries, opts)
      end

      defp do_warm(entries, opts) do
        init()
        batch_size = Keyword.get(opts, :batch_size, 100)
        on_progress = Keyword.get(opts, :on_progress)
        total = length(entries)

        entries
        |> Enum.with_index(1)
        |> Enum.chunk_every(batch_size)
        |> Enum.each(fn batch ->
          Enum.each(batch, fn {entry, idx} ->
            {key, value, entry_opts} = normalize_entry(entry)
            merged_opts = Keyword.merge(opts, entry_opts)
            put(key, value, merged_opts)

            if on_progress && rem(idx, batch_size) == 0 do
              on_progress.(idx, total)
            end
          end)
        end)

        if on_progress, do: on_progress.(total, total)
        :ok
      end

      defoverridable get!: 1, exists?: 1, touch: 2, all: 1, keys: 1, values: 1,
                     count: 1, delete_all: 1, get_all: 1, put_all: 2, clear: 0, stream: 1,
                     ping: 0, healthy?: 0, stats: 0, info: 1, put_new: 3,
                     tags: 1, keys_by_tag: 1, count_by_tag: 1, invalidate_tag: 1, invalidate_tags: 1,
                     warm: 2
    end
  end
end
