# Pure Function Verification with Decorators

## How Pure Function Verification Works

The `@decorate pure()` decorator verifies function purity through **two mechanisms**:

### 1. **Compile-Time Static Analysis** (when `strict: true`)
- Analyzes the function's AST (Abstract Syntax Tree)
- Detects potentially impure operations
- Issues warnings during compilation

### 2. **Runtime Verification** (when `verify: true`)
- Takes state snapshots before/after execution
- Runs the function multiple times with same inputs
- Verifies deterministic output and no state changes

## Verification Process

### Step 1: Compile-Time Checking (`strict: true`)

The decorator scans the function's AST for impure operations:

```elixir
defp find_impure_calls(ast) do
  # Detects:
  # - IO operations (IO.puts, IO.inspect, etc.)
  # - Process operations (Process.send, spawn, etc.)
  # - System calls (System.get_env, etc.)
  # - Message passing (send/receive)
  # - Random number generation (:rand)
  # - ETS operations
  # - Database calls
end
```

**What it catches:**
- `IO.*` - Any IO operations
- `Process.*` - Process manipulation
- `System.*` - System interactions
- `send/receive` - Message passing
- `:rand.*` - Random number generation
- `:ets.*` - ETS table operations

### Step 2: Runtime Verification (`verify: true`)

When enabled, the decorator wraps your function with verification logic:

```elixir
# 1. Capture initial state
initial_state = %{
  process_dict: Process.get(),
  message_queue_len: Process.info(self(), :message_queue_len)
}

# 2. Run function multiple times (default: 3)
results = for _ <- 1..samples, do: your_function(args)

# 3. Check all results are identical (determinism)
first_result = hd(results)
all_same = Enum.all?(results, &(&1 == first_result))

# 4. Capture final state
final_state = %{...}

# 5. Verify state unchanged
if initial_state != final_state do
  raise "Purity violation: State was modified"
end

if not all_same do
  raise "Purity violation: Non-deterministic results"
end
```

## Usage Examples

### Example 1: Pure Function - Passes All Checks

```elixir
defmodule MathOperations do
  use Events.Decorator

  # This passes both compile-time and runtime checks
  @decorate pure(verify: true, strict: true)
  def add(a, b) do
    a + b
  end

  # Pure recursive function
  @decorate pure(verify: true, strict: true, samples: 5)
  def factorial(0), do: 1
  def factorial(n) when n > 0 do
    n * factorial(n - 1)
  end

  # Pure data transformation
  @decorate pure(verify: true)
  def transform_user_data(user_map) do
    %{
      name: String.upcase(user_map.name),
      age: user_map.age,
      email: String.downcase(user_map.email)
    }
  end
end
```

### Example 2: Impure Function - Fails Compile-Time Check

```elixir
defmodule ImpureOperations do
  use Events.Decorator

  # FAILS: IO operations detected at compile-time
  @decorate pure(strict: true)
  def calculate_with_logging(x, y) do
    IO.puts("Calculating...")  # <- Impure: IO operation
    x + y
  end
  # Compile warning: "Function may not be pure. Found potentially impure operations: [:io]"

  # FAILS: Random number generation
  @decorate pure(strict: true)
  def random_calculation(x) do
    x + :rand.uniform(100)  # <- Impure: random number
  end
  # Compile warning: "Found potentially impure operations: [:random]"

  # FAILS: Process dictionary modification
  @decorate pure(verify: true)
  def modify_process_dict(x) do
    Process.put(:counter, x)  # <- Impure: modifies state
    x * 2
  end
  # Runtime error: "Purity violation: State was modified"
end
```

### Example 3: Allowing IO for Logging

```elixir
defmodule DebugOperations do
  use Events.Decorator

  # Allow IO operations (for logging/debugging)
  @decorate pure(verify: true, strict: true, allow_io: true)
  def calculate_with_debug(x, y) do
    Logger.debug("Inputs: #{x}, #{y}")  # Allowed with allow_io: true
    result = x * y
    Logger.debug("Result: #{result}")
    result  # Still deterministic despite logging
  end
end
```

### Example 4: Non-Deterministic Function Detection

```elixir
defmodule NonDeterministic do
  use Events.Decorator

  # FAILS: Returns different results for same input
  @decorate pure(verify: true, samples: 10)
  def unstable_function(x) do
    # Timestamp makes it non-deterministic
    %{
      value: x,
      processed_at: DateTime.utc_now()  # <- Different each call
    }
  end
  # Runtime error: "Purity violation: Non-deterministic results"

  # FAILS: Uses external state
  @decorate pure(verify: true)
  def depends_on_config(x) do
    multiplier = Application.get_env(:my_app, :multiplier, 1)
    x * multiplier  # Result depends on application config
  end
end
```

### Example 5: Complex Purity Verification

```elixir
defmodule ComplexPurity do
  use Events.Decorator

  # Verify complex nested structure purity
  @decorate pure(verify: true, samples: 5)
  def deep_transformation(nested_map) do
    nested_map
    |> Map.update(:users, [], &Enum.sort_by(&1, & &1.name))
    |> Map.update(:counts, %{}, &Map.new(&1, fn {k, v} -> {k, v * 2} end))
    |> Map.put(:version, "1.0.0")  # Static value - OK
  end

  # Database operations are impure
  @decorate pure(strict: true)
  def fetch_from_db(id) do
    Repo.get(User, id)  # <- Impure: database access
  end
  # Compile warning: "Found potentially impure operations: [:repo]"
end
```

## Options Explained

| Option | Purpose | Default | Example |
|--------|---------|---------|---------|
| `verify` | Enable runtime verification | `false` | `@decorate pure(verify: true)` |
| `strict` | Enable compile-time checking | `false` | `@decorate pure(strict: true)` |
| `allow_io` | Allow IO operations (logging) | `false` | `@decorate pure(allow_io: true)` |
| `samples` | Number of times to run for verification | `3` | `@decorate pure(samples: 10)` |

## What Makes a Function Pure?

A pure function must:

1. **Always return the same output for the same input** (Deterministic)
2. **Have no side effects** (No state modification)
3. **Not depend on external state** (Self-contained)

### ✅ Pure Operations

```elixir
# Mathematical operations
def add(a, b), do: a + b

# String manipulation
def format_name(first, last), do: "#{first} #{last}"

# Data transformations
def map_values(list), do: Enum.map(list, &(&1 * 2))

# Pattern matching
def get_status({:ok, value}), do: :success
def get_status({:error, _}), do: :failure
```

### ❌ Impure Operations

```elixir
# IO operations
def print_value(x), do: IO.puts(x)

# State modification
def increment_counter, do: Agent.update(:counter, &(&1 + 1))

# Random values
def random_id, do: :rand.uniform(1000)

# Current time
def timestamp, do: DateTime.utc_now()

# Database access
def get_user(id), do: Repo.get(User, id)

# External API calls
def fetch_weather, do: HTTPoison.get("api.weather.com")

# Message passing
def notify(pid, msg), do: send(pid, msg)
```

## Best Practices

### 1. Use Both Checks in Development

```elixir
# Maximum verification during development
if Mix.env() in [:dev, :test] do
  @decorate pure(verify: true, strict: true, samples: 10)
else
  @decorate pure()  # Documentation only in production
end
```

### 2. Separate Pure and Impure Parts

```elixir
# Impure wrapper
def process_user_with_logging(user_data) do
  Logger.info("Processing user: #{user_data.id}")

  # Call pure function for actual logic
  result = pure_user_transformation(user_data)

  Logger.info("Processing complete")
  result
end

# Pure function
@decorate pure(verify: true, strict: true)
defp pure_user_transformation(user_data) do
  # Pure transformation logic here
  %{user_data | processed: true}
end
```

### 3. Test Purity in Your Test Suite

```elixir
defmodule MathTest do
  use ExUnit.Case

  test "add function is pure" do
    # The decorator will verify purity automatically
    assert MathOperations.add(2, 3) == 5
    assert MathOperations.add(2, 3) == 5  # Same result
    assert MathOperations.add(2, 3) == 5  # Always same
  end
end
```

### 4. Use for Documentation Even Without Verification

```elixir
# Even without verification, it documents intent
@decorate pure()
def calculate_discount(price, percentage) do
  price * (1 - percentage / 100)
end
```

## Common Patterns

### Pattern 1: Pure Calculations with Logging

```elixir
@decorate pure(verify: true, allow_io: true)
def complex_calculation(data) do
  Logger.debug("Starting calculation", data: data)

  result = data
  |> step_one()
  |> step_two()
  |> step_three()

  Logger.debug("Calculation complete", result: result)
  result
end
```

### Pattern 2: Memoization Candidate

```elixir
# First verify it's pure
@decorate pure(verify: true, strict: true)
def expensive_pure_function(input) do
  # Complex but pure calculation
end

# Then add caching
@decorate compose([
  {:pure, [verify: true]},
  {:cacheable, [cache: MyCache, ttl: :infinity]}
])
def cached_pure_function(input) do
  expensive_pure_function(input)
end
```

### Pattern 3: Property-Based Testing

```elixir
@decorate pure(verify: true, samples: 100)
def sort_and_reverse(list) do
  list |> Enum.sort() |> Enum.reverse()
end

# In tests - property: always produces same result
property "sort_and_reverse is deterministic" do
  check all list <- list_of(integer()) do
    result1 = sort_and_reverse(list)
    result2 = sort_and_reverse(list)
    assert result1 == result2
  end
end
```

## Troubleshooting

### Issue: "Function may not be pure" but you think it is

**Solution**: Check for hidden impure operations:
- Calling other functions that aren't pure
- Using Date/DateTime.utc_now()
- Accessing Application config
- Using Process dictionary

### Issue: Runtime verification passes but compile-time fails

**Solution**: Use `allow_io: true` if the impure operations are only for debugging/logging and don't affect determinism.

### Issue: "Non-deterministic results" with seemingly pure function

**Solution**: Check for:
- Map ordering issues (maps don't guarantee order)
- Floating-point precision issues
- Hidden timestamps or IDs
- External function calls

## Summary

The pure function verification in your decorator system provides:

1. **Compile-time safety** - Catches obvious impurity during compilation
2. **Runtime verification** - Proves determinism and state immutability
3. **Documentation** - Clear intent even without verification
4. **Flexibility** - Allow IO for logging while maintaining logical purity
5. **Development aid** - Helps refactor code to be more functional

Use `@decorate pure()` to document intent, add `verify: true` for runtime checking, and `strict: true` for compile-time analysis. This multi-layered approach ensures your pure functions truly are pure!