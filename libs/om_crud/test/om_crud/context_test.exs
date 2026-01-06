defmodule OmCrud.ContextTest do
  use ExUnit.Case, async: true

  describe "use OmCrud.Context" do
    test "imports crud macro" do
      # The module should compile without errors
      defmodule TestContext do
        use OmCrud.Context
      end

      assert Code.ensure_loaded?(TestContext)
    end
  end

  describe "crud macro" do
    defmodule TestSchema do
      use Ecto.Schema

      schema "test_table" do
        field :name, :string
      end
    end

    defmodule ContextWithAllFunctions do
      use OmCrud.Context

      # This will generate all CRUD functions
      crud TestSchema, as: :test
    end

    test "generates fetch function" do
      assert function_exported?(ContextWithAllFunctions, :fetch_test, 1)
      assert function_exported?(ContextWithAllFunctions, :fetch_test, 2)
    end

    test "generates get function" do
      assert function_exported?(ContextWithAllFunctions, :get_test, 1)
      assert function_exported?(ContextWithAllFunctions, :get_test, 2)
    end

    test "generates list function" do
      assert function_exported?(ContextWithAllFunctions, :list_tests, 0)
      assert function_exported?(ContextWithAllFunctions, :list_tests, 1)
    end

    test "generates exists? function" do
      assert function_exported?(ContextWithAllFunctions, :test_exists?, 1)
      assert function_exported?(ContextWithAllFunctions, :test_exists?, 2)
    end

    test "generates create function" do
      assert function_exported?(ContextWithAllFunctions, :create_test, 1)
      assert function_exported?(ContextWithAllFunctions, :create_test, 2)
    end

    test "generates update function" do
      assert function_exported?(ContextWithAllFunctions, :update_test, 2)
      assert function_exported?(ContextWithAllFunctions, :update_test, 3)
    end

    test "generates delete function" do
      assert function_exported?(ContextWithAllFunctions, :delete_test, 1)
      assert function_exported?(ContextWithAllFunctions, :delete_test, 2)
    end

    test "generates create_all function" do
      assert function_exported?(ContextWithAllFunctions, :create_all_tests, 1)
      assert function_exported?(ContextWithAllFunctions, :create_all_tests, 2)
    end

    test "generates update_all function" do
      # update_all(filters, changes, opts \\ [])
      assert function_exported?(ContextWithAllFunctions, :update_all_tests, 2)
      assert function_exported?(ContextWithAllFunctions, :update_all_tests, 3)
    end

    test "generates delete_all function" do
      # delete_all(filters, opts \\ [])
      assert function_exported?(ContextWithAllFunctions, :delete_all_tests, 1)
      assert function_exported?(ContextWithAllFunctions, :delete_all_tests, 2)
    end

    test "generates filter function" do
      assert function_exported?(ContextWithAllFunctions, :filter_tests, 1)
      assert function_exported?(ContextWithAllFunctions, :filter_tests, 2)
    end

    test "generates count function" do
      assert function_exported?(ContextWithAllFunctions, :count_tests, 0)
      assert function_exported?(ContextWithAllFunctions, :count_tests, 1)
    end

    test "generates first/last functions" do
      assert function_exported?(ContextWithAllFunctions, :first_test, 0)
      assert function_exported?(ContextWithAllFunctions, :first_test, 1)
      assert function_exported?(ContextWithAllFunctions, :last_test, 0)
      assert function_exported?(ContextWithAllFunctions, :last_test, 1)
    end

    test "generates stream function" do
      assert function_exported?(ContextWithAllFunctions, :stream_tests, 0)
      assert function_exported?(ContextWithAllFunctions, :stream_tests, 1)
    end

    test "generates bang variants" do
      assert function_exported?(ContextWithAllFunctions, :fetch_test!, 1)
      assert function_exported?(ContextWithAllFunctions, :fetch_test!, 2)
      assert function_exported?(ContextWithAllFunctions, :first_test!, 0)
      assert function_exported?(ContextWithAllFunctions, :first_test!, 1)
      assert function_exported?(ContextWithAllFunctions, :last_test!, 0)
      assert function_exported?(ContextWithAllFunctions, :last_test!, 1)
      assert function_exported?(ContextWithAllFunctions, :create_test!, 1)
      assert function_exported?(ContextWithAllFunctions, :create_test!, 2)
      assert function_exported?(ContextWithAllFunctions, :update_test!, 2)
      assert function_exported?(ContextWithAllFunctions, :update_test!, 3)
      assert function_exported?(ContextWithAllFunctions, :delete_test!, 1)
      assert function_exported?(ContextWithAllFunctions, :delete_test!, 2)
    end

    test "generates shared helper functions" do
      assert function_exported?(ContextWithAllFunctions, :__apply_crud_filters__, 2)
      assert function_exported?(ContextWithAllFunctions, :__apply_crud_query_opts__, 2)
      assert function_exported?(ContextWithAllFunctions, :__preload_crud_records__, 3)
      assert function_exported?(ContextWithAllFunctions, :__reverse_crud_order__, 1)
    end
  end

  describe "crud macro with :only option" do
    defmodule LimitedSchema do
      use Ecto.Schema

      schema "limited_table" do
        field :name, :string
      end
    end

    defmodule ContextWithOnlyOption do
      use OmCrud.Context

      crud LimitedSchema, as: :limited, only: [:create, :fetch]
    end

    test "generates only specified functions" do
      assert function_exported?(ContextWithOnlyOption, :fetch_limited, 1)
      assert function_exported?(ContextWithOnlyOption, :create_limited, 1)
    end

    test "does not generate excluded functions" do
      refute function_exported?(ContextWithOnlyOption, :update_limited, 2)
      refute function_exported?(ContextWithOnlyOption, :delete_limited, 1)
      refute function_exported?(ContextWithOnlyOption, :list_limiteds, 0)
    end
  end

  describe "crud macro with :except option" do
    defmodule ExceptSchema do
      use Ecto.Schema

      schema "except_table" do
        field :name, :string
      end
    end

    defmodule ContextWithExceptOption do
      use OmCrud.Context

      crud ExceptSchema, as: :item, except: [:delete, :delete_all]
    end

    test "generates functions not in except list" do
      assert function_exported?(ContextWithExceptOption, :fetch_item, 1)
      assert function_exported?(ContextWithExceptOption, :create_item, 1)
      assert function_exported?(ContextWithExceptOption, :update_item, 2)
    end

    test "does not generate excepted functions" do
      refute function_exported?(ContextWithExceptOption, :delete_item, 1)
      refute function_exported?(ContextWithExceptOption, :delete_all_items, 1)
    end
  end
end
