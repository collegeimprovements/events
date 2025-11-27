defmodule Events.Services.S3 do
  @moduledoc """
  Clean, unified S3 API with first-class `s3://` URI support.

  ## Two API Styles

  ### 1. Direct API (config as last argument)

      config = S3.config(access_key_id: "...", secret_access_key: "...")

      S3.put("s3://bucket/file.txt", "content", config)
      {:ok, data} = S3.get("s3://bucket/file.txt", config)
      :ok = S3.delete("s3://bucket/file.txt", config)

  ### 2. Pipeline API (chainable, config first)

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("uploads/")
      |> S3.content_type("image/jpeg")
      |> S3.put("photo.jpg", image_data)

      # Or from environment
      S3.from_env()
      |> S3.expires_in({5, :minutes})
      |> S3.presign("s3://bucket/file.pdf")

  ## S3 URIs

  All operations accept `s3://bucket/key` URIs:

      "s3://my-bucket/path/to/file.txt"
      "s3://my-bucket/prefix/"              # For listing
      "s3://my-bucket"                      # Bucket root

  ## Pipeline Examples

      # Upload with metadata
      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("uploads/2024/")
      |> S3.content_type("image/jpeg")
      |> S3.metadata(%{user_id: "123"})
      |> S3.acl("public-read")
      |> S3.put("photo.jpg", jpeg_data)

      # Batch upload with concurrency control
      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("photos/")
      |> S3.concurrency(10)
      |> S3.timeout({2, :minutes})
      |> S3.put_all([{"a.jpg", data1}, {"b.jpg", data2}])

      # Download with globs
      S3.new(config)
      |> S3.get_all(["s3://bucket/docs/*.pdf"])

      # Copy with glob pattern
      S3.new(config)
      |> S3.copy_all("s3://source/*.jpg", to: "s3://dest/images/")

      # Presigned URLs
      S3.new(config)
      |> S3.expires_in({1, :hour})
      |> S3.method(:get)
      |> S3.presign_all(["s3://bucket/a.pdf", "s3://bucket/docs/*.pdf"])

  ## Configuration

      # From environment variables
      S3.from_env()

      # Manual configuration
      S3.config(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "us-east-1"
      )

      # With proxy
      S3.config(
        access_key_id: "...",
        secret_access_key: "...",
        proxy: {"proxy.company.com", 8080},
        proxy_auth: {"user", "password"}
      )

      # LocalStack / MinIO
      S3.config(
        access_key_id: "test",
        secret_access_key: "test",
        endpoint: "http://localhost:4566"
      )

  ## Batch Operations (Direct API)

      S3.put_all([{"a.txt", "..."}, {"b.txt", "..."}], config, to: "s3://bucket/")
      S3.get_all(["s3://bucket/*.txt"], config)
      S3.delete_all(["s3://bucket/temp/*.tmp"], config)
      S3.copy_all("s3://source/*.jpg", config, to: "s3://dest/")
      S3.presign_all(["s3://bucket/*.pdf"], config, expires_in: {1, :hour})
  """

  alias Events.Services.S3.Config
  alias Events.Services.S3.Client
  alias Events.Services.S3.Request
  alias Events.Services.S3.URI, as: S3URI

  @type config :: Config.t()
  @type request :: Request.t()
  @type uri :: String.t()
  @type content :: binary()
  @type key :: String.t()

  # ============================================
  # Pipeline API - Constructor & Chainable Options
  # ============================================

  @doc """
  Creates a new S3 request for pipeline-style operations.

  ## Examples

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.put("file.txt", "content")

      S3.new(access_key_id: "...", secret_access_key: "...")
      |> S3.get("s3://bucket/file.txt")
  """
  @spec new(Config.t() | keyword()) :: request()
  defdelegate new(config_or_opts), to: Request

  @doc "Sets the default bucket for pipeline operations."
  @spec bucket(request(), String.t()) :: request()
  defdelegate bucket(req, bucket), to: Request

  @doc "Sets the default prefix/path for pipeline operations."
  @spec prefix(request(), String.t()) :: request()
  defdelegate prefix(req, prefix), to: Request

  @doc "Sets the content type for uploads."
  @spec content_type(request(), String.t()) :: request()
  defdelegate content_type(req, content_type), to: Request

  @doc "Sets custom metadata for uploads."
  @spec metadata(request(), map()) :: request()
  defdelegate metadata(req, metadata), to: Request

  @doc "Sets the ACL for uploads (e.g., \"public-read\")."
  @spec acl(request(), String.t()) :: request()
  defdelegate acl(req, acl), to: Request

  @doc "Sets the storage class for uploads (e.g., \"GLACIER\")."
  @spec storage_class(request(), String.t()) :: request()
  defdelegate storage_class(req, storage_class), to: Request

  @doc "Sets expiration for presigned URLs. Accepts seconds or tuples like `{5, :minutes}`."
  @spec expires_in(request(), pos_integer() | {pos_integer(), atom()}) :: request()
  defdelegate expires_in(req, duration), to: Request

  @doc "Sets HTTP method for presigned URLs (:get or :put)."
  @spec method(request(), :get | :put) :: request()
  defdelegate method(req, method), to: Request

  @doc "Sets concurrency for batch operations."
  @spec concurrency(request(), pos_integer()) :: request()
  defdelegate concurrency(req, concurrency), to: Request

  @doc "Sets timeout for operations. Accepts ms or tuples like `{2, :minutes}`."
  @spec timeout(request(), pos_integer() | {pos_integer(), atom()}) :: request()
  defdelegate timeout(req, duration), to: Request

  # ============================================
  # Configuration
  # ============================================

  @doc """
  Creates S3 configuration from options.

  ## Options

  - `:access_key_id` - AWS access key (required)
  - `:secret_access_key` - AWS secret key (required)
  - `:region` - AWS region (default: "us-east-1")
  - `:endpoint` - Custom endpoint for LocalStack/MinIO
  - `:proxy` - Proxy tuple `{host, port}` or `{:http, host, port, opts}`
  - `:proxy_auth` - Proxy auth tuple `{username, password}`

  ## Examples

      config = S3.config(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "eu-west-1"
      )

      # With proxy
      config = S3.config(
        access_key_id: "...",
        secret_access_key: "...",
        proxy: {"proxy.example.com", 8080}
      )
  """
  @spec config(keyword()) :: config()
  defdelegate config(opts), to: Config, as: :new

  @doc """
  Creates S3 configuration/request from environment variables.

  Returns a Request struct for pipeline operations, or use `S3.config/0` for just config.

  ## Examples

      # Pipeline style
      S3.from_env()
      |> S3.bucket("my-bucket")
      |> S3.get("file.txt")

      # Get just the config
      config = S3.from_env().config
  """
  @spec from_env() :: request()
  defdelegate from_env(), to: Request

  # ============================================
  # Core Operations (Dual API)
  # ============================================

  @doc """
  Uploads content to S3.

  Works with both direct API (config) and pipeline API (request).

  ## Direct API

      :ok = S3.put("s3://bucket/file.txt", "hello", config)

  ## Pipeline API

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.content_type("text/plain")
      |> S3.put("file.txt", "hello")

  ## Options (direct API only)

  - `:content_type` - MIME type (auto-detected if not provided)
  - `:metadata` - Custom metadata map
  - `:acl` - Access control ("private", "public-read")
  - `:storage_class` - Storage class ("STANDARD", "GLACIER", etc.)
  """
  @spec put(request(), String.t(), binary()) :: :ok | {:error, term()}
  @spec put(uri(), content(), config()) :: :ok | {:error, term()}
  @spec put(uri(), content(), config(), keyword()) :: :ok | {:error, term()}
  def put(req_or_uri, key_or_content, content_or_config, opts \\ [])

  def put(%Request{} = req, key_or_uri, content, _opts) do
    Request.put(req, key_or_uri, content)
  end

  def put(uri, content, %Config{} = config, opts) do
    {bucket, key} = S3URI.parse!(uri)
    Client.put_object(config, bucket, key, content, opts)
  end

  @doc """
  Downloads content from S3.

  Works with both direct API (config) and pipeline API (request).

  ## Direct API

      {:ok, content} = S3.get("s3://bucket/file.txt", config)

  ## Pipeline API

      S3.new(config)
      |> S3.get("s3://bucket/file.txt")

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.get("file.txt")
  """
  @spec get(request(), String.t()) :: {:ok, binary()} | {:error, term()}
  @spec get(uri(), config()) :: {:ok, binary()} | {:error, term()}
  def get(%Request{} = req, key_or_uri) do
    Request.get(req, key_or_uri)
  end

  def get(uri, %Config{} = config) do
    {bucket, key} = S3URI.parse!(uri)
    Client.get_object(config, bucket, key)
  end

  @doc """
  Deletes an object from S3.

  Returns `:ok` even if the object doesn't exist (S3 behavior).

  ## Direct API

      :ok = S3.delete("s3://bucket/file.txt", config)

  ## Pipeline API

      S3.new(config)
      |> S3.delete("s3://bucket/file.txt")
  """
  @spec delete(request(), String.t()) :: :ok | {:error, term()}
  @spec delete(uri(), config()) :: :ok | {:error, term()}
  def delete(%Request{} = req, key_or_uri) do
    Request.delete(req, key_or_uri)
  end

  def delete(uri, %Config{} = config) do
    {bucket, key} = S3URI.parse!(uri)
    Client.delete_object(config, bucket, key)
  end

  @doc """
  Checks if an object exists.

  ## Direct API

      true = S3.exists?("s3://bucket/file.txt", config)

  ## Pipeline API

      S3.new(config) |> S3.exists?("s3://bucket/file.txt")
  """
  @spec exists?(request(), String.t()) :: boolean()
  @spec exists?(uri(), config()) :: boolean()
  def exists?(%Request{} = req, key_or_uri) do
    Request.exists?(req, key_or_uri)
  end

  def exists?(uri, %Config{} = config) do
    {bucket, key} = S3URI.parse!(uri)

    case Client.head_object(config, bucket, key) do
      {:ok, _} -> true
      {:error, :not_found} -> false
      {:error, _} -> false
    end
  end

  @doc """
  Gets object metadata without downloading content.

  ## Direct API

      {:ok, meta} = S3.head("s3://bucket/file.txt", config)

  ## Pipeline API

      S3.new(config) |> S3.head("s3://bucket/file.txt")
  """
  @spec head(request(), String.t()) :: {:ok, map()} | {:error, term()}
  @spec head(uri(), config()) :: {:ok, map()} | {:error, term()}
  def head(%Request{} = req, key_or_uri) do
    Request.head(req, key_or_uri)
  end

  def head(uri, %Config{} = config) do
    {bucket, key} = S3URI.parse!(uri)
    Client.head_object(config, bucket, key)
  end

  @doc """
  Lists objects in a bucket/prefix.

  ## Direct API

      {:ok, %{files: files, next: nil}} = S3.list("s3://bucket/uploads/", config)

  ## Pipeline API

      S3.new(config)
      |> S3.list("s3://bucket/uploads/")

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("uploads/")
      |> S3.list()

  ## Options (direct API)

  - `:limit` - Maximum objects to return (default: 1000)
  - `:continuation_token` - For pagination
  """
  @spec list(request()) :: {:ok, map()} | {:error, term()}
  @spec list(request(), String.t()) :: {:ok, map()} | {:error, term()}
  @spec list(uri(), config()) :: {:ok, map()} | {:error, term()}
  @spec list(uri(), config(), keyword()) :: {:ok, map()} | {:error, term()}
  def list(req_or_uri, config_or_uri \\ nil, opts \\ [])

  def list(%Request{} = req, nil, _opts) do
    Request.list(req)
  end

  def list(%Request{} = req, key_or_uri, _opts) when is_binary(key_or_uri) do
    Request.list(req, key_or_uri)
  end

  def list(uri, %Config{} = config, opts) do
    {bucket, prefix} = S3URI.parse!(uri)
    Client.list_objects(config, bucket, prefix, opts)
  end

  @doc """
  Lists all objects (handles pagination automatically).

  ## Examples

      {:ok, all_files} = S3.list_all("s3://bucket/uploads/", config)
  """
  @spec list_all(uri(), config(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_all(uri, config, opts \\ []) do
    do_list_all(uri, config, opts, [])
  end

  defp do_list_all(uri, %Config{} = config, opts, acc) do
    case list(uri, config, opts) do
      {:ok, %{files: files, next: nil}} ->
        {:ok, acc ++ files}

      {:ok, %{files: files, next: token}} ->
        do_list_all(uri, config, Keyword.put(opts, :continuation_token, token), acc ++ files)

      error ->
        error
    end
  end

  @doc """
  Copies an object within S3.

  ## Direct API

      :ok = S3.copy("s3://bucket/old.txt", "s3://bucket/new.txt", config)

  ## Pipeline API

      S3.new(config)
      |> S3.copy("s3://bucket/old.txt", "s3://bucket/new.txt")
  """
  @spec copy(request(), uri(), uri()) :: :ok | {:error, term()}
  @spec copy(uri(), uri(), config()) :: :ok | {:error, term()}
  def copy(%Request{} = req, source_uri, dest_uri) do
    Request.copy(req, source_uri, dest_uri)
  end

  def copy(source_uri, dest_uri, %Config{} = config) do
    {source_bucket, source_key} = S3URI.parse!(source_uri)
    {dest_bucket, dest_key} = S3URI.parse!(dest_uri)
    Client.copy_object(config, source_bucket, source_key, dest_bucket, dest_key)
  end

  # ============================================
  # Presigned URLs
  # ============================================

  @doc """
  Generates a presigned URL.

  ## Direct API

      {:ok, url} = S3.presign("s3://bucket/file.pdf", config)
      {:ok, url} = S3.presign("s3://bucket/upload.jpg", config, method: :put)

  ## Pipeline API

      S3.new(config)
      |> S3.expires_in({5, :minutes})
      |> S3.presign("s3://bucket/file.pdf")

      S3.new(config)
      |> S3.method(:put)
      |> S3.presign("s3://bucket/upload.jpg")

  ## Options (direct API)

  - `:method` - HTTP method `:get` (default) or `:put`
  - `:expires_in` - Expiration in seconds or duration tuple (default: 3600)
  """
  @spec presign(request(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @spec presign(uri(), config()) :: {:ok, String.t()} | {:error, term()}
  @spec presign(uri(), config(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presign(req_or_uri, config_or_key, opts \\ [])

  def presign(%Request{} = req, key_or_uri, _opts) do
    Request.presign(req, key_or_uri)
  end

  def presign(uri, %Config{} = config, opts) do
    {bucket, key} = S3URI.parse!(uri)
    method = Keyword.get(opts, :method, :get)
    expires_in = normalize_expiration(Keyword.get(opts, :expires_in, 3600))

    Client.presigned_url(config, bucket, key, method, expires_in)
  end

  @doc """
  Generates a presigned download URL (convenience wrapper).

  ## Examples

      {:ok, url} = S3.presign_get("s3://bucket/file.pdf", config)
      {:ok, url} = S3.presign_get("s3://bucket/file.pdf", config, expires_in: {1, :hour})
  """
  @spec presign_get(uri(), config(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presign_get(uri, config, opts \\ []) do
    presign(uri, config, Keyword.put(opts, :method, :get))
  end

  @doc """
  Generates a presigned upload URL (convenience wrapper).

  ## Examples

      {:ok, url} = S3.presign_put("s3://bucket/upload.jpg", config)
      {:ok, url} = S3.presign_put("s3://bucket/upload.jpg", config, expires_in: {5, :minutes})
  """
  @spec presign_put(uri(), config(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presign_put(uri, config, opts \\ []) do
    presign(uri, config, Keyword.put(opts, :method, :put))
  end

  # ============================================
  # Batch Operations (Dual API)
  # ============================================

  @doc """
  Uploads multiple files in parallel.

  ## Pipeline API

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("uploads/")
      |> S3.concurrency(10)
      |> S3.put_all([{"a.txt", "content"}, {"b.txt", "content"}])

  ## Direct API

      S3.put_all([{"s3://bucket/a.txt", "..."}], config)
      S3.put_all([{"a.txt", "..."}], config, to: "s3://bucket/")
  """
  @spec put_all(request(), [{String.t(), binary()}]) :: [{:ok, uri()} | {:error, uri(), term()}]
  @spec put_all([{String.t(), binary()}], config()) :: [{:ok, uri()} | {:error, uri(), term()}]
  @spec put_all([{String.t(), binary()}], config(), keyword()) ::
          [{:ok, uri()} | {:error, uri(), term()}]
  def put_all(req_or_files, files_or_config, opts \\ [])

  def put_all(%Request{} = req, files, _opts) do
    Request.put_all(req, files)
  end

  def put_all(files, %Config{} = config, opts) when is_list(files) do
    base_uri = Keyword.get(opts, :to)
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online() * 2)
    timeout = Keyword.get(opts, :timeout, 60_000)
    upload_opts = Keyword.drop(opts, [:to, :concurrency, :timeout])

    files
    |> Task.async_stream(
      fn {key_or_uri, content} ->
        uri = resolve_uri(key_or_uri, base_uri)
        {bucket, key} = S3URI.parse!(uri)

        case Client.put_object(config, bucket, key, content, upload_opts) do
          :ok -> {:ok, uri}
          {:error, reason} -> {:error, uri, reason}
        end
      end,
      max_concurrency: concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Downloads multiple files in parallel. Supports glob patterns.

  ## Pipeline API

      S3.new(config)
      |> S3.concurrency(10)
      |> S3.get_all(["s3://bucket/docs/*.pdf"])

  ## Direct API

      S3.get_all(["s3://bucket/a.txt", "s3://bucket/*.json"], config)
  """
  @spec get_all(request(), [uri()]) :: [{:ok, uri(), binary()} | {:error, uri(), term()}]
  @spec get_all([uri()], config()) :: [{:ok, uri(), binary()} | {:error, uri(), term()}]
  @spec get_all([uri()], config(), keyword()) ::
          [{:ok, uri(), binary()} | {:error, uri(), term()}]
  def get_all(req_or_uris, uris_or_config, opts \\ [])

  def get_all(%Request{} = req, uris, _opts) do
    Request.get_all(req, uris)
  end

  def get_all(uris, %Config{} = config, opts) when is_list(uris) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online() * 2)
    timeout = Keyword.get(opts, :timeout, 60_000)

    uris
    |> Enum.flat_map(&expand_uri_pattern(&1, config))
    |> Task.async_stream(
      fn uri ->
        case get(uri, config) do
          {:ok, content} -> {:ok, uri, content}
          {:error, reason} -> {:error, uri, reason}
        end
      end,
      max_concurrency: concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Copies multiple objects in parallel. Supports glob patterns.

  ## Pipeline API

      S3.new(config)
      |> S3.copy_all([{"s3://src/a.txt", "s3://dst/a.txt"}])

      S3.new(config)
      |> S3.copy_all("s3://source/*.jpg", to: "s3://dest/images/")

  ## Direct API

      S3.copy_all([{"s3://src/a.txt", "s3://dst/a.txt"}], config)
      S3.copy_all("s3://source/*.jpg", config, to: "s3://dest/")
  """
  @spec copy_all(request(), [{uri(), uri()}] | uri()) ::
          [{:ok, uri(), uri()} | {:error, uri(), term()}]
  @spec copy_all(request(), uri(), keyword()) ::
          [{:ok, uri(), uri()} | {:error, uri(), term()}]
  @spec copy_all([{uri(), uri()}] | uri(), config()) ::
          [{:ok, uri(), uri()} | {:error, uri(), term()}]
  @spec copy_all([{uri(), uri()}] | uri(), config(), keyword()) ::
          [{:ok, uri(), uri()} | {:error, uri(), term()}]
  def copy_all(req_or_source, source_or_config, opts \\ [])

  def copy_all(%Request{} = req, source, opts) do
    Request.copy_all(req, source, opts)
  end

  def copy_all(pairs, %Config{} = config, opts) when is_list(pairs) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online() * 2)
    timeout = Keyword.get(opts, :timeout, 60_000)

    pairs
    |> Task.async_stream(
      fn {source_uri, dest_uri} ->
        case copy(source_uri, dest_uri, config) do
          :ok -> {:ok, source_uri, dest_uri}
          {:error, reason} -> {:error, source_uri, reason}
        end
      end,
      max_concurrency: concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  def copy_all(source_pattern, config, opts) when is_binary(source_pattern) do
    dest_base = Keyword.fetch!(opts, :to)
    {dest_bucket, dest_prefix} = S3URI.parse!(dest_base)
    dest_prefix = normalize_prefix(dest_prefix)
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online() * 2)
    timeout = Keyword.get(opts, :timeout, 60_000)

    source_uris = expand_uri_pattern(source_pattern, config)

    source_uris
    |> Task.async_stream(
      fn source_uri ->
        filename = S3URI.filename(source_uri)
        dest_uri = S3URI.build(dest_bucket, dest_prefix <> filename)

        case copy(source_uri, dest_uri, config) do
          :ok -> {:ok, source_uri, dest_uri}
          {:error, reason} -> {:error, source_uri, reason}
        end
      end,
      max_concurrency: concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Deletes multiple objects in parallel. Supports glob patterns.

  ## Pipeline API

      S3.new(config)
      |> S3.delete_all(["s3://bucket/temp/*.tmp"])

  ## Direct API

      S3.delete_all(["s3://bucket/old/*.txt"], config)
  """
  @spec delete_all(request(), [uri()]) :: [{:ok, uri()} | {:error, uri(), term()}]
  @spec delete_all([uri()], config()) :: [{:ok, uri()} | {:error, uri(), term()}]
  @spec delete_all([uri()], config(), keyword()) ::
          [{:ok, uri()} | {:error, uri(), term()}]
  def delete_all(req_or_uris, uris_or_config, opts \\ [])

  def delete_all(%Request{} = req, uris, _opts) do
    Request.delete_all(req, uris)
  end

  def delete_all(uris, %Config{} = config, opts) when is_list(uris) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online() * 2)
    timeout = Keyword.get(opts, :timeout, 60_000)

    uris
    |> Enum.flat_map(&expand_uri_pattern(&1, config))
    |> Task.async_stream(
      fn uri ->
        case delete(uri, config) do
          :ok -> {:ok, uri}
          {:error, reason} -> {:error, uri, reason}
        end
      end,
      max_concurrency: concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Generates presigned URLs for multiple URIs. Supports glob patterns.

  ## Pipeline API

      S3.new(config)
      |> S3.expires_in({1, :hour})
      |> S3.presign_all(["s3://bucket/*.pdf"])

  ## Direct API

      S3.presign_all(["s3://bucket/*.pdf"], config, expires_in: {5, :minutes})
  """
  @spec presign_all(request(), [uri()]) :: [{:ok, uri(), String.t()} | {:error, uri(), term()}]
  @spec presign_all([uri()], config()) :: [{:ok, uri(), String.t()} | {:error, uri(), term()}]
  @spec presign_all([uri()], config(), keyword()) ::
          [{:ok, uri(), String.t()} | {:error, uri(), term()}]
  def presign_all(req_or_uris, uris_or_config, opts \\ [])

  def presign_all(%Request{} = req, uris, _opts) do
    Request.presign_all(req, uris)
  end

  def presign_all(uris, %Config{} = config, opts) when is_list(uris) do
    method = Keyword.get(opts, :method, :get)
    expires_in = normalize_expiration(Keyword.get(opts, :expires_in, 3600))

    uris
    |> Enum.flat_map(&expand_uri_pattern(&1, config))
    |> Enum.map(fn uri ->
      {bucket, key} = S3URI.parse!(uri)

      case Client.presigned_url(config, bucket, key, method, expires_in) do
        {:ok, url} -> {:ok, uri, url}
        {:error, reason} -> {:error, uri, reason}
      end
    end)
  end

  # Expand glob patterns like "s3://bucket/folder/*.pdf"
  defp expand_uri_pattern(uri, config) do
    case parse_glob_pattern(uri) do
      {:glob, bucket, prefix, pattern} ->
        expand_glob(bucket, prefix, pattern, config)

      :literal ->
        [uri]
    end
  end

  defp parse_glob_pattern(uri) do
    case S3URI.parse(uri) do
      {:ok, bucket, key} ->
        if String.contains?(key, "*") do
          # Split into prefix (before *) and pattern
          parts = String.split(key, "*", parts: 2)

          case parts do
            [prefix_part, suffix] ->
              # Get the directory prefix (everything before the last /)
              prefix = get_directory_prefix(prefix_part)
              # Build the glob pattern
              pattern = String.replace(prefix_part, prefix, "") <> "*" <> suffix
              {:glob, bucket, prefix, pattern}

            _ ->
              :literal
          end
        else
          :literal
        end

      :error ->
        :literal
    end
  end

  defp get_directory_prefix(path) do
    case String.split(path, "/") |> Enum.drop(-1) do
      [] -> ""
      parts -> Enum.join(parts, "/") <> "/"
    end
  end

  defp expand_glob(bucket, prefix, pattern, config) do
    base_uri = S3URI.build(bucket, prefix)

    case list_all(base_uri, config) do
      {:ok, files} ->
        files
        |> Enum.map(& &1.key)
        |> Enum.filter(&glob_match?(&1, prefix, pattern))
        |> Enum.map(&S3URI.build(bucket, &1))

      {:error, _} ->
        []
    end
  end

  defp glob_match?(key, prefix, pattern) do
    # Get the part of the key after the prefix
    relative_key = String.replace_prefix(key, prefix, "")
    # Convert glob pattern to regex
    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> then(&("^" <> &1 <> "$"))

    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, relative_key)
      _ -> false
    end
  end

  # ============================================
  # File Name Utilities
  # ============================================

  @doc """
  Normalizes a key/filename for safe S3 storage.

  ## Options

  - `:prefix` - Add path prefix
  - `:timestamp` - Add timestamp for uniqueness
  - `:uuid` - Add UUID for uniqueness
  - `:separator` - Character for spaces (default: "-")

  ## Examples

      S3.normalize_key("User's Photo (1).jpg")
      #=> "users-photo-1.jpg"

      S3.normalize_key("report.pdf", prefix: "docs", timestamp: true)
      #=> "docs/report-20240115-143022.pdf"

      S3.normalize_key("file.txt", uuid: true)
      #=> "file-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt"
  """
  @spec normalize_key(String.t(), keyword()) :: String.t()
  def normalize_key(filename, opts \\ []) do
    alias Events.Services.S3.FileNameNormalizer

    FileNameNormalizer.normalize(filename,
      prefix: opts[:prefix],
      add_timestamp: opts[:timestamp] || false,
      add_uuid: opts[:uuid] || false,
      separator: opts[:separator] || "-"
    )
  end

  @doc """
  Builds an S3 URI from bucket and key.

  ## Examples

      S3.uri("my-bucket", "path/to/file.txt")
      #=> "s3://my-bucket/path/to/file.txt"

      S3.uri("my-bucket", "")
      #=> "s3://my-bucket"
  """
  @spec uri(String.t(), String.t()) :: String.t()
  def uri(bucket, ""), do: "s3://#{bucket}"
  def uri(bucket, key), do: "s3://#{bucket}/#{key}"

  @doc """
  Parses an S3 URI into bucket and key.

  ## Examples

      {:ok, "my-bucket", "path/file.txt"} = S3.parse_uri("s3://my-bucket/path/file.txt")
      {:ok, "my-bucket", ""} = S3.parse_uri("s3://my-bucket")
      :error = S3.parse_uri("not-an-s3-uri")
  """
  @spec parse_uri(String.t()) :: {:ok, String.t(), String.t()} | :error
  defdelegate parse_uri(uri), to: S3URI, as: :parse

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_prefix(""), do: ""
  defp normalize_prefix(prefix), do: String.trim_trailing(prefix, "/") <> "/"

  # Resolve a key or full URI to a full URI
  defp resolve_uri("s3://" <> _ = uri, _base_uri), do: uri

  defp resolve_uri(key, nil) do
    raise ArgumentError, "Key #{inspect(key)} requires :to option with base URI"
  end

  defp resolve_uri(key, base_uri) do
    {bucket, prefix} = S3URI.parse!(base_uri)
    prefix = normalize_prefix(prefix)
    S3URI.build(bucket, prefix <> key)
  end

  defp normalize_expiration({n, :second}), do: n
  defp normalize_expiration({n, :seconds}), do: n
  defp normalize_expiration({n, :minute}), do: n * 60
  defp normalize_expiration({n, :minutes}), do: n * 60
  defp normalize_expiration({n, :hour}), do: n * 3600
  defp normalize_expiration({n, :hours}), do: n * 3600
  defp normalize_expiration({n, :day}), do: n * 86_400
  defp normalize_expiration({n, :days}), do: n * 86_400
  defp normalize_expiration({n, :week}), do: n * 604_800
  defp normalize_expiration({n, :weeks}), do: n * 604_800
  defp normalize_expiration({n, :month}), do: n * 2_592_000
  defp normalize_expiration({n, :months}), do: n * 2_592_000
  defp normalize_expiration({n, :year}), do: n * 31_536_000
  defp normalize_expiration({n, :years}), do: n * 31_536_000
  defp normalize_expiration(seconds) when is_integer(seconds), do: seconds
end
