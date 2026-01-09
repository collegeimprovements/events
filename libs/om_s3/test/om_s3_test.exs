defmodule OmS3Test do
  @moduledoc """
  Tests for OmS3 - Fluent S3 operations API.

  OmS3 provides a chainable, pipeline-friendly interface for S3 operations
  with filename normalization, presigned URLs, and multipart uploads.

  ## Use Cases

  - **File uploads**: Put objects with content type, metadata, ACL
  - **Presigned URLs**: Generate secure, time-limited download/upload links
  - **Filename normalization**: Sanitize user filenames for S3 keys
  - **Multipart uploads**: Handle large files with concurrent chunk uploads

  ## Pattern: Fluent S3 Pipeline

      OmS3.new(access_key_id: "...", secret_access_key: "...")
      |> OmS3.bucket("my-bucket")
      |> OmS3.prefix("uploads/")
      |> OmS3.content_type("image/jpeg")
      |> OmS3.acl("public-read")
      |> OmS3.expires_in({15, :minutes})
      |> OmS3.presign_upload("photo.jpg")

  Supports: put, get, delete, copy, list, presigned URLs, multipart uploads.
  """

  use ExUnit.Case, async: true

  describe "config/1" do
    test "creates config struct" do
      config =
        OmS3.config(
          access_key_id: "AKIATEST",
          secret_access_key: "secret123"
        )

      assert %OmS3.Config{} = config
      assert config.access_key_id == "AKIATEST"
    end
  end

  describe "uri/2" do
    test "builds S3 URI from bucket and key" do
      assert "s3://my-bucket/path/to/file.txt" = OmS3.uri("my-bucket", "path/to/file.txt")
    end

    test "builds S3 URI with empty key" do
      assert "s3://my-bucket" = OmS3.uri("my-bucket", "")
    end

    test "builds S3 URI with prefix" do
      assert "s3://bucket/uploads/" = OmS3.uri("bucket", "uploads/")
    end
  end

  describe "parse_uri/1" do
    test "parses valid S3 URI" do
      assert {:ok, "my-bucket", "path/file.txt"} = OmS3.parse_uri("s3://my-bucket/path/file.txt")
    end

    test "parses bucket-only URI" do
      assert {:ok, "bucket", ""} = OmS3.parse_uri("s3://bucket")
    end

    test "returns :error for invalid URI" do
      assert :error = OmS3.parse_uri("https://example.com")
    end
  end

  describe "normalize_key/2" do
    test "normalizes filename" do
      assert "users-photo-1.jpg" = OmS3.normalize_key("User's Photo (1).jpg")
    end

    test "adds prefix" do
      result = OmS3.normalize_key("file.txt", prefix: "docs")
      assert "docs/file.txt" = result
    end

    test "adds timestamp" do
      result = OmS3.normalize_key("file.txt", timestamp: true)
      assert Regex.match?(~r/^file-\d{8}-\d{6}\.txt$/, result)
    end

    test "adds UUID" do
      result = OmS3.normalize_key("file.txt", uuid: true)
      assert Regex.match?(~r/^file-[a-f0-9-]{36}\.txt$/, result)
    end

    test "uses custom separator" do
      assert "my_file.txt" = OmS3.normalize_key("my file.txt", separator: "_")
    end
  end

  describe "new/1 pipeline builder" do
    test "creates request with config" do
      config = OmS3.config(access_key_id: "test", secret_access_key: "test")
      req = OmS3.new(config)

      assert %OmS3.Request{} = req
      assert req.config == config
    end

    test "creates request from keyword options" do
      req = OmS3.new(access_key_id: "test", secret_access_key: "test")

      assert %OmS3.Request{} = req
      assert req.config.access_key_id == "test"
    end
  end

  describe "pipeline chainable options" do
    setup do
      req = OmS3.new(access_key_id: "test", secret_access_key: "test")
      {:ok, req: req}
    end

    test "bucket/2 sets bucket", %{req: req} do
      result = OmS3.bucket(req, "my-bucket")
      assert result.bucket == "my-bucket"
    end

    test "prefix/2 sets prefix", %{req: req} do
      result = OmS3.prefix(req, "uploads/")
      assert result.prefix == "uploads/"
    end

    test "content_type/2 sets content type", %{req: req} do
      result = OmS3.content_type(req, "image/jpeg")
      assert result.content_type == "image/jpeg"
    end

    test "metadata/2 sets metadata", %{req: req} do
      result = OmS3.metadata(req, %{user_id: "123"})
      assert result.metadata == %{user_id: "123"}
    end

    test "acl/2 sets ACL", %{req: req} do
      result = OmS3.acl(req, "public-read")
      assert result.acl == "public-read"
    end

    test "storage_class/2 sets storage class", %{req: req} do
      result = OmS3.storage_class(req, "GLACIER")
      assert result.storage_class == "GLACIER"
    end

    test "expires_in/2 sets expiration", %{req: req} do
      result = OmS3.expires_in(req, {5, :minutes})
      assert result.expires_in == 300
    end

    test "method/2 sets HTTP method", %{req: req} do
      result = OmS3.method(req, :put)
      assert result.method == :put
    end

    test "concurrency/2 sets concurrency", %{req: req} do
      result = OmS3.concurrency(req, 10)
      assert result.concurrency == 10
    end

    test "timeout/2 sets timeout", %{req: req} do
      result = OmS3.timeout(req, {2, :minutes})
      assert result.timeout == 120_000
    end

    test "chaining multiple options", %{req: req} do
      result =
        req
        |> OmS3.bucket("my-bucket")
        |> OmS3.prefix("uploads/")
        |> OmS3.content_type("image/jpeg")
        |> OmS3.acl("public-read")

      assert result.bucket == "my-bucket"
      assert result.prefix == "uploads/"
      assert result.content_type == "image/jpeg"
      assert result.acl == "public-read"
    end
  end
end
