# Events.Core.Query - Production-Grade Query System

A comprehensive, composable query builder for Elixir/Ecto applications using token pattern, pipelines, and pattern matching.

## Architecture

### Core Components

```
Events.Core.Query (Public API)
    ├── Token (Composable container)
    ├── Builder (Ecto query construction)
    ├── Executor (Query execution with telemetry)
    ├── Result (Structured response)
    ├── DSL (Macro-based interface)
    └── Multi (Transaction support)
```

### Design Patterns

1. **Token Pattern**: Immutable operations list that composes via pipeline
2. **Pattern Matching**: All operations use Elixir pattern matching for validation and execution
3. **Protocol-Based**: Extensible through behaviors
4. **Telemetry**: First-class observability support

## Features

### ✅ Implemented

- [x] Token-based composition
- [x] Comprehensive filtering (eq, neq, gt, gte, lt, lte, in, not_in, like, ilike, is_nil, not_nil, between, contains, jsonb_contains, jsonb_has_key)
- [x] Offset pagination with metadata
- [x] Cursor pagination with metadata
- [x] Joins (inner, left, right, full, cross)
- [x] Nested preloads with filters
- [x] Select, group_by, having
- [x] Distinct, limit, offset, order
- [x] Lock clauses
- [x] CTEs (Common Table Expressions)
- [x] Window functions
- [x] Raw SQL with named placeholders
- [x] Structured Result with rich metadata
- [x] Telemetry integration
- [x] Batch execution
- [x] Streaming support
- [x] Ecto.Multi integration
- [x] Transaction support
- [x] Macro-based DSL
- [x] Pipeline API

## Usage

### Quick Start

```elixir
# Import the DSL
import Events.Core.Query.DSL

# Simple query
query User do
  filter :status, :eq, "active"
  filter :age, :gte, 18
  order :created_at, :desc
  limit 20
end
|> execute()

# Pipeline style
User
|> Events.Core.Query.new()
|> Events.Core.Query.filter(:status, :eq, "active")
|> Events.Core.Query.paginate(:offset, limit: 20, offset: 40)
|> Events.Core.Query.execute()
```

### Filtering

```elixir
query Product do
  # Equality
  filter :status, :eq, "active"

  # Comparisons
  filter :price, :gte, 10.00
  filter :stock, :gt, 0

  # List membership
  filter :category, :in, ["electronics", "gadgets"]

  # Pattern matching
  filter :name, :ilike, "%widget%"

  # Null checks
  filter :deleted_at, :is_nil, nil

  # Range
  filter :price, :between, {10.00, 100.00}

  # JSONB
  filter :metadata, :jsonb_contains, %{featured: true}
end
|> execute()
```

### Pagination

#### Offset Pagination

```elixir
def list_posts(page \\ 1, per_page \\ 20) do
  offset = (page - 1) * per_page

  query Post do
    filter :published, :eq, true
    order :published_at, :desc
    paginate :offset, limit: per_page, offset: offset
  end
  |> execute(include_total_count: true)
end

# Result includes pagination metadata
%Events.Core.Query.Result{
  data: [...],
  pagination: %{
    type: :offset,
    limit: 20,
    offset: 40,
    has_more: true,
    has_previous: true,
    current_page: 3,
    total_pages: 10,
    total_count: 200
  }
}
```

#### Cursor Pagination

```elixir
def list_posts_cursor(after_cursor \\ nil) do
  query Post do
    filter :published, :eq, true
    order :published_at, :desc
    order :id, :desc
    paginate :cursor,
      cursor_fields: [:published_at, :id],
      limit: 20,
      after: after_cursor
  end
  |> execute()
end

# Get next page
def next_page(result) do
  if result.pagination.has_more do
    list_posts_cursor(result.pagination.end_cursor)
  end
end
```

### Joins and Preloads

```elixir
# Simple preload
query User do
  filter :status, :eq, "active"
  preload [:posts, :comments]
end

# Nested preloads with filters
query User do
  preload :posts do
    filter :published, :eq, true
    order :published_at, :desc
    limit 5

    preload :comments do
      filter :approved, :eq, true
    end
  end
end

# Custom joins
query User do
  join :posts, :left, as: :user_posts
  filter :user_posts, :published, :eq, true, binding: :user_posts
end
```

### Aggregations

```elixir
query Order do
  filter :created_at, :gte, ~D[2024-01-01]

  group_by [:status]
  having count: {:gte, 10}

  select %{
    status: :status,
    order_count: fragment("count(*)")
  }
end
```

### CTEs

```elixir
# Define CTE
active_users = query User do
  filter :status, :eq, "active"
  select [:id, :name]
end

# Use CTE
query Order do
  with_cte :active_users, active_users
  # Use the CTE in your query
end
```

### Window Functions

```elixir
query Sale do
  window :running_total,
    partition_by: :product_id,
    order_by: [asc: :sale_date]

  select %{
    sale_id: :id,
    amount: :amount,
    running_total: {:window, :sum, :amount, :running_total}
  }
end
```

### Raw SQL

```elixir
query User do
  raw_where "age BETWEEN :min_age AND :max_age", %{
    min_age: 18,
    max_age: 65
  }

  raw_where "created_at >= :start_date", %{
    start_date: ~N[2024-01-01 00:00:00]
  }
end
```

### Transactions

```elixir
# Simple transaction
Events.Core.Query.transaction(fn ->
  user_result = user_query |> Events.Core.Query.execute()
  post_result = post_query |> Events.Core.Query.execute()
  {:ok, {user_result, post_result}}
end)

# With Ecto.Multi
alias Events.Core.Query.Multi, as: QM

Ecto.Multi.new()
|> QM.query(:users, user_query)
|> QM.query(:posts, post_query)
|> QM.run(:process, fn _repo, %{users: users, posts: posts} ->
  {:ok, %{count: length(users.data) + length(posts.data)}}
end)
|> Events.Core.Repo.transaction()
```

### Batch Execution

```elixir
# Execute multiple queries in parallel
[users_result, posts_result, comments_result] =
  Events.Core.Query.batch([user_query, post_query, comment_query])
```

### Streaming

```elixir
# Stream large result sets
User
|> Events.Core.Query.new()
|> Events.Core.Query.filter(:status, :eq, "active")
|> Events.Core.Query.stream(max_rows: 1000)
|> Enum.each(fn user ->
  # Process each user
end)
```

## Result Structure

All queries return a structured `Result`:

```elixir
%Events.Core.Query.Result{
  data: [...],              # Query results

  pagination: %{
    type: :offset | :cursor | nil,
    limit: 20,
    offset: 0,
    has_more: true,
    has_previous: false,

    # Offset pagination
    current_page: 1,
    total_pages: 5,
    total_count: 100,
    next_offset: 20,
    prev_offset: nil,

    # Cursor pagination
    cursor_fields: [:id],
    start_cursor: "...",
    end_cursor: "...",
    after_cursor: nil,
    before_cursor: nil
  },

  metadata: %{
    query_time_μs: 1234,    # Query execution time
    total_time_μs: 1500,    # Total time including processing
    cached: false,
    sql: "SELECT ...",      # Generated SQL
    operation_count: 5,     # Number of operations in token
    optimizations_applied: []
  }
}
```

## Telemetry

The system emits telemetry events for monitoring:

```elixir
[:events, :query, :start]      # When query starts
[:events, :query, :stop]       # When query completes
[:events, :query, :exception]  # When query fails
```

Attach handlers:

```elixir
:telemetry.attach(
  "query-logger",
  [:events, :query, :stop],
  fn event, measurements, metadata, _config ->
    IO.puts("Query completed in #{measurements.duration}μs")
  end,
  nil
)
```

## Advanced Patterns

### Dynamic Filter Building

```elixir
def search_products(filters) do
  base = Events.Core.Query.new(Product)

  final_token =
    Enum.reduce(filters, base, fn
      {:category, cat}, token ->
        Events.Core.Query.filter(token, :category, :eq, cat)
      {:min_price, price}, token ->
        Events.Core.Query.filter(token, :price, :gte, price)
      _, token ->
        token
    end)

  Events.Core.Query.execute(final_token)
end
```

### Building Without Executing

```elixir
# Get the Ecto.Query
token = Events.Core.Query.new(User)
        |> Events.Core.Query.filter(:status, :eq, "active")

ecto_query = Events.Core.Query.build(token)

# Inspect or modify
IO.inspect(ecto_query)

# Execute manually
Events.Core.Repo.all(ecto_query)
```

## Configuration

Execute options:

```elixir
Events.Core.Query.execute(token,
  repo: Events.Core.Repo,              # Repo module
  timeout: 30_000,                # Query timeout (ms)
  telemetry: true,                # Enable telemetry
  include_total_count: true,      # Include total count (pagination)
  max_rows: 500                   # Streaming max rows
)
```

## Best Practices

1. **Use cursor pagination** for user-facing infinite scroll
2. **Use offset pagination** for admin interfaces with page numbers
3. **Include total_count sparingly** - it adds an extra COUNT query
4. **Batch related queries** to execute in parallel
5. **Use transactions** for operations that must succeed or fail together
6. **Stream large datasets** instead of loading everything into memory
7. **Use CTEs** for complex queries with repeated subqueries
8. **Monitor with telemetry** in production

## Performance Tips

- Filter before joining when possible
- Use indices on commonly filtered fields
- Limit preload depth to avoid N+1 queries
- Consider pagination for large result sets
- Use select to load only needed fields
- Use streaming for processing large datasets

## See Also

- `Events.Core.Query.Examples` - Comprehensive examples
- `Events.Core.Query.Token` - Token structure and operations
- `Events.Core.Query.Result` - Result structure
- `Events.Core.Query.Multi` - Transaction helpers
