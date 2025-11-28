# Claude Code Instructions for Events Project

## Required Reading

**IMPORTANT:** Before working on this codebase, you MUST follow these guidelines:

1. **`docs/development/AGENTS.md`** - Project conventions, code style, and patterns (READ FIRST)
2. **`docs/EVENTS_REFERENCE.md`** - Schema, Migration, and Decorator macro reference

The AGENTS.md file contains critical guidelines including:
- Pattern matching over conditionals (no `if...else`)
- Result tuples (`{:ok, result} | {:error, reason}`) for all fallible functions
- Token pattern for pipelines
- Soft delete conventions
- Phoenix/LiveView best practices
- Type decorators usage

---

## Schema and Migration Guidelines

**IMPORTANT:** This project has custom Schema and Migration macro systems that extend Ecto. Always use these instead of raw Ecto when available.

### Reference Documentation

Before creating or modifying schemas, migrations, or adding decorators, review:
- `docs/EVENTS_REFERENCE.md` - Complete reference with examples for Schema, Migration, and Decorator systems

### Schema Rules

1. **Always use `Events.Schema` instead of `Ecto.Schema`:**
   ```elixir
   # CORRECT
   use Events.Schema

   # WRONG - Don't use raw Ecto.Schema
   use Ecto.Schema
   ```

2. **Use field group macros for standard fields:**
   ```elixir
   schema "users" do
     # Custom fields first
     field :name, :string, required: true

     # Then field groups
     type_fields()
     status_fields(values: [:active, :inactive], default: :active)
     audit_fields()
     timestamps()
   end
   ```

3. **Use presets for common field patterns:**
   ```elixir
   import Events.Schema.Presets

   field :email, :string, email()
   field :username, :string, username()
   field :password, :string, password()
   ```

4. **Use validation options directly on fields:**
   ```elixir
   field :age, :integer, required: true, positive: true, max: 150
   field :email, :string, required: true, format: :email, mappers: [:trim, :downcase]
   ```

5. **Use `base_changeset/3` instead of manual cast/validate_required:**
   ```elixir
   def changeset(user, attrs) do
     user
     |> base_changeset(attrs)
     |> unique_constraints([{:email, []}])
   end
   ```

### Migration Rules

1. **Always use `Events.Migration` instead of `Ecto.Migration`:**
   ```elixir
   # CORRECT
   use Events.Migration

   # WRONG - Don't use raw Ecto.Migration
   use Ecto.Migration
   ```

2. **Use the pipeline pattern for table creation:**
   ```elixir
   def change do
     create_table(:users)
     |> with_uuid_primary_key()
     |> with_identity(:name, :email)
     |> with_audit()
     |> with_soft_delete()
     |> with_timestamps()
     |> execute()
   end
   ```

3. **Use DSL Enhanced macros inside create blocks:**
   ```elixir
   create table(:products, primary_key: false) do
     uuid_primary_key()
     type_fields()
     status_fields()
     metadata_field()
     timestamps(type: :utc_datetime_usec)
   end
   ```

4. **Use field builder helpers:**
   - `with_uuid_primary_key()` - UUIDv7 primary key
   - `with_type_fields()` - Type/subtype classification
   - `with_status_fields()` - Status tracking
   - `with_audit()` - Audit fields (created_by, updated_by)
   - `with_soft_delete()` - Soft delete support
   - `with_timestamps()` - inserted_at/updated_at
   - `with_metadata()` - JSONB metadata field

### When to Fall Back to Raw Ecto

Only use raw Ecto functions when:
1. The Events macros don't support a specific feature
2. You need very custom behavior not covered by the system
3. You're working with legacy code that hasn't been migrated

Even then, prefer extending the Events system over bypassing it.

### Quick Reference

**Schema Presets:** `email()`, `username()`, `password()`, `phone()`, `url()`, `slug()`, `money()`, `percentage()`, `age()`, `rating()`, `latitude()`, `longitude()`

**Field Groups:** `type_fields()`, `status_fields()`, `audit_fields()`, `timestamps()`, `metadata_field()`, `soft_delete_field()`, `standard_fields()`

**Migration Pipelines:** `with_uuid_primary_key()`, `with_identity()`, `with_authentication()`, `with_profile()`, `with_type_fields()`, `with_status_fields()`, `with_metadata()`, `with_tags()`, `with_audit()`, `with_soft_delete()`, `with_timestamps()`

**Mappers:** `:trim`, `:downcase`, `:upcase`, `:capitalize`, `:titlecase`, `:squish`, `:slugify`, `:digits_only`, `:alphanumeric_only`

---

## Decorator System

This project has a comprehensive decorator system for cross-cutting concerns. **Always use decorators** for type contracts, caching, telemetry, validation, and security instead of implementing these patterns manually.

See `docs/EVENTS_REFERENCE.md` for complete decorator documentation with all options and examples.

### Getting Started

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:my_app, :users, :get])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

### Decorator Best Practices

1. **Always use type decorators** - Every fallible function should declare its return type contract
2. **Stack decorators** for comprehensive behavior:
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom)
   @decorate telemetry_span([:app, :users, :create])
   @decorate validate_schema(schema: UserSchema)
   def create_user(params), do: ...
   ```
3. **Use `normalize_result/1`** for external APIs that don't follow result tuple pattern
4. **Add telemetry spans** to all public API functions
5. **Use caching decorators** instead of manual caching logic
6. **Apply security decorators** to all protected endpoints

### Quick Decorator Reference

| Category | Decorators |
|----------|-----------|
| **Types** | `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `normalize_result` |
| **Caching** | `cacheable`, `cache_put`, `cache_evict` |
| **Telemetry** | `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `log_query`, `capture_errors`, `measure`, `benchmark`, `track_memory` |
| **Validation** | `validate_schema`, `coerce_types`, `serialize`, `contract` |
| **Security** | `role_required`, `rate_limit`, `audit_log` |
| **Debugging** | `debug`, `inspect`, `pry` (dev only) |
| **Purity** | `pure`, `deterministic`, `idempotent`, `memoizable` |

---

## S3 API Guidelines

**IMPORTANT:** This project has a clean, unified S3 API at `Events.Services.S3`. Always use this module instead of raw ExAws or other S3 libraries.

### Module Location

- `Events.Services.S3` - Main API (use this)
- `Events.Services.S3.Config` - Configuration
- `Events.Services.S3.Client` - Low-level HTTP client (internal)
- `Events.Services.S3.Request` - Pipeline builder (internal)
- `Events.Services.S3.URI` - URI utilities

### Two API Styles

#### 1. Direct API (config as last argument)

```elixir
alias Events.Services.S3

config = S3.config(access_key_id: "...", secret_access_key: "...")

# Basic operations
:ok = S3.put("s3://bucket/file.txt", "content", config)
{:ok, data} = S3.get("s3://bucket/file.txt", config)
:ok = S3.delete("s3://bucket/file.txt", config)
true = S3.exists?("s3://bucket/file.txt", config)

# Presigned URLs
{:ok, url} = S3.presign("s3://bucket/file.pdf", config)
{:ok, url} = S3.presign_put("s3://bucket/upload.jpg", config, expires_in: {5, :minutes})
```

#### 2. Pipeline API (chainable, config first)

```elixir
alias Events.Services.S3

# Upload with metadata
S3.new(config)
|> S3.bucket("my-bucket")
|> S3.prefix("uploads/2024/")
|> S3.content_type("image/jpeg")
|> S3.metadata(%{user_id: "123"})
|> S3.put("photo.jpg", jpeg_data)

# From environment variables
S3.from_env()
|> S3.expires_in({5, :minutes})
|> S3.presign("s3://bucket/file.pdf")

# Batch operations with concurrency
S3.new(config)
|> S3.bucket("my-bucket")
|> S3.concurrency(10)
|> S3.put_all([{"a.txt", "content"}, {"b.txt", "content"}])
```

### S3 URIs

All operations accept `s3://bucket/key` URIs:

```elixir
"s3://my-bucket/path/to/file.txt"   # Full path
"s3://my-bucket/prefix/"             # For listing
"s3://my-bucket"                     # Bucket root
```

### Configuration

```elixir
# From environment (reads AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, etc.)
S3.from_env()

# Manual configuration
S3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)

# With proxy
S3.config(
  access_key_id: "...",
  secret_access_key: "...",
  proxy: {"proxy.example.com", 8080}
)

# LocalStack / MinIO
S3.config(
  access_key_id: "test",
  secret_access_key: "test",
  endpoint: "http://localhost:4566"
)
```

### Core Operations

| Function | Description |
|----------|-------------|
| `put/3-4` | Upload content |
| `get/2` | Download content |
| `delete/2` | Delete object |
| `exists?/2` | Check existence |
| `head/2` | Get metadata |
| `list/2-3` | List objects (paginated) |
| `list_all/3` | List all objects (handles pagination) |
| `copy/3` | Copy within S3 |
| `presign/2-3` | Generate presigned URL |
| `presign_get/2-3` | Presigned download URL |
| `presign_put/2-3` | Presigned upload URL |

### Batch Operations

All batch operations support glob patterns and parallel execution:

```elixir
# Upload multiple files
S3.put_all([{"a.txt", "..."}, {"b.txt", "..."}], config, to: "s3://bucket/")

# Download with globs
S3.get_all(["s3://bucket/*.pdf"], config)

# Delete with patterns
S3.delete_all(["s3://bucket/temp/*.tmp"], config)

# Copy with glob
S3.copy_all("s3://source/*.jpg", config, to: "s3://dest/")

# Presign multiple
S3.presign_all(["s3://bucket/*.pdf"], config, expires_in: {1, :hour})
```

### File Name Normalization

```elixir
S3.normalize_key("User's Photo (1).jpg")
#=> "users-photo-1.jpg"

S3.normalize_key("report.pdf", prefix: "docs", timestamp: true)
#=> "docs/report-20240115-143022.pdf"

S3.normalize_key("file.txt", uuid: true)
#=> "file-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt"
```

### Quick Reference

**Pipeline Setters:** `bucket/2`, `prefix/2`, `content_type/2`, `metadata/2`, `acl/2`, `storage_class/2`, `expires_in/2`, `method/2`, `concurrency/2`, `timeout/2`

**Environment Variables:**
- `AWS_ACCESS_KEY_ID` - Required
- `AWS_SECRET_ACCESS_KEY` - Required
- `AWS_REGION` / `AWS_DEFAULT_REGION` - Default: "us-east-1"
- `AWS_ENDPOINT_URL_S3` / `AWS_ENDPOINT` - Custom endpoint
- `HTTP_PROXY` / `HTTPS_PROXY` - Proxy configuration
- `S3_BUCKET` - Default bucket
