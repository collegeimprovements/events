defmodule Examples.HelpersUsageExample do
  @moduledoc """
  Practical examples of using Events.Query.Helpers in real-world scenarios.

  ## Setup

  Add this to your module to use the helpers:

      import Events.Query.Helpers

  """

  import Events.Query.DSL
  import Events.Query.Helpers
  alias Events.Query

  @doc """
  Example 1: Recent posts query using date helpers
  """
  def recent_posts do
    query Post do
      # Posts from the last week
      filter :published_at, :gte, last_week()

      # Updated in the last 24 hours
      filter :updated_at, :gte, hours_ago(24)

      # Not deleted
      filter :deleted_at, :is_nil, nil

      order :published_at, :desc
      limit 50
    end
  end

  @doc """
  Example 2: Active users query with time ranges
  """
  def active_users do
    query User do
      # Logged in within last 30 days
      filter :last_login_at, :gte, last_month()

      # Account created more than 7 days ago (not brand new)
      filter :created_at, :lte, last_week()

      # Active status
      filter :status, :eq, "active"

      order :last_login_at, :desc
    end
  end

  @doc """
  Example 3: Date range query (today's activity)
  """
  def todays_orders do
    query Order do
      # From start of today to end of today
      filter :created_at, :gte, start_of_day(today())
      filter :created_at, :lte, end_of_day(today())

      filter :status, :in, ["pending", "processing", "completed"]

      order :created_at, :desc
    end
  end

  @doc """
  Example 4: Weekly report (current week's data)
  """
  def weekly_report do
    query Event do
      # Everything from Monday 00:00:00 onwards
      filter :occurred_at, :gte, start_of_week()

      # Group and aggregate would happen in Repo.aggregate or similar
      order :occurred_at, :asc
    end
  end

  @doc """
  Example 5: Dynamic filtering with user input

  Perfect for API endpoints where you want to filter based on query params.
  """
  def search_posts(params) do
    # Define how query params map to database fields
    filter_mapping = %{
      status: {:eq, :status},
      author_id: {:eq, :author_id},
      min_views: {:gte, :view_count},
      max_views: {:lte, :view_count},
      search: {:ilike, :title},
      category: {:eq, :category}
    }

    query Post do
      # Static filters that always apply
      filter :deleted_at, :is_nil, nil
      filter :published, :eq, true
    end
    |> dynamic_filters(params, filter_mapping)
    |> sort_by(params["sort"])  # e.g., "-created_at" or "title,-views"
    |> paginate_from_params(params)  # handles limit, cursor, or offset
  end

  @doc """
  Example 6: Complex date filtering with custom ranges
  """
  def posts_in_custom_range(days_back) do
    cutoff_date = last_n_days(days_back)

    query Post do
      filter :published_at, :gte, cutoff_date
      filter :status, :eq, "published"
      order :published_at, :desc
    end
  end

  @doc """
  Example 7: Combining helpers with ensure_limit

  Useful for queries where you want a default limit but allow overrides.
  """
  def featured_posts(limit \\ nil) do
    token =
      query Post do
        filter :featured, :eq, true
        filter :published_at, :gte, last_month()
        order :published_at, :desc
      end

    # Apply limit if provided, otherwise ensure there's a default
    case limit do
      nil -> ensure_limit(token, 20)
      n when is_integer(n) -> Query.limit(token, n)
    end
  end

  @doc """
  Example 8: Monthly reports with start_of_month
  """
  def this_months_revenue do
    query Order do
      filter :created_at, :gte, start_of_month()
      filter :status, :eq, "completed"
      order :created_at, :asc
    end
  end

  @doc """
  Example 9: Year-to-date statistics
  """
  def year_to_date_orders do
    query Order do
      filter :created_at, :gte, start_of_year()
      filter :created_at, :lte, now()
      order :created_at, :desc
    end
  end

  @doc """
  Example 10: API endpoint with full dynamic capabilities

  This demonstrates a realistic API endpoint that handles:
  - Dynamic filtering
  - Sorting
  - Pagination
  - Default limits
  """
  def list_users(params) do
    filter_mapping = %{
      status: {:eq, :status},
      role: {:eq, :role},
      min_age: {:gte, :age},
      email: {:ilike, :email},
      verified: {:eq, :email_verified}
    }

    Query.new(User)
    |> dynamic_filters(params, filter_mapping)
    |> sort_by(params["sort"] || "-created_at")  # Default sort
    |> paginate_from_params(params)
    |> ensure_limit(50)  # Ensure there's a max limit
  end

  @doc """
  Example 11: Time-sensitive data (recent activity)
  """
  def recent_activity(minutes \\ 60) do
    query ActivityLog do
      filter :timestamp, :gte, minutes_ago(minutes)
      order :timestamp, :desc
      limit 100
    end
  end

  @doc """
  Example 12: Quarterly business reports
  """
  def quarterly_revenue do
    query Order do
      filter :completed_at, :gte, last_quarter()
      filter :status, :eq, "completed"
      order :completed_at, :desc
    end
  end

  @doc """
  Example 13: Chaining helpers with regular query operations
  """
  def advanced_search(params) do
    base_date =
      case params["timeframe"] do
        "week" -> last_week()
        "month" -> last_month()
        "quarter" -> last_quarter()
        "year" -> last_year()
        _ -> last_month()  # default
      end

    query Post do
      filter :published_at, :gte, base_date
      filter :status, :eq, "published"

      # Dynamic filters from user
    end
    |> dynamic_filters(params, %{
      author_id: {:eq, :author_id},
      category: {:eq, :category},
      min_rating: {:gte, :rating}
    })
    |> sort_by(params["sort"])
    |> ensure_limit(25)
  end

  @doc """
  Example 14: Safe sorting with error handling
  """
  def safe_sorted_posts(sort_param) do
    token =
      query Post do
        filter :published, :eq, true
      end

    case safe_sort_by(token, sort_param) do
      {:ok, sorted_token} ->
        {:ok, sorted_token |> ensure_limit(50)}

      {:error, :invalid_field} ->
        # Fall back to default sorting
        {:ok, token |> Query.order_by(:created_at, :desc) |> Query.limit(50)}
    end
  end

  @doc """
  Example 15: Complex business logic with date helpers
  """
  def subscription_expiring_soon do
    # Find subscriptions expiring in the next 7 days
    today_start = start_of_day(today())
    week_from_now = start_of_day(last_n_days(-7))  # negative = future

    query Subscription do
      filter :expires_at, :gte, today_start
      filter :expires_at, :lte, week_from_now
      filter :status, :eq, "active"
      order :expires_at, :asc
    end
  end
end
