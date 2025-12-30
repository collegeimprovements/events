defmodule FnDecorator.Caching.Adapters.Redis do
  @moduledoc """
  Redis-based cache store implementation.

  A production-ready implementation of `FnDecorator.Caching.Store` using Redis.
  Suitable for distributed caching across multiple nodes.

  ## Usage

      # Define your cache
      defmodule MyApp.Cache do
        use FnDecorator.Caching.Adapters.Redis,
          redis: MyApp.Redis,  # Redix connection or pool
          prefix: "cache:"
      end

      # Use it
      MyApp.Cache.put({User, 123}, user, ttl: :timer.minutes(5))
      MyApp.Cache.get({User, 123})

  ## Options

    * `:redis` - Redix connection module/name or `{module, pool_size}` for pooling (required)
    * `:prefix` - Key prefix for namespacing (default: "cache:")
    * `:serializer` - Module with `encode/1` and `decode/1` (default: `:erlang`)

  ## Key Encoding

  Cache keys (tuples, atoms, etc.) are encoded to Redis-compatible strings:
  - `{User, 123}` -> `"cache:{User,123}"`
  - `:session` -> `"cache:session"`

  ## Pattern Matching

  Pattern matching uses Redis SCAN with glob patterns:
  - `:all` -> `"cache:*"`
  - `{User, :_}` -> `"cache:{User,*}"`

  Note: Pattern operations (all, keys, delete_all) use SCAN which is safe for
  production but may be slow on very large keyspaces.

  ## Tags

  Entries can be tagged for bulk invalidation. Tags are stored in Redis SETs:

      Cache.put({:user, 1}, user, tags: [:users, "org:acme"])
      Cache.invalidate_tag(:users)  # Invalidates all entries tagged :users
  """

  alias FnDecorator.Caching.Pattern
  alias FnDecorator.Caching.Telemetry

  defmacro __using__(opts) do
    redis = Keyword.fetch!(opts, :redis)
    prefix = Keyword.get(opts, :prefix, "cache:")
    telemetry_enabled = Keyword.get(opts, :telemetry, true)

    quote do
      @behaviour FnDecorator.Caching.Store

      @redis unquote(redis)
      @prefix unquote(prefix)
      @tags_prefix unquote(prefix) <> "tag:"
      @key_tags_prefix unquote(prefix) <> "keytags:"
      @cache_name String.to_atom(unquote(prefix) <> "cache")
      @telemetry_enabled unquote(telemetry_enabled)
      @started_at System.monotonic_time(:millisecond)

      # ============================================
      # Health Checks
      # ============================================

      @impl true
      def ping do
        case redis_command(["PING"]) do
          {:ok, "PONG"} -> :pong
          {:ok, _} -> :pong
          {:error, reason} -> {:error, reason}
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
        base_stats =
          if @telemetry_enabled do
            Telemetry.get_stats(@cache_name)
          else
            %{hits: 0, misses: 0, hit_rate: 0.0, uptime_ms: nil}
          end

        key_count = count(:all)
        uptime = System.monotonic_time(:millisecond) - @started_at

        # Try to get Redis memory info
        memory_bytes =
          case redis_command(["MEMORY", "USAGE", @prefix <> "*"]) do
            {:ok, bytes} when is_integer(bytes) -> bytes
            _ -> nil
          end

        Map.merge(base_stats, %{
          keys: key_count,
          memory_bytes: memory_bytes,
          uptime_ms: uptime
        })
      end

      # ============================================
      # Key Info
      # ============================================

      @impl true
      def info(key) do
        redis_key = encode_key(key)

        with {:ok, data} when not is_nil(data) <- redis_command(["GET", redis_key]),
             {:ok, ttl_ms} <- redis_command(["PTTL", redis_key]) do
          value = decode_value(data)
          now = System.monotonic_time(:millisecond)
          entry_tags = tags(key)

          # Redis PTTL returns:
          # -2 if key doesn't exist
          # -1 if key has no TTL
          # positive integer for TTL in ms
          case ttl_ms do
            n when n < 0 ->
              # No TTL or doesn't exist
              %{
                status: :fresh,
                value: value,
                cached_at: nil,
                fresh_until: nil,
                stale_until: nil,
                ttl_remaining_ms: nil,
                expires_in_ms: nil,
                age_ms: nil,
                tags: entry_tags
              }

            n when is_integer(n) ->
              %{
                status: :fresh,
                value: value,
                cached_at: nil,
                fresh_until: now + n,
                stale_until: nil,
                ttl_remaining_ms: n,
                expires_in_ms: n,
                age_ms: nil,
                tags: entry_tags
              }
          end
        else
          _ -> nil
        end
      end

      # ============================================
      # Conditional Operations
      # ============================================

      @impl true
      def put_new(key, value, opts \\ []) do
        redis_key = encode_key(key)
        data = encode_value(value)
        ttl = Keyword.get(opts, :ttl)

        command =
          if ttl do
            ["SET", redis_key, data, "PX", ttl, "NX"]
          else
            ["SET", redis_key, data, "NX"]
          end

        case redis_command(command) do
          {:ok, "OK"} -> {:ok, :stored}
          {:ok, nil} -> {:ok, :exists}
          {:error, _} -> {:ok, :exists}
        end
      end

      # ============================================
      # Required: get/1, put/3, delete/1
      # ============================================

      @impl true
      def get(key) do
        redis_key = encode_key(key)

        case redis_command(["GET", redis_key]) do
          {:ok, nil} -> nil
          {:ok, data} -> decode_value(data)
          {:error, _} -> nil
        end
      end

      @impl true
      def put(key, value, opts \\ []) do
        redis_key = encode_key(key)
        data = encode_value(value)
        ttl = Keyword.get(opts, :ttl)
        entry_tags = Keyword.get(opts, :tags, [])

        # Remove old tag mappings first
        remove_key_from_tags(key)

        # Build commands
        set_command =
          if ttl do
            ["SET", redis_key, data, "PX", ttl]
          else
            ["SET", redis_key, data]
          end

        # Build pipeline for tags
        tag_commands =
          if entry_tags != [] do
            key_tags_key = @key_tags_prefix <> redis_key

            # Store which tags this key has
            store_key_tags = ["SADD", key_tags_key | Enum.map(entry_tags, &encode_tag/1)]

            # Add key to each tag set
            tag_adds = Enum.map(entry_tags, fn tag ->
              ["SADD", @tags_prefix <> encode_tag(tag), redis_key]
            end)

            # Set TTL on key_tags if main key has TTL
            ttl_commands =
              if ttl do
                [["PEXPIRE", key_tags_key, ttl]]
              else
                []
              end

            [store_key_tags | tag_adds] ++ ttl_commands
          else
            []
          end

        # Execute all commands
        if tag_commands != [] do
          redis_pipeline([set_command | tag_commands])
        else
          redis_command(set_command)
        end

        :ok
      end

      @impl true
      def delete(key) do
        redis_key = encode_key(key)

        # Remove tag mappings first
        remove_key_from_tags(key)

        # Delete the key and its key_tags
        key_tags_key = @key_tags_prefix <> redis_key
        redis_command(["DEL", redis_key, key_tags_key])

        :ok
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
        redis_key = encode_key(key)

        case redis_command(["EXISTS", redis_key]) do
          {:ok, 1} -> true
          {:ok, 0} -> false
          {:error, _} -> false
        end
      end

      @impl true
      def touch(key, opts) do
        redis_key = encode_key(key)
        ttl = Keyword.get(opts, :ttl)

        if ttl do
          case redis_command(["PEXPIRE", redis_key, ttl]) do
            {:ok, 1} -> :ok
            {:ok, 0} -> {:error, :not_found}
            {:error, reason} -> {:error, reason}
          end
        else
          # No TTL change, just check existence
          if exists?(key), do: :ok, else: {:error, :not_found}
        end
      end

      # ============================================
      # Optional: Bulk by Pattern
      # ============================================

      @impl true
      def all(pattern) do
        keys(pattern)
        |> Enum.map(fn key -> {key, get(key)} end)
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      end

      @impl true
      def keys(pattern) do
        redis_pattern = pattern_to_glob(pattern)
        scan_keys(redis_pattern)
        |> Enum.map(&decode_key/1)
      end

      @impl true
      def values(pattern) do
        keys(pattern)
        |> Enum.map(&get/1)
        |> Enum.reject(&is_nil/1)
      end

      @impl true
      def count(pattern) do
        keys(pattern) |> length()
      end

      @impl true
      def delete_all(pattern) do
        matching_keys = keys(pattern)
        count = length(matching_keys)

        if count > 0 do
          redis_keys = Enum.map(matching_keys, &encode_key/1)
          redis_command(["DEL" | redis_keys])
        end

        {:ok, count}
      end

      # ============================================
      # Optional: Bulk by Keys
      # ============================================

      @impl true
      def get_all(keys) when is_list(keys) do
        redis_keys = Enum.map(keys, &encode_key/1)

        case redis_command(["MGET" | redis_keys]) do
          {:ok, values} ->
            keys
            |> Enum.zip(values)
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Enum.map(fn {k, v} -> {k, decode_value(v)} end)
            |> Map.new()

          {:error, _} ->
            %{}
        end
      end

      @impl true
      def put_all(entries, opts \\ []) when is_list(entries) do
        ttl = Keyword.get(opts, :ttl)

        # Use pipeline for efficiency
        commands =
          Enum.map(entries, fn {key, value} ->
            redis_key = encode_key(key)
            data = encode_value(value)

            if ttl do
              ["SET", redis_key, data, "PX", ttl]
            else
              ["SET", redis_key, data]
            end
          end)

        redis_pipeline(commands)
        :ok
      end

      # ============================================
      # Optional: Maintenance
      # ============================================

      @impl true
      def clear do
        delete_all(:all)
        :ok
      end

      @impl true
      def stream(pattern) do
        # Redis SCAN-based stream
        Stream.resource(
          fn -> {"0", pattern_to_glob(pattern)} end,
          fn
            {:done, _} ->
              {:halt, nil}

            {cursor, redis_pattern} ->
              case redis_command(["SCAN", cursor, "MATCH", redis_pattern, "COUNT", "100"]) do
                {:ok, [next_cursor, keys]} ->
                  decoded = Enum.map(keys, fn k ->
                    key = decode_key(k)
                    {key, get(key)}
                  end)
                  |> Enum.reject(fn {_k, v} -> is_nil(v) end)

                  next_state =
                    if next_cursor == "0" do
                      {:done, nil}
                    else
                      {next_cursor, redis_pattern}
                    end

                  {decoded, next_state}

                {:error, _} ->
                  {:halt, nil}
              end
          end,
          fn _ -> :ok end
        )
      end

      # ============================================
      # Private Helpers
      # ============================================

      defp redis_command(command) do
        @redis.command(command)
      end

      defp redis_pipeline(commands) do
        @redis.pipeline(commands)
      end

      defp encode_key(key) do
        @prefix <> Base.encode64(:erlang.term_to_binary(key))
      end

      defp decode_key(redis_key) do
        redis_key
        |> String.trim_leading(@prefix)
        |> Base.decode64!()
        |> :erlang.binary_to_term()
      end

      defp encode_value(value) do
        :erlang.term_to_binary(value)
      end

      defp decode_value(nil), do: nil

      defp decode_value(data) do
        :erlang.binary_to_term(data)
      end

      defp pattern_to_glob(:all), do: @prefix <> "*"
      defp pattern_to_glob(:_), do: @prefix <> "*"

      defp pattern_to_glob(pattern) when is_tuple(pattern) do
        # For patterns like {User, :_}, we need to match encoded keys
        # Since we Base64 encode, we can't do partial matching easily
        # Fall back to fetching all and filtering
        @prefix <> "*"
      end

      defp pattern_to_glob(pattern), do: @prefix <> "*"

      defp scan_keys(redis_pattern) do
        scan_keys_acc("0", redis_pattern, [])
      end

      defp scan_keys_acc("0", _pattern, acc) when acc != [] do
        acc
      end

      defp scan_keys_acc(cursor, pattern, acc) do
        case redis_command(["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]) do
          {:ok, [next_cursor, keys]} ->
            # Filter keys that match our pattern after decoding
            new_acc = acc ++ keys
            if next_cursor == "0" do
              new_acc
            else
              scan_keys_acc(next_cursor, pattern, new_acc)
            end

          {:error, _} ->
            acc
        end
      end

      # Override to customize key matching for patterns
      # Since we encode keys, we need to decode and match in Elixir
      defp matches_pattern?(redis_key, :all), do: true
      defp matches_pattern?(redis_key, :_), do: true

      defp matches_pattern?(redis_key, pattern) do
        key = decode_key(redis_key)
        Pattern.matches?(pattern, key)
      end

      defp encode_tag(tag) when is_atom(tag), do: Atom.to_string(tag)
      defp encode_tag(tag) when is_binary(tag), do: tag

      defp decode_tag(tag_str) do
        # Try to convert back to atom if it was one
        try do
          String.to_existing_atom(tag_str)
        rescue
          ArgumentError -> tag_str
        end
      end

      # Remove a key from all its tag sets
      defp remove_key_from_tags(key) do
        redis_key = encode_key(key)
        key_tags_key = @key_tags_prefix <> redis_key

        case redis_command(["SMEMBERS", key_tags_key]) do
          {:ok, tag_strs} when is_list(tag_strs) and tag_strs != [] ->
            # Remove key from each tag set
            commands = Enum.map(tag_strs, fn tag_str ->
              ["SREM", @tags_prefix <> tag_str, redis_key]
            end)
            redis_pipeline(commands)

          _ ->
            :ok
        end
      end

      # ============================================
      # Tags
      # ============================================

      @impl true
      def tags(key) do
        redis_key = encode_key(key)
        key_tags_key = @key_tags_prefix <> redis_key

        case redis_command(["SMEMBERS", key_tags_key]) do
          {:ok, tag_strs} when is_list(tag_strs) ->
            Enum.map(tag_strs, &decode_tag/1)

          _ ->
            []
        end
      end

      @impl true
      def keys_by_tag(tag) do
        tag_key = @tags_prefix <> encode_tag(tag)

        case redis_command(["SMEMBERS", tag_key]) do
          {:ok, redis_keys} when is_list(redis_keys) ->
            redis_keys
            |> Enum.map(&decode_key/1)
            |> Enum.filter(&exists?/1)

          _ ->
            []
        end
      end

      @impl true
      def count_by_tag(tag) do
        keys_by_tag(tag) |> length()
      end

      @impl true
      def invalidate_tag(tag) do
        tag_key = @tags_prefix <> encode_tag(tag)

        case redis_command(["SMEMBERS", tag_key]) do
          {:ok, redis_keys} when is_list(redis_keys) and redis_keys != [] ->
            # Delete all keys and the tag set
            decoded_keys = Enum.map(redis_keys, &decode_key/1)
            Enum.each(decoded_keys, &delete/1)
            redis_command(["DEL", tag_key])
            {:ok, length(redis_keys)}

          _ ->
            {:ok, 0}
        end
      end

      @impl true
      def invalidate_tags(tags_list) when is_list(tags_list) do
        # Collect all keys matching any of the tags
        all_keys =
          tags_list
          |> Enum.flat_map(&keys_by_tag/1)
          |> Enum.uniq()

        Enum.each(all_keys, &delete/1)

        # Delete the tag sets
        tag_keys = Enum.map(tags_list, fn tag -> @tags_prefix <> encode_tag(tag) end)
        if tag_keys != [], do: redis_command(["DEL" | tag_keys])

        {:ok, length(all_keys)}
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

      defp normalize_entry({key, value}), do: {key, value, []}
      defp normalize_entry({key, value, opts}) when is_list(opts), do: {key, value, opts}

      defoverridable get!: 1, exists?: 1, touch: 2, all: 1, keys: 1, values: 1,
                     count: 1, delete_all: 1, get_all: 1, put_all: 2, clear: 0, stream: 1,
                     ping: 0, healthy?: 0, stats: 0, info: 1, put_new: 3,
                     tags: 1, keys_by_tag: 1, count_by_tag: 1, invalidate_tag: 1, invalidate_tags: 1,
                     warm: 2
    end
  end
end
