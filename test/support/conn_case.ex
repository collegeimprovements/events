defmodule EventsWeb.ConnCase do
  @moduledoc """
  Test case for Phoenix controller and integration tests.

  This module provides:
  - Connection setup for HTTP testing
  - Database sandbox for isolation
  - Custom assertions
  - JSON response helpers
  - Authentication helpers

  ## Usage

      defmodule EventsWeb.UserControllerTest do
        use EventsWeb.ConnCase, async: true

        test "GET /api/users", %{conn: conn} do
          conn = get(conn, ~p"/api/users")
          assert json_response(conn, 200)
        end
      end
  """

  use ExUnit.CaseTemplate

  import Plug.Conn
  import ExUnit.Assertions

  using do
    quote do
      # The default endpoint for testing
      @endpoint EventsWeb.Endpoint

      use EventsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EventsWeb.ConnCase

      # Mocking support
      use Mimic

      # Custom assertions
      use Events.Test.Assertions

      # Test data factory
      import Events.Test.Factory
    end
  end

  setup tags do
    Events.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Parses JSON response body.
  """
  def json_body(conn) do
    Jason.decode!(conn.resp_body)
  end

  @doc """
  Asserts successful JSON response with status 200.
  """
  def assert_json_response(conn, status \\ 200) do
    assert conn.status == status
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    json_body(conn)
  end

  @doc """
  Asserts error JSON response.
  """
  def assert_json_error(conn, status) do
    assert conn.status == status
    body = json_body(conn)
    assert Map.has_key?(body, "error") or Map.has_key?(body, "errors")
    body
  end

  @doc """
  Sets JSON content type headers for request.
  """
  def put_json_headers(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  @doc """
  Performs a JSON POST request.

  Must be used from a test that `use EventsWeb.ConnCase`.
  """
  defmacro json_post(conn, path, body) do
    quote do
      unquote(conn)
      |> EventsWeb.ConnCase.put_json_headers()
      |> post(unquote(path), Jason.encode!(unquote(body)))
    end
  end

  @doc """
  Performs a JSON PUT request.

  Must be used from a test that `use EventsWeb.ConnCase`.
  """
  defmacro json_put(conn, path, body) do
    quote do
      unquote(conn)
      |> EventsWeb.ConnCase.put_json_headers()
      |> put(unquote(path), Jason.encode!(unquote(body)))
    end
  end

  @doc """
  Performs a JSON PATCH request.

  Must be used from a test that `use EventsWeb.ConnCase`.
  """
  defmacro json_patch(conn, path, body) do
    quote do
      unquote(conn)
      |> EventsWeb.ConnCase.put_json_headers()
      |> patch(unquote(path), Jason.encode!(unquote(body)))
    end
  end
end
