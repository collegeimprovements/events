defmodule Events.CRUD.Operation do
  @moduledoc """
  Behavior for all CRUD operations.

  ## Implementation Guidelines

  All operations should follow this consistent pattern:

  ```elixir
  defmodule Events.CRUD.Operations.OperationName do
    @moduledoc "Brief description of what this operation does"
    use Events.CRUD.Operation, type: :operation_type

    @supported_values [...] # Define supported values for validation

    @impl true
    def validate_spec(spec) do
      # Use Events.CRUD.OperationUtils for consistent validation
      Events.CRUD.OperationUtils.validate_spec(spec, [
        field: &Events.CRUD.OperationUtils.validate_field/1,
        value: &validate_custom_logic/1
      ])
    end

    @impl true
    def execute(query, spec) do
      # Use Ecto.Query functions directly
      # Keep implementation focused and readable
      # Return modified query
    end

    @impl true
    def optimize(spec, context) do
      # Optional: implement query optimization
      # Access context for schema info, indexes, etc.
      # Return optimized spec or original
    end

    # Private validation helpers
    defp validate_custom_logic(spec) do
      # Custom validation logic specific to this operation
    end
  end
  ```

  ## Standard Validation Patterns

  Use `Events.CRUD.OperationUtils` for consistent validation:

  ```elixir
  # Field validation
  Events.CRUD.OperationUtils.validate_field(field)

  # Enum validation
  Events.CRUD.OperationUtils.validate_enum(value, @supported_values, "field_name")

  # Type validation
  Events.CRUD.OperationUtils.validate_type(value, :atom, "field_name")

  # Range validation
  Events.CRUD.OperationUtils.validate_range(value, 1..100, "field_name")
  ```

  ## Error Handling

  Use standardized error messages:

  ```elixir
  Events.CRUD.OperationUtils.error(:invalid_field, "username")
  Events.CRUD.OperationUtils.error(:unsupported_operator, "custom_op")
  Events.CRUD.OperationUtils.error(:type_mismatch, {"field", "atom"})
  ```
  """

  @type spec :: term()
  @type validation_result :: :ok | {:error, String.t()}
  @type query :: Ecto.Query.t()
  @type context :: map()

  @callback operation_type() :: atom()
  @callback validate_spec(spec) :: validation_result()
  @callback execute(query, spec) :: query
  @callback optimize(spec, context) :: spec

  defmacro __using__(opts) do
    quote do
      @behaviour Events.CRUD.Operation
      import Ecto.Query
      alias Events.CRUD.OperationUtils

      def operation_type, do: unquote(opts[:type])

      # Default implementations
      def validate_spec(_spec), do: :ok
      def optimize(spec, _context), do: spec

      defoverridable validate_spec: 1, optimize: 2
    end
  end
end
