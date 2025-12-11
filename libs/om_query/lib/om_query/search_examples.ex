defmodule OmQuery.SearchExamples do
  @moduledoc false
  # Example module - not part of public API.
  #
  # Comprehensive search examples with nested filters and pagination.
  # Demonstrates: dynamic filter construction, multi-level nested preloads,
  # different pagination at each level, parameter interpolation, real-world scenarios.

  alias OmQuery.DynamicBuilder

  # Suppress warnings for undefined schemas
  @compile {:no_warn_undefined,
            [User, Post, Comment, Product, Category, Review, Order, Customer, OrderItem]}

  @doc """
  Example 1: E-commerce product search with 3-level nesting.

  Search products with:
  - Category filters (level 1)
  - Paginated reviews (level 2)
  - Paginated review replies (level 3)

  Each level has its own pagination and filtering.
  """
  def ecommerce_product_search(params) do
    spec = %{
      filters: build_product_filters(params),
      orders: build_product_orders(params),
      pagination:
        {:paginate, :offset,
         %{
           limit: params[:products_per_page] || 20,
           offset: params[:products_offset] || 0
         }, []},
      preloads: [
        {:preload, :category, nil, []},
        {:preload, :reviews,
         %{
           filters: [
             {:filter, :status, :eq, "approved", []},
             {:filter, :rating, :gte, params[:min_rating] || 1, []}
           ],
           orders: [
             {:order, :helpful_count, :desc, []},
             {:order, :created_at, :desc, []}
           ],
           pagination:
             {:paginate, :offset,
              %{
                limit: params[:reviews_per_product] || 10,
                offset: 0
              }, []},
           preloads: [
             {:preload, :replies,
              %{
                filters: [
                  {:filter, :status, :eq, "approved", []}
                ],
                orders: [
                  {:order, :created_at, :asc, []}
                ],
                pagination:
                  {:paginate, :offset,
                   %{
                     limit: 5,
                     offset: 0
                   }, []}
              }, []}
           ]
         }, []}
      ]
    }

    DynamicBuilder.build(Product, spec, params)
  end

  defp build_product_filters(params) do
    base = [{:filter, :status, :eq, "active", []}]

    base
    |> maybe_add({:filter, :category_id, :eq, {:param, :category_id}, []}, params[:category_id])
    |> maybe_add({:filter, :price, :gte, {:param, :min_price}, []}, params[:min_price])
    |> maybe_add({:filter, :price, :lte, {:param, :max_price}, []}, params[:max_price])
    |> maybe_add({:filter, :in_stock, :eq, true, []}, params[:only_in_stock])
    |> maybe_add({:filter, :name, :ilike, {:param, :search_term}, []}, params[:search])
    |> maybe_add({:filter, :rating, :gte, {:param, :min_rating}, []}, params[:min_rating])
  end

  defp build_product_orders(params) do
    case params[:sort_by] do
      "price_asc" ->
        [{:order, :price, :asc, []}, {:order, :id, :asc, []}]

      "price_desc" ->
        [{:order, :price, :desc, []}, {:order, :id, :asc, []}]

      "rating" ->
        [{:order, :rating, :desc, []}, {:order, :review_count, :desc, []}, {:order, :id, :asc, []}]

      "popular" ->
        [{:order, :sales_count, :desc, []}, {:order, :id, :asc, []}]

      "newest" ->
        [{:order, :created_at, :desc, []}, {:order, :id, :asc, []}]

      _ ->
        [{:order, :featured, :desc, []}, {:order, :created_at, :desc, []}, {:order, :id, :asc, []}]
    end
  end

  @doc """
  Example 2: Blog/CMS content search with deep nesting.

  Search posts with:
  - Author information (level 1)
  - Paginated comments (level 2)
  - Paginated comment replies (level 3)
  - Reply author info (level 4)

  Uses cursor pagination at different levels.
  """
  def blog_content_search(params) do
    spec = %{
      filters:
        [
          {:filter, :status, :in, ["published", "featured"], []},
          {:filter, :published_at, :lte, {:param, :published_before}, []},
          {:filter, :published_at, :gte, {:param, :published_after}, []}
        ] ++ dynamic_blog_filters(params),
      orders: [
        {:order, :featured, :desc, []},
        {:order, :published_at, :desc, []},
        {:order, :id, :asc, []}
      ],
      pagination:
        {:paginate, :cursor,
         %{
           limit: params[:posts_limit] || 25,
           cursor_fields: [:published_at, :id]
         }, []},
      preloads: [
        {:preload, :author, nil, []},
        {:preload, :tags, nil, []},
        {:preload, :comments,
         %{
           filters: [
             {:filter, :status, :eq, "approved", []},
             {:filter, :deleted_at, :is_nil, nil, []}
           ],
           orders: [
             {:order, :pinned, :desc, []},
             {:order, :likes_count, :desc, []},
             {:order, :created_at, :desc, []}
           ],
           pagination:
             {:paginate, :cursor,
              %{
                limit: params[:comments_limit] || 15,
                cursor_fields: [:created_at, :id]
              }, []},
           preloads: [
             {:preload, :author, nil, []},
             {:preload, :replies,
              %{
                filters: [
                  {:filter, :status, :eq, "approved", []},
                  {:filter, :deleted_at, :is_nil, nil, []}
                ],
                orders: [
                  {:order, :created_at, :asc, []}
                ],
                pagination:
                  {:paginate, :offset,
                   %{
                     limit: 10,
                     offset: 0
                   }, []},
                preloads: [
                  {:preload, :author, nil, []}
                ]
              }, []}
           ]
         }, []}
      ]
    }

    DynamicBuilder.build(Post, spec, params)
  end

  defp dynamic_blog_filters(params) do
    []
    |> maybe_add({:filter, :category_id, :eq, {:param, :category_id}, []}, params[:category_id])
    |> maybe_add({:filter, :author_id, :eq, {:param, :author_id}, []}, params[:author_id])
    |> maybe_add({:filter, :title, :ilike, {:param, :search_pattern}, []}, params[:search])
    |> maybe_add({:filter, :tags, :contains, {:param, :tags}, []}, params[:tags])
    |> maybe_add({:filter, :views, :gte, {:param, :min_views}, []}, params[:min_views])
  end

  @doc """
  Example 3: Customer order history with line items.

  Shows orders with:
  - Different pagination for orders vs line items
  - Product details on line items
  - Reviews on products
  """
  def customer_order_history(customer_id, params) do
    spec = %{
      filters:
        [
          {:filter, :customer_id, :eq, customer_id, []},
          {:filter, :status, :not_in, ["cancelled", "refunded"], []}
        ] ++ date_range_filters(params),
      orders: [
        {:order, :created_at, :desc, []},
        {:order, :id, :desc, []}
      ],
      pagination:
        {:paginate, :offset,
         %{
           limit: params[:orders_per_page] || 10,
           offset: params[:orders_offset] || 0
         }, []},
      preloads: [
        {:preload, :order_items,
         %{
           filters: [],
           orders: [
             {:order, :created_at, :asc, []}
           ],
           pagination:
             {:paginate, :offset,
              %{
                limit: 50,
                offset: 0
              }, []},
           preloads: [
             {:preload, :product,
              %{
                filters: [
                  {:filter, :deleted_at, :is_nil, nil, []}
                ],
                preloads: [
                  {:preload, :category, nil, []},
                  {:preload, :reviews,
                   %{
                     filters: [
                       {:filter, :customer_id, :eq, customer_id, []},
                       {:filter, :status, :eq, "published", []}
                     ],
                     orders: [
                       {:order, :created_at, :desc, []}
                     ],
                     pagination:
                       {:paginate, :offset,
                        %{
                          limit: 1,
                          offset: 0
                        }, []}
                   }, []}
                ]
              }, []}
           ]
         }, []}
      ]
    }

    DynamicBuilder.build(Order, spec, params)
  end

  defp date_range_filters(params) do
    []
    |> maybe_add({:filter, :created_at, :gte, {:param, :from_date}, []}, params[:from_date])
    |> maybe_add({:filter, :created_at, :lte, {:param, :to_date}, []}, params[:to_date])
  end

  @doc """
  Example 4: Social media feed with complex nesting.

  Feed items with:
  - User info and stats
  - Comments with reactions
  - Nested comment threads
  - Multiple pagination strategies
  """
  def social_feed(user_id, params) do
    spec = %{
      filters: build_feed_filters(user_id, params),
      orders: build_feed_ordering(params),
      pagination:
        {:paginate, :cursor,
         %{
           limit: params[:feed_limit] || 20,
           cursor_fields: [:created_at, :id],
           after: params[:after_cursor]
         }, []},
      preloads: [
        {:preload, :author,
         %{
           select: [:id, :name, :avatar_url, :verified]
         }, []},
        {:preload, :reactions,
         %{
           filters: [
             {:filter, :user_id, :eq, user_id, []}
           ],
           limit: 1
         }, []},
        {:preload, :comments,
         %{
           filters: [
             {:filter, :status, :eq, "visible", []},
             {:filter, :parent_id, :is_nil, nil, []}
           ],
           orders: [
             {:order, :likes_count, :desc, []},
             {:order, :created_at, :desc, []}
           ],
           pagination:
             {:paginate, :offset,
              %{
                limit: params[:comments_per_post] || 5,
                offset: 0
              }, []},
           preloads: [
             {:preload, :author, nil, []},
             {:preload, :reactions,
              %{
                filters: [
                  {:filter, :user_id, :eq, user_id, []}
                ]
              }, []},
             {:preload, :replies,
              %{
                filters: [
                  {:filter, :status, :eq, "visible", []}
                ],
                orders: [
                  {:order, :created_at, :asc, []}
                ],
                pagination:
                  {:paginate, :offset,
                   %{
                     limit: 3,
                     offset: 0
                   }, []},
                preloads: [
                  {:preload, :author, nil, []}
                ]
              }, []}
           ]
         }, []}
      ]
    }

    DynamicBuilder.build(Post, spec, params)
  end

  defp build_feed_filters(_user_id, params) do
    base = [
      {:filter, :status, :eq, "published", []},
      {:filter, :visibility, :in, ["public", "friends"], []}
    ]

    base
    |> maybe_add({:filter, :author_id, :in, {:param, :following_ids}, []}, params[:following_ids])
    |> maybe_add({:filter, :created_at, :gte, {:param, :since}, []}, params[:since])
    |> maybe_add({:filter, :content_type, :eq, {:param, :content_type}, []}, params[:content_type])
  end

  defp build_feed_ordering(params) do
    case params[:sort] do
      "chronological" -> [{:order, :created_at, :desc, []}, {:order, :id, :desc, []}]
      "engagement" -> [{:order, :engagement_score, :desc, []}, {:order, :created_at, :desc, []}]
      "trending" -> [{:order, :trending_score, :desc, []}, {:order, :created_at, :desc, []}]
      _ -> [{:order, :relevance_score, :desc, []}, {:order, :created_at, :desc, []}]
    end
  end

  @doc """
  Example 5: Marketplace search with seller and buyer reviews.

  Products with:
  - Seller information and ratings
  - Buyer reviews with responses
  - Different pagination at each level
  - Complex filtering
  """
  def marketplace_search(params) do
    spec = %{
      filters: build_marketplace_filters(params),
      orders: build_marketplace_orders(params),
      pagination:
        {:paginate, :offset,
         %{
           limit: params[:products_per_page] || 24,
           offset: params[:products_offset] || 0
         }, []},
      preloads: [
        {:preload, :seller,
         %{
           filters: [
             {:filter, :status, :eq, "active", []},
             {:filter, :verified, :eq, true, []}
           ],
           preloads: [
             {:preload, :ratings,
              %{
                orders: [
                  {:order, :created_at, :desc, []}
                ],
                pagination:
                  {:paginate, :offset,
                   %{
                     limit: 5,
                     offset: 0
                   }, []}
              }, []}
           ]
         }, []},
        {:preload, :category, nil, []},
        {:preload, :reviews,
         %{
           filters:
             [
               {:filter, :status, :eq, "approved", []},
               {:filter, :verified_purchase, :eq, true, []}
             ] ++ review_rating_filter(params),
           orders: [
             {:order, :verified_purchase, :desc, []},
             {:order, :helpful_count, :desc, []},
             {:order, :created_at, :desc, []}
           ],
           pagination:
             {:paginate, :cursor,
              %{
                limit: params[:reviews_limit] || 10,
                cursor_fields: [:helpful_count, :created_at, :id]
              }, []},
           preloads: [
             {:preload, :buyer,
              %{
                select: [:id, :name, :avatar_url, :verified]
              }, []},
             {:preload, :seller_response,
              %{
                filters: [
                  {:filter, :status, :eq, "published", []}
                ]
              }, []},
             {:preload, :images,
              %{
                orders: [
                  {:order, :position, :asc, []}
                ],
                limit: 5
              }, []}
           ]
         }, []}
      ]
    }

    DynamicBuilder.build(Product, spec, params)
  end

  defp build_marketplace_filters(params) do
    base = [
      {:filter, :status, :eq, "active", []},
      {:filter, :deleted_at, :is_nil, nil, []}
    ]

    base
    |> maybe_add({:filter, :category_id, :in, {:param, :category_ids}, []}, params[:category_ids])
    |> maybe_add({:filter, :price, :between, {:param, :price_range}, []}, params[:price_range])
    |> maybe_add({:filter, :seller_id, :eq, {:param, :seller_id}, []}, params[:seller_id])
    |> maybe_add({:filter, :condition, :eq, {:param, :condition}, []}, params[:condition])
    |> maybe_add({:filter, :rating, :gte, {:param, :min_rating}, []}, params[:min_rating])
    |> maybe_add({:filter, :name, :ilike, {:param, :search_query}, []}, params[:q])
    |> maybe_add({:filter, :tags, :contains, {:param, :tags}, []}, params[:tags])
    |> maybe_add({:filter, :shipping_free, :eq, true, []}, params[:free_shipping])
  end

  defp build_marketplace_orders(params) do
    case params[:sort_by] do
      "price_low" ->
        [{:order, :price, :asc, []}, {:order, :id, :asc, []}]

      "price_high" ->
        [{:order, :price, :desc, []}, {:order, :id, :asc, []}]

      "rating" ->
        [{:order, :rating, :desc, []}, {:order, :review_count, :desc, []}, {:order, :id, :asc, []}]

      "newest" ->
        [{:order, :created_at, :desc, []}, {:order, :id, :asc, []}]

      "popular" ->
        [
          {:order, :view_count, :desc, []},
          {:order, :order_count, :desc, []},
          {:order, :id, :asc, []}
        ]

      "distance" ->
        [{:order, :distance, :asc, []}, {:order, :id, :asc, []}]

      _ ->
        [
          {:order, :relevance_score, :desc, []},
          {:order, :created_at, :desc, []},
          {:order, :id, :asc, []}
        ]
    end
  end

  defp review_rating_filter(params) do
    case params[:rating_filter] do
      rating when is_integer(rating) and rating >= 1 and rating <= 5 ->
        [{:filter, :rating, :eq, rating, []}]

      _ ->
        []
    end
  end

  @doc """
  Example 6: Analytics/reporting query with aggregations.

  Complex query demonstrating:
  - Time-based filtering
  - Multiple aggregation levels
  - Nested grouping
  - Different pagination strategies
  """
  def sales_analytics(params) do
    spec = %{
      filters:
        [
          {:filter, :status, :eq, "completed", []},
          {:filter, :created_at, :gte, {:param, :start_date}, []},
          {:filter, :created_at, :lte, {:param, :end_date}, []}
        ] ++ analytics_filters(params),
      orders: [
        {:order, :created_at, :desc, []},
        {:order, :id, :desc, []}
      ],
      pagination:
        {:paginate, :offset,
         %{
           limit: params[:limit] || 100,
           offset: params[:offset] || 0
         }, []},
      preloads: [
        {:preload, :customer,
         %{
           select: [:id, :email, :name, :customer_segment]
         }, []},
        {:preload, :items,
         %{
           filters: [
             {:filter, :status, :neq, "cancelled", []}
           ],
           preloads: [
             {:preload, :product,
              %{
                select: [:id, :name, :category_id, :price],
                preloads: [
                  {:preload, :category, nil, []}
                ]
              }, []}
           ]
         }, []}
      ],
      select: [
        :id,
        :customer_id,
        :total_amount,
        :tax_amount,
        :shipping_amount,
        :discount_amount,
        :created_at,
        :payment_method
      ]
    }

    DynamicBuilder.build(Order, spec, params)
  end

  defp analytics_filters(params) do
    []
    |> maybe_add({:filter, :customer_segment, :eq, {:param, :segment}, []}, params[:segment])
    |> maybe_add(
      {:filter, :payment_method, :in, {:param, :payment_methods}, []},
      params[:payment_methods]
    )
    |> maybe_add({:filter, :total_amount, :gte, {:param, :min_amount}, []}, params[:min_amount])
    |> maybe_add({:filter, :total_amount, :lte, {:param, :max_amount}, []}, params[:max_amount])
    |> maybe_add({:filter, :region, :eq, {:param, :region}, []}, params[:region])
  end

  @doc """
  Example 7: Using the search helper for common patterns.

  Demonstrates DynamicBuilder.search/3 for simplified queries.
  """
  def simple_user_search(params) do
    config = %{
      search_fields: [:name, :email, :bio],
      filterable_fields: [:status, :role, :verified, :country],
      sortable_fields: [:name, :created_at, :updated_at, :last_login_at],
      default_sort: {:created_at, :desc},
      default_per_page: 25
    }

    DynamicBuilder.search(User, params, config)
  end

  @doc """
  Example 8: Combining specs from multiple sources.

  Shows how to merge base specs with user-provided overrides.
  """
  def combined_spec_search(base_spec, user_filters, user_params) do
    # Start with base specification
    spec = base_spec

    # Add user filters
    spec =
      Map.update(spec, :filters, user_filters, fn existing ->
        existing ++ user_filters
      end)

    # Add pagination from params
    spec =
      Map.put(
        spec,
        :pagination,
        {:paginate, :offset,
         %{
           limit: user_params[:limit] || 20,
           offset: user_params[:offset] || 0
         }, []}
      )

    # Add ordering from params
    spec =
      if user_params[:sort_by] do
        Map.put(spec, :orders, [
          {:order, String.to_existing_atom(user_params[:sort_by]), :desc, []},
          {:order, :id, :asc, []}
        ])
      else
        spec
      end

    DynamicBuilder.build(Product, spec, user_params)
  end

  # Helper functions

  defp maybe_add(list, _item, nil), do: list
  defp maybe_add(list, _item, false), do: list
  defp maybe_add(list, item, _truthy), do: list ++ [item]
end
