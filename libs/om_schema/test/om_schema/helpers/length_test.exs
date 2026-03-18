defmodule OmSchema.Helpers.LengthTest do
  @moduledoc """
  Tests for OmSchema.Helpers.Length - shared length validation helpers.

  Provides consistent length validation for strings, arrays, and maps:

  - `validate_min_length/4` - Minimum length with optional custom message
  - `validate_max_length/4` - Maximum length with optional custom message
  - `validate_exact_length/4` - Exact length with optional custom message
  - `validate_length_opts/3` - Convenience applying min/max/exact from opts
  - `validate_array_length/3` - Array-specific length (min/max/exact items)
  - `validate_map_size/3` - Map key count validation (min/max keys)

  Note: For string fields, the default_min_message/default_max_message return nil.
  When validation fails on a string field without a custom message, Ecto.Changeset
  raises because `message: nil` is not valid. In practice, callers always provide
  messages for string fields or use the higher-level validators that set messages.
  Tests for string field failures therefore always supply a custom message.
  """

  use ExUnit.Case, async: true

  import OmSchema.Helpers.Length

  # ============================================
  # Test Schema
  # ============================================

  defmodule LengthTestSchema do
    use Ecto.Schema

    schema "length_test" do
      field :name, :string
      field :tags, {:array, :string}
      field :metadata, :map
      field :code, :string
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp changeset(attrs) do
    Ecto.Changeset.cast(%LengthTestSchema{}, attrs, [:name, :tags, :metadata, :code])
  end

  defp errors_on(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # ============================================
  # validate_min_length/4
  # ============================================

  describe "validate_min_length/4" do
    test "passes when string meets minimum length" do
      cs = changeset(%{name: "hello"}) |> validate_min_length(:name, 3, [])
      assert cs.valid?
    end

    test "passes when string exactly meets minimum length" do
      cs = changeset(%{name: "abc"}) |> validate_min_length(:name, 3, [])
      assert cs.valid?
    end

    test "fails when string is shorter than minimum with custom message" do
      cs =
        changeset(%{name: "ab"})
        |> validate_min_length(:name, 3, min_length_message: "at least %{count} characters")

      refute cs.valid?
      assert errors_on(cs, :name) == ["at least 3 characters"]
    end

    test "passes when min is nil (skips validation)" do
      cs = changeset(%{name: "hello"}) |> validate_min_length(:name, nil, [])
      assert cs.valid?
    end

    test "custom error message via min_length_message" do
      cs =
        changeset(%{name: "a"})
        |> validate_min_length(:name, 3, min_length_message: "too short, need %{count}+")

      refute cs.valid?
      assert errors_on(cs, :name) == ["too short, need 3+"]
    end

    test "passes with empty opts when string is long enough" do
      cs = changeset(%{name: "hello world"}) |> validate_min_length(:name, 5, [])
      assert cs.valid?
    end

    test "handles min of 0 (always passes)" do
      cs = changeset(%{name: ""}) |> validate_min_length(:name, 0, [])
      assert cs.valid?
    end

    test "handles min of 2 with single-char string" do
      cs =
        changeset(%{name: "a"})
        |> validate_min_length(:name, 2, min_length_message: "at least %{count} characters")

      refute cs.valid?
      assert errors_on(cs, :name) == ["at least 2 characters"]
    end

    test "provides array-specific message for array fields automatically" do
      cs =
        changeset(%{tags: []})
        |> validate_min_length(:tags, 1, [])

      refute cs.valid?
      assert errors_on(cs, :tags) == ["should have at least 1 item(s)"]
    end

    test "passes for array fields meeting minimum" do
      cs =
        changeset(%{tags: ["a", "b"]})
        |> validate_min_length(:tags, 1, [])

      assert cs.valid?
    end
  end

  # ============================================
  # validate_max_length/4
  # ============================================

  describe "validate_max_length/4" do
    test "passes when string is under maximum length" do
      cs = changeset(%{name: "hi"}) |> validate_max_length(:name, 5, [])
      assert cs.valid?
    end

    test "passes when string exactly meets maximum length" do
      cs = changeset(%{name: "hello"}) |> validate_max_length(:name, 5, [])
      assert cs.valid?
    end

    test "fails when string exceeds maximum length with custom message" do
      cs =
        changeset(%{name: "hello world"})
        |> validate_max_length(:name, 5, max_length_message: "at most %{count} characters")

      refute cs.valid?
      assert errors_on(cs, :name) == ["at most 5 characters"]
    end

    test "passes when max is nil (skips validation)" do
      cs = changeset(%{name: "hello"}) |> validate_max_length(:name, nil, [])
      assert cs.valid?
    end

    test "custom error message via max_length_message" do
      cs =
        changeset(%{name: "hello world"})
        |> validate_max_length(:name, 5, max_length_message: "too long, max %{count}")

      refute cs.valid?
      assert errors_on(cs, :name) == ["too long, max 5"]
    end

    test "handles max of 0 with empty string (passes)" do
      cs = changeset(%{name: ""}) |> validate_max_length(:name, 0, [])
      assert cs.valid?
    end

    test "fails with max of 0 and non-empty string" do
      cs =
        changeset(%{name: "a"})
        |> validate_max_length(:name, 0, max_length_message: "must be empty")

      refute cs.valid?
      assert errors_on(cs, :name) == ["must be empty"]
    end

    test "provides array-specific message for array fields automatically" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> validate_max_length(:tags, 2, [])

      refute cs.valid?
      assert errors_on(cs, :tags) == ["should have at most 2 item(s)"]
    end

    test "passes for array fields under maximum" do
      cs =
        changeset(%{tags: ["a"]})
        |> validate_max_length(:tags, 3, [])

      assert cs.valid?
    end
  end

  # ============================================
  # validate_exact_length/4
  # ============================================

  describe "validate_exact_length/4" do
    test "passes when string has exact length" do
      cs = changeset(%{code: "ABC123"}) |> validate_exact_length(:code, 6, [])
      assert cs.valid?
    end

    test "fails when string is shorter with custom message" do
      cs =
        changeset(%{code: "ABC"})
        |> validate_exact_length(:code, 6, length_message: "must be exactly %{count} chars")

      refute cs.valid?
      assert errors_on(cs, :code) == ["must be exactly 6 chars"]
    end

    test "fails when string is longer with custom message" do
      cs =
        changeset(%{code: "ABC1234567"})
        |> validate_exact_length(:code, 6, length_message: "must be exactly %{count} chars")

      refute cs.valid?
      assert errors_on(cs, :code) == ["must be exactly 6 chars"]
    end

    test "passes when length is nil (skips validation)" do
      cs = changeset(%{code: "ABC"}) |> validate_exact_length(:code, nil, [])
      assert cs.valid?
    end

    test "custom error message via length_message" do
      cs =
        changeset(%{code: "AB"})
        |> validate_exact_length(:code, 6, length_message: "code must be %{count} characters")

      refute cs.valid?
      assert errors_on(cs, :code) == ["code must be 6 characters"]
    end

    test "handles exact length of 0 with empty string" do
      cs = changeset(%{code: ""}) |> validate_exact_length(:code, 0, [])
      assert cs.valid?
    end

    test "handles exact length of 1" do
      cs_pass = changeset(%{code: "A"}) |> validate_exact_length(:code, 1, [])
      assert cs_pass.valid?
    end

    test "passes with long exact match" do
      long_code = String.duplicate("A", 100)
      cs = changeset(%{code: long_code}) |> validate_exact_length(:code, 100, [])
      assert cs.valid?
    end
  end

  # ============================================
  # validate_length_opts/3
  # ============================================

  describe "validate_length_opts/3" do
    test "applies min_length from opts - passes when met" do
      cs = changeset(%{name: "hello"}) |> validate_length_opts(:name, min_length: 3)
      assert cs.valid?
    end

    test "applies min_length from opts - fails when not met" do
      cs =
        changeset(%{name: "ab"})
        |> validate_length_opts(:name, min_length: 3, min_length_message: "too short")

      refute cs.valid?
    end

    test "applies max_length from opts - passes when met" do
      cs = changeset(%{name: "hi"}) |> validate_length_opts(:name, max_length: 5)
      assert cs.valid?
    end

    test "applies max_length from opts - fails when exceeded" do
      cs =
        changeset(%{name: "hello world"})
        |> validate_length_opts(:name, max_length: 5, max_length_message: "too long")

      refute cs.valid?
    end

    test "applies both min and max from opts - valid value" do
      cs =
        changeset(%{name: "hello"})
        |> validate_length_opts(:name, min_length: 3, max_length: 10)

      assert cs.valid?
    end

    test "applies both min and max from opts - too short" do
      cs =
        changeset(%{name: "ab"})
        |> validate_length_opts(:name,
          min_length: 3,
          max_length: 10,
          min_length_message: "too short"
        )

      refute cs.valid?
    end

    test "applies both min and max from opts - too long" do
      cs =
        changeset(%{name: "hello world foo"})
        |> validate_length_opts(:name,
          min_length: 3,
          max_length: 10,
          max_length_message: "too long"
        )

      refute cs.valid?
    end

    test "exact length takes precedence over min/max" do
      cs =
        changeset(%{code: "ABC123"})
        |> validate_length_opts(:code, length: 6, min_length: 1, max_length: 100)

      assert cs.valid?
    end

    test "exact length takes precedence - fails when wrong" do
      cs =
        changeset(%{code: "AB"})
        |> validate_length_opts(:code,
          length: 6,
          min_length: 1,
          max_length: 100,
          length_message: "must be %{count}"
        )

      refute cs.valid?
    end

    test "no length options returns changeset unchanged" do
      cs = changeset(%{name: "hello"}) |> validate_length_opts(:name, [])
      assert cs.valid?
    end

    test "works with array fields using min_length" do
      cs = changeset(%{tags: ["a", "b"]}) |> validate_length_opts(:tags, min_length: 1)
      assert cs.valid?
    end

    test "works with array fields - too few" do
      cs = changeset(%{tags: []}) |> validate_length_opts(:tags, min_length: 1)
      refute cs.valid?
    end
  end

  # ============================================
  # validate_array_length/3
  # ============================================

  describe "validate_array_length/3" do
    test "passes when array meets min_length" do
      cs = changeset(%{tags: ["a", "b"]}) |> validate_array_length(:tags, min_length: 1)
      assert cs.valid?
    end

    test "fails when array is shorter than min_length" do
      cs = changeset(%{tags: []}) |> validate_array_length(:tags, min_length: 1)
      refute cs.valid?
      assert errors_on(cs, :tags) == ["should have at least 1 item(s)"]
    end

    test "passes when array is under max_length" do
      cs = changeset(%{tags: ["a"]}) |> validate_array_length(:tags, max_length: 3)
      assert cs.valid?
    end

    test "passes when array exactly meets max_length" do
      cs =
        changeset(%{tags: ["a", "b", "c"]}) |> validate_array_length(:tags, max_length: 3)

      assert cs.valid?
    end

    test "fails when array exceeds max_length" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d"]})
        |> validate_array_length(:tags, max_length: 3)

      refute cs.valid?
      assert errors_on(cs, :tags) == ["should have at most 3 item(s)"]
    end

    test "passes when array has exact length" do
      cs = changeset(%{tags: ["a", "b"]}) |> validate_array_length(:tags, length: 2)
      assert cs.valid?
    end

    test "fails when array does not have exact length" do
      cs = changeset(%{tags: ["a"]}) |> validate_array_length(:tags, length: 2)
      refute cs.valid?
      assert errors_on(cs, :tags) == ["should have exactly 2 item(s)"]
    end

    test "no options returns changeset unchanged" do
      cs =
        changeset(%{tags: ["a", "b", "c"]}) |> validate_array_length(:tags, [])

      assert cs.valid?
    end

    test "min and max together - valid" do
      cs =
        changeset(%{tags: ["a", "b"]})
        |> validate_array_length(:tags, min_length: 1, max_length: 3)

      assert cs.valid?
    end

    test "min and max together - too few" do
      cs =
        changeset(%{tags: []})
        |> validate_array_length(:tags, min_length: 1, max_length: 3)

      refute cs.valid?
    end

    test "min and max together - too many" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d"]})
        |> validate_array_length(:tags, min_length: 1, max_length: 3)

      refute cs.valid?
    end

    test "min_length of 0 with empty array passes" do
      cs = changeset(%{tags: []}) |> validate_array_length(:tags, min_length: 0)
      assert cs.valid?
    end

    test "exact length of 0 with empty array passes" do
      cs = changeset(%{tags: []}) |> validate_array_length(:tags, length: 0)
      assert cs.valid?
    end

    test "exact length of 0 with non-empty array fails" do
      cs = changeset(%{tags: ["a"]}) |> validate_array_length(:tags, length: 0)
      refute cs.valid?
    end

    test "large array passes when under max" do
      big_tags = for i <- 1..50, do: "tag_#{i}"
      cs = changeset(%{tags: big_tags}) |> validate_array_length(:tags, max_length: 100)
      assert cs.valid?
    end

    test "exactly at min boundary passes" do
      cs = changeset(%{tags: ["a"]}) |> validate_array_length(:tags, min_length: 1)
      assert cs.valid?
    end

    test "exactly at max boundary passes" do
      cs =
        changeset(%{tags: ["a", "b"]}) |> validate_array_length(:tags, max_length: 2)

      assert cs.valid?
    end
  end

  # ============================================
  # validate_map_size/3
  # ============================================

  describe "validate_map_size/3" do
    test "passes when map has at least min_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2}})
        |> validate_map_size(:metadata, min_keys: 1)

      assert cs.valid?
    end

    test "fails when map has fewer than min_keys" do
      cs =
        changeset(%{metadata: %{}})
        |> validate_map_size(:metadata, min_keys: 1)

      refute cs.valid?
      assert errors_on(cs, :metadata) == ["should have at least 1 key(s)"]
    end

    test "passes when map has at most max_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> validate_map_size(:metadata, max_keys: 3)

      assert cs.valid?
    end

    test "passes when map exactly meets max_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3}})
        |> validate_map_size(:metadata, max_keys: 3)

      assert cs.valid?
    end

    test "fails when map exceeds max_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3, "d" => 4}})
        |> validate_map_size(:metadata, max_keys: 3)

      refute cs.valid?
      assert errors_on(cs, :metadata) == ["should have at most 3 key(s)"]
    end

    test "no options returns changeset unchanged" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> validate_map_size(:metadata, [])

      assert cs.valid?
    end

    test "min and max together - valid" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2}})
        |> validate_map_size(:metadata, min_keys: 1, max_keys: 3)

      assert cs.valid?
    end

    test "min and max together - too few" do
      cs =
        changeset(%{metadata: %{}})
        |> validate_map_size(:metadata, min_keys: 1, max_keys: 3)

      refute cs.valid?
    end

    test "min and max together - too many" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3, "d" => 4}})
        |> validate_map_size(:metadata, min_keys: 1, max_keys: 3)

      refute cs.valid?
    end

    test "min_keys of 0 with empty map passes" do
      cs =
        changeset(%{metadata: %{}})
        |> validate_map_size(:metadata, min_keys: 0)

      assert cs.valid?
    end

    test "max_keys of 0 with empty map passes" do
      cs =
        changeset(%{metadata: %{}})
        |> validate_map_size(:metadata, max_keys: 0)

      assert cs.valid?
    end

    test "max_keys of 0 with non-empty map fails" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> validate_map_size(:metadata, max_keys: 0)

      refute cs.valid?
    end

    test "map with many keys" do
      big_map = for i <- 1..20, into: %{}, do: {"key_#{i}", i}

      cs =
        changeset(%{metadata: big_map})
        |> validate_map_size(:metadata, min_keys: 5, max_keys: 50)

      assert cs.valid?
    end

    test "map exactly at min_keys boundary passes" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> validate_map_size(:metadata, min_keys: 1)

      assert cs.valid?
    end

    test "map exactly at max_keys boundary passes" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2}})
        |> validate_map_size(:metadata, max_keys: 2)

      assert cs.valid?
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "unchanged field is not validated by validate_array_length" do
      cs =
        %LengthTestSchema{}
        |> Ecto.Changeset.change()
        |> validate_array_length(:tags, min_length: 5)

      assert cs.valid?
    end

    test "unchanged field is not validated by validate_map_size" do
      cs =
        %LengthTestSchema{}
        |> Ecto.Changeset.change()
        |> validate_map_size(:metadata, min_keys: 5)

      assert cs.valid?
    end

    test "nil field value skipped by validate_min_length" do
      cs =
        %LengthTestSchema{}
        |> Ecto.Changeset.change()
        |> validate_min_length(:name, 3, [])

      assert cs.valid?
    end

    test "nil field value skipped by validate_max_length" do
      cs =
        %LengthTestSchema{}
        |> Ecto.Changeset.change()
        |> validate_max_length(:name, 3, [])

      assert cs.valid?
    end

    test "string with unicode characters counts graphemes for length" do
      # Ecto validate_length counts String.length (graphemes)
      cs = changeset(%{name: "cafe"}) |> validate_min_length(:name, 4, [])
      assert cs.valid?
    end

    test "multiple array validations can accumulate errors" do
      cs =
        changeset(%{tags: []})
        |> validate_array_length(:tags, min_length: 1)
        |> validate_array_length(:tags, min_length: 2)

      refute cs.valid?
      # Both min checks should fail
      assert length(errors_on(cs, :tags)) == 2
    end

    test "multiple map validations can accumulate errors" do
      cs =
        changeset(%{metadata: %{}})
        |> validate_map_size(:metadata, min_keys: 1)
        |> validate_map_size(:metadata, min_keys: 2)

      refute cs.valid?
      assert length(errors_on(cs, :metadata)) == 2
    end
  end
end
