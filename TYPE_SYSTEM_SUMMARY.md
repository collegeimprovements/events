# Type System Summary - Quick Reference

## TL;DR

**Question:** Can Elixir compiler understand our type decorators?

**Answer:** No, but we can make them work with Dialyzer (Elixir's static analyzer) by adding `@spec` annotations.

---

## Three-Layer Type Safety

### Layer 1: Documentation (Default)

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...
```

- ✅ Self-documenting code
- ✅ Zero runtime overhead
- ❌ No compile-time checking
- ❌ No runtime validation

**Use when:** Prototyping, non-critical functions

---

### Layer 2: Runtime Validation (Dev/Test)

```elixir
@decorate returns_result(
  ok: User.t(),
  error: :atom,
  validate: Mix.env() != :prod
)
def create_user(attrs), do: ...
```

- ✅ Catches bugs during development
- ✅ Zero prod overhead (disabled in production)
- ✅ Detailed error messages
- ❌ No compile-time checking

**Use when:** Development, testing, debugging

---

### Layer 3: Static Analysis (Dialyzer)

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(
  ok: User.t(),
  error: :atom,
  validate: Mix.env() != :prod
)
def create_user(attrs), do: ...
```

- ✅ Compile-time type checking
- ✅ Runtime validation in dev/test
- ✅ IDE hints and autocomplete
- ✅ Catches errors before production

**Use when:** Production code, public APIs

---

## Comparison Table

| Feature | @spec Only | Decorators Only | @spec + Decorators |
|---------|-----------|-----------------|-------------------|
| **Compile-time checking** | ✅ (Dialyzer) | ❌ | ✅ |
| **Runtime validation** | ❌ | ✅ | ✅ |
| **IDE support** | ✅ | ❌ | ✅ |
| **Pipeline helpers** | ❌ | ✅ | ✅ |
| **Zero prod overhead** | ✅ | ⚠️ | ✅ |
| **Documentation** | ✅ | ✅ | ✅ |
| **Boilerplate** | Medium | Low | Medium |

**Recommendation:** Use both `@spec` and decorators for production code.

---

## Quick Setup

### 1. Install Dialyzer (5 minutes)

```bash
# Add to mix.exs
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}

# Install
mix deps.get

# Build PLT (one-time, 5-10 min)
mix dialyzer --plt
```

### 2. Add @spec to Functions

```elixir
# Before
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...

# After
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(ok: User.t(), error: :atom, validate: true)
def create_user(attrs), do: ...
```

### 3. Run Dialyzer

```bash
mix dialyzer
```

---

## Real-World Example

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  # Result type - most common pattern
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  @decorate returns_result(
    ok: User.t(),
    error: Ecto.Changeset.t(),
    validate: Mix.env() != :prod
  )
  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end

  # Bang variant
  @spec create_user!(map()) :: User.t()
  @decorate returns_bang(User.t())
  def create_user!(attrs) do
    create_user(attrs)  # Automatically unwraps or raises
  end

  # Optional/Maybe type
  @spec find_user(integer()) :: User.t() | nil
  @decorate returns_maybe(User.t())
  def find_user(id) do
    Repo.get(User, id)
  end

  # List type
  @spec all_users() :: [User.t()]
  @decorate returns_list(of: User.t())
  def all_users do
    Repo.all(User)
  end

  # Pipeline-compatible
  @spec register_user(map()) :: {:ok, User.t()} | {:error, String.t()}
  @decorate returns_pipeline(ok: User.t(), error: :string)
  def register_user(attrs) do
    attrs
    |> create_user()
    |> and_then(&send_welcome_email/1)
    |> and_then(&create_settings/1)
  end
end
```

---

## When to Use Each Decorator

### `returns_result` - Most Common

```elixir
@spec func(input) :: {:ok, value} | {:error, reason}
@decorate returns_result(ok: User.t(), error: :atom)
```

**Use for:**
- Database operations (insert, update, delete)
- API calls
- File operations
- Any operation that can fail

---

### `returns_maybe` - Optional Values

```elixir
@spec func(input) :: value | nil
@decorate returns_maybe(User.t())
```

**Use for:**
- Database lookups (`Repo.get`)
- Finding records
- Optional associations
- Configuration values

---

### `returns_bang` - Raise on Error

```elixir
@spec func!(input) :: value
@decorate returns_bang(User.t())
```

**Use for:**
- Bang variants of functions
- Controller actions (let errors bubble)
- When you want to fail fast

---

### `returns_struct` - Specific Structs

```elixir
@spec func(input) :: %User{}
@decorate returns_struct(User, nullable: false)
```

**Use for:**
- Functions returning specific structs
- Builders and factories
- Non-nullable struct returns

---

### `returns_list` - Lists with Constraints

```elixir
@spec func() :: [User.t()]
@decorate returns_list(of: User.t(), min_length: 1, max_length: 100)
```

**Use for:**
- Querying multiple records
- Pagination
- Batch operations

---

### `returns_union` - Multiple Possible Types

```elixir
@spec func(input) :: User.t() | Organization.t() | nil
@decorate returns_union(types: [User.t(), Organization.t(), nil])
```

**Use for:**
- Polymorphic returns
- Conditional logic with different types
- API adapters

---

### `returns_pipeline` - Chainable Operations

```elixir
@spec func(input) :: {:ok, value} | {:error, reason}
@decorate returns_pipeline(ok: User.t(), error: :string)
```

**Use for:**
- Multi-step operations
- Transaction flows
- Complex business logic with error handling

---

## Type Specification Quick Reference

```elixir
# Basic types
@spec func() :: integer()
@spec func() :: String.t()
@spec func() :: atom()
@spec func() :: boolean()
@spec func() :: map()
@spec func() :: list()

# Structs
@spec func() :: User.t()
@spec func() :: %User{}

# Lists
@spec func() :: [User.t()]
@spec func() :: list(integer())

# Tuples
@spec func() :: {:ok, User.t()}
@spec func() :: {integer(), String.t()}

# Union types
@spec func() :: User.t() | nil
@spec func() :: {:ok, User.t()} | {:error, atom()}

# Maps
@spec func() :: %{name: String.t(), age: integer()}
@spec func() :: %{optional(atom()) => any()}

# Custom types
@type user_id :: pos_integer()
@spec func(user_id()) :: User.t()
```

---

## Decision Tree

```
Do you need type safety?
├─ No → Don't use decorators or @spec
└─ Yes → Is this a public API?
    ├─ No → Just use decorators
    │   @decorate returns_result(ok: User.t(), error: :atom)
    │
    └─ Yes → Use both @spec and decorators
        @spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
        @decorate returns_result(ok: User.t(), error: :atom, validate: true)
```

---

## Migration Path

### Phase 1: Add Decorators (Quick)

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...
```

**Time:** 5 minutes per module
**Benefit:** Self-documenting, runtime validation available

---

### Phase 2: Add @spec (When Stabilizing)

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs), do: ...
```

**Time:** 10 minutes per module
**Benefit:** Dialyzer analysis, IDE hints

---

### Phase 3: Enable Validation (Development)

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
@decorate returns_result(
  ok: User.t(),
  error: :atom,
  validate: Mix.env() != :prod
)
def create_user(attrs), do: ...
```

**Time:** 2 minutes per module
**Benefit:** Catch bugs during development

---

### Phase 4: CI/CD Integration

```yaml
# .github/workflows/ci.yml
- name: Run Dialyzer
  run: mix dialyzer
```

**Time:** 30 minutes one-time setup
**Benefit:** Catch type errors before production

---

## Key Takeaways

1. **Elixir's type system is optional** - You choose when and where to use it

2. **Three layers of safety:**
   - Documentation (decorators only)
   - Runtime validation (decorators with `validate: true`)
   - Static analysis (@spec + Dialyzer)

3. **Best practice: Use both @spec and decorators**
   - @spec for compile-time checking (Dialyzer)
   - Decorators for runtime validation (dev/test)

4. **Zero production overhead**
   - Disable validation with `validate: Mix.env() != :prod`
   - @spec has no runtime cost

5. **Gradual adoption**
   - Start with decorators (quick)
   - Add @spec when stabilizing APIs
   - Enable validation in critical paths
   - Integrate Dialyzer in CI/CD

---

## Resources

- **TYPE_DECORATORS.md** - Complete guide to all type decorators
- **COMPILER_INTEGRATION.md** - Deep dive into Dialyzer integration
- **DIALYZER_SETUP.md** - Step-by-step setup guide
- [Elixir Typespecs](https://hexdocs.pm/elixir/typespecs.html) - Official docs
- [Dialyxir](https://hexdocs.pm/dialyxir) - Dialyzer integration

---

## Common Questions

### Q: Do I need to use both @spec and decorators?

**A:** For production code, yes. @spec gives you compile-time checking (Dialyzer), decorators give you runtime validation and pipeline helpers.

### Q: What's the performance cost?

**A:** With `validate: Mix.env() != :prod`, there's zero cost in production. In dev/test, the overhead is minimal (microseconds per function call).

### Q: Can decorators generate @spec automatically?

**A:** Not currently, but it's technically possible as a future enhancement. For now, write both.

### Q: Should I use strict mode?

**A:** Only for critical functions (payments, security checks). Use `validate: true, strict: true` to raise on type mismatches.

### Q: How do I run Dialyzer?

**A:**
```bash
mix dialyzer --plt  # One-time PLT build
mix dialyzer        # Run analysis
```

### Q: What if Dialyzer is too slow?

**A:** Cache the PLT file and run in parallel: `mix dialyzer --parallel`

---

## Next Steps

1. ✅ Read **TYPE_DECORATORS.md** for examples
2. ✅ Read **DIALYZER_SETUP.md** for setup instructions
3. ✅ Add type decorators to your functions
4. ✅ Add @spec to public APIs
5. ✅ Run `mix dialyzer` to catch type errors
6. ✅ Enable runtime validation in dev/test
7. ✅ Integrate Dialyzer into CI/CD

**Happy typing! 🎉**
