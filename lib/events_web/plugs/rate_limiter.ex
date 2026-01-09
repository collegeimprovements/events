defmodule EventsWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug using Events.Services.RateLimiter (Hammer v7).

  ## Usage

  Add to your router pipeline:

      pipeline :api do
        plug :accepts, ["json"]
        plug EventsWeb.Plugs.RateLimiter
      end

  Or use with custom options:

      pipeline :api do
        plug :accepts, ["json"]
        plug EventsWeb.Plugs.RateLimiter,
          max_requests: 100,
          interval_ms: 60_000,
          id_prefix: "api"
      end

  ## Options

    * `:max_requests` - Maximum number of requests allowed (default: 60)
    * `:interval_ms` - Time window in milliseconds (default: 60_000 - 1 minute)
    * `:id_prefix` - Prefix for the rate limit bucket ID (default: "rl")
    * `:identifier` - Function to extract identifier from conn (default: uses IP address)

  ## Examples

  Rate limit by user ID:

      plug EventsWeb.Plugs.RateLimiter,
        identifier: fn conn ->
          conn.assigns[:current_user_id] || get_ip(conn)
        end
  """

  import Plug.Conn

  alias Events.Services.RateLimiter

  @behaviour Plug

  @default_max_requests 60
  @default_interval_ms 60_000
  @default_id_prefix "rl"

  @impl true
  def init(opts) do
    %{
      max_requests: Keyword.get(opts, :max_requests, @default_max_requests),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      id_prefix: Keyword.get(opts, :id_prefix, @default_id_prefix),
      identifier: Keyword.get(opts, :identifier, nil)
    }
  end

  @impl true
  def call(conn, opts) do
    identifier = get_identifier(conn, opts.identifier)
    bucket_id = "#{opts.id_prefix}:#{identifier}"

    case safe_check(bucket_id, opts.interval_ms, opts.max_requests) do
      {:allow, _count} ->
        conn

      {:deny, retry_after_ms} ->
        retry_after = max(div(retry_after_ms, 1000), 1)

        conn
        |> put_resp_header("x-ratelimit-limit", to_string(opts.max_requests))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("x-ratelimit-reset", to_string(retry_after))
        |> put_resp_header("retry-after", to_string(retry_after))
        |> send_resp(429, rate_limit_message(retry_after))
        |> halt()
    end
  end

  # Wraps rate limiter check with error handling - fail open on any errors
  defp safe_check(bucket_id, interval_ms, max_requests) do
    RateLimiter.check(bucket_id, interval_ms, max_requests)
  rescue
    _ -> {:allow, 0}
  end

  defp get_identifier(conn, nil), do: get_ip(conn)
  defp get_identifier(conn, fun) when is_function(fun, 1), do: fun.(conn)

  # Extracts IP address from the connection
  defp get_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp rate_limit_message(retry_after) do
    JSON.encode!(%{
      error: "Too many requests",
      message: "Rate limit exceeded. Please try again in #{retry_after} seconds.",
      retry_after: retry_after
    })
  end
end
