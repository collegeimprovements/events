defmodule OmS3.BatchResultTest do
  use ExUnit.Case, async: true

  alias OmS3.BatchResult

  @sample_results [
    {:ok, "s3://bucket/a.txt"},
    {:ok, "s3://bucket/b.txt"},
    {:ok, "s3://bucket/c.txt"},
    {:error, "s3://bucket/d.txt", :timeout},
    {:error, "s3://bucket/e.txt", {:s3_error, 404, %{}}},
    {:error, "s3://bucket/f.txt", {:s3_error, 503, %{}}}
  ]

  @all_success [
    {:ok, "s3://bucket/a.txt"},
    {:ok, "s3://bucket/b.txt"}
  ]

  @all_failed [
    {:error, "s3://bucket/a.txt", :timeout},
    {:error, "s3://bucket/b.txt", :not_found}
  ]

  describe "summarize/1" do
    test "calculates correct counts" do
      summary = BatchResult.summarize(@sample_results)

      assert summary.total == 6
      assert summary.succeeded == 3
      assert summary.failed == 3
      assert summary.success_rate == 0.5
    end

    test "returns success URIs" do
      summary = BatchResult.summarize(@sample_results)

      assert Enum.sort(summary.successes) == [
               "s3://bucket/a.txt",
               "s3://bucket/b.txt",
               "s3://bucket/c.txt"
             ]
    end

    test "returns structured failures" do
      summary = BatchResult.summarize(@sample_results)

      assert length(summary.failures) == 3

      timeout_failure = Enum.find(summary.failures, &(&1.uri == "s3://bucket/d.txt"))
      assert timeout_failure.reason == :timeout
      assert timeout_failure.error_type == :timeout
    end

    test "groups failures by error type" do
      summary = BatchResult.summarize(@sample_results)

      assert Map.has_key?(summary.by_error_type, :timeout)
      assert Map.has_key?(summary.by_error_type, :not_found)
      assert Map.has_key?(summary.by_error_type, :service_unavailable)
    end

    test "handles empty results" do
      summary = BatchResult.summarize([])

      assert summary.total == 0
      assert summary.succeeded == 0
      assert summary.failed == 0
      assert summary.success_rate == 1.0
    end

    test "handles all success" do
      summary = BatchResult.summarize(@all_success)

      assert summary.total == 2
      assert summary.succeeded == 2
      assert summary.failed == 0
      assert summary.success_rate == 1.0
    end

    test "handles all failures" do
      summary = BatchResult.summarize(@all_failed)

      assert summary.total == 2
      assert summary.succeeded == 0
      assert summary.failed == 2
      assert summary.success_rate == 0.0
    end
  end

  describe "all_succeeded?/1" do
    test "returns true when all succeeded" do
      assert BatchResult.all_succeeded?(@all_success)
    end

    test "returns false when any failed" do
      refute BatchResult.all_succeeded?(@sample_results)
    end

    test "returns true for empty list" do
      assert BatchResult.all_succeeded?([])
    end
  end

  describe "any_failed?/1" do
    test "returns true when any failed" do
      assert BatchResult.any_failed?(@sample_results)
    end

    test "returns false when all succeeded" do
      refute BatchResult.any_failed?(@all_success)
    end

    test "returns false for empty list" do
      refute BatchResult.any_failed?([])
    end
  end

  describe "successes/1" do
    test "extracts successful URIs" do
      successes = BatchResult.successes(@sample_results)

      assert Enum.sort(successes) == [
               "s3://bucket/a.txt",
               "s3://bucket/b.txt",
               "s3://bucket/c.txt"
             ]
    end

    test "handles results with content" do
      results = [
        {:ok, "s3://bucket/a.txt", "content a"},
        {:ok, "s3://bucket/b.txt", "content b"},
        {:error, "s3://bucket/c.txt", :not_found}
      ]

      assert BatchResult.successes(results) == ["s3://bucket/a.txt", "s3://bucket/b.txt"]
    end
  end

  describe "failures/1" do
    test "extracts failures as structured maps" do
      failures = BatchResult.failures(@sample_results)

      assert length(failures) == 3

      assert Enum.any?(failures, &(&1.uri == "s3://bucket/d.txt"))
      assert Enum.any?(failures, &(&1.error_type == :timeout))
    end
  end

  describe "failed_uris/1" do
    test "extracts just the URIs that failed" do
      uris = BatchResult.failed_uris(@sample_results)

      assert Enum.sort(uris) == [
               "s3://bucket/d.txt",
               "s3://bucket/e.txt",
               "s3://bucket/f.txt"
             ]
    end
  end

  describe "failures_by_type/1" do
    test "groups failures by error type" do
      by_type = BatchResult.failures_by_type(@sample_results)

      assert Map.has_key?(by_type, :timeout)
      assert Map.has_key?(by_type, :not_found)
      assert Map.has_key?(by_type, :service_unavailable)

      assert length(by_type[:timeout]) == 1
    end
  end

  describe "recoverable_failures/1" do
    test "returns only transient failures" do
      recoverable = BatchResult.recoverable_failures(@sample_results)

      error_types = Enum.map(recoverable, & &1.error_type)
      assert :timeout in error_types
      assert :service_unavailable in error_types
      refute :not_found in error_types
    end
  end

  describe "permanent_failures/1" do
    test "returns only permanent failures" do
      permanent = BatchResult.permanent_failures(@sample_results)

      error_types = Enum.map(permanent, & &1.error_type)
      assert :not_found in error_types
      refute :timeout in error_types
      refute :service_unavailable in error_types
    end
  end

  describe "format/1" do
    test "formats summary with failures" do
      summary = BatchResult.summarize(@sample_results)
      formatted = BatchResult.format(summary)

      assert formatted =~ "3/6 succeeded"
      assert formatted =~ "50.0%"
      assert formatted =~ "3 failed"
    end

    test "formats summary without failures" do
      summary = BatchResult.summarize(@all_success)
      formatted = BatchResult.format(summary)

      assert formatted =~ "2/2 succeeded"
      assert formatted =~ "100.0%"
      refute formatted =~ "failed"
    end
  end

  describe "raise_on_failure!/1" do
    test "returns results when all succeeded" do
      assert BatchResult.raise_on_failure!(@all_success) == @all_success
    end

    test "raises when any failed" do
      assert_raise RuntimeError, ~r/Batch operation failed/, fn ->
        BatchResult.raise_on_failure!(@sample_results)
      end
    end
  end

  describe "retry_failures/3" do
    test "retries failed operations with provided function" do
      results = [
        {:ok, "s3://bucket/a.txt"},
        {:error, "s3://bucket/b.txt", :timeout}
      ]

      retry_fn = fn uri, _reason ->
        {:ok, uri}
      end

      new_results = BatchResult.retry_failures(results, retry_fn)

      assert BatchResult.all_succeeded?(new_results)
      assert length(new_results) == 2
    end

    test "respects only_recoverable option" do
      results = [
        {:error, "s3://bucket/a.txt", :timeout},
        {:error, "s3://bucket/b.txt", :not_found}
      ]

      retry_fn = fn uri, _reason ->
        {:ok, uri}
      end

      new_results = BatchResult.retry_failures(results, retry_fn, only_recoverable: true)

      # Only the timeout should have been retried
      successes = BatchResult.successes(new_results)
      assert "s3://bucket/a.txt" in successes
      refute "s3://bucket/b.txt" in successes
    end
  end
end
