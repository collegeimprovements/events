defmodule Events.Decorators.Purity do
  @moduledoc """
  Function purity and determinism decorators.

  Marks and verifies function purity, determinism, and idempotence.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate pure()
        def calculate(x, y) do
          # Pure function - no side effects
          x + y
        end

        @decorate deterministic()
        def process(input) do
          # Always returns same output for same input
        end

        @decorate idempotent()
        def update_status(id, status) do
          # Can be called multiple times safely
        end

        @decorate memoizable(ttl: 60_000)
        def expensive_calculation(n) do
          # Safe to cache results
        end
      end
  """

  @doc """
  Marks function as pure (no side effects).

  ## Options

  - `:verify` - Verify purity at runtime
  - `:strict` - Strict purity checking
  """
  defmacro pure(opts \\ []) do
    quote do
      use Decorator.Define, pure: 1
      unquote(opts)
    end
  end

  @doc """
  Marks function as deterministic.

  Same input always produces same output.

  ## Options

  - `:verify` - Verify determinism with test runs
  - `:samples` - Number of verification samples
  """
  defmacro deterministic(opts \\ []) do
    quote do
      use Decorator.Define, deterministic: 1
      unquote(opts)
    end
  end

  @doc """
  Marks function as idempotent.

  Multiple calls have same effect as single call.

  ## Options

  - `:verify` - Verify idempotence
  - `:key` - Idempotence key
  """
  defmacro idempotent(opts \\ []) do
    quote do
      use Decorator.Define, idempotent: 1
      unquote(opts)
    end
  end

  @doc """
  Marks function as safe to memoize.

  ## Options

  - `:ttl` - Memoization time to live
  - `:cache` - Cache to use for memoization
  - `:auto` - Automatically memoize
  """
  defmacro memoizable(opts \\ []) do
    quote do
      use Decorator.Define, memoizable: 1
      unquote(opts)
    end
  end

  @doc """
  Marks function as referentially transparent.

  ## Options

  - `:verify` - Verify referential transparency
  """
  defmacro referentially_transparent(opts \\ []) do
    quote do
      use Decorator.Define, referentially_transparent: 1
      unquote(opts)
    end
  end
end