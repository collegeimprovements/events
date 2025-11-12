defmodule Events.Services.Aws.S3.PipelineTest do
  use ExUnit.Case, async: true

  alias Events.Services.Aws.{Context, S3}

  setup do
    context =
      Context.new(
        access_key_id: "test_key",
        secret_access_key: "test_secret",
        region: "us-east-1",
        bucket: "test-bucket"
      )

    {:ok, context: context}
  end

  describe "prepare/3" do
    test "prepares file with normalization", %{context: context} do
      {:ok, prepared} = S3.prepare("My Photo.jpg", context)

      assert prepared.original == "My Photo.jpg"
      assert prepared.normalized == "my-photo.jpg"
      assert prepared.key == "my-photo.jpg"
      assert prepared.context == context
    end

    test "prepares file with prefix", %{context: context} do
      {:ok, prepared} = S3.prepare("photo.jpg", context, prefix: "uploads")

      assert prepared.key == "uploads/photo.jpg"
    end

    test "prepares file with timestamp", %{context: context} do
      {:ok, prepared} = S3.prepare("file.txt", context, add_timestamp: true)

      assert prepared.key =~ ~r/file-\d{8}-\d{6}\.txt/
    end

    test "returns error for empty filename", %{context: context} do
      {:error, error} = S3.prepare("", context)

      assert error.error == :empty_filename
      assert error.message == "Filename cannot be empty"
    end

    test "returns error for nil filename", %{context: context} do
      {:error, error} = S3.prepare(nil, context)

      assert error.error == :nil_filename
    end
  end

  describe "prepare_batch/3" do
    test "prepares multiple files", %{context: context} do
      {:ok, prepared} = S3.prepare_batch(["file1.txt", "file2.pdf"], context)

      assert length(prepared) == 2
      assert Enum.at(prepared, 0).original == "file1.txt"
      assert Enum.at(prepared, 1).original == "file2.pdf"
    end

    test "returns errors for invalid files", %{context: context} do
      {:error, errors} = S3.prepare_batch(["valid.txt", "", nil], context)

      assert length(errors) == 2
    end
  end

  describe "pipe workflow - prepare only" do
    test "single file upload workflow - prepare step", %{context: context} do
      {:ok, prepared} =
        "User's Photo (1).jpg"
        |> S3.prepare(context, prefix: "uploads")

      assert prepared.key == "uploads/users-photo-1.jpg"
      assert prepared.original == "User's Photo (1).jpg"
    end

    test "batch upload workflow - prepare step", %{context: context} do
      {:ok, prepared} =
        ["photo1.jpg", "photo2.jpg"]
        |> S3.prepare_batch(context, prefix: "uploads")

      assert length(prepared) == 2
      assert Enum.at(prepared, 0).key == "uploads/photo1.jpg"
      assert Enum.at(prepared, 1).key == "uploads/photo2.jpg"
    end
  end

  describe "error handling" do
    test "handles prepare error in pipeline", %{context: context} do
      result =
        ""
        |> S3.prepare(context)
        |> S3.generate_presigned_upload_url()

      assert {:error, %{error: :empty_filename}} = result
    end

    test "handles batch errors gracefully", %{context: context} do
      result =
        ["valid.txt", "", "also-valid.pdf"]
        |> S3.prepare_batch(context)
        |> S3.generate_presigned_upload_urls()

      assert {:error, errors} = result
      assert length(errors) >= 1
    end
  end
end
