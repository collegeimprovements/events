# S3 Operations Cheatsheet

Composable, pipe-friendly S3 operations for Events application.

## Setup Context

```elixir
alias Events.Services.Aws.{Context, S3}

# Create context from environment variables (reads AWS_* env vars)
ctx = Context.s3()

# Or create with specific bucket
ctx = Context.s3() |> Context.with_bucket("my-bucket")

# Or create manually
ctx = Context.new(
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION"),
  bucket: "my-bucket",
  endpoint_url: System.get_env("AWS_ENDPOINT_URL_S3")
)
```

## 1. List Files/Objects on a Path

```elixir
# List all files in a prefix
{:ok, %{objects: objects, continuation_token: token}} =
  Context.s3()
  |> Context.with_bucket("my-bucket")
  |> S3.list_files("uploads/photos/")

# List with options (sorting, pagination)
{:ok, result} =
  Context.s3()
  |> Context.with_bucket("my-bucket")
  |> S3.list_objects(
    prefix: "uploads/",
    max_keys: 100,
    sort_by: :last_modified,
    sort_order: :desc
  )

# Get just the file keys
{:ok, keys} =
  Context.s3()
  |> Context.with_bucket("my-bucket")
  |> S3.Uploader.list_file_keys("uploads/")

# Iterate through results
objects
|> Enum.each(fn obj ->
  IO.puts("#{obj.key} - #{obj.size} bytes - #{obj.last_modified}")
end)
```

## 2. Upload File with Presigned URL + Metadata + Timestamps

### Generate Presigned Upload URL

```elixir
# Simple presigned upload URL
{:ok, url, key} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.presigned_upload_url("photo.jpg", expires_in: 300)

# With timestamp and prefix
{:ok, url, key} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.presigned_upload_url(
    "User's Photo.jpg",
    prefix: "photos/2024",
    add_timestamp: true,
    expires_in: 300,
    content_type: "image/jpeg"
  )
# Returns: {:ok, "https://...", "photos/2024/users-photo-20241116-143022.jpg"}

# Batch presigned URLs
filenames = ["photo1.jpg", "photo2.jpg", "document.pdf"]
results =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.Uploader.batch_presigned_upload_urls(
    filenames,
    prefix: "batch/2024",
    add_timestamp: true,
    expires_in: 300
  )
```

### Direct Upload with Metadata

```elixir
# Upload with custom metadata and timestamps
:ok =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.upload(
    "documents/report.pdf",
    file_content,
    content_type: "application/pdf",
    metadata: %{
      "user_id" => "123",
      "uploaded_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "organization" => "acme-corp",
      "version" => "1.0"
    }
  )

# Upload with normalized filename and timestamp
{:ok, key} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.upload_normalized(
    "User's Document (final).pdf",
    file_content,
    prefix: "documents",
    add_timestamp: true,
    metadata: %{
      "user_id" => "456",
      "uploaded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  )
# Returns: {:ok, "documents/users-document-final-20241116-143022.pdf"}

# Upload with UUID (for unique filenames)
{:ok, key} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.Uploader.upload_with_uuid(
    "photo.jpg",
    photo_content,
    prefix: "photos"
  )
# Returns: {:ok, "photos/a1b2c3d4-e5f6-7890-abcd-ef1234567890.jpg"}
```

### Pipe-Friendly Upload Preparation

```elixir
# Prepare and generate presigned upload URL
{:ok, result} =
  "User's Photo.jpg"
  |> S3.prepare(Context.s3() |> Context.with_bucket("uploads"), prefix: "photos")
  |> S3.generate_presigned_upload_url(expires_in: 300)

# Batch preparation
{:ok, results} =
  ["photo1.jpg", "photo2.jpg", "photo3.jpg"]
  |> S3.prepare_batch(
    Context.s3() |> Context.with_bucket("uploads"),
    prefix: "photos/batch",
    add_timestamp: true
  )
  |> S3.generate_presigned_upload_urls(expires_in: 300)
```

## 3. Download File with Presigned URL

```elixir
# Simple download URL
{:ok, url} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.presigned_download_url("documents/report.pdf", expires_in: 3600)

# Pipe-friendly version
{:ok, result} =
  "uploads/photo.jpg"
  |> S3.generate_presigned_download_url(
    Context.s3() |> Context.with_bucket("uploads"),
    expires_in: 3600
  )

# Batch download URLs
{:ok, results} =
  ["documents/file1.pdf", "documents/file2.jpg", "documents/file3.png"]
  |> S3.generate_presigned_download_urls(
    Context.s3() |> Context.with_bucket("uploads"),
    expires_in: 3600
  )

# Download file directly
{:ok, content} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.get_object("documents/report.pdf")

# Download to file
:ok =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.download_to_file("documents/report.pdf", "/tmp/report.pdf")
```

## Additional Operations

### Check if Object Exists

```elixir
{:ok, exists?} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.object_exists?("documents/report.pdf")
```

### Get Object Metadata (without downloading)

```elixir
{:ok, metadata} =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.head_object("documents/report.pdf")
```

### Copy Object

```elixir
:ok =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.copy_object("old/path/file.pdf", "new/path/file.pdf")
```

### Delete Object

```elixir
:ok =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.delete_object("documents/old-report.pdf")
```

### Upload from File System

```elixir
:ok =
  Context.s3()
  |> Context.with_bucket("uploads")
  |> S3.upload_file("documents/report.pdf", "/tmp/report.pdf")
```

## Common Patterns

### Upload Pipeline with Validation

```elixir
defmodule MyApp.FileUploader do
  alias Events.Services.Aws.{Context, S3}

  def upload_user_file(user_id, filename, content) do
    Context.s3()
    |> Context.with_bucket("user-uploads")
    |> S3.upload_normalized(
      filename,
      content,
      prefix: "users/#{user_id}",
      add_timestamp: true,
      metadata: %{
        "user_id" => to_string(user_id),
        "uploaded_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "ip_address" => get_client_ip()
      }
    )
  end

  def generate_upload_url(user_id, filename) do
    Context.s3()
    |> Context.with_bucket("user-uploads")
    |> S3.presigned_upload_url(
      filename,
      prefix: "users/#{user_id}",
      add_timestamp: true,
      expires_in: 300
    )
  end

  def list_user_files(user_id) do
    Context.s3()
    |> Context.with_bucket("user-uploads")
    |> S3.list_files("users/#{user_id}/")
  end

  def download_url(user_id, filename) do
    Context.s3()
    |> Context.with_bucket("user-uploads")
    |> S3.presigned_download_url("users/#{user_id}/#{filename}", expires_in: 3600)
  end
end
```

## IEx Quick Commands

```elixir
# Start IEx with environment loaded
iex -S mix

# Quick context setup
alias Events.Services.Aws.{Context, S3}
ctx = Context.s3() |> Context.with_bucket("your-bucket")

# List files
S3.list_files(ctx, "uploads/")

# Upload test file
S3.upload(ctx, "test.txt", "Hello, World!", metadata: %{"timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()})

# Generate download URL
S3.presigned_download_url(ctx, "test.txt", expires_in: 3600)

# Generate upload URL
S3.presigned_upload_url(ctx, "new-file.jpg", expires_in: 300)
```

## Environment Variables Required

```bash
# In .mise.toml or .env
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=ap-southeast-1
AWS_ENDPOINT_URL_S3=http://31.97.231.247:9000  # For MinIO
AWS_S3_FORCE_PATH_STYLE=true                    # For MinIO
S3_BUCKET=your-default-bucket                   # Optional default bucket
```
