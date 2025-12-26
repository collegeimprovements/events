# OmS3

Ergonomic S3 client with presigned URLs, streaming, and file utilities.

## Installation

```elixir
def deps do
  [{:om_s3, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
# Configure
config = OmS3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)

# Pipeline API
OmS3.new(config)
|> OmS3.bucket("my-bucket")
|> OmS3.put("path/file.txt", "content")
|> OmS3.run()
```

## Pipeline API

```elixir
# Upload
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.prefix("images/")
|> OmS3.content_type("image/jpeg")
|> OmS3.acl("public-read")
|> OmS3.put("photo.jpg", image_data)
|> OmS3.run()

# Download
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.get("images/photo.jpg")
|> OmS3.run()

# Delete
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.delete("images/photo.jpg")
|> OmS3.run()

# List
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.prefix("images/")
|> OmS3.list()
|> OmS3.run()
```

## Presigned URLs

```elixir
# Upload URL (PUT)
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.method(:put)
|> OmS3.expires_in({15, :minutes})
|> OmS3.presign("photos/new.jpg")

# Download URL (GET)
OmS3.new(config)
|> OmS3.bucket("uploads")
|> OmS3.expires_in({1, :hour})
|> OmS3.presign("photos/existing.jpg")
```

## S3 URIs

```elixir
# Build URI
OmS3.uri("my-bucket", "path/file.txt")
# => "s3://my-bucket/path/file.txt"

# Parse URI
{:ok, "my-bucket", "path/file.txt"} = OmS3.parse_uri("s3://my-bucket/path/file.txt")
```

## File Name Utilities

```elixir
# Normalize for S3
OmS3.normalize_key("User's Photo (1).jpg")
# => "users-photo-1.jpg"

OmS3.normalize_key("file.txt", prefix: "uploads", timestamp: true)
# => "uploads/file-20240115-143022.txt"

OmS3.normalize_key("file.txt", uuid: true)
# => "file-550e8400-e29b-41d4-a716-446655440000.txt"
```

## Configuration Options

```elixir
OmS3.config(
  access_key_id: "...",
  secret_access_key: "...",
  region: "us-east-1",             # Default: us-east-1
  endpoint: "http://localhost:4566", # Custom endpoint (LocalStack)
  proxy: {"proxy.example.com", 8080}, # HTTP proxy
  connect_timeout: 30_000,
  receive_timeout: 60_000
)
```

## Request Options

```elixir
|> OmS3.content_type("image/jpeg")
|> OmS3.acl("public-read")         # private, public-read, etc.
|> OmS3.storage_class("GLACIER")   # STANDARD, GLACIER, etc.
|> OmS3.metadata(%{user_id: "123"})
|> OmS3.expires_in({5, :minutes})
|> OmS3.timeout({2, :minutes})
|> OmS3.concurrency(10)            # For batch operations
```

## License

MIT
