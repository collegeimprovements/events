defmodule Events.Decorator.Testing.Helpers do
  @moduledoc """
  Shared utilities for testing decorators.
  """

  @doc """
  Loads fixtures for tests.
  """
  def load_fixtures(fixture_names) do
    quote do
      unquote(fixture_names)
      |> Enum.map(fn name ->
        cond do
          # Try to load from Fixtures module
          Code.ensure_loaded?(Fixtures) and function_exported?(Fixtures, name, 0) ->
            {name, apply(Fixtures, name, [])}

          # Try process dictionary
          value = Process.get(name) ->
            {name, value}

          # Try ExUnit context
          true ->
            {name, nil}
        end
      end)
      |> Map.new()
    end
  end

  @doc """
  Cleans up fixtures after test.
  """
  def cleanup_fixtures(fixture_names) do
    quote do
      if Code.ensure_loaded?(Fixtures) and function_exported?(Fixtures, :cleanup, 1) do
        Enum.each(unquote(fixture_names), fn name ->
          Fixtures.cleanup(name)
        end)
      end
    end
  end

  @doc """
  Generates sample data using a generator.
  """
  def generate_data(generator) do
    quote do
      case unquote(generator) do
        gen when is_function(gen, 0) ->
          gen.()

        gen when is_function(gen, 1) ->
          gen.(1)

        module when is_atom(module) ->
          if function_exported?(module, :build, 0) do
            module.build()
          else
            raise "Generator module #{inspect(module)} must implement build/0"
          end
      end
    end
  end

  @doc """
  Sets up property test generators.
  """
  def setup_generators(generators, context) do
    # Map argument names to generators
    arg_names =
      Enum.map(context.args, fn
        {name, _, _} -> name
        _ -> :arg
      end)

    Enum.zip(arg_names, generators)
    |> Map.new()
  end

  @doc """
  Validates that a test assertion passed.
  """
  def assert_test(condition, message \\ "Assertion failed") do
    quote do
      unless unquote(condition) do
        raise ExUnit.AssertionError, message: unquote(message)
      end
    end
  end
end
