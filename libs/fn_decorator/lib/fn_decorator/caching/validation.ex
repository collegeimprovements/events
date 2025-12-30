defmodule FnDecorator.Caching.Validation do
  @moduledoc """
  Compile-time validation for cacheable decorator options.

  Validates configuration at compile time using NimbleOptions to catch errors
  early and provide helpful error messages.

  ## Grouped API Schema

  The cacheable decorator uses a grouped structure for clarity:

      @decorate cacheable(
        store: [
          cache: MyCache,
          key: {User, id},
          ttl: :timer.minutes(5),
          only_if: &match?({:ok, _}, &1)
        ],
        serve_stale: [ttl: :timer.hours(1)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: [
          max_wait: 5_000,
          lock_ttl: 30_000,
          on_timeout: :serve_stale
        ],
        fallback: [on_error: :serve_stale]
      )

  ## NimbleOptions Integration

  This module uses NimbleOptions for schema definition and validation,
  providing consistent error messages and documentation.
  """

  # ============================================
  # Schema Definition
  # ============================================

  @store_schema NimbleOptions.new!([
    cache: [
      # Type is :any because at compile-time we receive AST nodes, not atoms
      type: :any,
      required: true,
      doc: "Cache module implementing get/1 and put/3, or MFA tuple for dynamic resolution"
    ],
    key: [
      type: :any,
      required: true,
      doc: "Cache key (any term)"
    ],
    ttl: [
      type: :pos_integer,
      required: true,
      doc: "Time-to-live in milliseconds. Value is considered fresh until TTL expires."
    ],
    only_if: [
      # Type is :any because at compile-time we receive AST for functions
      type: :any,
      required: false,
      default: nil,
      doc: """
      Function to determine if a result should be cached. Takes the result
      and returns a boolean. If nil, all results are cached.
      Example: &match?({:ok, _}, &1)
      """
    ],
    tags: [
      # Type is :any because it can be a list or a function (AST at compile-time)
      type: :any,
      required: false,
      default: nil,
      doc: """
      Tags for group-based invalidation. Can be:
      - A list of atoms/strings: [:users, :admins]
      - A function taking result: fn result -> ["org:\#{result.org_id}"] end
      """
    ]
  ])

  @serve_stale_schema NimbleOptions.new!([
    ttl: [
      type: :pos_integer,
      required: true,
      doc: """
      Extended TTL for stale-while-revalidate pattern.
      When set, expired values (beyond store.ttl but within serve_stale.ttl)
      are returned while triggering a background refresh.
      """
    ]
  ])

  @refresh_schema NimbleOptions.new!([
    on: [
      type: {:or, [{:in, [:stale_access]}, {:list, {:in, [:stale_access]}}, nil]},
      required: false,
      default: nil,
      doc: """
      Refresh trigger. Currently supports:
      - :stale_access - Trigger background refresh when stale data is accessed
      """
    ]
  ])

  @thunder_herd_schema NimbleOptions.new!([
    max_wait: [
      type: :pos_integer,
      required: false,
      default: 5_000,
      doc: "Maximum time (ms) to wait for another process to finish fetching"
    ],
    lock_ttl: [
      type: :pos_integer,
      required: false,
      default: 30_000,
      doc: "Lock validity duration (ms)"
    ],
    on_timeout: [
      type: :any,
      required: false,
      default: :serve_stale,
      doc: """
      Action when wait times out:
      - :serve_stale - Return stale value if available
      - :error - Return {:error, :cache_timeout}
      - :proceed - Execute fetch anyway
      - {:call, fun} - Call fun.() to get value
      - {:value, term} - Return fixed value
      """
    ]
  ])

  @fallback_schema NimbleOptions.new!([
    on_error: [
      type: :any,
      required: false,
      default: :raise,
      doc: """
      How to handle errors during fetch:
      - :raise - Re-raise the exception (default)
      - :serve_stale - Return stale value if available, else raise
      - {:call, fun} - Call fun.(error) to handle
      - {:value, term} - Return a fixed value
      """
    ]
  ])

  # Top-level schema without nested keys validation (we do that manually)
  @cacheable_schema NimbleOptions.new!([
    store: [
      type: :keyword_list,
      required: true,
      doc: "Cache storage configuration"
    ],
    serve_stale: [
      type: {:or, [:keyword_list, nil]},
      required: false,
      default: nil,
      doc: "Stale-while-revalidate configuration"
    ],
    refresh: [
      type: {:or, [:keyword_list, nil]},
      required: false,
      default: nil,
      doc: "Background refresh configuration"
    ],
    prevent_thunder_herd: [
      type: {:or, [:keyword_list, :boolean, nil]},
      required: false,
      default: true,
      doc: "Thunder herd prevention configuration. Set to false to disable."
    ],
    fallback: [
      type: {:or, [:keyword_list, nil]},
      required: false,
      default: nil,
      doc: "Fallback/error handling configuration"
    ]
  ])

  @cache_put_schema NimbleOptions.new!([
    cache: [
      # Type is :any because at compile-time we receive AST nodes, not atoms
      type: :any,
      required: true,
      doc: "Cache module or MFA tuple"
    ],
    keys: [
      type: {:list, :any},
      required: true,
      doc: "List of cache keys to update"
    ],
    ttl: [
      type: {:or, [:pos_integer, nil]},
      required: false,
      default: nil,
      doc: "Time-to-live in milliseconds"
    ],
    match: [
      # Type is :any because at compile-time we receive AST for functions
      type: :any,
      required: false,
      default: nil,
      doc: "Function to determine if result should be cached"
    ]
  ])

  @cache_evict_schema NimbleOptions.new!([
    cache: [
      # Type is :any because at compile-time we receive AST nodes, not atoms
      type: :any,
      required: true,
      doc: "Cache module or MFA tuple"
    ],
    keys: [
      type: {:or, [{:list, :any}, nil]},
      required: false,
      default: nil,
      doc: "List of specific cache keys to evict"
    ],
    match: [
      type: :any,
      required: false,
      default: nil,
      doc: """
      Pattern to match keys for eviction.
      - `:all` - Match all entries
      - `{User, :_}` - Match all User entries
      - `{:_, :profile}` - Match all profile entries
      """
    ],
    all_entries: [
      type: :boolean,
      required: false,
      default: false,
      doc: "If true, delete all cache entries (shorthand for match: :all)"
    ],
    before_invocation: [
      type: :boolean,
      required: false,
      default: false,
      doc: "If true, evict before function executes"
    ],
    only_if: [
      # Type is :any because at compile-time we receive AST for functions
      type: :any,
      required: false,
      default: nil,
      doc: "Function to determine if eviction should happen based on result"
    ],
    tags: [
      # Type is :any because it can be a list or a function (AST at compile-time)
      type: :any,
      required: false,
      default: nil,
      doc: """
      Tags for group-based invalidation. Can be:
      - A list of atoms/strings: [:users, :admins]
      - A function taking result: fn result -> ["org:\#{result.org_id}"] end
      """
    ]
  ])

  # ============================================
  # Public API
  # ============================================

  @doc """
  Validates cacheable options at compile time.

  Returns `{:ok, validated_opts}` on success or `{:error, exception}` on failure.

  ## Examples

      iex> Validation.validate(store: [cache: MyCache, key: :foo, ttl: 5000])
      {:ok, [store: [cache: MyCache, key: :foo, ttl: 5000, ...], ...]}

      iex> Validation.validate(store: [cache: MyCache, key: :foo])
      {:error, %NimbleOptions.ValidationError{...}}
  """
  @spec validate(keyword()) :: {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(opts) do
    with {:ok, top_level} <- NimbleOptions.validate(opts, @cacheable_schema),
         {:ok, store} <- validate_nested(top_level[:store], @store_schema, :store),
         {:ok, serve_stale} <- validate_optional_nested(top_level[:serve_stale], @serve_stale_schema, :serve_stale),
         {:ok, refresh} <- validate_optional_nested(top_level[:refresh], @refresh_schema, :refresh),
         {:ok, thunder_herd} <- validate_thunder_herd_option(top_level[:prevent_thunder_herd]),
         {:ok, fallback} <- validate_optional_nested(top_level[:fallback], @fallback_schema, :fallback) do
      validated = [
        store: store,
        serve_stale: serve_stale,
        refresh: refresh,
        prevent_thunder_herd: thunder_herd,
        fallback: fallback
      ]

      validate_constraints(validated)
    end
  end

  @doc """
  Validates cacheable options and raises on error.

  Returns validated options on success.

  ## Examples

      iex> Validation.validate!(store: [cache: MyCache, key: :foo, ttl: 5000])
      [store: [cache: MyCache, key: :foo, ttl: 5000, ...], ...]

      iex> Validation.validate!(store: [cache: MyCache, key: :foo])
      ** (NimbleOptions.ValidationError) ...
  """
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    case validate(opts) do
      {:ok, validated} -> validated
      {:error, error} -> raise error
    end
  end

  @doc """
  Validates cache_put options.
  """
  @spec validate_cache_put(keyword()) :: {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate_cache_put(opts) do
    NimbleOptions.validate(opts, @cache_put_schema)
  end

  @doc """
  Validates cache_put options and raises on error.
  """
  @spec validate_cache_put!(keyword()) :: keyword()
  def validate_cache_put!(opts) do
    NimbleOptions.validate!(opts, @cache_put_schema)
  end

  @doc """
  Validates cache_evict options.
  """
  @spec validate_cache_evict(keyword()) :: {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate_cache_evict(opts) do
    with {:ok, validated} <- NimbleOptions.validate(opts, @cache_evict_schema) do
      validate_cache_evict_constraints(validated)
    end
  end

  @doc """
  Validates cache_evict options and raises on error.
  """
  @spec validate_cache_evict!(keyword()) :: keyword()
  def validate_cache_evict!(opts) do
    case validate_cache_evict(opts) do
      {:ok, validated} -> validated
      {:error, error} -> raise error
    end
  end

  defp validate_cache_evict_constraints(opts) do
    keys = opts[:keys]
    match = opts[:match]
    tags = opts[:tags]
    all_entries = opts[:all_entries]

    has_keys = is_list(keys) and length(keys) > 0
    has_match = not is_nil(match)
    has_tags = not is_nil(tags)
    has_all = all_entries == true

    if has_keys or has_match or has_tags or has_all do
      {:ok, opts}
    else
      {:error,
       NimbleOptions.ValidationError.exception(
         "cache_evict requires at least one of: keys (non-empty list), match (pattern), tags, or all_entries: true"
       )}
    end
  end

  @doc """
  Returns the schema documentation for cacheable decorator.
  """
  @spec docs() :: String.t()
  def docs do
    NimbleOptions.docs(@cacheable_schema)
  end

  @doc """
  Returns the schema documentation for cache_put decorator.
  """
  @spec cache_put_docs() :: String.t()
  def cache_put_docs do
    NimbleOptions.docs(@cache_put_schema)
  end

  @doc """
  Returns the schema documentation for cache_evict decorator.
  """
  @spec cache_evict_docs() :: String.t()
  def cache_evict_docs do
    NimbleOptions.docs(@cache_evict_schema)
  end

  # ============================================
  # Nested Validation Helpers
  # ============================================

  defp validate_nested(opts, schema, _key) do
    NimbleOptions.validate(opts, schema)
  end

  defp validate_optional_nested(nil, _schema, _key), do: {:ok, nil}

  defp validate_optional_nested(opts, schema, _key) when is_list(opts) do
    NimbleOptions.validate(opts, schema)
  end

  defp validate_thunder_herd_option(nil), do: {:ok, nil}
  defp validate_thunder_herd_option(false), do: {:ok, false}
  defp validate_thunder_herd_option(true), do: {:ok, true}

  defp validate_thunder_herd_option(opts) when is_list(opts) do
    NimbleOptions.validate(opts, @thunder_herd_schema)
  end

  # ============================================
  # Constraint Validation
  # ============================================

  defp validate_constraints(opts) do
    with :ok <- validate_stale_ttl_constraint(opts),
         :ok <- validate_refresh_constraint(opts),
         :ok <- validate_thunder_herd_constraint(opts),
         :ok <- validate_fallback_constraint(opts) do
      {:ok, opts}
    end
  end

  defp validate_stale_ttl_constraint(opts) do
    store = opts[:store] || []
    serve_stale = opts[:serve_stale]
    store_ttl = store[:ttl]
    stale_ttl = if serve_stale, do: serve_stale[:ttl], else: nil

    cond do
      is_nil(stale_ttl) ->
        :ok

      stale_ttl <= store_ttl ->
        {:error,
         NimbleOptions.ValidationError.exception(
           "serve_stale.ttl (#{format_duration(stale_ttl)}) must be greater than store.ttl (#{format_duration(store_ttl)})"
         )}

      true ->
        :ok
    end
  end

  defp validate_refresh_constraint(opts) do
    refresh = opts[:refresh]
    serve_stale = opts[:serve_stale]

    triggers = if refresh, do: List.wrap(refresh[:on]), else: []
    has_stale_access = :stale_access in triggers
    has_serve_stale = not is_nil(serve_stale)

    if has_stale_access and not has_serve_stale do
      {:error,
       NimbleOptions.ValidationError.exception(
         "refresh.on: :stale_access requires serve_stale to be configured"
       )}
    else
      :ok
    end
  end

  defp validate_thunder_herd_constraint(opts) do
    case opts[:prevent_thunder_herd] do
      nil -> :ok
      false -> :ok
      true -> :ok

      thunder_herd when is_list(thunder_herd) ->
        max_wait = thunder_herd[:max_wait] || 5_000
        lock_ttl = thunder_herd[:lock_ttl] || 30_000
        on_timeout = thunder_herd[:on_timeout] || :serve_stale
        serve_stale = opts[:serve_stale]

        cond do
          lock_ttl < max_wait ->
            {:error,
             NimbleOptions.ValidationError.exception(
               "prevent_thunder_herd.lock_ttl (#{format_duration(lock_ttl)}) should be >= max_wait (#{format_duration(max_wait)}) to prevent duplicate fetches"
             )}

          on_timeout == :serve_stale and is_nil(serve_stale) ->
            {:error,
             NimbleOptions.ValidationError.exception(
               "prevent_thunder_herd.on_timeout: :serve_stale requires serve_stale to be configured"
             )}

          true ->
            :ok
        end
    end
  end

  defp validate_fallback_constraint(opts) do
    fallback = opts[:fallback]
    serve_stale = opts[:serve_stale]

    on_error = if fallback, do: fallback[:on_error], else: nil

    if on_error == :serve_stale and is_nil(serve_stale) do
      {:error,
       NimbleOptions.ValidationError.exception(
         "fallback.on_error: :serve_stale requires serve_stale to be configured"
       )}
    else
      :ok
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms >= 86_400_000 -> "#{div(ms, 86_400_000)}d"
      ms >= 3_600_000 -> "#{div(ms, 3_600_000)}h"
      ms >= 60_000 -> "#{div(ms, 60_000)}m"
      ms >= 1_000 -> "#{div(ms, 1_000)}s"
      true -> "#{ms}ms"
    end
  end
end
