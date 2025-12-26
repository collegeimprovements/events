# OmQuery

Composable query builder for Ecto with cursor pagination, search, and dynamic filters.

## Installation

```elixir
def deps do
  [{:om_query, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
alias OmQuery

# Build and execute queries
User
|> OmQuery.new()
|> OmQuery.filter(:status, :eq, "active")
|> OmQuery.filter(:age, :gte, 18)
|> OmQuery.order(:name, :asc)
|> OmQuery.paginate(:cursor, limit: 20)
|> OmQuery.execute(repo: MyApp.Repo)
```

## Features

### Filtering

```elixir
|> OmQuery.filter(:status, :eq, "active")
|> OmQuery.filter(:age, :gte, 18)
|> OmQuery.filter(:name, :ilike, "john%")
|> OmQuery.filter(:role, :in, ["admin", "moderator"])
|> OmQuery.filter(:deleted_at, :is_nil)
```

### Operators

`:eq`, `:ne`, `:gt`, `:gte`, `:lt`, `:lte`, `:in`, `:not_in`,
`:like`, `:ilike`, `:is_nil`, `:is_not_nil`, `:contains`, `:contained_by`

### Search

```elixir
|> OmQuery.search("john doe", [:name, :email, :bio])
```

### Ordering

```elixir
|> OmQuery.order(:inserted_at, :desc)
|> OmQuery.orders([{:priority, :desc}, {:name, :asc}])
```

### Pagination

```elixir
# Offset pagination
|> OmQuery.paginate(:offset, limit: 20, offset: 40)

# Cursor pagination (recommended for large datasets)
|> OmQuery.paginate(:cursor, limit: 20, after: cursor)
```

### Joins & Preloads

```elixir
|> OmQuery.join(:posts, :inner)
|> OmQuery.preload([:posts, :comments])
```

### Execution

```elixir
# Get results
|> OmQuery.execute(repo: Repo)         # {:ok, %OmQuery.Result{}}
|> OmQuery.all(repo: Repo)             # [%User{}, ...]
|> OmQuery.first(repo: Repo)           # %User{} | nil
|> OmQuery.one(repo: Repo)             # %User{} | nil
|> OmQuery.count(repo: Repo)           # 42
|> OmQuery.exists?(repo: Repo)         # true | false

# Stream for large datasets
|> OmQuery.stream(repo: Repo)
```

### Result

```elixir
{:ok, result} = OmQuery.execute(query, repo: Repo)

result.data           # [%User{}, ...]
result.metadata       # %{cursor: ..., has_more: true}
result.pagination     # %{limit: 20, ...}
```

## Dynamic Queries from Params

```elixir
params = %{
  "filter" => %{"status" => "active", "age_gte" => "18"},
  "sort" => "-inserted_at",
  "page" => %{"limit" => "20", "after" => "cursor123"}
}

User
|> OmQuery.new()
|> OmQuery.from_params(params)
|> OmQuery.execute(repo: Repo)
```

## DSL (Compile-time)

```elixir
defmodule MyApp.UserQuery do
  use OmQuery.DSL

  defquery active_adults do
    filter :status, :eq, "active"
    filter :age, :gte, 18
    order :name, :asc
  end
end

User |> MyApp.UserQuery.active_adults() |> OmQuery.execute(repo: Repo)
```

## License

MIT
