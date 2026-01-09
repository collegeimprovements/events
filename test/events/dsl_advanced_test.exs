defmodule Events.DSLAdvancedTest do
  use Events.TestCase, async: true

  import OmQuery.DSL
  alias OmQuery, as: Query

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
      assert %OmQuery.Token{} = cte_token
      assert length(cte_token.operations) == 2
    end

    test "with_cte using existing token" do
      cte_token =
        OmQuery.new(User)
        |> OmQuery.where(:active, :eq, true)

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
      assert [{:filter, _}, {:raw_where, {sql, params, _opts}}, {:filter, _}] = token.operations
      assert sql == "age BETWEEN :min AND :max"
      assert params == %{min: 18, max: 65}
    end

    test "raw_where without parameters" do
      token =
        query User do
          raw_where("created_at > NOW() - INTERVAL '7 days'")
        end

      assert [{:raw_where, {sql, params, _opts}}] = token.operations
      assert sql =~ "NOW()"
      assert params == []
    end

    test "raw_where with single parameter" do
      token =
        query User do
          raw_where("status = :status", %{status: "premium"})
        end

      assert [{:raw_where, {"status = :status", %{status: "premium"}, []}}] = token.operations
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
        OmQuery.new(User)
        |> OmQuery.where(:active, :eq, true)
        |> OmQuery.select([:id])

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
        OmQuery.new(User)
        |> OmQuery.where(:blocked, :eq, true)
        |> OmQuery.select([:id])

      token =
        query Post do
          filter(:user_id, :not_in_subquery, blocked_user_ids)
        end

      assert [{:filter, {:user_id, :not_in_subquery, ^blocked_user_ids, []}}] = token.operations
    end

    test "multiple subquery filters" do
      active_users =
        OmQuery.new(User)
        |> OmQuery.where(:active, :eq, true)
        |> OmQuery.select([:id])

      blocked_users =
        OmQuery.new(User)
        |> OmQuery.where(:blocked, :eq, true)
        |> OmQuery.select([:id])

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
        OmQuery.new(User)
        |> OmQuery.where(:active, :eq, true)

      high_engagement_subquery =
        OmQuery.new(Post)
        |> OmQuery.where(:views, :gt, 1000)
        |> OmQuery.select([:user_id])

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
      subquery = OmQuery.new(User) |> OmQuery.where(:active, :eq, true) |> OmQuery.select([:id])

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
        OmQuery.new(User)
        |> OmQuery.where(:role, :eq, "author")
        |> OmQuery.where(:active, :eq, true)
        |> OmQuery.select([:id])

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

      assert %OmQuery.Token{} = token
      # 1: with_cte, 2: filter (subquery), 3: raw_where, 4-5: filters, 6: order, 7: paginate
      assert length(token.operations) == 7
    end
  end

  describe "DSL - maybe with :when predicate" do
    test "maybe with default :present predicate" do
      # nil value - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:status, nil)

      assert token.operations == []

      # present value - should add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:status, "active")

      assert [{:filter, {:status, :eq, "active", []}}] = token.operations
    end

    test "maybe with :not_nil predicate allows false and empty string" do
      # nil - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:active, nil, :eq, when: :not_nil)

      assert token.operations == []

      # false - should add filter (not nil)
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:active, false, :eq, when: :not_nil)

      assert [{:filter, {:active, :eq, false, []}}] = token.operations

      # empty string - should add filter (not nil)
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:name, "", :eq, when: :not_nil)

      assert [{:filter, {:name, :eq, "", []}}] = token.operations
    end

    test "maybe with :not_blank predicate" do
      # nil - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:name, nil, :ilike, when: :not_blank)

      assert token.operations == []

      # empty string - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:name, "", :ilike, when: :not_blank)

      assert token.operations == []

      # whitespace only - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:name, "   ", :ilike, when: :not_blank)

      assert token.operations == []

      # valid string - should add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:name, "john", :ilike, when: :not_blank)

      assert [{:filter, {:name, :ilike, "john", []}}] = token.operations
    end

    test "maybe with :not_empty predicate" do
      # nil - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:tags, nil, :in, when: :not_empty)

      assert token.operations == []

      # empty list - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:tags, [], :in, when: :not_empty)

      assert token.operations == []

      # empty map - should not add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:metadata, %{}, :eq, when: :not_empty)

      assert token.operations == []

      # non-empty list - should add filter
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:tags, ["a", "b"], :in, when: :not_empty)

      assert [{:filter, {:tags, :in, ["a", "b"], []}}] = token.operations
    end

    test "maybe with custom predicate function" do
      # Value doesn't pass predicate
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:score, 0, :gte, when: &(&1 && &1 > 0))

      assert token.operations == []

      # Value passes predicate
      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:score, 50, :gte, when: &(&1 && &1 > 0))

      assert [{:filter, {:score, :gte, 50, []}}] = token.operations
    end

    test "maybe_on with :when predicate on joined table" do
      # nil value - should not add filter
      token =
        OmQuery.new(Product)
        |> OmQuery.maybe_on(:cat, :name, nil, :eq, when: :not_nil)

      assert token.operations == []

      # present value - should add filter with binding
      token =
        OmQuery.new(Product)
        |> OmQuery.maybe_on(:cat, :name, "Electronics", :eq, when: :not_nil)

      assert [{:filter, {:name, :eq, "Electronics", [binding: :cat]}}] = token.operations
    end

    test "maybe in DSL with :when option" do
      token =
        query User do
          maybe(:status == "active", when: :not_nil)
        end

      assert [{:filter, {:status, :eq, "active", []}}] = token.operations
    end
  end
end
