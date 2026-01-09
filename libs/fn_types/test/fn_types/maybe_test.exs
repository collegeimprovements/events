defmodule FnTypes.MaybeTest do
  @moduledoc """
  Tests for FnTypes.Maybe - Optional value handling.

  Maybe represents a value that may or may not exist, without using nil.
  Unlike Result which represents success/failure, Maybe represents presence/absence.

  ## When to Use Maybe vs Result

  - Use Maybe when absence is normal and expected (optional config, optional field)
  - Use Result when absence indicates a problem (fetch that should find something)

  ## Pattern: Safe Optional Value Access

  Maybe enables safe chaining of operations on optional values:

      user
      |> Maybe.get(:preferences)
      |> Maybe.and_then(&Maybe.get(&1, :theme))
      |> Maybe.unwrap_or("light")

  If any step produces none, subsequent steps are skipped.
  """

  use ExUnit.Case, async: true

  alias FnTypes.Maybe

  # ============================================================================
  # USE CASE: User Preferences with Optional Settings
  # ============================================================================

  describe "Use Case: User preferences with optional settings" do
    # User preferences may have missing values - this is normal, not an error.
    # Maybe makes optional values explicit while providing safe defaults.

    defp get_user_preferences(user_id) do
      preferences = %{
        1 => %{theme: "dark", notifications: true, language: nil},
        2 => %{theme: nil, notifications: false}
      }

      Map.get(preferences, user_id)
    end

    test "safely accessing optional preference" do
      prefs = get_user_preferences(1)

      theme = Maybe.from_nilable(prefs[:theme])
      assert theme == {:some, "dark"}

      # Language is explicitly nil
      language = Maybe.from_nilable(prefs[:language])
      assert language == :none
    end

    test "providing fallback for missing preference" do
      prefs = get_user_preferences(2)

      # User 2 has nil theme - use default
      theme =
        prefs[:theme]
        |> Maybe.from_nilable()
        |> Maybe.unwrap_or("light")

      assert theme == "light"
    end

    test "handling completely missing user" do
      prefs = get_user_preferences(999)

      result =
        prefs
        |> Maybe.from_nilable()
        |> Maybe.and_then(fn p -> Maybe.from_nilable(p[:theme]) end)
        |> Maybe.unwrap_or("default")

      assert result == "default"
    end
  end

  # ============================================================================
  # USE CASE: Optional Form Fields
  # ============================================================================

  describe "Use Case: Optional form fields" do
    # Form submissions often have optional fields. Maybe helps validate
    # and process only the fields that were provided.

    defp parse_optional_age(input) do
      case Integer.parse(input) do
        {age, ""} when age > 0 -> {:some, age}
        _ -> :none
      end
    end

    test "from_string handles empty optional fields" do
      # User didn't fill in bio
      assert Maybe.from_string("") == :none
      assert Maybe.from_string("   ") == :none

      # User provided bio
      assert Maybe.from_string("Hello!") == {:some, "Hello!"}
    end

    test "parsing optional numeric field" do
      assert parse_optional_age("25") == {:some, 25}
      assert parse_optional_age("not a number") == :none
      assert parse_optional_age("-5") == :none
    end

    test "collecting only provided optional fields" do
      form_data = %{
        name: "Alice",
        bio: "",
        website: "https://example.com",
        age: "30"
      }

      # Build map with only non-empty optional fields
      optional_fields =
        [
          {:bio, Maybe.from_string(form_data.bio)},
          {:website, Maybe.from_string(form_data.website)},
          {:age, parse_optional_age(form_data.age)}
        ]
        |> Enum.filter(fn {_k, v} -> Maybe.some?(v) end)
        |> Enum.map(fn {k, {:some, v}} -> {k, v} end)
        |> Map.new()

      assert optional_fields == %{website: "https://example.com", age: 30}
    end
  end

  # ============================================================================
  # USE CASE: Nested Configuration Access
  # ============================================================================

  describe "Use Case: Nested configuration access" do
    # Configuration often has nested optional sections.
    # Maybe.fetch_path provides safe deep access.

    defp app_config do
      %{
        database: %{
          primary: %{host: "localhost", port: 5432},
          replica: nil
        },
        cache: %{
          enabled: true,
          redis: %{host: "redis.local"}
        },
        features: nil
      }
    end

    test "fetch_path safely accesses nested config" do
      config = app_config()

      # Existing path
      assert Maybe.fetch_path(config, [:database, :primary, :host]) == {:some, "localhost"}

      # Path through nil value
      assert Maybe.fetch_path(config, [:database, :replica, :host]) == :none

      # Non-existent key
      assert Maybe.fetch_path(config, [:database, :primary, :username]) == :none

      # Entire section is nil
      assert Maybe.fetch_path(config, [:features, :flag_a]) == :none
    end

    test "providing defaults for missing config" do
      config = app_config()

      cache_host =
        config
        |> Maybe.fetch_path([:cache, :redis, :host])
        |> Maybe.unwrap_or("localhost")

      assert cache_host == "redis.local"

      replica_host =
        config
        |> Maybe.fetch_path([:database, :replica, :host])
        |> Maybe.unwrap_or("localhost")

      assert replica_host == "localhost"
    end
  end

  # ============================================================================
  # USE CASE: Cascading Value Resolution
  # ============================================================================

  describe "Use Case: Cascading value resolution (env → config → default)" do
    # Common pattern: check multiple sources until finding a value

    defp get_from_env(_key), do: nil
    defp get_from_config(:api_timeout), do: 30_000
    defp get_from_config(_key), do: nil
    defp default_value(:api_timeout), do: 5_000
    defp default_value(_), do: nil

    test "first_some finds first available value" do
      timeout =
        Maybe.first_some([
          fn -> Maybe.from_nilable(get_from_env(:api_timeout)) end,
          fn -> Maybe.from_nilable(get_from_config(:api_timeout)) end,
          fn -> Maybe.from_nilable(default_value(:api_timeout)) end
        ])

      assert timeout == {:some, 30_000}
    end

    test "or_else chains provide fallback sources" do
      result =
        Maybe.from_nilable(get_from_env(:missing_key))
        |> Maybe.or_else(fn -> Maybe.from_nilable(get_from_config(:missing_key)) end)
        |> Maybe.or_else(fn -> {:some, "final_default"} end)

      assert result == {:some, "final_default"}
    end

    test "first_some is lazy - stops at first success" do
      call_count = :counters.new(1, [:atomics])

      Maybe.first_some([
        fn ->
          :counters.add(call_count, 1, 1)
          :none
        end,
        fn ->
          :counters.add(call_count, 1, 1)
          {:some, "found"}
        end,
        fn ->
          :counters.add(call_count, 1, 1)
          {:some, "never reached"}
        end
      ])

      # Only first two functions were called
      assert :counters.get(call_count, 1) == 2
    end
  end

  # ============================================================================
  # USE CASE: Data Validation with Filtering
  # ============================================================================

  describe "Use Case: Data validation with filtering" do
    # Maybe.filter is useful for validating optional values

    test "filter keeps valid values, rejects invalid" do
      age_input = {:some, 25}

      # Valid age
      valid_age =
        age_input
        |> Maybe.filter(&(&1 >= 0 and &1 <= 150))

      assert valid_age == {:some, 25}

      # Invalid age becomes none
      invalid_age =
        {:some, -5}
        |> Maybe.filter(&(&1 >= 0 and &1 <= 150))

      assert invalid_age == :none
    end

    test "reject excludes specific values" do
      # Reject reserved usernames
      username = {:some, "admin"}

      result = Maybe.reject(username, &(&1 in ["admin", "root", "system"]))
      assert result == :none

      valid_username = {:some, "alice"}
      result = Maybe.reject(valid_username, &(&1 in ["admin", "root", "system"]))
      assert result == {:some, "alice"}
    end
  end

  # ============================================================================
  # USE CASE: Batch Processing with Optional Values
  # ============================================================================

  describe "Use Case: Batch processing with optional values" do
    # When processing lists that may contain optional values

    test "cat_somes extracts only present values from list" do
      api_responses = [
        {:some, %{id: 1, data: "a"}},
        :none,
        {:some, %{id: 3, data: "c"}},
        :none
      ]

      successful = Maybe.cat_somes(api_responses)
      assert length(successful) == 2
      assert Enum.map(successful, & &1.id) == [1, 3]
    end

    test "filter_map transforms and filters in one pass" do
      # Parse numbers, keeping only valid positive integers
      inputs = ["5", "abc", "-3", "10", "", "7"]

      results =
        Maybe.filter_map(inputs, fn input ->
          case Integer.parse(input) do
            {n, ""} when n > 0 -> {:some, n}
            _ -> :none
          end
        end)

      assert results == [5, 10, 7]
    end

    test "traverse fails if any item fails" do
      # All items must be valid
      items = ["apple", "banana", "cherry"]

      result =
        Maybe.traverse(items, fn item ->
          if String.length(item) > 3, do: {:some, String.upcase(item)}, else: :none
        end)

      assert result == {:some, ["APPLE", "BANANA", "CHERRY"]}
    end

    test "traverse returns none on first failure" do
      items = ["apple", "ok", "cherry"]

      result =
        Maybe.traverse(items, fn item ->
          if String.length(item) > 3, do: {:some, String.upcase(item)}, else: :none
        end)

      assert result == :none
    end
  end

  # ============================================================================
  # USE CASE: Converting Between Maybe and Result
  # ============================================================================

  describe "Use Case: Converting between Maybe and Result" do
    # Sometimes you need to switch between Maybe and Result semantics

    test "from_result converts success/failure to presence/absence" do
      # API returned data
      assert Maybe.from_result({:ok, %{user: "alice"}}) == {:some, %{user: "alice"}}

      # API returned error - we don't care about the specific error
      assert Maybe.from_result({:error, :not_found}) == :none
      assert Maybe.from_result({:error, :unauthorized}) == :none
    end

    test "to_result adds error context when value is missing" do
      # Convert presence to success
      assert Maybe.to_result({:some, 42}, :value_missing) == {:ok, 42}

      # Convert absence to specific error
      assert Maybe.to_result(:none, :value_missing) == {:error, :value_missing}
    end

    test "round-trip between types" do
      # Maybe → Result → Maybe
      original = {:some, "data"}

      result =
        original
        |> Maybe.to_result(:not_found)
        |> Maybe.from_result()

      assert result == original
    end
  end

  # ============================================================================
  # USE CASE: Combining Optional Values
  # ============================================================================

  describe "Use Case: Combining optional values" do
    # When you need multiple optional values together

    defp get_optional_first_name, do: {:some, "Jane"}
    defp get_optional_last_name, do: {:some, "Doe"}
    defp get_optional_middle_name, do: :none

    test "zip_with combines two optional values" do
      full_name =
        Maybe.zip_with(
          get_optional_first_name(),
          get_optional_last_name(),
          fn first, last -> "#{first} #{last}" end
        )

      assert full_name == {:some, "Jane Doe"}
    end

    test "zip_with returns none if either value missing" do
      result =
        Maybe.zip_with(
          get_optional_first_name(),
          get_optional_middle_name(),
          fn first, middle -> "#{first} #{middle}" end
        )

      assert result == :none
    end

    test "collect requires all values present" do
      all_names = Maybe.collect([
        get_optional_first_name(),
        get_optional_last_name()
      ])

      assert all_names == {:some, ["Jane", "Doe"]}

      # If any missing, result is none
      with_middle = Maybe.collect([
        get_optional_first_name(),
        get_optional_middle_name(),
        get_optional_last_name()
      ])

      assert with_middle == :none
    end
  end

  # ============================================================================
  # Core API Tests
  # ============================================================================

  describe "Maybe.some/1 and Maybe.none/0" do
    test "some wraps any value" do
      assert Maybe.some(42) == {:some, 42}
      assert Maybe.some(nil) == {:some, nil}
      assert Maybe.some(%{a: 1}) == {:some, %{a: 1}}
    end

    test "none returns none atom" do
      assert Maybe.none() == :none
    end
  end

  describe "Maybe.some?/1 and Maybe.none?/1" do
    test "some? returns true for some tuples" do
      assert Maybe.some?({:some, 42})
      assert Maybe.some?({:some, nil})
    end

    test "some? returns false for none and other values" do
      refute Maybe.some?(:none)
      refute Maybe.some?(:some)
      refute Maybe.some?(42)
    end

    test "none? returns true only for none atom" do
      assert Maybe.none?(:none)
      refute Maybe.none?({:some, 42})
      refute Maybe.none?(nil)
    end
  end

  describe "Maybe.from_nilable/1" do
    test "converts non-nil to some, nil to none" do
      assert Maybe.from_nilable(42) == {:some, 42}
      assert Maybe.from_nilable(nil) == :none
      assert Maybe.from_nilable(false) == {:some, false}
      assert Maybe.from_nilable(0) == {:some, 0}
      assert Maybe.from_nilable("") == {:some, ""}
    end
  end

  describe "Maybe.from_string/1" do
    test "handles empty, whitespace, and non-empty strings" do
      assert Maybe.from_string("hello") == {:some, "hello"}
      assert Maybe.from_string("") == :none
      assert Maybe.from_string("   ") == :none
      assert Maybe.from_string("  hello  ") == {:some, "hello"}
      assert Maybe.from_string(nil) == :none
    end
  end

  describe "Maybe.from_list/1 and Maybe.from_map/1" do
    test "converts based on emptiness" do
      assert Maybe.from_list([1, 2]) == {:some, [1, 2]}
      assert Maybe.from_list([]) == :none
      assert Maybe.from_map(%{a: 1}) == {:some, %{a: 1}}
      assert Maybe.from_map(%{}) == :none
    end
  end

  describe "Maybe.from_bool/2" do
    test "returns some on true, none on false" do
      assert Maybe.from_bool(true, "yes") == {:some, "yes"}
      assert Maybe.from_bool(false, "yes") == :none
    end
  end

  describe "Maybe.map/2" do
    test "transforms some, passes through none" do
      assert Maybe.map({:some, 5}, &(&1 * 2)) == {:some, 10}
      assert Maybe.map(:none, &(&1 * 2)) == :none
    end
  end

  describe "Maybe.and_then/2" do
    test "chains operations, short-circuits on none" do
      result =
        {:some, 5}
        |> Maybe.and_then(&{:some, &1 * 2})
        |> Maybe.and_then(&{:some, &1 + 1})

      assert result == {:some, 11}

      result =
        {:some, 5}
        |> Maybe.and_then(fn _ -> :none end)
        |> Maybe.and_then(&{:some, &1 * 2})

      assert result == :none
    end
  end

  describe "Maybe.or_else/2 and Maybe.or_value/2" do
    test "or_else provides fallback for none" do
      assert Maybe.or_else({:some, 42}, fn -> {:some, 0} end) == {:some, 42}
      assert Maybe.or_else(:none, fn -> {:some, 0} end) == {:some, 0}
    end

    test "or_value selects first some" do
      assert Maybe.or_value({:some, 1}, {:some, 2}) == {:some, 1}
      assert Maybe.or_value(:none, {:some, 2}) == {:some, 2}
      assert Maybe.or_value(:none, :none) == :none
    end
  end

  describe "Maybe.filter/2 and Maybe.reject/2" do
    test "filter keeps or discards based on predicate" do
      assert Maybe.filter({:some, 5}, &(&1 > 3)) == {:some, 5}
      assert Maybe.filter({:some, 2}, &(&1 > 3)) == :none
      assert Maybe.filter(:none, &(&1 > 3)) == :none
    end

    test "reject is inverse of filter" do
      assert Maybe.reject({:some, 5}, &(&1 > 3)) == :none
      assert Maybe.reject({:some, 2}, &(&1 > 3)) == {:some, 2}
    end
  end

  describe "Maybe.unwrap!/1 and unwrap_or variants" do
    test "unwrap! returns value or raises" do
      assert Maybe.unwrap!({:some, 42}) == 42
      assert_raise ArgumentError, fn -> Maybe.unwrap!(:none) end
    end

    test "unwrap_or provides default" do
      assert Maybe.unwrap_or({:some, 42}, 0) == 42
      assert Maybe.unwrap_or(:none, 0) == 0
    end

    test "unwrap_or_else computes default lazily" do
      assert Maybe.unwrap_or_else({:some, 42}, fn -> raise "not called" end) == 42
      assert Maybe.unwrap_or_else(:none, fn -> 0 end) == 0
    end
  end

  describe "Maybe.to_nilable/1 and Maybe.to_list/1" do
    test "converts to nullable value" do
      assert Maybe.to_nilable({:some, 42}) == 42
      assert Maybe.to_nilable(:none) == nil
    end

    test "converts to list" do
      assert Maybe.to_list({:some, 42}) == [42]
      assert Maybe.to_list(:none) == []
    end
  end

  describe "Maybe.flatten/1" do
    test "flattens nested maybe" do
      assert Maybe.flatten({:some, {:some, 42}}) == {:some, 42}
      assert Maybe.flatten({:some, :none}) == :none
      assert Maybe.flatten(:none) == :none
    end
  end

  describe "Maybe.zip/2 and Maybe.zip_with/3" do
    test "zip combines two maybes into tuple" do
      assert Maybe.zip({:some, 1}, {:some, 2}) == {:some, {1, 2}}
      assert Maybe.zip(:none, {:some, 2}) == :none
    end

    test "zip_with combines with function" do
      assert Maybe.zip_with({:some, 2}, {:some, 3}, &+/2) == {:some, 5}
      assert Maybe.zip_with(:none, {:some, 3}, &+/2) == :none
    end
  end

  describe "Maybe.apply/2 (Applicative)" do
    test "applies wrapped function to wrapped value" do
      assert Maybe.apply({:some, &String.upcase/1}, {:some, "hi"}) == {:some, "HI"}
      assert Maybe.apply(:none, {:some, "hi"}) == :none
      assert Maybe.apply({:some, &String.upcase/1}, :none) == :none
    end
  end

  describe "Maybe.collect/1 and Maybe.traverse/2" do
    test "collect gathers all some values" do
      assert Maybe.collect([{:some, 1}, {:some, 2}]) == {:some, [1, 2]}
      assert Maybe.collect([{:some, 1}, :none]) == :none
      assert Maybe.collect([]) == {:some, []}
    end

    test "traverse maps then collects" do
      assert Maybe.traverse([1, 2, 3], &{:some, &1 * 2}) == {:some, [2, 4, 6]}
      assert Maybe.traverse([1, 2], fn x -> if x > 1, do: :none, else: {:some, x} end) == :none
    end
  end

  describe "Maybe.tap_some/2 and Maybe.tap_none/2" do
    test "tap_some executes side effect for some" do
      log = Agent.start_link(fn -> nil end) |> elem(1)

      result = Maybe.tap_some({:some, 42}, fn v -> Agent.update(log, fn _ -> v end) end)

      assert result == {:some, 42}
      assert Agent.get(log, & &1) == 42
      Agent.stop(log)
    end

    test "tap_none executes side effect for none" do
      log = Agent.start_link(fn -> nil end) |> elem(1)

      result = Maybe.tap_none(:none, fn -> Agent.update(log, fn _ -> :executed end) end)

      assert result == :none
      assert Agent.get(log, & &1) == :executed
      Agent.stop(log)
    end
  end

  describe "Maybe.when_true/2 and Maybe.unless_true/2" do
    test "conditional maybe creation" do
      assert Maybe.when_true(true, 42) == {:some, 42}
      assert Maybe.when_true(false, 42) == :none
      assert Maybe.unless_true(false, 42) == {:some, 42}
      assert Maybe.unless_true(true, 42) == :none
    end

    test "lazy variants don't compute unless needed" do
      assert Maybe.when_true_lazy(false, fn -> raise "not called" end) == :none
      assert Maybe.unless_true_lazy(true, fn -> raise "not called" end) == :none
    end
  end

  describe "Maybe.get/2" do
    test "accesses map key as maybe" do
      assert Maybe.get(%{name: "Alice"}, :name) == {:some, "Alice"}
      assert Maybe.get(%{name: "Alice"}, :age) == :none
      assert Maybe.get(%{name: nil}, :name) == :none
    end
  end

  describe "Maybe.lift/1" do
    test "lifts function to work on maybes" do
      upcase = Maybe.lift(&String.upcase/1)

      assert upcase.({:some, "hello"}) == {:some, "HELLO"}
      assert upcase.(:none) == :none
    end
  end

  describe "Maybe.reduce/3" do
    test "folds some value, returns accumulator for none" do
      assert Maybe.reduce({:some, 5}, 10, &+/2) == 15
      assert Maybe.reduce(:none, 10, &+/2) == 10
    end
  end

  describe "Maybe.replace/2" do
    test "replaces value if some" do
      assert Maybe.replace({:some, 5}, 42) == {:some, 42}
      assert Maybe.replace(:none, 42) == :none
    end
  end
end
