# Dialyzer Setup Guide for Events Project

## Quick Start

### 1. Install Dialyxir

Already in your dependencies, but if not:

```elixir
# mix.exs
defp deps do
  [
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

Then:
```bash
mix deps.get
```

### 2. Build PLT (one-time setup, ~5-10 minutes)

```bash
mix dialyzer --plt
```

This builds a Persistent Lookup Table with type information for Erlang, Elixir, and your dependencies.

### 3. Run Dialyzer

```bash
mix dialyzer
```

---

## Example: Adding @spec to Existing Functions

Let's add proper type specifications to work with our type decorators.

### Before (Decorators Only)

```elixir
defmodule Events.Users do
  use Events.Decorator

  @decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

**Issues:**
- ❌ Dialyzer can't analyze this
- ❌ No IDE hints for argument types
- ❌ No compile-time type checking

### After (With @spec)

```elixir
defmodule Events.Users do
  use Events.Decorator

  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  @decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: true)
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

**Benefits:**
- ✅ Dialyzer analyzes types
- ✅ IDE provides hints
- ✅ Runtime validation in dev/test
- ✅ Comprehensive type safety

---

## Complete Example Module

```elixir
defmodule MyApp.UserRepository do
  @moduledoc """
  User repository with comprehensive type safety.

  Uses both @spec (for Dialyzer) and type decorators (for runtime validation).
  """

  use Events.Decorator
  alias MyApp.{User, Repo}
  alias Ecto.Changeset

  ## Types

  @type user_id :: pos_integer()
  @type user_attrs :: %{
    optional(:name) => String.t(),
    optional(:email) => String.t(),
    optional(:age) => non_neg_integer()
  }
  @type create_result :: {:ok, User.t()} | {:error, Changeset.t()}
  @type update_result :: {:ok, User.t()} | {:error, Changeset.t()}

  ## Functions

  @doc """
  Creates a new user.

  ## Examples

      iex> create_user(%{name: "John", email: "john@example.com"})
      {:ok, %User{}}

      iex> create_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_user(user_attrs()) :: create_result()
  @decorate returns_result(
    ok: User.t(),
    error: Changeset.t(),
    validate: Mix.env() != :prod
  )
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new user, raising on error.
  """
  @spec create_user!(user_attrs()) :: User.t()
  @decorate returns_bang(User.t())
  def create_user!(attrs) do
    create_user(attrs)
  end

  @doc """
  Finds a user by ID.

  Returns the user if found, nil otherwise.
  """
  @spec find_user(user_id()) :: User.t() | nil
  @decorate returns_maybe(User.t())
  def find_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Gets a user by ID, raising if not found.
  """
  @spec get_user!(user_id()) :: User.t()
  @decorate returns_bang(User.t())
  def get_user!(id) do
    case find_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Updates a user.
  """
  @spec update_user(User.t(), user_attrs()) :: update_result()
  @decorate returns_result(
    ok: User.t(),
    error: Changeset.t(),
    validate: true
  )
  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all users.
  """
  @spec all_users() :: [User.t()]
  @decorate returns_list(of: User.t())
  def all_users do
    Repo.all(User)
  end

  @doc """
  Lists active users with pagination.
  """
  @spec active_users(limit :: pos_integer()) :: [User.t()]
  @decorate returns_list(
    of: User.t(),
    min_length: 0,
    max_length: 100,
    validate: true
  )
  def active_users(limit \\ 50) do
    User
    |> where([u], u.active == true)
    |> limit(^min(limit, 100))
    |> Repo.all()
  end

  @doc """
  Deletes a user.
  """
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  @decorate returns_result(ok: User.t(), error: Changeset.t())
  def delete_user(user) do
    Repo.delete(user)
  end
end
```

---

## Running Dialyzer on This Module

```bash
$ mix dialyzer
Compiling 1 file (.ex)
Total errors: 0, Skipped: 0
done in 0m2.34s
```

If there are type errors, you'll see:
```bash
lib/my_app/user_repository.ex:45:invalid_contract
The @spec return type {:ok, User.t()} | {:error, Changeset.t()} does not match
the success typing: {:ok, %User{}} | {:error, atom()}
```

---

## Common Patterns

### 1. Result Types with Custom Errors

```elixir
@type error_reason ::
  :not_found
  | :unauthorized
  | :validation_failed
  | {:external_api_error, String.t()}

@spec fetch_user(user_id()) :: {:ok, User.t()} | {:error, error_reason()}
@decorate returns_result(ok: User.t(), error: :atom, validate: true)
def fetch_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
```

### 2. Pipeline with Multiple Steps

```elixir
@spec register_user(user_attrs()) :: {:ok, User.t()} | {:error, String.t()}
@decorate returns_pipeline(ok: User.t(), error: :string)
def register_user(attrs) do
  attrs
  |> create_user()
  |> and_then(&send_welcome_email/1)
  |> and_then(&create_default_settings/1)
  |> map_error(&format_error/1)
end

@spec send_welcome_email(User.t()) :: {:ok, User.t()} | {:error, String.t()}
defp send_welcome_email(user) do
  case Mailer.send_welcome(user) do
    {:ok, _} -> {:ok, user}
    {:error, reason} -> {:error, "Email failed: #{inspect(reason)}"}
  end
end

@spec create_default_settings(User.t()) :: {:ok, User.t()} | {:error, String.t()}
defp create_default_settings(user) do
  # ...
end
```

### 3. Union Types for Polymorphic Returns

```elixir
@spec find_entity(pos_integer()) :: User.t() | Organization.t() | nil
@decorate returns_union(types: [User.t(), Organization.t(), nil])
def find_entity(id) do
  Repo.get(User, id) || Repo.get(Organization, id)
end
```

### 4. Strict Validation for Critical Functions

```elixir
@spec charge_payment(user_id(), pos_integer()) ::
  {:ok, Payment.t()} | {:error, String.t()}
@decorate returns_result(
  ok: Payment.t(),
  error: :string,
  validate: true,
  strict: true  # Raises on type mismatch!
)
def charge_payment(user_id, amount) do
  # Critical: any type error raises immediately
  with {:ok, user} <- get_user(user_id),
       {:ok, payment} <- process_charge(user, amount) do
    {:ok, payment}
  end
end
```

---

## Configuring Dialyzer

Add to `mix.exs`:

```elixir
def project do
  [
    app: :events,
    version: "0.1.0",
    elixir: "~> 1.19",

    # Dialyzer configuration
    dialyzer: [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :error_handling,      # Check error handling
        :underspecs,          # Warn about under-specified functions
        :unmatched_returns,   # Warn about ignored return values
        :unknown              # Warn about unknown functions
      ],
      # Ignore warnings in test files
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  ]
end
```

### Create `.dialyzer_ignore.exs`

```elixir
[
  # Ignore warnings from specific files
  {"lib/events/decorator/testing/decorators.ex", :unknown_function},

  # Ignore specific line numbers
  {"lib/events/some_module.ex", :invalid_contract, 42},
]
```

---

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '27'

      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Restore PLT cache
        uses: actions/cache@v3
        id: plt_cache
        with:
          path: priv/plts
          key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: mix deps.get

      - name: Create PLT
        if: steps.plt_cache.outputs.cache-hit != 'true'
        run: mix dialyzer --plt

      - name: Run Dialyzer
        run: mix dialyzer --format github

      - name: Run tests
        run: mix test
```

---

## Troubleshooting

### Issue: "No PLT file found"

**Solution:**
```bash
mix dialyzer --plt
```

### Issue: "Could not load `:crypto` application"

**Solution:**
Make sure Erlang is properly installed with crypto support.

### Issue: Dialyzer is too slow

**Solution 1:** Cache the PLT file
```elixir
# mix.exs
dialyzer: [
  plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
]
```

**Solution 2:** Run in parallel
```bash
mix dialyzer --parallel
```

**Solution 3:** Only check specific files
```bash
mix dialyzer lib/my_app/users.ex
```

### Issue: Too many false positives

**Solution:** Create `.dialyzer_ignore.exs` to suppress specific warnings.

---

## Summary

### Recommended Workflow

1. **Write functions with type decorators first** (for rapid development)
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom)
   def create_user(attrs), do: ...
   ```

2. **Add @spec when stabilizing APIs** (for Dialyzer)
   ```elixir
   @spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
   @decorate returns_result(ok: User.t(), error: :atom)
   def create_user(attrs), do: ...
   ```

3. **Enable validation in dev/test** (catch runtime errors)
   ```elixir
   @spec create_user(map()) :: {:ok, User.t()} | {:error, atom()}
   @decorate returns_result(ok: User.t(), error: :atom, validate: Mix.env() != :prod)
   def create_user(attrs), do: ...
   ```

4. **Run Dialyzer in CI/CD** (catch type errors before production)
   ```bash
   mix dialyzer --format github
   ```

### Benefits

✅ **Compile-time checking** - Dialyzer catches type errors
✅ **Runtime validation** - Decorators catch bugs in dev/test
✅ **Zero prod overhead** - Validation disabled in production
✅ **Great documentation** - Types are self-documenting
✅ **IDE support** - Better autocomplete and hints
✅ **Pipeline helpers** - Chainable operations

**You get the best of both worlds: static analysis AND runtime safety!**
