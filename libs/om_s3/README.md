# OmS3

Composable S3 client for Elixir with pipeline API, batch operations, streaming, and first-class `s3://` URI support.

Works with **AWS S3** and any **S3-compatible service** (MinIO, RustFS, Cloudflare R2, DigitalOcean Spaces, Backblaze B2, Wasabi, LocalStack).

## Features

- **Dual API** - Direct function calls or chainable pipeline style
- **`s3://` URIs** - First-class URI support across all operations
- **Batch operations** - Parallel put/get/delete/copy/presign with concurrency control
- **Glob patterns** - `s3://bucket/logs/*.txt` in batch operations
- **Streaming** - Memory-efficient multipart upload and chunked download for large files
- **Structured errors** - Typed `OmS3.Error` with Recoverable/Normalizable protocols
- **Telemetry** - Automatic span events on every operation
- **Retries** - Built-in retry with `safe_transient` strategy via Req
- **Timeouts** - Three-level timeout control (connect, receive, pool)
- **Proxy** - Full HTTP proxy with NO_PROXY, env var fallback, auth
- **Presign caching** - GenServer or decorator-based URL cache with LRU eviction
- **S3-compatible** - Auto `path_style` for custom endpoints, provider-agnostic env vars

## Installation

```elixir
def deps do
  [{:om_s3, "~> 0.1.0"}]
end
```

## 1 min Setup Guide

**1. Add dependency** (`mix.exs`):

```elixir
{:om_s3, "~> 0.1.0"}
```

**2. Set environment variables** (`runtime.exs` or shell):

```bash
# Primary (checked first)
export S3_ACCESS_KEY_ID="AKIA..."
export S3_SECRET_ACCESS_KEY="..."
export S3_REGION="us-east-1"
export S3_ENDPOINT="http://localhost:9000"  # Optional: for MinIO/LocalStack/R2

# Fallback (AWS standard)
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
export AWS_ENDPOINT_URL_S3="..."            # Optional
```

**3. Configure proxy** (`config/config.exs` — optional):

```elixir
config :om_s3,
  proxy: "http://proxy:8080",                 # Or reads HTTP_PROXY env var
  proxy_auth: {"username", "password"}        # Optional
```

No supervision, no migrations. Use `OmS3.from_env()` to auto-detect credentials from env vars, or `OmS3.config(access_key_id: ..., secret_access_key: ..., region: ...)` for explicit config.

## Quick Start

```elixir
# Configure
config = OmS3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)

# Upload
:ok = OmS3.put("s3://my-bucket/hello.txt", "Hello, world!", config)

# Download
{:ok, content} = OmS3.get("s3://my-bucket/hello.txt", config)

# Check existence
true = OmS3.exists?("s3://my-bucket/hello.txt", config)

# Delete
:ok = OmS3.delete("s3://my-bucket/hello.txt", config)
```

### Pipeline API

```elixir
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.prefix("uploads/2024/")
|> OmS3.content_type("image/jpeg")
|> OmS3.metadata(%{user_id: "123"})
|> OmS3.put("photo.jpg", jpeg_data)
```

### From Environment

```elixir
# Reads S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_REGION, S3_ENDPOINT
# Falls back to AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
OmS3.from_env()
|> OmS3.bucket("my-bucket")
|> OmS3.get("file.txt")
```

---

## Configuration

### AWS S3

```elixir
config = OmS3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)
```

### S3-Compatible Services

```elixir
# MinIO / RustFS / LocalStack - just set endpoint
# path_style is auto-detected for custom endpoints
config = OmS3.config(
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin",
  endpoint: "http://localhost:9000",
  region: "us-east-1"
)

# Cloudflare R2
config = OmS3.config(
  access_key_id: "...",
  secret_access_key: "...",
  endpoint: "https://ACCOUNT_ID.r2.cloudflarestorage.com",
  region: "auto"
)

# DigitalOcean Spaces
config = OmS3.config(
  access_key_id: "...",
  secret_access_key: "...",
  endpoint: "https://nyc3.digitaloceanspaces.com",
  region: "nyc3"
)
```

When `endpoint` is set, `path_style` automatically defaults to `true` (required by most non-AWS providers). Override with `path_style: false` if your provider supports virtual-hosted-style.

### All Config Options

| Option | Default | Description |
|--------|---------|-------------|
| `access_key_id` | *required* | Access key |
| `secret_access_key` | *required* | Secret key |
| `region` | `"us-east-1"` | AWS region or provider region |
| `endpoint` | `nil` | Custom endpoint URL |
| `path_style` | auto | `true` for custom endpoints, `false` for AWS |
| `connect_timeout` | `30_000` | TCP connection timeout (ms) |
| `receive_timeout` | `60_000` | Response timeout (ms) |
| `pool_timeout` | `5_000` | Connection pool checkout timeout (ms) |
| `max_retries` | `3` | Retry attempts for transient failures |
| `proxy` | `nil` | `{host, port}`, `{:http, h, p, []}`, or URL string |
| `proxy_auth` | `nil` | `{username, password}` |
| `no_proxy` | `[]` | Hostnames/patterns to bypass proxy |
| `transfer_acceleration` | `false` | AWS Transfer Acceleration (AWS-only) |

### Environment Variables

| Variable | Fallback | Description |
|----------|----------|-------------|
| `S3_ACCESS_KEY_ID` | `AWS_ACCESS_KEY_ID` | Access key |
| `S3_SECRET_ACCESS_KEY` | `AWS_SECRET_ACCESS_KEY` | Secret key |
| `S3_REGION` | `AWS_REGION`, `AWS_DEFAULT_REGION` | Region |
| `S3_ENDPOINT` | `AWS_ENDPOINT_URL_S3`, `AWS_ENDPOINT` | Custom endpoint |
| `HTTP_PROXY` | `HTTPS_PROXY` | Proxy URL |
| `NO_PROXY` | - | Comma-separated bypass patterns |

### Proxy

```elixir
# Tuple
OmS3.config(proxy: {"proxy.company.com", 8080}, proxy_auth: {"user", "pass"}, ...)

# URL with embedded credentials
OmS3.config(proxy: "http://user:pass@proxy.company.com:8080", ...)

# From environment (automatic fallback if no explicit proxy)
# HTTP_PROXY=http://proxy:8080 NO_PROXY=localhost,.internal.com
```

---

## Core Operations

### Upload

```elixir
# Simple
:ok = OmS3.put("s3://bucket/file.txt", "content", config)

# With options
:ok = OmS3.put("s3://bucket/photo.jpg", data, config,
  content_type: "image/jpeg",
  metadata: %{user_id: "123"},
  acl: "public-read",
  storage_class: "STANDARD"
)

# Pipeline
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.content_type("text/plain")
|> OmS3.put("file.txt", "hello")
```

### Download

```elixir
{:ok, binary} = OmS3.get("s3://bucket/file.txt", config)
```

### Delete

```elixir
# Idempotent - succeeds even if object doesn't exist
:ok = OmS3.delete("s3://bucket/file.txt", config)
```

### Head (Metadata)

```elixir
{:ok, %{size: 1024, content_type: "text/plain", etag: "abc", last_modified: dt, metadata: %{}}} =
  OmS3.head("s3://bucket/file.txt", config)
```

### Exists

```elixir
true = OmS3.exists?("s3://bucket/file.txt", config)
false = OmS3.exists?("s3://bucket/nope.txt", config)
```

### Copy

```elixir
:ok = OmS3.copy("s3://src-bucket/a.txt", "s3://dst-bucket/b.txt", config)
```

### List

```elixir
# Single page
{:ok, %{files: files, next: token}} = OmS3.list("s3://bucket/prefix/", config)

# All pages (auto-paginates)
{:ok, all_files} = OmS3.list_all("s3://bucket/prefix/", config)

# With options
{:ok, result} = OmS3.list("s3://bucket/prefix/", config,
  limit: 100,
  sort: :key,
  order: :asc
)
```

---

## Batch Operations

All batch operations run in parallel with configurable concurrency and support glob patterns.

```elixir
# Upload multiple
results = OmS3.put_all([{"a.txt", "..."}, {"b.txt", "..."}], config,
  to: "s3://bucket/uploads/",
  concurrency: 10,
  timeout: 120_000
)

# Download with globs
results = OmS3.get_all(["s3://bucket/docs/*.pdf"], config)

# Delete with globs
results = OmS3.delete_all(["s3://bucket/temp/*.tmp"], config)

# Copy with glob pattern
results = OmS3.copy_all("s3://source/*.jpg", config, to: "s3://dest/images/")

# Presign multiple
results = OmS3.presign_all(["s3://bucket/*.pdf"], config, expires_in: {1, :hour})
```

### Pipeline Batch

```elixir
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.prefix("photos/")
|> OmS3.concurrency(10)
|> OmS3.timeout({2, :minutes})
|> OmS3.put_all([{"a.jpg", data1}, {"b.jpg", data2}])
```

### Result Analysis

```elixir
alias OmS3.BatchResult

results = OmS3.put_all(files, config, to: "s3://bucket/")

BatchResult.all_succeeded?(results)     #=> true/false
BatchResult.any_failed?(results)        #=> true/false

summary = BatchResult.summarize(results)
summary.total         #=> 100
summary.succeeded     #=> 95
summary.failed        #=> 5
summary.success_rate  #=> 0.95

# Categorize failures
BatchResult.recoverable_failures(results)  # transient - worth retrying
BatchResult.permanent_failures(results)    # access_denied, not_found, etc.

# Retry transient failures
BatchResult.retry_failures(results, fn uri, _reason ->
  OmS3.put(uri, get_content(uri), config)
end, max_attempts: 3, delay: 100)

# Strict mode - raise if anything failed
BatchResult.raise_on_failure!(results)
```

---

## Presigned URLs

```elixir
# Download URL (GET)
{:ok, url} = OmS3.presign_get("s3://bucket/file.pdf", config)
{:ok, url} = OmS3.presign_get("s3://bucket/file.pdf", config, expires_in: {5, :minutes})

# Upload form (POST, for browser direct uploads)
{:ok, %{url: url, fields: fields}} = OmS3.presign_put("s3://bucket/upload.jpg", config)

# Pipeline
{:ok, url} = OmS3.new(config)
|> OmS3.expires_in({1, :hour})
|> OmS3.presign("s3://bucket/file.pdf")

# Batch presign with globs
results = OmS3.presign_all(["s3://bucket/docs/*.pdf"], config, expires_in: {1, :hour})
```

### Duration Formats

```elixir
{5, :minutes}    # Tuple format
{1, :hour}
{7, :days}
3600             # Seconds (integer)
```

### Presign Cache

Prevent regeneration storms with cached presigned URLs:

```elixir
# Add to supervision tree
children = [{OmS3.PresignCache, name: MyApp.S3PresignCache}]

# Use - returns cached URL or generates new one
{:ok, url} = OmS3.PresignCache.get_or_generate(
  MyApp.S3PresignCache,
  "s3://bucket/file.pdf",
  config,
  expires_in: {1, :hour}
)

# Cache stats
OmS3.PresignCache.stats(MyApp.S3PresignCache)
#=> %{entries: 150, hits: 1000, misses: 50, hit_rate: 0.95}

# Invalidate
OmS3.PresignCache.invalidate(MyApp.S3PresignCache, "s3://bucket/file.pdf")

# With @cacheable decorator
@decorate cacheable(OmS3.PresignCache.preset(
  cache: MyApp.Cache,
  key: {:presign, uri},
  expires_in: {1, :hour}
))
def download_url(uri), do: OmS3.presign(uri, config())
```

---

## Streaming (Large Files)

Memory-efficient operations for files too large to hold in memory.

```elixir
alias OmS3.Stream, as: S3Stream

# Download to file
:ok = S3Stream.download_to_file("s3://bucket/large.zip", "/tmp/large.zip", config)

# Download as Elixir Stream
S3Stream.download("s3://bucket/large.zip", config)
|> Stream.into(File.stream!("/tmp/output.zip"))
|> Stream.run()

# Download with callback (progress tracking)
S3Stream.download_with_callback("s3://bucket/file.zip", config, fn chunk ->
  bytes = byte_size(chunk)
  send(self(), {:progress, bytes})
end)

# Upload from file (multipart)
:ok = S3Stream.upload_file("/path/to/large.zip", "s3://bucket/large.zip", config)

# Upload from stream
File.stream!("/path/to/large.zip", [], 5_242_880)
|> S3Stream.upload("s3://bucket/large.zip", config,
  content_type: "application/zip",
  metadata: %{source: "upload"}
)
```

Streaming automatically:
- Chunks downloads using HTTP Range requests (5MB default)
- Uses S3 multipart upload for uploads (5MB minimum part size)
- Aborts multipart uploads on failure (no orphaned parts)
- Raises `OmS3.StreamError` on failure (caught by `download_to_file`/`download_with_callback`)

---

## Error Handling

All operations return `{:ok, result}` or `{:error, %OmS3.Error{}}` with structured error types:

```elixir
case OmS3.get("s3://bucket/file.txt", config) do
  {:ok, content} ->
    process(content)

  {:error, %OmS3.Error{type: :not_found}} ->
    :missing

  {:error, %OmS3.Error{type: :access_denied, message: msg}} ->
    Logger.error("Access denied: #{msg}")

  {:error, %OmS3.Error{} = error} ->
    if FnTypes.Protocols.Recoverable.recoverable?(error) do
      retry_later()
    else
      {:error, error.type}
    end
end
```

### Error Types

| Type | HTTP | Recoverable | Description |
|------|------|-------------|-------------|
| `:not_found` | 404 | No | Object/bucket doesn't exist |
| `:access_denied` | 403 | No | Insufficient permissions |
| `:invalid_request` | 400 | No | Malformed request |
| `:conflict` | 409 | No | Concurrent modification |
| `:precondition_failed` | 412 | No | ETag mismatch |
| `:request_timeout` | 408 | Yes | Request took too long |
| `:connection_error` | - | Yes | Network/DNS/TLS failure |
| `:slow_down` | 503 | Yes | Rate limiting/throttling |
| `:service_unavailable` | 503 | Yes | S3 temporarily down |
| `:internal_error` | 500 | Yes | S3 internal error |

### FnTypes Protocol Integration

```elixir
# Normalize to FnTypes.Error
fn_error = FnTypes.Protocols.Normalizable.normalize(s3_error)

# Recovery strategy
FnTypes.Protocols.Recoverable.strategy(error)       #=> :retry_with_backoff
FnTypes.Protocols.Recoverable.retry_delay(error, 1)  #=> 500 (ms, with jitter)
FnTypes.Protocols.Recoverable.max_attempts(error)    #=> 3
FnTypes.Protocols.Recoverable.severity(error)        #=> :transient | :degraded | :permanent
FnTypes.Protocols.Recoverable.trips_circuit?(error)  #=> true (for :service_unavailable)
```

---

## Telemetry

All Client operations emit telemetry events automatically:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:om_s3, :request, :start]` | `system_time` | `operation`, `bucket`, `key` |
| `[:om_s3, :request, :stop]` | `duration` | `operation`, `bucket`, `key`, `status` |
| `[:om_s3, :request, :exception]` | `duration` | `operation`, `bucket`, `key`, `kind`, `reason` |
| `[:om_s3, :batch, :start]` | `system_time`, `count` | `operation` |
| `[:om_s3, :batch, :stop]` | `duration`, `succeeded`, `failed` | `operation` |

### Built-in Logger

```elixir
# Attach default logger (logs all ops, warns on slow ops > 5s)
OmS3.Telemetry.attach_default_logger(level: :info, log_slow_threshold: 5_000)
```

### Custom Metrics

```elixir
:telemetry.attach_many("s3-metrics",
  [[:om_s3, :request, :stop], [:om_s3, :request, :exception]],
  &MyApp.handle_s3_event/4,
  nil
)
```

---

## URI Utilities

```elixir
# Build / parse
OmS3.uri("bucket", "path/file.txt")      #=> "s3://bucket/path/file.txt"
OmS3.parse_uri("s3://bucket/file.txt")   #=> {:ok, "bucket", "file.txt"}

# URI module
OmS3.URI.filename("s3://b/path/file.txt") #=> "file.txt"
OmS3.URI.parent("s3://b/path/file.txt")   #=> "s3://b/path/"
OmS3.URI.extname("s3://b/photo.jpg")      #=> ".jpg"
OmS3.URI.join("s3://b/dir/", "file.txt")  #=> "s3://b/dir/file.txt"
OmS3.URI.valid?("s3://bucket/key")        #=> true

# File name normalization
OmS3.normalize_key("User's Photo (1).jpg")
#=> "users-photo-1.jpg"

OmS3.normalize_key("report.pdf", prefix: "docs", timestamp: true)
#=> "docs/report-20240115-143022.pdf"

OmS3.normalize_key("file.txt", uuid: true)
#=> "file-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt"
```

---

## Network Layer

| Feature | Implementation |
|---------|---------------|
| HTTP client | Req + ReqS3 (SigV4 signing) |
| Connection pooling | Finch (via Req) with configurable pool timeout |
| Retries | `retry: :safe_transient` + `max_retries` (default 3) |
| Timeouts | `connect_timeout` (30s) / `receive_timeout` (60s) / `pool_timeout` (5s) |
| Proxy | HTTP/HTTPS with auth, NO_PROXY, env var fallback |
| Error recovery | Exponential backoff with jitter via Recoverable protocol |

---

## Real-World Examples

### User Avatar Upload (Phoenix Controller)

```elixir
defmodule MyAppWeb.AvatarController do
  use MyAppWeb, :controller

  def create(conn, %{"avatar" => upload}) do
    user = conn.assigns.current_user

    # Sanitize user-provided filename, add UUID for uniqueness
    key = OmS3.normalize_key(upload.filename,
      prefix: "avatars/#{user.id}",
      uuid: true
    )

    uri = "s3://#{bucket()}/#{key}"
    content = File.read!(upload.path)

    case OmS3.put(uri, content, config(), content_type: upload.content_type) do
      :ok ->
        {:ok, url} = OmS3.presign_get(uri, config(), expires_in: {7, :days})
        json(conn, %{url: url, key: key})

      {:error, %OmS3.Error{type: type, message: msg}} ->
        conn |> put_status(422) |> json(%{error: "#{type}: #{msg}"})
    end
  end
end
```

### Direct Browser Upload (Presigned PUT)

```elixir
defmodule MyAppWeb.UploadLive do
  use MyAppWeb, :live_view

  def handle_event("request_upload", %{"filename" => filename, "content_type" => ct}, socket) do
    key = OmS3.normalize_key(filename,
      prefix: "uploads/#{socket.assigns.current_user.id}",
      timestamp: true
    )

    # Generate presigned upload URL for the browser
    {:ok, url} = OmS3.new(config())
    |> OmS3.method(:put)
    |> OmS3.expires_in({15, :minutes})
    |> OmS3.presign("s3://#{bucket()}/#{key}")

    {:noreply, push_event(socket, "upload_url", %{url: url, key: key})}
  end

  # Browser JS: fetch(url, {method: "PUT", body: file, headers: {"Content-Type": ct}})

  def handle_event("upload_complete", %{"key" => key}, socket) do
    uri = "s3://#{bucket()}/#{key}"

    if OmS3.exists?(uri, config()) do
      {:ok, meta} = OmS3.head(uri, config())
      {:noreply, put_flash(socket, :info, "Uploaded #{meta.size} bytes")}
    else
      {:noreply, put_flash(socket, :error, "Upload verification failed")}
    end
  end
end
```

### Batch Report Generation

```elixir
defmodule MyApp.Reports do
  def generate_and_upload(users, month) do
    # Generate all PDFs locally
    files =
      users
      |> Task.async_stream(&generate_pdf(&1, month), max_concurrency: 4)
      |> Enum.map(fn {:ok, {key, pdf}} -> {key, pdf} end)

    # Batch upload to S3 with concurrency control
    results =
      OmS3.new(config())
      |> OmS3.bucket("reports")
      |> OmS3.prefix("monthly/#{month}/")
      |> OmS3.content_type("application/pdf")
      |> OmS3.storage_class("STANDARD_IA")
      |> OmS3.concurrency(20)
      |> OmS3.timeout({5, :minutes})
      |> OmS3.put_all(files)

    # Analyze results
    summary = OmS3.BatchResult.summarize(results)
    Logger.info(OmS3.BatchResult.format(summary))

    # Retry any transient failures
    if OmS3.BatchResult.any_failed?(results) do
      OmS3.BatchResult.retry_failures(results, fn uri, _reason ->
        {_bucket, key} = OmS3.URI.parse!(uri)
        user_id = extract_user_id(key)
        pdf = generate_pdf(Users.get!(user_id), month)
        OmS3.put(uri, pdf, config())
      end)
    end

    {:ok, summary}
  end

  defp generate_pdf(user, month) do
    pdf = ReportGenerator.monthly(user, month)
    key = "user-#{user.id}.pdf"
    {key, pdf}
  end
end
```

### Data Export with Expiring Download Links

```elixir
defmodule MyApp.Exports do
  @ttl_days 7

  def create(user, type) do
    data = fetch_export_data(user, type)
    json = Jason.encode!(data)

    key = OmS3.normalize_key("#{type}-export.json",
      prefix: "exports/#{user.id}",
      timestamp: true
    )

    uri = "s3://#{bucket()}/#{key}"

    with :ok <- OmS3.put(uri, json, config(),
           content_type: "application/json",
           metadata: %{user_id: to_string(user.id), type: type}),
         {:ok, url} <- OmS3.presign_get(uri, config(), expires_in: {@ttl_days, :days}) do
      {:ok, %{url: url, key: key, expires_in_days: @ttl_days}}
    end
  end

  # Daily cleanup job
  def cleanup_expired do
    {:ok, files} = OmS3.list_all("s3://#{bucket()}/exports/", config())
    now = DateTime.utc_now()

    expired_uris =
      files
      |> Enum.filter(&(DateTime.diff(now, &1.last_modified, :day) > @ttl_days))
      |> Enum.map(&OmS3.uri(bucket(), &1.key))

    case expired_uris do
      [] -> :noop
      uris ->
        results = OmS3.delete_all(uris, config(), concurrency: 20)
        summary = OmS3.BatchResult.summarize(results)
        Logger.info("Export cleanup: #{summary.succeeded} deleted, #{summary.failed} failed")
    end
  end
end
```

### Image Processing Pipeline

```elixir
defmodule MyApp.ImagePipeline do
  alias OmS3.Stream, as: S3Stream

  def process_upload(source_uri, config) do
    # 1. Download original
    {:ok, original} = OmS3.get(source_uri, config)

    # 2. Generate variants
    variants = [
      {"thumb", resize(original, 150, 150)},
      {"medium", resize(original, 800, 600)},
      {"large", resize(original, 1920, 1080)}
    ]

    # 3. Upload all variants in parallel
    filename = OmS3.URI.filename(source_uri)
    base = Path.rootname(filename)
    ext = Path.extname(filename)

    files = Enum.map(variants, fn {variant, data} ->
      {"#{base}-#{variant}#{ext}", data}
    end)

    OmS3.new(config)
    |> OmS3.bucket("images")
    |> OmS3.prefix("processed/")
    |> OmS3.content_type("image/jpeg")
    |> OmS3.concurrency(3)
    |> OmS3.put_all(files)
    |> OmS3.BatchResult.raise_on_failure!()

    # 4. Generate presigned download URLs
    uris = Enum.map(files, fn {key, _} -> "s3://images/processed/#{key}" end)

    OmS3.new(config)
    |> OmS3.expires_in({24, :hours})
    |> OmS3.presign_all(uris)
    |> Enum.map(fn {:ok, uri, url} -> {OmS3.URI.filename(uri), url} end)
    |> Map.new()
  end
end
```

### Large File Streaming with Progress

```elixir
defmodule MyApp.LargeTransfer do
  alias OmS3.Stream, as: S3Stream

  def download_with_progress(uri, local_path, config) do
    # Get file size first
    {:ok, %{size: total_bytes}} = OmS3.head(uri, config)

    pid = self()
    downloaded = :counters.new(1, [:atomics])

    # Stream download with progress tracking
    case S3Stream.download_with_callback(uri, config, fn chunk ->
      :counters.add(downloaded, 1, byte_size(chunk))
      current = :counters.get(downloaded, 1)
      percent = Float.round(current / total_bytes * 100, 1)
      send(pid, {:progress, percent, current, total_bytes})
      File.write!(local_path, chunk, [:append, :binary])
    end) do
      :ok -> {:ok, :counters.get(downloaded, 1)}
      {:error, reason} -> {:error, reason}
    end
  end

  def upload_large_file(local_path, uri, config) do
    file_size = File.stat!(local_path).size
    Logger.info("Uploading #{Float.round(file_size / 1_048_576, 1)}MB to #{uri}")

    S3Stream.upload_file(local_path, uri, config,
      content_type: OmS3.ContentType.detect(local_path),
      chunk_size: 10 * 1024 * 1024  # 10MB chunks
    )
  end
end
```

### Migration Between S3 Providers

```elixir
defmodule MyApp.S3Migration do
  def migrate(source_prefix, dest_prefix) do
    source = OmS3.config(
      access_key_id: "old-key",
      secret_access_key: "old-secret",
      region: "us-east-1"
    )

    dest = OmS3.config(
      access_key_id: "new-key",
      secret_access_key: "new-secret",
      endpoint: "https://ACCT.r2.cloudflarestorage.com",
      region: "auto"
    )

    # List all files from source
    {:ok, files} = OmS3.list_all(source_prefix, source)
    Logger.info("Migrating #{length(files)} files")

    # Download from source and upload to dest in batches
    files
    |> Enum.chunk_every(50)
    |> Enum.each(fn batch ->
      # Download batch
      uris = Enum.map(batch, &OmS3.uri("source-bucket", &1.key))
      downloaded = OmS3.get_all(uris, source, concurrency: 10)

      # Upload to destination
      to_upload =
        downloaded
        |> Enum.filter(&match?({:ok, _, _}, &1))
        |> Enum.map(fn {:ok, uri, content} ->
          filename = OmS3.URI.filename(uri)
          {filename, content}
        end)

      OmS3.put_all(to_upload, dest,
        to: dest_prefix,
        concurrency: 10,
        timeout: 120_000
      )
      |> OmS3.BatchResult.raise_on_failure!()
    end)
  end
end
```

### Cleanup Old Files by Glob

```elixir
defmodule MyApp.S3Cleanup do
  # Delete all .tmp files older than 24 hours
  def cleanup_temp_files(config) do
    {:ok, files} = OmS3.list_all("s3://bucket/tmp/", config)
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    old_uris =
      files
      |> Enum.filter(&(DateTime.compare(&1.last_modified, cutoff) == :lt))
      |> Enum.map(&OmS3.uri("bucket", &1.key))

    case old_uris do
      [] ->
        Logger.info("No temp files to clean up")

      uris ->
        results = OmS3.delete_all(uris, config, concurrency: 50)
        summary = OmS3.BatchResult.summarize(results)
        Logger.info("Cleaned up #{summary.succeeded} temp files")
    end
  end

  # Delete all logs matching a glob pattern
  def delete_old_logs(config) do
    results = OmS3.delete_all(["s3://bucket/logs/2023-*.log"], config)
    OmS3.BatchResult.raise_on_failure!(results)
  end
end
```

### Storage Module Pattern

```elixir
defmodule MyApp.Storage do
  @bucket System.compile_env!(:my_app, :s3_bucket)

  defp config do
    OmS3.Config.from_env()
  end

  def upload(path, content, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, OmS3.ContentType.detect(path))
    metadata = Keyword.get(opts, :metadata, %{})

    OmS3.put("s3://#{@bucket}/#{path}", content, config(),
      content_type: content_type,
      metadata: metadata
    )
  end

  def download(path) do
    OmS3.get("s3://#{@bucket}/#{path}", config())
  end

  def url(path, opts \\ []) do
    expires = Keyword.get(opts, :expires_in, {1, :hour})
    OmS3.presign_get("s3://#{@bucket}/#{path}", config(), expires_in: expires)
  end

  def delete(path) do
    OmS3.delete("s3://#{@bucket}/#{path}", config())
  end

  def list(prefix \\ "") do
    OmS3.list_all("s3://#{@bucket}/#{prefix}", config())
  end
end

# Usage:
MyApp.Storage.upload("avatars/user-1.jpg", jpeg_data, content_type: "image/jpeg")
{:ok, url} = MyApp.Storage.url("avatars/user-1.jpg", expires_in: {24, :hours})
```

### Dev/Test with LocalStack

```elixir
# config/dev.exs
config :my_app, :s3_config,
  access_key_id: "test",
  secret_access_key: "test",
  endpoint: "http://localhost:4566",
  region: "us-east-1"

# config/prod.exs
config :my_app, :s3_config,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1")
```

```yaml
# docker-compose.yml
services:
  localstack:
    image: localstack/localstack
    ports: ["4566:4566"]
    environment:
      SERVICES: s3
      DEFAULT_REGION: us-east-1
```

```elixir
# test/support/s3_helper.ex
defmodule MyApp.S3TestHelper do
  def config do
    OmS3.config(
      access_key_id: "test",
      secret_access_key: "test",
      endpoint: "http://localhost:4566",
      region: "us-east-1"
    )
  end

  def setup_bucket(bucket) do
    # LocalStack auto-creates buckets on first put
    OmS3.put("s3://#{bucket}/.keep", "", config())
  end

  def cleanup_bucket(bucket) do
    {:ok, files} = OmS3.list_all("s3://#{bucket}/", config())
    uris = Enum.map(files, &OmS3.uri(bucket, &1.key))
    OmS3.delete_all(uris, config())
  end
end
```

---

## Architecture

```
OmS3 (facade)           - Dual API: direct + pipeline
  OmS3.Request          - Pipeline builder
  OmS3.Client           - Low-level HTTP (Req + ReqS3), telemetry spans
  OmS3.Config           - Configuration, proxy, path_style auto-detection
  OmS3.Error            - Structured errors + Normalizable/Recoverable protocols
  OmS3.Telemetry        - Event emission + default logger
  OmS3.Stream           - Multipart upload + chunked download
  OmS3.BatchResult      - Batch analysis + categorized retry
  OmS3.PresignCache     - URL caching (GenServer + decorator preset)
  OmS3.URI              - Parse/build/join s3:// URIs
  OmS3.Glob             - * and ** pattern matching for batch ops
  OmS3.Headers          - Upload header construction
  OmS3.ContentType      - MIME type detection (30+ extensions)
  OmS3.FileNameNormalizer - Safe filename sanitization
  OmS3.Duration         - {5, :minutes} -> seconds/ms conversion
```

## License

MIT
