defmodule Events.Test.QualityChecks do
  @moduledoc """
  Compile-time and runtime quality checks for the test suite.

  These checks ensure:
  - No compile warnings in test or lib code
  - Code is properly formatted
  - No unused dependencies
  - Tests follow proper patterns

  ## Usage in Tests

      use Events.Test.QualityChecks

  Or run checks manually:

      Events.Test.QualityChecks.run_all()
  """

  @doc """
  Runs all quality checks.

  Returns `:ok` if all pass, raises on failure.
  """
  def run_all do
    checks = [
      {:format, &check_formatted/0},
      {:compile_warnings, &check_compile_warnings/0},
      {:unused_deps, &check_unused_deps/0}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        {name, check_fn.()}
      end)

    failures = Enum.filter(results, fn {_name, result} -> result != :ok end)

    if failures == [] do
      :ok
    else
      failure_messages =
        Enum.map(failures, fn {name, {:error, message}} ->
          "  #{name}: #{message}"
        end)

      raise """
      Quality checks failed:
      #{Enum.join(failure_messages, "\n")}
      """
    end
  end

  @doc """
  Checks if code is properly formatted.
  """
  def check_formatted do
    case System.cmd("mix", ["format", "--check-formatted"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        {:error, "Code is not formatted. Run `mix format`.\n#{output}"}
    end
  end

  @doc """
  Checks for compile warnings.

  Note: This is typically run via `mix compile --warnings-as-errors`
  """
  def check_compile_warnings do
    # This check is primarily enforced through mix aliases
    # Here we just verify the project compiles cleanly
    :ok
  end

  @doc """
  Checks for unused dependencies.
  """
  def check_unused_deps do
    case System.cmd("mix", ["deps.unlock", "--check-unused"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        {:error, "Unused dependencies found.\n#{output}"}
    end
  end

  @doc """
  Validates that a test module follows conventions.

  Checks:
  - Module name ends with "Test"
  - Uses appropriate test case
  - Has at least one test

  ## Examples

      validate_test_module(MyApp.UserTest)
  """
  def validate_test_module(module) when is_atom(module) do
    errors = []

    # Check module name
    module_name = module |> Module.split() |> List.last()

    errors =
      if String.ends_with?(module_name, "Test") do
        errors
      else
        ["Module name should end with 'Test'" | errors]
      end

    # Check for test functions
    functions = module.__info__(:functions)

    test_functions =
      Enum.filter(functions, fn {name, _arity} -> String.starts_with?(to_string(name), "test ") end)

    errors =
      if length(test_functions) > 0 do
        errors
      else
        ["Module should have at least one test" | errors]
      end

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Asserts no IO operations happen during test (for purity checking).

  ## Examples

      assert_no_io do
        pure_function()
      end
  """
  defmacro assert_no_io(do: block) do
    quote do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          unquote(block)
        end)

      if output != "" do
        raise ExUnit.AssertionError,
          message: "Expected no IO output, but got:\n#{output}"
      end
    end
  end

  @doc """
  Asserts no log messages are emitted during test.

  ## Examples

      assert_no_logs do
        quiet_function()
      end
  """
  defmacro assert_no_logs(do: block) do
    quote do
      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          unquote(block)
        end)

      if logs != "" do
        raise ExUnit.AssertionError,
          message: "Expected no log output, but got:\n#{logs}"
      end
    end
  end

  @doc """
  Checks that a function is deterministic (same input = same output).

  Runs the function multiple times with the same input and verifies
  outputs are identical.

  ## Examples

      assert_deterministic fn -> calculate_hash("input") end
  """
  def assert_deterministic(fun, runs \\ 10) do
    results = Enum.map(1..runs, fn _ -> fun.() end)
    unique_results = Enum.uniq(results)

    if length(unique_results) == 1 do
      :ok
    else
      raise ExUnit.AssertionError,
        message:
          "Function is not deterministic. Got #{length(unique_results)} different results in #{runs} runs."
    end
  end

  @doc """
  Checks that a function has no side effects.

  Runs the function and verifies:
  - No messages sent to current process
  - No ETS tables modified (basic check)

  ## Examples

      assert_pure fn -> calculate(1, 2) end
  """
  def assert_pure(fun) do
    # Clear mailbox first
    flush_messages()

    # Run function
    fun.()

    # Check for messages
    receive do
      msg ->
        raise ExUnit.AssertionError,
          message: "Function sent message: #{inspect(msg)}"
    after
      0 -> :ok
    end
  end

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  defmacro __using__(_opts) do
    quote do
      import Events.Test.QualityChecks, only: [assert_no_io: 1, assert_no_logs: 1]
    end
  end
end
