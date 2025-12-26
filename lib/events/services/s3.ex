defmodule Events.Services.S3 do
  @moduledoc """
  S3 service for the Events application.

  This is a thin wrapper around `OmS3` that provides a convenient API
  for S3 operations within the Events application.

  See `OmS3` for full documentation.

  ## Examples

      # Direct API
      config = S3.config(access_key_id: "...", secret_access_key: "...")
      S3.put("s3://bucket/file.txt", "content", config)

      # Pipeline API
      S3.from_env()
      |> S3.bucket("my-bucket")
      |> S3.put("file.txt", "content")

  ## S3 URIs

  All operations accept `s3://bucket/key` URIs:

      "s3://my-bucket/path/to/file.txt"
      "s3://my-bucket/prefix/"
      "s3://my-bucket"
  """

  # ============================================
  # Re-export OmS3 types
  # ============================================

  @type config :: OmS3.config()
  @type request :: OmS3.request()
  @type uri :: OmS3.uri()

  # ============================================
  # Configuration
  # ============================================

  defdelegate config(opts), to: OmS3
  defdelegate from_env(), to: OmS3

  # ============================================
  # Pipeline API - Constructor & Chainable Options
  # ============================================

  defdelegate new(config_or_opts), to: OmS3
  defdelegate bucket(req, bucket), to: OmS3
  defdelegate prefix(req, prefix), to: OmS3
  defdelegate content_type(req, content_type), to: OmS3
  defdelegate metadata(req, metadata), to: OmS3
  defdelegate acl(req, acl), to: OmS3
  defdelegate storage_class(req, storage_class), to: OmS3
  defdelegate expires_in(req, duration), to: OmS3
  defdelegate method(req, method), to: OmS3
  defdelegate concurrency(req, concurrency), to: OmS3
  defdelegate timeout(req, duration), to: OmS3

  # ============================================
  # Core Operations (Dual API)
  # ============================================

  defdelegate put(req_or_uri, key_or_content, content_or_config, opts \\ []), to: OmS3
  defdelegate get(req_or_uri, key_or_config), to: OmS3
  defdelegate delete(req_or_uri, key_or_config), to: OmS3
  defdelegate exists?(req_or_uri, key_or_config), to: OmS3
  defdelegate head(req_or_uri, key_or_config), to: OmS3
  defdelegate list(req_or_uri, config_or_uri \\ nil, opts \\ []), to: OmS3
  defdelegate list_all(uri, config, opts \\ []), to: OmS3
  defdelegate copy(req_or_source, source_or_dest, dest_or_config), to: OmS3

  # ============================================
  # Presigned URLs
  # ============================================

  defdelegate presign(req_or_uri, config_or_key, opts \\ []), to: OmS3
  defdelegate presign_get(uri, config, opts \\ []), to: OmS3
  defdelegate presign_put(uri, config, opts \\ []), to: OmS3

  # ============================================
  # Batch Operations
  # ============================================

  defdelegate put_all(req_or_files, files_or_config, opts \\ []), to: OmS3
  defdelegate get_all(req_or_uris, uris_or_config, opts \\ []), to: OmS3
  defdelegate copy_all(req_or_source, source_or_config, opts \\ []), to: OmS3
  defdelegate delete_all(req_or_uris, uris_or_config, opts \\ []), to: OmS3
  defdelegate presign_all(req_or_uris, uris_or_config, opts \\ []), to: OmS3

  # ============================================
  # File Name Utilities
  # ============================================

  defdelegate normalize_key(filename, opts \\ []), to: OmS3
  defdelegate uri(bucket, key), to: OmS3
  defdelegate parse_uri(uri), to: OmS3
end

# Submodule aliases for compatibility
defmodule Events.Services.S3.Config do
  @moduledoc """
  S3 configuration. See `OmS3.Config` for documentation.
  """
  defdelegate new(opts), to: OmS3.Config
  defdelegate from_env(), to: OmS3.Config
end

defmodule Events.Services.S3.URI do
  @moduledoc """
  S3 URI utilities. See `OmS3.URI` for documentation.
  """
  defdelegate parse(uri), to: OmS3.URI
  defdelegate parse!(uri), to: OmS3.URI
  defdelegate valid?(uri), to: OmS3.URI
  defdelegate build(bucket, key), to: OmS3.URI
  defdelegate bucket(uri), to: OmS3.URI
  defdelegate key(uri), to: OmS3.URI
  defdelegate join(base_uri, path), to: OmS3.URI
  defdelegate parent(uri), to: OmS3.URI
  defdelegate filename(uri), to: OmS3.URI
  defdelegate extname(uri), to: OmS3.URI
end

defmodule Events.Services.S3.Request do
  @moduledoc """
  S3 pipeline request builder. See `OmS3.Request` for documentation.
  """
  defdelegate new(config_or_opts), to: OmS3.Request
  defdelegate from_env(), to: OmS3.Request
end

defmodule Events.Services.S3.FileNameNormalizer do
  @moduledoc """
  File name normalizer for S3. See `OmS3.FileNameNormalizer` for documentation.
  """
  defdelegate normalize(filename, opts \\ []), to: OmS3.FileNameNormalizer
  defdelegate unique_filename(filename, opts \\ []), to: OmS3.FileNameNormalizer
  defdelegate timestamped_filename(filename, opts \\ []), to: OmS3.FileNameNormalizer
  defdelegate sanitize(filename), to: OmS3.FileNameNormalizer
end
