# Nested Queries and API Consistency

## API Design Principles

All query operations follow a **consistent arity pattern** for predictability and ease of use.

### Consistent Function Signatures

Every operation that accepts options follows this pattern:

```elixir
operation(token, required_args..., opts \\ [])
```

## Core Operations

### 1. **filter/5** - Add filter conditions

```elixir
@spec filter(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
def filter(token, field, op, value, opts \\ [])
```

**Parameters:**
- `field` - Field name to filter on
- `op` - Operator (`:eq`, `:neq`, `:gt`, `:gte`, `:lt`, `:lte`, `:in`, `:not_in`, `:like`, `:ilike`, `:is_nil`, `:not_nil`, `:between`, `:contains`, `:jsonb_contains`, `:jsonb_has_key`)
- `value` - Value to compare against
- `opts` - Options
  - `:binding` - Named binding for joined tables (default: `:root`)
  - `:case_insensitive` - Case insensitive comparison (default: `false`)

**Examples:**

```elixir
# Simple filter
Query.filter(token, :status, :eq, "active")

# With case insensitive
Query.filter(token, :email, :eq, "john@example.com", case_insensitive: true)

# On joined table
Query.filter(token, :published, :eq, true, binding: :posts)
```

### 2. **order/4** - Add ordering

```elixir
@spec order(Token.t(), atom(), :asc | :desc, keyword()) :: Token.t()
def order(token, field, direction \\ :asc, opts \\ [])
```

**Parameters:**
- `field` - Field name to order by
- `direction` - Sort direction (`:asc` or `:desc`, default: `:asc`)
- `opts` - Options
  - `:binding` - Named binding for joined tables (default: `:root`)

**Examples:**

```elixir
# Simple ascending
Query.order(token, :name)

# Descending
Query.order(token, :created_at, :desc)

# On joined table
Query.order(token, :title, :asc, binding: :posts)
```

### 3. **paginate/3** - Add pagination

```elixir
@spec paginate(Token.t(), :offset | :cursor, keyword()) :: Token.t()
def paginate(token, type, opts \\ [])
```

**Parameters:**
- `type` - Pagination type (`:offset` or `:cursor`)
- `opts` - Pagination options
  - For offset: `:limit`, `:offset`
  - For cursor: `:limit`, `:cursor_fields`, `:after`, `:before`

**Examples:**

```elixir
# Offset pagination
Query.paginate(token, :offset, limit: 20, offset: 40)

# Cursor pagination
Query.paginate(token, :cursor,
  cursor_fields: [:created_at, :id],
  limit: 20,
  after: cursor
)
```

### 4. **join/4** - Add joins

```elixir
@spec join(Token.t(), atom() | module(), atom(), keyword()) :: Token.t()
def join(token, association_or_schema, type \\ :inner, opts \\ [])
```

**Parameters:**
- `association_or_schema` - Association name or schema module
- `type` - Join type (`:inner`, `:left`, `:right`, `:full`, `:cross`, default: `:inner`)
- `opts` - Options
  - `:as` - Named binding for this join
  - `:on` - Custom join conditions

**Examples:**

```elixir
# Simple association join
Query.join(token, :posts, :left)

# With named binding
Query.join(token, :posts, :inner, as: :user_posts)
```

### 5. **preload/3** - Add preloads (with nesting support)

```elixir
# Simple preload
@spec preload(Token.t(), atom() | list()) :: Token.t()
def preload(token, associations)

# Nested preload with filters
@spec preload(Token.t(), atom(), (Token.t() -> Token.t())) :: Token.t()
def preload(token, association, builder_fn)
```

**Examples:**

```elixir
# Simple preloads
Query.preload(token, :posts)
Query.preload(token, [:posts, :comments])

# Nested with filters
Query.preload(token, :posts, fn posts_token ->
  posts_token
  |> Query.filter(:published, :eq, true)
  |> Query.order(:created_at, :desc)
  |> Query.limit(10)
end)
```

## 3-Level Nested Example

### Basic Structure

```elixir
import Events.Core.Query.DSL

query Organization do
  filter(:status, :eq, "active")

  # Level 1: Users
  preload :users do
    filter(:status, :eq, "active")
    order(:name, :asc)
    limit(50)

    # Level 2: Posts
    preload :posts do
      filter(:status, :eq, "published")
      order(:published_at, :desc)
      limit(10)

      # Level 3: Comments
      preload :comments do
        filter(:status, :eq, "approved")
        order(:created_at, :desc)
        limit(5)
      end
    end
  end
end
```

### With Pagination at Each Level

```elixir
query Organization do
  filter(:status, :eq, "active")

  # Level 1: Users with offset pagination
  preload :users do
    filter(:status, :eq, "active")
    order(:created_at, :desc)
    paginate(:offset, limit: 20, offset: 0)

    # Level 2: Posts with offset pagination
    preload :posts do
      filter(:status, :eq, "published")
      order(:published_at, :desc)
      paginate(:offset, limit: 5, offset: 0)

      # Level 3: Comments with offset pagination
      preload :comments do
        filter(:status, :eq, "approved")
        order(:created_at, :desc)
        paginate(:offset, limit: 3, offset: 0)
      end
    end
  end
end
```

### With Cursor Pagination

```elixir
query Organization do
  filter(:status, :eq, "active")

  # Level 1: Users with cursor pagination
  preload :users do
    filter(:status, :eq, "active")
    order(:created_at, :desc)
    order(:id, :desc)
    paginate(:cursor,
      cursor_fields: [:created_at, :id],
      limit: 20,
      after: user_cursor
    )

    # Level 2: Posts with cursor pagination
    preload :posts do
      filter(:status, :eq, "published")
      order(:published_at, :desc)
      order(:id, :desc)
      paginate(:cursor,
        cursor_fields: [:published_at, :id],
        limit: 10,
        after: post_cursor
      )

      # Level 3: Comments with cursor pagination
      preload :comments do
        filter(:status, :eq, "approved")
        order(:created_at, :desc)
        order(:id, :desc)
        paginate(:cursor,
          cursor_fields: [:created_at, :id],
          limit: 5,
          after: comment_cursor
        )
      end
    end
  end
end
```

### With Complex Filters

```elixir
query Organization do
  filter(:status, :eq, "active")
  filter(:verified, :eq, true)

  # Level 1: Users with multiple filters
  preload :users do
    filter(:status, :eq, "active")
    filter(:role, :in, ["admin", "editor"])
    filter(:created_at, :gte, thirty_days_ago)
    filter(:email_verified, :eq, true)
    order(:last_login_at, :desc)
    limit(50)

    # Level 2: Posts with complex filters
    preload :posts do
      filter(:status, :eq, "published")
      filter(:views, :gte, 100)
      filter(:published_at, :gte, thirty_days_ago)
      filter(:featured, :eq, true)
      order(:views, :desc)
      order(:published_at, :desc)
      limit(20)

      # Level 3: Comments with strict filters
      preload :comments do
        filter(:status, :eq, "approved")
        filter(:flagged, :eq, false)
        filter(:spam_score, :lt, 0.3)
        order(:helpful_count, :desc)
        limit(10)
      end
    end
  end
end
```

### Pipeline Style (Same Result)

```elixir
Organization
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.preload(:users, fn users_token ->
  users_token
  |> Query.filter(:status, :eq, "active")
  |> Query.order(:name, :asc)
  |> Query.limit(50)
  |> Query.preload(:posts, fn posts_token ->
    posts_token
    |> Query.filter(:status, :eq, "published")
    |> Query.order(:published_at, :desc)
    |> Query.limit(10)
    |> Query.preload(:comments, fn comments_token ->
      comments_token
      |> Query.filter(:status, :eq, "approved")
      |> Query.order(:created_at, :desc)
      |> Query.limit(5)
    end)
  end)
end)
```

### Multiple Associations at Each Level

```elixir
query Organization do
  filter(:status, :eq, "active")

  # Multiple Level 1 preloads
  preload :users do
    filter(:status, :eq, "active")
    limit(100)

    # Multiple Level 2 preloads
    preload :posts do
      filter(:status, :eq, "published")
      limit(10)

      # Level 3 preloads
      preload :comments do
        filter(:status, :eq, "approved")
        limit(5)
      end

      preload :tags do
        filter(:active, :eq, true)
      end
    end

    # Another Level 2 preload
    preload(:profile)
  end

  # Another Level 1 preload
  preload :departments do
    filter(:active, :eq, true)
    order(:name, :asc)
  end
end
```

## Real-World Use Cases

### Dashboard Data Loading

```elixir
query Organization do
  filter(:status, :eq, "active")

  # Recent active users
  preload :users do
    filter(:status, :eq, "active")
    filter(:last_login_at, :gte, seven_days_ago)
    order(:last_login_at, :desc)
    limit(25)

    # Trending posts
    preload :posts do
      filter(:status, :eq, "published")
      filter(:published_at, :gte, seven_days_ago)
      filter(:views, :gte, 50)
      order(:views, :desc)
      limit(5)

      # Top comments
      preload :comments do
        filter(:status, :eq, "approved")
        filter(:created_at, :gte, seven_days_ago)
        order(:helpful_count, :desc)
        limit(3)
      end
    end
  end
end
```

### Social Feed Loading

```elixir
query User do
  filter(:id, :eq, current_user_id)

  # Following users
  preload :following do
    filter(:status, :eq, "active")
    order(:followed_at, :desc)
    limit(100)

    # Their recent posts
    preload :posts do
      filter(:status, :eq, "published")
      filter(:created_at, :gte, twenty_four_hours_ago)
      order(:created_at, :desc)
      limit(10)

      # Reactions on posts
      preload :reactions do
        filter(:type, :in, ["like", "love"])
        order(:created_at, :desc)
        limit(5)
      end
    end
  end
end
```

## Key Benefits

### 1. **Consistent API**
All operations follow the same pattern: `operation(token, required_args, opts \\ [])`

### 2. **Unlimited Nesting**
Preloads can be nested to any depth with full filtering and pagination at each level.

### 3. **Type Safety**
All operations are validated at token creation time, catching errors early.

### 4. **Composability**
Tokens can be built incrementally and passed around as first-class values.

### 5. **Performance**
Filters and pagination at each level minimize data fetching and memory usage.

### 6. **Flexibility**
Mix DSL and pipeline styles as needed. Both produce identical tokens.

## Testing Nested Queries

See `Events.Core.Query.NestedExample` for comprehensive examples you can run:

```elixir
# In IEx
iex> alias Events.Core.Query.NestedExample

# Inspect token structure
iex> NestedExample.inspect_nested_token()

# View all examples
iex> NestedExample.basic_three_level_nesting()
iex> NestedExample.three_level_with_pagination(1, 1, 1)
iex> NestedExample.three_level_with_cursors()
iex> NestedExample.dashboard_data_loading()
```

## Best Practices

1. **Limit Nesting Depth** - While unlimited nesting is supported, 3-4 levels is practical for most use cases
2. **Always Paginate** - Add limits to nested preloads to avoid loading too much data
3. **Filter Early** - Apply filters at the highest level possible to reduce data volume
4. **Use Cursor Pagination** - For user-facing infinite scroll features
5. **Use Offset Pagination** - For admin interfaces with page numbers
6. **Consistent Ordering** - Always specify ordering when using pagination
7. **Named Bindings** - Use descriptive binding names for complex joins

## Performance Considerations

- Each nested preload generates a separate query
- Ecto optimizes multiple preloads into fewer queries when possible
- Deep nesting (5+ levels) may impact performance
- Consider using joins instead of preloads for filtering purposes
- Use `limit` at every level to control data volume
- Monitor query count with telemetry

## See Also

- `QUERY_SYSTEM.md` - Complete API documentation
- `Events.Core.Query.Examples` - More query patterns
- `Events.Core.Query.Demo` - Working demonstrations
- `Events.Core.Query.NestedExample` - This module with all examples
