defmodule OmHttp.ProxyTest do
  use ExUnit.Case, async: true

  alias OmHttp.Proxy

  # ============================================
  # parse/1
  # ============================================

  describe "parse/1 with nil" do
    test "returns empty config" do
      assert {:ok, %Proxy{host: nil, auth: nil, no_proxy: []}} = Proxy.parse(nil)
    end
  end

  describe "parse/1 with URL string" do
    test "parses http proxy URL" do
      assert {:ok, config} = Proxy.parse("http://proxy.example.com:8080")
      assert config.host == {:http, "proxy.example.com", 8080, []}
      assert config.auth == nil
    end

    test "parses https proxy URL" do
      assert {:ok, config} = Proxy.parse("https://proxy.example.com:3128")
      assert config.host == {:https, "proxy.example.com", 3128, []}
      assert config.auth == nil
    end

    test "parses URL with embedded credentials" do
      assert {:ok, config} = Proxy.parse("http://user:pass@proxy.example.com:8080")
      assert config.host == {:http, "proxy.example.com", 8080, []}
      assert config.auth == {"user", "pass"}
    end

    test "decodes URL-encoded credentials" do
      assert {:ok, config} = Proxy.parse("http://user%40domain:p%40ss@proxy:8080")
      assert config.auth == {"user@domain", "p@ss"}
    end

    test "handles username without password" do
      assert {:ok, config} = Proxy.parse("http://user@proxy:8080")
      assert config.auth == {"user", ""}
    end

    test "uses URI-provided port 80 for http URLs without explicit port" do
      assert {:ok, config} = Proxy.parse("http://proxy.example.com")
      assert {:http, "proxy.example.com", 80, []} = config.host
    end

    test "defaults https port to 443" do
      assert {:ok, config} = Proxy.parse("https://proxy.example.com")
      assert {:https, "proxy.example.com", 443, []} = config.host
    end

    test "returns error for invalid URL" do
      assert {:error, {:invalid_proxy_url, "not-a-url"}} = Proxy.parse("not-a-url")
    end

    test "returns error for empty string" do
      assert {:error, {:invalid_proxy_url, ""}} = Proxy.parse("")
    end
  end

  describe "parse/1 with keyword options" do
    test "parses proxy URL from options" do
      assert {:ok, config} = Proxy.parse(proxy: "http://proxy:8080")
      assert config.host == {:http, "proxy", 8080, []}
    end

    test "parses proxy tuple from options" do
      assert {:ok, config} = Proxy.parse(proxy: {"proxy.example.com", 8080})
      assert config.host == {:http, "proxy.example.com", 8080, []}
    end

    test "parses Mint-format proxy from options" do
      proxy = {:http, "proxy.example.com", 8080, []}
      assert {:ok, config} = Proxy.parse(proxy: proxy)
      assert config.host == proxy
    end

    test "parses HTTPS Mint-format proxy" do
      proxy = {:https, "proxy.example.com", 3128, []}
      assert {:ok, config} = Proxy.parse(proxy: proxy)
      assert config.host == proxy
    end

    test "uses separate proxy_auth over URL-embedded credentials" do
      assert {:ok, config} = Proxy.parse(
        proxy: "http://urluser:urlpass@proxy:8080",
        proxy_auth: {"optuser", "optpass"}
      )

      assert config.auth == {"optuser", "optpass"}
    end

    test "falls back to URL-embedded credentials when no proxy_auth" do
      assert {:ok, config} = Proxy.parse(proxy: "http://user:pass@proxy:8080")
      assert config.auth == {"user", "pass"}
    end

    test "parses no_proxy as list" do
      assert {:ok, config} = Proxy.parse(proxy: "http://proxy:8080", no_proxy: ["localhost", ".internal.com"])
      assert config.no_proxy == ["localhost", ".internal.com"]
    end

    test "parses no_proxy as comma-separated string" do
      assert {:ok, config} = Proxy.parse(proxy: "http://proxy:8080", no_proxy: "localhost, .internal.com")
      assert config.no_proxy == ["localhost", ".internal.com"]
    end

    test "returns empty config when proxy key is nil" do
      assert {:ok, config} = Proxy.parse(proxy: nil)
      assert config.host == nil
    end

    test "returns error for invalid proxy format" do
      assert {:error, {:invalid_proxy_format, :bad}} = Proxy.parse(proxy: :bad)
    end
  end

  describe "parse/1 with map" do
    test "parses map input" do
      assert {:ok, config} = Proxy.parse(%{proxy: "http://proxy:8080", proxy_auth: {"u", "p"}})
      assert config.host == {:http, "proxy", 8080, []}
      assert config.auth == {"u", "p"}
    end
  end

  # ============================================
  # from_env/0
  # ============================================

  describe "from_env/0" do
    setup do
      # Clear all proxy env vars before each test
      env_vars = ~w(HTTPS_PROXY https_proxy HTTP_PROXY http_proxy NO_PROXY no_proxy)
      original = Map.new(env_vars, fn var -> {var, System.get_env(var)} end)

      Enum.each(env_vars, &System.delete_env/1)

      on_exit(fn ->
        Enum.each(original, fn
          {var, nil} -> System.delete_env(var)
          {var, val} -> System.put_env(var, val)
        end)
      end)

      :ok
    end

    test "returns :no_proxy when no env vars set" do
      assert :no_proxy = Proxy.from_env()
    end

    test "reads HTTPS_PROXY" do
      System.put_env("HTTPS_PROXY", "http://proxy:8080")
      assert {:ok, config} = Proxy.from_env()
      assert config.host == {:http, "proxy", 8080, []}
    end

    test "reads HTTP_PROXY when HTTPS_PROXY not set" do
      System.put_env("HTTP_PROXY", "http://proxy:3128")
      assert {:ok, config} = Proxy.from_env()
      assert config.host == {:http, "proxy", 3128, []}
    end

    test "prefers HTTPS_PROXY over HTTP_PROXY" do
      System.put_env("HTTPS_PROXY", "http://secure-proxy:8080")
      System.put_env("HTTP_PROXY", "http://regular-proxy:8080")
      assert {:ok, config} = Proxy.from_env()
      assert {:http, "secure-proxy", 8080, []} = config.host
    end

    test "reads lowercase variants" do
      System.put_env("https_proxy", "http://proxy:8080")
      assert {:ok, _} = Proxy.from_env()
    end

    test "includes NO_PROXY from env" do
      System.put_env("HTTP_PROXY", "http://proxy:8080")
      System.put_env("NO_PROXY", "localhost,.internal.com")

      assert {:ok, config} = Proxy.from_env()
      assert config.no_proxy == ["localhost", ".internal.com"]
    end

    test "returns :no_proxy for invalid env var URL" do
      System.put_env("HTTP_PROXY", "not-a-valid-url")
      assert :no_proxy = Proxy.from_env()
    end
  end

  # ============================================
  # get_config/1
  # ============================================

  describe "get_config/1" do
    setup do
      env_vars = ~w(HTTPS_PROXY https_proxy HTTP_PROXY http_proxy NO_PROXY no_proxy)
      original = Map.new(env_vars, fn var -> {var, System.get_env(var)} end)
      Enum.each(env_vars, &System.delete_env/1)

      on_exit(fn ->
        Enum.each(original, fn
          {var, nil} -> System.delete_env(var)
          {var, val} -> System.put_env(var, val)
        end)
      end)

      :ok
    end

    test "returns nil when no config and no env" do
      assert nil == Proxy.get_config(nil)
    end

    test "falls back to env when nil" do
      System.put_env("HTTP_PROXY", "http://env-proxy:8080")
      config = Proxy.get_config(nil)
      assert config.host == {:http, "env-proxy", 8080, []}
    end

    test "falls back to env when opts have no proxy key" do
      System.put_env("HTTP_PROXY", "http://env-proxy:8080")
      config = Proxy.get_config([])
      assert config.host == {:http, "env-proxy", 8080, []}
    end

    test "prefers explicit config over env" do
      System.put_env("HTTP_PROXY", "http://env-proxy:8080")
      config = Proxy.get_config(proxy: "http://explicit-proxy:9090")
      assert {:http, "explicit-proxy", 9090, []} = config.host
    end

    test "parses string URL" do
      config = Proxy.get_config("http://proxy:8080")
      assert config.host == {:http, "proxy", 8080, []}
    end

    test "returns nil for invalid string URL" do
      assert nil == Proxy.get_config("bad-url")
    end
  end

  # ============================================
  # to_req_options/1
  # ============================================

  describe "to_req_options/1" do
    test "returns empty list for nil" do
      assert [] == Proxy.to_req_options(nil)
    end

    test "returns empty list for unconfigured proxy" do
      assert [] == Proxy.to_req_options(%Proxy{host: nil})
    end

    test "returns proxy option without auth" do
      config = %Proxy{host: {:http, "proxy", 8080, []}}
      assert [proxy: {:http, "proxy", 8080, []}] = Proxy.to_req_options(config)
    end

    test "returns proxy and auth header with credentials" do
      config = %Proxy{host: {:http, "proxy", 8080, []}, auth: {"user", "pass"}}
      opts = Proxy.to_req_options(config)

      assert opts[:proxy] == {:http, "proxy", 8080, []}
      assert [{"proxy-authorization", auth}] = opts[:proxy_headers]
      assert auth == "Basic " <> Base.encode64("user:pass")
    end

    test "works with https proxy" do
      config = %Proxy{host: {:https, "proxy", 3128, []}}
      assert [proxy: {:https, "proxy", 3128, []}] = Proxy.to_req_options(config)
    end

    test "works with https proxy and auth" do
      config = %Proxy{host: {:https, "proxy", 3128, []}, auth: {"u", "p"}}
      opts = Proxy.to_req_options(config)
      assert opts[:proxy] == {:https, "proxy", 3128, []}
      assert [{"proxy-authorization", _}] = opts[:proxy_headers]
    end
  end

  # ============================================
  # should_bypass?/2
  # ============================================

  describe "should_bypass?/2" do
    test "returns false for nil config" do
      refute Proxy.should_bypass?(nil, "example.com")
    end

    test "returns false for empty no_proxy" do
      config = %Proxy{no_proxy: []}
      refute Proxy.should_bypass?(config, "example.com")
    end

    test "matches exact hostname" do
      config = %Proxy{no_proxy: ["localhost"]}
      assert Proxy.should_bypass?(config, "localhost")
      refute Proxy.should_bypass?(config, "notlocalhost")
    end

    test "matches dot-prefix wildcard suffix" do
      config = %Proxy{no_proxy: [".internal.com"]}
      assert Proxy.should_bypass?(config, "api.internal.com")
      assert Proxy.should_bypass?(config, "deep.api.internal.com")
      refute Proxy.should_bypass?(config, "internal.com")
      refute Proxy.should_bypass?(config, "notinternal.com")
    end

    test "matches bare domain suffix" do
      config = %Proxy{no_proxy: ["example.com"]}
      assert Proxy.should_bypass?(config, "api.example.com")
      assert Proxy.should_bypass?(config, "example.com")
      refute Proxy.should_bypass?(config, "notexample.com")
    end

    test "handles global wildcard *" do
      config = %Proxy{no_proxy: ["*"]}
      assert Proxy.should_bypass?(config, "anything.com")
      assert Proxy.should_bypass?(config, "localhost")
      assert Proxy.should_bypass?(config, "192.168.1.1")
    end

    test "matches case-insensitively" do
      config = %Proxy{no_proxy: ["LOCALHOST", ".Internal.COM"]}
      assert Proxy.should_bypass?(config, "localhost")
      assert Proxy.should_bypass?(config, "LOCALHOST")
      assert Proxy.should_bypass?(config, "api.internal.com")
      assert Proxy.should_bypass?(config, "API.INTERNAL.COM")
    end

    test "handles multiple patterns" do
      config = %Proxy{no_proxy: ["localhost", ".internal.com", "10.0.0.1"]}
      assert Proxy.should_bypass?(config, "localhost")
      assert Proxy.should_bypass?(config, "api.internal.com")
      assert Proxy.should_bypass?(config, "10.0.0.1")
      refute Proxy.should_bypass?(config, "external.com")
    end
  end

  # ============================================
  # to_req_options_for/2
  # ============================================

  describe "to_req_options_for/2" do
    test "returns empty for nil config" do
      assert [] == Proxy.to_req_options_for(nil, "example.com")
    end

    test "returns proxy options for non-bypassed host" do
      config = %Proxy{host: {:http, "proxy", 8080, []}, no_proxy: ["localhost"]}
      assert [proxy: _] = Proxy.to_req_options_for(config, "api.stripe.com")
    end

    test "returns empty for bypassed host" do
      config = %Proxy{host: {:http, "proxy", 8080, []}, no_proxy: ["localhost"]}
      assert [] == Proxy.to_req_options_for(config, "localhost")
    end
  end

  # ============================================
  # configured?/1
  # ============================================

  describe "configured?/1" do
    test "returns false for nil" do
      refute Proxy.configured?(nil)
    end

    test "returns false for nil host" do
      refute Proxy.configured?(%Proxy{host: nil})
    end

    test "returns true when host is set" do
      assert Proxy.configured?(%Proxy{host: {:http, "proxy", 8080, []}})
    end
  end

  # ============================================
  # display_url/1
  # ============================================

  describe "display_url/1" do
    test "returns nil for nil" do
      assert nil == Proxy.display_url(nil)
    end

    test "returns nil for unconfigured" do
      assert nil == Proxy.display_url(%Proxy{host: nil})
    end

    test "shows http URL without credentials" do
      config = %Proxy{host: {:http, "proxy", 8080, []}}
      assert "http://proxy:8080" == Proxy.display_url(config)
    end

    test "masks credentials in http URL" do
      config = %Proxy{host: {:http, "proxy", 8080, []}, auth: {"user", "secret"}}
      assert "http://***:***@proxy:8080" == Proxy.display_url(config)
    end

    test "shows https URL without credentials" do
      config = %Proxy{host: {:https, "proxy", 3128, []}}
      assert "https://proxy:3128" == Proxy.display_url(config)
    end

    test "masks credentials in https URL" do
      config = %Proxy{host: {:https, "proxy", 3128, []}, auth: {"user", "secret"}}
      assert "https://***:***@proxy:3128" == Proxy.display_url(config)
    end
  end

  # ============================================
  # Inspect protocol
  # ============================================

  describe "Inspect protocol" do
    test "shows not configured for nil host" do
      config = %Proxy{host: nil}
      assert inspect(config) == "#OmHttp.Proxy<not configured>"
    end

    test "shows URL without credentials" do
      config = %Proxy{host: {:http, "proxy", 8080, []}}
      assert inspect(config) == "#OmHttp.Proxy<http://proxy:8080>"
    end

    test "masks credentials" do
      config = %Proxy{host: {:http, "proxy", 8080, []}, auth: {"user", "secret"}}
      assert inspect(config) == "#OmHttp.Proxy<http://***:***@proxy:8080>"
    end

    test "shows https scheme" do
      config = %Proxy{host: {:https, "proxy", 3128, []}}
      assert inspect(config) == "#OmHttp.Proxy<https://proxy:3128>"
    end

    test "credentials never leak in inspect output" do
      config = %Proxy{host: {:http, "proxy", 8080, []}, auth: {"admin", "supersecret"}}
      output = inspect(config)
      refute output =~ "admin"
      refute output =~ "supersecret"
    end
  end
end
