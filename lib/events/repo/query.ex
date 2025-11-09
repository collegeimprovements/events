defmodule Events.Repo.Query do
  @moduledoc """
  Simple, keyword-based query interface for database operations.

  This module provides a composable, keyword-based API for all database operations
  following the project's conventions:

  - **Keyword lists for all options**
  - **Simple function calls** - no builders or complex DSLs
  - **Composable** - easy to build on top of
  - **Pattern matching** - {:ok, result} | {:error, reason}
  - **Soft delete by default**

  ## Basic Usage

      # Fetch records
      Query.all(Product, where: [status: "active"], limit: 10)
      Query.one(Product, where: [id: id])
      Query.one!(Product, where: [slug: "my-product"])

      # Create
      {:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)

      # Update
      {:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)

      # Delete (soft by default)
      {:ok, product} = Query.delete(product, deleted_by: user_id)

      # Restore
      {:ok, product} = Query.restore(product)

  ## Query Options

  All query functions accept these options via keyword list:

  - `:where` - Filter conditions (keyword list or map)
  - `:limit` - Limit results
  - `:offset` - Offset for pagination
  - `:order_by` - Order results (e.g., `[desc: :inserted_at]`)
  - `:preload` - Preload associations
  - `:select` - Select specific fields
  - `:include_deleted` - Include soft-deleted records (default: false)

  ## Examples

      # Simple where clause
      Query.all(Product, where: [status: "active", type: "widget"])

      # With pagination
      Query.all(Product,
        where: [status: "active"],
        order_by: [desc: :inserted_at],
        limit: 20,
        offset: 40
      )

      # With preloads
      Query.all(Product,
        where: [status: "published"],
        preload: [:category, :tags]
      )

      # Count
      count = Query.count(Product, where: [status: "active"])

      # Exists?
      exists? = Query.exists?(Product, where: [slug: "my-product"])

  ## Transactions

      {:ok, results} = Query.transaction(fn ->
        with {:ok, product} <- Query.insert(Product, %{name: "Widget"}, created_by: user_id),
             {:ok, _} <- Query.update(product, %{status: "active"}, updated_by: user_id) do
          {:ok, product}
        end
      end)
  """

  import Ecto.Query
  alias Events.Repo

  @type schema :: module()
  @type queryable :: Ecto.Query.t() | module()
  @type attrs :: map()
  @type opts :: keyword()
  @type where_clause :: keyword() | map()

  ## Query Functions

  @doc """
  Fetches all records matching the given options.

  ## Options

  - `:where` - Filter conditions
  - `:limit` - Limit results
  - `:offset` - Offset for pagination
  - `:order_by` - Order results
  - `:preload` - Preload associations
  - `:include_deleted` - Include soft-deleted records (default: false)

  ## Examples

      Query.all(Product, where: [status: "active"], limit: 10)
      Query.all(Product, where: [type: "widget"], order_by: [desc: :price])
  """
  @spec all(schema(), opts()) :: [Ecto.Schema.t()]
  def all(schema, opts \\ []) do
    schema
    |> build_query(opts)
    |> Repo.all()
  end

  @doc """
  Fetches a single record matching the given options.

  Returns `nil` if no record is found.

  ## Examples

      Query.one(Product, where: [id: id])
      Query.one(Product, where: [slug: "my-product"])
  """
  @spec one(schema(), opts()) :: Ecto.Schema.t() | nil
  def one(schema, opts \\ []) do
    schema
    |> build_query(opts)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Fetches a single record, raising if not found.

  ## Examples

      product = Query.one!(Product, where: [id: id])
  """
  @spec one!(schema(), opts()) :: Ecto.Schema.t()
  def one!(schema, opts \\ []) do
    case one(schema, opts) do
      nil -> raise Ecto.NoResultsError, queryable: schema
      record -> record
    end
  end

  @doc """
  Fetches a record by ID.

  ## Options

  - `:preload` - Preload associations
  - `:include_deleted` - Include soft-deleted records (default: false)

  ## Examples

      {:ok, product} = Query.fetch(Product, id)
      {:ok, product} = Query.fetch(Product, id, preload: [:category])
  """
  @spec fetch(schema(), term(), opts()) :: {:ok, Ecto.Schema.t()} | {:error, :not_found}
  def fetch(schema, id, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)
    preloads = Keyword.get(opts, :preload, [])

    query = from(s in schema, where: s.id == ^id)

    query =
      if include_deleted do
        query
      else
        from(s in query, where: is_nil(s.deleted_at))
      end

    query =
      if preloads != [] do
        from(s in query, preload: ^preloads)
      else
        query
      end

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Fetches a record by ID, raising if not found.

  ## Examples

      product = Query.fetch!(Product, id)
  """
  @spec fetch!(schema(), term(), opts()) :: Ecto.Schema.t()
  def fetch!(schema, id, opts \\ []) do
    case fetch(schema, id, opts) do
      {:ok, record} -> record
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: schema
    end
  end

  @doc """
  Counts records matching the given options.

  ## Examples

      count = Query.count(Product, where: [status: "active"])
  """
  @spec count(schema(), opts()) :: integer()
  def count(schema, opts \\ []) do
    schema
    |> build_query(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if any records exist matching the given options.

  ## Examples

      exists? = Query.exists?(Product, where: [slug: "my-product"])
  """
  @spec exists?(schema(), opts()) :: boolean()
  def exists?(schema, opts \\ []) do
    schema
    |> build_query(opts)
    |> Repo.exists?()
  end

  ## CRUD Functions

  @doc """
  Inserts a new record.

  ## Options

  - `:created_by` - User ID for audit trail

  ## Examples

      {:ok, product} = Query.insert(Product, %{name: "Widget", price: 9.99}, created_by: user_id)
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

  ## Options

  - `:created_by` - User ID for audit trail

  ## Examples

      {:ok, products} = Query.insert_all(Product, [
        %{name: "Widget A"},
        %{name: "Widget B"}
      ], created_by: user_id)
  """
  @spec insert_all(schema(), [attrs()], opts()) :: {:ok, list()} | {:error, term()}
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

    case Repo.insert_all(schema, records, returning: true) do
      {_count, records} -> {:ok, records}
      error -> {:error, error}
    end
  end

  @doc """
  Updates a record.

  ## Options

  - `:updated_by` - User ID for audit trail

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
  Updates all records matching the given options.

  Returns `{:ok, count}` where count is the number of updated records.

  ## Options

  - `:where` - Filter conditions (required)
  - `:updated_by` - User ID for audit trail

  ## Examples

      {:ok, 5} = Query.update_all(Product,
        %{status: "published"},
        where: [status: "draft"],
        updated_by: user_id
      )
  """
  @spec update_all(schema(), attrs(), opts()) :: {:ok, integer()} | {:error, term()}
  def update_all(schema, attrs, opts \\ []) do
    attrs = add_audit_fields(attrs, :update, opts)
    updates = Map.to_list(attrs)

    query =
      schema
      |> build_query(opts)
      |> update(set: ^updates)

    case Repo.update_all(query, []) do
      {count, _} -> {:ok, count}
      error -> {:error, error}
    end
  end

  @doc """
  Soft deletes a record.

  ## Options

  - `:deleted_by` - User ID for audit trail
  - `:hard` - If true, permanently deletes the record (default: false)

  ## Examples

      # Soft delete
      {:ok, product} = Query.delete(product, deleted_by: user_id)

      # Hard delete
      {:ok, product} = Query.delete(product, hard: true)
  """
  @spec delete(Ecto.Schema.t(), opts()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(struct, opts \\ []) when is_struct(struct) do
    if Keyword.get(opts, :hard, false) do
      Repo.delete(struct)
    else
      soft_delete(struct, opts)
    end
  end

  @doc """
  Deletes all records matching the given options.

  Soft deletes by default. Use `hard: true` for permanent deletion.

  ## Options

  - `:where` - Filter conditions (required)
  - `:deleted_by` - User ID for audit trail
  - `:hard` - If true, permanently deletes (default: false)

  ## Examples

      {:ok, 3} = Query.delete_all(Product,
        where: [status: "draft"],
        deleted_by: user_id
      )
  """
  @spec delete_all(schema(), opts()) :: {:ok, integer()} | {:error, term()}
  def delete_all(schema, opts \\ []) do
    if Keyword.get(opts, :hard, false) do
      query = build_query(schema, opts)

      case Repo.delete_all(query) do
        {count, _} -> {:ok, count}
        error -> {:error, error}
      end
    else
      update_all(schema, %{deleted_at: DateTime.utc_now()}, opts)
    end
  end

  @doc """
  Soft deletes a record.

  ## Options

  - `:deleted_by` - User ID for audit trail

  ## Examples

      {:ok, product} = Query.soft_delete(product, deleted_by: user_id)
  """
  @spec soft_delete(Ecto.Schema.t(), opts()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def soft_delete(struct, opts \\ []) when is_struct(struct) do
    now = DateTime.utc_now()
    deleted_by = Keyword.get(opts, :deleted_by)

    changes = %{deleted_at: now}
    changes = maybe_put(changes, :deleted_by_urm_id, deleted_by)

    struct
    |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
    |> Repo.update()
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
  Restores all soft-deleted records matching the given options.

  ## Options

  - `:where` - Filter conditions (required)

  ## Examples

      {:ok, 2} = Query.restore_all(Product, where: [type: "widget"])
  """
  @spec restore_all(schema(), opts()) :: {:ok, integer()} | {:error, term()}
  def restore_all(schema, opts \\ []) do
    updates = [deleted_at: nil, deleted_by_urm_id: nil]

    query =
      schema
      |> build_query(opts)
      |> update(set: ^updates)

    case Repo.update_all(query, []) do
      {count, _} -> {:ok, count}
      error -> {:error, error}
    end
  end

  ## Transaction Functions

  @doc """
  Runs a function inside a transaction.

  ## Examples

      {:ok, result} = Query.transaction(fn ->
        with {:ok, product} <- Query.insert(Product, %{name: "Widget"}, created_by: user_id),
             {:ok, _} <- Query.update(product, %{status: "active"}, updated_by: user_id) do
          {:ok, product}
        end
      end)
  """
  @spec transaction((-> any())) :: {:ok, any()} | {:error, any()}
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fun)
  end

  ## Aggregation Functions

  @doc """
  Calculates the sum of a field.

  ## Examples

      total = Query.sum(Order, :total, where: [status: "completed"])
  """
  @spec sum(schema(), atom(), opts()) :: number() | nil
  def sum(schema, field, opts \\ []) when is_atom(field) do
    schema
    |> build_query(opts)
    |> Repo.aggregate(:sum, field)
  end

  @doc """
  Calculates the average of a field.

  ## Examples

      avg_price = Query.avg(Product, :price, where: [status: "active"])
  """
  @spec avg(schema(), atom(), opts()) :: number() | nil
  def avg(schema, field, opts \\ []) when is_atom(field) do
    schema
    |> build_query(opts)
    |> Repo.aggregate(:avg, field)
  end

  @doc """
  Finds the minimum value of a field.

  ## Examples

      min_price = Query.min(Product, :price, where: [status: "active"])
  """
  @spec min(schema(), atom(), opts()) :: any()
  def min(schema, field, opts \\ []) when is_atom(field) do
    schema
    |> build_query(opts)
    |> select([s], field(s, ^field))
    |> order_by([s], asc: field(s, ^field))
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Finds the maximum value of a field.

  ## Examples

      max_price = Query.max(Product, :price, where: [status: "active"])
  """
  @spec max(schema(), atom(), opts()) :: any()
  def max(schema, field, opts \\ []) when is_atom(field) do
    schema
    |> build_query(opts)
    |> select([s], field(s, ^field))
    |> order_by([s], desc: field(s, ^field))
    |> limit(1)
    |> Repo.one()
  end

  ## Helper Functions

  @doc """
  Returns records that are not soft-deleted.

  ## Examples

      products = Product |> Query.not_deleted() |> Repo.all()
  """
  @spec not_deleted(queryable()) :: Ecto.Query.t()
  def not_deleted(query) do
    from(q in query, where: is_nil(q.deleted_at))
  end

  @doc """
  Returns only soft-deleted records.

  ## Examples

      deleted = Product |> Query.only_deleted() |> Repo.all()
  """
  @spec only_deleted(queryable()) :: Ecto.Query.t()
  def only_deleted(query) do
    from(q in query, where: not is_nil(q.deleted_at))
  end

  @doc """
  Returns records with active status and not deleted.

  ## Examples

      active = Product |> Query.active() |> Repo.all()
  """
  @spec active(queryable()) :: Ecto.Query.t()
  def active(query) do
    from(q in query,
      where: q.status == "active",
      where: is_nil(q.deleted_at)
    )
  end

  ## Private Functions

  defp build_query(schema, opts) do
    query = from(s in schema)

    # Apply soft delete filter (unless explicitly including deleted)
    query =
      if Keyword.get(opts, :include_deleted, false) do
        query
      else
        from(s in query, where: is_nil(s.deleted_at))
      end

    # Apply where clause
    query =
      case Keyword.get(opts, :where) do
        nil -> query
        where_clause -> apply_where(query, where_clause)
      end

    # Apply limit
    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit_value -> from(s in query, limit: ^limit_value)
      end

    # Apply offset
    query =
      case Keyword.get(opts, :offset) do
        nil -> query
        offset_value -> from(s in query, offset: ^offset_value)
      end

    # Apply order_by
    query =
      case Keyword.get(opts, :order_by) do
        nil -> query
        order_value -> from(s in query, order_by: ^order_value)
      end

    # Apply preload
    query =
      case Keyword.get(opts, :preload) do
        nil -> query
        [] -> query
        preload_value -> from(s in query, preload: ^preload_value)
      end

    # Apply select
    case Keyword.get(opts, :select) do
      nil -> query
      select_fields -> from(s in query, select: ^select_fields)
    end
  end

  defp apply_where(query, where_clause) when is_list(where_clause) or is_map(where_clause) do
    Enum.reduce(where_clause, query, fn {field, value}, acc ->
      from(s in acc, where: field(s, ^field) == ^value)
    end)
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
