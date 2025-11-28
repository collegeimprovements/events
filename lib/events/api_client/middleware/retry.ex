defmodule Events.APIClient.Middleware.Retry do
  @moduledoc """
  Retry middleware with exponential backoff and jitter.

  Provides intelligent retry logic for transient failures, including:
  - Exponential backoff with configurable base delay
  - Jitter to prevent thundering herd
  - Retry-After header awareness
  - Configurable retry conditions

  ## Usage as Req Plugin

      Req.new()
      |> Retry.attach()
      |> Req.get("/api/resource")

  ## Options

  - `:max_attempts` - Maximum retry attempts (default: 3)
  - `:base_delay` - Base delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay cap in milliseconds (default: 30000)
  - `:jitter` - Jitter factor 0.0-1.0 (default: 0.25)
  - `:retry_statuses` - HTTP statuses to retry (default: [429, 500, 502, 503, 504])
  - `:retry_on` - Custom retry predicate function

  ## Examples

      # Basic usage
      opts = Retry.options(max_attempts: 5, base_delay: 500)
      Req.request(opts)

      # With custom retry condition
      opts = Retry.options(
        max_attempts: 3,
        retry_on: fn
          {:ok, %{status: 429}} -> true
          {:error, %Mint.TransportError{}} -> true
          _ -> false
        end
      )
  """

  require Logger

  @default_max_attempts 3
  @default_base_delay 1_000
  @default_max_delay 30_000
  @default_jitter 0.25
  @default_retry_statuses [408, 429, 500, 502, 503, 504]

  @type opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          jitter: float(),
          retry_statuses: [pos_integer()],
          retry_on: (term() -> boolean())
        ]

  @doc """
  Creates Req options for retry middleware.

  ## Examples

      Retry.options()
      Retry.options(max_attempts: 5)
      Retry.options(max_attempts: 3, base_delay: 500)
  """
  @spec options(opts()) :: keyword()
  def options(opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    jitter = Keyword.get(opts, :jitter, @default_jitter)
    retry_statuses = Keyword.get(opts, :retry_statuses, @default_retry_statuses)
    custom_retry_on = Keyword.get(opts, :retry_on)

    retry_fn = build_retry_fn(retry_statuses, custom_retry_on)

    [
      retry: retry_fn,
      retry_delay: build_delay_fn(base_delay, max_delay, jitter),
      max_retries: max_attempts - 1
    ]
  end

  @doc """
  Attaches retry middleware to a Req request.

  ## Examples

      Req.new()
      |> Retry.attach()
      |> Req.get("/api/resource")

      Req.new()
      |> Retry.attach(max_attempts: 5)
      |> Req.get("/api/resource")
  """
  @spec attach(Req.Request.t(), opts()) :: Req.Request.t()
  def attach(%Req.Request{} = req, opts \\ []) do
    retry_opts = options(opts)
    Req.merge(req, retry_opts)
  end

  @doc """
  Calculates the delay for a given attempt number.

  Uses exponential backoff with jitter.

  ## Examples

      Retry.calculate_delay(1)  #=> ~1000 (with jitter)
      Retry.calculate_delay(2)  #=> ~2000 (with jitter)
      Retry.calculate_delay(3)  #=> ~4000 (with jitter)
  """
  @spec calculate_delay(pos_integer(), keyword()) :: pos_integer()
  def calculate_delay(attempt, opts \\ []) do
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    jitter = Keyword.get(opts, :jitter, @default_jitter)

    calculate_delay_with_jitter(attempt, base_delay, max_delay, jitter)
  end

  @doc """
  Determines if a response or error should be retried.

  ## Examples

      Retry.should_retry?({:ok, %{status: 429}})  #=> true
      Retry.should_retry?({:ok, %{status: 200}})  #=> false
      Retry.should_retry?({:error, %Mint.TransportError{}})  #=> true
  """
  @spec should_retry?(term(), keyword()) :: boolean()
  def should_retry?(result, opts \\ []) do
    retry_statuses = Keyword.get(opts, :retry_statuses, @default_retry_statuses)
    custom_fn = Keyword.get(opts, :retry_on)

    retry_fn = build_retry_fn(retry_statuses, custom_fn)
    retry_fn.(result)
  end

  @doc """
  Extracts Retry-After delay from response headers.

  Handles both seconds and HTTP-date formats.

  ## Examples

      Retry.extract_retry_after(%{headers: [{"retry-after", "5"}]})
      #=> 5000

      Retry.extract_retry_after(%{headers: []})
      #=> nil
  """
  @spec extract_retry_after(map()) :: pos_integer() | nil
  def extract_retry_after(%{headers: headers}) when is_list(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> parse_retry_after(value)
      nil -> nil
    end
  end

  def extract_retry_after(%{headers: headers}) when is_map(headers) do
    case Map.get(headers, "retry-after") do
      nil -> nil
      value -> parse_retry_after(value)
    end
  end

  def extract_retry_after(_), do: nil

  # ============================================
  # Private Helpers
  # ============================================

  defp build_retry_fn(retry_statuses, nil) do
    fn
      {:ok, %{status: status}} ->
        status in retry_statuses

      {:error, %{__exception__: true} = error} ->
        transient_error?(error)

      _ ->
        false
    end
  end

  defp build_retry_fn(retry_statuses, custom_fn) do
    default_fn = build_retry_fn(retry_statuses, nil)

    fn result ->
      custom_fn.(result) || default_fn.(result)
    end
  end

  defp build_delay_fn(base_delay, max_delay, jitter) do
    fn attempt, response ->
      # Check for Retry-After header first
      case extract_retry_after(response) do
        nil ->
          calculate_delay_with_jitter(attempt, base_delay, max_delay, jitter)

        retry_after_ms ->
          min(retry_after_ms, max_delay)
      end
    end
  end

  defp calculate_delay_with_jitter(attempt, base_delay, max_delay, jitter) do
    # Exponential: base * 2^(attempt-1)
    exponential_delay = base_delay * Integer.pow(2, attempt - 1)

    # Add jitter: delay * (1 + random(-jitter, +jitter))
    jitter_factor = 1 + (:rand.uniform() * 2 - 1) * jitter
    delay_with_jitter = round(exponential_delay * jitter_factor)

    # Cap at max delay
    min(delay_with_jitter, max_delay)
  end

  defp transient_error?(%Mint.TransportError{}), do: true
  defp transient_error?(%Mint.HTTPError{reason: :timeout}), do: true
  defp transient_error?(%{reason: :timeout}), do: true
  defp transient_error?(%{reason: :econnrefused}), do: true
  defp transient_error?(%{reason: :econnreset}), do: true
  defp transient_error?(%{reason: :closed}), do: true
  defp transient_error?(_), do: false

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} ->
        # Convert seconds to milliseconds
        seconds * 1000

      _ ->
        # Try parsing as HTTP-date
        parse_http_date(value)
    end
  end

  defp parse_retry_after(value) when is_integer(value) do
    value * 1000
  end

  defp parse_http_date(date_string) do
    # Basic HTTP-date parsing (RFC 7231)
    # This is simplified - full implementation would handle all formats
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        diff = DateTime.diff(datetime, DateTime.utc_now(), :millisecond)
        max(0, diff)

      _ ->
        nil
    end
  end
end
