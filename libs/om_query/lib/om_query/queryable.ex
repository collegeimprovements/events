defprotocol OmQuery.Queryable do
  @moduledoc """
  Protocol for types that can be converted to a Query token.

  This enables any queryable source to be used directly in Query pipelines
  without explicit `OmQuery.new()` calls.

  ## Implemented For

  - `Atom` (schema modules) - Creates a new token from the schema
  - `Ecto.Query` - Creates a token from an existing Ecto query
  - `OmQuery.Token` - Passes through unchanged

  ## Usage

  With this protocol, you can pipe directly from schemas:

      # Instead of:
      User
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.execute()

      # You can write:
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.execute()

  ## Custom Implementations

  You can implement this protocol for custom types:

      defimpl OmQuery.Queryable, for: MyApp.QueryBuilder do
        def to_token(%MyApp.QueryBuilder{schema: schema, filters: filters}) do
          schema
          |> OmQuery.Token.new()
          |> apply_filters(filters)
        end
      end
  """

  @doc """
  Convert a queryable source to a Query token.

  Returns an `OmQuery.Token` that can be used in query pipelines.
  """
  @spec to_token(t()) :: OmQuery.Token.t()
  def to_token(source)
end

# Atom implementation - for schema modules
defimpl OmQuery.Queryable, for: Atom do
  def to_token(schema) when schema != nil do
    OmQuery.Token.new(schema)
  end
end

# Token implementation - pass through unchanged
defimpl OmQuery.Queryable, for: OmQuery.Token do
  def to_token(token), do: token
end

# BitString implementation - for table names as strings
defimpl OmQuery.Queryable, for: BitString do
  def to_token(table_name) when is_binary(table_name) do
    # Create a dynamic query from table name
    # Note: This creates a schemaless query
    import Ecto.Query, only: [from: 2]
    query = from(t in table_name, [])
    OmQuery.Token.new(query)
  end
end

# Ecto.Query implementation - wrap existing queries
defimpl OmQuery.Queryable, for: Ecto.Query do
  def to_token(query) do
    OmQuery.Token.new(query)
  end
end
