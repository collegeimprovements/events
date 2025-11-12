# S3 Service

Clean, pipe-friendly S3 operations with automatic file normalization and error handling.

## Features

✅ **Pipe-Friendly API** - Clean, composable operations
✅ **Presigned URLs** - Upload and download with expiration
✅ **Batch Operations** - Process multiple files at once
✅ **File Normalization** - Automatic sanitization
✅ **Metadata Support** - Store custom data (username, timestamps, etc.)
✅ **Timestamp Tracking** - All operations track creation/modification times
✅ **Smart Sorting** - Sort files by last_modified (default), size, or name
✅ **Error Handling** - Comprehensive error messages

## Quick Start

### Single File Upload

```elixir
alias Events.Services.Aws.{Context, S3}

context = Context.from_config()

# Clean pipe workflow
{:ok, result} =
  "User's Photo (Final).jpg"
  |> S3.prepare(context, prefix: "uploads/users/123")
  |> S3.generate_presigned_upload_url(expires_in: 300)

# Returns:
# %{
#   url: "https://bucket.s3.amazonaws.com/...",
#   key: "uploads/users/123/users-photo-final.jpg",
#   original: "User's Photo (Final).jpg",
#   expires_at: ~U[2024-01-12 14:35:00Z],
#   generated_at: ~U[2024-01-12 14:30:00Z],
#   method: :put
# }

# Client uploads: HTTP PUT to result.url with file content
```

### Upload with Metadata

```elixir
# Store username and context with file
{:ok, result} =
  "report.pdf"
  |> S3.prepare(context,
    prefix: "uploads",
    metadata: %{
      "username" => "john.doe",
      "user_id" => "12345",
      "department" => "engineering",
      "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
  )
  |> S3.generate_presigned_upload_url(expires_in: 300)

# Metadata is stored in S3 with the file!

# Later, retrieve metadata:
{:ok, headers} = S3.head_object(context, "uploads/report.pdf")
username = headers["x-amz-meta-username"]
user_id = headers["x-amz-meta-user_id"]
```

### Batch Upload

```elixir
{:ok, results} =
  ["photo1.jpg", "photo2.jpg", "document.pdf"]
  |> S3.prepare_batch(context, prefix: "uploads", add_timestamp: true)
  |> S3.generate_presigned_upload_urls(expires_in: 300)

# Returns list of presigned URLs for each file
Enum.each(results, fn %{url: url, key: key} ->
  IO.puts("Upload #{key} to: #{url}")
end)
```

### Single File Download

```elixir
{:ok, result} =
  "uploads/document.pdf"
  |> S3.generate_presigned_download_url(context, expires_in: 3600)

# Works with different path formats:
"s3://bucket/file.pdf" |> S3.generate_presigned_download_url(context)
"https://bucket.s3.amazonaws.com/file.pdf" |> S3.generate_presigned_download_url(context)
```

### Batch Download

```elixir
{:ok, results} =
  ["uploads/file1.pdf", "uploads/file2.jpg", "s3://bucket/file3.png"]
  |> S3.generate_presigned_download_urls(context, expires_in: 3600)

# Share URLs with users
Enum.each(results, fn %{url: url} ->
  send_to_user(url)
end)
```

### List Files (Sorted)

```elixir
# List files sorted by last modified (newest first) - DEFAULT
{:ok, result} = S3.list_files(context, "uploads/")

# Sort by size (largest first)
{:ok, result} = S3.list_files(context, "uploads/", sort_by: :size, sort_order: :desc)

# Sort by name (A-Z)
{:ok, result} = S3.list_files(context, "uploads/", sort_by: :key, sort_order: :asc)

# Access file details
Enum.each(result.objects, fn obj ->
  IO.puts("#{obj.key} - #{obj.size} bytes - modified: #{obj.last_modified}")
end)
```

## API Reference

### Upload Workflow

```elixir
# Step 1: Prepare file (normalizes name)
{:ok, prepared} = S3.prepare(filename, context, opts)

# Step 2: Generate presigned URL
{:ok, result} = S3.generate_presigned_upload_url(prepared, opts)

# Or pipe it:
filename
|> S3.prepare(context, opts)
|> S3.generate_presigned_upload_url(opts)
```

**Prepare Options:**
- `:prefix` - Path prefix (e.g., "uploads/users/123")
- `:add_timestamp` - Add timestamp to filename
- `:add_uuid` - Add UUID to filename
- `:separator` - Character to replace spaces (default: "-")
- `:preserve_case` - Keep original case
- `:metadata` - Custom metadata map

**Presigned URL Options:**
- `:expires_in` - Expiration in seconds (default: 3600)

**Returns:**
- `url` - Presigned URL
- `key` - S3 key
- `original` - Original filename
- `expires_at` - When URL expires (DateTime)
- `generated_at` - When URL was generated (DateTime)
- `method` - `:get` or `:put`

### Download Workflow

```elixir
# Single file
path_or_url
|> S3.generate_presigned_download_url(context, opts)

# Multiple files
[path1, path2, path3]
|> S3.generate_presigned_download_urls(context, opts)
```

**Supported Path Formats:**
- S3 key: `"uploads/file.pdf"`
- S3 URL: `"s3://bucket/file.pdf"`
- HTTPS URL: `"https://bucket.s3.amazonaws.com/file.pdf"`

### Batch Operations

```elixir
# Batch upload
filenames
|> S3.prepare_batch(context, opts)
|> S3.generate_presigned_upload_urls(opts)

# Batch download
paths
|> S3.generate_presigned_download_urls(context, opts)
```

### List Files with Sorting

```elixir
S3.list_files(context, prefix, opts)
```

**Options:**
- `:prefix` - Filter by prefix
- `:max_keys` - Maximum files to return (default: 1000)
- `:continuation_token` - For pagination
- `:sort_by` - Sort by `:last_modified` (default), `:size`, or `:key`
- `:sort_order` - `:desc` (default, newest/largest first) or `:asc`

**Returns:**
```elixir
%{
  objects: [
    %{
      key: "uploads/file.pdf",
      size: 1024,
      last_modified: ~U[2024-01-12 14:30:00Z],
      etag: "\"abc123\"",
      storage_class: "STANDARD"
    },
    ...
  ],
  continuation_token: "..." # or nil
}
```

## Error Handling

All operations return `{:ok, result}` or `{:error, error}`:

```elixir
case S3.prepare("", context) do
  {:ok, prepared} ->
    # Success
    prepared

  {:error, %{error: reason, message: msg, original: file}} ->
    # Error with details
    Logger.error("Failed to prepare #{file}: #{msg}")
    {:error, reason}
end
```

**Error Structure:**
```elixir
%{
  error: :empty_filename | :invalid_url | {:s3_error, status, body} | ...,
  original: "original filename or path",
  message: "Human-readable error message"
}
```

**Common Errors:**
- `:empty_filename` - Filename is empty
- `:nil_filename` - Filename is nil
- `:invalid_filename_type` - Filename is not a string
- `:missing_access_key_id` - AWS credentials missing
- `:invalid_s3_url` - Malformed S3 URL
- `{:s3_error, status, body}` - S3 API error
- `{:presign_error, reason}` - Failed to generate presigned URL

## Examples

### User File Upload with Metadata

```elixir
defmodule MyApp.FileUpload do
  alias Events.Services.Aws.{Context, S3}

  def handle_upload(user_id, filename, file_content) do
    context = Context.from_config()

    # Generate presigned URL
    with {:ok, prepared} <- S3.prepare(filename, context,
           prefix: "users/#{user_id}",
           add_timestamp: true,
           metadata: %{"user_id" => to_string(user_id)}
         ),
         {:ok, result} <- S3.generate_presigned_upload_url(prepared, expires_in: 300) do

      # Return upload instructions to client
      {:ok, %{
        upload_url: result.url,
        s3_key: result.key,
        expires_at: result.expires_at,
        instructions: "PUT file content to upload_url"
      }}
    end
  end

  def get_download_url(s3_key) do
    context = Context.from_config()

    s3_key
    |> S3.generate_presigned_download_url(context, expires_in: 3600)
  end
end
```

### Bulk File Processing

```elixir
defmodule MyApp.BulkProcessor do
  alias Events.Services.Aws.{Context, S3}

  def process_user_uploads(user_id, filenames) do
    context = Context.from_config()

    # Generate upload URLs for all files
    case S3.prepare_batch(filenames, context,
           prefix: "users/#{user_id}/uploads",
           add_timestamp: true
         )
         |> S3.generate_presigned_upload_urls(expires_in: 600) do

      {:ok, results} ->
        # Success - return all URLs
        uploads = Enum.map(results, fn r ->
          %{file: r.original, url: r.url, key: r.key}
        end)
        {:ok, uploads}

      {:error, errors} ->
        # Some files failed
        {:error, errors}
    end
  end

  def get_user_files(user_id) do
    context = Context.from_config()

    # List files
    {:ok, %{objects: objects}} = S3.list_files(context, "users/#{user_id}/uploads/")

    # Generate download URLs for all
    keys = Enum.map(objects, & &1.key)

    case S3.generate_presigned_download_urls(keys, context, expires_in: 7200) do
      {:ok, results} ->
        files = Enum.map(results, fn r ->
          %{
            key: r.key,
            url: r.url,
            expires_at: r.expires_at
          }
        end)
        {:ok, files}

      {:error, errors} ->
        {:error, errors}
    end
  end
end
```

### Direct Upload/Download

```elixir
# Traditional API still available
context = Context.from_config()

# Direct upload
:ok = S3.upload(context, "path/file.pdf", content)

# Direct download
{:ok, content} = S3.get_object(context, "path/file.pdf")

# With normalization
{:ok, key} = S3.upload_normalized(context, "My File.pdf", content,
  prefix: "uploads",
  add_timestamp: true
)
```

## Configuration

```elixir
# config/config.exs
config :events, :aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: "us-east-1",
  bucket: "my-bucket"

# For S3-compatible services (MinIO, DigitalOcean Spaces, etc.)
config :events, :aws,
  access_key_id: "...",
  secret_access_key: "...",
  region: "us-east-1",
  bucket: "my-bucket",
  endpoint_url: "http://localhost:9000"
```

## File Normalization

All files are automatically normalized:

| Original | Normalized |
|----------|------------|
| `User's Photo (1).jpg` | `users-photo-1.jpg` |
| `My Document [Final].pdf` | `my-document-final.pdf` |
| `IMG 2024.jpg` | `img-2024.jpg` |

With timestamp:
```elixir
S3.prepare("file.txt", context, add_timestamp: true)
# => "file-20240112-143022.txt"
```

With UUID:
```elixir
S3.prepare("file.txt", context, add_uuid: true)
# => "file-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt"
```

## Implementation

- **Core**: `Events.Services.Aws.S3` - Main module
- **Adapter**: `Events.Services.Aws.S3.Adapter` - ReqS3 implementation
- **Pipeline**: `Events.Services.Aws.S3.Pipeline` - Pipe-friendly API
- **Normalizer**: `Events.Services.Aws.S3.FileNameNormalizer` - File sanitization
- **Dependency**: `req_s3` (~> 0.2.3) - Official ReqS3 plugin

## Testing

```bash
# Run all S3 tests
mix test test/events/services/aws/s3/

# Run specific tests
mix test test/events/services/aws/s3/pipeline_test.exs
```

**Test Results**: 35 tests passing ✅

## Best Practices

1. **Use pipes** for cleaner code
2. **Always handle errors** - operations return `{:ok, result}` or `{:error, error}`
3. **Set appropriate expiration times:**
   - Uploads: 5-15 minutes
   - Temporary downloads: 1-24 hours
   - Shared links: 7 days
4. **Add timestamps** for versioning
5. **Use prefixes** to organize files
6. **Batch operations** for multiple files
7. **Store metadata** for tracking

## Files

```
lib/events/services/aws/s3/
├── s3.ex                      # Main module with public API
├── adapter.ex                 # ReqS3 adapter (~220 lines)
├── pipeline.ex                # Pipe-friendly operations (~350 lines)
├── file_name_normalizer.ex    # File sanitization (~230 lines)
├── uploader.ex                # Upload helpers (~330 lines)
├── README.md                  # This file
└── METADATA_GUIDE.md          # Metadata usage guide

test/events/services/aws/s3/
├── file_name_normalizer_test.exs  # 24 tests
└── pipeline_test.exs               # 11 tests
```

## More Information

- **ReqS3**: https://hexdocs.pm/req_s3
- **Req**: https://hexdocs.pm/req
- **AWS S3**: https://docs.aws.amazon.com/s3/

---

**Summary**: Clean, pipe-friendly S3 service with presigned URLs, batch operations, automatic file normalization, and comprehensive error handling.
