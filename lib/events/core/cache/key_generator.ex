defmodule Events.Core.Cache.KeyGenerator do
  @moduledoc """
  Behaviour for generating cache keys from function arguments.

  This module provides a default implementation of cache key generation,
  but you can implement your own by creating a module that adopts this behaviour.

  ## Default Algorithm

  - `generate(_mod, _fun, [])` → `0` (no arguments)
  - `generate(_mod, _fun, [arg])` → `arg` (single argument used as key)
  - `generate(_mod, _fun, args)` → `:erlang.phash2(args)` (hash multiple arguments)

  ## Custom Key Generators

      defmodule MyApp.CustomKeyGenerator do
        @behaviour Events.Core.Cache.KeyGenerator

        @impl true
        def generate(mod, fun, args) do
          # Include module and function in key
          {mod, fun, :erlang.phash2(args)}
        end
      end

      # Use in cache configuration
      config :events, Events.Core.Cache,
        default_key_generator: MyApp.CustomKeyGenerator

  ## Important Notes

  - Only explicitly assigned variables are included in args
  - Ignored/underscored arguments are excluded
  - Pattern matches without assignment are excluded

  ## Examples

      # Only x and y included
      def my_function(x, _ignored, _, {_, _}, [_, _], %{a: a}, %{} = y)
      generate(Mod, :my_function, [x_value, y_value])

      # All args included
      def other_function(x, y, z)
      generate(Mod, :other_function, [x_value, y_value, z_value])
  """

  @doc """
  Generates a cache key from function arguments.

  ## Parameters

  - `module` - The module where the function is defined
  - `function` - The function name (atom)
  - `args` - List of argument values

  ## Returns

  A term that will be used as the cache key. Can be any Elixir term.
  """
  @callback generate(module :: module(), function :: atom(), args :: [term()]) :: term()

  @doc """
  Default key generation implementation.

  ## Examples

      iex> KeyGenerator.generate(MyMod, :func, [])
      0

      iex> KeyGenerator.generate(MyMod, :func, [123])
      123

      iex> KeyGenerator.generate(MyMod, :func, [1, 2, 3])
      # Returns phash2 of [1, 2, 3]
  """
  @spec generate(module(), atom(), [term()]) :: term()
  def generate(_mod, _fun, []), do: 0
  def generate(_mod, _fun, [arg]), do: arg
  def generate(_mod, _fun, args), do: :erlang.phash2(args)
end
