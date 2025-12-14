# FnTypes

A comprehensive functional programming library for Elixir providing monadic types, error handling, validation, and retry mechanisms.

## Installation

Add `fn_types` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fn_types, path: "libs/fn_types"}  # Or use hex once published
  ]
end
```

## Core Types

### Result

A monadic type for handling operations that can succeed or fail.

```elixir
alias FnTypes.Result

# Creating results
Result.ok(42)                    # {:ok, 42}
Result.error(:not_found)         # {:error, :not_found}

# Transforming results
{:ok, 5}
|> Result.map(&(&1 * 2))         # {:ok, 10}
|> Result.and_then(&validate/1)  # Chain fallible operations

# Pattern matching helpers
Result.ok?({:ok, _})             # true
Result.error?({:error, _})       # true

# Unwrapping
Result.unwrap_or({:error, _}, 0) # 0 (default value)
```

### Maybe

An option type for handling optional values.

```elixir
alias FnTypes.Maybe

# Creating maybes
Maybe.some(42)           # {:some, 42}
Maybe.none()             # :none

# From nilable values
Maybe.from_nilable(nil)  # :none
Maybe.from_nilable(42)   # {:some, 42}

# Transforming
{:some, 5}
|> Maybe.map(&(&1 * 2))  # {:some, 10}

# Unwrapping
Maybe.unwrap_or({:some, 42}, 0)  # 42
Maybe.unwrap_or(:none, 0)        # 0
```

### Validation

Applicative validation with error accumulation.

```elixir
alias FnTypes.Validation, as: V

# Validate with multiple rules
result = V.validate("test@example.com", [
  V.required(),
  V.min_length(5),
  V.format(:email)
])

# Field validation with context
V.new(%{name: "Alice", age: 25})
|> V.field(:name, [V.required(), V.min_length(2)])
|> V.field(:age, [V.min(18)])
|> V.to_result()
# {:ok, %{name: "Alice", age: 25}}

# Built-in validators
V.required()              # Non-nil, non-empty string
V.min_length(n)           # Minimum length for strings/lists
V.max_length(n)           # Maximum length
V.min(n)                  # Minimum numeric value
V.max(n)                  # Maximum numeric value
V.between(min, max)       # Numeric range
V.format(:email)          # Email format
V.format(:uuid)           # UUID format
V.format(~r/pattern/)     # Custom regex
V.inclusion(list)         # Value must be in list
V.type(:string)           # Type check (:string, :integer, :boolean)
```

### Ior (Inclusive Or)

A type that can hold a left value, right value, or both.

```elixir
alias FnTypes.Ior

Ior.left(:error)           # {:left, :error}
Ior.right(:success)        # {:right, :success}
Ior.both(:warning, :value) # {:both, :warning, :value}

# Useful for accumulating warnings while still producing a result
```

### NonEmptyList

A list guaranteed to have at least one element.

```elixir
alias FnTypes.NonEmptyList, as: NEL

{:ok, nel} = NEL.new([1, 2, 3])  # {:ok, {1, [2, 3]}}
NEL.head(nel)                    # 1
NEL.tail(nel)                    # [2, 3]
NEL.to_list(nel)                 # [1, 2, 3]

# Safe operations that maintain non-empty guarantee
NEL.map(nel, &(&1 * 2))          # {2, [4, 6]}
```

## Error Handling

### Error Struct

A structured error type with rich context.

```elixir
alias FnTypes.Error

error = Error.new(:validation, :invalid_email,
  message: "Email format is invalid",
  details: %{field: :email},
  context: %{user_id: 123},
  recoverable: false
)

# Chain errors
Error.with_context(error, %{request_id: "req_abc"})
Error.with_step(error, :validate_input)

# Get root cause
Error.root_cause(chained_error)

# Normalize various error types
Error.normalize(:not_found)
Error.normalize(%RuntimeError{message: "boom"})
```

### Retry

Retry operations with configurable backoff strategies.

```elixir
alias FnTypes.Retry

# Simple retry
Retry.execute(fn -> api_call() end)

# With options
Retry.execute(fn -> api_call() end,
  max_attempts: 5,
  base_delay: 100,
  max_delay: 5000,
  backoff: :exponential,
  on_retry: fn error, attempt, delay ->
    Logger.warning("Retry #{attempt}: #{inspect(error)}")
  end,
  when: fn error -> match?(%TimeoutError{}, error) end
)

# Backoff strategies
Retry.with_backoff(fn -> api_call() end, :exponential, base: 1000)
Retry.with_backoff(fn -> api_call() end, :linear, base: 500)
Retry.with_backoff(fn -> api_call() end, :fixed, base: 2000)

# Calculate delay for custom use
Retry.calculate_delay(3, :exponential, base: 100)  # 400
```

## Flow Control

### Throttler

Limit execution to once per interval.

```elixir
alias FnTypes.Throttler

{:ok, throttler} = Throttler.start_link(interval: 1000)

# First call executes immediately
Throttler.call(throttler, fn -> update_progress() end)
# {:ok, result}

# Subsequent calls within interval are blocked
Throttler.call(throttler, fn -> update_progress() end)
# {:error, :throttled}

# Check time remaining
Throttler.remaining(throttler)  # 450 (ms until next allowed)

# Reset to allow immediate execution
Throttler.reset(throttler)
```

### Debouncer

Wait for activity to stop before executing.

```elixir
alias FnTypes.Debouncer

{:ok, debouncer} = Debouncer.start_link()

# Only the last call executes after 200ms of quiet
Debouncer.call(debouncer, fn -> search(query1) end, 200)
Debouncer.call(debouncer, fn -> search(query2) end, 200)
Debouncer.call(debouncer, fn -> search(query3) end, 200)
# Only search(query3) runs

# Cancel pending execution
Debouncer.cancel(debouncer)
```

## Protocols

### Normalizable

Normalize any error type to a standard `FnTypes.Error` struct.

```elixir
defimpl FnTypes.Protocols.Normalizable, for: MyApp.APIError do
  def normalize(error, opts) do
    FnTypes.Error.new(:external, :api_error,
      message: error.message,
      details: error.details
    )
  end
end
```

### Recoverable

Define recovery strategies for error types.

```elixir
defimpl FnTypes.Protocols.Recoverable, for: MyApp.TransientError do
  def recoverable?(_), do: true
  def strategy(_), do: :retry_with_backoff
  def retry_delay(_, attempt), do: 100 * :math.pow(2, attempt - 1)
  def max_attempts(_), do: 3
  def trips_circuit?(_), do: false
  def severity(_), do: :transient
  def fallback(_), do: nil
end
```

### Identifiable

Extract identity from domain entities.

```elixir
# Derive for Ecto schemas
defmodule MyApp.User do
  @derive {FnTypes.Protocols.Identifiable, type: :user}
  use Ecto.Schema
  # ...
end

# Use it
FnTypes.Protocols.Identifiable.identity(user)
# {:user, "usr_123"}
```

## Behaviours

FnTypes includes standard functional programming behaviours:

- `FnTypes.Behaviours.Monad` - `pure/1`, `bind/2`, `map/2`
- `FnTypes.Behaviours.Applicative` - `pure/1`, `ap/2`, `map/2`, `map2/3`
- `FnTypes.Behaviours.Functor` - `map/2`
- `FnTypes.Behaviours.Foldable` - `fold_left/3`, `fold_right/3`, `to_list/1`
- `FnTypes.Behaviours.Semigroup` - `combine/2`

These are implemented by `Result`, `Maybe`, `Validation`, `Ior`, and `NonEmptyList`.

## Pipeline

Multi-step workflows with context and error handling.

```elixir
alias FnTypes.Pipeline

Pipeline.new(%{user_id: 123})
|> Pipeline.step(:user, &fetch_user/1)
|> Pipeline.step(:orders, &fetch_orders/1, after: :user)
|> Pipeline.step(:summary, &build_summary/1)
|> Pipeline.run()
```

## License

MIT
