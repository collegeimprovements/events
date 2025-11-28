defmodule Events.APIClient.ResponseTest do
  use ExUnit.Case, async: true

  alias Events.APIClient.Response

  describe "new/4" do
    test "creates a response with basic data" do
      resp = Response.new(200, %{"id" => "123"}, [])

      assert resp.status == 200
      assert resp.body == %{"id" => "123"}
      assert resp.headers == %{}
    end

    test "normalizes headers to lowercase map" do
      resp = Response.new(200, %{}, [{"Content-Type", "application/json"}, {"X-Request-Id", "abc"}])

      assert resp.headers["content-type"] == "application/json"
      assert resp.headers["x-request-id"] == "abc"
    end

    test "extracts API request ID from headers" do
      resp = Response.new(200, %{}, [{"x-request-id", "req_abc123"}])
      assert resp.api_request_id == "req_abc123"
    end

    test "extracts Stripe request ID" do
      resp = Response.new(200, %{}, [{"x-stripe-request-id", "stripe_123"}])
      assert resp.api_request_id == "stripe_123"
    end

    test "accepts opts" do
      resp = Response.new(200, %{}, [], request_id: "local_123", timing_ms: 150)

      assert resp.request_id == "local_123"
      assert resp.timing_ms == 150
    end

    test "extracts rate limit info" do
      headers = [
        {"x-ratelimit-limit", "100"},
        {"x-ratelimit-remaining", "95"},
        {"x-ratelimit-reset", "1705334400"}
      ]

      resp = Response.new(200, %{}, headers)

      assert resp.rate_limit.limit == 100
      assert resp.rate_limit.remaining == 95
      assert resp.rate_limit.reset == 1_705_334_400
    end
  end

  describe "status predicates" do
    test "success?" do
      assert Response.success?(Response.new(200, %{}, []))
      assert Response.success?(Response.new(201, %{}, []))
      assert Response.success?(Response.new(204, %{}, []))
      refute Response.success?(Response.new(400, %{}, []))
      refute Response.success?(Response.new(500, %{}, []))
    end

    test "client_error?" do
      assert Response.client_error?(Response.new(400, %{}, []))
      assert Response.client_error?(Response.new(404, %{}, []))
      assert Response.client_error?(Response.new(422, %{}, []))
      refute Response.client_error?(Response.new(200, %{}, []))
      refute Response.client_error?(Response.new(500, %{}, []))
    end

    test "server_error?" do
      assert Response.server_error?(Response.new(500, %{}, []))
      assert Response.server_error?(Response.new(502, %{}, []))
      assert Response.server_error?(Response.new(503, %{}, []))
      refute Response.server_error?(Response.new(200, %{}, []))
      refute Response.server_error?(Response.new(400, %{}, []))
    end

    test "redirect?" do
      assert Response.redirect?(Response.new(301, %{}, []))
      assert Response.redirect?(Response.new(302, %{}, []))
      assert Response.redirect?(Response.new(307, %{}, []))
      refute Response.redirect?(Response.new(200, %{}, []))
    end

    test "retryable?" do
      assert Response.retryable?(Response.new(429, %{}, []))
      assert Response.retryable?(Response.new(408, %{}, []))
      assert Response.retryable?(Response.new(500, %{}, []))
      assert Response.retryable?(Response.new(502, %{}, []))
      assert Response.retryable?(Response.new(503, %{}, []))
      refute Response.retryable?(Response.new(200, %{}, []))
      refute Response.retryable?(Response.new(400, %{}, []))
      refute Response.retryable?(Response.new(404, %{}, []))
    end

    test "rate_limited?" do
      assert Response.rate_limited?(Response.new(429, %{}, []))
      refute Response.rate_limited?(Response.new(200, %{}, []))
      refute Response.rate_limited?(Response.new(503, %{}, []))
    end
  end

  describe "get/3" do
    test "gets a value from body by string key" do
      resp = Response.new(200, %{"id" => "123", "email" => "test@example.com"}, [])

      assert Response.get(resp, "id") == "123"
      assert Response.get(resp, "email") == "test@example.com"
    end

    test "gets a value from body by atom key" do
      resp = Response.new(200, %{"id" => "123"}, [])
      assert Response.get(resp, :id) == "123"
    end

    test "returns default for missing key" do
      resp = Response.new(200, %{}, [])

      assert Response.get(resp, "missing") == nil
      assert Response.get(resp, "missing", "default") == "default"
    end

    test "handles nested access" do
      body = %{
        "customer" => %{
          "id" => "cus_123",
          "email" => "test@example.com"
        }
      }

      resp = Response.new(200, body, [])

      assert Response.get(resp, ["customer", "id"]) == "cus_123"
      assert Response.get(resp, ["customer", "email"]) == "test@example.com"
      assert Response.get(resp, ["customer", "missing"]) == nil
    end
  end

  describe "get_header/3" do
    test "gets header case-insensitively" do
      resp = Response.new(200, %{}, [{"Content-Type", "application/json"}])

      assert Response.get_header(resp, "content-type") == "application/json"
      assert Response.get_header(resp, "Content-Type") == "application/json"
    end

    test "returns default for missing header" do
      resp = Response.new(200, %{}, [])

      assert Response.get_header(resp, "x-missing") == nil
      assert Response.get_header(resp, "x-missing", "default") == "default"
    end
  end

  describe "retry_after_ms/1" do
    test "returns nil when no retry-after header" do
      resp = Response.new(429, %{}, [])
      assert Response.retry_after_ms(resp) == nil
    end

    test "parses retry-after in seconds" do
      resp = Response.new(429, %{}, [{"retry-after", "5"}])
      assert Response.retry_after_ms(resp) == 5000
    end
  end

  describe "to_result/1" do
    test "returns {:ok, body} for success" do
      resp = Response.new(200, %{"id" => "123"}, [])
      assert Response.to_result(resp) == {:ok, %{"id" => "123"}}
    end

    test "returns {:error, response} for error" do
      resp = Response.new(404, %{"error" => "not found"}, [])
      assert Response.to_result(resp) == {:error, resp}
    end
  end

  describe "to_full_result/1" do
    test "returns {:ok, response} for success" do
      resp = Response.new(200, %{"id" => "123"}, [])
      assert Response.to_full_result(resp) == {:ok, resp}
    end

    test "returns {:error, response} for error" do
      resp = Response.new(404, %{"error" => "not found"}, [])
      assert Response.to_full_result(resp) == {:error, resp}
    end
  end
end
