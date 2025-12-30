defmodule OmScheduler.ConfigTest do
  use ExUnit.Case, async: true

  alias OmScheduler.Config

  describe "to_ms/1" do
    test "returns milliseconds as-is" do
      assert Config.to_ms(1000) == 1000
      assert Config.to_ms(5000) == 5000
    end

    test "converts seconds to milliseconds" do
      assert Config.to_ms({1, :second}) == 1_000
      assert Config.to_ms({5, :seconds}) == 5_000
    end

    test "converts minutes to milliseconds" do
      assert Config.to_ms({1, :minute}) == 60_000
      assert Config.to_ms({5, :minutes}) == 300_000
    end

    test "converts hours to milliseconds" do
      assert Config.to_ms({1, :hour}) == 3_600_000
      assert Config.to_ms({2, :hours}) == 7_200_000
    end

    test "converts days to milliseconds" do
      assert Config.to_ms({1, :day}) == 86_400_000
      assert Config.to_ms({7, :days}) == 604_800_000
    end
  end

  describe "valid_duration?/1" do
    test "returns true for valid integer" do
      assert Config.valid_duration?(1000) == true
      assert Config.valid_duration?(1) == true
    end

    test "returns false for non-positive integers" do
      assert Config.valid_duration?(0) == false
      assert Config.valid_duration?(-1) == false
    end

    test "returns true for valid tuples" do
      assert Config.valid_duration?({5, :minutes}) == true
      assert Config.valid_duration?({1, :hour}) == true
      assert Config.valid_duration?({7, :days}) == true
    end

    test "returns false for invalid tuples" do
      assert Config.valid_duration?({-1, :seconds}) == false
      assert Config.valid_duration?({5, :invalid}) == false
    end

    test "returns false for invalid types" do
      assert Config.valid_duration?("1000") == false
      assert Config.valid_duration?(nil) == false
    end
  end

  describe "subtract_duration/2" do
    test "subtracts milliseconds" do
      now = ~U[2024-01-10 12:00:00.000Z]
      result = Config.subtract_duration(now, 3_600_000)
      assert result == ~U[2024-01-10 11:00:00.000Z]
    end

    test "subtracts duration tuple" do
      now = ~U[2024-01-10 12:00:00.000Z]
      result = Config.subtract_duration(now, {1, :hour})
      assert result == ~U[2024-01-10 11:00:00.000Z]
    end

    test "subtracts days" do
      now = ~U[2024-01-10 12:00:00.000Z]
      result = Config.subtract_duration(now, {7, :days})
      assert result == ~U[2024-01-03 12:00:00.000Z]
    end
  end

  describe "get_store_module/1" do
    test "returns Memory store for :memory" do
      assert Config.get_store_module(store: :memory) == OmScheduler.Store.Memory
    end

    test "returns Database store for :database" do
      assert Config.get_store_module(store: :database) == OmScheduler.Store.Database
    end

    test "returns Redis store for :redis" do
      assert Config.get_store_module(store: :redis) == OmScheduler.Store.Redis
    end

    test "returns Memory store by default" do
      assert Config.get_store_module([]) == OmScheduler.Store.Memory
    end

    test "returns custom module if provided" do
      assert Config.get_store_module(store: MyApp.CustomStore) == MyApp.CustomStore
    end
  end

  describe "producer_name/1" do
    test "generates producer name from atom" do
      assert Config.producer_name(:default) == :"OmScheduler.Queue.Producer.default"
    end

    test "generates producer name from string" do
      assert Config.producer_name("priority") == :"OmScheduler.Queue.Producer.priority"
    end
  end

  describe "leader?/1" do
    test "returns true when peer is nil" do
      assert Config.leader?(nil) == true
    end

    test "returns false when peer is false" do
      assert Config.leader?(false) == false
    end
  end

  describe "validate/1" do
    test "accepts valid minimal config" do
      assert {:ok, config} = Config.validate(enabled: true, store: :memory)
      assert config[:enabled] == true
      assert config[:store] == :memory
    end

    test "applies defaults" do
      assert {:ok, config} = Config.validate([])
      assert config[:enabled] == true
      assert config[:queues] == [default: 10]
    end

    test "rejects invalid store" do
      assert {:error, _} = Config.validate(store: :invalid_store)
    end

    test "requires repo for database store" do
      assert {:error, "repo is required when store is :database"} =
               Config.validate(store: :database)
    end
  end

  describe "schema/0" do
    test "returns NimbleOptions schema" do
      schema = Config.schema()
      assert is_list(schema)
      assert Keyword.has_key?(schema, :enabled)
      assert Keyword.has_key?(schema, :store)
      assert Keyword.has_key?(schema, :queues)
    end
  end
end
