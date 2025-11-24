# Example usage of the complete Events.CRUD system

# Import the DSL
import Events.CRUD.DSL

# 1. CREATE - Simple user creation
create(User, %{name: "John Doe", email: "john@example.com", status: "active"})

# 2. GET - Find user by ID with preloads
get(User, 123,
  preload: [
    {:posts,
     [
       where: {:status, :eq, "published", []},
       order: {:published_at, :desc},
       limit: 5
     ]},
    {:profile, []}
  ]
)

# 3. LIST - Complex filtering with joins and raw SQL
query User do
  # Regular Ecto filters
  where(:status, :eq, "active")
  where(:age, :gte, 18)

  # Join with conditions
  join(:posts, :left, [])
  where({:posts, :published}, :eq, true)

  # Raw SQL fragments
  raw_where("EXTRACT(YEAR FROM users.created_at) = :year", %{year: 2024})

  # Ordering and pagination
  order(:created_at, :desc)
  paginate(:offset, limit: 20, offset: 0)

  # Preloads with nested conditions
  preload :posts do
    where(:status, :eq, "published")
    order(:views, :desc)
    limit(10)

    preload :comments do
      where(:approved, :eq, true)
      order(:likes_count, :desc)
      limit(5)
    end
  end
end
|> execute()

# 4. UPDATE - Update with conditions
update(user, %{status: "inactive"})

# 5. Raw SQL Queries - Complex analytics
query do
  raw(
    """
    WITH user_stats AS (
      SELECT
        u.id,
        u.name,
        COUNT(p.id) as post_count,
        AVG(p.views) as avg_views,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.id) DESC) as activity_rank
      FROM users u
      LEFT JOIN posts p ON p.user_id = u.id AND p.status = :post_status
      WHERE u.created_at >= :start_date
      GROUP BY u.id, u.name
    ),
    top_categories AS (
      SELECT
        c.id,
        c.name,
        COUNT(p.id) as posts_in_category,
        RANK() OVER (ORDER BY COUNT(p.id) DESC) as category_rank
      FROM categories c
      LEFT JOIN posts p ON p.category_id = c.id
      GROUP BY c.id, c.name
    )
    SELECT
      us.id,
      us.name,
      us.post_count,
      us.avg_views,
      us.activity_rank,
      tc.name as top_category,
      tc.category_rank
    FROM user_stats us
    LEFT JOIN top_categories tc ON tc.id = (
      SELECT p.category_id
      FROM posts p
      WHERE p.user_id = us.id
      GROUP BY p.category_id
      ORDER BY COUNT(*) DESC
      LIMIT 1
    )
    WHERE us.post_count > :min_posts
    ORDER BY us.activity_rank
    LIMIT :limit OFFSET :offset
    """,
    %{
      post_status: "published",
      start_date: ~U[2024-01-01 00:00:00Z],
      min_posts: 1,
      limit: 50,
      offset: 0
    }
  )
end
|> execute()

# 6. Aggregation with GROUP BY and HAVING
query Order do
  select(%{total: sum(:amount), count: count(:id)})
  group([:status])
  having(count: {:gt, 10})
  order(:total, :desc)
end
|> execute()

# 7. Window Functions (when implemented)
query Product do
  select(%{
    id: :id,
    name: :name,
    price: :price,
    category_rank: {:window, :rank, [partition_by: :category_id, order_by: [desc: :price]]}
  })

  order(:category_rank, :asc)
end
|> execute()

# 8. Complex Composition
def active_users_query(limit) do
  query User do
    where(:status, :eq, "active")
    order(:created_at, :desc)
    paginate(:offset, limit: limit)
  end
end

def with_posts_preload(query_token) do
  Token.add(
    query_token,
    {:preload,
     {:posts,
      [
        {:where, {:status, :eq, "published", []}},
        {:order, {:views, :desc, []}},
        {:limit, 5}
      ]}}
  )
end

# Compose operations
active_users_query(10)
|> with_posts_preload()
|> execute()

# 9. Cursor-based Pagination
query Post do
  where(:status, :eq, "published")
  order(:published_at, :desc)
  # Tie-breaker for cursor pagination
  order(:id, :asc)
  paginate(:cursor, limit: 20, cursor_fields: [published_at: :desc, id: :asc])
end
|> execute()

# 10. Error Handling
case get(User, 999) do
  %Result{success: true, data: user} -> {:ok, user}
  %Result{success: false, error: :not_found} -> {:error, :user_not_found}
  %Result{success: false, error: changeset} -> {:error, changeset}
end
