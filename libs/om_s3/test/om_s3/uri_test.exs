defmodule OmS3.URITest do
  use ExUnit.Case, async: true

  alias OmS3.URI, as: S3URI

  describe "parse/1" do
    test "parses bucket and key" do
      assert {:ok, "my-bucket", "path/to/file.txt"} =
               S3URI.parse("s3://my-bucket/path/to/file.txt")
    end

    test "parses bucket with empty key" do
      assert {:ok, "my-bucket", ""} = S3URI.parse("s3://my-bucket")
    end

    test "parses bucket with just key" do
      assert {:ok, "bucket", "file.txt"} = S3URI.parse("s3://bucket/file.txt")
    end

    test "parses bucket with trailing slash prefix" do
      assert {:ok, "bucket", "prefix/"} = S3URI.parse("s3://bucket/prefix/")
    end

    test "returns :error for non-s3 URIs" do
      assert :error = S3URI.parse("https://example.com")
      assert :error = S3URI.parse("file:///path/to/file")
      assert :error = S3URI.parse("/local/path")
    end

    test "returns :error for empty bucket" do
      assert :error = S3URI.parse("s3:///key")
      assert :error = S3URI.parse("s3://")
    end
  end

  describe "parse!/1" do
    test "returns {bucket, key} tuple for valid URI" do
      assert {"bucket", "file.txt"} = S3URI.parse!("s3://bucket/file.txt")
    end

    test "returns empty key for bucket-only URI" do
      assert {"bucket", ""} = S3URI.parse!("s3://bucket")
    end

    test "raises ArgumentError for invalid URI" do
      assert_raise ArgumentError, ~r/Invalid S3 URI/, fn ->
        S3URI.parse!("https://example.com")
      end
    end
  end

  describe "valid?/1" do
    test "returns true for valid S3 URIs" do
      assert S3URI.valid?("s3://bucket/key")
      assert S3URI.valid?("s3://bucket")
      assert S3URI.valid?("s3://my-bucket/path/to/file.txt")
    end

    test "returns false for invalid URIs" do
      refute S3URI.valid?("https://example.com")
      refute S3URI.valid?("/local/path")
      refute S3URI.valid?("s3://")
    end
  end

  describe "build/2" do
    test "builds URI from bucket and key" do
      assert "s3://my-bucket/path/file.txt" = S3URI.build("my-bucket", "path/file.txt")
    end

    test "builds URI with empty key" do
      assert "s3://my-bucket" = S3URI.build("my-bucket", "")
    end

    test "builds URI with prefix" do
      assert "s3://bucket/prefix/" = S3URI.build("bucket", "prefix/")
    end
  end

  describe "bucket/1" do
    test "extracts bucket from URI" do
      assert {:ok, "my-bucket"} = S3URI.bucket("s3://my-bucket/file.txt")
    end

    test "returns :error for invalid URI" do
      assert :error = S3URI.bucket("invalid")
    end
  end

  describe "key/1" do
    test "extracts key from URI" do
      assert {:ok, "path/file.txt"} = S3URI.key("s3://bucket/path/file.txt")
    end

    test "returns empty string for bucket-only URI" do
      assert {:ok, ""} = S3URI.key("s3://bucket")
    end

    test "returns :error for invalid URI" do
      assert :error = S3URI.key("invalid")
    end
  end

  describe "join/2" do
    test "joins base URI with path" do
      assert "s3://bucket/uploads/photo.jpg" = S3URI.join("s3://bucket/uploads/", "photo.jpg")
    end

    test "handles base without trailing slash" do
      assert "s3://bucket/uploads/photo.jpg" = S3URI.join("s3://bucket/uploads", "photo.jpg")
    end

    test "handles path with leading slash" do
      assert "s3://bucket/uploads/photo.jpg" = S3URI.join("s3://bucket/uploads/", "/photo.jpg")
    end

    test "handles empty base key" do
      assert "s3://bucket/file.txt" = S3URI.join("s3://bucket", "file.txt")
    end

    test "handles nested paths" do
      assert "s3://bucket/a/b/c.txt" = S3URI.join("s3://bucket/a/", "b/c.txt")
    end
  end

  describe "parent/1" do
    test "returns parent directory" do
      assert "s3://bucket/uploads/" = S3URI.parent("s3://bucket/uploads/photo.jpg")
    end

    test "returns bucket for root-level file" do
      assert "s3://bucket" = S3URI.parent("s3://bucket/file.txt")
    end

    test "handles nested paths" do
      assert "s3://bucket/a/b/" = S3URI.parent("s3://bucket/a/b/c.txt")
    end
  end

  describe "filename/1" do
    test "extracts filename from URI" do
      assert "photo.jpg" = S3URI.filename("s3://bucket/uploads/photo.jpg")
    end

    test "handles root-level file" do
      assert "file.txt" = S3URI.filename("s3://bucket/file.txt")
    end
  end

  describe "extname/1" do
    test "extracts extension from URI" do
      assert ".jpg" = S3URI.extname("s3://bucket/photo.jpg")
    end

    test "returns empty for no extension" do
      assert "" = S3URI.extname("s3://bucket/no-extension")
    end
  end
end
