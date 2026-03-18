defmodule OmS3.ConfigTest do
  use ExUnit.Case, async: true

  alias OmS3.Config

  describe "new/1" do
    test "creates config with required fields" do
      config =
        Config.new(
          access_key_id: "AKIATEST",
          secret_access_key: "secret123"
        )

      assert config.access_key_id == "AKIATEST"
      assert config.secret_access_key == "secret123"
      assert config.region == "us-east-1"
    end

    test "creates config with custom region" do
      config =
        Config.new(
          access_key_id: "AKIATEST",
          secret_access_key: "secret123",
          region: "eu-west-1"
        )

      assert config.region == "eu-west-1"
    end

    test "creates config with custom endpoint" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          endpoint: "http://localhost:4566"
        )

      assert config.endpoint == "http://localhost:4566"
    end

    test "normalizes proxy tuple" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          proxy: {"proxy.example.com", 8080}
        )

      assert config.proxy == {:http, "proxy.example.com", 8080, []}
    end

    test "preserves full proxy tuple" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          proxy: {:http, "proxy.example.com", 8080, [ssl: true]}
        )

      assert config.proxy == {:http, "proxy.example.com", 8080, [ssl: true]}
    end

    test "stores proxy auth" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          proxy: {"proxy.example.com", 8080},
          proxy_auth: {"user", "pass"}
        )

      assert config.proxy_auth == {"user", "pass"}
    end

    test "sets custom timeouts" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          connect_timeout: 10_000,
          receive_timeout: 120_000
        )

      assert config.connect_timeout == 10_000
      assert config.receive_timeout == 120_000
    end

    test "uses default timeouts" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test"
        )

      assert config.connect_timeout == 30_000
      assert config.receive_timeout == 60_000
    end

    test "raises on missing access_key_id" do
      assert_raise KeyError, ~r/access_key_id/, fn ->
        Config.new(secret_access_key: "secret")
      end
    end

    test "raises on missing secret_access_key" do
      assert_raise KeyError, ~r/secret_access_key/, fn ->
        Config.new(access_key_id: "AKIATEST")
      end
    end

    test "defaults transfer_acceleration to false" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test"
        )

      assert config.transfer_acceleration == false
    end

    test "enables transfer_acceleration" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          transfer_acceleration: true
        )

      assert config.transfer_acceleration == true
    end

    test "defaults path_style to false" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test"
        )

      assert config.path_style == false
    end

    test "enables path_style" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          path_style: true
        )

      assert config.path_style == true
    end
  end

  describe "connect_options/1" do
    test "returns timeout option" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          connect_timeout: 15_000
        )

      opts = Config.connect_options(config)
      assert opts[:timeout] == 15_000
    end

    test "includes proxy when configured" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          proxy: {"proxy.example.com", 8080}
        )

      opts = Config.connect_options(config)
      assert opts[:proxy] == {:http, "proxy.example.com", 8080, []}
    end

    test "includes proxy auth header when configured" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          proxy: {"proxy.example.com", 8080},
          proxy_auth: {"user", "pass"}
        )

      opts = Config.connect_options(config)
      assert [{_, auth_header}] = opts[:proxy_headers]
      assert String.starts_with?(auth_header, "Basic ")
    end
  end

  describe "aws_sigv4_options/1" do
    test "returns AWS credentials for signing" do
      config =
        Config.new(
          access_key_id: "AKIATEST",
          secret_access_key: "secret123",
          region: "eu-west-1"
        )

      opts = Config.aws_sigv4_options(config)

      assert opts[:access_key_id] == "AKIATEST"
      assert opts[:secret_access_key] == "secret123"
      assert opts[:region] == "eu-west-1"
    end
  end

  describe "presign_options/3" do
    test "returns presign options" do
      config =
        Config.new(
          access_key_id: "AKIATEST",
          secret_access_key: "secret123",
          region: "us-east-1"
        )

      opts = Config.presign_options(config, "my-bucket", "path/file.txt")

      assert opts[:bucket] == "my-bucket"
      assert opts[:key] == "path/file.txt"
      assert opts[:access_key_id] == "AKIATEST"
      assert opts[:secret_access_key] == "secret123"
      assert opts[:region] == "us-east-1"
    end

    test "includes custom endpoint when configured" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          endpoint: "http://localhost:4566"
        )

      opts = Config.presign_options(config, "bucket", "key")

      assert opts[:aws_endpoint_url_s3] == "http://localhost:4566"
    end

    test "includes acceleration endpoint when enabled" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          transfer_acceleration: true
        )

      opts = Config.presign_options(config, "my-bucket", "key")

      assert opts[:aws_endpoint_url_s3] == "https://my-bucket.s3-accelerate.amazonaws.com"
    end
  end

  describe "endpoint_url/2" do
    test "returns path-style URL for custom endpoint (auto-detected)" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          endpoint: "http://localhost:4566"
        )

      # Custom endpoints auto-default to path_style: true
      assert config.path_style == true
      assert Config.endpoint_url(config, "my-bucket") == "http://localhost:4566/my-bucket"
    end

    test "returns virtual-hosted URL for custom endpoint when path_style: false" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          endpoint: "http://localhost:4566",
          path_style: false
        )

      assert Config.endpoint_url(config, "my-bucket") == "http://localhost:4566"
    end

    test "returns acceleration endpoint when enabled" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          transfer_acceleration: true
        )

      assert Config.endpoint_url(config, "my-bucket") == "https://my-bucket.s3-accelerate.amazonaws.com"
    end

    test "returns path-style endpoint when enabled" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          region: "eu-west-1",
          path_style: true
        )

      assert Config.endpoint_url(config, "my-bucket") == "https://s3.eu-west-1.amazonaws.com/my-bucket"
    end

    test "returns virtual-hosted-style endpoint by default" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          region: "us-east-1"
        )

      assert Config.endpoint_url(config, "my-bucket") == "https://my-bucket.s3.us-east-1.amazonaws.com"
    end
  end

  describe "transfer_acceleration?/1" do
    test "returns false when disabled" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test"
        )

      refute Config.transfer_acceleration?(config)
    end

    test "returns true when enabled" do
      config =
        Config.new(
          access_key_id: "test",
          secret_access_key: "test",
          transfer_acceleration: true
        )

      assert Config.transfer_acceleration?(config)
    end
  end
end
