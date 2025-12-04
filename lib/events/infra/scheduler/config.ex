defmodule Events.Infra.Scheduler.Config do
  @moduledoc """
  Configuration validation for the scheduler.

  Uses NimbleOptions for compile-time and runtime configuration validation.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        enabled: true,
        repo: Events.Core.Repo,
        store: :database,
        peer: Events.Infra.Scheduler.Peer.Postgres,
        queues: [
          default: 10,
          realtime: 20,
          maintenance: 5
        ],
        plugins: [
          Events.Infra.Scheduler.Plugins.Cron,
          {Events.Infra.Scheduler.Plugins.Pruner, max_age: {7, :days}}
        ],
        poll_interval: {1, :second}

  ## Options

  See `docs/0` for full option documentation.
  """

  @duration_units [:second, :seconds, :minute, :minutes, :hour, :hours, :day, :days]

  @doc """
  Returns the NimbleOptions schema for scheduler configuration.
  """
  def schema do
    [
      enabled: [
        type: :boolean,
        default: true,
        doc: "Enable or disable the scheduler."
      ],
      name: [
        type: :atom,
        doc: "Name for the scheduler instance. Allows multiple scheduler instances."
      ],
      repo: [
        type: :atom,
        doc: "Ecto repo module. Required when store is :database."
      ],
      store: [
        type: {:in, [:memory, :database, :auto]},
        default: :auto,
        doc: """
        Storage backend for job state.
        - `:memory` - ETS-based, suitable for development
        - `:database` - PostgreSQL-based, suitable for production
        - `:auto` - Use :database if repo is configured, otherwise :memory
        """
      ],
      peer: [
        type: {:or, [:atom, {:in, [false]}]},
        default: nil,
        doc: """
        Peer module for leader election.
        - `Events.Infra.Scheduler.Peer.Postgres` - PostgreSQL advisory lock
        - `Events.Infra.Scheduler.Peer.Global` - Erlang :global (single node)
        - `false` - Disable leader election (node won't run jobs)
        """
      ],
      queues: [
        type: {:or, [{:in, [false]}, :keyword_list]},
        default: [default: 10],
        doc: """
        Queue configurations as keyword list of {queue_name, concurrency}.
        Set to `false` to disable job processing on this node.
        """
      ],
      plugins: [
        type: {:or, [{:in, [false]}, {:list, {:or, [:atom, {:tuple, [:atom, :keyword_list]}]}}]},
        default: [],
        doc: """
        List of plugins to enable. Each plugin can be a module or {module, opts} tuple.
        Set to `false` to disable all plugins.
        """
      ],
      poll_interval: [
        type: {:or, [:pos_integer, {:tuple, [:pos_integer, :atom]}]},
        default: {1, :second},
        doc: "How often to poll for due jobs. Either milliseconds or {n, unit} tuple."
      ],
      stage_interval: [
        type: {:or, [:pos_integer, {:tuple, [:pos_integer, :atom]}]},
        default: {1, :second},
        doc: "How often to stage jobs from the store to queues."
      ],
      shutdown_grace_period: [
        type: {:or, [:pos_integer, {:tuple, [:pos_integer, :atom]}]},
        default: {15, :seconds},
        doc: "Grace period for running jobs during shutdown."
      ],
      prefix: [
        type: {:or, [:string, :atom]},
        default: "public",
        doc: "Database schema prefix for multi-tenant deployments."
      ],
      log: [
        type: {:or, [:boolean, {:in, [:debug, :info, :warning, :error]}]},
        default: :info,
        doc: "Log level for scheduler operations, or false to disable."
      ],
      testing: [
        type: {:in, [:disabled, :manual, :inline]},
        default: :disabled,
        doc: """
        Testing mode:
        - `:disabled` - Normal operation
        - `:manual` - Jobs must be manually triggered
        - `:inline` - Jobs execute synchronously in the calling process
        """
      ],
      middleware: [
        type: {:or, [{:in, [false]}, {:list, {:or, [:atom, {:tuple, [:atom, :keyword_list]}]}}]},
        default: [],
        doc: """
        List of middleware modules for job lifecycle interception.
        Each middleware can be a module or {module, opts} tuple.
        Middleware hooks: before_execute, after_execute, on_error, on_complete.
        """
      ],
      circuit_breakers: [
        type: {:or, [{:in, [false]}, :keyword_list]},
        default: [],
        doc: """
        Circuit breaker configurations as keyword list of {name, opts}.
        Each circuit breaker tracks failures and prevents cascading failures.
        Options: failure_threshold, success_threshold, reset_timeout, half_open_limit.

        Example:
          circuit_breakers: [
            external_api: [failure_threshold: 5, reset_timeout: {30, :seconds}],
            payment_gateway: [failure_threshold: 3, reset_timeout: {1, :minute}]
          ]
        """
      ],
      dead_letter: [
        type: {:or, [{:in, [false]}, :keyword_list]},
        default: [],
        doc: """
        Dead letter queue configuration.
        Stores jobs that fail after exhausting retries for later inspection/retry.

        Options:
        - enabled: Enable/disable DLQ (default: true)
        - max_age: Auto-prune entries older than this (default: {30, :days})
        - max_entries: Max entries to store (default: 10_000)
        - on_dead_letter: Callback function when job enters DLQ

        Example:
          dead_letter: [
            enabled: true,
            max_age: {30, :days},
            max_entries: 10_000,
            on_dead_letter: &MyApp.notify_dlq/1
          ]
        """
      ]
    ]
  end

  @doc """
  Validates the given configuration options.

  ## Examples

      iex> Config.validate!(enabled: true, store: :memory)
      [enabled: true, store: :memory, ...]

      iex> Config.validate!(store: :invalid)
      ** (NimbleOptions.ValidationError) ...
  """
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    opts
    |> NimbleOptions.validate!(schema())
    |> apply_defaults()
    |> validate_store_repo!()
  end

  @doc """
  Validates configuration without raising.
  """
  @spec validate(keyword()) :: {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(opts) do
    case NimbleOptions.validate(opts, schema()) do
      {:ok, validated} ->
        validated = apply_defaults(validated)

        case validate_store_repo(validated) do
          :ok -> {:ok, validated}
          {:error, _} = error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns documentation for all options.
  """
  @spec docs() :: String.t()
  def docs, do: NimbleOptions.docs(schema())

  @doc """
  Gets scheduler configuration from application environment.
  """
  @spec get() :: keyword()
  def get do
    Application.get_env(:events, Events.Infra.Scheduler, [])
  end

  @doc """
  Gets and validates scheduler configuration.
  """
  @spec get!() :: keyword()
  def get! do
    get() |> validate!()
  end

  @doc """
  Converts a duration tuple to milliseconds.

  ## Examples

      iex> Config.to_ms({5, :minutes})
      300_000

      iex> Config.to_ms(1000)
      1000
  """
  @spec to_ms(pos_integer() | {pos_integer(), atom()}) :: pos_integer()
  def to_ms(ms) when is_integer(ms) and ms > 0, do: ms
  def to_ms({n, :second}) when is_integer(n), do: n * 1_000
  def to_ms({n, :seconds}) when is_integer(n), do: n * 1_000
  def to_ms({n, :minute}) when is_integer(n), do: n * 60_000
  def to_ms({n, :minutes}) when is_integer(n), do: n * 60_000
  def to_ms({n, :hour}) when is_integer(n), do: n * 3_600_000
  def to_ms({n, :hours}) when is_integer(n), do: n * 3_600_000
  def to_ms({n, :day}) when is_integer(n), do: n * 86_400_000
  def to_ms({n, :days}) when is_integer(n), do: n * 86_400_000

  @doc """
  Returns valid duration units.
  """
  @spec duration_units() :: [atom()]
  def duration_units, do: @duration_units

  @doc """
  Validates a duration value.

  ## Examples

      iex> Config.valid_duration?({5, :minutes})
      true

      iex> Config.valid_duration?({-1, :seconds})
      false
  """
  @spec valid_duration?(term()) :: boolean()
  def valid_duration?(ms) when is_integer(ms) and ms > 0, do: true
  def valid_duration?({n, unit}) when is_integer(n) and n > 0 and unit in @duration_units, do: true
  def valid_duration?(_), do: false

  @doc """
  Calculates a cutoff DateTime by subtracting a duration from the given time.

  ## Examples

      iex> Config.subtract_duration(now, {7, :days})
      ~U[2024-01-01 00:00:00Z]

      iex> Config.subtract_duration(now, 3600_000)
      ~U[2024-01-07 23:00:00Z]
  """
  @spec subtract_duration(DateTime.t(), pos_integer() | {pos_integer(), atom()}) :: DateTime.t()
  def subtract_duration(datetime, ms) when is_integer(ms) do
    DateTime.add(datetime, -ms, :millisecond)
  end

  def subtract_duration(datetime, {n, unit}) when is_integer(n) and unit in @duration_units do
    subtract_duration(datetime, to_ms({n, unit}))
  end

  @doc """
  Checks if the given peer module indicates this node is the leader.

  Returns `true` if:
  - peer is `nil` (single node, always leader)
  - peer module's `leader?/0` returns `true`

  Returns `false` if:
  - peer is `false` (disabled, never leader)
  - peer module's `leader?/0` returns `false`

  ## Examples

      iex> Config.leader?(nil)
      true

      iex> Config.leader?(false)
      false

      iex> Config.leader?(Events.Infra.Scheduler.Peer.Postgres)
      true  # if this node holds the advisory lock
  """
  @spec leader?(atom() | false | nil) :: boolean()
  def leader?(nil), do: true
  def leader?(false), do: false
  def leader?(peer_module) when is_atom(peer_module), do: peer_module.leader?()

  @doc """
  Returns the store module based on configuration.

  ## Examples

      iex> Config.get_store_module(store: :memory)
      Events.Infra.Scheduler.Store.Memory

      iex> Config.get_store_module(store: :database)
      Events.Infra.Scheduler.Store.Database
  """
  @spec get_store_module(keyword()) :: module()
  def get_store_module(conf) do
    case Keyword.get(conf, :store) do
      :memory -> Events.Infra.Scheduler.Store.Memory
      :database -> Events.Infra.Scheduler.Store.Database
      module when is_atom(module) and not is_nil(module) -> module
      _ -> Events.Infra.Scheduler.Store.Memory
    end
  end

  @doc """
  Generates a queue producer process name.

  ## Examples

      iex> Config.producer_name(:default)
      :"Events.Infra.Scheduler.Queue.Producer.default"
  """
  @spec producer_name(atom() | String.t()) :: atom()
  def producer_name(queue) do
    :"Events.Infra.Scheduler.Queue.Producer.#{queue}"
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp apply_defaults(opts) do
    opts
    |> resolve_auto_store()
    |> apply_default_peer()
  end

  defp resolve_auto_store(opts) do
    case Keyword.get(opts, :store) do
      :auto -> Keyword.put(opts, :store, infer_store(opts))
      _ -> opts
    end
  end

  defp infer_store(opts) do
    case Keyword.has_key?(opts, :repo) do
      true -> :database
      false -> :memory
    end
  end

  defp apply_default_peer(opts) do
    case Keyword.get(opts, :peer) do
      nil -> Keyword.put(opts, :peer, default_peer_for_store(opts))
      _ -> opts
    end
  end

  defp default_peer_for_store(opts) do
    case Keyword.get(opts, :store) do
      :database -> Events.Infra.Scheduler.Peer.Postgres
      _ -> Events.Infra.Scheduler.Peer.Global
    end
  end

  defp validate_store_repo!(opts) do
    case validate_store_repo(opts) do
      :ok -> opts
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp validate_store_repo(opts) do
    case {Keyword.get(opts, :store), Keyword.get(opts, :repo)} do
      {:database, nil} -> {:error, "repo is required when store is :database"}
      _ -> :ok
    end
  end
end
