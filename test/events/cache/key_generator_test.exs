defmodule OmCache.KeyGeneratorTest do
  @moduledoc """
  Tests for OmCache.KeyGenerator.
  """

  use Events.DataCase, async: true

  alias OmCache.KeyGenerator

  describe "generate/3" do
    test "returns 0 for empty arguments" do
      assert KeyGenerator.generate(MyModule, :my_func, []) == 0
    end

    test "returns single argument as key" do
      assert KeyGenerator.generate(MyModule, :my_func, [123]) == 123
      assert KeyGenerator.generate(MyModule, :my_func, ["string"]) == "string"
      assert KeyGenerator.generate(MyModule, :my_func, [:atom]) == :atom
      assert KeyGenerator.generate(MyModule, :my_func, [{:tuple, 1}]) == {:tuple, 1}
    end

    test "returns phash2 of multiple arguments" do
      args = [1, 2, 3]
      expected_hash = :erlang.phash2(args)

      assert KeyGenerator.generate(MyModule, :my_func, args) == expected_hash
    end

    test "different argument orders produce different keys" do
      key1 = KeyGenerator.generate(MyModule, :func, [1, 2, 3])
      key2 = KeyGenerator.generate(MyModule, :func, [3, 2, 1])

      assert key1 != key2
    end

    test "same arguments produce same key" do
      args = [:a, :b, :c]

      key1 = KeyGenerator.generate(MyModule, :func, args)
      key2 = KeyGenerator.generate(MyModule, :func, args)

      assert key1 == key2
    end

    test "module and function are ignored in default implementation" do
      args = [42]

      key1 = KeyGenerator.generate(ModuleA, :func_a, args)
      key2 = KeyGenerator.generate(ModuleB, :func_b, args)

      # Both should return the single argument
      assert key1 == key2
      assert key1 == 42
    end

    test "handles complex data structures" do
      complex_args = [
        %{user: %{id: 1, roles: [:admin, :user]}},
        [1, 2, 3],
        {:ok, "result"}
      ]

      key = KeyGenerator.generate(MyModule, :func, complex_args)

      # Should produce a consistent hash
      assert is_integer(key)
      assert key == :erlang.phash2(complex_args)
    end

    test "handles nil arguments" do
      assert KeyGenerator.generate(MyModule, :func, [nil]) == nil

      key = KeyGenerator.generate(MyModule, :func, [nil, nil])
      assert is_integer(key)
    end
  end
end
