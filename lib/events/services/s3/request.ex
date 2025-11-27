defmodule Events.Services.S3.Request do
  @moduledoc """
  Pipeline-style request builder for S3 operations.

  Compose S3 operations with a clean, chainable API inspired by Req.

  ## Quick Start

      # Create a request with config
      S3.new(config)
      |> S3.put("s3://bucket/file.txt", "content")

      # Or start from environment
      S3.from_env()
      |> S3.get("s3://bucket/file.txt")

  ## Pipeline Style

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("uploads/2024/")
      |> S3.content_type("image/jpeg")
      |> S3.metadata(%{user_id: "123"})
      |> S3.put("photo.jpg", image_data)

  ## Batch Operations

      S3.new(config)
      |> S3.bucket("my-bucket")
      |> S3.prefix("photos/")
      |> S3.concurrency(10)
      |> S3.put_all([{"a.jpg", data1}, {"b.jpg", data2}])

  ## Presigned URLs

      S3.new(config)
      |> S3.expires_in({5, :minutes})
      |> S3.presign(:get, "s3://bucket/file.pdf")

  ## Glob Operations

      S3.new(config)
      |> S3.get_all(["s3://bucket/docs/*.pdf"])

      S3.new(config)
      |> S3.copy_all("s3://source/*.jpg", to: "s3://dest/images/")
  """

  alias Events.Services.S3.Config

  @type t :: %__MODULE__{
          config: Config.t(),
          bucket: String.t() | nil,
          prefix: String.t(),
          content_type: String.t() | nil,
          metadata: map(),
          acl: String.t() | nil,
          storage_class: String.t() | nil,
          expires_in: pos_integer(),
          method: :get | :put,
          concurrency: pos_integer(),
          timeout: pos_integer()
        }

  defstruct [
    :config,
    :bucket,
    :content_type,
    :acl,
    :storage_class,
    prefix: "",
    metadata: %{},
    expires_in: 3600,
    method: :get,
    concurrency: nil,
    timeout: 60_000
  ]

  # ============================================
  # Constructor
  # ============================================

  @doc """
  Creates a new S3 request with the given config.

  ## Examples

      req = S3.Request.new(config)
      req = S3.Request.new(access_key_id: "...", secret_access_key: "...")
  """
  @spec new(Config.t() | keyword()) :: t()
  def new(%Config{} = config) do
    %__MODULE__{
      config: config,
      concurrency: System.schedulers_online() * 2
    }
  end

  def new(opts) when is_list(opts) do
    new(Config.new(opts))
  end

  @doc """
  Creates a new S3 request from environment variables.

  ## Examples

      req = S3.Request.from_env()
  """
  @spec from_env() :: t()
  def from_env do
    new(Config.from_env())
  end

  # ============================================
  # Chainable Options
  # ============================================

  @doc """
  Sets the default bucket.

  ## Examples

      req |> S3.Request.bucket("my-bucket")
  """
  @spec bucket(t(), String.t()) :: t()
  def bucket(%__MODULE__{} = req, bucket) do
    %{req | bucket: bucket}
  end

  @doc """
  Sets the default prefix/path.

  ## Examples

      req |> S3.Request.prefix("uploads/2024/")
  """
  @spec prefix(t(), String.t()) :: t()
  def prefix(%__MODULE__{} = req, prefix) do
    %{req | prefix: prefix}
  end

  @doc """
  Sets the content type for uploads.

  ## Examples

      req |> S3.Request.content_type("image/jpeg")
  """
  @spec content_type(t(), String.t()) :: t()
  def content_type(%__MODULE__{} = req, content_type) do
    %{req | content_type: content_type}
  end

  @doc """
  Sets custom metadata for uploads.

  ## Examples

      req |> S3.Request.metadata(%{user_id: "123", source: "web"})
  """
  @spec metadata(t(), map()) :: t()
  def metadata(%__MODULE__{} = req, metadata) do
    %{req | metadata: metadata}
  end

  @doc """
  Sets the ACL for uploads.

  ## Examples

      req |> S3.Request.acl("public-read")
  """
  @spec acl(t(), String.t()) :: t()
  def acl(%__MODULE__{} = req, acl) do
    %{req | acl: acl}
  end

  @doc """
  Sets the storage class for uploads.

  ## Examples

      req |> S3.Request.storage_class("GLACIER")
  """
  @spec storage_class(t(), String.t()) :: t()
  def storage_class(%__MODULE__{} = req, storage_class) do
    %{req | storage_class: storage_class}
  end

  @doc """
  Sets the expiration for presigned URLs.

  Accepts seconds or duration tuples.

  ## Examples

      req |> S3.Request.expires_in(3600)
      req |> S3.Request.expires_in({5, :minutes})
      req |> S3.Request.expires_in({1, :hour})
      req |> S3.Request.expires_in({7, :days})
  """
  @spec expires_in(t(), pos_integer() | {pos_integer(), atom()}) :: t()
  def expires_in(%__MODULE__{} = req, duration) do
    %{req | expires_in: normalize_expiration(duration)}
  end

  @doc """
  Sets the HTTP method for presigned URLs.

  ## Examples

      req |> S3.Request.method(:put)
  """
  @spec method(t(), :get | :put) :: t()
  def method(%__MODULE__{} = req, method) when method in [:get, :put] do
    %{req | method: method}
  end

  @doc """
  Sets concurrency for batch operations.

  ## Examples

      req |> S3.Request.concurrency(10)
  """
  @spec concurrency(t(), pos_integer()) :: t()
  def concurrency(%__MODULE__{} = req, concurrency) do
    %{req | concurrency: concurrency}
  end

  @doc """
  Sets timeout for operations (in milliseconds).

  ## Examples

      req |> S3.Request.timeout(120_000)
      req |> S3.Request.timeout({2, :minutes})
  """
  @spec timeout(t(), pos_integer() | {pos_integer(), atom()}) :: t()
  def timeout(%__MODULE__{} = req, duration) do
    timeout_ms =
      case duration do
        {n, unit} -> normalize_expiration({n, unit}) * 1000
        ms when is_integer(ms) -> ms
      end

    %{req | timeout: timeout_ms}
  end

  # ============================================
  # Single Operations
  # ============================================

  @doc """
  Uploads content to S3.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.put("s3://bucket/file.txt", "content")

      S3.Request.new(config)
      |> S3.Request.bucket("my-bucket")
      |> S3.Request.prefix("uploads/")
      |> S3.Request.content_type("text/plain")
      |> S3.Request.put("file.txt", "content")
  """
  @spec put(t(), String.t(), binary()) :: :ok | {:error, term()}
  def put(%__MODULE__{} = req, key_or_uri, content) do
    {bucket, key} = resolve_location(req, key_or_uri)
    opts = build_upload_opts(req)

    Events.Services.S3.Client.put_object(req.config, bucket, key, content, opts)
  end

  @doc """
  Downloads content from S3.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.get("s3://bucket/file.txt")

      S3.Request.new(config)
      |> S3.Request.bucket("my-bucket")
      |> S3.Request.get("path/to/file.txt")
  """
  @spec get(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def get(%__MODULE__{} = req, key_or_uri) do
    {bucket, key} = resolve_location(req, key_or_uri)
    Events.Services.S3.Client.get_object(req.config, bucket, key)
  end

  @doc """
  Deletes an object from S3.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.delete("s3://bucket/file.txt")
  """
  @spec delete(t(), String.t()) :: :ok | {:error, term()}
  def delete(%__MODULE__{} = req, key_or_uri) do
    {bucket, key} = resolve_location(req, key_or_uri)
    Events.Services.S3.Client.delete_object(req.config, bucket, key)
  end

  @doc """
  Checks if an object exists.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.exists?("s3://bucket/file.txt")
  """
  @spec exists?(t(), String.t()) :: boolean()
  def exists?(%__MODULE__{} = req, key_or_uri) do
    {bucket, key} = resolve_location(req, key_or_uri)

    case Events.Services.S3.Client.head_object(req.config, bucket, key) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Gets object metadata.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.head("s3://bucket/file.txt")
  """
  @spec head(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def head(%__MODULE__{} = req, key_or_uri) do
    {bucket, key} = resolve_location(req, key_or_uri)
    Events.Services.S3.Client.head_object(req.config, bucket, key)
  end

  @doc """
  Lists objects.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.list("s3://bucket/prefix/")

      S3.Request.new(config)
      |> S3.Request.bucket("my-bucket")
      |> S3.Request.prefix("uploads/")
      |> S3.Request.list()
  """
  @spec list(t()) :: {:ok, map()} | {:error, term()}
  @spec list(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def list(req, key_or_uri \\ nil)

  def list(%__MODULE__{} = req, nil) do
    bucket = req.bucket || raise ArgumentError, "bucket required"
    Events.Services.S3.Client.list_objects(req.config, bucket, req.prefix, [])
  end

  def list(%__MODULE__{} = req, key_or_uri) do
    {bucket, prefix} = resolve_location(req, key_or_uri)
    Events.Services.S3.Client.list_objects(req.config, bucket, prefix, [])
  end

  @doc """
  Copies an object.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.copy("s3://bucket/old.txt", "s3://bucket/new.txt")
  """
  @spec copy(t(), String.t(), String.t()) :: :ok | {:error, term()}
  def copy(%__MODULE__{} = req, source_uri, dest_uri) do
    {src_bucket, src_key} = resolve_location(req, source_uri)
    {dst_bucket, dst_key} = resolve_location(req, dest_uri)
    Events.Services.S3.Client.copy_object(req.config, src_bucket, src_key, dst_bucket, dst_key)
  end

  @doc """
  Generates a presigned URL.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.expires_in({5, :minutes})
      |> S3.Request.presign("s3://bucket/file.pdf")

      S3.Request.new(config)
      |> S3.Request.method(:put)
      |> S3.Request.presign("s3://bucket/upload.jpg")
  """
  @spec presign(t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def presign(%__MODULE__{} = req, key_or_uri) do
    {bucket, key} = resolve_location(req, key_or_uri)
    Events.Services.S3.Client.presigned_url(req.config, bucket, key, req.method, req.expires_in)
  end

  # ============================================
  # Batch Operations
  # ============================================

  @doc """
  Uploads multiple files in parallel.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.bucket("my-bucket")
      |> S3.Request.prefix("uploads/")
      |> S3.Request.concurrency(10)
      |> S3.Request.put_all([{"a.txt", "content"}, {"b.txt", "content"}])

      # With full URIs
      S3.Request.new(config)
      |> S3.Request.put_all([
        {"s3://bucket/a.txt", "content a"},
        {"s3://bucket/b.txt", "content b"}
      ])
  """
  @spec put_all(t(), [{String.t(), binary()}]) :: [{:ok, String.t()} | {:error, String.t(), term()}]
  def put_all(%__MODULE__{} = req, files) do
    opts = build_upload_opts(req)

    files
    |> Task.async_stream(
      fn {key_or_uri, content} ->
        {bucket, key} = resolve_location(req, key_or_uri)
        uri = Events.Services.S3.URI.build(bucket, key)

        case Events.Services.S3.Client.put_object(req.config, bucket, key, content, opts) do
          :ok -> {:ok, uri}
          {:error, reason} -> {:error, uri, reason}
        end
      end,
      max_concurrency: req.concurrency,
      timeout: req.timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Downloads multiple files in parallel.

  Supports glob patterns.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.get_all(["s3://bucket/a.txt", "s3://bucket/b.txt"])

      # With globs
      S3.Request.new(config)
      |> S3.Request.get_all(["s3://bucket/docs/*.pdf"])
  """
  @spec get_all(t(), [String.t()]) :: [{:ok, String.t(), binary()} | {:error, String.t(), term()}]
  def get_all(%__MODULE__{} = req, uris) do
    uris
    |> Enum.flat_map(&expand_pattern(req, &1))
    |> Task.async_stream(
      fn uri ->
        case get(req, uri) do
          {:ok, content} -> {:ok, uri, content}
          {:error, reason} -> {:error, uri, reason}
        end
      end,
      max_concurrency: req.concurrency,
      timeout: req.timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Deletes multiple objects in parallel.

  Supports glob patterns.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.delete_all(["s3://bucket/old/*.tmp"])
  """
  @spec delete_all(t(), [String.t()]) :: [{:ok, String.t()} | {:error, String.t(), term()}]
  def delete_all(%__MODULE__{} = req, uris) do
    uris
    |> Enum.flat_map(&expand_pattern(req, &1))
    |> Task.async_stream(
      fn uri ->
        case delete(req, uri) do
          :ok -> {:ok, uri}
          {:error, reason} -> {:error, uri, reason}
        end
      end,
      max_concurrency: req.concurrency,
      timeout: req.timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Copies multiple objects in parallel.

  ## Examples

      # Explicit pairs
      S3.Request.new(config)
      |> S3.Request.copy_all([
        {"s3://bucket/old/a.txt", "s3://bucket/new/a.txt"},
        {"s3://bucket/old/b.txt", "s3://bucket/new/b.txt"}
      ])

      # Glob with destination
      S3.Request.new(config)
      |> S3.Request.copy_all("s3://source/*.jpg", to: "s3://dest/images/")
  """
  @spec copy_all(t(), [{String.t(), String.t()}] | String.t(), keyword()) ::
          [{:ok, String.t(), String.t()} | {:error, String.t(), term()}]
  def copy_all(req, source, opts \\ [])

  def copy_all(%__MODULE__{} = req, pairs, _opts) when is_list(pairs) do
    pairs
    |> Task.async_stream(
      fn {source_uri, dest_uri} ->
        case copy(req, source_uri, dest_uri) do
          :ok -> {:ok, source_uri, dest_uri}
          {:error, reason} -> {:error, source_uri, reason}
        end
      end,
      max_concurrency: req.concurrency,
      timeout: req.timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  def copy_all(%__MODULE__{} = req, source_pattern, opts) when is_binary(source_pattern) do
    dest_base = Keyword.fetch!(opts, :to)
    {dest_bucket, dest_prefix} = Events.Services.S3.URI.parse!(dest_base)
    dest_prefix = String.trim_trailing(dest_prefix, "/")
    dest_prefix = if dest_prefix == "", do: "", else: dest_prefix <> "/"

    source_pattern
    |> expand_pattern(req)
    |> Task.async_stream(
      fn source_uri ->
        filename = Events.Services.S3.URI.filename(source_uri)
        dest_uri = Events.Services.S3.URI.build(dest_bucket, dest_prefix <> filename)

        case copy(req, source_uri, dest_uri) do
          :ok -> {:ok, source_uri, dest_uri}
          {:error, reason} -> {:error, source_uri, reason}
        end
      end,
      max_concurrency: req.concurrency,
      timeout: req.timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Generates presigned URLs for multiple URIs.

  Supports glob patterns.

  ## Examples

      S3.Request.new(config)
      |> S3.Request.expires_in({1, :hour})
      |> S3.Request.presign_all(["s3://bucket/a.pdf", "s3://bucket/docs/*.pdf"])
  """
  @spec presign_all(t(), [String.t()]) ::
          [{:ok, String.t(), String.t()} | {:error, String.t(), term()}]
  def presign_all(%__MODULE__{} = req, uris) do
    uris
    |> Enum.flat_map(&expand_pattern(req, &1))
    |> Enum.map(fn uri ->
      case presign(req, uri) do
        {:ok, url} -> {:ok, uri, url}
        {:error, reason} -> {:error, uri, reason}
      end
    end)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp resolve_location(%__MODULE__{}, "s3://" <> _ = uri) do
    Events.Services.S3.URI.parse!(uri)
  end

  defp resolve_location(%__MODULE__{bucket: nil}, key) do
    raise ArgumentError, "bucket required for key #{inspect(key)}, use bucket/2 or full s3:// URI"
  end

  defp resolve_location(%__MODULE__{bucket: bucket, prefix: prefix}, key) do
    full_key =
      case prefix do
        "" -> key
        p -> String.trim_trailing(p, "/") <> "/" <> key
      end

    {bucket, full_key}
  end

  defp build_upload_opts(%__MODULE__{} = req) do
    []
    |> maybe_add(:content_type, req.content_type)
    |> maybe_add(:metadata, if(map_size(req.metadata) > 0, do: req.metadata))
    |> maybe_add(:acl, req.acl)
    |> maybe_add(:storage_class, req.storage_class)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp expand_pattern(%__MODULE__{} = req, uri) do
    alias Events.Services.S3.URI, as: S3URI

    case S3URI.parse(uri) do
      {:ok, bucket, key} ->
        if String.contains?(key, "*") do
          expand_glob(req, bucket, key)
        else
          [uri]
        end

      :error ->
        [uri]
    end
  end

  defp expand_glob(%__MODULE__{} = req, bucket, key_pattern) do
    alias Events.Services.S3.URI, as: S3URI

    # Get the prefix (everything before the first *)
    prefix = key_pattern |> String.split("*") |> List.first() |> get_directory_prefix()

    case Events.Services.S3.Client.list_objects(req.config, bucket, prefix, limit: 10_000) do
      {:ok, %{files: files}} ->
        files
        |> Enum.map(& &1.key)
        |> Enum.filter(&glob_match?(&1, prefix, key_pattern))
        |> Enum.map(&S3URI.build(bucket, &1))

      {:error, _} ->
        []
    end
  end

  defp get_directory_prefix(path) do
    case String.split(path, "/") |> Enum.drop(-1) do
      [] -> ""
      parts -> Enum.join(parts, "/") <> "/"
    end
  end

  defp glob_match?(key, prefix, pattern) do
    relative_key = String.replace_prefix(key, prefix, "")
    relative_pattern = String.replace_prefix(pattern, prefix, "")

    regex_pattern =
      relative_pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> then(&("^" <> &1 <> "$"))

    case Regex.compile(regex_pattern) do
      {:ok, regex} -> Regex.match?(regex, relative_key)
      _ -> false
    end
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
