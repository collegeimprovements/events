defmodule Events.Services.Aws.S3 do
  @moduledoc """
  S3 storage service behaviour.

  Defines the contract for S3 operations. Implementations should handle:
  - File uploads and downloads
  - Signed URL generation
  - File listing and management
  - Bucket operations

  ## Implementation

  Uses ReqS3 plugin by Dashbit for S3 operations.

  ## Usage

      # Create context
      context = Context.new(
        access_key_id: "...",
        secret_access_key: "...",
        region: "us-east-1",
        bucket: "my-bucket"
      )

      # Upload file
      S3.upload(context, "path/to/file.txt", "Hello, World!")

      # Generate signed URL
      {:ok, url} = S3.presigned_url(context, :get, "path/to/file.txt", expires_in: 3600)

      # List files
      {:ok, files} = S3.list_objects(context, prefix: "uploads/")

      # Download file
      {:ok, content} = S3.get_object(context, "path/to/file.txt")
  """

  @behaviour Events.Behaviours.Service

  alias Events.Services.Aws.Context
  alias Events.Services.Aws.S3.{FileNameNormalizer, Pipeline, Uploader}

  @type context :: Context.t()
  @type bucket :: String.t()
  @type key :: String.t()
  @type content :: binary() | iodata()
  @type metadata :: %{optional(String.t()) => String.t()}

  @type upload_opts :: [
          content_type: String.t(),
          metadata: metadata(),
          acl: String.t(),
          storage_class: String.t()
        ]

  @type presign_opts :: [
          expires_in: pos_integer(),
          query_params: keyword(),
          virtual_host: boolean()
        ]

  @type list_opts :: [
          prefix: String.t(),
          max_keys: pos_integer(),
          continuation_token: String.t(),
          sort_by: :last_modified | :size | :key,
          sort_order: :asc | :desc
        ]

  @type object_info :: %{
          key: key(),
          size: non_neg_integer(),
          last_modified: DateTime.t(),
          etag: String.t(),
          storage_class: String.t()
        }

  ## Behaviour Callbacks

  @doc """
  Uploads an object to S3.

  ## Options

  - `:content_type` - MIME type (default: "application/octet-stream")
  - `:metadata` - Custom metadata map
  - `:acl` - Access control ("private", "public-read", etc.)
  - `:storage_class` - Storage class ("STANDARD", "GLACIER", etc.)

  ## Examples

      S3.upload(context, "documents/report.pdf", file_content,
        content_type: "application/pdf",
        metadata: %{"user_id" => "123"}
      )
  """
  @callback upload(context(), key(), content(), upload_opts()) :: :ok | {:error, term()}

  @doc """
  Downloads an object from S3.

  Returns {:ok, binary()} on success, {:error, reason} on failure.
  """
  @callback get_object(context(), key()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Deletes an object from S3.
  """
  @callback delete_object(context(), key()) :: :ok | {:error, term()}

  @doc """
  Checks if an object exists in S3.
  """
  @callback object_exists?(context(), key()) :: {:ok, boolean()} | {:error, term()}

  @doc """
  Lists objects in a bucket with optional prefix filtering and sorting.

  ## Options

  - `:prefix` - Filter by prefix
  - `:max_keys` - Maximum number of keys to return (default: 1000)
  - `:continuation_token` - Token for pagination
  - `:sort_by` - Sort by :last_modified (default), :size, or :key
  - `:sort_order` - Sort order :desc (default) or :asc

  ## Returns

  Returns `{:ok, %{objects: [object_info()], continuation_token: String.t() | nil}}`

  Objects are sorted by last_modified descending by default (newest first).
  """
  @callback list_objects(context(), list_opts()) ::
              {:ok, %{objects: [object_info()], continuation_token: String.t() | nil}}
              | {:error, term()}

  @doc """
  Generates a presigned URL for uploading or downloading.

  ## Parameters

  - `method` - HTTP method (`:get` or `:put`)
  - `key` - Object key
  - `opts` - Presign options

  ## Options

  - `:expires_in` - URL expiration in seconds (default: 3600)
  - `:query_params` - Additional query parameters
  - `:virtual_host` - Use virtual host style URLs (default: false)

  ## Examples

      # Download URL
      {:ok, url} = S3.presigned_url(context, :get, "document.pdf", expires_in: 3600)

      # Upload URL
      {:ok, url} = S3.presigned_url(context, :put, "upload.jpg",
        expires_in: 300,
        query_params: [content_type: "image/jpeg"]
      )
  """
  @callback presigned_url(context(), :get | :put, key(), presign_opts()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Copies an object within S3.
  """
  @callback copy_object(context(), source_key :: key(), dest_key :: key()) ::
              :ok | {:error, term()}

  @doc """
  Gets object metadata without downloading the content.
  """
  @callback head_object(context(), key()) :: {:ok, map()} | {:error, term()}

  ## Public API (delegates to adapter)

  @doc """
  Gets the configured adapter module.

  Defaults to the ReqS3-based adapter.
  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:events, :aws, [])
    |> Keyword.get(:s3_adapter, Events.Services.Aws.S3.Adapter)
  end

  @doc "See callback documentation"
  @spec upload(context(), key(), content(), upload_opts()) :: :ok | {:error, term()}
  def upload(context, key, content, opts \\ []) do
    adapter().upload(context, key, content, opts)
  end

  @doc "See callback documentation"
  @spec get_object(context(), key()) :: {:ok, binary()} | {:error, term()}
  def get_object(context, key) do
    adapter().get_object(context, key)
  end

  @doc "See callback documentation"
  @spec delete_object(context(), key()) :: :ok | {:error, term()}
  def delete_object(context, key) do
    adapter().delete_object(context, key)
  end

  @doc "See callback documentation"
  @spec object_exists?(context(), key()) :: {:ok, boolean()} | {:error, term()}
  def object_exists?(context, key) do
    adapter().object_exists?(context, key)
  end

  @doc "See callback documentation"
  @spec list_objects(context(), list_opts()) ::
          {:ok, %{objects: [object_info()], continuation_token: String.t() | nil}}
          | {:error, term()}
  def list_objects(context, opts \\ []) do
    adapter().list_objects(context, opts)
  end

  @doc "See callback documentation"
  @spec presigned_url(context(), :get | :put, key(), presign_opts()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_url(context, method, key, opts \\ []) do
    adapter().presigned_url(context, method, key, opts)
  end

  @doc "See callback documentation"
  @spec copy_object(context(), key(), key()) :: :ok | {:error, term()}
  def copy_object(context, source_key, dest_key) do
    adapter().copy_object(context, source_key, dest_key)
  end

  @doc "See callback documentation"
  @spec head_object(context(), key()) :: {:ok, map()} | {:error, term()}
  def head_object(context, key) do
    adapter().head_object(context, key)
  end

  ## Helpers

  @doc """
  Uploads a file from the filesystem.

  ## Examples

      S3.upload_file(context, "document.pdf", "/tmp/report.pdf")
  """
  @spec upload_file(context(), key(), Path.t(), upload_opts()) :: :ok | {:error, term()}
  def upload_file(context, key, file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path) do
      content_type = opts[:content_type] || MIME.from_path(file_path)
      upload(context, key, content, Keyword.put(opts, :content_type, content_type))
    end
  end

  @doc """
  Downloads an object and writes it to a file.

  ## Examples

      S3.download_to_file(context, "document.pdf", "/tmp/downloaded.pdf")
  """
  @spec download_to_file(context(), key(), Path.t()) :: :ok | {:error, term()}
  def download_to_file(context, key, file_path) do
    with {:ok, content} <- get_object(context, key) do
      File.write(file_path, content)
    end
  end

  @doc """
  Generates a bucket name with context bucket or explicit bucket.

  ## Examples

      iex> S3.bucket_name(context)
      "my-bucket"

      iex> S3.bucket_name(context, "other-bucket")
      "other-bucket"
  """
  @spec bucket_name(context(), bucket() | nil) :: bucket()
  def bucket_name(%Context{bucket: bucket}, nil), do: bucket
  def bucket_name(_context, bucket) when is_binary(bucket), do: bucket

  @doc """
  Validates required S3 context fields.
  """
  @spec validate_context(context()) :: :ok | {:error, atom()}
  def validate_context(%Context{} = context) do
    with {:ok, _} <- Context.validate(context) do
      if context.bucket do
        :ok
      else
        {:error, :missing_bucket}
      end
    end
  end

  ## Convenience Functions for File Name Normalization

  @doc """
  Normalizes a file name for S3 storage.

  Delegates to `FileNameNormalizer.normalize/2`.

  ## Examples

      iex> S3.normalize_filename("User's Photo (1).jpg")
      "users-photo-1.jpg"

      iex> S3.normalize_filename("file.txt", prefix: "uploads", add_timestamp: true)
      "uploads/file-20240112-143022.txt"
  """
  @spec normalize_filename(String.t(), keyword()) :: String.t()
  def normalize_filename(filename, opts \\ []) do
    FileNameNormalizer.normalize(filename, opts)
  end

  @doc """
  Uploads a file with automatic name normalization.

  Delegates to `Uploader.upload_with_normalization/4`.

  ## Examples

      S3.upload_normalized(context, "User File.pdf", content, prefix: "documents")
  """
  @spec upload_normalized(context(), String.t(), content(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def upload_normalized(context, filename, content, opts \\ []) do
    Uploader.upload_with_normalization(context, filename, content, opts)
  end

  @doc """
  Generates a presigned URL for upload with normalized filename.

  Delegates to `Uploader.presigned_upload_url/3`.

  Returns `{:ok, url, normalized_key}` on success.

  ## Examples

      {:ok, url, key} = S3.presigned_upload_url(context, "photo.jpg", expires_in: 300)
  """
  @spec presigned_upload_url(context(), String.t(), keyword()) ::
          {:ok, String.t(), String.t()} | {:error, term()}
  def presigned_upload_url(context, filename, opts \\ []) do
    Uploader.presigned_upload_url(context, filename, opts)
  end

  @doc """
  Generates a presigned URL for download.

  Delegates to `Uploader.presigned_download_url/3`.

  ## Examples

      {:ok, url} = S3.presigned_download_url(context, "documents/file.pdf", expires_in: 3600)
  """
  @spec presigned_download_url(context(), key(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_download_url(context, key, opts \\ []) do
    Uploader.presigned_download_url(context, key, opts)
  end

  @doc """
  Lists files in a given S3 location (prefix).

  Delegates to `Uploader.list_files/3`.

  ## Examples

      {:ok, %{objects: objects, continuation_token: token}} =
        S3.list_files(context, "uploads/")
  """
  @spec list_files(context(), String.t(), keyword()) ::
          {:ok, %{objects: [object_info()], continuation_token: String.t() | nil}}
          | {:error, term()}
  def list_files(context, prefix, opts \\ []) do
    Uploader.list_files(context, prefix, opts)
  end

  ## Pipe-Friendly API

  @doc """
  Prepares a file for upload with normalization (pipe-friendly).

  ## Examples

      "User's Photo.jpg"
      |> S3.prepare(context, prefix: "uploads")
      |> S3.generate_presigned_upload_url(expires_in: 300)
  """
  defdelegate prepare(filename, context, opts \\ []), to: Pipeline

  @doc """
  Prepares multiple files for upload (pipe-friendly).

  ## Examples

      ["photo1.jpg", "photo2.jpg"]
      |> S3.prepare_batch(context, prefix: "uploads")
      |> S3.generate_presigned_upload_urls(expires_in: 300)
  """
  defdelegate prepare_batch(filenames, context, opts \\ []), to: Pipeline

  @doc """
  Generates presigned upload URL (pipe-friendly).

  ## Examples

      {:ok, result} =
        "photo.jpg"
        |> S3.prepare(context)
        |> S3.generate_presigned_upload_url(expires_in: 300)
  """
  defdelegate generate_presigned_upload_url(prepared, opts \\ []), to: Pipeline

  @doc """
  Generates presigned upload URLs for multiple files (pipe-friendly).

  ## Examples

      {:ok, results} =
        ["photo1.jpg", "photo2.jpg"]
        |> S3.prepare_batch(context)
        |> S3.generate_presigned_upload_urls(expires_in: 300)
  """
  defdelegate generate_presigned_upload_urls(prepared_files, opts \\ []), to: Pipeline

  @doc """
  Generates presigned download URL from path/URL (pipe-friendly).

  Handles S3 keys, s3:// URLs, and https:// URLs.

  ## Examples

      {:ok, result} =
        "uploads/photo.jpg"
        |> S3.generate_presigned_download_url(context, expires_in: 3600)

      {:ok, result} =
        "s3://bucket/file.pdf"
        |> S3.generate_presigned_download_url(context)
  """
  defdelegate generate_presigned_download_url(path_or_url, context, opts \\ []), to: Pipeline

  @doc """
  Generates presigned download URLs for multiple files (pipe-friendly).

  ## Examples

      {:ok, results} =
        ["uploads/file1.pdf", "uploads/file2.jpg"]
        |> S3.generate_presigned_download_urls(context, expires_in: 3600)
  """
  defdelegate generate_presigned_download_urls(paths, context, opts \\ []), to: Pipeline
end
