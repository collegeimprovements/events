defmodule FnDecorator.Caching.PatternTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Caching.Pattern

  describe "match?/2" do
    test ":all matches everything" do
      assert Pattern.matches?(:all, {User, 123})
      assert Pattern.matches?(:all, :anything)
      assert Pattern.matches?(:all, "string")
      assert Pattern.matches?(:all, [1, 2, 3])
    end

    test "exact tuple matches exact tuple" do
      assert Pattern.matches?({User, 123}, {User, 123})
      refute Pattern.matches?({User, 123}, {User, 456})
      refute Pattern.matches?({User, 123}, {Admin, 123})
    end

    test "wildcard :_ matches any value" do
      assert Pattern.matches?({User, :_}, {User, 1})
      assert Pattern.matches?({User, :_}, {User, 999})
      assert Pattern.matches?({User, :_}, {User, "abc"})
      refute Pattern.matches?({User, :_}, {Admin, 1})
    end

    test "wildcard in first position" do
      assert Pattern.matches?({:_, :profile}, {User, :profile})
      assert Pattern.matches?({:_, :profile}, {Admin, :profile})
      refute Pattern.matches?({:_, :profile}, {User, :settings})
    end

    test "multiple wildcards" do
      assert Pattern.matches?({:_, :_, :meta}, {User, 1, :meta})
      assert Pattern.matches?({:_, :_, :meta}, {Admin, "x", :meta})
      refute Pattern.matches?({:_, :_, :meta}, {User, 1, :data})
    end

    test "nested tuples with wildcards" do
      assert Pattern.matches?({{:cache, :_}, :_}, {{:cache, User}, 123})
      refute Pattern.matches?({{:cache, :_}, :_}, {{:other, User}, 123})
    end

    test "different tuple sizes don't match" do
      refute Pattern.matches?({User, :_}, {User, 1, :extra})
      refute Pattern.matches?({User, :_, :_}, {User, 1})
    end

    test "list of keys matches if key is in list" do
      keys = [{User, 1}, {User, 2}, {Admin, 1}]
      assert Pattern.matches?(keys, {User, 1})
      assert Pattern.matches?(keys, {Admin, 1})
      refute Pattern.matches?(keys, {User, 999})
    end

    test "non-tuple exact match" do
      assert Pattern.matches?(:session, :session)
      refute Pattern.matches?(:session, :other)
    end
  end

  describe "filter/2" do
    test "filters keys by pattern" do
      keys = [{User, 1}, {User, 2}, {Admin, 1}, {:session, "abc"}]

      assert Pattern.filter(keys, {User, :_}) == [{User, 1}, {User, 2}]
      assert Pattern.filter(keys, {Admin, :_}) == [{Admin, 1}]
      assert Pattern.filter(keys, {:session, :_}) == [{:session, "abc"}]
    end

    test ":all returns all keys" do
      keys = [{User, 1}, {Admin, 2}]
      assert Pattern.filter(keys, :all) == keys
    end

    test "empty list returns empty" do
      assert Pattern.filter([], {User, :_}) == []
    end
  end

  describe "wildcard?/1" do
    test "returns true for :all" do
      assert Pattern.wildcard?(:all)
    end

    test "returns true for tuple with :_" do
      assert Pattern.wildcard?({User, :_})
      assert Pattern.wildcard?({:_, :profile})
      assert Pattern.wildcard?({:_, :_, :_})
    end

    test "returns false for exact tuple" do
      refute Pattern.wildcard?({User, 123})
      refute Pattern.wildcard?({User, 1, :profile})
    end

    test "returns true for bare :_" do
      assert Pattern.wildcard?(:_)
    end

    test "returns false for lists" do
      refute Pattern.wildcard?([{User, 1}, {User, 2}])
    end

    test "returns false for atoms (except :all and :_)" do
      refute Pattern.wildcard?(:session)
      refute Pattern.wildcard?(:user)
    end
  end

  describe "key_list?/1" do
    test "returns true for non-empty list" do
      assert Pattern.key_list?([{User, 1}, {User, 2}])
      assert Pattern.key_list?([{User, 1}])
      assert Pattern.key_list?([:a, :b, :c])
    end

    test "returns false for empty list" do
      refute Pattern.key_list?([])
    end

    test "returns false for non-lists" do
      refute Pattern.key_list?({User, :_})
      refute Pattern.key_list?(:all)
      refute Pattern.key_list?("string")
    end
  end

  describe "to_ets_match_pattern/1" do
    test "converts :all to :_" do
      assert Pattern.to_ets_match_pattern(:all) == :_
    end

    test "passes through tuples" do
      assert Pattern.to_ets_match_pattern({User, :_}) == {User, :_}
      assert Pattern.to_ets_match_pattern({User, 123}) == {User, 123}
    end
  end
end
