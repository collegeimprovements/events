defmodule OmCache.MultiLevelTest do
  use ExUnit.Case

  alias OmCache.MultiLevel

  @l1 OmCache.TestL1Cache
  @l2 OmCache.TestL2Cache

  setup do
    @l1.delete_all()
    @l2.delete_all()
    :ok
  end

  describe "get/4" do
    test "returns nil when both levels miss" do
      assert MultiLevel.get(@l1, @l2, :missing) == nil
    end

    test "returns value from L1 on L1 hit" do
      @l1.put(:key, "l1_value")
      assert MultiLevel.get(@l1, @l2, :key) == "l1_value"
    end

    test "returns value from L2 on L1 miss and promotes to L1" do
      @l2.put(:key, "l2_value")
      assert MultiLevel.get(@l1, @l2, :key) == "l2_value"
      # Should now be in L1
      assert @l1.get(:key) == "l2_value"
    end

    test "skips L1 promotion when skip_promotion: true" do
      @l2.put(:key, "l2_value")
      assert MultiLevel.get(@l1, @l2, :key, skip_promotion: true) == "l2_value"
      assert @l1.get(:key) == nil
    end

    test "skips L1 when skip_l1: true" do
      @l1.put(:key, "l1_value")
      @l2.put(:key, "l2_value")
      assert MultiLevel.get(@l1, @l2, :key, skip_l1: true) == "l2_value"
    end
  end

  describe "put/5" do
    test "puts to both levels" do
      assert {:ok, :ok} = MultiLevel.put(@l1, @l2, :key, "value")
      assert @l1.get(:key) == "value"
      assert @l2.get(:key) == "value"
    end

    test "puts to L1 only" do
      assert {:ok, :ok} = MultiLevel.put(@l1, @l2, :key, "value", l1_only: true)
      assert @l1.get(:key) == "value"
      assert @l2.get(:key) == nil
    end

    test "puts to L2 only" do
      assert {:ok, :ok} = MultiLevel.put(@l1, @l2, :key, "value", l2_only: true)
      assert @l1.get(:key) == nil
      assert @l2.get(:key) == "value"
    end
  end

  describe "delete/4" do
    test "deletes from both levels" do
      @l1.put(:key, "value")
      @l2.put(:key, "value")
      assert {:ok, :ok} = MultiLevel.delete(@l1, @l2, :key)
      assert @l1.get(:key) == nil
      assert @l2.get(:key) == nil
    end
  end

  describe "get_or_fetch/5" do
    test "returns cached value on hit" do
      @l1.put(:key, "cached")

      assert {:ok, "cached"} =
               MultiLevel.get_or_fetch(@l1, @l2, :key, fn -> {:ok, "loaded"} end)
    end

    test "loads and stores on miss" do
      assert {:ok, "loaded"} =
               MultiLevel.get_or_fetch(@l1, @l2, :key, fn -> {:ok, "loaded"} end)

      assert @l1.get(:key) == "loaded"
      assert @l2.get(:key) == "loaded"
    end

    test "returns error when loader fails" do
      assert {:error, :not_found} =
               MultiLevel.get_or_fetch(@l1, @l2, :key, fn -> {:error, :not_found} end)
    end
  end

  describe "invalidate/4" do
    test "deletes from both levels (alias for delete)" do
      @l1.put(:key, "value")
      @l2.put(:key, "value")
      assert {:ok, :ok} = MultiLevel.invalidate(@l1, @l2, :key)
      assert @l1.get(:key) == nil
      assert @l2.get(:key) == nil
    end
  end

  describe "clear_all/3" do
    test "clears both caches" do
      @l1.put(:a, 1)
      @l2.put(:b, 2)
      assert {:ok, :ok} = MultiLevel.clear_all(@l1, @l2)
      assert @l1.count_all() == 0
      assert @l2.count_all() == 0
    end
  end
end
