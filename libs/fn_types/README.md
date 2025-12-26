# FnTypes

Functional programming types for Elixir: Result, Maybe, Pipeline, AsyncResult, Validation, and more.

## Installation

```elixir
def deps do
  [{:fn_types, "~> 0.1.0"}]
end
```

## Quick Start

### Result - Error handling

```elixir
alias FnTypes.Result

{:ok, user} = fetch_user(id)
|> Result.and_then(&validate/1)
|> Result.map(&transform/1)

# Pattern matching
case result do
  {:ok, value} -> handle_success(value)
  {:error, reason} -> handle_error(reason)
end
```

### Maybe - Optional values

```elixir
alias FnTypes.Maybe

Maybe.from_nilable(user.email)
|> Maybe.map(&String.downcase/1)
|> Maybe.unwrap_or("no-email@example.com")
```

### Pipeline - Multi-step workflows

```elixir
alias FnTypes.Pipeline

Pipeline.new(%{params: params})
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:create, &create_user/1)
|> Pipeline.step(:notify, &send_welcome/1)
|> Pipeline.run()
```

### AsyncResult - Concurrent operations

```elixir
alias FnTypes.AsyncResult

# Parallel execution
AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
])

# Race (first success wins)
AsyncResult.race([
  fn -> cache_get(key) end,
  fn -> db_get(key) end
])

# Retry with backoff
AsyncResult.retry(fn -> api_call() end,
  max_attempts: 3,
  initial_delay: 100
)
```

### Validation - Accumulating errors

```elixir
alias FnTypes.Validation

Validation.new(user_attrs)
|> Validation.validate(&check_email/1)
|> Validation.validate(&check_age/1)
|> Validation.validate(&check_name/1)
|> Validation.to_result()
```

### Guards

```elixir
import FnTypes.Guards

def process(result) when is_ok(result), do: ...
def process(result) when is_error(result), do: ...
```

## Modules

| Module | Purpose |
|--------|---------|
| `FnTypes.Result` | Error handling with {:ok, v} / {:error, e} |
| `FnTypes.Maybe` | Optional values |
| `FnTypes.Pipeline` | Multi-step workflows with context |
| `FnTypes.AsyncResult` | Concurrent operations |
| `FnTypes.Validation` | Accumulating validation errors |
| `FnTypes.Guards` | Guard macros (is_ok, is_error, etc.) |
| `FnTypes.Error` | Structured error type |
| `FnTypes.Lens` | Functional lenses for nested data |
| `FnTypes.NonEmptyList` | Non-empty list type |

## Configuration

```elixir
# config/config.exs
config :fn_types,
  telemetry_prefix: [:my_app]  # Default: [:fn_types]
```

## License

MIT
