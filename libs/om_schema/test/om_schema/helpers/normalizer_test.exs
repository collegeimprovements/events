defmodule OmSchema.Helpers.NormalizerTest do
  @moduledoc """
  Tests for OmSchema.Helpers.Normalizer - field value normalization.

  Normalizer provides general-purpose and type-specific normalization:

  - `normalize/2` - General normalization with mappers or legacy normalize opts
  - `normalize_email/1` - Email normalization (trim + downcase)
  - `normalize_phone/1` - Phone normalization (strip non-digits except +)
  - `normalize_url/1` - URL normalization (trim + downcase)
  - `normalize_slug/1` - Slug normalization (URL-safe format)
  """

  use ExUnit.Case, async: true

  alias OmSchema.Helpers.Normalizer

  # ============================================
  # normalize/2 - Auto-trim behavior
  # ============================================

  describe "normalize/2 auto-trim" do
    test "trims by default when no normalize or mappers option" do
      assert Normalizer.normalize("  hello  ", []) == "hello"
    end

    test "trims leading whitespace by default" do
      assert Normalizer.normalize("   hello", []) == "hello"
    end

    test "trims trailing whitespace by default" do
      assert Normalizer.normalize("hello   ", []) == "hello"
    end

    test "trims tabs and newlines by default" do
      assert Normalizer.normalize("\thello\n", []) == "hello"
    end

    test "disables auto-trim when trim: false" do
      assert Normalizer.normalize("  hello  ", trim: false) == "  hello  "
    end

    test "returns empty string after trimming whitespace-only value" do
      assert Normalizer.normalize("   ", []) == ""
    end

    test "leaves already-trimmed string unchanged" do
      assert Normalizer.normalize("hello", []) == "hello"
    end
  end

  # ============================================
  # normalize/2 - Legacy normalize option
  # ============================================

  describe "normalize/2 with normalize: atom" do
    test ":downcase lowercases the string" do
      assert Normalizer.normalize("HELLO", normalize: :downcase) == "hello"
    end

    test ":upcase uppercases the string" do
      assert Normalizer.normalize("hello", normalize: :upcase) == "HELLO"
    end

    test ":capitalize capitalizes first letter" do
      assert Normalizer.normalize("hello world", normalize: :capitalize) == "Hello world"
    end

    test ":titlecase capitalizes each word" do
      assert Normalizer.normalize("hello world foo", normalize: :titlecase) == "Hello World Foo"
    end

    test ":trim trims whitespace" do
      # Auto-trim already trims, but explicit :trim also works
      assert Normalizer.normalize("  hello  ", normalize: :trim) == "hello"
    end

    test ":squish trims and collapses spaces" do
      assert Normalizer.normalize("  hello   world  ", normalize: :squish) == "hello world"
    end

    test ":squish collapses tabs and newlines into single spaces" do
      assert Normalizer.normalize("hello\t\tworld\n\nfoo", normalize: :squish) == "hello world foo"
    end

    test ":slugify converts to URL-safe slug" do
      result = Normalizer.normalize("Hello World!", normalize: :slugify)
      assert result == "hello-world"
    end

    test ":alphanumeric_only removes non-alphanumeric chars" do
      assert Normalizer.normalize("hello-world_123!", normalize: :alphanumeric_only) ==
               "helloworld123"
    end

    test ":digits_only removes non-digit chars" do
      assert Normalizer.normalize("abc123def456", normalize: :digits_only) == "123456"
    end

    test "unknown normalizer atom passes value through" do
      assert Normalizer.normalize("hello", normalize: :unknown_thing) == "hello"
    end
  end

  describe "normalize/2 with normalize: list" do
    test "applies multiple normalizers in order" do
      assert Normalizer.normalize("  HELLO WORLD  ", normalize: [:trim, :downcase]) ==
               "hello world"
    end

    test "applies trim then slugify" do
      result = Normalizer.normalize("  Hello World!  ", normalize: [:trim, :slugify])
      assert result == "hello-world"
    end

    test "applies downcase then alphanumeric_only" do
      assert Normalizer.normalize("Hello-World!", normalize: [:downcase, :alphanumeric_only]) ==
               "helloworld"
    end

    test "empty normalizer list returns auto-trimmed value" do
      assert Normalizer.normalize("  hello  ", normalize: []) == "hello"
    end

    test "order matters - squish then upcase" do
      assert Normalizer.normalize("  hello   world  ", normalize: [:squish, :upcase]) ==
               "HELLO WORLD"
    end

    test "order matters - upcase then squish" do
      assert Normalizer.normalize("  HELLO   WORLD  ", normalize: [:upcase, :squish]) ==
               "HELLO WORLD"
    end
  end

  describe "normalize/2 with normalize: function" do
    test "applies a direct function" do
      assert Normalizer.normalize("hello", normalize: &String.reverse/1) == "olleh"
    end

    test "applies a custom anonymous function" do
      fun = fn value -> value <> "!" end
      assert Normalizer.normalize("hello", normalize: fun) == "hello!"
    end
  end

  describe "normalize/2 with normalize: {:custom, fun}" do
    test "applies custom function via tuple" do
      fun = fn value -> String.replace(value, "o", "0") end
      assert Normalizer.normalize("foo", normalize: {:custom, fun}) == "f00"
    end
  end

  describe "normalize/2 with normalize: {:slugify, opts}" do
    test "slugify with options list" do
      result = Normalizer.normalize("Hello World", normalize: {:slugify, separator: "_"})
      assert result == "hello_world"
    end
  end

  # ============================================
  # normalize/2 - Mappers option
  # ============================================

  describe "normalize/2 with mappers: list" do
    test "applies mapper functions in order" do
      mappers = [&String.trim/1, &String.downcase/1]
      assert Normalizer.normalize("  HELLO  ", mappers: mappers) == "hello"
    end

    test "mappers do NOT auto-trim" do
      # With mappers, no auto-trim - mappers control everything
      assert Normalizer.normalize("  hello  ", mappers: [&String.downcase/1]) == "  hello  "
    end

    test "single mapper function in list" do
      assert Normalizer.normalize("HELLO", mappers: [&String.downcase/1]) == "hello"
    end

    test "empty mapper list returns value unchanged" do
      assert Normalizer.normalize("  hello  ", mappers: []) == "  hello  "
    end

    test "supports atom shortcuts in mappers" do
      assert Normalizer.normalize("  HELLO  ", mappers: [:trim, :downcase]) == "hello"
    end

    test "supports mixed functions and atoms in mappers" do
      mappers = [:trim, &String.upcase/1]
      assert Normalizer.normalize("  hello  ", mappers: mappers) == "HELLO"
    end

    test "supports tuple format in mappers" do
      mappers = [:trim, {:slugify, [separator: "_"]}]
      assert Normalizer.normalize("  Hello World  ", mappers: mappers) == "hello_world"
    end

    test "unknown mapper type passes value through" do
      assert Normalizer.normalize("hello", mappers: [42]) == "hello"
    end
  end

  describe "normalize/2 with mappers: single mapper" do
    test "single function (not in list)" do
      assert Normalizer.normalize("HELLO", mappers: &String.downcase/1) == "hello"
    end

    test "single atom (not in list)" do
      assert Normalizer.normalize("  hello  ", mappers: :trim) == "hello"
    end
  end

  # ============================================
  # normalize/2 - Non-string values
  # ============================================

  describe "normalize/2 non-string values" do
    test "nil passes through" do
      assert Normalizer.normalize(nil, []) == nil
    end

    test "integer passes through" do
      assert Normalizer.normalize(42, []) == 42
    end

    test "atom passes through" do
      assert Normalizer.normalize(:hello, []) == :hello
    end

    test "list passes through" do
      assert Normalizer.normalize([1, 2, 3], []) == [1, 2, 3]
    end

    test "map passes through" do
      assert Normalizer.normalize(%{a: 1}, []) == %{a: 1}
    end
  end

  # ============================================
  # normalize/2 - Auto-trim + normalize interaction
  # ============================================

  describe "normalize/2 auto-trim + normalize combined" do
    test "auto-trims before applying normalize" do
      # Auto-trim removes whitespace, then downcase applies
      assert Normalizer.normalize("  HELLO  ", normalize: :downcase) == "hello"
    end

    test "auto-trim + squish" do
      # Auto-trim trims outer whitespace, then squish collapses inner
      assert Normalizer.normalize("  hello   world  ", normalize: :squish) == "hello world"
    end

    test "trim: false + normalize: :downcase preserves whitespace" do
      assert Normalizer.normalize("  HELLO  ", trim: false, normalize: :downcase) ==
               "  hello  "
    end
  end

  # ============================================
  # normalize_email/1
  # ============================================

  describe "normalize_email/1" do
    test "trims and lowercases email" do
      assert Normalizer.normalize_email("  User@Example.COM  ") == "user@example.com"
    end

    test "handles already-normalized email" do
      assert Normalizer.normalize_email("user@example.com") == "user@example.com"
    end

    test "handles uppercase email" do
      assert Normalizer.normalize_email("USER@EXAMPLE.COM") == "user@example.com"
    end

    test "handles nil" do
      assert Normalizer.normalize_email(nil) == nil
    end

    test "handles empty string" do
      assert Normalizer.normalize_email("") == ""
    end

    test "handles email with leading/trailing spaces only" do
      assert Normalizer.normalize_email("   ") == ""
    end

    test "preserves email structure" do
      assert Normalizer.normalize_email("  First.Last+tag@Sub.Example.COM  ") ==
               "first.last+tag@sub.example.com"
    end

    test "non-string passes through" do
      assert Normalizer.normalize_email(42) == 42
      assert Normalizer.normalize_email(:atom) == :atom
    end
  end

  # ============================================
  # normalize_phone/1
  # ============================================

  describe "normalize_phone/1" do
    test "strips non-digit chars except +" do
      assert Normalizer.normalize_phone("+1 (555) 123-4567") == "+15551234567"
    end

    test "handles dotted format" do
      assert Normalizer.normalize_phone("555.123.4567") == "5551234567"
    end

    test "handles dashes" do
      assert Normalizer.normalize_phone("555-123-4567") == "5551234567"
    end

    test "handles spaces" do
      assert Normalizer.normalize_phone("555 123 4567") == "5551234567"
    end

    test "preserves leading + for international numbers" do
      assert Normalizer.normalize_phone("+44 20 7946 0958") == "+442079460958"
    end

    test "handles nil" do
      assert Normalizer.normalize_phone(nil) == nil
    end

    test "handles empty string" do
      assert Normalizer.normalize_phone("") == ""
    end

    test "handles digits only" do
      assert Normalizer.normalize_phone("5551234567") == "5551234567"
    end

    test "strips letters" do
      assert Normalizer.normalize_phone("1-800-FLOWERS") == "1800"
    end

    test "non-string passes through" do
      assert Normalizer.normalize_phone(42) == 42
    end
  end

  # ============================================
  # normalize_url/1
  # ============================================

  describe "normalize_url/1" do
    test "trims and lowercases URL" do
      assert Normalizer.normalize_url("  HTTPS://Example.COM/Path  ") ==
               "https://example.com/path"
    end

    test "handles already-normalized URL" do
      assert Normalizer.normalize_url("https://example.com/path") ==
               "https://example.com/path"
    end

    test "handles nil" do
      assert Normalizer.normalize_url(nil) == nil
    end

    test "handles empty string" do
      assert Normalizer.normalize_url("") == ""
    end

    test "handles URL with query params" do
      assert Normalizer.normalize_url("  HTTPS://EXAMPLE.COM/Path?Key=Value  ") ==
               "https://example.com/path?key=value"
    end

    test "non-string passes through" do
      assert Normalizer.normalize_url(42) == 42
    end
  end

  # ============================================
  # normalize_slug/1
  # ============================================

  describe "normalize_slug/1" do
    test "converts to URL-safe slug" do
      assert Normalizer.normalize_slug("  Hello World!  ") == "hello-world"
    end

    test "collapses multiple hyphens" do
      assert Normalizer.normalize_slug("My  --  Post Title") == "my-post-title"
    end

    test "removes leading and trailing hyphens" do
      assert Normalizer.normalize_slug("--hello-world--") == "hello-world"
    end

    test "handles nil" do
      assert Normalizer.normalize_slug(nil) == nil
    end

    test "handles empty string" do
      assert Normalizer.normalize_slug("") == ""
    end

    test "handles whitespace only" do
      assert Normalizer.normalize_slug("   ") == ""
    end

    test "handles already-slugified string" do
      assert Normalizer.normalize_slug("hello-world") == "hello-world"
    end

    test "handles special characters" do
      assert Normalizer.normalize_slug("Hello @World #123") == "hello-world-123"
    end

    test "preserves underscores (word chars)" do
      result = Normalizer.normalize_slug("hello_world")
      # Underscores are \w characters, so they're kept
      assert result == "hello_world"
    end

    test "handles numbers" do
      assert Normalizer.normalize_slug("Post 42") == "post-42"
    end

    test "non-string passes through" do
      assert Normalizer.normalize_slug(42) == 42
      assert Normalizer.normalize_slug(nil) == nil
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "normalize/2 edge cases" do
    test "empty string with normalize options" do
      assert Normalizer.normalize("", normalize: :downcase) == ""
    end

    test "empty string with mappers" do
      assert Normalizer.normalize("", mappers: [&String.trim/1]) == ""
    end

    test "unicode string normalization" do
      assert Normalizer.normalize("  CAFÉ  ", normalize: :downcase) == "café"
    end

    test "unicode email normalization" do
      assert Normalizer.normalize_email("  ÜNÏCÖDÉ@EXAMPLE.COM  ") == "ünïcödé@example.com"
    end

    test "mappers option takes precedence over normalize" do
      # When mappers is present, normalize option is ignored
      result = Normalizer.normalize("HELLO", mappers: [:trim], normalize: :downcase)
      # mappers path: no auto-trim, just :trim is applied. :downcase is NOT applied.
      assert result == "HELLO"
    end

    test "chaining many normalizers" do
      result =
        Normalizer.normalize("  Hello   World  ", normalize: [:squish, :downcase, :slugify])

      assert result == "hello-world"
    end

    test "titlecase with extra spaces" do
      result = Normalizer.normalize("  hello   world  ", normalize: [:squish, :titlecase])
      assert result == "Hello World"
    end
  end
end
