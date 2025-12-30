defmodule FnDecorator.CachingTest do
  use ExUnit.Case, async: true

  # ============================================
  # Caching Schema Validation Tests
  # ============================================
  #
  # Note: Full integration tests with actual caching would require
  # a cache module to be available at compile time. These tests
  # validate the decorator schemas and ensure proper validation.
  # ============================================

  describe "cacheable schema validation" do
    test "validates store option is required" do
      assert_raise NimbleOptions.ValidationError, ~r/required :store option not found/, fn ->
        Code.compile_string("""
        defmodule TestCacheableNoStore do
          use FnDecorator

          @decorate cacheable(prevent_thunder_herd: false)
          def test_fn, do: :ok
        end
        """)
      end
    end

    test "validates cache within store is required" do
      assert_raise NimbleOptions.ValidationError, ~r/required :cache option not found/, fn ->
        Code.compile_string("""
        defmodule TestCacheableNoCache do
          use FnDecorator

          @decorate cacheable(store: [key: :test, ttl: 1000])
          def test_fn, do: :ok
        end
        """)
      end
    end

    test "validates on_error options" do
      # Note: The cache module must be a literal atom, not an alias like TestCache
      # which gets passed as AST. Using a fake atom that doesn't exist is fine for
      # schema validation since we're testing the on_error validation.
      assert_raise NimbleOptions.ValidationError, ~r/:on_error/, fn ->
        Code.compile_string("""
        defmodule TestCacheableInvalidOnError do
          use FnDecorator

          @decorate cacheable(cache: :fake_cache_module, key: :test, on_error: :invalid_option)
          def test_fn, do: :ok
        end
        """)
      end
    end
  end

  describe "cache_put schema validation" do
    test "validates cache is required" do
      assert_raise NimbleOptions.ValidationError, ~r/required :cache option not found/, fn ->
        Code.compile_string("""
        defmodule TestCachePutNoCache do
          use FnDecorator

          @decorate cache_put(keys: [:test])
          def test_fn, do: :ok
        end
        """)
      end
    end

    test "validates keys is required" do
      # Use literal atom for cache module to avoid AST issues
      assert_raise NimbleOptions.ValidationError, ~r/required :keys option not found/, fn ->
        Code.compile_string("""
        defmodule TestCachePutNoKeys do
          use FnDecorator

          @decorate cache_put(cache: :fake_cache_module)
          def test_fn, do: :ok
        end
        """)
      end
    end
  end

  describe "cache_evict schema validation" do
    test "validates cache is required" do
      assert_raise NimbleOptions.ValidationError, ~r/required :cache option not found/, fn ->
        Code.compile_string("""
        defmodule TestCacheEvictNoCache do
          use FnDecorator

          @decorate cache_evict(keys: [:test])
          def test_fn, do: :ok
        end
        """)
      end
    end

    test "validates at least one eviction target is required" do
      # Use literal atom for cache module to avoid AST issues
      # cache_evict now requires at least one of: keys, match, or all_entries
      assert_raise NimbleOptions.ValidationError, ~r/requires at least one of/, fn ->
        Code.compile_string("""
        defmodule TestCacheEvictNoTarget do
          use FnDecorator

          @decorate cache_evict(cache: :fake_cache_module)
          def test_fn, do: :ok
        end
        """)
      end
    end
  end
end
