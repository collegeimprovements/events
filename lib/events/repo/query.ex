defmodule Events.Repo.Query do
  @moduledoc """
  Simple CRUD helpers that compose naturally with Ecto.Query.

  This module provides simple functions that work seamlessly with Ecto's
  `from` syntax and keyword-based queries.

  ## Basic Usage

      # Works with schemas
      Query.all(Product)

      # Works with Ecto queries
      from(p in Product, where: p.status == "active")
      |> Query.all()

      # Supports keyword where clauses
      Query.all(Product, where: [status: "active", type: "widget"])

      # Composable
      from(p in Product, where: p.price > 10)
      |> Query.where(status: "active")
      |> Query.order_by(desc: :inserted_at)
      |> Query.limit(10)
      |> Query.all()

  ## CRUD Operations

      # Insert
      {:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)

      # Update
      {:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)

      # Delete (soft by default)
      {:ok, product} = Query.delete(product, deleted_by: user_id)

      # Update all matching a query
      from(p in Product, where: p.status == "draft")
      |> Query.update_all([set: [status: "published"]], updated_by: user_id)
  """

  import Ecto.Query
  alias Events.Repo

  @type queryable :: Ecto.Query.t() | module()
  @type schema :: module()
  @type attrs :: map()
  @type opts :: keyword()

  ## Query Functions

  @doc """
  Fetches all records.

  Automatically excludes soft-deleted records unless `:include_deleted` is true.

  ## Examples

      Query.all(Product)

      from(p in Product, where: p.status == "active")
      |> Query.all()

      Query.all(Product, where: [status: "active"])
      Query.all(Product, where: [status: "active"], include_deleted: true)
  """
  @spec all(queryable(), opts()) :: [Ecto.Schema.t()]
  def all(queryable, opts \\ []) do
    queryable
    |> maybe_filter_deleted(opts)
    |> maybe_apply_where(opts)
    |> Repo.all()
  end

  @doc """
  Fetches a single record.

  Returns `nil` if no record is found.

  ## Examples

      Query.one(Product)

      from(p in Product, where: p.slug == ^slug)
      |> Query.one()

      Query.one(Product, where: [slug: "my-product"])
  """
  @spec one(queryable(), opts()) :: Ecto.Schema.t() | nil
  def one(queryable, opts \\ []) do
    queryable
    |> maybe_filter_deleted(opts)
    |> maybe_apply_where(opts)
    |> Repo.one()
  end

  @doc """
  Fetches a single record, raising if not found.

  ## Examples

      from(p in Product, where: p.id == ^id)
      |> Query.one!()
  """
  @spec one!(queryable(), opts()) :: Ecto.Schema.t()
  def one!(queryable, opts \\ []) do
    queryable
    |> maybe_filter_deleted(opts)
    |> maybe_apply_where(opts)
    |> Repo.one!()
  end

  @doc """
  Fetches a record by ID.

  ## Examples

      {:ok, product} = Query.get(Product, id)
      {:ok, product} = Query.get(Product, id, include_deleted: true)
  """
  @spec get(schema(), term(), opts()) :: {:ok, Ecto.Schema.t()} | {:error, :not_found}
  def get(schema, id, opts \\ []) do
    case from(s in schema, where: s.id == ^id)
         |> maybe_filter_deleted(opts)
         |> Repo.one() do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Fetches a record by ID, raising if not found.

  ## Examples

      product = Query.get!(Product, id)
  """
  @spec get!(schema(), term(), opts()) :: Ecto.Schema.t()
  def get!(schema, id, opts \\ []) do
    case get(schema, id, opts) do
      {:ok, record} -> record
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: schema
    end
  end

  @doc """
  Counts records.

  ## Examples

      Query.count(Product)

      from(p in Product, where: p.status == "active")
      |> Query.count()

      Query.count(Product, where: [status: "active"])
  """
  @spec count(queryable(), opts()) :: integer()
  def count(queryable, opts \\ []) do
    queryable
    |> maybe_filter_deleted(opts)
    |> maybe_apply_where(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if any records exist.

  ## Examples

      from(p in Product, where: p.slug == ^slug)
      |> Query.exists?()
  """
  @spec exists?(queryable(), opts()) :: boolean()
  def exists?(queryable, opts \\ []) do
    queryable
    |> maybe_filter_deleted(opts)
    |> maybe_apply_where(opts)
    |> Repo.exists?()
  end

  ## CRUD Operations

  @doc """
  Inserts a new record.

  ## Examples

      {:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)
  """
  @spec insert(schema(), attrs(), opts()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def insert(schema, attrs, opts \\ []) do
    attrs = add_audit_fields(attrs, :insert, opts)

    changeset =
      if function_exported?(schema, :changeset, 2) do
        schema.__struct__() |> schema.changeset(attrs)
      else
        schema.__struct__() |> Ecto.Changeset.cast(attrs, Map.keys(attrs))
      end

    Repo.insert(changeset)
  end

  @doc """
  Inserts multiple records.

  ## Examples

      {:ok, {3, products}} = Query.insert_all(Product, [
        %{name: "A"},
        %{name: "B"},
        %{name: "C"}
      ], created_by: user_id)
  """
  @spec insert_all(schema(), [attrs()], opts()) :: {:ok, {integer(), list()}} | {:error, term()}
  def insert_all(schema, records, opts \\ []) when is_list(records) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    created_by = Keyword.get(opts, :created_by)

    records =
      Enum.map(records, fn record ->
        record
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
        |> maybe_put(:created_by_urm_id, created_by)
        |> maybe_put(:updated_by_urm_id, created_by)
      end)

    {count, results} = Repo.insert_all(schema, records, returning: true)
    {:ok, {count, results}}
  end

  @doc """
  Updates a record.

  ## Examples

      {:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)
  """
  @spec update(Ecto.Schema.t(), attrs(), opts()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def update(struct, attrs, opts \\ []) when is_struct(struct) do
    attrs = add_audit_fields(attrs, :update, opts)
    schema = struct.__struct__

    changeset =
      if function_exported?(schema, :changeset, 2) do
        schema.changeset(struct, attrs)
      else
        Ecto.Changeset.cast(struct, attrs, Map.keys(attrs))
      end

    Repo.update(changeset)
  end

  @doc """
  Updates all records matching a query.

  ## Examples

      # Using from query
      from(p in Product, where: p.status == "draft")
      |> Query.update_all([set: [status: "published"]], updated_by: user_id)

      # Using keyword where
      Query.update_all(Product, [set: [status: "published"]],
        where: [status: "draft"],
        updated_by: user_id
      )
  """
  @spec update_all(queryable(), keyword(), opts()) :: {:ok, integer()} | {:error, term()}
  def update_all(queryable, updates, opts \\ []) do
    # Add audit fields to updates if provided
    updates =
      case Keyword.get(opts, :updated_by) do
        nil -> updates
        user_id -> Keyword.put(updates, :set, Keyword.get(updates, :set, []) ++ [updated_by_urm_id: user_id])
      end

    query =
      queryable
      |> maybe_filter_deleted(opts)
      |> maybe_apply_where(opts)

    {count, _} = Repo.update_all(query, updates)
    {:ok, count}
  end

  @doc """
  Soft deletes a record.

  Use `hard: true` for permanent deletion.

  ## Examples

      {:ok, product} = Query.delete(product, deleted_by: user_id)
      {:ok, product} = Query.delete(product, hard: true)
  """
  @spec delete(Ecto.Schema.t(), opts()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(struct, opts \\ []) when is_struct(struct) do
    if Keyword.get(opts, :hard, false) do
      Repo.delete(struct)
    else
      now = DateTime.utc_now()
      deleted_by = Keyword.get(opts, :deleted_by)

      changes = %{deleted_at: now}
      changes = maybe_put(changes, :deleted_by_urm_id, deleted_by)

      struct
      |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
      |> Repo.update()
    end
  end

  @doc """
  Deletes all records matching a query.

  Soft deletes by default. Use `hard: true` for permanent deletion.

  ## Examples

      # Soft delete
      from(p in Product, where: p.status == "draft")
      |> Query.delete_all(deleted_by: user_id)

      # Hard delete
      from(p in Product, where: p.status == "draft")
      |> Query.delete_all(hard: true)

      # With keyword where
      Query.delete_all(Product, where: [status: "draft"], deleted_by: user_id)
  """
  @spec delete_all(queryable(), opts()) :: {:ok, integer()} | {:error, term()}
  def delete_all(queryable, opts \\ []) do
    if Keyword.get(opts, :hard, false) do
      query =
        queryable
        |> maybe_filter_deleted(opts)
        |> maybe_apply_where(opts)

      {count, _} = Repo.delete_all(query)
      {:ok, count}
    else
      now = DateTime.utc_now()
      deleted_by = Keyword.get(opts, :deleted_by)

      updates = [set: [deleted_at: now]]

      updates =
        if deleted_by do
          Keyword.put(updates, :set, Keyword.get(updates, :set) ++ [deleted_by_urm_id: deleted_by])
        else
          updates
        end

      query =
        queryable
        |> maybe_filter_deleted(opts)
        |> maybe_apply_where(opts)

      {count, _} = Repo.update_all(query, updates)
      {:ok, count}
    end
  end

  @doc """
  Restores a soft-deleted record.

  ## Examples

      {:ok, product} = Query.restore(product)
  """
  @spec restore(Ecto.Schema.t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def restore(struct) when is_struct(struct) do
    struct
    |> Ecto.Changeset.cast(%{deleted_at: nil, deleted_by_urm_id: nil}, [
      :deleted_at,
      :deleted_by_urm_id
    ])
    |> Repo.update()
  end

  @doc """
  Restores all soft-deleted records matching a query.

  ## Examples

      from(p in Product, where: p.type == "widget")
      |> Query.restore_all()

      Query.restore_all(Product, where: [type: "widget"])
  """
  @spec restore_all(queryable(), opts()) :: {:ok, integer()} | {:error, term()}
  def restore_all(queryable, opts \\ []) do
    updates = [set: [deleted_at: nil, deleted_by_urm_id: nil]]

    query =
      queryable
      |> maybe_apply_where(opts)
      |> where([q], not is_nil(q.deleted_at))

    {count, _} = Repo.update_all(query, updates)
    {:ok, count}
  end

  ## Transaction

  @doc """
  Runs a function inside a transaction.

  ## Examples

      {:ok, product} = Query.transaction(fn ->
        with {:ok, product} <- Query.insert(Product, attrs, created_by: user_id),
             {:ok, _} <- Query.update(category, %{count: count + 1}, updated_by: user_id) do
          {:ok, product}
        end
      end)
  """
  @spec transaction((-> any())) :: {:ok, any()} | {:error, any()}
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fun)
  end

  ## Query Helpers - Composable with from

  @doc """
  Adds where conditions to a query.

  Composable with Ecto.Query.

  ## Examples

      Product
      |> Query.where(status: "active")
      |> Query.where(type: "widget")
      |> Query.all()

      from(p in Product, where: p.price > 10)
      |> Query.where(status: "active")
      |> Query.all()
  """
  @spec where(queryable(), keyword()) :: Ecto.Query.t()
  def where(queryable, conditions) when is_list(conditions) do
    Enum.reduce(conditions, queryable, fn {field, value}, query ->
      from(q in query, where: field(q, ^field) == ^value)
    end)
  end

  @doc """
  Adds a limit to a query.

  ## Examples

      Product
      |> Query.where(status: "active")
      |> Query.limit(10)
      |> Query.all()
  """
  @spec limit(queryable(), pos_integer()) :: Ecto.Query.t()
  def limit(queryable, value) when is_integer(value) and value > 0 do
    from(q in queryable, limit: ^value)
  end

  @doc """
  Adds an offset to a query.

  ## Examples

      Product
      |> Query.offset(20)
      |> Query.limit(10)
      |> Query.all()
  """
  @spec offset(queryable(), non_neg_integer()) :: Ecto.Query.t()
  def offset(queryable, value) when is_integer(value) and value >= 0 do
    from(q in queryable, offset: ^value)
  end

  @doc """
  Adds ordering to a query.

  ## Examples

      Product
      |> Query.order_by(desc: :inserted_at)
      |> Query.all()

      Product
      |> Query.order_by([asc: :name, desc: :price])
      |> Query.all()
  """
  @spec order_by(queryable(), keyword()) :: Ecto.Query.t()
  def order_by(queryable, ordering) when is_list(ordering) do
    from(q in queryable, order_by: ^ordering)
  end

  @doc """
  Adds preloads to a query.

  ## Examples

      Product
      |> Query.preload([:category, :tags])
      |> Query.all()
  """
  @spec preload(queryable(), list()) :: Ecto.Query.t()
  def preload(queryable, assocs) when is_list(assocs) do
    from(q in queryable, preload: ^assocs)
  end

  @doc """
  Paginates a query.

  ## Examples

      Product
      |> Query.paginate(page: 2, per_page: 20)
      |> Query.all()
  """
  @spec paginate(queryable(), keyword()) :: Ecto.Query.t()
  def paginate(queryable, opts) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    queryable
    |> limit(per_page)
    |> offset((page - 1) * per_page)
  end

  ## Soft Delete Scopes

  @doc """
  Filters out soft-deleted records.

  ## Examples

      Product
      |> Query.not_deleted()
      |> Repo.all()

      from(p in Product, where: p.status == "active")
      |> Query.not_deleted()
      |> Repo.all()
  """
  @spec not_deleted(queryable()) :: Ecto.Query.t()
  def not_deleted(queryable) do
    from(q in queryable, where: is_nil(q.deleted_at))
  end

  @doc """
  Returns only soft-deleted records.

  ## Examples

      Product
      |> Query.only_deleted()
      |> Repo.all()
  """
  @spec only_deleted(queryable()) :: Ecto.Query.t()
  def only_deleted(queryable) do
    from(q in queryable, where: not is_nil(q.deleted_at))
  end

  @doc """
  Filters for active status and not deleted.

  ## Examples

      Product
      |> Query.active()
      |> Repo.all()
  """
  @spec active(queryable()) :: Ecto.Query.t()
  def active(queryable) do
    from(q in queryable,
      where: q.status == "active",
      where: is_nil(q.deleted_at)
    )
  end

  ## Aggregations

  @doc """
  Calculates the sum of a field.

  ## Examples

      from(o in Order, where: o.status == "completed")
      |> Query.sum(:total)
  """
  @spec sum(queryable(), atom()) :: number() | nil
  def sum(queryable, field) when is_atom(field) do
    queryable
    |> Repo.aggregate(:sum, field)
  end

  @doc """
  Calculates the average of a field.

  ## Examples

      Product
      |> Query.not_deleted()
      |> Query.avg(:price)
  """
  @spec avg(queryable(), atom()) :: number() | nil
  def avg(queryable, field) when is_atom(field) do
    queryable
    |> Repo.aggregate(:avg, field)
  end

  @doc """
  Finds the minimum value of a field.

  ## Examples

      Product |> Query.min(:price)
  """
  @spec min(queryable(), atom()) :: any()
  def min(queryable, field) when is_atom(field) do
    queryable
    |> select([q], field(q, ^field))
    |> order_by([q], asc: field(q, ^field))
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Finds the maximum value of a field.

  ## Examples

      Product |> Query.max(:price)
  """
  @spec max(queryable(), atom()) :: any()
  def max(queryable, field) when is_atom(field) do
    queryable
    |> select([q], field(q, ^field))
    |> order_by([q], desc: field(q, ^field))
    |> limit(1)
    |> Repo.one()
  end

  ## Private Helpers

  defp maybe_filter_deleted(queryable, opts) do
    if Keyword.get(opts, :include_deleted, false) do
      queryable
    else
      not_deleted(queryable)
    end
  end

  defp maybe_apply_where(queryable, opts) do
    case Keyword.get(opts, :where) do
      nil -> queryable
      conditions -> where(queryable, conditions)
    end
  end

  defp add_audit_fields(attrs, :insert, opts) do
    created_by = Keyword.get(opts, :created_by)

    attrs
    |> maybe_put(:created_by_urm_id, created_by)
    |> maybe_put(:updated_by_urm_id, created_by)
  end

  defp add_audit_fields(attrs, :update, opts) do
    updated_by = Keyword.get(opts, :updated_by)
    maybe_put(attrs, :updated_by_urm_id, updated_by)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
