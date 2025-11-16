defmodule Events.Services.Aws.S3.Examples do
  @moduledoc """
  Comprehensive examples for using the S3 service.

  This module demonstrates all the different ways to interact with S3,
  including listing files, generating presigned URLs, and batch operations.
  """

  alias Events.Services.Aws.{Context, S3}

  @doc """
  Creates an S3 context for examples.

  ## Examples

      iex> context = S3.Examples.create_context()
      %Context{bucket: "my-bucket", region: "us-east-1", ...}
  """
  def create_context do
    Context.new(
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION", "us-east-1"),
      bucket: System.get_env("S3_BUCKET")
    )
  end

  ## Listing Files Examples

  @doc """
  Example 1: List all files in bucket.

  ## Example

      {:ok, %{objects: objects, continuation_token: token}} =
        S3.Examples.list_all_files()

      # Returns all objects (up to max_keys limit)
      # objects = [
      #   %{
      #     key: "uploads/photo.jpg",
      #     size: 524288,
      #     last_modified: ~U[2024-01-15 10:30:00Z],
      #     etag: "abc123...",
      #     storage_class: "STANDARD"
      #   },
      #   ...
      # ]
  """
  def list_all_files do
    context = create_context()

    context
    |> S3.list_objects()
    |> case do
      {:ok, result} ->
        IO.puts("Found #{length(result.objects)} objects")
        {:ok, result}

      {:error, reason} ->
        IO.puts("Error listing files: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 2: List files with prefix filter.

  Filters to only show files in a specific "folder".

  ## Example

      {:ok, %{objects: objects}} =
        S3.Examples.list_files_by_prefix("uploads/2024/")

      # Only returns files matching the prefix
      # objects = [
      #   %{key: "uploads/2024/january/photo1.jpg", ...},
      #   %{key: "uploads/2024/january/photo2.jpg", ...}
      # ]
  """
  def list_files_by_prefix(prefix) do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix)
    |> case do
      {:ok, result} ->
        IO.puts("Found #{length(result.objects)} objects with prefix: #{prefix}")
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 3: List files with pagination.

  Useful for large buckets. Limits results and allows continuation.

  ## Example

      # First page
      {:ok, %{objects: page1, continuation_token: token}} =
        S3.Examples.list_files_paginated(limit: 100)

      # Next page
      {:ok, %{objects: page2, continuation_token: token2}} =
        S3.Examples.list_files_paginated(
          limit: 100,
          continuation_token: token
        )
  """
  def list_files_paginated(opts \\ []) do
    context = create_context()
    limit = Keyword.get(opts, :limit, 100)
    continuation_token = Keyword.get(opts, :continuation_token)

    list_opts = [
      max_keys: limit,
      continuation_token: continuation_token
    ]

    context
    |> S3.list_objects(list_opts)
    |> case do
      {:ok, %{objects: objects, continuation_token: next_token}} ->
        IO.puts("Retrieved page with #{length(objects)} objects")

        case next_token do
          nil -> IO.puts("This is the last page")
          token -> IO.puts("More pages available. Use token: #{token}")
        end

        {:ok, %{objects: objects, continuation_token: next_token}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 4: List all files across all pages (recursive).

  Automatically handles pagination to retrieve all files.

  ## Example

      {:ok, all_objects} = S3.Examples.list_all_files_recursive()
      IO.puts("Total files in bucket: \#{length(all_objects)}")
  """
  def list_all_files_recursive(prefix \\ "", accumulated \\ []) do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix, max_keys: 1000)
    |> case do
      {:ok, %{objects: objects, continuation_token: nil}} ->
        # Last page
        all_objects = accumulated ++ objects
        {:ok, all_objects}

      {:ok, %{objects: objects, continuation_token: token}} ->
        # More pages available
        new_accumulated = accumulated ++ objects

        context
        |> S3.list_objects(prefix: prefix, max_keys: 1000, continuation_token: token)
        |> handle_next_page(prefix, new_accumulated)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_next_page({:ok, %{objects: objects, continuation_token: nil}}, _prefix, accumulated) do
    {:ok, accumulated ++ objects}
  end

  defp handle_next_page({:ok, %{objects: objects, continuation_token: _token}}, prefix, accumulated) do
    list_all_files_recursive(prefix, accumulated ++ objects)
  end

  defp handle_next_page({:error, reason}, _prefix, _accumulated), do: {:error, reason}

  @doc """
  Example 5: Using the simpler list_files function with prefix.

  ## Example

      {:ok, %{objects: objects}} =
        S3.Examples.list_files_simple("uploads/images/")

      # Returns files in the uploads/images/ folder
  """
  def list_files_simple(prefix) do
    context = create_context()

    context
    |> S3.list_files(prefix)
    |> case do
      {:ok, result} ->
        IO.puts("Found #{length(result.objects)} files")
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 6: Filter and process files by extension.

  Lists files and filters to specific file types.

  ## Example

      {:ok, pdf_files} = S3.Examples.list_files_by_extension("uploads/", ".pdf")

      # Returns only PDF files
      # [
      #   %{key: "uploads/report1.pdf", ...},
      #   %{key: "uploads/contract.pdf", ...}
      # ]
  """
  def list_files_by_extension(prefix, extension) do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix)
    |> case do
      {:ok, %{objects: objects}} ->
        filtered =
          objects
          |> Enum.filter(fn obj -> String.ends_with?(obj.key, extension) end)

        IO.puts("Found #{length(filtered)} #{extension} files")
        {:ok, filtered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 7: List files sorted by size.

  Retrieves files and sorts them by size (largest first).

  ## Example

      {:ok, sorted_files} = S3.Examples.list_files_by_size("uploads/")

      # Returns files sorted by size (descending)
      # [
      #   %{key: "large-video.mp4", size: 52428800, ...},
      #   %{key: "medium-doc.pdf", size: 1048576, ...},
      #   %{key: "small-image.jpg", size: 204800, ...}
      # ]
  """
  def list_files_by_size(prefix \\ "") do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix)
    |> case do
      {:ok, %{objects: objects}} ->
        sorted = Enum.sort_by(objects, & &1.size, :desc)
        {:ok, sorted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 8: List recently modified files.

  Gets files modified in the last N days.

  ## Example

      {:ok, recent_files} = S3.Examples.list_recent_files(days: 7)

      # Returns files modified in the last 7 days
  """
  def list_recent_files(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    prefix = Keyword.get(opts, :prefix, "")
    cutoff_date = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    context = create_context()

    context
    |> S3.list_objects(prefix: prefix)
    |> case do
      {:ok, %{objects: objects}} ->
        recent =
          objects
          |> Enum.filter(fn obj ->
            DateTime.compare(obj.last_modified, cutoff_date) == :gt
          end)
          |> Enum.sort_by(& &1.last_modified, {:desc, DateTime})

        IO.puts("Found #{length(recent)} files modified in the last #{days} days")
        {:ok, recent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 9: Get total size of files in prefix.

  Calculates total storage used by files matching a prefix.

  ## Example

      {:ok, stats} = S3.Examples.get_folder_stats("uploads/2024/")

      # Returns:
      # %{
      #   total_files: 150,
      #   total_size_bytes: 524288000,
      #   total_size_mb: 500.0,
      #   total_size_gb: 0.49
      # }
  """
  def get_folder_stats(prefix) do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix)
    |> case do
      {:ok, %{objects: objects}} ->
        total_size = Enum.reduce(objects, 0, fn obj, acc -> acc + obj.size end)

        stats = %{
          total_files: length(objects),
          total_size_bytes: total_size,
          total_size_mb: Float.round(total_size / 1_048_576, 2),
          total_size_gb: Float.round(total_size / 1_073_741_824, 2)
        }

        IO.puts("""
        Folder Stats for "#{prefix}":
        - Files: #{stats.total_files}
        - Size: #{stats.total_size_mb} MB (#{stats.total_size_gb} GB)
        """)

        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example 10: Check if a "folder" (prefix) has any files.

  ## Example

      S3.Examples.folder_has_files?("uploads/temp/")
      # => true or false
  """
  def folder_has_files?(prefix) do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix, max_keys: 1)
    |> case do
      {:ok, %{objects: []}} -> false
      {:ok, %{objects: [_ | _]}} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Example 11: List files with pattern matching on results.

  Demonstrates different ways to handle list results.

  ## Example

      S3.Examples.list_and_handle("uploads/")
  """
  def list_and_handle(prefix) do
    context = create_context()

    context
    |> S3.list_objects(prefix: prefix)
    |> case do
      {:ok, %{objects: [], continuation_token: nil}} ->
        IO.puts("No files found in #{prefix}")
        :empty

      {:ok, %{objects: objects, continuation_token: nil}} when length(objects) < 10 ->
        IO.puts("Found a few files (#{length(objects)})")
        {:ok, :few, objects}

      {:ok, %{objects: objects, continuation_token: nil}} ->
        IO.puts("Found many files (#{length(objects)})")
        {:ok, :many, objects}

      {:ok, %{objects: objects, continuation_token: _token}} ->
        IO.puts("Found #{length(objects)} files, but more pages available")
        {:ok, :paginated, objects}

      {:error, :missing_bucket} ->
        IO.puts("Error: Bucket not configured")
        {:error, :configuration_error}

      {:error, reason} ->
        IO.puts("Error listing files: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 12: Pipeline-style file listing and processing.

  Demonstrates clean, functional approach with pipelines.

  ## Example

      S3.Examples.process_files_pipeline("uploads/images/")
  """
  def process_files_pipeline(prefix) do
    create_context()
    |> S3.list_objects(prefix: prefix)
    |> extract_objects()
    |> filter_large_files(min_size: 1_048_576)
    |> sort_by_date()
    |> take_latest(10)
    |> print_file_list()
  end

  defp extract_objects({:ok, %{objects: objects}}), do: {:ok, objects}
  defp extract_objects(error), do: error

  defp filter_large_files({:ok, objects}, opts) do
    min_size = Keyword.get(opts, :min_size, 0)
    filtered = Enum.filter(objects, &(&1.size >= min_size))
    {:ok, filtered}
  end

  defp filter_large_files(error, _opts), do: error

  defp sort_by_date({:ok, objects}) do
    sorted = Enum.sort_by(objects, & &1.last_modified, {:desc, DateTime})
    {:ok, sorted}
  end

  defp sort_by_date(error), do: error

  defp take_latest({:ok, objects}, count) do
    latest = Enum.take(objects, count)
    {:ok, latest}
  end

  defp take_latest(error, _count), do: error

  defp print_file_list({:ok, objects}) do
    IO.puts("\n=== File List ===")

    Enum.each(objects, fn obj ->
      size_mb = Float.round(obj.size / 1_048_576, 2)

      IO.puts("""
      - #{obj.key}
        Size: #{size_mb} MB
        Modified: #{DateTime.to_string(obj.last_modified)}
      """)
    end)

    {:ok, objects}
  end

  defp print_file_list(error), do: error
end
