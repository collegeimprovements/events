defmodule Events.Core.Query.Api.Advanced do
  @moduledoc false
  # Internal module for Query - advanced query operations
  #
  # Handles:
  # - with_cte - Common Table Expressions
  # - window - Window functions
  # - raw_where - Raw SQL where clauses
  # - lock - Row locking
  # - from_subquery - Subquery sources

  alias Events.Core.Query.Token

  @doc """
  Define a named window for use with window functions.

  Windows define the partitioning and ordering for window functions
  like `row_number()`, `rank()`, `sum() OVER`, etc.
  """
  @spec window(Token.t(), atom(), keyword()) :: Token.t()
  def window(token, name, opts \\ []) when is_atom(name) do
    Token.add_operation(token, {:window, {name, opts}})
  end

  @doc "Add a lock clause"
  @spec lock(Token.t(), String.t() | atom()) :: Token.t()
  def lock(token, mode) do
    Token.add_operation(token, {:lock, mode})
  end

  @doc """
  Add a CTE (Common Table Expression).

  ## Options

  - `:recursive` - Enable recursive CTE mode (default: false)

  ## Examples

      # Simple CTE
      base_query = Events.Core.Query.new(User) |> Events.Core.Query.filter(:active, :eq, true)

      Events.Core.Query.new(Order)
      |> Events.Core.Query.with_cte(:active_users, base_query)
      |> Events.Core.Query.join(:active_users, :inner, on: [user_id: :id])

      # Recursive CTE for hierarchical data (trees, graphs)
      # First define the base case and recursive case combined with union_all
      import Ecto.Query

      # Base case: root categories (no parent)
      base = from(c in "categories", where: is_nil(c.parent_id), select: %{id: c.id, name: c.name, depth: 0})

      # Recursive case: children joining with CTE
      recursive = from(c in "categories",
        join: tree in "category_tree", on: c.parent_id == tree.id,
        select: %{id: c.id, name: c.name, depth: tree.depth + 1}
      )

      # Combine with union_all
      cte_query = union_all(base, ^recursive)

      # Use recursive CTE
      from(c in "category_tree")
      |> Events.Core.Query.new()
      |> Events.Core.Query.with_cte(:category_tree, cte_query, recursive: true)
      |> Events.Core.Query.execute()

  ## SQL Equivalent (Recursive)

      WITH RECURSIVE category_tree AS (
        SELECT id, name, 0 as depth FROM categories WHERE parent_id IS NULL
        UNION ALL
        SELECT c.id, c.name, tree.depth + 1
        FROM categories c
        JOIN category_tree tree ON c.parent_id = tree.id
      )
      SELECT * FROM category_tree
  """
  @spec with_cte(Token.t(), atom(), Token.t() | Ecto.Query.t(), keyword()) :: Token.t()
  def with_cte(token, name, cte_token_or_query, opts \\ []) do
    if opts == [] do
      # Backwards compatible - no opts
      Token.add_operation(token, {:cte, {name, cte_token_or_query}})
    else
      Token.add_operation(token, {:cte, {name, cte_token_or_query, opts}})
    end
  end

  @doc """
  Add raw SQL fragment.

  Supports named placeholders:

  ## Example

      Events.Core.Query.new(User)
      |> Events.Core.Query.raw_where("age BETWEEN :min_age AND :max_age", %{min_age: 18, max_age: 65})
  """
  @spec raw_where(Token.t(), String.t(), map()) :: Token.t()
  def raw_where(token, sql, params \\ %{}) do
    Token.add_operation(token, {:raw_where, {sql, params}})
  end

  @doc """
  Convert token to a subquery.

  Wraps the query in an Ecto subquery for use in FROM, JOIN, WHERE, or SELECT clauses.

  ## Examples

      # Subquery in FROM
      subset = Query.new(Post) |> Query.where(:status, :eq, "draft")
      Query.from_subquery(subset) |> Query.where(:created_at, :gt, yesterday)

      # Subquery in WHERE with :in_subquery operator
      user_ids = Query.new(User) |> Query.where(:active, :eq, true) |> Query.select([:id])
      Query.new(Post) |> Query.where(:user_id, :in_subquery, user_ids)
  """
  @spec from_subquery(Token.t()) :: Ecto.Query.t()
  def from_subquery(%Token{} = token) do
    import Ecto.Query
    # Use runtime apply to avoid circular dependency
    query = apply(Events.Core.Query.Builder, :build, [token])
    subquery(query)
  end
end
