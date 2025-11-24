# Events.CRUD - Enterprise-Grade Database Operations

A comprehensive, composable CRUD system for Elixir applications with 100+ schemas support.

## Table of Contents

- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [API Reference](#api-reference)
- [Advanced Features](#advanced-features)
- [Best Practices](#best-practices)
- [Migration Guide](#migration-guide)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Installation

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:events_crud, "~> 1.0.0"}
  ]
end
```

### Basic Usage

```elixir
# DSL Approach (Recommended)
import Events.CRUD.DSL

result = query User do
  where :status, :eq, "active"
  order :created_at, :desc
  limit 10
end

# Functional Approach
import Events.CRUD.Query

result = User
         |> Events.CRUD.Query.where(:status, :eq, "active")
         |> Events.CRUD.Query.order(:created_at, :desc)
         |> Events.CRUD.Query.limit(10)
         |> Events.CRUD.Query.execute()
```

## Core Concepts

### Token-Based Pipeline

All operations are composed into tokens that flow through a validation → optimization → execution pipeline:

```elixir
token = Events.CRUD.new_token()
        |> Events.CRUD.where(:status, :eq, "active")  # Validation
        |> Events.CRUD.order(:created_at, :desc)     # Optimization
        |> Events.CRUD.limit(10)                      # Execution
```

### Operation Types

| Operation | Purpose | Example |
|-----------|---------|---------|
| `:where` | Filter records | `where :status, :eq, "active"` |
| `:join` | Join tables | `join :posts, :left` |
| `:order` | Sort results | `order :created_at, :desc` |
| `:preload` | Load associations | `preload :posts` |
| `:paginate` | Pagination | `paginate :offset, limit: 20` |
| `:select` | Field selection | `select [:id, :name]` |
| `:group` | Group records | `group [:category_id]` |
| `:having` | Filter groups | `having [count: {:gt, 5}]` |
| `:raw` | Raw SQL | `raw "SELECT * FROM users"` |
| `:debug` | Debug queries | `debug "Check query"` |

### Result Types

All operations return consistent result structures:

```elixir
%Events.CRUD.Result{
  success: true,
  data: [...],           # Query results or record
  error: nil,            # Error message if failed
  metadata: %{           # Rich metadata
    pagination: %{...},
    timing: %{...},
    optimization: %{...},
    query_info: %{...}
  }
}
```

## API Reference

### DSL Macros

#### Query Building

```elixir
query schema do
  # Operations...
end
```

#### Filtering

```elixir
where field, operator, value
where field, operator, value, opts
```

**Operators:**
- Comparison: `:eq`, `:neq`, `:gt`, `:gte`, `:lt`, `:lte`
- Membership: `:in`, `:not_in`
- Pattern: `:like`, `:ilike`
- Range: `:between`
- Null: `:is_nil`, `:not_nil`
- JSON: `:jsonb_contains`, `:jsonb_has_key`

#### Joining

```elixir
# Association joins
join :association, :join_type

# Custom joins with conditions
join Schema, :binding, on: condition, type: :join_type
```

#### Ordering

```elixir
order field, direction
order field, direction, opts
```

#### Preloading

```elixir
# Simple preload
preload :association

# Nested preload with conditions
preload :posts do
  where :published, :eq, true
  order :created_at, :desc
  limit 5
end
```

#### Pagination

```elixir
# Offset pagination
paginate :offset, limit: 20, offset: 40

# Cursor pagination
paginate :cursor, limit: 10, cursor: cursor_value
```

#### Selection

```elixir
select [:field1, :field2]
select %{field: expression}
```

#### Grouping & Aggregation

```elixir
group [:field1, :field2]
having [count: {:gt, 5}]
```

#### Raw SQL

```elixir
raw "SELECT * FROM users WHERE custom_condition"
raw sql, %{param: value}
raw_where "EXTRACT(YEAR FROM date) = :year", %{year: 2024}
```

#### Debugging

```elixir
debug "Label for this debug point"
debug()  # No label
```

### CRUD Operations

```elixir
create Schema, attrs
update record, changes
delete record
get Schema, id
list Schema, do: query_block
```

### Functional API

```elixir
Events.CRUD.Query.from(schema)
|> Events.CRUD.Query.where(field, op, value)
|> Events.CRUD.Query.join(assoc, type)
|> Events.CRUD.Query.order(field, dir)
|> Events.CRUD.Query.limit(count)
|> Events.CRUD.Query.execute()
```

## Advanced Features

### Custom Join Conditions

```elixir
query User do
  # Join posts with custom conditions
  join Post, :published_posts,
       on: published_posts.user_id == user.id and
           published_posts.status == "published" and
           published_posts.published_at <= ^DateTime.utc_now(),
       type: :left

  # Use in select
  select %{
    user_name: :name,
    post_count: count(published_posts.id)
  }
end
```

### Complex Preloading

```elixir
query User do
  preload :posts do
    where :status, :eq, "published"
    order :views, :desc
    limit 5

    preload :comments do
      where :approved, :eq, true
      order :created_at, :desc
      limit 3

      preload :author, select: [:id, :name]
    end
  end
end
```

### Dynamic Query Building

```elixir
def build_user_query(filters, sort, pagination) do
  # Start with base query
  query = Events.CRUD.new_token()

  # Apply dynamic filters
  query = Enum.reduce(filters, query, fn
    {:status, status}, q -> Events.CRUD.where(q, :status, :eq, status)
    {:age_min, min}, q -> Events.CRUD.where(q, :age, :gte, min)
    {:search, term}, q -> Events.CRUD.where(q, :name, :ilike, "%#{term}%")
    _, q -> q
  end)

  # Apply sorting
  query = case sort do
    %{field: field, dir: dir} -> Events.CRUD.order(query, field, dir)
    _ -> Events.CRUD.order(query, :created_at, :desc)
  end

  # Apply pagination
  query = case pagination do
    %{type: :cursor, limit: l, cursor: c} ->
      Events.CRUD.paginate(query, :cursor, limit: l, cursor: c)
    %{type: :offset, page: p, limit: l} ->
      offset = (p - 1) * l
      Events.CRUD.paginate(query, :offset, limit: l, offset: offset)
    _ ->
      Events.CRUD.paginate(query, :offset, limit: 20)
  end

  Events.CRUD.execute(query)
end
```

### Plugin System

Extend the CRUD system with custom operations:

```elixir
defmodule MyCustomOperations do
  @behaviour Events.CRUD.Plugin

  @impl true
  def plugin_info do
    %{
      name: :my_ops,
      operations: [:custom_filter, :advanced_sort],
      hooks: [
        before_execute: &log_query/1,
        after_execute: &log_result/1
      ],
      version: "1.0.0"
    }
  end

  def log_query(token) do
    IO.puts("Executing query with #{length(token.operations)} operations")
    token
  end

  def log_result(result) do
    IO.puts("Query completed in #{result.metadata.timing.total_time}μs")
    result
  end
end

# Register the plugin
Events.CRUD.Plugin.register(MyCustomOperations)
```

## Best Practices

### 1. Choose the Right API

**Use DSL for:**
- Complex, multi-step queries
- Readability is important
- Team prefers declarative style

**Use Functional API for:**
- Dynamic query building
- Programmatic composition
- Integration with existing functional code

### 2. Query Optimization

```elixir
# Good: Selective filtering first
query User do
  where :status, :eq, "active"      # Filter early
  where :created_at, :gte, cutoff   # More filtering
  join :posts, :left                # Join after filtering
  order :name, :asc                 # Order last
end

# Bad: Join before filtering
query User do
  join :posts, :left                # Creates large dataset
  where :status, :eq, "active"      # Filter after join
end
```

### 3. Error Handling

```elixir
case Events.CRUD.execute(token) do
  %Events.CRUD.Result{success: true, data: records} ->
    # Success handling
    process_records(records)

  %Events.CRUD.Result{success: false, error: error} ->
    # Error handling
    case error do
      "Validation failed: " <> reason -> handle_validation_error(reason)
      "Database error: " <> reason -> handle_db_error(reason)
      _ -> handle_unknown_error(error)
    end
end
```

### 4. Pagination Strategy

```elixir
# For user-facing lists: Cursor pagination
paginate :cursor, limit: 20

# For admin interfaces: Offset pagination
paginate :offset, limit: 50, offset: page * 50

# For analytics: No pagination or large limits
# (careful with memory usage)
```

### 5. Preloading Strategy

```elixir
# Preload what you need, when you need it
query User do
  preload :posts do
    # Only preload necessary associations
    preload :category, select: [:id, :name]
    # Don't preload :comments unless needed
  end
end

# Use separate queries for different use cases
def user_with_posts(user_id) do
  query User do
    where :id, :eq, user_id
    preload :posts, limit: 10
  end
end

def user_with_full_profile(user_id) do
  query User do
    where :id, :eq, user_id
    preload :posts do
      preload :comments
      preload :tags
    end
  end
end
```

### 6. Raw SQL Guidelines

```elixir
# Use raw SQL only when necessary
query do
  raw """
  SELECT u.*, COUNT(p.id) as post_count
  FROM users u
  LEFT JOIN posts p ON p.user_id = u.id AND p.status = 'published'
  WHERE u.active = true
  GROUP BY u.id
  HAVING COUNT(p.id) > :min_posts
  ORDER BY post_count DESC
  """,
  %{min_posts: 5}
end

# Prefer Ecto operations when possible
query User do
  where :active, :eq, true
  join :posts, :left
  group [:id]
  having [count: {:gt, 5}]
  order {:count, :desc}
  select %{user: fragment("COUNT(?)", :posts), count: fragment("COUNT(?)", :posts)}
end
```

## Configuration

```elixir
config :events,
  crud_default_limit: 20,         # Default pagination limit
  crud_max_limit: 1000,           # Maximum allowed limit
  crud_timeout: 30_000,           # Query timeout (ms) - 30 seconds
  crud_optimization: true,        # Enable query optimization
  crud_caching: false,            # Enable result caching (disabled by default)
  crud_observability: false,      # Enable monitoring (disabled by default)
  crud_timing: false,             # Enable execution timing (disabled by default)
  crud_opentelemetry: false       # Enable OpenTelemetry (disabled by default)
```

## Migration Guide

### From Ecto.Query

```elixir
# Old way
from(u in User,
  where: u.active == true,
  order_by: [desc: u.created_at],
  limit: 10,
  preload: [:posts]
)

# New way
query User do
  where :active, :eq, true
  order :created_at, :desc
  limit 10
  preload :posts
end
```

### From Repo Operations

```elixir
# Old way
Repo.all(from u in User, where: u.active == true)
Repo.get(User, id)
Repo.insert(changeset)
Repo.update(changeset)
Repo.delete(record)

# New way
list User, do: where :active, :eq, true
get User, id
create User, attrs
update record, changes
delete record
```

## Troubleshooting

### Common Issues

#### 1. Validation Errors
```elixir
# Check field names
where :invalid_field, :eq, "value"  # Error: Field must be atom or join tuple

# Check operator support
where :status, :invalid_op, "active"  # Error: Unsupported operator: invalid_op
```

#### 2. Join Issues
```elixir
# Missing association
join :nonexistent, :left  # Error: Association not found

# Invalid join condition
join Post, :posts, type: :invalid  # Error: Unsupported join type: invalid
```

#### 3. Performance Issues
```elixir
# Debug query execution
query User do
  debug "Before optimization"
  # ... operations ...
  debug "After optimization"
end

# Check execution metadata
case result do
  %Events.CRUD.Result{metadata: %{timing: timing}} ->
    IO.puts("Query took #{timing.total_time}μs")
end
```

### Debug Mode

Enable debug output to inspect queries:

```elixir
query User do
  debug "Initial query"
  where :active, :eq, true
  debug "After filtering"
  join :posts, :left
  debug "After join"
  limit 10
end
```

Output:
```
=== Initial query ===
Ecto Query: #Ecto.Query<from u in User>
Raw SQL: SELECT u."id", u."name" FROM "users" AS u
Parameters: []

=== After filtering ===
Ecto Query: #Ecto.Query<from u in User, where: u.active == ^true>
Raw SQL: SELECT u."id", u."name" FROM "users" AS u WHERE (u."active" = $1)
Parameters: [true]
```

### Monitoring

Enable observability for production monitoring:

```elixir
config :events,
  crud_observability: true,
  crud_timing: true
```

This provides detailed execution metrics and error tracking.

---

## Summary

Events.CRUD provides a comprehensive, enterprise-ready database operations system with:

- **Consistency**: Standardized patterns across all operations
- **Composability**: Easy chaining and combination of operations
- **Performance**: Optimized execution with monitoring
- **Extensibility**: Plugin system for custom operations
- **Safety**: Comprehensive validation and error handling
- **Observability**: Rich debugging and monitoring capabilities

Perfect for applications with 100+ schemas requiring maintainable, performant database operations.