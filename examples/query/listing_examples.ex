defmodule OmQuery.ListingExamples do
  @moduledoc false
  # Example module - not part of public API.
  #
  # Comprehensive examples for listing/query operations.
  # Demonstrates different ways to add filters and ordering:
  # 1. Multiple separate filter() calls - Chain individual filters
  # 2. Single filters() call with list - Pass all filters at once
  # 3. Multiple separate order() calls - Chain individual orders
  # 4. Single orders() call with list - Pass all orders at once
  # 5. Mixed approaches - Combine both patterns

  import OmQuery.DSL
  alias OmQuery

  # Suppress warnings for undefined schemas
  @compile {:no_warn_undefined, [User, Post, Product, Order]}

  ## FILTER EXAMPLES

  @doc """
  Example 1: Multiple separate filter calls (chaining pattern).

  This is the most common pattern - add filters one by one.
  """
  def filters_chaining_pipeline do
    User
    |> Query.new()
    |> Query.filter(:status, :eq, "active")
    |> Query.filter(:age, :gte, 18)
    |> Query.filter(:verified, :eq, true)
    |> Query.filter(:role, :in, ["admin", "editor"])
  end

  @doc """
  Example 2: Multiple filters in a single call (list pattern).

  Pass all filters as a list - useful when filters are computed dynamically.
  """
  def filters_list_pipeline do
    User
    |> Query.new()
    |> Query.filters([
      {:status, :eq, "active"},
      {:age, :gte, 18},
      {:verified, :eq, true},
      {:role, :in, ["admin", "editor"]}
    ])
  end

  @doc """
  Example 3: Multiple separate filter calls (DSL pattern).
  """
  def filters_chaining_dsl do
    query User do
      filter(:status, :eq, "active")
      filter(:age, :gte, 18)
      filter(:verified, :eq, true)
      filter(:role, :in, ["admin", "editor"])
    end
  end

  @doc """
  Example 4: Multiple filters in a single call (DSL pattern).
  """
  def filters_list_dsl do
    query User do
      filters([
        {:status, :eq, "active"},
        {:age, :gte, 18},
        {:verified, :eq, true},
        {:role, :in, ["admin", "editor"]}
      ])
    end
  end

  @doc """
  Example 5: Filters with options (4-tuple format).
  """
  def filters_with_options do
    query User do
      filters([
        {:status, :eq, "active", []},
        {:email, :ilike, "%@example.com", [case_insensitive: true]},
        {:name, :like, "%John%", []},
        {:published, :eq, true, [binding: :posts]}
      ])
    end
  end

  @doc """
  Example 6: Mixed 3-tuple and 4-tuple filters.
  """
  def filters_mixed_format do
    query User do
      filters([
        {:status, :eq, "active"},
        {:email, :ilike, "%@example.com", [case_insensitive: true]},
        {:age, :gte, 18},
        {:verified, :eq, true, []}
      ])
    end
  end

  @doc """
  Example 7: Dynamic filter building.

  Build filters based on runtime conditions.
  """
  def filters_dynamic(params) do
    base_filters = [
      {:status, :eq, "active"}
    ]

    filters_list =
      base_filters
      |> maybe_add_age_filter(params)
      |> maybe_add_role_filter(params)
      |> maybe_add_search_filter(params)

    User
    |> Query.new()
    |> Query.filters(filters_list)
  end

  defp maybe_add_age_filter(filters, %{min_age: age}) do
    filters ++ [{:age, :gte, age}]
  end

  defp maybe_add_age_filter(filters, _), do: filters

  defp maybe_add_role_filter(filters, %{roles: roles}) when is_list(roles) do
    filters ++ [{:role, :in, roles}]
  end

  defp maybe_add_role_filter(filters, _), do: filters

  defp maybe_add_search_filter(filters, %{search: term}) when is_binary(term) do
    filters ++ [{:name, :ilike, "%#{term}%"}]
  end

  defp maybe_add_search_filter(filters, _), do: filters

  ## ORDER EXAMPLES

  @doc """
  Example 8: Multiple separate order calls (chaining pattern).
  """
  def orders_chaining_pipeline do
    User
    |> Query.new()
    |> Query.order(:priority, :desc)
    |> Query.order(:created_at, :desc)
    |> Query.order(:id, :asc)
  end

  @doc """
  Example 9: Multiple orders in a single call (list pattern).
  """
  def orders_list_pipeline do
    User
    |> Query.new()
    |> Query.orders([
      {:priority, :desc},
      {:created_at, :desc},
      {:id, :asc}
    ])
  end

  @doc """
  Example 10: Multiple separate order calls (DSL pattern).
  """
  def orders_chaining_dsl do
    query User do
      order(:priority, :desc)
      order(:created_at, :desc)
      order(:id, :asc)
    end
  end

  @doc """
  Example 11: Multiple orders in a single call (DSL pattern).
  """
  def orders_list_dsl do
    query User do
      orders([
        {:priority, :desc},
        {:created_at, :desc},
        {:id, :asc}
      ])
    end
  end

  @doc """
  Example 12: Orders with just field names (defaults to :asc).
  """
  def orders_simple_format do
    query User do
      orders([:name, :email, :id])
    end
  end

  @doc """
  Example 13: Mixed order formats.
  """
  def orders_mixed_format do
    query User do
      orders([
        :name,
        {:created_at, :desc},
        {:updated_at, :desc},
        :id
      ])
    end
  end

  @doc """
  Example 14: Orders with binding for joined tables.
  """
  def orders_with_binding do
    query User do
      join(:posts, :left, as: :user_posts)

      orders([
        {:name, :asc, []},
        {:created_at, :desc, []},
        {:published_at, :desc, [binding: :user_posts]}
      ])
    end
  end

  ## COMBINED EXAMPLES

  @doc """
  Example 15: Combining filters and orders (separate calls).
  """
  def combined_separate_calls do
    User
    |> Query.new()
    |> Query.filter(:status, :eq, "active")
    |> Query.filter(:age, :gte, 18)
    |> Query.filter(:verified, :eq, true)
    |> Query.order(:priority, :desc)
    |> Query.order(:created_at, :desc)
    |> Query.order(:id, :asc)
    |> Query.limit(20)
  end

  @doc """
  Example 16: Combining filters and orders (list calls).
  """
  def combined_list_calls do
    User
    |> Query.new()
    |> Query.filters([
      {:status, :eq, "active"},
      {:age, :gte, 18},
      {:verified, :eq, true}
    ])
    |> Query.orders([
      {:priority, :desc},
      {:created_at, :desc},
      {:id, :asc}
    ])
    |> Query.limit(20)
  end

  @doc """
  Example 17: Combining filters and orders (DSL).
  """
  def combined_dsl do
    query User do
      filters([
        {:status, :eq, "active"},
        {:age, :gte, 18},
        {:verified, :eq, true}
      ])

      orders([
        {:priority, :desc},
        {:created_at, :desc},
        {:id, :asc}
      ])

      limit(20)
    end
  end

  @doc """
  Example 18: Mixed - some separate, some list-based.
  """
  def combined_mixed do
    query User do
      # Initial filter as separate call
      filter(:status, :eq, "active")

      # Additional filters as list
      filters([
        {:age, :gte, 18},
        {:verified, :eq, true}
      ])

      # Orders as list
      orders([
        {:priority, :desc},
        {:created_at, :desc}
      ])

      # Additional order as separate call
      order(:id, :asc)

      limit(20)
    end
  end

  ## COMPLEX REAL-WORLD EXAMPLES

  @doc """
  Example 19: Product listing with dynamic filters and sorting.
  """
  def product_listing(params) do
    base_query = Query.new(Product)

    # Build filters dynamically
    filters =
      []
      |> add_if(params[:category], fn cat -> {:category, :eq, cat} end)
      |> add_if(params[:min_price], fn price -> {:price, :gte, price} end)
      |> add_if(params[:max_price], fn price -> {:price, :lte, price} end)
      |> add_if(params[:in_stock], fn _ -> {:stock, :gt, 0} end)
      |> add_if(params[:search], fn term -> {:name, :ilike, "%#{term}%"} end)

    # Build ordering dynamically
    orders =
      case params[:sort_by] do
        "price_asc" -> [{:price, :asc}, :id]
        "price_desc" -> [{:price, :desc}, :id]
        "name" -> [:name, :id]
        "newest" -> [{:created_at, :desc}, :id]
        _ -> [{:featured, :desc}, {:created_at, :desc}, :id]
      end

    base_query
    |> Query.filters(filters)
    |> Query.orders(orders)
    |> Query.paginate(:offset, limit: params[:per_page] || 20, offset: params[:offset] || 0)
  end

  defp add_if(list, nil, _fun), do: list
  defp add_if(list, value, fun), do: list ++ [fun.(value)]

  @doc """
  Example 20: Blog post listing with multiple filter types.
  """
  def blog_post_listing(filters_map, sort_option) do
    # Convert map to filter list
    filter_list =
      filters_map
      |> Enum.flat_map(fn
        {:status, values} when is_list(values) ->
          [{:status, :in, values}]

        {:published_after, date} ->
          [{:published_at, :gte, date}]

        {:published_before, date} ->
          [{:published_at, :lte, date}]

        {:author_ids, ids} when is_list(ids) ->
          [{:author_id, :in, ids}]

        {:min_views, count} ->
          [{:views, :gte, count}]

        {:tags, tags} when is_list(tags) ->
          [{:tags, :contains, tags}]

        {:featured, true} ->
          [{:featured, :eq, true}]

        _ ->
          []
      end)

    # Determine ordering
    order_list =
      case sort_option do
        :popular -> [{:views, :desc}, {:comments_count, :desc}, :id]
        :recent -> [{:published_at, :desc}, :id]
        :trending -> [{:trending_score, :desc}, {:published_at, :desc}, :id]
        _ -> [{:published_at, :desc}, :id]
      end

    query Post do
      filters(filter_list)
      orders(order_list)
      limit(50)
    end
  end

  @doc """
  Example 21: All filter operators with both patterns.
  """
  def all_operators_showcase do
    # Using separate calls
    separate =
      Product
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:category, :neq, "archived")
      |> Query.filter(:price, :gt, 0)
      |> Query.filter(:price, :gte, 10)
      |> Query.filter(:stock, :lt, 100)
      |> Query.filter(:stock, :lte, 50)
      |> Query.filter(:category, :in, ["electronics", "gadgets"])
      |> Query.filter(:tags, :not_in, ["discontinued"])
      |> Query.filter(:name, :like, "%widget%")
      |> Query.filter(:description, :ilike, "%smart%")
      |> Query.filter(:deleted_at, :is_nil, nil)
      |> Query.filter(:verified_at, :not_nil, nil)
      |> Query.filter(:price, :between, {10.0, 100.0})
      |> Query.filter(:features, :contains, ["wifi"])
      |> Query.filter(:metadata, :jsonb_contains, %{featured: true})
      |> Query.filter(:attributes, :jsonb_has_key, "color")

    # Using list call
    list_based =
      Product
      |> Query.new()
      |> Query.filters([
        {:status, :eq, "active"},
        {:category, :neq, "archived"},
        {:price, :gt, 0},
        {:price, :gte, 10},
        {:stock, :lt, 100},
        {:stock, :lte, 50},
        {:category, :in, ["electronics", "gadgets"]},
        {:tags, :not_in, ["discontinued"]},
        {:name, :like, "%widget%"},
        {:description, :ilike, "%smart%"},
        {:deleted_at, :is_nil, nil},
        {:verified_at, :not_nil, nil},
        {:price, :between, {10.0, 100.0}},
        {:features, :contains, ["wifi"]},
        {:metadata, :jsonb_contains, %{featured: true}},
        {:attributes, :jsonb_has_key, "color"}
      ])

    # Both produce identical tokens
    {separate, list_based}
  end
end
