defmodule OmBehaviours.HealthCheck do
  @moduledoc """
  Base behaviour for health check providers.

  Health checks report the operational status of system components. Each check
  targets a specific subsystem (database, cache, external API, etc.) and returns
  a structured result that can be aggregated into an overall system health report.

  ## Design Principles

  - **Fast**: Checks should complete quickly (< 5s). Use `timeout/0` to enforce.
  - **Independent**: Each check should test one subsystem
  - **Non-Destructive**: Never modify state — read-only probes
  - **Severity-Aware**: Distinguish critical failures from degraded performance

  ## Severity Levels

  - `:critical` — System cannot function without this component (database, core service)
  - `:warning` — Degraded but functional (cache down, non-essential API unreachable)
  - `:info` — Informational checks (disk usage, queue depth)

  ## Example

      defmodule MyApp.HealthChecks.Database do
        use OmBehaviours.HealthCheck

        @impl true
        def name, do: :database

        @impl true
        def severity, do: :critical

        @impl true
        def check do
          case Ecto.Adapters.SQL.query(Repo, "SELECT 1") do
            {:ok, _} -> {:ok, %{latency_ms: 1}}
            {:error, reason} -> {:error, reason}
          end
        end
      end

      defmodule MyApp.HealthChecks.Cache do
        use OmBehaviours.HealthCheck

        @impl true
        def name, do: :cache

        @impl true
        def severity, do: :warning

        @impl true
        def check do
          key = "__health_check__"
          Cache.put(key, "ok", ttl: 1_000)

          case Cache.get(key) do
            "ok" -> {:ok, %{status: :connected}}
            _ -> {:error, :cache_unreachable}
          end
        end

        @impl true
        def timeout, do: 3_000
      end
  """

  @doc """
  Returns the health check name as an atom.

  Used for identification in health reports and logging.

  ## Examples

      def name, do: :database
      def name, do: :redis
      def name, do: :stripe_api
  """
  @callback name() :: atom()

  @doc """
  Returns the severity level of this health check.

  Determines how failures are treated in aggregated health reports.

  ## Returns

  - `:critical` — Failure means the system is unhealthy
  - `:warning` — Failure means degraded performance
  - `:info` — Informational, does not affect health status
  """
  @callback severity() :: :critical | :warning | :info

  @doc """
  Performs the health check.

  Should be a fast, non-destructive probe of the subsystem's health.

  ## Returns

  - `{:ok, details}` — Component is healthy; details is a map with diagnostic info
  - `{:error, reason}` — Component is unhealthy

  ## Examples

      def check do
        case HTTPClient.get(endpoint, timeout: 2_000) do
          {:ok, %{status: 200}} -> {:ok, %{status: :reachable}}
          {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
          {:error, reason} -> {:error, reason}
        end
      end
  """
  @callback check() :: {:ok, map()} | {:error, term()}

  @doc """
  Returns the maximum time in milliseconds this check is allowed to run.

  Optional. The default is 5 seconds.

  ## Examples

      # Quick check
      def timeout, do: 2_000

      # Slow external API
      def timeout, do: 10_000
  """
  @callback timeout() :: non_neg_integer()

  @doc """
  Sets up a module as a HealthCheck with a default timeout of 5 seconds.

  Only `name/0`, `severity/0`, and `check/0` must be implemented.

  ## Example

      defmodule MyApp.HealthChecks.ExternalApi do
        use OmBehaviours.HealthCheck

        @impl true
        def name, do: :external_api

        @impl true
        def severity, do: :warning

        @impl true
        def check do
          # ...
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour OmBehaviours.HealthCheck

      @doc false
      @impl OmBehaviours.HealthCheck
      def timeout, do: 5_000

      defoverridable timeout: 0
    end
  end

  @doc """
  Checks if a module implements the HealthCheck behaviour.

  ## Examples

      iex> OmBehaviours.HealthCheck.implements?(MyApp.HealthChecks.Database)
      true

      iex> OmBehaviours.HealthCheck.implements?(SomeOtherModule)
      false
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    OmBehaviours.implements?(module, __MODULE__)
  end

  @doc """
  Runs a health check with its configured timeout.

  Executes the check in a supervised task and enforces the timeout.
  Returns a normalized result with timing information.

  ## Parameters

  - `module` - A module implementing `OmBehaviours.HealthCheck`

  ## Returns

  - `{:ok, %{name: atom, severity: atom, status: :healthy, details: map, duration_ms: integer}}`
  - `{:ok, %{name: atom, severity: atom, status: :unhealthy, error: term, duration_ms: integer}}`
  - `{:ok, %{name: atom, severity: atom, status: :timeout, duration_ms: integer}}`

  ## Examples

      {:ok, result} = OmBehaviours.HealthCheck.run(MyApp.HealthChecks.Database)
      result.status  #=> :healthy
      result.details #=> %{latency_ms: 1}
  """
  @spec run(module()) :: {:ok, map()}
  def run(module) do
    timeout = module.timeout()
    start_time = System.monotonic_time(:millisecond)

    task = Task.async(fn -> module.check() end)

    result =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {:ok, details}} ->
          %{status: :healthy, details: details}

        {:ok, {:error, reason}} ->
          %{status: :unhealthy, error: reason}

        nil ->
          %{status: :timeout}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    {:ok,
     Map.merge(result, %{
       name: module.name(),
       severity: module.severity(),
       duration_ms: duration_ms
     })}
  end

  @doc """
  Runs multiple health checks concurrently.

  ## Parameters

  - `modules` - List of modules implementing `OmBehaviours.HealthCheck`

  ## Returns

  A list of health check results.

  ## Examples

      checks = [MyApp.HealthChecks.Database, MyApp.HealthChecks.Cache]
      results = OmBehaviours.HealthCheck.run_all(checks)
      Enum.all?(results, & &1.status == :healthy)
  """
  @spec run_all([module()]) :: [map()]
  def run_all(modules) do
    modules
    |> Enum.map(fn module ->
      Task.async(fn ->
        {:ok, result} = run(module)
        result
      end)
    end)
    |> Task.await_many(:timer.seconds(30))
  end
end
