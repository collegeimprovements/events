# Events Application Architecture

## Overview

This document describes the modular architecture for the Events application, focusing on the service-oriented design with composable, testable modules.

## Architectural Principles

1. **Single Responsibility**: Each module does one thing well
2. **Behaviour-Based**: Define contracts via behaviours, implement via adapters
3. **Explicit Dependencies**: Pass configuration as structs, not global config
4. **Error Normalization**: Standardize errors across all modules
5. **Composability**: All modules integrate with the decorator system
6. **Testability**: Mock adapters for all external dependencies

## Terminology

- **Services**: Core business capabilities with behaviour contracts (AWS, Redis, Profiling)
- **Adapters**: Behaviour implementations (Real, Mock, Test, Local)
- **Composers**: Pipeline-based data transformation (Validation, Transactions)
- **Normalizers**: Shape transformation utilities (Error standardization)
- **Contracts**: Shared behaviour definitions

## Directory Structure

```
lib/events/
├── contracts/                        # Shared behaviour definitions
│   ├── service.ex                    # Base service behaviour ✅
│   ├── adapter.ex                    # Base adapter behaviour ✅
│   └── composer.ex                   # Base composer behaviour ✅
│
├── normalizers/                      # Shape transformers
│   ├── error/
│   │   ├── error.ex                  # Standard error struct ✅
│   │   ├── codes.ex                  # Error code registry ✅
│   │   ├── normalizer.ex             # Main normalizer ✅
│   │   └── mappers/                  # Format-specific mappers
│   │       ├── ecto.ex               # Ecto.Changeset → Error ✅
│   │       ├── posix.ex              # :file errors → Error ✅
│   │       ├── http.ex               # HTTP errors → Error ✅
│   │       └── aws.ex                # AWS errors → Error ✅
│   └── result.ex                     # Result tuple helpers ✅
│
├── services/                         # Core service layer
│   ├── aws/
│   │   ├── context.ex                # AWS context struct ✅
│   │   ├── s3.ex                     # S3 behaviour ✅
│   │   ├── s3/
│   │   │   ├── ex_aws_adapter.ex     # ExAws implementation ⏳
│   │   │   ├── mock_adapter.ex       # Mock for tests ⏳
│   │   │   └── local_adapter.ex      # Local filesystem ⏳
│   │
│   ├── profiling/
│   │   ├── profiler.ex               # Profiler behaviour ⏳
│   │   ├── report.ex                 # Profile report struct ⏳
│   │   └── profiler/
│   │       ├── eprof_adapter.ex      # :eprof implementation ⏳
│   │       ├── fprof_adapter.ex      # :fprof implementation ⏳
│   │       └── telemetry_adapter.ex  # Telemetry-based ⏳
│   │
│   └── cache/
│       ├── client.ex                 # Cache client behaviour ⏳
│       └── client/
│           ├── redis_adapter.ex      # Redis-backed cache ⏳
│           └── local_adapter.ex      # In-memory cache ⏳
│
├── composers/                        # Data transformation pipelines
│   ├── validation/
│   │   ├── composer.ex               # Main validation composer ⏳
│   │   ├── rules.ex                  # Common validation rules ⏳
│   │   ├── changeset_builder.ex      # Changeset pipeline ⏳
│   │   └── validator.ex              # Custom validator behaviour ⏳
│   │
│   └── transactions/
│       ├── composer.ex               # Multi builder ⏳
│       ├── step.ex                   # Multi step definition ⏳
│       └── builder.ex                # Fluent Multi API ⏳
│
└── (existing modules)
    ├── repo.ex
    ├── schema.ex
    ├── decorator/
    └── ...

test/events/
├── contracts/
├── normalizers/
├── services/
└── composers/
```

Legend: ✅ Completed | ⏳ Pending

## Module Details

### 1. Contracts (✅ Complete)

#### Events.Contracts.Service
Base behaviour for all service modules. Defines optional callbacks for supervised services.

#### Events.Contracts.Adapter
Base behaviour for adapter implementations. Provides adapter resolution and validation.

#### Events.Contracts.Composer
Base behaviour for composer modules. Provides `defcompose` macro for fluent APIs.

### 2. Normalizers (✅ Complete)

#### Events.Normalizers.Error
Standard error struct with rich metadata. All errors should be normalized to this format.

**Fields**:
- `type`: Error category (`:validation`, `:not_found`, etc.)
- `code`: Specific error code (atom)
- `message`: Human-readable message
- `details`: Additional context (map)
- `source`: Original error source
- `stacktrace`: Optional stacktrace
- `metadata`: Request metadata

#### Events.Normalizers.Error.Codes
Central registry for error codes and default messages. Maintains consistency across the app.

#### Events.Normalizers.Error.Normalizer
Main normalization interface. Converts any error shape into standard Error struct.

**Key Functions**:
- `normalize/2` - Normalize any error
- `normalize_result/2` - Normalize result tuples
- `normalize_pipe/2` - Pipeline-friendly normalization
- `wrap/2` - Wrap function calls with error handling

#### Error Mappers
- **Ecto**: Changeset errors, query errors, constraint violations
- **POSIX**: File system errors (`:enoent`, `:eacces`, etc.)
- **HTTP**: Status codes, transport errors
- **AWS**: ExAws errors, S3/DynamoDB/SQS/SNS errors

#### Events.Normalizers.Result
Functional helpers for result tuples inspired by Rust's Result type.

**Key Functions**:
- `map/2`, `map_error/2` - Transform values
- `and_then/2`, `or_else/2` - Chain operations
- `unwrap!/1`, `unwrap_or/2` - Extract values
- `collect/1`, `traverse/2` - Collection operations
- `combine/2`, `combine_with/3` - Combine results

### 3. Services

#### Events.Services.Aws.Context (✅ Complete)
AWS configuration context. Holds credentials, region, bucket, endpoint.

**Construction**:
- `new/1` - From keyword list
- `from_config/0` - From application config
- `from_env/0` - From environment variables

#### Events.Services.Aws.S3 (✅ Complete)
S3 storage service behaviour and public API.

**Operations**:
- `upload/4`, `get_object/2`, `delete_object/2`
- `list_objects/2` - With pagination support
- `presigned_url/4` - Generate signed URLs for upload/download
- `copy_object/3`, `head_object/2`
- `upload_file/4`, `download_to_file/3` - Filesystem helpers

**Adapters** (⏳ To Implement):
- **ExAwsAdapter**: Production implementation using ExAws
- **MockAdapter**: In-memory mock for testing
- **LocalAdapter**: Local filesystem for development

#### Events.Services.Profiling.Profiler (⏳ To Implement)
Function profiling service behaviour.

**Operations**:
- `profile/3` - Profile a function call
- `profile_async/3` - Profile async operations
- `start_profiling/2` - Start continuous profiling
- `stop_profiling/1` - Stop and get report
- `format_report/2` - Format profile report

**Adapters** (⏳ To Implement):
- **EprofAdapter**: Using `:eprof`
- **FprofAdapter**: Using `:fprof`
- **TelemetryAdapter**: Using telemetry events

#### Events.Services.Cache.Client (⏳ To Implement)
Enhanced cache client wrapping Nebulex.

**Operations**:
- `get/3`, `put/4`, `delete/2`
- `get_many/3`, `put_many/3`, `delete_many/2`
- `fetch/4` - Get or compute and cache
- `transaction/3` - Transactional operations
- `ttl/2`, `expire/3` - TTL management

**Adapters** (⏳ To Implement):
- **RedisAdapter**: Redis-backed distributed cache
- **LocalAdapter**: Wraps existing Events.Cache

### 4. Composers

#### Events.Composers.Validation.Composer (⏳ To Implement)
Chainable validation pipeline builder.

**Operations**:
- `validate_required/2` - Required field validation
- `validate_format/3` - Pattern matching
- `validate_length/3` - Length constraints
- `validate_number/3` - Numeric constraints
- `validate_inclusion/3`, `validate_exclusion/3` - Set membership
- `validate_custom/2` - Custom validator function
- `build/1` - Build final changeset

**Usage**:
```elixir
Validation.Composer.new(User, params)
|> Validation.Composer.validate_required([:email, :name])
|> Validation.Composer.validate_format(:email, ~r/@/)
|> Validation.Composer.validate_length(:name, min: 3, max: 100)
|> Validation.Composer.build()
```

#### Events.Composers.Transactions.Composer (⏳ To Implement)
Ecto.Multi builder with fluent API.

**Operations**:
- `insert/3`, `update/3`, `delete/3` - Repo operations
- `run/3` - Custom function
- `put/3` - Put value
- `merge/2` - Merge another multi
- `inspect/3` - Debug inspection
- `build/1` - Build final Ecto.Multi

**Usage**:
```elixir
Transactions.Composer.new()
|> Transactions.Composer.insert(:user, user_changeset)
|> Transactions.Composer.run(:send_email, fn %{user: user} ->
     EmailService.send_welcome(user)
   end)
|> Transactions.Composer.insert(:audit_log, fn %{user: user} ->
     AuditLog.changeset(%{action: "user_created", user_id: user.id})
   end)
|> Transactions.Composer.build()
|> Repo.transaction()
```

## Decorator Integration

All services and composers integrate with the existing decorator system:

### Caching
```elixir
@decorate cacheable(cache: Events.Cache, key: {S3, context.bucket, key})
def get_object(context, key) do
  # Implementation
end
```

### Telemetry
```elixir
@decorate telemetry_span([:events, :aws, :s3, :upload])
def upload(context, key, content, opts) do
  # Implementation
end
```

### Logging
```elixir
@decorate log_call(level: :info, label: "S3 Upload")
@decorate log_if_slow(threshold: 5000)
def upload(context, key, content, opts) do
  # Implementation
end
```

### Performance
```elixir
@decorate measure(unit: :millisecond)
@decorate track_memory()
def profile(profiler, function, opts) do
  # Implementation
end
```

## Configuration

### Application Config

```elixir
# config/config.exs
config :events, :aws,
  s3_adapter: Events.Services.Aws.S3.ExAwsAdapter,
  access_key_id: "...",
  secret_access_key: "...",
  region: "us-east-1",
  bucket: "my-bucket"

config :events, :profiling,
  adapter: Events.Services.Profiling.EprofAdapter,
  enabled: true

config :events, :cache,
  adapter: Events.Services.Cache.LocalAdapter
```

### Runtime Config

```elixir
# config/runtime.exs
config :events, :aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1"),
  bucket: System.get_env("AWS_S3_BUCKET")
```

## Testing Strategy

### Unit Tests
Each adapter has comprehensive unit tests with mocks.

```elixir
# test/events/services/aws/s3/mock_adapter_test.exs
defmodule Events.Services.Aws.S3.MockAdapterTest do
  use ExUnit.Case, async: true

  alias Events.Services.Aws.{Context, S3}
  alias Events.Services.Aws.S3.MockAdapter

  setup do
    context = Context.new(
      access_key_id: "test",
      secret_access_key: "test",
      region: "us-east-1",
      bucket: "test-bucket"
    )

    {:ok, context: context}
  end

  test "upload and get_object", %{context: context} do
    assert :ok = MockAdapter.upload(context, "test.txt", "content")
    assert {:ok, "content"} = MockAdapter.get_object(context, "test.txt")
  end
end
```

### Integration Tests
Test real adapters with sandboxed environments (LocalStack for AWS, Redis for cache).

### Decorator Tests
Verify decorator integration works correctly with all services.

## Usage Examples

### AWS S3 Service

```elixir
# Initialize context
context = Context.from_env()

# Upload file
S3.upload(context, "documents/report.pdf", file_data,
  content_type: "application/pdf",
  metadata: %{"user_id" => "123"}
)

# Generate download URL (valid for 1 hour)
{:ok, url} = S3.presigned_url(context, :get, "documents/report.pdf",
  expires_in: 3600
)

# Generate upload URL (valid for 5 minutes)
{:ok, upload_url} = S3.presigned_url(context, :put, "uploads/photo.jpg",
  expires_in: 300
)

# List files with prefix
{:ok, %{objects: files, continuation_token: token}} =
  S3.list_objects(context, prefix: "uploads/", max_keys: 100)
```

### Error Normalization

```elixir
# Normalize Ecto changeset error
User.changeset(%User{}, %{email: "invalid"})
|> Repo.insert()
|> Normalizer.normalize_result()
#=> {:error, %Error{type: :validation, code: :changeset_invalid, details: %{errors: [...]}}}

# Normalize AWS error
S3.get_object(context, "nonexistent.txt")
|> Normalizer.normalize_result()
#=> {:error, %Error{type: :not_found, code: :no_such_key, ...}}

# Chain with Result helpers
Context.from_env()
|> Result.ok()
|> Result.and_then(&S3.get_object(&1, "data.json"))
|> Result.map(&Jason.decode!/1)
|> Result.map_error(&Normalizer.normalize/1)
```

### Validation Composer

```elixir
defmodule MyApp.Users do
  alias Events.Composers.Validation.Composer, as: Validation

  def create_user(params) do
    User
    |> Validation.new(params)
    |> Validation.validate_required([:email, :name, :password])
    |> Validation.validate_format(:email, ~r/@/)
    |> Validation.validate_length(:password, min: 8)
    |> Validation.validate_custom(:email, &unique_email?/1)
    |> Validation.build()
    |> case do
      %{valid?: true} = changeset -> Repo.insert(changeset)
      changeset -> {:error, changeset}
    end
  end

  defp unique_email?(email) do
    case Repo.get_by(User, email: email) do
      nil -> :ok
      _ -> {:error, "email already taken"}
    end
  end
end
```

### Transactions Composer

```elixir
defmodule MyApp.Orders do
  alias Events.Composers.Transactions.Composer, as: Transactions

  def create_order(user_id, items) do
    Transactions.new()
    |> Transactions.insert(:order, fn _ ->
      Order.changeset(%Order{user_id: user_id})
    end)
    |> Transactions.insert(:items, fn %{order: order} ->
      Enum.map(items, &OrderItem.changeset(&1, order.id))
    end)
    |> Transactions.update(:inventory, fn %{items: items} ->
      update_inventory(items)
    end)
    |> Transactions.run(:send_email, fn %{order: order} ->
      OrderMailer.send_confirmation(order)
    end)
    |> Transactions.build()
    |> Repo.transaction()
  end
end
```

### Profiling Service

```elixir
alias Events.Services.Profiling.Profiler

# Profile a function
{:ok, report} = Profiler.profile(fn ->
  expensive_computation()
end, iterations: 100)

# Format and display
Profiler.format_report(report, format: :table)
|> IO.puts()

# Continuous profiling
{:ok, pid} = Profiler.start_profiling(MyModule, :my_function)
# ... do work ...
{:ok, report} = Profiler.stop_profiling(pid)
```

## Benefits of This Architecture

1. **Modularity**: Each module has a single, well-defined responsibility
2. **Testability**: Mock adapters make testing trivial
3. **Flexibility**: Easy to swap implementations (LocalStack, Minio, etc.)
4. **Consistency**: Standardized error handling and patterns throughout
5. **Observability**: Built-in telemetry and logging via decorators
6. **Type Safety**: Comprehensive typespecs and behaviours
7. **Developer Experience**: Clear contracts, excellent documentation
8. **Composability**: Modules work together seamlessly
9. **Production Ready**: Follows Elixir/OTP best practices

## Next Steps

1. ✅ Implement base contracts (Service, Adapter, Composer)
2. ✅ Implement error normalization layer with all mappers
3. ✅ Implement Result helpers
4. ✅ Create AWS Context and S3 behaviour
5. ⏳ Implement S3 adapters (ExAws, Mock, Local)
6. ⏳ Implement Profiling service and adapters
7. ⏳ Implement Cache client and adapters
8. ⏳ Implement Validation Composer
9. ⏳ Implement Transactions Composer
10. ⏳ Add comprehensive test coverage
11. ⏳ Create usage documentation and examples
12. ⏳ Integrate into existing application workflows

## Contributing

When adding new services or composers:

1. Define a behaviour extending the appropriate contract
2. Implement at least two adapters (real + mock)
3. Add comprehensive tests for all adapters
4. Integrate decorators for telemetry and logging
5. Normalize errors to standard Error struct
6. Document with examples and typespecs
7. Follow existing patterns and conventions
