# Events.CRUD - Architectural Guidelines

## Overview

Events.CRUD is a composable, enterprise-grade database operations system designed for applications with 100+ schemas. This document outlines the architectural patterns and guidelines for extending and maintaining the system.

## Core Principles

### 1. **Composition over Inheritance**
- Operations are composed using tokens, not inherited
- Behavior is defined through protocols and behaviors
- Extensibility through plugins and custom operations

### 2. **Pattern Matching First**
- Heavy use of pattern matching for operation dispatch
- Validation through pattern matching
- Error handling through pattern matching

### 3. **Protocol-Based Design**
- Query builders use protocols for different strategies
- Operations categorized by behavior protocols
- Extensible through protocol implementations

### 4. **Token-Based Architecture**
- All operations flow through tokens
- Tokens provide composition, validation, and introspection
- Immutable token transformations

## Architectural Layers

```
┌─────────────────────────────────────┐
│         Application Layer           │
│  - Business Logic                   │
│  - DSL Usage                        │
│  - Custom Operations                │
├─────────────────────────────────────┤
│         CRUD System Layer           │
│  - Token Management                 │
│  - Operation Dispatch               │
│  - Query Building                   │
│  - Result Handling                  │
├─────────────────────────────────────┤
│         Foundation Layer            │
│  - Behaviors & Protocols            │
│  - Validation System                │
│  - Configuration                    │
│  - Error Handling                   │
├─────────────────────────────────────┤
│         Infrastructure Layer        │
│  - Ecto Integration                 │
│  - Database Adapters                │
│  - Connection Pooling               │
└─────────────────────────────────────┘
```

## Adding New Operations

### Step 1: Define Operation Category

Choose the appropriate behavior:

```elixir
# For read operations
defmodule MyApp.Operations.CustomQuery do
  use Events.CRUD.Operation.Query
  # ...
end

# For write operations
defmodule MyApp.Operations.CustomMutation do
  use Events.CRUD.Operation.Mutation
  # ...
end
```

### Step 2: Implement Required Callbacks

```elixir
@impl true
def validate_spec(spec) do
  # Use OperationUtils for consistent validation
  OperationUtils.validate_spec(spec, [
    field: &OperationUtils.validate_field/1,
    value: &validate_custom_value/1
  ])
end

@impl true
def execute(query, spec) do
  # Implement operation logic
  # Return modified Ecto.Query
end

@impl true
def optimize(spec, context) do
  # Optional: implement optimization logic
  spec
end
```

### Step 3: Register Operation

Add to validation mapping:

```elixir
# In your application startup
Events.CRUD.Validation.add_operation_mapping(:custom_operation, MyApp.Operations.CustomQuery)
```

### Step 4: Add DSL Support (Optional)

```elixir
# In your DSL extension
defmacro custom_operation(token, arg1, arg2) do
  quote do
    Events.CRUD.Token.add(unquote(token), {:custom_operation, {unquote(arg1), unquote(arg2)}})
  end
end
```

## Operation Categories

### Query Operations
- **Purpose**: Read data from database
- **Characteristics**:
  - Safe to reorder
  - No data modification
  - Can be cached
  - Can be optimized
- **Examples**: `where`, `join`, `order`, `preload`, `select`

### Mutation Operations
- **Purpose**: Modify data in database
- **Characteristics**:
  - Cannot be reordered
  - Modify data
  - Not cacheable
  - Require transactions
- **Examples**: `create`, `update`, `delete`

### Utility Operations
- **Purpose**: Provide debugging, monitoring, or control flow
- **Characteristics**:
  - Side effects only
  - Can be reordered
  - No data impact
- **Examples**: `debug`, `log`, `validate`

## Token Patterns

### Basic Composition

```elixir
# Sequential composition
token = Events.CRUD.Token.new()
        |> Events.CRUD.Token.where(:status, :eq, "active")
        |> Events.CRUD.Token.order(:created_at, :desc)
        |> Events.CRUD.Token.limit(10)

# Parallel composition
token1 = Events.CRUD.Token.where(Events.CRUD.Token.new(), :status, :eq, "active")
token2 = Events.CRUD.Token.order(Events.CRUD.Token.new(), :created_at, :desc)
combined = Events.CRUD.Token.merge(token1, token2)
```

### Advanced Patterns

```elixir
# Conditional composition
token = if admin? do
  Events.CRUD.Token.add(token, {:preload, {:admin_permissions, []}})
else
  token
end

# Dynamic composition
filters = [status: "active", role: "admin"]
token = Enum.reduce(filters, Events.CRUD.Token.new(), fn {field, value}, acc ->
  Events.CRUD.Token.where(acc, field, :eq, value)
end)
```

## Protocol Implementation Guidelines

### QueryBuilder Protocol

```elixir
defimpl Events.CRUD.QueryBuilder, for: MyCustomBuilder do
  def build(token) do
    # Custom query building logic
    # Return {:ok, query} or {:error, reason}
  end

  def optimize(token) do
    # Custom optimization logic
    # Return optimized token
  end

  def execute(query) do
    # Custom execution logic
    # Return Events.CRUD.Result
  end

  def complexity(token) do
    # Estimate query complexity
    # Return non_neg_integer()
  end
end
```

## Error Handling Patterns

### Validation Errors

```elixir
# Use OperationUtils for consistent error messages
{:error, OperationUtils.error(:invalid_field, "username")}
{:error, OperationUtils.error(:unsupported_operator, "custom_op")}
{:error, OperationUtils.error(:type_mismatch, {"field", "atom"})}
```

### Execution Errors

```elixir
# Wrap database errors
try do
  Repo.all(query)
rescue
  error -> Events.CRUD.Result.error("Database error: #{inspect(error)}")
end
```

### Result Pattern

```elixir
# Always return Events.CRUD.Result structs
%Events.CRUD.Result{
  success: true,
  data: result_data,
  error: nil,
  metadata: %{...}
}
```

## Testing Guidelines

### Unit Tests

```elixir
describe "MyOperation" do
  test "validates spec correctly" do
    assert {:ok, _} = MyOperation.validate_spec(valid_spec)
    assert {:error, _} = MyOperation.validate_spec(invalid_spec)
  end

  test "executes operation correctly" do
    query = MyOperation.execute(base_query, spec)
    assert %Ecto.Query{} = query
    # Assert query modifications
  end
end
```

### Integration Tests

```elixir
test "full operation pipeline" do
  token = Events.CRUD.Token.new()
          |> Events.CRUD.Token.where(:status, :eq, "active")
          |> Events.CRUD.Token.limit(10)

  result = Events.CRUD.Token.execute(token)

  assert %Events.CRUD.Result{success: true} = result
  assert is_list(result.data)
end
```

## Performance Considerations

### Query Optimization

1. **Filter Early**: Apply WHERE clauses before JOINs
2. **Index Awareness**: Consider available indexes in optimization
3. **Select Minimally**: Only select required fields
4. **Limit Appropriately**: Use pagination for large datasets

### Memory Management

1. **Streaming**: Use cursor pagination for large datasets
2. **Batching**: Process results in chunks
3. **Timeouts**: Set appropriate query timeouts
4. **Connection Pooling**: Efficient database connection usage

### Caching Strategy

1. **Query Result Caching**: Cache frequently accessed data
2. **Prepared Statement Caching**: Reuse query plans
3. **Metadata Caching**: Cache schema information
4. **Invalidation**: Proper cache invalidation on data changes

## Extension Points

### Custom Operations

```elixir
defmodule MyApp.Operations.GeoSearch do
  use Events.CRUD.Operation.Query

  @impl true
  def validate_spec({lat, lng, radius}) do
    # Validate geo coordinates
  end

  @impl true
  def execute(query, {lat, lng, radius}) do
    # Add geo search logic
  end
end
```

### Custom Query Builders

```elixir
defmodule MyApp.ElasticsearchBuilder do
  @behaviour Events.CRUD.QueryBuilder

  # Implement for Elasticsearch integration
end
```

### Plugin System

```elixir
defmodule MyApp.AnalyticsPlugin do
  @behaviour Events.CRUD.Plugin

  @impl true
  def plugin_info do
    %{
      name: :analytics,
      operations: [:analytics_query, :metrics],
      hooks: [
        before_execute: &track_query/1,
        after_execute: &track_performance/1
      ],
      version: "1.0.0"
    }
  end
end
```

## Migration Strategy

### From Raw Ecto

```elixir
# Old
from(u in User, where: u.active == true, limit: 10)

# New
query User do
  where :active, :eq, true
  limit 10
end
```

### From Repo Operations

```elixir
# Old
Repo.all(User)
Repo.get(User, 1)

# New
list User, do: []
get User, 1
```

### Gradual Migration

1. **Phase 1**: Use Events.CRUD for new queries
2. **Phase 2**: Migrate complex queries to Events.CRUD
3. **Phase 3**: Replace simple Repo calls
4. **Phase 4**: Full migration with custom operations

## Best Practices

### Code Organization

1. **One Operation Per File**: Keep operations focused
2. **Consistent Naming**: Follow `OperationName` pattern
3. **Clear Documentation**: Document behavior and examples
4. **Type Specifications**: Use comprehensive `@spec` annotations

### Performance

1. **Profile Queries**: Use debug operations to identify bottlenecks
2. **Optimize Selectively**: Only optimize performance-critical paths
3. **Monitor Usage**: Track query patterns and performance
4. **Cache Wisely**: Cache read-heavy operations

### Maintainability

1. **Version Operations**: Track operation versions
2. **Deprecation Path**: Provide migration paths for breaking changes
3. **Testing Coverage**: Comprehensive test coverage for all operations
4. **Documentation Updates**: Keep documentation current

This architectural guideline ensures Events.CRUD remains maintainable, extensible, and performant as your application grows to 100+ schemas.