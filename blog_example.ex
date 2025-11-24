defmodule BlogExample do
  @moduledoc """
  Complete example showing all CRUD features in a blog application context.
  """

  # Import the DSL for clean query syntax
  import Events.CRUD.DSL

  @doc """
  Example 2: Cursor pagination for infinite scroll
  Get posts with cursor-based pagination for better performance
  """
  def get_posts_cursor_paginated(cursor \\ nil) do
    query Post do
      where(:status, :eq, "published")
      where(:published_at, :lte, DateTime.utc_now())

      # Join with user for author info
      join(:user, :inner)

      # Preload author data
      preload(:user, select: [:id, :name, :avatar_url])

      # Sort by published date (newest first), then by ID for stable pagination
      order(:published_at, :desc)
      order(:id, :desc)

      # Cursor pagination with composite key
      paginate(:cursor, limit: 10, cursor: cursor, cursor_fields: [published_at: :desc, id: :desc])

      # Select post fields
      select([:id, :title, :excerpt, :published_at, :slug])
    end
  end

  @doc """
  Example 3: Raw SQL with complex aggregations
  Get user engagement statistics using raw SQL
  """
  def get_user_engagement_stats() do
    query do
      raw(
        """
        WITH user_stats AS (
          SELECT
            u.id,
            u.name,
            COUNT(DISTINCT p.id) as post_count,
            COUNT(DISTINCT c.id) as comment_count,
            COALESCE(AVG(p.views), 0) as avg_views,
            MAX(p.published_at) as last_post_date
          FROM users u
          LEFT JOIN posts p ON p.user_id = u.id AND p.status = 'published'
          LEFT JOIN comments c ON c.user_id = u.id AND c.approved = true
          WHERE u.status = 'active'
          GROUP BY u.id, u.name
        )
        SELECT * FROM user_stats
        WHERE post_count > 0
        ORDER BY post_count DESC, avg_views DESC
        LIMIT :limit
        """,
        %{
          limit: 50
        }
      )
    end
  end

  @doc """
  Example 4: CRUD operations - Create a new post
  """
  def create_blog_post(user_id, attrs) do
    # Validate input
    with {:ok, valid_attrs} <- validate_post_attrs(attrs) do
      # Create the post
      case create Post, Map.put(valid_attrs, :user_id, user_id) do
        %Events.CRUD.Result{success: true, data: post} ->
          IO.puts("Created post: #{post.title}")
          {:ok, post}

        %Events.CRUD.Result{success: false, error: error} ->
          IO.puts("Failed to create post: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  @doc """
  Example 5: CRUD operations - Update with optimistic locking
  """
  def update_post_with_comments(post_id, updates) do
    # First get the post with current comment count
    case get Post, post_id, preload: [:comments] do
      %Events.CRUD.Result{success: true, data: post} ->
        comment_count = length(post.comments)

        # Update the post
        case update(post, Map.put(updates, :comment_count, comment_count)) do
          %Events.CRUD.Result{success: true, data: updated_post} ->
            IO.puts("Updated post: #{updated_post.title}")
            {:ok, updated_post}

          %Events.CRUD.Result{success: false, error: error} ->
            {:error, error}
        end

      %Events.CRUD.Result{success: false, error: :not_found} ->
        {:error, :post_not_found}
    end
  end

  @doc """
  Example 6: Batch operations using direct API
  Update multiple posts at once
  """
  def publish_draft_posts(user_id) do
    # Build token manually for complex operations
    token =
      Events.CRUD.new_token()
      |> Events.CRUD.where(:user_id, :eq, user_id)
      |> Events.CRUD.where(:status, :eq, "draft")
      |> Events.CRUD.where(:ready_for_publish, :eq, true)
      |> Events.CRUD.order(:created_at, :asc)
      |> Events.CRUD.limit(10)

    # Get posts to update
    case Events.CRUD.execute(token) do
      %Events.CRUD.Result{success: true, data: drafts} ->
        IO.puts("Found #{length(drafts)} drafts ready for publishing")

        # Update each post
        results =
          Enum.map(drafts, fn draft ->
            publish_attrs = %{
              status: "published",
              published_at: DateTime.utc_now(),
              slug: generate_slug(draft.title)
            }

            case update(draft, publish_attrs) do
              %Events.CRUD.Result{success: true, data: post} ->
                {:ok, post}

              error ->
                {:error, {draft.id, error}}
            end
          end)

        # Analyze results
        successful = Enum.count(results, &match?({:ok, _}, &1))
        failed = Enum.count(results, &match?({:error, _}, &1))

        IO.puts("Published #{successful} posts, #{failed} failed")
        {:ok, %{successful: successful, failed: failed, results: results}}

      error ->
        {:error, error}
    end
  end

  @doc """
  Example 7: Advanced token manipulation
  Build and modify queries dynamically
  """
  def build_dynamic_query(filters, sort_options, pagination) do
    # Start with base token
    token = Events.CRUD.new_token()

    # Add dynamic filters
    token =
      Enum.reduce(filters, token, fn {field, op, value}, acc ->
        Events.CRUD.where(acc, field, op, value)
      end)

    # Add sorting
    token =
      case sort_options do
        %{field: field, direction: dir} ->
          Events.CRUD.order(token, field, dir)

        _ ->
          Events.CRUD.order(token, :created_at, :desc)
      end

    # Add pagination
    token =
      case pagination do
        %{type: :cursor, cursor: cursor, limit: limit} ->
          Events.CRUD.paginate(token, :cursor, cursor: cursor, limit: limit)

        %{type: :offset, page: page, limit: limit} ->
          offset = (page - 1) * limit
          Events.CRUD.paginate(token, :offset, limit: limit, offset: offset)

        _ ->
          Events.CRUD.paginate(token, :offset, limit: 20)
      end

    # Execute the query
    Events.CRUD.execute(token)
  end

  @doc """
  Example 1: Complex query with multiple operations using DSL
  Find active users with their recent published posts and comment counts
  """
  def find_active_users_with_stats() do
    result =
      query User do
        # Filter active users created in the last 30 days
        where(:status, :eq, "active")
        where(:created_at, :gte, ~U[2024-01-01 00:00:00Z])

        # Debug: Show query after initial filtering
        debug("After user filtering")

        # Join with posts for additional filtering
        join(:posts, :left)

        # Preload posts with nested conditions
        preload :posts do
          where(:status, :eq, "published")
          where(:published_at, :lte, DateTime.utc_now())
          order(:published_at, :desc)
          limit(5)

          # Preload comments for each post
          preload :comments do
            where(:approved, :eq, true)
            order(:created_at, :desc)
          end
        end

        # Debug: Show final query before execution
        debug("Final query with preloads")

        # Sort users by creation date
        order(:created_at, :desc)

        # Paginate results
        paginate(:offset, limit: 20, offset: 0)

        # Select specific fields
        select([:id, :name, :email, :created_at])
      end

    case result do
      %Events.CRUD.Result{success: true, data: users, metadata: meta} ->
        IO.puts("Found #{length(users)} users")
        IO.puts("Pagination: #{inspect(meta.pagination)}")

        # Process each user with their posts
        Enum.each(users, fn user ->
          post_count = length(user.posts)

          total_comments =
            user.posts
            |> Enum.map(&length(&1.comments))
            |> Enum.sum()

          IO.puts("#{user.name}: #{post_count} posts, #{total_comments} comments")
        end)

        {:ok, users}

      %Events.CRUD.Result{success: false, error: error} ->
        IO.puts("Query failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Example 11: Debug query execution
  Show how to use debug operations to inspect queries
  """
  def debug_query_example() do
    result =
      query User do
        # Initial filtering
        where(:status, :eq, "active")
        debug("After status filter")

        # Add more conditions
        where(:created_at, :gte, ~U[2024-01-01 00:00:00Z])
        debug("After date filter")

        # Join and preload
        join(:posts, :left)
        preload(:posts, limit: 3)
        debug("After join and preload")

        # Final operations
        order(:created_at, :desc)
        limit(10)
        debug("Final query")
      end

    case result do
      %Events.CRUD.Result{success: true, data: users} ->
        IO.puts("Found #{length(users)} users")
        {:ok, users}

      error ->
        {:error, error}
    end
  end

  @doc """
  Example 9: Complex analytics query with grouping
  Get post performance statistics by category
  """
  def get_post_performance_by_category() do
    query Post do
      where(:status, :eq, "published")
      where(:published_at, :gte, ~U[2024-01-01 00:00:00Z])

      # Join with categories
      join(:category, :inner)

      # Group by category
      group([:category_id])

      # Select aggregated data
      select(%{
        category_id: :category_id,
        category_name: :category__name,
        post_count: {:count, :id},
        total_views: {:sum, :views},
        avg_views: {:avg, :views},
        max_views: {:max, :views},
        min_views: {:min, :views}
      })

      # Filter groups with minimum posts
      having(post_count: {:gte, 5})

      # Sort by total views
      order({:total_views, :desc})

      # Limit results
      limit(20)
    end
  end

  @doc """
  Example 10: Using the system for admin operations
  Bulk user status updates with transaction safety
  """
  def bulk_update_user_status(user_ids, new_status) do
    # Validate inputs
    valid_statuses = ["active", "inactive", "suspended"]

    if new_status not in valid_statuses do
      {:error, :invalid_status}
    else
      # Get users to update
      token =
        Events.CRUD.new_token()
        |> Events.CRUD.where(:id, :in, user_ids)
        |> Events.CRUD.select([:id, :name, :status])

      case Events.CRUD.execute(token) do
        %Events.CRUD.Result{success: true, data: users} ->
          IO.puts("Updating #{length(users)} users to status: #{new_status}")

          # Update each user
          results =
            Enum.map(users, fn user ->
              case update(user, %{status: new_status}) do
                %Events.CRUD.Result{success: true, data: updated_user} ->
                  {:ok, updated_user}

                error ->
                  {:error, {user.id, error}}
              end
            end)

          # Return summary
          successful = Enum.count(results, &match?({:ok, _}, &1))
          {:ok, %{total: length(users), successful: successful, results: results}}

        error ->
          {:error, error}
      end
    end
  end

  @doc """
  Example 11: Advanced joins with custom on conditions
  Show how to use custom join conditions for complex relationships
  """
  def advanced_joins_example() do
    result =
      query User do
        # Basic filtering
        where(:status, :eq, "active")

        # Association join (standard)
        join(:posts, :left)

        # Custom join with on condition
        join(Post, :published_posts,
          on:
            published_posts.user_id == user.id and
              published_posts.status == "published" and
              published_posts.published_at <= ^DateTime.utc_now(),
          type: :inner
        )

        # Another custom join
        join(Comment, :approved_comments,
          on:
            approved_comments.post_id == published_posts.id and
              approved_comments.approved == true,
          type: :left
        )

        # Select with aggregations
        select(%{
          user_id: :id,
          user_name: :name,
          post_count: count(published_posts.id),
          comment_count: count(approved_comments.id)
        })

        # Group and filter
        group([:id, :name])
        having(post_count: {:gte, 1})

        # Order by engagement
        order({:comment_count, :desc})

        limit(20)
      end

    case result do
      %Events.CRUD.Result{success: true, data: stats} ->
        IO.puts("Found #{length(stats)} user engagement stats")

        Enum.each(stats, fn stat ->
          IO.puts("#{stat.user_name}: #{stat.post_count} posts, #{stat.comment_count} comments")
        end)

      _ ->
        IO.puts("Query failed")
    end
  end

  @doc """
  Example 12: Pure functions with custom joins
  Show the functional approach to custom joins
  """
  def functional_joins_example() do
    # Using pure functions for maximum flexibility
    User
    |> Events.CRUD.Query.where(:status, :eq, "active")
    |> Events.CRUD.Query.join(Post, :posts,
      on: posts.user_id == user.id and posts.published == true,
      type: :left
    )
    |> Events.CRUD.Query.join(Comment, :comments,
      on: comments.post_id == posts.id and comments.approved == true
    )
    |> Events.CRUD.Query.select([:id, :name, :email])
    |> Events.CRUD.Query.preload(:posts, fn q ->
      q
      |> Events.CRUD.Query.where(:status, :eq, "published")
      |> Events.CRUD.Query.order(:published_at, :desc)
      |> Events.CRUD.Query.limit(5)
    end)
    |> Events.CRUD.Query.debug("Custom joins query")
    |> Events.CRUD.Query.execute()
  end

  # Helper functions

  defp validate_post_attrs(attrs) do
    # Basic validation example
    required_fields = [:title, :content]
    missing = Enum.filter(required_fields, &is_nil(attrs[&1]))

    if missing != [] do
      {:error, {:missing_fields, missing}}
    else
      {:ok, attrs}
    end
  end

  defp generate_slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
