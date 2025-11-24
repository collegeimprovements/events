defprotocol Events.CRUD.QueryBuilder do
  @moduledoc """
  Protocol for building queries from tokens.

  Different implementations can provide different strategies for query construction,
  optimization, and execution.
  """

  @type token :: Events.CRUD.Token.t()
  @type query :: Ecto.Query.t()
  @type result :: Events.CRUD.Result.t()

  @doc """
  Builds an Ecto query from a token.
  """
  @spec build(token) :: {:ok, query} | {:error, String.t()}
  def build(token)

  @doc """
  Optimizes a token before building.
  """
  @spec optimize(token) :: token
  def optimize(token)

  @doc """
  Executes a built query.
  """
  @spec execute(query) :: result
  def execute(query)

  @doc """
  Estimates the complexity of a token.
  """
  @spec complexity(token) :: non_neg_integer()
  def complexity(token)
end

defmodule Events.CRUD.QueryBuilder.Standard do
  @moduledoc """
  Standard query builder implementation.

  Uses the existing operation-based approach for building and executing queries.
  """

  @behaviour Events.CRUD.QueryBuilder

  @impl true
  def build(token) do
    # Use existing builder logic
    Events.CRUD.Builder.build(token)
  end

  @impl true
  def optimize(token) do
    # Apply standard optimizations
    Events.CRUD.Token.optimize(token)
  end

  @impl true
  def execute(query) do
    Events.CRUD.Builder.execute(query)
  end

  @impl true
  def complexity(token) do
    Events.CRUD.Token.complexity(token)
  end
end

defmodule Events.CRUD.QueryBuilder.Streaming do
  @moduledoc """
  Streaming query builder for large datasets.

  Optimizes for memory efficiency when dealing with large result sets.
  """

  @behaviour Events.CRUD.QueryBuilder

  @impl true
  def build(token) do
    # Build query optimized for streaming
    case Events.CRUD.Builder.build(token) do
      {:ok, query} -> {:ok, query}
      error -> error
    end
  end

  @impl true
  def optimize(token) do
    # Apply streaming-specific optimizations
    # e.g., prefer cursor pagination, avoid preloads
    token
  end

  @impl true
  def execute(query) do
    # Execute with streaming
    Events.CRUD.Builder.execute_stream(query)
  end

  @impl true
  def complexity(token) do
    # Streaming has different complexity characteristics
    base_complexity = Events.CRUD.Token.complexity(token)
    # Streaming adds some overhead
    base_complexity + 5
  end
end

defmodule Events.CRUD.QueryBuilder.Analytics do
  @moduledoc """
  Analytics-focused query builder.

  Optimized for complex aggregations and reporting queries.
  """

  @behaviour Events.CRUD.QueryBuilder

  @impl true
  def build(token) do
    # Build with analytics-specific optimizations
    Events.CRUD.Builder.build_analytics(token)
  end

  @impl true
  def optimize(token) do
    # Apply analytics-specific optimizations
    # e.g., prefer raw SQL for complex aggregations
    token
  end

  @impl true
  def execute(query) do
    # Execute analytics query
    Events.CRUD.Builder.execute_analytics(query)
  end

  @impl true
  def complexity(token) do
    # Analytics queries are often more complex
    base_complexity = Events.CRUD.Token.complexity(token)
    base_complexity * 2
  end
end
