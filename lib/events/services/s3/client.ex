defmodule Events.Services.S3.Client do
  @moduledoc """
  Low-level S3 HTTP client using Req and ReqS3.

  This module handles the actual HTTP communication with S3.
  Use the `Events.Services.S3` module for the public API.
  """

  alias Events.Services.S3.Config

  @default_expires_in 3600

  # ============================================
  # Object Operations
  # ============================================

  @doc """
  Uploads an object to S3.
  """
  @spec put_object(Config.t(), String.t(), String.t(), binary(), keyword()) ::
          :ok | {:error, term()}
  def put_object(%Config{} = config, bucket, key, content, opts \\ []) do
    req = build_req(config)
    url = "s3://#{bucket}/#{key}"
    headers = build_upload_headers(key, opts)

    case Req.put(req, url: url, body: content, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads an object from S3.
  """
  @spec get_object(Config.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def get_object(%Config{} = config, bucket, key) do
    req = build_req(config)
    url = "s3://#{bucket}/#{key}"

    case Req.get(req, url: url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an object from S3.
  """
  @spec delete_object(Config.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete_object(%Config{} = config, bucket, key) do
    req = build_req(config)
    url = "s3://#{bucket}/#{key}"

    case Req.delete(req, url: url) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 404}} ->
        # S3 returns success even for non-existent objects
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets object metadata (HEAD request).
  """
  @spec head_object(Config.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def head_object(%Config{} = config, bucket, key) do
    req = build_req(config)
    url = "s3://#{bucket}/#{key}"

    case Req.head(req, url: url) do
      {:ok, %{status: 200, headers: headers}} ->
        {:ok, parse_metadata(headers)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists objects in a bucket with optional prefix.
  """
  @spec list_objects(Config.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def list_objects(%Config{} = config, bucket, prefix, opts \\ []) do
    req = build_req(config)
    limit = Keyword.get(opts, :limit, 1000)
    token = Keyword.get(opts, :continuation_token)
    sort_field = Keyword.get(opts, :sort, :last_modified)
    sort_order = Keyword.get(opts, :order, :desc)

    url = build_list_url(bucket, prefix, limit, token)

    case Req.get(req, url: url) do
      {:ok, %{status: 200, body: body}} ->
        parse_list_response(body, sort_field, sort_order)

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Copies an object within S3.
  """
  @spec copy_object(Config.t(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def copy_object(%Config{} = config, source_bucket, source_key, dest_bucket, dest_key) do
    req = build_req(config)
    url = "s3://#{dest_bucket}/#{dest_key}"
    copy_source = "/#{source_bucket}/#{source_key}"
    headers = %{"x-amz-copy-source" => copy_source}

    case Req.put(req, url: url, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================
  # Presigned URLs
  # ============================================

  @doc """
  Generates a presigned URL.
  """
  @spec presigned_url(Config.t(), String.t(), String.t(), :get | :put, pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_url(%Config{} = config, bucket, key, method, expires_in \\ @default_expires_in) do
    # ReqS3 expects milliseconds
    expires_in_ms = expires_in * 1000

    presign_opts =
      Config.presign_options(config, bucket, key)
      |> Keyword.put(:expires_in, expires_in_ms)

    case method do
      :get ->
        url = ReqS3.presign_url(presign_opts)
        {:ok, url}

      :put ->
        form = ReqS3.presign_form(presign_opts)
        {:ok, form.url}
    end
  rescue
    error ->
      {:error, {:presign_error, error}}
  end

  # ============================================
  # Private: Request Building
  # ============================================

  defp build_req(%Config{} = config) do
    connect_opts = Config.connect_options(config)
    aws_sigv4 = Config.aws_sigv4_options(config)

    Req.new(
      aws_sigv4: aws_sigv4,
      connect_options: connect_opts,
      receive_timeout: config.receive_timeout
    )
    |> ReqS3.attach()
  end

  defp build_upload_headers(key, opts) do
    content_type = Keyword.get(opts, :content_type) || detect_content_type(key)

    %{}
    |> Map.put("content-type", content_type)
    |> maybe_add_metadata(opts[:metadata])
    |> maybe_add_acl(opts[:acl])
    |> maybe_add_storage_class(opts[:storage_class])
  end

  defp maybe_add_metadata(headers, nil), do: headers
  defp maybe_add_metadata(headers, metadata) when map_size(metadata) == 0, do: headers

  defp maybe_add_metadata(headers, metadata) do
    Enum.reduce(metadata, headers, fn {k, v}, acc ->
      key = to_string(k)
      Map.put(acc, "x-amz-meta-#{key}", to_string(v))
    end)
  end

  defp maybe_add_acl(headers, nil), do: headers
  defp maybe_add_acl(headers, acl), do: Map.put(headers, "x-amz-acl", acl)

  defp maybe_add_storage_class(headers, nil), do: headers
  defp maybe_add_storage_class(headers, class), do: Map.put(headers, "x-amz-storage-class", class)

  # ============================================
  # Private: List Operations
  # ============================================

  defp build_list_url(bucket, prefix, limit, token) do
    params =
      [
        {"list-type", "2"},
        {"prefix", prefix},
        {"max-keys", to_string(limit)}
      ]
      |> maybe_add_token(token)

    query = URI.encode_query(params)
    "s3://#{bucket}?#{query}"
  end

  defp maybe_add_token(params, nil), do: params
  defp maybe_add_token(params, token), do: params ++ [{"continuation-token", token}]

  defp parse_list_response(body, sort_field, sort_order) when is_map(body) do
    files =
      body
      |> get_in(["ListBucketResult", "Contents"])
      |> List.wrap()
      |> Enum.map(&parse_object/1)
      |> sort_files(sort_field, sort_order)

    next_token = get_in(body, ["ListBucketResult", "NextContinuationToken"])

    {:ok, %{files: files, next: next_token}}
  rescue
    error ->
      {:error, {:parse_error, error}}
  end

  defp parse_object(obj) when is_map(obj) do
    %{
      key: obj["Key"],
      size: parse_int(obj["Size"]),
      last_modified: parse_datetime(obj["LastModified"]),
      etag: clean_etag(obj["ETag"]),
      storage_class: obj["StorageClass"] || "STANDARD"
    }
  end

  defp sort_files(files, field, order) do
    sorted =
      case field do
        :last_modified -> Enum.sort_by(files, & &1.last_modified, DateTime)
        :size -> Enum.sort_by(files, & &1.size)
        :key -> Enum.sort_by(files, & &1.key)
        _ -> Enum.sort_by(files, & &1.last_modified, DateTime)
      end

    case order do
      :asc -> sorted
      :desc -> Enum.reverse(sorted)
      _ -> Enum.reverse(sorted)
    end
  end

  # ============================================
  # Private: Response Parsing
  # ============================================

  defp parse_metadata(headers) do
    header_map =
      headers
      |> Enum.into(%{})
      |> Map.new(fn {k, v} -> {String.downcase(to_string(k)), v} end)

    custom_metadata =
      header_map
      |> Enum.filter(fn {k, _} -> String.starts_with?(k, "x-amz-meta-") end)
      |> Enum.map(fn {k, v} -> {String.replace(k, "x-amz-meta-", ""), v} end)
      |> Enum.into(%{})

    %{
      size: parse_int(header_map["content-length"]),
      content_type: header_map["content-type"],
      etag: clean_etag(header_map["etag"]),
      last_modified: parse_http_date(header_map["last-modified"]),
      metadata: custom_metadata
    }
  end

  defp parse_int(nil), do: 0
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_http_date(nil), do: nil

  defp parse_http_date(s) when is_binary(s) do
    # HTTP dates like "Wed, 15 Jan 2025 10:30:00 GMT"
    # Pattern: "Day, DD Mon YYYY HH:MM:SS GMT"
    regex = ~r/^\w+,\s+(\d{1,2})\s+(\w+)\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$/

    with [_, day, month, year, hour, min, sec] <- Regex.run(regex, s),
         {:ok, month_num} <- month_to_number(month),
         {:ok, date} <- Date.new(String.to_integer(year), month_num, String.to_integer(day)),
         {:ok, time} <-
           Time.new(String.to_integer(hour), String.to_integer(min), String.to_integer(sec)),
         {:ok, naive} <- NaiveDateTime.new(date, time) do
      DateTime.from_naive!(naive, "Etc/UTC")
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @months %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  defp month_to_number(month) do
    case Map.get(@months, month) do
      nil -> :error
      num -> {:ok, num}
    end
  end

  defp clean_etag(nil), do: nil
  defp clean_etag(etag), do: String.trim(etag, "\"")

  defp detect_content_type(key) do
    case Path.extname(key) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".pdf" -> "application/pdf"
      ".json" -> "application/json"
      ".xml" -> "application/xml"
      ".txt" -> "text/plain"
      ".html" -> "text/html"
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".zip" -> "application/zip"
      ".gz" -> "application/gzip"
      ".tar" -> "application/x-tar"
      ".mp4" -> "video/mp4"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".csv" -> "text/csv"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".xls" -> "application/vnd.ms-excel"
      ".xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      _ -> "application/octet-stream"
    end
  end
end
