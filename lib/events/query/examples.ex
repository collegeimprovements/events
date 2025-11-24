defmodule Events.Query.Examples do
  @moduledoc """
  Comprehensive examples demonstrating the query system.

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
end
