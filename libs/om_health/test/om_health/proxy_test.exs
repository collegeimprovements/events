defmodule OmHealth.ProxyTest do
  use ExUnit.Case, async: true

  alias OmHealth.Proxy

  describe "get_config/0" do
    test "returns proxy configuration map" do
      config = Proxy.get_config()

      assert is_map(config)
      assert Map.has_key?(config, :configured)
      assert Map.has_key?(config, :http_proxy)
      assert Map.has_key?(config, :https_proxy)
      assert Map.has_key?(config, :no_proxy)
      assert Map.has_key?(config, :services_using_proxy)
    end

    test "configured is boolean" do
      config = Proxy.get_config()
      assert is_boolean(config.configured)
    end

    test "services_using_proxy is a list" do
      config = Proxy.get_config()
      assert is_list(config.services_using_proxy)
    end

    test "accepts custom services option" do
      config = Proxy.get_config(services: ["Custom Service"])

      # Only has custom services if proxy is configured
      if config.configured do
        assert config.services_using_proxy == ["Custom Service"]
      else
        assert config.services_using_proxy == []
      end
    end
  end

  describe "configured?/0" do
    test "returns boolean" do
      result = Proxy.configured?()
      assert is_boolean(result)
    end
  end

  describe "with proxy environment variables" do
    setup do
      # Save current env vars
      original_http = System.get_env("HTTP_PROXY")
      original_https = System.get_env("HTTPS_PROXY")
      original_no_proxy = System.get_env("NO_PROXY")

      on_exit(fn ->
        # Restore original env vars
        if original_http, do: System.put_env("HTTP_PROXY", original_http), else: System.delete_env("HTTP_PROXY")
        if original_https, do: System.put_env("HTTPS_PROXY", original_https), else: System.delete_env("HTTPS_PROXY")
        if original_no_proxy, do: System.put_env("NO_PROXY", original_no_proxy), else: System.delete_env("NO_PROXY")
      end)

      :ok
    end

    test "detects HTTP_PROXY when set" do
      System.put_env("HTTP_PROXY", "http://proxy.test:8080")

      config = Proxy.get_config()

      assert config.configured == true
      assert config.http_proxy == "http://proxy.test:8080"
      assert is_list(config.services_using_proxy)
      assert length(config.services_using_proxy) > 0
    end

    test "detects HTTPS_PROXY when set" do
      System.put_env("HTTPS_PROXY", "https://proxy.test:8443")

      config = Proxy.get_config()

      assert config.configured == true
      assert config.https_proxy == "https://proxy.test:8443"
    end

    test "detects NO_PROXY when set" do
      System.put_env("HTTP_PROXY", "http://proxy.test:8080")
      System.put_env("NO_PROXY", "localhost,127.0.0.1,.internal")

      config = Proxy.get_config()

      assert config.no_proxy == "localhost,127.0.0.1,.internal"
    end

    test "returns empty services when no proxy configured" do
      System.delete_env("HTTP_PROXY")
      System.delete_env("HTTPS_PROXY")
      System.delete_env("http_proxy")
      System.delete_env("https_proxy")

      config = Proxy.get_config()

      assert config.configured == false
      assert config.services_using_proxy == []
    end
  end
end
