# Flexible Format Support

Complete guide to all the flexible input formats supported by the query system.

## Overview

The query system supports **maximum flexibility** in how you specify filters, orders, joins, and preloads. All formats are **completely interchangeable** and normalize to a consistent internal representation.

✅ **Tuple formats** - 3, 4, and 5-tuple variations
✅ **Keyword lists** - With `filter:`, `order:`, `order_by:` keys
✅ **Mixed formats** - Use different formats in the same spec
✅ **Nested specs** - All formats work at any nesting level

## Filter Formats

### All Equivalent Filter Formats

**Every one of these is valid and equivalent:**

```elixir
# Format 1: Full 5-tuple with tag
{:filter, :status, :eq, "active", []}

# Format 2: 4-tuple without tag
{:status, :eq, "active", []}

# Format 3: 3-tuple without tag
{:status, :eq, "active"}

# Format 4: Keyword list with filter: key and 4-tuple
[filter: {:status, :eq, "active", []}]

# Format 5: Keyword list with filter: key and 3-tuple
[filter: {:status, :eq, "active"}]
```

### In Practice

```elixir
# All these specs are IDENTICAL after normalization
spec1 = %{
  filters: [{:filter, :status, :eq, "active", []}]
}

spec2 = %{
  filters: [{:status, :eq, "active", []}]
}

spec3 = %{
  filters: [{:status, :eq, "active"}]
}

spec4 = %{
  filters: [[filter: {:status, :eq, "active", []}]]
}

spec5 = %{
  filters: [[filter: {:status, :eq, "active"}]]
}

# All produce the exact same query
DynamicBuilder.build(User, spec1)
DynamicBuilder.build(User, spec2)
DynamicBuilder.build(User, spec3)
DynamicBuilder.build(User, spec4)
DynamicBuilder.build(User, spec5)
```

### Multiple Filters - Mix and Match

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, "active", []},      # Format 1
    {:age, :gte, 18, []},                       # Format 2
    {:verified, :eq, true},                     # Format 3
    [filter: {:role, :in, ["admin"]}],          # Format 5
    [filter: {:country, :eq, "US", []}]         # Format 4
  ]
}

# All filters work together seamlessly!
token = DynamicBuilder.build(User, spec)
```

### Filter Format Table

| Format | Example | Options | Notes |
|--------|---------|---------|-------|
| 5-tuple | `{:filter, :status, :eq, "active", []}` | Yes | Explicit, verbose |
| 4-tuple | `{:status, :eq, "active", []}` | Yes | Most balanced |
| 3-tuple | `{:status, :eq, "active"}` | No | Shortest, no options |
| Keyword 4-tuple | `[filter: {:status, :eq, "active", []}]` | Yes | Self-documenting |
| Keyword 3-tuple | `[filter: {:status, :eq, "active"}]` | No | Self-documenting |

## Order Formats

### All Equivalent Order Formats

**Every one of these is valid and equivalent:**

```elixir
# Format 1: Full 4-tuple with tag
{:order, :created_at, :desc, []}

# Format 2: 3-tuple without tag
{:created_at, :desc, []}

# Format 3: 2-tuple without tag
{:created_at, :desc}

# Format 4: Keyword list with order: key and 3-tuple
[order: {:created_at, :desc, []}]

# Format 5: Keyword list with order: key and 2-tuple
[order: {:created_at, :desc}]

# Format 6: Keyword list with order_by: key and 3-tuple
[order_by: {:created_at, :desc, []}]

# Format 7: Keyword list with order_by: key and 2-tuple
[order_by: {:created_at, :desc}]

# Format 8: Single atom (defaults to :asc)
:created_at
```

### In Practice

```elixir
# All these specs are IDENTICAL after normalization
spec1 = %{
  orders: [{:order, :created_at, :desc, []}]
}

spec2 = %{
  orders: [{:created_at, :desc, []}]
}

spec3 = %{
  orders: [{:created_at, :desc}]
}

spec4 = %{
  orders: [[order: {:created_at, :desc}]]
}

spec5 = %{
  orders: [[order_by: {:created_at, :desc}]]
}

# All produce the exact same query
DynamicBuilder.build(User, spec1)
DynamicBuilder.build(User, spec2)
DynamicBuilder.build(User, spec3)
DynamicBuilder.build(User, spec4)
DynamicBuilder.build(User, spec5)
```

### Multiple Orders - Mix and Match

```elixir
spec = %{
  orders: [
    {:order, :priority, :desc, []},             # Format 1
    {:created_at, :desc, []},                   # Format 2
    {:name, :asc},                              # Format 3
    :id,                                        # Format 8 (defaults to :asc)
    [order: {:score, :desc}],                   # Format 5
    [order_by: {:rating, :desc}]                # Format 7
  ]
}

# All orders work together seamlessly!
token = DynamicBuilder.build(User, spec)
```

### Order Format Table

| Format | Example | Options | Direction | Notes |
|--------|---------|---------|-----------|-------|
| 4-tuple | `{:order, :created_at, :desc, []}` | Yes | Explicit | Full control |
| 3-tuple | `{:created_at, :desc, []}` | Yes | Explicit | Most balanced |
| 2-tuple | `{:created_at, :desc}` | No | Explicit | Clean, simple |
| Atom | `:created_at` | No | :asc | Shortest |
| Keyword order: | `[order: {:created_at, :desc}]` | Varies | Explicit | Self-documenting |
| Keyword order_by: | `[order_by: {:created_at, :desc}]` | Varies | Explicit | Alternative key |

## Real-World Examples

### Example 1: E-commerce Product Search

```elixir
def search_products(params) do
  spec = %{
    # Mix filter formats freely
    filters: [
      {:status, :eq, "active"},                           # 3-tuple
      {:price, :gte, params[:min_price] || 0, []},        # 4-tuple
      [filter: {:category_id, :in, params[:categories]}], # Keyword
      {:in_stock, :eq, true}                              # 3-tuple
    ],
    # Mix order formats freely
    orders: [
      {:featured, :desc},                                 # 2-tuple
      [order_by: {:rating, :desc}],                       # Keyword with order_by:
      :id                                                 # Atom (defaults :asc)
    ],
    pagination: {:paginate, :offset, %{
      limit: params[:per_page] || 20,
      offset: params[:offset] || 0
    }, []}
  }

  DynamicBuilder.build(Product, spec, params)
end
```

### Example 2: Blog Search with Nested Comments

```elixir
def search_posts(params) do
  spec = %{
    filters: [
      {:status, :in, ["published", "featured"]},
      [filter: {:author_id, :eq, params[:author_id]}]
    ],
    orders: [
      [order: {:featured, :desc}],
      {:published_at, :desc},
      :id
    ],
    preloads: [
      {:preload, :comments, %{
        # Nested specs also support all formats!
        filters: [
          {:status, :eq, "approved"},
          [filter: {:deleted_at, :is_nil, nil}]
        ],
        orders: [
          [order_by: {:likes_count, :desc}],
          {:created_at, :desc}
        ],
        pagination: {:paginate, :offset, %{limit: 10}, []}
      }, []}
    ]
  }

  DynamicBuilder.build(Post, spec, params)
end
```

### Example 3: Deep Nesting with All Formats

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, "active", []},              # 5-tuple
    {:age, :gte, 18}                                    # 3-tuple
  ],
  orders: [
    {:order, :priority, :desc, []},                     # 4-tuple
    [order: {:created_at, :desc}]                       # Keyword
  ],
  preloads: [
    {:preload, :posts, %{
      filters: [
        {:published, :eq, true},                        # 3-tuple
        [filter: {:featured, :eq, true, []}]            # Keyword with 4-tuple
      ],
      orders: [
        {:views, :desc},                                # 2-tuple
        [order_by: {:created_at, :desc}],               # Keyword with order_by:
        :id                                             # Atom
      ],
      preloads: [
        {:preload, :comments, %{
          filters: [
            [filter: {:approved, :eq, true}],           # Keyword
            {:spam, :eq, false}                         # 3-tuple
          ],
          orders: [
            [order: {:helpful_count, :desc, []}],       # Keyword with 3-tuple
            {:created_at, :asc}                         # 2-tuple
          ]
        }, []}
      ]
    }, []}
  ]
}

# Works at ALL nesting levels!
DynamicBuilder.build(User, spec)
```

## Why Multiple Formats?

### Different Use Cases

**5-tuple / 4-tuple with options**: When you need filter options
```elixir
{:email, :ilike, "%@example.com", [case_insensitive: true]}
```

**3-tuple / 2-tuple**: When you don't need options (most common)
```elixir
{:status, :eq, "active"}
{:created_at, :desc}
```

**Keyword lists**: When self-documenting code matters
```elixir
[filter: {:status, :eq, "active"}]
[order_by: {:created_at, :desc}]
```

**Atoms**: For simple ascending sorts
```elixir
:name  # Equivalent to {:order, :name, :asc, []}
```

### Readability vs Brevity

```elixir
# Maximum clarity (verbose)
%{
  filters: [{:filter, :status, :eq, "active", []}],
  orders: [{:order, :created_at, :desc, []}]
}

# Balanced (recommended for most cases)
%{
  filters: [{:status, :eq, "active"}],
  orders: [{:created_at, :desc}]
}

# Maximum brevity
%{
  filters: [{:status, :eq, "active"}],
  orders: [:created_at]  # defaults to :asc
}
```

## Migration Guide

### From Old Format to New

If you have existing code using only one format, you can freely mix in others:

```elixir
# Old code (still works!)
spec = %{
  filters: [
    {:filter, :status, :eq, "active", []},
    {:filter, :age, :gte, 18, []}
  ]
}

# New code (shorter, same result)
spec = %{
  filters: [
    {:status, :eq, "active"},
    {:age, :gte, 18}
  ]
}

# Or mix them!
spec = %{
  filters: [
    {:status, :eq, "active"},                    # 3-tuple
    {:filter, :email, :ilike, "%@ex.com", opts}  # 5-tuple with options
  ]
}
```

### From Ecto.Query to DynamicBuilder

```elixir
# Ecto.Query
from u in User,
  where: u.status == "active",
  where: u.age >= 18,
  order_by: [desc: u.created_at, asc: u.id]

# DynamicBuilder (closest to Ecto syntax)
%{
  filters: [
    {:status, :eq, "active"},
    {:age, :gte, 18}
  ],
  orders: [
    {:created_at, :desc},
    {:id, :asc}
  ]
}
|> then(&DynamicBuilder.build(User, &1))
```

## Best Practices

### 1. Be Consistent Within a Module

```elixir
defmodule MyApp.ProductQueries do
  # Pick one style and stick to it in this module

  def active_products do
    %{
      filters: [{:status, :eq, "active"}],      # 3-tuple
      orders: [{:created_at, :desc}]            # 2-tuple
    }
  end

  def featured_products do
    %{
      filters: [{:featured, :eq, true}],        # 3-tuple (consistent!)
      orders: [{:priority, :desc}]              # 2-tuple (consistent!)
    }
  end
end
```

### 2. Use Options When Needed

```elixir
# Without options: Use shorter format
{:status, :eq, "active"}

# With options: Use full format
{:email, :ilike, "%@example.com", [case_insensitive: true]}
{:published, :eq, true, [binding: :posts]}
```

### 3. Self-Document Complex Queries

```elixir
# For complex queries, keyword format adds clarity
%{
  filters: [
    [filter: {:status, :eq, "active"}],           # Clear intent
    [filter: {:deleted_at, :is_nil, nil}],        # What are we checking?
    [filter: {:verified, :eq, true}]              # More readable
  ],
  orders: [
    [order_by: {:priority, :desc}],               # Sort by priority first
    [order_by: {:created_at, :desc}],             # Then by creation date
    [order_by: {:id, :asc}]                       # Finally by ID
  ]
}
```

### 4. Atom Orders for Simple Sorts

```elixir
# Simple ascending sorts
%{
  orders: [:name, :email, :id]  # All default to :asc
}

# Much cleaner than:
%{
  orders: [
    {:order, :name, :asc, []},
    {:order, :email, :asc, []},
    {:order, :id, :asc, []}
  ]
}
```

## Normalization

All formats normalize to a consistent internal representation:

```elixir
# Input (any format)
filters: [
  {:status, :eq, "active"},
  [filter: {:age, :gte, 18}],
  {:filter, :verified, :eq, true, []}
]

# After normalization (internal)
[
  {:filter, :status, :eq, "active", []},
  {:filter, :age, :gte, 18, []},
  {:filter, :verified, :eq, true, []}
]
```

You can call `normalize_spec/2` directly to see the result:

```elixir
DynamicBuilder.normalize_spec([{:status, :eq, "active"}], :filter)
# => [{:filter, :status, :eq, "active", []}]

DynamicBuilder.normalize_spec([{:created_at, :desc}], :order)
# => [{:order, :created_at, :desc, []}]

DynamicBuilder.normalize_spec([:name, :id], :order)
# => [{:order, :name, :asc, []}, {:order, :id, :asc, []}]
```

## Summary

✅ **All filter formats are equivalent**
✅ **All order formats are equivalent**
✅ **Mix and match freely**
✅ **Works at any nesting level**
✅ **Use what's most readable for your use case**

The query system is designed to meet you where you are - use the format that makes the most sense for your specific situation!

## See Also

- `DYNAMIC_BUILDER.md` - Dynamic query building guide
- `Events.Query.DynamicBuilder` - Implementation details
- `test/events/query/dynamic_builder_formats_test.exs` - Format equivalence tests
- `LISTING_QUERIES.md` - List-based API guide
