# normalize_result Decorator - Quick Summary

## What It Does

**Transforms ANY return value or exception into `{:ok, result} | {:error, reason}`**

```elixir
# Before: Mixed return types
def get_user(id), do: Repo.get(User, id)  # Returns %User{} or nil
def fetch_api, do: HTTPoison.get!(url)     # Returns response or raises
def valid?(x), do: x > 0                   # Returns boolean

# After: Consistent result tuples
@decorate normalize_result(nil_is_error: true)
def get_user(id), do: Repo.get(User, id)  # {:ok, %User{}} or {:error, :nil_value}

@decorate normalize_result(wrap_exceptions: true)
def fetch_api, do: HTTPoison.get!(url)     # {:ok, response} or {:error, exception}

@decorate normalize_result(false_is_error: true)
def valid?(x), do: x > 0                   # {:ok, true} or {:error, :false_value}
```

---

## Quick Start

### 1. Wrap Nil Results

```elixir
@decorate normalize_result(nil_is_error: true)
def find_user(id) do
  Repo.get(User, id)
end
# %User{} → {:ok, %User{}}
# nil → {:error, :nil_value}
```

### 2. Catch Exceptions

```elixir
@decorate normalize_result(wrap_exceptions: true)
def read_file(path) do
  File.read!(path)
end
# Success → {:ok, contents}
# Raises → {:error, %File.Error{}}
```

### 3. Convert Error Atoms

```elixir
@decorate normalize_result(error_patterns: [:not_found, :invalid])
def check_status do
  :not_found
end
# Returns: {:error, :not_found}
```

### 4. Transform Values

```elixir
@decorate normalize_result(
  success_mapper: &String.upcase/1,
  error_mapper: fn error -> "Error: #{inspect(error)}" end
)
def get_name do
  "john"
end
# Returns: {:ok, "JOHN"}
```

---

## All Options

```elixir
@decorate normalize_result(
  # What atoms/strings indicate errors? Default: [:error, :invalid, :failed, :timeout]
  error_patterns: [:not_found, :timeout, "ERROR"],

  # Treat nil as error? Default: false
  nil_is_error: true,

  # Treat false as error? Default: false
  false_is_error: true,

  # Catch exceptions? Default: true
  wrap_exceptions: true,

  # Transform errors
  error_mapper: fn error -> "Failed: #{inspect(error)}" end,

  # Transform success values
  success_mapper: fn value -> Map.take(value, [:id, :name]) end
)
def my_function do
  # ... any implementation
end
```

---

## Normalization Rules

| Input | Default Behavior | With Options |
|-------|------------------|--------------|
| `%User{}` | `{:ok, %User{}}` | Apply success_mapper |
| `nil` | `{:ok, nil}` | `{:error, :nil_value}` if nil_is_error |
| `false` | `{:ok, false}` | `{:error, :false_value}` if false_is_error |
| `:error` | `{:error, :error}` (in default patterns) | Apply error_mapper |
| `:not_found` | `{:ok, :not_found}` | `{:error, :not_found}` if in error_patterns |
| `{:ok, x}` | `{:ok, x}` (pass through) | Apply success_mapper to x |
| `{:error, r}` | `{:error, r}` (pass through) | Apply error_mapper to r |
| Exception | Raises | `{:error, exception}` if wrap_exceptions |
| Any other | `{:ok, value}` | Apply success_mapper |

---

## Common Use Cases

### 1. Database Lookups

```elixir
@decorate normalize_result(nil_is_error: true)
def find_by_email(email) do
  Repo.get_by(User, email: email)
end

# Now you can use with statements:
with {:ok, user} <- find_by_email(email),
     {:ok, org} <- find_organization(user.org_id) do
  {:ok, %{user: user, org: org}}
end
```

### 2. External API Calls

```elixir
@decorate normalize_result(
  wrap_exceptions: true,
  error_mapper: fn
    %HTTPoison.Error{reason: reason} -> reason
    error -> inspect(error)
  end
)
def fetch_user_from_api(id) do
  "https://api.example.com/users/#{id}"
  |> HTTPoison.get!()
  |> Map.get(:body)
  |> Jason.decode!()
end
```

### 3. File Operations

```elixir
@decorate normalize_result(wrap_exceptions: true)
def read_config(path) do
  path
  |> File.read!()
  |> Jason.decode!()
end
```

### 4. Boolean Validations

```elixir
@decorate normalize_result(
  false_is_error: true,
  error_mapper: fn :false_value -> "Invalid email format" end
)
def validate_email(email) do
  String.contains?(email, "@")
end
```

### 5. Legacy Code Wrapping

```elixir
# Legacy function returns :error or data
defmodule Legacy do
  def fetch(id) when id > 0, do: %{id: id, name: "User"}
  def fetch(_), do: :error
end

# Modern wrapper
@decorate normalize_result(error_patterns: [:error])
def get_user(id) do
  Legacy.fetch(id)
end
# Returns: {:ok, %{...}} or {:error, :error}
```

---

## Combining with Other Decorators

```elixir
# Type validation + normalization
@spec create_user(map()) :: {:ok, User.t()} | {:error, String.t()}
@decorate returns_result(ok: User.t(), error: :string, validate: true)
@decorate normalize_result(
  nil_is_error: true,
  wrap_exceptions: true,
  error_mapper: &format_error/1
)
def create_user(attrs) do
  # Implementation
end

# Pipeline + normalization
@decorate returns_pipeline(ok: User.t(), error: :string)
@decorate normalize_result(nil_is_error: true, wrap_exceptions: true)
def fetch_and_process(id) do
  id |> find_user() |> process()
end
```

---

## Benefits

✅ **Consistency** - All functions return the same pattern
✅ **Pipeline-friendly** - Works with `with`, `case`, and pipelines
✅ **Exception safety** - No more unexpected crashes
✅ **Legacy compatibility** - Wrap old code without refactoring
✅ **Type-safe** - Combine with type decorators for validation
✅ **Flexible** - Highly configurable for any scenario

---

## Decision Tree

```
What does your function return?

├─ Raw value or nil
│  └─ Use: nil_is_error: true
│
├─ Boolean (true/false)
│  └─ Use: false_is_error: true
│
├─ Might raise exception
│  └─ Use: wrap_exceptions: true
│
├─ Error atoms like :invalid, :not_found
│  └─ Use: error_patterns: [:invalid, :not_found, ...]
│
├─ Already {:ok, _} | {:error, _}
│  └─ Use: Default (pass through)
│
└─ Need to transform values
   └─ Use: error_mapper or success_mapper
```

---

## Performance

- **Minimal overhead** without wrap_exceptions (~100 nanoseconds)
- **Small overhead** with wrap_exceptions (try/rescue/catch adds ~1-2 microseconds)
- **Zero cost** if function already returns result tuples (pass through)

---

## Testing

```elixir
test "normalizes nil to error" do
  assert {:error, :nil_value} = MyModule.find_user(999)
end

test "normalizes struct to success" do
  user = insert(:user)
  assert {:ok, ^user} = MyModule.find_user(user.id)
end

test "wraps exceptions" do
  assert {:error, %RuntimeError{}} = MyModule.risky_operation()
end
```

---

## Quick Reference Card

| Scenario | Configuration | Example |
|----------|--------------|---------|
| **Database lookup** | `nil_is_error: true` | `Repo.get(User, id)` |
| **API call** | `wrap_exceptions: true` | `HTTPoison.get!(url)` |
| **File read** | `wrap_exceptions: true` | `File.read!(path)` |
| **Validation** | `false_is_error: true` | `x > 0` |
| **Error atoms** | `error_patterns: [...]` | Returns `:not_found` |
| **Transform errors** | `error_mapper: fn ... end` | Custom error format |
| **Transform success** | `success_mapper: fn ... end` | Extract fields |
| **Already result** | Default (no options) | Pass through |

---

## Examples You Can Copy-Paste

### Wrap Database Call
```elixir
@decorate normalize_result(nil_is_error: true)
def find_user(id), do: Repo.get(User, id)
```

### Wrap HTTP Call
```elixir
@decorate normalize_result(wrap_exceptions: true)
def fetch_api(url), do: HTTPoison.get!(url)
```

### Wrap File Read
```elixir
@decorate normalize_result(wrap_exceptions: true)
def read_json(path), do: File.read!(path) |> Jason.decode!()
```

### Boolean to Result
```elixir
@decorate normalize_result(false_is_error: true)
def valid_age?(age), do: age >= 18
```

### Custom Error Patterns
```elixir
@decorate normalize_result(error_patterns: [:not_found, :timeout, :invalid])
def check_status, do: :not_found
```

### With Transformers
```elixir
@decorate normalize_result(
  nil_is_error: true,
  error_mapper: fn _ -> "Not found" end,
  success_mapper: &Map.take(&1, [:id, :name])
)
def get_user(id), do: Repo.get(User, id)
```

---

## When to Use

✅ **Use when:**
- Wrapping external libraries
- Converting legacy code
- Ensuring API consistency
- Simplifying error handling
- Making functions pipeline-friendly

❌ **Don't use when:**
- Function already returns result tuples consistently
- You need the exact exception (use wrap_exceptions: false)
- Performance is ultra-critical (microseconds matter)

---

## Summary

**The `normalize_result` decorator is your tool for ensuring EVERY function returns `{:ok, result} | {:error, reason}`.**

It's perfect for:
- 🔧 Wrapping external libraries
- 🔄 Converting legacy code
- 🎯 Ensuring consistency
- 🛡️ Exception safety
- 🔗 Pipeline compatibility

**Use it to make your entire codebase follow the same error handling pattern!**

---

## Documentation Files

- **NORMALIZE_RESULT_GUIDE.md** - Complete guide with all options and examples
- **NORMALIZE_RESULT_EXAMPLES.exs** - Interactive examples you can run
- **TYPE_DECORATORS.md** - All type decorators including normalize_result
- **TYPE_SYSTEM_SUMMARY.md** - Overview of the entire type system

---

**Start normalizing your results today! 🚀**
