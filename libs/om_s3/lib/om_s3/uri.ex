defmodule OmS3.URI do
  @moduledoc """
  S3 URI parsing utilities.

  Parses `s3://bucket/key` URIs into bucket and key components.

  ## Examples

      {:ok, "my-bucket", "path/to/file.txt"} = OmS3.URI.parse("s3://my-bucket/path/to/file.txt")
      {:ok, "my-bucket", "prefix/"} = OmS3.URI.parse("s3://my-bucket/prefix/")
      {:ok, "my-bucket", ""} = OmS3.URI.parse("s3://my-bucket")

      {"my-bucket", "file.txt"} = OmS3.URI.parse!("s3://my-bucket/file.txt")
  """

  @doc """
  Parses an S3 URI into bucket and key.

  Returns `{:ok, bucket, key}` on success, `:error` on failure.

  ## Examples

      {:ok, "my-bucket", "file.txt"} = OmS3.URI.parse("s3://my-bucket/file.txt")
      {:ok, "my-bucket", ""} = OmS3.URI.parse("s3://my-bucket")
      :error = OmS3.URI.parse("not-an-s3-uri")
  """
  @spec parse(String.t()) :: {:ok, String.t(), String.t()} | :error
  def parse("s3://" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [bucket, key] when bucket != "" -> {:ok, bucket, key}
      [bucket] when bucket != "" -> {:ok, bucket, ""}
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc """
  Parses an S3 URI, raising on invalid input.

  Returns `{bucket, key}` tuple.

  ## Examples

      {"my-bucket", "file.txt"} = OmS3.URI.parse!("s3://my-bucket/file.txt")

  ## Raises

      ArgumentError if the URI is invalid
  """
  @spec parse!(String.t()) :: {String.t(), String.t()}
  def parse!(uri) do
    case parse(uri) do
      {:ok, bucket, key} -> {bucket, key}
      :error -> raise ArgumentError, "Invalid S3 URI: #{inspect(uri)}"
    end
  end

  @doc """
  Checks if a string is a valid S3 URI.

  ## Examples

      true = OmS3.URI.valid?("s3://bucket/key")
      false = OmS3.URI.valid?("https://example.com")
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(uri), do: match?({:ok, _, _}, parse(uri))

  @doc """
  Builds an S3 URI from bucket and key.

  ## Examples

      "s3://my-bucket/path/file.txt" = OmS3.URI.build("my-bucket", "path/file.txt")
      "s3://my-bucket" = OmS3.URI.build("my-bucket", "")
  """
  @spec build(String.t(), String.t()) :: String.t()
  def build(bucket, ""), do: "s3://#{bucket}"
  def build(bucket, key), do: "s3://#{bucket}/#{key}"

  @doc """
  Extracts the bucket from an S3 URI.

  ## Examples

      {:ok, "my-bucket"} = OmS3.URI.bucket("s3://my-bucket/file.txt")
      :error = OmS3.URI.bucket("invalid")
  """
  @spec bucket(String.t()) :: {:ok, String.t()} | :error
  def bucket(uri) do
    case parse(uri) do
      {:ok, bucket, _key} -> {:ok, bucket}
      :error -> :error
    end
  end

  @doc """
  Extracts the key from an S3 URI.

  ## Examples

      {:ok, "path/file.txt"} = OmS3.URI.key("s3://my-bucket/path/file.txt")
      {:ok, ""} = OmS3.URI.key("s3://my-bucket")
      :error = OmS3.URI.key("invalid")
  """
  @spec key(String.t()) :: {:ok, String.t()} | :error
  def key(uri) do
    case parse(uri) do
      {:ok, _bucket, key} -> {:ok, key}
      :error -> :error
    end
  end

  @doc """
  Joins a base S3 URI with additional path segments.

  ## Examples

      "s3://bucket/uploads/photo.jpg" = OmS3.URI.join("s3://bucket/uploads/", "photo.jpg")
      "s3://bucket/a/b/c.txt" = OmS3.URI.join("s3://bucket/a/", "b/c.txt")
  """
  @spec join(String.t(), String.t()) :: String.t()
  def join(base_uri, path) do
    {bucket, base_key} = parse!(base_uri)
    base_key = String.trim_trailing(base_key, "/")
    path = String.trim_leading(path, "/")

    new_key =
      case {base_key, path} do
        {"", p} -> p
        {b, ""} -> b
        {b, p} -> "#{b}/#{p}"
      end

    build(bucket, new_key)
  end

  @doc """
  Returns the parent "directory" of an S3 URI.

  ## Examples

      "s3://bucket/uploads/" = OmS3.URI.parent("s3://bucket/uploads/photo.jpg")
      "s3://bucket" = OmS3.URI.parent("s3://bucket/file.txt")
  """
  @spec parent(String.t()) :: String.t()
  def parent(uri) do
    {bucket, key} = parse!(uri)

    case Path.dirname(key) do
      "." -> build(bucket, "")
      dir -> build(bucket, dir <> "/")
    end
  end

  @doc """
  Returns the filename portion of an S3 URI.

  ## Examples

      "photo.jpg" = OmS3.URI.filename("s3://bucket/uploads/photo.jpg")
      "file.txt" = OmS3.URI.filename("s3://bucket/file.txt")
  """
  @spec filename(String.t()) :: String.t()
  def filename(uri) do
    {_bucket, key} = parse!(uri)
    Path.basename(key)
  end

  @doc """
  Returns the file extension from an S3 URI.

  ## Examples

      ".jpg" = OmS3.URI.extname("s3://bucket/photo.jpg")
      "" = OmS3.URI.extname("s3://bucket/no-extension")
  """
  @spec extname(String.t()) :: String.t()
  def extname(uri) do
    {_bucket, key} = parse!(uri)
    Path.extname(key)
  end
end
