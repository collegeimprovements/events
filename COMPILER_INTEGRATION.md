# Compiler Integration - Type Decorators and Dialyzer

## Quick Answer

**No, the Elixir compiler cannot directly understand our type decorators.**

However, we can integrate with Dialyzer (Elixir's static analysis tool) to provide compile-time type checking.

---

## Current State

### What Our Type Decorators Do ✅

1. **Runtime Type Validation** - Checks types when functions execute
2. **Development-Time Warnings** - Logs type mismatches in dev/test
3. **Documentation** - Self-documenting code with clear type expectations
4. **Pipeline Support** - Chainable operations with type safety

### What They DON'T Do ❌

1. **Compile-Time Type Checking** - No errors during `mix compile`
2. **Dialyzer Integration** - Don't generate `@spec` annotations
3. **IDE Integration** - Limited autocomplete/type hints
4. **Static Analysis** - Can't catch type errors before runtime

---

## Elixir's Type System Overview

### 1. Typespecs (`@spec`) - Documentation Only

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

**What it does:**
- ✅ Documents function signatures
- ✅ Enables Dialyzer analysis
- ✅ Provides IDE hints (some editors)

**What it doesn't do:**
- ❌ No runtime enforcement
- ❌ No compile-time enforcement (by default)
- ❌ Doesn't prevent you from returning wrong types

### 2. Dialyzer - Static Analysis Tool

Dialyzer analyzes your code and `@spec` annotations to find type inconsistencies.

**Example:**
```elixir
@spec add(integer(), integer()) :: integer()
def add(a, b) do
  "#{a} + #{b}"  # Returns string, not integer!
end
```

Running `mix dialyzer` would catch this:
```
lib/math.ex:2:invalid_contract
The @spec for the function does not match the success typing of the function.
```

---

## How to Integrate Type Decorators with Dialyzer

### Option 1: Manual @spec Annotations (Current Best Practice)

Use both decorators AND manual `@spec`:

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: true)
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

**Pros:**
- ✅ Dialyzer analysis works
- ✅ Runtime validation in dev/test
- ✅ No magic, explicit types

**Cons:**
- ❌ Duplication (type specified twice)
- ❌ Can get out of sync

### Option 2: Automatic @spec Generation (Advanced)

We can enhance decorators to generate `@spec` annotations automatically using Elixir macros.

**How it would work:**

```elixir
# You write:
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
def create_user(attrs) do
  # ...
end

# Decorator expands to:
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  # ... (with runtime validation)
end
```

**Implementation challenge:**
- Need to infer argument types (tricky!)
- `@spec` must be placed before function definition
- Decorator library processes decorators after function is defined

### Option 3: Use Gradualizer (Experimental)

[Gradualizer](https://github.com/josefs/Gradualizer) is an experimental gradual type checker for Elixir.

```elixir
# Would check types at compile time
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

**Status:** Not production-ready, but promising for the future.

---

## Recommended Approach: Hybrid Strategy

### For Most Functions: Manual @spec + Runtime Validation

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: Mix.env() != :prod)
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

**Benefits:**
- ✅ Dialyzer catches issues at compile time
- ✅ Runtime validation in dev/test
- ✅ Zero overhead in production
- ✅ Clear documentation

### For Critical Functions: Strict Runtime Validation

```elixir
@spec charge_payment(integer()) :: {:ok, Payment.t()} | {:error, String.t()}
@decorate returns_result(ok: Payment.t(), error: :string, validate: true, strict: true)
def charge_payment(amount) do
  # Any type mismatch raises immediately
end
```

### For Rapid Development: Decorators Only

```elixir
# Skip @spec during prototyping
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs) do
  # ...
end
```

**Add @spec later when stabilizing:**
```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs) do
  # ...
end
```

---

## Setting Up Dialyzer

### 1. Add Dialyxir to Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

### 2. Configure Dialyzer

```elixir
# mix.exs
def project do
  [
    app: :events,
    dialyzer: [
      plt_add_apps: [:ex_unit],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [
        :error_handling,
        :underspecs,
        :unmatched_returns
      ]
    ]
  ]
end
```

### 3. Build PLT (Persistent Lookup Table)

```bash
mix dialyzer --plt
```

This builds type information for your dependencies (one-time, ~5-10 minutes).

### 4. Run Dialyzer

```bash
mix dialyzer
```

Analyzes your code for type inconsistencies.

---

## Example: Complete Type Safety

```elixir
defmodule MyApp.Users do
  use Events.Decorator
  alias MyApp.User
  alias Ecto.Changeset

  # Dialyzer checks compile-time, decorator checks runtime
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
  @decorate returns_result(ok: User.t(), error: Changeset.t(), validate: true)
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  # Bang variant
  @spec create_user!(map()) :: User.t()
  @decorate returns_bang(User.t())
  def create_user!(attrs) do
    create_user(attrs)
  end

  # Optional return
  @spec find_user(integer()) :: User.t() | nil
  @decorate returns_maybe(User.t())
  def find_user(id) do
    Repo.get(User, id)
  end

  # List return
  @spec all_users() :: [User.t()]
  @decorate returns_list(of: User.t())
  def all_users do
    Repo.all(User)
  end
end
```

**Running Dialyzer:**
```bash
$ mix dialyzer
Compiling 1 file (.ex)
...
Total errors: 0, Skipped: 0, Unnecessary Skips: 0
done in 0m1.23s
```

If you have type errors:
```bash
lib/my_app/users.ex:10:invalid_contract
The @spec return type does not match the function's return type.
```

---

## Type Specifications Cheat Sheet

### Basic Types

```elixir
@spec func() :: :ok                           # Atom
@spec func() :: integer()                     # Integer
@spec func() :: float()                       # Float
@spec func() :: boolean()                     # Boolean
@spec func() :: binary()                      # Binary/String
@spec func() :: atom()                        # Any atom
@spec func() :: map()                         # Any map
@spec func() :: list()                        # Any list
@spec func() :: tuple()                       # Any tuple
@spec func() :: pid()                         # Process ID
@spec func() :: reference()                   # Reference
@spec func() :: any()                         # Any type
```

### Composite Types

```elixir
@spec func() :: [integer()]                   # List of integers
@spec func() :: {integer(), String.t()}       # Tuple
@spec func() :: %{name: String.t()}           # Map with required keys
@spec func() :: %{optional(:key) => value}    # Map with optional keys
```

### Union Types

```elixir
@spec func() :: :ok | :error
@spec func() :: integer() | nil
@spec func() :: {:ok, User.t()} | {:error, atom()}
```

### Custom Types

```elixir
@type user_id :: integer()
@type result :: {:ok, User.t()} | {:error, Changeset.t()}

@spec create_user(user_id()) :: result()
def create_user(id), do: ...
```

### Struct Types

```elixir
@spec func() :: User.t()                      # %User{} struct
@spec func() :: %User{}                       # Also works
@spec func() :: struct()                      # Any struct
```

---

## Benefits of Using Both @spec and Decorators

| Feature | @spec Only | Decorators Only | Both |
|---------|------------|-----------------|------|
| Dialyzer analysis | ✅ | ❌ | ✅ |
| Runtime validation | ❌ | ✅ | ✅ |
| IDE hints | ✅ | ❌ | ✅ |
| Documentation | ✅ | ✅ | ✅ |
| Pipeline helpers | ❌ | ✅ | ✅ |
| Zero prod overhead | ✅ | ⚠️ (if disabled) | ✅ |

**Recommendation:** Use both for production code!

---

## Common Dialyzer Warnings and Fixes

### 1. Contract Mismatch

**Warning:**
```
The @spec return type does not match the function's return type.
```

**Fix:**
```elixir
# Wrong
@spec get_user(integer()) :: User.t()
def get_user(id), do: Repo.get(User, id)  # Returns User.t() | nil

# Right
@spec get_user(integer()) :: User.t() | nil
def get_user(id), do: Repo.get(User, id)
```

### 2. Unmatched Returns

**Warning:**
```
Expression produces a value but it's ignored.
```

**Fix:**
```elixir
# Wrong
def create_user(attrs) do
  User.changeset(%User{}, attrs)  # Returns changeset but not used
  {:ok, %User{}}
end

# Right
def create_user(attrs) do
  changeset = User.changeset(%User{}, attrs)
  Repo.insert(changeset)
end
```

### 3. Overly Specific Types

**Warning:**
```
The function has no local return.
```

**Fix:**
```elixir
# Wrong - too specific
@spec get_status() :: :active
def get_status(), do: :inactive  # Dialyzer: WTF?

# Right
@spec get_status() :: :active | :inactive
def get_status(), do: :inactive
```

---

## Future: Type Decorators with @spec Generation

We could enhance our type decorators to generate `@spec` automatically:

### Proposed Enhancement

```elixir
defmodule Events.Decorator.Types do
  # Add a new option: generate_spec
  @decorate returns_result(
    ok: User.t(),
    error: Ecto.Changeset.t(),
    validate: true,
    generate_spec: true  # <-- NEW
  )
  def create_user(attrs) do
    # ...
  end
end
```

**Implementation would:**
1. Extract argument types from function definition
2. Generate `@spec` annotation before function
3. Add runtime validation wrapper
4. Maintain compatibility with Dialyzer

**Challenges:**
- Inferring argument types is non-trivial
- Decorator library processes after function definition
- Would need to use `Module.put_attribute/3` carefully

**Benefits:**
- Single source of truth for types
- No duplication
- Automatically stays in sync

---

## Comparison with Other Languages

### TypeScript
```typescript
// Compile-time type checking
function createUser(attrs: Attrs): Result<User, Error> {
  return { ok: user };
}
```

### Rust
```rust
// Compile-time type checking + borrow checker
fn create_user(attrs: Attrs) -> Result<User, Error> {
    Ok(user)
}
```

### Elixir (Current)
```elixir
# Optional compile-time (Dialyzer) + optional runtime (our decorators)
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: true)
def create_user(attrs) do
  {:ok, user}
end
```

**Elixir's philosophy:**
- Types are optional (gradual typing)
- Runtime flexibility over compile-time guarantees
- "Let it crash" vs preventing all errors
- Use types where they add value

---

## Conclusion

### Current Best Practice

1. **Write @spec for public APIs** - Helps Dialyzer and documentation
2. **Use type decorators for runtime validation** - Catches bugs in dev/test
3. **Run Dialyzer in CI/CD** - Catch type errors before production
4. **Enable strict mode for critical functions** - Financial transactions, security checks
5. **Keep decorators lightweight in prod** - `validate: Mix.env() != :prod`

### Example Workflow

```elixir
# 1. Development: Use decorators only for speed
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...

# 2. Stabilizing: Add @spec for Dialyzer
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...

# 3. Production: Enable validation in dev only
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(ok: User.t(), error: :atom, validate: Mix.env() != :prod)
def create_user(attrs), do: ...
```

**The combination of @spec + decorators gives you:**
- ✅ Compile-time checking (Dialyzer)
- ✅ Runtime validation (decorators)
- ✅ Great documentation
- ✅ Pipeline helpers
- ✅ Zero prod overhead

---

## References

- [Elixir Typespecs](https://hexdocs.pm/elixir/typespecs.html)
- [Dialyxir Documentation](https://hexdocs.pm/dialyxir)
- [Gradualizer GitHub](https://github.com/josefs/Gradualizer)
- [Type checking in Elixir](https://dashbit.co/blog/typing-elixir)
