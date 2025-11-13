defmodule Events.Decorators.Validation do
  @moduledoc """
  Validation and contract decorators.

  Provides runtime validation of function inputs, outputs,
  and invariants.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate validate_args(schema: %{id: :integer, name: :string})
        def create_user(id, name) do
          # Validates arguments match schema
        end

        @decorate validate_result(fn result -> is_map(result) end)
        def fetch_data do
          # Validates result matches predicate
        end

        @decorate ensure(pre: fn x -> x > 0 end, post: fn _, r -> r > 0 end)
        def calculate(x) do
          # Ensures pre and post conditions
        end
      end
  """

  @doc """
  Validates function arguments.

  ## Options

  - `:schema` - Argument schema map
  - `:validator` - Custom validator function
  - `:on_invalid` - Action on invalid args (:error, :raise, :log)
  """
  defmacro validate_args(opts) do
    quote do
      use Decorator.Define, validate_args: 1
      unquote(opts)
    end
  end

  @doc """
  Validates function result.

  ## Options

  - `:validator` - Validation function (required)
  - `:on_invalid` - Action on invalid result
  - `:message` - Custom error message
  """
  defmacro validate_result(validator, opts \\ []) do
    quote do
      use Decorator.Define, validate_result: 2
      unquote(validator)
      unquote(opts)
    end
  end

  @doc """
  Ensures pre and post conditions.

  ## Options

  - `:pre` - Precondition function
  - `:post` - Postcondition function
  - `:invariant` - Invariant to maintain
  """
  defmacro ensure(opts) do
    quote do
      use Decorator.Define, ensure: 1
      unquote(opts)
    end
  end

  @doc """
  Validates against a contract.

  ## Options

  - `:contract` - Contract module
  - `:strict` - Strict contract enforcement
  """
  defmacro contract(contract_module, opts \\ []) do
    quote do
      use Decorator.Define, contract: 2
      unquote(contract_module)
      unquote(opts)
    end
  end

  @doc """
  Type checking decorator.

  ## Options

  - `:args` - Argument types
  - `:return` - Return type
  - `:runtime` - Enable runtime type checking
  """
  defmacro typed(opts) do
    quote do
      use Decorator.Define, typed: 1
      unquote(opts)
    end
  end
end
