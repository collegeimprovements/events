defmodule OmSchema.MappersTest do
  @moduledoc """
  Tests for OmSchema.Mappers - common mapper functions for field transformations.

  Mappers return single-argument functions suitable for the `mappers:` field option.

  - `trim/0` - Remove leading/trailing whitespace
  - `downcase/0` - Convert to lowercase
  - `upcase/0` - Convert to uppercase
  - `capitalize/0` - Capitalize first letter
  - `titlecase/0` - Capitalize each word
  - `squish/0` - Trim and collapse multiple spaces
  - `slugify/0`, `slugify/1` - Convert to URL-safe slug
  - `digits_only/0` - Remove non-digit characters
  - `alphanumeric_only/0` - Remove non-alphanumeric characters
  - `replace/2` - Replace pattern with replacement
  - `compose/1` - Compose multiple mappers into one
  """

  use ExUnit.Case, async: true

  alias OmSchema.Mappers

  # ============================================
  # trim/0
  # ============================================

  describe "trim/0" do
    test "returns a function" do
      assert is_function(Mappers.trim(), 1)
    end

    test "removes leading whitespace" do
      assert Mappers.trim().("   hello") == "hello"
    end

    test "removes trailing whitespace" do
      assert Mappers.trim().("hello   ") == "hello"
    end

    test "removes both leading and trailing whitespace" do
      assert Mappers.trim().("  hello  ") == "hello"
    end

    test "removes tabs and newlines" do
      assert Mappers.trim().("\thello\n") == "hello"
    end

    test "handles empty string" do
      assert Mappers.trim().("") == ""
    end

    test "handles whitespace-only string" do
      assert Mappers.trim().("   ") == ""
    end

    test "preserves internal whitespace" do
      assert Mappers.trim().("  hello world  ") == "hello world"
    end
  end

  # ============================================
  # downcase/0
  # ============================================

  describe "downcase/0" do
    test "returns a function" do
      assert is_function(Mappers.downcase(), 1)
    end

    test "lowercases uppercase string" do
      assert Mappers.downcase().("HELLO") == "hello"
    end

    test "lowercases mixed case" do
      assert Mappers.downcase().("Hello World") == "hello world"
    end

    test "handles already lowercase" do
      assert Mappers.downcase().("hello") == "hello"
    end

    test "handles empty string" do
      assert Mappers.downcase().("") == ""
    end

    test "handles unicode" do
      assert Mappers.downcase().("CAFÉ") == "café"
    end

    test "handles numbers and special chars (unchanged)" do
      assert Mappers.downcase().("ABC123!@#") == "abc123!@#"
    end
  end

  # ============================================
  # upcase/0
  # ============================================

  describe "upcase/0" do
    test "returns a function" do
      assert is_function(Mappers.upcase(), 1)
    end

    test "uppercases lowercase string" do
      assert Mappers.upcase().("hello") == "HELLO"
    end

    test "uppercases mixed case" do
      assert Mappers.upcase().("Hello World") == "HELLO WORLD"
    end

    test "handles already uppercase" do
      assert Mappers.upcase().("HELLO") == "HELLO"
    end

    test "handles empty string" do
      assert Mappers.upcase().("") == ""
    end

    test "handles unicode" do
      assert Mappers.upcase().("café") == "CAFÉ"
    end
  end

  # ============================================
  # capitalize/0
  # ============================================

  describe "capitalize/0" do
    test "returns a function" do
      assert is_function(Mappers.capitalize(), 1)
    end

    test "capitalizes first letter" do
      assert Mappers.capitalize().("hello world") == "Hello world"
    end

    test "lowercases rest of string" do
      assert Mappers.capitalize().("hELLO WORLD") == "Hello world"
    end

    test "handles single character" do
      assert Mappers.capitalize().("h") == "H"
    end

    test "handles empty string" do
      assert Mappers.capitalize().("") == ""
    end

    test "handles already capitalized" do
      assert Mappers.capitalize().("Hello world") == "Hello world"
    end

    test "handles all uppercase" do
      assert Mappers.capitalize().("HELLO") == "Hello"
    end
  end

  # ============================================
  # titlecase/0
  # ============================================

  describe "titlecase/0" do
    test "returns a function" do
      assert is_function(Mappers.titlecase(), 1)
    end

    test "capitalizes each word" do
      assert Mappers.titlecase().("hello world") == "Hello World"
    end

    test "handles single word" do
      assert Mappers.titlecase().("hello") == "Hello"
    end

    test "lowercases non-initial letters" do
      assert Mappers.titlecase().("hELLO wORLD") == "Hello World"
    end

    test "handles empty string" do
      assert Mappers.titlecase().("") == ""
    end

    test "collapses multiple spaces (from String.split)" do
      # String.split/1 splits on any whitespace, so multiple spaces collapse
      assert Mappers.titlecase().("hello   world") == "Hello World"
    end

    test "handles three words" do
      assert Mappers.titlecase().("foo bar baz") == "Foo Bar Baz"
    end

    test "handles leading/trailing spaces" do
      # String.split/1 ignores leading/trailing whitespace
      assert Mappers.titlecase().("  hello world  ") == "Hello World"
    end
  end

  # ============================================
  # squish/0
  # ============================================

  describe "squish/0" do
    test "returns a function" do
      assert is_function(Mappers.squish(), 1)
    end

    test "trims and collapses multiple spaces" do
      assert Mappers.squish().("  hello   world  ") == "hello world"
    end

    test "collapses tabs and newlines" do
      assert Mappers.squish().("hello\t\tworld\n\nfoo") == "hello world foo"
    end

    test "handles single space" do
      assert Mappers.squish().("hello world") == "hello world"
    end

    test "handles no spaces needed" do
      assert Mappers.squish().("hello") == "hello"
    end

    test "handles empty string" do
      assert Mappers.squish().("") == ""
    end

    test "handles whitespace-only string" do
      assert Mappers.squish().("   ") == ""
    end

    test "handles mixed whitespace types" do
      assert Mappers.squish().(" \t hello \n world \r ") == "hello world"
    end
  end

  # ============================================
  # slugify/0 and slugify/1
  # ============================================

  describe "slugify/0" do
    test "returns a function" do
      assert is_function(Mappers.slugify(), 1)
    end

    test "converts to URL-safe slug" do
      assert Mappers.slugify().("Hello World!") == "hello-world"
    end

    test "handles empty string" do
      assert Mappers.slugify().("") == ""
    end

    test "handles special characters" do
      assert Mappers.slugify().("Hello, World!!!") == "hello-world"
    end

    test "handles unicode" do
      assert Mappers.slugify().("café résumé") == "cafe-resume"
    end
  end

  describe "slugify/1 with options" do
    test "with uniquify: true adds suffix" do
      result = Mappers.slugify(uniquify: true).("Hello World")
      assert String.starts_with?(result, "hello-world-")
      # Default suffix is 6 chars
      suffix = String.replace_prefix(result, "hello-world-", "")
      assert String.length(suffix) == 6
    end

    test "with custom suffix length" do
      result = Mappers.slugify(uniquify: 8).("Hello World")
      suffix = String.replace_prefix(result, "hello-world-", "")
      assert String.length(suffix) == 8
    end

    test "with custom separator" do
      assert Mappers.slugify(separator: "_").("Hello World") == "hello_world"
    end

    test "with lowercase: false preserves case" do
      assert Mappers.slugify(lowercase: false).("Hello World") == "Hello-World"
    end

    test "with truncate limits length" do
      result = Mappers.slugify(truncate: 10).("Very Long Title Here")
      assert String.length(result) <= 10
    end

    test "combined options" do
      result = Mappers.slugify(separator: "_", uniquify: true).("Hello World")
      assert String.starts_with?(result, "hello_world_")
    end
  end

  # ============================================
  # digits_only/0
  # ============================================

  describe "digits_only/0" do
    test "returns a function" do
      assert is_function(Mappers.digits_only(), 1)
    end

    test "extracts only digits" do
      assert Mappers.digits_only().("abc123def456") == "123456"
    end

    test "handles phone number" do
      assert Mappers.digits_only().("+1 (555) 123-4567") == "15551234567"
    end

    test "handles no digits" do
      assert Mappers.digits_only().("hello") == ""
    end

    test "handles all digits" do
      assert Mappers.digits_only().("12345") == "12345"
    end

    test "handles empty string" do
      assert Mappers.digits_only().("") == ""
    end

    test "handles mixed special characters" do
      assert Mappers.digits_only().("a1!b2@c3#") == "123"
    end
  end

  # ============================================
  # alphanumeric_only/0
  # ============================================

  describe "alphanumeric_only/0" do
    test "returns a function" do
      assert is_function(Mappers.alphanumeric_only(), 1)
    end

    test "removes non-alphanumeric characters" do
      assert Mappers.alphanumeric_only().("hello-world_123!") == "helloworld123"
    end

    test "preserves letters and numbers" do
      assert Mappers.alphanumeric_only().("abc123") == "abc123"
    end

    test "removes spaces" do
      assert Mappers.alphanumeric_only().("hello world") == "helloworld"
    end

    test "removes special characters" do
      assert Mappers.alphanumeric_only().("!@#$%^&*()") == ""
    end

    test "handles empty string" do
      assert Mappers.alphanumeric_only().("") == ""
    end

    test "preserves uppercase and lowercase" do
      assert Mappers.alphanumeric_only().("Hello World 123") == "HelloWorld123"
    end
  end

  # ============================================
  # replace/2
  # ============================================

  describe "replace/2" do
    test "returns a function" do
      assert is_function(Mappers.replace(~r/-+/, "-"), 1)
    end

    test "replaces pattern with replacement" do
      assert Mappers.replace(~r/-+/, "-").("hello---world") == "hello-world"
    end

    test "replaces string pattern" do
      assert Mappers.replace("foo", "bar").("foo baz foo") == "bar baz bar"
    end

    test "handles no matches" do
      assert Mappers.replace("xyz", "abc").("hello world") == "hello world"
    end

    test "handles empty replacement" do
      assert Mappers.replace(~r/\s+/, "").("hello world") == "helloworld"
    end

    test "handles empty input" do
      assert Mappers.replace("a", "b").("") == ""
    end

    test "collapses whitespace" do
      assert Mappers.replace(~r/\s+/, " ").("hello   world   foo") == "hello world foo"
    end
  end

  # ============================================
  # compose/1
  # ============================================

  describe "compose/1" do
    test "returns a function" do
      assert is_function(Mappers.compose([Mappers.trim()]), 1)
    end

    test "composes two mappers" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.downcase()])
      assert mapper.("  HELLO  ") == "hello"
    end

    test "composes three mappers" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.downcase(), Mappers.slugify()])
      assert mapper.("  Hello World!  ") == "hello-world"
    end

    test "applies in left-to-right order" do
      # First upcase, then take digits only
      mapper = Mappers.compose([Mappers.upcase(), Mappers.digits_only()])
      assert mapper.("abc123") == "123"

      # First digits only, then upcase (digits unchanged by upcase)
      mapper2 = Mappers.compose([Mappers.digits_only(), Mappers.upcase()])
      assert mapper2.("abc123") == "123"
    end

    test "single mapper in list" do
      mapper = Mappers.compose([Mappers.trim()])
      assert mapper.("  hello  ") == "hello"
    end

    test "empty list returns value unchanged" do
      mapper = Mappers.compose([])
      assert mapper.("hello") == "hello"
    end

    test "compose email normalizer" do
      email_normalizer = Mappers.compose([Mappers.trim(), Mappers.downcase()])
      assert email_normalizer.("  User@Example.COM  ") == "user@example.com"
    end

    test "compose with squish and titlecase" do
      mapper = Mappers.compose([Mappers.squish(), Mappers.titlecase()])
      assert mapper.("  hello   world  ") == "Hello World"
    end

    test "compose with custom anonymous function" do
      mapper =
        Mappers.compose([
          Mappers.trim(),
          fn value -> value <> "!" end
        ])

      assert mapper.("  hello  ") == "hello!"
    end

    test "nested compose" do
      inner = Mappers.compose([Mappers.trim(), Mappers.downcase()])
      outer = Mappers.compose([inner, Mappers.slugify()])
      assert outer.("  Hello World!  ") == "hello-world"
    end
  end

  # ============================================
  # Integration: Mappers used together
  # ============================================

  describe "mapper integration" do
    test "email normalization pipeline" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.downcase()])
      assert mapper.("  USER@EXAMPLE.COM  ") == "user@example.com"
    end

    test "slug generation pipeline" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.squish(), Mappers.slugify()])
      assert mapper.("  Hello   World!  ") == "hello-world"
    end

    test "phone normalization pipeline" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.digits_only()])
      assert mapper.("  +1 (555) 123-4567  ") == "15551234567"
    end

    test "code normalization pipeline" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.upcase(), Mappers.alphanumeric_only()])
      assert mapper.("  abc-123-def  ") == "ABC123DEF"
    end

    test "name normalization pipeline" do
      mapper = Mappers.compose([Mappers.trim(), Mappers.squish(), Mappers.titlecase()])
      assert mapper.("  john   doe  ") == "John Doe"
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "all mappers handle empty string" do
      mappers = [
        Mappers.trim(),
        Mappers.downcase(),
        Mappers.upcase(),
        Mappers.capitalize(),
        Mappers.titlecase(),
        Mappers.squish(),
        Mappers.slugify(),
        Mappers.digits_only(),
        Mappers.alphanumeric_only(),
        Mappers.replace("a", "b")
      ]

      for mapper <- mappers do
        assert is_binary(mapper.("")), "Mapper should handle empty string"
      end
    end

    test "all mappers return strings" do
      mappers = [
        Mappers.trim(),
        Mappers.downcase(),
        Mappers.upcase(),
        Mappers.capitalize(),
        Mappers.titlecase(),
        Mappers.squish(),
        Mappers.slugify(),
        Mappers.digits_only(),
        Mappers.alphanumeric_only(),
        Mappers.replace("a", "b")
      ]

      for mapper <- mappers do
        assert is_binary(mapper.("test input")), "Mapper should return a string"
      end
    end

    test "unicode handling across mappers" do
      assert Mappers.downcase().("ÜBER") == "über"
      assert Mappers.upcase().("über") == "ÜBER"
      assert Mappers.capitalize().("über cool") == "Über cool"
      assert Mappers.trim().("  über  ") == "über"
    end

    test "very long string handling" do
      long_string = String.duplicate("hello world ", 1000)
      assert is_binary(Mappers.squish().(long_string))
      assert is_binary(Mappers.slugify().(long_string))
      assert is_binary(Mappers.trim().(long_string))
    end
  end
end
