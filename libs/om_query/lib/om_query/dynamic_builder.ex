defmodule OmQuery.DynamicBuilder do
  @moduledoc false
  # Advanced utility module - not part of primary public API.
  #
  # Dynamic query builder with parameter support and consistent 4-arity tuples.
  # Use this when building queries programmatically from data structures.
  #
  # Tuple Format:
  # - Filter: {:filter, field, operation, value, options}
  # - Order: {:order, field, direction, options}
  # - Preload: {:preload, association, query_spec, options}
  # - Join: {:join, association, type, options}
  # - Paginate: {:paginate, type, config, options}

  alias OmQuery
  alias OmQuery.Token
  alias OmQuery.PaginationValidator

  @type filter_spec :: {:filter, atom(), atom(), term() | {:param, atom()}, keyword()}
  @type order_spec :: {:order, atom(), :asc | :desc, keyword()}
  @type preload_spec ::
          {:preload, atom(), query_spec() | nil, keyword()}
  @type join_spec :: {:join, atom() | module(), atom(), keyword()}
  @type paginate_spec :: {:paginate, :offset | :cursor, map(), keyword()}

  @type query_spec :: %{
          optional(:filters) => [filter_spec()],
          optional(:orders) => [order_spec()],
          optional(:preloads) => [preload_spec()],
          optional(:joins) => [join_spec()],
          optional(:pagination) => paginate_spec(),
          optional(:select) => list() | map(),
          optional(:group_by) => atom() | list(),
          optional(:having) => keyword(),
          optional(:distinct) => boolean() | list(),
          optional(:limit) => pos_integer(),
          optional(:offset) => non_neg_integer()
        }

  @doc """
  Build a query token from a specification map with parameter binding.

  **Default Pagination:** If no pagination is specified, cursor-based pagination
  with a limit of 20 is applied automatically.

  ## Parameters

  - `schema` - Schema module or existing query
  - `spec` - Query specification map
  - `params` - Map of parameter values (optional)

  ## Examples

      # Simple query (gets default cursor pagination with limit: 20)
      spec = %{
        filters: [
          {:filter, :status, :eq, "active", []},
          {:filter, :age, :gte, 18, []}
        ],
        orders: [
          {:order, :created_at, :desc, []}
        ]
      }

      DynamicBuilder.build(User, spec)

      # Override with offset pagination
      spec = %{
        filters: [{:status, :eq, "active"}],
        pagination: {:paginate, :offset, %{limit: 50, offset: 0}, []}
      }

      DynamicBuilder.build(User, spec)

      # With parameters
      spec = %{
        filters: [
          {:filter, :status, :eq, {:param, :status}, []},
          {:filter, :age, :gte, {:param, :min_age}, []}
        ]
      }

      DynamicBuilder.build(User, spec, %{status: "active", min_age: 18})

      # With nested preloads (each level gets default cursor pagination)
      spec = %{
        preloads: [
          {:preload, :posts, %{
            filters: [{:filter, :published, :eq, true, []}]
          }, []}
        ]
      }

      DynamicBuilder.build(User, spec)
  """
  @spec build(module() | Ecto.Query.t(), query_spec(), map()) :: Token.t()
  def build(schema, spec, params \\ %{}) do
    token = OmQuery.new(schema)

    # Apply default cursor pagination if none specified
    # Infer cursor_fields from orders for correct pagination
    pagination = spec[:pagination] || default_pagination(spec[:orders] || [])

    token
    |> apply_filters(spec[:filters], params)
    |> apply_orders(spec[:orders], params)
    |> apply_joins(spec[:joins], params)
    |> apply_preloads(spec[:preloads], params)
    |> apply_select(spec[:select])
    |> apply_group_by(spec[:group_by])
    |> apply_having(spec[:having])
    |> apply_distinct(spec[:distinct])
    |> apply_limit(spec[:limit])
    |> apply_offset(spec[:offset])
    |> apply_pagination(pagination, params)
  end

  @doc """
  Convert a query specification to normalized 4-tuple format.

  Takes various input formats and normalizes them to consistent 4-tuples.

  ## Supported Filter Formats

      # All these are equivalent:
      {:filter, :status, :eq, "active", []}
      {:status, :eq, "active", []}
      {:status, :eq, "active"}
      [filter: {:status, :eq, "active", []}]
      [filter: {:status, :eq, "active"}]

  ## Supported Order Formats

      # All these are equivalent:
      {:order, :created_at, :desc, []}
      {:created_at, :desc, []}
      {:created_at, :desc}
      [order: {:created_at, :desc, []}]
      [order: {:created_at, :desc}]
      [order_by: {:created_at, :desc}]
      :created_at  # defaults to :asc

  ## Examples

      # 3-tuple filter → 4-tuple
      normalize_spec([{:status, :eq, "active"}], :filter)
      # => [{:filter, :status, :eq, "active", []}]

      # 2-tuple order → 4-tuple
      normalize_spec([{:created_at, :desc}], :order)
      # => [{:order, :created_at, :desc, []}]

      # Keyword list filter → 4-tuple
      normalize_spec([[filter: {:status, :eq, "active"}]], :filter)
      # => [{:filter, :status, :eq, "active", []}]
  """
  @spec normalize_spec(list(), :filter | :order | :preload | :join) :: list()
  def normalize_spec(specs, type) when is_list(specs) do
    Enum.flat_map(specs, fn spec -> normalize_one_or_many(spec, type) end)
  end

  # Handle keyword lists with multiple entries
  defp normalize_one_or_many([], _type), do: []

  defp normalize_one_or_many([{key, _value} | _rest] = spec, type) when is_atom(key) do
    # This is a keyword list
    Enum.flat_map(spec, fn {k, v} -> normalize_keyword_entry(k, v, type) end)
  end

  defp normalize_one_or_many(spec, type) when is_list(spec) do
    # This is a list of tuples - normalize each
    Enum.map(spec, fn item -> normalize_one(item, type) end)
  end

  defp normalize_one_or_many(spec, type), do: [normalize_one(spec, type)]

  # Normalize keyword list entries
  defp normalize_keyword_entry(:filter, value, :filter), do: [normalize_one(value, :filter)]
  defp normalize_keyword_entry(:order, value, :order), do: [normalize_one(value, :order)]
  defp normalize_keyword_entry(:order_by, value, :order), do: [normalize_one(value, :order)]
  defp normalize_keyword_entry(:preload, value, :preload), do: [normalize_one(value, :preload)]
  defp normalize_keyword_entry(:join, value, :join), do: [normalize_one(value, :join)]
  defp normalize_keyword_entry(_, _, _), do: []

  # Normalize individual specs to 4-tuple format

  ## FILTER NORMALIZATION ##

  # 5-tuple with :filter tag (already normalized)
  defp normalize_one({:filter, field, op, value, opts}, :filter) do
    {:filter, field, op, value, opts}
  end

  # 4-tuple without tag
  defp normalize_one({field, op, value, opts}, :filter) when is_atom(field) and is_atom(op) do
    {:filter, field, op, value, opts}
  end

  # 3-tuple without tag
  defp normalize_one({field, op, value}, :filter) when is_atom(field) and is_atom(op) do
    {:filter, field, op, value, []}
  end

  ## ORDER NORMALIZATION ##

  # 4-tuple with :order tag (already normalized)
  defp normalize_one({:order, field, direction, opts}, :order) do
    {:order, field, direction, opts}
  end

  # 3-tuple without tag
  defp normalize_one({field, direction, opts}, :order) when is_atom(field) and is_atom(direction) do
    {:order, field, direction, opts}
  end

  # 2-tuple without tag
  defp normalize_one({field, direction}, :order) when is_atom(field) and is_atom(direction) do
    {:order, field, direction, []}
  end

  # Single atom (defaults to :asc)
  defp normalize_one(field, :order) when is_atom(field) do
    {:order, field, :asc, []}
  end

  defp normalize_one({assoc, nested_spec}, :preload) when is_map(nested_spec) do
    {:preload, assoc, nested_spec, []}
  end

  defp normalize_one({assoc, nested_spec, opts}, :preload) when is_map(nested_spec) do
    {:preload, assoc, nested_spec, opts}
  end

  defp normalize_one({:preload, assoc, nested_spec, opts}, :preload) do
    {:preload, assoc, nested_spec, opts}
  end

  defp normalize_one(assoc, :preload) when is_atom(assoc) do
    {:preload, assoc, nil, []}
  end

  defp normalize_one({assoc, type}, :join) do
    {:join, assoc, type, []}
  end

  defp normalize_one({assoc, type, opts}, :join) do
    {:join, assoc, type, opts}
  end

  defp normalize_one({:join, assoc, type, opts}, :join) do
    {:join, assoc, type, opts}
  end

  # Apply operations
  defp apply_filters(token, nil, _params), do: token

  defp apply_filters(token, filters, params) when is_list(filters) do
    # Normalize all filters first to handle flexible formats
    normalized = normalize_spec(filters, :filter)

    Enum.reduce(normalized, token, fn {:filter, field, op, value, opts}, acc ->
      resolved_value = resolve_param(value, params)
      OmQuery.filter(acc, field, op, resolved_value, opts)
    end)
  end

  defp apply_orders(token, nil, _params), do: token

  defp apply_orders(token, orders, _params) when is_list(orders) do
    # Normalize all orders first to handle flexible formats
    normalized = normalize_spec(orders, :order)

    Enum.reduce(normalized, token, fn {:order, field, direction, opts}, acc ->
      OmQuery.order(acc, field, direction, opts)
    end)
  end

  defp apply_joins(token, nil, _params), do: token

  defp apply_joins(token, joins, _params) when is_list(joins) do
    # Normalize all joins first to handle flexible formats
    normalized = normalize_spec(joins, :join)

    Enum.reduce(normalized, token, fn {:join, assoc, type, opts}, acc ->
      OmQuery.join(acc, assoc, type, opts)
    end)
  end

  defp apply_preloads(token, nil, _params), do: token

  defp apply_preloads(token, preloads, params) when is_list(preloads) do
    # Normalize all preloads first to handle flexible formats
    normalized = normalize_spec(preloads, :preload)

    Enum.reduce(normalized, token, fn {:preload, assoc, nested_spec, _opts}, acc ->
      case nested_spec do
        nil ->
          OmQuery.preload(acc, assoc)

        spec when is_map(spec) ->
          OmQuery.preload(acc, assoc, fn nested_token ->
            build_from_token(nested_token, spec, params)
          end)
      end
    end)
  end

  defp apply_select(token, nil), do: token
  defp apply_select(token, fields), do: OmQuery.select(token, fields)

  defp apply_group_by(token, nil), do: token
  defp apply_group_by(token, fields), do: OmQuery.group_by(token, fields)

  defp apply_having(token, nil), do: token
  defp apply_having(token, conditions), do: OmQuery.having(token, conditions)

  defp apply_distinct(token, nil), do: token
  defp apply_distinct(token, value), do: OmQuery.distinct(token, value)

  defp apply_limit(token, nil), do: token
  defp apply_limit(token, value), do: OmQuery.limit(token, value)

  defp apply_offset(token, nil), do: token
  defp apply_offset(token, value), do: OmQuery.offset(token, value)

  defp apply_pagination(token, nil, _params), do: token

  defp apply_pagination(token, {:paginate, :cursor, config, _opts}, params) do
    resolved_config =
      config
      |> Enum.map(fn {k, v} -> {k, resolve_param(v, params)} end)
      |> Enum.into(%{})

    # Extract order_by from token operations for validation
    order_by_ops = extract_order_operations(token)

    # Validate cursor_fields if explicitly provided
    maybe_validate_cursor_fields(order_by_ops, resolved_config)

    OmQuery.paginate(token, :cursor, Enum.to_list(resolved_config))
  end

  defp apply_pagination(token, {:paginate, type, config, _opts}, params) do
    # Offset pagination - no validation needed
    resolved_config =
      config
      |> Enum.map(fn {k, v} -> {k, resolve_param(v, params)} end)
      |> Enum.into(%{})

    OmQuery.paginate(token, type, Enum.to_list(resolved_config))
  end

  defp maybe_validate_cursor_fields(order_by_ops, %{cursor_fields: cursor_fields}) do
    {:ok, _validated_fields} = validate_cursor_fields(order_by_ops, cursor_fields)
  end

  defp maybe_validate_cursor_fields(_order_by_ops, _config), do: :ok

  # Extract order operations from token for validation
  defp extract_order_operations(token) do
    token.operations
    |> Enum.filter(fn
      {:order, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:order, spec} -> spec end)
  end

  # Build from existing token (for nested preloads)
  defp build_from_token(token, spec, params) do
    # Apply default cursor pagination for nested specs if none specified
    # Infer cursor_fields from orders for correct pagination
    pagination = spec[:pagination] || default_pagination(spec[:orders] || [])

    token
    |> apply_filters(spec[:filters], params)
    |> apply_orders(spec[:orders], params)
    |> apply_joins(spec[:joins], params)
    |> apply_preloads(spec[:preloads], params)
    |> apply_select(spec[:select])
    |> apply_limit(spec[:limit])
    |> apply_offset(spec[:offset])
    |> apply_pagination(pagination, params)
  end

  # Resolve parameter references
  defp resolve_param({:param, key}, params) when is_map(params) do
    Map.get(params, key)
  end

  defp resolve_param(value, _params), do: value

  @doc """
  Build a dynamic search query from parameters.

  Handles common search patterns with minimal configuration.

  **Default Pagination:** Uses cursor-based pagination with limit of 20.
  To use offset pagination, pass `page` parameter or set `pagination_type: :offset` in config.

  ## Examples

      # Basic search with cursor pagination (default)
      params = %{
        search: "john",
        status: "active",
        sort_by: "created_at",
        sort_dir: "desc",
        limit: 20,
        after_cursor: "encoded_cursor"
      }

      config = %{
        search_fields: [:name, :email],
        filterable_fields: [:status, :role, :verified],
        sortable_fields: [:name, :created_at, :updated_at],
        default_sort: {:created_at, :desc},
        cursor_fields: [:created_at, :id]
      }

      DynamicBuilder.search(User, params, config)

      # Force offset pagination with page parameter
      params = %{
        search: "john",
        page: 1,
        per_page: 20
      }

      DynamicBuilder.search(User, params, config)
  """
  def search(schema, params, config \\ %{}) do
    spec = %{
      filters: build_search_filters(params, config),
      orders: build_search_orders(params, config),
      pagination: build_search_pagination(params, config)
    }

    build(schema, spec, params)
  end

  defp build_search_filters(params, config) do
    []
    |> add_search_filter(params[:search], config[:search_fields])
    |> add_filterable_fields(params, config[:filterable_fields])
  end

  defp add_search_filter(filters, nil, _search_fields), do: filters
  defp add_search_filter(filters, _search, nil), do: filters

  defp add_search_filter(filters, search, search_fields) do
    search_filter =
      search_fields
      |> List.first()
      |> build_ilike_filter(search)

    filters ++ [search_filter]
  end

  defp build_ilike_filter(field, search), do: {:filter, field, :ilike, "%#{search}%", []}

  defp add_filterable_fields(filters, _params, nil), do: filters

  defp add_filterable_fields(filters, params, filterable_fields) do
    Enum.reduce(filterable_fields, filters, fn field, acc ->
      case Map.get(params, field) do
        nil -> acc
        value -> acc ++ [{:filter, field, :eq, value, []}]
      end
    end)
  end

  defp build_search_orders(params, config) do
    do_build_search_orders(params[:sort_by], config[:sortable_fields], params, config)
  end

  defp do_build_search_orders(nil, _sortable_fields, _params, config), do: default_order(config)
  defp do_build_search_orders(_sort_by, nil, _params, config), do: default_order(config)

  defp do_build_search_orders(sort_by, sortable_fields, params, config) do
    field = String.to_existing_atom(sort_by)
    direction = parse_sort_direction(params[:sort_dir])

    build_sort_order(field in sortable_fields, field, direction, config)
  end

  defp parse_sort_direction("asc"), do: :asc
  defp parse_sort_direction(_), do: :desc

  defp build_sort_order(true, field, direction, _config), do: [{:order, field, direction, []}]
  defp build_sort_order(false, _field, _direction, config), do: default_order(config)

  defp default_order(%{default_sort: {field, dir}}), do: [{:order, field, dir, []}]
  defp default_order(_), do: [{:order, :id, :asc, []}]

  # Pattern match for offset pagination (explicit page param or config)
  defp build_search_pagination(%{page: page} = params, config) when not is_nil(page) do
    build_offset_pagination(params, config)
  end

  defp build_search_pagination(params, %{pagination_type: :offset} = config) do
    build_offset_pagination(params, config)
  end

  # Default to cursor pagination
  defp build_search_pagination(params, config) do
    limit = params[:limit] || params[:per_page] || config[:default_per_page] || 20
    cursor_fields = config[:cursor_fields] || [:id]

    %{limit: limit, cursor_fields: cursor_fields}
    |> maybe_add_cursor(:after, params[:after_cursor])
    |> maybe_add_cursor(:before, params[:before_cursor])
    |> then(&{:paginate, :cursor, &1, []})
  end

  defp build_offset_pagination(params, config) do
    per_page = params[:per_page] || config[:default_per_page] || 20
    page = params[:page] || 1
    offset = (page - 1) * per_page
    {:paginate, :offset, %{limit: per_page, offset: offset}, []}
  end

  defp maybe_add_cursor(config, _key, nil), do: config
  defp maybe_add_cursor(config, key, value), do: Map.put(config, key, value)

  @doc """
  Returns the default pagination specification.

  By default, uses cursor-based pagination with a limit of 20.
  Cursor fields are inferred from order_by and include directions.

  ## Examples

      default_pagination()
      # => {:paginate, :cursor, %{limit: 20, cursor_fields: [{:id, :asc}]}, []}

      default_pagination([{:created_at, :desc}, {:id, :asc}])
      # => {:paginate, :cursor, %{limit: 20, cursor_fields: [{:created_at, :desc}, {:id, :asc}]}, []}

      default_pagination([{:priority, :desc}])
      # => {:paginate, :cursor, %{limit: 20, cursor_fields: [{:priority, :desc}, {:id, :asc}]}, []}
  """
  def default_pagination(orders \\ []) do
    cursor_fields = PaginationValidator.infer(orders)
    {:paginate, :cursor, %{limit: 20, cursor_fields: cursor_fields}, []}
  end

  @doc """
  Infers cursor fields from order specifications.

  **DEPRECATED:** Use `OmQuery.PaginationValidator.infer/1` instead.
  This function is kept for backward compatibility but now delegates to the validator.

  Extracts field names AND directions from order tuples and ensures {:id, :asc} is included.

  ## Examples

      infer_cursor_fields([{:created_at, :desc}, {:id, :asc}])
      # => [{:created_at, :desc}, {:id, :asc}]

      infer_cursor_fields([{:priority, :desc}])
      # => [{:priority, :desc}, {:id, :asc}]

      infer_cursor_fields([])
      # => [{:id, :asc}]
  """
  def infer_cursor_fields(orders) do
    PaginationValidator.infer(orders)
  end

  @doc """
  Validates cursor_fields against order_by specification.

  If cursor_fields are provided, validates they match order_by exactly.
  If cursor_fields mismatch, logs error and raises exception.
  If cursor_fields are nil, infers them from order_by.

  ## Examples

      validate_cursor_fields([{:title, :asc}], nil)
      # => {:ok, [{:title, :asc}, {:id, :asc}]}

      validate_cursor_fields([{:title, :asc}], [{:title, :asc}, {:id, :asc}])
      # => {:ok, [{:title, :asc}, {:id, :asc}]}

      validate_cursor_fields([{:title, :asc}], [{:title, :desc}])
      # => Raises error with detailed message
  """
  def validate_cursor_fields(order_by, cursor_fields) do
    case PaginationValidator.validate_or_infer(order_by, cursor_fields) do
      {:ok, validated_fields} ->
        {:ok, validated_fields}

      {:error, reason} ->
        raise ArgumentError, """
        Invalid cursor pagination configuration:

        #{reason}

        order_by:      #{inspect(order_by)}
        cursor_fields: #{inspect(cursor_fields)}

        To fix this issue:
        1. Remove cursor_fields to use automatic inference, OR
        2. Ensure cursor_fields exactly match order_by fields and directions

        Examples:
          # Auto-inference (recommended)
          %{orders: [{:created_at, :desc}, {:id, :asc}]}

          # Explicit (must match exactly)
          %{
            orders: [{:created_at, :desc}, {:id, :asc}],
            pagination: {:paginate, :cursor, %{
              cursor_fields: [{:created_at, :desc}, {:id, :asc}]
            }, []}
          }
        """
    end
  end
end
