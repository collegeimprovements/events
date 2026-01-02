# Listing Queries - Filters and Ordering

Complete guide to filtering and ordering in the query system.

## Overview

The query system supports **both individual calls and list-based approaches** for filters and ordering:

✅ **Multiple separate calls** - Chain individual operations
✅ **Single call with list** - Pass all operations at once
✅ **Mixed approaches** - Combine both patterns

All approaches are **equivalent** and produce the same query token.

## Filter API

### Single Filter: `filter/5`

Add one filter at a time.

```elixir
@spec filter(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()

# Parameters:
# - field: Field name
# - op: Operator (:eq, :neq, :gt, :gte, :lt, :lte, :in, :not_in, :like, :ilike, :is_nil, :not_nil, :between, :contains, :jsonb_contains, :jsonb_has_key)
# - value: Value to compare
# - opts: Options (optional)
#   - :binding - For joined tables (default: :root)
#   - :case_insensitive - For string comparisons (default: false)
```

**Examples:**

```elixir
# Pipeline style - chaining
User
|> Query.new()
|> Query.filter(:status, :eq, "active")
|> Query.filter(:age, :gte, 18)
|> Query.filter(:verified, :eq, true)

# DSL style - separate calls
query User do
  filter(:status, :eq, "active")
  filter(:age, :gte, 18)
  filter(:verified, :eq, true)
end
```

### Multiple Filters: `filters/2`

Add multiple filters in one call.

```elixir
@spec filters(Token.t(), [
  {atom(), atom(), term()} |
  {atom(), atom(), term(), keyword()}
]) :: Token.t()

# Parameters:
# - filter_list: List of filter specifications
#   - 3-tuple: {field, op, value}
#   - 4-tuple: {field, op, value, opts}
```

**Examples:**

```elixir
# Pipeline style - single call
User
|> Query.new()
|> Query.filters([
  {:status, :eq, "active"},
  {:age, :gte, 18},
  {:verified, :eq, true}
])

# DSL style - single call
query User do
  filters([
    {:status, :eq, "active"},
    {:age, :gte, 18},
    {:verified, :eq, true}
  ])
end

# With options (4-tuple format)
Query.filters(token, [
  {:status, :eq, "active", []},
  {:email, :ilike, "%@example.com", [case_insensitive: true]},
  {:published, :eq, true, [binding: :posts]}
])

# Mixed 3-tuples and 4-tuples
Query.filters(token, [
  {:status, :eq, "active"},
  {:email, :ilike, "%@example.com", [case_insensitive: true]},
  {:age, :gte, 18}
])
```

## Order API

### Single Order: `order/4`

Add one order clause at a time.

```elixir
@spec order(Token.t(), atom(), :asc | :desc, keyword()) :: Token.t()

# Parameters:
# - field: Field name
# - direction: :asc or :desc (default: :asc)
# - opts: Options (optional)
#   - :binding - For joined tables (default: :root)
```

**Examples:**

```elixir
# Pipeline style - chaining
User
|> Query.new()
|> Query.order(:priority, :desc)
|> Query.order(:created_at, :desc)
|> Query.order(:id, :asc)

# DSL style - separate calls
query User do
  order(:priority, :desc)
  order(:created_at, :desc)
  order(:id, :asc)
end

# With default direction (ascending)
Query.order(token, :name)

# On joined table
Query.order(token, :title, :asc, binding: :posts)
```

### Multiple Orders: `orders/2`

Add multiple order clauses in one call.

```elixir
@spec orders(Token.t(), [
  atom() |
  {atom(), :asc | :desc} |
  {atom(), :asc | :desc, keyword()}
]) :: Token.t()

# Parameters:
# - order_list: List of order specifications
#   - Atom: field (defaults to :asc)
#   - 2-tuple: {field, direction}
#   - 3-tuple: {field, direction, opts}
```

**Examples:**

```elixir
# Pipeline style - single call
User
|> Query.new()
|> Query.orders([
  {:priority, :desc},
  {:created_at, :desc},
  {:id, :asc}
])

# DSL style - single call
query User do
  orders([
    {:priority, :desc},
    {:created_at, :desc},
    {:id, :asc}
  ])
end

# Simple format (all ascending)
Query.orders(token, [:name, :email, :id])

# Mixed formats
Query.orders(token, [
  :name,                      # defaults to :asc
  {:created_at, :desc},       # with direction
  {:updated_at, :desc},
  :id
])

# With options (3-tuple format)
Query.orders(token, [
  {:name, :asc, []},
  {:created_at, :desc, []},
  {:title, :asc, [binding: :posts]}
])
```

## Complete Examples

### Example 1: Separate Calls (Most Common)

```elixir
import OmQuery.DSL

query User do
  filter(:status, :eq, "active")
  filter(:age, :gte, 18)
  filter(:verified, :eq, true)
  filter(:role, :in, ["admin", "editor"])

  order(:priority, :desc)
  order(:created_at, :desc)
  order(:id, :asc)

  limit(20)
end
```

### Example 2: List-Based Calls

```elixir
import OmQuery.DSL

query User do
  filters([
    {:status, :eq, "active"},
    {:age, :gte, 18},
    {:verified, :eq, true},
    {:role, :in, ["admin", "editor"]}
  ])

  orders([
    {:priority, :desc},
    {:created_at, :desc},
    {:id, :asc}
  ])

  limit(20)
end
```

### Example 3: Mixed Approach

```elixir
query User do
  # Initial filter
  filter(:status, :eq, "active")

  # Additional filters as list
  filters([
    {:age, :gte, 18},
    {:verified, :eq, true}
  ])

  # Orders as list
  orders([
    {:priority, :desc},
    {:created_at, :desc}
  ])

  # Additional order
  order(:id, :asc)

  limit(20)
end
```

### Example 4: Dynamic Filter Building

```elixir
def list_products(params) do
  base_filters = [{:status, :eq, "active"}]

  filters_list =
    base_filters
    |> maybe_add_price_filter(params)
    |> maybe_add_category_filter(params)
    |> maybe_add_search_filter(params)

  orders_list =
    case params[:sort_by] do
      "price_asc" -> [{:price, :asc}, :id]
      "price_desc" -> [{:price, :desc}, :id]
      "name" -> [:name, :id]
      _ -> [{:created_at, :desc}, :id]
    end

  Product
  |> Query.new()
  |> Query.filters(filters_list)
  |> Query.orders(orders_list)
  |> Query.paginate(:offset, limit: 20, offset: params[:offset] || 0)
end

defp maybe_add_price_filter(filters, %{min_price: price}) do
  filters ++ [{:price, :gte, price}]
end
defp maybe_add_price_filter(filters, _), do: filters

defp maybe_add_category_filter(filters, %{category: cat}) do
  filters ++ [{:category, :eq, cat}]
end
defp maybe_add_category_filter(filters, _), do: filters

defp maybe_add_search_filter(filters, %{search: term}) do
  filters ++ [{:name, :ilike, "%#{term}%"}]
end
defp maybe_add_search_filter(filters, _), do: filters
```

### Example 5: Blog Post Listing

```elixir
def list_posts(filters_map, sort_option) do
  # Convert map to filter list
  filter_list =
    filters_map
    |> Enum.flat_map(fn
      {:status, values} when is_list(values) ->
        [{:status, :in, values}]

      {:published_after, date} ->
        [{:published_at, :gte, date}]

      {:published_before, date} ->
        [{:published_at, :lte, date}]

      {:author_ids, ids} when is_list(ids) ->
        [{:author_id, :in, ids}]

      {:min_views, count} ->
        [{:views, :gte, count}]

      _ ->
        []
    end)

  # Determine ordering
  order_list =
    case sort_option do
      :popular -> [{:views, :desc}, {:comments_count, :desc}, :id]
      :recent -> [{:published_at, :desc}, :id]
      :trending -> [{:trending_score, :desc}, {:published_at, :desc}, :id]
      _ -> [{:published_at, :desc}, :id]
    end

  query Post do
    filters(filter_list)
    orders(order_list)
    limit(50)
  end
end
```

## All 16 Filter Operators

Both patterns support all operators:

```elixir
# Separate calls
token
|> Query.filter(:status, :eq, "active")
|> Query.filter(:category, :neq, "archived")
|> Query.filter(:price, :gt, 0)
|> Query.filter(:price, :gte, 10)
|> Query.filter(:stock, :lt, 100)
|> Query.filter(:stock, :lte, 50)
|> Query.filter(:category, :in, ["electronics", "gadgets"])
|> Query.filter(:tags, :not_in, ["discontinued"])
|> Query.filter(:name, :like, "%widget%")
|> Query.filter(:description, :ilike, "%smart%")
|> Query.filter(:deleted_at, :is_nil, nil)
|> Query.filter(:verified_at, :not_nil, nil)
|> Query.filter(:price, :between, {10.0, 100.0})
|> Query.filter(:features, :contains, ["wifi"])
|> Query.filter(:metadata, :jsonb_contains, %{featured: true})
|> Query.filter(:attributes, :jsonb_has_key, "color")

# Single list call (identical result)
Query.filters(token, [
  {:status, :eq, "active"},
  {:category, :neq, "archived"},
  {:price, :gt, 0},
  {:price, :gte, 10},
  {:stock, :lt, 100},
  {:stock, :lte, 50},
  {:category, :in, ["electronics", "gadgets"]},
  {:tags, :not_in, ["discontinued"]},
  {:name, :like, "%widget%"},
  {:description, :ilike, "%smart%"},
  {:deleted_at, :is_nil, nil},
  {:verified_at, :not_nil, nil},
  {:price, :between, {10.0, 100.0}},
  {:features, :contains, ["wifi"]},
  {:metadata, :jsonb_contains, %{featured: true}},
  {:attributes, :jsonb_has_key, "color"}
])
```

## When to Use Each Pattern

### Use Separate Calls When:

- Building queries incrementally
- Each filter is independent
- Code readability is priority
- Working with simple, static filters

```elixir
query User do
  filter(:status, :eq, "active")
  filter(:age, :gte, 18)
  order(:name, :asc)
end
```

### Use List-Based Calls When:

- Filters/orders are computed dynamically
- Building from external input
- Conditionally adding filters
- Working with parameterized queries
- Need to manipulate filter list before applying

```elixir
def list_users(params) do
  filters = build_filters_from_params(params)
  orders = build_orders_from_sort(params[:sort])

  query User do
    filters(filters)
    orders(orders)
  end
end
```

### Use Mixed Approach When:

- Some filters are always present
- Others are conditional
- Want balance of readability and flexibility

```elixir
query User do
  # Always filter active users
  filter(:status, :eq, "active")

  # Conditionally add more filters
  filters(additional_filters)

  # Standard ordering
  orders([{:created_at, :desc}, :id])
end
```

## Performance Notes

- Multiple `filter()` calls: Each adds one operation to token
- Single `filters()` call: Efficiently adds all at once
- **No performance difference** - both produce identical queries
- Choose based on code clarity and maintainability
- Filter order matters for query optimization

## Summary

| Feature | Individual Calls | List-Based Call |
|---------|-----------------|-----------------|
| **Filters** | `filter/5` (chaining) | `filters/2` (list) |
| **Orders** | `order/4` (chaining) | `orders/2` (list) |
| **Format** | One operation per call | List of tuples |
| **Use Case** | Static, simple queries | Dynamic, computed queries |
| **Readability** | More verbose | More compact |
| **Flexibility** | Incremental building | Bulk operations |

## See Also

- `OmQuery.ListingExamples` - 21 comprehensive examples
- `QUERY_SYSTEM.md` - Complete API reference
- `NESTED_QUERIES.md` - Nested preloads guide
- `OmQuery.Demo` - Working demonstrations
