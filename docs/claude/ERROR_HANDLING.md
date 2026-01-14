# Error Handling Patterns

> **Consistent error handling with Result tuples, FnTypes.Error, and the Normalizable protocol.**

## Core Principles

1. **Always return Result tuples**: `{:ok, value}` or `{:error, reason}`
2. **Never raise for expected failures**: Exceptions are for bugs, not business logic
3. **Use structured errors**: Prefer `FnTypes.Error` over bare atoms/strings
4. **Normalize at boundaries**: Convert external errors to unified format

---

## Result Tuple Basics

### Creating Results

```elixir
alias FnTypes.Result

# Success
{:ok, user}
Result.ok(user)

# Error
{:error, :not_found}
Result.error(:not_found)

# From nilable
Result.from_nilable(Repo.get(User, id), :not_found)
#=> {:ok, user} | {:error, :not_found}

# From changeset
Result.from_changeset(changeset)
#=> {:ok, changeset} | {:error, changeset}

# With normalization
Result.from_changeset(changeset, normalize: true)
#=> {:ok, changeset} | {:error, %FnTypes.Error{type: :validation}}
```

### Chaining Results

```elixir
# and_then - chain success path
{:ok, user}
|> Result.and_then(&validate_user/1)
|> Result.and_then(&save_user/1)

# map - transform success value
{:ok, user}
|> Result.map(&format_response/1)

# map_error - transform error
{:error, changeset}
|> Result.map_error(&format_errors/1)

# or_else - handle errors
{:error, :not_found}
|> Result.or_else(fn _ -> {:ok, default_user()} end)
```

### With Statement (Preferred for Multiple Steps)

```elixir
def create_user_with_account(attrs) do
  with {:ok, user} <- create_user(attrs),
       {:ok, account} <- create_account(user),
       {:ok, _} <- send_welcome_email(user) do
    {:ok, %{user: user, account: account}}
  end
end
```

---

## FnTypes.Error Struct

### Structure

```elixir
%FnTypes.Error{
  type: :validation,           # Error category
  code: :email_invalid,        # Specific error code
  message: "Email is invalid", # Human-readable message
  details: %{field: :email},   # Additional context
  source: Ecto.Changeset,      # Origin module
  context: %{user_id: 123},    # Request context
  stacktrace: [...],           # Optional stacktrace
  recoverable: false,          # Can operation be retried?
  step: :validate_user         # Pipeline step (if applicable)
}
```

### Creating Errors

```elixir
alias FnTypes.Error

# Basic error
Error.new(:not_found, :user_not_found)

# With message
Error.new(:validation, :email_invalid,
  message: "Email format is invalid"
)

# Full error with context
Error.new(:conflict, :email_taken,
  message: "Email already registered",
  details: %{email: email, existing_user_id: existing.id},
  context: %{request_id: request_id},
  recoverable: false
)
```

### Error Types

| Type | Use For |
|------|---------|
| `:validation` | Input validation failures |
| `:not_found` | Resource doesn't exist |
| `:unauthorized` | Authentication failures |
| `:forbidden` | Authorization failures |
| `:conflict` | Duplicate/concurrent modification |
| `:unprocessable` | Valid input but can't process |
| `:timeout` | Operation timed out |
| `:external` | Third-party service errors |
| `:internal` | Unexpected system errors |

---

## Normalizable Protocol

The `FnTypes.Protocols.Normalizable` protocol converts any error type to `FnTypes.Error`.

### Built-in Implementations

```elixir
alias FnTypes.Protocols.Normalizable

# Ecto Changeset
Normalizable.normalize(invalid_changeset)
#=> %FnTypes.Error{type: :validation, code: :changeset_invalid, details: %{errors: ...}}

# Ecto.NoResultsError
Normalizable.normalize(%Ecto.NoResultsError{})
#=> %FnTypes.Error{type: :not_found, code: :no_results}

# Ecto.ConstraintError (unique)
Normalizable.normalize(%Ecto.ConstraintError{type: :unique, constraint: "users_email_index"})
#=> %FnTypes.Error{type: :conflict, code: :email_taken}

# Postgrex.Error
Normalizable.normalize(%Postgrex.Error{postgres: %{code: :unique_violation}})
#=> %FnTypes.Error{type: :conflict, code: :unique_violation}

# Atom errors
Normalizable.normalize(:not_found)
#=> %FnTypes.Error{type: :not_found, code: :not_found}
```

### Result Integration

```elixir
# Normalize error in Result
{:error, changeset}
|> Result.normalize_error()
#=> {:error, %FnTypes.Error{type: :validation}}

# With context
{:error, reason}
|> Result.normalize_error(context: %{user_id: 123})
```

### Custom Implementations

```elixir
defimpl FnTypes.Protocols.Normalizable, for: MyApp.ExternalAPIError do
  def normalize(%{status: 429, retry_after: seconds}, opts) do
    FnTypes.Error.new(:external, :rate_limited,
      message: "Rate limited, retry after #{seconds}s",
      details: %{retry_after: seconds},
      context: Keyword.get(opts, :context, %{}),
      recoverable: true
    )
  end

  def normalize(%{status: status, body: body}, opts) when status >= 500 do
    FnTypes.Error.new(:external, :server_error,
      message: "External service error",
      details: %{status: status, body: body},
      context: Keyword.get(opts, :context, %{}),
      recoverable: true
    )
  end
end
```

---

## Recoverable Protocol

The `FnTypes.Protocols.Recoverable` protocol determines retry behavior.

```elixir
alias FnTypes.Protocols.Recoverable

# Check if error is recoverable
Recoverable.recoverable?(%FnTypes.Error{recoverable: true})
#=> true

# Get retry strategy
Recoverable.retry_strategy(%FnTypes.Error{type: :timeout})
#=> {:retry, delay: 1000, max_attempts: 3}

Recoverable.retry_strategy(%FnTypes.Error{type: :validation})
#=> :no_retry
```

### Built-in Retry Classification

| Error Type | Recoverable? | Default Strategy |
|------------|--------------|------------------|
| `:timeout` | Yes | Exponential backoff |
| `:external` | Maybe | Check `recoverable` field |
| `:conflict` (stale) | Yes | Immediate retry |
| `:validation` | No | No retry |
| `:not_found` | No | No retry |
| `:unauthorized` | No | No retry |

---

## Error Handling Patterns

### Pattern 1: Boundary Normalization

Normalize errors at module boundaries:

```elixir
defmodule MyApp.Accounts do
  alias FnTypes.{Result, Error}

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> normalize_result()
  end

  defp normalize_result({:ok, _} = ok), do: ok
  defp normalize_result({:error, reason}) do
    {:error, FnTypes.Protocols.Normalizable.normalize(reason)}
  end
end
```

### Pattern 2: Error Wrapping with Context

Add context as errors propagate:

```elixir
def process_order(order_id) do
  with {:ok, order} <- fetch_order(order_id),
       {:ok, payment} <- charge_payment(order) |> add_context(order_id: order_id),
       {:ok, _} <- fulfill_order(order) |> add_context(order_id: order_id) do
    {:ok, order}
  end
end

defp add_context({:error, reason}, context) do
  {:error, Error.with_context(reason, context)}
end
defp add_context(ok, _context), do: ok
```

### Pattern 3: Error Translation for API

Convert internal errors to API responses:

```elixir
defmodule MyAppWeb.ErrorHelpers do
  def to_api_error(%FnTypes.Error{} = error) do
    %{
      error: %{
        type: error.type,
        code: error.code,
        message: error.message,
        details: sanitize_details(error.details)
      }
    }
  end

  def to_http_status(%FnTypes.Error{type: type}) do
    case type do
      :validation -> 422
      :not_found -> 404
      :unauthorized -> 401
      :forbidden -> 403
      :conflict -> 409
      :unprocessable -> 422
      :timeout -> 504
      :external -> 502
      :internal -> 500
      _ -> 500
    end
  end

  defp sanitize_details(details) do
    # Remove sensitive fields
    Map.drop(details, [:stacktrace, :internal_id])
  end
end
```

### Pattern 4: Pipeline Error Handling

```elixir
Pipeline.new(%{user_id: id})
|> Pipeline.step(:fetch, fn ctx ->
  case Repo.get(User, ctx.user_id) do
    nil -> {:error, Error.new(:not_found, :user_not_found)}
    user -> {:ok, %{user: user}}
  end
end)
|> Pipeline.step(:validate, fn ctx ->
  case validate(ctx.user) do
    :ok -> {:ok, %{}}
    {:error, reasons} ->
      {:error, Error.new(:validation, :invalid_user, details: %{reasons: reasons})}
  end
end)
|> Pipeline.run()
|> case do
  {:ok, ctx} ->
    {:ok, ctx.user}

  {:error, {:step_failed, step, %FnTypes.Error{} = error}} ->
    {:error, Error.with_step(error, step)}

  {:error, {:step_failed, step, reason}} ->
    {:error, Error.new(:internal, :step_failed,
      details: %{step: step, reason: reason}
    )}
end
```

---

## Common Error Scenarios

### Database Errors

```elixir
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
  |> case do
    {:ok, user} ->
      {:ok, user}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:error, FnTypes.Protocols.Normalizable.normalize(changeset)}
  end
end
```

### External API Errors

```elixir
def charge_payment(amount, card_token) do
  case StripeClient.charge(amount, card_token) do
    {:ok, charge} ->
      {:ok, charge}

    {:error, %{code: :card_declined, message: msg}} ->
      {:error, Error.new(:unprocessable, :card_declined,
        message: msg,
        recoverable: false
      )}

    {:error, %{code: :rate_limited, retry_after: seconds}} ->
      {:error, Error.new(:external, :rate_limited,
        details: %{retry_after: seconds},
        recoverable: true
      )}

    {:error, reason} ->
      {:error, Error.new(:external, :payment_failed,
        details: %{reason: reason},
        recoverable: true
      )}
  end
end
```

### Validation Errors

```elixir
def validate_order(order) do
  errors = []

  errors = if order.total <= 0,
    do: [{:total, "must be positive"} | errors],
    else: errors

  errors = if Enum.empty?(order.items),
    do: [{:items, "cannot be empty"} | errors],
    else: errors

  case errors do
    [] ->
      {:ok, order}

    errors ->
      {:error, Error.new(:validation, :invalid_order,
        details: %{errors: Map.new(errors)}
      )}
  end
end
```

---

## Anti-Patterns

### Don't: Return Bare Strings

```elixir
# BAD
{:error, "User not found"}

# GOOD
{:error, :not_found}
{:error, Error.new(:not_found, :user_not_found)}
```

### Don't: Raise for Expected Failures

```elixir
# BAD
def get_user!(id) do
  case Repo.get(User, id) do
    nil -> raise "User not found"
    user -> user
  end
end

# GOOD
def get_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
```

### Don't: Swallow Errors

```elixir
# BAD
def process(data) do
  case risky_operation(data) do
    {:ok, result} -> result
    {:error, _} -> nil  # Error is lost!
  end
end

# GOOD
def process(data) do
  risky_operation(data)
  # Let caller decide how to handle error
end
```

### Don't: Use Generic Error Atoms

```elixir
# BAD
{:error, :error}
{:error, :failed}
{:error, :invalid}

# GOOD
{:error, :user_not_found}
{:error, :payment_declined}
{:error, :validation_failed}
```

---

## Error Testing

```elixir
import FnTypes.Testing

test "returns not_found for missing user" do
  assert_error(:not_found, Accounts.get_user("nonexistent"))
end

test "returns validation error for invalid input" do
  error = assert_error(Accounts.create_user(%{email: "invalid"}))
  assert_error_type(:validation, {:error, error})
end

test "error has expected structure" do
  {:error, error} = Accounts.create_user(%{})
  assert %FnTypes.Error{type: :validation, code: :changeset_invalid} = error
  assert error.details.errors[:email] != nil
end
```
