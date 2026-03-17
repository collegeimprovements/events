defmodule OmS3.BatchResult do
  @moduledoc """
  Utilities for analyzing and aggregating batch operation results.

  Provides structured analysis of batch operation outcomes, making it easy
  to understand what succeeded, what failed, and why.

  ## Examples

      results = OmS3.put_all(files, config, to: "s3://bucket/")

      # Get summary
      summary = OmS3.BatchResult.summarize(results)
      #=> %OmS3.BatchResult{
      #=>   total: 100,
      #=>   succeeded: 95,
      #=>   failed: 5,
      #=>   success_rate: 0.95,
      #=>   successes: [...],
      #=>   failures: [%{uri: "s3://...", reason: :timeout}, ...]
      #=> }

      # Check if all succeeded
      OmS3.BatchResult.all_succeeded?(results)
      #=> false

      # Get just failures
      OmS3.BatchResult.failures(results)
      #=> [%{uri: "s3://...", reason: :timeout}, ...]

      # Retry failures
      OmS3.BatchResult.retry_failures(results, fn uri, reason ->
        OmS3.put(uri, get_content(uri), config)
      end)
  """

  @type result_item ::
          {:ok, String.t()}
          | {:ok, String.t(), binary()}
          | {:ok, String.t(), String.t()}
          | {:error, String.t(), term()}

  @type failure :: %{
          uri: String.t(),
          reason: term(),
          error_type: atom() | nil
        }

  @type t :: %__MODULE__{
          total: non_neg_integer(),
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          success_rate: float(),
          successes: [String.t()],
          failures: [failure()],
          by_error_type: %{atom() => [failure()]}
        }

  defstruct [
    :total,
    :succeeded,
    :failed,
    :success_rate,
    successes: [],
    failures: [],
    by_error_type: %{}
  ]

  @doc """
  Creates a comprehensive summary of batch operation results.

  Analyzes the results list and provides counts, success rate,
  and categorized failures.

  ## Examples

      results = OmS3.get_all(["s3://bucket/*.txt"], config)
      summary = OmS3.BatchResult.summarize(results)

      IO.puts("Success rate: \#{summary.success_rate * 100}%")
      IO.puts("Failed: \#{summary.failed} items")

      for failure <- summary.failures do
        IO.puts("  - \#{failure.uri}: \#{inspect(failure.reason)}")
      end
  """
  @spec summarize([result_item()]) :: t()
  def summarize(results) when is_list(results) do
    {successes, failures} = partition_results(results)

    total = length(results)
    succeeded = length(successes)
    failed = length(failures)
    success_rate = if total > 0, do: succeeded / total, else: 1.0

    by_error_type = group_by_error_type(failures)

    %__MODULE__{
      total: total,
      succeeded: succeeded,
      failed: failed,
      success_rate: Float.round(success_rate, 4),
      successes: successes,
      failures: failures,
      by_error_type: by_error_type
    }
  end

  @doc """
  Checks if all operations in a batch succeeded.

  ## Examples

      results = OmS3.put_all(files, config, to: "s3://bucket/")

      if OmS3.BatchResult.all_succeeded?(results) do
        IO.puts("All uploads complete!")
      else
        IO.puts("Some uploads failed")
      end
  """
  @spec all_succeeded?([result_item()]) :: boolean()
  def all_succeeded?(results) when is_list(results) do
    Enum.all?(results, &match?({:ok, _}, &1) or match?({:ok, _, _}, &1))
  end

  @doc """
  Checks if any operations in a batch failed.

  ## Examples

      if OmS3.BatchResult.any_failed?(results) do
        handle_failures(OmS3.BatchResult.failures(results))
      end
  """
  @spec any_failed?([result_item()]) :: boolean()
  def any_failed?(results) when is_list(results) do
    Enum.any?(results, &match?({:error, _, _}, &1))
  end

  @doc """
  Extracts just the successful URIs from results.

  ## Examples

      successes = OmS3.BatchResult.successes(results)
      #=> ["s3://bucket/a.txt", "s3://bucket/b.txt"]
  """
  @spec successes([result_item()]) :: [String.t()]
  def successes(results) when is_list(results) do
    results
    |> Enum.filter(&match?({:ok, _}, &1) or match?({:ok, _, _}, &1))
    |> Enum.map(fn
      {:ok, uri} -> uri
      {:ok, uri, _} -> uri
    end)
  end

  @doc """
  Extracts just the failures from results as structured maps.

  ## Examples

      failures = OmS3.BatchResult.failures(results)
      #=> [%{uri: "s3://bucket/c.txt", reason: :timeout, error_type: :request_timeout}]
  """
  @spec failures([result_item()]) :: [failure()]
  def failures(results) when is_list(results) do
    results
    |> Enum.filter(&match?({:error, _, _}, &1))
    |> Enum.map(fn {:error, uri, reason} ->
      %{
        uri: uri,
        reason: reason,
        error_type: classify_error(reason)
      }
    end)
  end

  @doc """
  Groups failures by error type.

  Useful for understanding patterns in failures.

  ## Examples

      by_type = OmS3.BatchResult.failures_by_type(results)
      #=> %{
      #=>   timeout: [%{uri: "s3://...", reason: :timeout}],
      #=>   not_found: [%{uri: "s3://...", reason: :not_found}]
      #=> }
  """
  @spec failures_by_type([result_item()]) :: %{atom() => [failure()]}
  def failures_by_type(results) when is_list(results) do
    results
    |> failures()
    |> group_by_error_type()
  end

  @doc """
  Returns a list of URIs that failed (for retry purposes).

  ## Examples

      failed_uris = OmS3.BatchResult.failed_uris(results)
      #=> ["s3://bucket/c.txt", "s3://bucket/d.txt"]
  """
  @spec failed_uris([result_item()]) :: [String.t()]
  def failed_uris(results) when is_list(results) do
    results
    |> failures()
    |> Enum.map(& &1.uri)
  end

  @doc """
  Filters results to only recoverable failures (transient errors).

  Returns failures that are worth retrying (timeouts, rate limits, etc.).

  ## Examples

      recoverable = OmS3.BatchResult.recoverable_failures(results)
      retry_uris = Enum.map(recoverable, & &1.uri)
  """
  @spec recoverable_failures([result_item()]) :: [failure()]
  def recoverable_failures(results) when is_list(results) do
    results
    |> failures()
    |> Enum.filter(&recoverable?/1)
  end

  @doc """
  Filters results to permanent failures (not worth retrying).

  Returns failures that won't succeed on retry (not found, access denied, etc.).

  ## Examples

      permanent = OmS3.BatchResult.permanent_failures(results)
      log_permanent_errors(permanent)
  """
  @spec permanent_failures([result_item()]) :: [failure()]
  def permanent_failures(results) when is_list(results) do
    results
    |> failures()
    |> Enum.reject(&recoverable?/1)
  end

  @doc """
  Retries failed operations using a provided retry function.

  The retry function receives the URI and original error reason,
  and should return the same result tuple format.

  ## Options

  - `:only_recoverable` - Only retry transient errors (default: true)
  - `:max_attempts` - Max retry attempts per item (default: 3)
  - `:delay` - Delay between retries in ms (default: 100)

  ## Examples

      # Retry with custom function
      new_results = OmS3.BatchResult.retry_failures(results, fn uri, _reason ->
        content = get_content_for(uri)
        OmS3.put(uri, content, config)
      end)

      # Only retry recoverable errors
      new_results = OmS3.BatchResult.retry_failures(results, retry_fn, only_recoverable: true)
  """
  @spec retry_failures([result_item()], (String.t(), term() -> result_item()), keyword()) ::
          [result_item()]
  def retry_failures(results, retry_fn, opts \\ []) when is_function(retry_fn, 2) do
    only_recoverable = Keyword.get(opts, :only_recoverable, true)
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    delay = Keyword.get(opts, :delay, 100)

    to_retry =
      if only_recoverable do
        recoverable_failures(results)
      else
        failures(results)
      end

    retry_results =
      to_retry
      |> Enum.map(fn failure ->
        do_retry(failure.uri, failure.reason, retry_fn, max_attempts, delay)
      end)

    # Merge: keep successes from original, replace retried failures with new results
    retried_uris = MapSet.new(to_retry, & &1.uri)

    original_kept =
      Enum.reject(results, fn
        {:error, uri, _} -> MapSet.member?(retried_uris, uri)
        _ -> false
      end)

    original_kept ++ retry_results
  end

  @doc """
  Formats a summary as a human-readable string.

  ## Examples

      summary = OmS3.BatchResult.summarize(results)
      IO.puts(OmS3.BatchResult.format(summary))
      #=> "Batch operation: 95/100 succeeded (95.0%), 5 failed"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = summary) do
    percentage = Float.round(summary.success_rate * 100, 1)

    base = "Batch operation: #{summary.succeeded}/#{summary.total} succeeded (#{percentage}%)"

    if summary.failed > 0 do
      error_breakdown =
        summary.by_error_type
        |> Enum.map(fn {type, failures} -> "#{type}: #{length(failures)}" end)
        |> Enum.join(", ")

      "#{base}, #{summary.failed} failed [#{error_breakdown}]"
    else
      base
    end
  end

  @doc """
  Raises an error if any operations failed.

  Useful for strict batch operations that should fail entirely on any error.

  ## Examples

      results
      |> OmS3.BatchResult.raise_on_failure!()
      |> then(fn _ -> IO.puts("All operations succeeded!") end)
  """
  @spec raise_on_failure!([result_item()]) :: [result_item()]
  def raise_on_failure!(results) do
    if any_failed?(results) do
      summary = summarize(results)
      raise "Batch operation failed: #{format(summary)}"
    else
      results
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp partition_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, uri}, {succ, fail} -> {[uri | succ], fail}
      {:ok, uri, _}, {succ, fail} -> {[uri | succ], fail}
      {:error, uri, reason}, {succ, fail} -> {succ, [%{uri: uri, reason: reason, error_type: classify_error(reason)} | fail]}
    end)
    |> then(fn {succ, fail} -> {Enum.reverse(succ), Enum.reverse(fail)} end)
  end

  defp group_by_error_type(failures) do
    Enum.group_by(failures, & &1.error_type)
  end

  defp classify_error(:not_found), do: :not_found
  defp classify_error(:timeout), do: :timeout
  defp classify_error(:access_denied), do: :access_denied
  defp classify_error({:s3_error, 404, _}), do: :not_found
  defp classify_error({:s3_error, 403, _}), do: :access_denied
  defp classify_error({:s3_error, 408, _}), do: :timeout
  defp classify_error({:s3_error, 429, _}), do: :rate_limited
  defp classify_error({:s3_error, 500, _}), do: :internal_error
  defp classify_error({:s3_error, 503, _}), do: :service_unavailable
  defp classify_error({:s3_error, status, _}) when status >= 400 and status < 500, do: :client_error
  defp classify_error({:s3_error, status, _}) when status >= 500, do: :server_error
  defp classify_error(%{__exception__: true}), do: :exception
  defp classify_error(_), do: :unknown

  defp recoverable?(failure) do
    failure.error_type in [:timeout, :rate_limited, :service_unavailable, :internal_error, :server_error]
  end

  defp do_retry(uri, reason, retry_fn, attempts_left, delay) when attempts_left > 0 do
    case retry_fn.(uri, reason) do
      {:ok, _} = success -> success
      {:ok, _, _} = success -> success
      {:error, _, new_reason} when attempts_left > 1 ->
        Process.sleep(delay)
        do_retry(uri, new_reason, retry_fn, attempts_left - 1, delay * 2)
      error -> error
    end
  end

  defp do_retry(uri, reason, _retry_fn, 0, _delay) do
    {:error, uri, reason}
  end
end
