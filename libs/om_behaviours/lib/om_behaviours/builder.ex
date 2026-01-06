defmodule OmBehaviours.Builder do
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
        use OmBehaviours.Builder

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

  This macro simplifies defining chainable builder methods by automatically
  wrapping the method body in a function definition.

  ## Parameters

  - `call` - The function signature (name and parameters)
  - `block` - The function body (should call `compose/2`)

  ## Examples

      defmodule MyApp.QueryBuilder do
        use OmBehaviours.Builder

        # Using defcompose for fluent methods
        defcompose where(builder, field, value) do
          compose(builder, {:where, field, value})
        end

        defcompose order_by(builder, field, direction \\ :asc) do
          compose(builder, {:order_by, field, direction})
        end

        defcompose limit(builder, count) do
          compose(builder, {:limit, count})
        end

        # Expands to regular function definitions:
        # def where(builder, field, value) do
        #   compose(builder, {:where, field, value})
        # end
      end

      # Usage - creates fluent API
      MyApp.QueryBuilder.new(User)
      |> MyApp.QueryBuilder.where(:status, :active)
      |> MyApp.QueryBuilder.order_by(:name, :asc)
      |> MyApp.QueryBuilder.limit(10)
      |> MyApp.QueryBuilder.build()

  ## Alternative Without defcompose

      # Without defcompose, you'd write:
      def where(builder, field, value) do
        compose(builder, {:where, field, value})
      end

      # defcompose just reduces boilerplate
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

  ## Parameters

  - `module` - The module to check

  ## Returns

  `true` if the module implements `OmBehaviours.Builder`, `false` otherwise.

  ## Examples

      defmodule MyApp.ValidationBuilder do
        use OmBehaviours.Builder

        defstruct [:data, :rules]

        @impl true
        def new(data, _opts), do: %__MODULE__{data: data, rules: []}

        @impl true
        def compose(builder, rule), do: %{builder | rules: [rule | builder.rules]}

        @impl true
        def build(builder), do: validate(builder.data, builder.rules)
      end

      iex> OmBehaviours.Builder.implements?(MyApp.ValidationBuilder)
      true

      iex> OmBehaviours.Builder.implements?(SomeOtherModule)
      false

  ## Real-World Usage

      # Validate builder contract at runtime
      defmodule MyApp.BuilderRegistry do
        @builders [
          MyApp.QueryBuilder,
          MyApp.ValidationBuilder,
          MyApp.PipelineBuilder
        ]

        def validate_all_builders do
          Enum.each(@builders, fn builder ->
            unless OmBehaviours.Builder.implements?(builder) do
              raise "Builder \#{inspect(builder)} must implement OmBehaviours.Builder"
            end
          end)
        end
      end
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    OmBehaviours.implements?(module, __MODULE__)
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour OmBehaviours.Builder
      import OmBehaviours.Builder, only: [defcompose: 2]
    end
  end
end
