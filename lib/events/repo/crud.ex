defmodule Events.Repo.Crud do
  @moduledoc """
  A comprehensive CRUD DSL for database operations with built-in support for:
  - SQL scopes for filtering
  - Soft delete operations
  - Audit tracking (created_by, updated_by, deleted_by)
  - Ecto.Multi integration for transactions
  - Chainable query building

  ## Features

  - **Soft Delete by Default**: Delete operations soft delete by default, preserving data
  - **Scope Integration**: Uses `Events.Repo.SqlScope.Scope` for powerful filtering
  - **Audit Trail**: Automatically tracks who created, updated, or deleted records
  - **Type Safety**: Compile-time checks and runtime validation
  - **Multi Support**: Build complex transactions with Ecto.Multi

  ## Basic Usage

      # Create
      Crud.new(Product)
      |> Crud.insert(%{name: "Widget", price: 9.99}, created_by: user_id)
      |> Crud.execute()

      # Read with scopes
      Crud.new(Product)
      |> Crud.where(fn scope ->
        scope
        |> Scope.active()
        |> Scope.status("published")
        |> Scope.gte("price", 10.00)
      end)
      |> Crud.select()
      |> Crud.execute()

      # Update with scopes
      Crud.new(Product)
      |> Crud.where(fn scope ->
        scope |> Scope.eq("id", product_id)
      end)
      |> Crud.update(%{price: 12.99}, updated_by: user_id)
      |> Crud.execute()

      # Soft delete
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
      |> Crud.delete(deleted_by: user_id)
      |> Crud.execute()

      # Hard delete (permanent)
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
      |> Crud.delete(deleted_by: user_id, hard: true)
      |> Crud.execute()

  ## Ecto.Multi Integration

      Multi.new()
      |> Crud.multi_insert(:create_product, Product, %{name: "Widget"}, created_by: user_id)
      |> Crud.multi_update(:update_price, Product, fn scope ->
        scope |> Scope.eq("type", "widget")
      end, %{price: 15.99}, updated_by: user_id)
      |> Crud.multi_delete(:archive_old, Product, fn scope ->
        scope |> Scope.lt("updated_at", old_date)
      end, deleted_by: user_id)
      |> Repo.transaction()

  ## Batch Operations

      # Insert multiple records
      Crud.new(Product)
      |> Crud.insert_all([
        %{name: "Widget A", price: 9.99},
        %{name: "Widget B", price: 12.99}
      ], created_by: user_id)
      |> Crud.execute()

      # Update all matching records
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.status("draft") end)
      |> Crud.update_all(%{status: "published"}, updated_by: user_id)
      |> Crud.execute()

  ## Advanced Queries

      # Pagination
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.active() end)
      |> Crud.select()
      |> Crud.limit(20)
      |> Crud.offset(40)
      |> Crud.order_by([desc: :inserted_at])
      |> Crud.execute()

      # Counting
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.active() end)
      |> Crud.count()
      |> Crud.execute()

      # Check existence
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("slug", "my-product") end)
      |> Crud.exists?()
      |> Crud.execute()
  """

  alias Events.Repo
  alias Events.Repo.SqlScope.Scope
  alias Ecto.Multi
  import Ecto.Query

  @type schema_module :: module()
  @type attrs :: map()
  @type scope_builder :: (Scope.t() -> Scope.t())
  @type user_id :: binary()

  @type operation ::
          :insert
          | :insert_all
          | :select
          | :select_one
          | :update
          | :update_all
          | :delete
          | :delete_all
          | :count
          | :exists

  @type t :: %__MODULE__{
          schema: schema_module() | nil,
          operation: operation() | nil,
          scope: Scope.t() | nil,
          attrs: attrs() | [attrs()] | nil,
          options: keyword(),
          query: Ecto.Query.t() | nil,
          limit_value: integer() | nil,
          offset_value: integer() | nil,
          order_by_value: keyword() | nil,
          preload_value: list() | nil
        }

  defstruct [
    :schema,
    :operation,
    :scope,
    :attrs,
    :options,
    :query,
    :limit_value,
    :offset_value,
    :order_by_value,
    :preload_value
  ]

  ## Builder Functions

  @doc """
  Creates a new CRUD operation builder for the given schema.

  ## Examples

      Crud.new(Product)
      Crud.new(User)
  """
  @spec new(schema_module()) :: t()
  def new(schema) when is_atom(schema) do
    %__MODULE__{
      schema: schema,
      scope: Scope.new(),
      options: []
    }
  end

  @doc """
  Adds a WHERE clause using the Scope DSL.

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope ->
        scope
        |> Scope.active()
        |> Scope.status("published")
        |> Scope.gte("price", 10.00)
      end)
  """
  @spec where(t(), scope_builder()) :: t()
  def where(%__MODULE__{} = crud, scope_builder) when is_function(scope_builder, 1) do
    new_scope = scope_builder.(crud.scope || Scope.new())
    %{crud | scope: new_scope}
  end

  @doc """
  Sets a limit on the number of records returned.

  ## Examples

      Crud.new(Product) |> Crud.limit(10)
  """
  @spec limit(t(), integer()) :: t()
  def limit(%__MODULE__{} = crud, value) when is_integer(value) and value > 0 do
    %{crud | limit_value: value}
  end

  @doc """
  Sets an offset for pagination.

  ## Examples

      Crud.new(Product) |> Crud.offset(20)
  """
  @spec offset(t(), integer()) :: t()
  def offset(%__MODULE__{} = crud, value) when is_integer(value) and value >= 0 do
    %{crud | offset_value: value}
  end

  @doc """
  Sets the order for results.

  ## Examples

      Crud.new(Product) |> Crud.order_by([desc: :inserted_at])
      Crud.new(Product) |> Crud.order_by([asc: :name, desc: :price])
  """
  @spec order_by(t(), keyword()) :: t()
  def order_by(%__MODULE__{} = crud, value) when is_list(value) do
    %{crud | order_by_value: value}
  end

  @doc """
  Sets associations to preload.

  ## Examples

      Crud.new(Product) |> Crud.preload([:category, :tags])
      Crud.new(Product) |> Crud.preload([category: :parent])
  """
  @spec preload(t(), list()) :: t()
  def preload(%__MODULE__{} = crud, value) when is_list(value) do
    %{crud | preload_value: value}
  end

  ## CRUD Operations

  @doc """
  Inserts a single record.

  ## Options

  - `:created_by` - User ID for audit trail
  - `:returning` - Fields to return (default: `true`)

  ## Examples

      Crud.new(Product)
      |> Crud.insert(%{name: "Widget", price: 9.99}, created_by: user_id)
      |> Crud.execute()
  """
  @spec insert(t(), attrs(), keyword()) :: t()
  def insert(%__MODULE__{schema: schema} = crud, attrs, opts \\ []) when is_map(attrs) do
    attrs_with_audit = add_audit_fields(attrs, :insert, opts)

    %{crud | operation: :insert, attrs: attrs_with_audit, options: opts}
  end

  @doc """
  Inserts multiple records in a single operation.

  ## Options

  - `:created_by` - User ID for audit trail
  - `:returning` - Fields to return (default: `true`)

  ## Examples

      Crud.new(Product)
      |> Crud.insert_all([
        %{name: "Widget A", price: 9.99},
        %{name: "Widget B", price: 12.99}
      ], created_by: user_id)
      |> Crud.execute()
  """
  @spec insert_all(t(), [attrs()], keyword()) :: t()
  def insert_all(%__MODULE__{} = crud, attrs_list, opts \\ []) when is_list(attrs_list) do
    attrs_with_audit = Enum.map(attrs_list, &add_audit_fields(&1, :insert, opts))

    %{crud | operation: :insert_all, attrs: attrs_with_audit, options: opts}
  end

  @doc """
  Selects records matching the current scope.

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.active() end)
      |> Crud.select()
      |> Crud.execute()
  """
  @spec select(t()) :: t()
  def select(%__MODULE__{} = crud) do
    %{crud | operation: :select}
  end

  @doc """
  Selects a single record matching the current scope.

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", product_id) end)
      |> Crud.select_one()
      |> Crud.execute()
  """
  @spec select_one(t()) :: t()
  def select_one(%__MODULE__{} = crud) do
    %{crud | operation: :select_one, limit_value: 1}
  end

  @doc """
  Updates a single record (use with select_one or provide a struct).

  ## Options

  - `:updated_by` - User ID for audit trail

  ## Examples

      # Update by scope
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", id) end)
      |> Crud.update(%{price: 12.99}, updated_by: user_id)
      |> Crud.execute()

      # Update struct directly
      Crud.new(Product)
      |> Crud.update(product, %{price: 12.99}, updated_by: user_id)
      |> Crud.execute()
  """
  @spec update(t(), attrs() | Ecto.Schema.t(), keyword()) :: t()
  def update(%__MODULE__{} = crud, attrs, opts \\ [])

  def update(%__MODULE__{} = crud, attrs, opts) when is_map(attrs) and not is_struct(attrs) do
    attrs_with_audit = add_audit_fields(attrs, :update, opts)
    %{crud | operation: :update, attrs: attrs_with_audit, options: opts}
  end

  @doc """
  Updates a struct directly.

  ## Examples

      Crud.new(Product)
      |> Crud.update(product_struct, %{price: 12.99}, updated_by: user_id)
      |> Crud.execute()
  """
  @spec update(t(), Ecto.Schema.t(), attrs(), keyword()) :: t()
  def update(%__MODULE__{} = crud, struct, attrs, opts)
      when is_struct(struct) and is_map(attrs) do
    attrs_with_audit = add_audit_fields(attrs, :update, opts)
    %{crud | operation: :update, attrs: {struct, attrs_with_audit}, options: opts}
  end

  @doc """
  Updates all records matching the current scope.

  ## Options

  - `:updated_by` - User ID for audit trail

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.status("draft") end)
      |> Crud.update_all(%{status: "published"}, updated_by: user_id)
      |> Crud.execute()
  """
  @spec update_all(t(), attrs(), keyword()) :: t()
  def update_all(%__MODULE__{} = crud, attrs, opts \\ []) when is_map(attrs) do
    attrs_with_audit = add_audit_fields(attrs, :update, opts)
    %{crud | operation: :update_all, attrs: attrs_with_audit, options: opts}
  end

  @doc """
  Deletes records matching the current scope.

  By default, performs a soft delete. Use `hard: true` for permanent deletion.

  ## Options

  - `:deleted_by` - User ID for audit trail (soft delete only)
  - `:hard` - If true, permanently deletes the record (default: false)

  ## Examples

      # Soft delete
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", id) end)
      |> Crud.delete(deleted_by: user_id)
      |> Crud.execute()

      # Hard delete
      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", id) end)
      |> Crud.delete(hard: true)
      |> Crud.execute()
  """
  @spec delete(t(), keyword()) :: t()
  def delete(%__MODULE__{} = crud, opts \\ []) do
    if Keyword.get(opts, :hard, false) do
      %{crud | operation: :delete_all, options: opts}
    else
      # Soft delete is just an update
      now = DateTime.utc_now()

      attrs = %{deleted_at: now}

      attrs =
        if deleted_by = Keyword.get(opts, :deleted_by) do
          Map.put(attrs, :deleted_by_urm_id, deleted_by)
        else
          attrs
        end

      %{crud | operation: :update_all, attrs: attrs, options: opts}
    end
  end

  @doc """
  Restores a soft-deleted record.

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("id", id) end)
      |> Crud.restore()
      |> Crud.execute()
  """
  @spec restore(t()) :: t()
  def restore(%__MODULE__{} = crud) do
    attrs = %{deleted_at: nil, deleted_by_urm_id: nil}
    %{crud | operation: :update_all, attrs: attrs, options: []}
  end

  @doc """
  Counts records matching the current scope.

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.active() end)
      |> Crud.count()
      |> Crud.execute()
  """
  @spec count(t()) :: t()
  def count(%__MODULE__{} = crud) do
    %{crud | operation: :count}
  end

  @doc """
  Checks if any records exist matching the current scope.

  ## Examples

      Crud.new(Product)
      |> Crud.where(fn scope -> scope |> Scope.eq("slug", "my-product") end)
      |> Crud.exists?()
      |> Crud.execute()
  """
  @spec exists?(t()) :: t()
  def exists?(%__MODULE__{} = crud) do
    %{crud | operation: :exists}
  end

  ## Execution

  @doc """
  Executes the built CRUD operation.

  Returns `{:ok, result}` or `{:error, reason}`.

  ## Examples

      {:ok, product} = Crud.new(Product)
        |> Crud.insert(%{name: "Widget"}, created_by: user_id)
        |> Crud.execute()

      {:ok, products} = Crud.new(Product)
        |> Crud.where(fn scope -> scope |> Scope.active() end)
        |> Crud.select()
        |> Crud.execute()
  """
  @spec execute(t()) :: {:ok, any()} | {:error, any()}
  def execute(%__MODULE__{} = crud) do
    case crud.operation do
      :insert -> execute_insert(crud)
      :insert_all -> execute_insert_all(crud)
      :select -> execute_select(crud)
      :select_one -> execute_select_one(crud)
      :update -> execute_update(crud)
      :update_all -> execute_update_all(crud)
      :delete_all -> execute_delete_all(crud)
      :count -> execute_count(crud)
      :exists -> execute_exists(crud)
      nil -> {:error, :no_operation_specified}
    end
  end

  @doc """
  Executes the built CRUD operation, raising on error.

  ## Examples

      product = Crud.new(Product)
        |> Crud.insert(%{name: "Widget"}, created_by: user_id)
        |> Crud.execute!()
  """
  @spec execute!(t()) :: any()
  def execute!(%__MODULE__{} = crud) do
    case execute(crud) do
      {:ok, result} -> result
      {:error, reason} -> raise "CRUD operation failed: #{inspect(reason)}"
    end
  end

  ## Ecto.Multi Integration

  @doc """
  Adds an insert operation to an Ecto.Multi.

  ## Examples

      Multi.new()
      |> Crud.multi_insert(:create_product, Product, %{name: "Widget"}, created_by: user_id)
      |> Repo.transaction()
  """
  @spec multi_insert(Multi.t(), atom(), schema_module(), attrs(), keyword()) :: Multi.t()
  def multi_insert(%Multi{} = multi, name, schema, attrs, opts \\ []) do
    attrs_with_audit = add_audit_fields(attrs, :insert, opts)
    changeset = schema.__struct__() |> Ecto.Changeset.cast(attrs_with_audit, Map.keys(attrs_with_audit))

    Multi.insert(multi, name, changeset)
  end

  @doc """
  Adds an update_all operation to an Ecto.Multi using a scope.

  ## Examples

      Multi.new()
      |> Crud.multi_update_all(:update_prices, Product, fn scope ->
        scope |> Scope.eq("category", "widgets")
      end, %{price: 9.99}, updated_by: user_id)
      |> Repo.transaction()
  """
  @spec multi_update_all(Multi.t(), atom(), schema_module(), scope_builder(), attrs(), keyword()) ::
          Multi.t()
  def multi_update_all(%Multi{} = multi, name, schema, scope_builder, attrs, opts \\ []) do
    Multi.run(multi, name, fn repo, _changes ->
      crud =
        new(schema)
        |> where(scope_builder)
        |> update_all(attrs, opts)

      execute_update_all(crud)
    end)
  end

  @doc """
  Adds a delete (soft delete) operation to an Ecto.Multi using a scope.

  ## Examples

      Multi.new()
      |> Crud.multi_delete(:archive_product, Product, fn scope ->
        scope |> Scope.eq("id", product_id)
      end, deleted_by: user_id)
      |> Repo.transaction()
  """
  @spec multi_delete(Multi.t(), atom(), schema_module(), scope_builder(), keyword()) :: Multi.t()
  def multi_delete(%Multi{} = multi, name, schema, scope_builder, opts \\ []) do
    Multi.run(multi, name, fn repo, _changes ->
      crud =
        new(schema)
        |> where(scope_builder)
        |> delete(opts)

      execute(crud)
    end)
  end

  ## Private Helpers

  defp add_audit_fields(attrs, :insert, opts) do
    attrs
    |> maybe_add_field(:created_by_urm_id, Keyword.get(opts, :created_by))
    |> maybe_add_field(:updated_by_urm_id, Keyword.get(opts, :created_by))
  end

  defp add_audit_fields(attrs, :update, opts) do
    maybe_add_field(attrs, :updated_by_urm_id, Keyword.get(opts, :updated_by))
  end

  defp maybe_add_field(attrs, _field, nil), do: attrs

  defp maybe_add_field(attrs, field, value) do
    Map.put(attrs, field, value)
  end

  defp execute_insert(%__MODULE__{schema: schema, attrs: attrs}) do
    changeset =
      schema.__struct__()
      |> Ecto.Changeset.cast(attrs, Map.keys(attrs))

    Repo.insert(changeset)
  end

  defp execute_insert_all(%__MODULE__{schema: schema, attrs: attrs_list, options: opts}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Add timestamps if not present
    attrs_list =
      Enum.map(attrs_list, fn attrs ->
        attrs
        |> Map.put_new(:inserted_at, now)
        |> Map.put_new(:updated_at, now)
      end)

    returning = Keyword.get(opts, :returning, true)
    {count, records} = Repo.insert_all(schema, attrs_list, returning: returning)

    {:ok, %{count: count, records: records}}
  end

  defp execute_select(%__MODULE__{schema: schema} = crud) do
    query = build_query(schema, crud)
    {:ok, Repo.all(query)}
  end

  defp execute_select_one(%__MODULE__{schema: schema} = crud) do
    query = build_query(schema, crud)
    {:ok, Repo.one(query)}
  end

  defp execute_update(%__MODULE__{attrs: {struct, attrs}}) when is_struct(struct) do
    changeset = Ecto.Changeset.cast(struct, attrs, Map.keys(attrs))
    Repo.update(changeset)
  end

  defp execute_update(%__MODULE__{schema: schema} = crud) do
    # First, fetch the record
    with {:ok, record} <- execute_select_one(%{crud | operation: :select_one}) do
      if record do
        changeset = Ecto.Changeset.cast(record, crud.attrs, Map.keys(crud.attrs))
        Repo.update(changeset)
      else
        {:error, :not_found}
      end
    end
  end

  defp execute_update_all(%__MODULE__{schema: schema, attrs: attrs} = crud) do
    query = build_query(schema, crud)

    # Convert attrs to keyword list for Ecto.Query.update
    updates = Enum.map(attrs, fn {k, v} -> {k, v} end)

    query = from(q in query, update: [set: ^updates])

    case Repo.update_all(query, []) do
      {count, _} -> {:ok, %{count: count}}
      error -> {:error, error}
    end
  end

  defp execute_delete_all(%__MODULE__{schema: schema} = crud) do
    query = build_query(schema, crud)

    case Repo.delete_all(query) do
      {count, _} -> {:ok, %{count: count}}
      error -> {:error, error}
    end
  end

  defp execute_count(%__MODULE__{schema: schema} = crud) do
    query = build_query(schema, crud)
    count = Repo.aggregate(query, :count)
    {:ok, count}
  end

  defp execute_exists(%__MODULE__{schema: schema} = crud) do
    query = build_query(schema, crud)
    exists = Repo.exists?(query)
    {:ok, exists}
  end

  defp build_query(schema, crud) do
    query = from(q in schema)

    # Apply scope
    query =
      if crud.scope && !Scope.empty?(crud.scope) do
        {sql, bindings} = Scope.to_sql(crud.scope)
        from(q in query, where: fragment(^sql, ^bindings))
      else
        query
      end

    # Apply limit
    query =
      if crud.limit_value do
        from(q in query, limit: ^crud.limit_value)
      else
        query
      end

    # Apply offset
    query =
      if crud.offset_value do
        from(q in query, offset: ^crud.offset_value)
      else
        query
      end

    # Apply order_by
    query =
      if crud.order_by_value do
        from(q in query, order_by: ^crud.order_by_value)
      else
        query
      end

    # Apply preload
    query =
      if crud.preload_value do
        from(q in query, preload: ^crud.preload_value)
      else
        query
      end

    query
  end
end
