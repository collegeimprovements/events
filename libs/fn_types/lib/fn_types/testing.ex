defmodule FnTypes.Testing do
  @moduledoc """
  Testing utilities for Result, Maybe, Pipeline, and other functional types.

  Provides ExUnit assertions and helpers specifically designed for testing
  code that uses FnTypes patterns.

  ## Usage

  Add to your test file or test_helper.exs:

      import FnTypes.Testing

  ## Assertions

  | Function | Use Case |
  |----------|----------|
  | `assert_ok/1` | Assert {:ok, value} and return value |
  | `assert_ok/2` | Assert {:ok, expected_value} |
  | `assert_error/1` | Assert {:error, reason} and return reason |
  | `assert_error/2` | Assert {:error, expected_reason} |
  | `assert_error_type/2` | Assert error matches a type/pattern |
  | `assert_just/1` | Assert {:just, value} (Maybe) |
  | `assert_nothing/1` | Assert :nothing (Maybe) |
  | `assert_pipeline_ok/1` | Assert pipeline succeeded |
  | `assert_pipeline_error/2` | Assert pipeline failed at step |

  ## Examples

      test "creates user successfully" do
        user = assert_ok(Accounts.create_user(%{email: "test@example.com"}))
        assert user.email == "test@example.com"
      end

      test "fails with invalid email" do
        changeset = assert_error(Accounts.create_user(%{email: "invalid"}))
        assert "is invalid" in errors_on(changeset).email
      end

      test "fails with not_found" do
        assert_error(:not_found, Accounts.get_user("nonexistent"))
      end

  ## Pattern Matching Assertions

      test "error has expected structure" do
        error = assert_error(operation())
        assert_error_type(:validation, error)
        assert_error_type(%FnTypes.Error{type: :validation}, error)
      end

  ## Pipeline Testing

      test "pipeline completes successfully" do
        ctx = assert_pipeline_ok(
          Pipeline.new(%{user_id: 123})
          |> Pipeline.step(:fetch, &fetch_user/1)
          |> Pipeline.step(:validate, &validate/1)
          |> Pipeline.run()
        )
        assert ctx.user != nil
      end

      test "pipeline fails at validation step" do
        assert_pipeline_error(:validate,
          Pipeline.new(%{user_id: 123})
          |> Pipeline.step(:fetch, &fetch_user/1)
          |> Pipeline.step(:validate, fn _ -> {:error, :invalid} end)
          |> Pipeline.run()
        )
      end
  """

  @doc """
  Imports all testing assertions.

  ## Usage

      defmodule MyTest do
        use ExUnit.Case
        import FnTypes.Testing
      end
  """
  defmacro __using__(_opts) do
    quote do
      import FnTypes.Testing
    end
  end

  # ============================================
  # Result Assertions
  # ============================================

  @doc """
  Asserts the result is `{:ok, value}` and returns the value.

  ## Examples

      user = assert_ok(Accounts.create_user(attrs))
      assert user.email == "test@example.com"
  """
  defmacro assert_ok(result) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          value

        {:error, reason} ->
          flunk("Expected {:ok, _}, got {:error, #{inspect(reason)}}")

        other ->
          flunk("Expected {:ok, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is `{:ok, expected_value}`.

  ## Examples

      assert_ok(42, compute_value())
      assert_ok(%{id: 123}, get_user())
  """
  defmacro assert_ok(expected, result) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          assert value == unquote(expected),
                 "Expected {:ok, #{inspect(unquote(expected))}}, got {:ok, #{inspect(value)}}"

          value

        {:error, reason} ->
          flunk("Expected {:ok, #{inspect(unquote(expected))}}, got {:error, #{inspect(reason)}}")

        other ->
          flunk("Expected {:ok, #{inspect(unquote(expected))}}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is `{:error, reason}` and returns the reason.

  ## Examples

      changeset = assert_error(Accounts.create_user(%{email: "invalid"}))
      assert changeset.errors[:email] != nil

      reason = assert_error(operation())
      assert reason == :not_found
  """
  defmacro assert_error(result) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          reason

        {:ok, value} ->
          flunk("Expected {:error, _}, got {:ok, #{inspect(value)}}")

        other ->
          flunk("Expected {:error, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is `{:error, expected_reason}`.

  ## Examples

      assert_error(:not_found, get_user("nonexistent"))
      assert_error(:unauthorized, protected_action())
  """
  defmacro assert_error(expected, result) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          assert reason == unquote(expected),
                 "Expected {:error, #{inspect(unquote(expected))}}, got {:error, #{inspect(reason)}}"

          reason

        {:ok, value} ->
          flunk("Expected {:error, #{inspect(unquote(expected))}}, got {:ok, #{inspect(value)}}")

        other ->
          flunk("Expected {:error, #{inspect(unquote(expected))}}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the error matches a type or pattern.

  Supports:
  - Atoms: `assert_error_type(:validation, result)`
  - FnTypes.Error type field: `assert_error_type(:not_found, result)`
  - Struct patterns: `assert_error_type(%FnTypes.Error{type: :validation}, result)`

  ## Examples

      # Match error atom
      assert_error_type(:not_found, {:error, :not_found})

      # Match FnTypes.Error type
      result = {:error, FnTypes.Error.new(:validation, :invalid_email)}
      assert_error_type(:validation, result)

      # Match struct pattern
      assert_error_type(%FnTypes.Error{code: :invalid_email}, result)
  """
  defmacro assert_error_type(expected_type, result) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          matches =
            case {unquote(expected_type), reason} do
              # Direct atom match
              {type, type} when is_atom(type) ->
                true

              # FnTypes.Error type field match
              {type, %FnTypes.Error{type: error_type}} when is_atom(type) ->
                type == error_type

              # Struct pattern match
              {%{__struct__: _} = pattern, %{__struct__: _} = error} ->
                match_struct_pattern?(pattern, error)

              # Tuple error type match
              {type, {error_type, _, _}} when is_atom(type) ->
                type == error_type

              {type, {error_type, _}} when is_atom(type) ->
                type == error_type

              _ ->
                false
            end

          unless matches do
            flunk(
              "Expected error type #{inspect(unquote(expected_type))}, got #{inspect(reason)}"
            )
          end

          reason

        {:ok, value} ->
          flunk(
            "Expected {:error, _} with type #{inspect(unquote(expected_type))}, got {:ok, #{inspect(value)}}"
          )

        other ->
          flunk(
            "Expected {:error, _} with type #{inspect(unquote(expected_type))}, got #{inspect(other)}"
          )
      end
    end
  end

  @doc false
  def match_struct_pattern?(pattern, error) when is_struct(pattern) and is_struct(error) do
    pattern
    |> Map.from_struct()
    |> Enum.all?(fn {key, value} ->
      case value do
        nil -> true
        expected -> Map.get(error, key) == expected
      end
    end)
  end

  def match_struct_pattern?(_, _), do: false

  @doc """
  Asserts the result is ok and the value matches a pattern.

  ## Examples

      assert_ok_match(%User{email: "test@example.com"}, create_user())
      assert_ok_match(%{status: :active}, get_account())
  """
  defmacro assert_ok_match(pattern, result) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          assert match?(unquote(pattern), value),
                 "Expected {:ok, #{unquote(Macro.to_string(pattern))}}, got {:ok, #{inspect(value)}}"

          value

        {:error, reason} ->
          flunk(
            "Expected {:ok, #{unquote(Macro.to_string(pattern))}}, got {:error, #{inspect(reason)}}"
          )

        other ->
          flunk("Expected {:ok, #{unquote(Macro.to_string(pattern))}}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is error and the reason matches a pattern.

  ## Examples

      assert_error_match({:validation, _, _}, validate_user())
      assert_error_match(%Ecto.Changeset{valid?: false}, create_user())
  """
  defmacro assert_error_match(pattern, result) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          assert match?(unquote(pattern), reason),
                 "Expected {:error, #{unquote(Macro.to_string(pattern))}}, got {:error, #{inspect(reason)}}"

          reason

        {:ok, value} ->
          flunk(
            "Expected {:error, #{unquote(Macro.to_string(pattern))}}, got {:ok, #{inspect(value)}}"
          )

        other ->
          flunk("Expected {:error, #{unquote(Macro.to_string(pattern))}}, got #{inspect(other)}")
      end
    end
  end

  # ============================================
  # Maybe Assertions
  # ============================================

  @doc """
  Asserts the maybe is `{:just, value}` and returns the value.

  ## Examples

      user = assert_just(find_user(id))
      assert user.active?
  """
  defmacro assert_just(maybe) do
    quote do
      case unquote(maybe) do
        {:just, value} ->
          value

        :nothing ->
          flunk("Expected {:just, _}, got :nothing")

        other ->
          flunk("Expected {:just, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the maybe is `:nothing`.

  ## Examples

      assert_nothing(find_deleted_user(id))
  """
  defmacro assert_nothing(maybe) do
    quote do
      case unquote(maybe) do
        :nothing ->
          :nothing

        {:just, value} ->
          flunk("Expected :nothing, got {:just, #{inspect(value)}}")

        other ->
          flunk("Expected :nothing, got #{inspect(other)}")
      end
    end
  end

  # ============================================
  # Pipeline Assertions
  # ============================================

  @doc """
  Asserts a pipeline result is ok and returns the context.

  ## Examples

      ctx = assert_pipeline_ok(
        Pipeline.new(%{id: 123})
        |> Pipeline.step(:fetch, &fetch/1)
        |> Pipeline.run()
      )
      assert ctx.user != nil
  """
  defmacro assert_pipeline_ok(result) do
    quote do
      case unquote(result) do
        {:ok, ctx} when is_map(ctx) ->
          ctx

        {:error, {:step_failed, step, reason}} ->
          flunk("Expected pipeline success, failed at step :#{step} with: #{inspect(reason)}")

        {:error, reason} ->
          flunk("Expected pipeline success, got error: #{inspect(reason)}")

        other ->
          flunk("Expected {:ok, context}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts a pipeline failed at a specific step.

  ## Examples

      assert_pipeline_error(:validate, pipeline_result)
      assert_pipeline_error(:fetch, Pipeline.run(pipeline))
  """
  defmacro assert_pipeline_error(expected_step, result) do
    quote do
      case unquote(result) do
        {:error, {:step_failed, step, reason}} ->
          assert step == unquote(expected_step),
                 "Expected pipeline to fail at :#{unquote(expected_step)}, failed at :#{step}"

          reason

        {:ok, ctx} ->
          flunk(
            "Expected pipeline to fail at :#{unquote(expected_step)}, but it succeeded with: #{inspect(ctx)}"
          )

        {:error, reason} ->
          flunk(
            "Expected pipeline to fail at :#{unquote(expected_step)}, got plain error: #{inspect(reason)}"
          )

        other ->
          flunk(
            "Expected pipeline to fail at :#{unquote(expected_step)}, got: #{inspect(other)}"
          )
      end
    end
  end

  @doc """
  Asserts a pipeline failed at a specific step with a specific reason.

  ## Examples

      assert_pipeline_error(:validate, :invalid_email, pipeline_result)
  """
  defmacro assert_pipeline_error(expected_step, expected_reason, result) do
    quote do
      case unquote(result) do
        {:error, {:step_failed, step, reason}} ->
          assert step == unquote(expected_step),
                 "Expected pipeline to fail at :#{unquote(expected_step)}, failed at :#{step}"

          assert reason == unquote(expected_reason),
                 "Expected failure reason #{inspect(unquote(expected_reason))}, got #{inspect(reason)}"

          reason

        {:ok, ctx} ->
          flunk(
            "Expected pipeline to fail at :#{unquote(expected_step)}, but it succeeded"
          )

        other ->
          flunk(
            "Expected pipeline to fail at :#{unquote(expected_step)}, got: #{inspect(other)}"
          )
      end
    end
  end

  # ============================================
  # Collection Assertions
  # ============================================

  @doc """
  Asserts all results in a list are ok and returns the values.

  ## Examples

      users = assert_all_ok([
        create_user(%{email: "a@test.com"}),
        create_user(%{email: "b@test.com"})
      ])
      assert length(users) == 2
  """
  defmacro assert_all_ok(results) do
    quote do
      unquote(results)
      |> Enum.with_index()
      |> Enum.map(fn {result, index} ->
        case result do
          {:ok, value} ->
            value

          {:error, reason} ->
            flunk("Expected all results to be ok, but result at index #{index} was {:error, #{inspect(reason)}}")

          other ->
            flunk("Expected all results to be ok, but result at index #{index} was #{inspect(other)}")
        end
      end)
    end
  end

  @doc """
  Asserts that at least one result in a list is an error.

  ## Examples

      assert_any_error([
        {:ok, 1},
        {:error, :failed},
        {:ok, 3}
      ])
  """
  defmacro assert_any_error(results) do
    quote do
      has_error =
        Enum.any?(unquote(results), fn
          {:error, _} -> true
          _ -> false
        end)

      unless has_error do
        flunk("Expected at least one error in results, but all were ok")
      end

      unquote(results)
    end
  end

  # ============================================
  # Helpers
  # ============================================

  @doc """
  Extracts ok values from a list of results, ignoring errors.

  Useful for setup in tests.

  ## Examples

      users = ok_values([
        create_user(%{email: "a@test.com"}),
        {:error, :duplicate},
        create_user(%{email: "b@test.com"})
      ])
      # => [user_a, user_b]
  """
  def ok_values(results) when is_list(results) do
    Enum.flat_map(results, fn
      {:ok, value} -> [value]
      _ -> []
    end)
  end

  @doc """
  Extracts error reasons from a list of results, ignoring successes.

  ## Examples

      errors = error_reasons([
        {:ok, 1},
        {:error, :failed},
        {:error, :timeout}
      ])
      # => [:failed, :timeout]
  """
  def error_reasons(results) when is_list(results) do
    Enum.flat_map(results, fn
      {:error, reason} -> [reason]
      _ -> []
    end)
  end

  @doc """
  Wraps a value in {:ok, value}.

  Useful for test fixtures.

  ## Examples

      ok_result = wrap_ok(%User{id: 1, email: "test@example.com"})
      # => {:ok, %User{...}}
  """
  def wrap_ok(value), do: {:ok, value}

  @doc """
  Wraps a reason in {:error, reason}.

  Useful for test fixtures.

  ## Examples

      error_result = wrap_error(:not_found)
      # => {:error, :not_found}
  """
  def wrap_error(reason), do: {:error, reason}

  @doc """
  Creates a function that always returns {:ok, value}.

  Useful for mocking.

  ## Examples

      mock_fetch = always_ok(%User{id: 1})
      mock_fetch.() #=> {:ok, %User{id: 1}}
  """
  def always_ok(value), do: fn -> {:ok, value} end

  @doc """
  Creates a function that always returns {:error, reason}.

  Useful for mocking.

  ## Examples

      mock_fetch = always_error(:not_found)
      mock_fetch.() #=> {:error, :not_found}
  """
  def always_error(reason), do: fn -> {:error, reason} end

  @doc """
  Creates a function that returns ok the first N times, then error.

  Useful for testing retry logic.

  ## Examples

      # Succeeds first 2 times, then fails
      flaky = flaky_fn(2, {:ok, :value}, {:error, :exhausted})

      flaky.() #=> {:ok, :value}
      flaky.() #=> {:ok, :value}
      flaky.() #=> {:error, :exhausted}
  """
  def flaky_fn(success_count, ok_value, error_value) do
    counter = :counters.new(1, [:atomics])

    fn ->
      count = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      if count < success_count do
        ok_value
      else
        error_value
      end
    end
  end

  @doc """
  Creates a function that fails the first N times, then succeeds.

  Useful for testing retry logic.

  ## Examples

      # Fails first 2 times, then succeeds
      eventually_ok = eventually_ok_fn(2, {:ok, :success}, {:error, :temporary})

      eventually_ok.() #=> {:error, :temporary}
      eventually_ok.() #=> {:error, :temporary}
      eventually_ok.() #=> {:ok, :success}
  """
  def eventually_ok_fn(fail_count, ok_value, error_value) do
    counter = :counters.new(1, [:atomics])

    fn ->
      count = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      if count < fail_count do
        error_value
      else
        ok_value
      end
    end
  end
end
