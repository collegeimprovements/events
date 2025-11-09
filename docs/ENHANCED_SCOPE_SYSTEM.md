# Enhanced Dynamic Scope & Constraint System

## Overview

A comprehensive system for building:
- **Partial indexes** with complex WHERE clauses
- **Check constraints** for data validation
- **Unique constraints** (single and composite)
- **Nested JSONB paths** (`metadata[:field1][:field2]`)
- **JSONB array operations**
- **Multi-column constraints**

---

## Table of Contents

1. [Scope Builder (Partial Indexes)](#1-scope-builder-partial-indexes)
2. [Check Constraints](#2-check-constraints)
3. [Unique Constraints](#3-unique-constraints)
4. [Nested JSONB Support](#4-nested-jsonb-support)
5. [Composite Constraints](#5-composite-constraints)
6. [Complete Examples](#6-complete-examples)

---

## 1. Scope Builder (Partial Indexes)

### Enhanced JSONB Support

#### Nested Path Access

```elixir
# Access nested JSONB fields
Scope.metadata_path(["settings", "notifications", "email"], "enabled")
# => metadata->'settings'->'notifications'->>'email' = 'enabled'

Scope.metadata_path_eq(["user", "preferences", "theme"], "dark")
# => metadata->'user'->'preferences'->>'theme' = 'dark'

# Numeric comparison on nested path
Scope.metadata_path_compare(["limits", "api", "rate"], :>, 1000)
# => (metadata->'limits'->'api'->>'rate')::int > 1000

# Check if nested path exists
Scope.metadata_path_exists(["settings", "advanced"])
# => metadata->'settings' ? 'advanced'
```

#### JSONB Array Operations

```elixir
# Array contains value
Scope.metadata_array_contains("tags", "featured")
# => metadata->'tags' @> '["featured"]'

# Array contains any of values
Scope.metadata_array_contains_any("tags", ["new", "featured", "trending"])
# => metadata->'tags' ?| array['new', 'featured', 'trending']

# Array contains all values
Scope.metadata_array_contains_all("tags", ["featured", "verified"])
# => metadata->'tags' ?& array['featured', 'verified']

# Array length comparison
Scope.metadata_array_length("tags", :>, 3)
# => jsonb_array_length(metadata->'tags') > 3

# Array element access
Scope.metadata_array_element("tags", 0, "featured")
# => metadata->'tags'->0 = '"featured"'
```

#### Advanced JSONB Operators

```elixir
# Deep path with multiple levels
Scope.metadata_deep_path(["user", "address", "country", "code"], "US")
# => metadata#>>'{user,address,country,code}' = 'US'

# JSONB key exists at any level
Scope.metadata_has_key("premium")
# => metadata ? 'premium'

# Check if JSONB is contained by another
Scope.metadata_contained_by(%{status: "active"})
# => metadata <@ '{"status":"active"}'

# JSONB keys exist
Scope.metadata_has_keys(["email", "phone", "address"])
# => metadata ?& array['email', 'phone', 'address']

# JSONB has any key
Scope.metadata_has_any_key(["email", "phone"])
# => metadata ?| array['email', 'phone']
```

---

## 2. Check Constraints

### Check Constraint Builder

```elixir
defmodule Events.Repo.CheckConstraint do
  @moduledoc """
  Builder for check constraints with chainable API.

  ## Examples

      # Simple check
      CheckConstraint.new(:price_positive)
      |> CheckConstraint.check(:price, :>, 0)
      |> CheckConstraint.to_sql()
      # => "price > 0"

      # Complex check
      CheckConstraint.new(:valid_date_range)
      |> CheckConstraint.check(:starts_at, :<, :ends_at)
      |> CheckConstraint.to_sql()
      # => "starts_at < ends_at"
  """

  defstruct name: nil, conditions: []

  # Basic field comparisons
  def check(constraint, field, operator, value) when is_atom(field) do
    add_condition(constraint, {:check, field, operator, value})
  end

  # Field to field comparison
  def check_fields(constraint, field1, operator, field2) do
    add_condition(constraint, {:check_fields, field1, operator, field2})
  end

  # Value in list
  def check_in(constraint, field, values) when is_list(values) do
    add_condition(constraint, {:check_in, field, values})
  end

  # Value not in list
  def check_not_in(constraint, field, values) when is_list(values) do
    add_condition(constraint, {:check_not_in, field, values})
  end

  # Pattern matching
  def check_like(constraint, field, pattern) do
    add_condition(constraint, {:check_like, field, pattern})
  end

  # Length constraints
  def check_length(constraint, field, operator, length) do
    add_condition(constraint, {:check_length, field, operator, length})
  end

  # NOT NULL check
  def check_not_null(constraint, field) do
    add_condition(constraint, {:check_not_null, field})
  end

  # Range check
  def check_between(constraint, field, min, max) do
    add_condition(constraint, {:check_between, field, min, max})
  end

  # JSONB checks
  def check_jsonb_exists(constraint, path) when is_list(path) do
    add_condition(constraint, {:check_jsonb_exists, path})
  end

  def check_jsonb_type(constraint, path, type) when is_list(path) do
    # type can be: "string", "number", "boolean", "object", "array"
    add_condition(constraint, {:check_jsonb_type, path, type})
  end

  # Array checks
  def check_array_length(constraint, field, operator, length) do
    add_condition(constraint, {:check_array_length, field, operator, length})
  end

  # Logical operators
  def check_and(constraint, checks) when is_list(checks) do
    add_condition(constraint, {:and, checks})
  end

  def check_or(constraint, checks) when is_list(checks) do
    add_condition(constraint, {:or, checks})
  end

  # Raw SQL
  def check_raw(constraint, sql) when is_binary(sql) do
    add_condition(constraint, {:raw, sql})
  end

  # Common patterns
  def positive(constraint, field), do: check(constraint, field, :>, 0)
  def negative(constraint, field), do: check(constraint, field, :<, 0)
  def non_negative(constraint, field), do: check(constraint, field, :>=, 0)
  def non_positive(constraint, field), do: check(constraint, field, :<=, 0)

  def percentage(constraint, field) do
    constraint
    |> check(field, :>=, 0)
    |> check(field, :<=, 100)
  end

  def email_format(constraint, field) do
    check_like(constraint, field, "%_@_%.__%")
  end

  def url_format(constraint, field) do
    check_raw(constraint, "#{field} ~* '^https?://'")
  end

  def valid_date_range(constraint, start_field, end_field) do
    check_fields(constraint, start_field, :<=, end_field)
  end

  # Generate SQL
  def to_sql(%__MODULE__{conditions: conditions}) do
    conditions
    |> Enum.reverse()
    |> Enum.map(&condition_to_sql/1)
    |> Enum.join(" AND ")
  end

  defp condition_to_sql({:check, field, operator, value}) do
    "#{field} #{op_to_sql(operator)} #{format_value(value)}"
  end

  defp condition_to_sql({:check_fields, field1, operator, field2}) do
    "#{field1} #{op_to_sql(operator)} #{field2}"
  end

  defp condition_to_sql({:check_in, field, values}) do
    formatted = Enum.map(values, &format_value/1) |> Enum.join(", ")
    "#{field} IN (#{formatted})"
  end

  defp condition_to_sql({:check_not_in, field, values}) do
    formatted = Enum.map(values, &format_value/1) |> Enum.join(", ")
    "#{field} NOT IN (#{formatted})"
  end

  defp condition_to_sql({:check_like, field, pattern}) do
    "#{field} LIKE '#{escape_sql(pattern)}'"
  end

  defp condition_to_sql({:check_length, field, operator, length}) do
    "length(#{field}) #{op_to_sql(operator)} #{length}"
  end

  defp condition_to_sql({:check_not_null, field}) do
    "#{field} IS NOT NULL"
  end

  defp condition_to_sql({:check_between, field, min, max}) do
    "#{field} BETWEEN #{format_value(min)} AND #{format_value(max)}"
  end

  defp condition_to_sql({:check_jsonb_exists, path}) do
    path_str = Enum.join(path, ",")
    "metadata#>>'{#{path_str}}' IS NOT NULL"
  end

  defp condition_to_sql({:check_jsonb_type, path, type}) do
    path_str = Enum.join(path, "->")
    "jsonb_typeof(metadata->'#{path_str}') = '#{type}'"
  end

  defp condition_to_sql({:check_array_length, field, operator, length}) do
    "array_length(#{field}, 1) #{op_to_sql(operator)} #{length}"
  end

  defp condition_to_sql({:and, checks}) do
    inner = Enum.map(checks, &to_sql/1) |> Enum.join(" AND ")
    "(#{inner})"
  end

  defp condition_to_sql({:or, checks}) do
    inner = Enum.map(checks, &to_sql/1) |> Enum.join(" OR ")
    "(#{inner})"
  end

  defp condition_to_sql({:raw, sql}), do: sql

  defp add_condition(%__MODULE__{conditions: conditions} = constraint, condition) do
    %{constraint | conditions: [condition | conditions]}
  end

  defp op_to_sql(:>), do: ">"
  defp op_to_sql(:<), do: "<"
  defp op_to_sql(:>=), do: ">="
  defp op_to_sql(:<=), do: "<="
  defp op_to_sql(:==), do: "="
  defp op_to_sql(:!=), do: "!="

  defp format_value(value) when is_binary(value), do: "'#{escape_sql(value)}'"
  defp format_value(value) when is_number(value), do: "#{value}"
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"

  defp escape_sql(value), do: String.replace(value, "'", "''")
end
```

### Usage in Migrations

```elixir
defmodule Events.Repo.Migrations.AddCheckConstraints do
  use Ecto.Migration
  alias Events.Repo.CheckConstraint

  def change do
    # Price must be positive
    create constraint(:products, :price_positive,
      check: CheckConstraint.new(:price_positive)
             |> CheckConstraint.positive(:price)
             |> CheckConstraint.to_sql()
    )

    # Discount percentage between 0 and 100
    create constraint(:products, :valid_discount,
      check: CheckConstraint.new(:valid_discount)
             |> CheckConstraint.percentage(:discount_percent)
             |> CheckConstraint.to_sql()
    )

    # Date range validation
    create constraint(:events, :valid_date_range,
      check: CheckConstraint.new(:valid_date_range)
             |> CheckConstraint.valid_date_range(:starts_at, :ends_at)
             |> CheckConstraint.to_sql()
    )

    # Status must be in list
    create constraint(:products, :valid_status,
      check: CheckConstraint.new(:valid_status)
             |> CheckConstraint.check_in(:status, ["draft", "published", "archived"])
             |> CheckConstraint.to_sql()
    )

    # Email format validation
    create constraint(:users, :valid_email,
      check: CheckConstraint.new(:valid_email)
             |> CheckConstraint.email_format(:email)
             |> CheckConstraint.to_sql()
    )

    # Stock quantity non-negative
    create constraint(:products, :stock_non_negative,
      check: CheckConstraint.new(:stock_non_negative)
             |> CheckConstraint.non_negative(:stock_quantity)
             |> CheckConstraint.to_sql()
    )

    # Complex: Price or sale price must be positive
    create constraint(:products, :positive_pricing,
      check: CheckConstraint.new(:positive_pricing)
             |> CheckConstraint.check_or([
               CheckConstraint.new() |> CheckConstraint.positive(:price),
               CheckConstraint.new() |> CheckConstraint.positive(:sale_price)
             ])
             |> CheckConstraint.to_sql()
    )

    # JSONB validation
    create constraint(:products, :valid_metadata_priority,
      check: CheckConstraint.new(:valid_metadata_priority)
             |> CheckConstraint.check_raw(
               "(metadata->>'priority')::int BETWEEN 1 AND 10"
             )
             |> CheckConstraint.to_sql()
    )
  end
end
```

---

## 3. Unique Constraints

### Single Column Unique Constraints

```elixir
defmodule Events.Repo.Migrations.AddUniqueConstraints do
  use Ecto.Migration
  import Events.Repo.MigrationMacros

  def change do
    # Simple unique constraint
    create unique_index(:users, [:email])

    # Unique with scope (partial)
    create unique_index(:users, [:email],
      where: "deleted_at IS NULL"
    )

    # Case-insensitive unique
    create unique_index(:users, ["lower(username)"],
      name: :unique_username_case_insensitive
    )
  end
end
```

### Composite Unique Constraints

```elixir
defmodule Events.Repo.Migrations.AddCompositeUniqueConstraints do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.Scope

  def change do
    # Composite unique: user_id + role_id
    create unique_index(:user_roles, [:user_id, :role_id])

    # Composite unique with scope
    create unique_index(:user_roles, [:user_id, :role_id],
      where: "deleted_at IS NULL"
    )

    # Using Scope builder
    create unique_index(:user_roles, [:user_id, :role_id],
      where: Scope.new() |> Scope.active() |> Scope.to_sql()
    )

    # Composite unique: slug per organization
    create unique_index(:products, [:organization_id, :slug],
      where: "deleted_at IS NULL",
      name: :unique_product_slug_per_org
    )

    # Composite unique: type + status combination
    create unique_index(:settings, [:type, :status],
      where: "deleted_at IS NULL AND type = 'global'"
    )

    # Multi-column with partial index
    create unique_index(:events, [:organization_id, :slug, :year],
      where: Scope.new()
             |> Scope.active()
             |> Scope.status("published")
             |> Scope.to_sql()
    )
  end
end
```

### Unique Constraint Helper Macro

```elixir
# Add to migration_macros.ex

@doc """
Creates a unique constraint with optional partial index.

## Options

- `:scope` - Partial index scope
- `:name` - Custom constraint name
- `:where` - Custom WHERE clause (deprecated, use :scope)

## Examples

    # Simple unique
    unique_constraint(:users, :email)

    # Unique with scope
    unique_constraint(:users, :email, scope: Scope.new() |> Scope.active())

    # Composite unique
    unique_constraint(:user_roles, [:user_id, :role_id], scope: :active)

    # Case-insensitive unique
    unique_constraint(:users, "lower(username)", name: :unique_username_ci)
"""
defmacro unique_constraint(table, columns, opts \\ []) do
  quote bind_quoted: [table: table, columns: columns, opts: opts] do
    scope = Keyword.get(opts, :scope)
    where_clause = Events.Repo.MigrationMacros.__resolve_scope__(scope)

    index_opts =
      opts
      |> Keyword.drop([:scope])
      |> Events.Repo.MigrationMacros.__maybe_add_where__(where_clause)

    columns_list = if is_list(columns), do: columns, else: [columns]

    create unique_index(table, columns_list, index_opts)
  end
end
```

---

## 4. Nested JSONB Support

### Deep Path Access

```elixir
# Enhanced Scope module with nested JSONB support

defmodule Events.Repo.Scope do
  # ... existing code ...

  @doc """
  Access nested JSONB path and compare value.

  ## Examples

      # metadata.settings.notifications.email = "enabled"
      metadata_path_eq(["settings", "notifications", "email"], "enabled")
      # => metadata->'settings'->'notifications'->>'email' = 'enabled'

      # metadata.user.preferences.theme = "dark"
      metadata_path_eq(["user", "preferences", "theme"], "dark")
  """
  def metadata_path_eq(%__MODULE__{} = scope, path, value) when is_list(path) do
    add_condition(scope, {:jsonb_path_eq, path, value})
  end

  @doc """
  Numeric comparison on nested JSONB path.

  ## Examples

      # metadata.limits.api.rate > 1000
      metadata_path_compare(["limits", "api", "rate"], :>, 1000)
      # => (metadata->'limits'->'api'->>'rate')::int > 1000
  """
  def metadata_path_compare(%__MODULE__{} = scope, path, operator, value, type \\ :int)
      when is_list(path) and operator in [:>, :<, :>=, :<=, :==, :!=] do
    add_condition(scope, {:jsonb_path_compare, path, operator, value, type})
  end

  @doc """
  Check if nested JSONB path exists.

  ## Examples

      # metadata.settings.advanced exists
      metadata_path_exists(["settings", "advanced"])
      # => metadata->'settings' ? 'advanced'
  """
  def metadata_path_exists(%__MODULE__{} = scope, path) when is_list(path) do
    add_condition(scope, {:jsonb_path_exists, path})
  end

  @doc """
  Check if nested path is not null.

  ## Examples

      metadata_path_not_null(["user", "address", "country"])
      # => metadata#>>'{user,address,country}' IS NOT NULL
  """
  def metadata_path_not_null(%__MODULE__{} = scope, path) when is_list(path) do
    add_condition(scope, {:jsonb_path_not_null, path})
  end

  @doc """
  Access using PostgreSQL #>> operator for deep paths.

  ## Examples

      # metadata#>>'{user,address,country,code}' = 'US'
      metadata_deep_path(["user", "address", "country", "code"], "US")
  """
  def metadata_deep_path(%__MODULE__{} = scope, path, value) when is_list(path) do
    add_condition(scope, {:jsonb_deep_path, path, value})
  end

  # SQL generation for nested JSONB

  defp condition_to_sql({:jsonb_path_eq, path, value}) do
    path_navigation = build_jsonb_path(path)
    "#{path_navigation} = #{format_value(value)}"
  end

  defp condition_to_sql({:jsonb_path_compare, path, operator, value, type}) do
    path_navigation = build_jsonb_path(path)
    op_str = operator_to_sql(operator)
    "(#{path_navigation})::#{type} #{op_str} #{value}"
  end

  defp condition_to_sql({:jsonb_path_exists, path}) do
    parent_path = Enum.slice(path, 0..-2//1)
    key = List.last(path)

    if parent_path == [] do
      "metadata ? '#{escape_sql(key)}'"
    else
      parent_navigation = build_jsonb_path_navigation(parent_path)
      "metadata#{parent_navigation} ? '#{escape_sql(key)}'"
    end
  end

  defp condition_to_sql({:jsonb_path_not_null, path}) do
    path_str = Enum.map(path, &escape_sql/1) |> Enum.join(",")
    "metadata#>>'{#{path_str}}' IS NOT NULL"
  end

  defp condition_to_sql({:jsonb_deep_path, path, value}) do
    path_str = Enum.map(path, &escape_sql/1) |> Enum.join(",")
    "metadata#>>'{#{path_str}}' = #{format_value(value)}"
  end

  # Helper to build JSONB path navigation
  # ["settings", "notifications", "email"] => ->'settings'->'notifications'->>'email'
  defp build_jsonb_path([]), do: "metadata"
  defp build_jsonb_path(path) do
    {parent_path, [last]} = Enum.split(path, -1)

    parent = if parent_path == [] do
      "metadata"
    else
      parent_nav = Enum.map(parent_path, &"'#{escape_sql(&1)}'") |> Enum.join("->")
      "metadata->#{parent_nav}"
    end

    "#{parent}->>'#{escape_sql(last)}'"
  end

  # Helper for exists check
  defp build_jsonb_path_navigation([]), do: ""
  defp build_jsonb_path_navigation(path) do
    "->" <> (Enum.map(path, &"'#{escape_sql(&1)}'") |> Enum.join("->"))
  end
end
```

### JSONB Array Operations

```elixir
# Add to Scope module

@doc """
JSONB array contains value.

## Examples

    # metadata.tags contains "featured"
    metadata_array_contains("tags", "featured")
    # => metadata->'tags' @> '["featured"]'
"""
def metadata_array_contains(%__MODULE__{} = scope, key, value) do
  add_condition(scope, {:jsonb_array_contains, key, value})
end

@doc """
JSONB array contains any of the values.

## Examples

    metadata_array_contains_any("tags", ["new", "featured"])
    # => metadata->'tags' ?| array['new', 'featured']
"""
def metadata_array_contains_any(%__MODULE__{} = scope, key, values) when is_list(values) do
  add_condition(scope, {:jsonb_array_contains_any, key, values})
end

@doc """
JSONB array contains all values.

## Examples

    metadata_array_contains_all("tags", ["featured", "verified"])
    # => metadata->'tags' ?& array['featured', 'verified']
"""
def metadata_array_contains_all(%__MODULE__{} = scope, key, values) when is_list(values) do
  add_condition(scope, {:jsonb_array_contains_all, key, values})
end

@doc """
JSONB array length comparison.

## Examples

    metadata_array_length("tags", :>, 3)
    # => jsonb_array_length(metadata->'tags') > 3
"""
def metadata_array_length(%__MODULE__{} = scope, key, operator, length)
    when operator in [:>, :<, :>=, :<=, :==, :!=] do
  add_condition(scope, {:jsonb_array_length, key, operator, length})
end

@doc """
Access JSONB array element by index.

## Examples

    metadata_array_element("tags", 0, "featured")
    # => metadata->'tags'->0 = '"featured"'
"""
def metadata_array_element(%__MODULE__{} = scope, key, index, value) do
  add_condition(scope, {:jsonb_array_element, key, index, value})
end

# SQL generation

defp condition_to_sql({:jsonb_array_contains, key, value}) do
  json_value = Jason.encode!([value])
  "metadata->'#{escape_sql(key)}' @> '#{json_value}'"
end

defp condition_to_sql({:jsonb_array_contains_any, key, values}) do
  array_str = Enum.map(values, &"'#{escape_sql(&1)}'") |> Enum.join(", ")
  "metadata->'#{escape_sql(key)}' ?| array[#{array_str}]"
end

defp condition_to_sql({:jsonb_array_contains_all, key, values}) do
  array_str = Enum.map(values, &"'#{escape_sql(&1)}'") |> Enum.join(", ")
  "metadata->'#{escape_sql(key)}' ?& array[#{array_str}]"
end

defp condition_to_sql({:jsonb_array_length, key, operator, length}) do
  op_str = operator_to_sql(operator)
  "jsonb_array_length(metadata->'#{escape_sql(key)}') #{op_str} #{length}"
end

defp condition_to_sql({:jsonb_array_element, key, index, value}) do
  "metadata->'#{escape_sql(key)}'->#{index} = '\"#{escape_sql(value)}\"'"
end
```

---

## 5. Composite Constraints

### Multi-Column Check Constraints

```elixir
# Complex business rules across multiple columns

create constraint(:products, :valid_pricing,
  check: CheckConstraint.new(:valid_pricing)
         |> CheckConstraint.check_or([
           # Either regular price exists
           CheckConstraint.new() |> CheckConstraint.check_not_null(:price),
           # Or sale price exists and is less than regular price
           CheckConstraint.new()
           |> CheckConstraint.check_not_null(:sale_price)
           |> CheckConstraint.check_fields(:sale_price, :<, :price)
         ])
         |> CheckConstraint.to_sql()
)

# Stock validation
create constraint(:products, :stock_consistency,
  check: CheckConstraint.new(:stock_consistency)
         |> CheckConstraint.check_raw(
           "stock_quantity >= reserved_quantity"
         )
         |> CheckConstraint.to_sql()
)

# Date range with duration
create constraint(:events, :valid_event_duration,
  check: CheckConstraint.new(:valid_event_duration)
         |> CheckConstraint.valid_date_range(:starts_at, :ends_at)
         |> CheckConstraint.check_raw(
           "EXTRACT(EPOCH FROM (ends_at - starts_at)) <= 86400" # Max 24 hours
         )
         |> CheckConstraint.to_sql()
)
```

### Conditional Constraints

```elixir
# If type is 'premium', then price must be > 100
create constraint(:products, :premium_pricing,
  check: CheckConstraint.new(:premium_pricing)
         |> CheckConstraint.check_raw(
           "type != 'premium' OR price > 100"
         )
         |> CheckConstraint.to_sql()
)

# If status is 'published', published_at must not be null
create constraint(:posts, :published_requires_date,
  check: CheckConstraint.new(:published_requires_date)
         |> CheckConstraint.check_raw(
           "status != 'published' OR published_at IS NOT NULL"
         )
         |> CheckConstraint.to_sql()
)

# Exclusive fields: either email or phone must be present
create constraint(:users, :contact_required,
  check: CheckConstraint.new(:contact_required)
         |> CheckConstraint.check_raw(
           "email IS NOT NULL OR phone IS NOT NULL"
         )
         |> CheckConstraint.to_sql()
)
```

---

## 6. Complete Examples

### E-commerce Product Table

```elixir
defmodule Events.Repo.Migrations.CreateProducts do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.{Scope, CheckConstraint}

  def change do
    create table(:products) do
      name_fields()
      status_field()
      type_fields()

      add :price, :decimal, precision: 10, scale: 2
      add :sale_price, :decimal, precision: 10, scale: 2
      add :cost, :decimal, precision: 10, scale: 2
      add :stock_quantity, :integer, default: 0
      add :reserved_quantity, :integer, default: 0
      add :min_order_quantity, :integer, default: 1
      add :max_order_quantity, :integer
      add :weight, :decimal
      add :visibility, :citext, default: "public"

      metadata_field()
      audit_fields()
      deleted_fields()
      timestamps()
    end

    # ========================================
    # UNIQUE CONSTRAINTS
    # ========================================

    # Unique slug per organization (if you have multi-tenancy)
    create unique_index(:products, [:slug],
      where: Scope.new() |> Scope.active() |> Scope.to_sql(),
      name: :unique_product_slug
    )

    # Unique SKU
    create unique_index(:products, [:sku],
      where: "deleted_at IS NULL AND sku IS NOT NULL"
    )

    # ========================================
    # CHECK CONSTRAINTS
    # ========================================

    # Price must be positive
    create constraint(:products, :price_positive,
      check: CheckConstraint.new(:price_positive)
             |> CheckConstraint.positive(:price)
             |> CheckConstraint.to_sql()
    )

    # Sale price less than regular price
    create constraint(:products, :sale_price_valid,
      check: CheckConstraint.new(:sale_price_valid)
             |> CheckConstraint.check_raw(
               "sale_price IS NULL OR sale_price < price"
             )
             |> CheckConstraint.to_sql()
    )

    # Cost less than price (profit margin)
    create constraint(:products, :profitable,
      check: CheckConstraint.new(:profitable)
             |> CheckConstraint.check_raw(
               "cost IS NULL OR cost < price"
             )
             |> CheckConstraint.to_sql()
    )

    # Stock quantities non-negative
    create constraint(:products, :stock_non_negative,
      check: CheckConstraint.new(:stock_non_negative)
             |> CheckConstraint.non_negative(:stock_quantity)
             |> CheckConstraint.to_sql()
    )

    create constraint(:products, :reserved_non_negative,
      check: CheckConstraint.new(:reserved_non_negative)
             |> CheckConstraint.non_negative(:reserved_quantity)
             |> CheckConstraint.to_sql()
    )

    # Reserved cannot exceed stock
    create constraint(:products, :stock_consistency,
      check: CheckConstraint.new(:stock_consistency)
             |> CheckConstraint.check_fields(:stock_quantity, :>=, :reserved_quantity)
             |> CheckConstraint.to_sql()
    )

    # Order quantity validation
    create constraint(:products, :valid_order_quantities,
      check: CheckConstraint.new(:valid_order_quantities)
             |> CheckConstraint.check_raw(
               "min_order_quantity > 0 AND (max_order_quantity IS NULL OR max_order_quantity >= min_order_quantity)"
             )
             |> CheckConstraint.to_sql()
    )

    # Status values
    create constraint(:products, :valid_status,
      check: CheckConstraint.new(:valid_status)
             |> CheckConstraint.check_in(:status, ["draft", "active", "published", "archived", "discontinued"])
             |> CheckConstraint.to_sql()
    )

    # JSONB validation: priority between 1-10
    create constraint(:products, :valid_priority,
      check: CheckConstraint.new(:valid_priority)
             |> CheckConstraint.check_raw(
               "metadata->>'priority' IS NULL OR (metadata->>'priority')::int BETWEEN 1 AND 10"
             )
             |> CheckConstraint.to_sql()
    )

    # JSONB validation: tags array not empty if exists
    create constraint(:products, :tags_not_empty,
      check: CheckConstraint.new(:tags_not_empty)
             |> CheckConstraint.check_raw(
               "metadata->'tags' IS NULL OR jsonb_array_length(metadata->'tags') > 0"
             )
             |> CheckConstraint.to_sql()
    )

    # ========================================
    # PARTIAL INDEXES (for queries)
    # ========================================

    # Active, published, in-stock products
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.status("published")
      |> Scope.public()
      |> Scope.where_gt(:stock_quantity, 0)
    )

    # Featured products
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.metadata_path_eq(["featured"], "true")
    )

    # Products on sale
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.where_not_null(:sale_price)
    )

    # Low stock alert
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.where_lte(:stock_quantity, 10)
      |> Scope.where_gt(:stock_quantity, 0)
    )

    # Premium products
    name_indexes(:products, scope:
      Scope.new()
      |> Scope.active()
      |> Scope.type("premium")
      |> Scope.metadata_path_compare(["subscription", "tier"], :>=, 2, :int)
    )

    # Products with specific tags
    create index(:products, [],
      where: Scope.new()
             |> Scope.active()
             |> Scope.metadata_array_contains("tags", "bestseller")
             |> Scope.to_sql(),
      name: :idx_products_bestseller_tag
    )
  end
end
```

### User Management System

```elixir
defmodule Events.Repo.Migrations.CreateUsers do
  use Ecto.Migration
  import Events.Repo.MigrationMacros
  alias Events.Repo.{Scope, CheckConstraint}

  def change do
    create table(:users) do
      add :email, :citext
      add :phone, :string
      add :username, :citext, null: false
      add :first_name, :string
      add :last_name, :string
      add :age, :integer
      add :account_type, :citext, default: "standard"

      status_field(default: "pending")
      metadata_field()
      audit_fields()
      deleted_fields()
      timestamps()
    end

    # ========================================
    # UNIQUE CONSTRAINTS
    # ========================================

    # Case-insensitive unique email
    create unique_index(:users, ["lower(email)"],
      where: "deleted_at IS NULL AND email IS NOT NULL",
      name: :unique_user_email
    )

    # Case-insensitive unique username
    create unique_index(:users, ["lower(username)"],
      where: "deleted_at IS NULL",
      name: :unique_username
    )

    # Unique phone (if provided)
    create unique_index(:users, [:phone],
      where: "deleted_at IS NULL AND phone IS NOT NULL",
      name: :unique_user_phone
    )

    # ========================================
    # CHECK CONSTRAINTS
    # ========================================

    # At least one contact method required
    create constraint(:users, :contact_required,
      check: CheckConstraint.new(:contact_required)
             |> CheckConstraint.check_raw("email IS NOT NULL OR phone IS NOT NULL")
             |> CheckConstraint.to_sql()
    )

    # Email format
    create constraint(:users, :valid_email,
      check: CheckConstraint.new(:valid_email)
             |> CheckConstraint.email_format(:email)
             |> CheckConstraint.to_sql()
    )

    # Age constraints
    create constraint(:users, :valid_age,
      check: CheckConstraint.new(:valid_age)
             |> CheckConstraint.check_between(:age, 13, 120)
             |> CheckConstraint.to_sql()
    )

    # Username length
    create constraint(:users, :username_length,
      check: CheckConstraint.new(:username_length)
             |> CheckConstraint.check_length(:username, :>=, 3)
             |> CheckConstraint.to_sql()
    )

    # Account type validation
    create constraint(:users, :valid_account_type,
      check: CheckConstraint.new(:valid_account_type)
             |> CheckConstraint.check_in(:account_type, ["standard", "premium", "enterprise"])
             |> CheckConstraint.to_sql()
    )

    # JSONB: nested preferences validation
    create constraint(:users, :valid_theme_preference,
      check: CheckConstraint.new(:valid_theme_preference)
             |> CheckConstraint.check_raw(
               "metadata#>>'{preferences,theme}' IS NULL OR metadata#>>'{preferences,theme}' IN ('light', 'dark', 'auto')"
             )
             |> CheckConstraint.to_sql()
    )

    # ========================================
    # PARTIAL INDEXES
    # ========================================

    # Active users
    create index(:users, [:email],
      where: Scope.new()
             |> Scope.active()
             |> Scope.status("active")
             |> Scope.to_sql()
    )

    # Premium users
    create index(:users, [:username],
      where: Scope.new()
             |> Scope.active()
             |> Scope.where_in(:account_type, ["premium", "enterprise"])
             |> Scope.to_sql()
    )

    # Users with email notifications enabled
    create index(:users, [:email],
      where: Scope.new()
             |> Scope.active()
             |> Scope.metadata_path_eq(["preferences", "notifications", "email"], "true")
             |> Scope.to_sql(),
      name: :idx_users_email_notifications
    )
  end
end
```

---

## 7. Advanced Patterns

### Multi-Tenant with Composite Constraints

```elixir
create table(:documents) do
  add :organization_id, references(:organizations, type: :uuid), null: false
  title_fields()
  status_field()
  metadata_field()
  deleted_fields()
  timestamps()
end

# Unique slug per organization
create unique_index(:documents, [:organization_id, :slug],
  where: Scope.new() |> Scope.active() |> Scope.to_sql()
)

# Composite check: published documents must have content
create constraint(:documents, :published_has_content,
  check: CheckConstraint.new(:published_has_content)
         |> CheckConstraint.check_raw(
           "status != 'published' OR (metadata->>'word_count')::int > 100"
         )
         |> CheckConstraint.to_sql()
)
```

### Hierarchical Data Validation

```elixir
create table(:categories) do
  name_fields()
  add :parent_id, references(:categories, type: :uuid)
  add :level, :integer, default: 0
  add :path, {:array, :uuid}
  metadata_field()
  deleted_fields()
  timestamps()
end

# Check: level matches path length
create constraint(:categories, :level_matches_path,
  check: CheckConstraint.new(:level_matches_path)
         |> CheckConstraint.check_raw("level = array_length(path, 1)")
         |> CheckConstraint.to_sql()
)

# Check: root categories have no parent
create constraint(:categories, :root_has_no_parent,
  check: CheckConstraint.new(:root_has_no_parent)
         |> CheckConstraint.check_raw(
           "(level = 0 AND parent_id IS NULL) OR (level > 0 AND parent_id IS NOT NULL)"
         )
         |> CheckConstraint.to_sql()
)

# Max nesting level
create constraint(:categories, :max_nesting,
  check: CheckConstraint.new(:max_nesting)
         |> CheckConstraint.check(:level, :<=, 5)
         |> CheckConstraint.to_sql()
)
```

---

## Summary

This enhanced system now supports:

✅ **Check Constraints** - Data validation at database level
✅ **Unique Constraints** - Single and composite, with partial indexes
✅ **Nested JSONB Paths** - `metadata[:field1][:field2]` access
✅ **JSONB Arrays** - Contains, length, element access
✅ **Multi-Column Constraints** - Complex business rules
✅ **Conditional Constraints** - If-then validation logic
✅ **Composite Indexes** - Multi-column unique and partial indexes

### Key Features

- **Type-safe builders** for constraints
- **Chainable API** for complex conditions
- **JSONB path navigation** with multiple levels
- **Array operations** for JSONB arrays
- **SQL generation** from structured data
- **Full integration** with existing migration macros

### Next Steps

Choose which features to implement first based on your needs:
1. Basic check constraints
2. Nested JSONB support
3. Composite unique constraints
4. JSONB array operations
5. Complete integration with migration macros
