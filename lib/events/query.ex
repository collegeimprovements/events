defmodule Events.Query do
  @moduledoc """
  Production-grade query builder with token pattern and pipelines.

  This is the **single entry point** for all query operations. All other modules
  in `Events.Query.*` are internal implementation details.

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

  - `Events.Query.DSL` - Macro-based DSL (`import Events.Query.DSL`)
  - `Events.Query.Fragment` - Reusable query fragments (`use Events.Query.Fragment`)
  - `Events.Query.Helpers` - Date/time utilities (`import Events.Query.Helpers`)
  - `Events.Query.Multi` - Ecto.Multi integration (`alias Events.Query.Multi`)
  - `Events.Query.FacetedSearch` - E-commerce faceted search
  - `Events.Query.TestHelpers` - Test utilities (`use Events.Query.TestHelpers`)

  ## Error Types

  - `Events.Query.ValidationError` - Invalid operation or value
  - `Events.Query.LimitExceededError` - Limit exceeds max_limit config
  - `Events.Query.PaginationError` - Invalid pagination configuration
  - `Events.Query.CursorError` - Invalid or expired cursor

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
  |> Query.new()
  |> Query.join(:posts, :left, as: :posts)           # as: names the binding
  |> Query.filter(:published, :eq, true, binding: :posts)  # binding: references it
  |> Query.order(:created_at, :desc, binding: :posts)
  |> Query.search("elixir", [{:title, :ilike, binding: :posts}])
  ```

  This matches Ecto's conventions where `as:` creates named bindings.

  ## Basic Usage

  ```elixir
  # Macro DSL
  import Events.Query

  query User do
    filter :status, :eq, "active"
    filter :age, :gte, 18
    order :created_at, :desc
    paginate :offset, limit: 20
  end
  |> execute()

  # Pipeline API
  User
  |> Events.Query.new()
  |> Events.Query.filter(:status, :eq, "active")
  |> Events.Query.paginate(:offset, limit: 20)
  |> Events.Query.execute()
  ```

  ## Result Format

  All queries return `%Events.Query.Result{}`:

  ```elixir
  %Events.Query.Result{
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

  4. **Limit preloads** - each preload is a separate query. Use `Query.join` + `Query.select`
     for denormalized results in a single query.

  ## Limitations

  - **Window functions:** Dynamic window functions aren't fully supported. Use `fragment/1`:
    ```elixir
    Query.select(token, %{
      rank: fragment("ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY price)")
    })
    ```
  - Subquery operators only work in filters, not in select
  - `:explain_analyze` in debug executes the query (use with care in production)
  """

  alias Events.Query.{Token, Builder, Executor, Result}

  # Re-export key types
  @type t :: Token.t()

  ## Public API

  @doc "Create a new query token from a schema"
  @spec new(module() | Ecto.Query.t()) :: Token.t()
  defdelegate new(schema_or_query), to: Token

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
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.debug()
      |> Query.execute()

      # Specific format
      token |> Query.debug(:pipeline)
      token |> Query.debug(:dsl)
      token |> Query.debug([:raw_sql, :ecto])

      # With options
      token |> Query.debug(:raw_sql, label: "Product Search", color: :green)

      # Debug at multiple points
      Product
      |> Query.new()
      |> Query.debug(:token, label: "Initial")
      |> Query.filter(:price, :gt, 100)
      |> Query.debug(:raw_sql, label: "After filter")
      |> Query.join(:category, :left)
      |> Query.debug(:raw_sql, label: "After join")
      |> Query.execute()
  """
  @spec debug(Token.t() | Ecto.Query.t(), atom() | [atom()], keyword()) ::
          Token.t() | Ecto.Query.t()
  defdelegate debug(input, format \\ :raw_sql, opts \\ []), to: Events.Query.Debug

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
      Query.where(token, :status, :eq, "active")

      # With options
      Query.where(token, :email, :eq, "john@example.com", case_insensitive: true)

      # On joined table
      Query.where(token, :published, :eq, true, binding: :posts)

      # Multiple separate calls (chaining)
      token
      |> Query.where(:status, :eq, "active")
      |> Query.where(:age, :gte, 18)
      |> Query.where(:verified, :eq, true)
  """
  @spec where(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def where(token, field, op, value, opts \\ []) do
    Token.add_operation(token, {:filter, {field, op, value, opts}})
  end

  @doc """
  Alias for `where/5`. Semantic alternative name.

  See `where/5` for documentation.
  """
  @spec filter(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def filter(token, field, op, value, opts \\ []) do
    where(token, field, op, value, opts)
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
      Query.wheres(token, [
        {:status, :eq, "active"},
        {:age, :gte, 18},
        {:verified, :eq, true}
      ])

      # List of 4-tuples with options
      Query.wheres(token, [
        {:status, :eq, "active", []},
        {:email, :eq, "john@example.com", [case_insensitive: true]},
        {:published, :eq, true, [binding: :posts]}
      ])

      # Mixed (3-tuples and 4-tuples)
      Query.wheres(token, [
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

  ## Examples

      # Match users who are active OR admins OR verified
      Query.where_any(token, [
        {:status, :eq, "active"},
        {:role, :eq, "admin"},
        {:verified, :eq, true}
      ])

      # With options
      Query.where_any(token, [
        {:email, :eq, "john@example.com", [case_insensitive: true]},
        {:username, :eq, "john", [case_insensitive: true]}
      ])

  ## SQL Equivalent

      WHERE (status = 'active' OR role = 'admin' OR verified = true)
  """
  @spec where_any(Token.t(), [
          {atom(), atom(), term()}
          | {atom(), atom(), term(), keyword()}
        ]) :: Token.t()
  def where_any(token, filter_list) when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = Enum.map(filter_list, &normalize_filter_spec/1)
    Token.add_operation(token, {:filter_group, {:or, normalized}})
  end

  @doc """
  Add an AND filter group - matches only if ALL conditions are true.

  This is semantically equivalent to multiple `where/5` calls, but groups
  the conditions explicitly for clarity.

  ## Parameters

  - `token` - The query token
  - `filter_list` - List of filter specifications (at least 2 required)

  ## Examples

      # Match users who are BOTH active AND verified
      Query.where_all(token, [
        {:status, :eq, "active"},
        {:verified, :eq, true}
      ])

  ## SQL Equivalent

      WHERE (status = 'active' AND verified = true)
  """
  @spec where_all(Token.t(), [
          {atom(), atom(), term()}
          | {atom(), atom(), term(), keyword()}
        ]) :: Token.t()
  def where_all(token, filter_list) when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = Enum.map(filter_list, &normalize_filter_spec/1)
    Token.add_operation(token, {:filter_group, {:and, normalized}})
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
        |> Query.new()
        |> Query.where(:post_id, :eq, some_post_id)

      Post
      |> Query.new()
      |> Query.exists(comments_subquery)

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
        |> Query.new()
        |> Query.where(:post_id, :eq, some_post_id)

      Post
      |> Query.new()
      |> Query.not_exists(comments_subquery)

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
      |> Query.new()
      |> Query.exclude_deleted()
      |> Query.execute()

      # With custom field name
      Post
      |> Query.new()
      |> Query.exclude_deleted(:removed_at)

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
      |> Query.new()
      |> Query.only_deleted()

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
        |> Query.new()
        |> Query.select([:user_id])

      User
      |> Query.new()
      |> Query.filter_subquery(:id, :in, purchaser_ids)

      # Find products not in any order
      ordered_product_ids = OrderItem
        |> Query.new()
        |> Query.select([:product_id])

      Product
      |> Query.new()
      |> Query.filter_subquery(:id, :not_in, ordered_product_ids)

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
      |> Query.new()
      |> Query.created_between(start_of_day, end_of_day)

      # With custom field
      Post
      |> Query.new()
      |> Query.created_between(start, finish, :published_at)

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
  Filter for records updated after a given time.

  Useful for sync operations or finding recently modified records.

  ## Examples

      # Find records updated in the last hour
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

      User
      |> Query.new()
      |> Query.updated_since(one_hour_ago)

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
      |> Query.new()
      |> Query.created_today()

      # Custom timestamp field
      Order
      |> Query.new()
      |> Query.created_today(:placed_at)
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
      |> Query.new()
      |> Query.updated_recently(2)

      # Custom field
      Product
      |> Query.new()
      |> Query.updated_recently(24, :last_synced_at)
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
      Query.with_status(token, "active")

      # Multiple statuses (IN query)
      Query.with_status(token, ["pending", "processing"])

      # Custom status field
      Query.with_status(token, "published", :state)
  """
  @spec with_status(Token.t(), String.t() | [String.t()], atom()) :: Token.t()
  def with_status(token, statuses, field \\ :status)

  def with_status(token, statuses, field) when is_list(statuses) do
    filter(token, field, :in, statuses)
  end

  def with_status(token, status, field) when is_binary(status) or is_atom(status) do
    filter(token, field, :eq, status)
  end

  # Normalize filter spec to 4-tuple format
  defp normalize_filter_spec({field, op, value}), do: {field, op, value, []}
  defp normalize_filter_spec({field, op, value, opts}), do: {field, op, value, opts}

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
      Query.paginate(token, :offset, limit: 20, offset: 40)

      # Cursor pagination
      Query.paginate(token, :cursor, cursor_fields: [:id], limit: 20, after: cursor)
  """
  @spec paginate(Token.t(), :offset | :cursor, keyword()) :: Token.t()
  def paginate(token, type, opts \\ []) do
    Token.add_operation(token, {:paginate, {type, opts}})
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
      Query.order_by(token, :name)

      # Single field - descending
      Query.order_by(token, :created_at, :desc)

      # Multiple fields at once (NEW!)
      Query.order_by(token, [{:priority, :desc}, {:created_at, :desc}, :id])

      # On joined table
      Query.order_by(token, :title, :asc, binding: :posts)

      # Multiple separate calls (chaining)
      token
      |> Query.order_by(:priority, :desc)
      |> Query.order_by(:created_at, :desc)
      |> Query.order_by(:id, :asc)
  """
  @spec order_by(Token.t(), atom() | list(), :asc | :desc, keyword()) :: Token.t()
  def order_by(token, field_or_list, direction \\ :asc, opts \\ [])

  # List form - delegate to order_bys
  def order_by(token, order_list, _direction, _opts) when is_list(order_list) do
    order_bys(token, order_list)
  end

  # Single field form
  def order_by(token, field, direction, opts) when is_atom(field) do
    Token.add_operation(token, {:order, {field, direction, opts}})
  end

  @doc """
  Alias for `order_by/4`. Semantic alternative name.

  Supports both single field and list syntax.

  See `order_by/4` for documentation.
  """
  @spec order(Token.t(), atom() | list(), :asc | :desc, keyword()) :: Token.t()
  def order(token, field_or_list, direction \\ :asc, opts \\ []) do
    order_by(token, field_or_list, direction, opts)
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
      Query.order_bys(token, [:name, :email, :id])

      # Ecto keyword syntax (NEW! - just like Ecto.Query)
      Query.order_bys(token, [asc: :name, desc: :created_at, asc: :id])
      Query.order_bys(token, [desc: :priority, desc_nulls_first: :score])

      # Tuple syntax (our original)
      Query.order_bys(token, [
        {:priority, :desc},
        {:created_at, :desc},
        {:id, :asc}
      ])

      # 3-tuples with options
      Query.order_bys(token, [
        {:priority, :desc, []},
        {:title, :asc, [binding: :posts]},
        {:id, :asc, []}
      ])

      # Mixed formats work too!
      Query.order_bys(token, [
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
      |> Query.join(:posts, :left, as: :user_posts)
      # Reference it with binding:
      |> Query.filter(:published, :eq, true, binding: :user_posts)
      |> Query.order(:created_at, :desc, binding: :user_posts)

  ## Examples

      # Association join (uses association as binding name)
      Query.join(token, :posts, :left)
      # Filter on it: Query.filter(token, :published, :eq, true, binding: :posts)

      # Named binding for clarity
      Query.join(token, :posts, :left, as: :user_posts)

      # Schema join with custom conditions
      Query.join(token, Post, :left, as: :posts, on: [author_id: :id])
  """
  @spec join(Token.t(), atom() | module(), atom(), keyword()) :: Token.t()
  def join(token, association_or_schema, type \\ :inner, opts \\ []) do
    Token.add_operation(token, {:join, {association_or_schema, type, opts}})
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
      Query.joins(token, [:posts, :comments])

      # List of 2-tuples with join types
      Query.joins(token, [
        {:posts, :left},
        {:comments, :inner}
      ])

      # List of 3-tuples with options
      Query.joins(token, [
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
      Query.preload(token, :posts)

      # Multiple associations
      Query.preload(token, [:posts, :comments])

      # Nested preload with filters (use preload/3)
      Query.preload(token, :posts, fn q ->
        q |> Query.filter(:published, :eq, true)
      end)
  """
  @spec preload(Token.t(), atom() | keyword() | list()) :: Token.t()
  def preload(token, associations) when is_atom(associations) do
    Token.add_operation(token, {:preload, associations})
  end

  def preload(token, associations) when is_list(associations) do
    Token.add_operation(token, {:preload, associations})
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
      Query.preload(token, :posts, fn q ->
        q
        |> Query.filter(:published, :eq, true)
        |> Query.order(:created_at, :desc)
        |> Query.limit(10)
      end)

      # Nested preloads with filters at each level
      Query.preload(token, :posts, fn q ->
        q
        |> Query.filter(:published, :eq, true)
        |> Query.preload(:comments, fn c ->
          c |> Query.filter(:approved, :eq, true)
        end)
      end)
  """
  @spec preload(Token.t(), atom(), (Token.t() -> Token.t())) :: Token.t()
  def preload(token, association, builder_fn) when is_function(builder_fn, 1) do
    nested_token = Token.new(:nested)
    nested_token = builder_fn.(nested_token)
    Token.add_operation(token, {:preload, {association, nested_token}})
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
      Query.select(token, [:id, :name, :price])

      # Select with aliases (same table)
      Query.select(token, %{
        product_id: :id,
        product_name: :name
      })

      # Select from base and joined tables
      Product
      |> Query.new()
      |> Query.join(:category, :left, as: :cat)
      |> Query.join(:brand, :left, as: :brand)
      |> Query.select(%{
        product_id: :id,
        product_name: :name,
        price: :price,
        category_id: {:cat, :id},
        category_name: {:cat, :name},
        brand_id: {:brand, :id},
        brand_name: {:brand, :name}
      })
      |> Query.execute()
  """
  @spec select(Token.t(), list() | map()) :: Token.t()
  def select(%Token{} = token, fields) when is_list(fields) or is_map(fields) do
    Token.add_operation(token, {:select, fields})
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
      |> Query.window(:running,
          partition_by: :category_id,
          order_by: [asc: :date],
          frame: {:rows, :unbounded_preceding, :current_row})

      # 3-row moving average
      token
      |> Query.window(:moving_avg,
          order_by: [asc: :date],
          frame: {:rows, {:preceding, 1}, {:following, 1}})

      # Range-based (value-based window)
      token
      |> Query.window(:price_range,
          order_by: [asc: :price],
          frame: {:range, {:preceding, 100}, {:following, 100}})

      # Without frame (default behavior)
      token
      |> Query.window(:price_rank, partition_by: :category_id, order_by: [desc: :price])

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
  @spec having(Token.t(), keyword()) :: Token.t()
  def having(token, conditions) do
    Token.add_operation(token, {:having, conditions})
  end

  @doc "Add a limit"
  @spec limit(Token.t(), pos_integer()) :: Token.t()
  def limit(token, value) do
    Token.add_operation(token, {:limit, value})
  end

  @doc "Add an offset"
  @spec offset(Token.t(), non_neg_integer()) :: Token.t()
  def offset(token, value) do
    Token.add_operation(token, {:offset, value})
  end

  @doc "Add distinct"
  @spec distinct(Token.t(), boolean() | list()) :: Token.t()
  def distinct(token, value) do
    Token.add_operation(token, {:distinct, value})
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
      base_query = Events.Query.new(User) |> Events.Query.filter(:active, :eq, true)

      Events.Query.new(Order)
      |> Events.Query.with_cte(:active_users, base_query)
      |> Events.Query.join(:active_users, :inner, on: [user_id: :id])

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
      |> Events.Query.new()
      |> Events.Query.with_cte(:category_tree, cte_query, recursive: true)
      |> Events.Query.execute()

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

  @doc """
  Add raw SQL fragment.

  Supports named placeholders:

  ## Example

      Events.Query.new(User)
      |> Events.Query.raw_where("age BETWEEN :min_age AND :max_age", %{min_age: 18, max_age: 65})
  """
  @spec raw_where(Token.t(), String.t(), map()) :: Token.t()
  def raw_where(token, sql, params \\ %{}) do
    Token.add_operation(token, {:raw_where, {sql, params}})
  end

  @doc """
  Include a query fragment's operations in the current token.

  Fragments are reusable query components defined with `Events.Query.Fragment`.

  ## Example

      defmodule MyApp.QueryFragments do
        use Events.Query.Fragment

        defragment :active_users do
          filter :status, :eq, "active"
          filter :verified, :eq, true
        end
      end

      # Include in query
      User
      |> Query.new()
      |> Query.include(MyApp.QueryFragments.active_users())
      |> Query.execute()
  """
  @spec include(Token.t(), Token.t()) :: Token.t()
  defdelegate include(token, fragment), to: Events.Query.Fragment

  @doc """
  Conditionally include a query fragment.

  ## Example

      User
      |> Query.new()
      |> Query.include_if(user_params[:show_active], MyApp.QueryFragments.active_users())
      |> Query.execute()
  """
  @spec include_if(Token.t(), boolean(), Token.t() | nil) :: Token.t()
  defdelegate include_if(token, condition, fragment), to: Events.Query.Fragment

  @doc """
  Convert token to a subquery.

  Wraps the query in an Ecto subquery for use in FROM, JOIN, WHERE, or SELECT clauses.

  ## Examples

      # Subquery in FROM
      subset = Query.new(Post) |> Query.where(:status, :eq, "draft")
      Query.from_subquery(subset) |> Query.where(:created_at, :gt, yesterday)

      # Subquery in WHERE with :in_subquery operator
      user_ids = Query.new(User) |> Query.where(:active, :eq, true) |> Query.select([:id])
      Query.new(Post) |> Query.where(:user_id, :in_subquery, user_ids)
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

      case Query.build_safe(token) do
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
  Execute the query and return result or error tuple.

  Returns `{:ok, result}` on success or `{:error, error}` on failure.
  This is the safe variant that never raises exceptions.

  For the raising variant, use `execute!/2`.

  ## Automatic Safety Limits

  **Important**: Queries without pagination or explicit limits are automatically
  limited to prevent unbounded result sets. The default safe limit is 20 records.

  To customize this behavior:
  - Add pagination: `Query.paginate(token, :cursor, limit: 50)`
  - Add explicit limit: `Query.limit(token, 100)`
  - Use streaming: `Query.stream(token)` for large datasets
  - Disable safety: Pass `unsafe: true` option (not recommended)

  ## Options

  - `:repo` - Repo module (default: `Events.Repo`)
  - `:timeout` - Query timeout in ms (default: 15_000)
  - `:telemetry` - Enable telemetry (default: true)
  - `:cache` - Enable caching (default: false)
  - `:cache_ttl` - Cache TTL in seconds (default: 60)
  - `:include_total_count` - Include total count in pagination (default: false)
  - `:unsafe` - Disable automatic safety limits (default: false, not recommended)
  - `:default_limit` - Override default safe limit (default: 20)

  ## Examples

      # With pattern matching
      case token |> Events.Query.execute() do
        {:ok, result} ->
          IO.puts("Got \#{length(result.data)} records")
        {:error, error} ->
          Logger.error("Query failed: \#{Exception.message(error)}")
      end

      # With options
      {:ok, result} = token |> Events.Query.execute(
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
      result = token |> Events.Query.execute!()

      # With options
      result = token |> Events.Query.execute!(
        timeout: 30_000,
        include_total_count: true
      )
  """
  @spec execute!(Token.t(), keyword()) :: Result.t()
  defdelegate execute!(token, opts \\ []), to: Executor

  @doc "Execute and return stream"
  @spec stream(Token.t(), keyword()) :: Enumerable.t()
  defdelegate stream(token, opts \\ []), to: Executor

  ## Cursor Utilities

  @doc """
  Encode a cursor from a record for cursor-based pagination.

  Useful for testing and manually creating cursors.

  ## Examples

      # Simple cursor
      cursor = Query.encode_cursor(%{id: 123}, [:id])

      # Multi-field cursor
      cursor = Query.encode_cursor(
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

      {:ok, data} = Query.decode_cursor(cursor_string)
      # => %{id: 123}

      {:error, reason} = Query.decode_cursor("invalid")
  """
  @spec decode_cursor(String.t() | any()) :: {:ok, map()} | {:error, String.t()}
  defdelegate decode_cursor(encoded), to: Builder

  @doc """
  Execute query in a transaction.

  ## Example

      Events.Query.transaction(fn ->
        user = User |> Events.Query.new() |> Events.Query.filter(:id, :eq, 1) |> Events.Query.execute()
        # ... more operations
        {:ok, user}
      end)
  """
  @spec transaction((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction(fun, opts \\ []) do
    repo = opts[:repo] || Events.Repo
    repo.transaction(fun, opts)
  end

  @doc """
  Execute multiple queries in a batch.

  Returns list of results in the same order as tokens.

  ## Example

      tokens = [
        User |> Events.Query.new() |> Events.Query.filter(:active, :eq, true),
        Post |> Events.Query.new() |> Events.Query.limit(10)
      ]

      [users_result, posts_result] = Events.Query.batch(tokens)
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
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.order(:created_at, :asc)
      |> Query.first()
      # => %User{...} or nil

      # With options
      Query.first(token, repo: MyApp.Repo)
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
      |> Query.new()
      |> Query.filter(:id, :eq, 123)
      |> Query.first!()
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
      |> Query.new()
      |> Query.filter(:email, :eq, "john@example.com")
      |> Query.one()
      # => %User{...} or nil

      # Raises if more than one result
      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.one()
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
      [_ | _] -> raise Ecto.MultipleResultsError, queryable: build(token)
    end
  end

  @doc """
  Get exactly one result, raising if zero or more than one.

  ## Examples

      User
      |> Query.new()
      |> Query.filter(:email, :eq, "john@example.com")
      |> Query.one!()
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
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.count()
      # => 42
  """
  @spec count(Token.t(), keyword()) :: non_neg_integer()
  def count(%Token{} = token, opts \\ []) do
    repo = opts[:repo] || Events.Repo
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
      |> Query.new()
      |> Query.filter(:email, :eq, "john@example.com")
      |> Query.exists?()
      # => true or false
  """
  @spec exists?(Token.t(), keyword()) :: boolean()
  def exists?(%Token{} = token, opts \\ []) do
    repo = opts[:repo] || Events.Repo
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
      |> Query.new()
      |> Query.filter(:status, :eq, "completed")
      |> Query.aggregate(:sum, :amount)
      # => Decimal.new("12345.67")

      # Average age
      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.aggregate(:avg, :age)
      # => 32.5

      # Count with field (non-null values)
      User
      |> Query.new()
      |> Query.aggregate(:count, :email)
      # => 100
  """
  @spec aggregate(Token.t(), :count | :sum | :avg | :min | :max, atom(), keyword()) :: term()
  def aggregate(%Token{} = token, aggregate_type, field, opts \\ [])
      when aggregate_type in [:count, :sum, :avg, :min, :max] do
    repo = opts[:repo] || Events.Repo
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
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.all()
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
      |> Query.remove_operations(:order)
      |> Query.remove_operations(:select)
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
      |> Query.new()
      |> Query.then_if(params[:status], fn token, status ->
        Query.filter(token, :status, :eq, status)
      end)
      |> Query.then_if(params[:min_age], fn token, age ->
        Query.filter(token, :age, :gte, age)
      end)
      |> Query.execute()
  """
  @spec then_if(Token.t(), term(), (Token.t(), term() -> Token.t())) :: Token.t()
  def then_if(%Token{} = token, nil, _fun), do: token
  def then_if(%Token{} = token, false, _fun), do: token
  def then_if(%Token{} = token, value, fun), do: fun.(token, value)

  @doc """
  Conditionally apply a function to the token (boolean version).

  ## Examples

      User
      |> Query.new()
      |> Query.if_true(show_active?, fn token ->
        Query.filter(token, :status, :eq, "active")
      end)
      |> Query.execute()
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
      Query.filter_by(token, params)

      # With explicit operators
      filters = %{
        status: "active",                          # :eq by default
        price: {:between, {10, 100}},              # price BETWEEN 10 AND 100
        category_id: {:in, [1, 2, 3]},             # category_id IN (1, 2, 3)
        rating: {:gte, 4},                         # rating >= 4
        name: {:ilike, "%phone%"},                 # name ILIKE '%phone%'
        deleted_at: {:is_nil, true}                # deleted_at IS NULL
      }
      Query.filter_by(token, filters)

      # JSONB queries
      filters = %{
        metadata: {:jsonb_contains, %{verified: true}},
        settings: {:jsonb_has_key, "theme"}
      }
      Query.filter_by(token, filters)

      # Fuzzy matching (requires pg_trgm extension)
      filters = %{
        name: {:similarity, "john", threshold: 0.4}
      }
      Query.filter_by(token, filters)

      # With binding for joined tables
      token
      |> Query.join(:category, :left, as: :cat)
      |> Query.filter_by(%{
        status: "active",
        name: {:eq, "Electronics", binding: :cat}
      })

      # Nil values are skipped (useful with params)
      params = %{status: "active", search: nil}  # search is skipped
      Query.filter_by(token, params)
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
      Query.search(token, "iphone", [:name, :description, :sku])

      # E-commerce search with ranking (best matches first)
      Query.search(token, "wireless headphones", [
        {:sku, :exact, rank: 1, take: 3},           # Exact SKU matches first
        {:name, :similarity, rank: 2, take: 10},    # Fuzzy name matches
        {:brand, :ilike, rank: 3, take: 5},         # Brand contains term
        {:description, :ilike, rank: 4, take: 5}    # Description matches
      ], rank: true)
      # Returns up to 23 results, ordered by relevance rank

      # Cross-table search with joins
      token
      |> Query.join(:brand, :left, as: :brand)
      |> Query.search("apple", [
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
      Query.search(token, "iphone", [:name, :description, :sku])

      # Per-field modes: different search strategy per field
      Query.search(token, "iphone", [
        {:sku, :exact},                              # Exact match on SKU
        {:name, :similarity},                        # Fuzzy match on name
        {:description, :ilike}                       # ILIKE on description
      ])

      # WITH RANKING: Results ordered by which field matched
      Query.search(token, "iphone", [
        {:sku, :exact, rank: 1},                     # Highest priority - exact SKU
        {:name, :similarity, rank: 2},               # Second - fuzzy name match
        {:brand, :starts_with, rank: 3},             # Third - brand prefix
        {:description, :ilike, rank: 4}              # Lowest - description contains
      ], rank: true)

      # E-commerce search with ranking
      Query.search(token, params[:q], [
        {:sku, :exact, rank: 1},                     # SKU-123 exact = top result
        {:name, :similarity, rank: 2, threshold: 0.3},
        {:brand, :starts_with, rank: 3},
        {:description, :word_similarity, rank: 4}
      ], rank: true)

      # WITH TAKE LIMITS: Control how many results from each field/rank
      Query.search(token, "iphone", [
        {:email, :exact, rank: 1, take: 5},          # Top 5 exact email matches
        {:name, :similarity, rank: 2, take: 10},     # Then 10 fuzzy name matches
        {:description, :ilike, rank: 3, take: 5}     # Then 5 description matches
      ], rank: true)
      # Total results: up to 20 (5 from email + 10 from name + 5 from description)
      # Results ordered by rank, then by relevance within each rank

      # Autocomplete with ranking (exact prefix > fuzzy)
      Query.search(token, input, [
        {:name, :starts_with, rank: 1, take: 5},     # Top 5 prefix matches
        {:name, :similarity, rank: 2, take: 10}      # Then 10 fuzzy matches
      ], rank: true)

      # Returns unchanged token if search term is nil or empty
      Query.search(token, nil, [:name])  # => token unchanged

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
  Query.search(token, "iphone", [
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
  def search(token, term, fields, opts \\ [])
  def search(%Token{} = token, nil, _fields, _opts), do: token
  def search(%Token{} = token, "", _fields, _opts), do: token

  def search(%Token{} = token, term, fields, opts) when is_binary(term) and is_list(fields) do
    default_mode = Keyword.get(opts, :mode, :ilike)
    default_threshold = Keyword.get(opts, :threshold, 0.3)
    enable_ranking = Keyword.get(opts, :rank, false)

    # Parse field specs and assign auto-ranks if not specified
    # Returns: [{field, mode, opts, rank, take}, ...]
    parsed_fields = parse_search_fields(fields, default_mode, default_threshold)

    # Build search filters
    search_filters =
      Enum.map(parsed_fields, fn {field, mode, field_opts, _rank, _take} ->
        build_search_filter_tuple(field, mode, term, field_opts)
      end)

    # Apply the OR filter
    token = where_any(token, search_filters)

    # Apply ranking if enabled
    if enable_ranking do
      apply_search_ranking(token, parsed_fields, term)
    else
      token
    end
  end

  # Parse field specifications into normalized format with ranks and take limits
  # Returns: {field, mode, opts, rank, take}
  defp parse_search_fields(fields, default_mode, default_threshold) do
    fields
    |> Enum.with_index(1)
    |> Enum.map(fn {field_spec, index} ->
      parse_single_field(field_spec, default_mode, default_threshold, index)
    end)
  end

  defp parse_single_field(field, default_mode, default_threshold, auto_rank) when is_atom(field) do
    {field, default_mode, [threshold: default_threshold], auto_rank, nil}
  end

  defp parse_single_field({field, mode}, _default_mode, default_threshold, auto_rank) do
    {field, mode, [threshold: default_threshold], auto_rank, nil}
  end

  defp parse_single_field({field, mode, opts}, _default_mode, default_threshold, auto_rank) do
    rank = Keyword.get(opts, :rank, auto_rank)
    threshold = Keyword.get(opts, :threshold, default_threshold)
    take = Keyword.get(opts, :take)
    {field, mode, Keyword.merge(opts, threshold: threshold), rank, take}
  end

  # Build filter tuple for a field (with binding support for joined tables)
  defp build_search_filter_tuple(field, mode, term, field_opts) do
    binding = Keyword.get(field_opts, :binding)
    base_opts = if binding, do: [binding: binding], else: []

    case mode do
      :ilike ->
        pattern = build_search_pattern(term, :contains)
        build_filter_with_opts(field, :ilike, pattern, base_opts)

      :like ->
        pattern = build_search_pattern(term, :contains)
        build_filter_with_opts(field, :like, pattern, base_opts)

      :starts_with ->
        pattern = build_search_pattern(term, :starts_with)
        case_sensitive = Keyword.get(field_opts, :case_sensitive, false)
        op = if case_sensitive, do: :like, else: :ilike
        build_filter_with_opts(field, op, pattern, base_opts)

      :ends_with ->
        pattern = build_search_pattern(term, :ends_with)
        case_sensitive = Keyword.get(field_opts, :case_sensitive, false)
        op = if case_sensitive, do: :like, else: :ilike
        build_filter_with_opts(field, op, pattern, base_opts)

      :contains ->
        pattern = build_search_pattern(term, :contains)
        case_sensitive = Keyword.get(field_opts, :case_sensitive, false)
        op = if case_sensitive, do: :like, else: :ilike
        build_filter_with_opts(field, op, pattern, base_opts)

      :exact ->
        build_filter_with_opts(field, :eq, term, base_opts)

      similarity_mode
      when similarity_mode in [:similarity, :word_similarity, :strict_word_similarity] ->
        threshold = Keyword.get(field_opts, :threshold, 0.3)
        opts = Keyword.merge(base_opts, threshold: threshold)
        {field, similarity_mode, term, opts}

      unknown ->
        raise ArgumentError, """
        Unknown search mode: #{inspect(unknown)} for field #{inspect(field)}

        Supported modes:
          :ilike, :like, :exact, :starts_with, :ends_with, :contains,
          :similarity, :word_similarity, :strict_word_similarity
        """
    end
  end

  # Build filter tuple with optional opts
  defp build_filter_with_opts(field, op, value, []), do: {field, op, value}
  defp build_filter_with_opts(field, op, value, opts), do: {field, op, value, opts}

  # Apply search ranking via ORDER BY
  # If any field has a :take limit, use the limited ranking operation
  defp apply_search_ranking(token, parsed_fields, term) do
    # Sort by rank to build CASE WHEN in priority order
    sorted_fields = Enum.sort_by(parsed_fields, fn {_, _, _, rank, _take} -> rank end)

    # Check if any field has a take limit
    has_take_limits = Enum.any?(sorted_fields, fn {_, _, _, _rank, take} -> take != nil end)

    if has_take_limits do
      # Use limited ranking with ROW_NUMBER OVER PARTITION BY
      Token.add_operation(token, {:search_rank_limited, {sorted_fields, term}})
    else
      # Simple ranking with ORDER BY
      Token.add_operation(token, {:search_rank, {sorted_fields, term}})
    end
  end

  defp build_search_pattern(term, :contains), do: "%#{term}%"
  defp build_search_pattern(term, :starts_with), do: "#{term}%"
  defp build_search_pattern(term, :ends_with), do: "%#{term}"
end
