defmodule OmQuery.Guide do
  @moduledoc false
  # Reference guide module - not part of public API.
  # This module contains comprehensive documentation for OmQuery.
  # The content below is kept as a large @doc for reference purposes.

  @doc ~S"""
  # OmQuery - Comprehensive Reference Guide

  A production-grade, composable query builder for Ecto with a focus on
  simplicity, consistency, composability, and safety.

  ## Design Philosophy

  - SQL: Familiar declarative syntax
  - PRQL: Pipeline composition and transforms
  - Functional Programming: Immutable tokens, pure transformations
  - Elixir: Pattern matching, explicit > implicit, pipelines

  ## Core Concepts - Token Pattern

  Queries are built by composing operations on an immutable Token:

  ```elixir
  # Each function returns a new Token (immutable)
  User
  |> OmQuery.new()                          # Create token
  |> OmQuery.filter(:status, :eq, "active") # Add filter
  |> OmQuery.order(:created_at, :desc)      # Add ordering
  |> OmQuery.paginate(:cursor, limit: 20)   # Add pagination
  |> OmQuery.execute()                      # Execute and get Result
  ```

  ### Result Structure

  All queries return a structured Result:

  ```elixir
  %OmQuery.Result{
    data: [...],                    # The query results
    pagination: %{                  # Pagination metadata
      type: :cursor,
      limit: 20,
      has_more: true,
      end_cursor: "abc123..."
    },
    metadata: %{                    # Query metadata
      query_time_μs: 1234,
      sql: "SELECT ...",
      operation_count: 3
    }
  }
  ```

  ---

  ## Quick Start Examples

  ### Basic Query

  ```elixir
  alias OmQuery

  # Simple filtered query
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.execute()

  # Multiple filters (AND)
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.filter(:age, :gte, 18)
  |> OmQuery.filter(:verified, :eq, true)
  |> OmQuery.execute()
  ```

  ### Using the DSL

  ```elixir
  import OmQuery.DSL

  query User do
    filter :status, :eq, "active"
    filter :age, :gte, 18
    order :created_at, :desc
    paginate :offset, limit: 20
  end
  |> execute()
  ```

  ---

  ## Filtering

  ### Basic Operators

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:eq` | `=` | `filter(:status, :eq, "active")` |
  | `:neq` | `!=` | `filter(:status, :neq, "deleted")` |
  | `:gt` | `>` | `filter(:age, :gt, 18)` |
  | `:gte` | `>=` | `filter(:age, :gte, 18)` |
  | `:lt` | `<` | `filter(:age, :lt, 65)` |
  | `:lte` | `<=` | `filter(:age, :lte, 65)` |

  ```elixir
  # Equality
  OmQuery.filter(token, :status, :eq, "active")

  # Comparison
  OmQuery.filter(token, :created_at, :gte, ~U[2024-01-01 00:00:00Z])
  OmQuery.filter(token, :amount, :lt, Decimal.new("100.00"))
  ```

  ### List Operators

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:in` | `IN (...)` | `filter(:status, :in, ["active", "pending"])` |
  | `:not_in` | `NOT IN (...)` | `filter(:role, :not_in, ["banned"])` |

  ```elixir
  # In list
  OmQuery.filter(token, :status, :in, ["active", "pending", "reviewing"])

  # Not in list
  OmQuery.filter(token, :role, :not_in, ["banned", "suspended"])
  ```

  ### Pattern Matching

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:like` | `LIKE` | `filter(:name, :like, "%john%")` |
  | `:ilike` | `ILIKE` | `filter(:email, :ilike, "%@gmail.com")` |

  ```elixir
  # Case-sensitive pattern
  OmQuery.filter(token, :name, :like, "John%")

  # Case-insensitive pattern (PostgreSQL)
  OmQuery.filter(token, :email, :ilike, "%@gmail.com")
  ```

  ### NULL Checks

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:is_nil` | `IS NULL` | `filter(:deleted_at, :is_nil, true)` |
  | `:not_nil` | `IS NOT NULL` | `filter(:email, :not_nil, true)` |

  ```elixir
  # Find soft-deleted records
  OmQuery.filter(token, :deleted_at, :not_nil, true)

  # Find records without email
  OmQuery.filter(token, :email, :is_nil, true)
  ```

  ### Range Queries

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:between` | `BETWEEN ... AND ...` | `filter(:age, :between, {18, 65})` |

  ```elixir
  # Age between 18 and 65
  OmQuery.filter(token, :age, :between, {18, 65})

  # Date range
  OmQuery.filter(token, :created_at, :between, {start_date, end_date})
  ```

  ### Array Operators (PostgreSQL)

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:contains` | `@>` | `filter(:tags, :contains, ["elixir"])` |

  ```elixir
  # Find posts tagged with "elixir"
  OmQuery.filter(token, :tags, :contains, ["elixir"])
  ```

  ### JSONB Operators (PostgreSQL)

  | Operator | SQL | Example |
  |----------|-----|---------|
  | `:jsonb_contains` | `@>` | `filter(:meta, :jsonb_contains, %{vip: true})` |
  | `:jsonb_has_key` | `?` | `filter(:meta, :jsonb_has_key, "role")` |

  ```elixir
  # Find users with VIP metadata
  OmQuery.filter(token, :metadata, :jsonb_contains, %{vip: true})

  # Find users with role in metadata
  OmQuery.filter(token, :metadata, :jsonb_has_key, "role")
  ```

  ### Case-Insensitive Equality

  ```elixir
  # Case-insensitive email match
  OmQuery.filter(token, :email, :eq, "John@Example.com", case_insensitive: true)
  ```

  ### Multiple Filters at Once

  ```elixir
  # Using filters/2
  OmQuery.filters(token, [
    {:status, :eq, "active"},
    {:age, :gte, 18},
    {:verified, :eq, true}
  ])

  # Using filter_by/2 (equality only)
  OmQuery.filter_by(token, %{status: "active", role: "admin"})
  ```

  ---

  ## OR / AND Groups

  ### OR Conditions (where_any)

  Match if ANY condition is true:

  ```elixir
  # Find users who are active OR admins OR verified
  OmQuery.where_any(token, [
    {:status, :eq, "active"},
    {:role, :eq, "admin"},
    {:verified, :eq, true}
  ])
  # SQL: WHERE (status = 'active' OR role = 'admin' OR verified = true)
  ```

  ### AND Conditions (where_all)

  Match if ALL conditions are true (same as multiple filters):

  ```elixir
  # Find users who are active AND verified
  OmQuery.where_all(token, [
    {:status, :eq, "active"},
    {:verified, :eq, true}
  ])
  # SQL: WHERE (status = 'active' AND verified = true)
  ```

  ### Complex Boolean Logic

  ```elixir
  # (active OR admin) AND (age >= 18)
  User
  |> OmQuery.new()
  |> OmQuery.where_any([
    {:status, :eq, "active"},
    {:role, :eq, "admin"}
  ])
  |> OmQuery.filter(:age, :gte, 18)
  |> OmQuery.execute()
  ```

  ---

  ## Ordering

  ### Single Field

  ```elixir
  # Ascending (default)
  OmQuery.order(token, :name)
  OmQuery.order(token, :name, :asc)

  # Descending
  OmQuery.order(token, :created_at, :desc)
  ```

  ### Multiple Fields

  ```elixir
  # Using orders/2 with Ecto keyword syntax
  OmQuery.orders(token, [desc: :priority, asc: :created_at, asc: :id])

  # Using orders/2 with tuple syntax
  OmQuery.orders(token, [
    {:priority, :desc},
    {:created_at, :asc},
    {:id, :asc}
  ])

  # Chaining
  token
  |> OmQuery.order(:priority, :desc)
  |> OmQuery.order(:created_at, :asc)
  |> OmQuery.order(:id, :asc)
  ```

  ### Null Positioning

  ```elixir
  # Nulls first
  OmQuery.order(token, :score, :desc_nulls_first)

  # Nulls last
  OmQuery.order(token, :score, :asc_nulls_last)
  ```

  Available directions: `:asc`, `:desc`, `:asc_nulls_first`, `:asc_nulls_last`,
  `:desc_nulls_first`, `:desc_nulls_last`

  ---

  ## Pagination

  ### Offset Pagination

  Traditional page-based pagination. Good for random access, simple to implement.

  ```elixir
  # Page 1
  OmQuery.paginate(token, :offset, limit: 20)

  # Page 3 (items 41-60)
  OmQuery.paginate(token, :offset, limit: 20, offset: 40)
  ```

  Result includes:

  ```elixir
  %{
    pagination: %{
      type: :offset,
      limit: 20,
      offset: 40,
      has_more: true,
      has_previous: true,
      current_page: 3,
      next_offset: 60,
      prev_offset: 20
    }
  }
  ```

  ### Cursor Pagination

  Keyset-based pagination. Better for stability, handles real-time data.

  ```elixir
  # First page
  token
  |> OmQuery.order(:created_at, :desc)
  |> OmQuery.order(:id, :asc)
  |> OmQuery.paginate(:cursor, limit: 20)
  |> OmQuery.execute()

  # Next page (using cursor from previous result)
  token
  |> OmQuery.order(:created_at, :desc)
  |> OmQuery.order(:id, :asc)
  |> OmQuery.paginate(:cursor, limit: 20, after: result.pagination.end_cursor)
  |> OmQuery.execute()
  ```

  Result includes:

  ```elixir
  %{
    pagination: %{
      type: :cursor,
      limit: 20,
      has_more: true,
      start_cursor: "abc...",
      end_cursor: "xyz..."
    }
  }
  ```

  ### Cursor Field Inference

  Cursor fields are automatically inferred from order_by:

  ```elixir
  # Cursor fields inferred as [{:created_at, :desc}, {:id, :asc}]
  token
  |> OmQuery.order(:created_at, :desc)
  |> OmQuery.order(:id, :asc)
  |> OmQuery.paginate(:cursor, limit: 20)
  ```

  ---

  ## Joins

  ### Association Joins

  ```elixir
  # Inner join (default)
  OmQuery.join(token, :posts)

  # Left join
  OmQuery.join(token, :posts, :left)

  # With binding name
  OmQuery.join(token, :posts, :left, as: :user_posts)
  ```

  ### Multiple Joins

  ```elixir
  OmQuery.joins(token, [
    :profile,
    {:posts, :left},
    {:comments, :left}
  ])
  ```

  ### Filtering on Joined Tables

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.join(:posts, :left, as: :posts)
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.filter(:published, :eq, true, binding: :posts)
  |> OmQuery.execute()
  ```

  ---

  ## Preloading

  ### Simple Preloads

  ```elixir
  # Single association
  OmQuery.preload(token, :posts)

  # Multiple associations
  OmQuery.preload(token, [:posts, :comments, :profile])
  ```

  ### Nested Preloads with Filters

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.preload(:posts, fn nested ->
    nested
    |> OmQuery.filter(:published, :eq, true)
    |> OmQuery.order(:created_at, :desc)
    |> OmQuery.limit(5)
  end)
  |> OmQuery.execute()
  ```

  ---

  ## Selection

  ### Select Specific Fields

  ```elixir
  # List of fields
  OmQuery.select(token, [:id, :name, :email])

  # Returns: %{id: 1, name: "John", email: "john@example.com"}
  ```

  ### Select with Mapping

  ```elixir
  OmQuery.select(token, %{
    user_id: :id,
    full_name: :name,
    contact_email: :email
  })
  ```

  ---

  ## Aggregations

  ### Group By with Having

  ```elixir
  Order
  |> OmQuery.new()
  |> OmQuery.select([:customer_id])
  |> OmQuery.group_by(:customer_id)
  |> OmQuery.having(count: {:gt, 5})
  |> OmQuery.execute()
  ```

  ### Aggregate Functions

  ```elixir
  # Count
  OmQuery.count(token)

  # Sum
  OmQuery.aggregate(token, :sum, :amount)

  # Average
  OmQuery.aggregate(token, :avg, :age)

  # Min/Max
  OmQuery.aggregate(token, :min, :price)
  OmQuery.aggregate(token, :max, :price)
  ```

  ---

  ## Convenience Functions

  ### first/1 - Get First Result

  ```elixir
  # Returns first record or nil
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.order(:created_at, :asc)
  |> OmQuery.first()
  # => %User{} or nil

  # Raises if no result
  OmQuery.first!(token)
  ```

  ### one/1 - Get Exactly One

  ```elixir
  # Returns single record or nil
  # Raises if more than one match
  User
  |> OmQuery.new()
  |> OmQuery.filter(:email, :eq, "john@example.com")
  |> OmQuery.one()
  # => %User{} or nil

  # Raises if no result or multiple
  OmQuery.one!(token)
  ```

  ### count/1 - Count Records

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.count()
  # => 42
  ```

  ### exists?/1 - Check Existence

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.filter(:email, :eq, "john@example.com")
  |> OmQuery.exists?()
  # => true or false
  ```

  ### all/1 - Get All as List

  ```elixir
  # Returns plain list without Result wrapper
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.all()
  # => [%User{}, %User{}, ...]
  ```

  ---

  ## Conditional Queries

  ### then_if/3 - Apply if Value Present

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.then_if(params[:status], fn token, status ->
    OmQuery.filter(token, :status, :eq, status)
  end)
  |> OmQuery.then_if(params[:min_age], fn token, age ->
    OmQuery.filter(token, :age, :gte, age)
  end)
  |> OmQuery.execute()
  ```

  ### if_true/3 - Apply if Boolean True

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.if_true(show_active_only?, fn token ->
    OmQuery.filter(token, :status, :eq, "active")
  end)
  |> OmQuery.execute()
  ```

  ### filter_by/2 - Filter from Map

  ```elixir
  params = %{status: "active", role: "admin", deleted: nil}

  User
  |> OmQuery.new()
  |> OmQuery.filter_by(params)  # nil values are ignored
  |> OmQuery.execute()
  # Applies: status = 'active' AND role = 'admin'
  ```

  ---

  ## Fragments (Reusable Query Components)

  ### Function-Based Fragments (Recommended)

  ```elixir
  defmodule MyApp.QueryFragments do
    alias OmQuery

    def active_users do
      OmQuery.Token.new(:nested)
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.filter(:verified, :eq, true)
    end

    def by_status(status \\\\ "active") do
      OmQuery.Token.new(:nested)
      |> OmQuery.filter(:status, :eq, status)
    end

    def recent_first do
      OmQuery.Token.new(:nested)
      |> OmQuery.order(:created_at, :desc)
    end

    def paginated(page \\\\ 1, per_page \\\\ 20) do
      offset = (page - 1) * per_page

      OmQuery.Token.new(:nested)
      |> OmQuery.paginate(:offset, limit: per_page, offset: offset)
    end
  end
  ```

  ### Using Fragments

  ```elixir
  alias MyApp.QueryFragments

  User
  |> OmQuery.new()
  |> OmQuery.include(QueryFragments.active_users())
  |> OmQuery.include(QueryFragments.recent_first())
  |> OmQuery.include(QueryFragments.paginated(2, 10))
  |> OmQuery.execute()
  ```

  ### Macro-Based Fragments

  ```elixir
  defmodule MyApp.QueryFragments do
    use OmQuery.Fragment

    defragment :active_users do
      filter :status, :eq, "active"
      filter :verified, :eq, true
    end

    defragment :by_status, [status: "active"] do
      filter :status, :eq, params[:status]
    end

    defragment :paginated, [page: 1, per_page: 20] do
      offset = (params[:page] - 1) * params[:per_page]
      paginate :offset, limit: params[:per_page], offset: offset
    end
  end
  ```

  ### Conditional Fragment Inclusion

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.include_if(params[:active_only], QueryFragments.active_users())
  |> OmQuery.execute()
  ```

  ### Fragment Composition

  ```elixir
  alias OmQuery.Fragment

  # Compose multiple fragments
  combined = Fragment.compose([
    QueryFragments.active_users(),
    QueryFragments.recent_first(),
    QueryFragments.paginated()
  ])

  OmQuery.include(token, combined)
  ```

  ---

  ## Subqueries

  ### IN Subquery

  ```elixir
  # Find posts by active users
  active_user_ids = User
    |> OmQuery.new()
    |> OmQuery.filter(:status, :eq, "active")
    |> OmQuery.select([:id])

  Post
  |> OmQuery.new()
  |> OmQuery.filter(:user_id, :in_subquery, active_user_ids)
  |> OmQuery.execute()
  ```

  ### NOT IN Subquery

  ```elixir
  Post
  |> OmQuery.new()
  |> OmQuery.filter(:user_id, :not_in_subquery, banned_user_ids)
  |> OmQuery.execute()
  ```

  ### EXISTS Subquery

  ```elixir
  # Find users who have posts
  posts_subquery = Post
    |> OmQuery.new()
    |> OmQuery.filter(:published, :eq, true)

  User
  |> OmQuery.new()
  |> OmQuery.exists(posts_subquery)
  |> OmQuery.execute()
  ```

  ### NOT EXISTS Subquery

  ```elixir
  # Find users without posts
  OmQuery.not_exists(token, posts_subquery)
  ```

  ---

  ## CTEs (Common Table Expressions)

  ### Simple CTE

  ```elixir
  active_users = User
    |> OmQuery.new()
    |> OmQuery.filter(:status, :eq, "active")

  Order
  |> OmQuery.new()
  |> OmQuery.with_cte(:active_users, active_users)
  |> OmQuery.join(:active_users, :inner, on: [user_id: :id])
  |> OmQuery.execute()
  ```

  ### Recursive CTE

  ```elixir
  import Ecto.Query

  # Build recursive CTE for hierarchical data
  base = from(c in "categories",
    where: is_nil(c.parent_id),
    select: %{id: c.id, name: c.name, depth: 0}
  )

  recursive = from(c in "categories",
    join: tree in "category_tree", on: c.parent_id == tree.id,
    select: %{id: c.id, name: c.name, depth: tree.depth + 1}
  )

  cte_query = union_all(base, ^recursive)

  from(c in "category_tree")
  |> OmQuery.new()
  |> OmQuery.with_cte(:category_tree, cte_query, recursive: true)
  |> OmQuery.execute()
  ```

  ---

  ## Raw SQL

  ### Raw WHERE Clause

  ```elixir
  # With named parameters
  OmQuery.raw_where(token, "age BETWEEN :min AND :max", %{min: 18, max: 65})

  # Complex expressions
  OmQuery.raw_where(token, "EXTRACT(YEAR FROM created_at) = :year", %{year: 2024})
  ```

  ---

  ## Locking

  ```elixir
  # FOR UPDATE
  OmQuery.lock(token, :update)

  # FOR SHARE
  OmQuery.lock(token, :share)

  # SKIP LOCKED
  OmQuery.lock(token, :update_skip_locked)

  # NOWAIT
  OmQuery.lock(token, :update_nowait)
  ```

  ---

  ## Streaming

  For large datasets, use streaming:

  ```elixir
  User
  |> OmQuery.new()
  |> OmQuery.filter(:status, :eq, "active")
  |> OmQuery.stream(max_rows: 500)
  |> Stream.each(&process_user/1)
  |> Stream.run()
  ```

  ---

  ## Transactions

  ```elixir
  OmQuery.transaction(fn ->
    user = User
      |> OmQuery.new()
      |> OmQuery.filter(:id, :eq, 123)
      |> OmQuery.lock(:update)
      |> OmQuery.first!()

    # ... modify and save user

    {:ok, user}
  end)
  ```

  ---

  ## Batch Execution

  Execute multiple queries in parallel:

  ```elixir
  tokens = [
    User |> OmQuery.new() |> OmQuery.filter(:status, :eq, "active"),
    Post |> OmQuery.new() |> OmQuery.limit(10),
    Order |> OmQuery.new() |> OmQuery.filter(:status, :eq, "pending")
  ]

  [users_result, posts_result, orders_result] = OmQuery.batch(tokens)
  ```

  ---

  ## Date/Time Helpers

  ```elixir
  import OmQuery.Helpers

  # Relative dates
  OmQuery.filter(token, :created_at, :gte, last_week())
  OmQuery.filter(token, :updated_at, :gte, hours_ago(24))
  OmQuery.filter(token, :expires_at, :lt, tomorrow())

  # Time periods
  OmQuery.filter(token, :created_at, :gte, start_of_month())
  OmQuery.filter(token, :created_at, :between, {start_of_day(date), end_of_day(date)})
  ```

  Available helpers:
  - `today()`, `yesterday()`, `tomorrow()`
  - `last_week()`, `last_month()`, `last_quarter()`, `last_year()`
  - `now()`, `minutes_ago(n)`, `hours_ago(n)`, `days_ago(n)`, `weeks_ago(n)`
  - `start_of_day(date)`, `end_of_day(date)`
  - `start_of_week()`, `start_of_month()`, `start_of_year()`

  ---

  ## Error Handling

  ### Safe Execution

  ```elixir
  case OmQuery.execute(token) do
    {:ok, result} -> handle_success(result)
    {:error, %CursorError{}} -> handle_invalid_cursor()
    {:error, error} -> handle_error(error)
  end
  ```

  ### Safe Building

  ```elixir
  case OmQuery.build_safe(token) do
    {:ok, query} -> Repo.all(query)
    {:error, error} -> handle_build_error(error)
  end
  ```

  ### Error Types

  - `ValidationError` - Invalid operation parameters
  - `LimitExceededError` - Limit exceeds max_limit config
  - `PaginationError` - Invalid pagination configuration
  - `CursorError` - Invalid or corrupted cursor
  - `FilterGroupError` - Invalid OR/AND group

  ---

  ## Configuration

  ```elixir
  # config/config.exs

  config :events, OmQuery.Token,
    default_limit: 20,      # Default pagination limit
    max_limit: 1000         # Maximum allowed limit
  ```

  ---

  ## Best Practices

  ### 1. Always Use Pagination

  ```elixir
  # Good
  OmQuery.paginate(token, :cursor, limit: 20)

  # Bad - unbounded query (will be auto-limited with warning)
  OmQuery.execute(token)
  ```

  ### 2. Use Cursor Pagination for Real-Time Data

  Offset pagination can skip or duplicate records when data changes.
  Cursor pagination is stable.

  ### 3. Prefer Function-Based Fragments

  More explicit, better tooling support, easier to test.

  ### 4. Use filter_by for User Input

  ```elixir
  # Safely applies only non-nil values
  OmQuery.filter_by(token, params)
  ```

  ### 5. Use then_if for Conditional Logic

  ```elixir
  # Clean conditional building
  token
  |> OmQuery.then_if(status, &OmQuery.filter(&1, :status, :eq, &2))
  |> OmQuery.then_if(min_age, &OmQuery.filter(&1, :age, :gte, &2))
  ```

  ### 6. Use Streaming for Large Datasets

  ```elixir
  # Process records without loading all into memory
  OmQuery.stream(token) |> Stream.each(&process/1) |> Stream.run()
  ```
  """
  def guide, do: :see_moduledoc
end
