# Claude Code Instructions for Events Project

## Required Reading

**IMPORTANT:** Before working on this codebase, you MUST follow these guidelines:

1. **`docs/development/AGENTS.md`** - Project conventions, code style, and patterns (READ FIRST)
2. **`docs/EVENTS_REFERENCE.md`** - Schema, Migration, and Decorator macro reference

The AGENTS.md file contains critical guidelines including:
- Pattern matching over conditionals (no `if...else`)
- Result tuples (`{:ok, result} | {:error, reason}`) for all fallible functions
- Token pattern for pipelines
- Soft delete conventions
- Phoenix/LiveView best practices
- Type decorators usage

---

## Schema and Migration Guidelines

**IMPORTANT:** This project has custom Schema and Migration macro systems that extend Ecto. Always use these instead of raw Ecto when available.

### Reference Documentation

Before creating or modifying schemas, migrations, or adding decorators, review:
- `docs/EVENTS_REFERENCE.md` - Complete reference with examples for Schema, Migration, and Decorator systems

### Schema Rules

1. **Always use `Events.Schema` instead of `Ecto.Schema`:**
   ```elixir
   # CORRECT
   use Events.Schema

   # WRONG - Don't use raw Ecto.Schema
   use Ecto.Schema
   ```

2. **Use field group macros for standard fields:**
   ```elixir
   schema "users" do
     # Custom fields first
     field :name, :string, required: true

     # Then field groups
     type_fields()
     status_fields(values: [:active, :inactive], default: :active)
     audit_fields()
     timestamps()
   end
   ```

3. **Use presets for common field patterns:**
   ```elixir
   import Events.Schema.Presets

   field :email, :string, email()
   field :username, :string, username()
   field :password, :string, password()
   ```

4. **Use validation options directly on fields:**
   ```elixir
   field :age, :integer, required: true, positive: true, max: 150
   field :email, :string, required: true, format: :email, mappers: [:trim, :downcase]
   ```

5. **Use `base_changeset/3` instead of manual cast/validate_required:**
   ```elixir
   def changeset(user, attrs) do
     user
     |> base_changeset(attrs)
     |> unique_constraints([{:email, []}])
   end
   ```

### Migration Rules

1. **Always use `Events.Migration` instead of `Ecto.Migration`:**
   ```elixir
   # CORRECT
   use Events.Migration

   # WRONG - Don't use raw Ecto.Migration
   use Ecto.Migration
   ```

2. **Use the pipeline pattern for table creation:**
   ```elixir
   def change do
     create_table(:users)
     |> with_uuid_primary_key()
     |> with_identity(:name, :email)
     |> with_audit()
     |> with_soft_delete()
     |> with_timestamps()
     |> execute()
   end
   ```

3. **Use DSL Enhanced macros inside create blocks:**
   ```elixir
   create table(:products, primary_key: false) do
     uuid_primary_key()
     type_fields()
     status_fields()
     metadata_field()
     timestamps(type: :utc_datetime_usec)
   end
   ```

4. **Use field builder helpers:**
   - `with_uuid_primary_key()` - UUIDv7 primary key
   - `with_type_fields()` - Type/subtype classification
   - `with_status_fields()` - Status tracking
   - `with_audit()` - Audit fields (created_by, updated_by)
   - `with_soft_delete()` - Soft delete support
   - `with_timestamps()` - inserted_at/updated_at
   - `with_metadata()` - JSONB metadata field

### When to Fall Back to Raw Ecto

Only use raw Ecto functions when:
1. The Events macros don't support a specific feature
2. You need very custom behavior not covered by the system
3. You're working with legacy code that hasn't been migrated

Even then, prefer extending the Events system over bypassing it.

### Quick Reference

**Schema Presets:** `email()`, `username()`, `password()`, `phone()`, `url()`, `slug()`, `money()`, `percentage()`, `age()`, `rating()`, `latitude()`, `longitude()`

**Field Groups:** `type_fields()`, `status_fields()`, `audit_fields()`, `timestamps()`, `metadata_field()`, `soft_delete_field()`, `standard_fields()`

**Migration Pipelines:** `with_uuid_primary_key()`, `with_identity()`, `with_authentication()`, `with_profile()`, `with_type_fields()`, `with_status_fields()`, `with_metadata()`, `with_tags()`, `with_audit()`, `with_soft_delete()`, `with_timestamps()`

**Mappers:** `:trim`, `:downcase`, `:upcase`, `:capitalize`, `:titlecase`, `:squish`, `:slugify`, `:digits_only`, `:alphanumeric_only`

---

## Decorator System

This project has a comprehensive decorator system for cross-cutting concerns. **Always use decorators** for type contracts, caching, telemetry, validation, and security instead of implementing these patterns manually.

See `docs/EVENTS_REFERENCE.md` for complete decorator documentation with all options and examples.

### Getting Started

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:my_app, :users, :get])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

### Decorator Best Practices

1. **Always use type decorators** - Every fallible function should declare its return type contract
2. **Stack decorators** for comprehensive behavior:
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom)
   @decorate telemetry_span([:app, :users, :create])
   @decorate validate_schema(schema: UserSchema)
   def create_user(params), do: ...
   ```
3. **Use `normalize_result/1`** for external APIs that don't follow result tuple pattern
4. **Add telemetry spans** to all public API functions
5. **Use caching decorators** instead of manual caching logic
6. **Apply security decorators** to all protected endpoints

### Quick Decorator Reference

| Category | Decorators |
|----------|-----------|
| **Types** | `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `normalize_result` |
| **Caching** | `cacheable`, `cache_put`, `cache_evict` |
| **Telemetry** | `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `log_query`, `capture_errors`, `measure`, `benchmark`, `track_memory` |
| **Validation** | `validate_schema`, `coerce_types`, `serialize`, `contract` |
| **Security** | `role_required`, `rate_limit`, `audit_log` |
| **Debugging** | `debug`, `inspect`, `pry` (dev only) |
| **Purity** | `pure`, `deterministic`, `idempotent`, `memoizable` |
