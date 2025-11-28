defmodule Events.TestCase do
  @moduledoc """
  Base test case for unit tests that don't require database access.

  ## When to Use Which Test Case

  | Test Case              | Use For                                      |
  |------------------------|----------------------------------------------|
  | `Events.TestCase`      | Pure functions, modules without DB access    |
  | `Events.DataCase`      | Tests requiring database (contexts, schemas) |
  | `EventsWeb.ConnCase`   | Phoenix controllers, API endpoints           |

  ## Usage

      defmodule Events.MyModuleTest do
        use Events.TestCase, async: true

        test "pure function works" do
          assert MyModule.calculate(1, 2) == 3
        end
      end

  ## Features

  - Custom assertions (`assert_ok`, `assert_error`, etc.)
  - Test data factory (`build/2`, `build_list/3`)
  - Mimic for mocking external dependencies
  - Property-based testing with StreamData
  - Common helpers (`capture_log`, `eventually`, `with_env`)

  ## Test Tags

      @tag :slow        # Tests taking > 1 second
      @tag :external    # Tests calling external APIs
      @tag :integration # Full integration tests
      @tag :property    # Property-based tests
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Mocking support
      use Mimic

      # Custom assertions
      use Events.Test.Assertions

      # Test data factory
      import Events.Test.Factory

      # Property-based testing (exclude filter to avoid conflicts with Query DSL)
      use ExUnitProperties
      import StreamData, except: [filter: 2, filter: 3]

      # Common test helpers
      import Events.TestCase.Helpers
    end
  end

  setup _tags do
    :ok
  end

  defmodule Helpers do
    @moduledoc """
    Common test helper functions.
    """

    @doc """
    Transforms changeset errors into a map of messages.

    ## Examples

        assert %{email: ["can't be blank"]} = errors_on(changeset)
        assert "is invalid" in errors_on(changeset).status
    """
    def errors_on(changeset) do
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)
    end

    @doc """
    Captures log output during test execution.

    ## Examples

        logs = capture_log(fn ->
          Logger.info("Hello")
        end)
        assert logs =~ "Hello"
    """
    defdelegate capture_log(fun), to: ExUnit.CaptureLog

    @doc """
    Captures IO output during test execution.

    ## Examples

        output = capture_io(fn ->
          IO.puts("Hello")
        end)
        assert output =~ "Hello"
    """
    defdelegate capture_io(fun), to: ExUnit.CaptureIO

    @doc """
    Waits for a condition to be true, with timeout.

    ## Examples

        eventually(fn -> Agent.get(agent, & &1) == :done end)
    """
    def eventually(condition, opts \\ []) do
      timeout = Keyword.get(opts, :timeout, 1000)
      interval = Keyword.get(opts, :interval, 50)
      deadline = System.monotonic_time(:millisecond) + timeout

      do_eventually(condition, interval, deadline)
    end

    defp do_eventually(condition, interval, deadline) do
      if condition.() do
        :ok
      else
        if System.monotonic_time(:millisecond) >= deadline do
          raise ExUnit.AssertionError, message: "Condition not met within timeout"
        else
          Process.sleep(interval)
          do_eventually(condition, interval, deadline)
        end
      end
    end

    @doc """
    Creates a unique test-scoped atom.

    Useful for naming processes or registering test-specific resources.
    """
    def unique_atom(prefix \\ "test") do
      :"#{prefix}_#{:erlang.unique_integer([:positive])}"
    end

    @doc """
    Temporarily sets application env for the duration of the block.

    ## Examples

        with_env(:my_app, :key, "test_value", fn ->
          assert Application.get_env(:my_app, :key) == "test_value"
        end)
    """
    def with_env(app, key, value, fun) do
      old_value = Application.get_env(app, key)

      try do
        Application.put_env(app, key, value)
        fun.()
      after
        if old_value do
          Application.put_env(app, key, old_value)
        else
          Application.delete_env(app, key)
        end
      end
    end

    @doc """
    Asserts that a message is received within the timeout.

    Similar to `assert_receive` but returns the message for further assertions.
    """
    defmacro receive_message(pattern, timeout \\ 100) do
      quote do
        receive do
          unquote(pattern) = msg -> msg
        after
          unquote(timeout) ->
            raise ExUnit.AssertionError,
              message: "Expected to receive message matching #{unquote(Macro.to_string(pattern))}"
        end
      end
    end
  end
end
