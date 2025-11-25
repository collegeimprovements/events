defmodule Events.Query.NestedExample do
  @moduledoc false
  # Example module - not part of public API.
  #
  # Comprehensive 3-level nested preload example with filters and pagination.
  # Demonstrates deep nesting capabilities of the query system.

  # Suppress warnings for undefined schemas
  @compile {:no_warn_undefined, [Organization, User, Post, Comment, Tag]}

  import Events.Query.DSL
  alias Events.Query

  # Suppress warnings for undefined schemas (documentation example)
  @compile {:no_warn_undefined, [Organization, User, Post, Comment, Tag]}

  @doc """
  Example 1: Basic 3-level nested preload.

  ## Structure

      Organization
      └── users (active only, limit 50)
          └── posts (published only, limit 10)
              └── comments (approved only, limit 5)

  ## Result

  Returns an organization with its active users, their published posts,
  and approved comments on those posts.
  """
  def basic_three_level_nesting do
    query Organization do
      filter(:status, :eq, "active")

      # Level 1: Preload users
      preload :users do
        filter(:status, :eq, "active")
        order(:name, :asc)
        limit(50)

        # Level 2: Preload posts for each user
        preload :posts do
          filter(:status, :eq, "published")
          order(:published_at, :desc)
          limit(10)

          # Level 3: Preload comments for each post
          preload :comments do
            filter(:status, :eq, "approved")
            order(:created_at, :desc)
            limit(5)
          end
        end
      end
    end
  end

  @doc """
  Example 2: 3-level nesting with pagination at each level.

  ## Structure

      Organization
      └── users (paginated: 20 per page)
          └── posts (paginated: 5 per page per user)
              └── comments (paginated: 3 per page per post)

  This demonstrates offset pagination at every level.
  """
  def three_level_with_pagination(user_page \\ 1, post_page \\ 1, comment_page \\ 1) do
    query Organization do
      filter(:status, :eq, "active")

      # Level 1: Users with offset pagination
      preload :users do
        filter(:status, :eq, "active")
        order(:created_at, :desc)
        paginate(:offset, limit: 20, offset: (user_page - 1) * 20)

        # Level 2: Posts with offset pagination
        preload :posts do
          filter(:status, :eq, "published")
          order(:published_at, :desc)
          paginate(:offset, limit: 5, offset: (post_page - 1) * 5)

          # Level 3: Comments with offset pagination
          preload :comments do
            filter(:status, :eq, "approved")
            order(:created_at, :desc)
            paginate(:offset, limit: 3, offset: (comment_page - 1) * 3)
          end
        end
      end
    end
  end

  @doc """
  Example 3: 3-level nesting with cursor pagination.

  ## Structure

      Organization
      └── users (cursor-based)
          └── posts (cursor-based)
              └── comments (cursor-based)

  This demonstrates cursor pagination for infinite scroll scenarios.
  """
  def three_level_with_cursors(user_cursor \\ nil, post_cursor \\ nil, comment_cursor \\ nil) do
    query Organization do
      filter(:status, :eq, "active")

      # Level 1: Users with cursor pagination
      preload :users do
        filter(:status, :eq, "active")
        order(:created_at, :desc)
        order(:id, :desc)

        paginate(:cursor,
          cursor_fields: [:created_at, :id],
          limit: 20,
          after: user_cursor
        )

        # Level 2: Posts with cursor pagination
        preload :posts do
          filter(:status, :eq, "published")
          order(:published_at, :desc)
          order(:id, :desc)

          paginate(:cursor,
            cursor_fields: [:published_at, :id],
            limit: 10,
            after: post_cursor
          )

          # Level 3: Comments with cursor pagination
          preload :comments do
            filter(:status, :eq, "approved")
            order(:created_at, :desc)
            order(:id, :desc)

            paginate(:cursor,
              cursor_fields: [:created_at, :id],
              limit: 5,
              after: comment_cursor
            )
          end
        end
      end
    end
  end

  @doc """
  Example 4: 3-level nesting with multiple filters and complex conditions.

  ## Structure

      Organization
      └── users (admins and editors only, created in last 30 days)
          └── posts (published, views > 100, with specific tags)
              └── comments (approved, not flagged, from verified users)

  Demonstrates complex filtering at each level.
  """
  def three_level_with_complex_filters do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    query Organization do
      filter(:status, :eq, "active")
      filter(:verified, :eq, true)

      # Level 1: Users with multiple filters
      preload :users do
        filter(:status, :eq, "active")
        filter(:role, :in, ["admin", "editor"])
        filter(:created_at, :gte, thirty_days_ago)
        filter(:email_verified, :eq, true)
        order(:last_login_at, :desc)
        limit(50)

        # Level 2: Posts with complex filters
        preload :posts do
          filter(:status, :eq, "published")
          filter(:views, :gte, 100)
          filter(:published_at, :gte, thirty_days_ago)
          filter(:featured, :eq, true)
          order(:views, :desc)
          order(:published_at, :desc)
          limit(20)

          # Level 3: Comments with strict filters
          preload :comments do
            filter(:status, :eq, "approved")
            filter(:flagged, :eq, false)
            filter(:spam_score, :lt, 0.3)
            order(:helpful_count, :desc)
            limit(10)
          end
        end
      end
    end
  end

  @doc """
  Example 5: 3-level nesting with multiple associations at each level.

  ## Structure

      Organization
      ├── users (with filters)
      │   ├── posts (with comments)
      │   │   └── comments
      │   └── profile (single association)
      └── departments (separate association)

  Demonstrates mixing multiple associations at different levels.
  """
  def three_level_with_multiple_associations do
    query Organization do
      filter(:status, :eq, "active")

      # Multiple Level 1 preloads
      preload :users do
        filter(:status, :eq, "active")
        limit(100)

        # Multiple Level 2 preloads
        preload :posts do
          filter(:status, :eq, "published")
          limit(10)

          # Level 3 preload
          preload :comments do
            filter(:status, :eq, "approved")
            limit(5)
          end

          # Another Level 3 preload at same level
          preload :tags do
            filter(:active, :eq, true)
          end
        end

        # Another Level 2 preload
        preload(:profile)
      end

      # Another Level 1 preload
      preload :departments do
        filter(:active, :eq, true)
        order(:name, :asc)
      end
    end
  end

  @doc """
  Example 6: Pipeline style with 3-level nesting.

  Same as basic example but using pipeline API instead of DSL.
  """
  def three_level_pipeline_style do
    Organization
    |> Query.new()
    |> Query.filter(:status, :eq, "active")
    |> Query.preload(:users, fn users_token ->
      users_token
      |> Query.filter(:status, :eq, "active")
      |> Query.order(:name, :asc)
      |> Query.limit(50)
      |> Query.preload(:posts, fn posts_token ->
        posts_token
        |> Query.filter(:status, :eq, "published")
        |> Query.order(:published_at, :desc)
        |> Query.limit(10)
        |> Query.preload(:comments, fn comments_token ->
          comments_token
          |> Query.filter(:status, :eq, "approved")
          |> Query.order(:created_at, :desc)
          |> Query.limit(5)
        end)
      end)
    end)
  end

  @doc """
  Example 7: Real-world use case - Dashboard data loading.

  Loads an organization's dashboard with:
  - Recent active users
  - Their trending posts
  - Top comments on those posts

  Each level has specific business logic applied.
  """
  def dashboard_data_loading do
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    query Organization do
      filter(:status, :eq, "active")

      # Recent active users
      preload :users do
        filter(:status, :eq, "active")
        filter(:last_login_at, :gte, seven_days_ago)
        order(:last_login_at, :desc)
        limit(25)

        # Trending posts (high engagement in last 7 days)
        preload :posts do
          filter(:status, :eq, "published")
          filter(:published_at, :gte, seven_days_ago)
          filter(:views, :gte, 50)
          order(:views, :desc)
          order(:comments_count, :desc)
          limit(5)

          # Top comments (most helpful)
          preload :comments do
            filter(:status, :eq, "approved")
            filter(:created_at, :gte, seven_days_ago)
            order(:helpful_count, :desc)
            limit(3)
          end
        end
      end
    end
  end

  @doc """
  Example 8: Inspecting nested token structure.

  Shows how to inspect the token to see all nested operations.
  """
  def inspect_nested_token do
    token = basic_three_level_nesting()

    IO.puts("\n=== Nested Token Structure ===\n")
    IO.puts("Root source: #{inspect(token.source)}")
    IO.puts("Root operations count: #{length(token.operations)}\n")

    # Find preload operations
    preload_ops = Events.Query.Token.get_operations(token, :preload)

    Enum.each(preload_ops, fn {:preload, preload_spec} ->
      case preload_spec do
        {assoc, nested_token} ->
          IO.puts("Preload: #{assoc}")
          IO.puts("  Operations: #{length(nested_token.operations)}")
          inspect_nested_preloads(nested_token, "  ")

        _ ->
          :ok
      end
    end)

    token
  end

  # Helper to recursively inspect nested preloads
  defp inspect_nested_preloads(token, indent) do
    preload_ops = Events.Query.Token.get_operations(token, :preload)

    Enum.each(preload_ops, fn {:preload, preload_spec} ->
      case preload_spec do
        {assoc, nested_token} ->
          IO.puts("#{indent}└─ #{assoc}")
          IO.puts("#{indent}   Operations: #{length(nested_token.operations)}")
          inspect_nested_preloads(nested_token, indent <> "   ")

        _ ->
          :ok
      end
    end)
  end
end
