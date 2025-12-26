defmodule OmHealth.EnvironmentTest do
  use ExUnit.Case, async: true

  alias OmHealth.Environment

  describe "get_info/1" do
    test "returns environment information map" do
      info = Environment.get_info()

      assert is_map(info)
      assert Map.has_key?(info, :mix_env)
      assert Map.has_key?(info, :elixir_version)
      assert Map.has_key?(info, :otp_release)
      assert Map.has_key?(info, :node_name)
      assert Map.has_key?(info, :hostname)
      assert Map.has_key?(info, :in_docker)
      assert Map.has_key?(info, :live_reload)
      assert Map.has_key?(info, :watchers)
    end

    test "returns valid elixir version" do
      info = Environment.get_info()
      assert is_binary(info.elixir_version)
      assert String.match?(info.elixir_version, ~r/^\d+\.\d+/)
    end

    test "returns valid OTP release" do
      info = Environment.get_info()
      assert is_binary(info.otp_release)
    end

    test "returns atom for node name" do
      info = Environment.get_info()
      assert is_atom(info.node_name)
    end

    test "returns string for hostname" do
      info = Environment.get_info()
      assert is_binary(info.hostname)
    end

    test "returns boolean for in_docker" do
      info = Environment.get_info()
      assert is_boolean(info.in_docker)
    end

    test "accepts keyword list options" do
      info = Environment.get_info(app_name: :test_app)
      assert is_map(info)
    end

    test "accepts map options" do
      info = Environment.get_info(%{app_name: :test_app})
      assert is_map(info)
    end
  end

  describe "in_docker?/0" do
    test "returns boolean" do
      result = Environment.in_docker?()
      assert is_boolean(result)
    end
  end

  describe "safe_mix_env/0" do
    test "returns current mix environment" do
      env = Environment.safe_mix_env()
      assert is_atom(env)
      assert env in [:dev, :test, :prod, :unknown]
    end
  end

  describe "safe_hostname/0" do
    test "returns hostname string" do
      hostname = Environment.safe_hostname()
      assert is_binary(hostname)
      assert hostname != ""
    end
  end
end
