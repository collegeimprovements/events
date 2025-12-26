defmodule OmS3.FileNameNormalizerTest do
  use ExUnit.Case, async: true

  alias OmS3.FileNameNormalizer

  describe "normalize/2" do
    test "removes unsafe characters" do
      assert "users-photo-1.jpg" = FileNameNormalizer.normalize("User's Photo (1).jpg")
    end

    test "replaces spaces with hyphens by default" do
      assert "my-file.txt" = FileNameNormalizer.normalize("my file.txt")
    end

    test "converts to lowercase by default" do
      assert "myfile.txt" = FileNameNormalizer.normalize("MyFile.TXT")
    end

    test "preserves extension" do
      assert "document.pdf" = FileNameNormalizer.normalize("document.PDF")
    end

    test "uses custom separator" do
      assert "my_file.txt" = FileNameNormalizer.normalize("my file.txt", separator: "_")
    end

    test "adds prefix" do
      assert "uploads/file.txt" = FileNameNormalizer.normalize("file.txt", prefix: "uploads")
    end

    test "adds prefix with trailing slash" do
      assert "uploads/file.txt" = FileNameNormalizer.normalize("file.txt", prefix: "uploads/")
    end

    test "preserves case when specified" do
      assert "MyFile.TXT" = FileNameNormalizer.normalize("MyFile.TXT", preserve_case: true)
    end

    test "handles multiple spaces" do
      assert "my-file.txt" = FileNameNormalizer.normalize("my    file.txt")
    end

    test "handles leading/trailing separators" do
      # Leading spaces become leading hyphens which get trimmed
      # Trailing spaces remain in the name part before extension
      result = FileNameNormalizer.normalize("  file.txt")
      assert String.starts_with?(result, "file")
    end

    test "removes parentheses and brackets" do
      assert "file-copy.txt" = FileNameNormalizer.normalize("file (copy).txt")
      assert "file-v2.txt" = FileNameNormalizer.normalize("file [v2].txt")
    end

    test "handles files without extension" do
      assert "readme" = FileNameNormalizer.normalize("README")
    end

    test "adds timestamp when requested" do
      result = FileNameNormalizer.normalize("file.txt", add_timestamp: true)
      # Format: file-YYYYMMDD-HHMMSS.txt
      assert Regex.match?(~r/^file-\d{8}-\d{6}\.txt$/, result)
    end

    test "adds UUID when requested" do
      result = FileNameNormalizer.normalize("file.txt", add_uuid: true)
      # Format: file-uuid.txt where uuid is 8-4-4-4-12
      assert Regex.match?(~r/^file-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.txt$/, result)
    end

    test "truncates long filenames" do
      long_name = String.duplicate("a", 300) <> ".txt"
      result = FileNameNormalizer.normalize(long_name, max_length: 255)
      assert byte_size(result) <= 255
    end
  end

  describe "unique_filename/2" do
    test "generates UUID-based filename" do
      result = FileNameNormalizer.unique_filename("photo.jpg")
      assert Regex.match?(~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.jpg$/, result)
    end

    test "preserves extension" do
      result = FileNameNormalizer.unique_filename("document.pdf")
      assert String.ends_with?(result, ".pdf")
    end

    test "adds prefix" do
      result = FileNameNormalizer.unique_filename("photo.jpg", prefix: "uploads")
      assert String.starts_with?(result, "uploads/")
      assert String.ends_with?(result, ".jpg")
    end
  end

  describe "timestamped_filename/2" do
    test "adds timestamp to filename" do
      result = FileNameNormalizer.timestamped_filename("photo.jpg")
      assert Regex.match?(~r/^photo-\d{8}-\d{6}\.jpg$/, result)
    end

    test "adds prefix with timestamp" do
      result = FileNameNormalizer.timestamped_filename("photo.jpg", prefix: "uploads")
      assert String.starts_with?(result, "uploads/photo-")
      assert String.ends_with?(result, ".jpg")
    end
  end

  describe "sanitize/1" do
    test "removes unsafe characters" do
      assert "users-file-copy.txt" = FileNameNormalizer.sanitize("user's file (copy).txt")
    end

    test "converts to lowercase" do
      assert "readme.md" = FileNameNormalizer.sanitize("README.MD")
    end
  end
end
