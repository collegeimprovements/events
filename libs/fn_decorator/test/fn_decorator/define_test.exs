defmodule FnDecorator.DefineTest do
  use ExUnit.Case, async: true

  # ============================================
  # Basic Usage Tests
  # ============================================

  describe "use FnDecorator" do
    defmodule BasicModule do
      use FnDecorator

      def simple_function(x) do
        x * 2
      end
    end

    test "enables decorator support in module" do
      # Module should compile and function should work
      assert BasicModule.simple_function(5) == 10
    end
  end

  # ============================================
  # Decorator Tests with returns_result
  # ============================================

  describe "returns_result decorator" do
    defmodule ReturnsResultModule do
      use FnDecorator

      # returns_result is documentation-only when validate is false (default)
      @decorate returns_result(ok: String.t(), error: :atom)
      def get_name(id) do
        if id > 0, do: {:ok, "User #{id}"}, else: {:error, :not_found}
      end
    end

    test "returns_result passes through result tuples" do
      assert {:ok, "User 1"} = ReturnsResultModule.get_name(1)
      assert {:error, :not_found} = ReturnsResultModule.get_name(-1)
    end
  end

  # ============================================
  # Pattern Matching with Decorators Tests
  # ============================================

  describe "decorators with pattern matching" do
    defmodule PatternMatchDecorators do
      use FnDecorator

      @decorate returns_result(ok: :atom, error: :atom)
      def handle(:ok), do: {:ok, :success}
      def handle(:error), do: {:error, :failure}
      def handle(other), do: {:ok, other}
    end

    test "decorators work with function clauses" do
      assert {:ok, :success} = PatternMatchDecorators.handle(:ok)
      assert {:error, :failure} = PatternMatchDecorators.handle(:error)
      assert {:ok, "other"} = PatternMatchDecorators.handle("other")
    end
  end

  # ============================================
  # Guard Clauses with Decorators Tests
  # ============================================

  describe "decorators with guards" do
    defmodule GuardDecorators do
      use FnDecorator

      @decorate returns_result(ok: :atom, error: :atom)
      def classify(x) when is_integer(x) and x > 0, do: {:ok, :positive}
      def classify(x) when is_integer(x) and x < 0, do: {:ok, :negative}
      def classify(0), do: {:ok, :zero}
      def classify(_), do: {:error, :unknown}
    end

    test "decorators work with guard clauses" do
      assert {:ok, :positive} = GuardDecorators.classify(5)
      assert {:ok, :negative} = GuardDecorators.classify(-5)
      assert {:ok, :zero} = GuardDecorators.classify(0)
      assert {:error, :unknown} = GuardDecorators.classify("not a number")
    end
  end

  # ============================================
  # Default Arguments Tests
  # ============================================

  describe "decorators with default arguments" do
    defmodule DefaultArgDecorators do
      use FnDecorator

      @decorate returns_result(ok: integer(), error: :atom)
      def with_defaults(x, multiplier \\ 2) do
        {:ok, x * multiplier}
      end
    end

    test "decorators work with default arguments" do
      assert {:ok, 10} = DefaultArgDecorators.with_defaults(5)
      assert {:ok, 15} = DefaultArgDecorators.with_defaults(5, 3)
    end
  end

  # ============================================
  # Keyword Arguments Tests
  # ============================================

  describe "decorators with keyword arguments" do
    defmodule KeywordArgDecorators do
      use FnDecorator

      @decorate returns_result(ok: integer(), error: :atom)
      def with_keywords(x, opts \\ []) do
        multiplier = Keyword.get(opts, :multiplier, 1)
        {:ok, x * multiplier}
      end
    end

    test "decorators work with keyword arguments" do
      assert {:ok, 5} = KeywordArgDecorators.with_keywords(5)
      assert {:ok, 15} = KeywordArgDecorators.with_keywords(5, multiplier: 3)
    end
  end

  # ============================================
  # Module Attributes in Decorated Functions
  # ============================================

  describe "module attributes with decorators" do
    defmodule AttributeDecorators do
      use FnDecorator

      @default_value 42

      @decorate returns_result(ok: integer(), error: :atom)
      def get_default do
        {:ok, @default_value}
      end
    end

    test "decorated functions can access module attributes" do
      assert {:ok, 42} = AttributeDecorators.get_default()
    end
  end

  # ============================================
  # Struct Creation in Decorated Functions
  # ============================================

  describe "struct creation with decorators" do
    defmodule User do
      defstruct [:id, :name]
    end

    defmodule StructDecorators do
      use FnDecorator

      @decorate returns_result(ok: FnDecorator.DefineTest.User, error: :atom)
      def create_user(id, name) do
        {:ok, %FnDecorator.DefineTest.User{id: id, name: name}}
      end
    end

    test "decorated functions can create structs" do
      {:ok, user} = StructDecorators.create_user(1, "Alice")
      assert user == %User{id: 1, name: "Alice"}
    end
  end

  # ============================================
  # Comprehensions in Decorated Functions
  # ============================================

  describe "comprehensions with decorators" do
    defmodule ComprehensionDecorators do
      use FnDecorator

      @decorate returns_result(ok: list(), error: :atom)
      def double_all(list) do
        {:ok, for(x <- list, do: x * 2)}
      end

      @decorate returns_result(ok: list(), error: :atom)
      def filter_and_double(list) do
        {:ok, for(x <- list, x > 0, do: x * 2)}
      end
    end

    test "decorated functions can use comprehensions" do
      assert {:ok, [2, 4, 6]} = ComprehensionDecorators.double_all([1, 2, 3])
      assert {:ok, [4, 6]} = ComprehensionDecorators.filter_and_double([-1, 2, 3])
    end
  end
end
