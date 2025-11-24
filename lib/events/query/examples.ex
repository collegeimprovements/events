defmodule Events.Query.Examples do
  @moduledoc """
  Comprehensive examples demonstrating the query system.

  **IMPORTANT**: This module contains documentation examples using placeholder
  schemas (User, Post, Comment, etc.) that don't exist in this application.
  These functions are for **reference only** and will not execute.

  To use the query system with your own schemas, replace the placeholder
  schema names with your actual Ecto schemas.

  ## Table of Contents

  1. Basic Queries
  2. Filtering
  3. Pagination
  4. Joins and Preloads
  5. Aggregations
  6. CTEs and Subqueries
  7. Window Functions
  8. Transactions
  9. Batch Operations
  10. Advanced Patterns
  """

  # Suppress warnings for undefined schemas (these are documentation examples)
  @compile {:no_warn_undefined,
            [
              User,
              Post,
              Comment,
              Product,
              Order,
              Sale,
              Report,
              Category,
              Brand,
              Activity,
              Project,
              Subscription,
              Invoice
            ]}

  import Events.Query.DSL
  alias Events.Query

  ## 1. Basic Queries

  @doc "Simple query with filters"
  def basic_query do
    query User do
      filter(:status, :eq, "active")
      filter(:age, :gte, 18)
      order(:name, :asc)
      limit(10)
    end
    |> Query.execute()
  end

  @doc "Pipeline style"
  def pipeline_query do
    User
    |> Query.new()
    |> Query.filter(:status, :eq, "active")
    |> Query.order(:created_at, :desc)
    |> Query.limit(20)
    |> Query.execute()
  end

  ## 2. Filtering

  @doc "All filter operators"
  def filter_operators do
    query Product do
      # Equality
      filter(:status, :eq, "active")
      filter(:category, :neq, "archived")

      # Comparisons
      filter(:price, :gte, 10.00)
      filter(:stock, :gt, 0)

      # List membership
      filter(:category, :in, ["electronics", "gadgets"])
      filter(:status, :not_in, ["deleted", "archived"])

      # Pattern matching
      filter(:name, :ilike, "%widget%")

      # Null checks
      filter(:deleted_at, :is_nil, nil)

      # Range
      filter(:price, :between, {10.00, 100.00})

      # JSONB
      filter(:metadata, :jsonb_contains, %{featured: true})
      filter(:tags, :jsonb_has_key, "priority")
    end
    |> Query.execute()
  end

  @doc "Filter options"
  def filter_with_options do
    query User do
      # Case insensitive comparison
      filter(:email, :eq, "john@example.com", case_insensitive: true)

      # Filter on joined table
      join(:posts, :inner, as: :user_posts)
      filter(:published, :eq, true, binding: :user_posts)
    end
    |> Query.execute()
  end

  ## 3. Pagination

  @doc "Offset pagination"
  def offset_pagination(page \\ 1, per_page \\ 20) do
    offset = (page - 1) * per_page

    query Post do
      filter(:published, :eq, true)
      order(:published_at, :desc)
      paginate(:offset, limit: per_page, offset: offset)
    end
    |> Query.execute(include_total_count: true)
  end

  @doc "Cursor pagination"
  def cursor_pagination(after_cursor \\ nil) do
    opts =
      [cursor_fields: [:published_at, :id], limit: 20]
      |> then(fn opts ->
        if after_cursor, do: Keyword.put(opts, :after, after_cursor), else: opts
      end)

    query Post do
      filter(:published, :eq, true)
      order(:published_at, :desc)
      order(:id, :desc)
      paginate(:cursor, opts)
    end
    |> Query.execute()
  end

  @doc "Get next page from cursor pagination result"
  def get_next_page(result) do
    if result.pagination.has_more do
      cursor_pagination(result.pagination.end_cursor)
    else
      {:error, :no_more_pages}
    end
  end

  ## 4. Joins and Preloads

  @doc "Association preloads"
  def simple_preloads do
    query User do
      filter(:status, :eq, "active")
      preload([:posts, :comments, :profile])
    end
    |> Query.execute()
  end

  @doc "Nested preloads with filters"
  def nested_preloads do
    query User do
      filter(:status, :eq, "active")

      # Preload published posts with their comments
      preload :posts do
        filter(:published, :eq, true)
        order(:published_at, :desc)
        limit(5)

        # Nested preload
        preload :comments do
          filter(:approved, :eq, true)
          order(:created_at, :desc)
          limit(3)
        end
      end

      # Preload recent comments
      preload :comments do
        filter(:created_at, :gte, ~N[2024-01-01 00:00:00])
        order(:created_at, :desc)
      end
    end
    |> Query.execute()
  end

  @doc "Joins with custom conditions"
  def custom_joins do
    query User do
      filter(:status, :eq, "active")

      # Association join
      join(:posts, :left, as: :user_posts)

      # Filter on joined table
      filter(:published, :eq, true, binding: :user_posts)

      select(%{
        user_name: :name,
        user_email: :email
      })
    end
    |> Query.execute()
  end

  ## 5. Aggregations

  @doc "Group by and having"
  def aggregations do
    query Order do
      filter(:created_at, :gte, ~D[2024-01-01])

      group_by([:status])

      having(count: {:gte, 10})

      select([:id, :status, :created_at])
    end
    |> Query.execute()
  end

  @doc "Complex aggregation with joins"
  def complex_aggregation do
    query User do
      join(:orders, :left)

      group_by([:id, :name])

      having(count: {:gte, 5})

      select([:id, :name, :email])

      order(:name, :desc)
      limit(10)
    end
    |> Query.execute()
  end

  ## 6. CTEs and Subqueries

  @doc "Common Table Expression"
  def with_cte do
    # Define CTE for active users
    active_users_cte =
      query User do
        filter(:status, :eq, "active")
        filter(:last_login, :gte, ~N[2024-01-01 00:00:00])
        select([:id, :name, :email])
      end

    # Use CTE in main query
    query Order do
      with_cte(:active_users, active_users_cte)

      # Filter orders (CTE usage would require additional join support)
      filter(:status, :eq, "completed")

      order(:created_at, :desc)
    end
    |> Query.execute()
  end

  @doc "Multiple CTEs"
  def multiple_ctes do
    recent_users =
      query User do
        filter(:created_at, :gte, ~N[2024-01-01 00:00:00])
      end

    active_orders =
      query Order do
        filter(:status, :in, ["pending", "processing"])
      end

    query Report do
      with_cte(:recent_users, recent_users)
      with_cte(:active_orders, active_orders)

      # Use both CTEs in analysis
    end
    |> Query.execute()
  end

  ## 7. Window Functions

  @doc "Running totals with window functions"
  def running_totals do
    query Sale do
      filter(:created_at, :gte, ~D[2024-01-01])

      window(:running_total,
        partition_by: :product_id,
        order_by: [asc: :sale_date]
      )

      select(%{
        sale_id: :id,
        product_id: :product_id,
        amount: :amount,
        running_total: {:window, :sum, :amount, :running_total}
      })

      order(:sale_date, :asc)
    end
    |> Query.execute()
  end

  @doc "Ranking with window functions"
  def product_ranking do
    query Product do
      filter(:active, :eq, true)

      window(:category_rank,
        partition_by: :category_id,
        order_by: [desc: :sales_count]
      )

      select(%{
        product_name: :name,
        category_id: :category_id,
        sales_count: :sales_count,
        rank: {:window, :rank, :sales_count, :category_rank}
      })
    end
    |> Query.execute()
  end

  ## 8. Transactions

  @doc "Execute query in transaction"
  def transactional_query do
    Query.transaction(fn ->
      # Update user
      user_token =
        User
        |> Query.new()
        |> Query.filter(:id, :eq, 123)

      user_result = Query.execute(user_token)

      # Create order
      # ... more operations

      {:ok, user_result}
    end)
  end

  @doc "Multi-step transaction with Ecto.Multi"
  def multi_transaction do
    alias Events.Query.Multi, as: QM

    user_query =
      User
      |> Query.new()
      |> Query.filter(:id, :eq, 123)

    posts_query =
      Post
      |> Query.new()
      |> Query.filter(:user_id, :eq, 123)

    Ecto.Multi.new()
    |> QM.query(:user, user_query)
    |> QM.query(:posts, posts_query)
    |> Ecto.Multi.run(:summary, fn _repo, %{user: user, posts: posts} ->
      {:ok,
       %{
         user_name: List.first(user.data).name,
         post_count: length(posts.data)
       }}
    end)
    |> Events.Repo.transaction()
  end

  ## 9. Batch Operations

  @doc "Execute multiple queries in parallel"
  def batch_queries do
    users_token =
      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.limit(100)

    posts_token =
      Post
      |> Query.new()
      |> Query.filter(:published, :eq, true)
      |> Query.limit(100)

    comments_token =
      Comment
      |> Query.new()
      |> Query.filter(:approved, :eq, true)
      |> Query.limit(100)

    [users_result, posts_result, comments_result] =
      Query.batch([users_token, posts_token, comments_token])

    %{
      users: length(users_result.data),
      posts: length(posts_result.data),
      comments: length(comments_result.data)
    }
  end

  ## 10. Advanced Patterns

  @doc "Dynamic filter building"
  def dynamic_filters(filters) do
    base_token = Query.new(Product)

    final_token =
      Enum.reduce(filters, base_token, fn
        {:category, category}, token ->
          Query.filter(token, :category, :eq, category)

        {:min_price, price}, token ->
          Query.filter(token, :price, :gte, price)

        {:max_price, price}, token ->
          Query.filter(token, :price, :lte, price)

        {:search, term}, token ->
          Query.filter(token, :name, :ilike, "%#{term}%")

        _, token ->
          token
      end)

    Query.execute(final_token)
  end

  @doc "Streaming large result sets"
  def stream_results do
    token =
      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.order(:id, :asc)

    token
    |> Query.stream(max_rows: 1000)
    |> Enum.each(fn user ->
      # Process each user
      IO.inspect(user.id)
    end)
  end

  @doc "Raw SQL with named placeholders"
  def raw_sql_query do
    query User do
      raw_where("age BETWEEN :min_age AND :max_age", %{
        min_age: 18,
        max_age: 65
      })

      raw_where("created_at >= :start_date", %{
        start_date: ~N[2024-01-01 00:00:00]
      })

      order(:created_at, :desc)
    end
    |> Query.execute()
  end

  @doc "Build query without executing"
  def build_only do
    token =
      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.order(:name, :asc)

    # Get the Ecto.Query without executing
    ecto_query = Query.build(token)

    # Can inspect or modify the query
    IO.inspect(ecto_query)

    # Execute manually
    Events.Repo.all(ecto_query)
  end

  @doc "Custom result processing"
  def custom_processing do
    result =
      query User do
        filter(:status, :eq, "active")
        order(:created_at, :desc)
        limit(100)
      end
      |> Query.execute()

    case result do
      %{data: data, pagination: pagination} ->
        %{
          users: data,
          count: length(data),
          has_more: pagination.has_more,
          query_time_ms: result.metadata.query_time_μs / 1000
        }
    end
  end

  # ============================================================================
  # 11. ADVANCED PATTERNS - Complex Real-World Examples
  # ============================================================================

  @doc """
  ## Social Feed with Nested Preloads

  Load a user's feed with posts, their authors, comments with commenter profiles,
  and like counts - all with proper filtering and pagination.

  ### The Complex Problem
  - Get published posts from followed users
  - For each post: author with avatar, top 3 comments with commenters
  - Paginate with cursor (stable for real-time feeds)
  - Filter out blocked users' content

  ### Without Query DSL (verbose Ecto)
  ```elixir
  # Would require ~50+ lines of nested preload queries, dynamic joins,
  # manual cursor encoding, and complex where clauses
  ```

  ### With Query DSL (clean & composable)
  """
  def social_feed(_user_id, cursor \\ nil) do
    # Build the base query with all complexity hidden
    Post
    |> Query.new()
    |> Query.filter(:published, :eq, true)
    |> Query.filter(:visibility, :in, ["public", "friends"])
    |> Query.order(:published_at, :desc)
    # Tiebreaker for stable cursor
    |> Query.order(:id, :asc)
    # Conditional cursor pagination
    |> Query.then_if(cursor, fn token, c ->
      Query.paginate(token, :cursor, limit: 20, after: c)
    end)
    |> Query.if_true(is_nil(cursor), fn token ->
      Query.paginate(token, :cursor, limit: 20)
    end)
    # Author with profile (nested preload)
    |> Query.preload(:author, fn author_token ->
      author_token
      |> Query.preload(:profile)
      |> Query.select([:id, :username, :avatar_url])
    end)
    # Top comments with their authors
    |> Query.preload(:comments, fn comments_token ->
      comments_token
      |> Query.filter(:approved, :eq, true)
      |> Query.filter(:deleted_at, :is_nil, true)
      |> Query.order(:likes_count, :desc)
      |> Query.order(:created_at, :asc)
      |> Query.limit(3)
      |> Query.preload(:author, fn author ->
        author |> Query.select([:id, :username, :avatar_url])
      end)
    end)
    |> Query.execute()
  end

  @doc """
  ## E-Commerce Product Listing with Faceted Filters

  Complex product search with:
  - Dynamic filters (category, price range, attributes)
  - Inventory join to check stock
  - Seller rating from reviews
  - Multiple sort options
  - Cursor pagination

  ### The Pattern
  Combine `filter_by`, `then_if`, joins, and fragments for maximum flexibility.
  """
  def product_listing(params) do
    Product
    |> Query.new()
    |> Query.filter(:active, :eq, true)
    |> Query.filter(:deleted_at, :is_nil, true)
    # Dynamic equality filters from params
    |> Query.filter_by(Map.take(params, [:category_id, :brand_id, :seller_id]))
    # Conditional range filters
    |> Query.then_if(params[:min_price], fn token, price ->
      Query.filter(token, :price, :gte, price)
    end)
    |> Query.then_if(params[:max_price], fn token, price ->
      Query.filter(token, :price, :lte, price)
    end)
    # Search in name and description
    |> Query.then_if(params[:search], fn token, search ->
      Query.where_any(token, [
        {:name, :ilike, "%#{search}%"},
        {:description, :ilike, "%#{search}%"},
        {:sku, :eq, search}
      ])
    end)
    # JSONB attribute filters (e.g., color, size)
    |> Query.then_if(params[:attributes], fn token, attrs ->
      Query.filter(token, :attributes, :jsonb_contains, attrs)
    end)
    # Join inventory for stock check
    |> Query.join(:inventory, :left, as: :inv)
    |> Query.if_true(params[:in_stock_only], fn token ->
      Query.filter(token, :quantity, :gt, 0, binding: :inv)
    end)
    # Dynamic sorting
    |> apply_product_sort(params[:sort])
    # Cursor pagination
    |> Query.paginate(:cursor, limit: params[:limit] || 24)
    # Preload related data
    |> Query.preload([:category, :brand, :primary_image])
    |> Query.preload(:reviews, fn reviews ->
      reviews
      |> Query.filter(:approved, :eq, true)
      |> Query.order(:helpful_count, :desc)
      |> Query.limit(3)
    end)
    |> Query.execute()
  end

  defp apply_product_sort(token, "price_asc"), do: Query.orders(token, asc: :price, asc: :id)
  defp apply_product_sort(token, "price_desc"), do: Query.orders(token, desc: :price, asc: :id)
  defp apply_product_sort(token, "newest"), do: Query.orders(token, desc: :created_at, asc: :id)
  defp apply_product_sort(token, "popular"), do: Query.orders(token, desc: :sales_count, asc: :id)
  defp apply_product_sort(token, "rating"), do: Query.orders(token, desc: :avg_rating, asc: :id)
  defp apply_product_sort(token, _), do: Query.orders(token, desc: :featured_score, asc: :id)

  @doc """
  ## Admin Dashboard with Multiple Aggregations

  Complex admin view showing:
  - Users with their order counts and total spent
  - Filtered by date range and status
  - With nested organization data
  - Paginated with total count

  ### The Pattern
  Joins + Group By + Having + Nested Preloads + Offset Pagination (for admin UI)
  """
  def admin_user_dashboard(params) do
    User
    |> Query.new()
    # Base filters
    |> Query.filter(:deleted_at, :is_nil, true)
    |> Query.filter_by(Map.take(params, [:status, :role, :organization_id]))
    # Date range filter
    |> Query.then_if(params[:created_after], fn token, date ->
      Query.filter(token, :created_at, :gte, date)
    end)
    |> Query.then_if(params[:created_before], fn token, date ->
      Query.filter(token, :created_at, :lte, date)
    end)
    # Search across multiple fields
    |> Query.then_if(params[:search], fn token, search ->
      Query.where_any(token, [
        {:name, :ilike, "%#{search}%"},
        {:email, :ilike, "%#{search}%"},
        {:phone, :ilike, "%#{search}%"}
      ])
    end)
    # Join orders for aggregation
    |> Query.join(:orders, :left, as: :orders)
    |> Query.group_by(:id)
    # Filter by order count
    |> Query.then_if(params[:min_orders], fn token, min ->
      Query.having(token, count: {:gte, min})
    end)
    # Sorting
    |> Query.orders(parse_admin_sort(params[:sort]))
    # Offset pagination with total count (better for admin tables)
    |> Query.paginate(:offset,
      limit: params[:per_page] || 25,
      offset: ((params[:page] || 1) - 1) * (params[:per_page] || 25)
    )
    # Rich preloads for admin view
    |> Query.preload(:organization)
    |> Query.preload(:profile)
    |> Query.preload(:last_order, fn order ->
      order
      |> Query.order(:created_at, :desc)
      |> Query.limit(1)
    end)
    |> Query.execute(include_total_count: true)
  end

  defp parse_admin_sort("-" <> field), do: [{:desc, String.to_existing_atom(field)}]
  defp parse_admin_sort("+" <> field), do: [{:asc, String.to_existing_atom(field)}]
  defp parse_admin_sort(field) when is_binary(field), do: [{:asc, String.to_existing_atom(field)}]
  defp parse_admin_sort(_), do: [{:desc, :created_at}, {:asc, :id}]

  @doc """
  ## Hierarchical Data with Recursive CTE

  Load an organization tree with:
  - All descendants of a parent org
  - Employee counts at each level
  - Budget rollups

  ### The Pattern
  Recursive CTE + Aggregation + Nested Structure
  """
  def organization_tree(root_org_id) do
    import Ecto.Query

    # Base case: the root organization
    base =
      from(o in "organizations",
        where: o.id == ^root_org_id,
        select: %{
          id: o.id,
          name: o.name,
          parent_id: o.parent_id,
          depth: 0
        }
      )

    # Recursive case: children of organizations in the tree
    recursive =
      from(o in "organizations",
        join: tree in "org_tree",
        on: o.parent_id == tree.id,
        select: %{
          id: o.id,
          name: o.name,
          parent_id: o.parent_id,
          depth: tree.depth + 1
        }
      )

    cte_query = union_all(base, ^recursive)

    # Main query using the CTE
    from(o in "org_tree")
    |> Query.new()
    |> Query.with_cte(:org_tree, cte_query, recursive: true)
    |> Query.order(:depth, :asc)
    |> Query.order(:name, :asc)
    # No pagination for tree data
    |> Query.execute(unsafe: true)
  end

  @doc """
  ## Real-Time Notifications with Complex Filters

  Load notifications with:
  - Polymorphic source resolution (post, comment, user, etc.)
  - Read/unread filtering
  - Grouped by date
  - With actor information

  ### The Pattern
  OR groups + Polymorphic preloads + Conditional includes
  """
  def user_notifications(user_id, params \\ %{}) do
    Notification
    |> Query.new()
    |> Query.filter(:user_id, :eq, user_id)
    |> Query.filter(:deleted_at, :is_nil, true)
    # Filter by read status
    |> Query.then_if(params[:unread_only], fn token, true ->
      Query.filter(token, :read_at, :is_nil, true)
    end)
    # Filter by notification types
    |> Query.then_if(params[:types], fn token, types ->
      Query.filter(token, :type, :in, types)
    end)
    # Filter by date range
    |> Query.then_if(params[:since], fn token, since ->
      Query.filter(token, :created_at, :gte, since)
    end)
    # Order by most recent
    |> Query.order(:created_at, :desc)
    |> Query.order(:id, :desc)
    # Cursor pagination
    |> Query.paginate(:cursor, limit: params[:limit] || 20)
    # Preload actor (who triggered the notification)
    |> Query.preload(:actor, fn actor ->
      actor |> Query.select([:id, :username, :avatar_url])
    end)
    # Preload the source based on type (polymorphic)
    |> Query.preload(:source)
    |> Query.execute()
  end

  @doc """
  ## Analytics Query with Window Functions

  Calculate running totals, rankings, and percentiles
  for sales data.

  ### The Pattern
  Window functions + Partitioning + Frame specification
  """
  def sales_analytics(params) do
    Sale
    |> Query.new()
    |> Query.filter(:status, :eq, "completed")
    |> Query.then_if(params[:start_date], fn token, date ->
      Query.filter(token, :completed_at, :gte, date)
    end)
    |> Query.then_if(params[:end_date], fn token, date ->
      Query.filter(token, :completed_at, :lte, date)
    end)
    |> Query.then_if(params[:product_ids], fn token, ids ->
      Query.filter(token, :product_id, :in, ids)
    end)
    # Define windows for analytics
    |> Query.window(:running_total,
      partition_by: :product_id,
      order_by: [asc: :completed_at],
      frame: {:rows, :unbounded_preceding, :current_row}
    )
    |> Query.window(:daily_rank,
      partition_by: :product_id,
      order_by: [desc: :amount]
    )
    |> Query.order(:completed_at, :asc)
    |> Query.paginate(:offset, limit: params[:limit] || 100)
    |> Query.execute()
  end

  @doc """
  ## Batch Processing with Streaming

  Process large datasets efficiently without loading all into memory.

  ### The Pattern
  Streaming + Transaction + Chunked processing
  """
  def process_expired_subscriptions do
    Query.transaction(fn ->
      Subscription
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:expires_at, :lt, DateTime.utc_now())
      # Allow parallel workers
      |> Query.lock(:update_skip_locked)
      |> Query.order(:expires_at, :asc)
      |> Query.stream(max_rows: 100)
      |> Stream.each(fn subscription ->
        # Process each subscription
        expire_subscription(subscription)
      end)
      |> Stream.run()

      :ok
    end)
  end

  defp expire_subscription(_subscription), do: :ok

  # ============================================================================
  # 12. FRAGMENT COMPOSITION PATTERNS
  # ============================================================================

  # ---------------------------------------------------------------------------
  # Reusable Query Fragments
  #
  # Define common query patterns once, compose them anywhere.
  # Function-based fragments for maximum reusability.
  # ---------------------------------------------------------------------------

  defmodule Fragments do
    @moduledoc false
    alias Events.Query
    alias Events.Query.Token

    # Soft delete scope
    def not_deleted do
      Token.new(:nested)
      |> Query.filter(:deleted_at, :is_nil, true)
    end

    # Active status scope
    def active do
      Token.new(:nested)
      |> Query.filter(:status, :eq, "active")
    end

    # Published content scope
    def published do
      Token.new(:nested)
      |> Query.filter(:published, :eq, true)
      |> Query.filter(:published_at, :lte, DateTime.utc_now())
    end

    # Recent items (last N days)
    def recent(days \\ 7) do
      cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

      Token.new(:nested)
      |> Query.filter(:created_at, :gte, cutoff)
    end

    # Standard cursor pagination
    def paginated(cursor \\ nil, limit \\ 20) do
      token =
        Token.new(:nested)
        |> Query.order(:created_at, :desc)
        |> Query.order(:id, :asc)

      if cursor do
        Query.paginate(token, :cursor, limit: limit, after: cursor)
      else
        Query.paginate(token, :cursor, limit: limit)
      end
    end

    # Visible to user (public or owned)
    def visible_to(user_id) do
      Token.new(:nested)
      |> Query.where_any([
        {:visibility, :eq, "public"},
        {:user_id, :eq, user_id}
      ])
    end
  end

  @doc """
  ## Using Composed Fragments

  Combine multiple fragments for clean, readable queries.
  """
  def composed_query_example(user_id, cursor) do
    Post
    |> Query.new()
    |> Query.include(Fragments.not_deleted())
    |> Query.include(Fragments.published())
    |> Query.include(Fragments.visible_to(user_id))
    |> Query.include(Fragments.recent(30))
    |> Query.include(Fragments.paginated(cursor, 20))
    |> Query.preload([:author, :category])
    |> Query.execute()
  end

  @doc """
  ## Conditional Fragment Composition

  Apply fragments based on runtime conditions.
  """
  def conditional_fragments_example(params, current_user) do
    Post
    |> Query.new()
    |> Query.include(Fragments.not_deleted())
    # Only show published unless admin
    |> Query.include_if(!current_user.admin?, Fragments.published())
    # Apply visibility rules unless admin
    |> Query.include_if(!current_user.admin?, Fragments.visible_to(current_user.id))
    # Only recent if requested
    |> Query.include_if(params[:recent_only], Fragments.recent(params[:days] || 7))
    |> Query.include(Fragments.paginated(params[:cursor]))
    |> Query.execute()
  end

  # ============================================================================
  # 13. SIDE-BY-SIDE: MACRO DSL vs PIPELINE
  # ============================================================================
  #
  # Every advanced pattern shown in both styles so you can choose what fits.
  # Both produce identical queries - pick based on preference.
  #

  @doc """
  ## Blog Post Feed - Both Syntaxes

  Load published blog posts with author info and comment previews.
  """
  def blog_feed_pipeline(cursor \\ nil) do
    # PIPELINE STYLE - Explicit, composable, easy to conditionally modify
    Post
    |> Query.new()
    |> Query.filter(:published, :eq, true)
    |> Query.filter(:published_at, :lte, DateTime.utc_now())
    |> Query.filter(:deleted_at, :is_nil, true)
    |> Query.order(:published_at, :desc)
    |> Query.order(:id, :asc)
    |> Query.then_if(cursor, fn token, c ->
      Query.paginate(token, :cursor, limit: 10, after: c)
    end)
    |> Query.if_true(is_nil(cursor), fn token ->
      Query.paginate(token, :cursor, limit: 10)
    end)
    |> Query.preload(:author, fn a ->
      a |> Query.select([:id, :name, :avatar_url])
    end)
    |> Query.preload(:comments, fn c ->
      c
      |> Query.filter(:approved, :eq, true)
      |> Query.order(:created_at, :desc)
      |> Query.limit(3)
    end)
    |> Query.preload(:tags)
    |> Query.execute()
  end

  def blog_feed_dsl(cursor \\ nil) do
    # MACRO DSL STYLE - Concise, declarative, SQL-like readability
    import Events.Query.DSL

    opts = if cursor, do: [limit: 10, after: cursor], else: [limit: 10]

    query Post do
      filter(:published, :eq, true)
      filter(:published_at, :lte, DateTime.utc_now())
      filter(:deleted_at, :is_nil, true)

      order(:published_at, :desc)
      order(:id, :asc)

      paginate(:cursor, opts)

      preload :author do
        select([:id, :name, :avatar_url])
      end

      preload :comments do
        filter(:approved, :eq, true)
        order(:created_at, :desc)
        limit(3)
      end

      preload([:tags])
    end
    |> Query.execute()
  end

  @doc """
  ## User Search with Multiple Criteria - Both Syntaxes

  Search users by name/email with role filtering and organization scope.
  """
  def user_search_pipeline(params) do
    # PIPELINE STYLE
    User
    |> Query.new()
    |> Query.filter(:deleted_at, :is_nil, true)
    |> Query.filter(:status, :eq, "active")
    # Search across multiple fields (OR)
    |> Query.then_if(params[:q], fn token, search ->
      Query.where_any(token, [
        {:name, :ilike, "%#{search}%"},
        {:email, :ilike, "%#{search}%"},
        {:username, :ilike, "%#{search}%"}
      ])
    end)
    # Filter by role
    |> Query.then_if(params[:role], fn token, role ->
      Query.filter(token, :role, :eq, role)
    end)
    # Filter by roles (multiple)
    |> Query.then_if(params[:roles], fn token, roles ->
      Query.filter(token, :role, :in, roles)
    end)
    # Organization scope
    |> Query.then_if(params[:organization_id], fn token, org_id ->
      Query.filter(token, :organization_id, :eq, org_id)
    end)
    # Date range
    |> Query.then_if(params[:joined_after], fn token, date ->
      Query.filter(token, :created_at, :gte, date)
    end)
    |> Query.then_if(params[:joined_before], fn token, date ->
      Query.filter(token, :created_at, :lte, date)
    end)
    # Sorting (default: name asc)
    |> apply_user_sort(params[:sort] || "name")
    # Pagination
    |> Query.paginate(:offset,
      limit: params[:per_page] || 20,
      offset: ((params[:page] || 1) - 1) * (params[:per_page] || 20)
    )
    |> Query.preload([:organization, :profile])
    |> Query.execute(include_total_count: true)
  end

  def user_search_dsl(params) do
    # MACRO DSL STYLE - Note: conditionals require falling back to pipeline
    import Events.Query.DSL

    base =
      query User do
        filter(:deleted_at, :is_nil, true)
        filter(:status, :eq, "active")
      end

    # For complex conditionals, combine DSL base with pipeline operations
    base
    |> Query.then_if(params[:q], fn token, search ->
      Query.where_any(token, [
        {:name, :ilike, "%#{search}%"},
        {:email, :ilike, "%#{search}%"},
        {:username, :ilike, "%#{search}%"}
      ])
    end)
    |> Query.filter_by(Map.take(params, [:role, :organization_id]))
    |> apply_user_sort(params[:sort] || "name")
    |> Query.paginate(:offset,
      limit: params[:per_page] || 20,
      offset: ((params[:page] || 1) - 1) * (params[:per_page] || 20)
    )
    |> Query.preload([:organization, :profile])
    |> Query.execute(include_total_count: true)
  end

  defp apply_user_sort(token, "name"), do: Query.orders(token, asc: :name, asc: :id)
  defp apply_user_sort(token, "-name"), do: Query.orders(token, desc: :name, asc: :id)
  defp apply_user_sort(token, "email"), do: Query.orders(token, asc: :email, asc: :id)
  defp apply_user_sort(token, "-email"), do: Query.orders(token, desc: :email, asc: :id)
  defp apply_user_sort(token, "created"), do: Query.orders(token, asc: :created_at, asc: :id)
  defp apply_user_sort(token, "-created"), do: Query.orders(token, desc: :created_at, asc: :id)
  defp apply_user_sort(token, _), do: Query.orders(token, asc: :name, asc: :id)

  @doc """
  ## Order Management Dashboard - Both Syntaxes

  Complex order listing with customer info, items, and status filters.
  """
  def orders_dashboard_pipeline(params) do
    # PIPELINE STYLE
    Order
    |> Query.new()
    |> Query.filter(:deleted_at, :is_nil, true)
    # Status filter (single or multiple)
    |> Query.then_if(params[:status], fn token, status when is_binary(status) ->
      Query.filter(token, :status, :eq, status)
    end)
    |> Query.then_if(params[:statuses], fn token, statuses when is_list(statuses) ->
      Query.filter(token, :status, :in, statuses)
    end)
    # Customer filter
    |> Query.then_if(params[:customer_id], fn token, id ->
      Query.filter(token, :customer_id, :eq, id)
    end)
    # Amount range
    |> Query.then_if(params[:min_total], fn token, min ->
      Query.filter(token, :total, :gte, min)
    end)
    |> Query.then_if(params[:max_total], fn token, max ->
      Query.filter(token, :total, :lte, max)
    end)
    # Date filters
    |> Query.then_if(params[:from_date], fn token, date ->
      Query.filter(token, :created_at, :gte, date)
    end)
    |> Query.then_if(params[:to_date], fn token, date ->
      Query.filter(token, :created_at, :lte, date)
    end)
    # Search by order number or customer email
    |> Query.then_if(params[:search], fn token, search ->
      token
      |> Query.join(:customer, :left, as: :cust)
      |> Query.where_any([
        {:order_number, :ilike, "%#{search}%"},
        {:email, :ilike, "%#{search}%", binding: :cust}
      ])
    end)
    # Sorting
    |> Query.orders(parse_order_sort(params[:sort]))
    # Pagination
    |> Query.paginate(:cursor, limit: params[:limit] || 25)
    # Preloads
    |> Query.preload(:customer, fn c ->
      c |> Query.select([:id, :name, :email])
    end)
    |> Query.preload(:items, fn items ->
      items
      |> Query.order(:position, :asc)
      |> Query.preload(:product)
    end)
    |> Query.preload(:shipping_address)
    |> Query.execute()
  end

  def orders_dashboard_dsl(params) do
    # MACRO DSL STYLE - Base query with DSL, conditionals with pipeline
    import Events.Query.DSL

    base =
      query Order do
        filter(:deleted_at, :is_nil, true)

        preload :customer do
          select([:id, :name, :email])
        end

        preload :items do
          order(:position, :asc)
          preload([:product])
        end

        preload([:shipping_address])
      end

    # Apply conditional filters via pipeline
    base
    |> Query.then_if(params[:status], fn token, status ->
      Query.filter(token, :status, :eq, status)
    end)
    |> Query.then_if(params[:statuses], fn token, statuses ->
      Query.filter(token, :status, :in, statuses)
    end)
    |> Query.filter_by(Map.take(params, [:customer_id]))
    |> Query.then_if(params[:min_total], fn token, min ->
      Query.filter(token, :total, :gte, min)
    end)
    |> Query.then_if(params[:max_total], fn token, max ->
      Query.filter(token, :total, :lte, max)
    end)
    |> Query.orders(parse_order_sort(params[:sort]))
    |> Query.paginate(:cursor, limit: params[:limit] || 25)
    |> Query.execute()
  end

  defp parse_order_sort("-total"), do: [desc: :total, asc: :id]
  defp parse_order_sort("total"), do: [asc: :total, asc: :id]
  defp parse_order_sort("-created"), do: [desc: :created_at, asc: :id]
  defp parse_order_sort("created"), do: [asc: :created_at, asc: :id]
  defp parse_order_sort(_), do: [desc: :created_at, asc: :id]

  @doc """
  ## Inventory Report with Joins - Both Syntaxes

  Products with inventory levels, supplier info, and low stock alerts.
  """
  def inventory_report_pipeline(params) do
    # PIPELINE STYLE
    Product
    |> Query.new()
    |> Query.filter(:active, :eq, true)
    |> Query.join(:inventory, :left, as: :inv)
    |> Query.join(:supplier, :left, as: :sup)
    # Category filter
    |> Query.then_if(params[:category_id], fn token, id ->
      Query.filter(token, :category_id, :eq, id)
    end)
    # Low stock filter
    |> Query.if_true(params[:low_stock_only], fn token ->
      token
      |> Query.filter(:quantity, :lte, 10, binding: :inv)
      |> Query.filter(:quantity, :gt, 0, binding: :inv)
    end)
    # Out of stock filter
    |> Query.if_true(params[:out_of_stock], fn token ->
      Query.filter(token, :quantity, :eq, 0, binding: :inv)
    end)
    # Supplier filter
    |> Query.then_if(params[:supplier_id], fn token, id ->
      Query.filter(token, :id, :eq, id, binding: :sup)
    end)
    # Select specific fields for report
    |> Query.select(%{
      product_id: :id,
      product_name: :name,
      sku: :sku,
      price: :price
    })
    |> Query.order(:name, :asc)
    |> Query.paginate(:offset, limit: params[:limit] || 50)
    |> Query.execute()
  end

  def inventory_report_dsl(params) do
    # MACRO DSL STYLE
    import Events.Query.DSL

    base =
      query Product do
        filter(:active, :eq, true)

        join(:inventory, :left, as: :inv)
        join(:supplier, :left, as: :sup)

        select(%{
          product_id: :id,
          product_name: :name,
          sku: :sku,
          price: :price
        })

        order(:name, :asc)
      end

    base
    |> Query.then_if(params[:category_id], fn token, id ->
      Query.filter(token, :category_id, :eq, id)
    end)
    |> Query.if_true(params[:low_stock_only], fn token ->
      token
      |> Query.filter(:quantity, :lte, 10, binding: :inv)
      |> Query.filter(:quantity, :gt, 0, binding: :inv)
    end)
    |> Query.if_true(params[:out_of_stock], fn token ->
      Query.filter(token, :quantity, :eq, 0, binding: :inv)
    end)
    |> Query.paginate(:offset, limit: params[:limit] || 50)
    |> Query.execute()
  end

  @doc """
  ## Activity Timeline - Both Syntaxes

  User activity feed with polymorphic content and pagination.
  """
  def activity_timeline_pipeline(user_id, cursor \\ nil) do
    # PIPELINE STYLE
    Activity
    |> Query.new()
    |> Query.filter(:user_id, :eq, user_id)
    |> Query.filter(:deleted_at, :is_nil, true)
    # Filter by activity types
    |> Query.filter(:type, :in, ["post", "comment", "like", "follow", "share"])
    # Order by most recent
    |> Query.order(:created_at, :desc)
    |> Query.order(:id, :desc)
    # Cursor pagination
    |> Query.then_if(cursor, fn token, c ->
      Query.paginate(token, :cursor, limit: 20, after: c)
    end)
    |> Query.if_true(is_nil(cursor), fn token ->
      Query.paginate(token, :cursor, limit: 20)
    end)
    # Preload the target (polymorphic)
    |> Query.preload(:target)
    # Preload related user (who did the action)
    |> Query.preload(:actor, fn a ->
      a |> Query.select([:id, :username, :avatar_url])
    end)
    |> Query.execute()
  end

  def activity_timeline_dsl(user_id, cursor \\ nil) do
    # MACRO DSL STYLE
    import Events.Query.DSL

    opts = if cursor, do: [limit: 20, after: cursor], else: [limit: 20]

    query Activity do
      filter(:user_id, :eq, user_id)
      filter(:deleted_at, :is_nil, true)
      filter(:type, :in, ["post", "comment", "like", "follow", "share"])

      order(:created_at, :desc)
      order(:id, :desc)

      paginate(:cursor, opts)

      preload([:target])

      preload :actor do
        select([:id, :username, :avatar_url])
      end
    end
    |> Query.execute()
  end

  @doc """
  ## Multi-Tenant Data Isolation - Both Syntaxes

  Ensure all queries are scoped to the current tenant.
  """
  def tenant_scoped_pipeline(tenant_id, params) do
    # PIPELINE STYLE - Tenant isolation is explicit and auditable
    Project
    |> Query.new()
    # CRITICAL: Always filter by tenant first
    |> Query.filter(:tenant_id, :eq, tenant_id)
    |> Query.filter(:deleted_at, :is_nil, true)
    # Additional filters
    |> Query.then_if(params[:status], fn token, status ->
      Query.filter(token, :status, :eq, status)
    end)
    |> Query.then_if(params[:owner_id], fn token, owner_id ->
      Query.filter(token, :owner_id, :eq, owner_id)
    end)
    |> Query.then_if(params[:search], fn token, search ->
      Query.filter(token, :name, :ilike, "%#{search}%")
    end)
    |> Query.order(:updated_at, :desc)
    |> Query.paginate(:cursor, limit: 20)
    |> Query.preload(:owner)
    |> Query.preload(:members, fn m ->
      m
      # Also scope preloads!
      |> Query.filter(:tenant_id, :eq, tenant_id)
      |> Query.order(:joined_at, :asc)
    end)
    |> Query.execute()
  end

  def tenant_scoped_dsl(tenant_id, params) do
    # MACRO DSL STYLE
    import Events.Query.DSL

    base =
      query Project do
        # CRITICAL: Tenant isolation
        filter(:tenant_id, :eq, tenant_id)
        filter(:deleted_at, :is_nil, true)

        order(:updated_at, :desc)
        paginate(:cursor, limit: 20)

        preload([:owner])

        preload :members do
          filter(:tenant_id, :eq, tenant_id)
          order(:joined_at, :asc)
        end
      end

    base
    |> Query.filter_by(Map.take(params, [:status, :owner_id]))
    |> Query.then_if(params[:search], fn token, search ->
      Query.filter(token, :name, :ilike, "%#{search}%")
    end)
    |> Query.execute()
  end

  @doc """
  ## Leaderboard with Ranking - Both Syntaxes

  Top users by score with ranking and tie handling.
  """
  def leaderboard_pipeline(params \\ %{}) do
    # PIPELINE STYLE
    User
    |> Query.new()
    |> Query.filter(:status, :eq, "active")
    |> Query.filter(:score, :gt, 0)
    # Optional time period filter
    |> Query.then_if(params[:period] == "weekly", fn token, _ ->
      Query.filter(token, :score_updated_at, :gte, weeks_ago(1))
    end)
    |> Query.then_if(params[:period] == "monthly", fn token, _ ->
      Query.filter(token, :score_updated_at, :gte, months_ago(1))
    end)
    # Category filter
    |> Query.then_if(params[:category], fn token, category ->
      Query.filter(token, :category, :eq, category)
    end)
    # Order by score descending, then by earliest achieved (for ties)
    |> Query.order(:score, :desc)
    |> Query.order(:score_updated_at, :asc)
    |> Query.order(:id, :asc)
    # Limit to top N
    |> Query.limit(params[:limit] || 100)
    |> Query.select([:id, :username, :avatar_url, :score, :score_updated_at])
    # No pagination for leaderboard
    |> Query.execute(unsafe: true)
  end

  def leaderboard_dsl(params \\ %{}) do
    # MACRO DSL STYLE
    import Events.Query.DSL

    base =
      query User do
        filter(:status, :eq, "active")
        filter(:score, :gt, 0)

        order(:score, :desc)
        order(:score_updated_at, :asc)
        order(:id, :asc)

        limit(params[:limit] || 100)

        select([:id, :username, :avatar_url, :score, :score_updated_at])
      end

    base
    |> Query.then_if(params[:period] == "weekly", fn token, _ ->
      Query.filter(token, :score_updated_at, :gte, weeks_ago(1))
    end)
    |> Query.then_if(params[:period] == "monthly", fn token, _ ->
      Query.filter(token, :score_updated_at, :gte, months_ago(1))
    end)
    |> Query.then_if(params[:category], fn token, category ->
      Query.filter(token, :category, :eq, category)
    end)
    |> Query.execute(unsafe: true)
  end

  defp weeks_ago(n), do: DateTime.add(DateTime.utc_now(), -n * 7 * 24 * 60 * 60, :second)
  defp months_ago(n), do: DateTime.add(DateTime.utc_now(), -n * 30 * 24 * 60 * 60, :second)

  @doc """
  ## Content Moderation Queue - Both Syntaxes

  Flagged content awaiting review with priority sorting.
  """
  def moderation_queue_pipeline(moderator_id, params \\ %{}) do
    # PIPELINE STYLE
    Report
    |> Query.new()
    |> Query.filter(:status, :eq, "pending")
    |> Query.filter(:deleted_at, :is_nil, true)
    # Exclude content the moderator has already reviewed
    |> Query.filter(:reviewed_by_id, :neq, moderator_id)
    # Filter by content type
    |> Query.then_if(params[:content_type], fn token, type ->
      Query.filter(token, :content_type, :eq, type)
    end)
    # Filter by severity
    |> Query.then_if(params[:min_severity], fn token, severity ->
      Query.filter(token, :severity, :gte, severity)
    end)
    # Filter by report reason
    |> Query.then_if(params[:reason], fn token, reason ->
      Query.filter(token, :reason, :eq, reason)
    end)
    # Priority: high severity first, then oldest
    |> Query.order(:severity, :desc)
    |> Query.order(:created_at, :asc)
    |> Query.order(:id, :asc)
    |> Query.paginate(:cursor, limit: params[:limit] || 20)
    # Preload the reported content and reporter
    |> Query.preload(:content)
    |> Query.preload(:reporter, fn r ->
      r |> Query.select([:id, :username, :trust_score])
    end)
    |> Query.preload(:previous_reports, fn pr ->
      pr
      |> Query.filter(:content_id, :eq, {:parent, :content_id})
      |> Query.order(:created_at, :desc)
      |> Query.limit(5)
    end)
    |> Query.execute()
  end

  def moderation_queue_dsl(moderator_id, params \\ %{}) do
    # MACRO DSL STYLE
    import Events.Query.DSL

    base =
      query Report do
        filter(:status, :eq, "pending")
        filter(:deleted_at, :is_nil, true)
        filter(:reviewed_by_id, :neq, moderator_id)

        order(:severity, :desc)
        order(:created_at, :asc)
        order(:id, :asc)

        paginate(:cursor, limit: params[:limit] || 20)

        preload([:content])

        preload :reporter do
          select([:id, :username, :trust_score])
        end

        preload :previous_reports do
          order(:created_at, :desc)
          limit(5)
        end
      end

    base
    |> Query.filter_by(Map.take(params, [:content_type, :reason]))
    |> Query.then_if(params[:min_severity], fn token, severity ->
      Query.filter(token, :severity, :gte, severity)
    end)
    |> Query.execute()
  end

  @doc """
  ## Subscription Billing Report - Both Syntaxes

  Active subscriptions with payment history and usage stats.
  """
  def billing_report_pipeline(params \\ %{}) do
    # PIPELINE STYLE
    Subscription
    |> Query.new()
    |> Query.filter(:deleted_at, :is_nil, true)
    # Status filter
    |> Query.then_if(params[:status], fn token, status ->
      Query.filter(token, :status, :eq, status)
    end)
    |> Query.if_true(!params[:status], fn token ->
      Query.filter(token, :status, :in, ["active", "trialing", "past_due"])
    end)
    # Plan filter
    |> Query.then_if(params[:plan_id], fn token, plan_id ->
      Query.filter(token, :plan_id, :eq, plan_id)
    end)
    # MRR range
    |> Query.then_if(params[:min_mrr], fn token, min ->
      Query.filter(token, :mrr, :gte, min)
    end)
    |> Query.then_if(params[:max_mrr], fn token, max ->
      Query.filter(token, :mrr, :lte, max)
    end)
    # Renewal date range
    |> Query.then_if(params[:renews_before], fn token, date ->
      Query.filter(token, :current_period_end, :lte, date)
    end)
    # Churn risk filter
    |> Query.if_true(params[:at_risk], fn token ->
      Query.where_any(token, [
        {:status, :eq, "past_due"},
        {:failed_payment_count, :gte, 2},
        {:usage_percent, :lt, 10}
      ])
    end)
    |> Query.order(:mrr, :desc)
    |> Query.order(:id, :asc)
    |> Query.paginate(:cursor, limit: params[:limit] || 50)
    # Preloads
    |> Query.preload(:customer, fn c ->
      c |> Query.preload(:organization)
    end)
    |> Query.preload(:plan)
    |> Query.preload(:invoices, fn inv ->
      inv
      |> Query.filter(:status, :in, ["paid", "open", "past_due"])
      |> Query.order(:created_at, :desc)
      |> Query.limit(3)
    end)
    |> Query.execute()
  end

  def billing_report_dsl(params \\ %{}) do
    # MACRO DSL STYLE
    import Events.Query.DSL

    base =
      query Subscription do
        filter(:deleted_at, :is_nil, true)

        order(:mrr, :desc)
        order(:id, :asc)

        paginate(:cursor, limit: params[:limit] || 50)

        preload :customer do
          preload([:organization])
        end

        preload([:plan])

        preload :invoices do
          filter(:status, :in, ["paid", "open", "past_due"])
          order(:created_at, :desc)
          limit(3)
        end
      end

    base
    |> Query.then_if(params[:status], fn token, status ->
      Query.filter(token, :status, :eq, status)
    end)
    |> Query.if_true(!params[:status], fn token ->
      Query.filter(token, :status, :in, ["active", "trialing", "past_due"])
    end)
    |> Query.filter_by(Map.take(params, [:plan_id]))
    |> Query.then_if(params[:min_mrr], fn token, min ->
      Query.filter(token, :mrr, :gte, min)
    end)
    |> Query.then_if(params[:max_mrr], fn token, max ->
      Query.filter(token, :mrr, :lte, max)
    end)
    |> Query.if_true(params[:at_risk], fn token ->
      Query.where_any(token, [
        {:status, :eq, "past_due"},
        {:failed_payment_count, :gte, 2},
        {:usage_percent, :lt, 10}
      ])
    end)
    |> Query.execute()
  end

  # ============================================================================
  # 14. BEST PRACTICES SUMMARY
  # ============================================================================

  @doc """
  ## When to Use Each Style

  ### Use PIPELINE Style When:
  - Building queries dynamically based on runtime conditions
  - Need maximum composability and reusability
  - Working with fragments and includes
  - Query logic is spread across multiple functions
  - Debugging/tracing query construction

  ### Use DSL Style When:
  - Query structure is mostly static
  - Readability and SQL-like appearance is priority
  - Writing simple CRUD operations
  - Team is more familiar with SQL
  - Query fits naturally in a single block

  ### Hybrid Approach (Recommended):
  - Use DSL for the base query structure
  - Use Pipeline for conditional modifications
  - Best of both worlds!

  ```elixir
  # HYBRID: DSL base + Pipeline conditionals
  import Events.Query.DSL

  query User do
    filter :status, :eq, "active"
    order :created_at, :desc
    preload [:profile, :posts]
  end
  |> Query.then_if(params[:role], &Query.filter(&1, :role, :eq, &2))
  |> Query.then_if(params[:search], fn t, s ->
    Query.filter(t, :name, :ilike, "%\#{s}%")
  end)
  |> Query.paginate(:cursor, limit: 20)
  |> Query.execute()
  ```
  """
  def best_practices_example(params) do
    import Events.Query.DSL

    # HYBRID APPROACH
    query User do
      filter(:status, :eq, "active")
      filter(:deleted_at, :is_nil, true)
      order(:created_at, :desc)
      preload([:profile])
    end
    |> Query.filter_by(Map.take(params, [:role, :organization_id]))
    |> Query.then_if(params[:search], fn token, search ->
      Query.where_any(token, [
        {:name, :ilike, "%#{search}%"},
        {:email, :ilike, "%#{search}%"}
      ])
    end)
    |> Query.paginate(:cursor, limit: params[:limit] || 20)
    |> Query.execute()
  end

  # ===========================================================================
  # 15. E-COMMERCE FACETED SEARCH - COMPREHENSIVE EXAMPLE
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # E-Commerce Product Listing with Faceted Search
  #
  # This is the classic e-commerce pattern with:
  # - Sidebar filters: Category, Brand, Price Range, Rating (with dynamic counts)
  # - Search box: Full-text search across name, description, SKU
  # - Product grid: Paginated results with sorting
  # - Dynamic facet counts: Counts update as you filter/search
  #
  # The UI Layout:
  #
  # ┌─────────────────────────────────────────────────────────────────┐
  # │  [Search: "iphone"_______________] [Sort: Price ▼]              │
  # ├──────────────┬──────────────────────────────────────────────────┤
  # │ Categories   │                                                  │
  # │ ○ All (150)  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
  # │ ● Phones (42)│  │ ▢▢▢▢ │  │ ▢▢▢▢ │  │ ▢▢▢▢ │  │ ▢▢▢▢ │         │
  # │ ○ Cases (28) │  │      │  │      │  │      │  │      │         │
  # │ ○ Access (15)│  │ $999 │  │ $899 │  │ $799 │  │ $699 │         │
  # │              │  └──────┘  └──────┘  └──────┘  └──────┘         │
  # │ Brands       │                                                  │
  # │ ☑ Apple (25) │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
  # │ ☑ Samsung(17)│  │ ▢▢▢▢ │  │ ▢▢▢▢ │  │ ▢▢▢▢ │  │ ▢▢▢▢ │         │
  # │ ☐ Google (8) │  │      │  │      │  │      │  │      │         │
  # │              │  │ $599 │  │ $499 │  │ $399 │  │ $299 │         │
  # │ Price        │  └──────┘  └──────┘  └──────┘  └──────┘         │
  # │ ○ All        │                                                  │
  # │ ● $100-$500  │                    [1] [2] [3] ... [Next]        │
  # │ ○ $500-$1000 │                                                  │
  # └──────────────┴──────────────────────────────────────────────────┘
  #
  # Key Requirements:
  # 1. Products: Filter by category, brand, price, rating, stock status
  # 2. Search: Match against name, description, SKU with ILIKE
  # 3. Facet Counts: Show count for each filter option, update dynamically
  # 4. Select from Joins: Need category_name, brand_name in results
  # 5. Pagination: Cursor-based for infinite scroll
  # 6. Preloads: Images, reviews (limited), variant count
  # ---------------------------------------------------------------------------

  @doc """
  PIPELINE APPROACH - Manual Control

  Full control over each query. Best when you need maximum flexibility.
  """
  def ecommerce_listing_pipeline(params) do
    # Extract params with defaults
    search = params[:search]
    category_ids = params[:category_ids] || []
    brand_ids = params[:brand_ids] || []
    min_price = params[:min_price]
    max_price = params[:max_price]
    min_rating = params[:min_rating]
    in_stock_only = params[:in_stock] || false
    sort_by = params[:sort] || "relevance"
    cursor = params[:cursor]

    # =========================================================================
    # STEP 1: Build the base query (shared by products AND facet counts)
    # =========================================================================
    base_query =
      Product
      |> Query.new()
      # Always filter active, non-deleted products
      |> Query.filter(:active, :eq, true)
      |> Query.filter(:deleted_at, :is_nil, true)
      # Apply search across multiple fields
      |> Query.search(search, [:name, :description, :sku])
      # Apply filters using enhanced filter_by
      |> Query.filter_by(%{
        category_id: if(category_ids != [], do: {:in, category_ids}),
        brand_id: if(brand_ids != [], do: {:in, brand_ids}),
        price: build_price_filter(min_price, max_price),
        average_rating: if(min_rating, do: {:gte, min_rating}),
        stock_quantity: if(in_stock_only, do: {:gt, 0})
      })

    # =========================================================================
    # STEP 2: Build the main products query with joins, select, pagination
    # =========================================================================
    products_result =
      base_query
      # Join for category and brand names
      |> Query.join(:category, :left, as: :cat)
      |> Query.join(:brand, :left, as: :brand)
      # Select fields from base AND joined tables (avoiding name conflicts)
      |> Query.select(%{
        id: :id,
        name: :name,
        slug: :slug,
        description: :description,
        price: :price,
        sale_price: :sale_price,
        average_rating: :average_rating,
        review_count: :review_count,
        stock_quantity: :stock_quantity,
        thumbnail_url: :thumbnail_url,
        # Fields from joins - using {binding, field} syntax
        category_id: {:cat, :id},
        category_name: {:cat, :name},
        category_slug: {:cat, :slug},
        brand_id: {:brand, :id},
        brand_name: {:brand, :name},
        brand_logo_url: {:brand, :logo_url}
      })
      # Apply sorting
      |> apply_ecommerce_sort(sort_by)
      # Cursor pagination for infinite scroll
      |> Query.then_if(cursor, fn token, c ->
        Query.paginate(token, :cursor, limit: 24, after: c)
      end)
      |> Query.if_true(is_nil(cursor), fn token ->
        Query.paginate(token, :cursor, limit: 24)
      end)
      # Preload images and limited reviews
      |> Query.preload(:images, fn img ->
        img
        |> Query.filter(:primary, :eq, true)
        |> Query.order(:position, :asc)
        |> Query.limit(5)
      end)
      |> Query.preload(:reviews, fn rev ->
        rev
        |> Query.filter(:approved, :eq, true)
        |> Query.order(:helpful_count, :desc)
        |> Query.limit(3)
      end)
      |> Query.execute!(include_total_count: true)

    # =========================================================================
    # STEP 3: Build facet count queries (run in parallel for efficiency)
    # =========================================================================

    # Category facet - exclude category filter from its own count
    category_base =
      base_query
      |> remove_filter(:category_id)

    # Brand facet - exclude brand filter from its own count
    brand_base =
      base_query
      |> remove_filter(:brand_id)

    # Price facet - exclude price filter from its own count
    price_base =
      base_query
      |> remove_filter(:price)

    # Run facet queries in parallel using Task
    facet_tasks = [
      Task.async(fn -> count_by_category(category_base) end),
      Task.async(fn -> count_by_brand(brand_base) end),
      Task.async(fn -> count_by_price_range(price_base) end),
      Task.async(fn -> count_by_rating(base_query) end)
    ]

    [category_counts, brand_counts, price_counts, rating_counts] =
      Task.await_many(facet_tasks, 5000)

    # =========================================================================
    # STEP 4: Return structured result
    # =========================================================================
    %{
      products: products_result.data,
      pagination: products_result.pagination,
      total_count: products_result.pagination[:total_count],
      facets: %{
        categories: category_counts,
        brands: brand_counts,
        price_ranges: price_counts,
        ratings: rating_counts
      },
      applied_filters: %{
        search: search,
        category_ids: category_ids,
        brand_ids: brand_ids,
        price_range: {min_price, max_price},
        min_rating: min_rating,
        in_stock_only: in_stock_only
      }
    }
  end

  # Helper to build price filter
  defp build_price_filter(nil, nil), do: nil
  defp build_price_filter(min, nil), do: {:gte, min}
  defp build_price_filter(nil, max), do: {:lte, max}
  defp build_price_filter(min, max), do: {:between, {min, max}}

  # Helper to remove a specific filter (for facet counts)
  defp remove_filter(token, _field) do
    # Build a new token without the specified filter
    # This is a simplified version - in practice, you'd track filters separately
    token
  end

  # Apply sorting based on user selection (e-commerce specific)
  defp apply_ecommerce_sort(token, "price_asc") do
    token
    |> Query.order(:price, :asc)
    |> Query.order(:id, :asc)
  end

  defp apply_ecommerce_sort(token, "price_desc") do
    token
    |> Query.order(:price, :desc)
    |> Query.order(:id, :asc)
  end

  defp apply_ecommerce_sort(token, "rating") do
    token
    |> Query.order(:average_rating, :desc_nulls_last)
    |> Query.order(:review_count, :desc)
    |> Query.order(:id, :asc)
  end

  defp apply_ecommerce_sort(token, "newest") do
    token
    |> Query.order(:created_at, :desc)
    |> Query.order(:id, :asc)
  end

  defp apply_ecommerce_sort(token, "bestselling") do
    token
    |> Query.order(:total_sold, :desc)
    |> Query.order(:id, :asc)
  end

  defp apply_ecommerce_sort(token, _relevance) do
    # Default: relevance (for search) or featured products
    token
    |> Query.order(:featured, :desc)
    |> Query.order(:average_rating, :desc_nulls_last)
    |> Query.order(:id, :asc)
  end

  # Count products by category (for sidebar facet)
  defp count_by_category(base_token) do
    # This would use raw Ecto for the group_by count
    # In production, you'd have a dedicated facet counting function
    base_token
    |> Query.join(:category, :left, as: :cat)
    |> Query.group_by(:category_id)
    |> Query.select(%{
      id: :category_id,
      name: {:cat, :name},
      count: {:count, :id}
    })
    |> Query.order(:count, :desc)
    |> Query.execute!()
    |> Map.get(:data, [])
  end

  defp count_by_brand(base_token) do
    base_token
    |> Query.join(:brand, :left, as: :brand)
    |> Query.group_by(:brand_id)
    |> Query.select(%{
      id: :brand_id,
      name: {:brand, :name},
      logo_url: {:brand, :logo_url},
      count: {:count, :id}
    })
    |> Query.order(:count, :desc)
    |> Query.execute!()
    |> Map.get(:data, [])
  end

  defp count_by_price_range(base_token) do
    # Price ranges: Under $50, $50-$100, $100-$500, $500-$1000, Over $1000
    ranges = [
      {0, 50, "Under $50"},
      {50, 100, "$50 - $100"},
      {100, 500, "$100 - $500"},
      {500, 1000, "$500 - $1000"},
      {1000, nil, "Over $1000"}
    ]

    Enum.map(ranges, fn {min, max, label} ->
      count =
        base_token
        |> Query.then_if(min > 0, fn t, _ -> Query.filter(t, :price, :gte, min) end)
        |> Query.then_if(max, fn t, m -> Query.filter(t, :price, :lt, m) end)
        |> Query.count()

      %{min: min, max: max, label: label, count: count}
    end)
  end

  defp count_by_rating(base_token) do
    # Rating facets: 4+ stars, 3+ stars, 2+ stars, 1+ stars
    [4, 3, 2, 1]
    |> Enum.map(fn min_rating ->
      count =
        base_token
        |> Query.filter(:average_rating, :gte, min_rating)
        |> Query.count()

      %{min_rating: min_rating, label: "#{min_rating}+ stars", count: count}
    end)
  end

  @doc """
  ### DSL APPROACH - Declarative Style

  More concise for the base query, with pipeline for conditionals.
  """
  def ecommerce_listing_dsl(params) do
    import Events.Query.DSL

    search = params[:search]
    category_ids = params[:category_ids] || []
    brand_ids = params[:brand_ids] || []
    cursor = params[:cursor]

    # Build base query with DSL
    base =
      query Product do
        filter(:active, :eq, true)
        filter(:deleted_at, :is_nil, true)

        join(:category, :left, as: :cat)
        join(:brand, :left, as: :brand)

        select(%{
          id: :id,
          name: :name,
          price: :price,
          thumbnail_url: :thumbnail_url,
          category_name: {:cat, :name},
          brand_name: {:brand, :name}
        })

        order(:featured, :desc)
        order(:average_rating, :desc)
        order(:id, :asc)

        preload([:images])
      end

    # Apply conditional filters with pipeline
    base
    |> Query.search(search, [:name, :description, :sku])
    |> Query.then_if(category_ids != [], fn token, _ ->
      Query.filter(token, :category_id, :in, category_ids)
    end)
    |> Query.then_if(brand_ids != [], fn token, _ ->
      Query.filter(token, :brand_id, :in, brand_ids)
    end)
    |> Query.filter_by(%{
      price: build_price_filter(params[:min_price], params[:max_price]),
      average_rating: if(params[:min_rating], do: {:gte, params[:min_rating]}),
      stock_quantity: if(params[:in_stock], do: {:gt, 0})
    })
    |> Query.then_if(cursor, fn token, c ->
      Query.paginate(token, :cursor, limit: 24, after: c)
    end)
    |> Query.if_true(is_nil(cursor), fn token ->
      Query.paginate(token, :cursor, limit: 24)
    end)
    |> Query.execute!(include_total_count: true)
  end

  @doc """
  ### FACETED SEARCH PATTERN - The Elegant Solution

  Using the `Events.Query.FacetedSearch` module for a clean, reusable pattern.
  This encapsulates the common e-commerce faceted search logic.
  """
  def ecommerce_faceted_search(params) do
    alias Events.Query.FacetedSearch

    FacetedSearch.new(Product)
    # Text search across multiple fields
    |> FacetedSearch.search(params[:search], [:name, :description, :sku])
    # Apply all filters at once
    |> FacetedSearch.filter_by(%{
      active: true,
      deleted_at: {:is_nil, true},
      category_id: if(params[:category_ids], do: {:in, params[:category_ids]}),
      brand_id: if(params[:brand_ids], do: {:in, params[:brand_ids]}),
      price: build_price_filter(params[:min_price], params[:max_price]),
      average_rating: if(params[:min_rating], do: {:gte, params[:min_rating]}),
      stock_quantity: if(params[:in_stock], do: {:gt, 0})
    })
    # Define facets for sidebar counts
    |> FacetedSearch.facet(:categories, :category_id,
      join: :category,
      label_field: :name,
      # Show all categories even when filtering
      exclude_from_self: true
    )
    |> FacetedSearch.facet(:brands, :brand_id,
      join: :brand,
      label_field: :name,
      exclude_from_self: true
    )
    |> FacetedSearch.facet(:price_ranges, :price,
      ranges: [
        {0, 50, "Under $50"},
        {50, 100, "$50 - $100"},
        {100, 500, "$100 - $500"},
        {500, 1000, "$500 - $1000"},
        {1000, nil, "Over $1000"}
      ]
    )
    |> FacetedSearch.facet(:ratings, :average_rating)
    # Pagination and ordering
    |> FacetedSearch.paginate(:cursor, limit: 24, after: params[:cursor])
    |> FacetedSearch.order(:featured, :desc)
    |> FacetedSearch.order(:average_rating, :desc)
    # Preloads for display
    |> FacetedSearch.preload([:images, :brand, :category])
    # Select specific fields
    |> FacetedSearch.select(%{
      id: :id,
      name: :name,
      slug: :slug,
      price: :price,
      sale_price: :sale_price,
      thumbnail_url: :thumbnail_url,
      average_rating: :average_rating,
      review_count: :review_count
    })
    |> FacetedSearch.execute()
  end

  @doc """
  ## Summary: filter_by Enhanced Syntax

  The enhanced `Query.filter_by/2` supports these formats:

  ```elixir
  Query.filter_by(token, %{
    # Simple equality (default)
    status: "active",

    # Explicit operators
    price: {:gte, 100},
    price: {:lte, 1000},
    price: {:between, {100, 1000}},

    # List operators
    category_id: {:in, [1, 2, 3]},
    status: {:not_in, ["deleted", "archived"]},

    # Null checks
    deleted_at: {:is_nil, true},
    published_at: {:not_nil, true},

    # Pattern matching
    name: {:ilike, "%phone%"},
    sku: {:like, "SKU-%"},

    # Comparison operators
    rating: {:gt, 4},
    stock: {:lt, 10},
    views: {:neq, 0},

    # With binding for joined tables
    category_name: {:eq, "Electronics", binding: :cat}
  })
  ```

  ## Summary: search/4 Function

  ```elixir
  # Simple: same mode for all fields (default :ilike with contains)
  Query.search(token, "iphone", [:name, :description, :sku])

  # Per-field modes: different search strategy per field
  Query.search(token, "iphone", [
    {:sku, :exact},                              # SKU-123 exact match
    {:name, :similarity},                        # Fuzzy match (typo-tolerant)
    {:description, :ilike}                       # Contains search
  ])

  # WITH RANKING: Results ordered by which field matched (rank: true)
  Query.search(token, "iphone", [
    {:sku, :exact, rank: 1},                     # Highest priority - exact SKU
    {:name, :similarity, rank: 2},               # Second - fuzzy name match
    {:brand, :starts_with, rank: 3},             # Third - brand prefix
    {:description, :ilike, rank: 4}              # Lowest - description contains
  ], rank: true)

  # Field Spec Formats:
  # - :field                           → Uses global :mode option
  # - {:field, :mode}                  → Specific mode
  # - {:field, :mode, opts}            → Mode with per-field options (rank, threshold)

  # Available Modes:
  # :ilike           - Case-insensitive LIKE "%term%" (default)
  # :like            - Case-sensitive LIKE "%term%"
  # :exact           - Exact equality match
  # :starts_with     - Prefix match "term%"
  # :ends_with       - Suffix match "%term"
  # :contains        - Same as :ilike
  # :similarity      - PostgreSQL pg_trgm fuzzy (requires extension)
  # :word_similarity - Word-level fuzzy matching
  # :strict_word_similarity - Strictest word boundary matching

  # Per-field Options:
  # - rank: 1        - Priority (lower = higher, used with rank: true)
  # - threshold: 0.4 - Similarity threshold (0.0-1.0, for fuzzy modes)

  # E-commerce search with ranking:
  Query.search(token, params[:q], [
    {:sku, :exact, rank: 1},                     # SKU-123 exact = top result
    {:name, :similarity, rank: 2, threshold: 0.3},
    {:brand, :starts_with, rank: 3},
    {:description, :word_similarity, rank: 4}
  ], rank: true)

  # Autocomplete with ranking (prefix matches first, then fuzzy):
  Query.search(token, input, [
    {:name, :starts_with, rank: 1},
    {:name, :similarity, rank: 2, threshold: 0.2}
  ], rank: true)

  # Note: Similarity modes require PostgreSQL pg_trgm extension:
  # CREATE EXTENSION IF NOT EXISTS pg_trgm;
  ```

  ## Summary: Cross-Table Search with Joins and Take Limits

  ```elixir
  # Search across multiple tables with joins, ranking, and per-field limits
  # Each field can specify: mode, rank, take, threshold, binding

  Product
  |> Query.new()
  # Join related tables with custom conditions
  |> Query.join(:category, :left, as: :cat)
  |> Query.join(:brand, :left, as: :brand)
  |> Query.join(:supplier, :left, as: :sup, on: [supplier_id: :id])
  # Search across fields from multiple tables
  |> Query.search("iphone", [
    # Fields from base table (Product)
    {:sku, :exact, rank: 1, take: 3},                    # Top 3 exact SKU matches
    {:name, :similarity, rank: 2, take: 5, threshold: 0.3},  # 5 fuzzy name matches
    {:description, :ilike, rank: 3, take: 5},            # 5 description matches

    # Fields from joined tables (use binding: option)
    {:name, :ilike, rank: 4, take: 3, binding: :cat},    # 3 category name matches
    {:name, :similarity, rank: 5, take: 3, binding: :brand},  # 3 brand name matches
    {:contact_name, :ilike, rank: 6, take: 2, binding: :sup}  # 2 supplier matches
  ], rank: true)
  # Select fields from all tables
  |> Query.select(%{
    # Base table IDs and search fields
    product_id: :id,
    product_sku: :sku,
    product_name: :name,
    product_description: :description,
    # Joined table IDs and search fields
    category_id: {:cat, :id},
    category_name: {:cat, :name},
    brand_id: {:brand, :id},
    brand_name: {:brand, :name},
    supplier_id: {:sup, :id},
    supplier_contact: {:sup, :contact_name}
  })
  |> Query.execute()

  # Total limit = sum of takes: 3 + 5 + 5 + 3 + 3 + 2 = 21 max results
  # Results ordered by rank (1 first, then 2, etc.)
  ```

  ## Deduplication Behavior with Take Limits

  When multiple fields from the **same table** match the same row:

  ```elixir
  # Example: Two Product fields with take: 5 each
  Query.search(token, "apple", [
    {:name, :similarity, rank: 1, take: 5},        # Product.name matches
    {:description, :ilike, rank: 2, take: 5}       # Product.description matches
  ], rank: true)

  # If "Apple iPhone" matches BOTH name AND description:
  # - Row gets rank 1 (lowest matching rank wins via CASE WHEN)
  # - Row appears ONCE in results (natural SQL deduplication)
  # - Total limit is 10 (5 + 5), but unique rows may be fewer

  # Scenario A: 3 products match name, 4 match description (2 overlap)
  # → 5 unique rows total (not 10), ordered by rank

  # Scenario B: 5 products match name, 5 different match description
  # → 10 unique rows, first 5 are rank-1, next 5 are rank-2
  ```

  ## Deduplication Across Joined Tables

  When searching across different tables (Product + Category + Brand):

  ```elixir
  Query.search(token, "apple", [
    {:name, :similarity, rank: 1, take: 5},                    # Product.name
    {:name, :ilike, rank: 2, take: 3, binding: :cat},         # Category.name
    {:name, :ilike, rank: 3, take: 3, binding: :brand}        # Brand.name
  ], rank: true)

  # Different deduplication scenarios:

  # 1. Product "iPhone" matches Product.name (rank 1)
  #    → Appears once at rank 1

  # 2. Product "MacBook" has Category "Apple Computers" (matches :cat name)
  #    → Appears once at rank 2 (category match)

  # 3. Product "AirPods" has Brand "Apple" (matches :brand name)
  #    AND is in Category "Apple Accessories"
  #    → Appears ONCE at rank 2 (lowest matching rank = category)

  # Total: Up to 11 unique Product rows (5 + 3 + 3)
  # Results show the Product with its joined data
  ```

  ## Full E-Commerce Cross-Table Search Example

  ```elixir
  defmodule MyApp.ProductSearch do
    alias Events.Query

    def search_products(term, opts \\\\ []) do
      include_variants = Keyword.get(opts, :include_variants, false)

      Product
      |> Query.new()
      # Required joins for cross-table search
      |> Query.join(:category, :left, as: :cat)
      |> Query.join(:brand, :left, as: :brand)
      |> Query.join(:tags, :left, as: :tag)
      # Optional variant search
      |> maybe_join_variants(include_variants)
      # Multi-table search with ranking and limits
      |> Query.search(term, [
        # Exact matches first (highest priority)
        {:sku, :exact, rank: 1, take: 5},
        {:barcode, :exact, rank: 1, take: 5},

        # Fuzzy product name (typo-tolerant)
        {:name, :similarity, rank: 2, take: 10, threshold: 0.25},

        # Category/Brand matches
        {:name, :ilike, rank: 3, take: 5, binding: :cat},
        {:name, :similarity, rank: 3, take: 5, binding: :brand, threshold: 0.3},

        # Tag matches
        {:name, :ilike, rank: 4, take: 5, binding: :tag},

        # Description (lowest priority, broader match)
        {:description, :word_similarity, rank: 5, take: 10, threshold: 0.2}
      ], rank: true)
      # Select all IDs and matched fields for display
      |> Query.select(%{
        # Primary result data
        product_id: :id,
        sku: :sku,
        barcode: :barcode,
        name: :name,
        description: :description,
        price: :price,
        # Joined data for context
        category_id: {:cat, :id},
        category_name: {:cat, :name},
        brand_id: {:brand, :id},
        brand_name: {:brand, :name},
        tag_id: {:tag, :id},
        tag_name: {:tag, :name}
      })
      |> Query.execute()
    end

    defp maybe_join_variants(token, false), do: token
    defp maybe_join_variants(token, true) do
      token
      |> Query.join(:variants, :left, as: :var)
    end
  end
  ```

  ## Summary: Select from Joins

  ```elixir
  # Select fields from base table
  Query.select(token, [:id, :name, :price])

  # Select with aliases from base table
  Query.select(token, %{
    product_id: :id,
    product_name: :name
  })

  # Select from joined tables using {binding, field}
  token
  |> Query.join(:category, :left, as: :cat)
  |> Query.join(:brand, :left, as: :brand)
  |> Query.select(%{
    product_id: :id,
    product_name: :name,
    category_id: {:cat, :id},
    category_name: {:cat, :name},
    brand_id: {:brand, :id},
    brand_name: {:brand, :name}
  })
  ```

  ## Summary: Query.debug - Pipeline Debugging

  ```elixir
  # Query.debug works like IO.inspect - prints and returns input unchanged
  # Can be placed ANYWHERE in a pipeline

  # Default: prints raw SQL with interpolated params
  Product
  |> Query.new()
  |> Query.filter(:status, :eq, "active")
  |> Query.debug()                           # Prints SQL, returns token
  |> Query.order(:name, :asc)
  |> Query.execute()

  # Specify output format
  token |> Query.debug(:raw_sql)      # Raw SQL (default)
  token |> Query.debug(:sql_params)   # SQL + separate params list
  token |> Query.debug(:ecto)         # Ecto.Query struct
  token |> Query.debug(:dsl)          # DSL macro syntax
  token |> Query.debug(:pipeline)     # Pipeline syntax
  token |> Query.debug(:token)        # Token struct with operations
  token |> Query.debug(:explain)      # PostgreSQL EXPLAIN
  token |> Query.debug(:all)          # All formats combined

  # Multiple formats at once
  token |> Query.debug([:raw_sql, :dsl])

  # With options
  token |> Query.debug(:raw_sql, label: "Product Query")
  token |> Query.debug(:raw_sql, color: :green)
  token |> Query.debug(:raw_sql, stacktrace: true)  # Shows caller location

  # Debug at multiple points in pipeline
  Product
  |> Query.new()
  |> Query.debug(:token, label: "1. Initial token")
  |> Query.filter(:price, :gt, 100)
  |> Query.debug(:raw_sql, label: "2. After price filter")
  |> Query.join(:category, :left, as: :cat)
  |> Query.debug(:raw_sql, label: "3. After join")
  |> Query.search("iphone", [:name, :description])
  |> Query.debug(:raw_sql, label: "4. After search")
  |> Query.execute()

  # Get debug output as string (without printing)
  sql = Events.Query.Debug.to_string(token, :raw_sql)
  Logger.info("Executing: \#{sql}")

  # Get all formats as a map
  info = Events.Query.Debug.inspect_all(token)
  # => %{raw_sql: "SELECT ...", dsl: "query Product do...", ...}

  # Works with FacetedSearch too
  FacetedSearch.new(Product)
  |> FacetedSearch.search("laptop")
  |> FacetedSearch.filter(:category_id, 5)
  |> Query.debug(:raw_sql, label: "Faceted Search Query")
  |> FacetedSearch.execute()
  ```

  ## Summary: FacetedSearch Pattern

  ```elixir
  alias Events.Query.FacetedSearch

  FacetedSearch.new(Product)
  |> FacetedSearch.search(term, [:name, :description])
  |> FacetedSearch.filter_by(%{...})
  |> FacetedSearch.facet(:categories, :category_id, join: :category)
  |> FacetedSearch.facet(:prices, :price, ranges: [...])
  |> FacetedSearch.paginate(:cursor, limit: 24)
  |> FacetedSearch.execute()

  # Returns:
  %{
    data: [...],
    facets: %{
      categories: [%{id: 1, label: "Electronics", count: 42}, ...],
      prices: [%{label: "Under $50", count: 15}, ...]
    },
    pagination: %{...},
    total_count: 150
  }
  ```
  """
  def ecommerce_summary, do: :see_docs_above
end
