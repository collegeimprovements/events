defmodule Events.Query do
  @moduledoc """
  Production-grade query builder with token pattern and pipelines.

  ## Features

  - Token-based composition with pattern matching
  - Protocol-based operations for extensibility
  - Cursor and offset pagination with metadata
  - Nested filters and preloads
  - Custom joins with conditions
  - Transactions, batching, CTEs, subqueries
  - Named SQL placeholders
  - Telemetry integration
  - Comprehensive result metadata

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
  """

  alias Events.Query.{Token, Builder, Executor, Result}

  # Re-export key types
  @type t :: Token.t()

  ## Public API

  @doc "Create a new query token from a schema"
  @spec new(module() | Ecto.Query.t()) :: Token.t()
  defdelegate new(schema_or_query), to: Token

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

  @doc "Add a join"
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

  @doc "Add a preload (single association or list)"
  @spec preload(Token.t(), atom() | keyword()) :: Token.t()
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

  @doc "Add nested preload with filters"
  @spec preload(Token.t(), atom(), (Token.t() -> Token.t())) :: Token.t()
  def preload(token, association, builder_fn) when is_function(builder_fn, 1) do
    nested_token = Token.new(:nested)
    nested_token = builder_fn.(nested_token)
    Token.add_operation(token, {:preload, {association, nested_token}})
  end

  @doc "Add a select clause"
  @spec select(Token.t(), list() | map()) :: Token.t()
  def select(token, fields) do
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
end
