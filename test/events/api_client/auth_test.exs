defmodule Events.Api.Client.AuthTest do
  use ExUnit.Case, async: true

  alias Events.Api.Client.Auth
  alias Events.Api.Client.Auth.{APIKey, Basic}
  alias Events.Api.Client.Request

  defmodule TestConfig do
    defstruct [:api_key]
  end

  describe "APIKey" do
    test "new/1 creates bearer auth by default" do
      auth = APIKey.new("sk_test_123")

      assert auth.key == "sk_test_123"
      assert auth.location == {:header, "authorization"}
      assert auth.prefix == nil
    end

    test "new/2 with header option" do
      auth = APIKey.new("sk_test_123", header: "x-api-key")

      assert auth.location == {:header, "x-api-key"}
    end

    test "new/2 with prefix option" do
      auth = APIKey.new("sk_test_123", header: "authorization", prefix: "Bearer")

      assert auth.prefix == "Bearer"
    end

    test "new/2 with query option" do
      auth = APIKey.new("abc123", query: "api_key")

      # Query param name is converted to atom at construction time
      assert auth.location == {:query, :api_key}
    end

    test "bearer/1 creates standard bearer token" do
      auth = APIKey.bearer("eyJ...")

      assert auth.key == "eyJ..."
      assert auth.location == {:header, "authorization"}
      assert auth.prefix == "Bearer"
    end

    test "stripe/1 creates Stripe-style auth" do
      auth = APIKey.stripe("sk_test_123")

      assert auth.key == "sk_test_123"
      assert auth.prefix == "Bearer"
    end

    test "query/2 creates query parameter auth" do
      auth = APIKey.query("abc123", "api_key")

      assert auth.key == "abc123"
      # Query param name is converted to atom at construction time
      assert auth.location == {:query, :api_key}
    end

    test "authenticate adds header without prefix" do
      auth = APIKey.new("sk_test_123", header: "x-api-key")
      req = Request.new(%TestConfig{api_key: "test"})

      authenticated = Auth.authenticate(auth, req)

      assert {"x-api-key", "sk_test_123"} in authenticated.headers
    end

    test "authenticate adds header with prefix" do
      auth = APIKey.bearer("sk_test_123")
      req = Request.new(%TestConfig{api_key: "test"})

      authenticated = Auth.authenticate(auth, req)

      assert {"authorization", "Bearer sk_test_123"} in authenticated.headers
    end

    test "authenticate adds query parameter" do
      auth = APIKey.query("abc123", "api_key")
      req = Request.new(%TestConfig{api_key: "test"})

      authenticated = Auth.authenticate(auth, req)

      assert authenticated.query == [api_key: "abc123"]
    end

    test "valid? always returns true" do
      auth = APIKey.new("sk_test_123")
      assert Auth.valid?(auth) == true
    end

    test "refresh returns auth unchanged" do
      auth = APIKey.new("sk_test_123")
      assert Auth.refresh(auth) == {:ok, auth}
    end
  end

  describe "Basic" do
    test "new/2 creates basic auth" do
      auth = Basic.new("username", "password")

      assert auth.username == "username"
      assert auth.password == "password"
    end

    test "twilio/2 creates Twilio-style auth" do
      auth = Basic.twilio("ACxxx", "auth_token")

      assert auth.username == "ACxxx"
      assert auth.password == "auth_token"
    end

    test "encoded_credentials/1 returns base64 encoded string" do
      auth = Basic.new("user", "pass")
      encoded = Basic.encoded_credentials(auth)

      assert encoded == Base.encode64("user:pass")
    end

    test "authenticate adds authorization header" do
      auth = Basic.new("user", "pass")
      req = Request.new(%TestConfig{api_key: "test"})

      authenticated = Auth.authenticate(auth, req)

      expected = "Basic " <> Base.encode64("user:pass")
      assert {"authorization", ^expected} = List.keyfind(authenticated.headers, "authorization", 0)
    end

    test "valid? always returns true" do
      auth = Basic.new("user", "pass")
      assert Auth.valid?(auth) == true
    end

    test "refresh returns auth unchanged" do
      auth = Basic.new("user", "pass")
      assert Auth.refresh(auth) == {:ok, auth}
    end
  end
end
