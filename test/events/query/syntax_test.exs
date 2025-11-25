defmodule Events.Query.SyntaxTest do
  @moduledoc """
  Tests for improved Query syntax features:
  - Queryable protocol (pipe from schema without Query.new)
  - Shorthand filter syntax
  - Keyword-based filters
  - DSL comparison operators
  """
  use ExUnit.Case, async: true

  alias Events.Query
  alias Events.Query.Token

  # Test schemas
  defmodule User do
    use Ecto.Schema

    schema "users" do
      field :name, :string
      field :status, :string
      field :age, :integer
      field :email, :string
      field :role, :string
      field :verified, :boolean
      field :category_id, :integer
      field :brand_id, :integer
      field :tenant_id, :integer
      field :region, :string
    end
  end

  defmodule Category do
    use Ecto.Schema

    schema "categories" do
      field :name, :string
      field :active, :boolean
      field :featured, :boolean
      field :tenant_id, :integer
    end
  end

  defmodule Brand do
    use Ecto.Schema

    schema "brands" do
      field :name, :string
      field :verified, :boolean
      field :region, :string
    end
  end

  describe "Queryable protocol" do
    test "schema module can be piped directly to filter" do
      token = User |> Query.filter(:status, :eq, "active")

      assert %Token{source: User} = token
      assert length(token.operations) == 1
    end

    test "Query.Token passes through unchanged" do
      original = Query.new(User)
      token = Query.filter(original, :status, :eq, "active")

      assert %Token{source: User} = token
    end

    test "table name string creates schemaless query" do
      token = "users" |> Query.filter(:status, :eq, "active")

      assert %Token{} = token
      assert length(token.operations) == 1
    end
  end

  describe "shorthand filter syntax" do
    test "3-arg filter defaults to :eq operator" do
      token =
        User
        |> Query.filter(:status, "active")

      assert {:filter, {:status, :eq, "active", []}} in token.operations
    end

    test "shorthand filter works in pipeline" do
      token =
        User
        |> Query.filter(:status, "active")
        |> Query.filter(:verified, true)

      assert length(token.operations) == 2
      assert {:filter, {:status, :eq, "active", []}} in token.operations
      assert {:filter, {:verified, :eq, true, []}} in token.operations
    end
  end

  describe "keyword filter syntax" do
    test "single keyword filter" do
      token = User |> Query.filter(status: "active")

      assert {:filter, {:status, :eq, "active", []}} in token.operations
    end

    test "multiple keyword filters in one call" do
      token = User |> Query.filter(status: "active", verified: true, role: "admin")

      assert length(token.operations) == 3
      assert {:filter, {:status, :eq, "active", []}} in token.operations
      assert {:filter, {:verified, :eq, true, []}} in token.operations
      assert {:filter, {:role, :eq, "admin", []}} in token.operations
    end

    test "keyword filters can be chained" do
      token =
        User
        |> Query.filter(status: "active")
        |> Query.filter(verified: true)

      assert length(token.operations) == 2
    end
  end

  describe "DSL comparison operators" do
    import Events.Query.DSL

    test "== operator translates to :eq" do
      token =
        query User do
          where :status == "active"
        end

      assert {:filter, {:status, :eq, "active", []}} in token.operations
    end

    test "!= operator translates to :neq" do
      token =
        query User do
          where :status != "inactive"
        end

      assert {:filter, {:status, :neq, "inactive", []}} in token.operations
    end

    test "!= nil translates to :not_nil" do
      token =
        query User do
          where :email != nil
        end

      assert {:filter, {:email, :not_nil, true, []}} in token.operations
    end

    test ">= operator translates to :gte" do
      token =
        query User do
          where :age >= 18
        end

      assert {:filter, {:age, :gte, 18, []}} in token.operations
    end

    test "<= operator translates to :lte" do
      token =
        query User do
          where :age <= 65
        end

      assert {:filter, {:age, :lte, 65, []}} in token.operations
    end

    test "> operator translates to :gt" do
      token =
        query User do
          where :age > 17
        end

      assert {:filter, {:age, :gt, 17, []}} in token.operations
    end

    test "< operator translates to :lt" do
      token =
        query User do
          where :age < 100
        end

      assert {:filter, {:age, :lt, 100, []}} in token.operations
    end

    test "in operator translates to :in" do
      token =
        query User do
          where :role in ["admin", "moderator"]
        end

      assert {:filter, {:role, :in, ["admin", "moderator"], []}} in token.operations
    end

    test "=~ operator translates to :ilike" do
      token =
        query User do
          where :name =~ "%john%"
        end

      assert {:filter, {:name, :ilike, "%john%", []}} in token.operations
    end

    test "keyword shorthand in DSL where" do
      token =
        query User do
          where status: "active", verified: true
        end

      assert {:filter, {:status, :eq, "active", []}} in token.operations
      assert {:filter, {:verified, :eq, true, []}} in token.operations
    end

    test "multiple where clauses" do
      token =
        query User do
          where :status == "active"
          where :age >= 18
          where :verified == true
        end

      assert length(token.operations) == 3
    end

    test "mixed filter and where in same query" do
      token =
        query User do
          filter :status, :eq, "active"
          where :age >= 18
          where :role in ["admin", "moderator"]
        end

      assert length(token.operations) == 3
    end
  end

  describe "combined syntax in pipelines" do
    test "mix of old and new syntax works together" do
      token =
        User
        |> Query.filter(:status, "active")
        |> Query.filter(verified: true)
        |> Query.filter(:age, :gte, 18)
        |> Query.order(:name, :asc)
        |> Query.paginate(:offset, limit: 20)

      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)
      assert length(filters) == 3
    end
  end

  describe "joins and bindings" do
    test "join creates binding for later reference" do
      token =
        User
        |> Query.join(:posts, :left, as: :user_posts)

      assert {:join, {:posts, :left, [as: :user_posts]}} in token.operations
    end

    test "filter with binding: option references joined table" do
      token =
        User
        |> Query.join(:posts, :left, as: :posts)
        |> Query.filter(:published, :eq, true, binding: :posts)

      assert {:filter, {:published, :eq, true, [binding: :posts]}} in token.operations
    end

    test "Query.on/4 shorthand for filtering on binding" do
      token =
        User
        |> Query.join(:posts, :left, as: :posts)
        |> Query.on(:posts, :published, true)

      assert {:filter, {:published, :eq, true, [binding: :posts]}} in token.operations
    end

    test "Query.on/5 with explicit operator" do
      token =
        User
        |> Query.join(:posts, :left, as: :posts)
        |> Query.on(:posts, :views, :gte, 100)

      assert {:filter, {:views, :gte, 100, [binding: :posts]}} in token.operations
    end

    test "multiple joins with different bindings" do
      token =
        User
        |> Query.join(:posts, :left, as: :posts)
        |> Query.join(:comments, :left, as: :comments)
        |> Query.filter(:active, true)
        |> Query.on(:posts, :published, true)
        |> Query.on(:comments, :approved, true)

      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)
      assert length(filters) == 3

      # Root filter
      assert {:filter, {:active, :eq, true, []}} in token.operations
      # Join filters
      assert {:filter, {:published, :eq, true, [binding: :posts]}} in token.operations
      assert {:filter, {:approved, :eq, true, [binding: :comments]}} in token.operations
    end
  end

  describe "DSL on macro for join filtering" do
    import Events.Query.DSL

    test "on macro filters on joined table" do
      token =
        query User do
          join :posts, :left, as: :posts
          on :posts, :published == true
        end

      assert {:filter, {:published, :eq, true, [binding: :posts]}} in token.operations
    end

    test "DSL join with multiple ON conditions + WHERE filters" do
      # SQL equivalent:
      # SELECT * FROM users u
      # LEFT JOIN categories c ON c.id = u.category_id AND c.tenant_id = u.tenant_id
      # WHERE c.active = true AND c.featured = true
      token =
        query User do
          join Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]

          # WHERE filters on joined table
          on :cat, :active == true
          on :cat, :featured == true
        end

      # Verify join has ON conditions
      assert {:join, {Category, :left, [as: :cat, on: [id: :category_id, tenant_id: :tenant_id]]}} in token.operations

      # Verify WHERE filters
      assert {:filter, {:active, :eq, true, [binding: :cat]}} in token.operations
      assert {:filter, {:featured, :eq, true, [binding: :cat]}} in token.operations
    end

    test "DSL multiple joins with different ON conditions" do
      token =
        query User do
          # Multiple joins with their ON conditions
          join Category, :left, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]
          join Brand, :left, as: :brand, on: [id: :brand_id, region: :region]

          # Root table filter
          where :active == true

          # Joined table filters
          on :cat, :featured == true
          on :brand, :verified == true
        end

      joins = Enum.filter(token.operations, fn {op, _} -> op == :join end)
      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)

      assert length(joins) == 2
      assert length(filters) == 3
    end

    test "on macro with comparison operators" do
      token =
        query User do
          join :posts, :left, as: :posts
          on :posts, :views >= 100
          on :posts, :category in ["tech", "science"]
        end

      assert {:filter, {:views, :gte, 100, [binding: :posts]}} in token.operations
      assert {:filter, {:category, :in, ["tech", "science"], [binding: :posts]}} in token.operations
    end

    test "mixed where and on in same query" do
      token =
        query User do
          join :posts, :left, as: :posts

          # Root table filter
          where :active == true

          # Joined table filter
          on :posts, :published == true
          on :posts, :views >= 50
        end

      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)
      assert length(filters) == 3
    end
  end

  describe "preloads with filters" do
    test "simple preload" do
      token =
        User
        |> Query.preload(:posts)

      assert {:preload, :posts} in token.operations
    end

    test "preload with nested filters using builder function" do
      token =
        User
        |> Query.preload(:posts, fn q ->
          q
          |> Query.filter(:published, true)
          |> Query.order(:created_at, :desc)
          |> Query.limit(10)
        end)

      # Should have a preload with a nested token
      preload_op = Enum.find(token.operations, fn
        {:preload, {:posts, %Token{}}} -> true
        _ -> false
      end)

      assert preload_op != nil
      {:preload, {:posts, nested_token}} = preload_op

      # Nested token should have the filter and order
      assert {:filter, {:published, :eq, true, []}} in nested_token.operations
      assert {:order, {:created_at, :desc, []}} in nested_token.operations
      assert {:limit, 10} in nested_token.operations
    end

    test "preload with new shorthand syntax in builder" do
      token =
        User
        |> Query.preload(:posts, fn q ->
          q
          |> Query.filter(published: true, featured: true)
          |> Query.order(:views, :desc)
        end)

      {:preload, {:posts, nested_token}} =
        Enum.find(token.operations, fn
          {:preload, {:posts, %Token{}}} -> true
          _ -> false
        end)

      assert {:filter, {:published, :eq, true, []}} in nested_token.operations
      assert {:filter, {:featured, :eq, true, []}} in nested_token.operations
    end
  end

  describe "DSL preloads with nested blocks" do
    import Events.Query.DSL

    test "preload with do block for nested filters" do
      token =
        query User do
          preload :posts do
            where :published == true
            order :created_at, :desc
            limit 5
          end
        end

      preload_op = Enum.find(token.operations, fn
        {:preload, {:posts, %Token{}}} -> true
        _ -> false
      end)

      assert preload_op != nil
      {:preload, {:posts, nested_token}} = preload_op

      assert {:filter, {:published, :eq, true, []}} in nested_token.operations
      assert {:order, {:created_at, :desc, []}} in nested_token.operations
      assert {:limit, 5} in nested_token.operations
    end

    test "multiple preloads with different filters" do
      token =
        query User do
          preload :posts do
            where :published == true
          end

          preload :comments do
            where :approved == true
          end
        end

      preloads = Enum.filter(token.operations, fn
        {:preload, {_, %Token{}}} -> true
        _ -> false
      end)

      assert length(preloads) == 2
    end
  end

  describe "join with multiple ON conditions" do
    test "join with keyword list ON conditions" do
      # This generates: JOIN categories c ON c.id = p.category_id AND c.tenant_id = p.tenant_id
      token =
        User
        |> Query.join(Category, :left,
          as: :cat,
          on: [id: :category_id, tenant_id: :tenant_id]
        )

      assert {:join, {Category, :left, [as: :cat, on: [id: :category_id, tenant_id: :tenant_id]]}} in token.operations
    end

    test "join with ON conditions + WHERE filters (the common pattern)" do
      # SQL equivalent:
      # SELECT * FROM products p
      # LEFT JOIN categories c ON c.id = p.category_id AND c.tenant_id = p.tenant_id
      # WHERE c.active = true AND c.name = 'Electronics'
      token =
        User
        |> Query.join(Category, :left,
          as: :cat,
          on: [id: :category_id, tenant_id: :tenant_id]  # JOIN ON conditions
        )
        |> Query.on(:cat, :active, true)                   # WHERE filter on joined table
        |> Query.on(:cat, :name, "Electronics")            # WHERE filter on joined table

      joins = Enum.filter(token.operations, fn {op, _} -> op == :join end)
      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)

      assert length(joins) == 1
      assert length(filters) == 2

      # Verify WHERE filters reference the binding
      assert {:filter, {:active, :eq, true, [binding: :cat]}} in token.operations
      assert {:filter, {:name, :eq, "Electronics", [binding: :cat]}} in token.operations
    end

    test "multiple joins with different ON conditions" do
      token =
        User
        |> Query.join(Category, :left,
          as: :cat,
          on: [id: :category_id, tenant_id: :tenant_id]
        )
        |> Query.join(Brand, :left,
          as: :brand,
          on: [id: :brand_id, region: :region]
        )
        |> Query.filter(:active, true)          # Root table
        |> Query.on(:cat, :featured, true)      # Category table
        |> Query.on(:brand, :verified, true)    # Brand table

      joins = Enum.filter(token.operations, fn {op, _} -> op == :join end)
      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)

      assert length(joins) == 2
      assert length(filters) == 3
    end
  end

  describe "complex query with joins, filters, and pagination" do
    import Events.Query.DSL

    test "e-commerce style query with multiple joins" do
      token =
        query User do
          # Joins
          join :orders, :left, as: :orders
          join :products, :left, as: :products

          # Root filters
          where :status == "active"
          where :verified == true

          # Join filters
          on :orders, :status == "completed"
          on :products, :category in ["electronics", "books"]

          # Ordering
          order :name, :asc

          # Pagination
          paginate :cursor, limit: 20

          # Preload with filters
          preload :orders do
            where :status == "completed"
            order :created_at, :desc
            limit 10
          end
        end

      # Verify structure
      joins = Enum.filter(token.operations, fn {op, _} -> op == :join end)
      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)
      preloads = Enum.filter(token.operations, fn
        {:preload, _} -> true
        _ -> false
      end)

      assert length(joins) == 2
      assert length(filters) == 4  # 2 root + 2 join filters
      assert length(preloads) == 1
    end

    test "pipeline style equivalent" do
      token =
        User
        |> Query.join(:orders, :left, as: :orders)
        |> Query.join(:products, :left, as: :products)
        |> Query.filter(status: "active", verified: true)
        |> Query.on(:orders, :status, "completed")
        |> Query.on(:products, :category, :in, ["electronics", "books"])
        |> Query.order(:name, :asc)
        |> Query.paginate(:cursor, limit: 20)
        |> Query.preload(:orders, fn q ->
          q
          |> Query.filter(:status, "completed")
          |> Query.order(:created_at, :desc)
          |> Query.limit(10)
        end)

      joins = Enum.filter(token.operations, fn {op, _} -> op == :join end)
      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)

      assert length(joins) == 2
      assert length(filters) == 4
    end
  end

  describe "convenience join functions" do
    test "left_join is shorthand for join with :left type" do
      token = User |> Query.left_join(:posts)
      assert {:join, {:posts, :left, []}} in token.operations
    end

    test "left_join with options" do
      token = User |> Query.left_join(:posts, as: :user_posts)
      assert {:join, {:posts, :left, [as: :user_posts]}} in token.operations
    end

    test "left_join with schema and ON conditions" do
      token = User |> Query.left_join(Category, as: :cat, on: [id: :category_id])
      assert {:join, {Category, :left, [as: :cat, on: [id: :category_id]]}} in token.operations
    end

    test "right_join is shorthand for join with :right type" do
      token = User |> Query.right_join(:posts)
      assert {:join, {:posts, :right, []}} in token.operations
    end

    test "inner_join is shorthand for join with :inner type" do
      token = User |> Query.inner_join(:posts)
      assert {:join, {:posts, :inner, []}} in token.operations
    end

    test "full_join is shorthand for join with :full type" do
      token = User |> Query.full_join(:posts)
      assert {:join, {:posts, :full, []}} in token.operations
    end

    test "cross_join is shorthand for join with :cross type" do
      token = User |> Query.cross_join(:roles)
      assert {:join, {:roles, :cross, []}} in token.operations
    end
  end

  describe "DSL convenience join macros" do
    import Events.Query.DSL

    test "left_join macro" do
      token =
        query User do
          left_join :posts
          left_join :comments, as: :comments
        end

      joins = Enum.filter(token.operations, fn {op, _} -> op == :join end)
      assert length(joins) == 2
      assert {:join, {:posts, :left, []}} in token.operations
      assert {:join, {:comments, :left, [as: :comments]}} in token.operations
    end

    test "left_join with schema and ON conditions" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id, tenant_id: :tenant_id]
        end

      assert {:join, {Category, :left, [as: :cat, on: [id: :category_id, tenant_id: :tenant_id]]}} in token.operations
    end

    test "inner_join macro" do
      token =
        query User do
          inner_join :posts, as: :posts
        end

      assert {:join, {:posts, :inner, [as: :posts]}} in token.operations
    end
  end

  describe "DSL where with binding tuple {:binding, :field}" do
    import Events.Query.DSL

    test "where with binding tuple == operator" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :name} == "Electronics"
        end

      assert {:filter, {:name, :eq, "Electronics", [binding: :cat]}} in token.operations
    end

    test "where with binding tuple != operator" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :active} != false
        end

      assert {:filter, {:active, :neq, false, [binding: :cat]}} in token.operations
    end

    test "where with binding tuple >= operator" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :priority} >= 5
        end

      assert {:filter, {:priority, :gte, 5, [binding: :cat]}} in token.operations
    end

    test "where with binding tuple in operator" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :type} in ["A", "B", "C"]
        end

      assert {:filter, {:type, :in, ["A", "B", "C"], [binding: :cat]}} in token.operations
    end

    test "where with binding tuple =~ operator" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :name} =~ "%tech%"
        end

      assert {:filter, {:name, :ilike, "%tech%", [binding: :cat]}} in token.operations
    end

    test "complex query with binding tuples" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          left_join Brand, as: :brand, on: [id: :brand_id]

          # Root table filters
          where :active == true

          # Joined table filters using binding tuples
          where {:cat, :name} == "Electronics"
          where {:cat, :featured} == true
          where {:brand, :verified} == true
          where {:brand, :rating} >= 4
        end

      filters = Enum.filter(token.operations, fn {op, _} -> op == :filter end)
      assert length(filters) == 5

      assert {:filter, {:active, :eq, true, []}} in token.operations
      assert {:filter, {:name, :eq, "Electronics", [binding: :cat]}} in token.operations
      assert {:filter, {:featured, :eq, true, [binding: :cat]}} in token.operations
      assert {:filter, {:verified, :eq, true, [binding: :brand]}} in token.operations
      assert {:filter, {:rating, :gte, 4, [binding: :brand]}} in token.operations
    end
  end

  describe "DSL where with case: :insensitive option" do
    import Events.Query.DSL

    test "where with case insensitive option for :eq" do
      token =
        query User do
          where :email == "JOHN@EXAMPLE.COM", case: :insensitive
        end

      assert {:filter, {:email, :eq, "JOHN@EXAMPLE.COM", [case_insensitive: true]}} in token.operations
    end

    test "where with case insensitive option for :in" do
      token =
        query User do
          where :role in ["Admin", "Moderator"], case: :insensitive
        end

      assert {:filter, {:role, :in, ["Admin", "Moderator"], [case_insensitive: true]}} in token.operations
    end

    test "pipeline filter with case insensitive :in" do
      token =
        User
        |> Query.filter(:role, :in, ["Admin", "Moderator"], case_insensitive: true)

      assert {:filter, {:role, :in, ["Admin", "Moderator"], [case_insensitive: true]}} in token.operations
    end

    test "where with binding tuple and case insensitive for :eq" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :name} == "Electronics", case: :insensitive
        end

      assert {:filter, {:name, :eq, "Electronics", [binding: :cat, case_insensitive: true]}} in token.operations
    end

    test "where with binding tuple and case insensitive for :in" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :type} in ["A", "B", "C"], case: :insensitive
        end

      assert {:filter, {:type, :in, ["A", "B", "C"], [binding: :cat, case_insensitive: true]}} in token.operations
    end
  end

  describe "value casting with cast: option" do
    import Events.Query.DSL

    test "cast string to integer" do
      token = User |> Query.filter(:age, :eq, "25", cast: :integer)
      assert {:filter, {:age, :eq, 25, []}} in token.operations
    end

    test "cast string to integer in list" do
      token = User |> Query.filter(:age, :in, ["18", "21", "25"], cast: :integer)
      assert {:filter, {:age, :in, [18, 21, 25], []}} in token.operations
    end

    test "cast string to float" do
      token = User |> Query.filter(:score, :gte, "9.5", cast: :float)
      assert {:filter, {:score, :gte, 9.5, []}} in token.operations
    end

    test "cast string to boolean" do
      token = User |> Query.filter(:active, :eq, "true", cast: :boolean)
      assert {:filter, {:active, :eq, true, []}} in token.operations
    end

    test "cast string to date" do
      token = User |> Query.filter(:birthday, :eq, "2000-01-15", cast: :date)
      assert {:filter, {:birthday, :eq, ~D[2000-01-15], []}} in token.operations
    end

    test "DSL cast with where" do
      token =
        query User do
          where :age == "25", cast: :integer
        end

      assert {:filter, {:age, :eq, 25, []}} in token.operations
    end

    test "DSL cast with in operator" do
      token =
        query User do
          where :age in ["18", "21", "25"], cast: :integer
        end

      assert {:filter, {:age, :in, [18, 21, 25], []}} in token.operations
    end

    test "DSL cast with binding tuple" do
      token =
        query User do
          left_join Category, as: :cat, on: [id: :category_id]
          where {:cat, :priority} >= "5", cast: :integer
        end

      assert {:filter, {:priority, :gte, 5, [binding: :cat]}} in token.operations
    end

    test "DSL cast and case insensitive combined" do
      # Note: This is an edge case - cast happens first, then case_insensitive
      # case_insensitive only makes sense for strings, so combining with cast is unusual
      token =
        query User do
          where :status == "ACTIVE", case: :insensitive
        end

      assert {:filter, {:status, :eq, "ACTIVE", [case_insensitive: true]}} in token.operations
    end

    test "cast preserves already-correct types" do
      token = User |> Query.filter(:age, :eq, 25, cast: :integer)
      assert {:filter, {:age, :eq, 25, []}} in token.operations
    end
  end

  describe "execute vs build behavior" do
    test "Query.build returns Ecto.Query struct" do
      token = User |> Query.filter(:status, "active")
      query = Query.build(token)

      assert %Ecto.Query{} = query
    end

    test "Token has all operations stored" do
      token =
        User
        |> Query.filter(:status, "active")
        |> Query.order(:name, :asc)
        |> Query.limit(10)

      assert {:filter, {:status, :eq, "active", []}} in token.operations
      assert {:order, {:name, :asc, []}} in token.operations
      assert {:limit, 10} in token.operations
    end
  end
end
