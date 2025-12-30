defmodule Events.Test.NetworkHelpers do
  @moduledoc """
  Helpers for testing code that makes network calls.

  Provides utilities for:
  - Simulating network failures
  - Handling flaky external services
  - Setting up test HTTP servers
  - Retry testing patterns

  ## Usage

      use Events.Test.NetworkHelpers

  Or import specific helpers:

      import Events.Test.NetworkHelpers

  ## Test Server Setup

      setup do
        {:ok, server} = start_test_server()
        %{server: server, base_url: test_server_url(server)}
      end

  ## Simulating Failures

      test "handles network timeout" do
        simulate_network_failure(:timeout) do
          assert {:error, :timeout} = MyClient.fetch_data()
        end
      end
  """

  @doc """
  Starts a test HTTP server with the given options.

  ## Options

  - `:scheme` - `:http` or `:https` (default: `:http`)
  - `:port` - Specific port to use (default: random available port)

  ## Examples

      {:ok, server} = start_test_server()
      {:ok, server} = start_test_server(scheme: :https)
  """
  def start_test_server(opts \\ []) do
    TestServer.start(opts)
  end

  @doc """
  Stops the test server.
  """
  def stop_test_server do
    TestServer.stop()
  end

  @doc """
  Returns the URL for the test server.
  """
  def test_server_url do
    TestServer.url()
  end

  @doc """
  Adds a route to the test server.

  ## Examples

      add_route("/api/users", fn conn ->
        Plug.Conn.send_resp(conn, 200, JSON.encode!(%{users: []}))
      end)

      add_route("/api/users/:id", via: :get, to: fn conn ->
        id = conn.path_params["id"]
        Plug.Conn.send_resp(conn, 200, JSON.encode!(%{id: id}))
      end)
  """
  def add_route(path, opts_or_handler) do
    case opts_or_handler do
      handler when is_function(handler) ->
        TestServer.add(path, to: handler)

      opts when is_list(opts) ->
        TestServer.add(path, opts)
    end
  end

  @doc """
  Adds a route that returns a JSON response.

  ## Examples

      add_json_route("/api/users", %{users: []})
      add_json_route("/api/users", %{users: []}, status: 201)
  """
  def add_json_route(path, body, opts \\ []) do
    status = Keyword.get(opts, :status, 200)
    method = Keyword.get(opts, :via, :get)

    TestServer.add(path,
      via: method,
      to: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(status, JSON.encode!(body))
      end
    )
  end

  @doc """
  Adds a route that simulates a network error.

  ## Error Types

  - `:timeout` - Delays response beyond typical timeout
  - `:connection_refused` - Closes connection immediately
  - `:server_error` - Returns 500 error
  - `:rate_limited` - Returns 429 error
  - `:bad_gateway` - Returns 502 error
  - `:service_unavailable` - Returns 503 error

  ## Examples

      add_error_route("/api/flaky", :timeout)
      add_error_route("/api/flaky", :server_error)
  """
  def add_error_route(path, error_type, opts \\ []) do
    method = Keyword.get(opts, :via, :get)

    handler =
      case error_type do
        :timeout ->
          fn conn ->
            # Sleep longer than typical client timeout
            Process.sleep(30_000)
            Plug.Conn.send_resp(conn, 200, "")
          end

        :connection_refused ->
          fn conn ->
            # Abruptly close connection
            send(conn.owner, {:plug_conn, :sent})
            raise Plug.Conn.WrapperError, conn: conn, kind: :error, reason: :closed
          end

        :server_error ->
          fn conn ->
            Plug.Conn.send_resp(conn, 500, JSON.encode!(%{error: "Internal Server Error"}))
          end

        :rate_limited ->
          fn conn ->
            conn
            |> Plug.Conn.put_resp_header("retry-after", "60")
            |> Plug.Conn.send_resp(429, JSON.encode!(%{error: "Too Many Requests"}))
          end

        :bad_gateway ->
          fn conn ->
            Plug.Conn.send_resp(conn, 502, JSON.encode!(%{error: "Bad Gateway"}))
          end

        :service_unavailable ->
          fn conn ->
            Plug.Conn.send_resp(conn, 503, JSON.encode!(%{error: "Service Unavailable"}))
          end
      end

    TestServer.add(path, via: method, to: handler)
  end

  @doc """
  Adds a route that fails the first N times, then succeeds.

  Useful for testing retry logic.

  ## Examples

      # Fails twice, then returns success
      add_flaky_route("/api/data", 2, success_body: %{data: "ok"})
  """
  def add_flaky_route(path, fail_count, opts \\ []) do
    success_body = Keyword.get(opts, :success_body, %{ok: true})
    error_type = Keyword.get(opts, :error_type, :server_error)
    method = Keyword.get(opts, :via, :get)

    # Use process dictionary to track call count
    counter_key = {:flaky_route_counter, path}

    TestServer.add(path,
      via: method,
      to: fn conn ->
        count = Process.get(counter_key, 0)
        Process.put(counter_key, count + 1)

        if count < fail_count do
          # Return error
          status =
            case error_type do
              :server_error -> 500
              :rate_limited -> 429
              :bad_gateway -> 502
              :service_unavailable -> 503
              _ -> 500
            end

          Plug.Conn.send_resp(
            conn,
            status,
            JSON.encode!(%{error: "Simulated failure #{count + 1}"})
          )
        else
          # Return success
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, JSON.encode!(success_body))
        end
      end
    )
  end

  @doc """
  Simulates a slow response with configurable delay.

  ## Examples

      add_slow_route("/api/slow", delay: 2000)  # 2 second delay
  """
  def add_slow_route(path, opts \\ []) do
    delay = Keyword.get(opts, :delay, 1000)
    body = Keyword.get(opts, :body, %{ok: true})
    method = Keyword.get(opts, :via, :get)

    TestServer.add(path,
      via: method,
      to: fn conn ->
        Process.sleep(delay)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, JSON.encode!(body))
      end
    )
  end

  @doc """
  Checks if network is available, raising to skip the test if not.

  Use for tests that require actual network connectivity.

  ## Examples

      @tag :external
      test "fetches from real API" do
        skip_if_offline()
        # ... test code
      end
  """
  def skip_if_offline(host \\ "google.com", port \\ 443) do
    case :gen_tcp.connect(to_charlist(host), port, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        raise ExUnit.AssertionError, message: "Skipping test: network unavailable (#{host}:#{port})"
    end
  end

  @doc """
  Asserts that a function call completes within a timeout.

  Useful for detecting network timeouts.

  ## Examples

      assert_completes_within 5000 do
        MyClient.fetch_data()
      end
  """
  defmacro assert_completes_within(timeout_ms, do: block) do
    quote do
      task = Task.async(fn -> unquote(block) end)

      case Task.yield(task, unquote(timeout_ms)) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} ->
          result

        nil ->
          raise ExUnit.AssertionError,
            message: "Operation did not complete within #{unquote(timeout_ms)}ms"
      end
    end
  end

  @doc """
  Retries a test block until it succeeds or max attempts reached.

  Useful for dealing with inherently flaky external services in integration tests.

  ## Examples

      with_retries max: 3, delay: 100 do
        result = ExternalAPI.fetch()
        assert result.status == :ok
      end
  """
  defmacro with_retries(opts, do: block) do
    max_attempts = Keyword.get(opts, :max, 3)
    delay = Keyword.get(opts, :delay, 100)

    quote do
      Enum.reduce_while(1..unquote(max_attempts), nil, fn attempt, _acc ->
        try do
          result = unquote(block)
          {:halt, result}
        rescue
          e in [ExUnit.AssertionError, MatchError] ->
            if attempt < unquote(max_attempts) do
              Process.sleep(unquote(delay) * attempt)
              {:cont, nil}
            else
              reraise e, __STACKTRACE__
            end
        end
      end)
    end
  end

  defmacro __using__(_opts) do
    quote do
      import Events.Test.NetworkHelpers
    end
  end
end
