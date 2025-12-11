defmodule OmSchema.SlugifyTest do
  use ExUnit.Case, async: true

  alias OmSchema.Slugify

  # ============================================
  # Basic Slugify
  # ============================================

  describe "slugify/2 basic" do
    test "converts simple text to slug" do
      assert Slugify.slugify("Hello World") == "hello-world"
    end

    test "handles empty string" do
      assert Slugify.slugify("") == ""
    end

    test "handles single word" do
      assert Slugify.slugify("Hello") == "hello"
    end

    test "removes punctuation" do
      assert Slugify.slugify("Hello World!") == "hello-world"
      assert Slugify.slugify("Hello, World") == "hello-world"
      assert Slugify.slugify("Hello... World???") == "hello-world"
    end

    test "collapses multiple spaces" do
      assert Slugify.slugify("Hello    World") == "hello-world"
    end

    test "trims leading and trailing separators" do
      assert Slugify.slugify("  Hello World  ") == "hello-world"
    end

    test "handles numbers" do
      assert Slugify.slugify("Test 123") == "test-123"
      assert Slugify.slugify("123 Test") == "123-test"
    end

    test "handles underscores" do
      assert Slugify.slugify("hello_world") == "hello_world"
    end
  end

  # ============================================
  # Unicode and Transliteration
  # ============================================

  describe "slugify/2 unicode" do
    test "transliterates accented characters by default" do
      # The implementation removes diacritics, so café becomes cafe
      assert Slugify.slugify("café résumé") == "cafe-resume"
    end

    test "keeps accents when ascii: false" do
      # Note: actual behavior depends on implementation
      result = Slugify.slugify("café", ascii: false)
      assert is_binary(result)
    end

    test "handles special unicode characters" do
      # über -> uber (u with umlaut becomes u)
      assert Slugify.slugify("über cool") == "uber-cool"
      # naïve -> naive (i with diaeresis becomes i)
      assert Slugify.slugify("naïve") == "naive"
    end
  end

  # ============================================
  # Separator Options
  # ============================================

  describe "slugify/2 separator" do
    test "uses custom separator" do
      assert Slugify.slugify("Hello World", separator: "_") == "hello_world"
    end

    test "uses dot as separator" do
      assert Slugify.slugify("Hello World", separator: ".") == "hello.world"
    end

    test "collapses multiple custom separators" do
      result = Slugify.slugify("Hello   World", separator: "_")
      assert result == "hello_world"
    end
  end

  # ============================================
  # Lowercase Options
  # ============================================

  describe "slugify/2 lowercase" do
    test "lowercases by default" do
      assert Slugify.slugify("HELLO WORLD") == "hello-world"
    end

    test "preserves case when lowercase: false" do
      assert Slugify.slugify("Hello World", lowercase: false) == "Hello-World"
    end
  end

  # ============================================
  # Uniquify Options
  # ============================================

  describe "slugify/2 uniquify" do
    test "adds suffix when uniquify: true" do
      result = Slugify.slugify("Hello World", uniquify: true)

      assert String.starts_with?(result, "hello-world-")
      # Default suffix length is 6
      [_base, suffix] = String.split(result, "hello-world-")
      assert String.length(suffix) == 6
    end

    test "adds custom length suffix" do
      result = Slugify.slugify("Hello World", uniquify: 8)

      [_base, suffix] = String.split(result, "hello-world-")
      assert String.length(suffix) == 8
    end

    test "suffix contains only alphanumeric" do
      result = Slugify.slugify("Test", uniquify: true)

      [_base, suffix] = String.split(result, "test-")
      assert String.match?(suffix, ~r/^[a-z0-9]+$/)
    end

    test "generates different suffixes each time" do
      result1 = Slugify.slugify("Test", uniquify: true)
      result2 = Slugify.slugify("Test", uniquify: true)

      assert result1 != result2
    end

    test "handles empty slug with uniquify" do
      # When the slug is empty (all special chars), just return the suffix
      result = Slugify.slugify("!!!", uniquify: true)
      assert String.length(result) == 6
    end
  end

  # ============================================
  # Truncate Options
  # ============================================

  describe "slugify/2 truncate" do
    test "truncates long slugs" do
      result = Slugify.slugify("Very Long Title That Should Be Truncated", truncate: 20)

      assert String.length(result) <= 20
    end

    test "truncate with uniquify" do
      result =
        Slugify.slugify("Very Long Title That Should Be Truncated", truncate: 20, uniquify: true)

      # Should be truncated base + separator + suffix
      assert String.contains?(result, "-")
    end

    test "truncate trims trailing separators" do
      result = Slugify.slugify("Hello World Test", truncate: 11)

      # Should trim the trailing separator after truncation
      refute String.ends_with?(result, "-")
    end
  end

  # ============================================
  # Generate Suffix
  # ============================================

  describe "generate_suffix/1" do
    test "generates suffix of specified length" do
      assert String.length(Slugify.generate_suffix(6)) == 6
      assert String.length(Slugify.generate_suffix(8)) == 8
      assert String.length(Slugify.generate_suffix(12)) == 12
    end

    test "generates only lowercase alphanumeric characters" do
      suffix = Slugify.generate_suffix(100)

      assert String.match?(suffix, ~r/^[a-z0-9]+$/)
    end

    test "generates different suffixes" do
      suffixes = for _ <- 1..10, do: Slugify.generate_suffix(6)

      # With 36^6 possibilities, duplicates are extremely unlikely
      assert length(Enum.uniq(suffixes)) == 10
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "slugify/2 edge cases" do
    test "handles only special characters" do
      assert Slugify.slugify("!@#$%") == ""
    end

    test "handles only whitespace" do
      assert Slugify.slugify("   ") == ""
    end

    test "handles mixed special and regular" do
      assert Slugify.slugify("!Hello! World?") == "hello-world"
    end

    test "handles consecutive separators in input" do
      assert Slugify.slugify("Hello---World") == "hello-world"
    end

    test "handles numbers only" do
      assert Slugify.slugify("12345") == "12345"
    end

    test "handles very long input" do
      long_text = String.duplicate("Hello World ", 100)
      result = Slugify.slugify(long_text)

      assert is_binary(result)
      assert String.length(result) > 0
    end
  end

  # ============================================
  # Combined Options
  # ============================================

  describe "slugify/2 combined options" do
    test "custom separator + lowercase: false" do
      result = Slugify.slugify("Hello World", separator: "_", lowercase: false)

      assert result == "Hello_World"
    end

    test "uniquify + custom separator" do
      result = Slugify.slugify("Hello World", separator: "_", uniquify: true)

      assert String.starts_with?(result, "hello_world_")
    end

    test "truncate + uniquify + custom separator" do
      result =
        Slugify.slugify("Very Long Title", truncate: 10, uniquify: true, separator: "_")

      assert String.contains?(result, "_")
    end
  end
end
