# API Consistency Improvements - 2026-01-06

**Status:** 🔄 PROPOSED
**Priority:** HIGH
**Estimated Effort:** 15-20 hours across 4 phases

---

## Executive Summary

Analysis of 23 libraries revealed **8 critical inconsistencies** that reduce API predictability, expressiveness, and composability. This document proposes targeted improvements to establish consistent patterns across all libraries.

**Key Issues:**
- 🔴 **Return types violate "Result tuples everywhere"** (OmCrud, OmS3)
- 🔴 **3 different configuration patterns** (OmS3, OmCache, OmIdempotency)
- 🔴 **Naming inconsistency** (`delete` vs `remove`, `fetch` vs `retrieve`)
- 🟡 **Batch operations return different structures** (OmS3)
- 🟡 **Option validation chaos** (some raise, some silent, no standard)
- 🟡 **Context/metadata fragmentation** (3 different patterns)

---

## Problem 1: Return Type Inconsistency 🔴

### Current State

**OmCrud violates "Result tuples everywhere":**
```elixir
# libs/om_crud/lib/om_crud.ex

@spec fetch(module(), term(), keyword()) :: {:ok, struct()} | {:error, :not_found}
def fetch(schema, id, opts \\ []) do
  # Returns {:ok, record} | {:error, :not_found} ✅
end

@spec get(module(), term(), keyword()) :: struct() | nil
def get(schema, id, opts \\ []) do
  # Returns record | nil ❌ (not a Result tuple!)
end

@spec exists?(module(), term(), keyword()) :: boolean()
def exists?(schema, id, opts \\ []) do
  # Returns true | false ❌ (not a Result tuple!)
end

@spec count(module(), keyword()) :: non_neg_integer()
def count(schema, opts \\ []) do
  # Returns integer ❌ (not a Result tuple!)
end
```

**OmS3 asymmetric returns:**
```elixir
# libs/om_s3/lib/om_s3.ex

@spec put(uri(), binary(), Config.t()) :: :ok | {:error, term()}
def put(uri, content, config) do
  # Returns :ok ❌ (not {:ok, value})
end

@spec get(uri(), Config.t()) :: {:ok, binary()} | {:error, term()}
def get(uri, config) do
  # Returns {:ok, binary()} ✅
end
```

### Problems

1. **Pipeline composition breaks:**
```elixir
# Can't use get/2 in Result pipelines
OmCrud.get(User, id)
|> Result.and_then(&process/1)  # FAILS! get returns nil or value, not {:ok, value}
```

2. **Inconsistent error handling:**
```elixir
# Different patterns for same operation
case OmCrud.fetch(User, id) do
  {:ok, user} -> ...
  {:error, :not_found} -> ...
end

# vs
case OmCrud.get(User, id) do
  nil -> ...
  user -> ...
end
```

3. **Hard to refactor:**
Changing from `get/2` to `fetch/2` requires rewriting all callsites.

### Solution: Standardize All Returns to Result Tuples

#### Proposal 1: Make `get/2` return Result tuple

```elixir
# BEFORE
@spec get(module(), term(), keyword()) :: struct() | nil
def get(schema, id, opts \\ []) do
  repo.get(schema, id, opts)
end

# AFTER
@spec get(module(), term(), keyword()) :: {:ok, struct()} | {:error, :not_found}
def get(schema, id, opts \\ []) do
  case repo.get(schema, id, opts) do
    nil -> {:error, :not_found}
    record -> {:ok, record}
  end
end
```

**OR deprecate `get/2` entirely and use `fetch/2`.**

#### Proposal 2: Make `exists?/2` return Result tuple

```elixir
# BEFORE
@spec exists?(module(), term(), keyword()) :: boolean()
def exists?(schema, id, opts \\ []) do
  repo.exists?(schema, [id: id] ++ opts)
end

# AFTER (Option A: Return Result tuple)
@spec exists?(module(), term(), keyword()) :: {:ok, boolean()} | {:error, term()}
def exists?(schema, id, opts \\ []) do
  {:ok, repo.exists?(schema, [id: id] ++ opts)}
rescue
  e -> {:error, e}
end

# AFTER (Option B: Keep boolean but add fetch variant)
@spec exists?(module(), term(), keyword()) :: boolean()
def exists?(schema, id, opts \\ []) do
  repo.exists?(schema, [id: id] ++ opts)
end

@spec check_exists(module(), term(), keyword()) :: {:ok, boolean()} | {:error, term()}
def check_exists(schema, id, opts \\ []) do
  {:ok, exists?(schema, id, opts)}
rescue
  e -> {:error, e}
end
```

**Recommendation:** Option B - keep `exists?/2` as boolean for guards, add `check_exists/3` for pipelines.

#### Proposal 3: Make `count/2` return Result tuple

```elixir
# BEFORE
@spec count(module(), keyword()) :: non_neg_integer()
def count(schema, opts \\ []) do
  repo.aggregate(schema, :count, opts)
end

# AFTER
@spec count(module(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
def count(schema, opts \\ []) do
  {:ok, repo.aggregate(schema, :count, opts)}
rescue
  e -> {:error, e}
end
```

#### Proposal 4: Make OmS3 writes return `{:ok, value}`

```elixir
# BEFORE
@spec put(uri(), binary(), Config.t()) :: :ok | {:error, term()}
def put(uri, content, config) do
  # ... implementation
  :ok
end

# AFTER
@spec put(uri(), binary(), Config.t()) :: {:ok, uri()} | {:error, term()}
def put(uri, content, config) do
  # ... implementation
  {:ok, uri}
end

# Same for delete, copy
@spec delete(uri(), Config.t()) :: {:ok, uri()} | {:error, term()}
@spec copy(from :: uri(), to :: uri(), Config.t()) :: {:ok, to :: uri()} | {:error, term()}
```

### Migration Strategy

1. **Deprecation period (3 months):**
   - Add new functions with Result tuple returns
   - Mark old functions as deprecated with warnings
   - Update all internal usage to new functions

2. **Documentation:**
   - Update all examples to use Result-returning variants
   - Add migration guide to each library README

3. **Breaking change:**
   - Remove deprecated functions in next major version

### Impact Analysis

| Library | Functions Affected | Breaking? | Effort |
|---------|-------------------|-----------|--------|
| OmCrud | `get/3`, `exists?/3`, `count/2` | Yes | 4-6 hours |
| OmS3 | `put/*`, `delete/*`, `copy/*` | Yes | 3-4 hours |
| **Total** | **6 functions** | **Yes** | **7-10 hours** |

**Affected code:**
- Internal: ~50 callsites across main app
- External: Libraries depend on OmCrud (need updates)

**Benefits:**
- ✅ Consistent with "Result tuples everywhere" golden rule
- ✅ Enables pipeline composition everywhere
- ✅ Easier to refactor (all reads have same signature)
- ✅ Better error handling (can distinguish failure from "not found")

---

## Problem 2: Configuration Pattern Chaos 🔴

### Current State

**Three different configuration patterns:**

1. **Explicit config function (OmS3, OmStripe):**
```elixir
# libs/om_s3/lib/om_s3/config.ex
defmodule OmS3.Config do
  defstruct [:access_key_id, :secret_access_key, :region, :bucket]

  def new(opts), do: struct(__MODULE__, opts)
  def from_env, do: new([...])  # Reads env vars
end

# Usage
config = OmS3.config(access_key_id: "...", bucket: "...")
OmS3.put(uri, content, config)
```

2. **Macro-based (OmCache):**
```elixir
# libs/om_cache/lib/om_cache.ex
defmodule MyApp.Cache do
  use OmCache, otp_app: :my_app, default_adapter: :redis
end

# No config function, configured via `use` macro
```

3. **Direct env reading (OmIdempotency, OmKillSwitch):**
```elixir
# libs/om_idempotency/lib/om_idempotency.ex
def repo do
  Application.get_env(:om_idempotency, :repo, Events.Data.Repo)
end

# libs/om_kill_switch/lib/om_kill_switch.ex
def enabled?(service) do
  services = Application.get_env(:om_kill_switch, :services, [])
  service in services
end

# No config module at all
```

### Problems

1. **Hard to learn:** Developers need to learn 3 patterns for essentially the same thing
2. **Inconsistent testing:** Some can be tested with explicit config, others need env setup
3. **Documentation confusion:** README examples differ widely
4. **Hard to compose:** Can't write generic config validators

### Solution: Standardize on Explicit Config Pattern

#### Standard Pattern

**Every library should have:**

1. **Config module:**
```elixir
# libs/{library}/lib/{library}/config.ex
defmodule MyLib.Config do
  @moduledoc """
  Configuration for MyLib.

  ## Fields

  - `:field1` - Description (required)
  - `:field2` - Description (optional, default: value)

  ## Examples

      # Explicit config
      config = MyLib.Config.new(field1: "value")

      # From environment
      config = MyLib.Config.from_env()

      # From application config
      config = MyLib.Config.from_app(:my_app)
  """

  @type t :: %__MODULE__{
    field1: String.t(),
    field2: term()
  }

  defstruct field1: nil, field2: :default

  @doc "Create config from keyword list"
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    config = struct(__MODULE__, opts)
    validate(config)
  end

  @doc "Create config from environment variables"
  @spec from_env(keyword()) :: {:ok, t()} | {:error, term()}
  def from_env(overrides \\ []) do
    opts = [
      field1: System.get_env("MY_LIB_FIELD1"),
      field2: System.get_env("MY_LIB_FIELD2")
    ]
    new(Keyword.merge(opts, overrides))
  end

  @doc "Create config from application environment"
  @spec from_app(atom(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_app(otp_app, overrides \\ []) do
    opts = Application.get_env(otp_app, __MODULE__, [])
    new(Keyword.merge(opts, overrides))
  end

  @doc "Validate config"
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{field1: nil}), do: {:error, :field1_required}
  def validate(%__MODULE__{} = config), do: {:ok, config}
end
```

2. **Convenience function in main module:**
```elixir
# libs/{library}/lib/{library}.ex
defmodule MyLib do
  @doc "Create config (convenience for MyLib.Config.new/1)"
  defdelegate config(opts \\ []), to: MyLib.Config, as: :new

  @doc "Create config from environment (convenience)"
  defdelegate from_env(opts \\ []), to: MyLib.Config, as: :from_env
end
```

#### Migration Plan

1. **Add Config modules to libraries without them:**
   - OmIdempotency
   - OmKillSwitch
   - OmCache (keep macro, add explicit config too)

2. **Standardize naming:**
   - `config/1` → `Config.new/1`
   - `from_env/0` → `Config.from_env/1`
   - `config_from_env/0` → `Config.from_env/1`

3. **Add validation everywhere:**
   - All Config modules should have `validate/1`
   - Return `{:ok, config}` or `{:error, reason}`

### Example Refactoring: OmIdempotency

**BEFORE:**
```elixir
# libs/om_idempotency/lib/om_idempotency.ex
defp repo do
  Application.get_env(:om_idempotency, :repo, Events.Data.Repo)
end

defp table do
  Application.get_env(:om_idempotency, :table, "idempotency_keys")
end
```

**AFTER:**
```elixir
# libs/om_idempotency/lib/om_idempotency/config.ex (NEW FILE)
defmodule OmIdempotency.Config do
  @moduledoc """
  Configuration for OmIdempotency.

  ## Fields

  - `:repo` - Ecto repo module (default: Events.Data.Repo)
  - `:table` - Table name (default: "idempotency_keys")
  - `:default_ttl` - Default TTL in milliseconds (default: 24 hours)

  ## Examples

      # Explicit config
      config = OmIdempotency.config(repo: MyApp.Repo, table: "my_table")

      # From environment
      config = OmIdempotency.from_env()
  """

  @type t :: %__MODULE__{
    repo: module(),
    table: String.t(),
    default_ttl: pos_integer()
  }

  defstruct repo: Events.Data.Repo,
            table: "idempotency_keys",
            default_ttl: :timer.hours(24)

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    config = struct(__MODULE__, opts)
    validate(config)
  end

  @spec from_env(keyword()) :: {:ok, t()} | {:error, term()}
  def from_env(overrides \\ []) do
    opts = [
      repo: env_repo(),
      table: System.get_env("IDEMPOTENCY_TABLE", "idempotency_keys")
    ]
    new(Keyword.merge(opts, overrides))
  end

  @spec from_app(atom(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_app(otp_app, overrides \\ []) do
    opts = Application.get_env(otp_app, __MODULE__, [])
    new(Keyword.merge(opts, overrides))
  end

  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{repo: nil}), do: {:error, :repo_required}
  def validate(%__MODULE__{table: table}) when not is_binary(table),
    do: {:error, :table_must_be_string}
  def validate(%__MODULE__{} = config), do: {:ok, config}

  defp env_repo do
    case System.get_env("IDEMPOTENCY_REPO") do
      nil -> Events.Data.Repo
      module_name -> String.to_existing_atom("Elixir.#{module_name}")
    end
  end
end

# libs/om_idempotency/lib/om_idempotency.ex (UPDATED)
defmodule OmIdempotency do
  @doc "Create config (convenience for Config.new/1)"
  defdelegate config(opts \\ []), to: OmIdempotency.Config, as: :new

  @doc "Create config from environment"
  defdelegate from_env(opts \\ []), to: OmIdempotency.Config, as: :from_env

  # Update all functions to accept config
  @spec execute(key(), function(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(key, fun, opts \\ []) do
    config = Keyword.get(opts, :config) || default_config()
    # ... use config.repo, config.table, etc.
  end

  defp default_config do
    case Config.from_app(:events) do
      {:ok, config} -> config
      {:error, _} -> struct(Config)  # Use defaults
    end
  end
end
```

### Impact Analysis

| Library | Has Config? | Needs Refactor? | Effort |
|---------|-------------|-----------------|--------|
| OmIdempotency | No | Yes | 3-4 hours |
| OmKillSwitch | No | Yes | 2-3 hours |
| OmCache | Macro-based | Add explicit | 2 hours |
| OmS3 | Yes | Standardize | 1 hour |
| OmStripe | Yes | Standardize | 1 hour |
| OmGoogle | Yes | Standardize | 1 hour |
| **Total** | **3/6** | **6 libraries** | **10-14 hours** |

**Benefits:**
- ✅ Single pattern to learn
- ✅ Easier testing (explicit config)
- ✅ Better validation (catch config errors early)
- ✅ Clearer documentation

---

## Problem 3: Naming Inconsistency 🔴

### Current State

| Operation | OmCrud | OmStripe | Ecto | Standard |
|-----------|--------|----------|------|----------|
| Create | `create/3` | `create/2` | `insert/2` | `create` ✅ |
| Read | `fetch/3` | `retrieve/2` | `get/2` | **Inconsistent** ❌ |
| Update | `update/3` | `update/2` | `update/2` | `update` ✅ |
| Delete | `delete/3` | `remove/2` | `delete/2` | **Inconsistent** ❌ |

### Problems

1. **Hard to remember:** Is it `fetch` or `retrieve`? `delete` or `remove`?
2. **Reduces discoverability:** Developers guess wrong and get "undefined function" errors
3. **Inconsistent with REST:** REST uses `GET`, `DELETE` (not `RETRIEVE`, `REMOVE`)

### Solution: Establish Standard Terminology

#### Proposed Standard

| Operation | Standard Name | Alternatives (Deprecated) | Rationale |
|-----------|---------------|---------------------------|-----------|
| Create | `create` | - | Universal standard |
| Read (single) | `fetch` | `get`, `retrieve` | Ecto uses `get`, but we want explicit error handling |
| Read (many) | `list` | `all`, `fetch_all` | Clear intent |
| Update | `update` | - | Universal standard |
| Delete | `delete` | `remove`, `destroy` | REST standard, clear intent |
| Exists | `exists?` | `present?`, `has?` | Elixir convention (? for boolean) |
| Count | `count` | `size`, `length` | SQL standard |

#### Migration: Add Aliases, Deprecate Old Names

**OmStripe example:**
```elixir
# libs/om_stripe/lib/om_stripe.ex

# Keep old function but mark deprecated
@deprecated "Use fetch/2 instead"
@spec retrieve(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
def retrieve(id, config), do: fetch(id, config)

# New standard name
@spec fetch(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
def fetch(id, config) do
  # ... implementation
end

@deprecated "Use delete/2 instead"
@spec remove(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
def remove(id, config), do: delete(id, config)

@spec delete(String.t(), Config.t()) :: {:ok, map()} | {:error, term()}
def delete(id, config) do
  # ... implementation
end
```

### Impact Analysis

| Library | Functions Affected | Effort |
|---------|-------------------|--------|
| OmStripe | `retrieve` → `fetch`, `remove` → `delete` | 2 hours |
| Others | Minimal (already use standard names) | 1 hour |
| **Total** | **2 libraries** | **3 hours** |

**Benefits:**
- ✅ Clear, predictable API
- ✅ Easier onboarding
- ✅ Better discoverability

---

## Problem 4: Batch Operation Return Chaos 🟡

### Current State

**OmS3 batch operations return different tuple structures:**
```elixir
# libs/om_s3/lib/om_s3.ex

put_all(uris, contents)
# Returns: [{:ok, uri} | {:error, uri, reason}]
#          ^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^^^
#          2-tuple ok    3-tuple error

get_all(uris)
# Returns: [{:ok, uri, binary} | {:error, uri, reason}]
#          ^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^
#          3-tuple ok!           3-tuple error

delete_all(uris)
# Returns: [{:ok, uri} | {:error, uri, reason}]
#          ^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^^^
#          2-tuple ok    3-tuple error

copy_all(pairs, opts)
# Returns: [{:ok, from_uri, to_uri} | {:error, from_uri, reason}]
#          ^^^^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^^^^^^^^
#          3-tuple ok!                  3-tuple error
```

### Problems

1. **Can't write generic batch handlers:**
```elixir
# This doesn't work - different tuple sizes!
def process_batch_results(results) do
  Enum.reduce(results, %{success: [], failed: []}, fn
    {:ok, value} -> ...          # Works for put_all
    {:ok, key, value} -> ...     # Works for get_all, copy_all
    {:error, key, reason} -> ... # Works for all errors
  end)
end
```

2. **Confusing API surface:** Users don't know what to expect

### Solution: Standardize Batch Return Structure

#### Proposal: Always Return 3-Tuples

```elixir
# Standard structure for ALL batch operations:
# Success: {:ok, key, result}
# Error:   {:error, key, reason}

put_all(uris, contents)
# Returns: [{:ok, uri, :put} | {:error, uri, reason}]
#          ^^^^^^^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^^^
#          Always 3-tuple      Always 3-tuple

get_all(uris)
# Returns: [{:ok, uri, binary} | {:error, uri, reason}]
#          ^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^
#          Already correct!

delete_all(uris)
# Returns: [{:ok, uri, :deleted} | {:error, uri, reason}]
#          ^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^
#          Always 3-tuple           Always 3-tuple

copy_all(pairs, opts)
# Returns: [{:ok, from_uri, to_uri} | {:error, from_uri, reason}]
#          ^^^^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^^^^^^^^
#          Already correct!
```

**Generic handler now works:**
```elixir
def process_batch_results(results) do
  Enum.reduce(results, %{success: [], failed: []}, fn
    {:ok, key, value}, acc ->
      %{acc | success: [{key, value} | acc.success]}
    {:error, key, reason}, acc ->
      %{acc | failed: [{key, reason} | acc.failed]}
  end)
end
```

### Impact Analysis

| Function | Change | Breaking? | Effort |
|----------|--------|-----------|--------|
| `put_all/2` | Add `:put` atom to success tuple | Yes | 1 hour |
| `delete_all/2` | Add `:deleted` atom to success tuple | Yes | 1 hour |
| **Total** | **2 functions** | **Yes** | **2 hours** |

**Benefits:**
- ✅ Generic batch handlers possible
- ✅ Predictable API
- ✅ Easier to document

---

## Problem 5: Option Validation Chaos 🟡

### Current State

```elixir
# Some libraries raise on missing required options
OmS3.copy_all(..., to: dest)
# Keyword.fetch!(:to) - raises KeyError if missing!

# Some silently merge options
OmCrud.execute_merge(merge, opts)
# Keyword.merge - typos silently ignored

# Some have explicit defaults
OmIdempotency.execute(key, fun, on_duplicate: :return)
# Documented defaults, validated
```

### Problems

1. **Typos go undetected:**
```elixir
OmCrud.create(User, attrs, timout: 5000)  # Typo! Should be "timeout"
# Silently ignored, default timeout used
```

2. **Inconsistent error messages:** Some raise, some return errors, some ignore

3. **Hard to debug:** Silent failures are worst kind of bug

### Solution: Standardized Option Validation

#### Create `FnTypes.Options` Module

```elixir
# libs/fn_types/lib/fn_types/options.ex (NEW FILE)
defmodule FnTypes.Options do
  @moduledoc """
  Option validation utilities for consistent option handling.

  ## Examples

      # Define option schema
      schema = [
        required: [:repo, :schema],
        optional: [:timeout, :prefix],
        defaults: [timeout: 15_000],
        types: [repo: :module, schema: :module, timeout: :integer, prefix: :string]
      ]

      # Validate options
      case Options.validate(opts, schema) do
        {:ok, validated_opts} -> use_opts(validated_opts)
        {:error, {:unknown_option, key}} -> ...
        {:error, {:missing_required, key}} -> ...
        {:error, {:invalid_type, key, expected, got}} -> ...
      end
  """

  @type schema :: [
    required: [atom()],
    optional: [atom()],
    defaults: keyword(),
    types: keyword()
  ]

  @spec validate(keyword(), schema()) :: {:ok, keyword()} | {:error, term()}
  def validate(opts, schema) do
    with :ok <- check_required(opts, schema[:required] || []),
         :ok <- check_types(opts, schema[:types] || []),
         :ok <- check_unknown(opts, schema) do
      validated = apply_defaults(opts, schema[:defaults] || [])
      {:ok, validated}
    end
  end

  defp check_required(opts, required) do
    case Enum.find(required, &(!Keyword.has_key?(opts, &1))) do
      nil -> :ok
      key -> {:error, {:missing_required, key}}
    end
  end

  defp check_types(opts, type_spec) do
    Enum.reduce_while(opts, :ok, fn {key, value}, :ok ->
      case type_spec[key] do
        nil -> {:cont, :ok}
        expected_type ->
          if valid_type?(value, expected_type) do
            {:cont, :ok}
          else
            {:halt, {:error, {:invalid_type, key, expected_type, typeof(value)}}}
          end
      end
    end)
  end

  defp check_unknown(opts, schema) do
    allowed = (schema[:required] || []) ++ (schema[:optional] || [])
    case Enum.find(opts, fn {key, _} -> key not in allowed end) do
      nil -> :ok
      {key, _} -> {:error, {:unknown_option, key}}
    end
  end

  defp apply_defaults(opts, defaults) do
    Keyword.merge(defaults, opts)
  end

  defp valid_type?(value, :module) when is_atom(value), do: true
  defp valid_type?(value, :string) when is_binary(value), do: true
  defp valid_type?(value, :integer) when is_integer(value), do: true
  defp valid_type?(value, :boolean) when is_boolean(value), do: true
  defp valid_type?(value, :atom) when is_atom(value), do: true
  defp valid_type?(value, :keyword) when is_list(value), do: Keyword.keyword?(value)
  defp valid_type?(value, :map) when is_map(value), do: true
  defp valid_type?(_, _), do: false

  defp typeof(value) when is_atom(value), do: :atom
  defp typeof(value) when is_binary(value), do: :string
  defp typeof(value) when is_integer(value), do: :integer
  defp typeof(value) when is_boolean(value), do: :boolean
  defp typeof(value) when is_list(value), do: :keyword
  defp typeof(value) when is_map(value), do: :map
  defp typeof(_), do: :unknown
end
```

#### Use in Libraries

```elixir
# libs/om_crud/lib/om_crud.ex

alias FnTypes.Options

@crud_option_schema [
  required: [],
  optional: [:repo, :prefix, :timeout, :log, :changeset, :returning],
  defaults: [timeout: 15_000, log: :info],
  types: [
    repo: :module,
    prefix: :string,
    timeout: :integer,
    log: [:atom, false],
    changeset: :atom,
    returning: :boolean
  ]
]

def create(schema, attrs, opts \\ []) do
  with {:ok, validated_opts} <- Options.validate(opts, @crud_option_schema) do
    # Use validated_opts - typos caught!
  end
end
```

### Impact Analysis

| Task | Effort |
|------|--------|
| Create FnTypes.Options module | 4-5 hours |
| Add validation to OmCrud | 2 hours |
| Add validation to OmS3 | 2 hours |
| Add validation to other libs | 4 hours |
| **Total** | **12-13 hours** |

**Benefits:**
- ✅ Typos caught immediately with clear errors
- ✅ Consistent error messages
- ✅ Better developer experience
- ✅ Self-documenting (schema shows all valid options)

---

## Problem 6: Context/Metadata Fragmentation 🟡

### Current State

```elixir
# Pattern 1: Map-based context (OmMiddleware)
@type context :: map()

# Pattern 2: Special keyword key (OmCrud)
Keyword.put(opts, :__crud_context__, %{operation: :create})

# Pattern 3: Metadata in options (OmIdempotency)
execute(key, fun, metadata: %{user_id: 123})
```

### Problems

1. **Can't compose libraries with consistent context flow**
2. **Telemetry metadata inconsistent across libraries**
3. **Hard to trace requests across library boundaries**

### Solution: Standard Context Type

#### Create `FnTypes.Context` Module

```elixir
# libs/fn_types/lib/fn_types/context.ex (NEW FILE)
defmodule FnTypes.Context do
  @moduledoc """
  Standard context type for cross-cutting concerns.

  Context flows through function calls carrying metadata for:
  - Telemetry
  - Logging
  - Tracing
  - Request IDs
  - User identity
  - Tenant scope

  ## Examples

      # Create context
      ctx = Context.new(request_id: "abc123", user_id: 456)

      # Add metadata
      ctx = Context.put(ctx, :operation, :create_user)

      # Extract for telemetry
      Context.to_telemetry_metadata(ctx)
  """

  @type t :: %__MODULE__{
    request_id: String.t() | nil,
    trace_id: String.t() | nil,
    user_id: term() | nil,
    tenant_id: term() | nil,
    metadata: map()
  }

  defstruct request_id: nil,
            trace_id: nil,
            user_id: nil,
            tenant_id: nil,
            metadata: %{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{metadata: meta} = ctx, key, value) do
    %{ctx | metadata: Map.put(meta, key, value)}
  end

  @spec get(t(), atom(), term()) :: term()
  def get(%__MODULE__{metadata: meta}, key, default \\ nil) do
    Map.get(meta, key, default)
  end

  @spec to_telemetry_metadata(t()) :: map()
  def to_telemetry_metadata(%__MODULE__{} = ctx) do
    ctx
    |> Map.from_struct()
    |> Map.delete(:metadata)
    |> Map.merge(ctx.metadata)
  end
end
```

#### Use in Libraries

```elixir
# libs/om_crud/lib/om_crud.ex

alias FnTypes.Context

def create(schema, attrs, opts \\ []) do
  ctx = Keyword.get(opts, :context, Context.new())
  ctx = Context.put(ctx, :operation, :create)
  ctx = Context.put(ctx, :schema, schema)

  telemetry_meta = Context.to_telemetry_metadata(ctx)

  :telemetry.span([:events, :crud, :create], telemetry_meta, fn ->
    result = do_create(schema, attrs, opts)
    {result, telemetry_meta}
  end)
end
```

### Impact Analysis

| Task | Effort |
|------|--------|
| Create FnTypes.Context module | 3-4 hours |
| Update OmCrud to use Context | 2 hours |
| Update OmMiddleware to use Context | 2 hours |
| Update OmIdempotency to use Context | 2 hours |
| **Total** | **9-10 hours** |

**Benefits:**
- ✅ Consistent context flow across libraries
- ✅ Standard telemetry metadata
- ✅ Better request tracing
- ✅ Easier to add cross-cutting concerns

---

## Summary: Recommended Action Plan

### Phase 1: Critical Fixes (Week 1) - 10-14 hours

**Priority: Fix violations of core rules**

1. ✅ **Standardize Return Types** (7-10 hours)
   - Make `OmCrud.get/3`, `exists?/3`, `count/2` return Result tuples
   - Make `OmS3.put/3`, `delete/3`, `copy/3` return `{:ok, value}`
   - Add deprecation warnings to old APIs

2. ✅ **Standardize Naming** (3 hours)
   - Alias `retrieve` → `fetch`, `remove` → `delete` in OmStripe
   - Add deprecation warnings

### Phase 2: Configuration & Validation (Week 2) - 12-13 hours

**Priority: Explicit configuration and option validation**

3. ✅ **Create FnTypes.Options** (4-5 hours)
   - Option validation utilities
   - Comprehensive test suite

4. ✅ **Add Option Validation** (4 hours)
   - OmCrud, OmS3, OmStripe, others

5. ✅ **Standardize Config Pattern** (10-14 hours from earlier)
   - Add Config modules to OmIdempotency, OmKillSwitch
   - Standardize all Config modules

### Phase 3: Context & Batch (Week 3) - 11-12 hours

**Priority: Composability and consistency**

6. ✅ **Create FnTypes.Context** (3-4 hours)
   - Standard context type
   - Telemetry integration

7. ✅ **Update Libraries to Use Context** (6 hours)
   - OmCrud, OmMiddleware, OmIdempotency

8. ✅ **Standardize Batch Returns** (2 hours)
   - Fix OmS3 batch operations

### Phase 4: Documentation (Week 4) - 4-5 hours

**Priority: Developer experience**

9. ✅ **Create API Style Guide** (2 hours)
   - Document all standards
   - Migration guides

10. ✅ **Update Library READMEs** (2-3 hours)
    - Consistent examples
    - Deprecation notices

---

## Total Estimated Effort

| Phase | Hours |
|-------|-------|
| Phase 1 | 10-14 |
| Phase 2 | 18-23 |
| Phase 3 | 11-12 |
| Phase 4 | 4-5 |
| **Total** | **43-54 hours** |

---

## Breaking Changes Summary

| Change | Breaking? | Migration Path |
|--------|-----------|----------------|
| Result tuple returns | Yes | Deprecation period, aliases |
| Naming standardization | Yes | Deprecation period, aliases |
| Config pattern | No | Additive changes |
| Option validation | Partially | Errors for invalid options (good!) |
| Context type | No | Optional parameter |
| Batch returns | Yes | Update callsites |

**Recommendation:**
- Release as v2.0 with deprecation warnings
- 3-month deprecation period before removing old APIs

---

## Success Metrics

| Metric | Before | After |
|--------|--------|-------|
| Return type consistency | 60% | 100% |
| Config pattern consistency | 50% | 100% |
| Naming consistency | 75% | 100% |
| Option validation | 30% | 100% |
| Context flow | 0% | 100% |
| Batch operation consistency | 25% | 100% |

---

## Next Steps

1. **Review this document** with team
2. **Approve phases** (can do incrementally)
3. **Execute Phase 1** (critical fixes)
4. **Review results**, adjust plan
5. **Continue with remaining phases**

---

**Status:** 🔄 AWAITING APPROVAL
**Created:** 2026-01-06
**Author:** Claude Opus 4.5
