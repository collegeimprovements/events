# OmBehaviours

Common behaviour patterns for Elixir applications: Adapter, Service, and Builder.

## Installation

```elixir
def deps do
  [{:om_behaviours, "~> 0.1.0"}]
end
```

## Quick Start

OmBehaviours provides three foundational patterns for building well-structured Elixir applications:

| Behaviour | Purpose | Use Case |
|-----------|---------|----------|
| `Adapter` | Swappable implementations | Storage backends, API clients, payment processors |
| `Service` | Supervised services | Connection pools, background workers, stateful services |
| `Builder` | Fluent construction | Query builders, validation pipelines, multi-step configs |

## Adapter Pattern

Adapters enable swappable backend implementations. Define a service behaviour, then implement it with different adapters (S3, local file, mock, etc.).

### Defining a Storage Service

```elixir
# Define the service behaviour
defmodule MyApp.Storage do
  @callback upload(key :: String.t(), data :: binary()) :: {:ok, url :: String.t()} | {:error, term()}
  @callback download(key :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
end
```

### S3 Adapter (Production)

```elixir
defmodule MyApp.Storage.S3 do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :s3

  @impl OmBehaviours.Adapter
  def adapter_config(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      region: Keyword.get(opts, :region, "us-east-1"),
      acl: Keyword.get(opts, :acl, :private)
    }
  end

  @impl MyApp.Storage
  def upload(key, data) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    # Use ExAws or similar to upload
    case ExAws.S3.put_object(config.bucket, key, data) |> ExAws.request() do
      {:ok, _} -> {:ok, "https://#{config.bucket}.s3.amazonaws.com/#{key}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl MyApp.Storage
  def download(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    ExAws.S3.get_object(config.bucket, key) |> ExAws.request()
  end

  @impl MyApp.Storage
  def delete(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    case ExAws.S3.delete_object(config.bucket, key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Local Adapter (Development)

```elixir
defmodule MyApp.Storage.Local do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :local

  @impl OmBehaviours.Adapter
  def adapter_config(opts) do
    %{
      root_path: Keyword.get(opts, :root_path, "priv/uploads")
    }
  end

  @impl MyApp.Storage
  def upload(key, data) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    path = Path.join(config.root_path, key)
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, data) do
      :ok -> {:ok, "file://#{path}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl MyApp.Storage
  def download(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    File.read(Path.join(config.root_path, key))
  end

  @impl MyApp.Storage
  def delete(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    case File.rm(Path.join(config.root_path, key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok  # Already deleted
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Mock Adapter (Testing)

```elixir
defmodule MyApp.Storage.Mock do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :mock

  @impl OmBehaviours.Adapter
  def adapter_config(_opts), do: %{}

  @impl MyApp.Storage
  def upload(key, _data), do: {:ok, "mock://#{key}"}

  @impl MyApp.Storage
  def download(_key), do: {:ok, "mock data"}

  @impl MyApp.Storage
  def delete(_key), do: :ok
end
```

### Dynamic Adapter Resolution

```elixir
# Resolve adapter at runtime
adapter = OmBehaviours.Adapter.resolve(:s3, MyApp.Storage)
#=> MyApp.Storage.S3

adapter = OmBehaviours.Adapter.resolve(:mock, MyApp.Storage)
#=> MyApp.Storage.Mock

# Use in configuration
config :my_app, :storage,
  adapter: :s3,
  bucket: "my-bucket"

# Resolve and use
def storage_adapter do
  config = Application.get_env(:my_app, :storage)
  OmBehaviours.Adapter.resolve(config[:adapter], MyApp.Storage)
end
```

## Service Pattern

Services represent supervised business capabilities with clear boundaries.

### Basic Service

```elixir
defmodule MyApp.NotificationService do
  @behaviour OmBehaviours.Service
  use GenServer

  @impl OmBehaviours.Service
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  @impl OmBehaviours.Service
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    {:ok, %{adapter: opts[:adapter] || :email}}
  end

  # Public API
  def send_notification(user, message) do
    GenServer.call(__MODULE__, {:send, user, message})
  end

  @impl GenServer
  def handle_call({:send, user, message}, _from, state) do
    result = do_send(state.adapter, user, message)
    {:reply, result, state}
  end

  defp do_send(:email, user, message) do
    # Send email
    {:ok, :sent}
  end

  defp do_send(:sms, user, message) do
    # Send SMS
    {:ok, :sent}
  end
end
```

### Adding to Supervision Tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.NotificationService, adapter: :email}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Service with Connection Pool

```elixir
defmodule MyApp.DatabaseService do
  @behaviour OmBehaviours.Service

  @impl OmBehaviours.Service
  def child_spec(opts) do
    pool_size = Keyword.get(opts, :pool_size, 10)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl OmBehaviours.Service
  def start_link(opts) do
    children = [
      {DBConnection, pool_opts(opts)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  defp pool_opts(opts) do
    [
      pool_size: Keyword.get(opts, :pool_size, 10),
      pool_timeout: Keyword.get(opts, :pool_timeout, 5000)
    ]
  end
end
```

## Builder Pattern

Builders provide fluent APIs for constructing complex data structures.

### Query Builder Example

```elixir
defmodule MyApp.QueryBuilder do
  use OmBehaviours.Builder

  defstruct [:schema, :filters, :sorts, :limit, :offset]

  @impl true
  def new(schema, opts \\ []) do
    %__MODULE__{
      schema: schema,
      filters: [],
      sorts: [],
      limit: opts[:limit],
      offset: opts[:offset]
    }
  end

  @impl true
  def compose(builder, {:filter, field, op, value}) do
    %{builder | filters: [{field, op, value} | builder.filters]}
  end

  def compose(builder, {:sort, field, direction}) do
    %{builder | sorts: [{field, direction} | builder.sorts]}
  end

  def compose(builder, {:limit, n}) do
    %{builder | limit: n}
  end

  def compose(builder, {:offset, n}) do
    %{builder | offset: n}
  end

  @impl true
  def build(builder) do
    import Ecto.Query

    query = from(s in builder.schema)

    query = Enum.reduce(builder.filters, query, fn
      {field, :eq, value}, q -> where(q, [s], field(s, ^field) == ^value)
      {field, :gt, value}, q -> where(q, [s], field(s, ^field) > ^value)
      {field, :lt, value}, q -> where(q, [s], field(s, ^field) < ^value)
      {field, :like, value}, q -> where(q, [s], like(field(s, ^field), ^value))
    end)

    query = Enum.reduce(builder.sorts, query, fn
      {field, :asc}, q -> order_by(q, [s], asc: field(s, ^field))
      {field, :desc}, q -> order_by(q, [s], desc: field(s, ^field))
    end)

    query = if builder.limit, do: limit(query, ^builder.limit), else: query
    query = if builder.offset, do: offset(query, ^builder.offset), else: query

    query
  end

  # Fluent API using defcompose
  defcompose where(builder, field, op, value) do
    compose(builder, {:filter, field, op, value})
  end

  defcompose where_eq(builder, field, value) do
    compose(builder, {:filter, field, :eq, value})
  end

  defcompose order_by(builder, field, direction \\ :asc) do
    compose(builder, {:sort, field, direction})
  end

  defcompose limit(builder, n) do
    compose(builder, {:limit, n})
  end

  defcompose offset(builder, n) do
    compose(builder, {:offset, n})
  end
end

# Usage
query = MyApp.QueryBuilder.new(User)
|> MyApp.QueryBuilder.where_eq(:status, :active)
|> MyApp.QueryBuilder.where(:age, :gt, 18)
|> MyApp.QueryBuilder.order_by(:created_at, :desc)
|> MyApp.QueryBuilder.limit(10)
|> MyApp.QueryBuilder.build()

Repo.all(query)
```

### Validation Builder Example

```elixir
defmodule MyApp.ValidationBuilder do
  use OmBehaviours.Builder

  defstruct [:data, :rules, :errors]

  @impl true
  def new(data, _opts \\ []) do
    %__MODULE__{data: data, rules: [], errors: []}
  end

  @impl true
  def compose(builder, {:required, field}) do
    %{builder | rules: [{:required, field} | builder.rules]}
  end

  def compose(builder, {:format, field, regex}) do
    %{builder | rules: [{:format, field, regex} | builder.rules]}
  end

  def compose(builder, {:length, field, opts}) do
    %{builder | rules: [{:length, field, opts} | builder.rules]}
  end

  @impl true
  def build(%{data: data, rules: rules}) do
    errors = Enum.reduce(Enum.reverse(rules), [], fn rule, errors ->
      case validate_rule(rule, data) do
        :ok -> errors
        {:error, field, message} -> [{field, message} | errors]
      end
    end)

    case errors do
      [] -> {:ok, data}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_rule({:required, field}, data) do
    case Map.get(data, field) do
      nil -> {:error, field, "is required"}
      "" -> {:error, field, "is required"}
      _ -> :ok
    end
  end

  defp validate_rule({:format, field, regex}, data) do
    value = Map.get(data, field, "")
    if Regex.match?(regex, to_string(value)) do
      :ok
    else
      {:error, field, "has invalid format"}
    end
  end

  defp validate_rule({:length, field, opts}, data) do
    value = Map.get(data, field, "")
    len = String.length(to_string(value))
    min = Keyword.get(opts, :min, 0)
    max = Keyword.get(opts, :max, :infinity)

    cond do
      len < min -> {:error, field, "must be at least #{min} characters"}
      max != :infinity and len > max -> {:error, field, "must be at most #{max} characters"}
      true -> :ok
    end
  end

  # Fluent API
  defcompose required(builder, field) do
    compose(builder, {:required, field})
  end

  defcompose format(builder, field, regex) do
    compose(builder, {:format, field, regex})
  end

  defcompose length(builder, field, opts) do
    compose(builder, {:length, field, opts})
  end
end

# Usage
result = MyApp.ValidationBuilder.new(%{email: "test@example.com", name: "Jo"})
|> MyApp.ValidationBuilder.required(:email)
|> MyApp.ValidationBuilder.required(:name)
|> MyApp.ValidationBuilder.format(:email, ~r/@/)
|> MyApp.ValidationBuilder.length(:name, min: 3)
|> MyApp.ValidationBuilder.build()

case result do
  {:ok, data} -> create_user(data)
  {:error, errors} -> handle_errors(errors)
end
```

## Helper Functions

### Check Behaviour Implementation

```elixir
# Check if a module implements a specific behaviour
OmBehaviours.implements?(MyApp.Storage.S3, OmBehaviours.Adapter)
#=> true

OmBehaviours.implements?(MyApp.Storage.S3, OmBehaviours.Service)
#=> false

# Behaviour-specific helpers
OmBehaviours.Adapter.implements?(MyApp.Storage.S3)
#=> true

OmBehaviours.Service.implements?(MyApp.NotificationService)
#=> true

OmBehaviours.Builder.implements?(MyApp.QueryBuilder)
#=> true
```

## Design Principles

### Adapter Guidelines

- **Stateless**: Pass configuration per-call, don't store state
- **Error Handling**: Always return `{:ok, result}` or `{:error, reason}`
- **Resource Cleanup**: Handle timeouts, close connections
- **Testability**: Mock adapters should be drop-in replacements

### Service Guidelines

- **Single Responsibility**: One service, one purpose
- **Explicit Configuration**: Pass config as opts, not global config
- **Supervision Ready**: Implement `child_spec/1` for supervision trees
- **Graceful Shutdown**: Handle terminate callbacks properly

### Builder Guidelines

- **Immutable**: Each operation returns a new builder
- **Chainable**: All methods return the builder struct
- **Explicit Build**: Separate building from execution
- **Composable**: Builders can wrap other builders

## License

MIT
