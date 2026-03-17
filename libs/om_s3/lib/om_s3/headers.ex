defmodule OmS3.Headers do
  @moduledoc """
  Upload header building for S3 operations.

  Constructs HTTP headers for S3 PUT requests including content type,
  custom metadata, ACL, and storage class. Emits runtime warnings when
  AWS-only features (ACL, storage class) are used with non-AWS endpoints.
  """

  require Logger

  alias OmS3.Config
  alias OmS3.ContentType

  @doc """
  Builds upload headers for an S3 PUT request.

  ## Options

  - `:content_type` - MIME type (auto-detected from key if not provided)
  - `:metadata` - Custom metadata map (keys become `x-amz-meta-*` headers)
  - `:acl` - Access control list (e.g., `"public-read"`)
  - `:storage_class` - Storage class (e.g., `"GLACIER"`)

  ## Examples

      OmS3.Headers.build_upload_headers("photo.jpg", [], config)
      #=> %{"content-type" => "image/jpeg"}

      OmS3.Headers.build_upload_headers("file.txt", [acl: "public-read"], config)
      #=> %{"content-type" => "text/plain", "x-amz-acl" => "public-read"}
  """
  @spec build_upload_headers(String.t(), keyword(), Config.t()) :: map()
  def build_upload_headers(key, opts, config) do
    content_type = Keyword.get(opts, :content_type) || ContentType.detect(key)

    %{"content-type" => content_type}
    |> maybe_add_metadata(opts[:metadata])
    |> maybe_add_acl(opts[:acl], config)
    |> maybe_add_storage_class(opts[:storage_class], config)
  end

  defp maybe_add_metadata(headers, nil), do: headers
  defp maybe_add_metadata(headers, metadata) when map_size(metadata) == 0, do: headers

  defp maybe_add_metadata(headers, metadata) do
    Enum.reduce(metadata, headers, fn {k, v}, acc ->
      Map.put(acc, "x-amz-meta-#{k}", to_string(v))
    end)
  end

  defp maybe_add_acl(headers, nil, _config), do: headers

  defp maybe_add_acl(headers, acl, config) do
    unless Config.aws_endpoint?(config) do
      Logger.warning("[OmS3] ACL header '#{acl}' may be ignored by non-AWS S3 providers")
    end

    Map.put(headers, "x-amz-acl", acl)
  end

  defp maybe_add_storage_class(headers, nil, _config), do: headers

  defp maybe_add_storage_class(headers, class, config) do
    unless Config.aws_endpoint?(config) do
      Logger.warning(
        "[OmS3] Storage class '#{class}' may be ignored by non-AWS S3 providers"
      )
    end

    Map.put(headers, "x-amz-storage-class", class)
  end
end
