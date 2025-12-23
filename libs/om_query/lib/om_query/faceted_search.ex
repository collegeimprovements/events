defmodule OmQuery.FacetedSearch do
  @moduledoc """
  Faceted search pattern for e-commerce and catalog applications.

  Provides an elegant pattern for building search UIs with:
  - Sidebar filters (categories, brands, price ranges, etc.)
  - Search box across multiple fields
  - Main content grid with pagination
  - Dynamic facet counts that update with filters/search

  ## The Problem

  E-commerce UIs need to:
  1. Show products matching filters + search
  2. Show counts for each facet value (e.g., "Electronics (42)")
  3. Update counts dynamically as filters are applied
  4. Handle pagination efficiently

  ## The Solution

  This module provides:
  1. `build_base/3` - Creates a base query with filters + search
  2. `with_facets/3` - Adds facet count queries
  3. `execute/2` - Runs all queries efficiently
  4. `FacetedResult` - Structured result with data + facets

  ## Example

      # Define your faceted search
      alias OmQuery.FacetedSearch

      params = %{
        search: "iphone",
        category_ids: [1, 2],
        min_price: 100,
        max_price: 1000,
        brand_ids: [5, 6, 7],
        in_stock: true
      }

      result =
        FacetedSearch.new(Product)
        |> FacetedSearch.search(params[:search], [:name, :description, :sku])
        |> FacetedSearch.filter_by(%{
          category_id: {:in, params[:category_ids]},
          price: {:between, {params[:min_price], params[:max_price]}},
          brand_id: {:in, params[:brand_ids]},
          in_stock: params[:in_stock]
        })
        |> FacetedSearch.paginate(:cursor, limit: 24)
        |> FacetedSearch.order(:relevance, :desc)
        |> FacetedSearch.facet(:categories, :category_id, join: :category, count_field: :name)
        |> FacetedSearch.facet(:brands, :brand_id, join: :brand, count_field: :name)
        |> FacetedSearch.facet(:price_ranges, :price, ranges: [
          {0, 50, "Under $50"},
          {50, 100, "$50 - $100"},
          {100, 500, "$100 - $500"},
          {500, nil, "Over $500"}
        ])
        |> FacetedSearch.execute()

      # Result structure
      %FacetedSearch.Result{
        data: [%Product{}, ...],
        pagination: %{...},
        facets: %{
          categories: [%{id: 1, name: "Electronics", count: 42}, ...],
          brands: [%{id: 5, name: "Apple", count: 15}, ...],
          price_ranges: [%{label: "Under $50", count: 10}, ...]
        },
        total_count: 150,
        metadata: %{query_time_μs: 1234}
      }
  """

  import Ecto.Query

  alias OmQuery
  alias OmQuery.Token

  defstruct [
    :source,
    :base_token,
    :search_config,
    :filters,
    :facets,
    :pagination,
    :ordering,
    :preloads,
    :select_fields
  ]

  @type facet_config :: %{
          field: atom(),
          join: atom() | nil,
          count_field: atom() | nil,
          label_field: atom() | nil,
          ranges: list() | nil,
          exclude_from_self: boolean()
        }

  @type t :: %__MODULE__{
          source: module(),
          base_token: Token.t() | nil,
          search_config: {String.t(), [atom()], keyword()} | nil,
          filters: map(),
          facets: [{atom(), facet_config()}],
          pagination: {atom(), keyword()} | nil,
          ordering: [{atom(), atom()}],
          preloads: list(),
          select_fields: map() | list() | nil
        }

  @doc """
  Create a new faceted search builder.

  ## Examples

      FacetedSearch.new(Product)
      FacetedSearch.new(from(p in Product, where: p.active == true))
  """
  @spec new(module() | Ecto.Query.t()) :: t()
  def new(source) do
    %__MODULE__{
      source: source,
      base_token: nil,
      search_config: nil,
      filters: %{},
      facets: [],
      pagination: nil,
      ordering: [],
      preloads: [],
      select_fields: nil
    }
  end

  @doc """
  Add text search across multiple fields.

  Uses `ILIKE` with OR logic across all specified fields.

  ## Options

  - `:match` - `:contains` (default), `:starts_with`, `:ends_with`, `:exact`
  - `:case_sensitive` - `false` (default)

  ## Examples

      FacetedSearch.new(Product)
      |> FacetedSearch.search("iphone", [:name, :description, :sku])

      # Prefix match
      |> FacetedSearch.search("Apple", [:brand_name], match: :starts_with)
  """
  @spec search(t(), String.t() | nil, [atom()], keyword()) :: t()
  def search(builder, term, fields, opts \\ [])
  def search(%__MODULE__{} = builder, nil, _fields, _opts), do: builder
  def search(%__MODULE__{} = builder, "", _fields, _opts), do: builder

  def search(%__MODULE__{} = builder, term, fields, opts) do
    %{builder | search_config: {term, fields, opts}}
  end

  @doc """
  Add filters using the enhanced filter_by syntax.

  Supports all filter operators with the tuple syntax.

  ## Examples

      FacetedSearch.new(Product)
      |> FacetedSearch.filter_by(%{
        status: "active",                      # :eq
        category_id: {:in, [1, 2, 3]},         # IN
        price: {:between, {10, 100}},          # BETWEEN
        rating: {:gte, 4},                     # >=
        deleted_at: {:is_nil, true}            # IS NULL
      })
  """
  @spec filter_by(t(), map()) :: t()
  def filter_by(%__MODULE__{filters: existing} = builder, new_filters) do
    %{builder | filters: Map.merge(existing, new_filters)}
  end

  @doc """
  Add a single filter.

  ## Examples

      FacetedSearch.filter(builder, :status, :eq, "active")
      FacetedSearch.filter(builder, :price, :gte, 100)
  """
  @spec filter(t(), atom(), atom(), term()) :: t()
  def filter(%__MODULE__{filters: filters} = builder, field, op, value) do
    %{builder | filters: Map.put(filters, field, {op, value})}
  end

  @doc """
  Define a facet for counting grouped values.

  Facets automatically respect all other filters and search, updating
  counts dynamically as the user filters.

  ## Options

  - `:join` - Association to join for labels (e.g., `:category`)
  - `:count_field` - Field to use for count grouping (default: the field itself)
  - `:label_field` - Field from joined table for display label (default: `:name`)
  - `:exclude_from_self` - Don't apply this facet's filter to its own counts (default: true)
    This allows showing "all categories with counts" even when filtering by category.
  - `:ranges` - For numeric facets, define ranges as `{min, max, label}` tuples

  ## Examples

      # Category facet with join for names
      FacetedSearch.facet(builder, :categories, :category_id,
        join: :category,
        label_field: :name
      )

      # Brand facet
      FacetedSearch.facet(builder, :brands, :brand_id,
        join: :brand,
        label_field: :name,
        exclude_from_self: true
      )

      # Price range facet
      FacetedSearch.facet(builder, :price_ranges, :price,
        ranges: [
          {0, 50, "Under $50"},
          {50, 100, "$50 - $100"},
          {100, 500, "$100 - $500"},
          {500, nil, "Over $500"}
        ]
      )

      # Rating facet (simple grouping)
      FacetedSearch.facet(builder, :ratings, :rating)
  """
  @spec facet(t(), atom(), atom(), keyword()) :: t()
  def facet(%__MODULE__{facets: facets, source: source} = builder, name, field, opts \\ []) do
    # Validate field exists in schema (if source is a schema module)
    validate_facet_field(source, field, opts[:join])

    config = %{
      field: field,
      join: opts[:join],
      count_field: opts[:count_field] || field,
      label_field: opts[:label_field] || :name,
      ranges: opts[:ranges],
      exclude_from_self: Keyword.get(opts, :exclude_from_self, true)
    }

    %{builder | facets: facets ++ [{name, config}]}
  end

  # Validate facet field exists in schema (warns if not found)
  defp validate_facet_field(source, field, join) when is_atom(source) and is_nil(join) do
    do_validate_facet_field(function_exported?(source, :__schema__, 1), source, field)
  end

  defp validate_facet_field(_source, _field, _join), do: :ok

  defp do_validate_facet_field(false, _source, _field), do: :ok

  defp do_validate_facet_field(true, source, field) do
    fields = source.__schema__(:fields)
    warn_if_field_missing(field in fields, field, source, fields)
  end

  defp warn_if_field_missing(true, _field, _source, _fields), do: :ok

  defp warn_if_field_missing(false, field, source, fields) do
    require Logger

    Logger.warning("""
    Facet field #{inspect(field)} not found in #{inspect(source)}.
    Available fields: #{inspect(fields)}

    If this is a field from a joined table, specify the :join option:
      facet(builder, :name, :category_name, join: :category)
    """)
  end

  @doc """
  Set pagination for the main results.

  ## Examples

      FacetedSearch.paginate(builder, :cursor, limit: 24)
      FacetedSearch.paginate(builder, :offset, limit: 20, offset: 40)
  """
  @spec paginate(t(), atom(), keyword()) :: t()
  def paginate(%__MODULE__{} = builder, type, opts) do
    %{builder | pagination: {type, opts}}
  end

  @doc """
  Add ordering to the results.

  ## Examples

      FacetedSearch.order(builder, :created_at, :desc)
      FacetedSearch.order(builder, :price, :asc)
  """
  @spec order(t(), atom(), atom()) :: t()
  def order(%__MODULE__{ordering: ordering} = builder, field, direction) do
    %{builder | ordering: ordering ++ [{field, direction}]}
  end

  @doc """
  Add preloads to the main results.

  ## Examples

      FacetedSearch.preload(builder, [:category, :brand, :images])
  """
  @spec preload(t(), atom() | list()) :: t()
  def preload(%__MODULE__{preloads: preloads} = builder, associations) when is_list(associations) do
    %{builder | preloads: preloads ++ associations}
  end

  def preload(%__MODULE__{preloads: preloads} = builder, association) when is_atom(association) do
    %{builder | preloads: preloads ++ [association]}
  end

  @doc """
  Select specific fields from results.

  ## Examples

      FacetedSearch.select(builder, [:id, :name, :price, :thumbnail_url])

      # With joins
      FacetedSearch.select(builder, %{
        id: :id,
        name: :name,
        category_name: {:category, :name}
      })
  """
  @spec select(t(), list() | map()) :: t()
  def select(%__MODULE__{} = builder, fields) do
    %{builder | select_fields: fields}
  end

  @doc """
  Debug a FacetedSearch builder - prints debug info and returns input unchanged.

  Works like `IO.inspect/2` - can be placed anywhere in a pipeline.
  Delegates to `OmQuery.Debug.debug/3`.

  ## Formats

  - `:raw_sql` - Raw SQL (default)
  - `:faceted` - FacetedSearch state
  - `:dsl` / `:pipeline` / `:token` / `:ecto` - See `OmQuery.Debug`

  ## Examples

      FacetedSearch.new(Product)
      |> FacetedSearch.search("iphone", [:name, :description])
      |> FacetedSearch.filter(:category_id, :eq, 5)
      |> FacetedSearch.debug()  # prints SQL, returns builder
      |> FacetedSearch.execute()

      # With format
      builder |> FacetedSearch.debug(:faceted)  # shows FacetedSearch state
      builder |> FacetedSearch.debug(:raw_sql)  # shows generated SQL
  """
  @spec debug(t(), atom() | [atom()], keyword()) :: t()
  def debug(%__MODULE__{} = builder, format \\ :raw_sql, opts \\ []) do
    OmQuery.Debug.debug(builder, format, opts)
  end

  @doc """
  Execute the faceted search and return structured results.

  Runs the main query and all facet count queries efficiently.

  ## Options

  - `:repo` - The Ecto repo to use (default: from config)
  - `:include_total_count` - Include total count in pagination (default: true)
  - `:parallel_facets` - Run facet queries in parallel (default: true)

  ## Returns

      %{
        data: [%Product{}, ...],
        pagination: %{type: :cursor, limit: 24, ...},
        facets: %{
          categories: [%{id: 1, name: "Electronics", count: 42}, ...],
          brands: [%{id: 5, name: "Apple", count: 15}, ...]
        },
        total_count: 150,
        metadata: %{query_time_μs: 1234}
      }
  """
  @spec execute(t(), keyword()) :: map()
  def execute(%__MODULE__{} = builder, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    # Build the base token with filters and search
    base_token = build_base_token(builder)

    # Build and execute main query
    main_result = execute_main_query(base_token, builder, opts)

    # Build and execute facet queries
    facets = execute_facet_queries(builder, opts)

    end_time = System.monotonic_time(:microsecond)

    %{
      data: main_result.data,
      pagination: main_result.pagination,
      facets: facets,
      total_count: main_result.pagination[:total_count],
      metadata: %{
        query_time_μs: end_time - start_time,
        cached: false
      }
    }
  end

  # Build the base token with all filters and search applied
  defp build_base_token(%__MODULE__{source: source, filters: filters, search_config: search_config}) do
    token = OmQuery.new(source)

    # Apply search if configured
    token =
      case search_config do
        {term, fields, opts} -> OmQuery.search(token, term, fields, opts)
        nil -> token
      end

    # Apply all filters
    OmQuery.filter_by(token, filters)
  end

  # Execute the main product query with pagination, ordering, preloads, select
  defp execute_main_query(base_token, builder, opts) do
    token =
      base_token
      |> apply_ordering(builder.ordering)
      |> apply_pagination(builder.pagination)
      |> apply_preloads(builder.preloads)
      |> apply_select(builder.select_fields)

    OmQuery.execute!(token, Keyword.put_new(opts, :include_total_count, true))
  end

  defp apply_ordering(token, []), do: token

  defp apply_ordering(token, ordering) do
    Enum.reduce(ordering, token, fn {field, dir}, acc ->
      OmQuery.order(acc, field, dir)
    end)
  end

  defp apply_pagination(token, nil), do: OmQuery.paginate(token, :cursor, limit: 20)

  defp apply_pagination(token, {type, opts}) do
    OmQuery.paginate(token, type, opts)
  end

  defp apply_preloads(token, []), do: token
  defp apply_preloads(token, preloads), do: OmQuery.preload(token, preloads)

  defp apply_select(token, nil), do: token
  defp apply_select(token, fields), do: OmQuery.select(token, fields)

  # Execute all facet count queries - parallel version
  defp execute_facet_queries(%__MODULE__{facets: facets} = builder, opts) do
    opts
    |> Keyword.get(:parallel_facets, true)
    |> do_execute_facets(facets, builder, opts)
  end

  defp do_execute_facets(true, facets, builder, opts) do
    facets
    |> Task.async_stream(&execute_facet_tuple(&1, builder, opts))
    |> Map.new(fn {:ok, result} -> result end)
  end

  defp do_execute_facets(false, facets, builder, opts) do
    Map.new(facets, &execute_facet_tuple(&1, builder, opts))
  end

  defp execute_facet_tuple({name, config}, builder, opts) do
    {name, execute_single_facet(builder, config, opts)}
  end

  # Execute a single facet - pattern match on ranges presence
  defp execute_single_facet(builder, %{ranges: ranges} = config, opts) when not is_nil(ranges) do
    execute_range_facet(builder, config, opts)
  end

  defp execute_single_facet(builder, config, opts) do
    execute_group_facet(builder, config, opts)
  end

  # Execute a facet with predefined ranges (e.g., price ranges)
  defp execute_range_facet(builder, config, opts) do
    base_token = build_facet_base_token(builder, config)
    repo = opts[:repo] || get_repo()

    # For each range, count matching items
    Enum.map(config.ranges, fn {min, max, label} ->
      token =
        base_token
        |> maybe_apply_min(config.field, min)
        |> maybe_apply_max(config.field, max)

      # Build and execute count query using dynamic
      query =
        token
        |> OmQuery.Builder.build()
        |> exclude(:select)
        |> exclude(:order_by)

      count_query = from(q in query, select: count(q.id))
      count = repo.one(count_query) || 0

      %{
        min: min,
        max: max,
        label: label,
        count: count
      }
    end)
  end

  defp maybe_apply_min(token, _field, nil), do: token
  defp maybe_apply_min(token, field, min), do: OmQuery.filter(token, field, :gte, min)

  defp maybe_apply_max(token, _field, nil), do: token
  defp maybe_apply_max(token, field, max), do: OmQuery.filter(token, field, :lt, max)

  # Execute a facet with group by (e.g., categories, brands)
  defp execute_group_facet(builder, config, opts) do
    repo = opts[:repo] || get_repo()

    builder
    |> build_facet_base_token(config)
    |> OmQuery.Builder.build()
    |> exclude(:select)
    |> exclude(:order_by)
    |> build_group_query(config)
    |> repo.all()
  end

  # Build group query with join for related table labels
  defp build_group_query(base_query, %{
         join: join,
         label_field: label_field,
         count_field: count_field
       })
       when not is_nil(join) do
    from(q in base_query,
      left_join: j in assoc(q, ^join),
      group_by: [field(q, ^count_field), field(j, ^label_field)],
      select: %{id: field(q, ^count_field), label: field(j, ^label_field), count: count(q.id)},
      order_by: [desc: count(q.id)]
    )
  end

  # Build simple group query without join
  defp build_group_query(base_query, %{count_field: count_field}) do
    from(q in base_query,
      group_by: field(q, ^count_field),
      select: %{id: field(q, ^count_field), count: count(q.id)},
      order_by: [desc: count(q.id)]
    )
  end

  # Build base token for facet, optionally excluding the facet's own filter
  defp build_facet_base_token(builder, config) do
    builder.source
    |> OmQuery.new()
    |> maybe_apply_search(builder.search_config)
    |> OmQuery.filter_by(get_facet_filters(builder.filters, config))
  end

  defp get_facet_filters(filters, %{exclude_from_self: true, field: field}),
    do: Map.delete(filters, field)

  defp get_facet_filters(filters, _config), do: filters

  defp maybe_apply_search(token, nil), do: token
  defp maybe_apply_search(token, {term, fields, opts}), do: OmQuery.search(token, term, fields, opts)

  defp get_repo do
    Application.get_env(:om_query, :default_repo) ||
      raise "No Ecto repo configured. Pass :repo option or configure: config :om_query, default_repo: MyApp.Repo"
  end
end
