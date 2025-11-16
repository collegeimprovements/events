defmodule Events.Services.Aws.S3.Pipeline do
  @moduledoc """
  Pipe-friendly S3 operations with clean error handling.

  Provides a fluent, composable API for S3 operations.

  ## Examples

      # Upload workflow
      "User's Photo (1).jpg"
      |> S3.prepare(context, prefix: "uploads")
      |> S3.generate_presigned_upload_url(expires_in: 300)

      # Download workflow
      "uploads/photo.jpg"
      |> S3.generate_presigned_download_url(context, expires_in: 3600)

      # Batch uploads
      ["photo1.jpg", "photo2.jpg", "document.pdf"]
      |> S3.prepare_batch(context, prefix: "uploads")
      |> S3.generate_presigned_upload_urls(expires_in: 300)

      # Batch downloads
      ["uploads/file1.pdf", "uploads/file2.jpg"]
      |> S3.generate_presigned_download_urls(context, expires_in: 3600)
  """

  alias Events.Services.Aws.{Context, S3}
  alias Events.Services.Aws.S3.FileNameNormalizer

  @type prepared_file :: %{
          original: String.t(),
          normalized: String.t(),
          key: String.t(),
          context: Context.t(),
          metadata: map(),
          prepared_at: DateTime.t()
        }

  @type presigned_result :: %{
          url: String.t(),
          key: String.t(),
          original: String.t(),
          expires_at: DateTime.t(),
          method: :get | :put,
          generated_at: DateTime.t()
        }

  @type error_result :: %{
          error: atom() | {atom(), term()},
          original: String.t() | nil,
          message: String.t()
        }

  @doc """
  Prepares a file for upload with normalization.

  ## Options

  - `:prefix` - Path prefix (e.g., "uploads/users/123")
  - `:add_timestamp` - Add timestamp to filename
  - `:add_uuid` - Add UUID to filename
  - `:separator` - Character to replace spaces (default: "-")
  - `:preserve_case` - Keep original case
  - `:metadata` - Custom metadata map

  ## Examples

      "My Photo.jpg"
      |> S3.prepare(context, prefix: "uploads")
      |> S3.generate_presigned_upload_url()
  """
  @spec prepare(String.t(), Context.t(), keyword()) ::
          {:ok, prepared_file()} | {:error, error_result()}
  def prepare(filename, %Context{} = context, opts \\ []) do
    with :ok <- validate_filename(filename),
         :ok <- validate_context(context) do
      normalized = FileNameNormalizer.normalize(filename, opts)
      key = normalized
      metadata = Keyword.get(opts, :metadata, %{})
      now = DateTime.utc_now()

      prepared = %{
        original: filename,
        normalized: Path.basename(normalized),
        key: key,
        context: context,
        metadata: Map.merge(metadata, %{"original_filename" => filename}),
        prepared_at: now
      }

      {:ok, prepared}
    else
      {:error, reason} ->
        {:error, build_error(reason, filename)}
    end
  rescue
    error -> {:error, build_error({:exception, error}, filename)}
  end

  @doc """
  Prepares multiple files for upload.

  ## Examples

      ["photo1.jpg", "photo2.jpg"]
      |> S3.prepare_batch(context, prefix: "uploads")
      |> S3.generate_presigned_upload_urls()
  """
  @spec prepare_batch([String.t()], Context.t(), keyword()) ::
          {:ok, [prepared_file()]} | {:error, [error_result()]}
  def prepare_batch(filenames, %Context{} = context, opts \\ []) when is_list(filenames) do
    results = Enum.map(filenames, &prepare(&1, context, opts))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] ->
        files = Enum.map(results, fn {:ok, file} -> file end)
        {:ok, files}

      _errors ->
        error_list = Enum.map(errors, fn {:error, err} -> err end)
        {:error, error_list}
    end
  end

  @doc """
  Generates presigned upload URL from prepared file.

  ## Options

  - `:expires_in` - Expiration in seconds (default: 3600)

  ## Examples

      {:ok, prepared} = S3.prepare("photo.jpg", context)
      {:ok, result} = S3.generate_presigned_upload_url(prepared, expires_in: 300)

      # Or pipe it
      "photo.jpg"
      |> S3.prepare(context)
      |> S3.generate_presigned_upload_url(expires_in: 300)
  """
  @spec generate_presigned_upload_url(
          {:ok, prepared_file()} | prepared_file(),
          keyword()
        ) :: {:ok, presigned_result()} | {:error, error_result()}
  def generate_presigned_upload_url({:ok, prepared}, opts),
    do: generate_presigned_upload_url(prepared, opts)

  def generate_presigned_upload_url({:error, _} = error, _opts), do: error

  def generate_presigned_upload_url(%{context: context, key: key} = prepared, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    now = DateTime.utc_now()

    case S3.presigned_url(context, :put, key, expires_in: expires_in) do
      {:ok, url} ->
        result = %{
          url: url,
          key: key,
          original: prepared.original,
          expires_at: DateTime.add(now, expires_in, :second),
          method: :put,
          generated_at: now
        }

        {:ok, result}

      {:error, reason} ->
        {:error, build_error(reason, prepared.original)}
    end
  rescue
    error -> {:error, build_error({:exception, error}, prepared.original)}
  end

  @doc """
  Generates presigned upload URLs for multiple files.

  ## Examples

      ["photo1.jpg", "photo2.jpg"]
      |> S3.prepare_batch(context, prefix: "uploads")
      |> S3.generate_presigned_upload_urls(expires_in: 300)
  """
  @spec generate_presigned_upload_urls(
          {:ok, [prepared_file()]} | [prepared_file()],
          keyword()
        ) :: {:ok, [presigned_result()]} | {:error, [error_result()]}
  def generate_presigned_upload_urls({:ok, prepared_files}, opts),
    do: generate_presigned_upload_urls(prepared_files, opts)

  def generate_presigned_upload_urls({:error, _} = error, _opts), do: error

  def generate_presigned_upload_urls(prepared_files, opts) when is_list(prepared_files) do
    results = Enum.map(prepared_files, &generate_presigned_upload_url(&1, opts))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] ->
        urls = Enum.map(results, fn {:ok, result} -> result end)
        {:ok, urls}

      _errors ->
        error_list = Enum.map(errors, fn {:error, err} -> err end)
        {:error, error_list}
    end
  end

  @doc """
  Generates presigned download URL from S3 key or HTTP path.

  Handles:
  - S3 keys: "uploads/file.pdf"
  - S3 URLs: "s3://bucket/file.pdf"
  - HTTPS URLs: "https://bucket.s3.amazonaws.com/file.pdf"

  ## Examples

      "uploads/photo.jpg"
      |> S3.generate_presigned_download_url(context, expires_in: 3600)

      "s3://my-bucket/file.pdf"
      |> S3.generate_presigned_download_url(context)

      "https://my-bucket.s3.amazonaws.com/file.pdf"
      |> S3.generate_presigned_download_url(context)
  """
  @spec generate_presigned_download_url(String.t(), Context.t(), keyword()) ::
          {:ok, presigned_result()} | {:error, error_result()}
  def generate_presigned_download_url(path_or_url, %Context{} = context, opts \\ []) do
    with {:ok, key} <- extract_key(path_or_url, context),
         :ok <- validate_context(context) do
      expires_in = Keyword.get(opts, :expires_in, 3600)
      now = DateTime.utc_now()

      case S3.presigned_url(context, :get, key, expires_in: expires_in) do
        {:ok, url} ->
          result = %{
            url: url,
            key: key,
            original: path_or_url,
            expires_at: DateTime.add(now, expires_in, :second),
            method: :get,
            generated_at: now
          }

          {:ok, result}

        {:error, reason} ->
          {:error, build_error(reason, path_or_url)}
      end
    else
      {:error, reason} ->
        {:error, build_error(reason, path_or_url)}
    end
  rescue
    error -> {:error, build_error({:exception, error}, path_or_url)}
  end

  @doc """
  Generates presigned download URLs for multiple files.

  ## Examples

      ["uploads/file1.pdf", "uploads/file2.jpg"]
      |> S3.generate_presigned_download_urls(context, expires_in: 3600)
  """
  @spec generate_presigned_download_urls([String.t()], Context.t(), keyword()) ::
          {:ok, [presigned_result()]} | {:error, [error_result()]}
  def generate_presigned_download_urls(paths, %Context{} = context, opts \\ [])
      when is_list(paths) do
    results = Enum.map(paths, &generate_presigned_download_url(&1, context, opts))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] ->
        urls = Enum.map(results, fn {:ok, result} -> result end)
        {:ok, urls}

      _errors ->
        error_list = Enum.map(errors, fn {:error, err} -> err end)
        {:error, error_list}
    end
  end

  ## Private Functions

  defp validate_filename(""), do: {:error, :empty_filename}
  defp validate_filename(nil), do: {:error, :nil_filename}
  defp validate_filename(filename) when is_binary(filename), do: :ok
  defp validate_filename(_), do: {:error, :invalid_filename_type}

  defp validate_context(%Context{} = context) do
    case Context.validate(context) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp extract_key("s3://" <> rest, _context) do
    # Handle s3://bucket/key - extract key regardless of bucket
    case String.split(rest, "/", parts: 2) do
      [_bucket, key] -> {:ok, key}
      _ -> {:error, :invalid_s3_url}
    end
  end

  defp extract_key("https://" <> rest, context) do
    # Handle https://bucket.s3.region.amazonaws.com/key
    # or https://s3.region.amazonaws.com/bucket/key
    bucket = context.bucket

    cond do
      String.starts_with?(rest, "#{bucket}.s3.") ->
        [_host | path_parts] = String.split(rest, "/")
        key = Enum.join(path_parts, "/")
        {:ok, key}

      String.contains?(rest, "/#{bucket}/") ->
        # Extract everything after /bucket/
        parts = String.split(rest, "/")

        case Enum.find_index(parts, &(&1 == bucket)) do
          nil ->
            {:error, :bucket_not_found_in_url}

          idx ->
            key = parts |> Enum.drop(idx + 1) |> Enum.join("/")
            {:ok, key}
        end

      true ->
        # Try to extract anything after the first /
        case String.split(rest, "/", parts: 2) do
          [_host, key] -> {:ok, key}
          _ -> {:error, :invalid_https_url}
        end
    end
  end

  defp extract_key("http://" <> _rest, _context) do
    # For local development (MinIO, LocalStack)
    # Extract key from path
    {:error, :http_urls_not_yet_supported}
  end

  defp extract_key(key, _context) when is_binary(key) do
    # Already a key
    {:ok, key}
  end

  defp extract_key(_, _context), do: {:error, :invalid_path_type}

  defp build_error(reason, original) do
    %{
      error: reason,
      original: original,
      message: format_error_message(reason)
    }
  end

  defp format_error_message(:empty_filename), do: "Filename cannot be empty"
  defp format_error_message(:nil_filename), do: "Filename cannot be nil"
  defp format_error_message(:invalid_filename_type), do: "Filename must be a string"
  defp format_error_message(:missing_access_key_id), do: "AWS access key ID is missing"

  defp format_error_message(:missing_secret_access_key),
    do: "AWS secret access key is missing"

  defp format_error_message(:missing_region), do: "AWS region is missing"
  defp format_error_message(:invalid_s3_url), do: "Invalid S3 URL format"
  defp format_error_message(:invalid_https_url), do: "Invalid HTTPS URL format"
  defp format_error_message(:http_urls_not_yet_supported), do: "HTTP URLs not yet supported"
  defp format_error_message(:invalid_path_type), do: "Path must be a string"
  defp format_error_message({:s3_error, status, _}), do: "S3 error: HTTP #{status}"
  defp format_error_message({:presign_error, _}), do: "Failed to generate presigned URL"
  defp format_error_message({:exception, error}), do: "Exception: #{Exception.message(error)}"
  defp format_error_message(:not_found), do: "File not found in S3"
  defp format_error_message(reason), do: "Error: #{inspect(reason)}"
end
