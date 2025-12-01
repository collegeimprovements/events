# Events.Types.Diff

Functional diff and patch operations for nested data structures.

## Overview

`Diff` provides tools for comparing, patching, and merging nested maps and lists. It's designed for:

- **Change tracking** - Know exactly what changed between two versions
- **Audit logging** - Record precise field-level changes
- **Undo/Redo** - Reverse diffs to restore previous state
- **Concurrent editing** - Three-way merge with conflict detection
- **Data synchronization** - Generate and apply patches

## Quick Start

```elixir
alias Events.Types.Diff

old = %{name: "Alice", age: 30, tags: ["a", "b"]}
new = %{name: "Alice", age: 31, tags: ["a", "c"]}

# Create a diff
diff = Diff.diff(old, new)
#=> %{age: {:changed, 30, 31}, tags: {:list_diff, [...]}}

# Apply the diff
Diff.patch(old, diff)
#=> %{name: "Alice", age: 31, tags: ["a", "c"]}

# Undo the change
Diff.patch(new, Diff.reverse(diff))
#=> %{name: "Alice", age: 30, tags: ["a", "b"]}
```

## Diff Format

The diff uses tagged tuples to describe changes:

| Tag | Meaning | Example |
|-----|---------|---------|
| `{:added, value}` | Key was added | `{:added, "new@email.com"}` |
| `{:removed, value}` | Key was removed | `{:removed, "old_field"}` |
| `{:changed, old, new}` | Value changed | `{:changed, 30, 31}` |
| `{:nested, diff}` | Nested map changes | `{:nested, %{city: {:changed, "NYC", "LA"}}}` |
| `{:list_diff, ops}` | List operations | `{:list_diff, [{:keep, 1}, {:add, 2}]}` |

### List Operations

| Operation | Meaning |
|-----------|---------|
| `{:keep, value}` | Element unchanged |
| `{:add, value}` | Element added |
| `{:remove, value}` | Element removed |
| `{:change, old, new}` | Element changed |

## Core Functions

### Diffing

```elixir
# Basic diff
Diff.diff(%{a: 1}, %{a: 2})
#=> %{a: {:changed, 1, 2}}

# Nested diff
Diff.diff(
  %{user: %{name: "Alice", age: 30}},
  %{user: %{name: "Alice", age: 31}}
)
#=> %{user: {:nested, %{age: {:changed, 30, 31}}}}

# List diff
Diff.diff([1, 2, 3], [1, 3, 4])
#=> {:list_diff, [{:keep, 1}, {:remove, 2}, {:keep, 3}, {:add, 4}]}

# List diff with key function (for maps/structs in lists)
Diff.diff_list(
  [%{id: 1, name: "a"}, %{id: 2, name: "b"}],
  [%{id: 1, name: "A"}, %{id: 3, name: "c"}],
  by: & &1.id
)
```

### Patching

```elixir
# Apply a diff
diff = %{name: {:changed, "Alice", "Bob"}, age: {:added, 25}}
Diff.patch(%{name: "Alice"}, diff)
#=> %{name: "Bob", age: 25}

# Safe patch with Result
Diff.apply_patch(data, diff)
#=> {:ok, patched_data} | {:error, :patch_failed}
```

### Reversing (Undo)

```elixir
old = %{count: 1}
new = %{count: 5}

diff = Diff.diff(old, new)
#=> %{count: {:changed, 1, 5}}

reverse = Diff.reverse(diff)
#=> %{count: {:changed, 5, 1}}

# Roundtrip
old |> Diff.patch(diff) |> Diff.patch(reverse)
#=> %{count: 1}  # Back to original
```

## Three-Way Merge

Merge concurrent changes from two sources against a common base.

### Non-Conflicting Changes

```elixir
base  = %{x: 1, y: 2, z: 3}
left  = %{x: 10, y: 2, z: 3}  # Changed x
right = %{x: 1, y: 20, z: 3}  # Changed y

Diff.merge3(base, left, right)
#=> {:ok, %{x: 10, y: 20, z: 3}}  # Both changes merged
```

### Conflict Detection

```elixir
base  = %{x: 1}
left  = %{x: 10}  # Changed x to 10
right = %{x: 20}  # Changed x to 20

Diff.merge3(base, left, right)
#=> {:conflict, %{x: {:conflict, 10, 20}}, [{[:x], 10, 20}]}
```

### Conflict Resolution Strategies

```elixir
# Left wins
Diff.merge3(base, left, right, :left_wins)
#=> {:ok, %{x: 10}}

# Right wins
Diff.merge3(base, left, right, :right_wins)
#=> {:ok, %{x: 20}}

# Custom resolver
resolver = fn _key, left_val, right_val ->
  {:ok, max(left_val, right_val)}  # Take larger value
end

Diff.merge3(base, left, right, resolver)
#=> {:ok, %{x: 20}}

# Resolver can also return :conflict
resolver = fn key, left, right ->
  if key == :critical_field do
    :conflict  # Force manual resolution
  else
    {:ok, right}
  end
end
```

## Utility Functions

### Check if Empty

```elixir
Diff.empty?(nil)                                    #=> true
Diff.empty?(%{})                                    #=> true
Diff.empty?(%{a: {:changed, 1, 2}})                #=> false
Diff.empty?({:list_diff, [{:keep, 1}]})            #=> true  (only keeps)
Diff.empty?({:list_diff, [{:keep, 1}, {:add, 2}]}) #=> false
```

### Get Changed Paths

```elixir
diff = %{
  name: {:changed, "a", "b"},
  settings: {:nested, %{
    theme: {:changed, "light", "dark"},
    notifications: {:nested, %{
      email: {:added, true}
    }}
  }}
}

Diff.changed_paths(diff)
#=> [[:name], [:settings, :theme], [:settings, :notifications, :email]]
```

### Summarize Changes

```elixir
diff = %{
  a: {:added, 1},
  b: {:removed, 2},
  c: {:changed, 3, 4},
  d: {:nested, %{e: {:changed, 5, 6}}}
}

Diff.summarize(diff)
#=> %{added: 1, removed: 1, changed: 2, nested: 1}
```

### Filter and Reject

```elixir
diff = %{a: {:changed, 1, 2}, b: {:added, 3}, c: {:removed, 4}}

# Keep only specific keys
Diff.filter(diff, [:a, :b])
#=> %{a: {:changed, 1, 2}, b: {:added, 3}}

# Exclude specific keys
Diff.reject(diff, [:c])
#=> %{a: {:changed, 1, 2}, b: {:added, 3}}
```

## Real-World Examples

### Audit Logging

```elixir
defmodule AuditLog do
  alias Events.Types.Diff

  def log_change(entity_type, entity_id, old_data, new_data, actor_id) do
    diff = Diff.diff(old_data, new_data)

    %{
      entity_type: entity_type,
      entity_id: entity_id,
      actor_id: actor_id,
      timestamp: DateTime.utc_now(),
      action: determine_action(diff),
      changed_fields: Diff.changed_paths(diff),
      summary: Diff.summarize(diff),
      diff: diff,  # Store for rollback capability
      previous_values: extract_old_values(diff)
    }
  end

  defp determine_action(nil), do: :unchanged
  defp determine_action(diff) do
    summary = Diff.summarize(diff)
    cond do
      summary.removed > 0 and summary.added == 0 -> :delete
      summary.added > 0 and summary.removed == 0 -> :create
      true -> :update
    end
  end

  defp extract_old_values(diff) when is_map(diff) do
    Map.new(diff, fn
      {key, {:changed, old, _new}} -> {key, old}
      {key, {:removed, old}} -> {key, old}
      {key, {:nested, nested}} -> {key, extract_old_values(nested)}
      {key, _} -> {key, nil}
    end)
  end
end

# Usage
old_user = %{name: "Alice", email: "alice@old.com", role: "user"}
new_user = %{name: "Alice", email: "alice@new.com", role: "admin"}

AuditLog.log_change(:user, "user_123", old_user, new_user, "admin_456")
#=> %{
#     entity_type: :user,
#     entity_id: "user_123",
#     actor_id: "admin_456",
#     action: :update,
#     changed_fields: [[:email], [:role]],
#     summary: %{added: 0, removed: 0, changed: 2, nested: 0},
#     ...
#   }
```

### Undo/Redo System

```elixir
defmodule UndoStack do
  alias Events.Types.Diff

  defstruct current: nil, undo_stack: [], redo_stack: []

  def new(initial_state) do
    %__MODULE__{current: initial_state}
  end

  def update(%__MODULE__{} = stack, new_state) do
    diff = Diff.diff(stack.current, new_state)

    if Diff.empty?(diff) do
      stack
    else
      %{stack |
        current: new_state,
        undo_stack: [diff | stack.undo_stack],
        redo_stack: []  # Clear redo on new change
      }
    end
  end

  def undo(%__MODULE__{undo_stack: []} = stack), do: {:error, :nothing_to_undo, stack}
  def undo(%__MODULE__{undo_stack: [diff | rest]} = stack) do
    reverse_diff = Diff.reverse(diff)
    new_state = Diff.patch(stack.current, reverse_diff)

    new_stack = %{stack |
      current: new_state,
      undo_stack: rest,
      redo_stack: [diff | stack.redo_stack]
    }

    {:ok, new_stack}
  end

  def redo(%__MODULE__{redo_stack: []} = stack), do: {:error, :nothing_to_redo, stack}
  def redo(%__MODULE__{redo_stack: [diff | rest]} = stack) do
    new_state = Diff.patch(stack.current, diff)

    new_stack = %{stack |
      current: new_state,
      undo_stack: [diff | stack.undo_stack],
      redo_stack: rest
    }

    {:ok, new_stack}
  end

  def can_undo?(%__MODULE__{undo_stack: stack}), do: stack != []
  def can_redo?(%__MODULE__{redo_stack: stack}), do: stack != []
end

# Usage
stack = UndoStack.new(%{text: "Hello"})
  |> UndoStack.update(%{text: "Hello World"})
  |> UndoStack.update(%{text: "Hello World!"})

stack.current  #=> %{text: "Hello World!"}

{:ok, stack} = UndoStack.undo(stack)
stack.current  #=> %{text: "Hello World"}

{:ok, stack} = UndoStack.undo(stack)
stack.current  #=> %{text: "Hello"}

{:ok, stack} = UndoStack.redo(stack)
stack.current  #=> %{text: "Hello World"}
```

### Concurrent Edit Merging

```elixir
defmodule DocumentEditor do
  alias Events.Types.Diff

  def merge_edits(base_doc, user_edits) when is_list(user_edits) do
    Enum.reduce(user_edits, {:ok, base_doc, []}, fn
      {user_id, edited_doc}, {:ok, current, conflicts} ->
        case Diff.merge3(base_doc, current, edited_doc) do
          {:ok, merged} ->
            {:ok, merged, conflicts}

          {:conflict, merged, new_conflicts} ->
            tagged_conflicts = Enum.map(new_conflicts, fn {path, left, right} ->
              %{path: path, current: left, incoming: right, user: user_id}
            end)
            {:ok, merged, conflicts ++ tagged_conflicts}
        end

      _, {:error, _} = error ->
        error
    end)
  end

  def resolve_conflicts(doc, conflicts, strategy) do
    Enum.reduce(conflicts, doc, fn conflict, acc ->
      value = case strategy do
        :keep_current -> conflict.current
        :accept_incoming -> conflict.incoming
        {:custom, fun} -> fun.(conflict)
      end

      put_in_path(acc, conflict.path, value)
    end)
  end

  defp put_in_path(data, [key], value), do: Map.put(data, key, value)
  defp put_in_path(data, [key | rest], value) do
    Map.update(data, key, %{}, &put_in_path(&1, rest, value))
  end
end

# Usage
base = %{title: "Draft", content: "...", metadata: %{version: 1}}

user_edits = [
  {"user_1", %{title: "Final", content: "...", metadata: %{version: 1}}},
  {"user_2", %{title: "Draft", content: "Updated", metadata: %{version: 2}}},
  {"user_3", %{title: "Complete", content: "Updated", metadata: %{version: 2}}}
]

case DocumentEditor.merge_edits(base, user_edits) do
  {:ok, merged, []} ->
    IO.puts("Clean merge!")
    merged

  {:ok, merged, conflicts} ->
    IO.puts("Merged with #{length(conflicts)} conflicts")
    DocumentEditor.resolve_conflicts(merged, conflicts, :accept_incoming)
end
```

### Configuration Drift Detection

```elixir
defmodule ConfigDrift do
  alias Events.Types.Diff

  def detect_drift(expected_config, actual_config) do
    diff = Diff.diff(expected_config, actual_config)

    if Diff.empty?(diff) do
      :in_sync
    else
      {:drift_detected, analyze_drift(diff)}
    end
  end

  defp analyze_drift(diff) do
    paths = Diff.changed_paths(diff)
    summary = Diff.summarize(diff)

    %{
      changed_paths: paths,
      total_changes: summary.added + summary.removed + summary.changed,
      severity: calculate_severity(paths),
      details: extract_details(diff, paths)
    }
  end

  defp calculate_severity(paths) do
    critical_paths = [[:database], [:security], [:auth]]

    if Enum.any?(paths, fn path ->
      Enum.any?(critical_paths, &List.starts_with?(path, &1))
    end) do
      :critical
    else
      :warning
    end
  end

  defp extract_details(diff, paths) do
    Enum.map(paths, fn path ->
      change = get_in_diff(diff, path)
      %{path: Enum.join(path, "."), change: format_change(change)}
    end)
  end

  defp get_in_diff(diff, [key]) do
    Map.get(diff, key)
  end
  defp get_in_diff(diff, [key | rest]) do
    case Map.get(diff, key) do
      {:nested, nested} -> get_in_diff(nested, rest)
      other -> other
    end
  end

  defp format_change({:changed, old, new}), do: "#{inspect(old)} → #{inspect(new)}"
  defp format_change({:added, val}), do: "added: #{inspect(val)}"
  defp format_change({:removed, val}), do: "removed: #{inspect(val)}"
  defp format_change(other), do: inspect(other)
end

# Usage
expected = %{
  database: %{pool_size: 10, timeout: 5000},
  cache: %{enabled: true, ttl: 3600},
  features: %{new_ui: false}
}

actual = %{
  database: %{pool_size: 5, timeout: 5000},  # Drifted!
  cache: %{enabled: true, ttl: 3600},
  features: %{new_ui: true}  # Also drifted
}

ConfigDrift.detect_drift(expected, actual)
#=> {:drift_detected, %{
#     changed_paths: [[:database, :pool_size], [:features, :new_ui]],
#     total_changes: 2,
#     severity: :critical,
#     details: [
#       %{path: "database.pool_size", change: "10 → 5"},
#       %{path: "features.new_ui", change: "false → true"}
#     ]
#   }}
```

## Function Reference

| Function | Description |
|----------|-------------|
| `diff/2` | Compute difference between two values |
| `diff_list/3` | Compute list diff with options |
| `patch/2` | Apply a diff to a value |
| `apply_patch/2` | Patch with Result return type |
| `reverse/1` | Create inverse diff for undo |
| `merge3/4` | Three-way merge with conflict handling |
| `merge_diffs/5` | Merge two diffs against base |
| `empty?/1` | Check if diff has no changes |
| `changed_paths/1` | Get list of changed key paths |
| `summarize/1` | Count changes by type |
| `filter/2` | Keep only specified keys |
| `reject/2` | Exclude specified keys |
| `from_changes/1` | Build diff from change list |

## Comparison with map_diff

| Feature | map_diff | Events.Types.Diff |
|---------|----------|-------------------|
| Basic map diffing | ✅ | ✅ |
| Nested map diffing | ✅ | ✅ |
| Struct name tracking | ✅ | ❌ |
| List diffing (LCS) | ❌ | ✅ |
| Patch application | ❌ | ✅ |
| Reverse/Undo | ❌ | ✅ |
| Three-way merge | ❌ | ✅ |
| Conflict detection | ❌ | ✅ |
| Conflict resolution | ❌ | ✅ |
| Path extraction | ❌ | ✅ |
| Summarization | ❌ | ✅ |
| Filter/Reject | ❌ | ✅ |

Our implementation trades struct name tracking for a richer feature set focused on practical operations like patching, merging, and undo capability.
