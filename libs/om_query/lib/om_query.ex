defmodule OmQuery do
  @moduledoc """
  Production-grade query builder with token pattern and pipelines.

  This is the **single entry point** for all query operations. All other modules
  in `OmQuery.*` are internal implementation details.

  ## Public API Summary

  ### Query Construction
  - `new/1` - Create a query token from a schema
  - `filter/5` - Add a filter condition (also aliased as `where/5`)
  - `filter_by/2` - Add multiple filters from a map/keyword list
  - `order/4` - Add ordering (also aliased as `order_by/4`)
  - `orders/2` - Add multiple orderings
  - `join/4` - Add a join
  - `joins/2` - Add multiple joins
  - `select/2` - Select specific fields
  - `preload/2,3` - Preload associations
  - `paginate/3` - Add pagination (cursor or offset)
  - `limit/2`, `offset/2` - Manual limit/offset
  - `distinct/2` - Add distinct clause
  - `group_by/2`, `having/2` - Grouping and having
  - `lock/2` - Add row locking

  ### Filter Helpers
  - `where_any/2` - OR filter group
  - `where_all/2` - AND filter group
  - `search/4` - Full-text search across fields
  - `exclude_deleted/2` - Filter out soft-deleted records
  - `only_deleted/2` - Return only soft-deleted records
  - `created_between/4` - Filter by date range
  - `updated_since/3` - Filter by update time
  - `filter_subquery/4` - Filter using subquery

  ### Execution
  - `execute/2` - Execute and return `{:ok, result}` or `{:error, error}`
  - `execute!/2` - Execute and return result or raise
  - `stream/2` - Return a stream for large datasets
  - `batch/2` - Execute multiple queries in parallel
  - `transaction/2` - Execute in a transaction

  ### Shortcuts
  - `first/2`, `first!/2` - Get first record
  - `one/2`, `one!/2` - Get exactly one record
  - `all/2` - Get all records
  - `count/2` - Count records
  - `exists?/2` - Check existence
  - `aggregate/4` - Run aggregate function

  ### Advanced
  - `build/1`, `build!/1` - Build raw Ecto.Query without executing
  - `debug/3` - Debug query (prints and returns unchanged)
  - `with_cte/4` - Add Common Table Expression
  - `from_subquery/1` - Build from a subquery
  - `raw_where/3` - Add raw SQL where clause
  - `window/3` - Add window function
  - `include/2` - Include a query fragment
  - `then_if/3` - Conditional pipeline helper

  ### Cursor Utilities
  - `encode_cursor/2` - Create cursor for testing
  - `decode_cursor/1` - Decode cursor for debugging

  ## Optional Submodules

  These modules provide additional features and can be explicitly imported:

  - `OmQuery.DSL` - Macro-based DSL (`import OmQuery.DSL`)
  - `OmQuery.Fragment` - Reusable query fragments (`use OmQuery.Fragment`)
  - `OmQuery.Helpers` - Date/time utilities (`import OmQuery.Helpers`)
  - `OmQuery.Multi` - Ecto.Multi integration (`alias OmQuery.Multi`)
  - `OmQuery.FacetedSearch` - E-commerce faceted search
  - `OmQuery.TestHelpers` - Test utilities (`use OmQuery.TestHelpers`)

  ## Error Types

  - `OmQuery.ValidationError` - Invalid operation or value
  - `OmQuery.LimitExceededError` - Limit exceeds max_limit config
  - `OmQuery.PaginationError` - Invalid pagination configuration
  - `OmQuery.CursorError` - Invalid or expired cursor

  ---

  ## Naming Conventions

  This module provides semantic aliases for some functions. **Preferred names are:**

  | Preferred      | Alias (works but not preferred) |
  |----------------|--------------------------------|
  | `filter/5`     | `where/5`                      |
  | `filter_by/2`  | `wheres/2`, `filters/2`        |
  | `order/4`      | `order_by/4`                   |
  | `orders/2`     | `order_bys/2`                  |

  The aliases exist for developers familiar with Ecto's naming, but we recommend
  using the preferred names for consistency.

  ## Binding Convention

  When working with joins, use `as:` to **name** a binding, and `binding:` to **reference** it:

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.join(:posts, :left, as: :posts)           # as: names the binding
  |> OmQuery.filter(:published, :eq, true, binding: :posts)  # binding: references it
  |> OmQuery.order(:created_at, :desc, binding: :posts)
  |> OmQuery.search("elixir", [{:title, :ilike, binding: :posts}])
  ```

  This matches Ecto's conventions where `as:` creates named bindings.

  ## Basic Usage

  ```elixir
  # Macro DSL
  import OmQuery

  query User do
    filter :status, :eq, "active"
    filter :age, :gte, 18
    order :created_at, :desc
    paginate :offset, limit: 20
  end
  |> execute()

  # Pipeline API
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.paginate(:offset, limit: 20)
  |> OmQuery.execute()
  ```

  ## Result Format

  All queries return `%OmQuery.Result{}`:

  ```elixir
  %OmQuery.Result{
    data: [...],
    pagination: %{
      type: :offset,
      limit: 20,
      offset: 0,
      has_more: true,
      total_count: 150  # if requested
    },
    metadata: %{
      query_time_μs: 1234,
      total_time_μs: 1500,
      cached: false
    }
  }
  ```

  ## Performance Tips

  1. **Use cursor pagination** for large datasets (offset becomes slow at high offsets)

  2. **Index filter fields properly:**
     ```sql
     -- Basic B-tree index for equality/range filters
     CREATE INDEX idx_users_status ON users(status);

     -- Partial index for common filters
     CREATE INDEX idx_products_active ON products(category_id) WHERE deleted_at IS NULL;

     -- GIN index for array/JSONB containment
     CREATE INDEX idx_products_tags ON products USING gin(tags);

     -- Trigram index for similarity search (requires pg_trgm)
     CREATE EXTENSION IF NOT EXISTS pg_trgm;
     CREATE INDEX idx_products_name_trgm ON products USING gin(name gin_trgm_ops);
     ```

  3. **Use `:binding`** option for filters on joined tables (avoids subqueries)

  4. **Limit preloads** - each preload is a separate query. Use `OmQuery.join` + `OmQuery.select`
     for denormalized results in a single query.

  ## Limitations

  - **Window functions:** Dynamic window functions aren't fully supported. Use `fragment/1`:
    ```elixir
    OmQuery.select(token, %{
      rank: fragment("ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY price)")
    })
    ```
  - Subquery operators only work in filters, not in select
  - `:explain_analyze` in debug executes the query (use with care in production)
  """

  alias OmQuery.{Token, Builder, Executor, Result, Queryable, Cast, Predicates, Search}

  # Configurable defaults - can be overridden via application config
  # config :om_query, default_repo: MyApp.Repo
  @default_repo Application.compile_env(:om_query, :default_repo, nil)

  # Re-export key types
  @type t :: Token.t()
  @type queryable :: Token.t() | module() | Ecto.Query.t() | String.t()

  ## Public API

  @doc """
  Create a new query token from a schema, Ecto query, or table name.

  ## Examples

      # From schema module
      OmQuery.new(User)

      # From existing Ecto query
      OmQuery.new(from u in User, where: u.admin == true)

      # From table name string (schemaless)
      OmQuery.new("users")
  """
  @spec new(module() | Ecto.Query.t() | String.t()) :: Token.t()
  defdelegate new(schema_or_query), to: Token

  # Internal helper to ensure we have a token from any queryable source
  @doc false
  defp ensure_token(%Token{} = token), do: token
  defp ensure_token(source), do: Queryable.to_token(source)

  @doc """
  Debug a query token - prints debug info and returns input unchanged.

  Works like `IO.inspect/2` - can be placed anywhere in a pipeline.
  Returns the input unchanged for seamless composition.

  ## Formats

  - `:raw_sql` - Raw SQL with interpolated params (default)
  - `:sql_params` - SQL + params separately
  - `:ecto` - Ecto.Query struct
  - `:dsl` - DSL macro syntax
  - `:pipeline` - Pipeline syntax
  - `:token` - Token struct
  - `:explain` - PostgreSQL EXPLAIN
  - `:explain_analyze` - PostgreSQL EXPLAIN ANALYZE (executes query!)
  - `:all` - All formats combined

  ## Options

  - `:label` - Custom label (default: "Query Debug")
  - `:pretty` - Pretty print (default: true)
  - `:repo` - Repo module for SQL generation
  - `:color` - ANSI color (default: :cyan)
  - `:stacktrace` - Show caller location (default: false)
  - `:return` - Return value: `:input` (default), `:output`, `:both`

  ## Examples

      # Default - prints raw SQL
      Product
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.debug()
      |> OmQuery.execute()

      # Specific format
      token |> OmQuery.debug(:pipeline)
      token |> OmQuery.debug(:dsl)
      token |> OmQuery.debug([:raw_sql, :ecto])

      # With options
      token |> OmQuery.debug(:raw_sql, label: "Product Search", color: :green)

      # Debug at multiple points
      Product
      |> OmQuery.new()
      |> OmQuery.debug(:token, label: "Initial")
      |> OmQuery.filter(:price, :gt, 100)
      |> OmQuery.debug(:raw_sql, label: "After filter")
      |> OmQuery.join(:category, :left)
      |> OmQuery.debug(:raw_sql, label: "After join")
      |> OmQuery.execute()
  """
  @spec debug(Token.t() | Ecto.Query.t(), atom() | [atom()], keyword()) ::
          Token.t() | Ecto.Query.t()
  defdelegate debug(input, format \\ :raw_sql, opts \\ []), to: OmQuery.Debug

  @doc """
  Add a where condition (Ecto-style naming).

  Alias: `filter/5` - Semantic alternative name for the same operation.

  ## Parameters

  - `token` - The query token
  - `field` - Field name to filter on
  - `op` - Filter operator (`:eq`, `:neq`, `:gt`, `:gte`, `:lt`, `:lte`, `:in`, `:not_in`, `:like`, `:ilike`, `:is_nil`, `:not_nil`, `:between`, `:contains`, `:jsonb_contains`, `:jsonb_has_key`)
  - `value` - Value to filter against
  - `opts` - Options (optional)
    - `:binding` - Named binding for joined tables (default: `:root`)
    - `:case_insensitive` - Case insensitive comparison for strings (default: `false`)

  ## Examples

      # Simple where clause
      OmQuery.where(token, :status, :eq, "active")

      # With options
      OmQuery.where(token, :email, :eq, "john@example.com", case_insensitive: true)

      # On joined table
      OmQuery.where(token, :published, :eq, true, binding: :posts)

      # Multiple separate calls (chaining)
      token
      |> OmQuery.where(:status, :eq, "active")
      |> OmQuery.where(:age, :gte, 18)
      |> OmQuery.where(:verified, :eq, true)
  """
  @spec where(queryable(), atom(), atom(), term(), keyword()) :: Token.t()
  def where(source, field, op, value, opts \\ []) do
    {cast_type, filter_opts} = Keyword.pop(opts, :cast)
    casted_value = Cast.cast(value, cast_type)

    source
    |> ensure_token()
    |> Token.add_operation({:filter, {field, op, casted_value, filter_opts}})
  end

  @doc """
  Alias for `where/5`. Semantic alternative name.

  See `where/5` for documentation.

  ## Shorthand Syntax

  When operator is `:eq`, you can omit it:

      # These are equivalent:
      OmQuery.filter(token, :status, :eq, "active")
      OmQuery.filter(token, :status, "active")

  For keyword-based equality filters:

      # These are equivalent:
      token
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.filter(:verified, :eq, true)

      OmQuery.filter(token, status: "active", verified: true)

  ## Piping from Schema

  You can pipe directly from a schema without `OmQuery.new()`:

      # These are equivalent:
      User |> OmQuery.new() |> OmQuery.filter(:status, :eq, "active")
      User |> OmQuery.filter(:status, :eq, "active")
  """
  @spec filter(queryable(), atom(), atom(), term(), keyword()) :: Token.t()
  def filter(source, field, op, value, opts \\ []) do
    where(source, field, op, value, opts)
  end

  @doc """
  Shorthand filter for equality (`:eq` operator).

  This is a convenience function when the operator is `:eq`.

  ## Examples

      # These are equivalent:
      OmQuery.filter(token, :status, :eq, "active")
      OmQuery.filter(token, :status, "active")

      # Pipe from schema directly:
      User |> OmQuery.filter(:status, "active")
  """
  @spec filter(queryable(), atom(), term()) :: Token.t()
  def filter(source, field, value) when is_atom(field) do
    where(source, field, :eq, value, [])
  end

  @doc """
  Filter with keyword list for multiple equality conditions.

  A convenient shorthand for multiple equality filters.

  ## Examples

      # These are equivalent:
      token
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.filter(:verified, :eq, true)
      |> OmQuery.filter(:role, :eq, "admin")

      OmQuery.filter(token, status: "active", verified: true, role: "admin")

      # Pipe from schema:
      User |> OmQuery.filter(status: "active", verified: true)
  """
  @spec filter(queryable(), keyword()) :: Token.t()
  def filter(source, filters) when is_list(filters) and length(filters) > 0 do
    token = ensure_token(source)

    Enum.reduce(filters, token, fn {field, value}, acc ->
      Token.add_operation(acc, {:filter, {field, :eq, value, []}})
    end)
  end

  @doc """
  Filter on a joined table using its binding name.

  This is a shorthand for `filter/5` with the `binding:` option.

  ## Parameters

  - `source` - The query token or queryable source
  - `binding` - The binding name (from `as:` in join)
  - `field` - Field name on the joined table
  - `value` - Value for equality filter (defaults to `:eq` operator)

  ## Examples

      # Long form:
      token
      |> OmQuery.join(:category, :left, as: :cat)
      |> OmQuery.filter(:active, :eq, true, binding: :cat)

      # Short form with on/4:
      token
      |> OmQuery.join(:category, :left, as: :cat)
      |> OmQuery.on(:cat, :active, true)

      # With operator:
      token
      |> OmQuery.join(:category, :left, as: :cat)
      |> OmQuery.on(:cat, :price, :gte, 100)

  ## Pipeline Example

      Product
      |> OmQuery.join(:category, :left, as: :cat)
      |> OmQuery.join(:brand, :left, as: :brand)
      |> OmQuery.filter(:active, true)           # Filter on root table
      |> OmQuery.on(:cat, :name, "Electronics")  # Filter on category
      |> OmQuery.on(:brand, :country, "US")      # Filter on brand
      |> OmQuery.execute()
  """
  @spec on(queryable(), atom(), atom(), term()) :: Token.t()
  def on(source, binding, field, value) when is_atom(binding) and is_atom(field) do
    source
    |> ensure_token()
    |> Token.add_operation({:filter, {field, :eq, value, [binding: binding]}})
  end

  @doc """
  Filter on a joined table with explicit operator.

  ## Examples

      token
      |> OmQuery.join(:products, :left, as: :prod)
      |> OmQuery.on(:prod, :price, :gte, 100)
      |> OmQuery.on(:prod, :status, :in, ["active", "pending"])
  """
  @spec on(queryable(), atom(), atom(), atom(), term()) :: Token.t()
  def on(source, binding, field, op, value)
      when is_atom(binding) and is_atom(field) and is_atom(op) do
    source
    |> ensure_token()
    |> Token.add_operation({:filter, {field, op, value, [binding: binding]}})
  end

  # ============================================================================
  # Conditional Filters (maybe)
  # ============================================================================

  @doc """
  Conditionally apply a filter only if the value is truthy.

  This is extremely useful when building queries from optional parameters.
  If value is `nil`, `false`, or empty string, the filter is skipped entirely.

  ## Parameters

  - `source` - The query token or queryable source
  - `field` - Field name to filter on
  - `value` - Value to filter by (filter skipped if nil/false/"")

  ## Examples

      # Instead of:
      token = User |> OmQuery.new()
      token = if params["status"], do: OmQuery.filter(token, :status, params["status"]), else: token
      token = if params["role"], do: OmQuery.filter(token, :role, params["role"]), else: token

      # Just write:
      User
      |> OmQuery.maybe(:status, params["status"])
      |> OmQuery.maybe(:role, params["role"])
      |> OmQuery.maybe(:min_age, params["min_age"], :gte, cast: :integer)
      |> OmQuery.execute()

  ## With Operators

      User
      |> OmQuery.maybe(:age, params["min_age"], :gte)
      |> OmQuery.maybe(:created_at, params["since"], :gte)
      |> OmQuery.maybe(:role, params["roles"], :in)

  ## Custom Predicates

  Use the `:when` option to customize when the filter is applied:

      # Only apply if not nil (allows false, "", [])
      OmQuery.maybe(User, :active, params[:active], :eq, when: :not_nil)

      # Only apply if not blank (nil, "", whitespace)
      OmQuery.maybe(User, :name, params[:name], :ilike, when: :not_blank)

      # Custom predicate function
      OmQuery.maybe(User, :score, params[:min], :gte, when: &(&1 && &1 > 0))
      OmQuery.maybe(User, :tags, params[:tags], :in, when: &(is_list(&1) and &1 != []))

  Built-in predicates:
  - `:present` - (default) not nil, false, "", [], %{}
  - `:not_nil` - only checks for nil
  - `:not_blank` - not nil, "", or whitespace-only string
  - `:not_empty` - not nil, [], or %{}
  """
  @spec maybe(queryable(), atom(), term()) :: Token.t()
  def maybe(source, field, value) do
    maybe(source, field, value, :eq, [])
  end

  @spec maybe(queryable(), atom(), term(), atom()) :: Token.t()
  def maybe(source, field, value, op) when is_atom(op) and op not in [:when] do
    maybe(source, field, value, op, [])
  end

  @spec maybe(queryable(), atom(), term(), keyword()) :: Token.t()
  def maybe(source, field, value, opts) when is_list(opts) do
    maybe(source, field, value, :eq, opts)
  end

  @spec maybe(queryable(), atom(), term(), atom(), keyword()) :: Token.t()
  def maybe(source, field, value, op, opts) when is_atom(op) do
    token = ensure_token(source)
    {predicate, filter_opts} = Keyword.pop(opts, :when, :present)

    if Predicates.check(predicate, value) do
      where(token, field, op, value, filter_opts)
    else
      token
    end
  end

  @doc """
  Conditionally apply a filter on a joined table.

  Like `maybe/4` but for joined tables using their binding name.
  Supports the same `:when` option for custom predicates.

  ## Examples

      Product
      |> OmQuery.left_join(Category, as: :cat, on: [id: :category_id])
      |> OmQuery.maybe_on(:cat, :name, params["category"])
      |> OmQuery.maybe_on(:cat, :priority, params["min_priority"], :gte)
      |> OmQuery.maybe_on(:cat, :active, params["active"], :eq, when: :not_nil)
  """
  @spec maybe_on(queryable(), atom(), atom(), term()) :: Token.t()
  def maybe_on(source, binding, field, value) do
    maybe_on(source, binding, field, value, :eq, [])
  end

  @spec maybe_on(queryable(), atom(), atom(), term(), atom()) :: Token.t()
  def maybe_on(source, binding, field, value, op) when is_atom(op) do
    maybe_on(source, binding, field, value, op, [])
  end

  @spec maybe_on(queryable(), atom(), atom(), term(), atom(), keyword()) :: Token.t()
  def maybe_on(source, binding, field, value, op, opts) when is_atom(binding) and is_atom(op) do
    token = ensure_token(source)
    {predicate, filter_opts} = Keyword.pop(opts, :when, :present)

    if Predicates.check(predicate, value) do
      full_opts = Keyword.put(filter_opts, :binding, binding)
      where(token, field, op, value, full_opts)
    else
      token
    end
  end

  # ============================================================================
  # Raw SQL Escape Hatch
  # ============================================================================

  @doc """
  Add a raw SQL fragment to the WHERE clause.

  Use this when you need SQL features not directly supported by the Query DSL.
  Parameters are safely interpolated using Ecto's fragment.

  ## Parameters

  - `source` - The query token or queryable source
  - `sql` - SQL fragment string with `?` placeholders
  - `params` - List of parameters to interpolate (default: [])
  - `opts` - Options (default: [])
    - `:binding` - Apply to a joined table

  ## Examples

      # Simple raw condition
      User
      |> OmQuery.raw("age + 5 > ?", [30])
      |> OmQuery.execute()

      # JSONB operations
      User
      |> OmQuery.raw("settings->>'theme' = ?", ["dark"])
      |> OmQuery.raw("metadata @> ?", [JSON.encode!(%{role: "admin"})])

      # PostgreSQL specific features
      Product
      |> OmQuery.raw("tsv @@ plainto_tsquery('english', ?)", [search_term])

      # Array operations
      User
      |> OmQuery.raw("? = ANY(roles)", ["admin"])

      # On joined table
      Product
      |> OmQuery.left_join(Category, as: :cat, on: [id: :category_id])
      |> OmQuery.raw("?.data->>'featured' = 'true'", [], binding: :cat)

  ## Safety Note

  Parameters are always safely interpolated - never concatenate user input
  directly into the SQL string.
  """
  @spec raw(queryable(), String.t(), list() | map(), keyword()) :: Token.t()
  def raw(source, sql, params \\ [], opts \\ [])
      when is_binary(sql) and (is_list(params) or is_map(params)) do
    source
    |> ensure_token()
    |> Token.add_operation({:raw_where, {sql, params, opts}})
  end

  # ============================================================================
  # Debug Helpers
  # ============================================================================

  @doc """
  Return the SQL string and parameters for a query.

  Useful for debugging or logging queries.

  ## Examples

      {sql, params} = User
        |> OmQuery.filter(:status, "active")
        |> OmQuery.to_sql()

      # sql => "SELECT ... FROM users WHERE status = $1"
      # params => ["active"]
  """
  @spec to_sql(Token.t(), keyword()) :: {String.t(), list()}
  def to_sql(%Token{} = token, opts \\ []) do
    repo = get_repo(opts)
    query = Builder.build(token)
    Ecto.Adapters.SQL.to_sql(:all, repo, query)
  end

  @doc """
  Add multiple where conditions at once (Ecto-style naming).

  Alias: `filters/2` - Semantic alternative name for the same operation.

  ## Parameters

  - `token` - The query token
  - `where_list` - List of where specifications. Each can be:
    - `{field, op, value}` - Simple 3-tuple
    - `{field, op, value, opts}` - 4-tuple with options

  ## Examples

      # List of 3-tuples
      OmQuery.wheres(token, [
        {:status, :eq, "active"},
        {:age, :gte, 18},
        {:verified, :eq, true}
      ])

      # List of 4-tuples with options
      OmQuery.wheres(token, [
        {:status, :eq, "active", []},
        {:email, :eq, "john@example.com", [case_insensitive: true]},
        {:published, :eq, true, [binding: :posts]}
      ])

      # Mixed (3-tuples and 4-tuples)
      OmQuery.wheres(token, [
        {:status, :eq, "active"},
        {:email, :ilike, "%@gmail.com", [case_insensitive: true]}
      ])
  """
  @spec wheres(Token.t(), [
          {atom(), atom(), term()}
          | {atom(), atom(), term(), keyword()}
        ]) :: Token.t()
  def wheres(token, where_list) when is_list(where_list) do
    Enum.reduce(where_list, token, fn
      {field, op, value}, acc ->
        where(acc, field, op, value)

      {field, op, value, opts}, acc ->
        where(acc, field, op, value, opts)
    end)
  end

  @doc """
  Alias for `wheres/2`. Semantic alternative name.

  See `wheres/2` for documentation.
  """
  @spec filters(Token.t(), [
          {atom(), atom(), term()}
          | {atom(), atom(), term(), keyword()}
        ]) :: Token.t()
  def filters(token, filter_list) when is_list(filter_list) do
    wheres(token, filter_list)
  end

  @doc """
  Add an OR filter group - matches if ANY condition is true.

  ## Parameters

  - `token` - The query token
  - `filter_list` - List of filter specifications (at least 2 required)
  - `opts` - Options applied to all filters (merged with per-filter options)
    - `:binding` - Named binding for all filters
    - `:case_insensitive` - Apply case-insensitive matching

  ## Examples

      # Match users who are active OR admins OR verified
      OmQuery.where_any(token, [
        {:status, :eq, "active"},
        {:role, :eq, "admin"},
        {:verified, :eq, true}
      ])

      # With global options applied to all filters
      OmQuery.where_any(token, [
        {:email, :eq, "john@example.com"},
        {:username, :eq, "john"}
      ], case_insensitive: true)

      # With binding for joined table
      OmQuery.where_any(token, [
        {:status, :eq, "shipped"},
        {:status, :eq, "delivered"}
      ], binding: :order)

  ## SQL Equivalent

      WHERE (status = 'active' OR role = 'admin' OR verified = true)
  """
  @spec where_any(
          Token.t(),
          [{atom(), atom(), term()} | {atom(), atom(), term(), keyword()}],
          keyword()
        ) :: Token.t()
  def where_any(token, filter_list, opts \\ [])

  def where_any(token, filter_list, opts) when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = normalize_filter_specs(filter_list, opts)
    Token.add_operation(token, {:filter_group, {:or, normalized}})
  end

  @doc """
  Add an AND filter group - matches only if ALL conditions are true.

  This is semantically equivalent to multiple `where/5` calls, but groups
  the conditions explicitly for clarity.

  ## Parameters

  - `token` - The query token
  - `filter_list` - List of filter specifications (at least 2 required)
  - `opts` - Options applied to all filters (merged with per-filter options)
    - `:binding` - Named binding for all filters
    - `:case_insensitive` - Apply case-insensitive matching

  ## Examples

      # Match users who are BOTH active AND verified
      OmQuery.where_all(token, [
        {:status, :eq, "active"},
        {:verified, :eq, true}
      ])

      # With binding for joined table
      OmQuery.where_all(token, [
        {:status, :eq, "paid"},
        {:shipped_at, :not_nil, true}
      ], binding: :order)

  ## SQL Equivalent

      WHERE (status = 'active' AND verified = true)
  """
  @spec where_all(
          Token.t(),
          [{atom(), atom(), term()} | {atom(), atom(), term(), keyword()}],
          keyword()
        ) :: Token.t()
  def where_all(token, filter_list, opts \\ [])

  def where_all(token, filter_list, opts) when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = normalize_filter_specs(filter_list, opts)
    Token.add_operation(token, {:filter_group, {:and, normalized}})
  end

  @doc """
  Add a NONE filter group - matches if NONE of the conditions are true.

  This is the negation of `where_any/2`. Useful for exclusion lists.

  ## Parameters

  - `token` - The query token
  - `filter_list` - List of filter specifications (at least 2 required)
  - `opts` - Options applied to all filters (merged with per-filter options)
    - `:binding` - Named binding for all filters
    - `:case_insensitive` - Apply case-insensitive matching

  ## Examples

      # Match users who are NOT active AND NOT admins (neither of these)
      OmQuery.where_none(token, [
        {:status, :eq, "active"},
        {:role, :eq, "admin"}
      ])

      # Exclude multiple statuses
      OmQuery.where_none(token, [
        {:status, :eq, "banned"},
        {:status, :eq, "deleted"},
        {:status, :eq, "suspended"}
      ])

      # With binding for joined table
      OmQuery.where_none(token, [
        {:status, :eq, "cancelled"},
        {:status, :eq, "refunded"}
      ], binding: :order)

  ## SQL Equivalent

      WHERE NOT (status = 'active' OR role = 'admin')
  """
  @spec where_none(
          Token.t(),
          [{atom(), atom(), term()} | {atom(), atom(), term(), keyword()}],
          keyword()
        ) :: Token.t()
  def where_none(token, filter_list, opts \\ [])

  def where_none(token, filter_list, opts) when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = normalize_filter_specs(filter_list, opts)
    Token.add_operation(token, {:filter_group, {:not_or, normalized}})
  end

  @doc """
  Add a negated filter condition.

  Inverts the operator to create the opposite condition.

  ## Operator Inversions

  | Original | Negated |
  |----------|---------|
  | `:eq` | `:neq` |
  | `:neq` | `:eq` |
  | `:gt` | `:lte` |
  | `:gte` | `:lt` |
  | `:lt` | `:gte` |
  | `:lte` | `:gt` |
  | `:in` | `:not_in` |
  | `:not_in` | `:in` |
  | `:is_nil` | `:not_nil` |
  | `:not_nil` | `:is_nil` |
  | `:like` | `:not_like` |
  | `:ilike` | `:not_ilike` |

  ## Examples

      # status != "active"
      OmQuery.where_not(token, :status, :eq, "active")

      # NOT (price > 100)  =>  price <= 100
      OmQuery.where_not(token, :price, :gt, 100)

      # NOT (role IN ["admin", "mod"])  =>  role NOT IN [...]
      OmQuery.where_not(token, :role, :in, ["admin", "mod"])

  ## SQL Equivalent

      -- where_not(:status, :eq, "active")
      WHERE status != 'active'

      -- where_not(:price, :gt, 100)
      WHERE price <= 100
  """
  @spec where_not(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def where_not(token, field, op, value, opts \\ []) do
    negated_op = negate_operator(op)
    where(token, field, negated_op, value, opts)
  end

  # Operator negation mapping
  defp negate_operator(:eq), do: :neq
  defp negate_operator(:neq), do: :eq
  defp negate_operator(:gt), do: :lte
  defp negate_operator(:gte), do: :lt
  defp negate_operator(:lt), do: :gte
  defp negate_operator(:lte), do: :gt
  defp negate_operator(:in), do: :not_in
  defp negate_operator(:not_in), do: :in
  defp negate_operator(:is_nil), do: :not_nil
  defp negate_operator(:not_nil), do: :is_nil
  defp negate_operator(:like), do: :not_like
  defp negate_operator(:ilike), do: :not_ilike
  defp negate_operator(:not_like), do: :like
  defp negate_operator(:not_ilike), do: :ilike

  defp negate_operator(op) do
    raise ArgumentError, "Cannot negate operator: #{inspect(op)}"
  end

  @doc """
  Compare two fields within the same row.

  Useful for queries like "find records where updated_at > created_at" or
  "find products where current_stock < min_stock".

  ## Supported Operators

  | Operator | Meaning |
  |----------|---------|
  | `:eq` | field1 = field2 |
  | `:neq` | field1 != field2 |
  | `:gt` | field1 > field2 |
  | `:gte` | field1 >= field2 |
  | `:lt` | field1 < field2 |
  | `:lte` | field1 <= field2 |

  ## Examples

      # Records that were modified after creation
      OmQuery.where_field(token, :updated_at, :gt, :created_at)

      # Products running low on stock
      OmQuery.where_field(token, :current_stock, :lt, :min_stock)

      # Orders where total matches subtotal (no discounts)
      OmQuery.where_field(token, :total, :eq, :subtotal)

      # With bindings for joined tables
      OmQuery.where_field(token, :user_id, :eq, :author_id, binding: :post)

  ## SQL Equivalent

      -- where_field(:updated_at, :gt, :created_at)
      WHERE updated_at > created_at

      -- where_field(:current_stock, :lt, :min_stock)
      WHERE current_stock < min_stock
  """
  @spec where_field(Token.t(), atom(), atom(), atom(), keyword()) :: Token.t()
  def where_field(token, field1, op, field2, opts \\ [])
      when is_atom(field1) and is_atom(op) and is_atom(field2) do
    ensure_token(token)
    |> Token.add_operation({:field_compare, {field1, op, field2, opts}})
  end

  @doc """
  Add an EXISTS subquery condition.

  Returns rows where the subquery returns at least one result.

  ## Parameters

  - `token` - The query token
  - `subquery` - A Token or Ecto.Query for the subquery

  ## Examples

      # Find posts that have at least one comment
      comments_subquery = Comment
        |> OmQuery.new()
        |> OmQuery.where(:post_id, :eq, some_post_id)

      Post
      |> OmQuery.new()
      |> OmQuery.exists(comments_subquery)

  ## SQL Equivalent

      WHERE EXISTS (SELECT 1 FROM comments WHERE post_id = ?)
  """
  @spec exists(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def exists(token, subquery) do
    Token.add_operation(token, {:exists, subquery})
  end

  @doc """
  Add a NOT EXISTS subquery condition.

  Returns rows where the subquery returns no results.

  ## Parameters

  - `token` - The query token
  - `subquery` - A Token or Ecto.Query for the subquery

  ## Examples

      # Find posts with no comments
      comments_subquery = Comment
        |> OmQuery.new()
        |> OmQuery.where(:post_id, :eq, some_post_id)

      Post
      |> OmQuery.new()
      |> OmQuery.not_exists(comments_subquery)

  ## SQL Equivalent

      WHERE NOT EXISTS (SELECT 1 FROM comments WHERE post_id = ?)
  """
  @spec not_exists(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def not_exists(token, subquery) do
    Token.add_operation(token, {:not_exists, subquery})
  end

  ## Convenience Functions
  ##
  ## These are common patterns wrapped as single functions for ease of use.

  @doc """
  Filter to exclude soft-deleted records.

  A convenience wrapper for the common pattern of filtering by `deleted_at IS NULL`.

  ## Parameters

  - `token` - The query token
  - `field` - The soft-delete timestamp field (default: `:deleted_at`)

  ## Examples

      # Exclude deleted records
      User
      |> OmQuery.new()
      |> OmQuery.exclude_deleted()
      |> OmQuery.execute()

      # With custom field name
      Post
      |> OmQuery.new()
      |> OmQuery.exclude_deleted(:removed_at)

  ## SQL Equivalent

      WHERE deleted_at IS NULL
  """
  @spec exclude_deleted(Token.t(), atom()) :: Token.t()
  def exclude_deleted(token, field \\ :deleted_at) do
    filter(token, field, :is_nil, true)
  end

  @doc """
  Filter to include only soft-deleted records.

  Opposite of `exclude_deleted/2` - returns only records that have been soft-deleted.

  ## Examples

      # Get only deleted records (for trash view)
      User
      |> OmQuery.new()
      |> OmQuery.only_deleted()

  ## SQL Equivalent

      WHERE deleted_at IS NOT NULL
  """
  @spec only_deleted(Token.t(), atom()) :: Token.t()
  def only_deleted(token, field \\ :deleted_at) do
    filter(token, field, :not_nil, true)
  end

  @doc """
  Filter by subquery (IN or NOT IN).

  A convenience wrapper for filtering where a field's value is in (or not in)
  the results of a subquery.

  ## Parameters

  - `token` - The query token
  - `field` - Field to filter on
  - `op` - `:in` or `:not_in`
  - `subquery` - Token or Ecto.Query that returns a single column

  ## Examples

      # Find users who have made a purchase
      purchaser_ids = Order
        |> OmQuery.new()
        |> OmQuery.select([:user_id])

      User
      |> OmQuery.new()
      |> OmQuery.filter_subquery(:id, :in, purchaser_ids)

      # Find products not in any order
      ordered_product_ids = OrderItem
        |> OmQuery.new()
        |> OmQuery.select([:product_id])

      Product
      |> OmQuery.new()
      |> OmQuery.filter_subquery(:id, :not_in, ordered_product_ids)

  ## SQL Equivalent

      WHERE id IN (SELECT user_id FROM orders)
      WHERE id NOT IN (SELECT product_id FROM order_items)
  """
  @spec filter_subquery(Token.t(), atom(), :in | :not_in, Token.t() | Ecto.Query.t()) :: Token.t()
  def filter_subquery(token, field, :in, subquery) do
    filter(token, field, :in_subquery, subquery)
  end

  def filter_subquery(token, field, :not_in, subquery) do
    filter(token, field, :not_in_subquery, subquery)
  end

  @doc """
  Filter for records created within a time range.

  A convenience wrapper for filtering by creation timestamp.

  ## Parameters

  - `token` - The query token
  - `start_time` - Start of the range (inclusive)
  - `end_time` - End of the range (inclusive)
  - `field` - The timestamp field (default: `:inserted_at`)

  ## Examples

      # Records created today
      today = Date.utc_today()
      start_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      end_of_day = DateTime.new!(today, ~T[23:59:59], "Etc/UTC")

      User
      |> OmQuery.new()
      |> OmQuery.created_between(start_of_day, end_of_day)

      # With custom field
      Post
      |> OmQuery.new()
      |> OmQuery.created_between(start, finish, :published_at)

  ## SQL Equivalent

      WHERE inserted_at BETWEEN ? AND ?
  """
  @spec created_between(
          Token.t(),
          DateTime.t() | NaiveDateTime.t(),
          DateTime.t() | NaiveDateTime.t(),
          atom()
        ) :: Token.t()
  def created_between(token, start_time, end_time, field \\ :inserted_at) do
    filter(token, field, :between, {start_time, end_time})
  end

  @doc """
  Filter field between two values (inclusive).

  A shorthand for `filter(token, field, :between, {min, max})`.

  ## Examples

      # Price between 10 and 100
      OmQuery.between(token, :price, 10, 100)

      # Age between 18 and 65
      OmQuery.between(token, :age, 18, 65)

      # With binding for joined table
      OmQuery.between(token, :quantity, 1, 10, binding: :items)

  ## SQL Equivalent

      WHERE price BETWEEN 10 AND 100
  """
  @spec between(Token.t(), atom(), term(), term(), keyword()) :: Token.t()
  def between(token, field, min, max, opts \\ []) do
    filter(token, field, :between, {min, max}, opts)
  end

  @doc """
  Filter field within any of multiple ranges (inclusive).

  Creates an OR condition matching any of the provided ranges.

  ## Examples

      # Score in multiple grade ranges
      OmQuery.between_any(token, :score, [{0, 10}, {50, 75}, {90, 100}])

      # Price tiers
      OmQuery.between_any(token, :price, [{10, 50}, {100, 200}], binding: :products)

  ## SQL Equivalent

      WHERE (score BETWEEN 0 AND 10 OR score BETWEEN 50 AND 75 OR score BETWEEN 90 AND 100)
  """
  @spec between_any(Token.t(), atom(), [{term(), term()}], keyword()) :: Token.t()
  def between_any(token, field, ranges, opts \\ []) when is_list(ranges) do
    filter(token, field, :between, ranges, opts)
  end

  @doc """
  Filter field to be greater than or equal to a value.

  A shorthand for `filter(token, field, :gte, value)`.

  ## Examples

      OmQuery.at_least(token, :price, 100)
      OmQuery.at_least(token, :age, 18)

  ## SQL Equivalent

      WHERE price >= 100
  """
  @spec at_least(Token.t(), atom(), term(), keyword()) :: Token.t()
  def at_least(token, field, value, opts \\ []) do
    filter(token, field, :gte, value, opts)
  end

  @doc """
  Filter field to be less than or equal to a value.

  A shorthand for `filter(token, field, :lte, value)`.

  ## Examples

      OmQuery.at_most(token, :price, 1000)
      OmQuery.at_most(token, :quantity, 50)

  ## SQL Equivalent

      WHERE price <= 1000
  """
  @spec at_most(Token.t(), atom(), term(), keyword()) :: Token.t()
  def at_most(token, field, value, opts \\ []) do
    filter(token, field, :lte, value, opts)
  end

  ## String Operations
  ##
  ## Convenient wrappers for common string matching patterns.
  ## Generated using metaprogramming for consistency.

  # String pattern function definitions: {name, pattern_type, op, negated_op, value_name, doc_example}
  @string_pattern_ops [
    {:starts_with, :prefix, :like, :not_like, "prefix",
     {"name", "John", "WHERE name LIKE 'John%'"}},
    {:ends_with, :suffix, :like, :not_like, "suffix",
     {"email", "@example.com", "WHERE email LIKE '%@example.com'"}},
    {:contains_string, :contains, :like, :not_like, "substring",
     {"description", "important", "WHERE description LIKE '%important%'"}}
  ]

  for {name, pattern_type, op, negated_op, value_name, {field_ex, value_ex, sql_ex}} <-
        @string_pattern_ops do
    negated_name = :"not_#{name}"

    @doc """
    Filter where string field #{String.replace(to_string(name), "_", " ")}s a given #{value_name}.

    ## Examples

        OmQuery.#{name}(token, :#{field_ex}, "#{value_ex}")
        OmQuery.#{name}(token, :#{field_ex}, "test", case_insensitive: true)

    ## SQL Equivalent

        #{sql_ex}
    """
    @spec unquote(name)(Token.t(), atom(), String.t(), keyword()) :: Token.t()
    def unquote(name)(token, field, value, opts \\ []) when is_binary(value) do
      pattern = string_pattern(value, unquote(pattern_type))
      string_filter(token, field, pattern, unquote(op), opts)
    end

    @doc """
    Filter where string field does NOT #{String.replace(to_string(name), "_", " ")} a given #{value_name}.

    ## Examples

        OmQuery.#{negated_name}(token, :#{field_ex}, "#{value_ex}")

    ## SQL Equivalent

        #{String.replace(sql_ex, "LIKE", "NOT LIKE")}
    """
    @spec unquote(negated_name)(Token.t(), atom(), String.t(), keyword()) :: Token.t()
    def unquote(negated_name)(token, field, value, opts \\ []) when is_binary(value) do
      pattern = string_pattern(value, unquote(pattern_type))
      string_filter(token, field, pattern, unquote(negated_op), opts)
    end
  end

  defp string_pattern(value, :prefix), do: value <> "%"
  defp string_pattern(value, :suffix), do: "%" <> value
  defp string_pattern(value, :contains), do: "%" <> value <> "%"

  defp string_filter(token, field, pattern, base_op, opts) do
    op = if opts[:case_insensitive], do: case_insensitive_op(base_op), else: base_op
    filter(token, field, op, pattern, Keyword.delete(opts, :case_insensitive))
  end

  defp case_insensitive_op(:like), do: :ilike
  defp case_insensitive_op(:not_like), do: :not_ilike

  ## Null/Blank Helpers
  ##
  ## Convenient wrappers for null and blank checking.

  @doc """
  Filter where field is NULL.

  A shorthand for `filter(token, field, :is_nil, true)`.

  ## Examples

      OmQuery.where_nil(token, :deleted_at)
      OmQuery.where_nil(token, :email, binding: :user)

  ## SQL Equivalent

      WHERE deleted_at IS NULL
  """
  @spec where_nil(Token.t(), atom(), keyword()) :: Token.t()
  def where_nil(token, field, opts \\ []) do
    filter(token, field, :is_nil, true, opts)
  end

  @doc """
  Filter where field is NOT NULL.

  A shorthand for `filter(token, field, :not_nil, true)`.

  ## Examples

      OmQuery.where_not_nil(token, :email)
      OmQuery.where_not_nil(token, :verified_at)

  ## SQL Equivalent

      WHERE email IS NOT NULL
  """
  @spec where_not_nil(Token.t(), atom(), keyword()) :: Token.t()
  def where_not_nil(token, field, opts \\ []) do
    filter(token, field, :not_nil, true, opts)
  end

  @doc """
  Filter where field IS NOT NULL.

  Alias for `where_not_nil/3` - provides naming consistency with the `:not_nil` operator.

  ## Examples

      OmQuery.is_not_nil(token, :email)
      OmQuery.is_not_nil(token, :verified_at)

  ## SQL Equivalent

      WHERE email IS NOT NULL
  """
  @spec is_not_nil(Token.t(), atom(), keyword()) :: Token.t()
  def is_not_nil(token, field, opts \\ []) do
    filter(token, field, :not_nil, true, opts)
  end

  @doc """
  Filter where field is blank (NULL or empty string).

  Useful for checking if a string field has no meaningful value.

  ## Examples

      OmQuery.where_blank(token, :middle_name)
      OmQuery.where_blank(token, :bio)

  ## SQL Equivalent

      WHERE (middle_name IS NULL OR middle_name = '')
  """
  @spec where_blank(Token.t(), atom(), keyword()) :: Token.t()
  def where_blank(token, field, opts \\ []) do
    # Use OR group: IS NULL OR equals empty string
    binding = opts[:binding]
    base_opts = if binding, do: [binding: binding], else: []

    where_any(token, [
      {field, :is_nil, true, base_opts},
      {field, :eq, "", base_opts}
    ])
  end

  @doc """
  Filter where field is present (NOT NULL and NOT empty string).

  Useful for ensuring a string field has a meaningful value.

  ## Examples

      OmQuery.where_present(token, :name)
      OmQuery.where_present(token, :email)

  ## SQL Equivalent

      WHERE name IS NOT NULL AND name != ''
  """
  @spec where_present(Token.t(), atom(), keyword()) :: Token.t()
  def where_present(token, field, opts \\ []) do
    # Use AND: NOT NULL AND not empty
    token
    |> filter(field, :not_nil, true, opts)
    |> filter(field, :neq, "", opts)
  end

  @doc """
  Filter for records updated after a given time.

  Useful for sync operations or finding recently modified records.

  ## Examples

      # Find records updated in the last hour
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

      User
      |> OmQuery.new()
      |> OmQuery.updated_since(one_hour_ago)

  ## SQL Equivalent

      WHERE updated_at > ?
  """
  @spec updated_since(Token.t(), DateTime.t() | NaiveDateTime.t(), atom()) :: Token.t()
  def updated_since(token, since, field \\ :updated_at) do
    filter(token, field, :gt, since)
  end

  @doc """
  Filter for records created today (UTC).

  ## Examples

      # Find users who signed up today
      User
      |> OmQuery.new()
      |> OmQuery.created_today()

      # Custom timestamp field
      Order
      |> OmQuery.new()
      |> OmQuery.created_today(:placed_at)
  """
  @spec created_today(Token.t(), atom()) :: Token.t()
  def created_today(token, field \\ :inserted_at) do
    today = Date.utc_today()
    start_time = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    end_time = DateTime.new!(today, ~T[23:59:59.999999], "Etc/UTC")
    created_between(token, start_time, end_time, field)
  end

  @doc """
  Filter for records updated in the last N hours.

  ## Examples

      # Find records updated in the last 2 hours
      User
      |> OmQuery.new()
      |> OmQuery.updated_recently(2)

      # Custom field
      Product
      |> OmQuery.new()
      |> OmQuery.updated_recently(24, :last_synced_at)
  """
  @spec updated_recently(Token.t(), pos_integer(), atom()) :: Token.t()
  def updated_recently(token, hours, field \\ :updated_at) when is_integer(hours) and hours > 0 do
    since = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)
    updated_since(token, since, field)
  end

  @doc """
  Filter records with a specific status or list of statuses.

  Convenience wrapper for common status filtering pattern.

  ## Examples

      # Single status
      OmQuery.with_status(token, "active")

      # Multiple statuses (IN query)
      OmQuery.with_status(token, ["pending", "processing"])

      # Custom status field
      OmQuery.with_status(token, "published", :state)
  """
  @spec with_status(Token.t(), String.t() | [String.t()], atom()) :: Token.t()
  def with_status(token, statuses, field \\ :status)

  def with_status(token, statuses, field) when is_list(statuses) do
    filter(token, field, :in, statuses)
  end

  def with_status(token, status, field) when is_binary(status) or is_atom(status) do
    filter(token, field, :eq, status)
  end

  ## Scopes
  ##
  ## Reusable query fragments that can be applied to any query.

  @doc """
  Apply a scope function to the query.

  Scopes are reusable query fragments. They can be:
  - Anonymous functions that take a token and return a token
  - Named functions from a module

  ## Examples

      # With anonymous function
      active_scope = fn q -> OmQuery.filter(q, :status, :eq, "active") end
      OmQuery.scope(token, active_scope)

      # With module function
      defmodule UserScopes do
        def active(token), do: OmQuery.filter(token, :status, :eq, "active")
        def verified(token), do: OmQuery.filter(token, :verified_at, :not_nil, true)
        def recent(token), do: OmQuery.order(token, :created_at, :desc) |> OmQuery.limit(10)
      end

      User
      |> OmQuery.scope(&UserScopes.active/1)
      |> OmQuery.scope(&UserScopes.verified/1)
      |> OmQuery.execute()

      # Or using apply_scope/3
      User
      |> OmQuery.apply_scope(UserScopes, :active)
      |> OmQuery.apply_scope(UserScopes, :verified)

  ## Use in Preloads

      # Apply scope to preloaded association
      User
      |> OmQuery.preload(:posts, fn q ->
        q
        |> OmQuery.scope(&PostScopes.published/1)
        |> OmQuery.order(:published_at, :desc)
      end)

  ## SQL Equivalent

      -- Depends on scope functions applied
  """
  @spec scope(Token.t() | queryable(), (Token.t() -> Token.t())) :: Token.t()
  def scope(source, scope_fn) when is_function(scope_fn, 1) do
    token = ensure_token(source)
    scope_fn.(token)
  end

  @doc """
  Apply a named scope from a module.

  The module must define a function with the given name that accepts
  a token and returns a token.

  ## Examples

      defmodule ProductScopes do
        def active(token), do: OmQuery.filter(token, :active, :eq, true)
        def in_stock(token), do: OmQuery.filter(token, :stock, :gt, 0)
        def on_sale(token), do: OmQuery.filter(token, :sale_price, :not_nil, true)
        def priced_under(token, max), do: OmQuery.filter(token, :price, :lt, max)
      end

      Product
      |> OmQuery.apply_scope(ProductScopes, :active)
      |> OmQuery.apply_scope(ProductScopes, :in_stock)
      |> OmQuery.apply_scope(ProductScopes, :priced_under, [100])
      |> OmQuery.execute()

  ## Use in Preloads

      User
      |> OmQuery.preload(:orders, fn q ->
        OmQuery.apply_scope(q, OrderScopes, :completed)
      end)

  ## Use in Joins (via scope function in on clause)

      User
      |> OmQuery.join(:posts, :left, as: :post)
      |> OmQuery.scope(&PostScopes.published/1)
  """
  @spec apply_scope(Token.t() | queryable(), module(), atom(), list()) :: Token.t()
  def apply_scope(source, module, scope_name, args \\ [])
      when is_atom(module) and is_atom(scope_name) and is_list(args) do
    token = ensure_token(source)
    apply(module, scope_name, [token | args])
  end

  @doc """
  Chain multiple scopes together.

  Applies a list of scope functions in order.

  ## Examples

      scopes = [
        &UserScopes.active/1,
        &UserScopes.verified/1,
        &UserScopes.recent/1
      ]

      User
      |> OmQuery.scopes(scopes)
      |> OmQuery.execute()
  """
  @spec scopes(Token.t() | queryable(), [(Token.t() -> Token.t())]) :: Token.t()
  def scopes(source, scope_fns) when is_list(scope_fns) do
    Enum.reduce(scope_fns, ensure_token(source), fn scope_fn, token ->
      scope_fn.(token)
    end)
  end

  ## Composable Filter Builders
  ##
  ## Functions for building filter conditions as data structures
  ## that can be combined before applying to a token.

  @doc """
  Build a filter condition tuple.

  Returns a filter specification that can be used with `where_any/2`,
  `where_all/2`, `where_none/2`, or `apply_filters/2`.

  ## Examples

      # Build individual conditions
      active = OmQuery.condition(:status, :eq, "active")
      verified = OmQuery.condition(:verified, :eq, true)

      # Use with where_any
      OmQuery.where_any(token, [active, verified])

      # With options
      admin = OmQuery.condition(:role, :eq, "admin", binding: :user)
  """
  @type filter_condition ::
          {atom(), atom(), term()}
          | {atom(), atom(), term(), keyword()}

  @spec condition(atom(), atom(), term(), keyword()) :: filter_condition()
  def condition(field, op, value, opts \\ []) when is_atom(field) and is_atom(op) do
    if opts == [] do
      {field, op, value}
    else
      {field, op, value, opts}
    end
  end

  @doc """
  Apply a list of filter conditions as an AND group.

  Similar to `where_all/2` but with a clearer name for the compositional style.

  ## Examples

      conditions = [
        OmQuery.condition(:active, :eq, true),
        OmQuery.condition(:verified, :eq, true)
      ]

      OmQuery.apply_all(token, conditions)
  """
  @spec apply_all(Token.t(), [filter_condition()], keyword()) :: Token.t()
  def apply_all(token, conditions, opts \\ []) when length(conditions) >= 2 do
    where_all(token, conditions, opts)
  end

  @doc """
  Apply a list of filter conditions as an OR group.

  Similar to `where_any/2` but with a clearer name for the compositional style.

  ## Examples

      conditions = [
        OmQuery.condition(:status, :eq, "active"),
        OmQuery.condition(:status, :eq, "pending")
      ]

      OmQuery.apply_any(token, conditions)
  """
  @spec apply_any(Token.t(), [filter_condition()], keyword()) :: Token.t()
  def apply_any(token, conditions, opts \\ []) when length(conditions) >= 2 do
    where_any(token, conditions, opts)
  end

  @doc """
  Apply a list of filter conditions, excluding all matches (NONE).

  Similar to `where_none/2` but with a clearer name for the compositional style.

  ## Examples

      excluded = [
        OmQuery.condition(:status, :eq, "banned"),
        OmQuery.condition(:status, :eq, "deleted")
      ]

      OmQuery.apply_none(token, excluded)
  """
  @spec apply_none(Token.t(), [filter_condition()], keyword()) :: Token.t()
  def apply_none(token, conditions, opts \\ []) when length(conditions) >= 2 do
    where_none(token, conditions, opts)
  end

  # Normalize filter spec to 4-tuple format
  defp normalize_filter_spec({field, op, value}), do: {field, op, value, []}
  defp normalize_filter_spec({field, op, value, opts}), do: {field, op, value, opts}

  # Normalize filter specs with global opts merged in
  defp normalize_filter_specs(filter_list, global_opts) do
    Enum.map(filter_list, fn spec ->
      {field, op, value, filter_opts} = normalize_filter_spec(spec)
      # Per-filter opts take precedence over global opts
      merged_opts = Keyword.merge(global_opts, filter_opts)
      {field, op, value, merged_opts}
    end)
  end

  @doc """
  Add pagination.

  ## Parameters

  - `token` - The query token
  - `type` - Pagination type (`:offset` or `:cursor`)
  - `opts` - Pagination options
    - For offset: `:limit`, `:offset`
    - For cursor: `:limit`, `:cursor_fields`, `:after`, `:before`

  ## Examples

      # Offset pagination
      OmQuery.paginate(token, :offset, limit: 20, offset: 40)

      # Cursor pagination
      OmQuery.paginate(token, :cursor, cursor_fields: [:id], limit: 20, after: cursor)
  """
  @spec paginate(queryable(), :offset | :cursor, keyword()) :: Token.t()
  def paginate(source, type, opts \\ []) do
    source
    |> ensure_token()
    |> Token.add_operation({:paginate, {type, opts}})
  end

  @doc """
  Add ordering (Ecto-style naming).

  Alias: `order/4` - Semantic alternative name for the same operation.

  ## Parameters

  **Single field:**
  - `token` - The query token
  - `field` - Field name to order by
  - `direction` - Sort direction (`:asc` or `:desc`, default: `:asc`)
  - `opts` - Options (optional)
    - `:binding` - Named binding for joined tables (default: `:root`)

  **Multiple fields (list):**
  - `token` - The query token
  - `order_list` - List of order specifications. Each can be:
    - `field` - Atom, defaults to `:asc`
    - `{field, direction}` - 2-tuple with direction
    - `{field, direction, opts}` - 3-tuple with options

  ## Examples

      # Single field - ascending
      OmQuery.order_by(token, :name)

      # Single field - descending
      OmQuery.order_by(token, :created_at, :desc)

      # Multiple fields at once (NEW!)
      OmQuery.order_by(token, [{:priority, :desc}, {:created_at, :desc}, :id])

      # On joined table
      OmQuery.order_by(token, :title, :asc, binding: :posts)

      # Multiple separate calls (chaining)
      token
      |> OmQuery.order_by(:priority, :desc)
      |> OmQuery.order_by(:created_at, :desc)
      |> OmQuery.order_by(:id, :asc)
  """
  @spec order_by(queryable(), atom() | list(), :asc | :desc, keyword()) :: Token.t()
  def order_by(source, field_or_list, direction \\ :asc, opts \\ [])

  # List form - delegate to order_bys
  def order_by(source, order_list, _direction, _opts) when is_list(order_list) do
    order_bys(source, order_list)
  end

  # Single field form
  def order_by(source, field, direction, opts) when is_atom(field) do
    source
    |> ensure_token()
    |> Token.add_operation({:order, {field, direction, opts}})
  end

  @doc """
  Alias for `order_by/4`. Semantic alternative name.

  Supports both single field and list syntax.

  See `order_by/4` for documentation.
  """
  @spec order(queryable(), atom() | list(), :asc | :desc, keyword()) :: Token.t()
  def order(source, field_or_list, direction \\ :asc, opts \\ []) do
    order_by(source, field_or_list, direction, opts)
  end

  @doc """
  Add multiple order clauses at once (Ecto-style naming).

  Alias: `orders/2` - Semantic alternative name for the same operation.

  Supports **both** Ecto keyword syntax and tuple syntax!

  ## Parameters

  - `token` - The query token
  - `order_list` - List of order specifications. Each can be:
    - `field` - Atom, defaults to `:asc`
    - **Ecto keyword syntax**: `{direction, field}` - e.g., `asc: :name`
    - **Tuple syntax**: `{field, direction}` - e.g., `{:name, :asc}`
    - `{field, direction, opts}` - 3-tuple with options

  The function intelligently detects which syntax you're using!

  ## Examples

      # Plain atoms (all default to :asc)
      OmQuery.order_bys(token, [:name, :email, :id])

      # Ecto keyword syntax (NEW! - just like Ecto.Query)
      OmQuery.order_bys(token, [asc: :name, desc: :created_at, asc: :id])
      OmQuery.order_bys(token, [desc: :priority, desc_nulls_first: :score])

      # Tuple syntax (our original)
      OmQuery.order_bys(token, [
        {:priority, :desc},
        {:created_at, :desc},
        {:id, :asc}
      ])

      # 3-tuples with options
      OmQuery.order_bys(token, [
        {:priority, :desc, []},
        {:title, :asc, [binding: :posts]},
        {:id, :asc, []}
      ])

      # Mixed formats work too!
      OmQuery.order_bys(token, [
        :name,                              # Plain atom
        asc: :email,                        # Ecto keyword syntax
        {:created_at, :desc},               # Tuple syntax
        {:title, :asc, [binding: :posts]}  # Tuple with opts
      ])
  """
  @spec order_bys(Token.t(), [
          atom()
          | {atom(), :asc | :desc}
          | {atom(), :asc | :desc, keyword()}
        ]) :: Token.t()
  def order_bys(token, order_list) when is_list(order_list) do
    Enum.reduce(order_list, token, fn
      # Plain atom - defaults to :asc
      field, acc when is_atom(field) ->
        order_by(acc, field, :asc)

      # 2-tuple - could be keyword or tuple syntax
      {key, value}, acc ->
        cond do
          # Ecto keyword syntax: [asc: :field, desc: :field]
          # Key is direction, value is field
          key in [
            :asc,
            :desc,
            :asc_nulls_first,
            :asc_nulls_last,
            :desc_nulls_first,
            :desc_nulls_last
          ] ->
            order_by(acc, value, key)

          # Tuple syntax: [{:field, :asc}, {:field, :desc}]
          # Key is field, value is direction
          value in [
            :asc,
            :desc,
            :asc_nulls_first,
            :asc_nulls_last,
            :desc_nulls_first,
            :desc_nulls_last
          ] ->
            order_by(acc, key, value)

          # Ambiguous - assume tuple syntax (field, direction) for backward compatibility
          true ->
            order_by(acc, key, value)
        end

      # 3-tuple - always tuple syntax with opts: {:field, :direction, opts}
      {field, direction, opts}, acc ->
        order_by(acc, field, direction, opts)
    end)
  end

  @doc """
  Alias for `order_bys/2`. Semantic alternative name.

  See `order_bys/2` for documentation.
  """
  @spec orders(Token.t(), [
          atom()
          | {atom(), :asc | :desc}
          | {atom(), :asc | :desc, keyword()}
        ]) :: Token.t()
  def orders(token, order_list) when is_list(order_list) do
    order_bys(token, order_list)
  end

  @doc """
  Add a join to the query.

  ## Parameters

  - `token` - The query token
  - `association_or_schema` - Association name (atom) or schema module
  - `type` - Join type: `:inner`, `:left`, `:right`, `:full`, `:cross` (default: `:inner`)
  - `opts` - Options:
    - `:as` - Name the binding for use in filters/orders (default: association name)
    - `:on` - Custom join conditions as keyword list

  ## Binding Convention

  Use `as:` in joins to **name** the binding, then use `binding:` in
  `filter/5`, `order/4`, `search/3` to **reference** that binding:

      # Create a named binding with as:
      token
      |> OmQuery.join(:posts, :left, as: :user_posts)
      # Reference it with binding:
      |> OmQuery.filter(:published, :eq, true, binding: :user_posts)
      |> OmQuery.order(:created_at, :desc, binding: :user_posts)

  ## Examples

      # Association join (uses association as binding name)
      OmQuery.join(token, :posts, :left)
      # Filter on it: OmQuery.filter(token, :published, :eq, true, binding: :posts)

      # Named binding for clarity
      OmQuery.join(token, :posts, :left, as: :user_posts)

      # Schema join with custom conditions
      OmQuery.join(token, Post, :left, as: :posts, on: [author_id: :id])
  """
  @spec join(queryable(), atom() | module(), atom(), keyword()) :: Token.t()
  def join(source, association_or_schema, type \\ :inner, opts \\ []) do
    source
    |> ensure_token()
    |> Token.add_operation({:join, {association_or_schema, type, opts}})
  end

  @doc """
  Add a LEFT JOIN to the query.

  Convenience function for `join(source, assoc, :left, opts)`.

  ## Examples

      User |> OmQuery.left_join(:posts)
      User |> OmQuery.left_join(:posts, as: :user_posts)
      User |> OmQuery.left_join(Category, as: :cat, on: [id: :category_id])
  """
  @spec left_join(queryable(), atom() | module(), keyword()) :: Token.t()
  def left_join(source, association_or_schema, opts \\ []) do
    join(source, association_or_schema, :left, opts)
  end

  @doc """
  Add a RIGHT JOIN to the query.

  Convenience function for `join(source, assoc, :right, opts)`.

  ## Examples

      User |> OmQuery.right_join(:posts)
      User |> OmQuery.right_join(:posts, as: :posts)
  """
  @spec right_join(queryable(), atom() | module(), keyword()) :: Token.t()
  def right_join(source, association_or_schema, opts \\ []) do
    join(source, association_or_schema, :right, opts)
  end

  @doc """
  Add an INNER JOIN to the query.

  Convenience function for `join(source, assoc, :inner, opts)`.

  ## Examples

      User |> OmQuery.inner_join(:posts)
      User |> OmQuery.inner_join(:posts, as: :posts)
  """
  @spec inner_join(queryable(), atom() | module(), keyword()) :: Token.t()
  def inner_join(source, association_or_schema, opts \\ []) do
    join(source, association_or_schema, :inner, opts)
  end

  @doc """
  Add a FULL OUTER JOIN to the query.

  Convenience function for `join(source, assoc, :full, opts)`.

  ## Examples

      User |> OmQuery.full_join(:posts)
  """
  @spec full_join(queryable(), atom() | module(), keyword()) :: Token.t()
  def full_join(source, association_or_schema, opts \\ []) do
    join(source, association_or_schema, :full, opts)
  end

  @doc """
  Add a CROSS JOIN to the query.

  Convenience function for `join(source, assoc, :cross, opts)`.

  ## Examples

      User |> OmQuery.cross_join(:roles)
  """
  @spec cross_join(queryable(), atom() | module(), keyword()) :: Token.t()
  def cross_join(source, association_or_schema, opts \\ []) do
    join(source, association_or_schema, :cross, opts)
  end

  @doc """
  Add multiple joins at once.

  ## Parameters

  - `token` - The query token
  - `join_list` - List of join specifications. Each can be:
    - `association` - Atom, defaults to `:inner` join
    - `{association, type}` - 2-tuple with join type
    - `{association, type, opts}` - 3-tuple with options

  ## Examples

      # List of atoms (all inner joins)
      OmQuery.joins(token, [:posts, :comments])

      # List of 2-tuples with join types
      OmQuery.joins(token, [
        {:posts, :left},
        {:comments, :inner}
      ])

      # List of 3-tuples with options
      OmQuery.joins(token, [
        {:posts, :left, []},
        {:comments, :inner, [on: [author_id: :id]]}
      ])
  """
  @spec joins(Token.t(), [
          atom()
          | {atom(), atom()}
          | {atom(), atom(), keyword()}
        ]) :: Token.t()
  def joins(token, join_list) when is_list(join_list) do
    Enum.reduce(join_list, token, fn
      assoc, acc when is_atom(assoc) ->
        join(acc, assoc, :inner, [])

      {assoc, type}, acc ->
        join(acc, assoc, type, [])

      {assoc, type, opts}, acc ->
        join(acc, assoc, type, opts)
    end)
  end

  @doc """
  Add a preload for associations.

  ## Examples

      # Single association
      OmQuery.preload(token, :posts)

      # Multiple associations
      OmQuery.preload(token, [:posts, :comments])

      # Nested preload with filters (use preload/3)
      OmQuery.preload(token, :posts, fn q ->
        q |> OmQuery.filter(:published, :eq, true)
      end)
  """
  @spec preload(queryable(), atom() | keyword() | list()) :: Token.t()
  def preload(source, associations) when is_atom(associations) do
    source
    |> ensure_token()
    |> Token.add_operation({:preload, associations})
  end

  def preload(source, associations) when is_list(associations) do
    source
    |> ensure_token()
    |> Token.add_operation({:preload, associations})
  end

  @doc """
  Alias for `preload/2` when passing a list.

  See `preload/2` for documentation.
  """
  @spec preloads(Token.t(), list()) :: Token.t()
  def preloads(token, associations) when is_list(associations) do
    preload(token, associations)
  end

  @doc """
  Add nested preload with filters and ordering.

  The builder function receives a fresh token and can add filters,
  ordering, pagination, and even nested preloads.

  ## Examples

      # Preload only published posts
      OmQuery.preload(token, :posts, fn q ->
        q
        |> OmQuery.filter(:published, :eq, true)
        |> OmQuery.order(:created_at, :desc)
        |> OmQuery.limit(10)
      end)

      # Nested preloads with filters at each level
      OmQuery.preload(token, :posts, fn q ->
        q
        |> OmQuery.filter(:published, :eq, true)
        |> OmQuery.preload(:comments, fn c ->
          c |> OmQuery.filter(:approved, :eq, true)
        end)
      end)
  """
  @spec preload(queryable(), atom(), (Token.t() -> Token.t())) :: Token.t()
  def preload(source, association, builder_fn) when is_function(builder_fn, 1) do
    nested_token = Token.new(:nested)
    nested_token = builder_fn.(nested_token)

    source
    |> ensure_token()
    |> Token.add_operation({:preload, {association, nested_token}})
  end

  @doc """
  Select fields from the base table and joined tables with aliasing.

  Supports selecting from multiple tables/bindings with custom aliases
  to avoid name conflicts.

  ## Select Formats

  - `[:field1, :field2]` - Simple field list from base table
  - `%{alias: :field}` - Map with aliases from base table
  - `%{alias: {:binding, :field}}` - Field from joined table

  ## Examples

      # Simple select from base table
      OmQuery.select(token, [:id, :name, :price])

      # Select with aliases (same table)
      OmQuery.select(token, %{
        product_id: :id,
        product_name: :name
      })

      # Select from base and joined tables
      Product
      |> OmQuery.new()
      |> OmQuery.join(:category, :left, as: :cat)
      |> OmQuery.join(:brand, :left, as: :brand)
      |> OmQuery.select(%{
        product_id: :id,
        product_name: :name,
        price: :price,
        category_id: {:cat, :id},
        category_name: {:cat, :name},
        brand_id: {:brand, :id},
        brand_name: {:brand, :name}
      })
      |> OmQuery.execute()
  """
  @spec select(queryable(), list() | map()) :: Token.t()
  def select(source, fields) when is_list(fields) or is_map(fields) do
    source
    |> ensure_token()
    |> Token.add_operation({:select, fields})
  end

  @doc """
  Merge additional fields into an existing select.

  Unlike `select/2`, which replaces the entire select clause, `select_merge/2`
  adds fields to the existing schema selection. This is useful when you want
  to include computed fields alongside the original struct fields.

  ## Select Formats

  - `[:field1, :field2]` - Simple field list from base table
  - `%{alias: :field}` - Map with aliases from base table
  - `%{alias: {:binding, :field}}` - Field from joined table

  ## Examples

      # Add computed fields to base schema
      User
      |> OmQuery.filter(:active, :eq, true)
      |> OmQuery.select_merge(%{
        full_name: fragment("first_name || ' ' || last_name"),
        account_age_days: fragment("EXTRACT(DAY FROM NOW() - inserted_at)")
      })
      |> OmQuery.execute()

      # Include fields from joined tables
      Order
      |> OmQuery.join(:customer, :left, as: :cust)
      |> OmQuery.select_merge(%{
        customer_name: {:cust, :name},
        customer_email: {:cust, :email}
      })
      |> OmQuery.execute()

      # Chain multiple select_merge calls
      Product
      |> OmQuery.filter(:active, :eq, true)
      |> OmQuery.select_merge([:name, :price])
      |> OmQuery.select_merge(%{discounted: fragment("price * 0.9")})
  """
  @spec select_merge(queryable(), list() | map()) :: Token.t()
  def select_merge(source, fields) when is_list(fields) or is_map(fields) do
    source
    |> ensure_token()
    |> Token.add_operation({:select_merge, fields})
  end

  @doc """
  Define a named window for use with window functions.

  Windows define the partitioning and ordering for window functions
  like `row_number()`, `rank()`, `sum() OVER`, etc.

  ## Parameters

  - `token` - The query token
  - `name` - Atom name for the window (referenced in select)
  - `opts` - Window definition options:
    - `:partition_by` - Field or list of fields to partition by
    - `:order_by` - Order specification within each partition
    - `:frame` - Frame specification for which rows to include

  ## Frame Specification

  The `:frame` option specifies which rows are included in the window calculation.
  Format: `{frame_type, start_bound, end_bound}` or `{frame_type, start_bound}`

  **Frame types:**
  - `:rows` - Physical row count
  - `:range` - Logical range based on ORDER BY values
  - `:groups` - Groups of peer rows (same ORDER BY value)

  **Bounds:**
  - `:unbounded_preceding` - From start of partition
  - `{:preceding, n}` - n rows/range before current
  - `:current_row` - Current row
  - `{:following, n}` - n rows/range after current
  - `:unbounded_following` - To end of partition

  ## Examples

      # Running total (all rows from start to current)
      token
      |> OmQuery.window(:running,
          partition_by: :category_id,
          order_by: [asc: :date],
          frame: {:rows, :unbounded_preceding, :current_row})

      # 3-row moving average
      token
      |> OmQuery.window(:moving_avg,
          order_by: [asc: :date],
          frame: {:rows, {:preceding, 1}, {:following, 1}})

      # Range-based (value-based window)
      token
      |> OmQuery.window(:price_range,
          order_by: [asc: :price],
          frame: {:range, {:preceding, 100}, {:following, 100}})

      # Without frame (default behavior)
      token
      |> OmQuery.window(:price_rank, partition_by: :category_id, order_by: [desc: :price])

  ## Window Function Syntax in Select

  Use `{:window, function, over: :window_name}` in select maps:

      - `{:window, :row_number, over: :w}` - Row number
      - `{:window, :rank, over: :w}` - Rank with gaps
      - `{:window, :dense_rank, over: :w}` - Rank without gaps
      - `{:window, {:sum, :amount}, over: :w}` - Running sum
      - `{:window, {:avg, :price}, over: :w}` - Running average
      - `{:window, {:lag, :value}, over: :w}` - Previous row value
      - `{:window, {:lead, :value}, over: :w}` - Next row value
      - `{:window, {:first_value, :field}, over: :w}` - First value in window
      - `{:window, {:last_value, :field}, over: :w}` - Last value in window

  ## SQL Equivalent

      -- Running total with frame
      SELECT name,
             SUM(amount) OVER running as running_total
      FROM sales
      WINDOW running AS (
        PARTITION BY category_id
        ORDER BY date ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )

      -- 3-row moving average
      SELECT name,
             AVG(price) OVER moving_avg as avg_3
      FROM products
      WINDOW moving_avg AS (
        ORDER BY date ASC
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
      )
  """
  @spec window(Token.t(), atom(), keyword()) :: Token.t()
  def window(token, name, opts \\ []) when is_atom(name) do
    Token.add_operation(token, {:window, {name, opts}})
  end

  @doc "Add a group by"
  @spec group_by(Token.t(), atom() | list()) :: Token.t()
  def group_by(token, fields) do
    Token.add_operation(token, {:group_by, fields})
  end

  @doc "Add a having clause"
  @spec having(queryable(), keyword()) :: Token.t()
  def having(source, conditions) do
    source
    |> ensure_token()
    |> Token.add_operation({:having, conditions})
  end

  @doc "Add a limit"
  @spec limit(queryable(), pos_integer()) :: Token.t()
  def limit(source, value) do
    source
    |> ensure_token()
    |> Token.add_operation({:limit, value})
  end

  @doc "Add an offset"
  @spec offset(queryable(), non_neg_integer()) :: Token.t()
  def offset(source, value) do
    source
    |> ensure_token()
    |> Token.add_operation({:offset, value})
  end

  @doc "Add distinct"
  @spec distinct(queryable(), boolean() | list()) :: Token.t()
  def distinct(source, value) do
    source
    |> ensure_token()
    |> Token.add_operation({:distinct, value})
  end

  @doc "Add a lock clause"
  @spec lock(Token.t(), String.t() | atom()) :: Token.t()
  def lock(token, mode) do
    Token.add_operation(token, {:lock, mode})
  end

  @doc """
  Add a CTE (Common Table Expression).

  ## Options

  - `:recursive` - Enable recursive CTE mode (default: false)

  ## Examples

      # Simple CTE
      base_query = OmQuery.new(User) |> OmQuery.filter(:active, :eq, true)

      OmQuery.new(Order)
      |> OmQuery.with_cte(:active_users, base_query)
      |> OmQuery.join(:active_users, :inner, on: [user_id: :id])

      # Recursive CTE for hierarchical data (trees, graphs)
      # First define the base case and recursive case combined with union_all
      import Ecto.Query

      # Base case: root categories (no parent)
      base = from(c in "categories", where: is_nil(c.parent_id), select: %{id: c.id, name: c.name, depth: 0})

      # Recursive case: children joining with CTE
      recursive = from(c in "categories",
        join: tree in "category_tree", on: c.parent_id == tree.id,
        select: %{id: c.id, name: c.name, depth: tree.depth + 1}
      )

      # Combine with union_all
      cte_query = union_all(base, ^recursive)

      # Use recursive CTE
      from(c in "category_tree")
      |> OmQuery.new()
      |> OmQuery.with_cte(:category_tree, cte_query, recursive: true)
      |> OmQuery.execute()

  ## SQL Equivalent (Recursive)

      WITH RECURSIVE category_tree AS (
        SELECT id, name, 0 as depth FROM categories WHERE parent_id IS NULL
        UNION ALL
        SELECT c.id, c.name, tree.depth + 1
        FROM categories c
        JOIN category_tree tree ON c.parent_id = tree.id
      )
      SELECT * FROM category_tree
  """
  @spec with_cte(Token.t(), atom(), Token.t() | Ecto.Query.t(), keyword()) :: Token.t()
  def with_cte(token, name, cte_token_or_query, opts \\ []) do
    if opts == [] do
      # Backwards compatible - no opts
      Token.add_operation(token, {:cte, {name, cte_token_or_query}})
    else
      Token.add_operation(token, {:cte, {name, cte_token_or_query, opts}})
    end
  end

  # ============================================================================
  # Set Operations (union, intersect, except)
  # ============================================================================

  @doc """
  Combine results with another query using UNION (removes duplicates).

  Both queries must have the same columns in the same order with compatible types.

  ## Examples

      # Combine active and VIP users (distinct)
      active_users = User |> OmQuery.filter(:status, :eq, "active")
      vip_users = User |> OmQuery.filter(:vip, :eq, true)

      active_users
      |> OmQuery.union(vip_users)
      |> OmQuery.execute()

      # With select to ensure matching columns
      cities_from_customers =
        Customer
        |> OmQuery.new()
        |> OmQuery.select([:city])

      cities_from_suppliers =
        Supplier
        |> OmQuery.new()
        |> OmQuery.select([:city])

      cities_from_customers
      |> OmQuery.union(cities_from_suppliers)
      |> OmQuery.execute()
  """
  @spec union(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def union(token, other) do
    Token.add_operation(token, {:combination, {:union, other}})
  end

  @doc """
  Combine results with another query using UNION ALL (keeps duplicates).

  More efficient than `union/2` when you don't need duplicate removal.

  ## Examples

      # Combine all orders from two time periods
      q1 = Order |> OmQuery.filter(:year, :eq, 2023)
      q2 = Order |> OmQuery.filter(:year, :eq, 2024)

      q1
      |> OmQuery.union_all(q2)
      |> OmQuery.order(:created_at, :desc)
      |> OmQuery.execute()
  """
  @spec union_all(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def union_all(token, other) do
    Token.add_operation(token, {:combination, {:union_all, other}})
  end

  @doc """
  Return only rows that appear in both queries using INTERSECT.

  ## Examples

      # Find users who are both customers AND suppliers
      customers = User |> OmQuery.filter(:role, :eq, "customer") |> OmQuery.select([:id])
      suppliers = User |> OmQuery.filter(:role, :eq, "supplier") |> OmQuery.select([:id])

      customers
      |> OmQuery.intersect(suppliers)
      |> OmQuery.execute()
  """
  @spec intersect(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def intersect(token, other) do
    Token.add_operation(token, {:combination, {:intersect, other}})
  end

  @doc """
  Return rows that appear in both queries using INTERSECT ALL (with duplicates).

  ## Examples

      q1 |> OmQuery.intersect_all(q2)
  """
  @spec intersect_all(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def intersect_all(token, other) do
    Token.add_operation(token, {:combination, {:intersect_all, other}})
  end

  @doc """
  Return rows from the first query that don't appear in the second using EXCEPT.

  ## Examples

      # Find users who are customers but NOT suppliers
      customers = User |> OmQuery.filter(:role, :eq, "customer") |> OmQuery.select([:id])
      suppliers = User |> OmQuery.filter(:role, :eq, "supplier") |> OmQuery.select([:id])

      customers
      |> OmQuery.except(suppliers)
      |> OmQuery.execute()
  """
  @spec except(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def except(token, other) do
    Token.add_operation(token, {:combination, {:except, other}})
  end

  @doc """
  Return rows from the first query that don't appear in the second using EXCEPT ALL.

  ## Examples

      q1 |> OmQuery.except_all(q2)
  """
  @spec except_all(Token.t(), Token.t() | Ecto.Query.t()) :: Token.t()
  def except_all(token, other) do
    Token.add_operation(token, {:combination, {:except_all, other}})
  end

  @doc """
  Add raw SQL fragment with named placeholders.

  **Deprecated:** Use `raw/4` instead, which supports both positional and named
  parameters, accepts any queryable, and supports options like `:binding`.

  ## Migration

      # Old (deprecated)
      token |> OmQuery.raw_where("age > :min", %{min: 18})

      # New (preferred) - with named params
      User |> OmQuery.raw("age > :min", %{min: 18})

      # New (preferred) - with positional params
      User |> OmQuery.raw("age > ?", [18])

  ## Example

      OmQuery.new(User)
      |> OmQuery.raw_where("age BETWEEN :min_age AND :max_age", %{min_age: 18, max_age: 65})
  """
  @deprecated "Use raw/4 instead for more features and consistency"
  @spec raw_where(Token.t(), String.t(), map()) :: Token.t()
  def raw_where(token, sql, params \\ %{}) do
    Token.add_operation(token, {:raw_where, {sql, params}})
  end

  @doc """
  Include a query fragment's operations in the current token.

  Fragments are reusable query components defined with `OmQuery.Fragment`.

  ## Example

      defmodule MyApp.QueryFragments do
        use OmQuery.Fragment

        defragment :active_users do
          filter :status, :eq, "active"
          filter :verified, :eq, true
        end
      end

      # Include in query
      User
      |> OmQuery.new()
      |> OmQuery.include(MyApp.QueryFragments.active_users())
      |> OmQuery.execute()
  """
  @spec include(Token.t(), Token.t()) :: Token.t()
  defdelegate include(token, fragment), to: OmQuery.Fragment

  @doc """
  Conditionally include a query fragment.

  ## Example

      User
      |> OmQuery.new()
      |> OmQuery.include_if(user_params[:show_active], MyApp.QueryFragments.active_users())
      |> OmQuery.execute()
  """
  @spec include_if(Token.t(), boolean(), Token.t() | nil) :: Token.t()
  defdelegate include_if(token, condition, fragment), to: OmQuery.Fragment

  @doc """
  Convert token to a subquery.

  Wraps the query in an Ecto subquery for use in FROM, JOIN, WHERE, or SELECT clauses.

  ## Examples

      # Subquery in FROM
      subset = OmQuery.new(Post) |> OmQuery.where(:status, :eq, "draft")
      OmQuery.from_subquery(subset) |> OmQuery.where(:created_at, :gt, yesterday)

      # Subquery in WHERE with :in_subquery operator
      user_ids = OmQuery.new(User) |> OmQuery.where(:active, :eq, true) |> OmQuery.select([:id])
      OmQuery.new(Post) |> OmQuery.where(:user_id, :in_subquery, user_ids)
  """
  @spec from_subquery(Token.t()) :: Ecto.Query.t()
  def from_subquery(%Token{} = token) do
    import Ecto.Query
    query = Builder.build(token)
    subquery(query)
  end

  @doc """
  Build the Ecto query without executing (safe variant).

  Returns `{:ok, query}` on success or `{:error, exception}` on failure.
  Use this when you want to handle build errors gracefully.

  For the raising variant, use `build!/1` or `build/1`.

  ## Examples

      case OmQuery.build_safe(token) do
        {:ok, query} -> Repo.all(query)
        {:error, %CursorError{}} -> handle_invalid_cursor()
        {:error, error} -> handle_error(error)
      end
  """
  @spec build_safe(Token.t()) :: {:ok, Ecto.Query.t()} | {:error, Exception.t()}
  defdelegate build_safe(token), to: Builder

  @doc """
  Build the Ecto query without executing (raising variant).

  Raises an exception on failure. This is the same as `build/1`.

  For the safe variant that returns tuples, use `build_safe/1`.
  """
  @spec build!(Token.t()) :: Ecto.Query.t()
  defdelegate build!(token), to: Builder

  @doc """
  Build the Ecto query without executing.

  Raises on failure. This is an alias for `build!/1` kept for backwards compatibility.

  For the safe variant, use `build_safe/1`.
  """
  @spec build(Token.t()) :: Ecto.Query.t()
  defdelegate build(token), to: Builder

  @doc """
  Convert a token to an Ecto.Query.

  Alias for `build/1` that provides a common interface name
  for libraries like OmCrud that expect `to_query/1`.

  ## Examples

      token = OmQuery.new(User) |> OmQuery.filter(:active, :eq, true)
      ecto_query = OmQuery.to_query(token)
  """
  @spec to_query(Token.t()) :: Ecto.Query.t()
  def to_query(%Token{} = token), do: Builder.build(token)

  @doc """
  Execute the query and return result or error tuple.

  Returns `{:ok, result}` on success or `{:error, error}` on failure.
  This is the safe variant that never raises exceptions.

  For the raising variant, use `execute!/2`.

  ## Automatic Safety Limits

  **Important**: Queries without pagination or explicit limits are automatically
  limited to prevent unbounded result sets. The default safe limit is 20 records.

  To customize this behavior:
  - Add pagination: `OmQuery.paginate(token, :cursor, limit: 50)`
  - Add explicit limit: `OmQuery.limit(token, 100)`
  - Use streaming: `OmQuery.stream(token)` for large datasets
  - Disable safety: Pass `unsafe: true` option (not recommended)

  ## Options

  - `:repo` - Repo module (default: configured default_repo)
  - `:timeout` - Query timeout in ms (default: 15_000)
  - `:telemetry` - Enable telemetry (default: true)
  - `:cache` - Enable caching (default: false)
  - `:cache_ttl` - Cache TTL in seconds (default: 60)
  - `:include_total_count` - Include total count in pagination (default: false)
  - `:unsafe` - Disable automatic safety limits (default: false, not recommended)
  - `:default_limit` - Override default safe limit (default: 20)

  ## Examples

      # With pattern matching
      case token |> OmQuery.execute() do
        {:ok, result} ->
          IO.puts("Got \#{length(result.data)} records")
        {:error, error} ->
          Logger.error("Query failed: \#{Exception.message(error)}")
      end

      # With options
      {:ok, result} = token |> OmQuery.execute(
        timeout: 30_000,
        include_total_count: true
      )
  """
  @spec execute(Token.t(), keyword()) :: {:ok, Result.t()} | {:error, Exception.t()}
  defdelegate execute(token, opts \\ []), to: Executor

  @doc """
  Execute the query and return structured result.

  Raises exceptions on failure. For a safe variant that returns tuples,
  use `execute/2`.

  ## Automatic Safety Limits

  Like `execute/2`, this function automatically applies safety limits to queries
  without pagination or explicit limits. See `execute/2` for details.

  ## Options

  Same as `execute/2`.

  ## Examples

      # Basic execution
      result = token |> OmQuery.execute!()

      # With options
      result = token |> OmQuery.execute!(
        timeout: 30_000,
        include_total_count: true
      )
  """
  @spec execute!(Token.t(), keyword()) :: Result.t()
  defdelegate execute!(token, opts \\ []), to: Executor

  @doc "Execute and return stream"
  @spec stream(Token.t(), keyword()) :: Enumerable.t()
  defdelegate stream(token, opts \\ []), to: Executor

  # ============================================================================
  # Batch Operations
  # ============================================================================

  @doc """
  Execute a batch update on all records matching the query filters.

  Returns `{:ok, {count, returning}}` on success or `{:error, reason}` on failure.

  ## Update Operations

  Supports Ecto's update operations:
  - `:set` - Set field(s) to value(s)
  - `:inc` - Increment numeric field(s) by value(s)
  - `:push` - Append value(s) to array field(s)
  - `:pull` - Remove value(s) from array field(s)

  ## Options

  - `:repo` - Ecto repo to use (default: configured)
  - `:timeout` - Query timeout in ms (default: 15000)
  - `:returning` - Fields to return (e.g., `[:id, :status]` or `true` for all)
  - `:prefix` - Database schema prefix for multi-tenant apps

  ## Examples

      # Set status to archived for inactive users
      User
      |> OmQuery.filter(:status, :eq, "inactive")
      |> OmQuery.filter(:last_login, :lt, one_year_ago)
      |> OmQuery.update_all(set: [status: "archived"])
      #=> {:ok, {42, nil}}

      # Increment retry count
      Job
      |> OmQuery.filter(:status, :eq, "failed")
      |> OmQuery.update_all(inc: [retry_count: 1])

      # With returning
      User
      |> OmQuery.filter(:id, :in, user_ids)
      |> OmQuery.update_all([set: [verified: true]], returning: [:id, :email])
      #=> {:ok, {3, [%{id: 1, email: "a@b.com"}, ...]}}

      # Multiple operations
      Product
      |> OmQuery.filter(:category, :eq, "electronics")
      |> OmQuery.update_all(set: [on_sale: true], inc: [view_count: 1])
  """
  @spec update_all(Token.t(), keyword(), keyword()) ::
          {:ok, {non_neg_integer(), nil | [map()]}} | {:error, term()}
  defdelegate update_all(token, updates, opts \\ []), to: Executor

  @doc """
  Execute a batch update. Raises on failure.

  See `update_all/3` for documentation.
  """
  @spec update_all!(Token.t(), keyword(), keyword()) :: {non_neg_integer(), nil | [map()]}
  defdelegate update_all!(token, updates, opts \\ []), to: Executor

  @doc """
  Execute a batch delete on all records matching the query filters.

  Returns `{:ok, {count, returning}}` on success or `{:error, reason}` on failure.

  ## Options

  - `:repo` - Ecto repo to use (default: configured)
  - `:timeout` - Query timeout in ms (default: 15000)
  - `:returning` - Fields to return (e.g., `[:id]` or `true` for all)
  - `:prefix` - Database schema prefix for multi-tenant apps

  ## Examples

      # Delete old soft-deleted records
      User
      |> OmQuery.filter(:deleted_at, :not_nil, true)
      |> OmQuery.filter(:deleted_at, :lt, one_year_ago)
      |> OmQuery.delete_all()
      #=> {:ok, {15, nil}}

      # Delete with returning
      Session
      |> OmQuery.filter(:expires_at, :lt, DateTime.utc_now())
      |> OmQuery.delete_all(returning: [:id, :user_id])
      #=> {:ok, {100, [%{id: 1, user_id: 5}, ...]}}

      # Delete from joined query
      Post
      |> OmQuery.join(:inner, :user, on: [id: :user_id])
      |> OmQuery.filter(:status, :eq, "banned", binding: :user)
      |> OmQuery.delete_all()
  """
  @spec delete_all(Token.t(), keyword()) ::
          {:ok, {non_neg_integer(), nil | [map()]}} | {:error, term()}
  defdelegate delete_all(token, opts \\ []), to: Executor

  @doc """
  Execute a batch delete. Raises on failure.

  See `delete_all/2` for documentation.
  """
  @spec delete_all!(Token.t(), keyword()) :: {non_neg_integer(), nil | [map()]}
  defdelegate delete_all!(token, opts \\ []), to: Executor

  # ============================================================================
  # Bulk Insert Operations
  # ============================================================================

  @doc """
  Insert multiple records in a single query.

  This is a low-level bulk insert that bypasses changesets for performance.
  For validated inserts, use OmCrud.create_all/3 instead.

  ## Options

  - `:repo` - Ecto repo to use (default: configured)
  - `:timeout` - Query timeout in ms (default: 15000)
  - `:returning` - Fields to return (e.g., `[:id]` or `true` for all)
  - `:prefix` - Database schema prefix for multi-tenant apps
  - `:on_conflict` - Conflict handling (see upsert_all/3)
  - `:conflict_target` - Column(s) for conflict detection
  - `:placeholders` - Map of shared values to reduce data transfer

  ## Examples

      # Basic bulk insert
      users = [
        %{name: "Alice", email: "alice@example.com"},
        %{name: "Bob", email: "bob@example.com"}
      ]
      {:ok, {2, nil}} = OmQuery.insert_all(User, users)

      # With returning
      {:ok, {2, records}} = OmQuery.insert_all(User, users, returning: [:id])

      # With placeholders
      now = DateTime.utc_now()
      OmQuery.insert_all(User, users, placeholders: %{now: now})
  """
  @spec insert_all(module(), [map()], keyword()) ::
          {:ok, {non_neg_integer(), nil | [map()]}} | {:error, term()}
  defdelegate insert_all(schema, entries, opts \\ []), to: Executor

  @doc """
  Insert multiple records. Raises on failure.

  See `insert_all/3` for documentation.
  """
  @spec insert_all!(module(), [map()], keyword()) :: {non_neg_integer(), nil | [map()]}
  defdelegate insert_all!(schema, entries, opts \\ []), to: Executor

  @doc """
  Upsert multiple records (insert or update on conflict).

  Combines insert with conflict resolution for idempotent bulk operations.

  ## Conflict Options

  - `:conflict_target` - Column(s) for uniqueness (required)
  - `:on_conflict` - What to do on conflict:
    - `:nothing` - Skip conflicting rows
    - `:replace_all` - Replace all fields
    - `{:replace, [:field1, :field2]}` - Replace specific fields
    - `{:replace_all_except, [:id, :inserted_at]}` - Replace all except listed

  ## Examples

      # Update name on email conflict
      {:ok, {count, nil}} = OmQuery.upsert_all(User, users,
        conflict_target: :email,
        on_conflict: {:replace, [:name, :updated_at]}
      )

      # Skip duplicates
      {:ok, {count, nil}} = OmQuery.upsert_all(User, users,
        conflict_target: :email,
        on_conflict: :nothing
      )
  """
  @spec upsert_all(module(), [map()], keyword()) ::
          {:ok, {non_neg_integer(), nil | [map()]}} | {:error, term()}
  defdelegate upsert_all(schema, entries, opts), to: Executor

  @doc """
  Upsert multiple records. Raises on failure.

  See `upsert_all/3` for documentation.
  """
  @spec upsert_all!(module(), [map()], keyword()) :: {non_neg_integer(), nil | [map()]}
  defdelegate upsert_all!(schema, entries, opts), to: Executor

  # ============================================================================
  # Batch Processing
  # ============================================================================

  @doc """
  Process query results in batches for memory efficiency.

  Useful for processing large datasets without loading everything into memory.

  ## Options

  - `:batch_size` - Records per batch (default: 1000)
  - `:order_by` - Ordering field(s) (default: `:id`)

  ## Examples

      # Process in batches of 500
      User
      |> OmQuery.filter(:status, :eq, "inactive")
      |> OmQuery.find_in_batches(batch_size: 500, fn batch ->
           Enum.each(batch, &send_email/1)
         end)
      #=> {:ok, %{total_batches: 10, total_records: 5000}}

      # With batch info
      User
      |> OmQuery.find_in_batches(fn batch, info ->
           IO.puts("Batch \#{info.batch_number}")
           process_batch(batch)
         end)
  """
  @spec find_in_batches(Token.t(), keyword() | function(), function() | nil) ::
          {:ok, map()} | {:error, term()}
  defdelegate find_in_batches(token, opts_or_callback, callback \\ nil), to: Executor

  @doc """
  Process each record individually with memory efficiency.

  Like `find_in_batches/3` but invokes callback for each record.

  ## Examples

      User
      |> OmQuery.filter(:needs_sync, :eq, true)
      |> OmQuery.find_each(fn user ->
           sync_to_external(user)
         end)
      #=> {:ok, %{total_records: 1500}}
  """
  @spec find_each(Token.t(), keyword() | function(), function() | nil) ::
          {:ok, map()} | {:error, term()}
  defdelegate find_each(token, opts_or_callback, callback \\ nil), to: Executor

  # ============================================================================
  # Query Plan Analysis (EXPLAIN)
  # ============================================================================

  @doc """
  Get the execution plan for a query without running it.

  Returns `{:ok, plan}` on success or `{:error, reason}` on failure.

  ## PostgreSQL Options

  | Option | Type | Description |
  |--------|------|-------------|
  | `:analyze` | boolean | Execute query and show actual times (default: false) |
  | `:verbose` | boolean | Show additional details |
  | `:costs` | boolean | Show estimated costs (default: true) |
  | `:buffers` | boolean | Show buffer usage (requires analyze) |
  | `:timing` | boolean | Show timing info (requires analyze) |
  | `:summary` | boolean | Show summary statistics |
  | `:format` | atom | Output format: `:text`, `:yaml`, or `:map` |

  ## Examples

      # Basic plan
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain()
      #=> {:ok, "Seq Scan on users  (cost=0.00..12.00 rows=1 width=100)\\n  Filter: (status = 'active')"}

      # With analyze (executes the query)
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain(analyze: true)

      # As structured map
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain(format: :map)
      #=> {:ok, [%{"Plan" => %{"Node Type" => "Seq Scan", ...}}]}

      # Full analysis with buffers
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain(analyze: true, buffers: true, timing: true)

  ## Safety Note

  When `analyze: true`, the query is actually executed (in a rolled-back transaction).
  Use with caution on production databases with expensive queries.
  """
  @spec explain(Token.t(), keyword()) :: {:ok, String.t() | list(map())} | {:error, term()}
  def explain(token, opts \\ []), do: Executor.explain(token, opts)

  @doc """
  Get the execution plan for a query. Raises on failure.

  See `explain/2` for documentation.
  """
  @spec explain!(Token.t(), keyword()) :: String.t() | list(map())
  def explain!(token, opts \\ []), do: Executor.explain!(token, opts)

  @doc """
  Print the execution plan to stdout and return the token unchanged.

  Useful for debugging in pipelines without breaking the chain.

  ## Examples

      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain_to_stdout(analyze: true)
      |> OmQuery.execute()
  """
  @spec explain_to_stdout(Token.t(), keyword()) :: Token.t()
  def explain_to_stdout(token, opts \\ []), do: Executor.explain_to_stdout(token, opts)

  ## Cursor Utilities

  @doc """
  Encode a cursor from a record for cursor-based pagination.

  Useful for testing and manually creating cursors.

  ## Examples

      # Simple cursor
      cursor = OmQuery.encode_cursor(%{id: 123}, [:id])

      # Multi-field cursor
      cursor = OmQuery.encode_cursor(
        %{created_at: ~U[2024-01-01 00:00:00Z], id: 123},
        [{:created_at, :desc}, {:id, :asc}]
      )
  """
  @spec encode_cursor(map() | nil, [atom() | {atom(), :asc | :desc}]) :: String.t() | nil
  defdelegate encode_cursor(record, fields), to: Result

  @doc """
  Decode a cursor string back to its original data.

  Useful for testing and debugging cursor contents.

  ## Examples

      {:ok, data} = OmQuery.decode_cursor(cursor_string)
      # => %{id: 123}

      {:error, reason} = OmQuery.decode_cursor("invalid")
  """
  @spec decode_cursor(String.t() | any()) :: {:ok, map()} | {:error, String.t()}
  defdelegate decode_cursor(encoded), to: Builder

  @doc """
  Execute query in a transaction.

  ## Example

      OmQuery.transaction(fn ->
        user = User |> OmQuery.new() |> OmQuery.filter(:id, :eq, 1) |> OmQuery.execute()
        # ... more operations
        {:ok, user}
      end)
  """
  @spec transaction((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction(fun, opts \\ []) do
    repo = get_repo(opts)
    repo.transaction(fun, opts)
  end

  @doc """
  Execute multiple queries in a batch.

  Returns list of results in the same order as tokens.

  ## Example

      tokens = [
        User |> OmQuery.new() |> OmQuery.filter(:active, :eq, true),
        Post |> OmQuery.new() |> OmQuery.limit(10)
      ]

      [users_result, posts_result] = OmQuery.batch(tokens)
  """
  @spec batch([Token.t()], keyword()) :: [Result.t()]
  def batch(tokens, opts \\ []) when is_list(tokens) do
    Executor.batch(tokens, opts)
  end

  ## Convenience Query Functions
  ##
  ## These functions provide common query patterns with a cleaner API.
  ## They build on top of the core execute/2 function.

  @doc """
  Get the first result from the query, or nil if no results.

  Automatically adds `limit: 1` if not already limited.

  ## Examples

      # Get first active user
      User
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.order(:created_at, :asc)
      |> OmQuery.first()
      # => %User{...} or nil

      # With options
      OmQuery.first(token, repo: MyApp.Repo)
  """
  @spec first(Token.t(), keyword()) :: term() | nil
  def first(%Token{} = token, opts \\ []) do
    token
    |> limit(1)
    |> execute!(Keyword.put(opts, :unsafe, true))
    |> Map.get(:data)
    |> List.first()
  end

  @doc """
  Get the first result, raising if no results found.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.filter(:id, :eq, 123)
      |> OmQuery.first!()
      # => %User{...} or raises Ecto.NoResultsError
  """
  @spec first!(Token.t(), keyword()) :: term()
  def first!(%Token{} = token, opts \\ []) do
    case first(token, opts) do
      nil -> raise Ecto.NoResultsError, queryable: build(token)
      result -> result
    end
  end

  @doc """
  Get exactly one result, raising if zero or more than one.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.filter(:email, :eq, "john@example.com")
      |> OmQuery.one()
      # => %User{...} or nil

      # Raises if more than one result
      User
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.one()
      # => raises Ecto.MultipleResultsError if multiple matches
  """
  @spec one(Token.t(), keyword()) :: term() | nil
  def one(%Token{} = token, opts \\ []) do
    result =
      token
      |> limit(2)
      |> execute!(Keyword.put(opts, :unsafe, true))
      |> Map.get(:data)

    case result do
      [] -> nil
      [single] -> single
      [_ | _] -> raise Ecto.MultipleResultsError, queryable: build(token), count: 2
    end
  end

  @doc """
  Get exactly one result, raising if zero or more than one.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.filter(:email, :eq, "john@example.com")
      |> OmQuery.one!()
      # => %User{...} or raises
  """
  @spec one!(Token.t(), keyword()) :: term()
  def one!(%Token{} = token, opts \\ []) do
    case one(token, opts) do
      nil -> raise Ecto.NoResultsError, queryable: build(token)
      result -> result
    end
  end

  @doc """
  Get the count of records matching the query.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.count()
      # => 42
  """
  @spec count(Token.t(), keyword()) :: non_neg_integer()
  def count(%Token{} = token, opts \\ []) do
    repo = get_repo(opts)
    timeout = opts[:timeout] || 15_000

    query =
      token
      |> remove_operations(:select)
      |> remove_operations(:order)
      |> remove_operations(:preload)
      |> remove_operations(:limit)
      |> remove_operations(:offset)
      |> remove_operations(:paginate)
      |> build()

    repo.aggregate(query, :count, timeout: timeout)
  end

  @doc """
  Check if any records match the query.

  More efficient than `count(token) > 0` as it uses EXISTS.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.filter(:email, :eq, "john@example.com")
      |> OmQuery.exists?()
      # => true or false
  """
  @spec exists?(Token.t(), keyword()) :: boolean()
  def exists?(%Token{} = token, opts \\ []) do
    repo = get_repo(opts)
    timeout = opts[:timeout] || 15_000

    query = build(token)
    repo.exists?(query, timeout: timeout)
  end

  @doc """
  Perform an aggregate operation on the query.

  ## Supported Aggregates

  - `:count` - Count of records (or field)
  - `:sum` - Sum of field values
  - `:avg` - Average of field values
  - `:min` - Minimum field value
  - `:max` - Maximum field value

  ## Examples

      # Sum of amounts
      Order
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "completed")
      |> OmQuery.aggregate(:sum, :amount)
      # => Decimal.new("12345.67")

      # Average age
      User
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.aggregate(:avg, :age)
      # => 32.5

      # Count with field (non-null values)
      User
      |> OmQuery.new()
      |> OmQuery.aggregate(:count, :email)
      # => 100
  """
  @spec aggregate(Token.t(), :count | :sum | :avg | :min | :max, atom(), keyword()) :: term()
  def aggregate(%Token{} = token, aggregate_type, field, opts \\ [])
      when aggregate_type in [:count, :sum, :avg, :min, :max] do
    repo = get_repo(opts)
    timeout = opts[:timeout] || 15_000

    query =
      token
      |> remove_operations(:select)
      |> remove_operations(:order)
      |> remove_operations(:preload)
      |> remove_operations(:limit)
      |> remove_operations(:offset)
      |> remove_operations(:paginate)
      |> build()

    repo.aggregate(query, aggregate_type, field, timeout: timeout)
  end

  @doc """
  Get all records as a plain list (without Result wrapper).

  Useful when you just want the data without pagination metadata.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.all()
      # => [%User{}, %User{}, ...]
  """
  @spec all(Token.t(), keyword()) :: [term()]
  def all(%Token{} = token, opts \\ []) do
    token
    |> execute!(opts)
    |> Map.get(:data)
  end

  @doc """
  Remove operations of a specific type from the token.

  Useful for transforming queries (e.g., building count queries).

  ## Examples

      token
      |> OmQuery.remove_operations(:order)
      |> OmQuery.remove_operations(:select)
  """
  @spec remove_operations(Token.t(), atom()) :: Token.t()
  defdelegate remove_operations(token, type), to: Token

  ## Pipeline Helpers
  ##
  ## Functions that help with pipeline composition.

  @doc """
  Conditionally apply a function to the token.

  Useful for building queries conditionally in a pipeline.

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.then_if(params[:status], fn token, status ->
        OmQuery.filter(token, :status, :eq, status)
      end)
      |> OmQuery.then_if(params[:min_age], fn token, age ->
        OmQuery.filter(token, :age, :gte, age)
      end)
      |> OmQuery.execute()
  """
  @spec then_if(Token.t(), term(), (Token.t(), term() -> Token.t())) :: Token.t()
  def then_if(%Token{} = token, nil, _fun), do: token
  def then_if(%Token{} = token, false, _fun), do: token
  def then_if(%Token{} = token, value, fun), do: fun.(token, value)

  @doc """
  Conditionally apply a function to the token (boolean version).

  ## Examples

      User
      |> OmQuery.new()
      |> OmQuery.if_true(show_active?, fn token ->
        OmQuery.filter(token, :status, :eq, "active")
      end)
      |> OmQuery.execute()
  """
  @spec if_true(Token.t(), boolean(), (Token.t() -> Token.t())) :: Token.t()
  def if_true(%Token{} = token, true, fun), do: fun.(token)
  def if_true(%Token{} = token, false, _fun), do: token

  @doc """
  Apply multiple filter conditions from a map or keyword list.

  Supports both simple equality and explicit operator tuples.
  Nil values and empty lists are automatically skipped.

  ## Filter Formats

  - `{field, value}` - Equality filter (`:eq`)
  - `{field, {op, value}}` - Explicit operator
  - `{field, {op, value, opts}}` - Operator with options (e.g., binding)

  ## All Supported Operators

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:eq` | `=` | `status: "active"` or `status: {:eq, "active"}` |
  | `:neq` | `!=` | `status: {:neq, "deleted"}` |
  | `:gt` | `>` | `age: {:gt, 18}` |
  | `:gte` | `>=` | `rating: {:gte, 4}` |
  | `:lt` | `<` | `price: {:lt, 100}` |
  | `:lte` | `<=` | `stock: {:lte, 10}` |
  | `:in` | `IN` | `status: {:in, ["active", "pending"]}` |
  | `:not_in` | `NOT IN` | `role: {:not_in, ["banned", "spam"]}` |
  | `:like` | `LIKE` | `name: {:like, "John%"}` |
  | `:ilike` | `ILIKE` | `email: {:ilike, "%@gmail.com"}` |
  | `:is_nil` | `IS NULL` | `deleted_at: {:is_nil, true}` |
  | `:not_nil` | `IS NOT NULL` | `email: {:not_nil, true}` |
  | `:between` | `BETWEEN` | `price: {:between, {10, 100}}` |
  | `:contains` | `@>` | `tags: {:contains, ["elixir"]}` |
  | `:jsonb_contains` | `@>` | `metadata: {:jsonb_contains, %{premium: true}}` |
  | `:jsonb_has_key` | `?` | `settings: {:jsonb_has_key, "notifications"}` |
  | `:similarity` | `similarity() >` | `name: {:similarity, "jon", threshold: 0.3}` |
  | `:word_similarity` | `word_similarity() >` | `title: {:word_similarity, "phone"}` |

  ## Examples

      # Simple equality filters (most common)
      params = %{status: "active", role: "admin"}
      OmQuery.filter_by(token, params)

      # With explicit operators
      filters = %{
        status: "active",                          # :eq by default
        price: {:between, {10, 100}},              # price BETWEEN 10 AND 100
        category_id: {:in, [1, 2, 3]},             # category_id IN (1, 2, 3)
        rating: {:gte, 4},                         # rating >= 4
        name: {:ilike, "%phone%"},                 # name ILIKE '%phone%'
        deleted_at: {:is_nil, true}                # deleted_at IS NULL
      }
      OmQuery.filter_by(token, filters)

      # JSONB queries
      filters = %{
        metadata: {:jsonb_contains, %{verified: true}},
        settings: {:jsonb_has_key, "theme"}
      }
      OmQuery.filter_by(token, filters)

      # Fuzzy matching (requires pg_trgm extension)
      filters = %{
        name: {:similarity, "john", threshold: 0.4}
      }
      OmQuery.filter_by(token, filters)

      # With binding for joined tables
      token
      |> OmQuery.join(:category, :left, as: :cat)
      |> OmQuery.filter_by(%{
        status: "active",
        name: {:eq, "Electronics", binding: :cat}
      })

      # Nil values are skipped (useful with params)
      params = %{status: "active", search: nil}  # search is skipped
      OmQuery.filter_by(token, params)
  """
  @spec filter_by(Token.t(), map() | keyword()) :: Token.t()
  def filter_by(%Token{} = token, filters) when is_map(filters) or is_list(filters) do
    Enum.reduce(filters, token, fn
      # Skip nil values
      {_key, nil}, acc ->
        acc

      # Skip empty lists for :in operators
      {_key, {:in, []}}, acc ->
        acc

      {_key, {:not_in, []}}, acc ->
        acc

      # Operator with options: {field, {op, value, opts}}
      {key, {op, value, opts}}, acc when is_atom(op) and is_list(opts) ->
        filter(acc, key, op, value, opts)

      # Operator tuple: {field, {op, value}}
      {key, {op, value}}, acc when is_atom(op) ->
        filter(acc, key, op, value)

      # Simple value: {field, value} defaults to :eq
      {key, value}, acc ->
        filter(acc, key, :eq, value)
    end)
  end

  @doc """
  Search across multiple fields using OR logic with optional ranking.

  Supports multiple search modes from simple LIKE patterns to PostgreSQL
  fuzzy matching with pg_trgm similarity. Each field can have its own mode
  and rank for result ordering.

  ## Quick Start

      # Basic search (OR across all fields)
      OmQuery.search(token, "iphone", [:name, :description, :sku])

      # E-commerce search with ranking (best matches first)
      OmQuery.search(token, "wireless headphones", [
        {:sku, :exact, rank: 1, take: 3},           # Exact SKU matches first
        {:name, :similarity, rank: 2, take: 10},    # Fuzzy name matches
        {:brand, :ilike, rank: 3, take: 5},         # Brand contains term
        {:description, :ilike, rank: 4, take: 5}    # Description matches
      ], rank: true)
      # Returns up to 23 results, ordered by relevance rank

      # Cross-table search with joins
      token
      |> OmQuery.join(:brand, :left, as: :brand)
      |> OmQuery.search("apple", [
        {:name, :ilike},
        {:name, :similarity, binding: :brand}       # Search brand.name too
      ])

  ## Field Specifications

  Fields can be specified in three formats:

  - `field` - Just the field name, uses global `:mode` option (default: `:ilike`)
  - `{field, mode}` - Field with specific mode
  - `{field, mode, opts}` - Field with mode and per-field options

  ## Search Modes

  - `:ilike` - Case-insensitive LIKE (default)
  - `:like` - Case-sensitive LIKE
  - `:exact` - Exact equality match
  - `:starts_with` - Prefix match (ILIKE with `term%`)
  - `:ends_with` - Suffix match (ILIKE with `%term`)
  - `:similarity` - PostgreSQL trigram similarity (requires pg_trgm)
  - `:word_similarity` - Match whole words within text (requires pg_trgm)
  - `:strict_word_similarity` - Strictest word boundary matching (requires pg_trgm)

  ## Global Options

  - `:mode` - Default mode for fields without explicit mode (default: `:ilike`)
  - `:threshold` - Default similarity threshold (default: 0.3)
  - `:rank` - Enable result ranking by field priority (default: false)

  ## Per-Field Options

  - `:rank` - Priority rank for this field (lower = higher priority, e.g., 1 = top)
  - `:take` - Limit how many results from this field/rank (requires `:rank` enabled)
  - `:threshold` - Similarity threshold for this field (overrides global)
  - `:case_sensitive` - For pattern modes, use case-sensitive matching
  - `:binding` - Named binding for joined tables (default: `:root`)

  ## Examples

      # Simple: same mode for all fields (default :ilike with contains)
      OmQuery.search(token, "iphone", [:name, :description, :sku])

      # Per-field modes: different search strategy per field
      OmQuery.search(token, "iphone", [
        {:sku, :exact},                              # Exact match on SKU
        {:name, :similarity},                        # Fuzzy match on name
        {:description, :ilike}                       # ILIKE on description
      ])

      # WITH RANKING: Results ordered by which field matched
      OmQuery.search(token, "iphone", [
        {:sku, :exact, rank: 1},                     # Highest priority - exact SKU
        {:name, :similarity, rank: 2},               # Second - fuzzy name match
        {:brand, :starts_with, rank: 3},             # Third - brand prefix
        {:description, :ilike, rank: 4}              # Lowest - description contains
      ], rank: true)

      # E-commerce search with ranking
      OmQuery.search(token, params[:q], [
        {:sku, :exact, rank: 1},                     # SKU-123 exact = top result
        {:name, :similarity, rank: 2, threshold: 0.3},
        {:brand, :starts_with, rank: 3},
        {:description, :word_similarity, rank: 4}
      ], rank: true)

      # WITH TAKE LIMITS: Control how many results from each field/rank
      OmQuery.search(token, "iphone", [
        {:email, :exact, rank: 1, take: 5},          # Top 5 exact email matches
        {:name, :similarity, rank: 2, take: 10},     # Then 10 fuzzy name matches
        {:description, :ilike, rank: 3, take: 5}     # Then 5 description matches
      ], rank: true)
      # Total results: up to 20 (5 from email + 10 from name + 5 from description)
      # Results ordered by rank, then by relevance within each rank

      # Autocomplete with ranking (exact prefix > fuzzy)
      OmQuery.search(token, input, [
        {:name, :starts_with, rank: 1, take: 5},     # Top 5 prefix matches
        {:name, :similarity, rank: 2, take: 10}      # Then 10 fuzzy matches
      ], rank: true)

      # Returns unchanged token if search term is nil or empty
      OmQuery.search(token, nil, [:name])  # => token unchanged

  ## How Ranking Works

  When `:rank` is enabled:
  1. Results are ordered by which field matched (lower rank = higher priority)
  2. For similarity modes, secondary ordering uses the similarity score (DESC)
  3. If no rank specified, fields are assigned auto-incrementing ranks

  The generated SQL uses CASE WHEN for ranking:
  ```sql
  ORDER BY
    CASE
      WHEN sku = 'term' THEN 1
      WHEN name % 'term' THEN 2
      WHEN brand ILIKE 'term%' THEN 3
      ELSE 999
    END ASC,
    similarity(name, 'term') DESC  -- secondary sort for similarity fields
  ```

  ## How Take Limits Work

  When `:take` is specified per field, results are ordered by rank and
  limited to the sum of all take values. This provides a practical approximation
  that works within Ecto's query builder constraints.

  **Current behavior:**
  - Results are ordered by rank (rank 1 first, then rank 2, etc.)
  - Total limit is the sum of all take values (e.g., take: 5 + take: 10 + take: 5 = 20)
  - Within each rank, results are ordered by similarity score (for fuzzy modes)

  **Example:**
  ```elixir
  OmQuery.search(token, "iphone", [
    {:email, :exact, rank: 1, take: 5},      # Rank 1 matches first
    {:name, :similarity, rank: 2, take: 10}, # Then rank 2 matches
    {:description, :ilike, rank: 3, take: 5} # Then rank 3 matches
  ], rank: true)
  # Returns up to 20 results, ordered by rank
  ```

  **Note:** For exact per-rank limits (enforced per-category counts), use
  a raw SQL query with window functions:

  ```sql
  SELECT * FROM (
    SELECT *,
      CASE
        WHEN email = 'term' THEN 1
        WHEN similarity(name, 'term') > 0.3 THEN 2
        WHEN description ILIKE '%term%' THEN 3
        ELSE 999
      END AS match_rank,
      ROW_NUMBER() OVER (
        PARTITION BY (CASE ... END)
        ORDER BY similarity(name, 'term') DESC
      ) AS row_num
    FROM products
    WHERE ...
  ) subq
  WHERE
    (match_rank = 1 AND row_num <= 5) OR
    (match_rank = 2 AND row_num <= 10) OR
    (match_rank = 3 AND row_num <= 5)
  ORDER BY match_rank, row_num
  ```

  ## PostgreSQL pg_trgm Setup

  For similarity modes, you need the pg_trgm extension:

      CREATE EXTENSION IF NOT EXISTS pg_trgm;

  For better performance, create a GIN or GiST index:

      CREATE INDEX products_name_trgm_idx ON products USING gin (name gin_trgm_ops);
  """
  @spec search(Token.t(), String.t() | nil, [atom() | tuple()], keyword()) :: Token.t()
  defdelegate search(token, term, fields, opts \\ []), to: Search

  # Private helper to get repo from opts or configured default
  defp get_repo(opts) do
    opts[:repo] || @default_repo ||
      raise "No repo configured. Pass :repo option or configure default_repo: config :om_query, default_repo: MyApp.Repo"
  end
end
