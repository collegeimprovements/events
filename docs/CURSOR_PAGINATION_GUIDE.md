# Cursor Pagination Guide

Complete guide to using cursor-based pagination correctly.

## Critical Rule: Cursor Fields MUST Match Order Fields

⚠️ **The most important rule:** Your `cursor_fields` MUST match your `order` specification for pagination to work correctly.

## Why This Matters

Cursor pagination works by:
1. Encoding values from the last record
2. Using those values to find where to continue
3. Filtering with `WHERE cursor_field > last_value`

**If cursor fields don't match order fields, you WILL get:**
- ❌ Skipped records
- ❌ Duplicate records
- ❌ Inconsistent results
- ❌ Data loss

## The Problem Explained

### Bad Example: Mismatched Fields

```elixir
spec = %{
  filters: [{:status, :eq, "active"}],
  orders: [
    {:priority, :desc},
    {:created_at, :desc}
  ],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:id]  # ❌ WRONG! Doesn't match orders!
  }, []}
}
```

**What happens:**
- Query orders by `priority DESC, created_at DESC, id ASC`
- Cursor encodes only `id` value
- Next page filters `WHERE id > ?` but orders by priority/created_at
- Records get skipped or duplicated!

**Example data showing the problem:**

```
Records in DB:
  id=1, priority=10, created_at=2024-01-01
  id=2, priority=10, created_at=2024-01-02
  id=3, priority=10, created_at=2024-01-03
  id=4, priority=9,  created_at=2024-01-04
  id=5, priority=9,  created_at=2024-01-05

Page 1 (limit 2):
  Returns: id=1, id=2
  Cursor: id=2

Page 2 (WHERE id > 2):
  Gets: id=3,4,5 ordered by priority, created_at
  Returns: id=3, id=4

Page 3 (WHERE id > 4):
  Returns: id=5

Result: All 5 records seen ✓

BUT if we add a new record between pages:
  id=6, priority=10, created_at=2024-01-06

Page 1: Returns id=1, id=2, cursor=2
[New record added: id=6, priority=10, created_at=2024-01-06]
Page 2 (WHERE id > 2):
  Query finds: id=3,4,5,6
  Orders by priority DESC, created_at DESC
  Result: id=6, id=3 (id=6 has higher priority+date!)

Page 3: cursor=3, gets id=4,5
  ❌ LOST: id=6 was shown but never with its proper position
```

### Good Example: Matched Fields

```elixir
spec = %{
  filters: [{:status, :eq, "active"}],
  orders: [
    {:priority, :desc},
    {:created_at, :desc},
    {:id, :asc}
  ],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:priority, :created_at, :id]  # ✅ MATCHES orders!
  }, []}
}
```

**What happens:**
- Query orders by `priority DESC, created_at DESC, id ASC`
- Cursor encodes `(priority, created_at, id)` values
- Next page filters `WHERE (priority, created_at, id) > (?, ?, ?)`
- Pagination is consistent and correct!

## Rules for Cursor Fields

### Rule 1: Match the Order Exactly

```elixir
# ✅ CORRECT
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [:created_at, :id]

# ❌ WRONG - Different fields
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [:priority, :id]

# ❌ WRONG - Different order
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [:id, :created_at]

# ❌ WRONG - Missing fields
orders: [{:priority, :desc}, {:created_at, :desc}, {:id, :asc}]
cursor_fields: [:priority, :id]  # Missing created_at!
```

### Rule 2: Include Unique Field (Usually ID)

```elixir
# ✅ CORRECT - ends with unique ID
cursor_fields: [:created_at, :id]
cursor_fields: [:priority, :created_at, :id]

# ⚠️ RISKY - no unique field
cursor_fields: [:created_at]  # Multiple records can have same timestamp!

# ❌ WRONG - can cause duplicates
cursor_fields: [:status]  # Many records share same status!
```

### Rule 3: Support Direction Notation

```elixir
# Both notations work:

# Notation 1: Atoms (infers from orders)
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [:created_at, :id]

# Notation 2: Tuples (explicit direction)
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [{:created_at, :desc}, {:id, :asc}]
```

## Common Patterns

### Pattern 1: Time-based Pagination

```elixir
spec = %{
  orders: [
    {:created_at, :desc},
    {:id, :asc}
  ],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:created_at, :id]
  }, []}
}
```

**Use case:** Recent items first, ID for uniqueness

### Pattern 2: Priority-based Pagination

```elixir
spec = %{
  orders: [
    {:priority, :desc},
    {:created_at, :desc},
    {:id, :asc}
  ],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:priority, :created_at, :id]
  }, []}
}
```

**Use case:** Task lists, urgent items first

### Pattern 3: Alphabetical Pagination

```elixir
spec = %{
  orders: [
    {:name, :asc},
    {:id, :asc}
  ],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:name, :id]
  }, []}
}
```

**Use case:** Alphabetical lists, directories

### Pattern 4: Score-based Pagination

```elixir
spec = %{
  orders: [
    {:score, :desc},
    {:votes, :desc},
    {:created_at, :desc},
    {:id, :asc}
  ],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:score, :votes, :created_at, :id]
  }, []}
}
```

**Use case:** Ranking systems, leaderboards

## Default Behavior Issue

⚠️ **Current default is NOT safe:**

```elixir
# Default pagination
{:paginate, :cursor, %{limit: 20, cursor_fields: [:id]}, []}

# If you have custom orders, this is WRONG:
spec = %{
  orders: [{:created_at, :desc}]
  # Gets default cursor_fields: [:id] - MISMATCH!
}
```

**Solution:** Always specify cursor_fields when using custom orders:

```elixir
spec = %{
  orders: [{:created_at, :desc}, {:id, :asc}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:created_at, :id]  # MUST MATCH!
  }, []}
}
```

## Nested Queries

Each nesting level needs matching cursor fields:

```elixir
spec = %{
  orders: [{:created_at, :desc}, {:id, :asc}],
  pagination: {:paginate, :cursor, %{
    limit: 20,
    cursor_fields: [:created_at, :id]
  }, []},
  preloads: [
    {:preload, :posts, %{
      orders: [{:published_at, :desc}, {:id, :asc}],
      pagination: {:paginate, :cursor, %{
        limit: 10,
        cursor_fields: [:published_at, :id]  # Match nested orders!
      }, []}
    }, []}
  ]
}
```

## How Cursor Encoding Works

```elixir
# After fetching results
result = Query.execute(token)

# Result contains cursor information
result.pagination.end_cursor
# => "eyJjcmVhdGVkX2F0IjoiMjAyNC0wMS0wMSIsImlkIjoxMH0="

# Decoded (Base64):
# {"created_at": "2024-01-01", "id": 10}

# Next page query uses these values:
# WHERE (created_at, id) > ('2024-01-01', 10)
```

## Troubleshooting

### Symptom: Records appearing twice

**Cause:** Cursor fields don't match order fields

**Fix:**
```elixir
# Before (wrong)
orders: [{:created_at, :desc}]
cursor_fields: [:id]

# After (correct)
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [:created_at, :id]
```

### Symptom: Records getting skipped

**Cause:** Missing fields in cursor_fields

**Fix:**
```elixir
# Before (wrong)
orders: [{:priority, :desc}, {:created_at, :desc}, {:id, :asc}]
cursor_fields: [:priority, :id]  # Missing created_at!

# After (correct)
orders: [{:priority, :desc}, {:created_at, :desc}, {:id, :asc}]
cursor_fields: [:priority, :created_at, :id]
```

### Symptom: Inconsistent page boundaries

**Cause:** No unique field in cursor

**Fix:**
```elixir
# Before (wrong)
orders: [{:created_at, :desc}]
cursor_fields: [:created_at]  # Not unique!

# After (correct)
orders: [{:created_at, :desc}, {:id, :asc}]
cursor_fields: [:created_at, :id]  # ID ensures uniqueness
```

## Best Practices

### 1. Always Match Cursor to Order

```elixir
# Template:
orders: [field1, field2, ..., :id]
cursor_fields: [field1, field2, ..., :id]
```

### 2. Always Include ID

```elixir
# ✅ GOOD
cursor_fields: [:created_at, :id]
cursor_fields: [:priority, :name, :id]

# ❌ BAD
cursor_fields: [:created_at]
cursor_fields: [:name]
```

### 3. Match Direction When Ambiguous

```elixir
# If order has mixed directions, be explicit:
orders: [{:priority, :desc}, {:created_at, :asc}, {:id, :asc}]
cursor_fields: [{:priority, :desc}, {:created_at, :asc}, {:id, :asc}]
```

### 4. Document Your Cursor Strategy

```elixir
defmodule MyApp.PostQueries do
  @doc """
  List posts ordered by publish date (newest first).

  Cursor fields: [:published_at, :id]
  Ensures consistent pagination even with same timestamps.
  """
  def list_recent_posts(cursor \\ nil) do
    %{
      orders: [{:published_at, :desc}, {:id, :asc}],
      pagination: {:paginate, :cursor, %{
        limit: 20,
        cursor_fields: [:published_at, :id],
        after: cursor
      }, []}
    }
    |> then(&DynamicBuilder.build(Post, &1))
    |> Query.execute()
  end
end
```

### 5. Test Your Pagination

```elixir
defmodule MyApp.PostQueriesTest do
  test "pagination doesn't skip or duplicate records" do
    # Create 100 posts
    posts = create_posts(100)

    # Paginate through all
    collected = []
    cursor = nil

    for _ <- 1..10 do
      result = list_recent_posts(cursor)
      collected = collected ++ result.data
      cursor = result.pagination.end_cursor
    end

    # Should have exactly 100 posts, no duplicates
    assert length(collected) == 100
    assert length(Enum.uniq_by(collected, & &1.id)) == 100
  end
end
```

## Summary

✅ **Cursor fields MUST match order fields**
✅ **Always include unique field (ID) at end**
✅ **Match field order exactly**
✅ **Test for skips and duplicates**
✅ **Document your cursor strategy**

**Remember:** Mismatched cursor and order fields will cause data loss and inconsistent results. Always keep them in sync!

## See Also

- `DEFAULT_PAGINATION.md` - Default pagination behavior
- `OmQuery.Builder` - Cursor implementation
- `OmQuery.Result` - Pagination metadata
