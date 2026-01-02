# Syntax Conversion Guide

Complete guide to converting between Pipeline, DSL, and Spec syntax styles.

## Overview

The query system supports three complementary syntax styles:

1. **Pipeline Style** - Functional composition with `|>`
2. **DSL Style** - Macro-based declarative syntax
3. **Spec Style** - Data-driven query specifications

All three styles produce identical query tokens and can be freely converted between each other.

## Three Syntax Styles

### Pipeline Style

Explicit, step-by-step query construction:

```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.filter(:age, :gte, 18)
|> Query.order(:name, :asc)
|> Query.limit(10)
|> Query.execute()
```

**Best for:**
- Incremental query building
- Debugging and inspection
- When you need explicit control
- Interactive development

### DSL Style

Clean, declarative block syntax:

```elixir
import OmQuery.DSL

query User do
  filter(:status, :eq, "active")
  filter(:age, :gte, 18)
  order(:name, :asc)
  limit(10)
end
|> Query.execute()
```

**Best for:**
- Static queries
- Readability
- Familiar Ecto-like syntax
- Nested preloads with blocks

### Spec Style

Data-driven, parameterized specifications:

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, "active", []},
    {:filter, :age, :gte, {:param, :min_age}, []}
  ],
  orders: [
    {:order, :name, :asc, []}
  ],
  pagination: {:paginate, :offset, %{limit: 10}, []}
}

DynamicBuilder.build(User, spec, %{min_age: 18})
|> Query.execute()
```

**Best for:**
- Dynamic query construction
- API-driven queries
- Parameterized queries
- Storing query templates

## Conversion Examples

### Example 1: Simple Query

**Pipeline:**
```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.order(:name, :asc)
|> Query.limit(10)
```

**DSL:**
```elixir
query User do
  filter(:status, :eq, "active")
  order(:name, :asc)
  limit(10)
end
```

**Spec:**
```elixir
spec = %{
  filters: [{:filter, :status, :eq, "active", []}],
  orders: [{:order, :name, :asc, []}],
  limit: 10
}

DynamicBuilder.build(User, spec)
```

### Example 2: Multiple Filters and Orders

**Pipeline:**
```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.filter(:age, :gte, 18)
|> Query.filter(:verified, :eq, true)
|> Query.order(:priority, :desc)
|> Query.order(:created_at, :desc)
|> Query.order(:id, :asc)
```

**DSL:**
```elixir
query User do
  filter(:status, :eq, "active")
  filter(:age, :gte, 18)
  filter(:verified, :eq, true)
  order(:priority, :desc)
  order(:created_at, :desc)
  order(:id, :asc)
end
```

**Spec:**
```elixir
%{
  filters: [
    {:filter, :status, :eq, "active", []},
    {:filter, :age, :gte, 18, []},
    {:filter, :verified, :eq, true, []}
  ],
  orders: [
    {:order, :priority, :desc, []},
    {:order, :created_at, :desc, []},
    {:order, :id, :asc, []}
  ]
}
|> then(&DynamicBuilder.build(User, &1))
```

### Example 3: Nested Preloads

**Pipeline:**
```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.preload(:posts, fn posts_token ->
  posts_token
  |> Query.filter(:published, :eq, true)
  |> Query.order(:created_at, :desc)
  |> Query.limit(5)
end)
```

**DSL:**
```elixir
query User do
  filter(:status, :eq, "active")

  preload :posts do
    filter(:published, :eq, true)
    order(:created_at, :desc)
    limit(5)
  end
end
```

**Spec:**
```elixir
%{
  filters: [
    {:filter, :status, :eq, "active", []}
  ],
  preloads: [
    {:preload, :posts, %{
      filters: [{:filter, :published, :eq, true, []}],
      orders: [{:order, :created_at, :desc, []}],
      limit: 5
    }, []}
  ]
}
|> then(&DynamicBuilder.build(User, &1))
```

### Example 4: With Pagination

**Pipeline:**
```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.order(:created_at, :desc)
|> Query.paginate(:offset, limit: 20, offset: 40)
```

**DSL:**
```elixir
query User do
  filter(:status, :eq, "active")
  order(:created_at, :desc)
  paginate(:offset, limit: 20, offset: 40)
end
```

**Spec:**
```elixir
%{
  filters: [{:filter, :status, :eq, "active", []}],
  orders: [{:order, :created_at, :desc, []}],
  pagination: {:paginate, :offset, %{limit: 20, offset: 40}, []}
}
|> then(&DynamicBuilder.build(User, &1))
```

## Automated Conversion

Use `OmQuery.SyntaxConverter` for automatic conversion:

### Token to DSL

```elixir
alias OmQuery.SyntaxConverter

token = User
  |> Query.new()
  |> Query.filter(:status, :eq, "active")
  |> Query.order(:name, :asc)

code = SyntaxConverter.token_to_dsl(token, User)
IO.puts(code)
```

**Output:**
```elixir
query User do
  filter(:status, :eq, "active")
  order(:name, :asc)
end
```

### Token to Pipeline

```elixir
code = SyntaxConverter.token_to_pipeline(token, User)
IO.puts(code)
```

**Output:**
```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.order(:name, :asc)
```

### Spec to DSL

```elixir
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

code = SyntaxConverter.spec_to_dsl(spec, User)
IO.puts(code)
```

**Output:**
```elixir
query User do
  filter(:status, :eq, "active")
  filter(:age, :gte, 18)
  order(:created_at, :desc)
  paginate(:offset, limit: 20)
end
```

### Spec to Pipeline

```elixir
code = SyntaxConverter.spec_to_pipeline(spec, User)
IO.puts(code)
```

**Output:**
```elixir
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.filter(:age, :gte, 18)
|> Query.order(:created_at, :desc)
|> Query.paginate(:offset, limit: 20)
```

## Mixing Styles

You can freely mix styles in the same application:

```elixir
# Build base query with DSL
base_query = query User do
  filter(:status, :eq, "active")
  order(:created_at, :desc)
end

# Add dynamic filters with pipeline
dynamic_query = if params[:verified] do
  base_query |> Query.filter(:verified, :eq, true)
else
  base_query
end

# Execute
result = Query.execute(dynamic_query)
```

Or:

```elixir
# Start with spec
spec = %{
  filters: [{:filter, :status, :eq, "active", []}]
}

# Build token
token = DynamicBuilder.build(User, spec)

# Extend with pipeline
token
|> Query.order(:name, :asc)
|> Query.limit(10)
|> Query.execute()
```

## When to Use Each Style

### Use Pipeline When:

✅ Building queries incrementally
✅ Conditionally adding operations
✅ Need explicit control flow
✅ Debugging query construction
✅ Working in IEx

```elixir
def build_user_query(params) do
  token = Query.new(User)

  token = if params[:status] do
    Query.filter(token, :status, :eq, params[:status])
  else
    token
  end

  token = if params[:sort] == "name" do
    Query.order(token, :name, :asc)
  else
    Query.order(token, :created_at, :desc)
  end

  token
end
```

### Use DSL When:

✅ Queries are mostly static
✅ Want Ecto-like familiar syntax
✅ Nested preloads with blocks
✅ Readability is priority
✅ Simple, clear intent

```elixir
def get_user_with_posts(user_id) do
  query User do
    filter(:id, :eq, user_id)

    preload :posts do
      filter(:published, :eq, true)
      order(:published_at, :desc)
      limit(10)
    end
  end
  |> Query.execute()
end
```

### Use Spec When:

✅ Building from external input
✅ API-driven queries
✅ Need parameterization
✅ Storing query templates
✅ Dynamic composition
✅ Query builders/generators

```elixir
def search(params) do
  spec = build_search_spec(params)

  DynamicBuilder.build(Product, spec, params)
  |> Query.execute()
end

defp build_search_spec(params) do
  %{
    filters: build_filters(params),
    orders: build_orders(params),
    pagination: build_pagination(params)
  }
end
```

## Complex Example: All Three Styles

Same query in all three styles:

### Pipeline

```elixir
Organization
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.preload(:users, fn users_token ->
  users_token
  |> Query.filter(:role, :in, ["admin", "editor"])
  |> Query.order(:name, :asc)
  |> Query.preload(:posts, fn posts_token ->
    posts_token
    |> Query.filter(:published, :eq, true)
    |> Query.order(:published_at, :desc)
    |> Query.limit(10)
  end)
end)
|> Query.order(:name, :asc)
|> Query.limit(5)
|> Query.execute()
```

### DSL

```elixir
query Organization do
  filter(:status, :eq, "active")

  preload :users do
    filter(:role, :in, ["admin", "editor"])
    order(:name, :asc)

    preload :posts do
      filter(:published, :eq, true)
      order(:published_at, :desc)
      limit(10)
    end
  end

  order(:name, :asc)
  limit(5)
end
|> Query.execute()
```

### Spec

```elixir
spec = %{
  filters: [
    {:filter, :status, :eq, "active", []}
  ],
  preloads: [
    {:preload, :users, %{
      filters: [
        {:filter, :role, :in, ["admin", "editor"], []}
      ],
      orders: [
        {:order, :name, :asc, []}
      ],
      preloads: [
        {:preload, :posts, %{
          filters: [
            {:filter, :published, :eq, true, []}
          ],
          orders: [
            {:order, :published_at, :desc, []}
          ],
          limit: 10
        }, []}
      ]
    }, []}
  ],
  orders: [
    {:order, :name, :asc, []}
  ],
  limit: 5
}

DynamicBuilder.build(Organization, spec)
|> Query.execute()
```

## Best Practices

### 1. Choose One Primary Style Per Module

```elixir
defmodule MyApp.UserQueries do
  # Use DSL primarily in this module
  import OmQuery.DSL

  def active_users do
    query User do
      filter(:status, :eq, "active")
      order(:name, :asc)
    end
  end

  def verified_users do
    query User do
      filter(:verified, :eq, true)
      order(:created_at, :desc)
    end
  end
end
```

### 2. Use Specs for API Endpoints

```elixir
defmodule MyAppWeb.ProductController do
  def index(conn, params) do
    spec = build_search_spec(params)

    result = DynamicBuilder.build(Product, spec, params)
      |> Query.execute()

    json(conn, result)
  end

  defp build_search_spec(params) do
    # Build from API params
  end
end
```

### 3. Pipeline for Conditional Logic

```elixir
def search_posts(params) do
  base = Query.new(Post)

  base
  |> apply_status_filter(params)
  |> apply_date_filter(params)
  |> apply_author_filter(params)
  |> apply_ordering(params)
  |> Query.execute()
end

defp apply_status_filter(token, %{status: status}) do
  Query.filter(token, :status, :eq, status)
end
defp apply_status_filter(token, _), do: token
```

### 4. DSL for Schema Defaults

```elixir
defmodule MyApp.Post do
  use Ecto.Schema
  import OmQuery.DSL

  schema "posts" do
    # fields...
  end

  def published_query do
    query __MODULE__ do
      filter(:status, :eq, "published")
      filter(:published_at, :lte, DateTime.utc_now())
      order(:published_at, :desc)
    end
  end
end
```

## See Also

- `OmQuery` - Core API
- `OmQuery.DSL` - Macro DSL
- `OmQuery.DynamicBuilder` - Spec building
- `OmQuery.SyntaxConverter` - Conversion utilities
- `DYNAMIC_BUILDER.md` - Dynamic query guide
- `LISTING_QUERIES.md` - Filters and orders
- `NESTED_QUERIES.md` - Nested preloads
