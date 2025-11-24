# Default Pagination

Guide to the default cursor-based pagination behavior in the query system.

## Overview

**By default, ALL queries use cursor-based pagination with a limit of 20 records.**

This applies to:
✅ Top-level queries built with `DynamicBuilder.build/3`
✅ Nested preload queries at any depth
✅ Search queries with `DynamicBuilder.search/3`

## Why Cursor Pagination by Default?

Cursor-based pagination is the default because it:

✅ **Scales better** - No performance degradation with deep pagination
✅ **More consistent** - Results don't shift when data changes
✅ **Better for APIs** - Standard for modern REST/GraphQL APIs
✅ **Handles real-time data** - Works well with frequently updated data
✅ **Prevents duplicates** - No risk of seeing same record twice when paginating

## Default Behavior

### Simple Query

```elixir
# This automatically gets cursor pagination with limit: 20
spec = %{
  filters: [{:status, :eq, "active"}],
  orders: [{:created_at, :desc}]
}

DynamicBuilder.build(User, spec)

# Equivalent to:
spec = %{
  filters: [{:status, :eq, "active"}],
  orders: [{:created_at, :desc}],
  pagination: {:paginate, :cursor, %{limit: 20, cursor_fields: [:id]}, []}
}
```

### Nested Queries

```elixir
# Each level automatically gets cursor pagination with limit: 20
spec = %{
  filters: [{:status, :eq, "active"}],
  preloads: [
    {:preload, :posts, %{
      filters: [{:published, :eq, true}],
      preloads: [
        {:preload, :comments, %{
          filters: [{:approved, :eq, true}]
          # Automatically gets pagination here too!
        }, []}
      ]
    }, []}
  ]
}

DynamicBuilder.build(User, spec)
```

### Search Queries

```elixir
# Automatically uses cursor pagination
params = %{
  search: "john",
  status: "active"
}

config = %{
  search_fields: [:name, :email],
  filterable_fields: [:status],
  cursor_fields: [:created_at, :id]  # Custom cursor fields
}

DynamicBuilder.search(User, params, config)
```

## Customizing Pagination

### 1. Change Limit

```elixir
# Cursor with different limit
spec = %{
  filters: [{:status, :eq, "active"}],
  pagination: {:paginate, :cursor, %{limit: 50, cursor_fields: [:id]}, []}
}

DynamicBuilder.build(User, spec)
```

### 2. Use Custom Cursor Fields

```elixir
# Better cursor fields for your sort order
spec = %{
  filters: [{:status, :eq, "active"}],
  orders: [{:created_at, :desc}, {:id, :asc}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:created_at, :id]  # Match your sort order!
  }, []}
}

DynamicBuilder.build(User, spec)
```

### 3. Navigate with Cursors

```elixir
# First page
spec = %{
  filters: [{:status, :eq, "active"}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:id]
  }, []}
}

result = DynamicBuilder.build(User, spec) |> Query.execute()

# Get next page
next_cursor = result.pagination.end_cursor

spec = %{
  filters: [{:status, :eq, "active"}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:id],
    after: next_cursor
  }, []}
}

next_result = DynamicBuilder.build(User, spec) |> Query.execute()
```

### 4. Switch to Offset Pagination

```elixir
# Override with offset pagination
spec = %{
  filters: [{:status, :eq, "active"}],
  pagination: {:paginate, :offset, %{limit: 20, offset: 0}, []}
}

DynamicBuilder.build(User, spec)
```

### 5. Disable Pagination

```elixir
# Get all records (use with caution!)
spec = %{
  filters: [{:status, :eq, "active"}]
  # Don't set pagination key - still gets default!
}

# To truly disable pagination, set limit: nil
spec = %{
  filters: [{:status, :eq, "active"}],
  limit: nil  # This will fetch all records
}
```

## Search Helper Behavior

### Default: Cursor Pagination

```elixir
params = %{
  search: "john",
  limit: 30  # Override default 20
}

DynamicBuilder.search(User, params)
# Uses cursor pagination with limit: 30
```

### Force Offset Pagination

```elixir
# Method 1: Use page parameter
params = %{
  search: "john",
  page: 2,
  per_page: 25
}

DynamicBuilder.search(User, params)
# Uses offset pagination because 'page' is present

# Method 2: Set in config
config = %{
  pagination_type: :offset
}

DynamicBuilder.search(User, params, config)
# Uses offset pagination
```

### Cursor Parameters

```elixir
params = %{
  search: "john",
  limit: 20,
  after_cursor: "base64_encoded_cursor"
}

config = %{
  cursor_fields: [:created_at, :id]
}

DynamicBuilder.search(User, params, config)
```

## Best Practices

### 1. Match Cursor Fields to Sort Order

```elixir
# Good - cursor fields match sort order
spec = %{
  orders: [{:created_at, :desc}, {:id, :asc}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:created_at, :id]  # Matches sort!
  }, []}
}

# Bad - mismatched cursor fields
spec = %{
  orders: [{:priority, :desc}, {:created_at, :desc}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:id]  # Doesn't match sort order!
  }, []}
}
```

### 2. Always Include ID in Cursor Fields

```elixir
# Good - includes ID for uniqueness
cursor_fields: [:created_at, :id]
cursor_fields: [:priority, :created_at, :id]

# Risky - no unique field
cursor_fields: [:created_at]  # Multiple records could have same timestamp!
```

### 3. Keep Limits Reasonable

```elixir
# Good limits
limit: 10   # Mobile/card views
limit: 20   # Default
limit: 50   # List views
limit: 100  # Admin interfaces

# Bad limits
limit: 1000  # Too many for cursor pagination
limit: 10000 # Just use offset or streaming
```

### 4. Nested Pagination Limits

```elixir
# Keep nested limits smaller than parent
spec = %{
  pagination: {:paginate, :cursor, %{limit: 20}, []},  # Parent: 20
  preloads: [
    {:preload, :posts, %{
      pagination: {:paginate, :cursor, %{limit: 5}, []}  # Nested: 5
    }, []}
  ]
}
```

### 5. Don't Mix Pagination Types

```elixir
# Good - consistent cursor throughout
spec = %{
  pagination: {:paginate, :cursor, %{limit: 20}, []},
  preloads: [
    {:preload, :posts, %{
      pagination: {:paginate, :cursor, %{limit: 5}, []}
    }, []}
  ]
}

# Avoid - mixing types can be confusing
spec = %{
  pagination: {:paginate, :cursor, %{limit: 20}, []},
  preloads: [
    {:preload, :posts, %{
      pagination: {:paginate, :offset, %{limit: 5, offset: 0}, []}
    }, []}
  ]
}
```

## When to Use Offset Pagination

Despite cursor being the default, offset pagination is better for:

✅ **Known page numbers** - "Go to page 5"
✅ **Page-based UI** - Traditional pagination controls
✅ **Small datasets** - Performance isn't a concern
✅ **Stable data** - Records rarely change
✅ **Reporting** - Fixed page boundaries

```elixir
# Override for these cases
spec = %{
  filters: [{:status, :eq, "active"}],
  pagination: {:paginate, :offset, %{
    limit: 25,
    offset: 50  # Page 3
  }, []}
}
```

## Result Structure

### Cursor Pagination Result

```elixir
%Events.Query.Result{
  data: [...],
  pagination: %{
    type: :cursor,
    limit: 20,
    has_more: true,
    has_previous: false,
    start_cursor: "encoded_start",
    end_cursor: "encoded_end",
    cursor_fields: [:id]
  },
  metadata: %{...}
}
```

### Offset Pagination Result

```elixir
%Events.Query.Result{
  data: [...],
  pagination: %{
    type: :offset,
    limit: 20,
    offset: 0,
    total_count: 150,
    current_page: 1,
    total_pages: 8,
    has_more: true,
    has_previous: false
  },
  metadata: %{...}
}
```

## Examples

### Example 1: Default Behavior

```elixir
# Simplest possible query - gets cursor pagination automatically
spec = %{
  filters: [{:status, :eq, "active"}]
}

result = DynamicBuilder.build(User, spec) |> Query.execute()

# Result has cursor pagination with limit: 20
result.pagination.type  # => :cursor
result.pagination.limit # => 20
```

### Example 2: Paginating Through Results

```elixir
defmodule MyApp.UserQueries do
  def list_active_users(cursor \\ nil) do
    spec = %{
      filters: [{:status, :eq, "active"}],
      orders: [{:created_at, :desc}, {:id, :asc}],
      pagination: build_pagination(cursor)
    }

    DynamicBuilder.build(User, spec) |> Query.execute()
  end

  defp build_pagination(nil) do
    {:paginate, :cursor, %{
      limit: 20,
      cursor_fields: [:created_at, :id]
    }, []}
  end

  defp build_pagination(cursor) do
    {:paginate, :cursor, %{
      limit: 20,
      cursor_fields: [:created_at, :id],
      after: cursor
    }, []}
  end
end

# First page
page1 = MyApp.UserQueries.list_active_users()

# Next page
page2 = MyApp.UserQueries.list_active_users(page1.pagination.end_cursor)
```

### Example 3: Nested with Custom Limits

```elixir
spec = %{
  filters: [{:status, :eq, "active"}],
  # Parent: default 20
  preloads: [
    {:preload, :posts, %{
      filters: [{:published, :eq, true}],
      pagination: {:paginate, :cursor, %{limit: 10}, []},  # Override to 10
      preloads: [
        {:preload, :comments, %{
          filters: [{:approved, :eq, true}],
          pagination: {:paginate, :cursor, %{limit: 3}, []}  # Only 3 comments
        }, []}
      ]
    }, []}
  ]
}

DynamicBuilder.build(User, spec) |> Query.execute()
```

## Summary

✅ **Default: Cursor pagination, limit 20**
✅ **Applies at all nesting levels**
✅ **Override with explicit pagination in spec**
✅ **Match cursor_fields to sort order**
✅ **Include ID in cursor fields for uniqueness**
✅ **Use offset pagination when needed**

The system is designed to give you sensible defaults while remaining fully customizable!

## See Also

- `Events.Query` - Core query API
- `Events.Query.DynamicBuilder` - Dynamic building
- `Events.Query.Result` - Result structure
- `QUERY_SYSTEM.md` - Complete API reference
- `DYNAMIC_BUILDER.md` - Dynamic query guide
