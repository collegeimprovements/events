# Functional Programming Utilities

This guide covers the functional programming modules in the Events framework:
**Maybe**, **Result**, **AsyncResult**, **Pipeline**, **Guards**, **Lens**, **Resource**, **RateLimiter**, and **Diff**.

## Quick Decision Guide

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Which module should I use?                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Is absence a valid, expected state?                                    │
│    YES → Use Maybe                                                      │
│    NO  → Is it an error?                                                │
│           YES → Use Result                                              │
│                                                                         │
│  Do you need concurrent/parallel operations?                            │
│    YES → Use AsyncResult                                                │
│                                                                         │
│  Do you have multiple sequential steps with shared context?             │
│    YES → Use Pipeline                                                   │
│                                                                         │
│  Do you need pattern matching guards?                                   │
│    YES → Use Guards                                                     │
│                                                                         │
│  Do you need to access/update nested data immutably?                    │
│    YES → Use Lens                                                       │
│                                                                         │
│  Do you need guaranteed resource cleanup (files, connections)?          │
│    YES → Use Resource                                                   │
│                                                                         │
│  Do you need rate limiting / throttling?                                │
│    YES → Use RateLimiter                                                │
│                                                                         │
│  Do you need to track changes, merge, or undo?                          │
│    YES → Use Diff                                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Comparison

### Core Monadic Types

| Feature | Maybe | Result | AsyncResult | Pipeline |
|---------|-------|--------|-------------|----------|
| **Purpose** | Optional values | Error handling | Concurrent ops | Multi-step flows |
| **Representation** | `{:some, v}` / `:none` | `{:ok, v}` / `{:error, e}` | `{:ok, v}` / `{:error, e}` | `%Pipeline{}` |
| **Absence meaning** | Valid, expected | Failure | Failure | N/A |
| **Concurrency** | No | No | Yes | Optional |
| **Context accumulation** | No | No | No | Yes |
| **Rollback support** | No | No | No | Yes |

### Utility Types

| Feature | Lens | Resource | RateLimiter | Diff |
|---------|------|----------|-------------|------|
| **Purpose** | Nested data access | Safe cleanup | Rate limiting | Change tracking |
| **Pure/Functional** | Yes | Yes | Yes | Yes |
| **Composable** | Yes | Yes | Yes | Yes |
| **State** | Stateless | Stateless | Returns new state | Returns diff |

See dedicated documentation:
- [Lens](LENS.md) - Functional lenses for immutable data
- [Resource](RESOURCE.md) - Safe resource management
- [RateLimiter](RATE_LIMITER.md) - Multiple rate limiting algorithms
- [Diff](DIFF.md) - Diffing, patching, and merging

---

## Maybe

Use `Maybe` when **absence is a valid, expected state** — not an error condition.

### When to Use Maybe

- Optional user profile fields (middle name, bio, avatar)
- Configuration with defaults
- Cache lookups (miss is expected)
- Finding first match from multiple sources
- Safe nested map/struct access

### When NOT to Use Maybe

- Database lookups by ID → use `Result` (not found is an error)
- Required validation → use `Result`
- External API calls → use `Result` or `AsyncResult`

### Real-World Examples

#### Example 1: Optional User Profile Fields

```elixir
alias Events.Maybe

defmodule UserProfile do
  # Get display name with fallback chain
  def display_name(user) do
    Maybe.first_some([
      fn -> Maybe.from_string(user.display_name) end,
      fn -> Maybe.from_string(user.full_name) end,
      fn -> Maybe.from_string(user.username) end,
      fn -> Maybe.some("Anonymous") end
    ])
    |> Maybe.unwrap!()
  end

  # Get avatar URL with default
  def avatar_url(user) do
    user.avatar_url
    |> Maybe.from_nilable()
    |> Maybe.filter(&valid_url?/1)
    |> Maybe.unwrap_or("/images/default-avatar.png")
  end

  # Get user's age if birthday is set
  def age(user) do
    user.birthday
    |> Maybe.from_nilable()
    |> Maybe.map(&calculate_age/1)
    |> Maybe.filter(&(&1 >= 0))
  end

  defp valid_url?(url), do: String.starts_with?(url, ["http://", "https://"])
  defp calculate_age(birthday), do: Date.diff(Date.utc_today(), birthday) |> div(365)
end

# Usage
user = %{display_name: nil, full_name: "John Doe", username: "johnd", avatar_url: nil}
UserProfile.display_name(user)  #=> "John Doe"
UserProfile.avatar_url(user)    #=> "/images/default-avatar.png"
UserProfile.age(user)           #=> :none
```

#### Example 2: Configuration with Defaults

```elixir
defmodule Config do
  alias Events.Maybe

  def get_database_url do
    Maybe.first_some([
      fn -> Maybe.from_string(System.get_env("DATABASE_URL")) end,
      fn -> Maybe.from_string(Application.get_env(:myapp, :database_url)) end,
      fn -> Maybe.some("postgres://localhost/myapp_dev") end
    ])
    |> Maybe.unwrap!()
  end

  def get_port do
    System.get_env("PORT")
    |> Maybe.from_string()
    |> Maybe.and_then(fn port_str ->
      case Integer.parse(port_str) do
        {port, ""} -> Maybe.some(port)
        _ -> Maybe.none()
      end
    end)
    |> Maybe.filter(&(&1 > 0 and &1 < 65536))
    |> Maybe.unwrap_or(4000)
  end

  def get_feature_flag(flag_name) do
    Application.get_env(:myapp, :features, %{})
    |> Maybe.get(flag_name)
    |> Maybe.unwrap_or(false)
  end
end
```

#### Example 3: Safe Nested Access

```elixir
defmodule DataExtractor do
  alias Events.Maybe

  # Safely extract deeply nested data
  def get_user_email(response) do
    response
    |> Maybe.from_nilable()
    |> Maybe.and_then(fn r -> Maybe.get(r, :data) end)
    |> Maybe.and_then(fn d -> Maybe.get(d, :user) end)
    |> Maybe.and_then(fn u -> Maybe.get(u, :email) end)
    |> Maybe.filter(&valid_email?/1)
  end

  # Or use fetch_path for cleaner nested access
  def get_user_email_v2(response) do
    Maybe.fetch_path(response, [:data, :user, :email])
    |> Maybe.filter(&valid_email?/1)
  end

  # Extract first matching item from a list
  def find_primary_address(user) do
    user.addresses
    |> Maybe.from_list()
    |> Maybe.and_then(fn addresses ->
      addresses
      |> Enum.find(&(&1.primary == true))
      |> Maybe.from_nilable()
    end)
  end

  defp valid_email?(email), do: String.contains?(email, "@")
end
```

#### Example 4: Combining Multiple Optional Values

```elixir
defmodule OrderCalculator do
  alias Events.Maybe

  def calculate_discount(user, promo_code) do
    # Both user loyalty discount and promo code are optional
    loyalty_discount = get_loyalty_discount(user)
    promo_discount = get_promo_discount(promo_code)

    # Combine if both present, take best discount
    Maybe.combine_with(loyalty_discount, promo_discount, fn l, p ->
      max(l, p)
    end)
    |> Maybe.or_else(fn ->
      # If only one exists, use that
      Maybe.or_value(loyalty_discount, promo_discount)
    end)
    |> Maybe.unwrap_or(0)
  end

  # Zip user preferences together
  def build_preferences(user) do
    theme = Maybe.from_nilable(user.theme_preference)
    language = Maybe.from_nilable(user.language_preference)
    timezone = Maybe.from_nilable(user.timezone_preference)

    Maybe.collect([theme, language, timezone])
    |> Maybe.map(fn [t, l, z] ->
      %{theme: t, language: l, timezone: z}
    end)
    |> Maybe.unwrap_or(%{theme: "light", language: "en", timezone: "UTC"})
  end

  defp get_loyalty_discount(user) do
    case user.loyalty_tier do
      :gold -> Maybe.some(0.15)
      :silver -> Maybe.some(0.10)
      :bronze -> Maybe.some(0.05)
      _ -> Maybe.none()
    end
  end

  defp get_promo_discount(nil), do: Maybe.none()
  defp get_promo_discount(code) do
    # Look up promo code...
    Maybe.some(0.20)
  end
end
```

### Maybe API Reference

```elixir
alias Events.Maybe

# ═══════════════════════════════════════════════════════════════════════════
# CREATION
# ═══════════════════════════════════════════════════════════════════════════

Maybe.some(42)                    # {:some, 42}
Maybe.none()                      # :none
Maybe.from_nilable(nil)           # :none
Maybe.from_nilable(42)            # {:some, 42}
Maybe.from_nilable(false)         # {:some, false} - false is not nil!
Maybe.from_result({:ok, v})       # {:some, v}
Maybe.from_result({:error, _})    # :none
Maybe.from_bool(true, 42)         # {:some, 42}
Maybe.from_bool(false, 42)        # :none
Maybe.from_string("")             # :none
Maybe.from_string("  ")           # :none (whitespace only)
Maybe.from_string("hello")        # {:some, "hello"}
Maybe.from_list([])               # :none
Maybe.from_list([1, 2])           # {:some, [1, 2]}
Maybe.from_map(%{})               # :none
Maybe.from_map(%{a: 1})           # {:some, %{a: 1}}
Maybe.when_true(cond, value)      # {:some, value} if cond is true
Maybe.unless_true(cond, value)    # {:some, value} if cond is false

# ═══════════════════════════════════════════════════════════════════════════
# TYPE CHECKING
# ═══════════════════════════════════════════════════════════════════════════

Maybe.some?({:some, 42})          # true
Maybe.some?(:none)                # false
Maybe.none?(:none)                # true
Maybe.none?({:some, 42})          # false

# ═══════════════════════════════════════════════════════════════════════════
# TRANSFORMATION
# ═══════════════════════════════════════════════════════════════════════════

{:some, 5} |> Maybe.map(&(&1 * 2))           # {:some, 10}
:none |> Maybe.map(&(&1 * 2))                # :none

{:some, 5} |> Maybe.replace(42)              # {:some, 42}
:none |> Maybe.replace(42)                   # :none

{:some, 5} |> Maybe.filter(&(&1 > 3))        # {:some, 5}
{:some, 2} |> Maybe.filter(&(&1 > 3))        # :none

{:some, 5} |> Maybe.reject(&(&1 > 3))        # :none
{:some, 2} |> Maybe.reject(&(&1 > 3))        # {:some, 2}

# ═══════════════════════════════════════════════════════════════════════════
# CHAINING (MONADIC BIND / FLAT_MAP)
# ═══════════════════════════════════════════════════════════════════════════

{:some, 5}
|> Maybe.and_then(fn x -> Maybe.some(x * 2) end)  # {:some, 10}

{:some, 5}
|> Maybe.and_then(fn _ -> Maybe.none() end)       # :none

:none
|> Maybe.and_then(fn x -> Maybe.some(x * 2) end)  # :none

:none |> Maybe.or_else(fn -> Maybe.some(42) end)  # {:some, 42}
{:some, 5} |> Maybe.or_else(fn -> Maybe.some(42) end)  # {:some, 5}

Maybe.or_value({:some, 1}, {:some, 2})            # {:some, 1}
Maybe.or_value(:none, {:some, 2})                 # {:some, 2}

# ═══════════════════════════════════════════════════════════════════════════
# EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════

Maybe.unwrap!({:some, 42})                        # 42
Maybe.unwrap!(:none)                              # raises ArgumentError

Maybe.unwrap_or({:some, 42}, 0)                   # 42
Maybe.unwrap_or(:none, 0)                         # 0

Maybe.unwrap_or_else(:none, fn -> expensive() end)  # calls expensive()
Maybe.unwrap_or_else({:some, 42}, fn -> expensive() end)  # 42 (no call)

Maybe.to_nilable({:some, 42})                     # 42
Maybe.to_nilable(:none)                           # nil

# ═══════════════════════════════════════════════════════════════════════════
# CONVERSION
# ═══════════════════════════════════════════════════════════════════════════

Maybe.to_result({:some, 42}, :not_found)          # {:ok, 42}
Maybe.to_result(:none, :not_found)                # {:error, :not_found}

Maybe.to_bool({:some, 42})                        # true
Maybe.to_bool(:none)                              # false

Maybe.to_list({:some, 42})                        # [42]
Maybe.to_list(:none)                              # []

Maybe.to_enum({:some, 42})                        # [42]
Maybe.to_enum(:none)                              # []

# ═══════════════════════════════════════════════════════════════════════════
# COLLECTION OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════

# Collect: all must be some
Maybe.collect([{:some, 1}, {:some, 2}])           # {:some, [1, 2]}
Maybe.collect([{:some, 1}, :none])                # :none
Maybe.collect([])                                 # {:some, []}

# Cat: filter and unwrap somes
Maybe.cat_somes([{:some, 1}, :none, {:some, 3}]) # [1, 3]

# Traverse: map then collect
Maybe.traverse([1, 2, 3], fn x ->
  if x > 0, do: {:some, x * 2}, else: :none
end)                                              # {:some, [2, 4, 6]}

# Filter map: map and keep somes
Maybe.filter_map([1, 2, 3, 4], fn x ->
  if rem(x, 2) == 0, do: {:some, x * 10}, else: :none
end)                                              # [20, 40]

# First some (lazy)
Maybe.first_some([
  fn -> :none end,
  fn -> {:some, 42} end,
  fn -> raise "never called" end
])                                                # {:some, 42}

# ═══════════════════════════════════════════════════════════════════════════
# COMBINING
# ═══════════════════════════════════════════════════════════════════════════

Maybe.combine({:some, 1}, {:some, 2})             # {:some, {1, 2}}
Maybe.combine(:none, {:some, 2})                  # :none

Maybe.combine_with({:some, 2}, {:some, 3}, &+/2)  # {:some, 5}
Maybe.combine_with(:none, {:some, 3}, &+/2)       # :none

Maybe.zip({:some, 1}, {:some, 2})                 # {:some, {1, 2}}
Maybe.zip_with({:some, 1}, {:some, 2}, &+/2)      # {:some, 3}
Maybe.zip_all([{:some, 1}, {:some, 2}])           # {:some, [1, 2]}

# ═══════════════════════════════════════════════════════════════════════════
# FLATTENING & APPLICATIVE
# ═══════════════════════════════════════════════════════════════════════════

Maybe.flatten({:some, {:some, 42}})               # {:some, 42}
Maybe.flatten({:some, :none})                     # :none
Maybe.flatten(:none)                              # :none

Maybe.apply({:some, &String.upcase/1}, {:some, "hi"})    # {:some, "HI"}
Maybe.apply({:some, &+/2}, {:some, 1}, {:some, 2})       # {:some, 3}
Maybe.apply(:none, {:some, "hi"})                        # :none

# ═══════════════════════════════════════════════════════════════════════════
# FUNCTION LIFTING
# ═══════════════════════════════════════════════════════════════════════════

upcase = Maybe.lift(&String.upcase/1)
upcase.({:some, "hello"})                         # {:some, "HELLO"}
upcase.(:none)                                    # :none

add = Maybe.lift(&+/2)
add.({:some, 1}, {:some, 2})                      # {:some, 3}

Maybe.lift_apply(&String.upcase/1, {:some, "hi"}) # {:some, "HI"}
Maybe.lift_apply(&+/2, {:some, 1}, {:some, 2})    # {:some, 3}

# ═══════════════════════════════════════════════════════════════════════════
# MAP/STRUCT ACCESS
# ═══════════════════════════════════════════════════════════════════════════

Maybe.get(%{name: "Alice"}, :name)                # {:some, "Alice"}
Maybe.get(%{name: nil}, :name)                    # :none (nil values → none)
Maybe.get(%{name: "Alice"}, :age)                 # :none (missing key)

Maybe.fetch_path(%{user: %{profile: %{name: "A"}}}, [:user, :profile, :name])
#=> {:some, "A"}

Maybe.fetch_path(%{user: nil}, [:user, :profile, :name])
#=> :none

# ═══════════════════════════════════════════════════════════════════════════
# SIDE EFFECTS
# ═══════════════════════════════════════════════════════════════════════════

{:some, 42} |> Maybe.tap_some(&IO.inspect/1)      # prints 42, returns {:some, 42}
:none |> Maybe.tap_some(&IO.inspect/1)            # prints nothing, returns :none

:none |> Maybe.tap_none(fn -> IO.puts("none!") end)  # prints "none!"
```

---

## Result

Use `Result` when **failure is an error condition** that needs handling.

### When to Use Result

- Database operations
- External API calls
- Input validation
- File operations
- Any operation that can "fail"

### When NOT to Use Result

- Optional fields → use `Maybe`
- Cache misses (if miss is expected) → use `Maybe`

### Real-World Examples

#### Example 1: User Registration

```elixir
alias Events.Result

defmodule UserRegistration do
  def register(params) do
    params
    |> validate_email()
    |> Result.and_then(&validate_password/1)
    |> Result.and_then(&check_email_unique/1)
    |> Result.and_then(&hash_password/1)
    |> Result.and_then(&create_user/1)
    |> Result.and_then(&send_welcome_email/1)
    |> Result.map(fn user -> %{user: user, message: "Welcome!"} end)
  end

  defp validate_email(%{email: email} = params) do
    cond do
      is_nil(email) -> {:error, {:validation, :email_required}}
      not String.contains?(email, "@") -> {:error, {:validation, :email_invalid}}
      true -> {:ok, params}
    end
  end

  defp validate_password(%{password: password} = params) do
    cond do
      is_nil(password) -> {:error, {:validation, :password_required}}
      String.length(password) < 8 -> {:error, {:validation, :password_too_short}}
      true -> {:ok, params}
    end
  end

  defp check_email_unique(%{email: email} = params) do
    if Repo.exists?(User, email: email) do
      {:error, {:conflict, :email_taken}}
    else
      {:ok, params}
    end
  end

  defp hash_password(%{password: password} = params) do
    {:ok, Map.put(params, :password_hash, Bcrypt.hash_pwd_salt(password))}
  end

  defp create_user(params) do
    %User{}
    |> User.changeset(params)
    |> Repo.insert()
    |> Result.map_error(fn changeset -> {:validation, changeset} end)
  end

  defp send_welcome_email(user) do
    case Mailer.send_welcome(user) do
      :ok -> {:ok, user}
      {:error, reason} -> {:error, {:email_failed, reason}}
    end
  end
end

# Usage
case UserRegistration.register(params) do
  {:ok, result} ->
    render(conn, "success.html", result)

  {:error, {:validation, :email_required}} ->
    render(conn, "error.html", message: "Email is required")

  {:error, {:validation, :email_invalid}} ->
    render(conn, "error.html", message: "Email format is invalid")

  {:error, {:conflict, :email_taken}} ->
    render(conn, "error.html", message: "Email already registered")

  {:error, {:email_failed, _}} ->
    # User created but email failed - maybe retry later
    render(conn, "success.html", message: "Check your email")
end
```

#### Example 2: API Client with Error Recovery

```elixir
defmodule ApiClient do
  alias Events.Result

  def fetch_user(id) do
    fetch_from_cache(id)
    |> Result.or_else(fn _cache_miss ->
      fetch_from_api(id)
      |> Result.and_then(&cache_response/1)
    end)
    |> Result.map_error(&normalize_error/1)
  end

  def fetch_with_fallback(primary_url, fallback_url) do
    http_get(primary_url)
    |> Result.or_else(fn error ->
      Logger.warn("Primary failed: #{inspect(error)}, trying fallback")
      http_get(fallback_url)
    end)
  end

  # Collect multiple results, partition successes and failures
  def fetch_all_users(ids) do
    results = Enum.map(ids, &fetch_user/1)

    case Result.partition(results) do
      %{ok: users, errors: []} ->
        {:ok, users}

      %{ok: users, errors: errors} ->
        Logger.warn("Some users failed to fetch: #{inspect(errors)}")
        {:ok, users}  # Return partial results
    end
  end

  # Try multiple strategies
  def resolve_user(identifier) do
    [
      fn -> fetch_by_id(identifier) end,
      fn -> fetch_by_email(identifier) end,
      fn -> fetch_by_username(identifier) end
    ]
    |> Enum.reduce_while({:error, :not_found}, fn fetch_fn, _acc ->
      case fetch_fn.() do
        {:ok, user} -> {:halt, {:ok, user}}
        {:error, _} -> {:cont, {:error, :not_found}}
      end
    end)
  end

  defp normalize_error(%HTTPoison.Error{reason: :timeout}), do: :timeout
  defp normalize_error(%HTTPoison.Error{reason: :econnrefused}), do: :connection_refused
  defp normalize_error(%{status: 404}), do: :not_found
  defp normalize_error(%{status: 401}), do: :unauthorized
  defp normalize_error(%{status: 429}), do: :rate_limited
  defp normalize_error(error), do: {:unknown, error}
end
```

#### Example 3: Safe Exception Handling

```elixir
defmodule SafeParser do
  alias Events.Result

  def parse_json(string) do
    Result.try_with(fn -> Jason.decode!(string) end)
    |> Result.map_error(fn
      %Jason.DecodeError{} = e -> {:json_error, e.position}
      e -> {:parse_error, e}
    end)
  end

  def parse_integer(string) do
    Result.try_with(fn -> String.to_integer(string) end)
    |> Result.map_error(fn _ -> :invalid_integer end)
  end

  def parse_date(string) do
    Result.try_with(fn -> Date.from_iso8601!(string) end)
    |> Result.map_error(fn _ -> :invalid_date end)
  end

  # Parse a complex structure
  def parse_event(json_string) do
    parse_json(json_string)
    |> Result.and_then(fn data ->
      with {:ok, name} <- get_required(data, "name"),
           {:ok, date_str} <- get_required(data, "date"),
           {:ok, date} <- parse_date(date_str),
           {:ok, capacity} <- get_optional_int(data, "capacity", 100) do
        {:ok, %{name: name, date: date, capacity: capacity}}
      end
    end)
  end

  defp get_required(map, key) do
    case Map.fetch(map, key) do
      {:ok, nil} -> {:error, {:missing_field, key}}
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_field, key}}
    end
  end

  defp get_optional_int(map, key, default) do
    case Map.get(map, key) do
      nil -> {:ok, default}
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) -> parse_integer(value)
      _ -> {:error, {:invalid_type, key}}
    end
  end
end
```

#### Example 4: Transforming Both Success and Error

```elixir
defmodule ResponseFormatter do
  alias Events.Result

  def format_api_response(result) do
    result
    |> Result.bimap(
      fn data -> %{success: true, data: data} end,
      fn error -> %{success: false, error: format_error(error)} end
    )
  end

  def format_for_logging(result) do
    result
    |> Result.bimap(
      fn data -> "Success: #{inspect(data)}" end,
      fn error -> "Error: #{inspect(error)}" end
    )
    |> case do
      {:ok, msg} -> msg
      {:error, msg} -> msg
    end
  end

  defp format_error(:not_found), do: "Resource not found"
  defp format_error(:unauthorized), do: "Authentication required"
  defp format_error({:validation, errors}), do: "Validation failed: #{inspect(errors)}"
  defp format_error(error), do: "Unknown error: #{inspect(error)}"
end
```

### Result API Reference

```elixir
alias Events.Result

# ═══════════════════════════════════════════════════════════════════════════
# CREATION
# ═══════════════════════════════════════════════════════════════════════════

Result.ok(42)                                     # {:ok, 42}
Result.error(:not_found)                          # {:error, :not_found}
Result.from_nilable(42, :not_found)               # {:ok, 42}
Result.from_nilable(nil, :not_found)              # {:error, :not_found}
Result.from_nilable_lazy(nil, fn -> build_error() end)  # {:error, ...}

# ═══════════════════════════════════════════════════════════════════════════
# EXCEPTION HANDLING
# ═══════════════════════════════════════════════════════════════════════════

Result.try_with(fn -> risky_operation() end)      # {:ok, result} | {:error, exception}
Result.try_with(fn x -> parse(x) end, input)      # pass argument
Result.try_with(fn -> throw(:ball) end)           # {:error, {:throw, :ball}}
Result.try_with(fn -> exit(:reason) end)          # {:error, {:exit, :reason}}

# ═══════════════════════════════════════════════════════════════════════════
# TYPE CHECKING
# ═══════════════════════════════════════════════════════════════════════════

Result.ok?({:ok, 42})                             # true
Result.ok?({:error, _})                           # false
Result.error?({:error, :bad})                     # true
Result.error?({:ok, _})                           # false

# ═══════════════════════════════════════════════════════════════════════════
# TRANSFORMATION
# ═══════════════════════════════════════════════════════════════════════════

{:ok, 5} |> Result.map(&(&1 * 2))                 # {:ok, 10}
{:error, :bad} |> Result.map(&(&1 * 2))           # {:error, :bad}

{:error, "err"} |> Result.map_error(&String.upcase/1)   # {:error, "ERR"}
{:ok, 42} |> Result.map_error(&String.upcase/1)         # {:ok, 42}

# Bimap: transform both at once
Result.bimap({:ok, 5}, &(&1 * 2), &String.upcase/1)     # {:ok, 10}
Result.bimap({:error, "bad"}, &(&1 * 2), &String.upcase/1)  # {:error, "BAD"}

# ═══════════════════════════════════════════════════════════════════════════
# CHAINING
# ═══════════════════════════════════════════════════════════════════════════

{:ok, 5}
|> Result.and_then(fn x -> {:ok, x * 2} end)      # {:ok, 10}

{:ok, 5}
|> Result.and_then(fn _ -> {:error, :failed} end) # {:error, :failed}

{:error, :bad}
|> Result.and_then(fn x -> {:ok, x * 2} end)      # {:error, :bad}

# Error recovery
{:error, :cache_miss}
|> Result.or_else(fn _ -> fetch_from_db() end)    # tries DB

{:ok, cached}
|> Result.or_else(fn _ -> fetch_from_db() end)    # returns cached

# ═══════════════════════════════════════════════════════════════════════════
# EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════

Result.unwrap!({:ok, 42})                         # 42
Result.unwrap!({:error, :bad})                    # raises ArgumentError

Result.unwrap_or({:ok, 42}, 0)                    # 42
Result.unwrap_or({:error, :bad}, 0)               # 0

Result.unwrap_or_else({:error, e}, fn e -> handle(e) end)

Result.to_option({:ok, 42})                       # 42
Result.to_option({:error, _})                     # nil

Result.to_bool({:ok, _})                          # true
Result.to_bool({:error, _})                       # false

# ═══════════════════════════════════════════════════════════════════════════
# COLLECTION OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════

# Collect: all must succeed
Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])    # {:ok, [1, 2, 3]}
Result.collect([{:ok, 1}, {:error, :bad}])        # {:error, :bad}

# Traverse: map then collect
Result.traverse([1, 2, 3], fn x -> {:ok, x * 2} end)  # {:ok, [2, 4, 6]}

# Partition: separate oks and errors
Result.partition([{:ok, 1}, {:error, :a}, {:ok, 2}])
#=> %{ok: [1, 2], errors: [:a]}

# Filter
Result.cat_ok([{:ok, 1}, {:error, _}, {:ok, 2}])      # [1, 2]
Result.cat_errors([{:ok, _}, {:error, :a}])           # [:a]

# ═══════════════════════════════════════════════════════════════════════════
# COMBINING
# ═══════════════════════════════════════════════════════════════════════════

Result.combine({:ok, 1}, {:ok, 2})                # {:ok, {1, 2}}
Result.combine({:error, :a}, {:ok, 2})            # {:error, :a}

Result.combine_with({:ok, 2}, {:ok, 3}, &+/2)     # {:ok, 5}

Result.zip({:ok, 1}, {:ok, 2})                    # {:ok, {1, 2}}
Result.zip_with({:ok, 1}, {:ok, 2}, &+/2)         # {:ok, 3}

# ═══════════════════════════════════════════════════════════════════════════
# FLATTENING & APPLICATIVE
# ═══════════════════════════════════════════════════════════════════════════

Result.flatten({:ok, {:ok, 42}})                  # {:ok, 42}
Result.flatten({:ok, {:error, :inner}})           # {:error, :inner}
Result.flatten({:error, :outer})                  # {:error, :outer}

Result.apply({:ok, &String.upcase/1}, {:ok, "hi"})  # {:ok, "HI"}
Result.apply({:ok, &+/2}, {:ok, 1}, {:ok, 2})       # {:ok, 3}

Result.swap({:ok, 42})                            # {:error, 42}
Result.swap({:error, :e})                         # {:ok, :e}

# ═══════════════════════════════════════════════════════════════════════════
# FUNCTION LIFTING
# ═══════════════════════════════════════════════════════════════════════════

upcase = Result.lift(&String.upcase/1)
upcase.({:ok, "hello"})                           # {:ok, "HELLO"}
upcase.({:error, :bad})                           # {:error, :bad}

add = Result.lift(&+/2)
add.({:ok, 1}, {:ok, 2})                          # {:ok, 3}

Result.lift_apply(&String.upcase/1, {:ok, "hi"})  # {:ok, "HI"}

# ═══════════════════════════════════════════════════════════════════════════
# ERROR INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════

# Wrap with context
{:error, :not_found}
|> Result.wrap_error(user_id: 123, action: :fetch)
#=> {:error, %{reason: :not_found, context: %{user_id: 123, action: :fetch}}}

# Add step information
{:error, :not_found}
|> Result.with_step(:fetch_user)
#=> {:error, {:step_failed, :fetch_user, :not_found}}

# Unwrap step
{:error, {:step_failed, :fetch, :not_found}}
|> Result.unwrap_step()
#=> {:error, :not_found}

# Convert to Error struct
{:error, :not_found}
|> Result.to_error(:not_found, message: "User not found")
#=> {:error, %Events.Types.Error{type: :not_found, ...}}

# ═══════════════════════════════════════════════════════════════════════════
# ENUMERABLE & REDUCE
# ═══════════════════════════════════════════════════════════════════════════

Result.to_enum({:ok, 42})                         # [42]
Result.to_enum({:error, _})                       # []

{:ok, 5} |> Result.to_enum() |> Enum.map(&(&1 * 2))  # [10]

Result.reduce({:ok, 5}, 0, &+/2)                  # 5
Result.reduce({:error, _}, 0, &+/2)               # 0

# ═══════════════════════════════════════════════════════════════════════════
# SIDE EFFECTS
# ═══════════════════════════════════════════════════════════════════════════

{:ok, 42} |> Result.tap(&IO.inspect/1)            # prints 42, returns {:ok, 42}
{:error, :bad} |> Result.tap(&IO.inspect/1)       # prints nothing, returns {:error, :bad}

{:error, :bad} |> Result.tap_error(&Logger.error/1)  # logs error
{:ok, 42} |> Result.tap_error(&Logger.error/1)       # no logging
```

---

## AsyncResult

Use `AsyncResult` for **concurrent operations** that return Result tuples.

### When to Use AsyncResult

- Fetching multiple resources in parallel
- Racing between data sources
- Batch operations with rate limiting
- Retry logic with backoff
- Progress tracking

### Real-World Examples

#### Example 1: Parallel Data Fetching

```elixir
defmodule Dashboard do
  alias Events.AsyncResult

  def load_dashboard(user_id) do
    # Fetch all dashboard data in parallel
    AsyncResult.parallel([
      fn -> fetch_user_profile(user_id) end,
      fn -> fetch_notifications(user_id) end,
      fn -> fetch_activity_feed(user_id) end,
      fn -> fetch_recommendations(user_id) end
    ], max_concurrency: 4, timeout: 5000)
    |> AsyncResult.map(fn [profile, notifications, activity, recommendations] ->
      %{
        profile: profile,
        notifications: notifications,
        activity: activity,
        recommendations: recommendations
      }
    end)
  end

  # Fetch with progress tracking for large operations
  def load_all_reports(report_ids, progress_callback) do
    tasks = Enum.map(report_ids, fn id ->
      fn -> fetch_report(id) end
    end)

    AsyncResult.parallel_with_progress(tasks, fn completed, total ->
      progress_callback.(completed, total)
      IO.puts("Loading reports: #{completed}/#{total}")
    end, max_concurrency: 5)
  end

  # Settle: get all results even if some fail
  def load_dashboard_best_effort(user_id) do
    result = AsyncResult.parallel_settle([
      fn -> fetch_user_profile(user_id) end,
      fn -> fetch_notifications(user_id) end,
      fn -> fetch_activity_feed(user_id) end
    ])

    # Log any failures but continue with available data
    Enum.each(result.errors, fn error ->
      Logger.warn("Dashboard component failed: #{inspect(error)}")
    end)

    {:ok, %{
      profile: Enum.at(result.results, 0) |> elem(1),
      notifications: Enum.at(result.results, 1) |> ok_or_default([]),
      activity: Enum.at(result.results, 2) |> ok_or_default([])
    }}
  end

  defp ok_or_default({:ok, val}, _default), do: val
  defp ok_or_default({:error, _}, default), do: default
end
```

#### Example 2: Racing Data Sources

```elixir
defmodule DataResolver do
  alias Events.AsyncResult

  def get_user(id) do
    # Race between cache and database - use whichever responds first
    AsyncResult.race([
      fn -> fetch_from_cache(id) end,
      fn -> fetch_from_database(id) end
    ])
  end

  def get_with_fallback(primary_ids, fallback_fn) do
    # Try primary sources first, fall back if all fail
    primary_tasks = Enum.map(primary_ids, fn id ->
      fn -> fetch_from_primary(id) end
    end)

    AsyncResult.race_with_fallback(primary_tasks, fallback_fn)
  end

  # Try sources sequentially until one succeeds
  def resolve_config(key) do
    AsyncResult.first_ok([
      fn -> fetch_from_env(key) end,
      fn -> fetch_from_config_service(key) end,
      fn -> fetch_from_defaults(key) end
    ])
  end

  defp fetch_from_cache(id) do
    case Cache.get("user:#{id}") do
      nil -> {:error, :cache_miss}
      user -> {:ok, user}
    end
  end

  defp fetch_from_database(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

#### Example 3: Batch Processing with Rate Limiting

```elixir
defmodule BulkProcessor do
  alias Events.AsyncResult

  def process_all_users(user_ids) do
    tasks = Enum.map(user_ids, fn id ->
      fn -> process_user(id) end
    end)

    # Process in batches to avoid overwhelming the system
    AsyncResult.batch(tasks,
      batch_size: 100,
      delay_between_batches: 1000
    )
  end

  def send_all_notifications(notifications) do
    tasks = Enum.map(notifications, fn notif ->
      fn -> send_notification(notif) end
    end)

    # Limit concurrency to respect API rate limits
    AsyncResult.parallel(tasks,
      max_concurrency: 10,
      timeout: 30_000
    )
  end

  def sync_with_external_api(items) do
    # Process sequentially until first error
    tasks = Enum.map(items, fn item ->
      fn -> sync_item(item) end
    end)

    AsyncResult.until_error(tasks)
  end
end
```

#### Example 4: Retry with Exponential Backoff

```elixir
defmodule ResilientClient do
  alias Events.AsyncResult

  def call_flaky_api(params) do
    AsyncResult.retry(
      fn -> make_api_call(params) end,
      max_attempts: 5,
      initial_delay: 100,
      max_delay: 5000,
      jitter: true
    )
  end

  def call_with_context(user_id, action) do
    # Add context to errors for better debugging
    AsyncResult.with_context(
      fn -> perform_action(user_id, action) end,
      user_id: user_id,
      action: action,
      timestamp: DateTime.utc_now()
    )
    # On error: {:error, %{reason: :timeout, context: %{user_id: 123, ...}}}
  end

  def fetch_and_combine(user_id) do
    # Combine two parallel operations
    AsyncResult.combine(
      fn -> fetch_user(user_id) end,
      fn -> fetch_preferences(user_id) end
    )
    |> AsyncResult.map(fn {user, prefs} ->
      Map.put(user, :preferences, prefs)
    end)
  end

  def aggregate_data(sources) do
    tasks = Enum.map(sources, fn source ->
      fn -> fetch_from(source) end
    end)

    AsyncResult.parallel(tasks)
    |> AsyncResult.and_then(fn results ->
      {:ok, merge_results(results)}
    end)
  end
end
```

### AsyncResult API Reference

```elixir
alias Events.AsyncResult

# ═══════════════════════════════════════════════════════════════════════════
# PARALLEL EXECUTION (FAIL-FAST)
# ═══════════════════════════════════════════════════════════════════════════

# Execute all in parallel, fail on first error
AsyncResult.parallel([
  fn -> {:ok, 1} end,
  fn -> {:ok, 2} end,
  fn -> {:ok, 3} end
])
#=> {:ok, [1, 2, 3]}

AsyncResult.parallel([
  fn -> {:ok, 1} end,
  fn -> {:error, :bad} end,
  fn -> {:ok, 3} end
])
#=> {:error, :bad}

# With options
AsyncResult.parallel(tasks,
  max_concurrency: 10,
  timeout: 5000,
  ordered: true
)

# Parallel map
AsyncResult.parallel_map([1, 2, 3], fn x -> {:ok, x * 2} end)
#=> {:ok, [2, 4, 6]}

# ═══════════════════════════════════════════════════════════════════════════
# SETTLEMENT (COLLECT ALL)
# ═══════════════════════════════════════════════════════════════════════════

AsyncResult.parallel_settle([
  fn -> {:ok, 1} end,
  fn -> {:error, :bad} end,
  fn -> {:ok, 3} end
])
#=> %{
#     ok: [1, 3],
#     errors: [:bad],
#     results: [{:ok, 1}, {:error, :bad}, {:ok, 3}]
#   }

# ═══════════════════════════════════════════════════════════════════════════
# RACING
# ═══════════════════════════════════════════════════════════════════════════

# Return first success
AsyncResult.race([
  fn -> Process.sleep(100); {:ok, :slow} end,
  fn -> {:ok, :fast} end,
  fn -> {:error, :failed} end
])
#=> {:ok, :fast}

# Race returns error only if ALL fail
AsyncResult.race([
  fn -> {:error, :a} end,
  fn -> {:error, :b} end
])
#=> {:error, [:a, :b]}

# Race with fallback
AsyncResult.race_with_fallback(
  [fn -> {:error, :primary_failed} end],
  fn -> {:ok, :from_fallback} end
)
#=> {:ok, :from_fallback}

# ═══════════════════════════════════════════════════════════════════════════
# SEQUENTIAL ALTERNATIVES
# ═══════════════════════════════════════════════════════════════════════════

# Try until first success (lazy, sequential)
AsyncResult.first_ok([
  fn -> {:error, :not_here} end,
  fn -> {:ok, :found} end,
  fn -> raise "never called" end
])
#=> {:ok, :found}

# Process until first error (returns completed values)
AsyncResult.until_error([
  fn -> {:ok, 1} end,
  fn -> {:ok, 2} end,
  fn -> {:error, :stopped} end,
  fn -> {:ok, 4} end  # never called
])
#=> {:error, {:at_index, 2, :stopped, [1, 2]}}

# ═══════════════════════════════════════════════════════════════════════════
# BATCHING
# ═══════════════════════════════════════════════════════════════════════════

AsyncResult.batch(tasks,
  batch_size: 10,
  delay_between_batches: 1000
)
#=> {:ok, all_results} | {:error, first_error}

# ═══════════════════════════════════════════════════════════════════════════
# RETRY
# ═══════════════════════════════════════════════════════════════════════════

AsyncResult.retry(fn -> flaky_call() end,
  max_attempts: 5,
  initial_delay: 100,     # ms
  max_delay: 5000,        # ms
  jitter: true            # randomize delays
)
#=> {:ok, result} | {:error, {:max_retries_exceeded, last_error}}

# ═══════════════════════════════════════════════════════════════════════════
# COMBINING
# ═══════════════════════════════════════════════════════════════════════════

AsyncResult.combine(
  fn -> {:ok, :user} end,
  fn -> {:ok, :prefs} end
)
#=> {:ok, {:user, :prefs}}

AsyncResult.combine_with(task1, task2, fn user, prefs ->
  Map.put(user, :preferences, prefs)
end)

AsyncResult.combine_all([task1, task2, task3], &reducer/2, initial_acc)

# ═══════════════════════════════════════════════════════════════════════════
# TRANSFORMATION
# ═══════════════════════════════════════════════════════════════════════════

AsyncResult.parallel(tasks)
|> AsyncResult.map(&Enum.sum/1)

AsyncResult.parallel(tasks)
|> AsyncResult.and_then(fn values -> process(values) end)

# ═══════════════════════════════════════════════════════════════════════════
# CONTEXT & PROGRESS
# ═══════════════════════════════════════════════════════════════════════════

# Add context to errors
AsyncResult.with_context(
  fn -> {:error, :timeout} end,
  user_id: 123, operation: :fetch
)
#=> {:error, %{reason: :timeout, context: %{user_id: 123, operation: :fetch}}}

# Parallel with context
AsyncResult.parallel_with_context([
  {fn -> {:ok, 1} end, id: 1},
  {fn -> {:ok, 2} end, id: 2}
])

# Progress tracking
AsyncResult.parallel_with_progress(tasks, fn completed, total ->
  IO.puts("Progress: #{completed}/#{total}")
end, timeout: 10000)

# ═══════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════

# Safe execution (wraps exceptions)
AsyncResult.safe(fn -> risky_operation() end)
#=> {:ok, result} | {:error, %RuntimeError{}}

# With timeout
AsyncResult.with_timeout(fn -> slow_operation() end, 5000)
#=> {:ok, result} | {:error, :timeout}
```

---

## Pipeline

Use `Pipeline` for **multi-step workflows** with shared context.

### When to Use Pipeline

- Multi-step business processes (registration, checkout)
- Operations requiring rollback on failure
- Workflows with branching logic
- Steps that need shared context
- Operations requiring cleanup (ensure)

### Real-World Examples

#### Example 1: User Registration Flow

```elixir
defmodule RegistrationPipeline do
  alias Events.Pipeline

  def register(params) do
    Pipeline.new(params)
    |> Pipeline.step(:validate_input, &validate_input/1)
    |> Pipeline.step(:check_existing, &check_existing_user/1)
    |> Pipeline.step(:hash_password, &hash_password/1)
    |> Pipeline.step(:create_user, &create_user/1, rollback: &delete_user/1)
    |> Pipeline.step(:create_profile, &create_profile/1, rollback: &delete_profile/1)
    |> Pipeline.step(:send_welcome_email, &send_welcome_email/1)
    |> Pipeline.step(:track_signup, &track_signup_event/1)
    |> Pipeline.run_with_rollback()
  end

  defp validate_input(%{email: email, password: password} = ctx) do
    cond do
      !valid_email?(email) -> {:error, :invalid_email}
      String.length(password) < 8 -> {:error, :password_too_short}
      true -> {:ok, %{}}
    end
  end

  defp check_existing_user(%{email: email} = ctx) do
    if Repo.exists?(User, email: email) do
      {:error, :email_taken}
    else
      {:ok, %{}}
    end
  end

  defp hash_password(%{password: password} = ctx) do
    {:ok, %{password_hash: Bcrypt.hash_pwd_salt(password)}}
  end

  defp create_user(ctx) do
    case Repo.insert(%User{
      email: ctx.email,
      password_hash: ctx.password_hash
    }) do
      {:ok, user} -> {:ok, %{user: user}}
      {:error, changeset} -> {:error, {:db_error, changeset}}
    end
  end

  defp delete_user(ctx) do
    if ctx[:user], do: Repo.delete(ctx.user)
    :ok
  end

  defp create_profile(ctx) do
    case Repo.insert(%Profile{user_id: ctx.user.id, name: ctx[:name]}) do
      {:ok, profile} -> {:ok, %{profile: profile}}
      {:error, changeset} -> {:error, {:db_error, changeset}}
    end
  end

  defp delete_profile(ctx) do
    if ctx[:profile], do: Repo.delete(ctx.profile)
    :ok
  end

  defp send_welcome_email(ctx) do
    Mailer.send_welcome(ctx.user)
    {:ok, %{email_sent: true}}
  end

  defp track_signup_event(ctx) do
    Analytics.track("user_signed_up", %{user_id: ctx.user.id})
    {:ok, %{}}
  end

  defp valid_email?(email), do: String.contains?(email, "@")
end
```

#### Example 2: Order Processing with Branching

```elixir
defmodule OrderPipeline do
  alias Events.Pipeline

  def process_order(order_params) do
    Pipeline.new(order_params)
    |> Pipeline.step(:validate_order, &validate_order/1)
    |> Pipeline.step(:calculate_total, &calculate_total/1)
    |> Pipeline.step(:check_inventory, &check_inventory/1)

    # Branch based on payment method
    |> Pipeline.branch(:payment_method, %{
      credit_card: &process_credit_card/1,
      paypal: &process_paypal/1,
      bank_transfer: &process_bank_transfer/1
    }, default: fn p -> Pipeline.step(p, :invalid_payment, fn _ -> {:error, :invalid_payment_method} end) end)

    # Conditional step: only for premium users
    |> Pipeline.step_if(:apply_discount,
      fn ctx -> ctx.user.premium? end,
      &apply_premium_discount/1
    )

    # Guard: ensure total is positive
    |> Pipeline.guard(:valid_total,
      fn ctx -> ctx.total > 0 end,
      :invalid_order_total
    )

    |> Pipeline.step(:reserve_inventory, &reserve_inventory/1, rollback: &release_inventory/1)
    |> Pipeline.step(:charge_payment, &charge_payment/1, rollback: &refund_payment/1)
    |> Pipeline.step(:create_order, &create_order/1)
    |> Pipeline.step(:send_confirmation, &send_confirmation/1)
    |> Pipeline.run_with_rollback()
  end

  defp process_credit_card(pipeline) do
    pipeline
    |> Pipeline.step(:validate_card, &validate_credit_card/1)
    |> Pipeline.step(:authorize_card, &authorize_credit_card/1)
  end

  defp process_paypal(pipeline) do
    pipeline
    |> Pipeline.step(:redirect_paypal, &initiate_paypal/1)
    |> Pipeline.step(:confirm_paypal, &confirm_paypal/1)
  end

  defp process_bank_transfer(pipeline) do
    pipeline
    |> Pipeline.step(:generate_reference, &generate_bank_reference/1)
    |> Pipeline.step(:await_transfer, &create_pending_transfer/1)
  end

  # ... step implementations
end
```

#### Example 3: Data Import Pipeline with Checkpoints

```elixir
defmodule ImportPipeline do
  alias Events.Pipeline

  def import_data(file_path) do
    Pipeline.new(%{file_path: file_path})
    |> Pipeline.step(:read_file, &read_file/1)
    |> Pipeline.checkpoint(:file_read)

    |> Pipeline.step(:parse_csv, &parse_csv/1)
    |> Pipeline.step(:validate_headers, &validate_headers/1)
    |> Pipeline.checkpoint(:validated)

    |> Pipeline.step(:transform_records, &transform_records/1)
    |> Pipeline.checkpoint(:transformed)

    # Retry on transient failures
    |> Pipeline.step_with_retry(:insert_batch, &insert_batch/1,
      max_attempts: 3,
      delay: 1000,
      should_retry: fn err -> err in [:timeout, :deadlock] end
    )

    |> Pipeline.step(:update_stats, &update_stats/1)

    # Ensure cleanup runs regardless of success/failure
    |> Pipeline.ensure(:cleanup, fn ctx, _result ->
      File.rm(ctx[:temp_file])
    end)

    |> Pipeline.run_with_ensure()
  end

  def resume_from_checkpoint(pipeline, checkpoint_name) do
    pipeline
    |> Pipeline.rollback_to(checkpoint_name)
    |> Pipeline.step(:retry_from_here, &retry_step/1)
    |> Pipeline.run()
  end

  # Check what steps would run without executing
  def preview_import(file_path) do
    pipeline = build_pipeline(file_path)
    Pipeline.dry_run(pipeline)
    #=> [:read_file, :parse_csv, :validate_headers, ...]
  end

  # Get detailed step info
  def inspect_import(file_path) do
    pipeline = build_pipeline(file_path)
    Pipeline.inspect_steps(pipeline)
    #=> [%{name: :read_file, has_rollback: false}, ...]
  end
end
```

#### Example 4: Pipeline Composition

```elixir
defmodule ComposablePipelines do
  alias Events.Pipeline

  # Reusable validation segment
  def validation_segment do
    Pipeline.segment([
      {:validate_email, &validate_email/1},
      {:validate_name, &validate_name/1},
      {:validate_age, &validate_age/1}
    ])
  end

  # Reusable notification segment
  def notification_segment do
    Pipeline.segment([
      {:send_email, &send_email/1},
      {:send_sms, &send_sms/1},
      {:log_notification, &log_notification/1}
    ])
  end

  # Compose segments together
  def full_signup_pipeline(params) do
    Pipeline.new(params)
    |> Pipeline.include(validation_segment())
    |> Pipeline.step(:create_account, &create_account/1)
    |> Pipeline.include(notification_segment())
    |> Pipeline.run()
  end

  # Dynamic pipeline construction
  def build_dynamic_pipeline(params, options) do
    base = Pipeline.new(params)

    base
    |> maybe_add_step(options[:validate], :validation, validation_segment())
    |> maybe_add_step(options[:notify], :notify, notification_segment())
    |> Pipeline.run()
  end

  defp maybe_add_step(pipeline, true, _name, segment) do
    Pipeline.include(pipeline, segment)
  end
  defp maybe_add_step(pipeline, _, _, _), do: pipeline
end
```

#### Example 5: Pipeline with Parallel Steps

```elixir
defmodule EnrichmentPipeline do
  alias Events.Pipeline

  def enrich_user(user_id) do
    Pipeline.new(%{user_id: user_id})
    |> Pipeline.step(:fetch_user, &fetch_user/1)

    # Execute multiple enrichments in parallel
    |> Pipeline.parallel([
      {:fetch_profile, &fetch_profile/1},
      {:fetch_preferences, &fetch_preferences/1},
      {:fetch_activity, &fetch_recent_activity/1},
      {:fetch_friends, &fetch_friends_count/1}
    ], max_concurrency: 4)

    |> Pipeline.step(:merge_data, &merge_all_data/1)
    |> Pipeline.step(:cache_result, &cache_enriched_user/1)
    |> Pipeline.run()
  end

  defp merge_all_data(ctx) do
    {:ok, %{
      enriched_user: %{
        user: ctx.user,
        profile: ctx.fetch_profile,
        preferences: ctx.fetch_preferences,
        activity: ctx.fetch_activity,
        friends_count: ctx.fetch_friends
      }
    }}
  end
end
```

### Pipeline API Reference

```elixir
alias Events.Pipeline

# ═══════════════════════════════════════════════════════════════════════════
# CREATION
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.new(%{user_id: 123})
Pipeline.new(%{}, telemetry_prefix: [:my_app, :signup])
Pipeline.from_result({:ok, user}, :user)    # Start from existing result

# ═══════════════════════════════════════════════════════════════════════════
# STEPS
# ═══════════════════════════════════════════════════════════════════════════

# Basic step
Pipeline.step(pipeline, :fetch_user, fn ctx ->
  case Repo.get(User, ctx.user_id) do
    nil -> {:error, :not_found}
    user -> {:ok, %{user: user}}  # Merged into context
  end
end)

# Step with rollback
Pipeline.step(pipeline, :charge, &charge/1, rollback: &refund/1)

# Transform a specific key
Pipeline.transform(pipeline, :user, :display_name, fn user ->
  {:ok, "#{user.first_name} #{user.last_name}"}
end)

# Assign static or computed value
Pipeline.assign(pipeline, :timestamp, DateTime.utc_now())
Pipeline.assign(pipeline, :token, fn ctx -> generate_token(ctx.user) end)

# Conditional step
Pipeline.step_if(pipeline, :notify,
  fn ctx -> ctx.user.notifications_enabled end,
  &send_notification/1
)

# Validation step
Pipeline.validate(pipeline, :valid_email, fn ctx ->
  if valid?(ctx.email), do: :ok, else: {:error, :invalid_email}
end)

# Step with retry
Pipeline.step_with_retry(pipeline, :api_call, &call_api/1,
  max_attempts: 3,
  delay: 100,
  should_retry: fn err -> err == :timeout end
)

# Guard step
Pipeline.guard(pipeline, :authorized,
  fn ctx -> ctx.user.admin? end,
  :unauthorized
)

# ═══════════════════════════════════════════════════════════════════════════
# BRANCHING
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.branch(pipeline, :account_type, %{
  premium: fn p -> Pipeline.step(p, :premium, &handle_premium/1) end,
  standard: fn p -> Pipeline.step(p, :standard, &handle_standard/1) end
}, default: &handle_default/1)

Pipeline.when_true(pipeline, ctx.user.admin?, fn p ->
  Pipeline.step(p, :admin_setup, &setup_admin/1)
end)

# ═══════════════════════════════════════════════════════════════════════════
# PARALLEL STEPS
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.parallel(pipeline, [
  {:fetch_profile, &fetch_profile/1},
  {:fetch_settings, &fetch_settings/1}
], max_concurrency: 4, timeout: 5000)

# ═══════════════════════════════════════════════════════════════════════════
# SIDE EFFECTS
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.tap(pipeline, :log, fn ctx ->
  Logger.info("Processing user #{ctx.user.id}")
  :ok
end)

Pipeline.tap_always(pipeline, :metrics, fn ctx ->
  Metrics.increment("users.processed")
end)

# ═══════════════════════════════════════════════════════════════════════════
# CHECKPOINTS
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.checkpoint(pipeline, :after_validation)
Pipeline.checkpoints(pipeline)                    # [:after_validation, ...]
Pipeline.rollback_to(pipeline, :after_validation) # Restore to checkpoint

# ═══════════════════════════════════════════════════════════════════════════
# CONTEXT MANIPULATION
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.map_context(pipeline, fn ctx -> Map.take(ctx, [:user, :order]) end)
Pipeline.merge_context(pipeline, %{timestamp: DateTime.utc_now()})
Pipeline.drop_context(pipeline, [:temp_data, :internal])

# ═══════════════════════════════════════════════════════════════════════════
# COMPOSITION
# ═══════════════════════════════════════════════════════════════════════════

# Create reusable segment
segment = Pipeline.segment([
  {:step1, &step1/1},
  {:step2, &step2/1}
])

Pipeline.include(pipeline, segment)
Pipeline.compose(pipeline1, pipeline2)

# ═══════════════════════════════════════════════════════════════════════════
# CLEANUP (ENSURE)
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.ensure(pipeline, :cleanup, fn ctx, result ->
  File.close(ctx.file_handle)
  # result is {:ok, _} or {:error, _}
end)

Pipeline.run_with_ensure(pipeline)

# ═══════════════════════════════════════════════════════════════════════════
# EXECUTION
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.run(pipeline)
#=> {:ok, final_context} | {:error, {:step_failed, step_name, reason}}

Pipeline.run_with_rollback(pipeline)
#=> {:ok, ctx} | {:error, {:step_failed, step, reason, rollback_errors: [...]}}

Pipeline.run_with_ensure(pipeline)

Pipeline.run_with_timeout(pipeline, 5000)
#=> {:ok, ctx} | {:error, :timeout}

Pipeline.run!(pipeline)  # Raises on error

# ═══════════════════════════════════════════════════════════════════════════
# INSPECTION
# ═══════════════════════════════════════════════════════════════════════════

Pipeline.context(pipeline)           # Current context map
Pipeline.completed_steps(pipeline)   # [:step1, :step2, ...]
Pipeline.pending_steps(pipeline)     # [:step3, :step4, ...]
Pipeline.halted?(pipeline)           # true/false
Pipeline.error(pipeline)             # nil or error reason

# Debugging
Pipeline.dry_run(pipeline)           # [:step1, :step2, ...] without executing
Pipeline.inspect_steps(pipeline)     # [%{name: :step1, has_rollback: true}, ...]
Pipeline.to_string(pipeline)         # Pretty printed representation
IO.inspect(pipeline)                 # Uses Inspect protocol
```

---

## Guards

Use `Guards` for **pattern matching helpers** in function heads and case expressions.

### Real-World Examples

#### Example 1: Function Heads with Guards

```elixir
defmodule ResponseHandler do
  import Events.Guards

  def handle(result) when is_ok(result) do
    {:ok, value} = result
    process_success(value)
  end

  def handle(result) when is_error(result) do
    {:error, reason} = result
    log_and_handle_error(reason)
  end

  def handle_maybe(maybe) when is_some(maybe) do
    {:some, value} = maybe
    use_value(value)
  end

  def handle_maybe(maybe) when is_none(maybe) do
    use_default()
  end
end
```

#### Example 2: Pattern Matching Macros

```elixir
defmodule UserController do
  import Events.Guards

  def show(conn, %{"id" => id}) do
    case fetch_user(id) do
      ok(user) ->
        render(conn, "show.html", user: user)

      error(:not_found) ->
        conn
        |> put_status(:not_found)
        |> render("404.html")

      error(:unauthorized) ->
        conn
        |> put_status(:unauthorized)
        |> redirect(to: "/login")

      error(reason) ->
        Logger.error("Failed to fetch user: #{inspect(reason)}")
        conn
        |> put_status(:internal_server_error)
        |> render("500.html")
    end
  end

  def profile(conn, params) do
    case get_optional_field(params, "bio") do
      some(bio) ->
        render(conn, "profile.html", bio: bio)

      none() ->
        render(conn, "profile.html", bio: "No bio provided")
    end
  end
end
```

#### Example 3: Validation with Guards

```elixir
defmodule Validator do
  import Events.Guards

  def validate_name(name) when is_non_empty_string(name) do
    {:ok, String.trim(name)}
  end

  def validate_name(_), do: {:error, :name_required}

  def validate_items(items) when is_non_empty_list(items) do
    {:ok, items}
  end

  def validate_items(_), do: {:error, :items_required}

  def validate_age(age) when is_positive_integer(age) and age < 150 do
    {:ok, age}
  end

  def validate_age(age) when is_non_negative_integer(age) do
    {:error, :age_too_high}
  end

  def validate_age(_), do: {:error, :invalid_age}

  def validate_metadata(meta) when is_non_empty_map(meta) do
    {:ok, meta}
  end

  def validate_metadata(_), do: {:ok, %{}}
end
```

### Guards API Reference

```elixir
import Events.Guards

# ═══════════════════════════════════════════════════════════════════════════
# RESULT GUARDS
# ═══════════════════════════════════════════════════════════════════════════

is_ok({:ok, 42})              # true
is_ok({:error, _})            # false

is_error({:error, :bad})      # true
is_error({:ok, _})            # false

is_result({:ok, _})           # true
is_result({:error, _})        # true
is_result(:something)         # false

# ═══════════════════════════════════════════════════════════════════════════
# MAYBE GUARDS
# ═══════════════════════════════════════════════════════════════════════════

is_some({:some, 42})          # true
is_some(:none)                # false

is_none(:none)                # true
is_none({:some, _})           # false

is_maybe({:some, _})          # true
is_maybe(:none)               # true
is_maybe(:other)              # false

# ═══════════════════════════════════════════════════════════════════════════
# PATTERN MATCHING MACROS
# ═══════════════════════════════════════════════════════════════════════════

# Use in case expressions
case result do
  ok(value) -> use(value)
  error(reason) -> handle(reason)
end

case maybe do
  some(x) -> use(x)
  none() -> default()
end

# Use in function heads
def handle(ok(value)), do: process(value)
def handle(error(reason)), do: log(reason)

# ═══════════════════════════════════════════════════════════════════════════
# UTILITY GUARDS
# ═══════════════════════════════════════════════════════════════════════════

is_non_empty_string("hello")    # true
is_non_empty_string("")         # false
is_non_empty_string(nil)        # false

is_non_empty_list([1, 2])       # true
is_non_empty_list([])           # false

is_non_empty_map(%{a: 1})       # true
is_non_empty_map(%{})           # false

is_positive_integer(5)          # true
is_positive_integer(0)          # false
is_positive_integer(-1)         # false

is_non_negative_integer(0)      # true
is_non_negative_integer(5)      # true
is_non_negative_integer(-1)     # false
```

---

## Testing

Each module has companion test helpers with assertions and generators.

### Maybe Testing

```elixir
defmodule MyTest do
  use ExUnit.Case
  import Events.Types.Maybe.Test

  test "returns some for valid input" do
    result = MyModule.get_value(input)
    assert_some(result)
    assert_some(result, 42)  # Assert specific value
  end

  test "returns none for invalid input" do
    result = MyModule.get_value(nil)
    assert_none(result)
  end

  # Property-based testing with StreamData
  property "map preserves some" do
    check all value <- StreamData.integer() do
      result = Maybe.some(value) |> Maybe.map(&(&1 * 2))
      assert_some(result, value * 2)
    end
  end

  # Generators
  test "with generated maybes" do
    # gen_maybe generates {:some, value} or :none
    for maybe <- StreamData.list_of(gen_maybe(StreamData.integer())) do
      # test with random maybes
    end
  end
end
```

### Result Testing

```elixir
defmodule MyTest do
  use ExUnit.Case
  import Events.Types.Result.Test

  test "returns ok for valid input" do
    result = MyModule.process(valid_input)
    assert_ok(result)
    assert_ok(result, expected_value)
  end

  test "returns error for invalid input" do
    result = MyModule.process(invalid_input)
    assert_error(result)
    assert_error(result, :invalid_input)
  end

  # Generators
  property "and_then chains correctly" do
    check all result <- gen_result(StreamData.integer(), StreamData.atom(:alphanumeric)) do
      chained = Result.and_then(result, fn x -> {:ok, x * 2} end)
      if Result.ok?(result) do
        assert_ok(chained)
      else
        assert_error(chained)
      end
    end
  end
end
```

### Pipeline Testing

```elixir
defmodule MyTest do
  use ExUnit.Case
  import Events.Types.Pipeline.Test

  test "pipeline executes all steps" do
    result = MyPipeline.run(params)
    assert_pipeline_ok(result)
  end

  test "pipeline has expected steps" do
    pipeline = MyPipeline.build(params)
    assert_steps(pipeline, [:validate, :process, :save])
  end

  test "with mocked step" do
    pipeline =
      MyPipeline.build(params)
      |> mock_step(:external_api, fn ctx ->
        {:ok, %{api_response: mock_response()}}
      end)

    result = Pipeline.run(pipeline)
    assert_pipeline_ok(result)
  end

  test "dry run shows steps without executing" do
    pipeline = MyPipeline.build(params)
    steps = Pipeline.dry_run(pipeline)
    assert steps == [:validate, :process, :external_api, :save]
  end
end
```

---

## Best Practices

### 1. Choose the Right Type

```elixir
# GOOD: Use Maybe for optional fields
def get_middle_name(user), do: Maybe.from_nilable(user.middle_name)

# BAD: Using Result for optional fields
def get_middle_name(user) do
  case user.middle_name do
    nil -> {:error, :no_middle_name}  # This isn't an error!
    name -> {:ok, name}
  end
end

# GOOD: Use Result for operations that can fail
def fetch_user(id), do: Repo.get(User, id) |> Result.from_nilable(:not_found)

# BAD: Using Maybe for errors
def fetch_user(id), do: Repo.get(User, id) |> Maybe.from_nilable()  # Loses error info
```

### 2. Chain Operations Instead of Nesting

```elixir
# GOOD: Chain with and_then
fetch_user(id)
|> Result.and_then(&validate_user/1)
|> Result.and_then(&save_user/1)
|> Result.map(&format_response/1)

# BAD: Nested case statements
case fetch_user(id) do
  {:ok, user} ->
    case validate_user(user) do
      {:ok, valid_user} ->
        case save_user(valid_user) do
          {:ok, saved} -> {:ok, format_response(saved)}
          error -> error
        end
      error -> error
    end
  error -> error
end
```

### 3. Use Pipeline for Complex Workflows

```elixir
# GOOD: Pipeline for multi-step operations
Pipeline.new(params)
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:process, &process/1)
|> Pipeline.step(:save, &save/1, rollback: &cleanup/1)
|> Pipeline.run_with_rollback()

# BAD: Manual error handling
with {:ok, validated} <- validate(params),
     {:ok, processed} <- process(validated),
     {:ok, saved} <- save(processed) do
  {:ok, saved}
else
  error ->
    cleanup(params)  # Manual rollback
    error
end
```

### 4. Add Context to Errors

```elixir
# GOOD: Errors with context
fetch_user(id)
|> Result.wrap_error(user_id: id, operation: :fetch)
|> Result.map_error(fn error ->
  Logger.error("Failed", error)
  error
end)

# BAD: Generic errors
fetch_user(id)  # Returns {:error, :not_found} - no context!
```

### 5. Use Guards for Clean Pattern Matching

```elixir
# GOOD: Guards in function heads
import Events.Guards

def process(result) when is_ok(result), do: handle_success(result)
def process(result) when is_error(result), do: handle_error(result)

# Pattern macros in case
case fetch_data() do
  ok(data) -> use(data)
  error(reason) -> log(reason)
end
```

### 6. Prefer Lazy Evaluation

```elixir
# GOOD: Lazy defaults (only computed if needed)
Maybe.unwrap_or_else(maybe, fn -> expensive_computation() end)
Result.or_else(result, fn _ -> expensive_fallback() end)

# BAD: Eager evaluation (always computed)
Maybe.unwrap_or(maybe, expensive_computation())  # Called even if some!
```

---

## Migration Guide

### From Raw Tuples to Result

```elixir
# Before: Manual case matching
def process(input) do
  case validate(input) do
    {:ok, validated} ->
      case transform(validated) do
        {:ok, transformed} ->
          case save(transformed) do
            {:ok, saved} -> {:ok, saved}
            {:error, reason} -> {:error, {:save_failed, reason}}
          end
        {:error, reason} -> {:error, {:transform_failed, reason}}
      end
    {:error, reason} -> {:error, {:validation_failed, reason}}
  end
end

# After: Result chaining
def process(input) do
  input
  |> validate()
  |> Result.and_then(&transform/1)
  |> Result.and_then(&save/1)
  |> Result.map_error(&categorize_error/1)
end
```

### From nil Checks to Maybe

```elixir
# Before: Nil checks
def get_display_name(user) do
  if user.display_name do
    user.display_name
  else
    if user.full_name do
      user.full_name
    else
      "Anonymous"
    end
  end
end

# After: Maybe chain
def get_display_name(user) do
  Maybe.first_some([
    fn -> Maybe.from_string(user.display_name) end,
    fn -> Maybe.from_string(user.full_name) end,
    fn -> Maybe.some("Anonymous") end
  ])
  |> Maybe.unwrap!()
end
```

### From Manual Parallel to AsyncResult

```elixir
# Before: Manual Task handling
def fetch_all(ids) do
  tasks = Enum.map(ids, fn id ->
    Task.async(fn -> fetch(id) end)
  end)

  results = Task.await_many(tasks, 5000)

  errors = Enum.filter(results, &match?({:error, _}, &1))
  if errors == [] do
    {:ok, Enum.map(results, fn {:ok, v} -> v end)}
  else
    {:error, hd(errors)}
  end
end

# After: AsyncResult
def fetch_all(ids) do
  AsyncResult.parallel_map(ids, &fetch/1, timeout: 5000)
end
```

### From with to Pipeline

```elixir
# Before: with statement
def register(params) do
  with {:ok, validated} <- validate(params),
       {:ok, user} <- create_user(validated),
       {:ok, _} <- send_email(user),
       {:ok, _} <- track_event(user) do
    {:ok, user}
  else
    {:error, :invalid_email} -> {:error, "Invalid email address"}
    {:error, :email_taken} -> {:error, "Email already registered"}
    {:error, reason} -> {:error, "Registration failed: #{reason}"}
  end
end

# After: Pipeline
def register(params) do
  Pipeline.new(params)
  |> Pipeline.step(:validate, &validate/1)
  |> Pipeline.step(:create_user, &create_user/1, rollback: &delete_user/1)
  |> Pipeline.step(:send_email, &send_email/1)
  |> Pipeline.step(:track_event, &track_event/1)
  |> Pipeline.run_with_rollback()
  |> format_registration_result()
end
```

---

## Future Data Structures

The following data structures are planned for future implementation. They follow the same functional programming principles as the existing modules.

### Tier 1: High Practical Value

#### Lens

Composable getters/setters for nested data structures.

```elixir
# Problem: Updating deeply nested structures is verbose
user = %{profile: %{settings: %{theme: "light"}}}
put_in(user, [:profile, :settings, :theme], "dark")

# With Lens:
theme_lens = Lens.make([:profile, :settings, :theme])
Lens.set(theme_lens, user, "dark")
Lens.over(theme_lens, user, &String.upcase/1)

# Composable
profile = Lens.at(:profile)
settings = Lens.at(:settings)
theme = Lens.compose(profile, settings, Lens.at(:theme))
```

**Use cases:**
- Updating deeply nested configuration
- Immutable data transformations
- State management in LiveView
- JSON/map manipulation

#### Resource

Safe resource acquisition/release (bracket pattern).

```elixir
# Guarantees cleanup even on exceptions
Resource.bracket(
  acquire: fn -> File.open!("data.txt") end,
  release: fn file -> File.close(file) end,
  use: fn file -> IO.read(file, :all) end
)

# Composable resources
db_conn = Resource.make(&connect_db/0, &disconnect/1)
file = Resource.make(&open_file/0, &close_file/1)

Resource.both(db_conn, file)
|> Resource.use(fn {conn, file} -> import_data(conn, file) end)
```

**Use cases:**
- Database connections
- File handles
- External API sessions
- Lock acquisition

#### RateLimiter

Token bucket / sliding window as a pure data structure.

```elixir
limiter = RateLimiter.new(rate: 100, per: :second)

case RateLimiter.acquire(limiter) do
  {:ok, limiter} -> proceed(limiter)
  {:error, :rate_limited, retry_after} -> wait(retry_after)
end

# Sliding window
limiter = RateLimiter.sliding_window(max: 1000, window: :minute)

# Token bucket with burst
limiter = RateLimiter.token_bucket(rate: 10, per: :second, burst: 50)
```

**Use cases:**
- API rate limiting
- Request throttling
- Resource protection
- Fair scheduling

#### Memo

Memoization as an explicit, pure data structure.

```elixir
memo = Memo.new()
{result, memo} = Memo.get_or_compute(memo, key, fn -> expensive() end)

# With TTL
memo = Memo.new(ttl: :timer.minutes(5))

# Bounded size (LRU eviction)
memo = Memo.new(max_size: 1000)

# Unlike process-based caching, this is pure and testable
```

**Use cases:**
- Expensive computations
- Recursive algorithms (fibonacci, etc.)
- Request deduplication
- Pure, testable caching

#### Predicate

Composable predicates for validation and filtering.

```elixir
is_adult = Predicate.new(&(&1.age >= 18))
is_verified = Predicate.new(&(&1.verified))

can_purchase = Predicate.and(is_adult, is_verified)
can_view = Predicate.or(is_adult, Predicate.new(&(&1.has_permission)))

Predicate.test(can_purchase, user)

# With descriptions for error messages
is_valid_email = Predicate.new(&valid_email?/1, "must be a valid email")
Predicate.explain(is_valid_email)
#=> "must be a valid email"
```

**Use cases:**
- Complex validation rules
- Query builders
- Access control
- Filter composition

### Tier 2: Domain-Specific but Powerful

#### Diff

Structural diffing with patch/unpatch capabilities.

```elixir
old = %{name: "Alice", age: 30}
new = %{name: "Alice", age: 31, email: "a@b.com"}

diff = Diff.compute(old, new)
#=> %Diff{changes: [{:update, :age, 30, 31}, {:add, :email, "a@b.com"}]}

Diff.apply(old, diff) == new  # true
Diff.revert(new, diff) == old # true

# For lists
Diff.list_diff([1, 2, 3], [1, 3, 4])
#=> [{:remove, 1, 2}, {:add, 2, 4}]
```

**Use cases:**
- Audit logging
- Undo/redo functionality
- Sync protocols
- Change tracking

#### Saga

Distributed transaction compensation pattern.

```elixir
# Like Pipeline but with automatic rollback on failure
Saga.new()
|> Saga.step(:reserve_inventory, &reserve/1, compensate: &unreserve/1)
|> Saga.step(:charge_payment, &charge/1, compensate: &refund/1)
|> Saga.step(:ship_order, &ship/1, compensate: &cancel_shipment/1)
|> Saga.execute(order)
# If ship fails, automatically calls refund then unreserve

# With timeout per step
Saga.step(:external_call, &call/1,
  compensate: &rollback/1,
  timeout: 5000
)
```

**Use cases:**
- Distributed transactions
- Order processing
- Multi-service workflows
- Event-driven architectures

#### Batch

Efficient batched operations with backpressure.

```elixir
# Accumulate items, flush when batch full or timeout
Batch.new(size: 100, timeout: :timer.seconds(5))
|> Batch.add(item1)
|> Batch.add(item2)
|> Batch.on_flush(&bulk_insert/1)

# With backpressure
Batch.new(size: 100, max_pending: 1000)
|> Batch.add(item)  # Blocks if too many pending
```

**Use cases:**
- Bulk database inserts
- Log aggregation
- Metrics collection
- Stream processing

#### Ior (Inclusive Or)

Like Result but can hold both success and error (warnings with success).

```elixir
# {:left, errors} - failure only
# {:right, value} - success only
# {:both, errors, value} - success with warnings

validate_with_warnings(data)
|> Ior.map(&process/1)  # processes if Right or Both
#=> {:both, ["field X deprecated"], %{processed: true}}

# Accumulate warnings
Ior.combine(result1, result2)  # Combines warnings from both
```

**Use cases:**
- Validation with warnings
- Deprecation notices
- Partial success scenarios
- Non-fatal error accumulation

### Tier 3: Advanced Patterns

#### Zipper

Navigate and modify tree/list structures with context.

```elixir
# Navigate a tree while keeping track of where you are
zipper = Zipper.from_list([1, 2, 3, 4, 5])
zipper
|> Zipper.next()      # focus on 2
|> Zipper.next()      # focus on 3
|> Zipper.replace(30) # [1, 2, 30, 4, 5]
|> Zipper.prev()      # back to 2
|> Zipper.to_list()   # reconstruct

# For trees
zipper = Zipper.from_tree(ast)
zipper
|> Zipper.down()      # first child
|> Zipper.right()     # sibling
|> Zipper.edit(&transform/1)
|> Zipper.root()      # back to root
```

**Use cases:**
- AST manipulation
- Tree editing
- Navigation with undo
- Cursor-based editing

#### Builder

Type-safe builder pattern for complex struct construction.

```elixir
User.builder()
|> Builder.set(:name, "Alice")
|> Builder.set(:email, "alice@example.com")
|> Builder.build()
#=> {:ok, %User{}} or {:error, [:age_required]}

# With validation at each step
Builder.set(builder, :age, -5)
#=> {:error, :age_must_be_positive}

# Required vs optional fields
User.builder()
|> Builder.require([:name, :email])
|> Builder.optional([:bio, :avatar])
```

**Use cases:**
- Complex object construction
- API request builders
- Query builders
- Configuration objects

#### Lazy

Deferred computation with memoization.

```elixir
lazy_value = Lazy.new(fn -> expensive_computation() end)

# Not computed yet
Lazy.computed?(lazy_value)  #=> false

# Force evaluation
{value, lazy_value} = Lazy.force(lazy_value)

# Now memoized
Lazy.computed?(lazy_value)  #=> true
{value, _} = Lazy.force(lazy_value)  # Returns cached value

# Map over lazy values (still lazy)
Lazy.map(lazy_value, &transform/1)
```

**Use cases:**
- Expensive computations
- Infinite sequences
- Conditional evaluation
- Resource optimization

#### Reader

Dependency injection monad for threading configuration.

```elixir
# Define computations that need config
fetch_user = Reader.new(fn config ->
  config.repo.get(User, config.user_id)
end)

send_email = Reader.new(fn config ->
  config.mailer.send(config.user, "Welcome!")
end)

# Compose without passing config
workflow = Reader.and_then(fetch_user, fn user ->
  Reader.map(send_email, fn _ -> user end)
end)

# Run with config at the edge
Reader.run(workflow, %{repo: Repo, mailer: Mailer, user_id: 123})
```

**Use cases:**
- Dependency injection
- Configuration threading
- Testing with mocks
- Environment-dependent code

### Implementation Priority

Based on practical value for this codebase:

1. **Lens** - Nested schema updates are common
2. **Resource** - Pairs with S3, database, and external APIs
3. **RateLimiter** - API integrations need rate limiting
4. **Memo** - Pure memoization for expensive operations
5. **Predicate** - Composable validation rules
6. **Saga** - Natural extension of Pipeline for distributed transactions
7. **Ior** - Validation system would benefit from "success with warnings"
8. **Diff** - Audit logging and change tracking
9. **Batch** - Bulk operations optimization
10. **Zipper** - AST/tree manipulation
11. **Builder** - Complex struct construction
12. **Lazy** - Deferred computation
13. **Reader** - Dependency injection
