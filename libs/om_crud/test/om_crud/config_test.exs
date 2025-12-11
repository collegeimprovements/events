defmodule OmCrud.ConfigTest do
  use ExUnit.Case, async: true

  describe "default_repo/0" do
    test "raises when not configured" do
      # Temporarily unset the config
      original = Application.get_env(:om_crud, :default_repo)
      Application.delete_env(:om_crud, :default_repo)

      assert_raise ArgumentError, ~r/OmCrud requires a default repo/, fn ->
        OmCrud.Config.default_repo()
      end

      # Restore original config
      if original, do: Application.put_env(:om_crud, :default_repo, original)
    end

    test "returns configured repo when set" do
      Application.put_env(:om_crud, :default_repo, TestRepo)

      assert OmCrud.Config.default_repo() == TestRepo

      Application.delete_env(:om_crud, :default_repo)
    end
  end

  describe "telemetry_prefix/0" do
    test "returns default prefix when not configured" do
      original = Application.get_env(:om_crud, :telemetry_prefix)
      Application.delete_env(:om_crud, :telemetry_prefix)

      assert OmCrud.Config.telemetry_prefix() == [:om_crud, :execute]

      if original, do: Application.put_env(:om_crud, :telemetry_prefix, original)
    end

    test "returns configured prefix when set" do
      Application.put_env(:om_crud, :telemetry_prefix, [:custom, :prefix])

      assert OmCrud.Config.telemetry_prefix() == [:custom, :prefix]

      Application.delete_env(:om_crud, :telemetry_prefix)
    end
  end
end
