# Events.Repo.Query Module - Security and Correctness Analysis

## Executive Summary
The Events.Repo.Query module is a composable query builder for Ecto with significant features but contains several critical issues ranging from design flaws to potential runtime errors. Below is a comprehensive analysis across all seven requested categories.

---

## 1. POTENTIAL RUNTIME ERRORS AND EDGE CASES

### 1.1 CRITICAL: Missing Pattern Match Handling in `build_preload_query/2` (Lines 1276-1334)

**Location:** Lines 1276-1334

**Issue:** The `build_preload_query/2` function returns a closure that uses `from(a in assoc)` where `assoc` is an atom, not a schema module. This will fail at runtime.

```elixir
defp build_preload_query(assoc, opts) do
  fn ->
    query = from(a in assoc)  # BUG: assoc is an atom, not a schema
    # ...
  end
end
```

**Problem:** 
- `from/2` requires a module or query, not an atom
- When Ecto evaluates this preload closure, it will crash with a compilation error
- The pattern `from(a in assoc)` where `assoc` is a symbol is invalid Ecto syntax

**Impact:** HIGH - Any use of conditional preloads with the `where:`, `order_by:`, `limit:`, or `offset:` options will fail

**Evidence:** Line 1291: `query = from(a in assoc)` - This attempts to use a bare atom in `from/2` macro

**Mitigation needed:** The function needs the actual schema module, which is unavailable in the current design. Consider using raw Ecto.Query functions instead of the `from/2` macro.

---

### 1.2 CRITICAL: Invalid Fragment Syntax in `apply_jsonb_has_key/3` (Line 1688, 1692)

**Location:** Lines 1687-1693

**Issue:** PostgreSQL JSONB `?` operator syntax is incorrect in the fragment

```elixir
defp apply_jsonb_has_key(query, 0, field, key) do
  from(q in query, where: fragment("? ? ?", field(q, ^field), "?", ^key))
end
```

**Problem:**
- The `?` operator in PostgreSQL JSONB requires the operator as a literal, not a parameter
- Current code: `fragment("? ? ?", field, "?", key)` will generate `column ? ? value`
- Correct syntax: `column ? 'key'` (with key as string, not parameter)
- The fragment is trying to parameterize the operator itself

**Correct approach:**
```elixir
from(q in query, where: fragment("? ? ?", field(q, ^field), literal(^key)))
# OR
from(q in query, where: fragment("? ? ?::text", field(q, ^field), ^key))
```

**Impact:** HIGH - JSONB key presence checks will fail or produce incorrect SQL

---

### 1.3 CRITICAL: Unchecked Empty List in `apply_in/3` and `apply_not_in/3` (Lines 1561-1575)

**Location:** Lines 1561-1575

**Issue:** No validation that list is non-empty before passing to SQL IN clause

```elixir
defp apply_in(query, 0, field, values) when is_list(values) do
  from(q in query, where: field(q, ^field) in ^values)  # Empty list generates invalid SQL
end
```

**Problem:**
- Empty list `[]` in SQL `IN` clause is invalid: `WHERE id IN ()`
- PostgreSQL will reject with: "syntax error at or near ')'"
- No guard clause to catch empty lists

**Expected behavior:** Should either:
- Return query unchanged (since no values to match)
- Raise a validation error
- Return falsy condition (WHERE 1=0)

**Impact:** MEDIUM-HIGH - Can crash queries when filter values accidentally empty

---

### 1.4 HIGH: Missing Error Handling in `get_through_final_field/3` (Lines 1202-1228)

**Location:** Lines 1202-1228

**Issue:** Multiple points of failure with no graceful error handling

```elixir
defp get_through_final_field(schema, through_assoc, _final_assoc) do
  case schema.__schema__(:association, through_assoc) do
    %{related: through_schema} ->
      through_schema.__schema__(:associations)
      |> Enum.find(fn assoc_name ->
        case through_schema.__schema__(:association, assoc_name) do
          %{owner: ^through_schema, related: _} -> true
          _ -> false
        end
      end)
      |> case do
        nil ->
          raise ArgumentError,
                "Could not find final association in #{inspect(through_schema)}"
        field ->
          field
      end
```

**Problems:**
1. If `through_schema.__schema__(:associations)` returns `nil`, `Enum.find/2` will crash
2. If the association lookup returns unexpected structure, crashes silently occur
3. No validation that `through_assoc` actually exists before calling `__schema__`
4. The error message doesn't mention which through_assoc was problematic

**Impact:** MEDIUM - Cryptic errors when schema structure is unexpected

---

### 1.5 MEDIUM: `apply_between/4` Assumes Tuple Structure (Lines 1653-1661)

**Location:** Lines 1653-1661

```elixir
defp apply_between(query, 0, field, {min, max}, _opts) do
  from(q in query, where: field(q, ^field) >= ^min and field(q, ^field) <= ^max)
end
```

**Issue:** 
- Function signature requires `{min, max}` tuple, but there's no guard
- If user passes anything other than 2-tuple, pattern match fails with cryptic error
- Documentation says `:between` takes "two values" but no validation of format

**Example failure:**
```elixir
Query.where(query, {:price, :between, [10, 100]})  # Crashes - list not tuple
Query.where(query, {:price, :between, 10..100})      # Crashes - range not tuple
```

**Impact:** MEDIUM - Poor error messages for common usage mistakes

---

### 1.6 MEDIUM: Race Condition in Soft Delete Pattern (Lines 1035-1048)

**Location:** Lines 1035-1048 in `delete/2`

```elixir
def delete(struct, opts \\ []) when is_struct(struct) do
  if Keyword.get(opts, :hard, false) do
    Repo.delete(struct)
  else
    now = DateTime.utc_now()
    deleted_by = Keyword.get(opts, :deleted_by)
    
    changes = %{deleted_at: now}
    changes = if deleted_by, do: Map.put(changes, :deleted_by_urm_id, deleted_by), else: changes
    
    struct
    |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
    |> Repo.update()
  end
end
```

**Issues:**
1. **Time-of-check-time-of-use (TOCTOU):** `DateTime.utc_now()` is called in application code, not database. In distributed systems, clocks may differ
2. **Concurrent Deletes:** Two processes calling `delete/2` simultaneously could set different `deleted_at` timestamps
3. **Update Isolation:** The update doesn't check if record was already deleted (no optimistic locking)

**Concurrent scenario:**
- Process A and B call `delete(struct)` simultaneously
- Process A sets `deleted_at = 2024-01-01 10:00:00.000`
- Process B sets `deleted_at = 2024-01-01 10:00:00.001`
- Both succeed, but audit trail is inconsistent

**Better approach:**
- Use database `NOW()` via `fragment/1`
- Add check for already-deleted records
- Use `select` option to return old values

**Impact:** MEDIUM - Data consistency issues in concurrent delete scenarios

---

### 1.7 MEDIUM: `include_deleted/1` Loses Previously Applied Filters (Line 903-906)

**Location:** Lines 902-907

```elixir
def include_deleted(%__MODULE__{schema: schema} = builder) do
  # Remove the deleted_at filter
  query = from(s in schema)  # WARNING: Completely rebuilds query!
  %{builder | query: query, include_deleted: true}
end
```

**Issue:**
- Creates brand new query from just the schema, losing ALL previously applied conditions
- Any where/join/order_by/limit applied before `include_deleted()` is lost

**Example failure:**
```elixir
Query.new(Product)
|> Query.where(status: "active")      # Filter 1
|> Query.where(price: {:gt, 100})     # Filter 2
|> Query.include_deleted()            # BUG: Loses both filters!
|> Query.limit(10)                    # Only this limit remains
|> Repo.all()  # Returns unfiltered deleted and active products
```

**Correct approach:**
```elixir
# Rebuild WITHOUT the deleted_at filter
from(s in builder.query, ...)  # Use existing query as base
```

**Impact:** HIGH - Silent data loss, returns wrong results

---

## 2. SQL INJECTION VULNERABILITIES

### 2.1 SAFE: Proper Parameterization Throughout

**Assessment:** The module uses Ecto's parameterized queries correctly:
- All user inputs are passed as `^param` parameters, not string interpolation
- `fragment/2` uses parameterized arguments: `fragment("lower(?)", ^value)`
- No raw SQL concatenation detected

**Examples of safe patterns:**
```elixir
from(q in query, where: field(q, ^field) == ^value)              # Safe
from(q in query, where: fragment("lower(?)", ^value))            # Safe
from(q in query, where: field(q, ^field) in ^values)             # Safe
```

**However, potential issue:**

### 2.2 MEDIUM: Fragment Use Without Validation (Lines 1664, 1672, 1680, 1688, 1692)

**Location:** Lines 1663-1693

```elixir
defp apply_contains(query, 0, field, value) do
  from(q in query, where: fragment("? @> ?", field(q, ^field), ^value))
end

defp apply_jsonb_contains(query, 0, field, value) do
  from(q in query, where: fragment("? @> ?::jsonb", field(q, ^field), ^value))
end
```

**Issue:**
- While parameterized, these PostgreSQL operators require specific data types
- No validation that `field` is actually JSONB or array type
- Passing wrong types to PostgreSQL operators could cause:
  - Runtime errors (operator doesn't exist for type)
  - Type coercion surprises
  - Performance degradation (full table scans)

**Impact:** LOW (Parameterized, but could be safer with type validation)

---

### 2.3 MEDIUM: Fragment in `apply_jsonb_has_key` Operator Syntax (Lines 1687-1693)

**Location:** Lines 1687-1693

```elixir
defp apply_jsonb_has_key(query, 0, field, key) do
  from(q in query, where: fragment("? ? ?", field(q, ^field), "?", ^key))
end
```

**Issue:**
- The `?` operator is being passed as a literal string parameter
- This generates invalid SQL like: `column ? '?' key` (operator as data)
- PostgreSQL will interpret it as string comparison, not operator
- Correct syntax would require: `column ? 'key'`

**This is a logic bug, not SQL injection, but produces incorrect queries**

**Impact:** HIGH - JSONB key checks don't work

---

## 3. MISSING ERROR HANDLING

### 3.1 CRITICAL: No Validation in `where/2` Clause Filters (Lines 315-355)

**Location:** Lines 315-355

**Issues:**
1. No guard on `conditions` being valid format when it's a tuple
2. Tuple with wrong arity pattern matches silently fail
3. No check that atom `field` actually exists in schema

```elixir
def where(%__MODULE__{} = builder, {field, op, value})
    when is_atom(field) and is_atom(op) do
  # No validation that field exists in schema or op is supported
  __MODULE__.where(builder, {nil, field, op, value, []})
end
```

**Example failures:**
```elixir
Query.where(query, {:nonexistent_field, :eq, "value"})  # Silent failure
Query.where(query, {:price, :unsupported_op, 100})      # Generic error at runtime
Query.where(query, {1, :eq, 100})                       # Pattern match silently ignored
```

**Impact:** MEDIUM - Invalid queries compiled without early error detection

---

### 3.2 HIGH: No Validation of Join Associations (Lines 380-441)

**Location:** Lines 380-441 in `join/3`

```elixir
def join(%__MODULE__{} = builder, assoc_name, join_type) when is_atom(join_type) do
  case get_association_type(builder.schema, assoc_name) do
    {:through, [intermediate_assoc, final_field]} ->
      join_through_auto(builder, intermediate_assoc, final_field, assoc_name, join_type)
    :direct ->
      join_direct(builder, assoc_name, join_type)
  end
end
```

**Issues:**
1. `get_association_type/2` doesn't validate association exists
2. Calling `__schema__(:association, invalid_assoc)` returns `nil`, which doesn't match any case
3. Function falls through with no default case - returns the input builder unchanged!
4. Silent failure - no error, just returns unmodified builder

**Example:**
```elixir
Query.new(Product)
|> Query.join(:nonexistent_assoc)  # BUG: Silently ignored, no join occurs
|> Query.where({:nonexistent_assoc, :name, "test"})  # Later crashes with "Join not found"
```

**Impact:** HIGH - Joins silently fail, downstream errors are cryptic

---

### 3.3 HIGH: `get_binding/2` Error Message Quality (Lines 1111-1120)

**Location:** Lines 1111-1120

```elixir
defp get_binding(builder, join_name) do
  if Map.has_key?(builder.joins, join_name) do
    join_name
  else
    raise "Join :#{join_name} not found. Did you forget to call Query.join/2?"
  end
end
```

**Issue:** 
- Error message uses string interpolation directly
- Doesn't show available joins for debugging
- Could suggest better alternatives

**Better error:**
```elixir
available = builder.joins |> Map.keys() |> inspect()
raise "Join :#{join_name} not found. Available joins: #{available}"
```

**Impact:** LOW - Debugging difficulty

---

### 3.4 MEDIUM: `select/2` with Map Silently Ignores Non-Atom Values (Lines 705-726)

**Location:** Lines 705-726

```elixir
def select(%__MODULE__{} = builder, field_map) when is_map(field_map) do
  # ...
  select_expr =
    Enum.reduce(field_map, %{}, fn {key, field}, acc when is_atom(field) ->  # GUARD!
      Map.put(acc, key, dynamic([s], field(s, ^field)))
    end)
  
  query = from(s in builder.query, select: ^select_expr)
  %{builder | query: query}
end
```

**Issue:**
- The pattern match `fn {key, field}, acc when is_atom(field)` filters out non-atom values
- Non-atom values (fragments, calculations, etc.) are silently dropped
- No error, just silent data loss

**Example:**
```elixir
Query.select(query, %{
  id: :id,
  name: :name,
  calculated: fragment("price * quantity")  # Silently dropped!
})
```

**Impact:** MEDIUM - Silent selection of wrong fields

---

## 4. POTENTIAL NIL POINTER EXCEPTIONS

### 4.1 HIGH: `get_through_final_field/3` - Multiple Nil Risks (Lines 1202-1228)

**Location:** Lines 1202-1228

```elixir
defp get_through_final_field(schema, through_assoc, _final_assoc) do
  case schema.__schema__(:association, through_assoc) do
    %{related: through_schema} ->
      through_schema.__schema__(:associations)  # Could return nil
      |> Enum.find(fn assoc_name ->  # Crashes if previous is nil
        case through_schema.__schema__(:association, assoc_name) do
```

**Nil Risks:**
1. `__schema__(:associations)` could return `nil` if association malformed
2. `through_schema` could be `nil` if related field missing
3. `Enum.find/2` called on `nil` causes FunctionClauseError

**Scenario:**
```elixir
# Schema with missing through configuration
defmodule Product do
  schema "products" do
    has_many :tags, Tag  # Missing through: :product_tags
  end
end

Query.join(Product, :tags)  # Crashes with nil error
```

**Impact:** HIGH - Crashes in through association handling

---

### 4.2 MEDIUM: `process_preload/1` Pattern Match Risk (Lines 1262-1273)

**Location:** Lines 1262-1273

```elixir
defp process_preload({assoc, opts}) when is_atom(assoc) and is_list(opts) do
  case opts do
    [%Ecto.Query{} | _] ->
      {assoc, opts}
    _ ->
      query = build_preload_query(assoc, opts)  # Returns closure
      {assoc, query}
  end
end
```

**Issue:**
- `build_preload_query/2` returns a closure (`fn -> ... end`)
- The closure contains `from(a in assoc)` where `assoc` is not yet bound
- Ecto will try to evaluate the closure and fail with cryptic error

**Impact:** MEDIUM-HIGH - Crashes when using conditional preloads

---

### 4.3 MEDIUM: `apply_opts/2` Ignores Unknown Options Silently (Lines 1089-1106)

**Location:** Lines 1089-1106

```elixir
defp apply_opts(builder, opts) do
  Enum.reduce(opts, builder, fn
    {:where, conditions}, acc -> __MODULE__.where(acc, conditions)
    # ... other patterns ...
    _, acc -> acc  # DANGER: Silently ignores unknown options!
  end)
end
```

**Issue:**
- Any typo in option names is silently ignored
- User thinks they're applying a filter but it's not

**Example:**
```elixir
Query.new(Product, [
  where: [status: "active"],
  limit: 10,
  order_bby: [asc: :name]  # Typo! Silently ignored
])
```

**Impact:** MEDIUM - Silent configuration errors

---

## 5. INFINITE LOOPS OR RECURSION ISSUES

### 5.1 SAFE: No Infinite Recursion Detected

**Assessment:** Recursion patterns are safe:

1. **`where/2` recursive calls (Lines 315-355):**
   - Each clause transforms the tuple progressively
   - Base case converts to fully qualified form `{join, field, op, value, opts}`
   - Terminates in `apply_filter/6`
   - No circular patterns detected

2. **`Enum.reduce` usage throughout:**
   - All Enum operations use proper list reduction
   - No unbounded recursion

3. **Join operations:**
   - `join_through_auto/5` and `join_direct/4` don't call each other recursively
   - Proper termination

**However, watch out for:**

### 5.2 MEDIUM: Nested Preload Recursion (Lines 1324-1330)

**Location:** Lines 1324-1330

```elixir
# Apply nested preloads
query =
  if nested_preloads != [] do
    processed_nested = process_preloads(nested_preloads)
    from(a in query, preload: ^processed_nested)
  else
    query
  end
```

**Potential issue:**
- `process_preloads` calls `build_preload_query` which calls `process_preloads` again
- If user provides deeply nested preloads, stack depth could be exceeded
- Ecto preload recursion depth could hit limits

**Example crash scenario:**
```elixir
# Artificially deep nesting
deep_preloads = [user: [posts: [comments: [author: [profile: [settings: [...]]]]]]]
Query.preload(query, deep_preloads)  # Could hit stack limit
```

**Impact:** LOW - Unlikely in practice (Ecto has limits anyway)

---

## 6. RACE CONDITIONS

### 6.1 CRITICAL: Soft Delete Race Condition (Lines 1035-1048)

**Location:** Lines 1035-1048 in `delete/2`

**Already covered in Section 1.6 - Time-of-check-time-of-use vulnerability**

**Summary:** 
- `DateTime.utc_now()` called in Elixir, not database
- Concurrent deletes can have inconsistent timestamps
- No concurrency control (no optimistic locking)

**Additional race scenario:**
```
Thread 1: Check if deleted (deleted_at IS NULL)  ✓ Not deleted
Thread 2: Check if deleted (deleted_at IS NULL)  ✓ Not deleted
Thread 1: Update deleted_at = T1
Thread 2: Update deleted_at = T2  -- Overwrites T1, both succeed!
Result: Last writer wins, inconsistent audit trail
```

**Impact:** HIGH - Concurrent soft delete data corruption

---

### 6.2 MEDIUM: Update-All Race Condition (Lines 1013-1023)

**Location:** Lines 1013-1023 in `update_all/3`

```elixir
def update_all(%__MODULE__{query: query}, updates, opts \\ []) do
  updates =
    case Keyword.get(opts, :updated_by) do
      nil -> updates
      user_id -> Keyword.update(updates, :set, [], &(&1 ++ [updated_by_urm_id: user_id]))
    end

  {count, _} = Repo.update_all(query, updates)
  {:ok, count}
end
```

**Issues:**
1. No `updated_at` timestamp is automatically set (unlike `update/3` which uses changesets)
2. Users can have stale data if they fetched before the bulk update
3. No concurrency control

**Scenario:**
```
User fetches Product v1: {price: 100, updated_at: 2024-01-01}
Concurrent: update_all sets price = 50, but no updated_at change
User's v1 is now stale, no timestamp indicates change
```

**Better approach:** Auto-add `updated_at: DateTime.utc_now()` to bulk updates

**Impact:** MEDIUM - Stale data in concurrent scenarios

---

### 6.3 MEDIUM: Delete-All Race Condition (Lines 1064-1085)

**Location:** Lines 1064-1085 in `delete_all/2`

```elixir
def delete_all(%__MODULE__{query: query}, opts \\ []) do
  if Keyword.get(opts, :hard, false) do
    {count, _} = Repo.delete_all(query)
    {:ok, count}
  else
    now = DateTime.utc_now()  # Called in Elixir, not DB
    deleted_by = Keyword.get(opts, :deleted_by)
    # ...
    {count, _} = Repo.update_all(query, updates)
    {:ok, count}
  end
end
```

**Issues:**
1. Soft delete timestamp from Elixir process, not database
2. If multiple processes call simultaneously, different timestamps set
3. No transaction ensuring atomicity
4. Query could match different records between check and update

**Concurrent scenario:**
```
Process A: delete_all(status: "draft"), sets deleted_at = T1 for 5 records
Process B: delete_all(status: "draft"), sets deleted_at = T2 for 6 records (includes one from A)
Result: Inconsistent delete timestamps, possible audit trail corruption
```

**Impact:** MEDIUM-HIGH - Concurrent soft delete corruption

---

## 7. TYPE MISMATCHES AND INVALID PATTERN MATCHES

### 7.1 CRITICAL: `build_preload_query` Returns Invalid Ecto Form (Lines 1276-1334)

**Location:** Lines 1276-1334

**Already detailed in Section 1.1**

```elixir
defp build_preload_query(assoc, opts) do
  fn ->
    import Ecto.Query
    query = from(a in assoc)  # ERROR: assoc is atom, needs schema module
    # ... rest of query building ...
  end
end
```

**Type mismatch:**
- Expected: `from(a in SomeSchema)`
- Actual: `from(a in :some_assoc)`  (atom)
- Result: Compile-time error in Ecto

**Impact:** CRITICAL - Any conditional preload usage fails

---

### 7.2 HIGH: `apply_filter` Unknown Operation Handling (Lines 1377-1378)

**Location:** Lines 1357-1378

```elixir
case op do
  :eq -> apply_eq(...)
  :neq -> apply_neq(...)
  # ... other cases ...
  _ -> raise "Unknown operation: #{op}"
end
```

**Issues:**
1. Error happens at query execution time, not definition time
2. Typos in operation names aren't caught early
3. No type checking that `op` is valid atom

**Example:**
```elixir
Query.where(query, {:price, :gt, 100})    # Works
Query.where(query, {:price, :gtt, 100})   # Typo! Raises error at Repo.all time
```

**Better approach:** Compile-time validation of operations

**Impact:** MEDIUM - Late error detection

---

### 7.3 MEDIUM: `select/2` Type Mismatch with Non-Atom Values (Lines 720-722)

**Location:** Lines 705-726

```elixir
select_expr =
  Enum.reduce(field_map, %{}, fn {key, field}, acc when is_atom(field) ->
    Map.put(acc, key, dynamic([s], field(s, ^field)))
  end)
```

**Type mismatch:**
- Guard `when is_atom(field)` filters out valid selections
- Non-atom values like `fragment/1`, `field/2` expressions silently dropped
- Enum.reduce doesn't include accumulator updater for non-atoms, so they're lost

**Example:**
```elixir
Query.select(query, %{
  id: :id,
  price: :price,
  total: fragment("price * quantity")  # Type: tuple (fragment result)
})
# Result: Only {id: id, price: price} selected, total is lost!
```

**Impact:** MEDIUM - Silent loss of calculated fields

---

### 7.4 MEDIUM: `apply_trim` Type Inconsistency (Lines 1414-1444)

**Location:** Lines 1414-1444

```elixir
defp apply_trim(value, op, opts) do
  trim_enabled = Keyword.get(opts, :trim, true)

  if trim_enabled do
    case op do
      op when op in [:in, :not_in] and is_list(value) ->
        Enum.map(value, fn
          v when is_binary(v) -> String.trim(v)
          v -> v  # Non-string values passed through
        end)
      # ...
      _ ->
        if is_binary(value), do: String.trim(value), else: value
    end
  else
    value
  end
end
```

**Issues:**
1. Assumes binary (string) values in lists for `:in` operations
2. Non-binary values mixed in `:in` list not validated
3. Mixed type lists could cause unexpected SQL behavior

**Example:**
```elixir
Query.where(query, {:id, :in, [1, "2", :invalid]})  # Mixed types, no error
```

**Impact:** LOW - Permissive but could mask data errors

---

### 7.5 MEDIUM: `apply_between` Tuple Destructuring (Lines 1653-1661)

**Location:** Lines 1653-1661

```elixir
defp apply_between(query, 0, field, {min, max}, _opts) do
  from(q in query, where: field(q, ^field) >= ^min and field(q, ^field) <= ^max)
end
```

**Type mismatch:**
- Function requires `{min, max}` tuple in pattern match
- No guard to validate 2-tuple structure
- Passing wrong format raises FunctionClauseError with cryptic message

**Example:**
```elixir
Query.where(query, {:price, :between, [10, 100]})  # List not tuple
# Error: no function clause matches {:price, :between, [10, 100]}
```

**Better approach:**
```elixir
def apply_between(query, binding, field, {min, max}, _opts) when is_tuple({min, max}) do
  # ...
end
```

**Impact:** MEDIUM - Poor error messages

---

### 7.6 LOW: `having` Aggregate Assumption (Lines 605-628)

**Location:** Lines 605-628

```elixir
def having(builder, conditions) when is_list(conditions) do
  query =
    Enum.reduce(conditions, builder.query, fn {aggregate, {op, value}}, q ->
      case aggregate do
        :count -> ...
        _ -> q  # Silently ignored
      end
    end)
```

**Issues:**
1. Only `:count` aggregate is supported
2. Other aggregates (`:sum`, `:avg`, `:max`) silently ignored
3. Error message could be clearer

**Example:**
```elixir
Query.having(query, [sum: {:gt, 1000}])  # Silently ignored!
```

**Impact:** LOW - Limited feature, but design could be clearer

---

## SUMMARY TABLE

| Category | Severity | Count | Key Issues |
|----------|----------|-------|-----------|
| Runtime Errors | CRITICAL | 3 | build_preload_query, apply_jsonb_has_key, empty list IN |
| SQL Injection | MEDIUM | 1 | Fragment operator syntax |
| Error Handling | HIGH | 4 | Missing validation throughout |
| Nil Pointers | HIGH | 2 | Through field lookup, pattern match |
| Infinite Loops | MEDIUM | 1 | Nested preload recursion |
| Race Conditions | CRITICAL | 2 | Soft delete, bulk update timing |
| Type Mismatches | HIGH | 3 | Preload from/2, select guards |

---

## RECOMMENDATIONS

1. **URGENT (Release-blocking):**
   - Fix `build_preload_query` - either redesign or disable conditional preloads
   - Fix JSONB operator syntax in fragments
   - Add validation for empty lists in `:in` operations
   - Add association existence validation in `join/3`

2. **HIGH PRIORITY (Next sprint):**
   - Implement database-side timestamps for soft deletes
   - Add optimistic locking to concurrent operations
   - Improve error messages with context
   - Fix `include_deleted` to preserve existing filters

3. **MEDIUM PRIORITY:**
   - Validate pattern match requirements (tuples, lists, etc.)
   - Add early validation for field/operation existence
   - Handle edge cases in type conversions
   - Improve select/2 to support non-atom expressions

4. **TESTING GAPS:**
   - Add tests for concurrent delete/update scenarios
   - Add tests for malformed filter tuples
   - Add tests for empty list handling
   - Add tests for invalid association joins

