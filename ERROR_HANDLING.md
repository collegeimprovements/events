# Comprehensive Error Handling Layer

## Overview

This document describes the complete error handling system built for consistent error normalization, context enrichment, storage, and formatting across the Events application.

## Design Goals

1. **Consistency**: All errors normalized to a standard format regardless of source
2. **Rich Context**: Capture debugging information (user, request, application, temporal)
3. **Storage**: Store errors for analytics, debugging, and resolution tracking
4. **Composability**: Works seamlessly with existing decorator system
5. **Type Safety**: Comprehensive typespecs throughout
6. **Performance**: Efficient fingerprinting and deduplication

## Architecture

```
lib/events/normalizers/
├── error/
│   ├── error.ex              # Standard error struct ✅
│   ├── codes.ex              # Error code registry ✅
│   ├── normalizer.ex         # Main normalization interface ✅
│   ├── context.ex            # Context enrichment ✅
│   ├── storage.ex            # Database storage ✅
│   └── mappers/              # Source-specific mappers
│       ├── ecto.ex           # Ecto errors ✅
│       ├── posix.ex          # File system errors ✅
│       ├── http.ex           # HTTP errors ✅
│       ├── aws.ex            # AWS/ExAws errors ✅
│       ├── stripe.ex         # Stripe payment errors ✅
│       ├── graphql.ex        # GraphQL/Absinthe errors ✅
│       └── business.ex       # Domain/business logic errors ✅
└── result.ex                 # Result type helpers ✅
```

## Core Components

### 1. Error Struct (`Events.Normalizers.Error`)

The canonical error format used throughout the application.

**Fields:**
- `type` - Error category (`:validation`, `:not_found`, `:unauthorized`, etc.)
- `code` - Specific error code (atom or string)
- `message` - Human-readable error message
- `details` - Additional context (map)
- `source` - Original error source module/system
- `stacktrace` - Optional stacktrace for debugging
- `metadata` - Enriched context (user, request, application, temporal)

**Error Types:**
- `:validation` - Input validation failures
- `:not_found` - Resource not found
- `:unauthorized` - Authentication required
- `:forbidden` - Permission denied
- `:conflict` - Resource conflicts
- `:internal` - Internal server errors
- `:external` - External service errors
- `:timeout` - Operation timeouts
- `:rate_limit` - Rate limiting
- `:bad_request` - Malformed requests
- `:unprocessable` - Business rule violations
- `:service_unavailable` - Service unavailable
- `:network` - Network errors
- `:configuration` - Configuration errors
- `:unknown` - Unknown errors

### 2. Error Normalizer (`Events.Normalizers.Error.Normalizer`)

Main interface for normalizing any error into the standard format.

**Key Functions:**
```elixir
# Normalize any error
Normalizer.normalize({:error, :not_found})
Normalizer.normalize(%Ecto.Changeset{valid?: false})
Normalizer.normalize(%Stripe.Error{})

# Normalize result tuples
{:ok, user} |> Normalizer.normalize_result()  # Passes through
{:error, reason} |> Normalizer.normalize_result()  # Normalizes error

# Pipeline-friendly normalization
value |> Normalizer.normalize_pipe()

# Wrap function calls
Normalizer.wrap(fn -> risky_operation() end)
```

### 3. Error Mappers

Source-specific mappers that handle normalization from different error sources.

#### Ecto Mapper (`Events.Normalizers.Error.Mappers.Ecto`)
- Ecto.Changeset validation errors
- Ecto.NoResultsError
- Ecto.MultipleResultsError
- Database constraint violations (unique, foreign_key, check, exclusion)

#### POSIX Mapper (`Events.Normalizers.Error.Mappers.Posix`)
- File system errors (`:enoent`, `:eacces`, `:eisdir`, etc.)
- 20+ POSIX error codes mapped to appropriate types

#### HTTP Mapper (`Events.Normalizers.Error.Mappers.Http`)
- HTTP status codes (4xx, 5xx)
- Transport/connection errors (timeout, connection refused, DNS, etc.)
- Req client errors

#### AWS Mapper (`Events.Normalizers.Error.Mappers.Aws`)
- S3 errors (NoSuchKey, AccessDenied, BucketNotEmpty, etc.)
- DynamoDB errors
- SQS errors
- SNS errors
- General AWS errors (Throttling, ExpiredToken, etc.)

#### Stripe Mapper (`Events.Normalizers.Error.Mappers.Stripe`)
- Card errors (declined, insufficient funds, expired, etc.)
- Processing errors
- API errors (rate_limit, authentication, etc.)
- Payment intent errors
- Webhook errors

#### GraphQL Mapper (`Events.Normalizers.Error.Mappers.Graphql`)
- Absinthe/GraphQL query errors
- Validation and parsing errors
- Field resolution errors
- Intelligent message pattern matching
- Bidirectional conversion (Error ↔ Absinthe format)

#### Business Mapper (`Events.Normalizers.Error.Mappers.Business`)
- Domain-specific errors
- Account & balance errors (insufficient_balance, account_suspended)
- Subscription & billing errors (subscription_expired, trial_expired)
- Quota & limits (quota_exceeded, storage_limit_exceeded)
- Workflow & state (invalid_state_transition, concurrent_modification)
- Inventory & stock (out_of_stock, reservation_expired)
- Geographic restrictions (region_restricted, country_blocked)
- 40+ predefined business error codes

### 4. Context Enrichment (`Events.Normalizers.Error.Context`)

Enriches errors with contextual information for debugging and analytics.

**Context Types:**

**User Context:**
```elixir
Context.enrich_user(error,
  user_id: 123,
  urm_id: "uuid",
  role: :admin,
  tenant_id: 456
)
```

**Request Context:**
```elixir
Context.enrich_request(error,
  request_id: "req_123",
  ip_address: "192.168.1.1",
  user_agent: "...",
  operation: "createUser"
)
```

**Application Context:**
```elixir
Context.enrich_application(error,
  module: MyApp.Users,
  function: {:create_user, 1},
  environment: :production,
  release: "1.2.3"
)
```

**Temporal Context:**
```elixir
Context.enrich_temporal(error,
  timestamp: DateTime.utc_now(),
  processing_time_ms: 1500,
  retry_attempt: 2
)
```

**All-in-one:**
```elixir
Context.enrich(error,
  user: [user_id: 123],
  request: [request_id: "req_123"],
  application: [module: __MODULE__],
  temporal: [retry_attempt: 1]
)
```

**Automatic Helpers:**
```elixir
error
|> Context.capture_caller()     # Auto-capture module/function/line
|> Context.with_environment()   # Auto-add env, node, hostname
|> Context.with_timestamp()     # Auto-add timestamp
|> Context.with_retry(2, 3)     # Track retry attempts
```

### 5. Error Storage (`Events.Normalizers.Error.Storage`)

Database persistence for errors with deduplication and analytics.

**Schema Fields:**
- `error_type`, `code`, `message`, `source` - Error identification
- `error_details`, `metadata` - JSONB fields for flexible data
- `stacktrace` - Full stacktrace (text)
- `fingerprint` - SHA256 hash for grouping similar errors
- `count` - Occurrence count for this fingerprint
- `first_seen_at`, `last_seen_at` - Temporal tracking
- `resolved_at`, `resolved_by_urm_id` - Resolution tracking
- Standard audit fields from `events_schema`

**Key Features:**

**Automatic Deduplication:**
```elixir
# First occurrence - creates new record
Storage.store(error)  # count: 1

# Same error again - increments count
Storage.store(error)  # count: 2

# Different error - creates new record
Storage.store(other_error)  # count: 1
```

**Fingerprinting:**
Errors are fingerprinted based on:
- Error type
- Error code
- Source
- Message pattern (with dynamic parts normalized)

Dynamic parts removed: UUIDs, numbers, timestamps → stable fingerprint for grouping.

**Async Storage:**
```elixir
# Fire and forget (logs on failure)
Storage.store_async(error)
```

**Querying:**
```elixir
# Get by ID
Storage.get(error_id)

# Get by fingerprint
Storage.get_by_fingerprint(fingerprint)

# List with filters
Storage.list(
  type: :validation,
  resolved: false,
  limit: 10
)

# Recent errors
Storage.get_recent(hours: 24)
Storage.get_recent(minutes: 30, type: :validation)

# Analytics - group by field
Storage.group_by(:type)
#=> %{validation: 42, not_found: 18, ...}

Storage.group_by(:code, filters: [type: :validation])
#=> %{invalid_email: 15, required_field: 8, ...}

# Mark as resolved
Storage.resolve(error_id, resolved_by: urm_id)
```

### 6. Result Helpers (`Events.Normalizers.Result`)

Functional helpers for working with result tuples inspired by Rust's Result type.

**Transformation:**
```elixir
{:ok, 5} |> Result.map(&(&1 * 2))  #=> {:ok, 10}
{:error, :not_found} |> Result.map_error(&Normalizer.normalize/1)
```

**Chaining:**
```elixir
{:ok, email}
|> Result.and_then(&find_user_by_email/1)
|> Result.and_then(&send_welcome_email/1)
|> Result.map(&format_response/1)
|> Result.map_error(&Normalizer.normalize/1)
```

**Error Recovery:**
```elixir
{:error, :not_found}
|> Result.or_else(fn _ -> {:ok, default_user()} end)
```

**Unwrapping:**
```elixir
Result.unwrap!({:ok, 42})  #=> 42
Result.unwrap_or({:error, :oops}, 0)  #=> 0
Result.unwrap_or_else({:error, :oops}, fn _ -> 0 end)  #=> 0
```

**Collections:**
```elixir
# Collect list of results
Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])
#=> {:ok, [1, 2, 3]}

# Map and collect (short-circuits on error)
Result.traverse([1, 2, 3], fn x -> {:ok, x * 2} end)
#=> {:ok, [2, 4, 6]}
```

**Inspection:**
```elixir
{:ok, user}
|> Result.tap(&IO.inspect/1)  # Side effect, returns result unchanged
|> Result.map(&format/1)

{:error, reason}
|> Result.tap_error(&Logger.error("Error: #{inspect(&1)}"))
|> Result.or_else(&recover/1)
```

## Database Schema

**Table: `errors`**

```sql
CREATE TABLE errors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),

  -- Error identification
  error_type VARCHAR NOT NULL,
  code VARCHAR NOT NULL,
  message TEXT NOT NULL,
  source VARCHAR,

  -- Error details
  error_details JSONB DEFAULT '{}',
  metadata JSONB DEFAULT '{}',
  stacktrace TEXT,

  -- Grouping & analytics
  fingerprint VARCHAR UNIQUE NOT NULL,
  count INTEGER DEFAULT 1 NOT NULL,
  first_seen_at TIMESTAMP NOT NULL,
  last_seen_at TIMESTAMP NOT NULL,

  -- Resolution
  resolved_at TIMESTAMP,
  resolved_by_urm_id UUID,

  -- Standard audit fields
  type VARCHAR,
  subtype VARCHAR,
  created_by_urm_id UUID,
  updated_by_urm_id UUID,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Indexes for efficient querying
CREATE INDEX ON errors (error_type);
CREATE INDEX ON errors (code);
CREATE INDEX ON errors (source);
CREATE INDEX ON errors (fingerprint);
CREATE INDEX ON errors (resolved_at);
CREATE INDEX ON errors (last_seen_at);
CREATE INDEX ON errors (first_seen_at);

-- Composite indexes
CREATE INDEX ON errors (error_type, code);
CREATE INDEX ON errors (error_type, resolved_at);
CREATE INDEX ON errors (source, error_type);

-- GIN indexes for JSONB
CREATE INDEX ON errors USING GIN (error_details);
CREATE INDEX ON errors USING GIN (metadata);

-- Unique constraint for deduplication
CREATE UNIQUE INDEX ON errors (fingerprint);
```

## Usage Examples

### Basic Error Normalization

```elixir
# Normalize various error types
Normalizer.normalize({:error, :not_found})
#=> %Error{type: :not_found, code: :not_found, message: "Resource not found"}

Normalizer.normalize(%Ecto.Changeset{valid?: false})
#=> %Error{type: :validation, code: :changeset_invalid, details: %{errors: [...]}}

Normalizer.normalize({:error, %Stripe.Error{code: :card_declined}})
#=> %Error{type: :unprocessable, code: :card_declined, source: :stripe}
```

### GraphQL Resolver with Full Context

```elixir
defmodule MyAppWeb.Resolvers.Users do
  alias Events.Normalizers.Error.{Normalizer, Context, Storage}
  alias Events.Normalizers.Result

  def create_user(_parent, args, resolution) do
    result =
      args
      |> Accounts.create_user()
      |> Result.map_error(fn error ->
        error
        |> Normalizer.normalize()
        |> Context.enrich(
          user: [
            urm_id: get_current_urm_id(resolution),
            role: get_current_role(resolution)
          ],
          request: [
            request_id: get_request_id(resolution),
            ip_address: get_ip(resolution),
            operation: "createUser"
          ],
          application: [
            module: __MODULE__,
            function: {:create_user, 3},
            environment: Mix.env()
          ]
        )
        |> Context.with_timestamp()
        |> tap(&Storage.store_async(&1, created_by_urm_id: get_current_urm_id(resolution)))
      end)

    case result do
      {:ok, user} -> {:ok, user}
      {:error, error} ->
        # Convert to Absinthe format
        {:error, Mappers.Graphql.to_absinthe(error)}
    end
  end
end
```

### Phoenix Controller with Error Handling

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  alias Events.Normalizers.Error.{Normalizer, Context, Storage}

  def create(conn, params) do
    request_id = Logger.metadata()[:request_id]

    result =
      params
      |> Accounts.create_user()
      |> Normalizer.normalize_result()

    case result do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> render(:show, user: user)

      {:error, error} ->
        enriched_error =
          error
          |> Context.enrich(
            user: [urm_id: conn.assigns[:current_urm_id]],
            request: [
              request_id: request_id,
              ip_address: to_string(:inet.ntoa(conn.remote_ip)),
              path: conn.request_path,
              method: conn.method
            ]
          )
          |> Context.with_timestamp()

        Storage.store_async(enriched_error)

        conn
        |> put_status(status_code_for_error(error))
        |> json(Error.to_map(enriched_error))
    end
  end

  defp status_code_for_error(%{type: :validation}), do: 422
  defp status_code_for_error(%{type: :not_found}), do: 404
  defp status_code_for_error(%{type: :unauthorized}), do: 401
  defp status_code_for_error(%{type: :forbidden}), do: 403
  defp status_code_for_error(%{type: :conflict}), do: 409
  defp status_code_for_error(_), do: 500
end
```

### Business Logic with Custom Errors

```elixir
defmodule MyApp.Accounts do
  alias Events.Normalizers.Error.Mappers.Business

  def withdraw(user, amount) do
    cond do
      user.balance < amount ->
        {:error,
         Business.normalize(:insufficient_balance,
           message: "Insufficient balance to complete withdrawal",
           details: %{current: user.balance, required: amount}
         )}

      user.account_status == :suspended ->
        {:error, Business.normalize(:account_suspended)}

      user.daily_withdrawal + amount > user.daily_limit ->
        {:error,
         Business.normalize(:quota_exceeded,
           message: "Daily withdrawal limit exceeded",
           details: %{
             current: user.daily_withdrawal,
             limit: user.daily_limit,
             attempted: amount
           }
         )}

      true ->
        # Perform withdrawal
        {:ok, updated_user}
    end
  end
end
```

### Retry with Error Context

```elixir
defmodule MyApp.Workers.EmailWorker do
  alias Events.Normalizers.Error.{Normalizer, Context, Storage}

  def perform(args, max_retries \\ 3) do
    do_perform(args, 0, max_retries)
  end

  defp do_perform(args, attempt, max_retries) when attempt < max_retries do
    case send_email(args) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        error =
          reason
          |> Normalizer.normalize()
          |> Context.enrich(
            temporal: [
              retry_attempt: attempt + 1,
              total_retries: max_retries
            ],
            application: [
              module: __MODULE__,
              function: {:perform, 2}
            ]
          )
          |> Context.with_timestamp()

        Storage.store_async(error)

        # Exponential backoff
        :timer.sleep(:math.pow(2, attempt) * 1000)

        do_perform(args, attempt + 1, max_retries)
    end
  end

  defp do_perform(_args, attempt, max_retries) do
    {:error, :max_retries_exceeded}
  end
end
```

### Error Analytics Dashboard

```elixir
defmodule MyAppWeb.Admin.ErrorsController do
  use MyAppWeb, :controller

  alias Events.Normalizers.Error.Storage

  def index(conn, params) do
    # Overview stats
    total_errors = Storage.group_by(:error_type)
    by_source = Storage.group_by(:source)
    unresolved = Storage.list(resolved: false, limit: 100)
    recent = Storage.get_recent(hours: 24)

    # Top errors by occurrence
    top_errors =
      Storage.list(order_by: :count, limit: 10)

    render(conn, :index,
      total_errors: total_errors,
      by_source: by_source,
      unresolved: unresolved,
      recent: recent,
      top_errors: top_errors
    )
  end

  def show(conn, %{"id" => id}) do
    error = Storage.get(id)
    similar = Storage.get_by_fingerprint(error.fingerprint)

    render(conn, :show, error: error, similar: similar)
  end

  def resolve(conn, %{"id" => id}) do
    urm_id = conn.assigns[:current_urm_id]

    case Storage.resolve(id, resolved_by: urm_id) do
      {:ok, error} ->
        conn
        |> put_flash(:info, "Error marked as resolved")
        |> redirect(to: ~p"/admin/errors/#{error}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to resolve error")
        |> redirect(to: ~p"/admin/errors/#{id}")
    end
  end
end
```

## Integration with Decorators

The error system integrates seamlessly with the existing decorator system:

```elixir
defmodule MyApp.Services.PaymentService do
  use Events.Decorator

  alias Events.Normalizers.Error.{Normalizer, Context, Storage}

  @decorate telemetry_span([:app, :payment, :process])
  @decorate log_call(level: :info)
  @decorate measure(unit: :millisecond)
  def process_payment(user, amount) do
    Stripe.Charge.create(%{
      amount: amount,
      currency: "usd",
      customer: user.stripe_customer_id
    })
    |> case do
      {:ok, charge} ->
        {:ok, charge}

      {:error, stripe_error} ->
        error =
          stripe_error
          |> Normalizer.normalize()
          |> Context.enrich(
            user: [user_id: user.id, urm_id: user.urm_id],
            application: [module: __MODULE__, function: {:process_payment, 2}]
          )
          |> Context.with_timestamp()

        Storage.store_async(error)

        {:error, error}
    end
  end
end
```

## Best Practices

### 1. Always Normalize Errors at Boundaries

```elixir
# ✅ Good: Normalize at controller/resolver boundary
def create_user(conn, params) do
  params
  |> Accounts.create_user()
  |> Normalizer.normalize_result()
  |> handle_result(conn)
end

# ❌ Bad: Let raw errors bubble up
def create_user(conn, params) do
  case Accounts.create_user(params) do
    {:ok, user} -> ...
    {:error, changeset} -> ...  # Raw changeset exposed
  end
end
```

### 2. Enrich Errors with Context

```elixir
# ✅ Good: Rich context for debugging
error
|> Context.enrich(user: [...], request: [...], application: [...])
|> Context.with_timestamp()
|> Storage.store()

# ❌ Bad: No context
Storage.store(error)
```

### 3. Store Errors Asynchronously

```elixir
# ✅ Good: Non-blocking
Storage.store_async(error)

# ⚠️  Use sync only when needed
Storage.store(error)
```

### 4. Use Result Helpers for Composition

```elixir
# ✅ Good: Functional composition
email
|> Result.ok()
|> Result.and_then(&find_user/1)
|> Result.and_then(&send_email/1)
|> Result.map_error(&Normalizer.normalize/1)

# ❌ Bad: Nested case statements
case find_user(email) do
  {:ok, user} ->
    case send_email(user) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  {:error, reason} -> {:error, reason}
end
```

### 5. Define Custom Business Errors

```elixir
# ✅ Good: Explicit error definitions
defmodule MyApp.Accounts.Errors do
  alias Events.Normalizers.Error.Mappers.Business

  def insufficient_balance(current, required) do
    Business.normalize(:insufficient_balance,
      message: "Insufficient balance",
      details: %{current: current, required: required}
    )
  end
end

# Use in business logic
def withdraw(user, amount) do
  if user.balance < amount do
    {:error, Errors.insufficient_balance(user.balance, amount)}
  else
    # perform withdrawal
  end
end
```

## Configuration

```elixir
# config/config.exs
config :events, :error_storage,
  enabled: true,
  async: true,
  retention_days: 90

# Disable in test
# config/test.exs
config :events, :error_storage,
  enabled: false
```

## Migration

To use error storage, run the migration:

```bash
mix ecto.migrate
```

## Benefits

1. **Consistency**: All errors follow the same structure
2. **Debuggability**: Rich context makes debugging production issues easy
3. **Analytics**: Track error patterns, frequencies, and trends
4. **Resolution Tracking**: Mark errors as resolved, track who resolved them
5. **Deduplication**: Automatic grouping of similar errors
6. **Performance**: Async storage, efficient indexing
7. **Type Safety**: Comprehensive typespecs throughout
8. **Composability**: Works with decorators, Result helpers, pipelines
9. **Flexibility**: Easy to add new error mappers
10. **Production Ready**: Battle-tested patterns from real-world applications

## Future Enhancements

- [ ] Error rate alerts (via telemetry)
- [ ] Error clustering (ML-based)
- [ ] Automatic error assignment to team members
- [ ] Integration with external error tracking (Sentry, DataDog, etc.)
- [ ] Error playbooks (automated resolution suggestions)
- [ ] A/B testing impact on error rates
- [ ] User-facing error messages (i18n support)
- [ ] Error trend analysis and predictions

---

**Status**: ✅ Production Ready

**Last Updated**: 2025-01-12
