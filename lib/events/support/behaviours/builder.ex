defmodule Events.Support.Behaviours.Builder do
  @moduledoc """
  Base behaviour for builder modules.

  Builders are responsible for constructing complex data structures through
  chainable operations. They provide fluent APIs for building changesets,
  Ecto.Multi transactions, validation pipelines, etc.

  ## Design Principles

  - **Fluent API**: Chainable operations that return the builder struct
  - **Immutable**: Each operation returns a new builder instance
  - **Composable**: Can be combined with other builders
  - **Explicit Build**: Separate building from execution
  - **Type-Safe**: Use structs and typespecs

  ## Example

      defmodule MyApp.Builders.UserValidation do
        @behaviour Events.Support.Behaviours.Builder

        defstruct [:data, :rules, :errors]

        @impl true
        def new(data, opts \\ []) do
          %__MODULE__{
            data: data,
            rules: [],
            errors: []
          }
        end

        @impl true
        def compose(builder, operation) do
          # Apply operation and return new builder
        end

        @impl true
        def build(builder) do
          # Return the final built result
        end

        # Fluent API methods
        def validate_email(builder) do
          compose(builder, {:validate, :email})
        end

        def validate_length(builder, field, opts) do
          compose(builder, {:validate_length, field, opts})
        end
      end

      # Usage:
      UserValidation.new(%{email: "test@example.com"})
      |> UserValidation.validate_email()
      |> UserValidation.validate_length(:name, min: 3)
      |> UserValidation.build()
  """

  @doc """
  Creates a new builder instance with initial data and options.

  ## Parameters

  - `data` - Initial data to build with (changeset, schema, map, etc.)
  - `opts` - Optional configuration for the builder

  ## Returns

  A new builder struct instance.
  """
  @callback new(data :: term(), opts :: keyword()) :: struct()

  @doc """
  Applies a composition operation to the builder.

  This is the core method that handles all transformations. Each operation
  should return a new builder instance with the operation applied.

  ## Parameters

  - `builder` - The current builder struct
  - `operation` - The operation to apply (tuple describing the operation)

  ## Returns

  A new builder struct with the operation applied.
  """
  @callback compose(builder :: struct(), operation :: term()) :: struct()

  @doc """
  Builds the final result from the builder.

  This method converts the builder's accumulated state into the final
  output (changeset, Ecto.Multi, validation result, etc.).

  ## Parameters

  - `builder` - The builder struct to build

  ## Returns

  The built result (varies by builder type).
  """
  @callback build(builder :: struct()) :: term()

  @doc """
  Helper macro to define a fluent method on a builder.

  ## Example

      use Events.Support.Behaviours.Builder

      defcompose validate_email(builder, field) do
        compose(builder, {:validate, :email, field})
      end

      # Expands to:
      def validate_email(builder, field) do
        compose(builder, {:validate, :email, field})
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
  Helper to check if a module implements the Builder behaviour.
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
      @behaviour Events.Support.Behaviours.Builder
      import Events.Support.Behaviours.Builder, only: [defcompose: 2]
    end
  end
end
