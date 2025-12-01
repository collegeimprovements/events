defmodule Events.Types.Result.Test do
  @moduledoc """
  Testing utilities for Result types.

  Provides generators for property-based testing, assertions for
  ExUnit tests, and helper functions for testing Result-returning code.

  ## Usage in Tests

      defmodule MyModuleTest do
        use ExUnit.Case
        import Events.Types.Result.Test

        test "create_user returns ok for valid input" do
          result = MyModule.create_user(%{email: "test@example.com"})
          assert_ok(result)
          assert_ok(result, fn user -> user.email == "test@example.com" end)
        end

        test "create_user returns error for invalid input" do
          result = MyModule.create_user(%{})
          assert_error(result)
          assert_error(result, :validation_failed)
        end
      end

  ## Property-Based Testing

      use ExUnitProperties
      import Events.Types.Result.Test

      property "map preserves structure" do
        check all result <- gen_result(integer(), atom(:alphanumeric)) do
          mapped = Result.map(result, &(&1 * 2))
          assert (Result.ok?(result) and Result.ok?(mapped)) or
                 (Result.error?(result) and Result.error?(mapped))
        end
      end
  """

  alias Events.Types.Result

  # ============================================
  # Assertions
  # ============================================

  @doc """
  Asserts that a value is ok.

  Can optionally check the value matches expected or passes a predicate.

  ## Examples

      assert_ok({:ok, 42})
      assert_ok({:ok, user}, %User{id: 1})
      assert_ok({:ok, user}, fn u -> u.active? end)
  """
  defmacro assert_ok(result) do
    quote do
      case unquote(result) do
        {:ok, _value} ->
          :ok

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Expected {:ok, _}, got {:error, #{inspect(reason)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:ok, _}, got: #{inspect(other)}"
      end
    end
  end

  defmacro assert_ok(result, expected) when is_function(expected) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          pred = unquote(expected)

          unless pred.(value) do
            raise ExUnit.AssertionError,
              message: "Expected predicate to return true for value: #{inspect(value)}"
          end

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Expected {:ok, _}, got {:error, #{inspect(reason)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:ok, _}, got: #{inspect(other)}"
      end
    end
  end

  defmacro assert_ok(result, expected_value) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          assert value == unquote(expected_value),
                 "Expected {:ok, #{inspect(unquote(expected_value))}}, got {:ok, #{inspect(value)}}"

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message:
              "Expected {:ok, #{inspect(unquote(expected_value))}}, got {:error, #{inspect(reason)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:ok, _}, got: #{inspect(other)}"
      end
    end
  end

  @doc """
  Asserts that a value is error.

  Can optionally check the error reason matches expected.

  ## Examples

      assert_error({:error, :not_found})
      assert_error({:error, :not_found}, :not_found)
      assert_error({:error, %{field: _}}, fn err -> Map.has_key?(err, :field) end)
  """
  defmacro assert_error(result) do
    quote do
      case unquote(result) do
        {:error, _reason} ->
          :ok

        {:ok, value} ->
          raise ExUnit.AssertionError,
            message: "Expected {:error, _}, got {:ok, #{inspect(value)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:error, _}, got: #{inspect(other)}"
      end
    end
  end

  defmacro assert_error(result, expected) when is_function(expected) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          pred = unquote(expected)

          unless pred.(reason) do
            raise ExUnit.AssertionError,
              message: "Expected predicate to return true for error: #{inspect(reason)}"
          end

        {:ok, value} ->
          raise ExUnit.AssertionError,
            message: "Expected {:error, _}, got {:ok, #{inspect(value)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:error, _}, got: #{inspect(other)}"
      end
    end
  end

  defmacro assert_error(result, expected_reason) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          assert reason == unquote(expected_reason),
                 "Expected {:error, #{inspect(unquote(expected_reason))}}, got {:error, #{inspect(reason)}}"

        {:ok, value} ->
          raise ExUnit.AssertionError,
            message:
              "Expected {:error, #{inspect(unquote(expected_reason))}}, got {:ok, #{inspect(value)}}"

        other ->
          raise ExUnit.AssertionError,
            message: "Expected {:error, _}, got: #{inspect(other)}"
      end
    end
  end

  @doc """
  Asserts that a value is a valid Result type.

  ## Examples

      assert_result({:ok, 42})
      assert_result({:error, :bad})
  """
  defmacro assert_result(value) do
    quote do
      case unquote(value) do
        {:ok, _} ->
          :ok

        {:error, _} ->
          :ok

        other ->
          raise ExUnit.AssertionError,
            message: "Expected Result type ({:ok, _} or {:error, _}), got: #{inspect(other)}"
      end
    end
  end

  @doc """
  Refutes that a value is ok (expects error).
  """
  defmacro refute_ok(result) do
    quote do
      assert_error(unquote(result))
    end
  end

  @doc """
  Refutes that a value is error (expects ok).
  """
  defmacro refute_error(result) do
    quote do
      assert_ok(unquote(result))
    end
  end

  # ============================================
  # Generators (for StreamData / PropCheck)
  # Only compiled when StreamData is available
  # ============================================

  if Code.ensure_loaded?(StreamData) do
    @doc """
    Generates Result values wrapping the given generators.

    For use with StreamData property-based testing.

    ## Examples

        import StreamData

        # Generate Result with integer values and atom errors
        gen_result(integer(), atom(:alphanumeric))

        # With bias towards ok values (default 70% ok)
        gen_result(integer(), atom(:alphanumeric), ok_probability: 0.9)
    """
    @spec gen_result(StreamData.t(a), StreamData.t(e), keyword()) :: StreamData.t(Result.t(a, e))
          when a: term(), e: term()
    def gen_result(value_gen, error_gen, opts \\ []) do
      ok_prob = Keyword.get(opts, :ok_probability, 0.7)

      StreamData.frequency([
        {round(ok_prob * 100), StreamData.map(value_gen, &{:ok, &1})},
        {round((1 - ok_prob) * 100), StreamData.map(error_gen, &{:error, &1})}
      ])
    end

    @doc """
    Generates only ok values.

    ## Examples

        gen_ok(integer())
        #=> {:ok, <integer>}
    """
    @spec gen_ok(StreamData.t(a)) :: StreamData.t(Result.ok(a)) when a: term()
    def gen_ok(value_gen) do
      StreamData.map(value_gen, &{:ok, &1})
    end

    @doc """
    Generates only error values.

    ## Examples

        gen_error(atom(:alphanumeric))
        #=> {:error, <atom>}
    """
    @spec gen_error(StreamData.t(e)) :: StreamData.t(Result.error(e)) when e: term()
    def gen_error(error_gen) do
      StreamData.map(error_gen, &{:error, &1})
    end

    @doc """
    Generates a list of Result values.
    """
    @spec gen_result_list(StreamData.t(a), StreamData.t(e), keyword()) ::
            StreamData.t([Result.t(a, e)])
          when a: term(), e: term()
    def gen_result_list(value_gen, error_gen, opts \\ []) do
      min_length = Keyword.get(opts, :min_length, 0)
      max_length = Keyword.get(opts, :max_length, 10)

      StreamData.list_of(
        gen_result(value_gen, error_gen),
        min_length: min_length,
        max_length: max_length
      )
    end
  end

  # ============================================
  # Test Helpers
  # ============================================

  @doc """
  Creates an ok value for testing.

  ## Examples

      ok(42)
      #=> {:ok, 42}
  """
  @spec ok(term()) :: Result.ok(term())
  def ok(value), do: {:ok, value}

  @doc """
  Creates an error value for testing.

  ## Examples

      error(:not_found)
      #=> {:error, :not_found}
  """
  @spec error(term()) :: Result.error(term())
  def error(reason), do: {:error, reason}

  @doc """
  Unwraps an ok value or raises in test context.

  ## Examples

      unwrap!({:ok, 42})
      #=> 42
  """
  @spec unwrap!(Result.t(a, term())) :: a when a: term()
  def unwrap!({:ok, value}), do: value

  def unwrap!({:error, reason}),
    do: raise(ExUnit.AssertionError, message: "Expected ok, got error: #{inspect(reason)}")

  @doc """
  Unwraps an error reason or raises in test context.

  ## Examples

      unwrap_error!({:error, :not_found})
      #=> :not_found
  """
  @spec unwrap_error!(Result.t(term(), e)) :: e when e: term()
  def unwrap_error!({:error, reason}), do: reason

  def unwrap_error!({:ok, value}),
    do: raise(ExUnit.AssertionError, message: "Expected error, got ok: #{inspect(value)}")

  @doc """
  Checks if two Result values are equal.

  ## Examples

      result_eq?({:ok, 1}, {:ok, 1})
      #=> true

      result_eq?({:error, :a}, {:error, :a})
      #=> true
  """
  @spec result_eq?(Result.t(a, e), Result.t(a, e)) :: boolean() when a: term(), e: term()
  def result_eq?({:ok, a}, {:ok, b}), do: a == b
  def result_eq?({:error, a}, {:error, b}), do: a == b
  def result_eq?(_, _), do: false

  @doc """
  Creates sample Result values for testing.

  ## Examples

      samples = sample_results()
      Enum.each(samples, fn result -> test_function(result) end)
  """
  @spec sample_results() :: [Result.t(term(), term())]
  def sample_results do
    [
      {:ok, nil},
      {:ok, 0},
      {:ok, 1},
      {:ok, ""},
      {:ok, "hello"},
      {:ok, []},
      {:ok, [1, 2, 3]},
      {:ok, %{}},
      {:ok, %{key: "value"}},
      {:error, :not_found},
      {:error, :unauthorized},
      {:error, :validation_failed},
      {:error, "error message"},
      {:error, %{field: :email, message: "invalid"}}
    ]
  end

  @doc """
  Runs a function with both ok and error inputs, returning results.

  Useful for verifying functions handle both cases correctly.

  ## Examples

      test_both_cases(
        fn result -> Result.map(result, &(&1 * 2)) end,
        ok_value: 5,
        error_value: :bad
      )
      #=> %{ok_result: {:ok, 10}, error_result: {:error, :bad}}
  """
  @spec test_both_cases((Result.t(a, e) -> Result.t(b, e)), keyword()) :: map()
        when a: term(), b: term(), e: term()
  def test_both_cases(fun, opts \\ []) do
    ok_value = Keyword.get(opts, :ok_value, 42)
    error_value = Keyword.get(opts, :error_value, :error)

    %{
      ok_result: fun.({:ok, ok_value}),
      error_result: fun.({:error, error_value})
    }
  end

  @doc """
  Creates a stub function that returns ok.

  ## Examples

      stub = stub_ok(42)
      stub.() #=> {:ok, 42}
  """
  @spec stub_ok(term()) :: (-> Result.ok(term()))
  def stub_ok(value), do: fn -> {:ok, value} end

  @doc """
  Creates a stub function that returns error.

  ## Examples

      stub = stub_error(:not_found)
      stub.() #=> {:error, :not_found}
  """
  @spec stub_error(term()) :: (-> Result.error(term()))
  def stub_error(reason), do: fn -> {:error, reason} end

  @doc """
  Creates a stub that alternates between ok and error.

  Useful for testing retry logic.

  ## Examples

      stub = stub_alternating([{:error, :temp}, {:error, :temp}, {:ok, 42}])
      stub.() #=> {:error, :temp}
      stub.() #=> {:error, :temp}
      stub.() #=> {:ok, 42}
  """
  @spec stub_alternating([Result.t()]) :: (-> Result.t())
  def stub_alternating(results) when is_list(results) do
    agent = Agent.start_link(fn -> results end) |> elem(1)

    fn ->
      Agent.get_and_update(agent, fn
        [] -> {{:error, :stub_exhausted}, []}
        [h | t] -> {h, t}
      end)
    end
  end
end
