defmodule Events.Core.Query.Api.Joining do
  @moduledoc false
  # Internal module for Query - joining operations
  #
  # Handles join operations with conveniences:
  # - Generic join/4 with type parameter
  # - Type-specific shortcuts (inner_join, left_join, right_join, full_join, cross_join)
  # - Multiple joins (joins/2)

  alias Events.Core.Query.Token

  @doc """
  Add a join to the query.

  ## Parameters

  - `token` - The query token
  - `association_or_schema` - Association name (atom) or schema module
  - `type` - Join type: `:inner`, `:left`, `:right`, `:full`, `:cross` (default: `:inner`)
  - `opts` - Options:
    - `:as` - Name the binding for use in filters/orders (default: association name)
    - `:on` - Custom join conditions as keyword list

  ## Binding Convention

  Use `as:` in joins to **name** the binding, then use `binding:` in
  `filter/5`, `order/4`, `search/3` to **reference** that binding:

      # Create a named binding with as:
      token
      |> Query.join(:posts, :left, as: :user_posts)
      # Reference it with binding:
      |> Query.filter(:published, :eq, true, binding: :user_posts)
      |> Query.order(:created_at, :desc, binding: :user_posts)

  ## Examples

      # Association join (uses association as binding name)
      Query.join(token, :posts, :left)
      # Filter on it: Query.filter(token, :published, :eq, true, binding: :posts)

      # Named binding for clarity
      Query.join(token, :posts, :left, as: :user_posts)

      # Schema join with custom conditions
      Query.join(token, Post, :left, as: :posts, on: [author_id: :id])
  """
  @spec join(Token.t(), atom() | module(), atom(), keyword()) :: Token.t()
  def join(token, association_or_schema, type \\ :inner, opts \\ []) do
    Token.add_operation(token, {:join, {association_or_schema, type, opts}})
  end

  @doc """
  Add a LEFT JOIN to the query.

  Convenience function for `join(source, assoc, :left, opts)`.

  ## Examples

      User |> Query.left_join(:posts)
      User |> Query.left_join(:posts, as: :user_posts)
      User |> Query.left_join(Category, as: :cat, on: [id: :category_id])
  """
  @spec left_join(Token.t(), atom() | module(), keyword()) :: Token.t()
  def left_join(token, association_or_schema, opts \\ []) do
    join(token, association_or_schema, :left, opts)
  end

  @doc """
  Add a RIGHT JOIN to the query.

  Convenience function for `join(source, assoc, :right, opts)`.

  ## Examples

      User |> Query.right_join(:posts)
      User |> Query.right_join(:posts, as: :posts)
  """
  @spec right_join(Token.t(), atom() | module(), keyword()) :: Token.t()
  def right_join(token, association_or_schema, opts \\ []) do
    join(token, association_or_schema, :right, opts)
  end

  @doc """
  Add an INNER JOIN to the query.

  Convenience function for `join(source, assoc, :inner, opts)`.

  ## Examples

      User |> Query.inner_join(:posts)
      User |> Query.inner_join(:posts, as: :posts)
  """
  @spec inner_join(Token.t(), atom() | module(), keyword()) :: Token.t()
  def inner_join(token, association_or_schema, opts \\ []) do
    join(token, association_or_schema, :inner, opts)
  end

  @doc """
  Add a FULL OUTER JOIN to the query.

  Convenience function for `join(source, assoc, :full, opts)`.

  ## Examples

      User |> Query.full_join(:posts)
  """
  @spec full_join(Token.t(), atom() | module(), keyword()) :: Token.t()
  def full_join(token, association_or_schema, opts \\ []) do
    join(token, association_or_schema, :full, opts)
  end

  @doc """
  Add a CROSS JOIN to the query.

  Convenience function for `join(source, assoc, :cross, opts)`.

  ## Examples

      User |> Query.cross_join(:roles)
  """
  @spec cross_join(Token.t(), atom() | module(), keyword()) :: Token.t()
  def cross_join(token, association_or_schema, opts \\ []) do
    join(token, association_or_schema, :cross, opts)
  end

  @doc """
  Add multiple joins at once.

  ## Parameters

  - `token` - The query token
  - `join_list` - List of join specifications. Each can be:
    - `association` - Atom, defaults to `:inner` join
    - `{association, type}` - 2-tuple with join type
    - `{association, type, opts}` - 3-tuple with options

  ## Examples

      # List of atoms (all inner joins)
      Query.joins(token, [:posts, :comments])

      # List of 2-tuples with join types
      Query.joins(token, [
        {:posts, :left},
        {:comments, :inner}
      ])

      # List of 3-tuples with options
      Query.joins(token, [
        {:posts, :left, []},
        {:comments, :inner, [on: [author_id: :id]]}
      ])
  """
  @spec joins(Token.t(), [
          atom()
          | {atom(), atom()}
          | {atom(), atom(), keyword()}
        ]) :: Token.t()
  def joins(token, join_list) when is_list(join_list) do
    Enum.reduce(join_list, token, fn
      assoc, acc when is_atom(assoc) ->
        join(acc, assoc, :inner, [])

      {assoc, type}, acc ->
        join(acc, assoc, type, [])

      {assoc, type, opts}, acc ->
        join(acc, assoc, type, opts)
    end)
  end
end
