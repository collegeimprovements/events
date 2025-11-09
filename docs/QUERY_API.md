# Query API - Composable Builder with Smart Filters

A powerful query builder that composes with both keyword and pipe syntax, featuring smart filter operations, join support, and built-in soft delete awareness.

## Features

✅ **Builder Pattern** - Accumulates query operations
✅ **Smart Filter Syntax** - `{field, operation, value, options}` with intelligent defaults
✅ **Join Support** - Filter on joined tables including many-to-many
✅ **Soft Delete** - Automatically excludes deleted records
✅ **Dual Syntax** - Works with both keyword and pipe syntax
✅ **Window Functions** - ROW_NUMBER, RANK, DENSE_RANK, LEAD, LAG, and more
✅ **Subqueries** - Support for WHERE IN, EXISTS, FROM, and SELECT subqueries
✅ **Conditional Preloads** - Preload associations with filters and ordering
✅ **Aggregation** - GROUP BY, HAVING, DISTINCT support
✅ **Final Execution** - Use with `Repo.all()`, `Repo.one()`, or `to_sql()`

## Quick Start

```elixir
alias Events.Repo.Query
alias Events.Repo

# Pipe syntax
Query.new(Product)
|> Query.where(status: "active")
|> Query.where({:price, :gt, 100})
|> Query.limit(10)
|> Repo.all()

# Keyword syntax
Query.new(Product, [
  where: [status: "active"],
  where: {:price, :gt, 100},
  limit: 10
])
|> Repo.all()

# Get SQL for debugging
{sql, params} = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.to_sql()
```

## Filter Syntax

The `where/2` function supports multiple formats for maximum flexibility:

### Simple Equality (Inferred)

```elixir
# String/integer equality
Query.where(query, status: "active")
Query.where(query, price: 100)

# Multiple conditions
Query.where(query, [status: "active", type: "widget"])
```

### List = IN Operator (Inferred)

```elixir
# List automatically uses :in
Query.where(query, status: ["active", "pending", "published"])

# Equivalent to
Query.where(query, {:status, :in, ["active", "pending", "published"]})
```

### With Explicit Operators

```elixir
# Comparisons
Query.where(query, {:price, :gt, 100})
Query.where(query, {:price, :gte, 100})
Query.where(query, {:price, :lt, 1000})
Query.where(query, {:price, :lte, 1000})

# Range
Query.where(query, {:price, :between, {10, 100}})

# Pattern matching
Query.where(query, {:name, :like, "%widget%"})
Query.where(query, {:name, :ilike, "%widget%"})  # case-insensitive

# NULL checks
Query.where(query, {:deleted_at, :is_nil, nil})
Query.where(query, {:deleted_at, :not_nil, nil})

# List operations
Query.where(query, {:id, :in, [id1, id2, id3]})
Query.where(query, {:id, :not_in, [id1, id2, id3]})
```

### With Options

```elixir
# Include NULL values
Query.where(query, {:email, :eq, "user@example.com", include_nil: true})

# Case-sensitive matching (disabled by default)
Query.where(query, {:name, :eq, "Widget", case_sensitive: true})

# Disable trimming (enabled by default)
Query.where(query, {:code, :eq, " ABC ", trim: false})
```

## Default Behavior (Important!)

**By default, all string filters are:**
- ✅ **Trimmed** - Leading/trailing whitespace is automatically removed (`trim: true`)
- ✅ **Case insensitive** - Comparisons ignore case differences (`case_sensitive: false`)

This means these queries are **equivalent**:

```elixir
Query.where(query, name: "widget")
Query.where(query, name: "Widget")
Query.where(query, name: "WIDGET")
Query.where(query, name: " widget ")
Query.where(query, name: "  WIDGET  ")

# All match records where name is "Widget", "widget", "WIDGET", etc.
```

**To disable these defaults:**

```elixir
# Case-sensitive exact match
Query.where(query, {:name, :eq, "Widget", case_sensitive: true})

# No trimming
Query.where(query, {:code, :eq, " ABC ", trim: false})

# Both disabled - exact match only
Query.where(query, {:name, :eq, "Widget", trim: false, case_sensitive: true})
```

**Why these defaults?**
- Most user input has accidental whitespace that should be ignored
- Case-insensitive searches are more user-friendly
- You can always override when you need exact matching (codes, IDs, etc.)

**Applies to all operations:**
- `:eq`, `:neq` - Uses `LOWER()` for case insensitivity
- `:like`, `:not_like` - Uses `ILIKE` by default instead of `LIKE`
- `:in`, `:not_in` - Trims and lowercases each value in the list
- `:between` - Trims and lowercases both min and max values

### Value Transformation

The `value_fn` option allows custom transformations (applied **after** trimming):

```elixir
# Custom normalization
Query.where(query, {:sku, :eq, "abc-123", value_fn: &String.upcase/1})
# Value is first trimmed, then uppercased

# Normalize email to lowercase (trimming is automatic)
Query.where(query, {:email, :eq, "USER@EXAMPLE.COM", value_fn: &String.downcase/1})

# Apply to lists - transforms each element (after trimming)
Query.where(query, {:tags, :in, ["tag1", "tag2"], value_fn: &String.upcase/1})

# Apply to :between - transforms both min and max
Query.where(query, {:price, :between, {10.5555, 99.9999}, value_fn: &Float.round(&1, 2)})

# Custom transformation function
normalize_sku = fn sku ->
  sku
  |> String.upcase()
  |> String.replace(~r/[^A-Z0-9]/, "")
end

Query.where(query, {:sku, :eq, " abc-123 ", value_fn: normalize_sku})
# First trimmed to "abc-123", then transformed to "ABC123"

# In filters list
Query.new(Product, filters: [
  {:name, :eq, "Widget"},  # Automatically trimmed and case-insensitive
  {:sku, :eq, "abc-123", value_fn: &String.upcase/1},
  {:tags, :in, ["featured", "new"]}  # Each tag trimmed and case-insensitive
])
```

**How it works:**
- For simple values (`:eq`, `:neq`, `:gt`, etc.): applies the function to the value
- For `:in` and `:not_in`: applies the function to each element in the list
- For `:between`: applies the function to both min and max values
- For `:is_nil` and `:not_nil`: no transformation (these don't use values)

## Date/Time Comparisons

The `data_type` option handles date, datetime, and time comparisons properly by casting both the database field and comparison value to the appropriate PostgreSQL type. It also **automatically parses date strings** in various formats for maximum convenience.

### Why This Is Needed

When comparing date/datetime fields in PostgreSQL, you often want to compare only the date portion, ignoring the time. The `data_type` option makes this easy and correct:

```elixir
# Without data_type - compares full timestamp (includes time!)
Query.where(query, {:created_at, :eq, ~D[2024-01-15]})
# Might not match records with created_at = "2024-01-15 14:30:00"

# With data_type - compares only date parts
Query.where(query, {:created_at, :eq, ~D[2024-01-15], data_type: :date})
# Matches all records created on 2024-01-15, regardless of time

# Can also use string dates - automatically parsed!
Query.where(query, {:created_at, :eq, "2024-01-15", data_type: :date})
Query.where(query, {:created_at, :eq, "01/15/2024", data_type: :date})  # US format
```

### Supported Data Types

- `:date` - Casts to PostgreSQL `date` type (compares only date, ignores time)
- `:datetime` - Casts to PostgreSQL `timestamp` type (full datetime comparison)
- `:time` - Casts to PostgreSQL `time` type (compares only time, ignores date)

### Automatic Date Format Parsing

When `data_type: :date` is specified, string values are **automatically parsed** into Date structs. Supported formats:

- **`yyyy-mm-dd`** - ISO format with dash (e.g., "2024-01-15")
- **`yyyy/mm/dd`** - ISO format with slash (e.g., "2024/01/15")
- **`mm-dd-yyyy`** - US format with dash (e.g., "01-15-2024")
- **`mm/dd/yyyy`** - US format with slash (e.g., "01/15/2024")

This works with all date operations: `:eq`, `:neq`, `:gt`, `:gte`, `:lt`, `:lte`, `:between`, `:in`, `:not_in`

```elixir
# All of these are equivalent and work correctly:
Query.where(query, {:created_at, :eq, ~D[2024-01-15], data_type: :date})
Query.where(query, {:created_at, :eq, "2024-01-15", data_type: :date})
Query.where(query, {:created_at, :eq, "2024/01/15", data_type: :date})
Query.where(query, {:created_at, :eq, "01-15-2024", data_type: :date})
Query.where(query, {:created_at, :eq, "01/15/2024", data_type: :date})

# Works with all operations
Query.where(query, {:expires_at, :gt, "06/01/2024", data_type: :date})
Query.where(query, {:start_date, :gte, "2024-01-01", data_type: :date})

# Works with :between
Query.where(query, {:created_at, :between, {"01/01/2024", "12/31/2024"}, data_type: :date})

# Works with :in for multiple dates
Query.where(query, {:event_date, :in, ["2024-01-15", "2024-02-20", "03/15/2024"], data_type: :date})
```

### Date Comparisons (`:date`)

```elixir
# Find records created on a specific date (using various formats)
Query.where(query, {:created_at, :eq, ~D[2024-01-15], data_type: :date})
Query.where(query, {:created_at, :eq, "2024-01-15", data_type: :date})
Query.where(query, {:created_at, :eq, "01/15/2024", data_type: :date})

# Find records created after a date
Query.where(query, {:expires_at, :gt, "06/01/2024", data_type: :date})

# Date range - all records in 2024 (using string dates)
Query.where(query, {:created_at, :between, {"2024-01-01", "2024-12-31"}, data_type: :date})

# Find records NOT created on a specific date
Query.where(query, {:created_at, :neq, "01-15-2024", data_type: :date})

# Complex date filtering with mixed formats
Query.new(Order, filters: [
  {:created_at, :gte, "2024-01-01", data_type: :date},
  {:created_at, :lte, "03/31/2024", data_type: :date},
  status: "completed"
])

# Using :in for multiple specific dates
Query.where(query, {
  :event_date,
  :in,
  ["2024-01-15", "2024-02-20", "03/15/2024"],
  data_type: :date
})
```

### DateTime Comparisons (`:datetime`)

```elixir
# Exact datetime comparison (includes time)
Query.where(query, {:updated_at, :gte, ~U[2024-01-01 00:00:00Z], data_type: :datetime})

# Find records updated in the last hour
cutoff = DateTime.utc_now() |> DateTime.add(-3600, :second)
Query.where(query, {:updated_at, :gte, cutoff, data_type: :datetime})

# DateTime range
Query.where(query, {
  :scheduled_at,
  :between,
  {~U[2024-06-01 09:00:00Z], ~U[2024-06-01 17:00:00Z]},
  data_type: :datetime
})
```

### Time Comparisons (`:time`)

```elixir
# Find records with start time before 6 PM
Query.where(query, {:start_time, :lt, ~T[18:00:00], data_type: :time})

# Business hours filter
Query.where(query, {:start_time, :between, {~T[09:00:00], ~T[17:00:00]}, data_type: :time})

# Time equality
Query.where(query, {:reminder_time, :eq, ~T[14:30:00], data_type: :time})
```

### Combining with Other Options

You can combine `data_type` with other options:

```elixir
# Date comparison with NULL handling
Query.where(query, {:expires_at, :eq, ~D[2024-12-31], data_type: :date, include_nil: true})

# Date filter in a list
Query.new(Event, filters: [
  status: "active",
  {:start_date, :gte, ~D[2024-01-01], data_type: :date},
  {:end_date, :lte, ~D[2024-12-31], data_type: :date}
])
```

### How It Works

Under the hood, the `data_type` option uses PostgreSQL's casting syntax:

```elixir
# This query:
Query.where(query, {:created_at, :eq, ~D[2024-01-15], data_type: :date})

# Generates SQL like:
# WHERE created_at::date = '2024-01-15'::date

# This query:
Query.where(query, {:start_time, :lt, ~T[18:00:00], data_type: :time})

# Generates SQL like:
# WHERE start_time::time < '18:00:00'::time
```

### Practical Examples

```elixir
# Find all orders placed today
today = Date.utc_today()
Query.new(Order)
|> Query.where({:placed_at, :eq, today, data_type: :date})
|> Repo.all()

# Find orders placed on a specific date (using string - great for user input!)
Query.new(Order)
|> Query.where({:placed_at, :eq, "01/15/2024", data_type: :date})
|> Repo.all()

# Find events happening this week (using string dates from user input)
Query.new(Event, filters: [
  {:event_date, :between, {"01/01/2024", "01/07/2024"}, data_type: :date},
  status: "active"
])
|> Repo.all()

# Dynamic date filtering from user input (various formats accepted)
def find_orders_by_date(date_string) do
  Query.new(Order)
  |> Query.where({:created_at, :eq, date_string, data_type: :date})
  |> Repo.all()
end

# Works with any supported format:
find_orders_by_date("2024-01-15")  # ISO format
find_orders_by_date("01/15/2024")  # US format
find_orders_by_date("2024/01/15")  # ISO with slashes

# Find appointments in morning hours (before noon)
Query.new(Appointment)
|> Query.where({:scheduled_time, :lt, ~T[12:00:00], data_type: :time})
|> Query.order_by(asc: :scheduled_time)
|> Repo.all()

# Complex date filtering with joins and string dates
Query.new(Product)
|> Query.join(:category)
|> Query.where([
  {:created_at, :gte, "2024-01-01", data_type: :date},
  {:created_at, :lte, "03/31/2024", data_type: :date},  # Mixed formats OK!
  {:category, :name, "Electronics"}
])
|> Repo.all()

# Filter by multiple specific dates (great for holiday/event queries)
Query.new(Sale, filters: [
  {:sale_date, :in, ["12/25/2024", "12/26/2024", "01/01/2025"], data_type: :date},
  status: "active"
])
|> Repo.all()

# Building filters dynamically from user input
def build_date_filters(params) do
  filters = []

  filters = if params["start_date"] do
    [{:created_at, :gte, params["start_date"], data_type: :date} | filters]
  else
    filters
  end

  filters = if params["end_date"] do
    [{:created_at, :lte, params["end_date"], data_type: :date} | filters]
  else
    filters
  end

  Query.new(Order, filters: filters) |> Repo.all()
end

# Handles user input in any format automatically!
build_date_filters(%{"start_date" => "01/01/2024", "end_date" => "2024-12-31"})
```

## List-Based Filters

The Query API supports passing all filters as a list for easy composition and dynamic query building. The `filters:` option accepts the full range of filter syntax including operators, options, and join table filters.

### Using `filters:` Option

```elixir
# Simple list of filters
Query.new(Product, filters: [
  status: "active",
  {:price, :gt, 100},
  {:name, :ilike, "%widget%"}
]) |> Repo.all()

# Mix keyword and tuple formats
Query.new(Product, filters: [
  status: "active",
  type: "physical",
  {:price, :between, {10, 100}},
  {:name, :ilike, "%widget%", case_sensitive: false}
]) |> Repo.all()

# Filters with options (4-tuple syntax)
Query.new(Product, filters: [
  {:name, :ilike, "%pro%", case_sensitive: false},
  {:email, :eq, nil, include_nil: true},
  {:description, :like, "%premium%"},
  {:price, :gte, 100}
]) |> Repo.all()

# Filters on joined tables
Query.new(Product, [
  join: :category,
  join: :brand,
  filters: [
    status: "active",                                    # Main table
    {:price, :gte, 100},                                # Main table with operator
    {:category, :name, "Electronics"},                  # Join table simple
    {:category, :active, true},                         # Join table simple
    {:brand, :country, :in, ["USA", "Japan"]},         # Join table with operator
    {:brand, :name, :ilike, "%tech%", case_sensitive: false}  # Join table with options
  ]
]) |> Repo.all()

# All filter syntax supported:
# - Simple: field: value
# - With operator: {:field, :op, value}
# - With options: {:field, :op, value, opts}
# - Join simple: {:join, :field, value}
# - Join with op: {:join, :field, :op, value}
# - Join with options: {:join, :field, :op, value, opts}
```

### Using `where:` with a List

```elixir
# Pass list to where: option
Query.new(Product, where: [
  status: "active",
  {:price, :gt, 100},
  {:stock, :gte, 1}
]) |> Repo.all()

# Build filter list dynamically
filters = [
  status: "active",
  {:price, :gt, 100}
]

if include_featured do
  filters = filters ++ [tags: ["featured"]]
end

Query.new(Product, where: filters) |> Repo.all()
```

### Passing Lists to `where/2`

```elixir
# Pass list directly to where/2
query = Query.new(Product)

filters = [
  status: "active",
  {:price, :gt, 100},
  {:name, :ilike, "%widget%"}
]

query
|> Query.where(filters)
|> Repo.all()
```

### Dynamic Filter Building

```elixir
# Build filters from params
def search_products(params) do
  filters = []

  filters = if params[:status], do: filters ++ [status: params[:status]], else: filters
  filters = if params[:min_price], do: filters ++ [{:price, :gte, params[:min_price]}], else: filters
  filters = if params[:max_price], do: filters ++ [{:price, :lte, params[:max_price]}], else: filters
  filters = if params[:search], do: filters ++ [{:name, :ilike, "%#{params[:search]}%"}], else: filters

  Query.new(Product, filters: filters) |> Repo.all()
end

# More functional approach
def search_products_v2(params) do
  filters = [
    {:status, params[:status]},
    {:min_price, params[:min_price]},
    {:max_price, params[:max_price]},
    {:search, params[:search]}
  ]
  |> Enum.reject(fn {_key, val} -> is_nil(val) end)
  |> Enum.flat_map(fn
    {:status, status} -> [status: status]
    {:min_price, min} -> [{:price, :gte, min}]
    {:max_price, max} -> [{:price, :lte, max}]
    {:search, term} -> [{:name, :ilike, "%#{term}%"}]
  end)

  Query.new(Product, filters: filters) |> Repo.all()
end

# With options - case insensitive search
def search_products_flexible(params) do
  filters = []

  filters = if params[:status], do: filters ++ [status: params[:status]], else: filters
  filters = if params[:min_price], do: filters ++ [{:price, :gte, params[:min_price]}], else: filters
  filters = if params[:max_price], do: filters ++ [{:price, :lte, params[:max_price]}], else: filters

  # Add case-insensitive search with options
  filters = if params[:search] do
    filters ++ [{:name, :ilike, "%#{params[:search]}%", case_sensitive: false}]
  else
    filters
  end

  Query.new(Product, filters: filters) |> Repo.all()
end

# Dynamic filters with joins
def search_products_with_category(params) do
  opts = []
  filters = []

  # Add join if category filter is present
  opts = if params[:category], do: opts ++ [join: :category], else: opts

  # Build filters including join table filters
  filters = if params[:status], do: filters ++ [status: params[:status]], else: filters
  filters = if params[:min_price], do: filters ++ [{:price, :gte, params[:min_price]}], else: filters

  # Filter on joined category table
  filters = if params[:category] do
    filters ++ [{:category, :slug, params[:category]}]
  else
    filters
  end

  opts = opts ++ [filters: filters, order_by: [desc: :inserted_at]]
  Query.new(Product, opts) |> Repo.all()
end

# With value transformation - normalize user input
def search_products_normalized(params) do
  filters = []

  # Normalize status (trim whitespace)
  filters = if params[:status] do
    filters ++ [{:status, :eq, params[:status], value_fn: &String.trim/1}]
  else
    filters
  end

  # Normalize email (trim and lowercase)
  filters = if params[:email] do
    normalize_email = fn email -> email |> String.trim() |> String.downcase() end
    filters ++ [{:email, :eq, params[:email], value_fn: normalize_email}]
  else
    filters
  end

  # Normalize tags (trim each tag)
  filters = if params[:tags] && is_list(params[:tags]) do
    filters ++ [{:tags, :in, params[:tags], value_fn: &String.trim/1}]
  else
    filters
  end

  Query.new(Product, filters: filters) |> Repo.all()
end
```

### Combining Multiple Options

```elixir
# Combine filters with other options
Query.new(Product, [
  filters: [
    status: "active",
    {:price, :gt, 100}
  ],
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
]) |> Repo.all()

# Mix filters: and where: options
Query.new(Product, [
  filters: [status: "active"],
  where: {:price, :gt, 100},
  limit: 10
]) |> Repo.all()
```

### Filters with Joins

```elixir
# Filters list can include join filters
Query.new(Product, [
  join: :category,
  filters: [
    status: "active",
    {:price, :gt, 100},
    {:category, :name, "Electronics"}  # Filter on joined table
  ]
]) |> Repo.all()

# More complex example
Query.new(Product, [
  join: :category,
  filters: [
    status: "active",
    type: "physical",
    {:price, :between, {10, 100}},
    {:category, :name, "Electronics"},
    {:category, :active, true}
  ],
  order_by: [desc: :price],
  limit: 10
]) |> Repo.all()
```

### Nested Lists

```elixir
# where: accepts nested lists
Query.new(Product, where: [
  [status: "active"],  # First batch of filters
  {:price, :gt, 100},  # Single filter
  [type: "physical", stock: 1]  # Another batch
]) |> Repo.all()

# Useful for grouping related filters
base_filters = [status: "active", type: "physical"]
price_filters = [{:price, :gte, 10}, {:price, :lte, 100}]
category_filters = [{:category, :name, "Electronics"}]

Query.new(Product, [
  join: :category,
  where: [base_filters, price_filters, category_filters]
]) |> Repo.all()
```

## Operations Reference

| Operation | Description | Example |
|-----------|-------------|---------|
| `:eq` | Equal | `{:status, :eq, "active"}` |
| `:neq` | Not equal | `{:status, :neq, "deleted"}` |
| `:gt` | Greater than | `{:price, :gt, 100}` |
| `:gte` | Greater than or equal | `{:price, :gte, 100}` |
| `:lt` | Less than | `{:price, :lt, 1000}` |
| `:lte` | Less than or equal | `{:price, :lte, 1000}` |
| `:in` | In list | `{:status, :in, ["active", "pending"]}` |
| `:not_in` | Not in list | `{:status, :not_in, ["deleted"]}` |
| `:like` | Pattern match (case-sensitive) | `{:name, :like, "%widget%"}` |
| `:ilike` | Pattern match (case-insensitive) | `{:name, :ilike, "%widget%"}` |
| `:not_like` | Not like | `{:name, :not_like, "%test%"}` |
| `:not_ilike` | Not ilike | `{:name, :not_ilike, "%test%"}` |
| `:is_nil` | Is NULL | `{:deleted_at, :is_nil, nil}` |
| `:not_nil` | Is not NULL | `{:email, :not_nil, nil}` |
| `:between` | Between range | `{:price, :between, {10, 100}}` |
| `:contains` | Array contains | `{:tags, :contains, ["featured"]}` |
| `:contained_by` | Array contained by | `{:tags, :contained_by, [...]}` |
| `:jsonb_contains` | JSONB contains | `{:metadata, :jsonb_contains, %{key: "value"}}` |
| `:jsonb_has_key` | JSONB has key | `{:metadata, :jsonb_has_key, "featured"}` |

## Joins

### Basic Joins

```elixir
# Inner join (default)
Query.new(Product)
|> Query.join(:category)
|> Query.where({:category, :name, "Electronics"})
|> Repo.all()

# Left join
Query.new(Product)
|> Query.join(:category, :left)
|> Repo.all()

# Right join
Query.new(Product)
|> Query.join(:category, :right)
|> Repo.all()
```

### Many-to-Many Joins (Through Associations)

When you have a many-to-many relationship through a join table, the Query builder provides three ways to handle it:

**Schema Setup:**
```elixir
defmodule Product do
  schema "products" do
    has_many :product_tags, ProductTag
    has_many :tags, through: [:product_tags, :tag]
  end
end

defmodule ProductTag do
  schema "product_tags" do
    belongs_to :product, Product
    belongs_to :tag, Tag
    field :type, :string  # Custom field on join table
  end
end
```

#### Option 1: Auto-Detection

The builder automatically detects `through:` associations and creates bindings for both tables:

```elixir
# Simple many-to-many join (auto-detected)
Query.new(Product)
|> Query.join(:tags)
|> Query.where({:tags, :name, "red"})
|> Repo.all()

# Filter on BOTH the join table AND the final table
Query.new(Product)
|> Query.join(:tags)
|> Query.where({:product_tags, :type, "featured"})  # Filter join table
|> Query.where({:tags, :name, "red"})  # Filter final table
|> Repo.all()
```

#### Option 2: Explicit Through (Recommended)

Use the `through:` option for clarity and inline filtering:

```elixir
# Explicit through specification
Query.new(Product)
|> Query.join(:tags, through: :product_tags)
|> Query.where({:tags, :name, "red"})
|> Repo.all()

# With inline filtering on join table
Query.new(Product)
|> Query.join(:tags, through: :product_tags, where: {:type, "featured"})
|> Query.where({:tags, :name, "red"})
|> Repo.all()

# Multiple filters on join table
Query.new(Product)
|> Query.join(:tags,
     through: :product_tags,
     where: [
       {:type, "featured"},
       {:active, true}
     ]
   )
|> Query.where({:tags, :name, :in, ["red", "green", "blue"]})
|> Repo.all()

# Left join with through
Query.new(Product)
|> Query.join(:tags, type: :left, through: :product_tags, where: {:type, "featured"})
|> Repo.all()
```

#### Option 3: Keyword Syntax

```elixir
# Clean keyword syntax
Query.new(Product, [
  join: :tags,
  filters: [
    {:product_tags, :type, "featured"},
    {:tags, :name, "red"}
  ]
]) |> Repo.all()
```

### Alternative: join_through/3 Function

The `join_through/3` function is still available but `join(:tags, through: :product_tags)` is now the recommended approach:

```elixir
# Using join_through (alternative syntax)
Query.new(Product)
|> Query.join_through(:tags,
     through: :product_tags,
     where: {:type, "featured"}
   )
|> Query.where({:tags, :name, "red"})
|> Repo.all()

# Recommended: use join with through: option instead
Query.new(Product)
|> Query.join(:tags, through: :product_tags, where: {:type, "featured"})
|> Query.where({:tags, :name, "red"})
|> Repo.all()
```

### Filtering on Joined Tables

```elixir
# Filter on main table AND joined table
Query.new(Product)
|> Query.where(status: "active")  # Main table
|> Query.join(:category)
|> Query.where({:category, :name, "Electronics"})  # Joined table
|> Query.where({:category, :active, true})  # Another joined filter
|> Repo.all()

# With operators on joined tables
Query.new(Product)
|> Query.join(:category)
|> Query.where({:category, :priority, :gt, 5})
|> Repo.all()
```

### Multiple Joins

```elixir
Query.new(Product)
|> Query.join(:category)
|> Query.join(:brand)
|> Query.where({:category, :name, "Electronics"})
|> Query.where({:brand, :name, "ACME"})
|> Repo.all()
```

## Query Building

### Pipe Syntax

```elixir
products = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.where({:price, :gte, 10})
  |> Query.where({:price, :lte, 100})
  |> Query.order_by(desc: :inserted_at)
  |> Query.limit(20)
  |> Query.offset(40)
  |> Repo.all()
```

### Keyword Syntax

```elixir
# Using multiple where: options
products = Query.new(Product, [
  where: [status: "active"],
  where: {:price, :gte, 10},
  where: {:price, :lte, 100},
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
])
|> Repo.all()

# Using filters: option (recommended for multiple filters)
products = Query.new(Product, [
  filters: [
    status: "active",
    {:price, :gte, 10},
    {:price, :lte, 100}
  ],
  order_by: [desc: :inserted_at],
  limit: 20,
  offset: 40
])
|> Repo.all()

# Filters with options (case sensitivity, include_nil, etc.)
products = Query.new(Product, [
  filters: [
    {:name, :ilike, "%widget%", case_sensitive: false},
    {:description, :like, "%premium%"},
    {:email, :eq, nil, include_nil: true}
  ],
  limit: 10
])
|> Repo.all()

# Filters on join tables
products = Query.new(Product, [
  join: :category,
  filters: [
    status: "active",
    {:category, :name, "Electronics"},
    {:category, :active, true}
  ],
  order_by: [desc: :inserted_at],
  limit: 10
])
|> Repo.all()

# Complex multi-join filters with options
products = Query.new(Product, [
  join: :category,
  join: :brand,
  filters: [
    status: "active",
    {:price, :between, {100, 1000}},
    {:category, :name, :in, ["Electronics", "Gadgets"]},
    {:brand, :country, "USA"},
    {:name, :ilike, "%pro%", case_sensitive: false}
  ],
  order_by: [desc: :popularity],
  limit: 20
])
|> Repo.all()
```

### Mixed Syntax

```elixir
# Start with keyword, continue with pipe
products = Query.new(Product, [
  where: [status: "active"],
  limit: 10
])
|> Query.where({:price, :gt, 100})
|> Query.order_by(desc: :price)
|> Repo.all()
```

## Preloads

### Basic Preloads

```elixir
# Simple preload
Query.new(Product)
|> Query.preload([:category, :tags, :user])
|> Repo.all()

# In keyword syntax
Query.new(Product, preload: [:category, :tags])
|> Repo.all()
```

### Conditional Preloads

Preload with filtering, ordering, and limiting on associated records:

```elixir
# Preload only active tags
Query.new(Product)
|> Query.preload([
  tags: [where: [active: true]]
])
|> Repo.all()

# Preload latest 5 comments
Query.new(Product)
|> Query.preload([
  comments: [
    where: [approved: true],
    order_by: [desc: :inserted_at],
    limit: 5
  ]
])
|> Repo.all()

# Mix conditional and basic preloads
Query.new(Product)
|> Query.preload([
  :category,  # Simple preload
  :user,      # Simple preload
  tags: [where: [active: true], order_by: [asc: :name]],  # Conditional
  reviews: [where: [rating: {:gte, 4}], order_by: [desc: :inserted_at]]
])
|> Repo.all()
```

### Nested Preloads with Conditions

```elixir
# Preload category with its active parent
Query.new(Product)
|> Query.preload([
  category: [
    where: [active: true],
    preload: [:parent]
  ]
])
|> Repo.all()

# Complex nested preloads
Query.new(Product)
|> Query.preload([
  category: [
    where: [active: true],
    preload: [
      parent: [where: [active: true]],
      :translations
    ]
  ],
  tags: [
    where: [active: true],
    order_by: [asc: :priority],
    preload: [:translations]
  ]
])
|> Repo.all()
```

### Using Ecto.Query for Preloads

For complex cases, use raw Ecto queries:

```elixir
import Ecto.Query

Query.new(Product)
|> Query.preload([
  tags: from(t in Tag, where: t.active == true, order_by: t.name),
  comments: from(c in Comment, where: c.approved == true, limit: 10)
])
|> Repo.all()
```

### Keyword Syntax with Conditional Preloads

```elixir
Query.new(Product, [
  where: [status: "active"],
  preload: [
    :category,
    tags: [where: [active: true]],
    reviews: [
      where: [approved: true],
      order_by: [desc: :rating],
      limit: 5
    ]
  ],
  order_by: [desc: :inserted_at],
  limit: 10
]) |> Repo.all()
```

## Advanced Queries

### Distinct

Get unique results:

```elixir
# Distinct on all fields
Query.new(Product)
|> Query.where(status: "active")
|> Query.distinct(true)
|> Repo.all()

# Distinct on specific fields
Query.new(Product)
|> Query.distinct([:category_id, :status])
|> Repo.all()

# In keyword syntax
Query.new(Product, [
  where: [status: "active"],
  distinct: true
]) |> Repo.all()
```

### Group By and Having

Aggregate and filter grouped results:

```elixir
# Group by single field
Query.new(Product)
|> Query.group_by(:category_id)
|> Repo.all()

# Group by multiple fields
Query.new(Product)
|> Query.group_by([:category_id, :status])
|> Repo.all()

# Group by with HAVING clause
Query.new(Product)
|> Query.group_by(:category_id)
|> Query.having([count: {:gt, 5}])
|> Repo.all()

# Using SQL fragment for complex having
Query.new(Product)
|> Query.group_by(:category_id)
|> Query.having("count(*) > ? AND avg(price) > ?", [5, 100])
|> Repo.all()

# Keyword syntax
Query.new(Product, [
  group_by: :category_id,
  having: [count: {:gt, 5}]
]) |> Repo.all()
```

### Real-World Group By Examples

```elixir
# Count products per category
Query.new(Product)
|> Query.where(status: "active")
|> Query.group_by(:category_id)
|> Repo.all()
|> Enum.map(fn product ->
  %{category_id: product.category_id, count: Repo.aggregate(query, :count)}
end)

# Categories with more than 10 products
Query.new(Product)
|> Query.group_by(:category_id)
|> Query.having([count: {:gt, 10}])
|> Repo.all()

# Find tags used on multiple products
Query.new(Product)
|> Query.join(:tags)
|> Query.group_by([{:tags, :id}])
|> Query.having([count: {:gt, 1}])
|> Repo.all()
```

## Window Functions

Window functions perform calculations across a set of rows related to the current row, without collapsing the result set like GROUP BY does.

### Common Window Functions

```elixir
# ROW_NUMBER - assigns unique sequential number
Query.new(Product)
|> Query.window(:w, partition_by: :category_id, order_by: [desc: :price])
|> Query.select(%{
  id: :id,
  name: :name,
  row_number: {:window, :row_number, :w}
})
|> Repo.all()

# RANK - assigns rank with gaps for ties
Query.new(Product)
|> Query.window(:rank_window, partition_by: :category_id, order_by: [desc: :sales])
|> Query.select(%{
  id: :id,
  sales: :sales,
  rank: {:window, :rank, :rank_window}
})
|> Repo.all()

# DENSE_RANK - assigns rank without gaps
Query.new(Product)
|> Query.window(:w, partition_by: :category_id, order_by: [desc: :rating])
|> Query.select(%{
  id: :id,
  rating: :rating,
  dense_rank: {:window, :dense_rank, :w}
})
|> Repo.all()
```

### Inline Window Definitions

You can define windows inline without pre-declaring them:

```elixir
# Inline window definition
Query.new(Product)
|> Query.select(%{
  id: :id,
  name: :name,
  row_number: {:window, :row_number, [partition_by: :category_id, order_by: [desc: :price]]}
})
|> Repo.all()
```

### Aggregate Functions as Windows

```elixir
# Running totals
Query.new(Order)
|> Query.window(:running, order_by: [asc: :inserted_at])
|> Query.select(%{
  id: :id,
  amount: :amount,
  running_total: {:window, {:sum, :amount}, :running}
})
|> Repo.all()

# Moving averages
Query.new(Product)
|> Query.window(:w, partition_by: :category_id, order_by: [asc: :inserted_at])
|> Query.select(%{
  id: :id,
  price: :price,
  avg_price: {:window, {:avg, :price}, :w}
})
|> Repo.all()

# Count within partitions
Query.new(Product)
|> Query.window(:category_window, partition_by: :category_id)
|> Query.select(%{
  id: :id,
  category_id: :category_id,
  products_in_category: {:window, {:count, :id}, :category_window}
})
|> Repo.all()
```

### Lead and Lag Functions

Access values from preceding or following rows:

```elixir
# Compare with next price
Query.new(Product)
|> Query.window(:w, partition_by: :category_id, order_by: [asc: :price])
|> Query.select(%{
  id: :id,
  price: :price,
  next_price: {:window, {:lead, :price}, :w},
  prev_price: {:window, {:lag, :price}, :w}
})
|> Repo.all()

# First and last values in window
Query.new(Product)
|> Query.window(:w, partition_by: :category_id, order_by: [desc: :inserted_at])
|> Query.select(%{
  id: :id,
  price: :price,
  first_price: {:window, {:first_value, :price}, :w},
  last_price: {:window, {:last_value, :price}, :w}
})
|> Repo.all()
```

### Multiple Windows

Define and use multiple windows in a single query:

```elixir
Query.new(Product)
|> Query.window(:price_rank, partition_by: :category_id, order_by: [desc: :price])
|> Query.window(:date_rank, partition_by: :category_id, order_by: [desc: :inserted_at])
|> Query.select(%{
  id: :id,
  name: :name,
  price_rank: {:window, :rank, :price_rank},
  recency_rank: {:window, :rank, :date_rank}
})
|> Repo.all()
```

### Real-World Examples

#### Top N Per Category

```elixir
# Get top 3 products per category by price
Query.new(Product)
|> Query.window(:rank_window, partition_by: :category_id, order_by: [desc: :price])
|> Query.select(%{
  id: :id,
  name: :name,
  category_id: :category_id,
  price: :price,
  rank: {:window, :rank, :rank_window}
})
|> Repo.all()
|> Enum.filter(fn product -> product.rank <= 3 end)
```

#### Sales Comparison

```elixir
# Compare each month's sales to previous month
Query.new(MonthlySales)
|> Query.window(:w, order_by: [asc: :month])
|> Query.select(%{
  month: :month,
  sales: :sales,
  prev_month_sales: {:window, {:lag, :sales}, :w},
  growth: {:window, {:lead, :sales}, :w}
})
|> Repo.all()
```

## Subqueries

Subqueries allow you to use the result of one query within another query.

### Subquery in WHERE Clause

#### IN Subquery

```elixir
# Find orders for active products
active_product_ids = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.select([:id])

Query.new(Order)
|> Query.where_in_subquery(:product_id, active_product_ids)
|> Repo.all()

# NOT IN - orders for inactive products
Query.new(Order)
|> Query.where_not_in_subquery(:product_id, active_product_ids)
|> Repo.all()
```

#### EXISTS Subquery

```elixir
# Find categories that have products
products_subquery = Query.new(Product)
  |> Query.where(dynamic([p, parent: c], p.category_id == c.id))

Query.new(Category)
|> Query.where_exists(products_subquery)
|> Repo.all()

# NOT EXISTS - categories without products
Query.new(Category)
|> Query.where_not_exists(products_subquery)
|> Repo.all()
```

### Subquery in FROM Clause

Use a subquery as the source table:

```elixir
# Build filtered subquery
active_products = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.where({:price, :gt, 100})
  |> Query.select([:id, :name, :category_id, :price])

# Use as FROM clause
Query.from_subquery(active_products, :products)
|> Query.where({:products, :price, :lt, 500})
|> Query.order_by([desc: :price])
|> Repo.all()
```

### Subquery in SELECT Clause

Add scalar subqueries (single value) to your SELECT:

```elixir
# Add product count to each category
product_count = Query.new(Product)
  |> Query.where(dynamic([p, parent: c], p.category_id == c.id))
  |> Query.select(fragment("count(*)"))

Query.new(Category)
|> Query.select([:id, :name])
|> Query.select_subquery(:product_count, product_count)
|> Repo.all()

# Multiple scalar subqueries
active_count = Query.new(Product)
  |> Query.where(dynamic([p, parent: c], p.category_id == c.id and p.status == "active"))
  |> Query.select(fragment("count(*)"))

inactive_count = Query.new(Product)
  |> Query.where(dynamic([p, parent: c], p.category_id == c.id and p.status == "inactive"))
  |> Query.select(fragment("count(*)"))

Query.new(Category)
|> Query.select([:id, :name])
|> Query.select_subquery(:active_products, active_count)
|> Query.select_subquery(:inactive_products, inactive_count)
|> Repo.all()
```

### Real-World Subquery Examples

#### Find Users with No Orders

```elixir
users_with_orders = Query.new(Order)
  |> Query.select([:user_id])
  |> Query.distinct(true)

Query.new(User)
|> Query.where_not_in_subquery(:id, users_with_orders)
|> Repo.all()
```

#### Products Never Ordered

```elixir
ordered_product_ids = Query.new(OrderItem)
  |> Query.select([:product_id])
  |> Query.distinct(true)

Query.new(Product)
|> Query.where_not_in_subquery(:id, ordered_product_ids)
|> Repo.all()
```

#### Categories with High-Value Products

```elixir
high_value_category_ids = Query.new(Product)
  |> Query.where({:price, :gt, 1000})
  |> Query.select([:category_id])
  |> Query.distinct(true)

Query.new(Category)
|> Query.where_in_subquery(:id, high_value_category_ids)
|> Repo.all()
```

#### Complex Filtering with Subqueries

```elixir
# Find products in categories that have at least 10 products
categories_with_many_products = Query.new(Product)
  |> Query.group_by(:category_id)
  |> Query.having("count(*) >= ?", [10])
  |> Query.select([:category_id])

Query.new(Product)
|> Query.where_in_subquery(:category_id, categories_with_many_products)
|> Query.order_by(desc: :inserted_at)
|> Repo.all()
```

#### Subquery with Aggregation

```elixir
# Find products priced above their category average
avg_price_by_category = from p in Product,
  group_by: p.category_id,
  select: %{category_id: p.category_id, avg_price: avg(p.price)}

expensive_products = Query.new(Product)
|> Query.join(:category)
|> Query.where(
  dynamic([p],
    p.price > subquery(
      from ap in subquery(avg_price_by_category),
      where: ap.category_id == parent_as(:products).category_id,
      select: ap.avg_price
    )
  )
)
|> Repo.all()
```

## Execution

### With Repo Functions

```elixir
# All records
products = Query.new(Product)
  |> Query.where(status: "active")
  |> Repo.all()

# One record
product = Query.new(Product)
  |> Query.where(slug: "my-product")
  |> Repo.one()

# One record (raises if not found)
product = Query.new(Product)
  |> Query.where(id: id)
  |> Repo.one!()

# Count
count = Query.new(Product)
  |> Query.where(status: "active")
  |> Repo.aggregate(:count)

# Exists?
exists = Query.new(Product)
  |> Query.where(slug: "my-product")
  |> Repo.exists?()
```

### Convert to Ecto.Query

```elixir
# Get the underlying Ecto.Query
ecto_query = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.to_query()

# Use with any Ecto functions
Repo.all(ecto_query)
Repo.stream(ecto_query)
```

### Get SQL

```elixir
# For debugging or logging
{sql, params} = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.where({:price, :gt, 100})
  |> Query.to_sql()

IO.puts(sql)
# => SELECT p0.* FROM products AS p0 WHERE (p0.deleted_at IS NULL) AND (p0.status = $1) AND (p0.price > $2)

IO.inspect(params)
# => ["active", 100]
```

### Inspect Query (Human-Readable)

```elixir
# Get human-readable Ecto query representation
query_str = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.join(:tags, through: :product_tags, where: {:type, "featured"})
  |> Query.inspect()

IO.puts(query_str)
# Prints formatted Ecto.Query struct with all details
```

## CRUD Operations

### Insert

```elixir
{:ok, product} = Query.insert(Product, %{
  name: "Widget",
  price: 9.99,
  status: "active"
}, created_by: user_id)
```

### Update

```elixir
# Update single record
{:ok, product} = Query.update(product, %{
  price: 12.99
}, updated_by: user_id)

# Update all matching query
{:ok, count} = Query.new(Product)
  |> Query.where(status: "draft")
  |> Query.update_all([set: [status: "published"]], updated_by: user_id)
```

### Delete

```elixir
# Soft delete (default)
{:ok, product} = Query.delete(product, deleted_by: user_id)

# Hard delete (permanent)
{:ok, product} = Query.delete(product, hard: true)

# Delete all matching query
{:ok, count} = Query.new(Product)
  |> Query.where(status: "draft")
  |> Query.delete_all(deleted_by: user_id)

# Hard delete all
{:ok, count} = Query.new(Product)
  |> Query.where(status: "old")
  |> Query.delete_all(hard: true)
```

## Soft Delete

### Default Behavior

By default, all queries exclude soft-deleted records:

```elixir
# Only returns non-deleted products
products = Query.new(Product)
  |> Query.where(status: "active")
  |> Repo.all()
```

### Including Deleted Records

```elixir
# Include soft-deleted records
products = Query.new(Product, include_deleted: true)
  |> Query.where(status: "active")
  |> Repo.all()

# Or with pipe
products = Query.new(Product)
  |> Query.include_deleted()
  |> Query.where(status: "active")
  |> Repo.all()
```

### Lifecycle

```elixir
# Create
{:ok, product} = Query.insert(Product, %{name: "Widget"}, created_by: user_id)

# Soft delete
{:ok, deleted} = Query.delete(product, deleted_by: user_id)
# deleted.deleted_at => ~U[2024-01-15 10:30:00]
# deleted.deleted_by_urm_id => user_id

# Query won't find it (soft-deleted)
Query.new(Product) |> Query.where(id: product.id) |> Repo.one()
# => nil

# Unless we include deleted
Query.new(Product, include_deleted: true)
|> Query.where(id: product.id)
|> Repo.one()
# => %Product{deleted_at: ~U[...]}
```

## Complex Examples

### E-Commerce Product Search

```elixir
def search_products(params) do
  query = Query.new(Product)

  query = if params[:category] do
    query
    |> Query.join(:category)
    |> Query.where({:category, :slug, params[:category]})
  else
    query
  end

  query = if params[:min_price] do
    Query.where(query, {:price, :gte, params[:min_price]})
  else
    query
  end

  query = if params[:max_price] do
    Query.where(query, {:price, :lte, params[:max_price]})
  else
    query
  end

  query = if params[:search] do
    Query.where(query, {:name, :ilike, "%#{params[:search]}%"})
  else
    query
  end

  query
  |> Query.order_by(desc: :inserted_at)
  |> Query.limit(params[:per_page] || 20)
  |> Query.offset((params[:page] || 0) * (params[:per_page] || 20))
  |> Repo.all()
end
```

### Paginated List with Filters

```elixir
def list_products_paginated(filters, page, per_page) do
  base_query = Query.new(Product)

  query = Enum.reduce(filters, base_query, fn
    {:status, status}, acc ->
      Query.where(acc, status: status)

    {:type, type}, acc ->
      Query.where(acc, type: type)

    {:min_price, min}, acc ->
      Query.where(acc, {:price, :gte, min})

    {:max_price, max}, acc ->
      Query.where(acc, {:price, :lte, max})

    {:category_id, cat_id}, acc ->
      acc
      |> Query.join(:category)
      |> Query.where({:category, :id, cat_id})

    _, acc -> acc
  end)

  products = query
    |> Query.order_by(desc: :inserted_at)
    |> Query.limit(per_page)
    |> Query.offset((page - 1) * per_page)
    |> Repo.all()

  total = query |> Repo.aggregate(:count)

  %{
    entries: products,
    page: page,
    per_page: per_page,
    total_count: total,
    total_pages: ceil(total / per_page)
  }
end
```

### JSONB Metadata Filtering

```elixir
# Find products with featured flag
Query.new(Product)
|> Query.where({:metadata, :jsonb_contains, %{"featured" => true}})
|> Repo.all()

# Find products with video_url in metadata
Query.new(Product)
|> Query.where({:metadata, :jsonb_has_key, "video_url"})
|> Repo.all()
```

### Multi-Table Search

```elixir
Query.new(Product)
|> Query.join(:category)
|> Query.join(:brand)
|> Query.where(status: "active")
|> Query.where({:category, :name, "Electronics"})
|> Query.where({:brand, :country, "USA"})
|> Query.where({:price, :between, {100, 500}})
|> Query.order_by([desc: :popularity, asc: :price])
|> Query.limit(10)
|> Repo.all()
```

### Many-to-Many with Join Table Filtering

Real-world example: Find non-deleted products with specific tags and tag types.

```elixir
# Products with "red" tag that are marked as "featured" type
# Option 1: Auto-detection with separate filters
Query.new(Product)
|> Query.join(:tags)
|> Query.where({:product_tags, :type, "featured"})
|> Query.where({:tags, :name, "red"})
|> Repo.all()

# Option 2: Explicit through with inline filter (recommended)
Query.new(Product)
|> Query.join(:tags, through: :product_tags, where: {:type, "featured"})
|> Query.where({:tags, :name, "red"})
|> Repo.all()

# Products with multiple tag colors, all must be "primary" type
Query.new(Product)
|> Query.join(:tags, through: :product_tags, where: {:type, "primary"})
|> Query.where({:tags, :name, :in, ["red", "green", "blue"]})
|> Repo.all()

# Multiple filters on join table - very clean
Query.new(Product)
|> Query.join(:tags,
     through: :product_tags,
     where: [
       {:type, "featured"},
       {:active, true}
     ]
   )
|> Query.where({:tags, :name, :in, ["red", "green", "blue"]})
|> Query.order_by(desc: :inserted_at)
|> Repo.all()

# Keyword syntax - extremely clean
Query.new(Product, [
  join: :tags,
  filters: [
    status: "active",
    {:product_tags, :type, "featured"},
    {:product_tags, :active, true},
    {:tags, :name, :in, ["red", "green", "blue"]}
  ],
  order_by: [desc: :inserted_at],
  limit: 20
]) |> Repo.all()

# Function to search by tag with options
def find_products_by_tags(tag_names, tag_type \\ nil) do
  query = Query.new(Product)

  # Use explicit through when filtering join table
  query = if tag_type do
    Query.join(query, :tags, through: :product_tags, where: {:type, tag_type})
  else
    Query.join(query, :tags)
  end

  query
  |> Query.where({:tags, :name, :in, tag_names})
  |> Repo.all()
end

# Usage
find_products_by_tags(["red", "green"], "featured")
find_products_by_tags(["red", "green"])  # Any type
```

## Context Pattern

```elixir
defmodule Events.Products do
  alias Events.Product
  alias Events.Repo
  alias Events.Repo.Query

  def list_products(filters \\ []) do
    build_query(filters)
    |> Repo.all()
  end

  def list_products_paginated(filters, page, per_page) do
    query = build_query(filters)

    products = query
      |> Query.limit(per_page)
      |> Query.offset((page - 1) * per_page)
      |> Repo.all()

    total = query |> Repo.aggregate(:count)

    %{
      entries: products,
      page: page,
      per_page: per_page,
      total_count: total,
      total_pages: ceil(total / per_page)
    }
  end

  def get_product(id) do
    case Query.new(Product)
         |> Query.where(id: id)
         |> Repo.one() do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  def create_product(attrs, opts \\ []) do
    Query.insert(Product, attrs, opts)
  end

  def update_product(product, attrs, opts \\ []) do
    Query.update(product, attrs, opts)
  end

  def delete_product(product, opts \\ []) do
    Query.delete(product, opts)
  end

  def publish_products(product_ids, user_id) do
    Query.new(Product)
    |> Query.where({:id, :in, product_ids})
    |> Query.where(status: "draft")
    |> Query.update_all([set: [status: "published"]], updated_by: user_id)
  end

  # Private

  defp build_query(filters) do
    Enum.reduce(filters, Query.new(Product), fn
      {:status, status}, acc ->
        Query.where(acc, status: status)

      {:type, type}, acc ->
        Query.where(acc, type: type)

      {:price_min, min}, acc ->
        Query.where(acc, {:price, :gte, min})

      {:price_max, max}, acc ->
        Query.where(acc, {:price, :lte, max})

      {:search, term}, acc ->
        Query.where(acc, {:name, :ilike, "%#{term}%"})

      {:category, category}, acc ->
        acc
        |> Query.join(:category)
        |> Query.where({:category, :slug, category})

      {:order, order}, acc ->
        Query.order_by(acc, order)

      _, acc -> acc
    end)
  end
end
```

## Best Practices

### 1. Use Smart Defaults

```elixir
# ✅ Good - let Query infer the operation
Query.where(query, status: "active")
Query.where(query, tags: ["featured", "new"])

# ❌ Unnecessary - operation is inferred
Query.where(query, {:status, :eq, "active"})
Query.where(query, {:tags, :in, ["featured", "new"]})
```

### 2. Compose Filters

```elixir
# ✅ Good - build filters incrementally
def build_query(filters) do
  Enum.reduce(filters, Query.new(Product), fn filter, acc ->
    apply_filter(acc, filter)
  end)
end

defp apply_filter(query, {:status, status}), do: Query.where(query, status: status)
defp apply_filter(query, {:min_price, min}), do: Query.where(query, {:price, :gte, min})
defp apply_filter(query, _), do: query
```

### 3. Use to_sql() for Debugging

```elixir
# ✅ Good - inspect generated SQL during development
query = Query.new(Product)
  |> Query.where(status: "active")
  |> Query.join(:category)

{sql, params} = Query.to_sql(query)
IO.puts("\nSQL: #{sql}")
IO.inspect(params, label: "Params")
```

### 4. Always Use Audit Fields

```elixir
# ✅ Good
Query.insert(Product, attrs, created_by: user_id)
Query.update(product, attrs, updated_by: user_id)
Query.delete(product, deleted_by: user_id)

# ❌ Bad - no audit trail
Query.insert(Product, attrs)
Query.update(product, attrs)
```

### 5. Prefer Soft Delete

```elixir
# ✅ Good - preserves data
Query.delete(product, deleted_by: user_id)

# ⚠️ Use sparingly - permanent
Query.delete(product, hard: true)
```

## Summary

The Query API provides:

- **Builder pattern** with `Query.new/2`
- **Smart filters** with `{field, op, value, opts}`
- **Join support** with filters on joined tables (including many-to-many)
- **Soft delete** by default
- **Window functions** for advanced analytics (ROW_NUMBER, RANK, LEAD, LAG, etc.)
- **Subqueries** for complex filtering (IN, EXISTS, FROM, SELECT)
- **Conditional preloads** with filters and ordering
- **Aggregation** with GROUP BY, HAVING, DISTINCT
- **Dual syntax** - keyword and pipe
- **Final execution** - `Repo.all()`, `Repo.one()`, `to_sql()`

**Build queries naturally. Filter intelligently. Analyze powerfully. Execute simply.**
