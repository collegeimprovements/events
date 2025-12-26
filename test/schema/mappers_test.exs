defmodule Events.Core.Schema.MappersTest do
  use Events.TestCase, async: true

  import OmSchema.Mappers

  describe "trim/0" do
    test "removes leading and trailing whitespace" do
      assert trim().("  hello  ") == "hello"
      assert trim().("hello") == "hello"
      assert trim().("  ") == ""
    end
  end

  describe "downcase/0" do
    test "converts string to lowercase" do
      assert downcase().("HELLO") == "hello"
      assert downcase().("Hello World") == "hello world"
      assert downcase().("hello") == "hello"
    end
  end

  describe "upcase/0" do
    test "converts string to uppercase" do
      assert upcase().("hello") == "HELLO"
      assert upcase().("Hello World") == "HELLO WORLD"
      assert upcase().("HELLO") == "HELLO"
    end
  end

  describe "capitalize/0" do
    test "capitalizes first letter" do
      assert capitalize().("hello world") == "Hello world"
      assert capitalize().("HELLO") == "Hello"
    end
  end

  describe "titlecase/0" do
    test "capitalizes first letter of each word" do
      assert titlecase().("hello world") == "Hello World"
      assert titlecase().("the quick brown fox") == "The Quick Brown Fox"
    end
  end

  describe "squish/0" do
    test "trims and collapses multiple spaces" do
      assert squish().("  hello   world  ") == "hello world"
      assert squish().("hello\t\tworld") == "hello world"
    end
  end

  describe "digits_only/0" do
    test "removes all non-numeric characters" do
      assert digits_only().("abc123def456") == "123456"
      assert digits_only().("(555) 123-4567") == "5551234567"
    end
  end

  describe "alphanumeric_only/0" do
    test "removes all non-alphanumeric characters" do
      assert alphanumeric_only().("hello-world_123!") == "helloworld123"
      assert alphanumeric_only().("test@example.com") == "testexamplecom"
    end
  end

  describe "replace/2" do
    test "replaces pattern with replacement" do
      mapper = replace(~r/-+/, "-")
      assert mapper.("hello---world") == "hello-world"
    end
  end

  describe "compose/1" do
    test "composes multiple mappers" do
      email_normalizer = compose([trim(), downcase()])
      assert email_normalizer.("  TEST@EXAMPLE.COM  ") == "test@example.com"
    end

    test "applies mappers left to right" do
      mapper = compose([trim(), upcase(), fn x -> x <> "!" end])
      assert mapper.("  hello  ") == "HELLO!"
    end
  end
end
