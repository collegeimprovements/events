defprotocol Events.Query.Queryable do
  @moduledoc """
  Protocol for types that can be converted to a Query token.

  This enables any queryable source to be used directly in Query pipelines
  without explicit `Query.new()` calls.

  ## Implemented For

  - `Atom` (schema modules) - Creates a new token from the schema
  - `Ecto.Query` - Creates a token from an existing Ecto query
  - `Events.Query.Token` - Passes through unchanged

  ## Usage

  With this protocol, you can pipe directly from schemas:

      # Instead of:
      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.execute()

      # You can write:
      User
      |> Query.filter(:status, :eq, "active")
      |> Query.execute()

  ## Custom Implementations

  You can implement this protocol for custom types:

      defimpl Events.Query.Queryable, for: MyApp.QueryBuilder do
        def to_token(%MyApp.QueryBuilder{schema: schema, filters: filters}) do
          schema
          |> Events.Query.Token.new()
          |> apply_filters(filters)
        end
      end
  """

  @doc """
  Convert a queryable source to a Query token.

  Returns an `Events.Query.Token` that can be used in query pipelines.
  """
  @spec to_token(t()) :: Events.Query.Token.t()
  def to_token(source)
end

# Atom implementation - for schema modules
defimpl Events.Query.Queryable, for: Atom do
  def to_token(schema) when schema != nil do
    Events.Query.Token.new(schema)
  end
end

# Token implementation - pass through unchanged
defimpl Events.Query.Queryable, for: Events.Query.Token do
  def to_token(token), do: token
end

# BitString implementation - for table names as strings
defimpl Events.Query.Queryable, for: BitString do
  def to_token(table_name) when is_binary(table_name) do
    # Create a dynamic query from table name
    # Note: This creates a schemaless query
    import Ecto.Query, only: [from: 2]
    query = from(t in table_name, [])
    Events.Query.Token.new(query)
  end
end

# Ecto.Query implementation - wrap existing queries
defimpl Events.Query.Queryable, for: Ecto.Query do
  def to_token(query) do
    Events.Query.Token.new(query)
  end
end
