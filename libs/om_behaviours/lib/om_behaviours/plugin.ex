defmodule OmBehaviours.Plugin do
  @moduledoc """
  Base behaviour for extension point plugins.

  Plugins provide a standardized way to extend library or application functionality
  through a lifecycle of validation, preparation, and optional supervised startup.

  ## Plugin Lifecycle

  1. **`validate/1`** — Check that configuration is valid (fail fast)
  2. **`prepare/1`** — Transform config, acquire resources, return runtime state
  3. **`start_link/1`** (optional) — Start a supervised process if needed

  ## Design Principles

  - **Validate Early**: Catch config errors at boot, not at runtime
  - **Stateless Preferred**: Prefer stateless plugins; use `start_link/1` only when state is needed
  - **Composable**: Plugins should work independently and alongside other plugins
  - **Explicit**: Plugin name and config requirements should be self-documenting

  ## Example

      defmodule MyApp.Plugins.RateLimiter do
        use OmBehaviours.Plugin

        @impl true
        def plugin_name, do: :rate_limiter

        @impl true
        def validate(opts) do
          case Keyword.fetch(opts, :max_requests) do
            {:ok, n} when is_integer(n) and n > 0 -> :ok
            _ -> {:error, ":max_requests must be a positive integer"}
          end
        end

        @impl true
        def prepare(opts) do
          {:ok, %{
            max_requests: Keyword.fetch!(opts, :max_requests),
            window_ms: Keyword.get(opts, :window_ms, 60_000)
          }}
        end
      end

      # Stateful plugin with supervised process
      defmodule MyApp.Plugins.MetricsCollector do
        use OmBehaviours.Plugin

        @impl true
        def plugin_name, do: :metrics_collector

        @impl true
        def validate(_opts), do: :ok

        @impl true
        def prepare(opts) do
          {:ok, %{interval: Keyword.get(opts, :interval, 5_000)}}
        end

        @impl true
        def start_link(state) do
          GenServer.start_link(__MODULE__, state, name: __MODULE__)
        end
      end
  """

  @doc """
  Returns the plugin name as an atom.

  Used for plugin registration, selection, and logging.

  ## Examples

      def plugin_name, do: :rate_limiter
      def plugin_name, do: :metrics_collector
  """
  @callback plugin_name() :: atom()

  @doc """
  Validates plugin configuration.

  Called at boot time to catch configuration errors early. Should return
  `:ok` if valid, or `{:error, reason}` with a descriptive message.

  ## Parameters

  - `opts` - Plugin configuration options

  ## Returns

  - `:ok` — Configuration is valid
  - `{:error, reason}` — Configuration is invalid

  ## Examples

      def validate(opts) do
        case Keyword.fetch(opts, :api_key) do
          {:ok, key} when is_binary(key) -> :ok
          _ -> {:error, ":api_key is required and must be a string"}
        end
      end
  """
  @callback validate(opts :: keyword()) :: :ok | {:error, term()}

  @doc """
  Prepares the plugin for use by transforming configuration into runtime state.

  Called after validation succeeds. Use this to build runtime config maps,
  establish connections, or acquire resources.

  ## Parameters

  - `opts` - Validated plugin configuration

  ## Returns

  - `{:ok, state}` — Plugin prepared successfully with runtime state
  - `{:error, reason}` — Preparation failed

  ## Examples

      def prepare(opts) do
        {:ok, %{
          endpoint: Keyword.fetch!(opts, :endpoint),
          timeout: Keyword.get(opts, :timeout, 5_000),
          headers: [{"Authorization", "Bearer \#{Keyword.fetch!(opts, :api_key)}"}]
        }}
      end
  """
  @callback prepare(opts :: keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Optionally starts a supervised process for stateful plugins.

  Only implement this if the plugin needs to maintain state, run background
  tasks, or manage connections. The returned pid will be supervised.

  ## Parameters

  - `state` - The runtime state returned by `prepare/1`

  ## Returns

  - `{:ok, pid}` — Process started successfully
  - `{:error, reason}` — Process failed to start
  - `:ignore` — Plugin doesn't need a process
  """
  @callback start_link(state :: term()) :: {:ok, pid()} | {:error, term()} | :ignore

  @doc """
  Sets up a module as a Plugin with a default `start_link/1` that returns `:ignore`.

  Only `plugin_name/0`, `validate/1`, and `prepare/1` must be implemented.

  ## Example

      defmodule MyApp.Plugins.Logger do
        use OmBehaviours.Plugin

        @impl true
        def plugin_name, do: :logger

        @impl true
        def validate(_opts), do: :ok

        @impl true
        def prepare(opts), do: {:ok, opts}
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour OmBehaviours.Plugin

      @doc false
      @impl OmBehaviours.Plugin
      def start_link(_state), do: :ignore

      defoverridable start_link: 1
    end
  end

  @doc """
  Checks if a module implements the Plugin behaviour.

  ## Examples

      iex> OmBehaviours.Plugin.implements?(MyApp.Plugins.RateLimiter)
      true

      iex> OmBehaviours.Plugin.implements?(SomeOtherModule)
      false
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    OmBehaviours.implements?(module, __MODULE__)
  end
end
