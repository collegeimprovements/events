# OmS3 Cheatsheet

> Composable S3 client with pipeline API, batch operations, and streaming. For full docs, see `README.md`.

## Setup

```elixir
# From explicit config
config = OmS3.config(access_key_id: "AKIA...", secret_access_key: "...", region: "us-east-1")

# From environment (S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_REGION, S3_ENDPOINT)
config = OmS3.from_env()

# S3-compatible (MinIO, R2, etc.) — path_style auto-detected
config = OmS3.config(access_key_id: "...", secret_access_key: "...", endpoint: "http://localhost:9000")
```

---

## Core Operations

```elixir
# Upload
:ok = OmS3.put("s3://bucket/file.txt", "content", config)
:ok = OmS3.put("s3://bucket/photo.jpg", data, config,
  content_type: "image/jpeg", metadata: %{user_id: "123"})

# Download
{:ok, binary} = OmS3.get("s3://bucket/file.txt", config)

# Delete (idempotent)
:ok = OmS3.delete("s3://bucket/file.txt", config)

# Head (metadata)
{:ok, %{size: 1024, content_type: "text/plain", etag: "abc"}} =
  OmS3.head("s3://bucket/file.txt", config)

# Exists
true = OmS3.exists?("s3://bucket/file.txt", config)

# Copy
:ok = OmS3.copy("s3://src/a.txt", "s3://dst/b.txt", config)

# List
{:ok, %{files: files, next: token}} = OmS3.list("s3://bucket/prefix/", config)
{:ok, all_files} = OmS3.list_all("s3://bucket/prefix/", config)
```

---

## Pipeline API

```elixir
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.prefix("uploads/2024/")
|> OmS3.content_type("image/jpeg")
|> OmS3.metadata(%{user_id: "123"})
|> OmS3.put("photo.jpg", jpeg_data)
```

---

## Batch Operations

```elixir
# Upload multiple (parallel)
results = OmS3.put_all([{"a.txt", data1}, {"b.txt", data2}], config,
  to: "s3://bucket/uploads/", concurrency: 10)

# Download with globs
results = OmS3.get_all(["s3://bucket/docs/*.pdf"], config)

# Delete with globs
results = OmS3.delete_all(["s3://bucket/temp/*.tmp"], config)

# Copy with glob
results = OmS3.copy_all("s3://source/*.jpg", config, to: "s3://dest/images/")

# Presign multiple
results = OmS3.presign_all(["s3://bucket/*.pdf"], config, expires_in: {1, :hour})

# Pipeline batch
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.concurrency(10)
|> OmS3.timeout({2, :minutes})
|> OmS3.put_all([{"a.jpg", data1}, {"b.jpg", data2}])
```

### Batch Results

```elixir
alias OmS3.BatchResult

BatchResult.all_succeeded?(results)              #=> true/false
BatchResult.any_failed?(results)

summary = BatchResult.summarize(results)
summary.total                                    #=> 100
summary.succeeded                                #=> 95
summary.failed                                   #=> 5
summary.success_rate                             #=> 0.95

BatchResult.recoverable_failures(results)         # worth retrying
BatchResult.permanent_failures(results)           # access_denied, etc.
BatchResult.retry_failures(results, &retry_fn/2, max_attempts: 3)
BatchResult.raise_on_failure!(results)            # strict mode
```

---

## Presigned URLs

```elixir
# Download URL
{:ok, url} = OmS3.presign_get("s3://bucket/file.pdf", config)
{:ok, url} = OmS3.presign_get("s3://bucket/file.pdf", config, expires_in: {5, :minutes})

# Upload form (browser direct upload)
{:ok, %{url: url, fields: fields}} = OmS3.presign_put("s3://bucket/upload.jpg", config)

# Pipeline presign
{:ok, url} = OmS3.new(config)
|> OmS3.expires_in({1, :hour})
|> OmS3.presign("s3://bucket/file.pdf")

# Duration formats
{5, :minutes}  |  {1, :hour}  |  {7, :days}  |  3600  # seconds
```

### Presign Cache

```elixir
# Supervision tree
children = [{OmS3.PresignCache, name: MyApp.S3PresignCache}]

# Get or generate cached URL
{:ok, url} = OmS3.PresignCache.get_or_generate(
  MyApp.S3PresignCache, "s3://bucket/file.pdf", config, expires_in: {1, :hour})

OmS3.PresignCache.stats(MyApp.S3PresignCache)    #=> %{entries: 150, hit_rate: 0.95}
OmS3.PresignCache.invalidate(MyApp.S3PresignCache, "s3://bucket/file.pdf")
```

---

## Streaming (Large Files)

```elixir
alias OmS3.Stream, as: S3Stream

# Download to file
:ok = S3Stream.download_to_file("s3://bucket/large.zip", "/tmp/large.zip", config)

# Download as stream
S3Stream.download("s3://bucket/large.zip", config)
|> Stream.into(File.stream!("/tmp/output.zip"))
|> Stream.run()

# Download with progress
S3Stream.download_with_callback("s3://bucket/file.zip", config, fn chunk ->
  send(self(), {:progress, byte_size(chunk)})
end)

# Upload from file (multipart)
:ok = S3Stream.upload_file("/path/to/large.zip", "s3://bucket/large.zip", config)

# Upload from stream
File.stream!("/path/to/large.zip", [], 5_242_880)
|> S3Stream.upload("s3://bucket/large.zip", config, content_type: "application/zip")
```

---

## URI Utilities

```elixir
OmS3.uri("bucket", "path/file.txt")             #=> "s3://bucket/path/file.txt"
OmS3.parse_uri("s3://bucket/file.txt")           #=> {:ok, "bucket", "file.txt"}

OmS3.URI.filename("s3://b/path/file.txt")        #=> "file.txt"
OmS3.URI.parent("s3://b/path/file.txt")          #=> "s3://b/path/"
OmS3.URI.extname("s3://b/photo.jpg")             #=> ".jpg"
OmS3.URI.join("s3://b/dir/", "file.txt")         #=> "s3://b/dir/file.txt"
OmS3.URI.valid?("s3://bucket/key")               #=> true

# Safe filename
OmS3.normalize_key("User's Photo (1).jpg")       #=> "users-photo-1.jpg"
OmS3.normalize_key("report.pdf", prefix: "docs", timestamp: true)
OmS3.normalize_key("file.txt", uuid: true)
```

---

## Error Handling

```elixir
case OmS3.get(uri, config) do
  {:ok, content} -> process(content)
  {:error, %OmS3.Error{type: :not_found}} -> :missing
  {:error, %OmS3.Error{type: :access_denied}} -> :forbidden
  {:error, %OmS3.Error{} = e} ->
    if FnTypes.Protocols.Recoverable.recoverable?(e), do: retry(), else: fail()
end
```

| Type | HTTP | Recoverable |
|------|------|-------------|
| `:not_found` | 404 | No |
| `:access_denied` | 403 | No |
| `:invalid_request` | 400 | No |
| `:request_timeout` | 408 | Yes |
| `:connection_error` | - | Yes |
| `:slow_down` | 503 | Yes |
| `:service_unavailable` | 503 | Yes |

---

## Config Options

| Option | Default | Description |
|--------|---------|-------------|
| `access_key_id` | *required* | Access key |
| `secret_access_key` | *required* | Secret key |
| `region` | `"us-east-1"` | AWS/provider region |
| `endpoint` | `nil` | Custom endpoint URL |
| `path_style` | auto | `true` for custom endpoints |
| `connect_timeout` | `30_000` | TCP timeout (ms) |
| `receive_timeout` | `60_000` | Response timeout (ms) |
| `max_retries` | `3` | Transient failure retries |
| `proxy` | `nil` | Proxy URL or tuple |

---

## Storage Module Pattern

```elixir
defmodule MyApp.Storage do
  @bucket System.compile_env!(:my_app, :s3_bucket)
  defp config, do: OmS3.Config.from_env()

  def upload(path, content, opts \\ []) do
    OmS3.put("s3://#{@bucket}/#{path}", content, config(),
      content_type: Keyword.get(opts, :content_type))
  end

  def download(path), do: OmS3.get("s3://#{@bucket}/#{path}", config())

  def url(path, opts \\ []) do
    OmS3.presign_get("s3://#{@bucket}/#{path}", config(),
      expires_in: Keyword.get(opts, :expires_in, {1, :hour}))
  end

  def delete(path), do: OmS3.delete("s3://#{@bucket}/#{path}", config())
end
```
