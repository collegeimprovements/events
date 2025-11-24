defmodule Events.CRUD.Operation.Query do
  @moduledoc """
  Behavior for query operations that read data.

  Query operations are read-only operations that retrieve data from the database.
  They can be composed together and optimized for performance.

  ## Examples

      defmodule Events.CRUD.Operations.Where do
        use Events.CRUD.Operation.Query

        @impl true
        def execute(query, {field, op, value, opts}) do
          # Implementation
        end
      end
  """

  @callback execute(Ecto.Query.t(), spec :: term()) :: Ecto.Query.t()

  defmacro __using__(_opts) do
    quote do
      use Events.CRUD.Operation, type: :query_operation
      @behaviour Events.CRUD.Operation.Query

      # Query operations are generally safe to reorder
      def reorderable?(_spec), do: true

      # Query operations don't modify data
      def modifies_data?(_spec), do: false

      defoverridable reorderable?: 1, modifies_data?: 1
    end
  end
end
