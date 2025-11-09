defmodule Events.Repo.QueryBuilder do
  @moduledoc """
  High-level query builder that combines Ecto.Query with the Scope DSL.

  This module provides a fluent, chainable API for building complex queries
  that seamlessly integrates the Scope DSL with Ecto's query capabilities.

  ## Features

  - **Chainable API**: Build queries step by step
  - **Scope Integration**: Use the powerful Scope DSL for filtering
  - **Soft Delete Aware**: Automatically excludes deleted records
  - **Preloading**: Easy association preloading
  - **Pagination**: Built-in limit/offset and cursor pagination
  - **Aggregations**: Count, sum, avg, min, max support

  ## Basic Usage

      # Simple query with scope
      QueryBuilder.new(Product)
      |> QueryBuilder.active()
      |> QueryBuilder.scope(fn s -> s |> Scope.status("published") end)
      |> QueryBuilder.all()

      # Paginated query
      QueryBuilder.new(Product)
      |> QueryBuilder.active()
      |> QueryBuilder.order_by(desc: :inserted_at)
      |> QueryBuilder.paginate(page: 2, per_page: 20)
      |> QueryBuilder.all()

      # Query with preloads
      QueryBuilder.new(Product)
      |> QueryBuilder.scope(fn s -> s |> Scope.featured() end)
      |> QueryBuilder.preload([:category, :tags])
      |> QueryBuilder.all()

  ## Complex Queries

      QueryBuilder.new(Product)
      |> QueryBuilder.active()
      |> QueryBuilder.scope(fn s ->
        s
        |> Scope.status("published")
        |> Scope.gte("price", 10.00)
        |> Scope.lt("price", 100.00)
        |> Scope.jsonb_eq("metadata", ["featured"], true)
      end)
      |> QueryBuilder.order_by([desc: :featured_at, asc: :name])
      |> QueryBuilder.limit(10)
      |> QueryBuilder.all()

  ## Aggregations

      # Count
      count = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.count()

      # Sum
      total_revenue = QueryBuilder.new(Order)
        |> QueryBuilder.scope(fn s -> s |> Scope.status("completed") end)
        |> QueryBuilder.sum(:total)

  ## Find Operations

      # Find by ID
      {:ok, product} = QueryBuilder.new(Product)
        |> QueryBuilder.find(product_id)

      # Find by field
      {:ok, product} = QueryBuilder.new(Product)
        |> QueryBuilder.find_by(slug: "my-product")
  """

  import Ecto.Query
  alias Events.Repo
  alias Events.Repo.SqlScope.Scope
  alias Events.Repo.SoftDelete

  @type t :: %__MODULE__{
          schema: module(),
          query: Ecto.Query.t(),
          scope: Scope.t() | nil,
          exclude_deleted: boolean(),
          preloads: list(),
          limit_value: integer() | nil,
          offset_value: integer() | nil,
          order_by_value: keyword() | nil
        }

  defstruct [
    :schema,
    :query,
    :scope,
    :exclude_deleted,
    :preloads,
    :limit_value,
    :offset_value,
    :order_by_value
  ]

  ## Builder Functions

  @doc """
  Creates a new QueryBuilder for the given schema.

  By default, soft-deleted records are excluded. Use `with_deleted/1` to include them.

  ## Examples

      QueryBuilder.new(Product)
  """
  @spec new(module()) :: t()
  def new(schema) when is_atom(schema) do
    %__MODULE__{
      schema: schema,
      query: from(q in schema),
      scope: Scope.new(),
      exclude_deleted: true,
      preloads: []
    }
  end

  @doc """
  Adds a scope filter to the query.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.scope(fn s ->
        s
        |> Scope.active()
        |> Scope.status("published")
        |> Scope.gte("price", 10.00)
      end)
  """
  @spec scope(t(), (Scope.t() -> Scope.t())) :: t()
  def scope(%__MODULE__{} = qb, scope_fn) when is_function(scope_fn, 1) do
    new_scope = scope_fn.(qb.scope || Scope.new())
    %{qb | scope: new_scope}
  end

  @doc """
  Convenience function to add an "active" scope (status = active AND deleted_at IS NULL).

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.active()
  """
  @spec active(t()) :: t()
  def active(%__MODULE__{} = qb) do
    scope(qb, fn s -> Scope.active(s) end)
  end

  @doc """
  Includes soft-deleted records in the query.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.with_deleted()
  """
  @spec with_deleted(t()) :: t()
  def with_deleted(%__MODULE__{} = qb) do
    %{qb | exclude_deleted: false}
  end

  @doc """
  Queries only soft-deleted records.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.only_deleted()
  """
  @spec only_deleted(t()) :: t()
  def only_deleted(%__MODULE__{} = qb) do
    qb
    |> scope(fn s -> Scope.deleted(s) end)
    |> with_deleted()
  end

  @doc """
  Adds preloads to the query.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.preload([:category, :tags])

      QueryBuilder.new(Product)
      |> QueryBuilder.preload([category: :parent])
  """
  @spec preload(t(), list()) :: t()
  def preload(%__MODULE__{} = qb, assocs) when is_list(assocs) do
    %{qb | preloads: qb.preloads ++ assocs}
  end

  @doc """
  Sets a limit on the number of records.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.limit(10)
  """
  @spec limit(t(), integer()) :: t()
  def limit(%__MODULE__{} = qb, value) when is_integer(value) and value > 0 do
    %{qb | limit_value: value}
  end

  @doc """
  Sets an offset for pagination.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.offset(20)
  """
  @spec offset(t(), integer()) :: t()
  def offset(%__MODULE__{} = qb, value) when is_integer(value) and value >= 0 do
    %{qb | offset_value: value}
  end

  @doc """
  Sets the ordering for results.

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.order_by(desc: :inserted_at)

      QueryBuilder.new(Product)
      |> QueryBuilder.order_by([asc: :name, desc: :price])
  """
  @spec order_by(t(), keyword() | list()) :: t()
  def order_by(%__MODULE__{} = qb, value) when is_list(value) do
    %{qb | order_by_value: value}
  end

  @doc """
  Paginates the query.

  ## Options

  - `:page` - Page number (1-indexed)
  - `:per_page` - Records per page

  ## Examples

      QueryBuilder.new(Product)
      |> QueryBuilder.paginate(page: 2, per_page: 20)
  """
  @spec paginate(t(), keyword()) :: t()
  def paginate(%__MODULE__{} = qb, opts) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    qb
    |> limit(per_page)
    |> offset((page - 1) * per_page)
  end

  ## Execution Functions

  @doc """
  Executes the query and returns all matching records.

  ## Examples

      products = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.all()
  """
  @spec all(t()) :: [Ecto.Schema.t()]
  def all(%__MODULE__{} = qb) do
    qb
    |> build_final_query()
    |> Repo.all()
  end

  @doc """
  Executes the query and returns a single record.

  Returns `nil` if no record is found.

  ## Examples

      product = QueryBuilder.new(Product)
        |> QueryBuilder.scope(fn s -> s |> Scope.eq("id", id) end)
        |> QueryBuilder.one()
  """
  @spec one(t()) :: Ecto.Schema.t() | nil
  def one(%__MODULE__{} = qb) do
    qb
    |> limit(1)
    |> build_final_query()
    |> Repo.one()
  end

  @doc """
  Executes the query and returns a single record, raising if not found.

  ## Examples

      product = QueryBuilder.new(Product)
        |> QueryBuilder.scope(fn s -> s |> Scope.eq("id", id) end)
        |> QueryBuilder.one!()
  """
  @spec one!(t()) :: Ecto.Schema.t()
  def one!(%__MODULE__{} = qb) do
    qb
    |> limit(1)
    |> build_final_query()
    |> Repo.one!()
  end

  @doc """
  Finds a record by its primary key.

  ## Examples

      {:ok, product} = QueryBuilder.new(Product)
        |> QueryBuilder.find(product_id)

      {:error, :not_found} = QueryBuilder.new(Product)
        |> QueryBuilder.find("invalid-id")
  """
  @spec find(t(), any()) :: {:ok, Ecto.Schema.t()} | {:error, :not_found}
  def find(%__MODULE__{schema: schema} = qb, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record ->
        if qb.exclude_deleted && SoftDelete.deleted?(record) do
          {:error, :not_found}
        else
          {:ok, record}
        end
    end
  end

  @doc """
  Finds a record by its primary key, raising if not found.

  ## Examples

      product = QueryBuilder.new(Product)
        |> QueryBuilder.find!(product_id)
  """
  @spec find!(t(), any()) :: Ecto.Schema.t()
  def find!(%__MODULE__{} = qb, id) do
    case find(qb, id) do
      {:ok, record} -> record
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: qb.schema
    end
  end

  @doc """
  Finds a record by specific field values.

  ## Examples

      {:ok, product} = QueryBuilder.new(Product)
        |> QueryBuilder.find_by(slug: "my-product")

      {:ok, product} = QueryBuilder.new(Product)
        |> QueryBuilder.find_by(type: "widget", status: "active")
  """
  @spec find_by(t(), keyword()) :: {:ok, Ecto.Schema.t()} | {:error, :not_found}
  def find_by(%__MODULE__{} = qb, clauses) when is_list(clauses) do
    qb =
      Enum.reduce(clauses, qb, fn {field, value}, acc ->
        scope(acc, fn s -> Scope.eq(s, to_string(field), value) end)
      end)

    case one(qb) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Finds a record by specific field values, raising if not found.

  ## Examples

      product = QueryBuilder.new(Product)
        |> QueryBuilder.find_by!(slug: "my-product")
  """
  @spec find_by!(t(), keyword()) :: Ecto.Schema.t()
  def find_by!(%__MODULE__{} = qb, clauses) do
    case find_by(qb, clauses) do
      {:ok, record} -> record
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: qb.schema
    end
  end

  @doc """
  Counts the number of records matching the query.

  ## Examples

      count = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.count()
  """
  @spec count(t()) :: integer()
  def count(%__MODULE__{} = qb) do
    qb
    |> build_final_query()
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if any records exist matching the query.

  ## Examples

      exists = QueryBuilder.new(Product)
        |> QueryBuilder.scope(fn s -> s |> Scope.eq("slug", "my-product") end)
        |> QueryBuilder.exists?()
  """
  @spec exists?(t()) :: boolean()
  def exists?(%__MODULE__{} = qb) do
    qb
    |> build_final_query()
    |> Repo.exists?()
  end

  @doc """
  Calculates the sum of a numeric field.

  ## Examples

      total = QueryBuilder.new(Order)
        |> QueryBuilder.scope(fn s -> s |> Scope.status("completed") end)
        |> QueryBuilder.sum(:total)
  """
  @spec sum(t(), atom()) :: number() | nil
  def sum(%__MODULE__{} = qb, field) when is_atom(field) do
    qb
    |> build_final_query()
    |> Repo.aggregate(:sum, field)
  end

  @doc """
  Calculates the average of a numeric field.

  ## Examples

      avg_price = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.avg(:price)
  """
  @spec avg(t(), atom()) :: number() | nil
  def avg(%__MODULE__{} = qb, field) when is_atom(field) do
    qb
    |> build_final_query()
    |> Repo.aggregate(:avg, field)
  end

  @doc """
  Finds the minimum value of a field.

  ## Examples

      min_price = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.min(:price)
  """
  @spec min(t(), atom()) :: any()
  def min(%__MODULE__{} = qb, field) when is_atom(field) do
    qb
    |> build_final_query()
    |> select([q], field(q, ^field))
    |> order_by([q], asc: field(q, ^field))
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Finds the maximum value of a field.

  ## Examples

      max_price = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.max(:price)
  """
  @spec max(t(), atom()) :: any()
  def max(%__MODULE__{} = qb, field) when is_atom(field) do
    qb
    |> build_final_query()
    |> select([q], field(q, ^field))
    |> order_by([q], desc: field(q, ^field))
    |> limit(1)
    |> Repo.one()
  end

  ## Private Helpers

  defp build_final_query(%__MODULE__{} = qb) do
    query = qb.query

    # Apply soft delete filter
    query =
      if qb.exclude_deleted do
        from(q in query, where: is_nil(q.deleted_at))
      else
        query
      end

    # Apply scope
    query =
      if qb.scope && !Scope.empty?(qb.scope) do
        {sql, bindings} = Scope.to_sql(qb.scope)
        from(q in query, where: fragment(^sql, ^bindings))
      else
        query
      end

    # Apply limit
    query =
      if qb.limit_value do
        from(q in query, limit: ^qb.limit_value)
      else
        query
      end

    # Apply offset
    query =
      if qb.offset_value do
        from(q in query, offset: ^qb.offset_value)
      else
        query
      end

    # Apply order_by
    query =
      if qb.order_by_value do
        from(q in query, order_by: ^qb.order_by_value)
      else
        query
      end

    # Apply preload
    query =
      if qb.preloads != [] do
        from(q in query, preload: ^qb.preloads)
      else
        query
      end

    query
  end

  @doc """
  Returns a paginated result with metadata.

  ## Examples

      %{entries: products, metadata: metadata} = QueryBuilder.new(Product)
        |> QueryBuilder.active()
        |> QueryBuilder.paginate_with_metadata(page: 2, per_page: 20)

      # metadata contains:
      # %{
      #   page: 2,
      #   per_page: 20,
      #   total_count: 100,
      #   total_pages: 5,
      #   has_prev: true,
      #   has_next: true
      # }
  """
  @spec paginate_with_metadata(t(), keyword()) :: %{entries: list(), metadata: map()}
  def paginate_with_metadata(%__MODULE__{} = qb, opts) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    # Get total count
    total_count = count(qb)

    # Get entries
    entries =
      qb
      |> paginate(page: page, per_page: per_page)
      |> all()

    total_pages = ceil(total_count / per_page)

    %{
      entries: entries,
      metadata: %{
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages,
        has_prev: page > 1,
        has_next: page < total_pages
      }
    }
  end
end
