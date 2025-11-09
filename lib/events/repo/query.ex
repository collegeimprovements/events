defmodule Events.Repo.Query do
  @moduledoc """
  Composable query builder with smart filter syntax.

  ## Features

  - Builder pattern that composes with both keyword and pipe syntax
  - Smart filter syntax: `{field, operation, value, options}`
  - Support for joins with filters on joined tables
  - Soft delete by default
  - Returns Ecto.Query - use with `Repo.all`, `Repo.one`, or `to_sql()`
  - Accept filters as a list for easy composition

  ## Basic Usage

      # Pipe syntax
      Query.new(Product)
      |> Query.where(status: "active")
      |> Query.where({:price, :gt, 100})
      |> Query.limit(10)
      |> Repo.all()

      # Keyword syntax
      Query.new(Product, [
        where: [status: "active"],
        where: {:price, :gt, 100},
        limit: 10
      ])
      |> Repo.all()

      # List of filters
      filters = [
        [status: "active"],
        {:price, :gt, 100},
        {:name, :ilike, "%widget%"}
      ]
      Query.new(Product, where: filters) |> Repo.all()

      # Using filters: option
      Query.new(Product, filters: [
        status: "active",
        {:price, :gt, 100}
      ]) |> Repo.all()

      # Get SQL
      query = Query.new(Product)
        |> Query.where(status: "active")

      {sql, params} = Query.to_sql(query)

  ## Filter Syntax

      # Simple equality (inferred)
      Query.where(query, status: "active")
      Query.where(query, price: 100)

      # With operator
      Query.where(query, {:price, :gt, 100})
      Query.where(query, {:price, :between, 10, 100})

      # List means :in
      Query.where(query, status: ["active", "pending"])
      Query.where(query, {:id, :in, [id1, id2, id3]})

      # With options
      Query.where(query, {:name, :ilike, "%widget%", case_sensitive: false})
      Query.where(query, {:email, :eq, nil, include_nil: true})

  ## Joins

      Query.new(Product)
      |> Query.join(:category)
      |> Query.where({:category, :name, "Electronics"})
      |> Repo.all()

  ## Operations

  Supported operations:
  - `:eq`, `:neq` - Equality
  - `:gt`, `:gte`, `:lt`, `:lte` - Comparisons
  - `:in`, `:not_in` - List membership
  - `:like`, `:ilike`, `:not_like`, `:not_ilike` - Pattern matching
  - `:is_nil`, `:not_nil` - NULL checks
  - `:between` - Range (takes two values)
  - `:contains`, `:contained_by` - Array operations
  - `:jsonb_contains`, `:jsonb_has_key` - JSONB operations

  ## Options

  - `:case_sensitive` - For string comparisons (default: true)
  - `:include_nil` - Include NULL values (default: false)
  - `:type` - Cast value to type (:integer, :string, :float, etc)
  """

  import Ecto.Query
  alias Events.Repo

  @type t :: %__MODULE__{
          schema: module(),
          query: Ecto.Query.t(),
          joins: %{atom() => atom()},
          include_deleted: boolean()
        }

  defstruct [
    :schema,
    :query,
    joins: %{},
    include_deleted: false
  ]

  ## Builder Functions

  @doc """
  Creates a new query builder.

  ## Examples

      Query.new(Product)

      # Keyword syntax
      Query.new(Product, [
        where: [status: "active"],
        limit: 10
      ])

      # With list of filters
      Query.new(Product, [
        where: [
          [status: "active"],
          {:price, :gt, 100},
          {:name, :ilike, "%widget%"}
        ]
      ])

      # Using filters: option
      Query.new(Product, filters: [
        status: "active",
        {:price, :gt, 100}
      ])
  """
  @spec new(module(), keyword()) :: t()
  def new(schema, opts \\ []) do
    query = from(s in schema)

    # Apply soft delete filter by default
    query =
      if Keyword.get(opts, :include_deleted, false) do
        query
      else
        from(s in query, where: is_nil(s.deleted_at))
      end

    builder = %__MODULE__{
      schema: schema,
      query: query,
      include_deleted: Keyword.get(opts, :include_deleted, false)
    }

    # Apply keyword options
    apply_opts(builder, opts)
  end

  @doc """
  Adds WHERE conditions.

  ## Examples

      # Simple equality
      Query.where(query, status: "active")
      Query.where(query, [status: "active", type: "widget"])

      # With operators
      Query.where(query, {:price, :gt, 100})
      Query.where(query, {:price, :between, 10, 100})

      # List = IN
      Query.where(query, status: ["active", "pending"])

      # On joined table
      Query.where(query, {:category, :name, "Electronics"})

      # With options
      Query.where(query, {:name, :ilike, "%widget%", case_sensitive: false})
  """
  @spec where(t(), keyword() | tuple()) :: t()
  def where(%__MODULE__{} = builder, conditions) when is_list(conditions) do
    Enum.reduce(conditions, builder, fn condition, acc ->
      where(acc, condition)
    end)
  end

  def where(%__MODULE__{} = builder, {field, value}) when is_atom(field) do
    # Simple field: value - infer operation
    where(builder, {field, infer_operation(value), value})
  end

  def where(%__MODULE__{} = builder, {field, op, value}) when is_atom(field) and is_atom(op) do
    # Field on main table
    where(builder, {nil, field, op, value, []})
  end

  def where(%__MODULE__{} = builder, {field, op, value, opts})
      when is_atom(field) and is_atom(op) and is_list(opts) do
    # Field on main table with options
    where(builder, {nil, field, op, value, opts})
  end

  def where(%__MODULE__{} = builder, {join_name, field, value})
      when is_atom(join_name) and is_atom(field) do
    # Field on joined table - infer operation
    where(builder, {join_name, field, infer_operation(value), value, []})
  end

  def where(%__MODULE__{} = builder, {join_name, field, op, value})
      when is_atom(join_name) and is_atom(field) and is_atom(op) do
    # Field on joined table with operation
    where(builder, {join_name, field, op, value, []})
  end

  def where(%__MODULE__{} = builder, {join_name, field, op, value, opts})
      when is_atom(join_name) and is_atom(field) and is_atom(op) and is_list(opts) do
    # Full filter specification
    binding = get_binding(builder, join_name)
    query = apply_filter(builder.query, binding, field, op, value, opts)
    %{builder | query: query}
  end

  @doc """
  Joins an association.

  Automatically detects many-to-many through associations and creates bindings
  for both the intermediate join table and the final table.

  ## Examples

      # Direct association
      Query.join(query, :category)
      Query.join(query, :category, :left)

      # Many-to-many through (auto-detected)
      Query.join(query, :tags)  # Creates bindings for :product_tags AND :tags
      |> Query.where({:product_tags, :type, "featured"})  # Filter join table
      |> Query.where({:tags, :name, "red"})  # Filter final table
  """
  @spec join(t(), atom(), atom()) :: t()
  def join(%__MODULE__{} = builder, assoc_name, join_type \\ :inner) do
    # Check if this is a through association
    case get_association_type(builder.schema, assoc_name) do
      {:through, [intermediate_assoc, final_field]} ->
        join_through_auto(builder, intermediate_assoc, final_field, assoc_name, join_type)

      :direct ->
        join_direct(builder, assoc_name, join_type)
    end
  end

  @doc """
  Explicitly joins through an intermediate table with optional filtering.

  Use this when you want explicit control over the join path and filtering
  on the intermediate table.

  ## Examples

      # Join through product_tags to tags, filter on product_tags.type
      Query.join_through(query, :tags,
        through: :product_tags,
        where: {:type, "featured"}
      )
      |> Query.where({:tags, :name, "red"})

      # Multiple filters on join table
      Query.join_through(query, :tags,
        through: :product_tags,
        where: [
          {:type, "featured"},
          {:active, true}
        ]
      )
  """
  @spec join_through(t(), atom(), keyword()) :: t()
  def join_through(%__MODULE__{} = builder, final_assoc, opts) do
    through_assoc = Keyword.get(opts, :through)
    through_filters = Keyword.get(opts, :where)
    join_type = Keyword.get(opts, :type, :inner)

    unless through_assoc do
      raise ArgumentError, "join_through requires :through option"
    end

    # Get the final field name from the through association
    final_field = get_through_final_field(builder.schema, through_assoc, final_assoc)

    # Join the intermediate table
    builder = join_direct(builder, through_assoc, join_type)

    # Apply filters on intermediate table if provided
    builder =
      if through_filters do
        where(builder, normalize_through_filter(through_assoc, through_filters))
      else
        builder
      end

    # Join the final table from the intermediate binding
    query =
      case join_type do
        :inner ->
          from [{^through_assoc, t}] in builder.query,
            join: f in assoc(t, ^final_field),
            as: ^final_assoc

        :left ->
          from [{^through_assoc, t}] in builder.query,
            left_join: f in assoc(t, ^final_field),
            as: ^final_assoc

        :right ->
          from [{^through_assoc, t}] in builder.query,
            right_join: f in assoc(t, ^final_field),
            as: ^final_assoc
      end

    %{builder | query: query, joins: Map.put(builder.joins, final_assoc, final_assoc)}
  end

  @doc """
  Adds ORDER BY.

  ## Examples

      Query.order_by(query, desc: :inserted_at)
      Query.order_by(query, [asc: :name, desc: :price])
  """
  @spec order_by(t(), keyword()) :: t()
  def order_by(%__MODULE__{} = builder, ordering) when is_list(ordering) do
    query = from(s in builder.query, order_by: ^ordering)
    %{builder | query: query}
  end

  @doc """
  Adds LIMIT.

  ## Examples

      Query.limit(query, 10)
  """
  @spec limit(t(), pos_integer()) :: t()
  def limit(%__MODULE__{} = builder, value) when is_integer(value) and value > 0 do
    query = from(s in builder.query, limit: ^value)
    %{builder | query: query}
  end

  @doc """
  Adds OFFSET.

  ## Examples

      Query.offset(query, 20)
  """
  @spec offset(t(), non_neg_integer()) :: t()
  def offset(%__MODULE__{} = builder, value) when is_integer(value) and value >= 0 do
    query = from(s in builder.query, offset: ^value)
    %{builder | query: query}
  end

  @doc """
  Adds preloads.

  ## Examples

      Query.preload(query, [:category, :tags])
  """
  @spec preload(t(), list()) :: t()
  def preload(%__MODULE__{} = builder, assocs) when is_list(assocs) do
    query = from(s in builder.query, preload: ^assocs)
    %{builder | query: query}
  end

  @doc """
  Includes soft-deleted records.

  ## Examples

      Query.new(Product)
      |> Query.include_deleted()
      |> Repo.all()
  """
  @spec include_deleted(t()) :: t()
  def include_deleted(%__MODULE__{schema: schema} = builder) do
    # Remove the deleted_at filter
    query = from(s in schema)
    %{builder | query: query, include_deleted: true}
  end

  @doc """
  Returns the built Ecto.Query.

  Use this with Repo.all, Repo.one, etc.

  ## Examples

      query = Query.new(Product)
        |> Query.where(status: "active")
        |> Query.to_query()

      Repo.all(query)
  """
  @spec to_query(t()) :: Ecto.Query.t()
  def to_query(%__MODULE__{query: query}), do: query

  @doc """
  Converts the query to SQL.

  Returns `{sql, params}`.

  ## Examples

      {sql, params} = Query.new(Product)
        |> Query.where(status: "active")
        |> Query.to_sql()
  """
  @spec to_sql(t()) :: {String.t(), list()}
  def to_sql(%__MODULE__{query: query}) do
    Ecto.Adapters.SQL.to_sql(:all, Repo, query)
  end

  ## CRUD Operations

  @doc """
  Inserts a record.

  ## Examples

      {:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)
  """
  @spec insert(module(), map(), keyword()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
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
  Updates a record.

  ## Examples

      {:ok, product} = Query.update(product, %{price: 19.99}, updated_by: user_id)
  """
  @spec update(Ecto.Schema.t(), map(), keyword()) ::
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
  Updates all records matching the query.

  ## Examples

      {:ok, count} = Query.new(Product)
        |> Query.where(status: "draft")
        |> Query.update_all([set: [status: "published"]], updated_by: user_id)
  """
  @spec update_all(t(), keyword(), keyword()) :: {:ok, integer()}
  def update_all(%__MODULE__{query: query}, updates, opts \\ []) do
    updates =
      case Keyword.get(opts, :updated_by) do
        nil -> updates
        user_id -> Keyword.update(updates, :set, [], &(&1 ++ [updated_by_urm_id: user_id]))
      end

    {count, _} = Repo.update_all(query, updates)
    {:ok, count}
  end

  @doc """
  Soft deletes a record.

  ## Examples

      {:ok, product} = Query.delete(product, deleted_by: user_id)
      {:ok, product} = Query.delete(product, hard: true)  # permanent
  """
  @spec delete(Ecto.Schema.t(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(struct, opts \\ []) when is_struct(struct) do
    if Keyword.get(opts, :hard, false) do
      Repo.delete(struct)
    else
      now = DateTime.utc_now()
      deleted_by = Keyword.get(opts, :deleted_by)

      changes = %{deleted_at: now}
      changes = if deleted_by, do: Map.put(changes, :deleted_by_urm_id, deleted_by), else: changes

      struct
      |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
      |> Repo.update()
    end
  end

  @doc """
  Deletes all records matching the query.

  ## Examples

      {:ok, count} = Query.new(Product)
        |> Query.where(status: "draft")
        |> Query.delete_all(deleted_by: user_id)

      {:ok, count} = Query.new(Product)
        |> Query.where(status: "draft")
        |> Query.delete_all(hard: true)  # permanent
  """
  @spec delete_all(t(), keyword()) :: {:ok, integer()}
  def delete_all(%__MODULE__{query: query}, opts \\ []) do
    if Keyword.get(opts, :hard, false) do
      {count, _} = Repo.delete_all(query)
      {:ok, count}
    else
      now = DateTime.utc_now()
      deleted_by = Keyword.get(opts, :deleted_by)

      updates = [set: [deleted_at: now]]

      updates =
        if deleted_by do
          Keyword.update(updates, :set, [], &(&1 ++ [deleted_by_urm_id: deleted_by]))
        else
          updates
        end

      {count, _} = Repo.update_all(query, updates)
      {:ok, count}
    end
  end

  ## Private Helpers

  defp apply_opts(builder, opts) do
    Enum.reduce(opts, builder, fn
      {:where, conditions}, acc -> where(acc, conditions)
      {:filters, filter_list}, acc -> where(acc, filter_list)
      {:join, assoc}, acc -> join(acc, assoc)
      {:order_by, ordering}, acc -> order_by(acc, ordering)
      {:limit, value}, acc -> limit(acc, value)
      {:offset, value}, acc -> offset(acc, value)
      {:preload, assocs}, acc -> preload(acc, assocs)
      {:include_deleted, _}, acc -> acc  # Already handled in new/2
      _, acc -> acc
    end)
  end

  defp infer_operation(value) when is_list(value), do: :in
  defp infer_operation(_), do: :eq

  defp get_binding(_builder, nil), do: 0

  defp get_binding(builder, join_name) do
    if Map.has_key?(builder.joins, join_name) do
      join_name  # Return the atom name for use with as()
    else
      raise "Join :#{join_name} not found. Did you forget to call Query.join/2?"
    end
  end

  # Determine if an association is a through association
  defp get_association_type(schema, assoc_name) do
    case schema.__schema__(:association, assoc_name) do
      %{through: through_path} when is_list(through_path) and length(through_path) == 2 ->
        {:through, through_path}

      _ ->
        :direct
    end
  end

  # Join through association automatically (for has_many :through)
  defp join_through_auto(builder, intermediate_assoc, final_field, final_name, join_type) do
    # Join intermediate table first
    query =
      case join_type do
        :inner ->
          from(s in builder.query, join: i in assoc(s, ^intermediate_assoc), as: ^intermediate_assoc)

        :left ->
          from(s in builder.query,
            left_join: i in assoc(s, ^intermediate_assoc),
            as: ^intermediate_assoc
          )

        :right ->
          from(s in builder.query,
            right_join: i in assoc(s, ^intermediate_assoc),
            as: ^intermediate_assoc
          )
      end

    # Join final table from intermediate
    query =
      case join_type do
        :inner ->
          from [{^intermediate_assoc, i}] in query,
            join: f in assoc(i, ^final_field),
            as: ^final_name

        :left ->
          from [{^intermediate_assoc, i}] in query,
            left_join: f in assoc(i, ^final_field),
            as: ^final_name

        :right ->
          from [{^intermediate_assoc, i}] in query,
            right_join: f in assoc(i, ^final_field),
            as: ^final_name
      end

    # Store both bindings
    joins =
      builder.joins
      |> Map.put(intermediate_assoc, intermediate_assoc)
      |> Map.put(final_name, final_name)

    %{builder | query: query, joins: joins}
  end

  # Direct join (non-through association)
  defp join_direct(builder, assoc_name, join_type) do
    query =
      case join_type do
        :inner ->
          from(s in builder.query, join: a in assoc(s, ^assoc_name), as: ^assoc_name)

        :left ->
          from(s in builder.query, left_join: a in assoc(s, ^assoc_name), as: ^assoc_name)

        :right ->
          from(s in builder.query, right_join: a in assoc(s, ^assoc_name), as: ^assoc_name)
      end

    %{builder | query: query, joins: Map.put(builder.joins, assoc_name, assoc_name)}
  end

  # Get the final field name from through association
  defp get_through_final_field(schema, through_assoc, _final_assoc) do
    # Get the through schema
    case schema.__schema__(:association, through_assoc) do
      %{related: through_schema} ->
        # Look for associations in the through schema that match
        # For ProductTag, this would find :tag association
        through_schema.__schema__(:associations)
        |> Enum.find(fn assoc_name ->
          case through_schema.__schema__(:association, assoc_name) do
            %{owner: ^through_schema, related: _} -> true
            _ -> false
          end
        end)
        |> case do
          nil ->
            raise ArgumentError,
                  "Could not find final association in #{inspect(through_schema)}"

          field ->
            field
        end

      _ ->
        raise ArgumentError, "#{inspect(through_assoc)} is not a valid association"
    end
  end

  # Normalize through filter to include the join table name
  defp normalize_through_filter(through_assoc, filter) when is_tuple(filter) do
    case filter do
      {field, value} when is_atom(field) ->
        {through_assoc, field, value}

      {field, op, value} when is_atom(field) and is_atom(op) ->
        {through_assoc, field, op, value}

      {field, op, value, opts} when is_atom(field) and is_atom(op) and is_list(opts) ->
        {through_assoc, field, op, value, opts}
    end
  end

  defp normalize_through_filter(through_assoc, filters) when is_list(filters) do
    Enum.map(filters, &normalize_through_filter(through_assoc, &1))
  end

  defp apply_filter(query, binding, field, op, value, opts) do
    case op do
      :eq -> apply_eq(query, binding, field, value, opts)
      :neq -> apply_neq(query, binding, field, value, opts)
      :gt -> apply_comparison(query, binding, field, :>, value)
      :gte -> apply_comparison(query, binding, field, :>=, value)
      :lt -> apply_comparison(query, binding, field, :<, value)
      :lte -> apply_comparison(query, binding, field, :<=, value)
      :in -> apply_in(query, binding, field, value)
      :not_in -> apply_not_in(query, binding, field, value)
      :like -> apply_like(query, binding, field, value, opts)
      :ilike -> apply_ilike(query, binding, field, value, opts)
      :not_like -> apply_not_like(query, binding, field, value, opts)
      :not_ilike -> apply_not_ilike(query, binding, field, value, opts)
      :is_nil -> apply_is_nil(query, binding, field)
      :not_nil -> apply_not_nil(query, binding, field)
      :between -> apply_between(query, binding, field, value)
      :contains -> apply_contains(query, binding, field, value)
      :contained_by -> apply_contained_by(query, binding, field, value)
      :jsonb_contains -> apply_jsonb_contains(query, binding, field, value)
      :jsonb_has_key -> apply_jsonb_has_key(query, binding, field, value)
      _ -> raise "Unknown operation: #{op}"
    end
  end

  defp apply_eq(query, 0, field, value, opts) do
    include_nil = Keyword.get(opts, :include_nil, false)

    if include_nil do
      from(q in query, where: field(q, ^field) == ^value or is_nil(field(q, ^field)))
    else
      from(q in query, where: field(q, ^field) == ^value)
    end
  end

  defp apply_eq(query, binding, field, value, opts) do
    include_nil = Keyword.get(opts, :include_nil, false)

    if include_nil do
      from(q in query,
        where: field(as(^binding), ^field) == ^value or is_nil(field(as(^binding), ^field))
      )
    else
      from(q in query, where: field(as(^binding), ^field) == ^value)
    end
  end

  defp apply_neq(query, 0, field, value, _opts) do
    from(q in query, where: field(q, ^field) != ^value)
  end

  defp apply_neq(query, binding, field, value, _opts) do
    from(q in query, where: field(as(^binding), ^field) != ^value)
  end

  defp apply_comparison(query, 0, field, op, value) do
    from(q in query, where: field(q, ^field) |> fragment("? #{op} ?", ^value))
  end

  defp apply_comparison(query, binding, field, op, value) do
    from(q in query, where: field(as(^binding), ^field) |> fragment("? #{op} ?", ^value))
  end

  defp apply_in(query, 0, field, values) when is_list(values) do
    from(q in query, where: field(q, ^field) in ^values)
  end

  defp apply_in(query, binding, field, values) when is_list(values) do
    from(q in query, where: field(as(^binding), ^field) in ^values)
  end

  defp apply_not_in(query, 0, field, values) when is_list(values) do
    from(q in query, where: field(q, ^field) not in ^values)
  end

  defp apply_not_in(query, binding, field, values) when is_list(values) do
    from(q in query, where: field(as(^binding), ^field) not in ^values)
  end

  defp apply_like(query, 0, field, pattern, _opts) do
    from(q in query, where: like(field(q, ^field), ^pattern))
  end

  defp apply_like(query, binding, field, pattern, _opts) do
    from(q in query, where: like(field(as(^binding), ^field), ^pattern))
  end

  defp apply_ilike(query, 0, field, pattern, _opts) do
    from(q in query, where: ilike(field(q, ^field), ^pattern))
  end

  defp apply_ilike(query, binding, field, pattern, _opts) do
    from(q in query, where: ilike(field(as(^binding), ^field), ^pattern))
  end

  defp apply_not_like(query, 0, field, pattern, _opts) do
    from(q in query, where: not like(field(q, ^field), ^pattern))
  end

  defp apply_not_like(query, binding, field, pattern, _opts) do
    from(q in query, where: not like(field(as(^binding), ^field), ^pattern))
  end

  defp apply_not_ilike(query, 0, field, pattern, _opts) do
    from(q in query, where: not ilike(field(q, ^field), ^pattern))
  end

  defp apply_not_ilike(query, binding, field, pattern, _opts) do
    from(q in query, where: not ilike(field(as(^binding), ^field), ^pattern))
  end

  defp apply_is_nil(query, 0, field) do
    from(q in query, where: is_nil(field(q, ^field)))
  end

  defp apply_is_nil(query, binding, field) do
    from(q in query, where: is_nil(field(as(^binding), ^field)))
  end

  defp apply_not_nil(query, 0, field) do
    from(q in query, where: not is_nil(field(q, ^field)))
  end

  defp apply_not_nil(query, binding, field) do
    from(q in query, where: not is_nil(field(as(^binding), ^field)))
  end

  defp apply_between(query, 0, field, {min, max}) do
    from(q in query, where: field(q, ^field) >= ^min and field(q, ^field) <= ^max)
  end

  defp apply_between(query, binding, field, {min, max}) do
    from(q in query,
      where: field(as(^binding), ^field) >= ^min and field(as(^binding), ^field) <= ^max
    )
  end

  defp apply_contains(query, 0, field, value) do
    from(q in query, where: fragment("? @> ?", field(q, ^field), ^value))
  end

  defp apply_contains(query, binding, field, value) do
    from(q in query, where: fragment("? @> ?", field(as(^binding), ^field), ^value))
  end

  defp apply_contained_by(query, 0, field, value) do
    from(q in query, where: fragment("? <@ ?", field(q, ^field), ^value))
  end

  defp apply_contained_by(query, binding, field, value) do
    from(q in query, where: fragment("? <@ ?", field(as(^binding), ^field), ^value))
  end

  defp apply_jsonb_contains(query, 0, field, value) do
    from(q in query, where: fragment("? @> ?::jsonb", field(q, ^field), ^value))
  end

  defp apply_jsonb_contains(query, binding, field, value) do
    from(q in query, where: fragment("? @> ?::jsonb", field(as(^binding), ^field), ^value))
  end

  defp apply_jsonb_has_key(query, 0, field, key) do
    from(q in query, where: fragment("? ? ?", field(q, ^field), "?", ^key))
  end

  defp apply_jsonb_has_key(query, binding, field, key) do
    from(q in query, where: fragment("? ? ?", field(as(^binding), ^field), "?", ^key))
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

# Implement Ecto.Queryable protocol so Query works with Repo.all, Repo.one, etc
defimpl Ecto.Queryable, for: Events.Repo.Query do
  def to_query(%Events.Repo.Query{query: query}), do: query
end
