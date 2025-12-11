defmodule FnTypes.Diff do
  @moduledoc """
  Functional diff and patch operations for nested data structures.

  Diff provides tools for comparing, patching, and merging nested maps and lists.
  Useful for tracking changes, applying updates, and handling conflicts.

  ## Quick Start

      alias FnTypes.Diff

      old = %{name: "Alice", age: 30, tags: ["a", "b"]}
      new = %{name: "Alice", age: 31, tags: ["a", "c"]}

      # Create a diff
      diff = Diff.diff(old, new)
      #=> %{age: {:changed, 30, 31}, tags: {:changed, ["a", "b"], ["a", "c"]}}

      # Apply the diff
      Diff.patch(old, diff)
      #=> %{name: "Alice", age: 31, tags: ["a", "c"]}

  ## Diff Types

  The diff format uses tagged tuples to describe changes:

  - `{:added, value}` - Key/value was added
  - `{:removed, value}` - Key/value was removed
  - `{:changed, old, new}` - Value changed from old to new
  - `{:nested, diff}` - Nested map with its own diff
  - `{:list_diff, ops}` - List with element-level operations

  ## Merge Operations

      # Three-way merge
      base = %{x: 1, y: 2}
      left = %{x: 1, y: 3}
      right = %{x: 2, y: 2}

      Diff.merge3(base, left, right)
      #=> {:ok, %{x: 2, y: 3}}  # Non-conflicting changes merged

      # With conflicts
      left = %{x: 10}
      right = %{x: 20}

      Diff.merge3(base, left, right)
      #=> {:conflict, %{x: {:conflict, 10, 20}}, conflicts}

  ## List Diffing

      old_list = [1, 2, 3, 4]
      new_list = [1, 3, 4, 5]

      Diff.diff_list(old_list, new_list)
      #=> {:list_diff, [{:keep, 1}, {:remove, 2}, {:keep, 3}, {:keep, 4}, {:add, 5}]}

  ## Conflict Resolution

      # Custom conflict resolver
      Diff.merge3(base, left, right, fn _key, left_val, right_val ->
        {:ok, max(left_val, right_val)}  # Always take the larger value
      end)

      # Built-in strategies
      Diff.merge3(base, left, right, :left_wins)
      Diff.merge3(base, left, right, :right_wins)
      Diff.merge3(base, left, right, :newest_wins)
  """

  alias FnTypes.Result

  # ============================================================================
  # Types
  # ============================================================================

  @type diff_value ::
          {:added, any()}
          | {:removed, any()}
          | {:changed, old :: any(), new :: any()}
          | {:nested, diff()}
          | {:list_diff, [list_op()]}

  @type diff :: %{optional(any()) => diff_value()}

  @type list_op ::
          {:keep, any()}
          | {:add, any()}
          | {:remove, any()}
          | {:change, old :: any(), new :: any()}

  @type conflict :: {:conflict, left :: any(), right :: any()}

  @type merge_result :: {:ok, any()} | {:conflict, any(), [conflict_info()]}

  @type conflict_info :: {path :: [any()], left :: any(), right :: any()}

  @type conflict_resolver ::
          :left_wins
          | :right_wins
          | (key :: any(), left :: any(), right :: any() -> {:ok, any()} | :conflict)

  # ============================================================================
  # Core Diff Operations
  # ============================================================================

  @doc """
  Computes the difference between two values.

  Returns a diff describing how to transform `old` into `new`.

  ## Examples

      Diff.diff(%{a: 1}, %{a: 2})
      #=> %{a: {:changed, 1, 2}}

      Diff.diff(%{a: 1}, %{a: 1, b: 2})
      #=> %{b: {:added, 2}}

      Diff.diff(%{a: 1, b: 2}, %{a: 1})
      #=> %{b: {:removed, 2}}

      Diff.diff(%{x: %{y: 1}}, %{x: %{y: 2}})
      #=> %{x: {:nested, %{y: {:changed, 1, 2}}}}
  """
  @spec diff(any(), any()) :: diff() | nil
  def diff(old, new) when old == new, do: nil

  def diff(old, new) when is_map(old) and is_map(new) do
    diff_maps(old, new)
  end

  def diff(old, new) when is_list(old) and is_list(new) do
    {:list_diff, diff_lists(old, new)}
  end

  def diff(old, new) do
    {:changed, old, new}
  end

  @doc """
  Computes detailed diff for lists.

  ## Options

  - `:by` - Function to extract comparison key from elements
  - `:algorithm` - `:lcs` (longest common subsequence) or `:simple` (index-based)

  ## Examples

      Diff.diff_list([1, 2, 3], [1, 3, 4])
      #=> [{:keep, 1}, {:remove, 2}, {:keep, 3}, {:add, 4}]

      # With key function
      old = [%{id: 1, name: "a"}, %{id: 2, name: "b"}]
      new = [%{id: 1, name: "A"}, %{id: 3, name: "c"}]

      Diff.diff_list(old, new, by: & &1.id)
  """
  @spec diff_list(list(), list(), keyword()) :: [list_op()]
  def diff_list(old, new, opts \\ []) do
    case Keyword.get(opts, :algorithm, :lcs) do
      :lcs -> lcs_diff(old, new, Keyword.get(opts, :by))
      :simple -> simple_diff(old, new)
    end
  end

  # ============================================================================
  # Patch Operations
  # ============================================================================

  @doc """
  Applies a diff to a value, producing the new value.

  ## Examples

      diff = %{age: {:changed, 30, 31}}
      Diff.patch(%{name: "Alice", age: 30}, diff)
      #=> %{name: "Alice", age: 31}

      diff = %{x: {:added, 1}}
      Diff.patch(%{}, diff)
      #=> %{x: 1}
  """
  @spec patch(any(), diff() | nil) :: any()
  def patch(value, nil), do: value
  def patch(value, diff) when is_map(value) and is_map(diff), do: patch_map(value, diff)
  def patch(value, {:list_diff, ops}) when is_list(value), do: patch_list(value, ops)
  def patch(_old, {:changed, _old_val, new_val}), do: new_val
  def patch(value, diff) when map_size(diff) == 0, do: value

  @doc """
  Applies a diff and returns Result.

  ## Examples

      Diff.apply_patch(old, diff)
      #=> {:ok, new_value}

      Diff.apply_patch(old, incompatible_diff)
      #=> {:error, :patch_failed}
  """
  @spec apply_patch(any(), diff() | nil) :: Result.t(any(), atom())
  def apply_patch(value, diff) do
    {:ok, patch(value, diff)}
  rescue
    _ -> {:error, :patch_failed}
  end

  @doc """
  Reverses a diff so it can be used to undo changes.

  ## Examples

      diff = Diff.diff(old, new)
      reverse = Diff.reverse(diff)

      Diff.patch(Diff.patch(old, diff), reverse)
      #=> old  # Back to original
  """
  @spec reverse(diff() | nil) :: diff() | nil
  def reverse(nil), do: nil

  def reverse(diff) when is_map(diff) do
    Map.new(diff, fn {key, change} ->
      {key, reverse_change(change)}
    end)
  end

  def reverse({:list_diff, ops}) do
    {:list_diff, reverse_list_ops(ops)}
  end

  def reverse({:changed, old, new}) do
    {:changed, new, old}
  end

  # ============================================================================
  # Merge Operations
  # ============================================================================

  @doc """
  Three-way merge of two values against a common base.

  ## Examples

      base = %{x: 1, y: 2, z: 3}
      left = %{x: 10, y: 2, z: 3}  # Changed x
      right = %{x: 1, y: 20, z: 3}  # Changed y

      Diff.merge3(base, left, right)
      #=> {:ok, %{x: 10, y: 20, z: 3}}  # Both changes merged

      # With conflict
      left = %{x: 10}
      right = %{x: 20}

      Diff.merge3(base, left, right)
      #=> {:conflict, %{x: {:conflict, 10, 20}}, [{[:x], 10, 20}]}
  """
  @spec merge3(any(), any(), any(), conflict_resolver()) :: merge_result()
  def merge3(base, left, right, resolver \\ :conflict) do
    left_diff = diff(base, left)
    right_diff = diff(base, right)

    merge_diffs(base, left_diff, right_diff, resolver, [])
  end

  @doc """
  Merges two diffs, detecting conflicts.

  ## Examples

      diff1 = %{a: {:changed, 1, 2}}
      diff2 = %{b: {:added, 3}}

      Diff.merge_diffs(base, diff1, diff2)
      #=> {:ok, merged_diff}
  """
  @spec merge_diffs(any(), diff() | nil, diff() | nil, conflict_resolver(), [any()]) ::
          merge_result()
  def merge_diffs(base, nil, nil, _resolver, _path), do: {:ok, base}
  def merge_diffs(base, left_diff, nil, _resolver, _path), do: {:ok, patch(base, left_diff)}
  def merge_diffs(base, nil, right_diff, _resolver, _path), do: {:ok, patch(base, right_diff)}

  def merge_diffs(base, left_diff, right_diff, resolver, path)
      when is_map(left_diff) and is_map(right_diff) do
    all_keys = MapSet.union(MapSet.new(Map.keys(left_diff)), MapSet.new(Map.keys(right_diff)))

    {result, conflicts} =
      Enum.reduce(all_keys, {base, []}, fn key, {acc, conflicts} ->
        left_change = Map.get(left_diff, key)
        right_change = Map.get(right_diff, key)
        key_path = path ++ [key]

        case merge_changes(Map.get(base, key), left_change, right_change, resolver, key_path) do
          {:ok, nil} ->
            # No change for this key
            {acc, conflicts}

          {:ok, new_value} ->
            {Map.put(acc, key, new_value), conflicts}

          {:removed} ->
            {Map.delete(acc, key), conflicts}

          {:conflict, left_val, right_val} ->
            conflict_marker = {:conflict, left_val, right_val}
            {Map.put(acc, key, conflict_marker), [{key_path, left_val, right_val} | conflicts]}
        end
      end)

    if conflicts == [] do
      {:ok, result}
    else
      {:conflict, result, Enum.reverse(conflicts)}
    end
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Checks if a diff has any changes.

  ## Examples

      Diff.empty?(nil)
      #=> true

      Diff.empty?(%{})
      #=> true

      Diff.empty?(%{a: {:changed, 1, 2}})
      #=> false
  """
  @spec empty?(diff() | nil) :: boolean()
  def empty?(nil), do: true
  def empty?(diff) when is_map(diff), do: map_size(diff) == 0
  def empty?({:list_diff, []}), do: true
  def empty?({:list_diff, ops}), do: Enum.all?(ops, &match?({:keep, _}, &1))
  def empty?(_), do: false

  @doc """
  Returns the set of keys/paths that have changes.

  ## Examples

      diff = %{a: {:changed, 1, 2}, b: {:nested, %{c: {:added, 3}}}}
      Diff.changed_paths(diff)
      #=> [[:a], [:b, :c]]
  """
  @spec changed_paths(diff() | nil) :: [[any()]]
  def changed_paths(nil), do: []

  def changed_paths(diff) when is_map(diff) do
    diff
    |> Enum.flat_map(fn {key, change} ->
      case change do
        {:nested, nested} ->
          nested
          |> changed_paths()
          |> Enum.map(&[key | &1])

        _ ->
          [[key]]
      end
    end)
  end

  def changed_paths({:list_diff, ops}) do
    ops
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{:keep, _}, _idx} -> []
      {_, idx} -> [[idx]]
    end)
  end

  @doc """
  Summarizes a diff for human-readable output.

  ## Examples

      Diff.summarize(diff)
      #=> %{added: 2, removed: 1, changed: 3}
  """
  @spec summarize(diff() | nil) :: map()
  def summarize(nil), do: %{added: 0, removed: 0, changed: 0, nested: 0}

  def summarize(diff) when is_map(diff) do
    Enum.reduce(diff, %{added: 0, removed: 0, changed: 0, nested: 0}, fn {_key, change}, acc ->
      case change do
        {:added, _} -> Map.update!(acc, :added, &(&1 + 1))
        {:removed, _} -> Map.update!(acc, :removed, &(&1 + 1))
        {:changed, _, _} -> Map.update!(acc, :changed, &(&1 + 1))
        {:nested, nested} -> merge_summaries(acc, summarize(nested))
        {:list_diff, _} -> Map.update!(acc, :changed, &(&1 + 1))
      end
    end)
  end

  @doc """
  Filters a diff to only include specified keys/paths.

  ## Examples

      diff = %{a: {:changed, 1, 2}, b: {:added, 3}, c: {:removed, 4}}
      Diff.filter(diff, [:a, :b])
      #=> %{a: {:changed, 1, 2}, b: {:added, 3}}
  """
  @spec filter(diff() | nil, [any()]) :: diff() | nil
  def filter(nil, _keys), do: nil

  def filter(diff, keys) when is_map(diff) do
    Map.take(diff, keys)
  end

  @doc """
  Excludes specified keys/paths from a diff.

  ## Examples

      diff = %{a: {:changed, 1, 2}, b: {:added, 3}, c: {:removed, 4}}
      Diff.reject(diff, [:c])
      #=> %{a: {:changed, 1, 2}, b: {:added, 3}}
  """
  @spec reject(diff() | nil, [any()]) :: diff() | nil
  def reject(nil, _keys), do: nil

  def reject(diff, keys) when is_map(diff) do
    Map.drop(diff, keys)
  end

  @doc """
  Creates a diff from a list of changes.

  ## Examples

      Diff.from_changes([
        {:set, :name, "Alice"},
        {:delete, :temp_field},
        {:update, :count, fn x -> x + 1 end}
      ])
  """
  @spec from_changes([{:set, any(), any()} | {:delete, any()} | {:update, any(), function()}]) ::
          diff()
  def from_changes(changes) do
    Enum.reduce(changes, %{}, fn
      {:set, key, value}, acc ->
        Map.put(acc, key, {:added, value})

      {:delete, key}, acc ->
        Map.put(acc, key, {:removed, nil})

      {:update, key, _fun}, acc ->
        # Update requires the current value, which we don't have here
        # This is a marker that will need to be resolved during patch
        Map.put(acc, key, {:update, :pending})
    end)
  end

  # ============================================================================
  # Private - Map Diffing
  # ============================================================================

  defp diff_maps(old, new) do
    old_keys = MapSet.new(Map.keys(old))
    new_keys = MapSet.new(Map.keys(new))

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    diff =
      Enum.reduce(added_keys, %{}, fn key, acc ->
        Map.put(acc, key, {:added, Map.get(new, key)})
      end)

    diff =
      Enum.reduce(removed_keys, diff, fn key, acc ->
        Map.put(acc, key, {:removed, Map.get(old, key)})
      end)

    Enum.reduce(common_keys, diff, fn key, acc ->
      old_val = Map.get(old, key)
      new_val = Map.get(new, key)

      case diff(old_val, new_val) do
        nil ->
          acc

        nested when is_map(nested) and not is_struct(nested) ->
          Map.put(acc, key, {:nested, nested})

        {:list_diff, _} = list_diff ->
          Map.put(acc, key, list_diff)

        change ->
          Map.put(acc, key, change)
      end
    end)
  end

  # ============================================================================
  # Private - List Diffing
  # ============================================================================

  defp diff_lists(old, new) do
    lcs_diff(old, new, nil)
  end

  # Simple LCS-based diff
  defp lcs_diff(old, new, key_fn) do
    old_items = if key_fn, do: Enum.map(old, key_fn), else: old
    new_items = if key_fn, do: Enum.map(new, key_fn), else: new

    lcs = compute_lcs(old_items, new_items)

    build_list_ops(old, new, lcs, key_fn)
  end

  defp compute_lcs([], _new), do: []
  defp compute_lcs(_old, []), do: []

  defp compute_lcs([h | old_rest], [h | new_rest]) do
    [h | compute_lcs(old_rest, new_rest)]
  end

  defp compute_lcs([_oh | old_rest] = old, [_nh | new_rest] = new) do
    lcs1 = compute_lcs(old_rest, new)
    lcs2 = compute_lcs(old, new_rest)

    if length(lcs1) >= length(lcs2), do: lcs1, else: lcs2
  end

  defp build_list_ops(old, new, lcs, key_fn) do
    do_build_list_ops(old, new, lcs, key_fn, [])
    |> Enum.reverse()
  end

  defp do_build_list_ops([], [], _lcs, _key_fn, acc), do: acc

  defp do_build_list_ops([], [h | rest], lcs, key_fn, acc) do
    do_build_list_ops([], rest, lcs, key_fn, [{:add, h} | acc])
  end

  defp do_build_list_ops([h | rest], [], lcs, key_fn, acc) do
    do_build_list_ops(rest, [], lcs, key_fn, [{:remove, h} | acc])
  end

  defp do_build_list_ops([oh | old_rest], [nh | new_rest], [lcs_h | lcs_rest], key_fn, acc) do
    old_key = if key_fn, do: key_fn.(oh), else: oh
    new_key = if key_fn, do: key_fn.(nh), else: nh

    cond do
      old_key == lcs_h and new_key == lcs_h ->
        # Both match LCS - keep
        op = if oh == nh, do: {:keep, oh}, else: {:change, oh, nh}
        do_build_list_ops(old_rest, new_rest, lcs_rest, key_fn, [op | acc])

      old_key == lcs_h ->
        # Old matches LCS, new doesn't - add new
        do_build_list_ops([oh | old_rest], new_rest, [lcs_h | lcs_rest], key_fn, [{:add, nh} | acc])

      new_key == lcs_h ->
        # New matches LCS, old doesn't - remove old
        do_build_list_ops(old_rest, [nh | new_rest], [lcs_h | lcs_rest], key_fn, [
          {:remove, oh} | acc
        ])

      true ->
        # Neither matches - remove old, add new
        do_build_list_ops(old_rest, new_rest, [lcs_h | lcs_rest], key_fn, [
          {:add, nh},
          {:remove, oh} | acc
        ])
    end
  end

  defp do_build_list_ops([oh | old_rest], [nh | new_rest], [], key_fn, acc) do
    # No more LCS - change
    do_build_list_ops(old_rest, new_rest, [], key_fn, [{:change, oh, nh} | acc])
  end

  defp simple_diff(old, new) do
    max_len = max(length(old), length(new))

    0..(max_len - 1)
    |> Enum.map(fn i ->
      old_val = Enum.at(old, i)
      new_val = Enum.at(new, i)

      cond do
        old_val == nil -> {:add, new_val}
        new_val == nil -> {:remove, old_val}
        old_val == new_val -> {:keep, old_val}
        true -> {:change, old_val, new_val}
      end
    end)
  end

  # ============================================================================
  # Private - Patching
  # ============================================================================

  defp patch_map(map, diff) do
    Enum.reduce(diff, map, fn {key, change}, acc ->
      case change do
        {:added, value} ->
          Map.put(acc, key, value)

        {:removed, _value} ->
          Map.delete(acc, key)

        {:changed, _old, new} ->
          Map.put(acc, key, new)

        {:nested, nested_diff} ->
          Map.update(acc, key, %{}, &patch(&1, nested_diff))

        {:list_diff, ops} ->
          Map.update(acc, key, [], &patch_list(&1, ops))
      end
    end)
  end

  defp patch_list(_list, ops) do
    # Rebuild list from operations
    Enum.flat_map(ops, fn
      {:keep, val} -> [val]
      {:add, val} -> [val]
      {:remove, _val} -> []
      {:change, _old, new} -> [new]
    end)
  end

  # ============================================================================
  # Private - Reversing
  # ============================================================================

  defp reverse_change({:added, value}), do: {:removed, value}
  defp reverse_change({:removed, value}), do: {:added, value}
  defp reverse_change({:changed, old, new}), do: {:changed, new, old}
  defp reverse_change({:nested, nested}), do: {:nested, reverse(nested)}
  defp reverse_change({:list_diff, ops}), do: {:list_diff, reverse_list_ops(ops)}

  defp reverse_list_ops(ops) do
    Enum.map(ops, fn
      {:keep, val} -> {:keep, val}
      {:add, val} -> {:remove, val}
      {:remove, val} -> {:add, val}
      {:change, old, new} -> {:change, new, old}
    end)
  end

  # ============================================================================
  # Private - Merging
  # ============================================================================

  defp merge_changes(_base_val, nil, nil, _resolver, _path), do: {:ok, nil}
  defp merge_changes(base_val, nil, right, _resolver, _path), do: apply_change(base_val, right)
  defp merge_changes(base_val, left, nil, _resolver, _path), do: apply_change(base_val, left)

  defp merge_changes(base_val, left, right, _resolver, _path) when left == right do
    # Same change on both sides - no conflict
    apply_change(base_val, left)
  end

  defp merge_changes(base_val, {:nested, left_nested}, {:nested, right_nested}, resolver, path) do
    # Both nested - recursive merge
    case merge_diffs(base_val || %{}, left_nested, right_nested, resolver, path) do
      {:ok, merged} -> {:ok, merged}
      # Propagate conflicts in merged value
      {:conflict, merged, _conflicts} -> {:ok, merged}
    end
  end

  defp merge_changes(_base_val, left_change, right_change, resolver, path) do
    left_val = extract_new_value(left_change)
    right_val = extract_new_value(right_change)

    resolve_conflict(path, left_val, right_val, resolver)
  end

  defp apply_change(_base, {:added, value}), do: {:ok, value}
  defp apply_change(_base, {:removed, _value}), do: {:removed}
  defp apply_change(_base, {:changed, _old, new}), do: {:ok, new}
  defp apply_change(base, {:nested, nested}), do: {:ok, patch(base || %{}, nested)}
  defp apply_change(base, {:list_diff, ops}), do: {:ok, patch_list(base || [], ops)}

  defp extract_new_value({:added, val}), do: val
  defp extract_new_value({:removed, _}), do: nil
  defp extract_new_value({:changed, _, new}), do: new
  defp extract_new_value({:nested, _} = nested), do: nested
  defp extract_new_value({:list_diff, _} = list_diff), do: list_diff

  defp resolve_conflict(_path, left, right, :conflict) do
    {:conflict, left, right}
  end

  defp resolve_conflict(_path, left, _right, :left_wins) do
    {:ok, left}
  end

  defp resolve_conflict(_path, _left, right, :right_wins) do
    {:ok, right}
  end

  defp resolve_conflict(path, left, right, resolver) when is_function(resolver, 3) do
    key = List.last(path)

    case resolver.(key, left, right) do
      {:ok, value} -> {:ok, value}
      :conflict -> {:conflict, left, right}
    end
  end

  # ============================================================================
  # Private - Utilities
  # ============================================================================

  defp merge_summaries(s1, s2) do
    %{
      added: s1.added + s2.added,
      removed: s1.removed + s2.removed,
      changed: s1.changed + s2.changed,
      nested: s1.nested + s2.nested + 1
    }
  end
end
