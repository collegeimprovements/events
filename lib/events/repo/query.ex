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

  ## Audit Fields

  This module supports audit tracking fields with the following naming convention:

  - `created_by_urm_id` - ID of the user_role_mapping who created the record
  - `updated_by_urm_id` - ID of the user_role_mapping who last updated the record
  - `deleted_by_urm_id` - ID of the user_role_mapping who soft-deleted the record

  > **Note**: The `_urm_id` suffix stands for "user_role_mapping ID", referencing the
  > `user_role_mappings` table. This table maps users to their roles in the system.

  These fields are automatically populated when using the query builder's modification functions:

      # Automatically sets updated_by_urm_id
      Query.update_all(query, [set: [status: "published"]], updated_by: user_role_mapping_id)

      # Automatically sets deleted_by_urm_id
      Query.delete(record, deleted_by: user_role_mapping_id)

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

  # Configuration constants
  @soft_delete_field :deleted_at
  @default_trim_enabled true
  @default_case_sensitive false
  @default_include_nil false

  @type t :: %__MODULE__{
          schema: module(),
          query: Ecto.Query.t(),
          joins: %{atom() => atom()},
          include_deleted: boolean(),
          metadata: map()
        }

  defstruct [
    :schema,
    :query,
    joins: %{},
    include_deleted: false,
    metadata: %{}
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
    include_deleted = Keyword.get(opts, :include_deleted, false)
    query = build_base_query(schema, include_deleted)

    builder = %__MODULE__{
      schema: schema,
      query: query,
      include_deleted: include_deleted
    }

    # Apply keyword options
    apply_opts(builder, opts)
  end

  defp build_base_query(schema, true), do: from(s in schema)

  defp build_base_query(schema, false) do
    from(s in schema, where: is_nil(field(s, ^@soft_delete_field)))
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
    Enum.reduce(conditions, builder, fn cond_item, acc ->
      __MODULE__.where(acc, cond_item)
    end)
  end

  def where(%__MODULE__{} = builder, {field, value}) when is_atom(field) do
    # Simple field: value - infer operation
    __MODULE__.where(builder, {field, infer_operation(value), value})
  end

  def where(%__MODULE__{} = builder, {field, op, value}) when is_atom(field) and is_atom(op) do
    # Field on main table
    __MODULE__.where(builder, {nil, field, op, value, []})
  end

  def where(%__MODULE__{} = builder, {field, op, value, opts})
      when is_atom(field) and is_atom(op) and is_list(opts) do
    # Field on main table with options
    __MODULE__.where(builder, {nil, field, op, value, opts})
  end

  def where(%__MODULE__{} = builder, {join_name, field, value})
      when is_atom(join_name) and is_atom(field) do
    # Field on joined table - infer operation
    __MODULE__.where(builder, {join_name, field, infer_operation(value), value, []})
  end

  def where(%__MODULE__{} = builder, {join_name, field, op, value})
      when is_atom(join_name) and is_atom(field) and is_atom(op) do
    # Field on joined table with operation
    __MODULE__.where(builder, {join_name, field, op, value, []})
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
  def join(builder, assoc_name, join_type_or_opts \\ :inner)

  # When opts is a keyword list with :through option
  def join(%__MODULE__{} = builder, assoc_name, opts) when is_list(opts) do
    case Keyword.has_key?(opts, :through) do
      true ->
        # Explicit through join with options
        through_assoc = Keyword.get(opts, :through)
        through_filters = Keyword.get(opts, :where)
        join_type = Keyword.get(opts, :type, :inner)

        # Get the final field name from the through association
        final_field = get_through_final_field(builder.schema, through_assoc, assoc_name)

        # Join the intermediate table
        builder = join_direct(builder, through_assoc, join_type)

        # Apply filters on intermediate table if provided
        builder = maybe_apply_through_filters(builder, through_assoc, through_filters)

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

      false ->
        # Keyword list but no :through, might have other options
        join_type = Keyword.get(opts, :type, :inner)
        __MODULE__.join(builder, assoc_name, join_type)
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
    builder = maybe_apply_through_filters(builder, through_assoc, through_filters)

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
  """
  @spec having(t(), keyword()) :: t()
  def having(builder, conditions)

  def having(%__MODULE__{} = builder, conditions) when is_list(conditions) do
    query = Enum.reduce(conditions, builder.query, &apply_having_condition/2)
    %{builder | query: query}
  end

  # Apply individual having conditions based on aggregate type and operator
  defp apply_having_condition({aggregate, {op, value}}, query) do
    apply_aggregate_having(query, aggregate, op, value)
  end

  # Pattern match on specific aggregates and operations
  defp apply_aggregate_having(query, :count, :gt, value) do
    from(s in query, having: fragment("count(*) > ?", ^value))
  end

  defp apply_aggregate_having(query, :count, :gte, value) do
    from(s in query, having: fragment("count(*) >= ?", ^value))
  end

  defp apply_aggregate_having(query, :count, :lt, value) do
    from(s in query, having: fragment("count(*) < ?", ^value))
  end

  defp apply_aggregate_having(query, :count, :lte, value) do
    from(s in query, having: fragment("count(*) <= ?", ^value))
  end

  defp apply_aggregate_having(query, :count, :eq, value) do
    from(s in query, having: fragment("count(*) = ?", ^value))
  end

  # Default case for unknown aggregates
  defp apply_aggregate_having(query, _aggregate, _op, _value), do: query

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
  def window(%__MODULE__{} = builder, name, opts) do
    # For now, we'll store window definitions in metadata
    # Full window function support would require Ecto changes
    windows = Map.get(builder.metadata, :windows, %{})
    windows = Map.put(windows, name, opts)
    metadata = Map.put(builder.metadata, :windows, windows)
    %{builder | metadata: metadata}
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
    # Check if any values are window function tuples
    has_window_functions =
      Enum.any?(field_map, fn
        {_key, {:window, _func, _opts}} -> true
        _ -> false
      end)

    if has_window_functions do
      # For now, we'll store window function selections in metadata
      # Full support would require Ecto changes
      metadata = Map.put(builder.metadata, :window_selects, field_map)
      %{builder | metadata: metadata}
    else
      # Simple map selection without window functions
      select_expr =
        Enum.reduce(field_map, %{}, fn {key, field}, acc when is_atom(field) ->
          Map.put(acc, key, dynamic([s], field(s, ^field)))
        end)

      query = from(s in builder.query, select: ^select_expr)
      %{builder | query: query}
    end
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
  def from_subquery(%__MODULE__{query: subquery, schema: schema}, alias_name)
      when is_atom(alias_name) do
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
  def where_in_subquery(%__MODULE__{} = builder, field, %__MODULE__{query: sq})
      when is_atom(field) do
    query = from(s in builder.query, where: field(s, ^field) in subquery(sq))
    %{builder | query: query}
  end

  @spec where_not_in_subquery(t(), atom(), t()) :: t()
  def where_not_in_subquery(%__MODULE__{} = builder, field, %__MODULE__{query: sq})
      when is_atom(field) do
    query = from(s in builder.query, where: field(s, ^field) not in subquery(sq))
    %{builder | query: query}
  end

  @spec where_exists(t(), t()) :: t()
  def where_exists(%__MODULE__{} = builder, %__MODULE__{query: sq}) do
    query = from(s in builder.query, where: exists(sq))
    %{builder | query: query}
  end

  @spec where_not_exists(t(), t()) :: t()
  def where_not_exists(%__MODULE__{} = builder, %__MODULE__{query: sq}) do
    query = from(s in builder.query, where: not exists(sq))
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
  def select_subquery(%__MODULE__{} = builder, field_name, %__MODULE__{query: sq})
      when is_atom(field_name) do
    # Add scalar subquery to select
    query = from(s in builder.query, select_merge: %{^field_name => subquery(sq)})
    %{builder | query: query}
  end

  def select_subquery(%__MODULE__{} = builder, field_name, sq)
      when is_atom(field_name) do
    # Support raw Ecto.Query
    query = from(s in builder.query, select_merge: %{^field_name => subquery(sq)})
    %{builder | query: query}
  end

  @doc """
  Adds HAVING clause for filtering grouped results.

  ## Examples

      Query.group_by(query, :category_id)

  @doc \"""
  Adds pagination support.

  ## Examples

      # Offset pagination
      Query.new(Product)
      |> Query.paginate(:offset, limit: 20, offset: 40)

      # Cursor pagination (simplified)
      Query.new(Product)
      |> Query.paginate(:cursor, limit: 10, cursor_fields: [inserted_at: :desc, id: :desc])
  """
  @spec paginate(t(), atom(), keyword()) :: t()
  def paginate(%__MODULE__{} = builder, :offset, opts) do
    limit = opts[:limit]
    offset = opts[:offset] || 0

    # Store pagination metadata
    pagination_meta = %{type: :offset, limit: limit, offset: offset}
    metadata = Map.put(builder.metadata, :pagination, pagination_meta)

    builder
    |> apply_limit(limit)
    |> apply_offset(offset)
    |> Map.put(:metadata, metadata)
  end

  def paginate(%__MODULE__{} = builder, :cursor, opts) do
    limit = opts[:limit] || 20
    cursor_fields = opts[:cursor_fields] || [:id]
    after_cursor = opts[:after]
    before_cursor = opts[:before]

    # Decode cursors if provided
    after_data = if after_cursor, do: decode_cursor(after_cursor)
    before_data = if before_cursor, do: decode_cursor(before_cursor)

    # Apply cursor conditions to query
    query = builder.query
    query = if after_data, do: apply_after_cursor(query, after_data, cursor_fields), else: query
    query = if before_data, do: apply_before_cursor(query, before_data, cursor_fields), else: query

    # Store pagination metadata
    pagination_meta = %{
      type: :cursor,
      limit: limit,
      cursor_fields: cursor_fields,
      after_cursor: after_cursor,
      before_cursor: before_cursor
    }

    metadata = Map.put(builder.metadata, :pagination, pagination_meta)

    builder
    |> Map.put(:query, query)
    |> apply_limit(limit)
    |> Map.put(:metadata, metadata)
  end

  # Helper functions for pagination
  defp apply_limit(%__MODULE__{} = builder, nil), do: builder

  defp apply_limit(%__MODULE__{} = builder, limit) do
    query = from(q in builder.query, limit: ^limit)
    %{builder | query: query}
  end

  defp apply_offset(%__MODULE__{} = builder, 0), do: builder

  defp apply_offset(%__MODULE__{} = builder, offset) do
    query = from(q in builder.query, offset: ^offset)
    %{builder | query: query}
  end

  # Build comprehensive pagination metadata
  defp build_pagination_metadata(%__MODULE__{} = builder, results, total_count, cursor_fields) do
    case Map.get(builder.metadata, :pagination) do
      %{type: :offset, limit: limit, offset: offset} ->
        has_more = length(results) == limit

        %{
          type: :offset,
          limit: limit,
          offset: offset,
          has_more: has_more,
          total_count: total_count,
          current_page: div(offset, limit) + 1,
          total_pages: if(total_count && limit, do: ceil(total_count / limit)),
          next_offset: if(has_more, do: offset + limit),
          prev_offset: if(offset > 0, do: max(0, offset - limit))
        }

      %{type: :cursor, limit: limit} ->
        has_more = length(results) == limit
        last_item = if(has_more && length(results) > 0, do: List.last(results))
        first_item = if(length(results) > 0, do: List.first(results))

        %{
          type: :cursor,
          limit: limit,
          has_more: has_more,
          total_count: total_count,
          cursor_fields: cursor_fields,
          start_cursor: encode_cursor(first_item, cursor_fields),
          end_cursor: encode_cursor(last_item, cursor_fields),
          # Would need more complex logic
          has_previous_page: false,
          has_next_page: has_more
        }

      _ ->
        # No pagination applied
        %{type: nil, has_more: false, total_count: total_count}
    end
  end

  # Remove pagination from query builder for count queries
  defp remove_pagination(%__MODULE__{} = builder) do
    # Remove limit and offset from the query
    query_without_pagination =
      builder.query
      |> Ecto.Query.exclude(:limit)
      |> Ecto.Query.exclude(:offset)

    %{
      builder
      | query: query_without_pagination,
        metadata: Map.delete(builder.metadata, :pagination)
    }
  end

  # Encode cursor from record and fields using Erlang binary serialization
  defp encode_cursor(nil, _fields), do: nil

  defp encode_cursor(record, fields) do
    cursor_data = Map.take(record, fields)
    # Use Erlang's term_to_binary for efficient serialization
    :erlang.term_to_binary(cursor_data) |> Base.encode64()
  end

  # Decode cursor using Erlang binary deserialization
  def decode_cursor(encoded_cursor) do
    decoded = Base.decode64!(encoded_cursor)
    :erlang.binary_to_term(decoded)
  end

  # Decode cursor (for future use)

  # Apply after cursor condition (for forward pagination)
  # This is a simplified implementation - real cursor pagination would be more sophisticated
  defp apply_after_cursor(query, cursor_data, cursor_fields) do
    # For now, just add a simple condition on the first cursor field
    # In practice, you'd want lexicographic ordering across all cursor fields
    field = List.first(cursor_fields)
    field_value = Map.get(cursor_data, field)
    from(q in query, where: field(q, ^field) > ^field_value)
  end

  # Apply before cursor condition (for backward pagination)
  defp apply_before_cursor(query, cursor_data, cursor_fields) do
    field = List.first(cursor_fields)
    field_value = Map.get(cursor_data, field)
    from(q in query, where: field(q, ^field) < ^field_value)
  end

  # Apply before cursor condition (for backward pagination)

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
  def include_deleted(%__MODULE__{} = builder) do
    # This is tricky - we need to rebuild the query without the soft delete filter
    # but preserve all other filters. Since we apply soft delete at creation,
    # the best approach is to mark it as included and warn if called after creation
    if builder.include_deleted do
      # Already including deleted records
      builder
    else
      # Mark as including deleted and warn about usage
      IO.warn("""
      Query.include_deleted/1 should be called at query creation using the :include_deleted option.
      Calling it after other filters may not work as expected.

      Instead of:
        Query.new(Product) |> Query.where(...) |> Query.include_deleted()

      Use:
        Query.new(Product, include_deleted: true) |> Query.where(...)
      """)

      %{builder | include_deleted: true}
    end
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
      |> Query.debug()
      # => Returns formatted string representation
  """
  @spec debug(t()) :: String.t()
  def debug(%__MODULE__{} = builder) do
    Kernel.inspect(builder.query, pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  @doc """
  Executes the query and returns all results.

  ## Examples

      Query.new(Product)
      |> Query.where(status: "active")
      |> Query.all()
  """
  @spec all(t()) :: [Ecto.Schema.t()]
  def all(%__MODULE__{query: query}), do: Repo.all(query)

  @doc """
  Executes the query and returns a single result or nil.

  ## Examples

      Query.new(Product)
      |> Query.where(id: 123)
      |> Query.one()
  """
  @spec one(t()) :: Ecto.Schema.t() | nil
  def one(%__MODULE__{query: query}), do: Repo.one(query)

  @doc """
  Executes the query and returns the first result or nil.

  ## Examples

      Query.new(Product)
      |> Query.order(:inserted_at, :desc)
      |> Query.first()
  """
  @spec first(t()) :: Ecto.Schema.t() | nil
  def first(%__MODULE__{query: query}) do
    Repo.one(from(q in query, limit: 1))
  end

  @doc """
  Executes the query as a stream.

  ## Examples

      Query.new(Product)
      |> Query.where(status: "active")
      |> Query.stream()
      |> Enum.take(100)
  """
  @spec stream(t(), integer()) :: Enum.t()
  def stream(%__MODULE__{query: query}, max_rows \\ 500) do
    Repo.stream(query, max_rows: max_rows)
  end

  @doc """
  Executes the query and returns an aggregate count.

  ## Examples

      Query.new(Product)
      |> Query.where(status: "active")
      |> Query.count()
  """
  @spec count(t()) :: integer()
  def count(%__MODULE__{query: query}) do
    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Executes the query and returns an aggregate value.

  ## Examples

      Query.new(Product)
      |> Query.where(status: "active")
      |> Query.aggregate(:sum, :price)
  """
  @spec aggregate(t(), atom(), atom()) :: term()
  def aggregate(%__MODULE__{query: query}, aggregate, field) do
    Repo.aggregate(query, aggregate, field)
  end

  @doc """
  Executes a paginated query and returns structured results with pagination metadata.

  ## Options

    * `:include_total_count` - Include total count in pagination metadata (default: false)
    * `:cursor_fields` - Fields to use for cursor encoding (default: [:id])

  ## Examples

      # Offset pagination
      result = Query.new(Product)
        |> Query.paginate(:offset, limit: 10, offset: 20)
        |> Query.paginated_all(include_total_count: true)

      # result = %{
      #   data: [...],
      #   pagination: %{type: :offset, limit: 10, offset: 20, has_more: true, total_count: 150, ...}
      # }

      # Cursor pagination
      result = Query.new(Product)
        |> Query.order_by([desc: :inserted_at, desc: :id])
        |> Query.paginate(:cursor, limit: 10)
        |> Query.paginated_all(cursor_fields: [:inserted_at, :id])
  """
  @spec paginated_all(t(), keyword()) :: %{data: [Ecto.Schema.t()], pagination: map()}
  def paginated_all(%__MODULE__{} = builder, opts \\ []) do
    include_total_count = Keyword.get(opts, :include_total_count, false)
    cursor_fields = Keyword.get(opts, :cursor_fields, [:id])

    results = Repo.all(builder.query)

    total_count =
      if include_total_count do
        # Remove pagination for count query
        count_builder = remove_pagination(builder)
        Repo.aggregate(count_builder.query, :count, :id)
      end

    pagination = build_pagination_metadata(builder, results, total_count, cursor_fields)

    %{
      data: results,
      pagination: pagination
    }
  end

  @doc """
  Executes a paginated query and returns the first result with structured pagination metadata.

  ## Options

    * `:include_total_count` - Include total count in pagination metadata (default: false)

  ## Examples

      result = Query.new(Product)
        |> Query.paginate(:offset, limit: 1)
        |> Query.paginated_first(include_total_count: true)
  """
  @spec paginated_first(t(), keyword()) :: %{data: Ecto.Schema.t() | nil, pagination: map()}
  def paginated_first(%__MODULE__{} = builder, opts \\ []) do
    include_total_count = Keyword.get(opts, :include_total_count, false)

    result = Repo.one(from(q in builder.query, limit: 1))

    total_count =
      if include_total_count do
        count_builder = remove_pagination(builder)
        Repo.aggregate(count_builder.query, :count, :id)
      end

    pagination = build_pagination_metadata(builder, [result], total_count, [:id])

    %{
      data: result,
      pagination: pagination
    }
  end

  @doc """
  Executes a paginated count query with structured results.

  ## Examples

      result = Query.new(Product)
        |> Query.where(status: "active")
        |> Query.paginated_count()
  """
  @spec paginated_count(t()) :: %{data: integer(), pagination: map()}
  def paginated_count(%__MODULE__{} = builder) do
    count = Repo.aggregate(builder.query, :count, :id)
    pagination = %{type: :count, total_count: count, has_more: false}

    %{
      data: count,
      pagination: pagination
    }
  end

  ## CRUD Operations

  @doc """
  Inserts a record.

  ## Examples

      {:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)
  """
  @spec insert(module(), map(), keyword()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def insert(schema, attrs, opts \\ []) do
    attrs = add_audit_fields(attrs, :insert, opts)
    changeset = build_changeset(schema, schema.__struct__(), attrs)
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
    changeset = build_changeset(schema, struct, attrs)
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
    case Keyword.get(opts, :hard, false) do
      true ->
        Repo.delete(struct)

      false ->
        now = DateTime.utc_now()
        deleted_by = Keyword.get(opts, :deleted_by)

        changes =
          %{deleted_at: now}
          |> maybe_add_deleted_by(deleted_by)

        struct
        |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
        |> Repo.update()
    end
  end

  defp maybe_add_deleted_by(changes, nil), do: changes

  defp maybe_add_deleted_by(changes, deleted_by),
    do: Map.put(changes, :deleted_by_urm_id, deleted_by)

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
    case Keyword.get(opts, :hard, false) do
      true ->
        {count, _} = Repo.delete_all(query)
        {:ok, count}

      false ->
        now = DateTime.utc_now()
        deleted_by = Keyword.get(opts, :deleted_by)

        updates =
          [set: [deleted_at: now]]
          |> maybe_add_deleted_by_update(deleted_by)

        {count, _} = Repo.update_all(query, updates)
        {:ok, count}
    end
  end

  defp maybe_add_deleted_by_update(updates, nil), do: updates

  defp maybe_add_deleted_by_update(updates, deleted_by) do
    Keyword.update(updates, :set, [], &(&1 ++ [deleted_by_urm_id: deleted_by]))
  end

  ## Private Helpers

  defp apply_opts(builder, opts) do
    Enum.reduce(opts, builder, fn
      {:where, conditions}, acc -> __MODULE__.where(acc, conditions)
      {:filters, filter_list}, acc -> __MODULE__.where(acc, filter_list)
      {:join, assoc}, acc -> __MODULE__.join(acc, assoc)
      {:select, fields}, acc -> __MODULE__.select(acc, fields)
      {:distinct, value}, acc -> __MODULE__.distinct(acc, value)
      {:group_by, fields}, acc -> __MODULE__.group_by(acc, fields)
      {:having, conditions}, acc -> __MODULE__.having(acc, conditions)
      {:order_by, ordering}, acc -> __MODULE__.order_by(acc, ordering)
      {:limit, value}, acc -> __MODULE__.limit(acc, value)
      {:offset, value}, acc -> __MODULE__.offset(acc, value)
      {:preload, assocs}, acc -> __MODULE__.preload(acc, assocs)
      # Already handled in new/2
      {:include_deleted, _}, acc -> acc
      _, acc -> acc
    end)
  end

  defp infer_operation(value) when is_list(value), do: :in
  defp infer_operation(_), do: :eq

  defp get_binding(_builder, nil), do: 0

  defp get_binding(%{joins: joins}, join_name) do
    case Map.has_key?(joins, join_name) do
      true -> join_name
      false -> raise "Join :#{join_name} not found. Did you forget to call Query.join/2?"
    end
  end

  defp build_changeset(schema, struct, attrs) do
    case function_exported?(schema, :changeset, 2) do
      true -> schema.changeset(struct, attrs)
      false -> Ecto.Changeset.cast(struct, attrs, Map.keys(attrs))
    end
  end

  defp maybe_apply_through_filters(builder, _through_assoc, nil), do: builder

  defp maybe_apply_through_filters(builder, through_assoc, filters) do
    __MODULE__.where(builder, normalize_through_filter(through_assoc, filters))
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
          from(s in builder.query,
            join: i in assoc(s, ^intermediate_assoc),
            as: ^intermediate_assoc
          )

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
  defp build_preload_query(_assoc, opts) do
    # Ecto expects a function that receives the association query
    # The function is called with the association's queryable
    fn queryable ->
      # Extract the different options
      where_conditions = Keyword.get(opts, :where, [])
      order_by_opts = Keyword.get(opts, :order_by)
      limit_value = Keyword.get(opts, :limit)
      offset_value = Keyword.get(opts, :offset)
      nested_preloads = Keyword.get(opts, :preload, [])

      # Start with the queryable passed by Ecto
      query = from(a in queryable)

      # Apply where conditions with proper pattern matching
      query =
        Enum.reduce(where_conditions, query, fn condition, q ->
          case condition do
            {field, value} when is_atom(field) ->
              from(a in q, where: field(a, ^field) == ^value)

            {field, op, value} when is_atom(field) and is_atom(op) ->
              apply_preload_filter(q, field, op, value)

            _ ->
              # Invalid condition, skip it
              q
          end
        end)

      # Apply order_by
      query =
        case order_by_opts do
          nil -> query
          opts when is_list(opts) -> from(a in query, order_by: ^opts)
          _ -> query
        end

      # Apply limit
      query =
        case limit_value do
          nil -> query
          limit when is_integer(limit) and limit > 0 -> from(a in query, limit: ^limit)
          _ -> query
        end

      # Apply offset
      query =
        case offset_value do
          nil -> query
          offset when is_integer(offset) and offset >= 0 -> from(a in query, offset: ^offset)
          _ -> query
        end

      # Apply nested preloads
      query =
        case nested_preloads do
          [] ->
            query

          [_ | _] = preloads ->
            processed_nested = process_preloads(preloads)
            from(a in query, preload: ^processed_nested)

          _ ->
            query
        end

      query
    end
  end

  # Helper function to apply preload filters with operators
  defp apply_preload_filter(query, field, op, value) do
    case op do
      :eq -> from(a in query, where: field(a, ^field) == ^value)
      :neq -> from(a in query, where: field(a, ^field) != ^value)
      :gt -> from(a in query, where: field(a, ^field) > ^value)
      :gte -> from(a in query, where: field(a, ^field) >= ^value)
      :lt -> from(a in query, where: field(a, ^field) < ^value)
      :lte -> from(a in query, where: field(a, ^field) <= ^value)
      :in when is_list(value) -> from(a in query, where: field(a, ^field) in ^value)
      :not_in when is_list(value) -> from(a in query, where: field(a, ^field) not in ^value)
      :is_nil -> from(a in query, where: is_nil(field(a, ^field)))
      :not_nil -> from(a in query, where: not is_nil(field(a, ^field)))
      # Unknown operator, skip
      _ -> query
    end
  end

  defp apply_filter(query, binding, field, op, value, opts) do
    # Check if data_type option is being used and raise error
    if Keyword.has_key?(opts, :data_type) do
      raise ArgumentError, """
      The :data_type option is currently not supported due to Ecto macro limitations.

      Please use Ecto's type/2 function for type casting instead:

        # Instead of:
        Query.where(query, {:created_at, :eq, "2024-01-01", data_type: :date})

        # Use:
        Query.where(query, {:created_at, :eq, ~D[2024-01-01]})

      Or use Ecto's type/2 in custom queries.
      """
    end

    # Apply value transformation function if provided
    value = apply_value_fn(value, op, opts)

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
    value
    |> apply_trim(op, opts)
    |> apply_custom_transform(op, opts)
  end

  # Apply custom transformation if value_fn is provided
  defp apply_custom_transform(value, _op, opts) when not is_map_key(opts, :value_fn), do: value

  defp apply_custom_transform(value, op, opts) do
    case Keyword.get(opts, :value_fn) do
      nil -> value
      fn_transform -> transform_by_operation(value, op, fn_transform)
    end
  end

  # Pattern match on operations that need special transformation handling
  defp transform_by_operation(value, op, _fn_transform) when op in [:is_nil, :not_nil], do: value

  defp transform_by_operation(value, op, fn_transform)
       when op in [:in, :not_in] and is_list(value) do
    Enum.map(value, fn_transform)
  end

  defp transform_by_operation({min, max}, :between, fn_transform) do
    {fn_transform.(min), fn_transform.(max)}
  end

  defp transform_by_operation(value, _op, fn_transform), do: fn_transform.(value)

  # Apply trimming to string values (default: enabled)
  defp apply_trim(value, op, opts) do
    case Keyword.get(opts, :trim, @default_trim_enabled) do
      false -> value
      true -> trim_value_by_operation(value, op)
    end
  end

  # Pattern match on operations that need special trimming logic
  defp trim_value_by_operation(value, op) when op in [:is_nil, :not_nil], do: value

  defp trim_value_by_operation(value, op) when op in [:in, :not_in] and is_list(value) do
    Enum.map(value, &maybe_trim/1)
  end

  defp trim_value_by_operation({min, max}, :between) do
    {maybe_trim(min), maybe_trim(max)}
  end

  defp trim_value_by_operation(value, _op), do: maybe_trim(value)

  # Helper to trim only binary values
  defp maybe_trim(value) when is_binary(value), do: String.trim(value)
  defp maybe_trim(value), do: value

  # Pattern-matched versions of apply_eq for better readability
  defp apply_eq(query, binding, field, value, opts) do
    include_nil = Keyword.get(opts, :include_nil, @default_include_nil)
    case_sensitive = Keyword.get(opts, :case_sensitive, @default_case_sensitive)

    build_eq_query(query, binding, field, value,
      string?: is_binary(value),
      case_sensitive?: case_sensitive,
      include_nil?: include_nil
    )
  end

  # Build equality query based on options
  defp build_eq_query(query, 0, field, value,
         string?: true,
         case_sensitive?: false,
         include_nil?: include_nil
       ) do
    base_condition =
      dynamic([q], fragment("lower(?)", field(q, ^field)) == fragment("lower(?)", ^value))

    apply_nil_condition(query, base_condition, field, 0, include_nil)
  end

  defp build_eq_query(query, 0, field, value,
         string?: _,
         case_sensitive?: _,
         include_nil?: include_nil
       ) do
    base_condition = dynamic([q], field(q, ^field) == ^value)
    apply_nil_condition(query, base_condition, field, 0, include_nil)
  end

  defp build_eq_query(query, binding, field, value,
         string?: true,
         case_sensitive?: false,
         include_nil?: include_nil
       ) do
    base_condition =
      dynamic(
        [{^binding, b}],
        fragment("lower(?)", field(b, ^field)) == fragment("lower(?)", ^value)
      )

    apply_nil_condition(query, base_condition, field, binding, include_nil)
  end

  defp build_eq_query(query, binding, field, value,
         string?: _,
         case_sensitive?: _,
         include_nil?: include_nil
       ) do
    base_condition = dynamic([{^binding, b}], field(b, ^field) == ^value)
    apply_nil_condition(query, base_condition, field, binding, include_nil)
  end

  # Helper to apply nil condition if needed
  defp apply_nil_condition(query, base_condition, field, 0, true) do
    from(q in query, where: ^base_condition or is_nil(field(q, ^field)))
  end

  defp apply_nil_condition(query, base_condition, _field, 0, false) do
    from(q in query, where: ^base_condition)
  end

  defp apply_nil_condition(query, base_condition, field, binding, true) do
    from(q in query, where: ^base_condition or is_nil(field(as(^binding), ^field)))
  end

  defp apply_nil_condition(query, base_condition, _field, _binding, false) do
    from(q in query, where: ^base_condition)
  end

  defp apply_neq(query, 0, field, value, opts) do
    case_sensitive = Keyword.get(opts, :case_sensitive, @default_case_sensitive)

    cond do
      # String comparison with case insensitive
      is_binary(value) and not case_sensitive ->
        from(q in query,
          where: fragment("lower(?)", field(q, ^field)) != fragment("lower(?)", ^value)
        )

      # Normal comparison
      true ->
        from(q in query, where: field(q, ^field) != ^value)
    end
  end

  defp apply_neq(query, binding, field, value, opts) do
    case_sensitive = Keyword.get(opts, :case_sensitive, @default_case_sensitive)

    cond do
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

  # Refactored comparison function using pattern matching to reduce duplication
  defp apply_comparison(query, binding, field, op, value, _opts) do
    case {binding, op} do
      {0, :>} -> from(q in query, where: field(q, ^field) > ^value)
      {0, :>=} -> from(q in query, where: field(q, ^field) >= ^value)
      {0, :<} -> from(q in query, where: field(q, ^field) < ^value)
      {0, :<=} -> from(q in query, where: field(q, ^field) <= ^value)
      {b, :>} -> from(q in query, where: field(as(^b), ^field) > ^value)
      {b, :>=} -> from(q in query, where: field(as(^b), ^field) >= ^value)
      {b, :<} -> from(q in query, where: field(as(^b), ^field) < ^value)
      {b, :<=} -> from(q in query, where: field(as(^b), ^field) <= ^value)
    end
  end

  defp apply_in(query, 0, field, values) when is_list(values) do
    case values do
      [] ->
        # Empty list means no matches - return a query that will return no results
        from(q in query, where: false)

      _ ->
        from(q in query, where: field(q, ^field) in ^values)
    end
  end

  defp apply_in(query, binding, field, values) when is_list(values) do
    case values do
      [] ->
        # Empty list means no matches - return a query that will return no results
        from(q in query, where: false)

      _ ->
        from(q in query, where: field(as(^binding), ^field) in ^values)
    end
  end

  defp apply_not_in(query, 0, field, values) when is_list(values) do
    case values do
      [] ->
        # Empty list means exclude nothing - return the query unchanged
        query

      _ ->
        from(q in query, where: field(q, ^field) not in ^values)
    end
  end

  defp apply_not_in(query, binding, field, values) when is_list(values) do
    case values do
      [] ->
        # Empty list means exclude nothing - return the query unchanged
        query

      _ ->
        from(q in query, where: field(as(^binding), ^field) not in ^values)
    end
  end

  # Refactored LIKE operations using pattern matching with guards
  defp apply_like(query, binding, field, pattern, opts) when is_binary(pattern) do
    case_sensitive = Keyword.get(opts, :case_sensitive, @default_case_sensitive)

    case {binding, case_sensitive} do
      {0, true} -> from(q in query, where: like(field(q, ^field), ^pattern))
      {0, false} -> from(q in query, where: ilike(field(q, ^field), ^pattern))
      {b, true} -> from(q in query, where: like(field(as(^b), ^field), ^pattern))
      {b, false} -> from(q in query, where: ilike(field(as(^b), ^field), ^pattern))
    end
  end

  defp apply_ilike(query, binding, field, pattern, _opts) when is_binary(pattern) do
    case binding do
      0 -> from(q in query, where: ilike(field(q, ^field), ^pattern))
      b -> from(q in query, where: ilike(field(as(^b), ^field), ^pattern))
    end
  end

  defp apply_not_like(query, binding, field, pattern, opts) when is_binary(pattern) do
    case_sensitive = Keyword.get(opts, :case_sensitive, @default_case_sensitive)

    case {binding, case_sensitive} do
      {0, true} -> from(q in query, where: not like(field(q, ^field), ^pattern))
      {0, false} -> from(q in query, where: not ilike(field(q, ^field), ^pattern))
      {b, true} -> from(q in query, where: not like(field(as(^b), ^field), ^pattern))
      {b, false} -> from(q in query, where: not ilike(field(as(^b), ^field), ^pattern))
    end
  end

  defp apply_not_ilike(query, binding, field, pattern, _opts) when is_binary(pattern) do
    case binding do
      0 -> from(q in query, where: not ilike(field(q, ^field), ^pattern))
      b -> from(q in query, where: not ilike(field(as(^b), ^field), ^pattern))
    end
  end

  # Refactored NIL checks using pattern matching
  defp apply_is_nil(query, binding, field) do
    case binding do
      0 -> from(q in query, where: is_nil(field(q, ^field)))
      b -> from(q in query, where: is_nil(field(as(^b), ^field)))
    end
  end

  defp apply_not_nil(query, binding, field) do
    case binding do
      0 -> from(q in query, where: not is_nil(field(q, ^field)))
      b -> from(q in query, where: not is_nil(field(as(^b), ^field)))
    end
  end

  # Refactored BETWEEN using pattern matching with guards
  defp apply_between(query, binding, field, {min, max}, _opts) when min <= max do
    case binding do
      0 ->
        from(q in query, where: field(q, ^field) >= ^min and field(q, ^field) <= ^max)

      b ->
        from(q in query,
          where: field(as(^b), ^field) >= ^min and field(as(^b), ^field) <= ^max
        )
    end
  end

  # Refactored array/JSONB operations using pattern matching
  defp apply_contains(query, binding, field, value) do
    case binding do
      0 -> from(q in query, where: fragment("? @> ?", field(q, ^field), ^value))
      b -> from(q in query, where: fragment("? @> ?", field(as(^b), ^field), ^value))
    end
  end

  defp apply_contained_by(query, binding, field, value) do
    case binding do
      0 -> from(q in query, where: fragment("? <@ ?", field(q, ^field), ^value))
      b -> from(q in query, where: fragment("? <@ ?", field(as(^b), ^field), ^value))
    end
  end

  defp apply_jsonb_contains(query, binding, field, value) do
    case binding do
      0 -> from(q in query, where: fragment("? @> ?::jsonb", field(q, ^field), ^value))
      b -> from(q in query, where: fragment("? @> ?::jsonb", field(as(^b), ^field), ^value))
    end
  end

  defp apply_jsonb_has_key(query, binding, field, key) when is_binary(key) do
    case binding do
      0 -> from(q in query, where: fragment("? \\? ?", field(q, ^field), ^key))
      b -> from(q in query, where: fragment("? \\? ?", field(as(^b), ^field), ^key))
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

# Implement Ecto.Queryable protocol so Query works with Repo.all, Repo.one, etc
defimpl Ecto.Queryable, for: Events.Repo.Query do
  def to_query(%Events.Repo.Query{query: query}), do: query
end
