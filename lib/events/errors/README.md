# Events.Errors - Unified Error Handling System

A clean, well-organized error handling system with clear separation of concerns.

## Architecture

```
lib/events/errors/
├── error.ex              # Core error struct and types
├── registry.ex           # Error codes catalog
├── normalizer.ex         # Public normalization API
├── mappers.ex            # Mapper namespace
├── mappers/              # External format converters
│   ├── ecto.ex          # Ecto changesets/queries
│   ├── http.ex          # HTTP status codes
│   ├── aws.ex           # AWS service errors
│   ├── posix.ex         # File system errors
│   ├── stripe.ex        # Payment errors
│   ├── graphql.ex       # GraphQL/Absinthe
│   ├── business.ex      # Domain errors
│   └── exception.ex     # Elixir exceptions
├── enrichment/           # Context enrichment
│   └── context.ex       # Metadata enrichment
└── persistence/          # Error storage
    └── storage.ex       # Database persistence
```

## Core Concepts

### 1. Error Struct (`Events.Errors.Error`)

Standard error representation with:
- `type` - Error category (validation, not_found, etc.)
- `code` - Specific error identifier
- `message` - Human-readable message
- `details` - Additional context
- `source` - Original error source
- `stacktrace` - Debug information
- `metadata` - Request/user context

### 2. Registry (`Events.Errors.Registry`)

Centralized error codes and messages:
- 100+ predefined error codes
- 14 error types
- Fallback messages
- Easy extensibility

### 3. Normalizer (`Events.Errors.Normalizer`)

Converts external errors to standard format:
- Ecto changesets
- HTTP errors
- AWS errors
- POSIX errors
- Stripe errors
- GraphQL errors
- Business errors
- Exceptions

### 4. Mappers (`Events.Errors.Mappers.*`)

Specialized converters for each error source with deep domain knowledge.

### 5. Enrichment (`Events.Errors.Enrichment.Context`)

Adds contextual metadata:
- User context (ID, role, etc.)
- Request context (ID, path, method)
- Application context (version, environment)
- Temporal context (timestamps)

### 6. Persistence (`Events.Errors.Persistence.Storage`)

Store and query errors:
- Automatic deduplication via fingerprinting
- Query interface
- Error resolution tracking
- Analytics and grouping

## Quick Start

```elixir
# Import the main module
alias Events.Errors

# Basic normalization
Errors.normalize({:error, :not_found})
#=> %Error{type: :not_found, code: :not_found, message: "Resource not found"}

# Normalize with metadata
Errors.normalize(changeset, metadata: %{request_id: "req_123"})

# Full pipeline: normalize + enrich + store
Errors.handle(error_tuple,
  context: [
    user: [user_id: 123, role: :admin],
    request: [request_id: "req_123", path: "/api/users"]
  ],
  store: true
)
```

## Common Usage Patterns

### 1. Phoenix Controller

```elixir
def create(conn, params) do
  case Users.create_user(params) do
    {:ok, user} ->
      json(conn, user)

    {:error, changeset} ->
      error =
        changeset
        |> Errors.normalize()
        |> Errors.enrich(
          user: [user_id: conn.assigns.current_user.id],
          request: [request_id: conn.assigns.request_id, path: conn.request_path]
        )
        |> Errors.store()

      conn
      |> put_status(:unprocessable_entity)
      |> json(Errors.to_map(error))
  end
end
```

### 2. GraphQL Resolver

```elixir
def create_user(_parent, args, %{context: context}) do
  case Users.create_user(args) do
    {:ok, user} ->
      {:ok, user}

    {:error, reason} ->
      error =
        reason
        |> Errors.normalize()
        |> Errors.enrich(
          user: [user_id: context.current_user.id],
          application: [resolver: :create_user]
        )

      # GraphQL mapper converts to Absinthe format
      {:error, Events.Errors.Mappers.Graphql.to_absinthe(error)}
  end
end
```

### 3. Background Job

```elixir
def perform(%{user_id: user_id}) do
  case process_user(user_id) do
    {:ok, _result} ->
      :ok

    {:error, reason} ->
      error =
        reason
        |> Errors.normalize()
        |> Errors.enrich(
          user: [user_id: user_id],
          application: [job: :process_user, attempt: 1]
        )
        |> Errors.store()

      if Errors.retriable?(error) do
        {:error, :retry}
      else
        {:error, :failed}
      end
  end
end
```

### 4. Service Layer

```elixir
defmodule MyApp.Users do
  alias Events.Errors

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> Errors.normalize_result()
  end

  def get_user!(id) do
    Errors.wrap(fn ->
      Repo.get!(User, id)
    end)
  end
end
```

## Error Types

- **validation** - Input validation failures
- **not_found** - Resource not found
- **unauthorized** - Authentication required
- **forbidden** - Insufficient permissions
- **conflict** - Resource conflicts
- **internal** - Server errors
- **external** - Third-party service errors
- **timeout** - Operation timeouts
- **rate_limit** - Rate limiting
- **bad_request** - Malformed requests
- **unprocessable** - Cannot process
- **service_unavailable** - Service down
- **network** - Network errors
- **configuration** - Config errors
- **unknown** - Unclassified errors

## Type Checking

```elixir
error = Errors.normalize({:error, :not_found})

Errors.validation?(error)    #=> false
Errors.not_found?(error)     #=> true
Errors.unauthorized?(error)  #=> false
Errors.internal?(error)      #=> false
Errors.retriable?(error)     #=> false
```

## Querying Stored Errors

```elixir
# Get recent errors
Errors.get_recent(hours: 24)
Errors.get_recent(minutes: 30, type: :validation)

# Query with filters
Errors.Persistence.Storage.list(
  type: :validation,
  resolved: false,
  since: ~U[2024-01-01 00:00:00Z],
  limit: 50
)

# Group by field
Errors.group_by(:type)
#=> %{validation: 42, not_found: 18, ...}

Errors.group_by(:code, filters: [type: :validation])
#=> %{invalid_email: 15, required_field: 8, ...}

# Resolve errors
Errors.resolve(error_id, resolved_by: urm_id)
```

## Adding Custom Error Codes

Add to `Events.Errors.Registry`:

```elixir
@codes %{
  # ... existing codes ...
  custom: %{
    custom_error: "Custom error message",
    another_error: "Another error message"
  }
}
```

## Adding Custom Mappers

Create a new mapper in `lib/events/errors/mappers/`:

```elixir
defmodule Events.Errors.Mappers.CustomService do
  alias Events.Errors.Error

  def normalize(%CustomService.Error{} = error) do
    Error.new(:external, :custom_service_error,
      message: error.message,
      details: %{code: error.code},
      source: CustomService
    )
  end
end
```

## Migration

The errors are stored in the `errors` table:

```bash
mix ecto.migrate
```

Features:
- UUIDv7 primary keys (time-ordered)
- CITEXT for case-insensitive fields
- Automatic fingerprinting for deduplication
- JSONB for flexible metadata
- Comprehensive indexing
- Audit fields integration

## Benefits

✅ **Consistent** - Single error format across the app
✅ **Clean** - Clear separation of concerns
✅ **Extensible** - Easy to add new mappers and codes
✅ **Debuggable** - Rich context and storage
✅ **Type-safe** - Strong typing with specs
✅ **Composable** - Works in pipelines
✅ **Observable** - Query and analyze errors
✅ **Well-organized** - Easy to navigate

## API Reference

### Main Module (`Events.Errors`)

```elixir
# Core
new(type, code, opts \\ [])
validation?(error)
not_found?(error)
unauthorized?(error)
internal?(error)
retriable?(error)

# Transformation
to_tuple(error)
to_map(error)
with_metadata(error, metadata)
with_message(error, message)
with_details(error, details)

# Registry
message(type, code)
exists?(type, code)
list(type)
types()

# Normalization
normalize(error, opts \\ [])
normalize_result(result, opts \\ [])
normalize_pipe(value, opts \\ [])
wrap(fun, opts \\ [])

# Enrichment
enrich(error, context)
capture_caller(error)
with_environment(error)
with_timestamp(error)

# Persistence
store(error, opts \\ [])
store_async(error, opts \\ [])
get(id)
get_by_fingerprint(fingerprint)
get_recent(opts)
group_by(field, opts \\ [])
resolve(id, opts)

# Pipeline
handle(error, opts \\ [])
```

## Future Enhancements

- [ ] Error reporting integrations (Sentry, Rollbar)
- [ ] Error rate limiting
- [ ] Automatic error recovery strategies
- [ ] Machine learning for error classification
- [ ] Error trend analysis
- [ ] Slack/email notifications
- [ ] Error resolution workflows

## Universal Error Handler

The `Events.Errors.Handler` module provides a universal error handling function that can be used across all contexts.

### Key Features

- **Auto-detection** - Detects context (Plug.Conn, GraphQL, Worker) and formats appropriately
- **Auto-enrichment** - Extracts user, request, and application context automatically
- **Auto-logging** - Logs errors at appropriate levels
- **Auto-storage** - Stores errors with deduplication
- **Format conversion** - Returns errors in the right format for each context

### Quick Examples

#### Phoenix Controller

```elixir
def create(conn, params) do
  case Users.create_user(params) do
    {:ok, user} -> 
      json(conn, user)
    
    {:error, reason} -> 
      # Returns conn with status and JSON error
      Errors.handle_plug_error(conn, reason)
  end
end
```

#### GraphQL Resolver

```elixir
def create_user(_parent, args, %{context: context}) do
  case Users.create_user(args) do
    {:ok, user} -> {:ok, user}
    {:error, reason} -> Errors.handle_graphql_error(reason, context)
  end
end
```

#### Background Worker

```elixir
def perform(%{user_id: user_id}) do
  case process_user(user_id) do
    {:ok, _} -> :ok
    {:error, reason} -> 
      # Returns :ok or {:error, :retry} based on error type
      Errors.handle_worker_error(reason, %{user_id: user_id})
  end
end
```

#### Generic Context

```elixir
def process_data(data) do
  case risky_operation(data) do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> 
      Errors.handle_error(reason, 
        metadata: %{operation: :process_data},
        context: :service
      )
  end
end
```

### Handler Options

```elixir
Errors.handle_error(error, context, [
  format: :json,           # :json, :graphql, :tuple, :map, :error
  status: 422,             # HTTP status (for Plug.Conn only)
  store: true,             # Store in database
  log: true,               # Log the error
  log_level: :error,       # :debug, :info, :warn, :error
  context: :controller,    # :controller, :resolver, :worker, :plug
  metadata: %{},           # Additional metadata
  enrich: true             # Enrich with context
])
```

### Auto-Enrichment

The handler automatically extracts context from:

**Plug.Conn (Phoenix Controllers)**:
- User: `current_user` from assigns
- Request: request_id, path, method, remote_ip
- Application: context type, node, environment

**GraphQL (Absinthe)**:
- User: `current_user` from context
- Request: request_id, path
- Application: context type, node, environment

**Generic Context**:
- Any map/keyword list with user/request data
- Custom metadata passed in options

### Complete Example

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias Events.Errors

  # Simple usage - auto-detects everything
  def create(conn, params) do
    case Users.create_user(params) do
      {:ok, user} -> json(conn, user)
      {:error, reason} -> Errors.handle_plug_error(conn, reason)
    end
  end

  # Custom options
  def experimental_feature(conn, params) do
    case Users.experimental(params) do
      {:ok, result} -> 
        json(conn, result)
      
      {:error, reason} -> 
        # Don't store experimental feature errors
        # Log as debug instead of error
        Errors.handle_plug_error(conn, reason,
          store: false,
          log_level: :debug
        )
    end
  end

  # Catch all unexpected errors
  def action(conn, _) do
    apply(__MODULE__, action_name(conn), [conn, conn.params])
  rescue
    error -> Errors.handle_plug_error(conn, error)
  end
end
```

See `Events.Errors.Examples` module for more real-world examples.
