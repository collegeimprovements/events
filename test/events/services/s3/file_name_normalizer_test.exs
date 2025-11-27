defmodule Events.Services.S3.FileNameNormalizerTest do
  use ExUnit.Case, async: true

  alias Events.Services.S3.FileNameNormalizer

  describe "normalize/2" do
    test "normalizes basic filename" do
      assert FileNameNormalizer.normalize("file.txt") == "file.txt"
    end

    test "converts to lowercase" do
      assert FileNameNormalizer.normalize("MyFile.PDF") == "myfile.pdf"
    end

    test "replaces spaces with hyphens" do
      assert FileNameNormalizer.normalize("my file.txt") == "my-file.txt"
    end

    test "removes special characters" do
      assert FileNameNormalizer.normalize("user's file (copy).txt") == "users-file-copy.txt"
    end

    test "handles multiple spaces" do
      assert FileNameNormalizer.normalize("file   name.txt") == "file-name.txt"
    end

    test "preserves file extension" do
      assert FileNameNormalizer.normalize("document.pdf") == "document.pdf"
      assert FileNameNormalizer.normalize("image.jpg") == "image.jpg"
    end

    test "handles files without extension" do
      assert FileNameNormalizer.normalize("README") == "readme"
    end

    test "adds prefix when provided" do
      result = FileNameNormalizer.normalize("file.txt", prefix: "uploads")
      assert result == "uploads/file.txt"
    end

    test "adds prefix with trailing slash" do
      result = FileNameNormalizer.normalize("file.txt", prefix: "uploads/2024/")
      assert result == "uploads/2024/file.txt"
    end

    test "uses custom separator" do
      result = FileNameNormalizer.normalize("my file.txt", separator: "_")
      assert result == "my_file.txt"
    end

    test "preserves case when requested" do
      result = FileNameNormalizer.normalize("MyFile.PDF", preserve_case: true)
      assert result == "MyFile.PDF"
    end

    test "adds timestamp to filename" do
      result = FileNameNormalizer.normalize("file.txt", add_timestamp: true)
      # Should have pattern: file-YYYYMMDD-HHMMSS.txt
      assert result =~ ~r/file-\d{8}-\d{6}\.txt/
    end

    test "adds UUID to filename" do
      result = FileNameNormalizer.normalize("file.txt", add_uuid: true)
      # Should have pattern: file-uuid.txt
      assert result =~ ~r/file-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.txt/
    end

    test "truncates long filenames" do
      long_name = String.duplicate("a", 300) <> ".txt"
      result = FileNameNormalizer.normalize(long_name, max_length: 50)
      assert byte_size(result) <= 50
      assert String.ends_with?(result, ".txt")
    end

    test "handles complex real-world filename" do
      result = FileNameNormalizer.normalize("User's Photo (Final Version) [2024].jpg")
      assert result == "users-photo-final-version-2024.jpg"
    end
  end

  describe "unique_filename/2" do
    test "generates UUID-based filename" do
      result = FileNameNormalizer.unique_filename("photo.jpg")
      assert result =~ ~r/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.jpg/
    end

    test "preserves extension" do
      result = FileNameNormalizer.unique_filename("document.pdf")
      assert String.ends_with?(result, ".pdf")
    end

    test "adds prefix when provided" do
      result = FileNameNormalizer.unique_filename("photo.jpg", prefix: "uploads")
      assert result =~ ~r/uploads\/[a-f0-9-]+\.jpg/
    end

    test "generates different UUIDs each time" do
      result1 = FileNameNormalizer.unique_filename("file.txt")
      result2 = FileNameNormalizer.unique_filename("file.txt")
      assert result1 != result2
    end
  end

  describe "timestamped_filename/2" do
    test "adds timestamp to filename" do
      result = FileNameNormalizer.timestamped_filename("photo.jpg")
      assert result =~ ~r/photo-\d{8}-\d{6}\.jpg/
    end

    test "works with prefix" do
      result = FileNameNormalizer.timestamped_filename("photo.jpg", prefix: "uploads")
      assert result =~ ~r/uploads\/photo-\d{8}-\d{6}\.jpg/
    end
  end

  describe "sanitize/1" do
    test "removes all unsafe characters" do
      assert FileNameNormalizer.sanitize("user's file (copy).txt") == "users-file-copy.txt"
    end

    test "converts to lowercase" do
      assert FileNameNormalizer.sanitize("MyFile.PDF") == "myfile.pdf"
    end

    test "handles unicode characters" do
      assert FileNameNormalizer.sanitize("Fichier Français.pdf") =~ "fichier"
    end
  end
end
