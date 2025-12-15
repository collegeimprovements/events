defmodule Events.Core.Query.Api.Selecting do
  @moduledoc false
  # Internal module for Query - selecting operations
  #
  # Handles select, preload, distinct, group_by, and having operations.

  alias Events.Core.Query.Token

  @doc """
  Add a preload for associations.

  ## Examples

      # Single association
      Query.preload(token, :posts)

      # Multiple associations
      Query.preload(token, [:posts, :comments])

      # Nested preload with filters (use preload/3)
      Query.preload(token, :posts, fn q ->
        q |> Query.filter(:published, :eq, true)
      end)
  """
  @spec preload(Token.t(), atom() | keyword() | list()) :: Token.t()
  def preload(token, associations) when is_atom(associations) do
    Token.add_operation(token, {:preload, associations})
  end

  def preload(token, associations) when is_list(associations) do
    Token.add_operation(token, {:preload, associations})
  end

  @doc """
  Alias for `preload/2` when passing a list.

  See `preload/2` for documentation.
  """
  @spec preloads(Token.t(), list()) :: Token.t()
  def preloads(token, associations) when is_list(associations) do
    preload(token, associations)
  end

  @doc """
  Add nested preload with filters and ordering.

  The builder function receives a fresh token and can add filters,
  ordering, pagination, and even nested preloads.

  ## Examples

      # Preload only published posts
      Query.preload(token, :posts, fn q ->
        q
        |> Query.filter(:published, :eq, true)
        |> Query.order(:created_at, :desc)
        |> Query.limit(10)
      end)

      # Nested preloads with filters at each level
      Query.preload(token, :posts, fn q ->
        q
        |> Query.filter(:published, :eq, true)
        |> Query.preload(:comments, fn c ->
          c |> Query.filter(:approved, :eq, true)
        end)
      end)
  """
  @spec preload(Token.t(), atom(), (Token.t() -> Token.t())) :: Token.t()
  def preload(token, association, builder_fn) when is_function(builder_fn, 1) do
    nested_token = Token.new(:nested)
    nested_token = builder_fn.(nested_token)
    Token.add_operation(token, {:preload, {association, nested_token}})
  end

  @doc """
  Select fields from the base table and joined tables with aliasing.

  Supports selecting from multiple tables/bindings with custom aliases
  to avoid name conflicts.

  ## Select Formats

  - `[:field1, :field2]` - Simple field list from base table
  - `%{alias: :field}` - Map with aliases from base table
  - `%{alias: {:binding, :field}}` - Field from joined table

  ## Examples

      # Simple select from base table
      Query.select(token, [:id, :name, :price])

      # Select with aliases (same table)
      Query.select(token, %{
        product_id: :id,
        product_name: :name
      })

      # Select from base and joined tables
      Product
      |> Query.new()
      |> Query.join(:category, :left, as: :cat)
      |> Query.join(:brand, :left, as: :brand)
      |> Query.select(%{
        product_id: :id,
        product_name: :name,
        price: :price,
        category_id: {:cat, :id},
        category_name: {:cat, :name},
        brand_id: {:brand, :id},
        brand_name: {:brand, :name}
      })
      |> Query.execute()
  """
  @spec select(Token.t(), list() | map()) :: Token.t()
  def select(token, fields) when is_list(fields) or is_map(fields) do
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

  @doc "Add distinct"
  @spec distinct(Token.t(), boolean() | list()) :: Token.t()
  def distinct(token, value) do
    Token.add_operation(token, {:distinct, value})
  end
end
