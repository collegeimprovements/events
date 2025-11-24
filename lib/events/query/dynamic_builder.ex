defmodule Events.Query.DynamicBuilder do
  @moduledoc """
  Dynamic query builder with parameter support and consistent 4-arity tuples.

  ## Consistent Tuple Format

  ALL operations use 4-element tuples for maximum consistency:

  - **Filter**: `{:filter, field, operation, value, options}`
  - **Order**: `{:order, field, direction, options}`
  - **Preload**: `{:preload, association, query_spec, options}`
  - **Join**: `{:join, association, type, options}`
  - **Paginate**: `{:paginate, type, config, options}`

  ## Dynamic Building

  Build queries from data structures with variable interpolation:

      # Query specification with parameters
      spec = %{
        filters: [
          {:filter, :status, :eq, {:param, :status}, []},
          {:filter, :age, :gte, {:param, :min_age}, []}
        ],
        orders: [
          {:order, :created_at, :desc, []},
          {:order, :id, :asc, []}
        ],
        pagination: {:paginate, :offset, %{limit: 20, offset: 0}, []}
      }

      # Bind parameters
      params = %{status: "active", min_age: 18}

      # Build query
      query = DynamicBuilder.build(User, spec, params)

  ## Nested Specifications

  Support for nested preloads with their own filters/pagination:

      spec = %{
        filters: [{:filter, :status, :eq, "active", []}],
        preloads: [
          {:preload, :posts, %{
            filters: [{:filter, :published, :eq, true, []}],
            orders: [{:order, :created_at, :desc, []}],
            pagination: {:paginate, :offset, %{limit: 10}, []},
            preloads: [
              {:preload, :comments, %{
                filters: [{:filter, :approved, :eq, true, []}],
                orders: [{:order, :created_at, :desc, []}],
                pagination: {:paginate, :offset, %{limit: 5}, []}
              }, []}
            ]
          }, []}
        ]
      }
  """

  alias Events.Query
  alias Events.Query.Token

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

  ## Parameters

  - `schema` - Schema module or existing query
  - `spec` - Query specification map
  - `params` - Map of parameter values (optional)

  ## Examples

      # Simple query
      spec = %{
        filters: [
          {:filter, :status, :eq, "active", []},
          {:filter, :age, :gte, 18, []}
        ],
        orders: [
          {:order, :created_at, :desc, []}
        ],
        pagination: {:paginate, :offset, %{limit: 20}, []}
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

      # With nested preloads
      spec = %{
        preloads: [
          {:preload, :posts, %{
            filters: [{:filter, :published, :eq, true, []}],
            pagination: {:paginate, :offset, %{limit: 10}, []}
          }, []}
        ]
      }

      DynamicBuilder.build(User, spec)
  """
  @spec build(module() | Ecto.Query.t(), query_spec(), map()) :: Token.t()
  def build(schema, spec, params \\ %{}) do
    token = Query.new(schema)

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
    |> apply_pagination(spec[:pagination], params)
  end

  @doc """
  Convert a query specification to normalized 4-tuple format.

  Takes various input formats and normalizes them to consistent 4-tuples.

  ## Examples

      # 3-tuple filter → 4-tuple
      normalize_spec([{:status, :eq, "active"}], :filter)
      # => [{:filter, :status, :eq, "active", []}]

      # 2-tuple order → 4-tuple
      normalize_spec([{:created_at, :desc}], :order)
      # => [{:order, :created_at, :desc, []}]
  """
  @spec normalize_spec(list(), :filter | :order | :preload | :join) :: list()
  def normalize_spec(specs, type) when is_list(specs) do
    Enum.map(specs, fn spec -> normalize_one(spec, type) end)
  end

  # Normalize individual specs to 4-tuple format
  defp normalize_one({field, op, value}, :filter) do
    {:filter, field, op, value, []}
  end

  defp normalize_one({field, op, value, opts}, :filter) do
    {:filter, field, op, value, opts}
  end

  defp normalize_one({:filter, field, op, value, opts}, :filter) do
    {:filter, field, op, value, opts}
  end

  defp normalize_one({field, direction}, :order) do
    {:order, field, direction, []}
  end

  defp normalize_one({field, direction, opts}, :order) do
    {:order, field, direction, opts}
  end

  defp normalize_one({:order, field, direction, opts}, :order) do
    {:order, field, direction, opts}
  end

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
    Enum.reduce(filters, token, fn filter_spec, acc ->
      {:filter, field, op, value, opts} = normalize_one(filter_spec, :filter)
      resolved_value = resolve_param(value, params)
      Query.filter(acc, field, op, resolved_value, opts)
    end)
  end

  defp apply_orders(token, nil, _params), do: token

  defp apply_orders(token, orders, _params) when is_list(orders) do
    Enum.reduce(orders, token, fn order_spec, acc ->
      {:order, field, direction, opts} = normalize_one(order_spec, :order)
      Query.order(acc, field, direction, opts)
    end)
  end

  defp apply_joins(token, nil, _params), do: token

  defp apply_joins(token, joins, _params) when is_list(joins) do
    Enum.reduce(joins, token, fn join_spec, acc ->
      {:join, assoc, type, opts} = normalize_one(join_spec, :join)
      Query.join(acc, assoc, type, opts)
    end)
  end

  defp apply_preloads(token, nil, _params), do: token

  defp apply_preloads(token, preloads, params) when is_list(preloads) do
    Enum.reduce(preloads, token, fn preload_spec, acc ->
      {:preload, assoc, nested_spec, _opts} = normalize_one(preload_spec, :preload)

      case nested_spec do
        nil ->
          Query.preload(acc, assoc)

        spec when is_map(spec) ->
          Query.preload(acc, assoc, fn nested_token ->
            build_from_token(nested_token, spec, params)
          end)
      end
    end)
  end

  defp apply_select(token, nil), do: token
  defp apply_select(token, fields), do: Query.select(token, fields)

  defp apply_group_by(token, nil), do: token
  defp apply_group_by(token, fields), do: Query.group_by(token, fields)

  defp apply_having(token, nil), do: token
  defp apply_having(token, conditions), do: Query.having(token, conditions)

  defp apply_distinct(token, nil), do: token
  defp apply_distinct(token, value), do: Query.distinct(token, value)

  defp apply_limit(token, nil), do: token
  defp apply_limit(token, value), do: Query.limit(token, value)

  defp apply_offset(token, nil), do: token
  defp apply_offset(token, value), do: Query.offset(token, value)

  defp apply_pagination(token, nil, _params), do: token

  defp apply_pagination(token, {:paginate, type, config, _opts}, params) do
    resolved_config =
      config
      |> Enum.map(fn {k, v} -> {k, resolve_param(v, params)} end)
      |> Enum.into(%{})

    Query.paginate(token, type, Enum.to_list(resolved_config))
  end

  # Build from existing token (for nested preloads)
  defp build_from_token(token, spec, params) do
    token
    |> apply_filters(spec[:filters], params)
    |> apply_orders(spec[:orders], params)
    |> apply_joins(spec[:joins], params)
    |> apply_preloads(spec[:preloads], params)
    |> apply_select(spec[:select])
    |> apply_limit(spec[:limit])
    |> apply_offset(spec[:offset])
    |> apply_pagination(spec[:pagination], params)
  end

  # Resolve parameter references
  defp resolve_param({:param, key}, params) when is_map(params) do
    Map.get(params, key)
  end

  defp resolve_param(value, _params), do: value

  @doc """
  Build a dynamic search query from parameters.

  Handles common search patterns with minimal configuration.

  ## Examples

      # Basic search
      params = %{
        search: "john",
        status: "active",
        sort_by: "created_at",
        sort_dir: "desc",
        page: 1,
        per_page: 20
      }

      config = %{
        search_fields: [:name, :email],
        filterable_fields: [:status, :role, :verified],
        sortable_fields: [:name, :created_at, :updated_at],
        default_sort: {:created_at, :desc}
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
    filters = []

    # Add search filter
    filters =
      if params[:search] && config[:search_fields] do
        search_filters =
          Enum.map(config[:search_fields], fn field ->
            {:filter, field, :ilike, "%#{params[:search]}%", []}
          end)

        # OR logic would need special handling - for now just use first field
        filters ++ [List.first(search_filters)]
      else
        filters
      end

    # Add filterable fields
    filters =
      if config[:filterable_fields] do
        Enum.reduce(config[:filterable_fields], filters, fn field, acc ->
          case Map.get(params, field) do
            nil -> acc
            value -> acc ++ [{:filter, field, :eq, value, []}]
          end
        end)
      else
        filters
      end

    filters
  end

  defp build_search_orders(params, config) do
    cond do
      params[:sort_by] && config[:sortable_fields] ->
        field = String.to_existing_atom(params[:sort_by])
        direction = if params[:sort_dir] == "asc", do: :asc, else: :desc

        if field in config[:sortable_fields] do
          [{:order, field, direction, []}]
        else
          default_order(config)
        end

      true ->
        default_order(config)
    end
  end

  defp default_order(%{default_sort: {field, dir}}), do: [{:order, field, dir, []}]
  defp default_order(_), do: [{:order, :id, :asc, []}]

  defp build_search_pagination(params, config) do
    per_page = params[:per_page] || config[:default_per_page] || 20
    page = params[:page] || 1
    offset = (page - 1) * per_page

    {:paginate, :offset, %{limit: per_page, offset: offset}, []}
  end
end
