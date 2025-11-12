# Type Decorators - Complete Guide

## Overview

The type decorator system provides runtime type validation and documentation for common Elixir return type patterns. It supports Result types, Maybe/Optional types, Bang variants, Structs, Lists, Union types, and Pipeline-compatible results.

## Features

- **Runtime Type Validation** - Optional validation in dev/test environments
- **Strict Mode** - Raises on type mismatches for critical functions
- **Type Documentation** - Clear @spec annotations without boilerplate
- **Pipeline Support** - Chainable operations with `and_then`, `map_ok`, `map_error`
- **Union Types** - Multiple possible return types
- **Flexible Configuration** - Enable/disable validation per decorator

---

## Quick Reference

| Decorator | Use Case | Example Return Type |
|-----------|----------|---------------------|
| `@decorate returns_result` | `{:ok, value} \| {:error, reason}` | `{:ok, User.t()} \| {:error, atom()}` |
| `@decorate returns_maybe` | `value \| nil` | `User.t() \| nil` |
| `@decorate returns_bang` | Bang variants (unwrap or raise) | `User.t()` |
| `@decorate returns_struct` | Specific struct types | `%User{}` |
| `@decorate returns_list` | List with element validation | `[User.t()]` |
| `@decorate returns_union` | Multiple possible types | `User.t() \| Organization.t() \| nil` |
| `@decorate returns_pipeline` | Pipeline-compatible results | `PipelineResult.t()` |

---

## Detailed Documentation

### 1. `returns_result` - Result Type Pattern

The most common Elixir pattern for functions that can succeed or fail.

**Options:**
- `:ok` - Type specification for success value (required)
- `:error` - Type specification for error reason (required)
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# Basic usage with atom types
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# With runtime validation enabled
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: true)
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# Strict mode - raises on type mismatch
@decorate returns_result(ok: :integer, error: :string, validate: true, strict: true)
def divide(a, b) do
  if b == 0 do
    {:error, "Division by zero"}
  else
    {:ok, div(a, b)}
  end
end

# Nested result types
@decorate returns_result(ok: {:list, User.t()}, error: {:map, :atom, :string})
def fetch_users(filters) do
  case validate_filters(filters) do
    :ok -> {:ok, Repo.all(User)}
    {:error, reasons} -> {:error, reasons}
  end
end
```

**Type Validation:**
- Verifies result matches `{:ok, value} | {:error, reason}` pattern
- Checks `:ok` value matches expected type
- Checks `:error` reason matches expected type
- Logs warnings or raises exceptions based on `:strict` mode

---

### 2. `returns_maybe` - Optional/Maybe Type

For functions that may or may not return a value (like `Repo.get/2`).

**Options:**
- First positional argument - Type specification for non-nil value (required)
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# Basic optional type
@decorate returns_maybe(User.t())
def find_user(email) do
  Repo.get_by(User, email: email)
end

# With validation
@decorate returns_maybe(User.t(), validate: true)
def find_user_by_id(id) do
  Repo.get(User, id)
end

# Optional list
@decorate returns_maybe({:list, :integer})
def parse_numbers(string) do
  case Integer.parse(string) do
    {num, ""} -> [num]
    _ -> nil
  end
end

# Optional struct with strict mode
@decorate returns_maybe(Organization.t(), validate: true, strict: true)
def current_organization(user) do
  user.organization
end
```

**Type Validation:**
- Accepts `nil` as valid
- If non-nil, validates against specified type
- Useful for database lookups, optional config, nullable associations

---

### 3. `returns_bang` - Bang Variant Pattern

Automatically unwraps `{:ok, value}` or raises on `{:error, reason}`.

**Options:**
- First positional argument - Expected return type (required)
- `:on_error` - Error handling strategy: `:unwrap` (default) or `:raise`
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# Unwraps {:ok, value} or raises on {:error, reason}
@decorate returns_bang(User.t())
def get_user!(id) do
  User.get(id)  # Returns {:ok, user} or {:error, reason}
end
# Calling get_user!(123) returns %User{} directly or raises

# With custom error handling
@decorate returns_bang(User.t(), on_error: :raise)
def fetch_user!(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end

# Bang variant with validation
@decorate returns_bang(:integer, validate: true, strict: true)
def count_users! do
  case Repo.aggregate(User, :count) do
    count when is_integer(count) -> {:ok, count}
    _ -> {:error, "Failed to count users"}
  end
end
```

**Behavior:**
- If function returns `{:ok, value}`, unwraps to `value`
- If function returns `{:error, reason}`, raises `UnwrapError`
- Validates unwrapped value matches expected type
- Perfect for controller actions where you want to let errors bubble up

---

### 4. `returns_struct` - Struct Type Validation

Validates return value is a specific struct type.

**Options:**
- First positional argument - Struct module (required)
- `:nullable` - Allow nil returns (default: `false`)
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# Non-nullable struct
@decorate returns_struct(User)
def build_user(attrs) do
  struct!(User, attrs)
end

# Nullable struct (like Repo.get)
@decorate returns_struct(User, nullable: true)
def find_user(id) do
  Repo.get(User, id)
end

# With validation enabled
@decorate returns_struct(Organization, validate: true, strict: true)
def create_organization(attrs) do
  %Organization{name: attrs[:name], slug: attrs[:slug]}
end

# Embedded struct
@decorate returns_struct(User.Profile, nullable: true)
def get_profile(user) do
  user.profile
end
```

**Type Validation:**
- Verifies return value is struct of specified module
- If `:nullable` is true, allows nil
- If `:nullable` is false, raises/logs on nil
- Useful for database models, embedded schemas, custom structs

---

### 5. `returns_list` - List Type with Constraints

Validates list returns with optional element type and length constraints.

**Options:**
- `:of` - Element type specification (optional, default: `:any`)
- `:min_length` - Minimum list length (optional)
- `:max_length` - Maximum list length (optional)
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# List of users
@decorate returns_list(of: User.t())
def all_users do
  Repo.all(User)
end

# List with length constraints
@decorate returns_list(of: :integer, min_length: 1, max_length: 100)
def recent_ids do
  User
  |> limit(100)
  |> select([u], u.id)
  |> Repo.all()
end

# With validation enabled
@decorate returns_list(of: User.t(), validate: true, strict: true)
def active_users do
  User
  |> where([u], u.active == true)
  |> Repo.all()
end

# List without element type constraint
@decorate returns_list(min_length: 1)
def get_tags do
  ["elixir", "phoenix", "ecto"]
end

# Paginated list with max length
@decorate returns_list(of: Post.t(), max_length: 50, validate: true)
def paginated_posts(page) do
  Post
  |> limit(50)
  |> offset(^(page * 50))
  |> Repo.all()
end
```

**Type Validation:**
- Verifies return value is a list
- Validates each element matches `:of` type if specified
- Checks `:min_length` constraint
- Checks `:max_length` constraint
- Logs/raises violations based on `:strict` mode

---

### 6. `returns_union` - Union Type Pattern

For functions that can return multiple different types.

**Options:**
- `:types` - List of allowed types (required)
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# Entity that could be User or Organization
@decorate returns_union(types: [User.t(), Organization.t(), nil])
def find_entity(id) do
  Repo.get(User, id) || Repo.get(Organization, id)
end

# Multiple return types
@decorate returns_union(types: [:integer, :string, nil])
def parse_value(input) do
  case Integer.parse(input) do
    {num, ""} -> num
    _ -> input
  end
end

# With validation
@decorate returns_union(types: [User.t(), :anonymous], validate: true)
def current_user(conn) do
  conn.assigns[:current_user] || :anonymous
end

# Result or direct value
@decorate returns_union(types: [{:ok, User.t()}, {:error, :atom}, User.t()])
def flexible_fetch(id, mode: :direct) do
  if mode == :direct do
    Repo.get!(User, id)
  else
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

**Type Validation:**
- Verifies return value matches at least one type in `:types`
- Supports primitive types, struct types, patterns
- Logs/raises if no types match
- Perfect for polymorphic returns, API adapters, conditional logic

---

### 7. `returns_pipeline` - Pipeline-Compatible Results

Wraps results in a `PipelineResult` struct with chainable operations.

**Options:**
- `:ok` - Type specification for success value (required)
- `:error` - Type specification for error reason (required)
- `:validate` - Enable runtime validation (default: `false`)
- `:strict` - Raise on mismatch instead of logging (default: `false`)

**Examples:**

```elixir
# Basic pipeline result
@decorate returns_pipeline(ok: User.t(), error: Ecto.Changeset.t())
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# Chaining operations
def register_user(attrs) do
  attrs
  |> create_user()
  |> and_then(&send_welcome_email/1)
  |> and_then(&create_default_organization/1)
  |> map_ok(&UserView.render/1)
  |> map_error(&format_error/1)
end

# With validation
@decorate returns_pipeline(ok: Post.t(), error: :atom, validate: true)
def create_post(user, attrs) do
  %Post{user_id: user.id}
  |> Post.changeset(attrs)
  |> Repo.insert()
end

# Complex pipeline
@decorate returns_pipeline(ok: %{user: User.t(), token: :string}, error: :string)
def authenticate(email, password) do
  email
  |> find_user_by_email()
  |> and_then(&verify_password(&1, password))
  |> and_then(&generate_token/1)
  |> map_ok(fn user -> %{user: user, token: generate_token(user)} end)
  |> map_error(fn _ -> "Authentication failed" end)
end
```

**PipelineResult API:**

```elixir
# and_then - chains operations, only runs on success
result
|> and_then(fn user -> send_email(user) end)
|> and_then(&update_last_login/1)

# map_ok - transforms success value
result
|> map_ok(fn user -> UserView.render(user) end)

# map_error - transforms error reason
result
|> map_error(fn changeset -> format_errors(changeset) end)

# unwrap - extracts {:ok, value} or raises
result |> unwrap()  # Returns value or raises UnwrapError

# unwrap_or - extracts value or returns default
result |> unwrap_or(%User{})

# to_tuple - converts back to {:ok, value} | {:error, reason}
result |> to_tuple()
```

**Type Validation:**
- Validates result is `{:ok, value} | {:error, reason}`
- Wraps in `PipelineResult` struct
- Provides chainable methods for composition
- Perfect for multi-step operations, transaction flows

---

## Type Specifications

The type system supports the following type specifications:

### Primitive Types
- `:atom` - Atom values
- `:string` - Binary strings
- `:integer` - Integer numbers
- `:float` - Float numbers
- `:boolean` - true/false
- `:list` - Any list
- `:map` - Any map
- `:tuple` - Any tuple
- `:pid` - Process identifier
- `:reference` - Reference
- `:any` - Any value (no validation)
- `nil` - nil value

### Struct Types
```elixir
User.t()              # User struct
Organization.t()      # Organization struct
Ecto.Changeset.t()    # Ecto changeset
```

### Pattern Types
```elixir
{:ok, User.t()}                    # OK tuple with User
{:error, :atom}                    # Error tuple with atom
{:list, User.t()}                  # List of users
{:map, :atom, :string}             # Map with atom keys, string values
```

---

## Validation Modes

### 1. Documentation Only (Default)
```elixir
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...
```
- Only adds @spec annotation
- No runtime overhead
- Use in production for documentation

### 2. Runtime Validation (Dev/Test)
```elixir
@decorate returns_result(ok: User.t(), error: :atom, validate: true)
def create_user(attrs), do: ...
```
- Validates return type at runtime
- Logs warnings on mismatch
- Useful during development

### 3. Strict Mode (Critical Functions)
```elixir
@decorate returns_result(ok: User.t(), error: :atom, validate: true, strict: true)
def create_user(attrs), do: ...
```
- Validates return type at runtime
- Raises `TypeError` on mismatch
- Use for critical functions where type safety is essential

---

## Error Handling

### TypeError Exception
```elixir
defmodule Events.Decorator.Types.TypeError do
  defexception [:message]
end
```

Raised in strict mode when type validation fails:
```elixir
** (Events.Decorator.Types.TypeError) Type mismatch in MyApp.Users.create_user/1: Expected {:ok, User.t()}, got {:ok, :invalid}
```

### UnwrapError Exception
```elixir
defmodule Events.Decorator.Types.UnwrapError do
  defexception [:message, :reason]
end
```

Raised when unwrapping `{:error, reason}` in bang variants:
```elixir
** (Events.Decorator.Types.UnwrapError) Failed to unwrap result in MyApp.Users.get_user!/1: :not_found
```

---

## Performance Considerations

### Compile-Time vs Runtime

**Compile-Time (No Validation):**
- Zero runtime overhead
- Only adds @spec annotations
- Recommended for production

**Runtime Validation:**
- Small overhead per function call
- Only enabled with `validate: true`
- Useful in dev/test environments

### Best Practices

1. **Use validation in dev/test only**
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom, validate: Mix.env() != :prod)
   ```

2. **Enable strict mode for critical functions**
   ```elixir
   @decorate returns_result(ok: :integer, error: :string, validate: true, strict: true)
   def charge_payment(amount), do: ...
   ```

3. **Document only in production**
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom)
   def create_user(attrs), do: ...
   ```

---

## Real-World Examples

### API Client with Error Handling
```elixir
defmodule MyApp.APIClient do
  use Events.Decorator

  @decorate returns_result(ok: :map, error: :string, validate: true)
  def fetch_user(id) do
    case HTTPoison.get("https://api.example.com/users/#{id}") do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @decorate returns_bang(:map)
  def fetch_user!(id) do
    fetch_user(id)
  end
end
```

### Database Repository Pattern
```elixir
defmodule MyApp.UserRepository do
  use Events.Decorator

  @decorate returns_maybe(User.t())
  def find(id) do
    Repo.get(User, id)
  end

  @decorate returns_bang(User.t())
  def get!(id) do
    case find(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @decorate returns_list(of: User.t(), validate: true)
  def all do
    Repo.all(User)
  end

  @decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
  def create(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

### Multi-Step Pipeline
```elixir
defmodule MyApp.Registration do
  use Events.Decorator

  @decorate returns_pipeline(ok: User.t(), error: :string)
  def register(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def complete_registration(attrs) do
    attrs
    |> register()
    |> and_then(&send_welcome_email/1)
    |> and_then(&create_default_settings/1)
    |> map_ok(&UserView.render/1)
    |> map_error(fn
      %Ecto.Changeset{} = cs -> format_changeset_errors(cs)
      error -> inspect(error)
    end)
  end
end
```

---

## Migration Guide

### From Manual @spec to Type Decorators

**Before:**
```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

**After:**
```elixir
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

**Benefits:**
- Runtime validation available
- Consistent type documentation
- Less boilerplate
- Chainable pipeline operations

---

## Testing Type Decorators

```elixir
defmodule MyApp.UsersTest do
  use ExUnit.Case

  describe "create_user/1" do
    test "returns {:ok, user} on success" do
      attrs = %{email: "test@example.com", name: "Test"}
      assert {:ok, %User{}} = Users.create_user(attrs)
    end

    test "returns {:error, changeset} on validation failure" do
      attrs = %{email: "invalid"}
      assert {:error, %Ecto.Changeset{}} = Users.create_user(attrs)
    end
  end

  describe "get_user!/1 with returns_bang" do
    test "returns user when found" do
      user = insert(:user)
      assert %User{id: ^user.id} = Users.get_user!(user.id)
    end

    test "raises on not found" do
      assert_raise Events.Decorator.Types.UnwrapError, fn ->
        Users.get_user!(999999)
      end
    end
  end

  describe "find_user/1 with returns_maybe" do
    test "returns user when found" do
      user = insert(:user)
      assert %User{} = Users.find_user(user.id)
    end

    test "returns nil when not found" do
      assert nil == Users.find_user(999999)
    end
  end
end
```

---

## Summary

The type decorator system provides:

✅ **Runtime Type Validation** - Catch type errors early in development
✅ **Clear Documentation** - @spec annotations with less boilerplate
✅ **Pipeline Support** - Chainable operations for multi-step flows
✅ **Flexible Validation** - Enable/disable per decorator
✅ **Multiple Patterns** - Result, Maybe, Bang, Struct, List, Union types
✅ **Production Ready** - Zero overhead when validation disabled
✅ **Developer Friendly** - Clear error messages and intuitive API

Use type decorators to make your Elixir code more robust, self-documenting, and maintainable!
