defmodule EventsWeb.Plugs.RateLimiterTest do
  @moduledoc """
  Tests for EventsWeb.Plugs.RateLimiter.

  Uses Mimic to mock Hammer rate limiting to test the plug behavior
  without requiring a real Redis backend.
  """

  use EventsWeb.ConnCase, async: true

  alias EventsWeb.Plugs.RateLimiter

  setup do
    Mimic.copy(Hammer)
    :ok
  end

  describe "init/1" do
    test "returns default options when none provided" do
      opts = RateLimiter.init([])

      assert opts.max_requests == 60
      assert opts.interval_ms == 60_000
      assert opts.id_prefix == "rl"
      assert is_nil(opts.identifier)
    end

    test "accepts custom max_requests" do
      opts = RateLimiter.init(max_requests: 100)

      assert opts.max_requests == 100
    end

    test "accepts custom interval_ms" do
      opts = RateLimiter.init(interval_ms: 30_000)

      assert opts.interval_ms == 30_000
    end

    test "accepts custom id_prefix" do
      opts = RateLimiter.init(id_prefix: "api_v2")

      assert opts.id_prefix == "api_v2"
    end

    test "accepts custom identifier function" do
      custom_identifier = fn conn -> conn.assigns[:user_id] || "anonymous" end
      opts = RateLimiter.init(identifier: custom_identifier)

      assert opts.identifier == custom_identifier
    end
  end

  describe "call/2 - allowing requests" do
    test "allows request when under rate limit", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:allow, 1}
      end)

      opts = RateLimiter.init([])
      result_conn = RateLimiter.call(conn, opts)

      refute result_conn.halted
      assert result_conn.status == nil
    end

    test "allows multiple requests until limit reached", %{conn: conn} do
      # Simulate incrementing count
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:allow, 5}
      end)
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:allow, 10}
      end)

      opts = RateLimiter.init([])

      conn1 = RateLimiter.call(conn, opts)
      conn2 = RateLimiter.call(build_conn(), opts)

      refute conn1.halted
      refute conn2.halted
    end
  end

  describe "call/2 - denying requests" do
    test "denies request when rate limit exceeded", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:deny, 60}
      end)

      opts = RateLimiter.init([])
      result_conn = RateLimiter.call(conn, opts)

      assert result_conn.halted
      assert result_conn.status == 429
    end

    test "includes rate limit headers when denied", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:deny, 60}
      end)

      opts = RateLimiter.init(max_requests: 100, interval_ms: 60_000)
      result_conn = RateLimiter.call(conn, opts)

      assert get_resp_header(result_conn, "x-ratelimit-limit") == ["100"]
      assert get_resp_header(result_conn, "x-ratelimit-remaining") == ["0"]
      assert get_resp_header(result_conn, "x-ratelimit-reset") == ["60"]
      assert get_resp_header(result_conn, "retry-after") == ["60"]
    end

    test "returns JSON error response when denied", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:deny, 60}
      end)

      opts = RateLimiter.init([])
      result_conn = RateLimiter.call(conn, opts)

      body = JSON.decode!(result_conn.resp_body)

      assert body["error"] == "Too many requests"
      assert body["message"] =~ "Rate limit exceeded"
      assert body["retry_after"] == 60
    end

    test "calculates retry_after based on interval_ms", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:deny, 100}
      end)

      opts = RateLimiter.init(interval_ms: 120_000)
      result_conn = RateLimiter.call(conn, opts)

      assert get_resp_header(result_conn, "retry-after") == ["120"]

      body = JSON.decode!(result_conn.resp_body)
      assert body["retry_after"] == 120
    end
  end

  describe "call/2 - error handling" do
    test "allows request on Hammer error", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, _max ->
        {:error, :redis_connection_failed}
      end)

      opts = RateLimiter.init([])
      result_conn = RateLimiter.call(conn, opts)

      # Should fail open - allow the request
      refute result_conn.halted
    end
  end

  describe "call/2 - bucket ID generation" do
    test "uses default IP-based identifier", %{conn: conn} do
      conn = %{conn | remote_ip: {192, 168, 1, 100}}

      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        assert bucket_id == "rl:192.168.1.100"
        {:allow, 1}
      end)

      opts = RateLimiter.init([])
      RateLimiter.call(conn, opts)
    end

    test "uses custom identifier function", %{conn: conn} do
      conn = Plug.Conn.assign(conn, :user_id, "user_123")

      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        assert bucket_id == "api:user_123"
        {:allow, 1}
      end)

      opts =
        RateLimiter.init(
          id_prefix: "api",
          identifier: fn c -> c.assigns[:user_id] end
        )

      RateLimiter.call(conn, opts)
    end

    test "uses X-Forwarded-For header when present", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-forwarded-for", "10.0.0.1")

      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        assert bucket_id == "rl:10.0.0.1"
        {:allow, 1}
      end)

      opts = RateLimiter.init([])
      RateLimiter.call(conn, opts)
    end

    test "uses full X-Forwarded-For header value (including proxy chain)", %{conn: conn} do
      # Note: The current implementation uses the entire header value
      # A more robust implementation would parse and use only the first IP
      conn =
        conn
        |> put_req_header("x-forwarded-for", "10.0.0.1, 192.168.1.1")

      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        # Current behavior: uses full header value
        assert bucket_id == "rl:10.0.0.1, 192.168.1.1"
        {:allow, 1}
      end)

      opts = RateLimiter.init([])
      RateLimiter.call(conn, opts)
    end

    test "uses id_prefix in bucket ID", %{conn: conn} do
      conn = %{conn | remote_ip: {127, 0, 0, 1}}

      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        assert bucket_id =~ "custom_prefix:"
        {:allow, 1}
      end)

      opts = RateLimiter.init(id_prefix: "custom_prefix")
      RateLimiter.call(conn, opts)
    end
  end

  describe "call/2 - rate limit parameters" do
    test "passes correct interval_ms to Hammer", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, interval, _max ->
        assert interval == 30_000
        {:allow, 1}
      end)

      opts = RateLimiter.init(interval_ms: 30_000)
      RateLimiter.call(conn, opts)
    end

    test "passes correct max_requests to Hammer", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn _bucket_id, _interval, max ->
        assert max == 200
        {:allow, 1}
      end)

      opts = RateLimiter.init(max_requests: 200)
      RateLimiter.call(conn, opts)
    end
  end

  describe "integration scenarios" do
    test "rate limits by API endpoint", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        assert bucket_id =~ "api_users"
        {:allow, 1}
      end)

      opts =
        RateLimiter.init(
          id_prefix: "api_users",
          max_requests: 10,
          interval_ms: 1_000
        )

      RateLimiter.call(conn, opts)
    end

    test "different users have separate rate limits", %{conn: conn} do
      Hammer
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        send(self(), {:bucket_id, bucket_id})
        {:allow, 1}
      end)
      |> expect(:check_rate, fn bucket_id, _interval, _max ->
        send(self(), {:bucket_id, bucket_id})
        {:allow, 1}
      end)

      opts =
        RateLimiter.init(identifier: fn c -> c.assigns[:user_id] end)

      conn1 = Plug.Conn.assign(conn, :user_id, "user_1")
      conn2 = Plug.Conn.assign(build_conn(), :user_id, "user_2")

      RateLimiter.call(conn1, opts)
      RateLimiter.call(conn2, opts)

      assert_receive {:bucket_id, "rl:user_1"}
      assert_receive {:bucket_id, "rl:user_2"}
    end
  end
end
