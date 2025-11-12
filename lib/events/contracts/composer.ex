defmodule Events.Contracts.Composer do
  @moduledoc """
  Base behaviour for composer modules.

  Composers are responsible for building complex data structures through
  chainable operations. They provide fluent APIs for constructing changesets,
  Ecto.Multi transactions, validation pipelines, etc.

  ## Design Principles

  - **Fluent API**: Chainable operations that return the composer struct
  - **Immutable**: Each operation returns a new composer instance
  - **Composable**: Can be combined with other composers
  - **Explicit Build**: Separate building from execution
  - **Type-Safe**: Use structs and typespecs

  ## Example

      defmodule MyApp.Composers.UserValidation do
        @behaviour Events.Contracts.Composer

        defstruct [:data, :rules, :errors]

        @impl true
        def new(data, opts \\\\ []) do
          %__MODULE__{
            data: data,
            rules: [],
            errors: []
          }
        end

        @impl true
        def compose(composer, operation) do
          # Apply operation and return new composer
        end

        @impl true
        def build(composer) do
          # Return the final built result
        end

        # Fluent API methods
        def validate_email(composer) do
          compose(composer, {:validate, :email})
        end

        def validate_length(composer, field, opts) do
          compose(composer, {:validate_length, field, opts})
        end
      end

      # Usage:
      UserValidation.new(%{email: "test@example.com"})
      |> UserValidation.validate_email()
      |> UserValidation.validate_length(:name, min: 3)
      |> UserValidation.build()
  """

  @doc """
  Creates a new composer instance with initial data and options.

  ## Parameters

  - `data` - Initial data to compose (changeset, schema, map, etc.)
  - `opts` - Optional configuration for the composer

  ## Returns

  A new composer struct instance.
  """
  @callback new(data :: term(), opts :: keyword()) :: struct()

  @doc """
  Applies a composition operation to the composer.

  This is the core method that handles all transformations. Each operation
  should return a new composer instance with the operation applied.

  ## Parameters

  - `composer` - The current composer struct
  - `operation` - The operation to apply (tuple describing the operation)

  ## Returns

  A new composer struct with the operation applied.
  """
  @callback compose(composer :: struct(), operation :: term()) :: struct()

  @doc """
  Builds the final result from the composer.

  This method converts the composer's accumulated state into the final
  output (changeset, Ecto.Multi, validation result, etc.).

  ## Parameters

  - `composer` - The composer struct to build

  ## Returns

  The built result (varies by composer type).
  """
  @callback build(composer :: struct()) :: term()

  @doc """
  Helper macro to define a fluent method on a composer.

  ## Example

      use Events.Contracts.Composer

      defcompose validate_email(composer, field) do
        compose(composer, {:validate, :email, field})
      end

      # Expands to:
      def validate_email(composer, field) do
        compose(composer, {:validate, :email, field})
      end
  """
  defmacro defcompose(call, do: block) do
    quote do
      def unquote(call) do
        unquote(block)
      end
    end
  end

  @doc """
  Helper to check if a module implements the Composer behaviour.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    :attributes
    |> module.__info__()
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(__MODULE__)
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Events.Contracts.Composer
      import Events.Contracts.Composer, only: [defcompose: 2]
    end
  end
end
