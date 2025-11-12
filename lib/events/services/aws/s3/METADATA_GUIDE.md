# S3 Metadata Guide

S3 allows you to store custom metadata with each file. This is perfect for tracking usernames, upload dates, file types, permissions, etc.

## What is Metadata?

S3 metadata are key-value pairs stored **with** the file. They're:
- ✅ Stored in S3 (not your database)
- ✅ Retrieved when you fetch file info
- ✅ Small (2KB limit per file)
- ✅ Perfect for tracking context

## Quick Examples

### Store Username on Upload

```elixir
context = Context.from_config()

# Prepare file with user metadata
{:ok, prepared} = S3.prepare(
  "report.pdf",
  context,
  prefix: "uploads",
  metadata: %{
    "username" => "john.doe",
    "user_id" => "12345",
    "department" => "engineering"
  }
)

{:ok, result} = S3.generate_presigned_upload_url(prepared, expires_in: 300)

# Client uploads to result.url
# Metadata is automatically stored with the file!
```

### Direct Upload with Metadata

```elixir
:ok = S3.upload(
  context,
  "documents/report.pdf",
  file_content,
  content_type: "application/pdf",
  metadata: %{
    "uploaded_by" => "jane.smith",
    "user_id" => "67890",
    "project" => "q4-analysis",
    "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now())
  }
)
```

### Retrieve Metadata

```elixir
# Get file metadata (without downloading content)
{:ok, metadata} = S3.head_object(context, "documents/report.pdf")

# Access custom metadata (prefixed with x-amz-meta-)
username = metadata["x-amz-meta-username"]
user_id = metadata["x-amz-meta-user_id"]
department = metadata["x-amz-meta-department"]

IO.puts("Uploaded by: #{username} (ID: #{user_id})")
IO.puts("Department: #{department}")
```

## Common Metadata Patterns

### 1. User Tracking

```elixir
metadata: %{
  "username" => "john.doe",
  "user_id" => "12345",
  "user_email" => "john@example.com"
}
```

### 2. Upload Context

```elixir
metadata: %{
  "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now()),
  "uploaded_from" => "web_app",
  "client_ip" => "192.168.1.1",
  "user_agent" => "Mozilla/5.0..."
}
```

### 3. File Classification

```elixir
metadata: %{
  "file_type" => "invoice",
  "category" => "financial",
  "year" => "2024",
  "quarter" => "Q1",
  "status" => "approved"
}
```

### 4. Access Control

```elixir
metadata: %{
  "visibility" => "private",
  "shared_with" => "team:engineering",
  "expiry_date" => "2024-12-31",
  "access_level" => "confidential"
}
```

### 5. Processing Status

```elixir
metadata: %{
  "processing_status" => "pending",
  "thumbnail_generated" => "false",
  "virus_scanned" => "true",
  "scan_result" => "clean"
}
```

## Complete Upload Workflow with Metadata

```elixir
defmodule MyApp.FileUpload do
  alias Events.Services.Aws.{Context, S3}

  def handle_user_upload(user, filename, file_content) do
    context = Context.from_config()

    # Rich metadata about the upload
    metadata = %{
      "username" => user.username,
      "user_id" => to_string(user.id),
      "user_email" => user.email,
      "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "original_filename" => filename,
      "file_size" => to_string(byte_size(file_content)),
      "content_type" => MIME.from_path(filename),
      "upload_source" => "web_interface",
      "app_version" => "1.0.0"
    }

    # Prepare and upload
    with {:ok, prepared} <- S3.prepare(
           filename,
           context,
           prefix: "users/#{user.id}/uploads",
           add_timestamp: true,
           metadata: metadata
         ),
         {:ok, result} <- S3.generate_presigned_upload_url(prepared, expires_in: 300) do

      {:ok, %{
        upload_url: result.url,
        s3_key: result.key,
        metadata_stored: Map.keys(metadata)
      }}
    end
  end

  def get_file_info(s3_key) do
    context = Context.from_config()

    case S3.head_object(context, s3_key) do
      {:ok, headers} ->
        # Extract custom metadata
        metadata = extract_custom_metadata(headers)

        {:ok, %{
          key: s3_key,
          size: headers["content-length"],
          content_type: headers["content-type"],
          last_modified: headers["last-modified"],
          custom_metadata: metadata
        }}

      error ->
        error
    end
  end

  defp extract_custom_metadata(headers) do
    headers
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "x-amz-meta-") end)
    |> Enum.map(fn {key, value} ->
      # Remove x-amz-meta- prefix
      clean_key = String.replace_prefix(key, "x-amz-meta-", "")
      {clean_key, value}
    end)
    |> Enum.into(%{})
  end
end
```

## Batch Upload with Different Metadata

```elixir
def batch_upload_with_metadata(user_id, files) do
  context = Context.from_config()

  # Prepare each file with unique metadata
  prepared_files =
    Enum.map(files, fn {filename, content, file_type} ->
      metadata = %{
        "user_id" => to_string(user_id),
        "file_type" => file_type,
        "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "original_name" => filename
      }

      S3.prepare(filename, context,
        prefix: "users/#{user_id}",
        add_timestamp: true,
        metadata: metadata
      )
    end)

  # Generate URLs
  case prepared_files do
    results when is_list(results) ->
      {:ok, prepared} = {:ok, Enum.map(results, fn {:ok, p} -> p end)}

      S3.generate_presigned_upload_urls(prepared, expires_in: 300)
  end
end
```

## Search Files by Metadata

While S3 doesn't support querying by metadata directly, you can:

1. **List and filter locally:**
```elixir
def find_files_by_user(user_id) do
  context = Context.from_config()

  # List all files
  {:ok, result} = S3.list_files(context, "uploads/")

  # Check metadata for each file
  matching_files =
    result.objects
    |> Enum.map(fn obj ->
      {:ok, meta} = S3.head_object(context, obj.key)
      {obj, meta}
    end)
    |> Enum.filter(fn {_obj, meta} ->
      meta["x-amz-meta-user_id"] == to_string(user_id)
    end)
    |> Enum.map(fn {obj, meta} -> %{obj | metadata: meta} end)

  {:ok, matching_files}
end
```

2. **Use prefixes for organization (better):**
```elixir
# Store files under user-specific prefixes
# uploads/user-123/file.pdf
# uploads/user-456/file.pdf

# Then list specific user's files:
{:ok, result} = S3.list_files(context, "uploads/user-#{user_id}/")
```

## Metadata Limits

- **Size**: Max 2KB per file for all metadata combined
- **Count**: No hard limit, but stay under 2KB total
- **Keys**: Case-insensitive, alphanumeric + hyphens/underscores
- **Values**: Strings only (convert numbers/dates to strings)

## Best Practices

✅ **DO:**
- Store user identifiers (username, user_id)
- Store timestamps (uploaded_at, expires_at)
- Store classification (category, type, status)
- Convert all values to strings
- Use snake_case for keys

❌ **DON'T:**
- Store sensitive data (passwords, tokens)
- Store large data (use separate database)
- Store frequently-changing data
- Use special characters in keys

## Practical Example: File Management System

```elixir
defmodule MyApp.FileManager do
  alias Events.Services.Aws.{Context, S3}

  def upload_document(user, filename, content, opts \\ []) do
    context = Context.from_config()

    metadata = %{
      # User info
      "user_id" => to_string(user.id),
      "username" => user.username,

      # File info
      "original_name" => filename,
      "file_type" => Keyword.get(opts, :file_type, "document"),

      # Timestamps
      "uploaded_at" => DateTime.to_iso8601(DateTime.utc_now()),

      # Classification
      "category" => Keyword.get(opts, :category, "general"),
      "visibility" => Keyword.get(opts, :visibility, "private"),

      # Processing
      "status" => "uploaded",
      "virus_scan" => "pending"
    }

    with {:ok, prepared} <- S3.prepare(
           filename,
           context,
           prefix: "documents/#{user.id}",
           add_timestamp: true,
           metadata: metadata
         ),
         {:ok, result} <- S3.generate_presigned_upload_url(prepared, expires_in: 600) do

      {:ok, %{
        upload_url: result.url,
        key: result.key,
        metadata: metadata
      }}
    end
  end

  def get_document_details(s3_key) do
    context = Context.from_config()

    with {:ok, headers} <- S3.head_object(context, s3_key) do
      metadata = extract_metadata(headers)

      {:ok, %{
        key: s3_key,
        size: parse_int(headers["content-length"]),
        uploaded_by: metadata["username"],
        user_id: metadata["user_id"],
        uploaded_at: metadata["uploaded_at"],
        category: metadata["category"],
        status: metadata["status"],
        virus_scan: metadata["virus_scan"]
      }}
    end
  end

  def update_processing_status(s3_key, status) do
    context = Context.from_config()

    # Get current metadata
    {:ok, headers} = S3.head_object(context, s3_key)
    current_metadata = extract_metadata(headers)

    # Update status
    new_metadata = Map.put(current_metadata, "status", status)

    # Re-upload with new metadata (copy to self with new metadata)
    # Note: This is a workaround since S3 doesn't support metadata-only updates
    # In production, you might track this in your database instead
  end

  defp extract_metadata(headers) do
    headers
    |> Enum.filter(fn {k, _} -> String.starts_with?(k, "x-amz-meta-") end)
    |> Enum.map(fn {k, v} -> {String.replace_prefix(k, "x-amz-meta-", ""), v} end)
    |> Enum.into(%{})
  end

  defp parse_int(str) when is_binary(str), do: String.to_integer(str)
  defp parse_int(int) when is_integer(int), do: int
end
```

## Summary

✅ **Metadata is already supported** in all upload operations
✅ Use `:metadata` option when preparing or uploading files
✅ Retrieve with `S3.head_object/2`
✅ Perfect for tracking context (username, timestamps, categories)
✅ Stored in S3 (not your database)
✅ Retrieved efficiently (without downloading file content)

**Pro Tip**: Combine metadata with organized prefixes (e.g., `users/123/uploads/`) for best performance!
