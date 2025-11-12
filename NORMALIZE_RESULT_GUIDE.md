# normalize_result Decorator - Complete Guide

## Overview

The `normalize_result` decorator transforms **any return value or exception** into the standard Elixir result pattern: `{:ok, result} | {:error, reason}`.

This is incredibly useful for:
- Wrapping external libraries that don't return result tuples
- Converting legacy code to use result patterns
- Ensuring consistent API responses
- Simplifying error handling across your codebase
- Making any function "pipeline-friendly"

---

## Quick Examples

### Basic Usage - Wrap Raw Values

```elixir
# Without decorator - returns raw value or nil
def get_user(id) do
  Repo.get(User, id)
end
# Returns: %User{} or nil

# With decorator - always returns result tuple
@decorate normalize_result()
def get_user(id) do
  Repo.get(User, id)
end
# Returns: {:ok, %User{}} or {:ok, nil}
```

### Treat nil as Error

```elixir
@decorate normalize_result(nil_is_error: true)
def get_user(id) do
  Repo.get(User, id)
end
# Returns: {:ok, %User{}} or {:error, :nil_value}
```

### Wrap Exceptions

```elixir
@decorate normalize_result(wrap_exceptions: true)
def risky_operation do
  raise "Something went wrong!"
end
# Returns: {:error, %RuntimeError{message: "Something went wrong!"}}
# Instead of crashing
```

### Convert Error Atoms

```elixir
@decorate normalize_result(error_patterns: [:not_found, :invalid])
def check_status do
  :not_found  # This atom indicates an error
end
# Returns: {:error, :not_found}
```

---

## All Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `error_patterns` | `[atom() \| String.t()]` | `[:error, :invalid, :failed, :timeout]` | Atoms/strings that indicate errors |
| `nil_is_error` | `boolean()` | `false` | Treat nil as `{:error, :nil_value}` |
| `false_is_error` | `boolean()` | `false` | Treat false as `{:error, :false_value}` |
| `wrap_exceptions` | `boolean()` | `true` | Catch exceptions and return as errors |
| `error_mapper` | `(any() -> any())` | `nil` | Transform error values |
| `success_mapper` | `(any() -> any())` | `nil` | Transform success values |

---

## Normalization Rules

### 1. Already Result Tuples → Pass Through

```elixir
@decorate normalize_result()
def create_user(attrs) do
  {:ok, %User{}}  # Already a result tuple
end
# Returns: {:ok, %User{}} (unchanged)

@decorate normalize_result()
def fetch_data do
  {:error, :timeout}  # Already an error tuple
end
# Returns: {:error, :timeout} (unchanged)
```

### 2. Error Patterns → Convert to Error Tuple

```elixir
@decorate normalize_result(error_patterns: [:error, :invalid, :not_found])
def find_record(id) do
  :not_found  # Matches error pattern
end
# Returns: {:error, :not_found}

@decorate normalize_result(error_patterns: ["ERROR", "FAILED"])
def check_api do
  "ERROR"  # String error pattern
end
# Returns: {:error, "ERROR"}
```

**Default error patterns:** `:error`, `:invalid`, `:failed`, `:timeout`

### 3. nil Handling → Configurable

```elixir
# Default: nil is wrapped in {:ok, nil}
@decorate normalize_result()
def find_user(email) do
  nil
end
# Returns: {:ok, nil}

# With nil_is_error: true
@decorate normalize_result(nil_is_error: true)
def find_user(email) do
  nil
end
# Returns: {:error, :nil_value}
```

### 4. false Handling → Configurable

```elixir
# Default: false is wrapped in {:ok, false}
@decorate normalize_result()
def is_valid? do
  false
end
# Returns: {:ok, false}

# With false_is_error: true
@decorate normalize_result(false_is_error: true)
def is_valid? do
  false
end
# Returns: {:error, :false_value}
```

### 5. Exceptions → Convert to Errors

```elixir
@decorate normalize_result(wrap_exceptions: true)
def divide(a, b) do
  a / b  # Raises if b is 0
end
# Returns: {:ok, result} or {:error, %ArithmeticError{}}

@decorate normalize_result(wrap_exceptions: false)
def divide(a, b) do
  a / b
end
# Raises ArithmeticError (doesn't wrap)
```

**Exception types handled:**
- `rescue` → `{:error, exception}`
- `exit` → `{:error, {:exit, reason}}`
- `throw` → `{:error, {:throw, value}}`

### 6. All Other Values → Wrap in Success

```elixir
@decorate normalize_result()
def get_name do
  "John Doe"
end
# Returns: {:ok, "John Doe"}

@decorate normalize_result()
def get_count do
  42
end
# Returns: {:ok, 42}

@decorate normalize_result()
def list_items do
  [1, 2, 3]
end
# Returns: {:ok, [1, 2, 3]}

@decorate normalize_result()
def build_struct do
  %User{name: "John"}
end
# Returns: {:ok, %User{name: "John"}}
```

---

## Real-World Examples

### Example 1: Wrapping External HTTP Client

```elixir
defmodule MyApp.APIClient do
  use Events.Decorator

  # HTTPoison returns various formats
  @decorate normalize_result(
    nil_is_error: true,
    wrap_exceptions: true,
    error_mapper: &format_api_error/1
  )
  def fetch_user(id) do
    case HTTPoison.get("https://api.example.com/users/#{id}") do
      {:ok, %{status_code: 200, body: body}} ->
        Jason.decode!(body)

      {:ok, %{status_code: 404}} ->
        nil  # Will become {:error, :nil_value}

      {:ok, %{status_code: status}} ->
        :failed  # Will become {:error, :failed}

      {:error, %HTTPoison.Error{reason: reason}} ->
        reason  # Will be wrapped and mapped
    end
  end

  defp format_api_error(error) do
    "API Error: #{inspect(error)}"
  end
end

# Usage:
case APIClient.fetch_user(123) do
  {:ok, user} -> IO.puts("Got user: #{user["name"]}")
  {:error, reason} -> IO.puts("Failed: #{reason}")
end
```

### Example 2: Database Lookups with nil as Error

```elixir
defmodule MyApp.UserRepository do
  use Events.Decorator

  # Repo.get returns struct or nil
  @decorate normalize_result(nil_is_error: true)
  def find_user(id) do
    Repo.get(User, id)
  end

  # Now you can use with statements easily
  def get_user_with_org(user_id) do
    with {:ok, user} <- find_user(user_id),
         {:ok, org} <- find_organization(user.org_id) do
      {:ok, %{user: user, organization: org}}
    end
  end
end
```

### Example 3: File Operations with Exception Handling

```elixir
defmodule MyApp.FileService do
  use Events.Decorator

  @decorate normalize_result(
    wrap_exceptions: true,
    error_mapper: fn
      %File.Error{reason: reason} -> reason
      exception -> Exception.message(exception)
    end
  )
  def read_config(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end

# Usage:
case FileService.read_config("config.json") do
  {:ok, config} -> use_config(config)
  {:error, :enoent} -> IO.puts("Config file not found")
  {:error, reason} -> IO.puts("Error: #{reason}")
end
```

### Example 4: Converting Boolean Results

```elixir
defmodule MyApp.Validator do
  use Events.Decorator

  # Convert boolean validation to result tuple
  @decorate normalize_result(
    false_is_error: true,
    error_mapper: fn :false_value -> "Validation failed" end
  )
  def validate_email(email) do
    String.contains?(email, "@")
  end
end

# Usage:
case Validator.validate_email("invalid") do
  {:ok, true} -> "Valid email"
  {:error, msg} -> "Error: #{msg}"
end
```

### Example 5: External API with Custom Error Patterns

```elixir
defmodule MyApp.PaymentGateway do
  use Events.Decorator

  @decorate normalize_result(
    error_patterns: [:declined, :insufficient_funds, :fraud_detected, :timeout],
    error_mapper: &format_payment_error/1,
    success_mapper: &format_payment_success/1
  )
  def charge_card(card, amount) do
    # Payment gateway returns various atoms
    ExternalPaymentAPI.charge(card, amount)
  end

  defp format_payment_error(:declined), do: "Card was declined"
  defp format_payment_error(:insufficient_funds), do: "Insufficient funds"
  defp format_payment_error(:fraud_detected), do: "Suspicious activity detected"
  defp format_payment_error(error), do: "Payment error: #{inspect(error)}"

  defp format_payment_success(charge_id) do
    %{
      charge_id: charge_id,
      charged_at: DateTime.utc_now()
    }
  end
end
```

### Example 6: Wrapping Legacy Code

```elixir
# Legacy module returns mixed formats
defmodule Legacy.UserService do
  def get_user(id) when id > 0, do: %{id: id, name: "User #{id}"}
  def get_user(_), do: nil

  def authenticate(user, pass) do
    if user && pass == "secret" do
      true
    else
      :invalid_credentials
    end
  end
end

# Modern wrapper with consistent results
defmodule MyApp.UserService do
  use Events.Decorator

  @decorate normalize_result(nil_is_error: true)
  def get_user(id) do
    Legacy.UserService.get_user(id)
  end

  @decorate normalize_result(
    error_patterns: [:invalid_credentials],
    false_is_error: true
  )
  def authenticate(user, password) do
    Legacy.UserService.authenticate(user, password)
  end
end

# Now you have consistent API:
# get_user(1) → {:ok, %{id: 1, name: "User 1"}}
# get_user(0) → {:error, :nil_value}
# authenticate(user, "secret") → {:ok, true}
# authenticate(user, "wrong") → {:error, :invalid_credentials}
```

---

## Combining with Other Decorators

### With returns_result for Validation

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, String.t()}
@decorate returns_result(ok: User.t(), error: :string, validate: true)
@decorate normalize_result(
  nil_is_error: true,
  wrap_exceptions: true,
  error_mapper: &format_error/1
)
def create_user(attrs) do
  # Any exception or nil becomes error tuple
  # Then validated against expected types
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

### With Pipeline for Chaining

```elixir
@decorate returns_pipeline(ok: User.t(), error: :string)
@decorate normalize_result(nil_is_error: true, wrap_exceptions: true)
def fetch_and_process(user_id) do
  user_id
  |> find_user()
  |> process_user()
  |> enrich_data()
end

# Can chain operations:
fetch_and_process(123)
|> and_then(&send_notification/1)
|> map_ok(&UserView.render/1)
```

---

## Performance Considerations

### With wrap_exceptions: true
```elixir
@decorate normalize_result(wrap_exceptions: true)
def operation do
  # try/rescue/catch block added
  # Small overhead (~1-2 microseconds)
end
```

### Without wrap_exceptions (faster)
```elixir
@decorate normalize_result(wrap_exceptions: false)
def operation do
  # No try/rescue block
  # Minimal overhead
  # Let exceptions bubble up
end
```

### Recommendation
- Use `wrap_exceptions: true` for **external API calls, file operations**
- Use `wrap_exceptions: false` for **internal functions** where exceptions are unexpected

---

## Common Patterns

### Pattern 1: Database Lookups

```elixir
@decorate normalize_result(nil_is_error: true)
def find_by_email(email) do
  Repo.get_by(User, email: email)
end
```

### Pattern 2: External APIs

```elixir
@decorate normalize_result(
  wrap_exceptions: true,
  error_mapper: fn
    %HTTPoison.Error{reason: reason} -> reason
    error -> inspect(error)
  end
)
def fetch_data(url) do
  HTTPoison.get!(url).body |> Jason.decode!()
end
```

### Pattern 3: Validation Functions

```elixir
@decorate normalize_result(
  false_is_error: true,
  error_mapper: fn :false_value -> "Validation failed" end
)
def valid_age?(age) do
  age >= 18
end
```

### Pattern 4: File Operations

```elixir
@decorate normalize_result(wrap_exceptions: true)
def read_json(path) do
  File.read!(path) |> Jason.decode!()
end
```

### Pattern 5: Boolean to Result

```elixir
@decorate normalize_result(
  false_is_error: true,
  success_mapper: fn true -> :success end,
  error_mapper: fn :false_value -> :failure end
)
def process do
  # Returns boolean internally
  some_boolean_operation()
end
# Result: {:ok, :success} or {:error, :failure}
```

---

## Error Mappers - Advanced Usage

### Transform Exceptions to User-Friendly Messages

```elixir
@decorate normalize_result(
  wrap_exceptions: true,
  error_mapper: fn
    %Ecto.NoResultsError{} ->
      "Record not found"

    %DBConnection.ConnectionError{} ->
      "Database connection failed"

    %Jason.DecodeError{} ->
      "Invalid JSON format"

    exception ->
      "System error: #{Exception.message(exception)}"
  end
)
def fetch_user_data(id) do
  # Any exception is caught and mapped to friendly message
end
```

### Extract Specific Error Information

```elixir
@decorate normalize_result(
  wrap_exceptions: true,
  error_mapper: fn
    %Ecto.Changeset{} = changeset ->
      %{
        type: :validation_error,
        errors: format_changeset_errors(changeset)
      }

    exception ->
      %{
        type: :system_error,
        message: Exception.message(exception)
      }
  end
)
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end
```

---

## Success Mappers - Transform Results

### Format Output

```elixir
@decorate normalize_result(
  success_mapper: fn user ->
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      created_at: user.inserted_at |> DateTime.to_iso8601()
    }
  end
)
def get_user(id) do
  Repo.get(User, id)
end
```

### Extract Specific Fields

```elixir
@decorate normalize_result(
  nil_is_error: true,
  success_mapper: &Map.take(&1, [:id, :name, :email])
)
def find_user_basic(id) do
  Repo.get(User, id)
end
```

---

## Testing

```elixir
defmodule MyApp.UserServiceTest do
  use ExUnit.Case

  describe "find_user/1 with normalize_result" do
    test "returns {:ok, user} when found" do
      user = insert(:user)
      assert {:ok, ^user} = UserService.find_user(user.id)
    end

    test "returns {:error, :nil_value} when not found" do
      assert {:error, :nil_value} = UserService.find_user(999999)
    end
  end

  describe "risky_operation/0 with exception wrapping" do
    test "returns {:error, exception} when it raises" do
      assert {:error, %RuntimeError{}} = UserService.risky_operation()
    end
  end

  describe "validate_email/1 with false_is_error" do
    test "returns {:ok, true} for valid email" do
      assert {:ok, true} = UserService.validate_email("test@example.com")
    end

    test "returns {:error, msg} for invalid email" do
      assert {:error, _msg} = UserService.validate_email("invalid")
    end
  end
end
```

---

## Migration Guide

### Before: Mixed Return Types

```elixir
def get_user(id) do
  Repo.get(User, id)  # Returns %User{} or nil
end

def fetch_data(url) do
  HTTPoison.get!(url)  # Returns response or raises
end

def valid?(x) do
  x > 0  # Returns boolean
end
```

### After: Consistent Result Tuples

```elixir
@decorate normalize_result(nil_is_error: true)
def get_user(id) do
  Repo.get(User, id)  # Returns {:ok, %User{}} or {:error, :nil_value}
end

@decorate normalize_result(wrap_exceptions: true)
def fetch_data(url) do
  HTTPoison.get!(url)  # Returns {:ok, response} or {:error, exception}
end

@decorate normalize_result(false_is_error: true)
def valid?(x) do
  x > 0  # Returns {:ok, true} or {:error, :false_value}
end
```

---

## Summary

The `normalize_result` decorator is your Swiss Army knife for converting **any function** into one that returns consistent `{:ok, result} | {:error, reason}` tuples.

### Key Benefits

✅ **Consistency** - All functions return the same pattern
✅ **Pipeline-friendly** - Works seamlessly with `with` statements and pipelines
✅ **Exception safety** - Catch and convert exceptions to errors
✅ **Legacy compatibility** - Wrap old code without refactoring
✅ **Flexible** - Highly configurable for different scenarios
✅ **Type-safe** - Combine with `returns_result` for validation

### When to Use

- Wrapping external libraries
- Converting legacy code
- Normalizing third-party APIs
- Ensuring consistent error handling
- Making functions pipeline-compatible
- Simplifying exception handling

### Quick Decision Guide

| Your Function Returns | Use Configuration |
|----------------------|-------------------|
| Raw value or nil | `nil_is_error: true` |
| Boolean | `false_is_error: true` |
| Raises exceptions | `wrap_exceptions: true` |
| Error atoms like `:invalid` | `error_patterns: [:invalid, ...]` |
| Already result tuples | Default (pass through) |
| Need to transform | Use `error_mapper` or `success_mapper` |

**Start using `normalize_result` today to make your codebase more consistent and maintainable!**
