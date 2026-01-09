defmodule Events.AdvancedQueryTest do
  use Events.TestCase, async: true

  alias OmQuery

  describe "CTEs (Common Table Expressions)" do
    test "creates CTE from token" do
      cte_token =
        User
        |> OmQuery.new()
        |> OmQuery.where(:active, :eq, true)

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, cte_token)

      assert [{:cte, {:active_users, ^cte_token}}] = token.operations
    end

    test "creates CTE operation with token" do
      cte_token =
        User
        |> OmQuery.new()
        |> OmQuery.where(:status, :eq, "active")

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, cte_token)
        |> OmQuery.where(:published, :eq, true)

      assert [{:cte, {:active_users, ^cte_token}}, {:filter, _}] = token.operations
    end

    test "creates CTE operation with Ecto.Query" do
      import Ecto.Query

      cte_query = from("users", select: [:id])

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, cte_query)

      assert [{:cte, {:active_users, ^cte_query}}] = token.operations
    end

    test "creates CTE operation with raw SQL fragment" do
      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(
          :ranked_posts,
          {:fragment, "SELECT *, ROW_NUMBER() OVER (ORDER BY created_at DESC) as rank FROM posts"}
        )

      assert [{:cte, {:ranked_posts, {:fragment, sql}}}] = token.operations
      assert sql =~ "ROW_NUMBER()"
    end

    test "multiple CTEs" do
      cte1 =
        User
        |> OmQuery.new()
        |> OmQuery.where(:active, :eq, true)

      cte2 =
        Comment
        |> OmQuery.new()
        |> OmQuery.where(:approved, :eq, true)

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, cte1)
        |> OmQuery.with_cte(:approved_comments, cte2)

      assert [{:cte, {:active_users, _}}, {:cte, {:approved_comments, _}}] = token.operations
    end
  end

  describe "subqueries" do
    test "in_subquery with token creates filter operation" do
      user_ids_query =
        User
        |> OmQuery.new()
        |> OmQuery.where(:active, :eq, true)
        |> OmQuery.select([:id])

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.where(:user_id, :in_subquery, user_ids_query)

      assert [{:filter, {:user_id, :in_subquery, ^user_ids_query, []}}] = token.operations
    end

    test "not_in_subquery with token creates filter operation" do
      blocked_user_ids_query =
        User
        |> OmQuery.new()
        |> OmQuery.where(:status, :eq, "blocked")
        |> OmQuery.select([:id])

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.where(:user_id, :not_in_subquery, blocked_user_ids_query)

      assert [{:filter, {:user_id, :not_in_subquery, ^blocked_user_ids_query, []}}] =
               token.operations
    end

    test "in_subquery with Ecto.Query creates filter operation" do
      import Ecto.Query

      user_ids_query = from("users", where: [active: true], select: [:id])

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.where(:user_id, :in_subquery, user_ids_query)

      assert [{:filter, {:user_id, :in_subquery, ^user_ids_query, []}}] = token.operations
    end

    test "multiple subquery filters" do
      active_user_ids =
        User
        |> OmQuery.new()
        |> OmQuery.where(:active, :eq, true)
        |> OmQuery.select([:id])

      blocked_user_ids =
        User
        |> OmQuery.new()
        |> OmQuery.where(:blocked, :eq, true)
        |> OmQuery.select([:id])

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.where(:user_id, :in_subquery, active_user_ids)
        |> OmQuery.where(:user_id, :not_in_subquery, blocked_user_ids)

      assert length(token.operations) == 2

      assert [
               {:filter, {:user_id, :in_subquery, _, []}},
               {:filter, {:user_id, :not_in_subquery, _, []}}
             ] = token.operations
    end
  end

  describe "raw SQL with named parameters" do
    test "creates raw_where operation" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("age BETWEEN :min AND :max", %{min: 18, max: 65})

      assert [{:raw_where, {"age BETWEEN :min AND :max", %{min: 18, max: 65}}}] = token.operations
    end

    test "creates raw_where with multiple named parameters" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("name = :name AND email = :email", %{
          name: "John",
          email: "john@example.com"
        })

      assert [{:raw_where, {sql, params}}] = token.operations
      assert sql == "name = :name AND email = :email"
      assert params == %{name: "John", email: "john@example.com"}
    end

    test "creates raw_where with single named parameter" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("status = :status", %{status: "active"})

      assert [{:raw_where, {"status = :status", %{status: "active"}}}] = token.operations
    end

    test "creates raw_where with no parameters" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("created_at > NOW() - INTERVAL '7 days'", %{})

      assert [{:raw_where, {sql, %{}}}] = token.operations
      assert sql =~ "NOW()"
    end

    test "creates raw_where with duplicate parameter names" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("age >= :threshold OR rank >= :threshold", %{threshold: 100})

      assert [{:raw_where, {sql, %{threshold: 100}}}] = token.operations
      assert sql =~ ":threshold"
    end

    test "combines raw_where with regular filters" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.where(:status, :eq, "active")
        |> OmQuery.raw_where("age BETWEEN :min AND :max", %{min: 18, max: 65})
        |> OmQuery.where(:verified, :eq, true)

      assert length(token.operations) == 3
      assert [{:filter, _}, {:raw_where, _}, {:filter, _}] = token.operations
    end

    test "multiple raw_where clauses" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("age >= :min_age", %{min_age: 18})
        |> OmQuery.raw_where("score <= :max_score", %{max_score: 100})

      assert length(token.operations) == 2
      assert [{:raw_where, _}, {:raw_where, _}] = token.operations
    end
  end

  describe "complex combinations" do
    test "CTE with subquery and raw SQL operations" do
      # Create a CTE for active users
      active_users_cte =
        User
        |> OmQuery.new()
        |> OmQuery.where(:active, :eq, true)
        |> OmQuery.raw_where("last_login > :cutoff", %{cutoff: "2024-01-01"})

      # Create a subquery for high-engagement posts
      high_engagement_posts =
        Post
        |> OmQuery.new()
        |> OmQuery.where(:views, :gt, 1000)
        |> OmQuery.select([:user_id])

      # Main query combining everything
      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, active_users_cte)
        |> OmQuery.where(:user_id, :in_subquery, high_engagement_posts)
        |> OmQuery.where(:published, :eq, true)

      assert length(token.operations) == 3

      assert [
               {:cte, _},
               {:filter, {:user_id, :in_subquery, _, []}},
               {:filter, {:published, :eq, true, []}}
             ] = token.operations
    end

    test "CTE with raw SQL fragment" do
      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:ranked, {:fragment, "SELECT *, ROW_NUMBER() OVER () as rn FROM posts"})
        |> OmQuery.where(:published, :eq, true)

      assert [{:cte, {:ranked, {:fragment, _}}}, {:filter, _}] = token.operations
    end

    test "all advanced features together" do
      cte =
        User
        |> OmQuery.new()
        |> OmQuery.where(:active, :eq, true)

      subquery =
        Post
        |> OmQuery.new()
        |> OmQuery.where(:views, :gt, 100)
        |> OmQuery.select([:user_id])

      token =
        Post
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, cte)
        |> OmQuery.where(:user_id, :in_subquery, subquery)
        |> OmQuery.raw_where("created_at > :since", %{since: "2024-01-01"})
        |> OmQuery.where(:published, :eq, true)

      assert length(token.operations) == 4
    end
  end
end
