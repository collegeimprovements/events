# Library Composition Reference

> **How libs compose together** - Protocol integration patterns, dependency injection, and cross-library interoperability.

## Architecture Overview

```
Layer 0: Foundation (zero deps)
    dag, om_behaviours, om_middleware
         ↓
Layer 1: Functional Types
    fn_types, fn_decorator, effect
         ↓
Layer 2: Data Layer
    om_schema → om_migration → om_query, om_crud
         ↓
Layer 3: Services
    om_api_client → om_stripe, om_google, om_s3, om_cache, om_pubsub
         ↓
Layer 4: Orchestration
    om_scheduler (integrates dag, fn_types, fn_decorator)
         ↓
Layer 5: Application (Events)
    Protocol implementations, config, extensions
```

---

## Composition Patterns

### 1. Protocol-Based Composition

The primary composition mechanism. Libs define protocols, implementations can live anywhere.

#### Core Protocols (FnTypes)

| Protocol | Purpose | Fallback |
|----------|---------|----------|
| `Normalizable` | Convert errors to `FnTypes.Error` | `@fallback_to_any true` |
| `Recoverable` | Determine retry strategies | `@fallback_to_any true` |
| `Identifiable` | Extract unique identifiers | `@fallback_to_any true` |

```elixir
# Any module can implement these protocols
defimpl FnTypes.Protocols.Normalizable, for: MyApp.CustomError do
  def normalize(error, opts) do
    %FnTypes.Error{
      type: :custom_error,
      message: error.message,
      details: %{code: error.code},
      context: Keyword.get(opts, :context, %{})
    }
  end
end
```

#### CRUD Protocols (OmCrud)

| Protocol | Purpose | Use Case |
|----------|---------|----------|
| `Executable` | Unified execution via `OmCrud.run/1` | Query tokens, Multi, Merge |
| `Validatable` | Pre-execution validation | Input validation |
| `Debuggable` | Introspection for debugging | Debug output |

---

### 2. Breaking Circular Dependencies

**Problem**: OmQuery and OmCrud need to work together, but neither should depend on the other.

**Solution**: Implement protocols at the application layer.

```elixir
# lib/events/data/protocols/crud_query.ex
# This file implements OmCrud protocols for OmQuery.Token

defimpl OmCrud.Executable, for: OmQuery.Token do
  alias OmQuery.Executor

  def execute(token, opts \\ []) do
    Executor.execute(token, opts)
  end
end

defimpl OmCrud.Validatable, for: OmQuery.Token do
  def validate(%OmQuery.Token{source: source, operations: ops}) do
    errors = []
    errors = if is_nil(source), do: ["source is required" | errors], else: errors
    errors = if not is_list(ops), do: ["operations must be a list" | errors], else: errors
    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end
end

defimpl OmCrud.Debuggable, for: OmQuery.Token do
  def to_debug(%OmQuery.Token{source: source, operations: ops, metadata: meta}) do
    %{type: :query, source: source, operation_count: length(ops), metadata: meta}
  end
end
```

**Result**: Seamless composition without circular dependencies.

```elixir
# This works because protocols are implemented at app layer
User
|> OmQuery.new()
|> OmQuery.filter(:active, :eq, true)
|> OmQuery.limit(10)
|> OmCrud.run()
# => {:ok, %OmQuery.Result{data: [%User{}, ...]}}
```

---

### 3. Configuration-Based Composition

All libs read defaults from application config. No magic strings in code.

```elixir
# config/config.exs
config :om_schema, default_repo: Events.Data.Repo
config :om_query, default_repo: Events.Data.Repo
config :om_crud, default_repo: Events.Data.Repo
config :fn_types, FnTypes.Retry, default_repo: Events.Data.Repo
```

**Effect**: Zero-config function calls.

```elixir
# No need to pass repo - uses configured default
OmCrud.create(User, %{name: "John"})
OmQuery.new(User) |> OmQuery.all()
```

---

### 4. Dual-Namespace Configuration (OmScheduler Pattern)

When a lib needs both app-specific and lib-specific config:

```elixir
# config/config.exs

# App-specific config in :events namespace
config :om_scheduler, app_name: :events  # Tell scheduler where to look

config :events, OmScheduler,
  enabled: true,
  repo: Events.Data.Repo,
  store: :memory,
  queues: [default: 5]

# Lib-specific config (telemetry) in :om_scheduler namespace
config :om_scheduler, OmScheduler.Telemetry,
  telemetry_prefix: [:events, :scheduler]

config :om_scheduler, OmScheduler.Workflow.Telemetry,
  telemetry_prefix: [:events, :scheduler, :workflow]
```

**Why**: Separates runtime concerns (repo, queues) from compile-time concerns (telemetry prefixes).

---

### 5. Behavior-Based Adapters

Use `OmBehaviours` for consistent adapter patterns.

```elixir
defmodule MyApp.Storage.S3Adapter do
  use OmBehaviours.Adapter

  @impl true
  def adapter_name, do: :s3

  @impl true
  def adapter_config do
    [bucket: {:env, "S3_BUCKET"}, region: {:env, "AWS_REGION"}]
  end

  def upload(path, content) do
    OmS3.put_object(path, content)
  end
end
```

---

### 6. Middleware Composition

Use `OmMiddleware` for composable processing pipelines.

```elixir
defmodule MyApp.TimingMiddleware do
  use OmMiddleware

  @impl true
  def before_execute(context) do
    {:ok, Map.put(context, :started_at, System.monotonic_time())}
  end

  @impl true
  def after_execute(result, context) do
    elapsed = System.monotonic_time() - context.started_at
    Logger.info("Operation took #{elapsed}ns")
    {:ok, result}
  end
end

# Compose middleware
OmMiddleware.wrap(
  [TimingMiddleware, LoggingMiddleware, {RateLimiter, bucket: "api"}],
  %{user_id: 123},
  fn -> expensive_operation() end
)
```

---

### 7. Decorator Extension

Extend FnDecorator with app-specific decorators.

```elixir
# lib/events/extensions/decorator/decorator.ex
defmodule Events.Extensions.Decorator do
  @moduledoc """
  Events-specific decorator extensions.

  Use `FnDecorator` for standard decorators (caching, telemetry).
  Use this module for Events-specific decorators (scheduler, workflow).
  """

  defmacro __using__(_opts) do
    quote do
      use FnDecorator
      # Import Events-specific decorators
      import Events.Extensions.Decorator.Define
    end
  end
end
```

---

## Cross-Library Integration Patterns

### OmQuery + OmCrud

```elixir
# Build query with OmQuery, execute with OmCrud
User
|> OmQuery.new()
|> OmQuery.filter(:email, :contains, "@example.com")
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.paginate(page: 1, page_size: 20)
|> OmCrud.run()
```

### OmCrud.Multi + OmQuery

```elixir
alias OmCrud.Multi

Multi.new()
|> Multi.create(:user, User, user_attrs)
|> Multi.run(:count, fn _ ->
     User
     |> OmQuery.new()
     |> OmQuery.filter(:active, :eq, true)
     |> OmQuery.count()
     |> OmCrud.run()
   end)
|> OmCrud.run()
```

### FnTypes.Pipeline + OmCrud

```elixir
alias FnTypes.Pipeline

Pipeline.new(%{params: params})
|> Pipeline.step(:validate, &validate_params/1)
|> Pipeline.step(:create_user, fn ctx ->
     OmCrud.create(User, ctx.params)
   end)
|> Pipeline.step(:create_settings, fn ctx ->
     OmCrud.create(Settings, %{user_id: ctx.create_user.id})
   end)
|> Pipeline.run()
```

### FnTypes.AsyncResult + OmCrud

```elixir
alias FnTypes.AsyncResult

# Parallel fetches
AsyncResult.parallel([
  fn -> OmCrud.fetch(User, user_id) end,
  fn -> OmCrud.fetch(Account, account_id) end,
  fn -> OmCrud.fetch(Settings, settings_id) end
])
|> AsyncResult.map(fn [user, account, settings] ->
     %{user: user, account: account, settings: settings}
   end)
```

### Decorators + OmCrud

```elixir
use FnDecorator

@decorate cacheable(Presets.database(cache: MyApp.Cache, key: {User, id}))
@decorate telemetry_span([:app, :users, :get])
def get_user(id) do
  OmCrud.fetch(User, id)
end
```

### OmScheduler.Workflow + OmCrud

```elixir
defmodule MyApp.OnboardingWorkflow do
  use Events.Extensions.Decorator, name: :user_onboarding

  @decorate step()
  def create_user(ctx) do
    OmCrud.create(User, ctx.params)
  end

  @decorate step(after: :create_user)
  def create_settings(ctx) do
    OmCrud.create(Settings, %{user_id: ctx.create_user.id})
  end

  @decorate step(after: :create_settings)
  def send_welcome(ctx) do
    Mailer.send_welcome(ctx.create_user)
  end
end
```

---

## Error Handling Composition

### Normalizable Protocol Chain

```elixir
# All errors flow through Normalizable for consistent handling
defimpl FnTypes.Protocols.Normalizable, for: Ecto.Changeset do
  def normalize(changeset, opts) do
    %FnTypes.Error{
      type: :validation_error,
      message: "Validation failed",
      details: %{errors: format_errors(changeset)},
      context: Keyword.get(opts, :context, %{})
    }
  end
end

defimpl FnTypes.Protocols.Normalizable, for: Postgrex.Error do
  def normalize(error, opts) do
    %FnTypes.Error{
      type: :database_error,
      message: error.message,
      details: %{code: error.postgres.code},
      context: Keyword.get(opts, :context, %{})
    }
  end
end
```

### Using Error Normalization

```elixir
# Option 1: Explicit normalization
def create_user(attrs) do
  OmCrud.create(User, attrs)
  |> FnTypes.Error.normalize_result()
end

# Option 2: normalize_result decorator with error_mapper
use FnDecorator

@decorate normalize_result(error_mapper: &FnTypes.Error.normalize/1)
def create_user(attrs) do
  OmCrud.create(User, attrs)
end
```

### Recoverable Protocol Chain

```elixir
# Retry strategies based on error type
defimpl FnTypes.Protocols.Recoverable, for: DBConnection.ConnectionError do
  def recoverable?(_), do: true
  def retry_strategy(_), do: {:exponential, base: 100, max: 5000, max_attempts: 3}
end

# Usage with Retry
FnTypes.Retry.execute(fn -> database_operation() end)
# Automatically uses Recoverable protocol for retry decisions
```

---

## Adding New Integrations

### Step 1: Define Protocol (if needed)

```elixir
# In your lib
defprotocol MyLib.Processable do
  @fallback_to_any true
  def process(item, opts)
end

defimpl MyLib.Processable, for: Any do
  def process(item, _opts), do: {:ok, item}
end
```

### Step 2: Implement at App Layer

```elixir
# lib/events/data/protocols/my_integration.ex
defimpl MyLib.Processable, for: OmQuery.Token do
  def process(token, opts) do
    token
    |> OmQuery.Executor.execute(opts)
    |> case do
      {:ok, result} -> {:ok, result.data}
      error -> error
    end
  end
end
```

### Step 3: Use Seamlessly

```elixir
User
|> OmQuery.new()
|> OmQuery.filter(:active, :eq, true)
|> MyLib.process()
```

---

## Telemetry Configuration Convention

All libs emit telemetry events with configurable prefixes. The Events app uses a consistent naming hierarchy.

### Telemetry Prefix Pattern

```elixir
# config/config.exs

# Base prefix for the app
config :fn_types, telemetry_prefix: [:events]

# Layer-specific prefixes follow the pattern: [:events, :layer]
config :om_schema, telemetry_prefix: [:events, :schema]
config :om_query, telemetry_prefix: [:events, :query]
config :om_crud, telemetry_prefix: [:events, :crud]
config :fn_types, FnTypes.Retry, telemetry_prefix: [:events, :retry]
config :om_kill_switch, telemetry_prefix: [:events, :kill_switch]

# Scheduler has nested components
config :om_scheduler, OmScheduler.Telemetry, telemetry_prefix: [:events, :scheduler]
config :om_scheduler, OmScheduler.Workflow.Telemetry, telemetry_prefix: [:events, :scheduler, :workflow]
config :om_scheduler, OmScheduler.Peer.Global, telemetry_prefix: [:events, :scheduler, :peer]
```

### Resulting Event Names

| Lib | Event Example |
|-----|---------------|
| OmSchema | `[:events, :schema, :changeset, :validation]` |
| OmQuery | `[:events, :query, :execute, :start]` |
| OmCrud | `[:events, :crud, :create, :stop]` |
| FnTypes.Retry | `[:events, :retry, :attempt]` |
| OmScheduler | `[:events, :scheduler, :job, :executed]` |
| Workflow | `[:events, :scheduler, :workflow, :step, :completed]` |

### Attaching Handlers

```elixir
# Attach to all events from a lib
:telemetry.attach_many("events-query-logger", [
  [:events, :query, :execute, :start],
  [:events, :query, :execute, :stop],
  [:events, :query, :execute, :exception]
], &MyApp.Telemetry.handle_event/4, nil)

# Or use a wildcard handler module
defmodule MyApp.Telemetry do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    :telemetry.attach_many("events-metrics", [
      [:events, :crud, :create, :stop],
      [:events, :crud, :update, :stop],
      [:events, :query, :execute, :stop]
    ], &__MODULE__.handle_event/4, nil)

    Supervisor.init([], strategy: :one_for_one)
  end

  def handle_event(event, measurements, metadata, _config) do
    # Log, metrics, traces, etc.
  end
end
```

### Convention Summary

| Pattern | Use |
|---------|-----|
| `[:app]` | Base prefix for the application |
| `[:app, :lib]` | Lib-specific events |
| `[:app, :lib, :submodule]` | Nested component events |
| `[:app, :lib, :action, :phase]` | Standard event naming (start/stop/exception) |

---

## OmMiddleware: When to Use

OmMiddleware and decorators serve different purposes. Here's when to use each.

### Decorators vs Middleware

| Aspect | Decorators | OmMiddleware |
|--------|------------|--------------|
| Application | Compile-time | Runtime |
| Granularity | Per-function | Per-operation |
| Configuration | Static | Dynamic |
| Use case | Cross-cutting concerns | Request/job pipelines |

### Use Decorators When

- Behavior is known at compile time
- Applied consistently to specific functions
- Need tight integration with function signature
- Want zero-config, convention-based behavior

```elixir
# Decorator: compile-time, function-level
@decorate cacheable(cache: MyCache, key: {User, id})
@decorate telemetry_span([:app, :users, :get])
def get_user(id), do: Repo.get(User, id)
```

### Use OmMiddleware When

- Middleware chain varies at runtime
- Processing jobs, requests, or messages
- Need lifecycle hooks (before/after/error/complete)
- Building reusable processing pipelines

```elixir
# Middleware: runtime, operation-level
defmodule MyApp.ApiClient do
  @middleware [
    MyApp.Middleware.Auth,
    MyApp.Middleware.RateLimit,
    MyApp.Middleware.Retry,
    MyApp.Middleware.Logging
  ]

  def call(endpoint, params) do
    OmMiddleware.wrap(@middleware, %{endpoint: endpoint}, fn ->
      HTTPClient.post(endpoint, params)
    end)
  end
end
```

### Combining Both

Decorators and middleware can work together:

```elixir
defmodule MyApp.Jobs.ProcessOrder do
  use FnDecorator

  @middleware [
    MyApp.Middleware.Timing,
    MyApp.Middleware.ErrorNormalization
  ]

  # Decorator for telemetry/caching at function level
  @decorate telemetry_span([:app, :jobs, :process_order])
  def run(order_id) do
    # Middleware for job-specific pipeline
    OmMiddleware.wrap(@middleware, %{order_id: order_id}, fn ->
      do_process_order(order_id)
    end)
  end
end
```

### OmMiddleware Integration Opportunities

**Current usage**: OmMiddleware is available but underutilized in the Events codebase.

**Potential integrations**:

1. **API Client middleware** - Auth, retry, rate limiting for external APIs
2. **Job processing** - Timing, error handling, metrics for background jobs
3. **Request pipeline** - Plug-style middleware for Phoenix controllers
4. **Workflow steps** - Wrap workflow step execution with middleware

**Example: API Client with Middleware**

```elixir
defmodule Events.Integrations.Stripe.Middleware do
  @middleware [
    Events.Middleware.Idempotency,
    Events.Middleware.StripeAuth,
    {Events.Middleware.Retry, max_attempts: 3},
    Events.Middleware.Telemetry
  ]

  def call(operation, params) do
    OmMiddleware.wrap(@middleware, %{operation: operation}, fn ->
      OmStripe.request(operation, params)
    end)
  end
end
```

---

## Proxy Configuration (OmHttp.Proxy)

All HTTP clients use `OmHttp.Proxy` for consistent proxy handling across the codebase.

### Supported Input Formats

```elixir
# URL with embedded credentials
"http://user:password@proxy.example.com:8080"

# URL without credentials
"http://proxy.example.com:8080"

# Tuple format
{"proxy.example.com", 8080}

# Tuple with separate auth
proxy: {"proxy.example.com", 8080}
proxy_auth: {"username", "password"}

# Full Mint format
{:http, "proxy.example.com", 8080, []}
```

### Application Config

Configure proxy once in your app config and all clients use it automatically:

```elixir
# config/runtime.exs

# OmApiClient (all API clients using this framework)
config :om_api_client,
  proxy: System.get_env("HTTP_PROXY"),
  proxy_auth: case {System.get_env("PROXY_USER"), System.get_env("PROXY_PASS")} do
    {nil, _} -> nil
    {_, nil} -> nil
    {user, pass} -> {user, pass}
  end

# OmStripe
config :om_stripe,
  proxy: System.get_env("HTTP_PROXY"),
  proxy_auth: {System.get_env("PROXY_USER"), System.get_env("PROXY_PASS")}

# OmS3
config :om_s3,
  proxy: System.get_env("HTTP_PROXY"),
  proxy_auth: {System.get_env("PROXY_USER"), System.get_env("PROXY_PASS")}

# Or simpler with URL-embedded credentials (parses user:pass from URL)
config :om_api_client, proxy: System.get_env("HTTP_PROXY")
config :om_stripe, proxy: System.get_env("HTTP_PROXY")
config :om_s3, proxy: System.get_env("HTTP_PROXY")
```

### Environment Variables

All HTTP clients automatically fall back to environment variables:

- `HTTPS_PROXY` / `https_proxy` (checked first)
- `HTTP_PROXY` / `http_proxy`
- `NO_PROXY` / `no_proxy` (comma-separated exclusions)

### Proxy Priority Order

| Priority | Source | Example |
|----------|--------|---------|
| 1 (highest) | Config map | `Client.new(%{proxy: "..."})` |
| 2 | Module-level | `use OmApiClient, proxy: "..."` |
| 3 | Application config | `config :om_api_client, proxy: "..."` |
| 4 (lowest) | Environment | `HTTP_PROXY=http://proxy:8080` |

### Library Support Matrix

| Lib | App Config Key | Module/Function Config | Auto Env Fallback |
|-----|----------------|------------------------|-------------------|
| `OmApiClient` | `config :om_api_client, proxy: ...` | `use OmApiClient, proxy: ...` | Yes |
| `OmStripe` | `config :om_stripe, proxy: ...` | `Config.new(proxy: ...)` | Yes |
| `OmS3` | `config :om_s3, proxy: ...` | `Config.new(proxy: ...)` | Yes |
| `OmGoogle` | — | `get_access_token(c, s, proxy: ...)` | Yes |

### Usage Examples

**OmApiClient**:
```elixir
# At module level (recommended for consistent proxy across all requests)
defmodule MyApp.Clients.Stripe do
  use OmApiClient,
    base_url: "https://api.stripe.com",
    proxy: "http://user:pass@proxy:8080"
    # Or with separate auth:
    # proxy: "http://proxy:8080",
    # proxy_auth: {"user", "pass"}
end

# Via config map (overrides module-level default)
Stripe.new(%{api_key: "sk_xxx", proxy: "http://other-proxy:8080"})

# Via builder
Stripe.new(config)
|> Request.proxy("http://proxy:8080", {"user", "pass"})

# Auto from env (no explicit config needed)
Stripe.new(%{api_key: "sk_xxx"})  # Uses HTTP_PROXY if set
```

**OmStripe**:
```elixir
# Via Config.new (explicit proxy)
config = OmStripe.Config.new(
  api_key: "sk_test_xxx",
  proxy: "http://user:pass@proxy:8080"
)

# From environment (reads app config, then HTTP_PROXY)
config = OmStripe.Config.from_env()

# App config takes precedence over env vars
# config :om_stripe, proxy: "http://internal-proxy:8080"
config = OmStripe.Config.from_env()  # Uses app config proxy
```

**OmS3**:
```elixir
# Via Config.new (explicit proxy)
config = OmS3.Config.new(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1",
  proxy: "http://user:pass@proxy:8080"
)

# From environment (reads app config, then HTTP_PROXY)
config = OmS3.Config.from_env()

# App config takes precedence over env vars
# config :om_s3, proxy: "http://internal-proxy:8080"
config = OmS3.Config.from_env()  # Uses app config proxy
```

**OmGoogle**:
```elixir
# Explicit proxy
{:ok, token} = ServiceAccount.get_access_token(creds, scopes,
  proxy: "http://user:pass@proxy:8080"
)

# Auto from env
{:ok, token} = ServiceAccount.get_access_token(creds, scopes)
```

### Direct OmHttp.Proxy Usage

For custom HTTP clients or advanced scenarios:

```elixir
alias OmHttp.Proxy

# Parse from various inputs
{:ok, config} = Proxy.parse("http://user:pass@proxy:8080")
{:ok, config} = Proxy.parse(proxy: {"proxy.com", 8080}, proxy_auth: {"user", "pass"})

# Get from environment
case Proxy.from_env() do
  {:ok, config} -> Proxy.to_req_options(config)
  :no_proxy -> []
end

# Get config with env fallback
config = Proxy.get_config(proxy: "http://proxy:8080")  # Uses explicit
config = Proxy.get_config(nil)  # Falls back to env

# Convert to Req connect_options
connect_opts = Proxy.to_req_options(config)
Req.get!(url, connect_options: connect_opts)

# Check NO_PROXY exclusions
Proxy.should_bypass?(config, "localhost")  #=> true if in no_proxy list
```

---

## Timeout Configuration

All HTTP clients support configurable timeouts with sensible defaults.

### Timeout Types

| Type | Req Option | Description |
|------|------------|-------------|
| Connect timeout | `connect_options: [timeout: ms]` | Time to establish TCP connection |
| Receive timeout | `receive_timeout: ms` | Time to receive response after connected |
| Pool timeout | `pool_timeout: ms` | Time to wait for connection pool checkout |

### Default Values

| Library | Connect Timeout | Receive Timeout | Pool Timeout | Max Retries |
|---------|-----------------|-----------------|--------------|-------------|
| `OmApiClient` | None (from config) | None (from config) | None (from config) | None (from config) |
| `OmStripe` | 30,000 ms | 60,000 ms | 5,000 ms | 3 |
| `OmS3` | 30,000 ms | 60,000 ms | 5,000 ms | 3 |
| `OmGoogle` | 30,000 ms | 60,000 ms | 5,000 ms | 3 |

**Note:** All timeout values are validated - negative or zero values will raise `ArgumentError`.

### Application Config

```elixir
# config/runtime.exs

# OmApiClient (all API clients using this framework)
config :om_api_client,
  timeout: 30_000,          # Connect timeout (ms)
  receive_timeout: 60_000,  # Receive timeout (ms)
  pool_timeout: 5_000       # Pool checkout timeout (ms)

# OmStripe
config :om_stripe,
  timeout: 30_000,
  receive_timeout: 60_000,
  pool_timeout: 5_000,
  max_retries: 3,
  proxy: System.get_env("HTTP_PROXY")

# OmS3
config :om_s3,
  timeout: 30_000,          # Alias for connect_timeout
  receive_timeout: 60_000,
  pool_timeout: 5_000,
  max_retries: 3,
  proxy: System.get_env("HTTP_PROXY")

# OmGoogle
config :om_google,
  timeout: 30_000,
  receive_timeout: 60_000,
  pool_timeout: 5_000,
  max_retries: 3,
  proxy: System.get_env("HTTP_PROXY")
```

### Timeout Priority Order

| Priority | Source | Example |
|----------|--------|---------|
| 1 (highest) | Config map/struct | `Config.new(timeout: 10_000)` |
| 2 | Module-level | `use OmApiClient, timeout: 30_000` |
| 3 (lowest) | Application config | `config :om_api_client, timeout: 30_000` |

### Library Support Matrix

| Lib | Config Key | App Config | Per-Request |
|-----|------------|------------|-------------|
| `OmApiClient` | `timeout:`, `receive_timeout:`, `pool_timeout:`, `max_retries:` | ✓ | `Request.timeout/2`, `Request.pool_timeout/2` |
| `OmStripe` | `timeout:`, `receive_timeout:`, `pool_timeout:`, `max_retries:` | ✓ | Via Config |
| `OmS3` | `timeout:` (alias), `receive_timeout:`, `pool_timeout:`, `max_retries:` | ✓ | Via Config |
| `OmGoogle` | `timeout:`, `receive_timeout:`, `pool_timeout:`, `max_retries:` | ✓ | Per-call opts |

### Usage Examples

**OmApiClient**:
```elixir
# At module level
defmodule MyApp.Clients.Api do
  use OmApiClient,
    base_url: "https://api.example.com",
    timeout: 30_000,
    receive_timeout: 60_000
end

# Via config map
Api.new(%{api_key: "xxx", timeout: 10_000})

# Per-request (overrides defaults)
Api.new(config)
|> Request.timeout(5_000)
|> Request.receive_timeout(15_000)
```

**OmStripe**:
```elixir
# Via Config (30s connect, 60s receive defaults)
config = OmStripe.Config.new(
  api_key: "sk_test_xxx",
  timeout: 15_000,           # Connect timeout
  receive_timeout: 30_000,   # Receive timeout
  max_retries: 5             # Retry attempts
)

# From environment (uses defaults)
config = OmStripe.Config.from_env()
```

**OmS3**:
```elixir
# Custom timeouts (timeout is alias for connect_timeout)
config = OmS3.Config.new(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1",
  timeout: 10_000,           # Or use :connect_timeout
  receive_timeout: 120_000   # 2 minutes for large files
)
```

**OmGoogle**:
```elixir
# Per-call timeouts
{:ok, token} = ServiceAccount.get_access_token(creds, scopes,
  timeout: 10_000,
  receive_timeout: 30_000
)
```

---

## Error Types with Protocol Support

Both OmS3 and OmGoogle provide structured error types that implement `Normalizable` and `Recoverable` protocols.

### OmS3.Error

Structured error handling for S3 operations.

```elixir
# Create from S3 response
error = OmS3.Error.from_response(403, %{"Code" => "AccessDenied", "Message" => "..."})
error.type
#=> :access_denied

# Create from raw Client errors
error = OmS3.Error.from_raw({:s3_error, 404, body})
error.type
#=> :not_found

# Check recoverability
FnTypes.Protocols.Recoverable.recoverable?(error)
#=> false (access_denied is permanent)

# Normalize to FnTypes.Error
FnTypes.Error.normalize(error)
#=> %FnTypes.Error{type: :forbidden, code: :access_denied, ...}
```

#### S3 Error Types

| Type | HTTP Status | Recoverable | Strategy |
|------|-------------|-------------|----------|
| `:access_denied` | 403 | No | fail_fast |
| `:not_found` | 404 | No | fail_fast |
| `:conflict` | 409 | No | fail_fast |
| `:request_timeout` | 408 | Yes | retry |
| `:slow_down` | 503 | Yes | retry_with_backoff |
| `:service_unavailable` | 503 | Yes | retry_with_backoff |
| `:internal_error` | 500 | Yes | retry_with_backoff |
| `:connection_error` | - | Yes | retry |
| `:invalid_request` | 400 | No | fail_fast |

### OmGoogle.Error

Structured error handling for Google API operations.

```elixir
# Create from Google API response
error = OmGoogle.Error.from_response(403, %{
  "error" => %{
    "code" => 403,
    "message" => "Permission denied",
    "status" => "PERMISSION_DENIED"
  }
})
error.type
#=> :permission_denied

# Create from OAuth2 errors
error = OmGoogle.Error.from_response(400, %{
  "error" => "invalid_grant",
  "error_description" => "Token has been expired"
})
error.type
#=> :token_expired

# Create from ServiceAccount errors
error = OmGoogle.Error.from_token_error({:token_error, 401, body})

# Check recoverability
FnTypes.Protocols.Recoverable.recoverable?(error)
#=> true (rate_limited is recoverable)

# Normalize to FnTypes.Error
FnTypes.Error.normalize(error)
#=> %FnTypes.Error{type: :forbidden, code: :permission_denied, ...}
```

#### Google Error Types

| Type | HTTP/gRPC Status | Recoverable | Strategy |
|------|------------------|-------------|----------|
| `:invalid_credentials` | - | No | fail_fast |
| `:token_expired` | 401/UNAUTHENTICATED | Yes | retry (triggers refresh) |
| `:permission_denied` | 403/PERMISSION_DENIED | No | fail_fast |
| `:not_found` | 404/NOT_FOUND | No | fail_fast |
| `:quota_exceeded` | RESOURCE_EXHAUSTED | Yes | retry_with_backoff |
| `:rate_limited` | 429 | Yes | retry_with_backoff |
| `:service_unavailable` | 503/UNAVAILABLE | Yes | retry_with_backoff |
| `:internal_error` | 500/INTERNAL | Yes | retry_with_backoff |
| `:connection_error` | - | Yes | retry |
| `:invalid_request` | 400/INVALID_ARGUMENT | No | fail_fast |

### Using Recoverable for Retry Decisions

```elixir
alias FnTypes.Protocols.Recoverable

# Check if retry makes sense
if Recoverable.recoverable?(error) do
  strategy = Recoverable.strategy(error)
  delay = Recoverable.retry_delay(error, attempt)
  max = Recoverable.max_attempts(error)

  if attempt < max do
    Process.sleep(delay)
    retry_operation()
  else
    {:error, error}
  end
else
  {:error, error}
end

# Check circuit breaker
if Recoverable.trips_circuit?(error) do
  CircuitBreaker.trip(:s3)
end
```

### Error Normalization Flow

```elixir
# Raw S3 result → OmS3.Error → FnTypes.Error
def put_object_normalized(bucket, key, content, config) do
  case OmS3.put_object(bucket, key, content, config) do
    :ok -> :ok
    {:error, reason} ->
      error = OmS3.Error.from_raw(reason)
      {:error, FnTypes.Error.normalize(error)}
  end
end

# With context
{:error, FnTypes.Error.normalize(error, context: %{bucket: bucket, key: key})}
```

---

## Best Practices

1. **Protocols over behaviors** for runtime polymorphism
2. **Behaviors over protocols** for compile-time contracts
3. **App-layer protocol implementations** to break circular deps
4. **Config-based defaults** to eliminate magic strings
5. **Dual-namespace config** when mixing runtime/compile concerns
6. **Middleware composition** for cross-cutting concerns
7. **Decorator extension** for domain-specific decorators

---

## Files Reference

| Purpose | Location |
|---------|----------|
| Protocol implementations | `lib/events/data/protocols/` |
| Decorator extensions | `lib/events/extensions/decorator/` |
| Lib configuration | `config/config.exs` |
| Runtime configuration | `config/runtime.exs` |
| Core protocols | `libs/fn_types/lib/fn_types/protocols/` |
| CRUD protocols | `libs/om_crud/lib/om_crud/` |
| Middleware base | `libs/om_middleware/lib/om_middleware.ex` |
| Proxy configuration | `libs/om_http/lib/om_http/proxy.ex` |
| S3 error types | `libs/om_s3/lib/om_s3/error.ex` |
| Google error types | `libs/om_google/lib/om_google/error.ex` |
