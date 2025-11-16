defmodule Events.Services.Aws.S3.Adapter do
  @moduledoc """
  S3 adapter implementation using ReqS3.

  Provides production-ready S3 operations using the ReqS3 plugin
  by Dashbit/Wojtek Mach.

  ## Features

  - Simple `s3://` URL scheme for S3 operations
  - Automatic XML parsing for list operations
  - Built-in AWS Signature V4 authentication
  - Presigned URL generation for uploads and downloads
  - Support for S3-compatible services (MinIO, DigitalOcean Spaces, etc.)

  ## Configuration

      config :events, :aws,
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        bucket: "my-bucket"

  ## Usage

      context = Context.new(
        access_key_id: "...",
        secret_access_key: "...",
        region: "us-east-1",
        bucket: "my-bucket"
      )

      # Upload file
      S3.upload(context, "documents/file.pdf", content)

      # Generate presigned URL for upload (5 minutes)
      {:ok, url} = S3.presigned_url(context, :put, "uploads/photo.jpg", expires_in: 300)

      # Generate presigned URL for download (1 hour)
      {:ok, url} = S3.presigned_url(context, :get, "documents/file.pdf", expires_in: 3600)

      # List files
      {:ok, %{objects: objects}} = S3.list_objects(context, prefix: "uploads/")
  """

  @behaviour Events.Services.Aws.S3
  @behaviour Events.Behaviours.Adapter

  alias Events.Services.Aws.Context

  @default_expires_in 3600
  @default_region "us-east-1"

  ## Adapter Callbacks

  @impl Events.Behaviours.Adapter
  def adapter_name, do: :s3

  @impl Events.Behaviours.Adapter
  def adapter_config(opts) do
    %{
      access_key_id: Keyword.fetch!(opts, :access_key_id),
      secret_access_key: Keyword.fetch!(opts, :secret_access_key),
      region: Keyword.get(opts, :region, @default_region),
      bucket: Keyword.fetch!(opts, :bucket)
    }
  end

  ## S3 Callbacks

  @impl Events.Services.Aws.S3
  def upload(%Context{} = context, key, content, opts \\ []) do
    req = build_req(context)
    url = "s3://#{context.bucket}/#{key}"

    headers = build_upload_headers(opts)

    case Req.put(req, url: url, body: content, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Events.Services.Aws.S3
  def get_object(%Context{} = context, key) do
    req = build_req(context)
    url = "s3://#{context.bucket}/#{key}"

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

  @impl Events.Services.Aws.S3
  def delete_object(%Context{} = context, key) do
    req = build_req(context)
    url = "s3://#{context.bucket}/#{key}"

    case Req.delete(req, url: url) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 404}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Events.Services.Aws.S3
  def object_exists?(%Context{} = context, key) do
    req = build_req(context)
    url = "s3://#{context.bucket}/#{key}"

    case Req.head(req, url: url) do
      {:ok, %{status: 200}} ->
        {:ok, true}

      {:ok, %{status: 404}} ->
        {:ok, false}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Events.Services.Aws.S3
  def list_objects(%Context{} = context, opts \\ []) do
    req = build_req(context)
    prefix = Keyword.get(opts, :prefix, "")
    max_keys = Keyword.get(opts, :max_keys, 1000)
    continuation_token = Keyword.get(opts, :continuation_token)
    sort_by = Keyword.get(opts, :sort_by, :last_modified)
    sort_order = Keyword.get(opts, :sort_order, :desc)

    # Build URL with query parameters
    url = build_list_url(context.bucket, prefix, max_keys, continuation_token)

    case Req.get(req, url: url) do
      {:ok, %{status: 200, body: body}} ->
        case parse_list_response(body) do
          {:ok, result} ->
            sorted_objects = sort_objects(result.objects, sort_by, sort_order)
            {:ok, %{result | objects: sorted_objects}}

          error ->
            error
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Events.Services.Aws.S3
  def presigned_url(%Context{} = context, method, key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, @default_expires_in)

    # Convert expires_in from seconds to milliseconds for ReqS3
    expires_in_ms = expires_in * 1000

    presign_opts = [
      bucket: context.bucket,
      key: key,
      access_key_id: context.access_key_id,
      secret_access_key: context.secret_access_key,
      region: context.region,
      expires_in: expires_in_ms
    ]

    presign_opts = maybe_add_endpoint_url(presign_opts, context)

    case method do
      :get ->
        # For downloads, use presign_url
        url = ReqS3.presign_url(presign_opts)
        {:ok, url}

      :put ->
        # For uploads, use presign_form and extract URL
        form = ReqS3.presign_form(presign_opts)
        {:ok, form.url}
    end
  rescue
    error ->
      {:error, {:presign_error, error}}
  end

  @impl Events.Services.Aws.S3
  def copy_object(%Context{} = context, source_key, dest_key) do
    req = build_req(context)
    url = "s3://#{context.bucket}/#{dest_key}"
    copy_source = "/#{context.bucket}/#{source_key}"

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

  @impl Events.Services.Aws.S3
  def head_object(%Context{} = context, key) do
    req = build_req(context)
    url = "s3://#{context.bucket}/#{key}"

    case Req.head(req, url: url) do
      {:ok, %{status: 200, headers: headers}} ->
        metadata = parse_head_response(headers)
        {:ok, metadata}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Functions

  defp build_req(%Context{} = context) do
    aws_sigv4 = [
      access_key_id: context.access_key_id,
      secret_access_key: context.secret_access_key,
      region: context.region
    ]

    Req.new(aws_sigv4: aws_sigv4)
    |> ReqS3.attach()
  end

  defp build_upload_headers(opts) do
    %{}
    |> maybe_add_content_type(opts[:content_type])
    |> maybe_add_metadata(opts[:metadata])
    |> maybe_add_acl(opts[:acl])
    |> maybe_add_storage_class(opts[:storage_class])
  end

  defp maybe_add_content_type(headers, nil), do: headers

  defp maybe_add_content_type(headers, content_type),
    do: Map.put(headers, "content-type", content_type)

  defp maybe_add_metadata(headers, nil), do: headers

  defp maybe_add_metadata(headers, metadata) do
    Enum.reduce(metadata, headers, fn {key, value}, acc ->
      Map.put(acc, "x-amz-meta-#{key}", value)
    end)
  end

  defp maybe_add_acl(headers, nil), do: headers

  defp maybe_add_acl(headers, acl),
    do: Map.put(headers, "x-amz-acl", acl)

  defp maybe_add_storage_class(headers, nil), do: headers

  defp maybe_add_storage_class(headers, storage_class),
    do: Map.put(headers, "x-amz-storage-class", storage_class)

  defp build_list_url(bucket, prefix, max_keys, continuation_token) do
    query_params =
      [
        {"list-type", "2"},
        {"prefix", prefix},
        {"max-keys", to_string(max_keys)}
      ]
      |> maybe_add_continuation_token(continuation_token)

    query_string = URI.encode_query(query_params)
    "s3://#{bucket}?#{query_string}"
  end

  defp maybe_add_continuation_token(params, nil), do: params

  defp maybe_add_continuation_token(params, token) do
    params ++ [{"continuation-token", token}]
  end

  defp maybe_add_endpoint_url(opts, %Context{endpoint_url: nil}), do: opts

  defp maybe_add_endpoint_url(opts, %Context{endpoint_url: endpoint_url}) do
    Keyword.put(opts, :aws_endpoint_url_s3, endpoint_url)
  end

  defp parse_list_response(body) when is_map(body) do
    # ReqS3 automatically parses XML to map
    objects =
      body
      |> get_in(["ListBucketResult", "Contents"])
      |> List.wrap()
      |> Enum.map(&parse_object/1)

    continuation_token =
      get_in(body, ["ListBucketResult", "NextContinuationToken"])

    {:ok, %{objects: objects, continuation_token: continuation_token}}
  rescue
    error ->
      {:error, {:parse_error, error}}
  end

  defp parse_object(obj) when is_map(obj) do
    %{
      key: obj["Key"],
      size: parse_integer(obj["Size"]),
      last_modified: parse_datetime(obj["LastModified"]),
      etag: obj["ETag"],
      storage_class: obj["StorageClass"] || "STANDARD"
    }
  end

  defp parse_integer(nil), do: 0
  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value) when is_binary(value), do: String.to_integer(value)

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_head_response(headers) do
    headers
    |> Enum.into(%{})
    |> Map.new(fn {key, value} -> {String.downcase(to_string(key)), value} end)
  end

  defp sort_objects(objects, sort_by, sort_order) do
    sorted =
      case sort_by do
        :last_modified ->
          Enum.sort_by(objects, & &1.last_modified, DateTime)

        :size ->
          Enum.sort_by(objects, & &1.size)

        :key ->
          Enum.sort_by(objects, & &1.key)

        _ ->
          # Default to last_modified
          Enum.sort_by(objects, & &1.last_modified, DateTime)
      end

    case sort_order do
      :asc -> sorted
      :desc -> Enum.reverse(sorted)
      _ -> Enum.reverse(sorted)
    end
  end
end
