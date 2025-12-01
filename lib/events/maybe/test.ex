defmodule Events.Maybe.Test do
  @moduledoc """
  Testing utilities for Maybe types.

  Provides generators for property-based testing, assertions for
  ExUnit tests, and helper functions for testing Maybe-returning code.

  ## Usage in Tests

      defmodule MyModuleTest do
        use ExUnit.Case
        import Events.Maybe.Test

        test "find_user returns some for existing user" do
          result = MyModule.find_user(1)
          assert_some(result)
          assert_some(result, %User{id: 1})
        end

        test "find_user returns none for missing user" do
          result = MyModule.find_user(999)
          assert_none(result)
        end
      end

  ## Property-Based Testing

      use ExUnitProperties
      import Events.Maybe.Test

      property "map preserves structure" do
        check all maybe <- gen_maybe(integer()) do
          result = Maybe.map(maybe, &(&1 * 2))
          assert (Maybe.some?(maybe) and Maybe.some?(result)) or
                 (Maybe.none?(maybe) and Maybe.none?(result))
        end
      end
  """

  alias Events.Maybe

  # ============================================
  # Assertions
  # ============================================

  @doc """
  Asserts that a value is some.

  ## Examples

      assert_some({:some, 42})
      assert_some({:some, user}, %User{id: 1})
  """
  defmacro assert_some(maybe) do
    quote do
      case unquote(maybe) do
        {:some, _value} ->
          :ok

        :none ->
          raise ExUnit.AssertionError,
            message: "Expected {:some, _}, got :none"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:some, _}, got: #{inspect(other)}"
      end
    end
  end

  defmacro assert_some(maybe, expected_value) do
    quote do
      case unquote(maybe) do
        {:some, value} ->
          assert value == unquote(expected_value),
                 "Expected {:some, #{inspect(unquote(expected_value))}}, got {:some, #{inspect(value)}}"

        :none ->
          raise ExUnit.AssertionError,
            message: "Expected {:some, #{inspect(unquote(expected_value))}}, got :none"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:some, _}, got: #{inspect(other)}"
      end
    end
  end

  @doc """
  Asserts that a value is none.

  ## Examples

      assert_none(:none)
  """
  defmacro assert_none(maybe) do
    quote do
      case unquote(maybe) do
        :none ->
          :ok

        {:some, value} ->
          raise ExUnit.AssertionError,
            message: "Expected :none, got {:some, #{inspect(value)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected :none, got: #{inspect(other)}"
      end
    end
  end

  @doc """
  Asserts that a value is a valid Maybe type.

  ## Examples

      assert_maybe({:some, 42})
      assert_maybe(:none)
  """
  defmacro assert_maybe(value) do
    quote do
      case unquote(value) do
        {:some, _} ->
          :ok

        :none ->
          :ok

        other ->
          raise ExUnit.AssertionError,
            message: "Expected Maybe type ({:some, _} or :none), got: #{inspect(other)}"
      end
    end
  end

  @doc """
  Refutes that a value is some (expects none).

  ## Examples

      refute_some(:none)
  """
  defmacro refute_some(maybe) do
    quote do
      assert_none(unquote(maybe))
    end
  end

  @doc """
  Refutes that a value is none (expects some).

  ## Examples

      refute_none({:some, 42})
  """
  defmacro refute_none(maybe) do
    quote do
      assert_some(unquote(maybe))
    end
  end

  # ============================================
  # Generators (for StreamData / PropCheck)
  # Only compiled when StreamData is available
  # ============================================

  if Code.ensure_loaded?(StreamData) do
    @doc """
    Generates Maybe values wrapping the given generator.

    For use with StreamData property-based testing.

    ## Examples

        import StreamData

        # Generate Maybe integers
        gen_maybe(integer())

        # Generate Maybe strings
        gen_maybe(string(:alphanumeric))

        # With bias towards some values (default 70% some)
        gen_maybe(integer(), some_probability: 0.9)
    """
    @spec gen_maybe(StreamData.t(a), keyword()) :: StreamData.t(Maybe.t(a)) when a: term()
    def gen_maybe(value_gen, opts \\ []) do
      some_prob = Keyword.get(opts, :some_probability, 0.7)

      StreamData.frequency([
        {round(some_prob * 100), StreamData.map(value_gen, &{:some, &1})},
        {round((1 - some_prob) * 100), StreamData.constant(:none)}
      ])
    end

    @doc """
    Generates only some values.

    ## Examples

        gen_some(integer())
        #=> {:some, <integer>}
    """
    @spec gen_some(StreamData.t(a)) :: StreamData.t(Maybe.some(a)) when a: term()
    def gen_some(value_gen) do
      StreamData.map(value_gen, &{:some, &1})
    end

    @doc """
    Generates only none.

    ## Examples

        gen_none()
        #=> :none
    """
    @spec gen_none() :: StreamData.t(Maybe.nothing())
    def gen_none do
      StreamData.constant(:none)
    end

    @doc """
    Generates a list of Maybe values.

    ## Examples

        gen_maybe_list(integer(), min_length: 1, max_length: 10)
    """
    @spec gen_maybe_list(StreamData.t(a), keyword()) :: StreamData.t([Maybe.t(a)]) when a: term()
    def gen_maybe_list(value_gen, opts \\ []) do
      min_length = Keyword.get(opts, :min_length, 0)
      max_length = Keyword.get(opts, :max_length, 10)

      StreamData.list_of(gen_maybe(value_gen), min_length: min_length, max_length: max_length)
    end
  end

  # ============================================
  # Test Helpers
  # ============================================

  @doc """
  Creates a some value for testing.

  ## Examples

      some(42)
      #=> {:some, 42}
  """
  @spec some(term()) :: Maybe.some(term())
  def some(value), do: {:some, value}

  @doc """
  Returns none for testing.

  ## Examples

      none()
      #=> :none
  """
  @spec none() :: Maybe.nothing()
  def none, do: :none

  @doc """
  Unwraps a some value or raises in test context.

  ## Examples

      unwrap!({:some, 42})
      #=> 42
  """
  @spec unwrap!(Maybe.t(a)) :: a when a: term()
  def unwrap!({:some, value}), do: value
  def unwrap!(:none), do: raise(ExUnit.AssertionError, message: "Expected some, got none")

  @doc """
  Checks if two Maybe values are equal.

  ## Examples

      maybe_eq?({:some, 1}, {:some, 1})
      #=> true

      maybe_eq?(:none, :none)
      #=> true
  """
  @spec maybe_eq?(Maybe.t(a), Maybe.t(a)) :: boolean() when a: term()
  def maybe_eq?({:some, a}, {:some, b}), do: a == b
  def maybe_eq?(:none, :none), do: true
  def maybe_eq?(_, _), do: false

  @doc """
  Creates sample Maybe values for testing.

  ## Examples

      samples = sample_maybes()
      Enum.each(samples, fn maybe -> test_function(maybe) end)
  """
  @spec sample_maybes() :: [Maybe.t(term())]
  def sample_maybes do
    [
      :none,
      {:some, nil},
      {:some, 0},
      {:some, 1},
      {:some, ""},
      {:some, "hello"},
      {:some, []},
      {:some, [1, 2, 3]},
      {:some, %{}},
      {:some, %{key: "value"}}
    ]
  end

  @doc """
  Runs a function with both some and none inputs, returning results.

  Useful for verifying functions handle both cases correctly.

  ## Examples

      test_both_cases(
        fn maybe -> Maybe.map(maybe, &(&1 * 2)) end,
        some_value: 5
      )
      #=> %{some_result: {:some, 10}, none_result: :none}
  """
  @spec test_both_cases((Maybe.t(a) -> Maybe.t(b)), keyword()) :: map() when a: term(), b: term()
  def test_both_cases(fun, opts \\ []) do
    some_value = Keyword.get(opts, :some_value, 42)

    %{
      some_result: fun.({:some, some_value}),
      none_result: fun.(:none)
    }
  end
end
