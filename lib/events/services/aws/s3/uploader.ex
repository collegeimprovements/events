defmodule Events.Services.Aws.S3.Uploader do
  @moduledoc """
  High-level S3 upload helpers with automatic file name normalization.

  This module wraps the S3 adapter and provides convenient functions for
  uploading files with normalized names, presigned URLs, and batch operations.

  ## Examples

      # Upload with automatic normalization
      Uploader.upload_with_normalization(context, "User's Photo (1).jpg", content)
      # => Uploads as "users-photo-1.jpg"

      # Upload with prefix and timestamp
      Uploader.upload_with_normalization(
        context,
        "document.pdf",
        content,
        prefix: "uploads/2024",
        add_timestamp: true
      )
      # => Uploads as "uploads/2024/document-20240112-143022.pdf"

      # Generate presigned upload URL with normalized name
      Uploader.presigned_upload_url(context, "user file.jpg", expires_in: 300)
      # => Returns URL for uploading to "user-file.jpg"

      # List files in a specific folder
      Uploader.list_files(context, "uploads/photos/")
  """

  alias Events.Services.Aws.{Context, S3}
  alias Events.Services.Aws.S3.FileNameNormalizer

  @type upload_opts :: [
          content_type: String.t(),
          metadata: map(),
          acl: String.t(),
          storage_class: String.t(),
          prefix: String.t(),
          add_timestamp: boolean(),
          add_uuid: boolean(),
          separator: String.t(),
          preserve_case: boolean()
        ]

  @type presign_opts :: [
          expires_in: pos_integer(),
          query_params: keyword(),
          virtual_host: boolean(),
          prefix: String.t(),
          add_timestamp: boolean(),
          preserve_case: boolean()
        ]

  @doc """
  Uploads a file with automatic name normalization.

  ## Options

  - `:content_type` - MIME type (auto-detected if not provided)
  - `:metadata` - Custom metadata map
  - `:acl` - Access control ("private", "public-read", etc.)
  - `:storage_class` - Storage class ("STANDARD", "GLACIER", etc.)
  - `:prefix` - Path prefix (e.g., "uploads/2024/01")
  - `:add_timestamp` - Append timestamp to filename (default: false)
  - `:add_uuid` - Append UUID to filename (default: false)
  - `:separator` - Character to replace spaces (default: "-")
  - `:preserve_case` - Keep original case (default: false)

  ## Examples

      Uploader.upload_with_normalization(
        context,
        "My Document.pdf",
        file_content,
        prefix: "documents",
        add_timestamp: true
      )
  """
  @spec upload_with_normalization(Context.t(), String.t(), binary(), upload_opts()) ::
          {:ok, String.t()} | {:error, term()}
  def upload_with_normalization(%Context{} = context, filename, content, opts \\ []) do
    # Extract normalization options
    normalize_opts = extract_normalize_opts(opts)

    # Normalize filename
    normalized_key = FileNameNormalizer.normalize(filename, normalize_opts)

    # Extract S3 upload options
    upload_opts = extract_upload_opts(opts)

    # Add content type if not provided
    upload_opts =
      if opts[:content_type] do
        upload_opts
      else
        content_type = MIME.from_path(filename)
        Keyword.put(upload_opts, :content_type, content_type)
      end

    case S3.upload(context, normalized_key, content, upload_opts) do
      :ok -> {:ok, normalized_key}
      error -> error
    end
  end

  @doc """
  Uploads a file with a unique UUID-based name.

  ## Examples

      Uploader.upload_with_uuid(context, "photo.jpg", content, prefix: "uploads")
      # => Uploads as "uploads/a1b2c3d4-e5f6-7890-abcd-ef1234567890.jpg"
  """
  @spec upload_with_uuid(Context.t(), String.t(), binary(), upload_opts()) ::
          {:ok, String.t()} | {:error, term()}
  def upload_with_uuid(%Context{} = context, filename, content, opts \\ []) do
    opts = Keyword.put(opts, :add_uuid, true)
    upload_with_normalization(context, filename, content, opts)
  end

  @doc """
  Generates a presigned URL for uploading with normalized filename.

  The URL will be valid for the specified duration (default: 1 hour).
  The client can use this URL to upload directly to S3.

  ## Options

  - `:expires_in` - URL expiration in seconds (default: 3600)
  - `:prefix` - Path prefix
  - `:add_timestamp` - Add timestamp to filename
  - `:preserve_case` - Keep original case
  - `:content_type` - Content type for the upload

  ## Examples

      # Generate 5-minute upload URL
      {:ok, url, key} = Uploader.presigned_upload_url(
        context,
        "user photo.jpg",
        expires_in: 300,
        prefix: "uploads"
      )

      # Client can now PUT to the URL
      Req.put(url, body: file_content)
  """
  @spec presigned_upload_url(Context.t(), String.t(), presign_opts()) ::
          {:ok, String.t(), String.t()} | {:error, term()}
  def presigned_upload_url(%Context{} = context, filename, opts \\ []) do
    normalize_opts = extract_normalize_opts(opts)
    normalized_key = FileNameNormalizer.normalize(filename, normalize_opts)

    presign_opts = extract_presign_opts(opts)

    case S3.presigned_url(context, :put, normalized_key, presign_opts) do
      {:ok, url} -> {:ok, url, normalized_key}
      error -> error
    end
  end

  @doc """
  Generates a presigned URL for downloading.

  ## Examples

      {:ok, url} = Uploader.presigned_download_url(
        context,
        "documents/report.pdf",
        expires_in: 3600
      )
  """
  @spec presigned_download_url(Context.t(), String.t(), presign_opts()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_download_url(%Context{} = context, key, opts \\ []) do
    presign_opts = extract_presign_opts(opts)
    S3.presigned_url(context, :get, key, presign_opts)
  end

  @doc """
  Lists all files in a given S3 location (prefix).

  ## Options

  - `:max_keys` - Maximum number of files to return (default: 1000)
  - `:continuation_token` - Token for pagination

  ## Examples

      {:ok, result} = Uploader.list_files(context, "uploads/")

      Enum.each(result.objects, fn obj ->
        IO.puts("File: \#{obj.key}, Size: \#{obj.size}")
      end)

      # Paginate through results
      if result.continuation_token do
        {:ok, next_page} = Uploader.list_files(
          context,
          "uploads/",
          continuation_token: result.continuation_token
        )
      end
  """
  @spec list_files(Context.t(), String.t(), keyword()) ::
          {:ok, %{objects: [map()], continuation_token: String.t() | nil}} | {:error, term()}
  def list_files(%Context{} = context, prefix, opts \\ []) do
    list_opts = Keyword.put(opts, :prefix, prefix)
    S3.list_objects(context, list_opts)
  end

  @doc """
  Lists all files in a given location and returns just the keys.

  ## Examples

      {:ok, keys} = Uploader.list_file_keys(context, "uploads/")
      # => ["uploads/file1.jpg", "uploads/file2.pdf", ...]
  """
  @spec list_file_keys(Context.t(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def list_file_keys(%Context{} = context, prefix, opts \\ []) do
    case list_files(context, prefix, opts) do
      {:ok, %{objects: objects}} ->
        keys = Enum.map(objects, & &1.key)
        {:ok, keys}

      error ->
        error
    end
  end

  @doc """
  Batch upload multiple files with normalization.

  Returns a list of results for each upload.

  ## Examples

      files = [
        {"photo1.jpg", photo1_content},
        {"photo2.jpg", photo2_content},
        {"document.pdf", doc_content}
      ]

      results = Uploader.batch_upload(context, files, prefix: "uploads")
      # => [
      #   {:ok, "uploads/photo1.jpg"},
      #   {:ok, "uploads/photo2.jpg"},
      #   {:ok, "uploads/document.pdf"}
      # ]
  """
  @spec batch_upload(Context.t(), [{String.t(), binary()}], upload_opts()) ::
          [{:ok, String.t()} | {:error, term()}]
  def batch_upload(%Context{} = context, files, opts \\ []) do
    Enum.map(files, fn {filename, content} ->
      upload_with_normalization(context, filename, content, opts)
    end)
  end

  @doc """
  Generates multiple presigned upload URLs.

  Useful for allowing clients to upload multiple files directly to S3.

  ## Examples

      filenames = ["photo1.jpg", "photo2.jpg", "document.pdf"]
      results = Uploader.batch_presigned_upload_urls(
        context,
        filenames,
        prefix: "uploads",
        expires_in: 300
      )
      # => [
      #   {:ok, "https://...", "uploads/photo1.jpg"},
      #   {:ok, "https://...", "uploads/photo2.jpg"},
      #   {:ok, "https://...", "uploads/document.pdf"}
      # ]
  """
  @spec batch_presigned_upload_urls(Context.t(), [String.t()], presign_opts()) ::
          [{:ok, String.t(), String.t()} | {:error, term()}]
  def batch_presigned_upload_urls(%Context{} = context, filenames, opts \\ []) do
    Enum.map(filenames, fn filename ->
      presigned_upload_url(context, filename, opts)
    end)
  end

  ## Private Functions

  defp extract_normalize_opts(opts) do
    [
      prefix: opts[:prefix],
      add_timestamp: opts[:add_timestamp],
      add_uuid: opts[:add_uuid],
      separator: opts[:separator],
      preserve_case: opts[:preserve_case]
    ]
    |> Enum.filter(fn {_k, v} -> v != nil end)
  end

  defp extract_upload_opts(opts) do
    [
      content_type: opts[:content_type],
      metadata: opts[:metadata],
      acl: opts[:acl],
      storage_class: opts[:storage_class]
    ]
    |> Enum.filter(fn {_k, v} -> v != nil end)
  end

  defp extract_presign_opts(opts) do
    query_params =
      if opts[:content_type] do
        [content_type: opts[:content_type]]
      else
        []
      end

    [
      expires_in: opts[:expires_in],
      query_params: query_params ++ (opts[:query_params] || []),
      virtual_host: opts[:virtual_host]
    ]
    |> Enum.filter(fn {_k, v} -> v != nil and v != [] end)
  end
end
