defmodule Events.APIClient.RequestTest do
  use ExUnit.Case, async: true

  alias Events.APIClient.Request

  defmodule TestConfig do
    defstruct [:api_key]
  end

  describe "new/1" do
    test "creates a request with config" do
      config = %TestConfig{api_key: "test_key"}
      req = Request.new(config)

      assert %Request{} = req
      assert req.config == config
      assert req.method == :get
      assert req.path == "/"
      assert req.retries == 3
      assert req.timeout == 30_000
    end
  end

  describe "method/2" do
    test "sets HTTP method" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.method(:post)
      assert req.method == :post
    end

    test "accepts all valid methods" do
      config = %TestConfig{api_key: "test"}

      for method <- [:get, :post, :put, :patch, :delete, :head, :options] do
        req = Request.new(config) |> Request.method(method)
        assert req.method == method
      end
    end
  end

  describe "path/2" do
    test "sets the request path" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.path("/v1/customers")
      assert req.path == "/v1/customers"
    end
  end

  describe "append_path/2" do
    test "appends a segment to the path" do
      config = %TestConfig{api_key: "test"}

      req =
        Request.new(config)
        |> Request.path("/v1/customers")
        |> Request.append_path("cus_123")

      assert req.path == "/v1/customers/cus_123"
    end

    test "handles trailing slashes" do
      config = %TestConfig{api_key: "test"}

      req =
        Request.new(config)
        |> Request.path("/v1/customers/")
        |> Request.append_path("charges")

      assert req.path == "/v1/customers/charges"
    end
  end

  describe "query/2" do
    test "sets query parameters as keyword list" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.query(limit: 10, offset: 20)
      assert req.query == [limit: 10, offset: 20]
    end

    test "sets query parameters as map" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.query(%{limit: 10})
      assert req.query == %{limit: 10}
    end
  end

  describe "put_query/3" do
    test "adds a single query parameter" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.put_query(:limit, 10)
      assert req.query == [limit: 10]
    end

    test "adds to existing parameters" do
      config = %TestConfig{api_key: "test"}

      req =
        Request.new(config)
        |> Request.query(offset: 0)
        |> Request.put_query(:limit, 10)

      # Keyword.put prepends, so order is reversed
      assert req.query == [limit: 10, offset: 0]
    end
  end

  describe "headers/2 and header/3" do
    test "sets headers" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.headers([{"content-type", "application/json"}])
      assert req.headers == [{"content-type", "application/json"}]
    end

    test "adds a single header" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.header("x-custom", "value")
      assert {"x-custom", "value"} in req.headers
    end
  end

  describe "body/2" do
    test "sets raw body" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.body("raw content")
      assert req.body == "raw content"
    end
  end

  describe "json/2" do
    test "sets JSON body and content-type header" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.json(%{email: "test@example.com"})

      assert req.body == {:json, %{email: "test@example.com"}}
      assert {"content-type", "application/json"} in req.headers
    end
  end

  describe "form/2" do
    test "sets form body and content-type header" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.form(email: "test@example.com")

      assert req.body == {:form, [email: "test@example.com"]}
      assert {"content-type", "application/x-www-form-urlencoded"} in req.headers
    end
  end

  describe "resilience options" do
    test "sets idempotency key" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.idempotency_key("unique_123")
      assert req.idempotency_key == "unique_123"
    end

    test "sets retries" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.retries(5)
      assert req.retries == 5
    end

    test "sets timeout in milliseconds" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.timeout(60_000)
      assert req.timeout == 60_000
    end

    test "sets timeout with duration tuple" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.timeout({30, :seconds})
      assert req.timeout == 30_000
    end

    test "sets timeout with minutes" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.timeout({2, :minutes})
      assert req.timeout == 120_000
    end

    test "sets circuit breaker" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.circuit_breaker(:stripe_api)
      assert req.circuit_breaker == :stripe_api
    end

    test "sets rate limit key" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.rate_limit_key(:stripe_api)
      assert req.rate_limit_key == :stripe_api
    end
  end

  describe "metadata/2 and metadata/3" do
    test "adds metadata with key-value" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.metadata(:operation, :create_customer)
      assert req.metadata == %{operation: :create_customer}
    end

    test "merges metadata map" do
      config = %TestConfig{api_key: "test"}

      req =
        Request.new(config)
        |> Request.metadata(:user_id, "123")
        |> Request.metadata(%{trace_id: "abc", span_id: "def"})

      assert req.metadata == %{user_id: "123", trace_id: "abc", span_id: "def"}
    end

    test "gets metadata" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.metadata(:operation, :test)

      assert Request.get_metadata(req, :operation) == :test
      assert Request.get_metadata(req, :missing) == nil
      assert Request.get_metadata(req, :missing, :default) == :default
    end
  end

  describe "to_req_options/2" do
    test "converts request to Req options" do
      config = %TestConfig{api_key: "test"}

      req =
        Request.new(config)
        |> Request.method(:post)
        |> Request.path("/v1/customers")
        |> Request.query(limit: 10)
        |> Request.header("x-custom", "value")
        |> Request.timeout(60_000)

      opts = Request.to_req_options(req)

      assert opts[:method] == :post
      assert opts[:url] == "/v1/customers"
      assert opts[:params] == [limit: 10]
      assert {"x-custom", "value"} in opts[:headers]
      assert opts[:receive_timeout] == 60_000
    end

    test "handles JSON body" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.json(%{email: "test@example.com"})
      opts = Request.to_req_options(req)

      assert opts[:json] == %{email: "test@example.com"}
    end

    test "handles form body" do
      config = %TestConfig{api_key: "test"}
      req = Request.new(config) |> Request.form(email: "test@example.com")
      opts = Request.to_req_options(req)

      assert opts[:form] == [email: "test@example.com"]
    end
  end

  describe "chaining" do
    test "supports full pipeline" do
      config = %TestConfig{api_key: "test"}

      req =
        Request.new(config)
        |> Request.method(:post)
        |> Request.path("/v1/customers")
        |> Request.query(expand: ["charges"])
        |> Request.json(%{email: "user@example.com"})
        |> Request.header("x-request-id", "abc123")
        |> Request.idempotency_key("idem_123")
        |> Request.timeout({30, :seconds})
        |> Request.retries(5)
        |> Request.circuit_breaker(:stripe)
        |> Request.metadata(:operation, :create)

      assert req.method == :post
      assert req.path == "/v1/customers"
      assert req.query == [expand: ["charges"]]
      assert req.body == {:json, %{email: "user@example.com"}}
      assert req.idempotency_key == "idem_123"
      assert req.timeout == 30_000
      assert req.retries == 5
      assert req.circuit_breaker == :stripe
      assert req.metadata[:operation] == :create
    end
  end
end
