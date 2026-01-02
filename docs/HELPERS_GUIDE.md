# Query Helpers Guide

Comprehensive guide to using `OmQuery.Helpers` for more ergonomic query building.

## Setup

```elixir
import OmQuery.Helpers
```

## Date Helpers (return `Date.t()`)

All date helpers return dates in UTC.

| Helper | Returns | Example |
|--------|---------|---------|
| `today()` | Current date | `~D[2024-01-15]` |
| `yesterday()` | Yesterday's date | `~D[2024-01-14]` |
| `tomorrow()` | Tomorrow's date | `~D[2024-01-16]` |
| `last_n_days(n)` | N days ago | `last_n_days(7)` → 7 days ago |
| `last_week()` | 7 days ago | Same as `last_n_days(7)` |
| `last_month()` | 30 days ago | Same as `last_n_days(30)` |
| `last_quarter()` | 90 days ago | Same as `last_n_days(90)` |
| `last_year()` | 365 days ago | Same as `last_n_days(365)` |

### Usage

```elixir
query Post do
  filter :published_date, :gte, last_week()
  filter :created_date, :eq, today()
end
```

## DateTime Helpers (return `DateTime.t()`)

All datetime helpers return UTC timestamps.

| Helper | Returns | Example |
|--------|---------|---------|
| `now()` | Current DateTime | `~U[2024-01-15 14:30:00Z]` |
| `minutes_ago(n)` | N minutes ago | `minutes_ago(30)` → 30 min ago |
| `hours_ago(n)` | N hours ago | `hours_ago(24)` → 24 hours ago |
| `days_ago(n)` | N days ago (DateTime) | `days_ago(7)` → 7 days ago |
| `weeks_ago(n)` | N weeks ago | `weeks_ago(2)` → 14 days ago |

### Usage

```elixir
query User do
  filter :last_login_at, :gte, hours_ago(24)
  filter :updated_at, :gte, days_ago(7)
end
```

## Time Period Helpers

Create precise time boundaries for date ranges.

| Helper | Returns | Example |
|--------|---------|---------|
| `start_of_day(date)` | Midnight (00:00:00) | `~U[2024-01-15 00:00:00Z]` |
| `end_of_day(date)` | Last microsecond | `~U[2024-01-15 23:59:59.999999Z]` |
| `start_of_week()` | Monday 00:00:00 | Current week's Monday |
| `start_of_month()` | 1st day 00:00:00 | Current month's first day |
| `start_of_year()` | Jan 1st 00:00:00 | Current year's first day |

### Usage

```elixir
# Get today's orders
query Order do
  filter :created_at, :gte, start_of_day(today())
  filter :created_at, :lte, end_of_day(today())
end

# Get this week's events
query Event do
  filter :occurred_at, :gte, start_of_week()
end
```

## Query Helpers

### `dynamic_filters/3`

Apply filters dynamically based on user input.

**Signature**: `dynamic_filters(token, params, mapping)`

```elixir
# Define mapping: param_key => {operator, field}
mapping = %{
  status: {:eq, :status},
  min_age: {:gte, :age},
  search: {:ilike, :name}
}

params = %{status: "active", min_age: 18}

Query.new(User)
|> dynamic_filters(params, mapping)
# Applies: WHERE status = 'active' AND age >= 18
```

**Features**:
- Skips `nil` values automatically
- Clean mapping syntax
- Type-safe operations

### `ensure_limit/2`

Ensure query has a limit, applying default if needed.

**Signature**: `ensure_limit(token, default_limit)`

```elixir
Query.new(User)
|> Query.where(:active, :eq, true)
|> ensure_limit(20)
# Adds limit(20) if no limit or pagination exists
# Does nothing if limit/paginate already present
```

**Use case**: API endpoints where you want to guarantee a max result size.

### `sort_by/2`

Parse and apply sorting from string parameters.

**Signature**: `sort_by(token, sort_string)`

**Formats**:
- `"field"` or `"+field"` → ascending
- `"-field"` → descending
- `"field1,-field2,+field3"` → multiple fields

```elixir
Query.new(Post)
|> sort_by("-created_at")
# ORDER BY created_at DESC

Query.new(User)
|> sort_by("name,-created_at,id")
# ORDER BY name ASC, created_at DESC, id ASC
```

**Error handling**: Invalid field names are silently skipped.

### `safe_sort_by/2`

Safe version that returns `{:ok, token}` or `{:error, :invalid_field}`.

```elixir
case safe_sort_by(token, params["sort"]) do
  {:ok, sorted_token} -> sorted_token
  {:error, :invalid_field} -> token  # Use unsorted
end
```

### `paginate_from_params/2`

Apply pagination from request parameters.

**Signature**: `paginate_from_params(token, params)`

**Supported params**:
- `"limit"` - number of results (default: 20)
- `"cursor"` - cursor token (uses cursor pagination)
- `"offset"` - offset value (uses offset pagination)

```elixir
# Cursor pagination
params = %{"limit" => "25", "cursor" => "abc123"}
Query.new(User) |> paginate_from_params(params)

# Offset pagination
params = %{"limit" => "50", "offset" => "100"}
Query.new(User) |> paginate_from_params(params)

# Default (cursor with limit 20)
Query.new(User) |> paginate_from_params(%{})
```

**Priority**: `cursor` > `offset` > default cursor pagination

## Complete Example: API Endpoint

Here's a realistic API endpoint using all helpers:

```elixir
defmodule MyApp.PostController do
  import OmQuery.Helpers
  alias Events.Query

  def index(params) do
    # Define filter mapping
    filter_mapping = %{
      status: {:eq, :status},
      author_id: {:eq, :author_id},
      min_views: {:gte, :view_count},
      search: {:ilike, :title},
      category: {:eq, :category}
    }

    # Build query
    posts =
      Query.new(Post)
      # Static filters
      |> Query.where(:deleted_at, :is_nil, nil)
      |> Query.where(:published_at, :gte, last_month())

      # Dynamic filters from params
      |> dynamic_filters(params, filter_mapping)

      # Sorting (e.g., params["sort"] = "-created_at,title")
      |> sort_by(params["sort"] || "-created_at")

      # Pagination
      |> paginate_from_params(params)

      # Ensure limit
      |> ensure_limit(50)

      # Execute
      |> Repo.execute()

    {:ok, posts}
  end
end
```

**Request examples**:

```
GET /posts?status=published&min_views=100&sort=-views,title&limit=25&cursor=abc

GET /posts?author_id=123&category=tech&sort=title&limit=50&offset=100

GET /posts?search=elixir
```

## Best Practices

### 1. Date vs DateTime Helpers

- Use **Date helpers** (`last_week()`, `today()`) for date-only fields
- Use **DateTime helpers** (`hours_ago()`, `now()`) for timestamp fields

```elixir
# ✅ Good
filter :birth_date, :gte, last_year()           # Date field
filter :created_at, :gte, hours_ago(24)          # DateTime field

# ❌ Bad
filter :birth_date, :gte, days_ago(365)          # DateTime for Date field
filter :created_at, :gte, last_week()            # Date for DateTime field
```

### 2. UTC Timezone

All helpers return UTC values. Convert to user timezone in presentation layer:

```elixir
# Query always in UTC
query Order do
  filter :created_at, :gte, start_of_day(today())
end

# Convert to user timezone when displaying
DateTime.shift_zone(order.created_at, "America/New_York")
```

### 3. Time Ranges

Use period helpers for precise boundaries:

```elixir
# ✅ Good - Exact day range
filter :created_at, :gte, start_of_day(today())
filter :created_at, :lte, end_of_day(today())

# ⚠️ Less precise - Might miss records
filter :created_at, :eq, today()  # Only matches midnight
```

### 4. Dynamic Filtering Patterns

Keep static filters separate from dynamic ones:

```elixir
# ✅ Good structure
Query.new(User)
|> Query.where(:deleted_at, :is_nil, nil)    # Static
|> Query.where(:verified, :eq, true)          # Static
|> dynamic_filters(params, mapping)           # Dynamic
|> sort_by(params["sort"])                    # Dynamic
|> paginate_from_params(params)               # Dynamic
|> ensure_limit(100)                          # Safeguard
```

### 5. Error Handling

Use `safe_sort_by` when accepting untrusted input:

```elixir
# ✅ Good - Safe with fallback
case safe_sort_by(token, params["sort"]) do
  {:ok, sorted} -> sorted
  {:error, :invalid_field} ->
    token |> Query.order_by(:created_at, :desc)
end

# ⚠️ Risky - Might have unexpected behavior
sort_by(token, params["sort"])  # Invalid fields silently ignored
```

## Performance Tips

1. **Index your date/time columns** - Helpers generate time-based filters frequently
2. **Use cursor pagination** - Better performance than offset for large datasets
3. **Limit dynamic filters** - Too many optional filters can complicate query planning
4. **Combine with CTEs** - Use `with_cte` for complex date ranges

```elixir
query Order do
  with_cte :recent_users do
    filter :last_login, :gte, last_week()
  end

  filter :amount, :gt, 100
  filter :created_at, :gte, last_month()
end
```

## Testing with Helpers

Helpers use real-time values, so mock time in tests:

```elixir
# In tests, you may want to work with fixed dates
test "filters recent posts" do
  # Create test data with known dates
  post = insert(:post, published_at: ~U[2024-01-10 00:00:00Z])

  # Query uses real-time helpers
  token = query Post do
    filter :published_at, :gte, last_week()
  end

  results = Repo.execute(token)

  # Assertions depend on current date
  # Consider using libraries like `ExUnit.Callbacks.on_exit/1`
  # or mocking time for deterministic tests
end
```

## Additional Resources

- See `examples/helpers_usage_example.ex` for 15 practical examples
- See `test/events/query/helpers_test.exs` for comprehensive test suite
- See `lib/events/query/helpers.ex` for implementation details

## Summary

The helpers module makes query building more intuitive and maintainable:

- **Date/Time helpers** → Clean, readable time-based filters
- **Query helpers** → Dynamic, user-driven queries without boilerplate
- **Period helpers** → Precise time boundaries
- **Type-safe** → Compile-time safety with runtime flexibility

Import once, use everywhere:

```elixir
import OmQuery.Helpers
```

Happy querying! 🚀
