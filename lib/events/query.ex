defmodule Events.Query do
  @moduledoc """
  Production-grade query builder with token pattern and pipelines.

  ## Features

  - Token-based composition with pattern matching
  - Protocol-based operations for extensibility
  - Cursor and offset pagination with metadata
  - Nested filters and preloads
  - Custom joins with conditions
  - Transactions, batching, CTEs, subqueries
  - Named SQL placeholders
  - Telemetry integration
  - Comprehensive result metadata

  ## Basic Usage

  ```elixir
  # Macro DSL
  import Events.Query

  query User do
    filter :status, :eq, "active"
    filter :age, :gte, 18
    order :created_at, :desc
    paginate :offset, limit: 20
  end
  |> execute()

  # Pipeline API
  User
  |> Events.Query.new()
  |> Events.Query.filter(:status, :eq, "active")
  |> Events.Query.paginate(:offset, limit: 20)
  |> Events.Query.execute()
  ```

  ## Result Format

  All queries return `%Events.Query.Result{}`:

  ```elixir
  %Events.Query.Result{
    data: [...],
    pagination: %{
      type: :offset,
      limit: 20,
      offset: 0,
      has_more: true,
      total_count: 150  # if requested
    },
    metadata: %{
      query_time_μs: 1234,
      total_time_μs: 1500,
      cached: false
    }
  }
  ```
  """

  alias Events.Query.{Token, Builder, Executor, Result}

  # Re-export key types
  @type t :: Token.t()

  ## Public API

  @doc "Create a new query token from a schema"
  @spec new(module() | Ecto.Query.t()) :: Token.t()
  defdelegate new(schema_or_query), to: Token

  @doc "Add a filter condition"
  @spec filter(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def filter(token, field, op, value, opts \\ []) do
    Token.add_operation(token, {:filter, {field, op, value, opts}})
  end

  @doc "Add pagination"
  @spec paginate(Token.t(), :offset | :cursor, keyword()) :: Token.t()
  def paginate(token, type, opts \\ []) do
    Token.add_operation(token, {:paginate, {type, opts}})
  end

  @doc "Add ordering"
  @spec order(Token.t(), atom(), :asc | :desc) :: Token.t()
  def order(token, field, direction \\ :asc) do
    Token.add_operation(token, {:order, {field, direction}})
  end

  @doc "Add a join"
  @spec join(Token.t(), atom() | module(), atom(), keyword()) :: Token.t()
  def join(token, association_or_schema, type \\ :inner, opts \\ []) do
    Token.add_operation(token, {:join, {association_or_schema, type, opts}})
  end

  @doc "Add a preload"
  @spec preload(Token.t(), atom() | keyword()) :: Token.t()
  def preload(token, associations) when is_atom(associations) do
    Token.add_operation(token, {:preload, associations})
  end

  def preload(token, associations) when is_list(associations) do
    Token.add_operation(token, {:preload, associations})
  end

  @doc "Add nested preload with filters"
  @spec preload(Token.t(), atom(), (Token.t() -> Token.t())) :: Token.t()
  def preload(token, association, builder_fn) when is_function(builder_fn, 1) do
    nested_token = Token.new(:nested)
    nested_token = builder_fn.(nested_token)
    Token.add_operation(token, {:preload, {association, nested_token}})
  end

  @doc "Add a select clause"
  @spec select(Token.t(), list() | map()) :: Token.t()
  def select(token, fields) do
    Token.add_operation(token, {:select, fields})
  end

  @doc "Add a group by"
  @spec group_by(Token.t(), atom() | list()) :: Token.t()
  def group_by(token, fields) do
    Token.add_operation(token, {:group_by, fields})
  end

  @doc "Add a having clause"
  @spec having(Token.t(), keyword()) :: Token.t()
  def having(token, conditions) do
    Token.add_operation(token, {:having, conditions})
  end

  @doc "Add a limit"
  @spec limit(Token.t(), pos_integer()) :: Token.t()
  def limit(token, value) do
    Token.add_operation(token, {:limit, value})
  end

  @doc "Add an offset"
  @spec offset(Token.t(), non_neg_integer()) :: Token.t()
  def offset(token, value) do
    Token.add_operation(token, {:offset, value})
  end

  @doc "Add distinct"
  @spec distinct(Token.t(), boolean() | list()) :: Token.t()
  def distinct(token, value) do
    Token.add_operation(token, {:distinct, value})
  end

  @doc "Add a lock clause"
  @spec lock(Token.t(), String.t() | atom()) :: Token.t()
  def lock(token, mode) do
    Token.add_operation(token, {:lock, mode})
  end

  @doc """
  Add a CTE (Common Table Expression).

  ## Example

      base_query = Events.Query.new(User) |> Events.Query.filter(:active, :eq, true)

      Events.Query.new(Order)
      |> Events.Query.with_cte(:active_users, base_query)
      |> Events.Query.join(:active_users, :inner, on: [user_id: :id])
  """
  @spec with_cte(Token.t(), atom(), Token.t() | Ecto.Query.t()) :: Token.t()
  def with_cte(token, name, cte_token_or_query) do
    Token.add_operation(token, {:cte, {name, cte_token_or_query}})
  end

  @doc """
  Add a window definition.

  ## Example

      Events.Query.new(Sale)
      |> Events.Query.window(:running_total, partition_by: :product_id, order_by: [asc: :date])
      |> Events.Query.select(%{amount: :amount, total: {:window, :sum, :amount, :running_total}})
  """
  @spec window(Token.t(), atom(), keyword()) :: Token.t()
  def window(token, name, definition) do
    Token.add_operation(token, {:window, {name, definition}})
  end

  @doc """
  Add raw SQL fragment.

  Supports named placeholders:

  ## Example

      Events.Query.new(User)
      |> Events.Query.raw_where("age BETWEEN :min_age AND :max_age", %{min_age: 18, max_age: 65})
  """
  @spec raw_where(Token.t(), String.t(), map()) :: Token.t()
  def raw_where(token, sql, params \\ %{}) do
    Token.add_operation(token, {:raw_where, {sql, params}})
  end

  @doc "Build the Ecto query without executing"
  @spec build(Token.t()) :: Ecto.Query.t()
  defdelegate build(token), to: Builder

  @doc """
  Execute the query and return results.

  ## Options

  - `:repo` - Repo module (default: `Events.Repo`)
  - `:timeout` - Query timeout in ms (default: 15_000)
  - `:telemetry` - Enable telemetry (default: true)
  - `:cache` - Enable caching (default: false)
  - `:cache_ttl` - Cache TTL in seconds (default: 60)
  - `:include_total_count` - Include total count in pagination (default: false)

  ## Examples

      # Basic execution
      result = token |> Events.Query.execute()

      # With options
      result = token |> Events.Query.execute(
        timeout: 30_000,
        include_total_count: true
      )
  """
  @spec execute(Token.t(), keyword()) :: Result.t()
  defdelegate execute(token, opts \\ []), to: Executor

  @doc "Execute and return stream"
  @spec stream(Token.t(), keyword()) :: Enumerable.t()
  defdelegate stream(token, opts \\ []), to: Executor

  @doc """
  Execute query in a transaction.

  ## Example

      Events.Query.transaction(fn ->
        user = User |> Events.Query.new() |> Events.Query.filter(:id, :eq, 1) |> Events.Query.execute()
        # ... more operations
        {:ok, user}
      end)
  """
  @spec transaction((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction(fun, opts \\ []) do
    repo = opts[:repo] || Events.Repo
    repo.transaction(fun, opts)
  end

  @doc """
  Execute multiple queries in a batch.

  Returns list of results in the same order as tokens.

  ## Example

      tokens = [
        User |> Events.Query.new() |> Events.Query.filter(:active, :eq, true),
        Post |> Events.Query.new() |> Events.Query.limit(10)
      ]

      [users_result, posts_result] = Events.Query.batch(tokens)
  """
  @spec batch([Token.t()], keyword()) :: [Result.t()]
  def batch(tokens, opts \\ []) when is_list(tokens) do
    Executor.batch(tokens, opts)
  end
end
