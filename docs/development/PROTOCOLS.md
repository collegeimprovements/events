# Protocol Design Guide for Events

This document outlines the protocols recommended for the Events codebase, organized by priority and use case.

## Philosophy

**Use protocols when:**
- Multiple disparate types need polymorphic behavior
- You want extensibility without modifying core code
- The operation is about "what" not "how" (dispatch on type)

**Don't use protocols when:**
- Simple function composition suffices
- Only one or two types need the behavior
- Performance is critical in hot paths (protocol dispatch has overhead)

## Existing Protocols (Reference)

### Events.Api.Client.Auth
Authentication strategy protocol - excellent example of correct usage.

```elixir
defprotocol Events.Api.Client.Auth do
  @spec authenticate(t, Request.t()) :: Request.t()
  def authenticate(auth, request)

  @spec valid?(t) :: boolean()
  def valid?(auth)

  @spec refresh(t) :: {:ok, t} | {:error, term()}
  def refresh(auth)
end
```

### Events.Core.Query.Queryable
Query source conversion - enables uniform query building from atoms, strings, Ecto queries.

```elixir
defprotocol Events.Core.Query.Queryable do
  @spec to_token(t()) :: Events.Core.Query.Token.t()
  def to_token(source)
end
```

---

## Essential Protocols (Implement First)

### 1. Normalizable - Error Normalization

**Purpose:** Convert any error source into a standard `FnTypes.Error` struct.

**Current Problem:** 8+ mapper modules with similar patterns.

```elixir
defprotocol FnTypes.Protocols.Normalizable do
  @moduledoc """
  Protocol for normalizing various error types into FnTypes.Error.

  Implement this for any type that can represent an error condition.
  """

  @doc """
  Normalize the error into a standard FnTypes.Error struct.

  Options:
  - `:context` - Additional context to attach
  - `:source` - Override the source field
  - `:stacktrace` - Stacktrace to attach
  """
  @spec normalize(t, keyword()) :: FnTypes.Error.t()
  def normalize(error, opts \\ [])
end
```

**Implementations:**

```elixir
# Ecto Changesets
defimpl FnTypes.Protocols.Normalizable, for: Ecto.Changeset do
  def normalize(%{valid?: false} = changeset, opts) do
    FnTypes.Error.new(:validation, :changeset_invalid,
      message: Keyword.get(opts, :message, "Validation failed"),
      details: %{errors: extract_errors(changeset)},
      source: Ecto.Changeset,
      context: Keyword.get(opts, :context, %{})
    )
  end

  defp extract_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

# Standard Exceptions
defimpl FnTypes.Protocols.Normalizable, for: Any do
  defmacro __deriving__(module, _struct, _opts) do
    quote do
      defimpl FnTypes.Protocols.Normalizable, for: unquote(module) do
        def normalize(exception, opts) do
          FnTypes.Error.new(:internal, :exception,
            message: Exception.message(exception),
            source: unquote(module),
            stacktrace: Keyword.get(opts, :stacktrace),
            context: Keyword.get(opts, :context, %{})
          )
        end
      end
    end
  end

  def normalize(value, opts) do
    FnTypes.Error.new(:internal, :unknown_error,
      message: "Unknown error: #{inspect(value)}",
      context: Keyword.get(opts, :context, %{})
    )
  end
end

# Specific exceptions
defimpl FnTypes.Protocols.Normalizable, for: Ecto.NoResultsError do
  def normalize(exception, opts) do
    FnTypes.Error.new(:not_found, :no_results,
      message: Exception.message(exception),
      source: Ecto,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{})
    )
  end
end

defimpl FnTypes.Protocols.Normalizable, for: Ecto.StaleEntryError do
  def normalize(exception, opts) do
    FnTypes.Error.new(:conflict, :stale_entry,
      message: Exception.message(exception),
      source: Ecto,
      stacktrace: Keyword.get(opts, :stacktrace)
    )
  end
end
```

**Usage:**
```elixir
# Before (multiple mapper modules)
Events.Errors.Mappers.Ecto.normalize(changeset)
Events.Errors.Mappers.Exception.normalize(exception)

# After (single dispatch)
FnTypes.Protocols.Normalizable.normalize(changeset)
FnTypes.Protocols.Normalizable.normalize(exception)
```

---

### 2. Identifiable - Entity Identity ✅ IMPLEMENTED

**Status:** Fully implemented in `lib/events/identifiable.ex`

**Purpose:** Extract identity from domain entities for deduplication, caching, and event sourcing.

**Location:**
- Protocol: `lib/events/identifiable.ex`
- Implementations: `lib/events/identifiable/impl/`
- Helpers: `lib/events/identifiable/helpers.ex`
- Tests: `test/events/identifiable_test.exs`

```elixir
defprotocol FnTypes.Protocols.Identifiable do
  @moduledoc """
  Protocol for extracting identity from domain entities.

  Used for:
  - Cache key generation
  - Event sourcing aggregate identification
  - Deduplication in async operations
  - Equality comparisons for entities
  """

  @doc "Returns the entity type as an atom"
  @spec entity_type(t) :: atom()
  def entity_type(entity)

  @doc "Returns the unique identifier"
  @spec id(t) :: String.t() | integer()
  def id(entity)

  @doc "Returns a tuple of {type, id} for compound identity"
  @spec identity(t) :: {atom(), String.t() | integer()}
  def identity(entity)
end
```

**Implementations:**

| Type | entity_type | id | Notes |
|------|-------------|-----|-------|
| `Any` (fallback) | `:unknown` | Extracts `:id` field | Safe default |
| `FnTypes.Error` | Error type (`:validation`, etc.) | Error ID (`err_xxx`) | Uses error's type |
| `Ecto.Changeset` | Derived from schema | From data or changes | Supports changesets |
| Derived schemas | Configured or auto-derived | Configured field | Via `@derive` |

**Usage in schemas:**
```elixir
defmodule Events.Domains.Accounts.User do
  @derive {FnTypes.Protocols.Identifiable, type: :user}
  use Events.Schema
  # ...
end

# Usage
user = Repo.get!(User, "usr_123")
FnTypes.Protocols.Identifiable.identity(user)
#=> {:user, "usr_123"}
```

**Derive Options:**
```elixir
# Auto-derive type from module name (MyApp.User -> :user)
@derive Events.Identifiable

# Explicit type
@derive {FnTypes.Protocols.Identifiable, type: :user}

# Custom ID field
@derive {FnTypes.Protocols.Identifiable, type: :invoice, id_field: :invoice_number}
```

**Helper Functions (`FnTypes.Protocols.Identifiable.Helpers`):**

| Function | Description |
|----------|-------------|
| `cache_key/2` | Generate cache key string (`"user:usr_123"`) |
| `cache_key_tuple/1` | Get identity as tuple for ETS/Cachex |
| `same_entity?/2` | Compare entities by identity |
| `persisted?/1` | Check if entity has an ID |
| `unique_by_identity/1` | Deduplicate list by identity |
| `group_by_type/1` | Group entities by type |
| `extract_ids/1` | Get all IDs from list |
| `identity_map/1` | Create `{identity => entity}` lookup |
| `find_by_identity/2` | Find entity in list by identity |
| `to_global_id/1` | Encode as GraphQL global ID |
| `from_global_id/1` | Decode GraphQL global ID |
| `idempotency_key/3` | Generate idempotency key |
| `format_identity/1` | Human-readable format |
| `identity_info/1` | Comprehensive identity summary |

**Common Patterns:**

```elixir
alias Events.Identifiable
alias FnTypes.Protocols.Identifiable.Helpers

# Cache key generation
key = Helpers.cache_key(user)  #=> "user:usr_123"
key = Helpers.cache_key(user, prefix: "v1")  #=> "v1:user:usr_123"

# Entity equality
Helpers.same_entity?(user_v1, user_v2)  #=> true (same id)

# Deduplication
unique_users = Helpers.unique_by_identity(users)

# GraphQL global IDs
global_id = Helpers.to_global_id(user)  #=> "dXNlcjp1c3JfMTIz"
{:ok, {:user, "usr_123"}} = Helpers.from_global_id(global_id)

# Idempotency keys
key = Helpers.idempotency_key(order, :process_payment)
#=> "order:ord_123:process_payment"

# Audit logging
def audit(entity, action, actor) do
  {entity_type, entity_id} = Identifiable.identity(entity)
  {actor_type, actor_id} = Identifiable.identity(actor)
  # ...
end
```

---

### 3. Cacheable - Cache Configuration

**Purpose:** Define cache key, TTL, and safety for domain objects.

```elixir
defprotocol Events.Core.Cacheable do
  @moduledoc """
  Protocol for defining caching behavior of domain objects.

  Integrates with Nebulex/Cachex for automatic cache management.
  """

  @doc "Generate a cache key for this value"
  @spec cache_key(t) :: term()
  def cache_key(value)

  @doc "Return TTL in seconds (nil for default)"
  @spec cache_ttl(t) :: pos_integer() | nil
  def cache_ttl(value)

  @doc "Whether this value is safe to cache (no sensitive data, stable state)"
  @spec cacheable?(t) :: boolean()
  def cacheable?(value)
end
```

**Implementations:**

```elixir
defimpl Events.Core.Cacheable, for: Events.Domains.Accounts.User do
  def cache_key(user) do
    {:user, user.id}
  end

  def cache_ttl(user) do
    case user.status do
      :active -> 300      # 5 minutes for active users
      :suspended -> 60    # 1 minute for suspended (may change)
      :deleted -> nil     # Don't cache deleted users
    end
  end

  def cacheable?(user) do
    user.status != :deleted
  end
end

defimpl Events.Core.Cacheable, for: Events.Domains.Accounts.Account do
  def cache_key(account), do: {:account, account.id}
  def cache_ttl(_), do: 600  # 10 minutes
  def cacheable?(account), do: account.status == :active
end
```

**Usage with cache decorator:**
```elixir
@decorate cacheable(protocol: Events.Core.Cacheable)
def get_user(id) do
  Repo.get(User, id)
end
```

---

### 4. Recoverable - Error Recovery Strategy

**Purpose:** Define recovery strategies for different error types.

```elixir
defprotocol FnTypes.Protocols.Recoverable do
  @moduledoc """
  Protocol for defining error recovery strategies.

  Used by retry mechanisms, circuit breakers, and resilience patterns.
  """

  @doc "Whether this error is recoverable"
  @spec recoverable?(t) :: boolean()
  def recoverable?(error)

  @doc "Suggested recovery strategy"
  @spec strategy(t) :: :retry | :retry_with_backoff | :circuit_break | :fail_fast | :fallback
  def strategy(error)

  @doc "Delay before retry in milliseconds (for retry strategies)"
  @spec retry_delay(t, attempt :: pos_integer()) :: pos_integer()
  def retry_delay(error, attempt)

  @doc "Maximum retry attempts"
  @spec max_attempts(t) :: pos_integer()
  def max_attempts(error)
end
```

**Implementations:**

```elixir
defimpl FnTypes.Protocols.Recoverable, for: FnTypes.Error do
  def recoverable?(error) do
    error.type in [:timeout, :network, :rate_limited, :external]
  end

  def strategy(error) do
    case error.type do
      :rate_limited -> :retry_with_backoff
      :timeout -> :retry
      :network -> :retry_with_backoff
      :external -> :circuit_break
      _ -> :fail_fast
    end
  end

  def retry_delay(error, attempt) do
    case error.type do
      :rate_limited ->
        # Respect Retry-After header if present
        error.metadata[:retry_after] || exponential_backoff(attempt)
      :timeout ->
        1000  # Fixed 1 second
      _ ->
        exponential_backoff(attempt)
    end
  end

  def max_attempts(error) do
    case error.type do
      :rate_limited -> 5
      :timeout -> 3
      :network -> 3
      _ -> 1
    end
  end

  defp exponential_backoff(attempt) do
    min(:math.pow(2, attempt) * 100, 30_000) |> round()
  end
end

# HTTP-specific errors
defimpl FnTypes.Protocols.Recoverable, for: Mint.TransportError do
  def recoverable?(_), do: true
  def strategy(_), do: :retry_with_backoff
  def retry_delay(_, attempt), do: min(:math.pow(2, attempt) * 100, 10_000) |> round()
  def max_attempts(_), do: 3
end
```

---

### 5. Loggable - Structured Logging Context

**Purpose:** Extract structured logging context from domain objects.

```elixir
defprotocol Events.Loggable do
  @moduledoc """
  Protocol for extracting structured logging context.

  Integrates with Logger metadata for consistent, searchable logs.
  """

  @doc "Extract a map of loggable context"
  @spec log_context(t) :: map()
  def log_context(value)

  @doc "Sensitivity level - determines what gets logged"
  @spec log_level(t) :: :full | :safe | :minimal
  def log_level(value)
end
```

**Implementations:**

```elixir
defimpl Events.Loggable, for: Events.Domains.Accounts.User do
  def log_context(user) do
    %{
      user_id: user.id,
      user_email: mask_email(user.email),
      user_status: user.status,
      user_type: user.type
    }
  end

  def log_level(_), do: :safe

  defp mask_email(email) do
    case String.split(email, "@") do
      [local, domain] -> "#{String.slice(local, 0, 2)}***@#{domain}"
      _ -> "***"
    end
  end
end

defimpl Events.Loggable, for: FnTypes.Error do
  def log_context(error) do
    %{
      error_type: error.type,
      error_code: error.code,
      error_message: error.message,
      error_id: error.id
    }
  end

  def log_level(error) do
    if error.type in [:internal, :external], do: :full, else: :safe
  end
end
```

**Usage with decorator:**
```elixir
@decorate log_context(protocol: Events.Loggable)
def create_user(params) do
  # Logger automatically includes user context
end
```

---

## Recommended Protocols (High Value)

### 6. Displayable - Human-Readable Output

**Purpose:** Generate human-readable representations for UI/emails/reports.

```elixir
defprotocol Events.Displayable do
  @moduledoc """
  Protocol for human-readable display output.

  Different from Inspect (for developers) - this is for end users.
  """

  @doc "Short display name"
  @spec display_name(t) :: String.t()
  def display_name(value)

  @doc "Full display with details"
  @spec display_full(t) :: String.t()
  def display_full(value)
end
```

---

### 7. Diffable - Change Tracking

**Purpose:** Compute and apply differences between versions.

```elixir
defprotocol Events.Diffable do
  @moduledoc """
  Protocol for computing differences between versions.

  Useful for audit logs, event sourcing, and efficient updates.
  """

  @doc "Compute the difference from old to new"
  @spec diff(old :: t, new :: t) :: map()
  def diff(old, new)

  @doc "Fields to include in diff (nil for all)"
  @spec diffable_fields(t) :: [atom()] | nil
  def diffable_fields(value)
end
```

---

### 8. Telemetryable - Metrics Extraction

**Purpose:** Extract telemetry metrics from domain objects.

```elixir
defprotocol Events.Telemetryable do
  @moduledoc """
  Protocol for extracting telemetry metrics.

  Integrates with :telemetry for observability.
  """

  @doc "Extract metrics as a map"
  @spec metrics(t) :: map()
  def metrics(value)

  @doc "Extract metadata/tags for the metrics"
  @spec metric_tags(t) :: map()
  def metric_tags(value)
end
```

---

## Nice-to-Have Protocols

### 9. Validatable - Pre-Persistence Validation

```elixir
defprotocol Events.Validatable do
  @doc "Validate the value, returning {:ok, value} or {:error, errors}"
  @spec validate(t) :: {:ok, t} | {:error, term()}
  def validate(value)
end
```

### 10. Hashable - Consistent Hashing

```elixir
defprotocol Events.Hashable do
  @doc "Generate a consistent hash for the value"
  @spec hash(t) :: integer()
  def hash(value)
end
```

### 11. Comparable - Domain Ordering

```elixir
defprotocol Events.Comparable do
  @doc "Compare two values: :lt, :eq, or :gt"
  @spec compare(t, t) :: :lt | :eq | :gt
  def compare(a, b)
end
```

---

## Implementation Priority

### Phase 1: Foundation ✅
1. ~~**Normalizable** - Unify error handling~~ → See `FnTypes.Error` and `FnTypes.Protocols.Recoverable`
2. **Identifiable** - Entity identity for caching/events ✅ IMPLEMENTED
3. **Loggable** - Structured logging

### Phase 2: Reliability (Partial)
4. **Recoverable** - Error recovery strategies ✅ IMPLEMENTED
5. **Cacheable** - Cache configuration

### Phase 3: Observability
6. **Telemetryable** - Metrics extraction
7. **Diffable** - Change tracking

### Phase 4: Polish
8. **Displayable** - Human-readable output
9. **Validatable** - Pre-persistence validation

---

## Anti-Patterns to Avoid

### Don't: Protocol for Core Monadic Operations
```elixir
# BAD - Don't do this
defprotocol Events.Monad do
  def bind(m, f)
  def return(value)
end
```
**Why:** Result, Maybe, Validation have different semantics. Explicit module functions are clearer.

### Don't: Protocol for Simple Type Conversion
```elixir
# BAD - Overkill
defprotocol Events.ToString do
  def to_string(value)
end
```
**Why:** Use `String.Chars` protocol or explicit functions.

### Don't: Protocol with Too Many Methods
```elixir
# BAD - Too broad
defprotocol Events.Entity do
  def id(e)
  def type(e)
  def validate(e)
  def serialize(e)
  def cache_key(e)
  def log_context(e)
end
```
**Why:** Split into focused protocols (Identifiable, Validatable, Cacheable, Loggable).

---

## Integration with Existing Systems

### With Decorators
```elixir
# Decorator that uses Loggable protocol
@decorate log_context()
def create_user(user_params) do
  # Automatically extracts context via Events.Loggable.log_context/1
end
```

### With Pipeline
```elixir
Pipeline.new(ctx)
|> Pipeline.step(:validate, fn ctx ->
  case Events.Validatable.validate(ctx.params) do
    {:ok, _} -> {:ok, %{}}
    {:error, e} -> {:error, FnTypes.Protocols.Normalizable.normalize(e)}
  end
end)
```

### With Error Handling
```elixir
def with_recovery(fun) do
  case fun.() do
    {:ok, result} -> {:ok, result}
    {:error, error} ->
      if FnTypes.Protocols.Recoverable.recoverable?(error) do
        retry_with_strategy(fun, error)
      else
        {:error, error}
      end
  end
end
```
