defmodule OmScheduler.Plugin do
  @moduledoc """
  Behaviour for scheduler plugins.

  Plugins extend scheduler functionality with periodic tasks like
  job scheduling, execution pruning, and index maintenance.

  ## Implementing a Plugin

      defmodule MyApp.Scheduler.Plugins.MyPlugin do
        @behaviour OmScheduler.Plugin

        @impl true
        def init(opts) do
          {:ok, %{interval: opts[:interval] || 60_000}}
        end

        @impl true
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: opts[:name])
        end

        @impl true
        def validate(opts) do
          NimbleOptions.validate(opts, schema())
        end
      end

  ## Built-in Plugins

  - `OmScheduler.Plugins.Cron` - Schedules due jobs
  - `OmScheduler.Plugins.Pruner` - Cleans up old executions
  """

  @doc """
  Validates and prepares plugin configuration.

  Called before the plugin is started. Returns `{:ok, prepared_opts}` or `{:error, reason}`.
  """
  @callback prepare(keyword()) :: {:ok, keyword()} | {:error, term()}

  @doc """
  Starts the plugin process.

  Should start a GenServer or similar process.
  """
  @callback start_link(keyword()) :: GenServer.on_start()

  @doc """
  Validates plugin options.

  Called at configuration time. Returns `:ok` or `{:error, reason}`.
  """
  @callback validate(keyword()) :: :ok | {:error, term()}

  @optional_callbacks [prepare: 1, validate: 1]

  @doc """
  Returns a child spec for a plugin.

  If the plugin is a module, uses default spec.
  If it's a tuple `{Module, opts}`, passes opts to start_link.
  """
  @spec child_spec(module() | {module(), keyword()}, keyword()) :: Supervisor.child_spec()
  def child_spec(plugin, opts \\ [])

  def child_spec({module, plugin_opts}, opts) do
    merged_opts = Keyword.merge(plugin_opts, opts)

    %{
      id: module,
      start: {module, :start_link, [merged_opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def child_spec(module, opts) when is_atom(module) do
    child_spec({module, []}, opts)
  end
end
