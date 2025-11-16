# Simplified AWS S3 API

A radically simplified API for AWS S3 operations with clear, obvious naming and sensible defaults.

## Quick Start

### Zero Configuration (Using ENV Variables)

```elixir
# Set environment variables:
# AWS_ACCESS_KEY_ID="your-key"
# AWS_SECRET_ACCESS_KEY="your-secret"
# AWS_REGION="us-east-1"

alias Events.Services.Aws.SimpleS3

# List files
{:ok, %{files: files}} = SimpleS3.list("my-bucket")

# Upload
:ok = SimpleS3.upload("my-bucket", "photo.jpg", file_content)

# Download
{:ok, content} = SimpleS3.download("my-bucket", "photo.jpg")

# Check existence
SimpleS3.exists?("my-bucket", "photo.jpg")  #=> true

# Delete
:ok = SimpleS3.delete("my-bucket", "photo.jpg")
```

### With Explicit Credentials

```elixir
alias Events.Services.Aws
alias Events.Services.Aws.SimpleS3

# Connect with explicit credentials
aws = Aws.connect(
  key: "AKIAIOSFODNN7EXAMPLE",
  secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  region: "us-east-1"
)

# Use connection with all operations
SimpleS3.list(aws, "my-bucket")
SimpleS3.upload(aws, "my-bucket", "file.txt", content)
```

## Complete API Reference

### List Operations

#### `list/3` - List files in a bucket

```elixir
# List all files (up to 1000)
{:ok, %{files: files, next_token: nil}} = SimpleS3.list("my-bucket")

# List with prefix
{:ok, %{files: files}} = SimpleS3.list("my-bucket", prefix: "uploads/")

# Pagination
{:ok, %{files: page1, next_token: token}} =
  SimpleS3.list("my-bucket", limit: 100)

{:ok, %{files: page2, next_token: token2}} =
  SimpleS3.list("my-bucket", limit: 100, token: token)

# Each file has:
# %{
#   path: "uploads/photo.jpg",
#   size: 524288,
#   modified_at: ~U[2024-01-15 10:30:00Z],
#   etag: "abc123..."
# }
```

**Options:**
- `:prefix` - Only list files with this prefix (default: `""`)
- `:limit` - Maximum files to return (default: `1000`)
- `:token` - Continuation token for pagination

#### `list_all/3` - List all files recursively

Automatically handles pagination to retrieve all files.

```elixir
# Get all files in bucket
{:ok, all_files} = SimpleS3.list_all("my-bucket")

# Get all files in folder
{:ok, files} = SimpleS3.list_all("my-bucket", prefix: "uploads/2024/")
```

### Upload Operations

#### `upload/5` - Upload a file

```elixir
# Simple upload
:ok = SimpleS3.upload("my-bucket", "photo.jpg", image_binary)

# With content type
:ok = SimpleS3.upload("my-bucket", "doc.pdf", pdf_content,
  type: "application/pdf"
)

# With metadata
:ok = SimpleS3.upload("my-bucket", "file.txt", content,
  metadata: %{"user_id" => "123", "version" => "2"}
)

# Public file
:ok = SimpleS3.upload("my-bucket", "public/logo.png", content,
  public: true
)
```

**Options:**
- `:type` - Content type (default: `"application/octet-stream"`)
- `:metadata` - Custom metadata map
- `:public` - Make file public (default: `false`)

### Download Operations

#### `download/3` - Download a file

```elixir
{:ok, content} = SimpleS3.download("my-bucket", "photo.jpg")
{:ok, pdf} = SimpleS3.download("my-bucket", "documents/report.pdf")

# With explicit credentials
{:ok, content} = SimpleS3.download(aws, "my-bucket", "file.txt")
```

### Delete Operations

#### `delete/3` - Delete a file

```elixir
:ok = SimpleS3.delete("my-bucket", "old-file.txt")

# With explicit credentials
:ok = SimpleS3.delete(aws, "my-bucket", "file.txt")
```

### Existence Checks

#### `exists?/3` - Check if file exists

```elixir
SimpleS3.exists?("my-bucket", "photo.jpg")     #=> true
SimpleS3.exists?("my-bucket", "missing.txt")   #=> false
```

### URL Generation

#### `url_for_upload/4` - Generate presigned upload URL

```elixir
# Simple upload URL (1 hour expiration)
{:ok, url} = SimpleS3.url_for_upload("my-bucket", "photo.jpg")

# With custom expiration (5 minutes)
{:ok, url} = SimpleS3.url_for_upload("my-bucket", "file.pdf",
  expires: 300
)

# With content type
{:ok, url} = SimpleS3.url_for_upload("my-bucket", "image.png",
  type: "image/png",
  expires: 1800
)
```

**Options:**
- `:expires` - Expiration in seconds (default: `3600`)
- `:type` - Content type for the upload
- `:metadata` - Custom metadata

#### `url_for_download/4` - Generate presigned download URL

```elixir
# Simple download URL (1 hour expiration)
{:ok, url} = SimpleS3.url_for_download("my-bucket", "photo.jpg")

# Short-lived URL (5 minutes)
{:ok, url} = SimpleS3.url_for_download("my-bucket", "secret.pdf",
  expires: 300
)
```

**Options:**
- `:expires` - Expiration in seconds (default: `3600`)

### Copy Operations

#### `copy/4` - Copy a file

```elixir
# Copy within same bucket
:ok = SimpleS3.copy("my-bucket", "old-path.jpg", "new-path.jpg")

# Copy between buckets
:ok = SimpleS3.copy("source-bucket", "file.txt",
  to_bucket: "dest-bucket",
  to_path: "copied-file.txt"
)
```

### Utility Operations

#### `info/3` - Get file metadata

```elixir
{:ok, info} = SimpleS3.info("my-bucket", "photo.jpg")

# Returns:
# %{
#   size: 524288,
#   modified_at: ~U[2024-01-15 10:30:00Z],
#   content_type: "image/jpeg",
#   etag: "abc123..."
# }
```

#### `folder_size/3` - Calculate folder size

```elixir
{:ok, stats} = SimpleS3.folder_size("my-bucket", prefix: "uploads/2024/")

# Returns:
# %{
#   total_files: 42,
#   total_bytes: 1048576
# }
```

## Design Principles

### 1. Bucket-First API

The bucket name is always the first argument after the optional connection:

```elixir
SimpleS3.list("my-bucket")
SimpleS3.list(aws, "my-bucket")
```

### 2. Clear Verbs

We use obvious, clear function names:
- `list` not `list_objects`
- `upload` not `put_object`
- `download` not `get_object`
- `exists?` not `object_exists?`

### 3. Sensible Defaults

Common cases work with zero configuration:
- Default limit: 1000 files
- Default expiration: 3600 seconds (1 hour)
- Default content type: "application/octet-stream"

### 4. Progressive Disclosure

Simple things are simple, complex things are possible:

```elixir
# Simple: Just upload
SimpleS3.upload("my-bucket", "file.txt", content)

# Complex: Full control
SimpleS3.upload(aws, "my-bucket", "file.txt", content,
  type: "text/plain",
  metadata: %{"version" => "2"},
  public: true
)
```

## Environment Variables

The client automatically uses these ENV variables:

- `AWS_ACCESS_KEY_ID` - Your AWS access key
- `AWS_SECRET_ACCESS_KEY` - Your AWS secret key
- `AWS_REGION` - Default region (default: "us-east-1")
- `AWS_DEFAULT_REGION` - Alternative region variable
- `S3_BUCKET` - Default bucket name
- `AWS_ENDPOINT_URL` - Custom endpoint (for LocalStack, MinIO)

## LocalStack / MinIO Support

```elixir
# Using ENV
# AWS_ENDPOINT_URL="http://localhost:4566"

# Or explicit connection
aws = Aws.connect(
  key: "test",
  secret: "test",
  region: "us-east-1",
  endpoint: "http://localhost:4566"
)

SimpleS3.list(aws, "my-bucket")
```

## Error Handling

All operations return standard Elixir result tuples:

```elixir
case SimpleS3.download("my-bucket", "photo.jpg") do
  {:ok, content} ->
    # Use content
    IO.puts("Downloaded #{byte_size(content)} bytes")

  {:error, :not_found} ->
    IO.puts("File not found")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Complete Example: File Upload Flow

```elixir
alias Events.Services.Aws.SimpleS3

# 1. Check if file exists
exists? = SimpleS3.exists?("my-bucket", "photo.jpg")

# 2. Upload if it doesn't exist
unless exists? do
  :ok = SimpleS3.upload("my-bucket", "photo.jpg", image_data,
    type: "image/jpeg",
    metadata: %{"uploaded_by" => "user_123"}
  )
end

# 3. Get file info
{:ok, info} = SimpleS3.info("my-bucket", "photo.jpg")
IO.puts("File size: #{info.size} bytes")

# 4. Generate download URL (valid for 1 hour)
{:ok, download_url} = SimpleS3.url_for_download("my-bucket", "photo.jpg")

# 5. Later, download the file
{:ok, content} = SimpleS3.download("my-bucket", "photo.jpg")

# 6. Copy to archive
:ok = SimpleS3.copy("my-bucket", "photo.jpg", "archive/photo-2024.jpg")

# 7. Delete original
:ok = SimpleS3.delete("my-bucket", "photo.jpg")
```

## Complete Example: Listing and Processing Files

```elixir
alias Events.Services.Aws.SimpleS3

# List all images in uploads folder
{:ok, %{files: files}} = SimpleS3.list("my-bucket",
  prefix: "uploads/images/"
)

# Filter to JPEGs
jpeg_files = Enum.filter(files, fn file ->
  String.ends_with?(file.path, ".jpg")
end)

# Sort by size (largest first)
sorted_files = Enum.sort_by(jpeg_files, & &1.size, :desc)

# Process each file
Enum.each(sorted_files, fn file ->
  IO.puts("""
  File: #{file.path}
  Size: #{Float.round(file.size / 1024 / 1024, 2)} MB
  Modified: #{file.modified_at}
  """)

  # Generate download URL for each
  {:ok, url} = SimpleS3.url_for_download("my-bucket", file.path,
    expires: 300
  )

  IO.puts("Download: #{url}\n")
end)
```

## Migration from Existing S3 Module

If you're currently using the existing `Events.Services.Aws.S3` module:

### Before (Context-based):
```elixir
context = Context.new(
  access_key_id: "...",
  secret_access_key: "...",
  region: "us-east-1",
  bucket: "my-bucket"
)

S3.list_objects(context, prefix: "uploads/")
S3.upload(context, "file.txt", content)
```

### After (SimpleS3):
```elixir
# Option 1: Use ENV variables
SimpleS3.list("my-bucket", prefix: "uploads/")
SimpleS3.upload("my-bucket", "file.txt", content)

# Option 2: Explicit connection
aws = Aws.connect(
  key: "...",
  secret: "...",
  region: "us-east-1"
)

SimpleS3.list(aws, "my-bucket", prefix: "uploads/")
SimpleS3.upload(aws, "my-bucket", "file.txt", content)
```

## Comparison with Standard S3 Module

| Feature | Standard `S3` Module | New `SimpleS3` Module |
|---------|---------------------|----------------------|
| Context required | Yes | No (optional) |
| Bucket in context | Yes | No (passed as argument) |
| Function naming | `list_objects`, `get_object` | `list`, `download` |
| Default arguments | Some | More sensible defaults |
| ENV variable support | Limited | Full support |
| API clarity | Good | Better |
| Verbosity | More verbose | More concise |

Both modules use the same underlying adapter, so they have identical functionality and performance.
