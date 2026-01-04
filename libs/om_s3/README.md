# OmS3

Ergonomic S3 client with presigned URLs, streaming, batch operations, and file utilities.

## Installation

```elixir
def deps do
  [{:om_s3, "~> 0.1.0"}]
end
```

---

## Why OmS3?

Without OmS3, S3 operations are verbose and error-prone:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RAW AWS/ExAws APPROACH                              │
│                                                                             │
│  # Verbose configuration everywhere                                         │
│  ExAws.S3.put_object("bucket", "key", content)                             │
│  |> ExAws.request(                                                          │
│       access_key_id: "...",                                                 │
│       secret_access_key: "...",                                             │
│       region: "us-east-1"                                                   │
│     )                                                                       │
│                                                                             │
│  # Manual presigned URL generation                                          │
│  # No batch operations                                                      │
│  # No glob patterns                                                         │
│  # No file name sanitization                                                │
│  # Inconsistent error handling                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WITH OmS3                                         │
│                                                                             │
│  # Dual API: Direct or Pipeline                                             │
│  OmS3.put("s3://bucket/file.txt", content, config)                         │
│                                                                             │
│  OmS3.new(config)                                                           │
│  |> OmS3.bucket("uploads")                                                  │
│  |> OmS3.content_type("image/jpeg")                                         │
│  |> OmS3.put("photo.jpg", data)                                             │
│                                                                             │
│  # Batch operations with globs                                              │
│  OmS3.get_all("s3://bucket/docs/*.pdf", config)                            │
│                                                                             │
│  # Presigned URLs in one call                                               │
│  OmS3.presign("s3://bucket/file.pdf", config, expires_in: {1, :hour})      │
│                                                                             │
│  # Safe file names                                                          │
│  OmS3.normalize_key("User's Photo (1).jpg")  #=> "users-photo-1.jpg"       │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Benefits:**

| Feature | Raw S3 | OmS3 |
|---------|--------|------|
| Configuration | Pass everywhere | Configure once |
| API Style | Single verbose | Dual (direct + pipeline) |
| Batch Operations | Manual loops | Built-in with concurrency |
| Glob Patterns | Not supported | `*.pdf`, `docs/**/*.txt` |
| Presigned URLs | Complex setup | Single function call |
| File Sanitization | Manual | `normalize_key/2` |
| S3 URIs | Parse yourself | `parse_uri/1`, `uri/2` |
| Error Handling | Inconsistent | Always `{:ok, _} \| {:error, _}` |

---

## Quick Start

```elixir
# 1. Configure
config = OmS3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)

# 2. Upload a file
OmS3.put("s3://my-bucket/hello.txt", "Hello, World!", config)
#=> {:ok, %{status: 200}}

# 3. Download a file
{:ok, content} = OmS3.get("s3://my-bucket/hello.txt", config)
#=> {:ok, "Hello, World!"}

# 4. Generate presigned URL
{:ok, url} = OmS3.presign("s3://my-bucket/hello.txt", config)
#=> {:ok, "https://my-bucket.s3.amazonaws.com/hello.txt?X-Amz-..."}
```

---

## Configuration

### Basic Configuration

```elixir
config = OmS3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)
```

### Full Configuration Options

```elixir
config = OmS3.config(
  # Required: AWS credentials
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),

  # Region (default: us-east-1)
  region: "eu-west-1",

  # Custom endpoint for S3-compatible services
  endpoint: "http://localhost:4566",  # LocalStack
  # endpoint: "http://localhost:9000", # MinIO

  # Proxy settings
  proxy: {"proxy.example.com", 8080},
  # Or with auth: {"proxy.example.com", 8080, "user", "pass"}

  # Timeouts
  connect_timeout: 30_000,   # Connection timeout (ms)
  receive_timeout: 60_000,   # Response timeout (ms)

  # Force path-style URLs (required for some S3-compatible services)
  force_path_style: true
)
```

### Environment-Based Configuration

```elixir
# In config/config.exs
config :my_app, :s3,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1"),
  bucket: System.get_env("S3_BUCKET")

# Usage
defmodule MyApp.Storage do
  def config do
    Application.get_env(:my_app, :s3) |> OmS3.config()
  end

  def upload(key, content) do
    bucket = Application.get_env(:my_app, :s3)[:bucket]
    OmS3.put("s3://#{bucket}/#{key}", content, config())
  end
end
```

---

## Dual API Styles

OmS3 offers two API styles for different use cases:

### Direct API (S3 URI + Config)

Best for simple, one-off operations:

```elixir
# Upload
OmS3.put("s3://bucket/path/file.txt", content, config)

# Download
{:ok, content} = OmS3.get("s3://bucket/path/file.txt", config)

# Delete
OmS3.delete("s3://bucket/path/file.txt", config)

# Check existence
{:ok, true} = OmS3.exists?("s3://bucket/path/file.txt", config)

# List objects
{:ok, objects} = OmS3.list("s3://bucket/path/", config)
```

### Pipeline API (Chainable)

Best for complex operations with many options:

```elixir
# Upload with options
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.prefix("images/2024/")
|> OmS3.content_type("image/jpeg")
|> OmS3.acl("public-read")
|> OmS3.storage_class("STANDARD_IA")
|> OmS3.metadata(%{user_id: "123", original_name: "photo.jpg"})
|> OmS3.put("resized.jpg", image_data)
|> OmS3.run()

# Download with timeout
OmS3.new(config)
|> OmS3.bucket("large-files")
|> OmS3.timeout({5, :minutes})
|> OmS3.get("huge-dataset.csv")
|> OmS3.run()
```

### When to Use Which

| Scenario | Recommended API |
|----------|-----------------|
| Simple upload/download | Direct API |
| Setting multiple options | Pipeline API |
| Batch operations | Pipeline API |
| One-off operations | Direct API |
| Reusable request templates | Pipeline API |
| Scripts and quick tasks | Direct API |

---

## Core Operations

### Put (Upload)

```elixir
# Simple upload
OmS3.put("s3://bucket/file.txt", "content", config)

# With content type (auto-detected if not specified)
OmS3.put("s3://bucket/image.png", png_binary, config,
  content_type: "image/png"
)

# With metadata
OmS3.put("s3://bucket/doc.pdf", pdf_binary, config,
  metadata: %{
    "x-amz-meta-author" => "John Doe",
    "x-amz-meta-version" => "1.0"
  }
)

# With ACL
OmS3.put("s3://bucket/public.html", html, config,
  acl: "public-read"
)

# With storage class
OmS3.put("s3://bucket/archive.zip", data, config,
  storage_class: "GLACIER"
)
```

**Pipeline Style:**

```elixir
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.content_type("application/pdf")
|> OmS3.acl("private")
|> OmS3.storage_class("STANDARD_IA")
|> OmS3.metadata(%{uploaded_by: user.id})
|> OmS3.put("documents/report.pdf", pdf_data)
|> OmS3.run()
```

### Get (Download)

```elixir
# Simple download
{:ok, content} = OmS3.get("s3://bucket/file.txt", config)

# With byte range
{:ok, partial} = OmS3.get("s3://bucket/video.mp4", config,
  range: "bytes=0-1023"
)

# Get metadata only (HEAD request)
{:ok, metadata} = OmS3.head("s3://bucket/file.txt", config)
#=> {:ok, %{
#     content_type: "text/plain",
#     content_length: 1234,
#     etag: "\"abc123\"",
#     last_modified: ~U[2024-01-15 10:00:00Z],
#     metadata: %{"x-amz-meta-author" => "John"}
#   }}
```

### Delete

```elixir
# Delete single object
OmS3.delete("s3://bucket/file.txt", config)

# Delete returns :ok even if object doesn't exist
OmS3.delete("s3://bucket/nonexistent.txt", config)
#=> {:ok, %{status: 204}}
```

### Exists

```elixir
# Check if object exists
{:ok, true} = OmS3.exists?("s3://bucket/file.txt", config)
{:ok, false} = OmS3.exists?("s3://bucket/missing.txt", config)

# With error handling
case OmS3.exists?("s3://bucket/file.txt", config) do
  {:ok, true} -> IO.puts("File exists")
  {:ok, false} -> IO.puts("File not found")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

### Head (Metadata)

```elixir
{:ok, info} = OmS3.head("s3://bucket/file.txt", config)
#=> {:ok, %{
#     content_type: "text/plain",
#     content_length: 1234,
#     etag: "\"d41d8cd98f00b204e9800998ecf8427e\"",
#     last_modified: ~U[2024-01-15 10:30:00Z],
#     metadata: %{}
#   }}
```

### List

```elixir
# List all objects in bucket
{:ok, objects} = OmS3.list("s3://bucket/", config)

# List with prefix
{:ok, objects} = OmS3.list("s3://bucket/images/", config)

# With pagination
{:ok, %{objects: objects, continuation_token: token}} =
  OmS3.list("s3://bucket/", config, max_keys: 100)

# Continue pagination
{:ok, more} = OmS3.list("s3://bucket/", config,
  continuation_token: token
)

# List returns object info
[
  %{key: "images/photo1.jpg", size: 12345, last_modified: ~U[...]},
  %{key: "images/photo2.jpg", size: 67890, last_modified: ~U[...]},
  ...
]
```

### Copy

```elixir
# Copy within same bucket
OmS3.copy("s3://bucket/original.txt", "s3://bucket/backup.txt", config)

# Copy between buckets
OmS3.copy(
  "s3://source-bucket/file.txt",
  "s3://dest-bucket/file.txt",
  config
)

# Copy with new metadata
OmS3.copy(
  "s3://bucket/file.txt",
  "s3://bucket/new-file.txt",
  config,
  metadata: %{copied_at: DateTime.utc_now() |> to_string()}
)
```

---

## Batch Operations

OmS3 provides efficient batch operations with built-in concurrency control.

### Put All (Batch Upload)

```elixir
# Upload multiple files
files = [
  {"doc1.pdf", pdf1_content},
  {"doc2.pdf", pdf2_content},
  {"doc3.pdf", pdf3_content}
]

OmS3.new(config)
|> OmS3.bucket("documents")
|> OmS3.prefix("reports/2024/")
|> OmS3.content_type("application/pdf")
|> OmS3.concurrency(10)
|> OmS3.put_all(files)
|> OmS3.run()
#=> {:ok, [
#     {:ok, "reports/2024/doc1.pdf"},
#     {:ok, "reports/2024/doc2.pdf"},
#     {:ok, "reports/2024/doc3.pdf"}
#   ]}
```

### Get All (Batch Download)

```elixir
# Download multiple files
keys = [
  "s3://bucket/file1.txt",
  "s3://bucket/file2.txt",
  "s3://bucket/file3.txt"
]

{:ok, results} = OmS3.get_all(keys, config, concurrency: 5)
#=> {:ok, [
#     {:ok, "content1"},
#     {:ok, "content2"},
#     {:ok, "content3"}
#   ]}
```

### Glob Pattern Support

OmS3 supports glob patterns for batch operations:

```elixir
# Download all PDFs
{:ok, pdfs} = OmS3.get_all("s3://bucket/docs/*.pdf", config)

# Download recursively
{:ok, all_images} = OmS3.get_all("s3://bucket/images/**/*.jpg", config)

# Copy with glob
OmS3.copy_all(
  "s3://source/uploads/*.jpg",
  config,
  to: "s3://dest/images/"
)

# Delete with glob
OmS3.delete_all("s3://bucket/temp/*.tmp", config)
```

**Supported Glob Patterns:**

| Pattern | Matches |
|---------|---------|
| `*` | Any characters in filename |
| `**` | Any path (recursive) |
| `?` | Single character |
| `[abc]` | Character class |
| `{a,b}` | Alternatives |

**Examples:**

```elixir
# All PDFs in docs/
"s3://bucket/docs/*.pdf"

# All images recursively
"s3://bucket/images/**/*.{jpg,png,gif}"

# Files starting with "report_"
"s3://bucket/reports/report_*.xlsx"

# Single character match
"s3://bucket/logs/app-?.log"  # app-1.log, app-2.log, etc.
```

### Delete All (Batch Delete)

```elixir
# Delete specific files
OmS3.delete_all([
  "s3://bucket/file1.txt",
  "s3://bucket/file2.txt"
], config)

# Delete with glob
OmS3.delete_all("s3://bucket/temp/**/*", config)

# Delete all objects with prefix
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.prefix("user/123/")
|> OmS3.delete_all()
|> OmS3.run()
```

### Concurrency Control

```elixir
# Set concurrency for batch operations
OmS3.new(config)
|> OmS3.bucket("large-bucket")
|> OmS3.concurrency(20)  # 20 parallel operations
|> OmS3.get_all("*.pdf")
|> OmS3.run()

# Default is System.schedulers_online() * 2
```

---

## Presigned URLs

Generate temporary URLs for direct browser access.

### Download URLs (GET)

```elixir
# Default expiration (1 hour)
{:ok, url} = OmS3.presign("s3://bucket/file.pdf", config)

# Custom expiration
{:ok, url} = OmS3.presign("s3://bucket/file.pdf", config,
  expires_in: {15, :minutes}
)

# With content disposition (force download)
{:ok, url} = OmS3.presign("s3://bucket/file.pdf", config,
  expires_in: {1, :hour},
  content_disposition: "attachment; filename=\"report.pdf\""
)

# Pipeline style
{:ok, url} = OmS3.new(config)
|> OmS3.bucket("downloads")
|> OmS3.expires_in({30, :minutes})
|> OmS3.presign("reports/monthly.pdf")
```

### Upload URLs (PUT)

```elixir
# Generate upload URL
{:ok, url} = OmS3.presign("s3://bucket/uploads/new-file.pdf", config,
  method: :put,
  expires_in: {15, :minutes}
)

# Client-side upload (JavaScript example):
# fetch(url, { method: 'PUT', body: file })

# Pipeline style
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.method(:put)
|> OmS3.expires_in({15, :minutes})
|> OmS3.content_type("application/pdf")
|> OmS3.presign("user-uploads/document.pdf")
```

### Upload Forms (POST)

For browser form uploads with additional controls:

```elixir
{:ok, form} = OmS3.presign_form("s3://bucket/uploads/", config,
  expires_in: {30, :minutes},
  max_size: 10_485_760,  # 10MB
  content_type_starts_with: "image/",
  key_starts_with: "uploads/user123/"
)

#=> {:ok, %{
#     url: "https://bucket.s3.amazonaws.com",
#     fields: %{
#       "key" => "uploads/${filename}",
#       "policy" => "base64...",
#       "x-amz-signature" => "...",
#       "x-amz-credential" => "...",
#       "x-amz-date" => "...",
#       "x-amz-algorithm" => "AWS4-HMAC-SHA256"
#     }
#   }}
```

**HTML Form Example:**

```html
<form action="<%= form.url %>" method="post" enctype="multipart/form-data">
  <%= for {name, value} <- form.fields do %>
    <input type="hidden" name="<%= name %>" value="<%= value %>">
  <% end %>
  <input type="file" name="file">
  <button type="submit">Upload</button>
</form>
```

### Expiration Time Formats

```elixir
# Tuple format
expires_in: {15, :minutes}
expires_in: {1, :hour}
expires_in: {24, :hours}
expires_in: {7, :days}

# Milliseconds (integer)
expires_in: 900_000  # 15 minutes

# Using :timer
expires_in: :timer.minutes(15)
expires_in: :timer.hours(1)
```

---

## S3 URIs

OmS3 provides utilities for working with S3 URIs (`s3://bucket/key`).

### Building URIs

```elixir
# Build from components
OmS3.uri("my-bucket", "path/to/file.txt")
#=> "s3://my-bucket/path/to/file.txt"

# With prefix
OmS3.uri("my-bucket", "file.txt", prefix: "uploads/2024/")
#=> "s3://my-bucket/uploads/2024/file.txt"
```

### Parsing URIs

```elixir
# Parse URI to components
{:ok, bucket, key} = OmS3.parse_uri("s3://my-bucket/path/file.txt")
#=> {:ok, "my-bucket", "path/file.txt"}

# Handle invalid URIs
:error = OmS3.parse_uri("not-an-s3-uri")

# Bang version
{bucket, key} = OmS3.parse_uri!("s3://bucket/key")
```

### URI Utilities

```elixir
alias OmS3.URI

# Extract bucket
URI.bucket("s3://my-bucket/path/file.txt")
#=> "my-bucket"

# Extract key
URI.key("s3://my-bucket/path/file.txt")
#=> "path/file.txt"

# Get parent path
URI.parent("s3://bucket/a/b/c/file.txt")
#=> "s3://bucket/a/b/c/"

# Get filename
URI.filename("s3://bucket/path/file.txt")
#=> "file.txt"

# Get extension
URI.extname("s3://bucket/path/file.txt")
#=> ".txt"

# Join paths
URI.join("s3://bucket/path/", "subdir/file.txt")
#=> "s3://bucket/path/subdir/file.txt"
```

---

## File Name Utilities

OmS3 provides utilities to normalize file names for safe S3 storage.

### Basic Normalization

```elixir
# Remove special characters, lowercase
OmS3.normalize_key("User's Photo (1).jpg")
#=> "users-photo-1.jpg"

# Handle unicode
OmS3.normalize_key("Café Menu.pdf")
#=> "cafe-menu.pdf"

# Multiple spaces/dashes
OmS3.normalize_key("my   file---name.txt")
#=> "my-file-name.txt"
```

### With Options

```elixir
# Add prefix
OmS3.normalize_key("report.pdf", prefix: "documents")
#=> "documents/report.pdf"

# Add timestamp
OmS3.normalize_key("report.pdf", timestamp: true)
#=> "report-20240115-143022.pdf"

# Add UUID
OmS3.normalize_key("report.pdf", uuid: true)
#=> "report-550e8400-e29b-41d4-a716-446655440000.pdf"

# Custom separator
OmS3.normalize_key("my file.txt", separator: "_")
#=> "my_file.txt"

# Preserve case
OmS3.normalize_key("MyFile.TXT", preserve_case: true)
#=> "MyFile.TXT"

# Max length
OmS3.normalize_key("very-long-file-name.pdf", max_length: 20)
#=> "very-long-file-n.pdf"

# Combined
OmS3.normalize_key("User's Report.pdf",
  prefix: "uploads/2024",
  timestamp: true,
  uuid: true
)
#=> "uploads/2024/users-report-20240115-143022-550e8400-e29b-41d4-a716-446655440000.pdf"
```

### Content Type Detection

OmS3 auto-detects content types from file extensions:

```elixir
# Automatic detection (30+ extensions)
OmS3.put("s3://bucket/image.jpg", data, config)
# Content-Type: image/jpeg

OmS3.put("s3://bucket/data.json", json, config)
# Content-Type: application/json

# Manual override
OmS3.put("s3://bucket/file", data, config,
  content_type: "application/octet-stream"
)
```

**Supported Extensions:**

| Category | Extensions |
|----------|------------|
| Images | jpg, jpeg, png, gif, svg, webp, ico, bmp |
| Documents | pdf, doc, docx, xls, xlsx, ppt, pptx |
| Text | txt, csv, html, css, js, json, xml, md |
| Archives | zip, tar, gz, rar, 7z |
| Audio | mp3, wav, ogg, m4a, flac |
| Video | mp4, webm, avi, mov, mkv |

---

## Real-World Examples

### 1. User Avatar Upload (Phoenix)

```elixir
defmodule MyAppWeb.AvatarController do
  use MyAppWeb, :controller

  def create(conn, %{"avatar" => upload}) do
    user = conn.assigns.current_user

    # Normalize filename with user-specific prefix
    key = OmS3.normalize_key(upload.filename,
      prefix: "avatars/#{user.id}",
      uuid: true
    )

    # Read and upload
    content = File.read!(upload.path)

    case OmS3.put("s3://#{bucket()}/#{key}", content, config(),
      content_type: upload.content_type,
      acl: "public-read"
    ) do
      {:ok, _} ->
        # Update user with new avatar URL
        {:ok, url} = OmS3.presign("s3://#{bucket()}/#{key}", config(),
          expires_in: {7, :days}
        )

        user
        |> User.avatar_changeset(%{avatar_url: url})
        |> Repo.update()

        json(conn, %{url: url})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Upload failed: #{inspect(reason)}"})
    end
  end

  defp config, do: Application.get_env(:my_app, :s3) |> OmS3.config()
  defp bucket, do: Application.get_env(:my_app, :s3)[:bucket]
end
```

### 2. Direct Browser Upload (LiveView)

```elixir
defmodule MyAppWeb.UploadLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :upload_url, nil)}
  end

  def handle_event("request_upload", %{"filename" => filename}, socket) do
    # Generate presigned upload URL
    key = OmS3.normalize_key(filename,
      prefix: "uploads/#{socket.assigns.current_user.id}",
      timestamp: true
    )

    {:ok, url} = OmS3.presign("s3://#{bucket()}/#{key}", config(),
      method: :put,
      expires_in: {15, :minutes}
    )

    {:noreply, assign(socket, upload_url: url, upload_key: key)}
  end

  def handle_event("upload_complete", _params, socket) do
    # Verify upload and process
    case OmS3.exists?("s3://#{bucket()}/#{socket.assigns.upload_key}", config()) do
      {:ok, true} ->
        # Process uploaded file
        {:noreply, put_flash(socket, :info, "Upload complete!")}

      {:ok, false} ->
        {:noreply, put_flash(socket, :error, "Upload verification failed")}
    end
  end
end
```

**JavaScript for Direct Upload:**

```javascript
async function uploadFile(file, presignedUrl) {
  const response = await fetch(presignedUrl, {
    method: 'PUT',
    body: file,
    headers: {
      'Content-Type': file.type
    }
  });

  if (response.ok) {
    // Notify LiveView of completion
    this.pushEvent('upload_complete', {});
  }
}
```

### 3. Batch Report Generation

```elixir
defmodule MyApp.Reports.Generator do
  def generate_monthly_reports(month, year) do
    users = Users.with_activity_in_month(month, year)

    # Generate reports in parallel
    reports = users
    |> Task.async_stream(fn user ->
      report = generate_report(user, month, year)
      key = "reports/#{year}/#{month}/user-#{user.id}.pdf"
      {key, report}
    end, max_concurrency: 10)
    |> Enum.map(fn {:ok, result} -> result end)

    # Batch upload
    OmS3.new(config())
    |> OmS3.bucket("reports")
    |> OmS3.content_type("application/pdf")
    |> OmS3.storage_class("STANDARD_IA")
    |> OmS3.concurrency(20)
    |> OmS3.put_all(reports)
    |> OmS3.run()
  end
end
```

### 4. Data Export with Cleanup

```elixir
defmodule MyApp.Exports do
  @export_ttl_days 7

  def create_export(user, data_type) do
    export_data = fetch_export_data(user, data_type)

    key = OmS3.normalize_key("#{data_type}-export.json",
      prefix: "exports/#{user.id}",
      timestamp: true
    )

    case OmS3.put("s3://#{bucket()}/#{key}", Jason.encode!(export_data), config(),
      content_type: "application/json",
      metadata: %{
        "x-amz-meta-user-id" => to_string(user.id),
        "x-amz-meta-expires-at" => expiration_date()
      }
    ) do
      {:ok, _} ->
        {:ok, url} = OmS3.presign("s3://#{bucket()}/#{key}", config(),
          expires_in: {@export_ttl_days, :days}
        )
        {:ok, %{url: url, expires_in: @export_ttl_days}}

      error -> error
    end
  end

  # Cleanup job (run daily)
  def cleanup_expired_exports do
    # List all exports
    {:ok, objects} = OmS3.list("s3://#{bucket()}/exports/", config())

    # Filter expired
    now = DateTime.utc_now()
    expired = Enum.filter(objects, fn obj ->
      DateTime.diff(now, obj.last_modified, :day) > @export_ttl_days
    end)

    # Batch delete
    if length(expired) > 0 do
      keys = Enum.map(expired, & "s3://#{bucket()}/#{&1.key}")
      OmS3.delete_all(keys, config())
    end
  end

  defp expiration_date do
    DateTime.utc_now()
    |> DateTime.add(@export_ttl_days, :day)
    |> DateTime.to_iso8601()
  end
end
```

### 5. LocalStack/MinIO Development

```elixir
# config/dev.exs
config :my_app, :s3,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1",
  endpoint: "http://localhost:4566",  # LocalStack
  force_path_style: true,
  bucket: "dev-bucket"

# Or MinIO
config :my_app, :s3,
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin",
  region: "us-east-1",
  endpoint: "http://localhost:9000",
  force_path_style: true,
  bucket: "dev-bucket"
```

```bash
# docker-compose.yml for LocalStack
services:
  localstack:
    image: localstack/localstack
    ports:
      - "4566:4566"
    environment:
      - SERVICES=s3
      - DEFAULT_REGION=us-east-1
```

```elixir
# Create bucket in development
def setup_dev_bucket do
  # LocalStack/MinIO need bucket creation
  OmS3.create_bucket("dev-bucket", config())
end
```

---

## Best Practices

### 1. Always Use Normalized Keys

```elixir
# GOOD: Normalized, safe key
key = OmS3.normalize_key(user_filename, prefix: "uploads", uuid: true)
OmS3.put("s3://bucket/#{key}", content, config)

# BAD: User input directly in key (security risk!)
OmS3.put("s3://bucket/#{user_filename}", content, config)
```

### 2. Use Presigned URLs for Client Uploads

```elixir
# GOOD: Client uploads directly to S3
{:ok, url} = OmS3.presign("s3://bucket/#{key}", config, method: :put)
# Client uploads to `url`

# BAD: Upload through your server (wastes bandwidth)
def upload(conn, %{"file" => file}) do
  content = File.read!(file.path)
  OmS3.put("s3://bucket/file", content, config)
end
```

### 3. Set Appropriate Storage Classes

```elixir
# Frequently accessed
OmS3.put(uri, data, config, storage_class: "STANDARD")

# Infrequent access (cheaper storage, retrieval cost)
OmS3.put(uri, data, config, storage_class: "STANDARD_IA")

# Archive (very cheap, slow retrieval)
OmS3.put(uri, data, config, storage_class: "GLACIER")
```

### 4. Handle Errors Gracefully

```elixir
# GOOD: Pattern match on results
case OmS3.get(uri, config) do
  {:ok, content} -> process(content)
  {:error, :not_found} -> {:error, :file_not_found}
  {:error, :access_denied} -> {:error, :unauthorized}
  {:error, reason} -> {:error, {:s3_error, reason}}
end

# BAD: Assume success
{:ok, content} = OmS3.get(uri, config)  # Will crash on error!
```

### 5. Use Batch Operations for Multiple Files

```elixir
# GOOD: Batch with concurrency control
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.concurrency(10)
|> OmS3.get_all(keys)
|> OmS3.run()

# BAD: Sequential operations
Enum.map(keys, fn key ->
  OmS3.get(key, config)
end)
```

### 6. Organize Keys with Prefixes

```elixir
# GOOD: Organized key structure
"users/#{user_id}/avatars/#{filename}"
"exports/#{year}/#{month}/#{report_id}.pdf"
"temp/#{session_id}/#{filename}"

# BAD: Flat structure
"#{filename}"  # No organization, hard to manage
```

---

## Options Reference

### Pipeline Options

| Method | Type | Description |
|--------|------|-------------|
| `bucket/2` | string | Target bucket name |
| `prefix/2` | string | Key prefix for all operations |
| `content_type/2` | string | MIME type |
| `acl/2` | string | Access control: "private", "public-read", etc. |
| `storage_class/2` | string | "STANDARD", "STANDARD_IA", "GLACIER", etc. |
| `metadata/2` | map | Custom metadata headers |
| `expires_in/2` | tuple/int | Presigned URL expiration |
| `method/2` | atom | `:get`, `:put`, `:delete` for presigned URLs |
| `timeout/2` | tuple/int | Request timeout |
| `concurrency/2` | integer | Parallel operations for batch |

### Operation Options

| Option | Operations | Description |
|--------|------------|-------------|
| `content_type` | put | MIME type |
| `acl` | put | Access control |
| `storage_class` | put | Storage tier |
| `metadata` | put, copy | Custom metadata |
| `range` | get | Byte range for partial download |
| `max_keys` | list | Pagination limit |
| `continuation_token` | list | Pagination cursor |
| `expires_in` | presign | URL expiration time |
| `method` | presign | HTTP method for URL |
| `content_disposition` | presign | Force download filename |
| `concurrency` | batch ops | Parallel execution limit |

### ACL Values

| Value | Description |
|-------|-------------|
| `"private"` | Owner-only access (default) |
| `"public-read"` | Public read, owner write |
| `"public-read-write"` | Public read/write |
| `"authenticated-read"` | Authenticated AWS users can read |
| `"bucket-owner-read"` | Bucket owner can read |
| `"bucket-owner-full-control"` | Bucket owner has full control |

### Storage Classes

| Class | Description | Use Case |
|-------|-------------|----------|
| `STANDARD` | High availability, low latency | Frequently accessed |
| `STANDARD_IA` | Lower cost, retrieval fee | Infrequent access |
| `ONEZONE_IA` | Single AZ, cheaper | Non-critical data |
| `GLACIER` | Archive, hours to retrieve | Long-term archive |
| `GLACIER_IR` | Archive, minutes to retrieve | Archive with faster access |
| `DEEP_ARCHIVE` | Cheapest, 12+ hours | Compliance archives |

---

## Error Handling

OmS3 returns consistent `{:ok, result} | {:error, reason}` tuples:

```elixir
case OmS3.get(uri, config) do
  {:ok, content} ->
    {:ok, content}

  {:error, :not_found} ->
    {:error, :file_not_found}

  {:error, :access_denied} ->
    {:error, :unauthorized}

  {:error, {:http_error, status, body}} ->
    Logger.error("S3 HTTP error: #{status} - #{body}")
    {:error, :s3_error}

  {:error, :timeout} ->
    {:error, :timeout}

  {:error, reason} ->
    Logger.error("S3 error: #{inspect(reason)}")
    {:error, :unknown_error}
end
```

**Common Error Reasons:**

| Error | Cause |
|-------|-------|
| `:not_found` | Object doesn't exist |
| `:access_denied` | Invalid credentials or permissions |
| `:timeout` | Request exceeded timeout |
| `:invalid_uri` | Malformed S3 URI |
| `{:http_error, status, body}` | HTTP error from S3 |

## License

MIT
