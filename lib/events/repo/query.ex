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

      # Keyword syntax with all options
      Query.new(Product, [
        where: [status: "active"],
        where: {:price, :gt, 100},
        select: [:id, :name, :price],
        order_by: [desc: :inserted_at],
        limit: 10
      ])
      |> Repo.all()

      # Using filters: option
      Query.new(Product, [
        filters: [status: "active", {:price, :gt, 100}],
        preload: [:category, :tags],
        order_by: [desc: :price],
        limit: 20
      ]) |> Repo.all()

      # With window functions
      Query.new(Product, [
        select: %{
          id: :id,
          name: :name,
          rank: {:window, :rank, [partition_by: :category_id, order_by: [desc: :price]]}
        }
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

  - `:case_sensitive` - For string comparisons (default: false - case insensitive)
  - `:trim` - Trim string values before comparison (default: true)
  - `:include_nil` - Include NULL values (default: false)
  - `:type` - Cast value to type (:integer, :string, :float, etc)
  - `:data_type` - Specify data type for special handling (:date, :datetime, :time)
  - `:value_fn` - Function to transform the value before filtering (1-arity function)

  ## Default Behavior

  By default, all string filters are:
  - **Trimmed** - Leading/trailing whitespace is removed (`:trim` defaults to `true`)
  - **Case insensitive** - Comparisons ignore case (`:case_sensitive` defaults to `false`)

  This means these are equivalent:

      Query.where(query, name: "widget")
      Query.where(query, name: "Widget")
      Query.where(query, name: " WIDGET ")

  To disable these defaults:

      Query.where(query, {:name, :eq, "Widget", trim: false, case_sensitive: true})

  ## Value Transformation

  The `:value_fn` option accepts a 1-arity function for custom transformations
  (applied after trimming):

      # Custom normalization
      Query.where(query, {:sku, :eq, "abc-123", value_fn: &String.upcase/1})

      # Transform multiple values in :in operation
      Query.where(query, {:tags, :in, ["tag1", "tag2"], value_fn: &String.upcase/1})

      # Apply to both values in :between
      Query.where(query, {:price, :between, {10.5, 99.9}, value_fn: &Float.round(&1, 2)})

  ## Date/Time Comparisons

  The `:data_type` option handles date, datetime, and time comparisons properly by
  casting both the field and value to the appropriate PostgreSQL type. It also
  automatically parses date strings in various formats.

      # Compare only date parts (ignores time) - using Date struct
      Query.where(query, {:created_at, :eq, ~D[2024-01-15], data_type: :date})

      # Using string dates - automatically parsed to Date
      Query.where(query, {:created_at, :eq, "2024-01-15", data_type: :date})      # yyyy-mm-dd
      Query.where(query, {:created_at, :eq, "2024/01/15", data_type: :date})      # yyyy/mm/dd
      Query.where(query, {:created_at, :eq, "01-15-2024", data_type: :date})      # mm-dd-yyyy
      Query.where(query, {:created_at, :eq, "01/15/2024", data_type: :date})      # mm/dd/yyyy

      # Date range comparison with string dates
      Query.where(query, {:created_at, :between, {"2024-01-01", "2024-12-31"}, data_type: :date})

      # Greater than comparison on dates
      Query.where(query, {:expires_at, :gt, "06/01/2024", data_type: :date})

      # Datetime comparison (with timezone handling)
      Query.where(query, {:updated_at, :gte, ~U[2024-01-01 00:00:00Z], data_type: :datetime})

      # Time-only comparison
      Query.where(query, {:start_time, :lt, ~T[18:00:00], data_type: :time})

  Supported date formats:
  - `yyyy-mm-dd` (ISO format with dash)
  - `yyyy/mm/dd` (ISO format with slash)
  - `mm-dd-yyyy` (US format with dash)
  - `mm/dd/yyyy` (US format with slash)
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

      # Using filters: option (supports all filter syntax)
      Query.new(Product, filters: [
        status: "active",
        {:price, :gt, 100}
      ])

      # Filters with options
      Query.new(Product, filters: [
        {:name, :ilike, "%widget%", case_sensitive: false},
        {:email, :eq, nil, include_nil: true},
        {:price, :between, {10, 100}}
      ])

      # Filters with value transformation
      Query.new(Product, filters: [
        {:name, :eq, " Widget ", value_fn: &String.trim/1},
        {:email, :eq, "USER@EXAMPLE.COM", value_fn: &String.downcase/1},
        {:status, :in, [" active ", " pending "], value_fn: &String.trim/1}
      ])

      # Filters on join tables (requires join first)
      Query.new(Product, [
        join: :category,
        filters: [
          status: "active",
          {:category, :name, "Electronics"},
          {:category, :active, true}
        ]
      ])

      # Complex filters with joins and options
      Query.new(Product, [
        join: :category,
        join: :tags,
        filters: [
          status: "active",
          {:price, :gte, 100},
          {:category, :name, :in, ["Electronics", "Gadgets"]},
          {:tags, :name, :ilike, "%featured%", case_sensitive: false}
        ],
        order_by: [desc: :price],
        limit: 20
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

      # Explicit through with options
      Query.join(query, :tags, through: :product_tags)
      Query.join(query, :tags, through: :product_tags, where: {:type, "featured"})
      Query.join(query, :tags, type: :left, through: :product_tags)
  """
  @spec join(t(), atom(), atom() | keyword()) :: t()
  def join(%__MODULE__{} = builder, assoc_name, join_type_or_opts \\ :inner)

  # When opts is a keyword list with :through option
  def join(%__MODULE__{} = builder, assoc_name, opts) when is_list(opts) do
    if Keyword.has_key?(opts, :through) do
      # Explicit through join with options
      through_assoc = Keyword.get(opts, :through)
      through_filters = Keyword.get(opts, :where)
      join_type = Keyword.get(opts, :type, :inner)

      # Get the final field name from the through association
      final_field = get_through_final_field(builder.schema, through_assoc, assoc_name)

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
              as: ^assoc_name

          :left ->
            from [{^through_assoc, t}] in builder.query,
              left_join: f in assoc(t, ^final_field),
              as: ^assoc_name

          :right ->
            from [{^through_assoc, t}] in builder.query,
              right_join: f in assoc(t, ^final_field),
              as: ^assoc_name
        end

      %{builder | query: query, joins: Map.put(builder.joins, assoc_name, assoc_name)}
    else
      # Keyword list but no :through, might have other options
      join_type = Keyword.get(opts, :type, :inner)
      join(builder, assoc_name, join_type)
    end
  end

  # When join_type is an atom
  def join(%__MODULE__{} = builder, assoc_name, join_type) when is_atom(join_type) do
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
  Adds DISTINCT clause.

  ## Examples

      # Distinct on all fields
      Query.distinct(query, true)

      # Distinct on specific fields
      Query.distinct(query, [:category_id, :status])

      # Distinct on expression
      Query.distinct(query, [desc: :inserted_at])
  """
  @spec distinct(t(), boolean() | list()) :: t()
  def distinct(%__MODULE__{} = builder, true) do
    query = from(s in builder.query, distinct: true)
    %{builder | query: query}
  end

  def distinct(%__MODULE__{} = builder, fields) when is_list(fields) do
    query = from(s in builder.query, distinct: ^fields)
    %{builder | query: query}
  end

  @doc """
  Adds GROUP BY clause.

  ## Examples

      Query.group_by(query, :category_id)
      Query.group_by(query, [:category_id, :status])
  """
  @spec group_by(t(), atom() | list()) :: t()
  def group_by(%__MODULE__{} = builder, field) when is_atom(field) do
    query = from(s in builder.query, group_by: field(s, ^field))
    %{builder | query: query}
  end

  def group_by(%__MODULE__{} = builder, fields) when is_list(fields) do
    query = from(s in builder.query, group_by: ^fields)
    %{builder | query: query}
  end

  @doc """
  Adds HAVING clause for filtering grouped results.

  ## Examples

      Query.group_by(query, :category_id)
      |> Query.having([count: {:gt, 5}])

      Query.group_by(query, :category_id)
      |> Query.having("count(*) > ?", [5])
  """
  @spec having(t(), keyword() | String.t(), list()) :: t()
  def having(%__MODULE__{} = builder, conditions, bindings \\ [])

  def having(%__MODULE__{} = builder, sql, bindings) when is_binary(sql) and is_list(bindings) do
    query = from(s in builder.query, having: fragment(^sql, ^bindings))
    %{builder | query: query}
  end

  def having(%__MODULE__{} = builder, conditions, _) when is_list(conditions) do
    # Simple keyword-based having
    query =
      Enum.reduce(conditions, builder.query, fn {aggregate, {op, value}}, q ->
        case aggregate do
          :count ->
            case op do
              :gt -> from(s in q, having: fragment("count(*) > ?", ^value))
              :gte -> from(s in q, having: fragment("count(*) >= ?", ^value))
              :lt -> from(s in q, having: fragment("count(*) < ?", ^value))
              :lte -> from(s in q, having: fragment("count(*) <= ?", ^value))
              :eq -> from(s in q, having: fragment("count(*) = ?", ^value))
            end

          _ ->
            q
        end
      end)

    %{builder | query: query}
  end

  @doc """
  Defines a named window for use with window functions.

  Windows define partitioning and ordering for window functions like
  ROW_NUMBER(), RANK(), DENSE_RANK(), LEAD(), LAG(), etc.

  ## Examples

      # Define a window partitioned by category_id
      Query.window(query, :w, partition_by: :category_id, order_by: [desc: :price])

      # Multiple windows
      Query.new(Product)
      |> Query.window(:price_rank, partition_by: :category_id, order_by: [desc: :price])
      |> Query.window(:date_rank, partition_by: :category_id, order_by: [desc: :inserted_at])

      # Window with just ordering
      Query.window(query, :w, order_by: [desc: :price])

      # Window with just partitioning
      Query.window(query, :w, partition_by: [:category_id, :status])
  """
  @spec window(t(), atom(), keyword()) :: t()
  def window(%__MODULE__{} = builder, name, opts) when is_atom(name) and is_list(opts) do
    window_spec = build_window_spec(opts)
    query = from(s in builder.query, windows: [{^name, ^window_spec}])
    %{builder | query: query}
  end

  @doc """
  Adds a SELECT clause with support for window functions.

  ## Examples

      # Select specific fields
      Query.select(query, [:id, :name, :price])

      # Select with map (useful for custom field names)
      Query.select(query, %{product_id: :id, product_name: :name})

      # Use window functions with named window
      Query.new(Product)
      |> Query.window(:w, partition_by: :category_id, order_by: [desc: :price])
      |> Query.select(%{
        id: :id,
        name: :name,
        row_number: {:window, :row_number, :w},
        rank: {:window, :rank, :w}
      })

      # Use window functions with inline definition
      Query.select(query, %{
        id: :id,
        row_number: {:window, :row_number, [partition_by: :category_id, order_by: [desc: :price]]}
      })

      # Window functions: :row_number, :rank, :dense_rank
      # With field: :lead, :lag, :first_value, :last_value
      Query.select(query, %{
        id: :id,
        next_price: {:window, {:lead, :price}, :w}
      })

      # Aggregates as window functions
      Query.select(query, %{
        id: :id,
        running_total: {:window, {:sum, :amount}, :w}
      })
  """
  @spec select(t(), list() | map()) :: t()
  def select(%__MODULE__{} = builder, fields) when is_list(fields) do
    # Simple field list
    query = from(s in builder.query, select: map(s, ^fields))
    %{builder | query: query}
  end

  def select(%__MODULE__{} = builder, field_map) when is_map(field_map) do
    # Map with potentially window functions
    # Build select using SQL fragments for window functions
    query = build_select_query(builder.query, field_map)
    %{builder | query: query}
  end

  @doc """
  Creates a query from a subquery (for use in FROM clause).

  ## Examples

      # Build subquery
      active_products = Query.new(Product)
        |> Query.where(status: "active")
        |> Query.select([:id, :name, :category_id])

      # Use as FROM clause
      Query.from_subquery(active_products, :products)
      |> Query.where({:products, :name, :ilike, "%widget%"})
      |> Repo.all()

      # With alias
      Query.from_subquery(active_products, :p)
      |> Query.join(:category, on: {:p, :category_id, :eq, {:category, :id}})
  """
  @spec from_subquery(t(), atom()) :: t()
  def from_subquery(%__MODULE__{query: subquery, schema: schema}, alias_name) when is_atom(alias_name) do
    # Create a new query from the subquery
    query = from(s in subquery(subquery), as: ^alias_name)

    %__MODULE__{
      schema: schema,
      query: query,
      joins: %{alias_name => alias_name},
      include_deleted: false
    }
  end

  @doc """
  Adds a WHERE condition using a subquery.

  ## Examples

      # WHERE id IN (subquery)
      subquery = Query.new(Product)
        |> Query.where(status: "active")
        |> Query.select([:id])

      Query.new(Order)
      |> Query.where_in_subquery(:product_id, subquery)
      |> Repo.all()

      # WHERE id NOT IN (subquery)
      Query.new(Order)
      |> Query.where_not_in_subquery(:product_id, subquery)

      # WHERE EXISTS (subquery)
      subquery = Query.new(OrderItem)
        |> Query.where({:order_id, :eq, {:parent, :id}})

      Query.new(Order)
      |> Query.where_exists(subquery)
  """
  @spec where_in_subquery(t(), atom(), t()) :: t()
  def where_in_subquery(%__MODULE__{} = builder, field, %__MODULE__{query: subquery})
      when is_atom(field) do
    query = from(s in builder.query, where: field(s, ^field) in subquery(^subquery))
    %{builder | query: query}
  end

  @spec where_not_in_subquery(t(), atom(), t()) :: t()
  def where_not_in_subquery(%__MODULE__{} = builder, field, %__MODULE__{query: subquery})
      when is_atom(field) do
    query = from(s in builder.query, where: field(s, ^field) not in subquery(^subquery))
    %{builder | query: query}
  end

  @spec where_exists(t(), t()) :: t()
  def where_exists(%__MODULE__{} = builder, %__MODULE__{query: subquery}) do
    query = from(s in builder.query, where: exists(^subquery))
    %{builder | query: query}
  end

  @spec where_not_exists(t(), t()) :: t()
  def where_not_exists(%__MODULE__{} = builder, %__MODULE__{query: subquery}) do
    query = from(s in builder.query, where: not exists(^subquery))
    %{builder | query: query}
  end

  @doc """
  Adds a scalar subquery to the SELECT clause.

  ## Examples

      # Add count from related table
      product_count_subquery = Query.new(Product)
        |> Query.where(dynamic([p, parent: c], p.category_id == c.id))
        |> Query.select(fragment("count(*)"))

      Query.new(Category)
      |> Query.select([:id, :name])
      |> Query.select_subquery(:product_count, product_count_subquery)
      |> Repo.all()

      # Multiple scalar subqueries
      Query.new(Category)
      |> Query.select_subquery(:active_products, active_count_query)
      |> Query.select_subquery(:inactive_products, inactive_count_query)
  """
  @spec select_subquery(t(), atom(), t() | Ecto.Query.t()) :: t()
  def select_subquery(%__MODULE__{} = builder, field_name, %__MODULE__{query: subquery})
      when is_atom(field_name) do
    # Add scalar subquery to select
    query = from(s in builder.query, select_merge: %{^field_name => subquery(^subquery)})
    %{builder | query: query}
  end

  def select_subquery(%__MODULE__{} = builder, field_name, subquery)
      when is_atom(field_name) do
    # Support raw Ecto.Query
    query = from(s in builder.query, select_merge: %{^field_name => subquery(^subquery)})
    %{builder | query: query}
  end

  @doc """
  Adds preloads with optional conditional filtering.

  ## Examples

      # Basic preload
      Query.preload(query, [:category, :tags])

      # Conditional preload with filters
      Query.preload(query, [
        :category,
        tags: [where: [active: true]]
      ])

      # Multiple conditions on preload
      Query.preload(query, [
        tags: [where: [active: true], order_by: [asc: :name], limit: 5]
      ])

      # Nested preloads with conditions
      Query.preload(query, [
        category: [where: [active: true]],
        tags: [
          where: [active: true],
          preload: [:translations]
        ]
      ])

      # Mix basic and conditional
      Query.preload(query, [
        :user,
        comments: [where: [approved: true], order_by: [desc: :inserted_at]]
      ])

      # With Ecto.Query
      Query.preload(query, [
        tags: from(t in Tag, where: t.active == true, order_by: t.name)
      ])
  """
  @spec preload(t(), list() | keyword()) :: t()
  def preload(%__MODULE__{} = builder, assocs) when is_list(assocs) do
    processed_assocs = process_preloads(assocs)
    query = from(s in builder.query, preload: ^processed_assocs)
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

  @doc """
  Returns a human-readable inspection of the query for debugging.

  ## Examples

      Query.new(Product)
      |> Query.where(status: "active")
      |> Query.join(:tags, through: :product_tags, where: {:type, "featured"})
      |> Query.inspect()
      # => Returns formatted string representation
  """
  @spec inspect(t()) :: String.t()
  def inspect(%__MODULE__{} = builder) do
    Kernel.inspect(builder.query, pretty: true, limit: :infinity, printable_limit: :infinity)
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

  # Build window specification from options
  defp build_window_spec(opts) do
    partition_by = Keyword.get(opts, :partition_by)
    order_by = Keyword.get(opts, :order_by)

    spec = []

    spec =
      if partition_by do
        partition_fields = if is_list(partition_by), do: partition_by, else: [partition_by]
        [{:partition_by, partition_fields} | spec]
      else
        spec
      end

    spec =
      if order_by do
        [{:order_by, order_by} | spec]
      else
        spec
      end

    spec
  end

  # Build select query with window functions
  defp build_select_query(query, field_map) do
    # Build the select map with proper expressions
    select_fields = build_select_map_expr(field_map)

    from s in query,
      select: ^select_fields
  end

  # Build select map expression
  defp build_select_map_expr(field_map) do
    Enum.reduce(field_map, %{}, fn
      {key, {:window, func, window_or_opts}}, acc ->
        Map.put(acc, key, build_window_dynamic(func, window_or_opts))

      {key, field}, acc when is_atom(field) ->
        Map.put(acc, key, dynamic([s], field(s, ^field)))
    end)
  end

  # Build window function as dynamic expression
  defp build_window_dynamic(func, window_name) when is_atom(window_name) do
    # Using named window - the window must be defined separately
    func_sql = build_window_func_sql(func)
    # For named windows, we reference them by name
    # This needs the window to be already defined in the query
    dynamic([], fragment("#{func_sql} OVER ?", ^window_name))
  end

  defp build_window_dynamic(func, opts) when is_list(opts) do
    # Inline window definition - build full SQL
    func_sql = build_window_func_sql(func)
    window_sql = build_window_clause_sql(opts)
    full_sql = "#{func_sql} OVER (#{window_sql})"
    dynamic([], fragment(^full_sql))
  end

  # Build window function SQL
  defp build_window_func_sql(:row_number), do: "ROW_NUMBER()"
  defp build_window_func_sql(:rank), do: "RANK()"
  defp build_window_func_sql(:dense_rank), do: "DENSE_RANK()"
  defp build_window_func_sql({:lead, field}), do: "LEAD(#{field})"
  defp build_window_func_sql({:lag, field}), do: "LAG(#{field})"
  defp build_window_func_sql({:first_value, field}), do: "FIRST_VALUE(#{field})"
  defp build_window_func_sql({:last_value, field}), do: "LAST_VALUE(#{field})"
  defp build_window_func_sql({:sum, field}), do: "SUM(#{field})"
  defp build_window_func_sql({:avg, field}), do: "AVG(#{field})"
  defp build_window_func_sql({:count, field}), do: "COUNT(#{field})"
  defp build_window_func_sql({:min, field}), do: "MIN(#{field})"
  defp build_window_func_sql({:max, field}), do: "MAX(#{field})"

  # Build window clause SQL
  defp build_window_clause_sql(opts) do
    partition_by = Keyword.get(opts, :partition_by)
    order_by = Keyword.get(opts, :order_by)

    parts = []

    parts =
      if partition_by do
        fields = if is_list(partition_by), do: partition_by, else: [partition_by]
        field_list = Enum.map_join(fields, ", ", &to_string/1)
        ["PARTITION BY #{field_list}" | parts]
      else
        parts
      end

    parts =
      if order_by do
        order_clause = build_order_by_sql(order_by)
        ["ORDER BY #{order_clause}" | parts]
      else
        parts
      end

    Enum.join(Enum.reverse(parts), " ")
  end

  # Build ORDER BY SQL from keyword list
  defp build_order_by_sql(order_list) when is_list(order_list) do
    Enum.map_join(order_list, ", ", fn
      {:asc, field} -> "#{field} ASC"
      {:desc, field} -> "#{field} DESC"
      field when is_atom(field) -> "#{field}"
    end)
  end

  defp apply_opts(builder, opts) do
    Enum.reduce(opts, builder, fn
      {:where, conditions}, acc -> where(acc, conditions)
      {:filters, filter_list}, acc -> where(acc, filter_list)
      {:join, assoc}, acc -> join(acc, assoc)
      {:select, fields}, acc -> select(acc, fields)
      {:distinct, value}, acc -> distinct(acc, value)
      {:group_by, fields}, acc -> group_by(acc, fields)
      {:having, conditions}, acc -> having(acc, conditions)
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

  # Process preload specifications into Ecto-compatible format
  defp process_preloads(assocs) when is_list(assocs) do
    Enum.map(assocs, &process_preload/1)
  end

  # Atom - simple preload
  defp process_preload(assoc) when is_atom(assoc), do: assoc

  # Tuple with Ecto.Query - pass through
  defp process_preload({assoc, %Ecto.Query{} = query}) when is_atom(assoc) do
    {assoc, query}
  end

  # Tuple with keyword list - build query from conditions
  defp process_preload({assoc, opts}) when is_atom(assoc) and is_list(opts) do
    # Check if it's already an Ecto.Query in the list
    case opts do
      [%Ecto.Query{} | _] ->
        {assoc, opts}

      _ ->
        # Build a query from the options
        query = build_preload_query(assoc, opts)
        {assoc, query}
    end
  end

  # Build an Ecto query for a preload association with conditions
  defp build_preload_query(assoc, opts) do
    # We need to get the association's schema, but we don't have it here
    # So we'll build a query function that Ecto can call
    fn ->
      # Extract the different options
      where_conditions = Keyword.get(opts, :where, [])
      order_by_opts = Keyword.get(opts, :order_by)
      limit_value = Keyword.get(opts, :limit)
      offset_value = Keyword.get(opts, :offset)
      nested_preloads = Keyword.get(opts, :preload, [])

      # Build the query dynamically
      # Note: This will be evaluated by Ecto with the proper schema
      import Ecto.Query

      query = from(a in assoc)

      # Apply where conditions
      query =
        Enum.reduce(where_conditions, query, fn {field, value}, q ->
          from(a in q, where: field(a, ^field) == ^value)
        end)

      # Apply order_by
      query =
        if order_by_opts do
          from(a in query, order_by: ^order_by_opts)
        else
          query
        end

      # Apply limit
      query =
        if limit_value do
          from(a in query, limit: ^limit_value)
        else
          query
        end

      # Apply offset
      query =
        if offset_value do
          from(a in query, offset: ^offset_value)
        else
          query
        end

      # Apply nested preloads
      query =
        if nested_preloads != [] do
          processed_nested = process_preloads(nested_preloads)
          from(a in query, preload: ^processed_nested)
        else
          query
        end

      query
    end
  end

  defp apply_filter(query, binding, field, op, value, opts) do
    # Apply value transformation function if provided
    value = apply_value_fn(value, op, opts)

    # Normalize data type values (e.g., convert date strings to Date)
    value = normalize_data_type_value(value, op, opts)

    case op do
      :eq -> apply_eq(query, binding, field, value, opts)
      :neq -> apply_neq(query, binding, field, value, opts)
      :gt -> apply_comparison(query, binding, field, :>, value, opts)
      :gte -> apply_comparison(query, binding, field, :>=, value, opts)
      :lt -> apply_comparison(query, binding, field, :<, value, opts)
      :lte -> apply_comparison(query, binding, field, :<=, value, opts)
      :in -> apply_in(query, binding, field, value)
      :not_in -> apply_not_in(query, binding, field, value)
      :like -> apply_like(query, binding, field, value, opts)
      :ilike -> apply_ilike(query, binding, field, value, opts)
      :not_like -> apply_not_like(query, binding, field, value, opts)
      :not_ilike -> apply_not_ilike(query, binding, field, value, opts)
      :is_nil -> apply_is_nil(query, binding, field)
      :not_nil -> apply_not_nil(query, binding, field)
      :between -> apply_between(query, binding, field, value, opts)
      :contains -> apply_contains(query, binding, field, value)
      :contained_by -> apply_contained_by(query, binding, field, value)
      :jsonb_contains -> apply_jsonb_contains(query, binding, field, value)
      :jsonb_has_key -> apply_jsonb_has_key(query, binding, field, value)
      _ -> raise "Unknown operation: #{op}"
    end
  end

  # Apply value transformation function if provided in options
  defp apply_value_fn(value, op, opts) do
    # First apply trimming if enabled (default: true)
    value = apply_trim(value, op, opts)

    # Then apply custom value_fn if provided
    case Keyword.get(opts, :value_fn) do
      nil ->
        value

      fn_transform when is_function(fn_transform, 1) ->
        case op do
          # For :in and :not_in, apply function to each element in the list
          op when op in [:in, :not_in] and is_list(value) ->
            Enum.map(value, fn_transform)

          # For :between, apply function to both min and max
          :between when is_tuple(value) ->
            {min, max} = value
            {fn_transform.(min), fn_transform.(max)}

          # For :is_nil and :not_nil, don't transform (no value used)
          op when op in [:is_nil, :not_nil] ->
            value

          # For all other operations, apply function to the value
          _ ->
            fn_transform.(value)
        end
    end
  end

  # Apply trimming to string values (default: enabled)
  defp apply_trim(value, op, opts) do
    trim_enabled = Keyword.get(opts, :trim, true)

    if trim_enabled do
      case op do
        # For :in and :not_in, trim each string element in the list
        op when op in [:in, :not_in] and is_list(value) ->
          Enum.map(value, fn
            v when is_binary(v) -> String.trim(v)
            v -> v
          end)

        # For :between, trim both values if they're strings
        :between when is_tuple(value) ->
          {min, max} = value
          min = if is_binary(min), do: String.trim(min), else: min
          max = if is_binary(max), do: String.trim(max), else: max
          {min, max}

        # For :is_nil and :not_nil, don't transform
        op when op in [:is_nil, :not_nil] ->
          value

        # For all other operations, trim if it's a string
        _ ->
          if is_binary(value), do: String.trim(value), else: value
      end
    else
      value
    end
  end

  # Normalize values based on data_type option
  # Converts string date/time values to appropriate Elixir types
  defp normalize_data_type_value(value, op, opts) do
    data_type = Keyword.get(opts, :data_type)

    case data_type do
      :date ->
        case op do
          # For :in and :not_in, convert each element in the list
          op when op in [:in, :not_in] and is_list(value) ->
            Enum.map(value, &parse_date_value/1)

          # For :between, convert both min and max
          :between when is_tuple(value) ->
            {min, max} = value
            {parse_date_value(min), parse_date_value(max)}

          # For :is_nil and :not_nil, don't transform
          op when op in [:is_nil, :not_nil] ->
            value

          # For all other operations, convert the value
          _ ->
            parse_date_value(value)
        end

      :datetime ->
        case op do
          op when op in [:in, :not_in] and is_list(value) ->
            Enum.map(value, &parse_datetime_value/1)

          :between when is_tuple(value) ->
            {min, max} = value
            {parse_datetime_value(min), parse_datetime_value(max)}

          op when op in [:is_nil, :not_nil] ->
            value

          _ ->
            parse_datetime_value(value)
        end

      :time ->
        case op do
          op when op in [:in, :not_in] and is_list(value) ->
            Enum.map(value, &parse_time_value/1)

          :between when is_tuple(value) ->
            {min, max} = value
            {parse_time_value(min), parse_time_value(max)}

          op when op in [:is_nil, :not_nil] ->
            value

          _ ->
            parse_time_value(value)
        end

      _ ->
        value
    end
  end

  # Parse date from various string formats or return existing Date
  defp parse_date_value(%Date{} = date), do: date
  defp parse_date_value(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp parse_date_value(%NaiveDateTime{} = naive), do: NaiveDateTime.to_date(naive)

  defp parse_date_value(value) when is_binary(value) do
    cond do
      # yyyy-mm-dd or yyyy/mm/dd
      Regex.match?(~r/^\d{4}[-\/]\d{1,2}[-\/]\d{1,2}$/, value) ->
        parse_date_iso_format(value)

      # mm-dd-yyyy or mm/dd/yyyy
      Regex.match?(~r/^\d{1,2}[-\/]\d{1,2}[-\/]\d{4}$/, value) ->
        parse_date_us_format(value)

      # If already a valid ISO date string (from Date sigil)
      true ->
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          {:error, _} -> raise "Invalid date format: #{value}. Expected formats: yyyy-mm-dd, yyyy/mm/dd, mm-dd-yyyy, mm/dd/yyyy"
        end
    end
  end

  defp parse_date_value(value), do: value

  # Parse ISO format: yyyy-mm-dd or yyyy/mm/dd
  defp parse_date_iso_format(value) do
    normalized = String.replace(value, "/", "-")
    case Date.from_iso8601(normalized) do
      {:ok, date} -> date
      {:error, _} -> raise "Invalid date: #{value}"
    end
  end

  # Parse US format: mm-dd-yyyy or mm/dd/yyyy
  defp parse_date_us_format(value) do
    parts = String.split(value, ~r/[-\/]/)
    case parts do
      [month, day, year] ->
        # Convert to ISO format: yyyy-mm-dd
        iso_string = "#{year}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}"
        case Date.from_iso8601(iso_string) do
          {:ok, date} -> date
          {:error, _} -> raise "Invalid date: #{value}"
        end
      _ ->
        raise "Invalid date format: #{value}"
    end
  end

  # Parse datetime from string or return existing DateTime
  defp parse_datetime_value(%DateTime{} = datetime), do: datetime
  defp parse_datetime_value(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")

  defp parse_datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} ->
        # Try NaiveDateTime
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          {:error, _} -> raise "Invalid datetime format: #{value}. Expected ISO8601 format."
        end
    end
  end

  defp parse_datetime_value(value), do: value

  # Parse time from string or return existing Time
  defp parse_time_value(%Time{} = time), do: time

  defp parse_time_value(value) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> time
      {:error, _} -> raise "Invalid time format: #{value}. Expected ISO8601 format (HH:MM:SS)."
    end
  end

  defp parse_time_value(value), do: value

  defp apply_eq(query, 0, field, value, opts) do
    include_nil = Keyword.get(opts, :include_nil, false)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    data_type = Keyword.get(opts, :data_type)

    cond do
      # Date/datetime/time comparison - cast to appropriate type
      data_type in [:date, :datetime, :time] ->
        cast_type = get_pg_cast_type(data_type)
        if include_nil do
          from(q in query,
            where:
              fragment("?::#{cast_type} = ?::#{cast_type}", field(q, ^field), ^value) or
                is_nil(field(q, ^field))
          )
        else
          from(q in query, where: fragment("?::#{cast_type} = ?::#{cast_type}", field(q, ^field), ^value))
        end

      # String comparison with case insensitive (default)
      is_binary(value) and not case_sensitive ->
        if include_nil do
          from(q in query,
            where:
              fragment("lower(?)", field(q, ^field)) == fragment("lower(?)", ^value) or
                is_nil(field(q, ^field))
          )
        else
          from(q in query, where: fragment("lower(?)", field(q, ^field)) == fragment("lower(?)", ^value))
        end

      # Normal comparison (non-string or case sensitive)
      true ->
        if include_nil do
          from(q in query, where: field(q, ^field) == ^value or is_nil(field(q, ^field)))
        else
          from(q in query, where: field(q, ^field) == ^value)
        end
    end
  end

  defp apply_eq(query, binding, field, value, opts) do
    include_nil = Keyword.get(opts, :include_nil, false)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    data_type = Keyword.get(opts, :data_type)

    cond do
      # Date/datetime/time comparison - cast to appropriate type
      data_type in [:date, :datetime, :time] ->
        cast_type = get_pg_cast_type(data_type)
        if include_nil do
          from(q in query,
            where:
              fragment("?::#{cast_type} = ?::#{cast_type}", field(as(^binding), ^field), ^value) or
                is_nil(field(as(^binding), ^field))
          )
        else
          from(q in query,
            where: fragment("?::#{cast_type} = ?::#{cast_type}", field(as(^binding), ^field), ^value)
          )
        end

      # String comparison with case insensitive (default)
      is_binary(value) and not case_sensitive ->
        if include_nil do
          from(q in query,
            where:
              fragment("lower(?)", field(as(^binding), ^field)) == fragment("lower(?)", ^value) or
                is_nil(field(as(^binding), ^field))
          )
        else
          from(q in query,
            where: fragment("lower(?)", field(as(^binding), ^field)) == fragment("lower(?)", ^value)
          )
        end

      # Normal comparison (non-string or case sensitive)
      true ->
        if include_nil do
          from(q in query,
            where: field(as(^binding), ^field) == ^value or is_nil(field(as(^binding), ^field))
          )
        else
          from(q in query, where: field(as(^binding), ^field) == ^value)
        end
    end
  end

  defp apply_neq(query, 0, field, value, opts) do
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    data_type = Keyword.get(opts, :data_type)

    cond do
      # Date/datetime/time comparison - cast to appropriate type
      data_type in [:date, :datetime, :time] ->
        cast_type = get_pg_cast_type(data_type)
        from(q in query, where: fragment("?::#{cast_type} != ?::#{cast_type}", field(q, ^field), ^value))

      # String comparison with case insensitive
      is_binary(value) and not case_sensitive ->
        from(q in query, where: fragment("lower(?)", field(q, ^field)) != fragment("lower(?)", ^value))

      # Normal comparison
      true ->
        from(q in query, where: field(q, ^field) != ^value)
    end
  end

  defp apply_neq(query, binding, field, value, opts) do
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    data_type = Keyword.get(opts, :data_type)

    cond do
      # Date/datetime/time comparison - cast to appropriate type
      data_type in [:date, :datetime, :time] ->
        cast_type = get_pg_cast_type(data_type)
        from(q in query,
          where: fragment("?::#{cast_type} != ?::#{cast_type}", field(as(^binding), ^field), ^value)
        )

      # String comparison with case insensitive
      is_binary(value) and not case_sensitive ->
        from(q in query,
          where: fragment("lower(?)", field(as(^binding), ^field)) != fragment("lower(?)", ^value)
        )

      # Normal comparison
      true ->
        from(q in query, where: field(as(^binding), ^field) != ^value)
    end
  end

  defp apply_comparison(query, 0, field, op, value, opts) do
    data_type = Keyword.get(opts, :data_type)

    if data_type in [:date, :datetime, :time] do
      cast_type = get_pg_cast_type(data_type)
      from(q in query,
        where: fragment("?::#{cast_type} #{op} ?::#{cast_type}", field(q, ^field), ^value)
      )
    else
      from(q in query, where: field(q, ^field) |> fragment("? #{op} ?", ^value))
    end
  end

  defp apply_comparison(query, binding, field, op, value, opts) do
    data_type = Keyword.get(opts, :data_type)

    if data_type in [:date, :datetime, :time] do
      cast_type = get_pg_cast_type(data_type)
      from(q in query,
        where: fragment("?::#{cast_type} #{op} ?::#{cast_type}", field(as(^binding), ^field), ^value)
      )
    else
      from(q in query, where: field(as(^binding), ^field) |> fragment("? #{op} ?", ^value))
    end
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

  defp apply_like(query, 0, field, pattern, opts) do
    # Default to case insensitive (ILIKE)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)

    if case_sensitive do
      from(q in query, where: like(field(q, ^field), ^pattern))
    else
      from(q in query, where: ilike(field(q, ^field), ^pattern))
    end
  end

  defp apply_like(query, binding, field, pattern, opts) do
    # Default to case insensitive (ILIKE)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)

    if case_sensitive do
      from(q in query, where: like(field(as(^binding), ^field), ^pattern))
    else
      from(q in query, where: ilike(field(as(^binding), ^field), ^pattern))
    end
  end

  defp apply_ilike(query, 0, field, pattern, _opts) do
    from(q in query, where: ilike(field(q, ^field), ^pattern))
  end

  defp apply_ilike(query, binding, field, pattern, _opts) do
    from(q in query, where: ilike(field(as(^binding), ^field), ^pattern))
  end

  defp apply_not_like(query, 0, field, pattern, opts) do
    # Default to case insensitive (NOT ILIKE)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)

    if case_sensitive do
      from(q in query, where: not like(field(q, ^field), ^pattern))
    else
      from(q in query, where: not ilike(field(q, ^field), ^pattern))
    end
  end

  defp apply_not_like(query, binding, field, pattern, opts) do
    # Default to case insensitive (NOT ILIKE)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)

    if case_sensitive do
      from(q in query, where: not like(field(as(^binding), ^field), ^pattern))
    else
      from(q in query, where: not ilike(field(as(^binding), ^field), ^pattern))
    end
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

  defp apply_between(query, 0, field, {min, max}, opts) do
    data_type = Keyword.get(opts, :data_type)

    if data_type in [:date, :datetime, :time] do
      cast_type = get_pg_cast_type(data_type)
      from(q in query,
        where:
          fragment("?::#{cast_type} >= ?::#{cast_type}", field(q, ^field), ^min) and
            fragment("?::#{cast_type} <= ?::#{cast_type}", field(q, ^field), ^max)
      )
    else
      from(q in query, where: field(q, ^field) >= ^min and field(q, ^field) <= ^max)
    end
  end

  defp apply_between(query, binding, field, {min, max}, opts) do
    data_type = Keyword.get(opts, :data_type)

    if data_type in [:date, :datetime, :time] do
      cast_type = get_pg_cast_type(data_type)
      from(q in query,
        where:
          fragment("?::#{cast_type} >= ?::#{cast_type}", field(as(^binding), ^field), ^min) and
            fragment("?::#{cast_type} <= ?::#{cast_type}", field(as(^binding), ^field), ^max)
      )
    else
      from(q in query,
        where: field(as(^binding), ^field) >= ^min and field(as(^binding), ^field) <= ^max
      )
    end
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

  # Convert data type to PostgreSQL cast type
  defp get_pg_cast_type(:date), do: "date"
  defp get_pg_cast_type(:datetime), do: "timestamp"
  defp get_pg_cast_type(:time), do: "time"
end

# Implement Ecto.Queryable protocol so Query works with Repo.all, Repo.one, etc
defimpl Ecto.Queryable, for: Events.Repo.Query do
  def to_query(%Events.Repo.Query{query: query}), do: query
end
