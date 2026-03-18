defmodule OmCache.WarmingTest do
  use ExUnit.Case

  alias OmCache.Warming

  @cache OmCache.TestCache

  setup do
    @cache.delete_all()
    :ok
  end

  describe "warm/4" do
    test "warms cache with loaded values" do
      assert {:ok, 3} =
               Warming.warm(@cache, [1, 2, 3], fn id ->
                 {:ok, "user_#{id}"}
               end, key_fn: &{:user, &1})

      assert @cache.get({:user, 1}) == "user_1"
      assert @cache.get({:user, 2}) == "user_2"
      assert @cache.get({:user, 3}) == "user_3"
    end

    test "skips errors by default" do
      assert {:ok, 1} =
               Warming.warm(@cache, [1, 2], fn
                 1 -> {:ok, "good"}
                 2 -> {:error, :not_found}
               end)

      assert @cache.get(1) == "good"
      assert @cache.get(2) == nil
    end

    test "stops on error when on_error: :stop" do
      result =
        Warming.warm(@cache, [1, 2], fn _ -> {:error, :boom} end, on_error: :stop)

      assert {:error, _} = result
    end

    test "uses identity key_fn by default" do
      assert {:ok, 1} = Warming.warm(@cache, [:my_key], fn _k -> {:ok, "value"} end)
      assert @cache.get(:my_key) == "value"
    end
  end

  describe "warm_batch/4" do
    test "bulk inserts pre-loaded data" do
      data = [%{id: 1, name: "alice"}, %{id: 2, name: "bob"}]

      assert {:ok, 2} = Warming.warm_batch(@cache, data, fn item -> {:user, item.id} end)
      assert @cache.get({:user, 1}) == %{id: 1, name: "alice"}
      assert @cache.get({:user, 2}) == %{id: 2, name: "bob"}
    end

    test "applies TTL" do
      data = [%{id: 1}]

      assert {:ok, 1} =
               Warming.warm_batch(@cache, data, fn item -> {:user, item.id} end, ttl: 100)

      assert @cache.get({:user, 1}) == %{id: 1}

      # Wait for TTL
      Process.sleep(150)
      assert @cache.get({:user, 1}) == nil
    end
  end
end
