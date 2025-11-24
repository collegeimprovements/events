## Dynamic Query Building

Complete guide to building queries dynamically with parameter interpolation and consistent tuple formats.

## Overview

The `Events.Query.DynamicBuilder` module provides a powerful way to build queries from data structures, enabling:

✅ **Consistent 4-tuple format** for all operations
✅ **Parameter interpolation** with `{:param, key}` syntax
✅ **Nested query specifications** with independent pagination
✅ **Format normalization** from various input formats
✅ **Dynamic search helpers** for common patterns
✅ **Full composability** with the core Query API

## Core Concept: Query Specifications

A query specification is a map describing the complete query structure:

```elixir
spec = %{
  filters: [filter_spec, ...],
  orders: [order_spec, ...],
  joins: [join_spec, ...],
  preloads: [preload_spec, ...],
  select: fields,
  group_by: fields,
  having: conditions,
  distinct: value,
  limit: integer,
  offset: integer,
  pagination: paginate_spec
}
```

## Consistent 4-Tuple Format

ALL operations use 4-element tuples for maximum consistency:

### Filter Specification

```elixir
{:filter, field, operation, value, options}

# Examples
{:filter, :status, :eq, "active", []}
{:filter, :email, :ilike, "%@example.com", [case_insensitive: true]}
{:filter, :age, :gte, 18, []}
{:filter, :published, :eq, true, [binding: :posts]}
```

### Order Specification

```elixir
{:order, field, direction, options}

# Examples
{:order, :created_at, :desc, []}
{:order, :name, :asc, []}
{:order, :title, :asc, [binding: :posts]}
{:order, :priority, :desc, [nulls: :last]}
```

### Preload Specification

```elixir
{:preload, association, query_spec | nil, options}

# Examples
{:preload, :posts, nil, []}  # Simple preload

{:preload, :posts, %{        # Nested with filters
  filters: [{:filter, :published, :eq, true, []}],
  orders: [{:order, :created_at, :desc, []}],
  pagination: {:paginate, :offset, %{limit: 10}, []}
}, []}
```

### Join Specification

```elixir
{:join, association, type, options}

# Examples
{:join, :posts, :inner, []}
{:join, :comments, :left, [as: :post_comments]}
{:join, Category, :inner, [on: [category_id: :id]]}
```

### Pagination Specification

```elixir
{:paginate, type, config, options}

# Examples
{:paginate, :offset, %{limit: 20, offset: 0}, []}
{:paginate, :cursor, %{limit: 25, cursor_fields: [:created_at, :id]}, []}
```

## Parameter Interpolation

Use `{:param, key}` to reference values from the params map:

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, {:param, :status}, []},
    {:filter, :age, :gte, {:param, :min_age}, []},
    {:filter, :role, :in, {:param, :roles}, []}
  ]
}

params = %{
  status: "active",
  min_age: 18,
  roles: ["admin", "editor"]
}

token = DynamicBuilder.build(User, spec, params)
```

Parameters are resolved when building the query, allowing for:
- Dynamic value injection
- Safe parameterization
- Reusable specifications
- Multi-tenant queries

## Building Queries

### Basic Building

```elixir
alias Events.Query.DynamicBuilder

spec = %{
  filters: [
    {:filter, :status, :eq, "active", []},
    {:filter, :age, :gte, 18, []}
  ],
  orders: [
    {:order, :created_at, :desc, []}
  ],
  pagination: {:paginate, :offset, %{limit: 20}, []}
}

token = DynamicBuilder.build(User, spec)
result = Query.execute(token)
```

### With Parameters

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, {:param, :status}, []},
    {:filter, :category, :in, {:param, :categories}, []},
    {:filter, :price, :gte, {:param, :min_price}, []}
  ],
  orders: [
    {:order, :created_at, :desc, []}
  ],
  pagination: {:paginate, :offset, %{
    limit: {:param, :per_page},
    offset: {:param, :offset}
  }, []}
}

params = %{
  status: "active",
  categories: ["electronics", "gadgets"],
  min_price: 10.0,
  per_page: 25,
  offset: 0
}

token = DynamicBuilder.build(Product, spec, params)
```

### Nested Specifications

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, "active", []}
  ],
  preloads: [
    {:preload, :posts, %{
      filters: [
        {:filter, :published, :eq, true, []},
        {:filter, :created_at, :gte, {:param, :since}, []}
      ],
      orders: [
        {:order, :created_at, :desc, []}
      ],
      pagination: {:paginate, :offset, %{limit: 10}, []},
      preloads: [
        {:preload, :comments, %{
          filters: [
            {:filter, :approved, :eq, true, []}
          ],
          orders: [
            {:order, :created_at, :desc, []}
          ],
          pagination: {:paginate, :offset, %{limit: 5}, []}
        }, []}
      ]
    }, []}
  ]
}

token = DynamicBuilder.build(User, spec, %{since: ~D[2024-01-01]})
```

## Format Normalization

The builder accepts multiple input formats and normalizes them to 4-tuples:

```elixir
# 3-tuple filters → 4-tuple
DynamicBuilder.normalize_spec([
  {:status, :eq, "active"},
  {:age, :gte, 18}
], :filter)
# =>
[
  {:filter, :status, :eq, "active", []},
  {:filter, :age, :gte, 18, []}
]

# 2-tuple orders → 4-tuple
DynamicBuilder.normalize_spec([
  {:created_at, :desc},
  {:name, :asc}
], :order)
# =>
[
  {:order, :created_at, :desc, []},
  {:order, :name, :asc, []}
]

# Atom orders → 4-tuple (defaults to :asc)
DynamicBuilder.normalize_spec([:name, :email], :order)
# =>
[
  {:order, :name, :asc, []},
  {:order, :email, :asc, []}
]
```

## Dynamic Search Helper

For common search patterns, use the `search/3` function:

```elixir
params = %{
  search: "john",
  status: "active",
  role: "admin",
  sort_by: "created_at",
  sort_dir: "desc",
  page: 1,
  per_page: 20
}

config = %{
  search_fields: [:name, :email, :bio],
  filterable_fields: [:status, :role, :verified],
  sortable_fields: [:name, :created_at, :updated_at],
  default_sort: {:created_at, :desc},
  default_per_page: 25
}

token = DynamicBuilder.search(User, params, config)
```

The search helper automatically:
- Builds search filters from `params[:search]`
- Applies filterable field values
- Handles sorting with validation
- Sets up pagination
- Provides sensible defaults

## Real-World Examples

### Example 1: E-commerce Product Listing

```elixir
def list_products(params) do
  base_filters = [{:filter, :status, :eq, "active", []}]

  filters = base_filters
    |> maybe_add_filter(:category_id, :eq, params[:category])
    |> maybe_add_filter(:price, :gte, params[:min_price])
    |> maybe_add_filter(:price, :lte, params[:max_price])
    |> maybe_add_filter(:in_stock, :eq, true, params[:only_in_stock])
    |> maybe_add_search(:name, params[:search])

  orders = case params[:sort_by] do
    "price_asc" -> [{:order, :price, :asc, []}, {:order, :id, :asc, []}]
    "price_desc" -> [{:order, :price, :desc, []}, {:order, :id, :asc, []}]
    "popular" -> [{:order, :sales_count, :desc, []}, {:order, :id, :asc, []}]
    _ -> [{:order, :created_at, :desc, []}, {:order, :id, :asc, []}]
  end

  spec = %{
    filters: filters,
    orders: orders,
    pagination: {:paginate, :offset, %{
      limit: params[:per_page] || 20,
      offset: ((params[:page] || 1) - 1) * (params[:per_page] || 20)
    }, []},
    preloads: [
      {:preload, :category, nil, []},
      {:preload, :reviews, %{
        filters: [{:filter, :status, :eq, "approved", []}],
        orders: [{:order, :helpful_count, :desc, []}],
        pagination: {:paginate, :offset, %{limit: 5}, []}
      }, []}
    ]
  }

  DynamicBuilder.build(Product, spec, params)
end

defp maybe_add_filter(filters, _field, _op, nil), do: filters
defp maybe_add_filter(filters, _field, _op, _value, false), do: filters
defp maybe_add_filter(filters, field, op, value, _truthy) do
  filters ++ [{:filter, field, op, value, []}]
end

defp maybe_add_search(filters, _field, nil), do: filters
defp maybe_add_search(filters, field, term) do
  filters ++ [{:filter, field, :ilike, "%#{term}%", []}]
end
```

### Example 2: Blog Post Search with Nested Comments

```elixir
def search_posts(params) do
  spec = %{
    filters: [
      {:filter, :status, :in, ["published", "featured"], []},
      {:filter, :published_at, :lte, {:param, :before_date}, []},
      {:filter, :published_at, :gte, {:param, :after_date}, []}
    ] ++ optional_filters(params),
    orders: [
      {:order, :featured, :desc, []},
      {:order, :published_at, :desc, []},
      {:order, :id, :asc, []}
    ],
    pagination: {:paginate, :cursor, %{
      limit: params[:limit] || 25,
      cursor_fields: [:published_at, :id],
      after: params[:after_cursor]
    }, []},
    preloads: [
      {:preload, :author, nil, []},
      {:preload, :comments, %{
        filters: [
          {:filter, :status, :eq, "approved", []},
          {:filter, :parent_id, :is_nil, nil, []}
        ],
        orders: [
          {:order, :likes_count, :desc, []},
          {:order, :created_at, :desc, []}
        ],
        pagination: {:paginate, :offset, %{limit: 10}, []},
        preloads: [
          {:preload, :author, nil, []},
          {:preload, :replies, %{
            filters: [{:filter, :status, :eq, "approved", []}],
            orders: [{:order, :created_at, :asc, []}],
            pagination: {:paginate, :offset, %{limit: 5}, []}
          }, []}
        ]
      }, []}
    ]
  }

  DynamicBuilder.build(Post, spec, params)
end

defp optional_filters(params) do
  []
  |> maybe_add_param_filter(:category_id, :eq, params[:category_id])
  |> maybe_add_param_filter(:author_id, :eq, params[:author_id])
  |> maybe_add_param_filter(:title, :ilike, search_pattern(params[:search]))
  |> maybe_add_param_filter(:tags, :contains, params[:tags])
end

defp maybe_add_param_filter(filters, _field, _op, nil), do: filters
defp maybe_add_param_filter(filters, field, op, value) do
  filters ++ [{:filter, field, op, {:param, field}, []}]
end

defp search_pattern(nil), do: nil
defp search_pattern(term), do: "%#{term}%"
```

### Example 3: Multi-tenant Query

```elixir
def list_tenant_resources(tenant_id, resource_type, params) do
  spec = %{
    filters: [
      {:filter, :tenant_id, :eq, tenant_id, []},
      {:filter, :resource_type, :eq, resource_type, []},
      {:filter, :deleted_at, :is_nil, nil, []}
    ] ++ dynamic_filters(params),
    orders: build_orders(params),
    pagination: {:paginate, :offset, %{
      limit: params[:limit] || 50,
      offset: params[:offset] || 0
    }, []}
  }

  DynamicBuilder.build(Resource, spec, params)
end
```

## Syntax Conversion

Convert between pipeline and DSL syntax:

```elixir
alias Events.Query.SyntaxConverter

# Token to DSL
token = User
  |> Query.new()
  |> Query.filter(:status, :eq, "active")
  |> Query.order(:name, :asc)

dsl_code = SyntaxConverter.token_to_dsl(token, User)
IO.puts(dsl_code)
# =>
# query User do
#   filter(:status, :eq, "active")
#   order(:name, :asc)
# end

# Token to Pipeline
pipeline_code = SyntaxConverter.token_to_pipeline(token, User)
IO.puts(pipeline_code)
# =>
# User
# |> Query.new()
# |> Query.filter(:status, :eq, "active")
# |> Query.order(:name, :asc)

# Spec to DSL
spec = %{
  filters: [{:filter, :status, :eq, "active", []}],
  orders: [{:order, :name, :asc, []}]
}

dsl_code = SyntaxConverter.spec_to_dsl(spec, User)

# Spec to Pipeline
pipeline_code = SyntaxConverter.spec_to_pipeline(spec, User)
```

## Performance Considerations

### Filter Order

Place most selective filters first:

```elixir
# Good - tenant_id is highly selective
filters: [
  {:filter, :tenant_id, :eq, tenant_id, []},
  {:filter, :status, :eq, "active", []},
  {:filter, :created_at, :gte, date, []}
]

# Less optimal
filters: [
  {:filter, :created_at, :gte, date, []},
  {:filter, :status, :eq, "active", []},
  {:filter, :tenant_id, :eq, tenant_id, []}
]
```

### Pagination Depth

Limit nesting depth and pagination sizes:

```elixir
# Reasonable nesting
preloads: [
  {:preload, :posts, %{
    pagination: {:paginate, :offset, %{limit: 10}, []},  # Top-level: 10
    preloads: [
      {:preload, :comments, %{
        pagination: {:paginate, :offset, %{limit: 5}, []}  # Nested: 5
      }, []}
    ]
  }, []}
]
```

### Selective Preloading

Only preload what you need:

```elixir
# Good - selective preloading
preloads: [
  {:preload, :author, %{select: [:id, :name, :avatar_url]}, []},
  {:preload, :tags, nil, []}
]

# Less optimal - loading entire associations
preloads: [
  {:preload, :author, nil, []},
  {:preload, :tags, nil, []},
  {:preload, :categories, nil, []},
  {:preload, :metadata, nil, []}
]
```

## Best Practices

### 1. Always Use 4-Tuples in Specs

```elixir
# Good
{:filter, :status, :eq, "active", []}
{:order, :name, :asc, []}

# Avoid - will need normalization
{:status, :eq, "active"}
{:name, :asc}
```

### 2. Separate Base and Dynamic Filters

```elixir
def build_filters(params) do
  base = [
    {:filter, :deleted_at, :is_nil, nil, []},
    {:filter, :status, :eq, "active", []}
  ]

  base
  |> add_optional_filters(params)
  |> add_search_filters(params)
end
```

### 3. Use Params for User Input

```elixir
# Good - parameterized
{:filter, :user_id, :eq, {:param, :user_id}, []}

# Avoid - direct interpolation (SQL injection risk)
{:filter, :user_id, :eq, params[:user_id], []}
```

### 4. Provide Defaults

```elixir
pagination: {:paginate, :offset, %{
  limit: params[:per_page] || 20,  # Default limit
  offset: params[:offset] || 0      # Default offset
}, []}
```

### 5. Document Complex Specs

```elixir
@doc """
Build product search specification.

## Parameters

- `params[:category_id]` - Filter by category
- `params[:min_price]` - Minimum price filter
- `params[:search]` - Text search on name/description
- `params[:sort_by]` - Sort field (price_asc, price_desc, popular)

## Preloads

- Reviews: Limited to 5 most helpful
- Category: Always included
"""
def build_product_spec(params) do
  # ...
end
```

## See Also

- `Events.Query` - Core query API
- `Events.Query.Token` - Token structure
- `Events.Query.DynamicBuilder` - Dynamic building
- `Events.Query.SyntaxConverter` - Syntax conversion
- `Events.Query.SearchExamples` - Comprehensive examples
- `LISTING_QUERIES.md` - Filter and order guide
- `NESTED_QUERIES.md` - Nested preload guide
- `QUERY_SYSTEM.md` - Complete API reference
