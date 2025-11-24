defmodule Events.DSLAdvancedTest do
  use ExUnit.Case, async: true

  import Events.Query.DSL
  alias Events.Query

  describe "DSL - CTEs" do
    test "with_cte using do block" do
      token =
        query User do
          with_cte :active_users do
            filter(:status, :eq, "active")
            filter(:last_login, :gte, "2024-01-01")
          end

          filter(:published, :eq, true)
        end

      assert [{:cte, {:active_users, cte_token}}, {:filter, _}] = token.operations
      assert %Query.Token{} = cte_token
      assert length(cte_token.operations) == 2
    end

    test "with_cte using existing token" do
      cte_token =
        Query.new(User)
        |> Query.where(:active, :eq, true)

      token =
        query Post do
          with_cte(:active_users, cte_token)
          filter(:published, :eq, true)
        end

      assert [{:cte, {:active_users, ^cte_token}}, {:filter, _}] = token.operations
    end

    test "multiple CTEs in DSL" do
      token =
        query Order do
          with_cte :active_users do
            filter(:status, :eq, "active")
          end

          with_cte :recent_orders do
            filter(:created_at, :gte, "2024-01-01")
          end

          filter(:amount, :gt, 100)
        end

      assert length(token.operations) == 3

      assert [{:cte, {:active_users, _}}, {:cte, {:recent_orders, _}}, {:filter, _}] =
               token.operations
    end
  end

  describe "DSL - raw SQL" do
    test "raw_where with named parameters" do
      token =
        query User do
          filter(:status, :eq, "active")
          raw_where("age BETWEEN :min AND :max", %{min: 18, max: 65})
          filter(:verified, :eq, true)
        end

      assert length(token.operations) == 3
      assert [{:filter, _}, {:raw_where, {sql, params}}, {:filter, _}] = token.operations
      assert sql == "age BETWEEN :min AND :max"
      assert params == %{min: 18, max: 65}
    end

    test "raw_where without parameters" do
      token =
        query User do
          raw_where("created_at > NOW() - INTERVAL '7 days'")
        end

      assert [{:raw_where, {sql, params}}] = token.operations
      assert sql =~ "NOW()"
      assert params == %{}
    end

    test "raw_where with single parameter" do
      token =
        query User do
          raw_where("status = :status", %{status: "premium"})
        end

      assert [{:raw_where, {"status = :status", %{status: "premium"}}}] = token.operations
    end

    test "multiple raw_where clauses" do
      token =
        query User do
          raw_where("age >= :min_age", %{min_age: 18})
          raw_where("score <= :max_score", %{max_score: 100})
        end

      assert length(token.operations) == 2
      assert [{:raw_where, _}, {:raw_where, _}] = token.operations
    end
  end

  describe "DSL - subqueries" do
    test "in_subquery operator through filter" do
      user_ids_subquery =
        Query.new(User)
        |> Query.where(:active, :eq, true)
        |> Query.select([:id])

      token =
        query Post do
          filter(:user_id, :in_subquery, user_ids_subquery)
          filter(:published, :eq, true)
        end

      assert [{:filter, {:user_id, :in_subquery, ^user_ids_subquery, []}}, {:filter, _}] =
               token.operations
    end

    test "not_in_subquery operator through filter" do
      blocked_user_ids =
        Query.new(User)
        |> Query.where(:blocked, :eq, true)
        |> Query.select([:id])

      token =
        query Post do
          filter(:user_id, :not_in_subquery, blocked_user_ids)
        end

      assert [{:filter, {:user_id, :not_in_subquery, ^blocked_user_ids, []}}] = token.operations
    end

    test "multiple subquery filters" do
      active_users =
        Query.new(User)
        |> Query.where(:active, :eq, true)
        |> Query.select([:id])

      blocked_users =
        Query.new(User)
        |> Query.where(:blocked, :eq, true)
        |> Query.select([:id])

      token =
        query Post do
          filter(:user_id, :in_subquery, active_users)
          filter(:user_id, :not_in_subquery, blocked_users)
        end

      assert length(token.operations) == 2
    end
  end

  describe "DSL - complex combinations" do
    test "CTE + subquery + raw SQL + regular filters" do
      active_users_cte =
        Query.new(User)
        |> Query.where(:active, :eq, true)

      high_engagement_subquery =
        Query.new(Post)
        |> Query.where(:views, :gt, 1000)
        |> Query.select([:user_id])

      token =
        query Post do
          with_cte(:active_users, active_users_cte)
          filter(:user_id, :in_subquery, high_engagement_subquery)
          raw_where("created_at > :since", %{since: "2024-01-01"})
          filter(:published, :eq, true)
          order(:created_at, :desc)
          limit(50)
        end

      assert length(token.operations) == 6

      assert [
               {:cte, _},
               {:filter, {:user_id, :in_subquery, _, []}},
               {:raw_where, _},
               {:filter, _},
               {:order, _},
               {:limit, _}
             ] = token.operations
    end

    test "nested CTE with do blocks" do
      token =
        query Order do
          with_cte :recent_users do
            filter(:created_at, :gte, "2024-01-01")
            filter(:status, :eq, "active")
          end

          with_cte :high_value_orders do
            filter(:amount, :gte, 1000)
            filter(:status, :eq, "completed")
          end

          raw_where("shipping_country IN (:countries)", %{countries: ["US", "CA", "UK"]})
          filter(:processed, :eq, true)
        end

      assert length(token.operations) == 4
    end

    test "all features in single query" do
      subquery = Query.new(User) |> Query.where(:active, :eq, true) |> Query.select([:id])

      token =
        query Post do
          # CTE
          with_cte :active_users do
            filter(:status, :eq, "active")
            raw_where("last_login > :cutoff", %{cutoff: "2024-01-01"})
          end

          # Subquery
          filter(:user_id, :in_subquery, subquery)

          # Raw SQL
          raw_where("views > :min_views", %{min_views: 100})

          # Regular operations
          filter(:published, :eq, true)
          order(:created_at, :desc)
          paginate(:cursor, limit: 20)
        end

      assert length(token.operations) == 6
    end
  end

  describe "DSL - ergonomic examples" do
    test "realistic blog query with all features" do
      # Get active authors
      active_authors =
        Query.new(User)
        |> Query.where(:role, :eq, "author")
        |> Query.where(:active, :eq, true)
        |> Query.select([:id])

      # Build the main query
      token =
        query Post do
          # CTE for recent activity
          with_cte :recent_activity do
            filter(:created_at, :gte, "2024-01-01")
            filter(:status, :eq, "published")
          end

          # Filter by active authors (subquery)
          filter(:author_id, :in_subquery, active_authors)

          # Custom SQL condition
          raw_where("views > :min_views OR featured = :featured", %{min_views: 1000, featured: true})

          # Regular filters
          filter(:deleted_at, :is_nil, nil)
          filter(:draft, :eq, false)

          # Ordering and pagination
          order(:published_at, :desc)
          paginate(:cursor, limit: 25)
        end

      assert %Query.Token{} = token
      # 1: with_cte, 2: filter (subquery), 3: raw_where, 4-5: filters, 6: order, 7: paginate
      assert length(token.operations) == 7
    end
  end
end
