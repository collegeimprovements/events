defmodule Events.Services.Aws.SimpleS3 do
  @moduledoc """
  Simple, obvious S3 client.

  A radically simplified API for S3 operations. No complex contexts,
  no adapter patterns - just simple, clear function names.

  ## Design Principles

  1. **Bucket-first API** - Bucket name is always the first argument
  2. **Clear verbs** - `upload`, `download`, `list`, `delete`, `exists?`
  3. **Sensible defaults** - Common cases work with zero options
  4. **Optional connection** - Use ENV vars or explicit credentials

  ## Quick Examples

      # List files
      SimpleS3.list("my-bucket")
      SimpleS3.list("my-bucket", prefix: "uploads/")

      # Upload
      SimpleS3.upload("my-bucket", "photo.jpg", file_content)
      SimpleS3.upload("my-bucket", "doc.pdf", content, type: "application/pdf")

      # Download
      {:ok, content} = SimpleS3.download("my-bucket", "photo.jpg")

      # Check existence
      SimpleS3.exists?("my-bucket", "photo.jpg")  #=> true | false

      # Delete
      SimpleS3.delete("my-bucket", "photo.jpg")

      # Generate URLs
      {:ok, url} = SimpleS3.url_for_upload("my-bucket", "photo.jpg")
      {:ok, url} = SimpleS3.url_for_download("my-bucket", "photo.jpg")

  ## With Explicit Credentials

      aws = Aws.connect(key: "...", secret: "...", region: "us-east-1")

      SimpleS3.list(aws, "my-bucket")
      SimpleS3.upload(aws, "my-bucket", "file.txt", content)
  """

  alias Events.Services.Aws
  alias Events.Services.Aws.S3.Adapter

  @type conn :: Aws.connection_or_nil()
  @type bucket :: String.t()
  @type key :: String.t()
  @type content :: binary()

  ## List Operations

  @doc """
  Lists files in a bucket.

  ## Options

  - `:prefix` - Only list files with this prefix (default: "")
  - `:limit` - Maximum files to return (default: 1000)
  - `:token` - Continuation token for pagination

  ## Returns

  `{:ok, %{files: [...], next_token: token | nil}}` or `{:error, reason}`

  ## Examples

      # List all files
      {:ok, %{files: files}} = SimpleS3.list("my-bucket")

      # List with prefix
      {:ok, %{files: files}} = SimpleS3.list("my-bucket", prefix: "uploads/")

      # Pagination
      {:ok, %{files: page1, next_token: token}} =
        SimpleS3.list("my-bucket", limit: 100)

      {:ok, %{files: page2}} =
        SimpleS3.list("my-bucket", limit: 100, token: token)

      # With explicit credentials
      {:ok, %{files: files}} = SimpleS3.list(aws, "my-bucket")
  """
  @spec list(bucket(), keyword()) ::
          {:ok, %{files: [map()], next_token: String.t() | nil}} | {:error, term()}
  @spec list(conn(), bucket(), keyword()) ::
          {:ok, %{files: [map()], next_token: String.t() | nil}} | {:error, term()}

  def list(bucket, opts \\ [])
  def list(bucket, opts) when is_binary(bucket) and is_list(opts), do: list(nil, bucket, opts)

  def list(conn, bucket, opts) when is_binary(bucket) and is_list(opts) do
    context = Aws.to_context(conn, bucket: bucket)

    adapter_opts = [
      prefix: Keyword.get(opts, :prefix, ""),
      max_keys: Keyword.get(opts, :limit, 1000),
      continuation_token: Keyword.get(opts, :token)
    ]

    case Adapter.list_objects(context, adapter_opts) do
      {:ok, %{objects: objects, continuation_token: token}} ->
        {:ok,
         %{
           files: Enum.map(objects, &normalize_file/1),
           next_token: token
         }}

      error ->
        error
    end
  end

  defp normalize_file(obj) do
    %{
      path: obj.key,
      size: obj.size,
      modified_at: obj.last_modified,
      etag: obj.etag
    }
  end

  @doc """
  Lists all files recursively (handles pagination automatically).

  ## Options

  - `:prefix` - Only list files with this prefix (default: "")

  ## Examples

      # Get all files
      {:ok, all_files} = SimpleS3.list_all("my-bucket")

      # Get all files in folder
      {:ok, files} = SimpleS3.list_all("my-bucket", prefix: "uploads/")
  """
  @spec list_all(bucket(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @spec list_all(conn(), bucket(), keyword()) :: {:ok, [map()]} | {:error, term()}

  def list_all(bucket, opts \\ [])
  def list_all(bucket, opts) when is_binary(bucket) and is_list(opts), do: list_all(nil, bucket, opts)

  def list_all(conn, bucket, opts) when is_binary(bucket) and is_list(opts) do
    do_list_all(conn, bucket, opts, [])
  end

  defp do_list_all(conn, bucket, opts, accumulated) do
    case list(conn, bucket, opts) do
      {:ok, %{files: files, next_token: nil}} ->
        {:ok, accumulated ++ files}

      {:ok, %{files: files, next_token: token}} ->
        new_opts = Keyword.put(opts, :token, token)
        do_list_all(conn, bucket, new_opts, accumulated ++ files)

      error ->
        error
    end
  end

  ## Upload Operations

  @doc """
  Uploads a file to S3.

  ## Options

  - `:type` - Content type (default: "application/octet-stream")
  - `:metadata` - Custom metadata map
  - `:public` - Make file public (default: false)

  ## Examples

      # Simple upload
      SimpleS3.upload("my-bucket", "photo.jpg", image_binary)

      # With content type
      SimpleS3.upload("my-bucket", "doc.pdf", pdf_content,
        type: "application/pdf"
      )

      # With metadata
      SimpleS3.upload("my-bucket", "file.txt", content,
        metadata: %{"user_id" => "123", "version" => "2"}
      )

      # Public file
      SimpleS3.upload("my-bucket", "public/logo.png", content,
        public: true
      )
  """
  @spec upload(bucket(), key(), content(), keyword()) :: :ok | {:error, term()}
  @spec upload(conn(), bucket(), key(), content(), keyword()) :: :ok | {:error, term()}

  def upload(bucket, path, content, opts \\ [])
  def upload(bucket, path, content, opts) when is_binary(bucket) and is_binary(path) and is_list(opts),
    do: upload(nil, bucket, path, content, opts)

  def upload(conn, bucket, path, content, opts) when is_binary(bucket) and is_binary(path) and is_list(opts) do
    context = Aws.to_context(conn, bucket: bucket)

    upload_opts = [
      content_type: Keyword.get(opts, :type, "application/octet-stream"),
      metadata: Keyword.get(opts, :metadata, %{}),
      acl: if(Keyword.get(opts, :public, false), do: "public-read", else: "private")
    ]

    Adapter.upload(context, path, content, upload_opts)
  end

  ## Download Operations

  @doc """
  Downloads a file from S3.

  ## Examples

      {:ok, content} = SimpleS3.download("my-bucket", "photo.jpg")
      {:ok, pdf} = SimpleS3.download("my-bucket", "documents/report.pdf")

      # With explicit credentials
      {:ok, content} = SimpleS3.download(aws, "my-bucket", "file.txt")
  """
  @spec download(bucket(), key()) :: {:ok, binary()} | {:error, term()}
  @spec download(conn(), bucket(), key()) :: {:ok, binary()} | {:error, term()}

  def download(bucket, path) when is_binary(bucket) and is_binary(path), do: download(nil, bucket, path)

  def download(conn, bucket, path) when is_binary(bucket) and is_binary(path) do
    context = Aws.to_context(conn, bucket: bucket)
    Adapter.get_object(context, path)
  end

  ## Delete Operations

  @doc """
  Deletes a file from S3.

  ## Examples

      :ok = SimpleS3.delete("my-bucket", "old-file.txt")

      # With explicit credentials
      :ok = SimpleS3.delete(aws, "my-bucket", "file.txt")
  """
  @spec delete(bucket(), key()) :: :ok | {:error, term()}
  @spec delete(conn(), bucket(), key()) :: :ok | {:error, term()}

  def delete(bucket, path) when is_binary(bucket) and is_binary(path), do: delete(nil, bucket, path)

  def delete(conn, bucket, path) when is_binary(bucket) and is_binary(path) do
    context = Aws.to_context(conn, bucket: bucket)
    Adapter.delete_object(context, path)
  end

  ## Existence Checks

  @doc """
  Checks if a file exists in S3.

  ## Examples

      SimpleS3.exists?("my-bucket", "photo.jpg")
      #=> true

      SimpleS3.exists?("my-bucket", "missing.txt")
      #=> false
  """
  @spec exists?(bucket(), key()) :: boolean()
  @spec exists?(conn(), bucket(), key()) :: boolean()

  def exists?(bucket, path) when is_binary(bucket) and is_binary(path), do: exists?(nil, bucket, path)

  def exists?(conn, bucket, path) when is_binary(bucket) and is_binary(path) do
    context = Aws.to_context(conn, bucket: bucket)

    case Adapter.object_exists?(context, path) do
      {:ok, true} -> true
      _ -> false
    end
  end

  ## URL Generation

  @doc """
  Generates a presigned URL for uploading a file.

  ## Options

  - `:expires` - Expiration in seconds (default: 3600 - 1 hour)
  - `:type` - Content type for the upload
  - `:metadata` - Custom metadata

  ## Examples

      # Simple upload URL
      {:ok, url} = SimpleS3.url_for_upload("my-bucket", "photo.jpg")

      # With expiration (5 minutes)
      {:ok, url} = SimpleS3.url_for_upload("my-bucket", "file.pdf",
        expires: 300
      )

      # With content type
      {:ok, url} = SimpleS3.url_for_upload("my-bucket", "image.png",
        type: "image/png",
        expires: 1800
      )
  """
  @spec url_for_upload(bucket(), key(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @spec url_for_upload(conn(), bucket(), key(), keyword()) :: {:ok, String.t()} | {:error, term()}

  def url_for_upload(bucket, path, opts \\ [])
  def url_for_upload(bucket, path, opts) when is_binary(bucket) and is_binary(path) and is_list(opts),
    do: url_for_upload(nil, bucket, path, opts)

  def url_for_upload(conn, bucket, path, opts) when is_binary(bucket) and is_binary(path) and is_list(opts) do
    context = Aws.to_context(conn, bucket: bucket)
    expires_in = Keyword.get(opts, :expires, 3600)

    presign_opts = [expires_in: expires_in]

    Adapter.presigned_url(context, :put, path, presign_opts)
  end

  @doc """
  Generates a presigned URL for downloading a file.

  ## Options

  - `:expires` - Expiration in seconds (default: 3600 - 1 hour)

  ## Examples

      # Simple download URL
      {:ok, url} = SimpleS3.url_for_download("my-bucket", "photo.jpg")

      # Short-lived URL (5 minutes)
      {:ok, url} = SimpleS3.url_for_download("my-bucket", "secret.pdf",
        expires: 300
      )
  """
  @spec url_for_download(bucket(), key(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @spec url_for_download(conn(), bucket(), key(), keyword()) :: {:ok, String.t()} | {:error, term()}

  def url_for_download(bucket, path, opts \\ [])
  def url_for_download(bucket, path, opts) when is_binary(bucket) and is_binary(path) and is_list(opts),
    do: url_for_download(nil, bucket, path, opts)

  def url_for_download(conn, bucket, path, opts) when is_binary(bucket) and is_binary(path) and is_list(opts) do
    context = Aws.to_context(conn, bucket: bucket)
    expires_in = Keyword.get(opts, :expires, 3600)

    presign_opts = [expires_in: expires_in]

    Adapter.presigned_url(context, :get, path, presign_opts)
  end

  ## Copy Operations

  @doc """
  Copies a file within S3.

  ## Examples

      # Copy within same bucket
      SimpleS3.copy("my-bucket", "old-path.jpg", "new-path.jpg")

      # Copy between buckets
      SimpleS3.copy("source-bucket", "file.txt",
        to_bucket: "dest-bucket",
        to_path: "copied-file.txt"
      )
  """
  @spec copy(bucket(), key(), key() | keyword()) :: :ok | {:error, term()}
  @spec copy(conn(), bucket(), key(), key() | keyword()) :: :ok | {:error, term()}

  def copy(source_bucket, source_path, destination)
      when is_binary(source_bucket) and is_binary(source_path),
      do: copy(nil, source_bucket, source_path, destination)

  def copy(conn, source_bucket, source_path, destination_path)
      when is_binary(source_bucket) and is_binary(source_path) and is_binary(destination_path) do
    context = Aws.to_context(conn, bucket: source_bucket)
    source_key = source_path
    Adapter.copy_object(context, source_key, destination_path)
  end

  def copy(conn, source_bucket, source_path, opts)
      when is_binary(source_bucket) and is_binary(source_path) and is_list(opts) do
    dest_bucket = Keyword.get(opts, :to_bucket, source_bucket)
    dest_path = Keyword.fetch!(opts, :to_path)

    context = Aws.to_context(conn, bucket: dest_bucket)
    source_key = source_path
    Adapter.copy_object(context, source_key, dest_path)
  end

  ## Utility Operations

  @doc """
  Gets file metadata without downloading content.

  ## Examples

      {:ok, info} = SimpleS3.info("my-bucket", "photo.jpg")

      # Returns:
      # %{
      #   size: 524288,
      #   modified_at: ~U[2024-01-15 10:30:00Z],
      #   content_type: "image/jpeg",
      #   etag: "abc123..."
      # }
  """
  @spec info(bucket(), key()) :: {:ok, map()} | {:error, term()}
  @spec info(conn(), bucket(), key()) :: {:ok, map()} | {:error, term()}

  def info(bucket, path) when is_binary(bucket) and is_binary(path), do: info(nil, bucket, path)

  def info(conn, bucket, path) when is_binary(bucket) and is_binary(path) do
    context = Aws.to_context(conn, bucket: bucket)

    case Adapter.head_object(context, path) do
      {:ok, metadata} ->
        parsed_metadata = parse_metadata(metadata)
        {:ok, parsed_metadata}

      error ->
        error
    end
  end

  defp parse_metadata(metadata) when is_map(metadata) do
    %{
      size: get_header(metadata, "content-length") |> parse_int(),
      modified_at: get_header(metadata, "last-modified") |> parse_date(),
      content_type: get_header(metadata, "content-type"),
      etag: get_header(metadata, "etag")
    }
  end

  defp get_header(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  end

  defp parse_int(nil), do: 0
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_date(nil), do: DateTime.utc_now()
  defp parse_date(%DateTime{} = dt), do: dt

  defp parse_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  @doc """
  Calculates total size of files matching a prefix.

  ## Examples

      {:ok, %{total_files: 42, total_bytes: 1048576}} =
        SimpleS3.folder_size("my-bucket", prefix: "uploads/2024/")
  """
  @spec folder_size(bucket(), keyword()) :: {:ok, map()} | {:error, term()}
  @spec folder_size(conn(), bucket(), keyword()) :: {:ok, map()} | {:error, term()}

  def folder_size(bucket, opts \\ [])
  def folder_size(bucket, opts) when is_binary(bucket) and is_list(opts), do: folder_size(nil, bucket, opts)

  def folder_size(conn, bucket, opts) when is_binary(bucket) and is_list(opts) do
    case list_all(conn, bucket, opts) do
      {:ok, files} ->
        total = Enum.reduce(files, 0, fn file, acc -> acc + file.size end)
        {:ok, %{total_files: length(files), total_bytes: total}}

      error ->
        error
    end
  end
end
