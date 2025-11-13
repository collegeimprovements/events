defmodule Events.Decorators.Testing do
  @moduledoc """
  Testing support decorators.

  Provides fixtures, mocking, test data generation, and test-specific behaviors.

  ## Usage

      defmodule MyModuleTest do
        use ExUnit.Case
        use Events.Decorator

        @decorate with_fixtures([:user, :account])
        test "user operations" do
          # Fixtures automatically loaded
        end

        @decorate sample_data(count: 100)
        test "bulk operations" do
          # Test data generated
        end

        @decorate timeout_test(5000)
        test "long running test" do
          # Test timeout enforced
        end

        @decorate mock(module: External.API, fun: :call)
        test "external integration" do
          # External call mocked
        end
      end
  """

  @doc """
  Automatically loads test fixtures.

  ## Options

  - `:fixtures` - List of fixture names to load
  - `:path` - Fixture file path
  - `:format` - Fixture format (:json, :yaml, :exs)
  """
  defmacro with_fixtures(fixtures, opts \\ []) do
    quote do
      use Decorator.Define, with_fixtures: 2
      unquote(fixtures)
      unquote(opts)
    end
  end

  @doc """
  Generates sample test data.

  ## Options

  - `:count` - Number of samples to generate
  - `:generator` - Data generator module
  - `:schema` - Data schema for generation
  """
  defmacro sample_data(opts) do
    quote do
      use Decorator.Define, sample_data: 1
      unquote(opts)
    end
  end

  @doc """
  Enforces test timeout.

  ## Options

  - `:timeout` - Timeout in milliseconds (required)
  - `:on_timeout` - Action on timeout (:fail, :skip)
  """
  defmacro timeout_test(timeout_ms, opts \\ []) do
    quote do
      use Decorator.Define, timeout_test: 2
      unquote(timeout_ms)
      unquote(opts)
    end
  end

  @doc """
  Mocks external dependencies.

  ## Options

  - `:module` - Module to mock (required)
  - `:fun` - Function to mock
  - `:with` - Mock implementation
  - `:return` - Return value
  """
  defmacro mock(opts) do
    quote do
      use Decorator.Define, mock: 1
      unquote(opts)
    end
  end

  @doc """
  Property-based testing decorator.

  ## Options

  - `:property` - Property to test
  - `:generators` - Input generators
  - `:runs` - Number of test runs
  """
  defmacro property(opts) do
    quote do
      use Decorator.Define, property: 1
      unquote(opts)
    end
  end

  @doc """
  Snapshot testing decorator.

  ## Options

  - `:name` - Snapshot name
  - `:path` - Snapshot file path
  - `:update` - Update snapshots
  """
  defmacro snapshot(opts \\ []) do
    quote do
      use Decorator.Define, snapshot: 1
      unquote(opts)
    end
  end
end