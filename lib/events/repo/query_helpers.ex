defmodule Events.Repo.QueryHelpers do
  @moduledoc """
  Composable helper functions for building queries using keyword lists.

  These helpers follow the project conventions:
  - Simple functions with keyword list arguments
  - Composable - can be piped together
  - Pattern matching for clean code

  ## Usage

      # Compose query options
      opts = []
      |> QueryHelpers.where(status: "active")
      |> QueryHelpers.where(type: "widget")
      |> QueryHelpers.limit(10)
      |> QueryHelpers.order_by(desc: :inserted_at)

      products = Query.all(Product, opts)

      # Or build directly
      products = Query.all(Product,
        QueryHelpers.paginate([], page: 2, per_page: 20)
      )
  """

  @type opts :: keyword()

  ## Query Option Builders

  @doc """
  Adds where conditions to query options.

  ## Examples

      opts = QueryHelpers.where([], status: "active", type: "widget")
      products = Query.all(Product, opts)

      # Composable
      opts = []
      |> QueryHelpers.where(status: "active")
      |> QueryHelpers.where(type: "widget")
  """
  @spec where(opts(), keyword()) :: opts()
  def where(opts, conditions) when is_list(conditions) do
    existing = Keyword.get(opts, :where, [])
    Keyword.put(opts, :where, existing ++ conditions)
  end

  @doc """
  Adds a limit to query options.

  ## Examples

      opts = QueryHelpers.limit([], 10)
  """
  @spec limit(opts(), pos_integer()) :: opts()
  def limit(opts, value) when is_integer(value) and value > 0 do
    Keyword.put(opts, :limit, value)
  end

  @doc """
  Adds an offset to query options.

  ## Examples

      opts = QueryHelpers.offset([], 20)
  """
  @spec offset(opts(), non_neg_integer()) :: opts()
  def offset(opts, value) when is_integer(value) and value >= 0 do
    Keyword.put(opts, :offset, value)
  end

  @doc """
  Adds ordering to query options.

  ## Examples

      opts = QueryHelpers.order_by([], desc: :inserted_at)
      opts = QueryHelpers.order_by([], [asc: :name, desc: :price])
  """
  @spec order_by(opts(), keyword()) :: opts()
  def order_by(opts, value) when is_list(value) do
    Keyword.put(opts, :order_by, value)
  end

  @doc """
  Adds preloads to query options.

  ## Examples

      opts = QueryHelpers.preload([], [:category, :tags])
  """
  @spec preload(opts(), list()) :: opts()
  def preload(opts, assocs) when is_list(assocs) do
    existing = Keyword.get(opts, :preload, [])
    Keyword.put(opts, :preload, existing ++ assocs)
  end

  @doc """
  Includes soft-deleted records in query options.

  ## Examples

      opts = QueryHelpers.include_deleted([])
  """
  @spec include_deleted(opts()) :: opts()
  def include_deleted(opts) do
    Keyword.put(opts, :include_deleted, true)
  end

  @doc """
  Adds pagination to query options.

  ## Options

  - `:page` - Page number (1-indexed, default: 1)
  - `:per_page` - Records per page (default: 20)

  ## Examples

      opts = QueryHelpers.paginate([], page: 2, per_page: 20)
      products = Query.all(Product, opts)
  """
  @spec paginate(opts(), keyword()) :: opts()
  def paginate(opts, pagination_opts \\ []) do
    page = Keyword.get(pagination_opts, :page, 1)
    per_page = Keyword.get(pagination_opts, :per_page, 20)

    opts
    |> limit(per_page)
    |> offset((page - 1) * per_page)
  end

  ## Common Query Patterns

  @doc """
  Query options for active records (status = active, not deleted).

  ## Examples

      products = Query.all(Product, QueryHelpers.active())
  """
  @spec active() :: opts()
  def active do
    where([], status: "active")
  end

  @doc """
  Query options for published records.

  ## Examples

      posts = Query.all(Post, QueryHelpers.published())
  """
  @spec published() :: opts()
  def published do
    where([], status: "published")
  end

  @doc """
  Query options for recent records.

  ## Options

  - `:days` - Number of days (default: 7)

  ## Examples

      recent = Query.all(Product, QueryHelpers.recent(days: 30))
  """
  @spec recent(keyword()) :: opts()
  def recent(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    []
    |> where(inserted_at: {:>=, cutoff})
    |> order_by(desc: :inserted_at)
  end

  ## Scope Composition

  @doc """
  Merges multiple query option lists.

  Later options override earlier ones.

  ## Examples

      base = QueryHelpers.active()
      specific = QueryHelpers.where([], type: "widget")
      opts = QueryHelpers.merge(base, specific)
  """
  @spec merge(opts(), opts()) :: opts()
  def merge(opts1, opts2) do
    # Special handling for :where to merge conditions
    case {Keyword.get(opts1, :where), Keyword.get(opts2, :where)} do
      {nil, _} ->
        Keyword.merge(opts1, opts2)

      {_, nil} ->
        Keyword.merge(opts1, opts2)

      {where1, where2} ->
        merged_where = where1 ++ where2

        opts1
        |> Keyword.delete(:where)
        |> Keyword.merge(Keyword.delete(opts2, :where))
        |> Keyword.put(:where, merged_where)
    end
  end

  ## Utility Functions

  @doc """
  Builds pagination metadata from query results.

  ## Examples

      opts = QueryHelpers.paginate([], page: 2, per_page: 20)
      products = Query.all(Product, opts)
      total = Query.count(Product)

      metadata = QueryHelpers.pagination_metadata(
        page: 2,
        per_page: 20,
        total_count: total
      )
  """
  @spec pagination_metadata(keyword()) :: map()
  def pagination_metadata(opts) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    total_count = Keyword.get(opts, :total_count, 0)
    total_pages = ceil(total_count / per_page)

    %{
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_prev: page > 1,
      has_next: page < total_pages
    }
  end
end
