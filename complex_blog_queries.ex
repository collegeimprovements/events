defmodule BlogPlatform.Queries do
  @moduledoc """
  Complex query examples for a blog platform using the full CRUD DSL.
  """

  import Events.CRUD.DSL

  @doc """
  Example 1: Complex user analytics with nested preloads and custom joins

  Get active users with their engagement metrics, recent posts, and comment activity.
  Includes custom join conditions and nested preloading with filters.
  """
  def get_user_engagement_analytics(opts \\ []) do
    # Extract options with defaults
    since_date = Keyword.get(opts, :since, ~U[2024-01-01 00:00:00Z])
    min_posts = Keyword.get(opts, :min_posts, 1)
    include_admins = Keyword.get(opts, :include_admins, false)

    query User do
      # Basic user filtering
      where(:status, :eq, "active")
      where(:created_at, :gte, since_date)

      # Exclude/include admins based on option
      if not include_admins do
        where(:role, :neq, "admin")
      end

      # Debug: Check initial filtering
      debug("After user filtering")

      # Custom join with posts (only published ones)
      join(Post, :published_posts,
        on:
          published_posts.user_id == user.id and
            published_posts.status == "published" and
            published_posts.published_at <= ^DateTime.utc_now(),
        type: :left
      )

      # Custom join with comments (only approved ones)
      join(Comment, :approved_comments,
        on:
          approved_comments.user_id == user.id and
            approved_comments.approved == true and
            approved_comments.created_at >= ^since_date,
        type: :left
      )

      # Association join with categories (for post categorization)
      join(:categories, :left)

      # Complex select with aggregations
      select(%{
        user_id: :id,
        user_name: :name,
        user_email: :email,
        user_role: :role,
        total_posts: count(published_posts.id),
        total_comments: count(approved_comments.id),
        avg_post_views: avg(published_posts.views),
        last_post_date: max(published_posts.published_at),
        last_comment_date: max(approved_comments.created_at),
        categories_used: count(categories.id)
      })

      # Group by user fields
      group([:id, :name, :email, :role])

      # Filter groups with minimum activity
      having(total_posts: {:gte, min_posts})
      having(total_comments: {:gte, 0})

      # Sort by engagement (posts + comments)
      order({:total_posts, :desc})
      order({:total_comments, :desc})

      # Limit results for performance
      limit(100)

      # Debug: Check final query
      debug("Final analytics query")
    end
  end

  @doc """
  Example 2: Advanced post search with full-text search and faceted results

  Search posts by content, tags, and categories with relevance scoring.
  Includes cursor pagination for infinite scroll.
  """
  def search_posts(search_query, filters \\ [], cursor \\ nil) do
    query Post do
      # Status filtering
      where(:status, :eq, "published")
      where(:published_at, :lte, DateTime.utc_now())

      # Full-text search on title and content
      if search_query != "" do
        raw_where(
          "to_tsvector('english', title || ' ' || content) @@ plainto_tsquery(:query)",
          %{query: search_query}
        )
      end

      # Apply dynamic filters
      for {field, condition} <- filters do
        case {field, condition} do
          {:category_id, id} -> where(:category_id, :eq, id)
          {:author_id, id} -> where(:user_id, :eq, id)
          {:tags, tags} when is_list(tags) -> where(:tags, :contains, tags)
          {:date_from, date} -> where(:published_at, :gte, date)
          {:date_to, date} -> where(:published_at, :lte, date)
          {:min_views, count} -> where(:views, :gte, count)
          {:max_views, count} -> where(:views, :lte, count)
          # Handled below
          {:sort_by, sort_type} -> :ok
          # Ignore unknown filters
          _ -> :ok
        end
      end

      # Join with author for display
      join(:user, :inner)

      # Join with category
      join(:category, :left)

      # Join with comments for engagement metrics
      join(Comment, :all_comments,
        on: all_comments.post_id == post.id,
        type: :left
      )

      # Join with approved comments only
      join(Comment, :approved_comments,
        on:
          approved_comments.post_id == post.id and
            approved_comments.approved == true,
        type: :left
      )

      # Preload author with selected fields
      preload(:user, select: [:id, :name, :avatar_url])

      # Preload category
      preload(:category, select: [:id, :name, :slug])

      # Preload approved comments with limits
      preload :approved_comments do
        where(:approved, :eq, true)
        order(:created_at, :desc)
        limit(5)

        # Nested preload of comment authors
        preload(:user, select: [:id, :name])
      end

      # Select post data with computed fields
      select(%{
        id: :id,
        title: :title,
        slug: :slug,
        excerpt: :excerpt,
        content: :content,
        published_at: :published_at,
        views: :views,
        reading_time: fragment("ceil(length(content) / 200.0)"),
        author: :user,
        category: :category,
        tags: :tags,
        comment_count: count(approved_comments.id),
        total_comment_count: count(all_comments.id),
        engagement_score:
          fragment(
            "(? + ?) * 1.0 / GREATEST(EXTRACT(epoch FROM NOW() - ?), 1)",
            :views,
            count(approved_comments.id),
            :published_at
          )
      })

      # Group by post fields (needed for aggregations)
      group([
        :id,
        :title,
        :slug,
        :excerpt,
        :content,
        :published_at,
        :views,
        :user_id,
        :category_id,
        :tags
      ])

      # Sort by relevance (engagement score) or date
      case filters[:sort_by] do
        :relevance -> order({:engagement_score, :desc})
        :newest -> order({:published_at, :desc})
        :oldest -> order({:published_at, :asc})
        :most_viewed -> order({:views, :desc})
        :most_commented -> order({:comment_count, :desc})
        # Default to newest
        _ -> order({:published_at, :desc})
      end

      # Cursor pagination for infinite scroll
      paginate(:cursor, limit: 20, cursor: cursor, cursor_fields: [published_at: :desc, id: :desc])

      debug("Post search query")
    end
  end

  @doc """
  Example 3: Content moderation dashboard with complex filtering

  Get posts requiring moderation with author and category context.
  Includes conditional logic based on moderation rules.
  """
  def get_posts_needing_moderation(moderator_role) do
    query Post do
      # Posts that need review
      where(:status, :in, ["pending_review", "flagged"])
      where(:moderation_required, :eq, true)

      # Time-based filtering (recent posts only)
      where(:created_at, :gte, DateTime.add(DateTime.utc_now(), -30, :day))

      # Join with author
      join(:user, :inner)

      # Conditional joins based on moderator role
      if moderator_role in ["admin", "senior_moderator"] do
        # Admins can see all flagged content
        join(Comment, :flagged_comments,
          on:
            flagged_comments.post_id == post.id and
              flagged_comments.flagged == true,
          type: :left
        )
      else
        # Regular moderators only see their category's content
        join(:category, :inner)
        where(:category__moderator_id, :eq, moderator_role)
      end

      # Preload author
      preload(:user, select: [:id, :name, :email, :role])

      # Preload category if joined
      if moderator_role not in ["admin", "senior_moderator"] do
        preload(:category, select: [:id, :name, :moderator_id])
      end

      # Preload recent comments for context
      preload :comments do
        where(:created_at, :gte, DateTime.add(DateTime.utc_now(), -7, :day))
        order(:created_at, :desc)
        limit(10)

        preload(:user, select: [:id, :name])
      end

      # Select moderation-relevant data
      select(%{
        id: :id,
        title: :title,
        content: :content,
        status: :status,
        moderation_reason: :moderation_reason,
        created_at: :created_at,
        author: :user,
        category: :category,
        comment_count: count(comments.id),
        flagged_comments: count(flagged_comments.id),
        priority_score: fragment("CASE
          WHEN ? = 'flagged' THEN 100
          WHEN ? > 10 THEN 50
          WHEN ? > 5 THEN 25
          ELSE 10
        END", :status, count(comments.id), count(comments.id))
      })

      # Group for aggregations
      group([
        :id,
        :title,
        :content,
        :status,
        :moderation_reason,
        :created_at,
        :user_id,
        :category_id
      ])

      # Sort by priority (flagged posts first, then by engagement)
      order({:priority_score, :desc})
      order({:created_at, :desc})

      # Limit for manageable dashboard
      limit(50)

      debug("Moderation dashboard query")
    end
  end
end
