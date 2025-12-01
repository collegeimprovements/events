defmodule Events.Api.Client.Supervisor do
  @moduledoc """
  Supervisor for managing API client middleware processes.

  Provides a simple way to start and supervise circuit breakers and rate limiters
  for API clients. Each client can have its own dedicated processes.

  ## Usage

  Add to your application supervision tree:

      # In your application.ex
      children = [
        # Other children...
        {Events.Api.Client.Supervisor, clients: [
          [name: :stripe, circuit_breaker: true, rate_limiter: true],
          [name: :github, circuit_breaker: [failure_threshold: 10], rate_limiter: [bucket_size: 5000]]
        ]}
      ]

  Or start individual client supervisors:

      Events.Api.Client.Supervisor.start_link(name: :stripe, circuit_breaker: true, rate_limiter: true)

  ## Using with Clients

  Once started, clients can reference the middleware by name:

      use Events.Api.Client,
        base_url: "https://api.stripe.com",
        circuit_breaker: :stripe_circuit_breaker,
        rate_limiter: :stripe_rate_limiter

  ## Client Supervisor

  For a single API client, use `Events.Api.Client.ClientSupervisor`:

      {Events.Api.Client.ClientSupervisor, name: :stripe}

  This starts both a circuit breaker and rate limiter for that client.

  ## Dynamic Clients

  For runtime-created clients, use the registry-based approach:

      Events.Api.Client.Supervisor.start_client(:my_api, circuit_breaker: true)
      Events.Api.Client.Supervisor.stop_client(:my_api)
  """

  use Supervisor

  alias Events.Api.Client.Middleware.{CircuitBreaker, RateLimiter}

  @type client_opts :: [
          name: atom(),
          circuit_breaker: boolean() | keyword(),
          rate_limiter: boolean() | keyword()
        ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts the API client supervisor.

  ## Options

  - `:clients` - List of client configurations to start
  - `:name` - Name for this supervisor (default: `Events.Api.Client.Supervisor`)

  ## Client Options

  Each client in the `:clients` list can have:

  - `:name` - Client name (required, used as prefix for process names)
  - `:circuit_breaker` - Enable circuit breaker (true, false, or keyword opts)
  - `:rate_limiter` - Enable rate limiter (true, false, or keyword opts)

  ## Examples

      # In application.ex
      {Events.Api.Client.Supervisor, clients: [
        [name: :stripe, circuit_breaker: true, rate_limiter: true],
        [name: :github, circuit_breaker: [failure_threshold: 10]]
      ]}

      # Or with custom supervisor name
      {Events.Api.Client.Supervisor, name: MyApp.APIClients, clients: [...]}
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts middleware for a client dynamically.

  ## Examples

      Events.Api.Client.Supervisor.start_client(:my_api, circuit_breaker: true)
  """
  @spec start_client(atom(), keyword()) :: :ok | {:error, term()}
  def start_client(client_name, opts \\ []) when is_atom(client_name) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)
    client_opts = Keyword.put(opts, :name, client_name)

    children = build_children([client_opts])

    Enum.each(children, fn child_spec ->
      Supervisor.start_child(supervisor, child_spec)
    end)

    :ok
  end

  @doc """
  Stops middleware for a client.

  ## Examples

      Events.Api.Client.Supervisor.stop_client(:my_api)
  """
  @spec stop_client(atom(), keyword()) :: :ok
  def stop_client(client_name, opts \\ []) when is_atom(client_name) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)

    cb_name = circuit_breaker_name(client_name)
    rl_name = rate_limiter_name(client_name)

    Supervisor.terminate_child(supervisor, {CircuitBreaker, cb_name})
    Supervisor.delete_child(supervisor, {CircuitBreaker, cb_name})

    Supervisor.terminate_child(supervisor, {RateLimiter, rl_name})
    Supervisor.delete_child(supervisor, {RateLimiter, rl_name})

    :ok
  end

  @doc """
  Returns the circuit breaker process name for a client.

  ## Examples

      Events.Api.Client.Supervisor.circuit_breaker_name(:stripe)
      #=> :stripe_circuit_breaker
  """
  @spec circuit_breaker_name(atom()) :: atom()
  def circuit_breaker_name(client_name) do
    String.to_atom("#{client_name}_circuit_breaker")
  end

  @doc """
  Returns the rate limiter process name for a client.

  ## Examples

      Events.Api.Client.Supervisor.rate_limiter_name(:stripe)
      #=> :stripe_rate_limiter
  """
  @spec rate_limiter_name(atom()) :: atom()
  def rate_limiter_name(client_name) do
    String.to_atom("#{client_name}_rate_limiter")
  end

  @doc """
  Checks if a client's middleware is running.

  ## Examples

      Events.Api.Client.Supervisor.client_running?(:stripe)
      #=> true
  """
  @spec client_running?(atom()) :: boolean()
  def client_running?(client_name) do
    cb_running = Process.whereis(circuit_breaker_name(client_name)) != nil
    rl_running = Process.whereis(rate_limiter_name(client_name)) != nil
    cb_running or rl_running
  end

  @doc """
  Gets the status of all middleware for a client.

  ## Examples

      Events.Api.Client.Supervisor.client_status(:stripe)
      #=> %{
        circuit_breaker: %{state: :closed, failure_count: 0, ...},
        rate_limiter: %{tokens: 100, api_remaining: nil, ...}
      }
  """
  @spec client_status(atom()) :: map()
  def client_status(client_name) do
    cb_name = circuit_breaker_name(client_name)
    rl_name = rate_limiter_name(client_name)

    %{
      circuit_breaker: safe_get_state(CircuitBreaker, cb_name),
      rate_limiter: safe_get_state(RateLimiter, rl_name)
    }
  end

  defp safe_get_state(module, name) do
    if Process.whereis(name) do
      module.get_state(name)
    else
      nil
    end
  end

  # ============================================
  # Supervisor Callbacks
  # ============================================

  @impl true
  def init(opts) do
    clients = Keyword.get(opts, :clients, [])
    children = build_children(clients)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_children(clients) do
    Enum.flat_map(clients, &build_client_children/1)
  end

  defp build_client_children(opts) do
    client_name = Keyword.fetch!(opts, :name)

    children = []

    children =
      case Keyword.get(opts, :circuit_breaker) do
        nil -> children
        false -> children
        true -> [circuit_breaker_spec(client_name, []) | children]
        cb_opts when is_list(cb_opts) -> [circuit_breaker_spec(client_name, cb_opts) | children]
      end

    children =
      case Keyword.get(opts, :rate_limiter) do
        nil -> children
        false -> children
        true -> [rate_limiter_spec(client_name, []) | children]
        rl_opts when is_list(rl_opts) -> [rate_limiter_spec(client_name, rl_opts) | children]
      end

    children
  end

  defp circuit_breaker_spec(client_name, opts) do
    name = circuit_breaker_name(client_name)
    {CircuitBreaker, Keyword.put(opts, :name, name)}
  end

  defp rate_limiter_spec(client_name, opts) do
    name = rate_limiter_name(client_name)
    {RateLimiter, Keyword.put(opts, :name, name)}
  end
end

defmodule Events.Api.Client.ClientSupervisor do
  @moduledoc """
  Supervisor for a single API client's middleware.

  Use this when you want to supervise middleware for a single client
  as a unit.

  ## Usage

      # In your supervision tree
      children = [
        {Events.Api.Client.ClientSupervisor, name: :stripe},
        {Events.Api.Client.ClientSupervisor, name: :github, circuit_breaker: [failure_threshold: 10]}
      ]

  ## Options

  - `:name` - Client name (required)
  - `:circuit_breaker` - Circuit breaker options (default: enabled with defaults)
  - `:rate_limiter` - Rate limiter options (default: enabled with defaults)

  ## Process Names

  This supervisor creates processes with predictable names:

  - Circuit breaker: `{client_name}_circuit_breaker`
  - Rate limiter: `{client_name}_rate_limiter`

  ## Example with Custom Options

      {Events.Api.Client.ClientSupervisor,
        name: :stripe,
        circuit_breaker: [failure_threshold: 3, reset_timeout: 60_000],
        rate_limiter: [bucket_size: 25, refill_rate: 5]
      }
  """

  use Supervisor

  alias Events.Api.Client.Middleware.{CircuitBreaker, RateLimiter}
  alias Events.Api.Client.Supervisor, as: APISupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    client_name = Keyword.fetch!(opts, :name)
    supervisor_name = String.to_atom("#{client_name}_client_supervisor")
    Supervisor.start_link(__MODULE__, opts, name: supervisor_name)
  end

  @impl true
  def init(opts) do
    client_name = Keyword.fetch!(opts, :name)

    cb_opts = Keyword.get(opts, :circuit_breaker, [])
    rl_opts = Keyword.get(opts, :rate_limiter, [])

    children = []

    children =
      case cb_opts do
        false ->
          children

        opts_list ->
          [
            {CircuitBreaker,
             Keyword.put(opts_list, :name, APISupervisor.circuit_breaker_name(client_name))}
            | children
          ]
      end

    children =
      case rl_opts do
        false ->
          children

        opts_list ->
          [
            {RateLimiter,
             Keyword.put(opts_list, :name, APISupervisor.rate_limiter_name(client_name))}
            | children
          ]
      end

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Returns a child spec for this supervisor.
  """
  def child_spec(opts) do
    client_name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, client_name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end
end
