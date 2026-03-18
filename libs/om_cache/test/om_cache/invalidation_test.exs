defmodule OmCache.InvalidationTest do
  use ExUnit.Case

  alias OmCache.Invalidation

  @cache OmCache.TestCache

  setup do
    @cache.delete_all()
    :ok
  end

  describe "invalidate_pattern/3" do
    test "deletes keys matching tuple pattern" do
      @cache.put({:user, 1}, "alice")
      @cache.put({:user, 2}, "bob")
      @cache.put({:session, "abc"}, "session_data")

      assert {:ok, count} = Invalidation.invalidate_pattern(@cache, {:user, :_})
      assert count == 2
      assert @cache.get({:user, 1}) == nil
      assert @cache.get({:user, 2}) == nil
      assert @cache.get({:session, "abc"}) == "session_data"
    end

    test "handles no matches" do
      @cache.put(:key, "value")
      assert {:ok, 0} = Invalidation.invalidate_pattern(@cache, {:nonexistent, :_})
    end

    test "matches exact non-tuple patterns" do
      @cache.put(:foo, "bar")
      assert {:ok, 1} = Invalidation.invalidate_pattern(@cache, :foo)
    end
  end

  describe "matches_pattern?/2" do
    test "matches tuples with wildcards" do
      assert Invalidation.matches_pattern?({:user, 1}, {:user, :_})
      assert Invalidation.matches_pattern?({:user, 1}, {:_, 1})
      assert Invalidation.matches_pattern?({:user, 1}, {:_, :_})
      refute Invalidation.matches_pattern?({:user, 1}, {:session, :_})
    end

    test "does not match different tuple sizes" do
      refute Invalidation.matches_pattern?({:user, 1, :extra}, {:user, :_})
    end

    test "matches exact values" do
      assert Invalidation.matches_pattern?(:foo, :foo)
      refute Invalidation.matches_pattern?(:foo, :bar)
    end

    test "wildcard matches anything" do
      assert Invalidation.matches_pattern?(:anything, :_)
      assert Invalidation.matches_pattern?({:a, :b}, :_)
    end
  end

  describe "put_tagged/4 and invalidate_tagged/3" do
    test "tags entries and invalidates by tag" do
      Invalidation.put_tagged(@cache, {:product, 1}, "widget", tags: [:products, :electronics])
      Invalidation.put_tagged(@cache, {:product, 2}, "gadget", tags: [:products, :toys])
      Invalidation.put_tagged(@cache, {:product, 3}, "phone", tags: [:electronics])

      # Both product 1 and 2 have :products tag
      assert {:ok, count} = Invalidation.invalidate_tagged(@cache, :products)
      assert count == 2
      assert @cache.get({:product, 1}) == nil
      assert @cache.get({:product, 2}) == nil
      assert @cache.get({:product, 3}) == "phone"
    end
  end

  describe "invalidate_group/3" do
    test "deletes all specified keys" do
      @cache.put(:a, 1)
      @cache.put(:b, 2)
      @cache.put(:c, 3)

      assert {:ok, 2} = Invalidation.invalidate_group(@cache, [:a, :b])
      assert @cache.get(:a) == nil
      assert @cache.get(:b) == nil
      assert @cache.get(:c) == 3
    end
  end

  describe "invalidate_all/2" do
    test "clears entire cache" do
      @cache.put(:a, 1)
      @cache.put(:b, 2)

      assert {:ok, :ok} = Invalidation.invalidate_all(@cache)
      assert @cache.count_all() == 0
    end
  end
end
