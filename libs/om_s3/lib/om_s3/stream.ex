defmodule OmS3.Stream do
  @moduledoc """
  Streaming operations for large S3 objects.

  Provides memory-efficient streaming for downloading and uploading large files
  without loading the entire content into memory.

  ## Download Streaming

      # Stream to file
      OmS3.Stream.download("s3://bucket/large-file.zip", config)
      |> Stream.into(File.stream!("/tmp/output.zip"))
      |> Stream.run()

      # Process chunks
      OmS3.Stream.download("s3://bucket/data.csv", config)
      |> Stream.each(&process_chunk/1)
      |> Stream.run()

      # With callback
      OmS3.Stream.download("s3://bucket/file.zip", config, fn chunk ->
        IO.write(file, chunk)
      end)

  ## Upload Streaming

      # Stream from file
      File.stream!("/path/to/large-file.zip", [], 5_242_880)
      |> OmS3.Stream.upload("s3://bucket/uploaded.zip", config)

      # Stream from enumerable
      data_stream
      |> OmS3.Stream.upload("s3://bucket/file.dat", config, chunk_size: 5_242_880)
  """

  alias OmS3.Config
  alias OmS3.URI, as: S3URI

  @default_chunk_size 5 * 1024 * 1024
  @min_chunk_size 5 * 1024 * 1024

  @type stream_opts :: [
          chunk_size: pos_integer(),
          timeout: pos_integer()
        ]

  # ============================================
  # Download Streaming
  # ============================================

  @doc """
  Creates a stream for downloading an S3 object in chunks.

  Returns an `Enumerable` that yields binary chunks as they are received.
  Memory-efficient for large files.

  ## Options

  - `:chunk_size` - Size of each chunk in bytes (default: 5MB)
  - `:timeout` - HTTP timeout in ms (default: 60_000)

  ## Examples

      # Stream to file
      OmS3.Stream.download("s3://bucket/large.zip", config)
      |> Stream.into(File.stream!("/tmp/large.zip"))
      |> Stream.run()

      # Count bytes
      OmS3.Stream.download("s3://bucket/file.dat", config)
      |> Enum.reduce(0, fn chunk, acc -> acc + byte_size(chunk) end)

      # With custom chunk size
      OmS3.Stream.download("s3://bucket/file.dat", config, chunk_size: 10_485_760)
  """
  @spec download(String.t(), Config.t(), stream_opts()) :: Enumerable.t()
  def download(uri, %Config{} = config, opts \\ []) do
    {bucket, key} = S3URI.parse!(uri)
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    timeout = Keyword.get(opts, :timeout, 60_000)

    Stream.resource(
      fn -> init_download(config, bucket, key, chunk_size, timeout) end,
      &stream_download/1,
      &cleanup_download/1
    )
  end

  @doc """
  Downloads an S3 object with a callback for each chunk.

  Useful for processing data as it streams without accumulating in memory.

  ## Examples

      # Write to file handle
      {:ok, file} = File.open("/tmp/output.zip", [:write, :binary])
      OmS3.Stream.download_with_callback("s3://bucket/large.zip", config, fn chunk ->
        IO.binwrite(file, chunk)
      end)
      File.close(file)

      # Progress tracking
      OmS3.Stream.download_with_callback(uri, config, fn chunk ->
        bytes = byte_size(chunk)
        send(self(), {:progress, bytes})
        process_chunk(chunk)
      end)
  """
  @spec download_with_callback(String.t(), Config.t(), (binary() -> any()), stream_opts()) ::
          :ok | {:error, term()}
  def download_with_callback(uri, %Config{} = config, callback, opts \\ [])
      when is_function(callback, 1) do
    uri
    |> download(config, opts)
    |> Enum.each(callback)

    :ok
  rescue
    e -> {:error, e}
  end

  @doc """
  Downloads an S3 object directly to a file.

  Convenience function that handles file operations.

  ## Options

  - `:chunk_size` - Size of each chunk in bytes (default: 5MB)
  - `:timeout` - HTTP timeout in ms (default: 60_000)
  - `:overwrite` - Whether to overwrite existing file (default: true)

  ## Examples

      :ok = OmS3.Stream.download_to_file("s3://bucket/large.zip", "/tmp/large.zip", config)

      # Without overwriting
      {:error, :file_exists} = OmS3.Stream.download_to_file(uri, path, config, overwrite: false)
  """
  @spec download_to_file(String.t(), String.t(), Config.t(), keyword()) ::
          :ok | {:error, term()}
  def download_to_file(uri, local_path, %Config{} = config, opts \\ []) do
    overwrite = Keyword.get(opts, :overwrite, true)
    stream_opts = Keyword.take(opts, [:chunk_size, :timeout])

    cond do
      not overwrite and File.exists?(local_path) ->
        {:error, :file_exists}

      true ->
        dir = Path.dirname(local_path)
        File.mkdir_p!(dir)

        uri
        |> download(config, stream_opts)
        |> Stream.into(File.stream!(local_path, [:write, :binary]))
        |> Stream.run()

        :ok
    end
  rescue
    e -> {:error, e}
  end

  # ============================================
  # Upload Streaming
  # ============================================

  @doc """
  Uploads a stream to S3 using multipart upload.

  Takes an enumerable of binary chunks and uploads them efficiently.

  ## Options

  - `:chunk_size` - Minimum chunk size for multipart (default/minimum: 5MB)
  - `:content_type` - MIME type (auto-detected from key if not provided)
  - `:metadata` - Custom metadata map
  - `:acl` - Access control ("private", "public-read")
  - `:storage_class` - Storage class ("STANDARD", "GLACIER", etc.)
  - `:timeout` - HTTP timeout in ms (default: 60_000)

  ## Examples

      # From file stream
      File.stream!("/path/to/large.zip", [], 5_242_880)
      |> OmS3.Stream.upload("s3://bucket/large.zip", config)

      # From enumerable with options
      data_chunks
      |> OmS3.Stream.upload("s3://bucket/data.bin", config,
        content_type: "application/octet-stream",
        metadata: %{source: "streaming"}
      )
  """
  @spec upload(Enumerable.t(), String.t(), Config.t(), keyword()) ::
          :ok | {:error, term()}
  def upload(stream, uri, %Config{} = config, opts \\ []) do
    {bucket, key} = S3URI.parse!(uri)
    chunk_size = max(Keyword.get(opts, :chunk_size, @default_chunk_size), @min_chunk_size)
    timeout = Keyword.get(opts, :timeout, 60_000)

    with {:ok, upload_id} <- init_multipart_upload(config, bucket, key, opts),
         {:ok, parts} <- upload_parts(stream, config, bucket, key, upload_id, chunk_size, timeout),
         :ok <- complete_multipart_upload(config, bucket, key, upload_id, parts) do
      :ok
    else
      {:error, reason} = error ->
        # Attempt to abort on failure
        abort_multipart_upload(config, bucket, key, reason)
        error
    end
  end

  @doc """
  Uploads a local file to S3 using streaming.

  Memory-efficient upload for large files.

  ## Options

  Same as `upload/4`.

  ## Examples

      :ok = OmS3.Stream.upload_file("/path/to/large.zip", "s3://bucket/large.zip", config)
  """
  @spec upload_file(String.t(), String.t(), Config.t(), keyword()) ::
          :ok | {:error, term()}
  def upload_file(local_path, uri, %Config{} = config, opts \\ []) do
    chunk_size = max(Keyword.get(opts, :chunk_size, @default_chunk_size), @min_chunk_size)

    local_path
    |> File.stream!([], chunk_size)
    |> upload(uri, config, opts)
  end

  # ============================================
  # Private: Download Implementation
  # ============================================

  defp init_download(config, bucket, key, chunk_size, timeout) do
    case get_object_size(config, bucket, key) do
      {:ok, size} ->
        %{
          config: config,
          bucket: bucket,
          key: key,
          chunk_size: chunk_size,
          timeout: timeout,
          total_size: size,
          offset: 0,
          done: false
        }

      {:error, reason} ->
        %{error: reason, done: true}
    end
  end

  defp stream_download(%{done: true} = state), do: {:halt, state}
  defp stream_download(%{error: _} = state), do: {:halt, state}

  defp stream_download(state) do
    %{
      config: config,
      bucket: bucket,
      key: key,
      chunk_size: chunk_size,
      timeout: timeout,
      total_size: total_size,
      offset: offset
    } = state

    end_byte = min(offset + chunk_size - 1, total_size - 1)
    range = "bytes=#{offset}-#{end_byte}"

    case get_object_range(config, bucket, key, range, timeout) do
      {:ok, chunk} ->
        new_offset = end_byte + 1
        done = new_offset >= total_size
        {[chunk], %{state | offset: new_offset, done: done}}

      {:error, reason} ->
        {[{:error, reason}], %{state | done: true, error: reason}}
    end
  end

  defp cleanup_download(_state), do: :ok

  defp get_object_size(config, bucket, key) do
    case OmS3.Client.head_object(config, bucket, key) do
      {:ok, %{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_object_range(config, bucket, key, range, timeout) do
    req = build_req(config, timeout)
    url = "s3://#{bucket}/#{key}"

    case Req.get(req, url: url, headers: %{"range" => range}) do
      {:ok, %{status: status, body: body}} when status in [200, 206] ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================
  # Private: Upload Implementation
  # ============================================

  defp init_multipart_upload(config, bucket, key, opts) do
    req = build_req(config, Keyword.get(opts, :timeout, 60_000))
    url = "s3://#{bucket}/#{key}?uploads"
    headers = OmS3.Headers.build_upload_headers(key, opts, config)

    case Req.post(req, url: url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        upload_id = get_in(body, ["InitiateMultipartUploadResult", "UploadId"])
        {:ok, upload_id}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upload_parts(stream, config, bucket, key, upload_id, chunk_size, timeout) do
    stream
    |> buffer_chunks(chunk_size)
    |> Stream.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {chunk, part_number}, {:ok, parts} ->
      case upload_part(config, bucket, key, upload_id, part_number, chunk, timeout) do
        {:ok, etag} ->
          {:cont, {:ok, [{part_number, etag} | parts]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  defp buffer_chunks(stream, chunk_size) do
    # Buffer incoming chunks and emit complete chunks of chunk_size
    # Uses a simple accumulator-based approach
    Stream.transform(stream, <<>>, fn incoming_chunk, buffer ->
      combined = buffer <> incoming_chunk
      split_into_chunks(combined, chunk_size)
    end)
  end

  defp split_into_chunks(data, chunk_size) do
    do_split_chunks(data, chunk_size, [])
  end

  defp do_split_chunks(data, chunk_size, acc) when byte_size(data) >= chunk_size do
    {chunk, rest} = :erlang.split_binary(data, chunk_size)
    do_split_chunks(rest, chunk_size, [chunk | acc])
  end

  defp do_split_chunks(remainder, _chunk_size, acc) do
    # Return accumulated chunks (reversed) and remainder as new buffer
    {Enum.reverse(acc), remainder}
  end

  defp upload_part(config, bucket, key, upload_id, part_number, chunk, timeout) do
    req = build_req(config, timeout)
    url = "s3://#{bucket}/#{key}?partNumber=#{part_number}&uploadId=#{upload_id}"

    case Req.put(req, url: url, body: chunk) do
      {:ok, %{status: 200, headers: headers}} ->
        etag =
          headers
          |> Enum.into(%{})
          |> Map.get("etag", "")
          |> String.trim("\"")

        {:ok, etag}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete_multipart_upload(config, bucket, key, upload_id, parts) do
    req = build_req(config, 60_000)
    url = "s3://#{bucket}/#{key}?uploadId=#{upload_id}"

    body = build_complete_multipart_body(parts)

    case Req.post(req, url: url, body: body, headers: %{"content-type" => "application/xml"}) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:s3_error, status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_complete_multipart_body(parts) do
    parts_xml =
      parts
      |> Enum.map(fn {part_number, etag} ->
        "<Part><PartNumber>#{part_number}</PartNumber><ETag>\"#{etag}\"</ETag></Part>"
      end)
      |> Enum.join()

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><CompleteMultipartUpload>#{parts_xml}</CompleteMultipartUpload>"
  end

  defp abort_multipart_upload(config, bucket, key, upload_id) when is_binary(upload_id) do
    req = build_req(config, 30_000)
    url = "s3://#{bucket}/#{key}?uploadId=#{upload_id}"
    Req.delete(req, url: url)
    :ok
  rescue
    _ -> :ok
  end

  defp abort_multipart_upload(_config, _bucket, _key, _reason), do: :ok

  # ============================================
  # Private: Request Building
  # ============================================

  defp build_req(%Config{} = config, timeout) do
    connect_opts = OmS3.Config.connect_options(config)
    aws_sigv4 = OmS3.Config.aws_sigv4_options(config)

    Req.new(
      aws_sigv4: aws_sigv4,
      connect_options: connect_opts,
      receive_timeout: timeout,
      pool_timeout: config.pool_timeout,
      retry: :safe_transient,
      max_retries: config.max_retries
    )
    |> ReqS3.attach()
  end

end
