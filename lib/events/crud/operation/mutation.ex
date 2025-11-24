defmodule Events.CRUD.Operation.Mutation do
  @moduledoc """
  Behavior for mutation operations that modify data.

  Mutation operations create, update, or delete data in the database.
  They have different optimization and composition rules than query operations.

  ## Examples

      defmodule Events.CRUD.Operations.Create do
        use Events.CRUD.Operation.Mutation

        @impl true
        def execute(schema, attrs, opts) do
          # Implementation
        end
      end
  """

  @callback execute(schema :: module(), data :: term(), opts :: keyword()) :: Events.CRUD.Result.t()

  defmacro __using__(_opts) do
    quote do
      use Events.CRUD.Operation, type: :mutation_operation
      @behaviour Events.CRUD.Operation.Mutation

      # Mutation operations cannot be reordered
      def reorderable?(_spec), do: false

      # Mutation operations modify data
      def modifies_data?(_spec), do: true

      defoverridable reorderable?: 1, modifies_data?: 1
    end
  end
end
