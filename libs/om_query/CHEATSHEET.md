# OmQuery Cheatsheet

> Composable query builder for Ecto with cursor pagination, full-text search, and faceted filtering. For full docs, see `README.md`.

## Setup

```elixir
config :om_query, default_repo: MyApp.Repo
config :om_query, OmQuery.Token, default_limit: 20, max_limit: 1000
```

```elixir
alias OmQuery
alias OmQuery.{Result, Cursor, FacetedSearch, Merge}
```

---

## Query Building

```elixir
# Create token
token = OmQuery.new(User)

# Filter (where)
|> OmQuery.filter(:status, :active)              # equality
|> OmQuery.filter(:age, :gte, 18)                # comparison
|> OmQuery.filter(:role, :in, [:admin, :mod])     # in list
|> OmQuery.filter(:email, :ilike, "%@corp.com")   # pattern
|> OmQuery.filter(:deleted_at, :is_nil)           # null check
|> OmQuery.filter(:score, :between, {1, 100})     # range
|> OmQuery.filter(:tags, :contains, ["elixir"])    # array contains
|> OmQuery.filter(:meta, :jsonb_has_key, "plan")   # JSONB

# Multiple equality filters
|> OmQuery.filter(status: :active, role: :admin)

# Conditional (only applies if value is truthy)
|> OmQuery.maybe(:status, params[:status])
|> OmQuery.maybe(:role, params[:role], :eq, when: :present)
```

---

## Filter Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `:eq` | `=` | `filter(:status, :eq, :active)` |
| `:neq` | `!=` | `filter(:status, :neq, :deleted)` |
| `:gt` | `>` | `filter(:age, :gt, 18)` |
| `:gte` | `>=` | `filter(:age, :gte, 18)` |
| `:lt` | `<` | `filter(:price, :lt, 100)` |
| `:lte` | `<=` | `filter(:price, :lte, 100)` |
| `:in` | `IN` | `filter(:role, :in, [:a, :b])` |
| `:not_in` | `NOT IN` | `filter(:role, :not_in, [:x])` |
| `:like` | `LIKE` | `filter(:name, :like, "J%")` |
| `:ilike` | `ILIKE` | `filter(:email, :ilike, "%@gmail%")` |
| `:is_nil` | `IS NULL` | `filter(:deleted_at, :is_nil)` |
| `:not_nil` | `IS NOT NULL` | `filter(:verified_at, :not_nil)` |
| `:between` | `BETWEEN` | `filter(:score, :between, {1, 10})` |
| `:contains` | `@>` | `filter(:tags, :contains, ["a"])` |
| `:jsonb_contains` | `@>` | `filter(:meta, :jsonb_contains, %{})` |
| `:jsonb_has_key` | `?` | `filter(:meta, :jsonb_has_key, "k")` |
| `:similarity` | `%` | `filter(:name, :similarity, "srch")` |

---

## Advanced Filtering

```elixir
# OR group (any match)
|> OmQuery.where_any([
  {:status, :eq, :active},
  {:role, :eq, :admin}
])

# AND group (all match)
|> OmQuery.where_all([
  {:age, :gte, 18},
  {:verified_at, :not_nil}
])

# NOR group (none match)
|> OmQuery.where_none([
  {:status, :eq, :banned},
  {:status, :eq, :deleted}
])

# Negated
|> OmQuery.where_not(:status, :eq, :deleted)

# Compare two fields
|> OmQuery.where_field(:updated_at, :gt, :inserted_at)

# Filter on joined table
|> OmQuery.on(:organization, :plan, :eq, :enterprise)

# Raw SQL escape hatch
|> OmQuery.raw("age > ? AND age < ?", [18, 65])
```

---

## Convenience Filters

```elixir
|> OmQuery.exclude_deleted()                     # deleted_at IS NULL
|> OmQuery.only_deleted()                        # deleted_at IS NOT NULL
|> OmQuery.created_between(~D[2024-01-01], ~D[2024-12-31])
|> OmQuery.between(:price, 10, 100)
|> OmQuery.at_least(:score, 80)
|> OmQuery.at_most(:age, 65)
|> OmQuery.where_nil(:deleted_at)
|> OmQuery.where_not_nil(:verified_at)
|> OmQuery.where_blank(:bio)                     # NULL or ""
|> OmQuery.where_present(:email)                 # NOT NULL and not ""
|> OmQuery.with_status(:active)
|> OmQuery.with_status([:active, :pending])
|> OmQuery.updated_since(~U[2024-01-01 00:00:00Z])
|> OmQuery.created_today()
|> OmQuery.updated_recently(24)                  # last 24 hours
```

---

## Subquery Filters

```elixir
|> OmQuery.exists(admin_query)
|> OmQuery.not_exists(banned_query)
|> OmQuery.filter_subquery(:org_id, :in, active_orgs_query)
|> OmQuery.filter_subquery(:id, :not_in, excluded_query)
```

---

## Search

```elixir
# Basic (ILIKE across fields)
|> OmQuery.search("john", [:name, :email])

# With mode
|> OmQuery.search("john", [:name], mode: :starts_with)
# Modes: :ilike | :like | :starts_with | :ends_with | :exact | :similarity

# Per-field config
|> OmQuery.search("john", [
  {:name, :ilike},
  {:email, :exact},
  {:bio, :similarity, rank: 2}
], rank: true)
```

---

## Ordering

```elixir
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.order(:name, :asc)
|> OmQuery.order(:score, :desc_nulls_last)

# Multiple
|> OmQuery.orders([
  {:inserted_at, :desc},
  {:name, :asc}
])
```

---

## Pagination

```elixir
# Cursor pagination (recommended)
|> OmQuery.paginate(:cursor, limit: 20)
|> OmQuery.paginate(:cursor, limit: 20, after: cursor)
|> OmQuery.paginate(:cursor, limit: 20, before: cursor)

# Offset pagination
|> OmQuery.paginate(:offset, limit: 20, offset: 40)

# Simple limit/offset
|> OmQuery.limit(10)
|> OmQuery.offset(20)
```

---

## Joins & Preloads

```elixir
# Joins
|> OmQuery.join(:organization)                   # inner join
|> OmQuery.left_join(:posts)
|> OmQuery.inner_join(:account, as: :acct)
|> OmQuery.joins([{:organization, :left}, {:posts, :inner}])

# Preloads
|> OmQuery.preload([:organization, :posts])
|> OmQuery.preload(:posts, fn q -> OmQuery.filter(q, :published, true) end)
```

---

## Select & Group

```elixir
|> OmQuery.select([:id, :name, :email])
|> OmQuery.select_merge(%{full_name: dynamic([u], u.first_name <> " " <> u.last_name)})
|> OmQuery.group_by([:status])
|> OmQuery.having(count: {:gt, 5})
|> OmQuery.distinct(true)
```

---

## Advanced Operations

```elixir
# CTE (Common Table Expression)
|> OmQuery.with_cte(:recent, recent_query)
|> OmQuery.with_cte(:tree, tree_query, recursive: true)

# Set operations
|> OmQuery.union(other_token)
|> OmQuery.union_all(other_token)
|> OmQuery.intersect(other_token)
|> OmQuery.except(other_token)

# Row locking
|> OmQuery.lock("FOR UPDATE")
|> OmQuery.lock("FOR UPDATE SKIP LOCKED")
|> OmQuery.lock("FOR UPDATE NOWAIT")

# Scopes
|> OmQuery.scope(&active_scope/1)
|> OmQuery.scopes([&active/1, &published/1])

# Conditional pipeline
|> OmQuery.then_if(admin?, fn t -> OmQuery.filter(t, :role, :admin) end)
|> OmQuery.if_true(include_deleted, &OmQuery.only_deleted/1)
```

---

## Execution

```elixir
# Standard execution (returns Result struct)
{:ok, result} = OmQuery.execute(token)
result.data                                      #=> [%User{}, ...]
result.pagination                                #=> %{has_more: true, end_cursor: "..."}
result.metadata                                  #=> %{query_time_us: 1234}

# With options
{:ok, result} = OmQuery.execute(token, repo: MyRepo, include_total: true)

# Shortcuts
users = OmQuery.all(token)                       #=> [%User{}, ...]
user = OmQuery.first(token)                      #=> %User{} | nil
user = OmQuery.one!(token)                       #=> %User{} (raises if 0 or 2+)
count = OmQuery.count(token)                     #=> 42
exists = OmQuery.exists?(token)                  #=> true

# Aggregation
OmQuery.aggregate(token, :sum, :amount)
OmQuery.aggregate(token, :avg, :score)

# Streaming
OmQuery.stream(token, batch_size: 100)           #=> Enumerable
OmQuery.find_in_batches(token, 500, &process_batch/1)
OmQuery.find_each(token, &process_record/1)

# Parallel batch
OmQuery.batch([token1, token2, token3])

# Bulk mutation
OmQuery.update_all(token, set: [status: :archived])
OmQuery.delete_all(token)
```

---

## Debugging

```elixir
|> OmQuery.debug(:raw_sql)                       # print SQL
|> OmQuery.debug(:sql_params)                    # SQL + params
|> OmQuery.debug(:explain)                       # PostgreSQL EXPLAIN
|> OmQuery.debug(:explain_analyze)               # EXPLAIN ANALYZE
|> OmQuery.debug(:token)                         # token internals

{sql, params} = OmQuery.to_sql(token)
query = OmQuery.build(token)                     # Ecto.Query
```

---

## Faceted Search

```elixir
{:ok, result} =
  FacetedSearch.new(Product)
  |> FacetedSearch.search("laptop", [:name, :description])
  |> FacetedSearch.filter(:price, :between, {500, 2000})
  |> FacetedSearch.filter_by(%{in_stock: true})
  |> FacetedSearch.facet(:brand, :brand_id, join: :brand)
  |> FacetedSearch.facet(:price_range, :price,
       ranges: [{0, 500, "Under $500"}, {500, 1000, "$500-$1000"}, {1000, nil, "$1000+"}])
  |> FacetedSearch.facet(:category, :category_id, exclude_from_self: true)
  |> FacetedSearch.order(:relevance, :desc)
  |> FacetedSearch.paginate(:cursor, limit: 20)
  |> FacetedSearch.execute()

result.data                                      #=> [%Product{}, ...]
result.facets                                    #=> %{brand: [...], price_range: [...]}
result.total_count                               #=> 142
```

---

## PostgreSQL MERGE

```elixir
{:ok, {count, records}} =
  User
  |> Merge.new(source_data)
  |> Merge.match_on(:email)
  |> Merge.when_matched(:update, [:name, :updated_at])
  |> Merge.when_matched(&source_newer?/1, :update, [:name])  # conditional
  |> Merge.when_matched(:nothing)                             # fallback
  |> Merge.when_not_matched(:insert)
  |> Merge.returning([:id, :email])
  |> Merge.execute()
```

---

## Cursor Utilities

```elixir
cursor = OmQuery.encode_cursor(record, [:inserted_at, :id])
{:ok, values} = OmQuery.decode_cursor(cursor)
```

---

## Ecto.Multi Integration

```elixir
alias OmQuery.Multi

Ecto.Multi.new()
|> Multi.query(:users, user_token)
|> Multi.query_data(:active, active_token)       # extract .data
|> Multi.query_one(:admin, admin_token)          # first result
|> Multi.transaction()
```

---

## Full Example

```elixir
def list_users(params) do
  User
  |> OmQuery.new()
  |> OmQuery.exclude_deleted()
  |> OmQuery.maybe(:status, params[:status])
  |> OmQuery.maybe(:role, params[:role])
  |> OmQuery.then_if(params[:search], fn t ->
       OmQuery.search(t, params[:search], [:name, :email])
     end)
  |> OmQuery.left_join(:organization)
  |> OmQuery.preload([:organization])
  |> OmQuery.order(:inserted_at, :desc)
  |> OmQuery.paginate(:cursor, limit: params[:limit] || 20, after: params[:cursor])
  |> OmQuery.execute()
end
```
