# Code Patterns Reference

> **This file contains executable examples.** All code blocks are tested and should be used as templates.

## Pattern Matching

### Function Clauses Over Conditionals

```elixir
# CORRECT - Multiple function clauses
def process({:ok, value}), do: {:ok, transform(value)}
def process({:error, reason}), do: {:error, reason}
def process(nil), do: {:error, :nil_input}

# WRONG - Nested conditionals
def process(result) do
  if result do
    case result do
      {:ok, value} -> {:ok, transform(value)}
      {:error, reason} -> {:error, reason}
    end
  else
    {:error, :nil_input}
  end
end
```

### Guard Clauses

```elixir
# CORRECT - Guards in function heads
def calculate_discount(%{type: :premium, total: total}) when total > 1000, do: total * 0.20
def calculate_discount(%{type: :premium, total: total}), do: total * 0.10
def calculate_discount(%{type: :regular, total: total}) when total > 1000, do: total * 0.10
def calculate_discount(%{type: :regular, total: total}), do: total * 0.05
def calculate_discount(_), do: 0

# WRONG - Nested if statements
def calculate_discount(order) do
  if order.type == :premium do
    if order.total > 1000, do: order.total * 0.20, else: order.total * 0.10
  else
    if order.total > 1000, do: order.total * 0.10, else: order.total * 0.05
  end
end
```

### Destructuring in Function Heads

```elixir
# CORRECT
def render_user(%User{name: name, email: email, role: :admin}) do
  "Admin: #{name} (#{email})"
end

def render_user(%User{name: name, email: email}) do
  "User: #{name} (#{email})"
end

# WRONG
def render_user(user) do
  if user.role == :admin do
    "Admin: #{user.name} (#{user.email})"
  else
    "User: #{user.name} (#{user.email})"
  end
end
```

### Early Returns

```elixir
# CORRECT - Early validation with pattern matching
def process(nil), do: {:error, :nil_input}
def process(""), do: {:error, :empty_input}
def process(value) when byte_size(value) > 1000, do: {:error, :too_large}
def process(value), do: {:ok, String.upcase(value)}

# WRONG - Deeply nested validation
def process(value) do
  if value do
    if value != "" do
      if byte_size(value) <= 1000 do
        {:ok, String.upcase(value)}
      else
        {:error, :too_large}
      end
    else
      {:error, :empty_input}
    end
  else
    {:error, :nil_input}
  end
end
```

---

## Result Tuples

### All Fallible Functions Return Result Tuples

```elixir
# CORRECT
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# WRONG - Returning raw value or raising
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert!()  # Never use bang in app code
end
```

### Pattern Match on Results

```elixir
# CORRECT - Flat case statement
case create_user(attrs) do
  {:ok, user} -> send_welcome_email(user)
  {:error, changeset} -> log_validation_errors(changeset)
end

# CORRECT - with for sequential operations
with {:ok, user} <- create_user(attrs),
     {:ok, _email} <- send_welcome_email(user),
     {:ok, _settings} <- create_default_settings(user) do
  {:ok, user}
end

# WRONG - Nested case
case create_user(attrs) do
  {:ok, user} ->
    case send_welcome_email(user) do
      {:ok, _} ->
        case create_default_settings(user) do
          {:ok, _} -> {:ok, user}
          error -> error
        end
      error -> error
    end
  error -> error
end
```

---

## Pipeline Operator

### Flat Transformations

```elixir
# CORRECT - Flat pipeline
def process_data(data) do
  data
  |> validate()
  |> transform()
  |> enrich()
  |> persist()
end

# WRONG - Nested function calls
def process_data(data) do
  persist(enrich(transform(validate(data))))
end
```

---

## Macros

### When NOT to Use Macros

```elixir
# WRONG - Macro for simple logic
defmacro double(x) do
  quote do: unquote(x) * 2
end

# CORRECT - Plain function
def double(x), do: x * 2

# WRONG - Macro for conditional
defmacro when_admin(user, do: block) do
  quote do
    if unquote(user).role == :admin, do: unquote(block)
  end
end

# CORRECT - Pattern matching function
def when_admin(%User{role: :admin}, fun), do: fun.()
def when_admin(%User{}, _fun), do: :ok
```

### When Macros ARE Acceptable

- Building DSLs (Phoenix routes, Ecto schemas)
- Compile-time optimizations
- Code generation from external sources
- Library-level abstractions (decorator system)

---

## Quick Reference

| Scenario | Use This | Not This |
|----------|----------|----------|
| Multiple conditions | `case` or `cond` | `if...else if` |
| Function variations | Multiple function clauses | Single function with if |
| Sequential operations | `with` | Nested `case` |
| Transformations | Pipe `\|>` | Nested calls |
| Error handling | `{:ok, _} \| {:error, _}` | Mixed returns |
| Validation | Guard clauses | if inside function |
| Polymorphism | Protocols | Macros |
| Contracts | Behaviours | Macros |
