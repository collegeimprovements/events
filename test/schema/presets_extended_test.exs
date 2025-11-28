defmodule Events.Schema.PresetsExtendedTest do
  use Events.TestCase, async: true

  import Events.Schema.TestHelpers
  import Events.Schema.Presets

  describe "zip_code/1" do
    test "validates US zip codes" do
      assert_valid("12345", :string, zip_code())
      assert_valid("12345-6789", :string, zip_code())
      assert_invalid("1234", :string, zip_code())
      assert_invalid("123456", :string, zip_code())
      assert_invalid("12345-67", :string, zip_code())
    end
  end

  describe "ipv4/1" do
    test "validates IPv4 addresses" do
      assert_valid("192.168.1.1", :string, ipv4())
      assert_valid("10.0.0.0", :string, ipv4())
      assert_valid("255.255.255.255", :string, ipv4())
      assert_invalid("192.168.1", :string, ipv4())
      assert_invalid("192.168.1.256", :string, ipv4())
      assert_invalid("192.168.1.1.1", :string, ipv4())
    end
  end

  describe "mac_address/1" do
    test "validates MAC addresses" do
      assert_valid("00:1B:44:11:3A:B7", :string, mac_address())
      assert_valid("00-1B-44-11-3A-B7", :string, mac_address())
      assert_invalid("00:1B:44:11:3A", :string, mac_address())
      assert_invalid("00:1B:44:11:3A:B7:C8", :string, mac_address())
      assert_invalid("GG:1B:44:11:3A:B7", :string, mac_address())
    end
  end

  describe "hex_color/1" do
    test "validates hex color codes" do
      assert_valid("#FF0000", :string, hex_color())
      assert_valid("#00FF00", :string, hex_color())
      assert_valid("#0000FF", :string, hex_color())
      # With alpha
      assert_valid("#FF0000AA", :string, hex_color())
      assert_invalid("#FF00", :string, hex_color())
      assert_invalid("#GGGGGG", :string, hex_color())
      # Missing #
      assert_invalid("FF0000", :string, hex_color())
    end
  end

  describe "credit_card/1" do
    test "validates credit card numbers" do
      # 16 digits
      assert_valid("4532015112830366", :string, credit_card())
      # 16 digits
      assert_valid("6011111111111117", :string, credit_card())
      # 16 digits
      assert_valid("5105105105105100", :string, credit_card())
      # 13 digits (Visa)
      assert_valid("4222222222222", :string, credit_card())
      # 12 digits (too short)
      assert_invalid("123456789012", :string, credit_card())
      # 20 digits (too long)
      assert_invalid("12345678901234567890", :string, credit_card())
    end

    test "normalizes credit card by removing spaces" do
      result = test_normalization("4532 0151 1283 0366", credit_card())
      assert result == "4532015112830366"
    end
  end

  describe "latitude/1 and longitude/1" do
    test "validates latitude" do
      assert_valid(0, :float, latitude())
      assert_valid(45.5, :float, latitude())
      assert_valid(-45.5, :float, latitude())
      assert_valid(90.0, :float, latitude())
      assert_valid(-90.0, :float, latitude())
      assert_invalid(90.1, :float, latitude())
      assert_invalid(-90.1, :float, latitude())
    end

    test "validates longitude" do
      assert_valid(0, :float, longitude())
      assert_valid(122.5, :float, longitude())
      assert_valid(-122.5, :float, longitude())
      assert_valid(180.0, :float, longitude())
      assert_valid(-180.0, :float, longitude())
      assert_invalid(180.1, :float, longitude())
      assert_invalid(-180.1, :float, longitude())
    end
  end

  describe "age/1" do
    test "validates age" do
      assert_valid(0, :integer, age())
      assert_valid(25, :integer, age())
      assert_valid(100, :integer, age())
      assert_valid(150, :integer, age())
      assert_invalid(-1, :integer, age())
      assert_invalid(151, :integer, age())
    end
  end

  describe "rating/1" do
    test "validates ratings 1-5" do
      assert_valid(1, :integer, rating())
      assert_valid(2, :integer, rating())
      assert_valid(3, :integer, rating())
      assert_valid(4, :integer, rating())
      assert_valid(5, :integer, rating())
      assert_invalid(0, :integer, rating())
      assert_invalid(6, :integer, rating())
    end
  end

  describe "country_code/1" do
    test "validates ISO 3166-1 alpha-2 country codes" do
      assert_valid("US", :string, country_code())
      assert_valid("GB", :string, country_code())
      assert_valid("FR", :string, country_code())
      assert_valid("JP", :string, country_code())
      assert_invalid("USA", :string, country_code())
      assert_invalid("U", :string, country_code())
      assert_invalid("12", :string, country_code())
    end

    test "normalizes to uppercase" do
      # country_code() returns full opts, so we need to pass them all
      result = test_normalization("us", country_code())
      assert result == "US"
    end
  end

  describe "currency_code/1" do
    test "validates ISO 4217 currency codes" do
      assert_valid("USD", :string, currency_code())
      assert_valid("EUR", :string, currency_code())
      assert_valid("GBP", :string, currency_code())
      assert_valid("JPY", :string, currency_code())
      assert_invalid("US", :string, currency_code())
      assert_invalid("USDD", :string, currency_code())
      assert_invalid("123", :string, currency_code())
    end
  end

  describe "domain/1" do
    test "validates domain names" do
      assert_valid("example.com", :string, domain())
      assert_valid("sub.example.com", :string, domain())
      assert_valid("deep.sub.example.com", :string, domain())
      assert_valid("example.co.uk", :string, domain())
      assert_invalid("example", :string, domain())
      assert_invalid(".com", :string, domain())
      assert_invalid("example.", :string, domain())
    end

    test "normalizes to lowercase" do
      # domain() returns full opts, so we need to pass them all
      result = test_normalization("EXAMPLE.COM", domain())
      assert result == "example.com"
    end
  end

  describe "ethereum_address/1" do
    test "validates Ethereum addresses" do
      assert_valid("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb4", :string, ethereum_address())
      assert_valid("0x0000000000000000000000000000000000000000", :string, ethereum_address())
      # Too short
      assert_invalid("0x742d35Cc6634C0532925a3b844Bc9e7595f0bE", :string, ethereum_address())
      # Missing 0x
      assert_invalid("742d35Cc6634C0532925a3b844Bc9e7595f0bEb4", :string, ethereum_address())
      # Invalid chars
      assert_invalid("0xGGGG35Cc6634C0532925a3b844Bc9e7595f0bEb4", :string, ethereum_address())
    end
  end

  describe "semver/1" do
    test "validates semantic versions" do
      assert_valid("1.0.0", :string, semver())
      assert_valid("v1.0.0", :string, semver())
      assert_valid("2.1.3-alpha", :string, semver())
      assert_valid("1.0.0-beta.1", :string, semver())
      assert_valid("1.0.0+build.123", :string, semver())
      assert_valid("1.2.3-beta.1+build.456", :string, semver())
      assert_invalid("1.0", :string, semver())
      assert_invalid("1", :string, semver())
      assert_invalid("v1", :string, semver())
    end
  end

  describe "jwt/1" do
    test "validates JWT tokens" do
      valid_jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

      assert_valid(valid_jwt, :string, jwt())
      assert_invalid("not.a.jwt", :string, jwt())
      assert_invalid("missing.parts", :string, jwt())
      assert_invalid("too.many.parts.here", :string, jwt())
    end
  end

  describe "hashtag/1" do
    test "validates hashtags" do
      assert_valid("#elixir", :string, hashtag())
      assert_valid("#ElixirLang", :string, hashtag())
      assert_valid("#coding2023", :string, hashtag())
      assert_invalid("#", :string, hashtag())
      # Must start with letter
      assert_invalid("#123", :string, hashtag())
      # Missing #
      assert_invalid("elixir", :string, hashtag())
    end

    test "normalizes to lowercase" do
      result = test_normalization("#ElixirLang", hashtag())
      assert result == "#elixirlang"
    end
  end

  describe "social_handle/1" do
    test "validates social media handles" do
      assert_valid("@username", :string, social_handle())
      assert_valid("username", :string, social_handle())
      assert_valid("user_name", :string, social_handle())
      assert_valid("user123", :string, social_handle())
      # No hyphens
      assert_invalid("user-name", :string, social_handle())
      # No dots
      assert_invalid("user.name", :string, social_handle())
    end

    test "normalizes by removing @ and lowercasing" do
      result = test_normalization("@UserName", social_handle())
      assert result == "username"
    end
  end

  describe "iban/1" do
    test "validates IBAN format" do
      assert_valid("GB82WEST12345698765432", :string, iban())
      assert_valid("DE89370400440532013000", :string, iban())
      assert_valid("FR1420041010050500013M02606", :string, iban())
      # Too short
      assert_invalid("GB82WEST123456", :string, iban())
      assert_invalid("INVALID", :string, iban())
    end

    test "normalizes by removing spaces and uppercasing" do
      result = test_normalization("gb82 west 1234 5698 7654 32", iban())
      assert result == "GB82WEST12345698765432"
    end
  end
end
