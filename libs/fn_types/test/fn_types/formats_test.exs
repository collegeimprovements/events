defmodule FnTypes.FormatsTest do
  use ExUnit.Case, async: true

  alias FnTypes.Formats

  doctest Formats

  describe "email?/1" do
    test "validates correct email addresses" do
      assert Formats.email?("user@example.com")
      assert Formats.email?("user.name@example.com")
      assert Formats.email?("user+tag@example.co.uk")
      assert Formats.email?("user_name@example-domain.com")
      assert Formats.email?("123@example.com")
      assert Formats.email?("user@subdomain.example.com")
    end

    test "rejects invalid email addresses" do
      refute Formats.email?("invalid@")
      refute Formats.email?("@example.com")
      refute Formats.email?("user@")
      refute Formats.email?("user example@test.com")
      refute Formats.email?("user")
      refute Formats.email?("")
    end

    test "handles non-string input" do
      refute Formats.email?(nil)
      refute Formats.email?(123)
      refute Formats.email?(%{})
    end
  end

  describe "url?/1" do
    test "validates correct URLs" do
      assert Formats.url?("https://example.com")
      assert Formats.url?("http://example.com")
      assert Formats.url?("https://subdomain.example.com")
      assert Formats.url?("http://localhost:3000")
      assert Formats.url?("https://example.com/path")
      assert Formats.url?("https://example.com/path?query=value")
    end

    test "rejects invalid URLs" do
      refute Formats.url?("ftp://example.com")
      refute Formats.url?("example.com")
      refute Formats.url?("not-a-url")
      refute Formats.url?("")
    end

    test "handles non-string input" do
      refute Formats.url?(nil)
      refute Formats.url?(123)
    end
  end

  describe "uuid_v4?/1" do
    test "validates correct UUID v4" do
      assert Formats.uuid_v4?("550e8400-e29b-41d4-a716-446655440000")
      assert Formats.uuid_v4?("6ba7b810-9dad-41d1-80b4-00c04fd430c8")
    end

    test "rejects invalid UUID v4" do
      refute Formats.uuid_v4?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")  # v7
      refute Formats.uuid_v4?("not-a-uuid")
      refute Formats.uuid_v4?("550e8400-e29b-11d4-a716-446655440000")  # Wrong version
      refute Formats.uuid_v4?("")
    end

    test "handles non-string input" do
      refute Formats.uuid_v4?(nil)
      refute Formats.uuid_v4?(123)
    end
  end

  describe "uuid_v7?/1" do
    test "validates correct UUID v7" do
      assert Formats.uuid_v7?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")
      assert Formats.uuid_v7?("01893e5a-3b2f-7456-9abc-def012345678")
    end

    test "rejects invalid UUID v7" do
      refute Formats.uuid_v7?("550e8400-e29b-41d4-a716-446655440000")  # v4
      refute Formats.uuid_v7?("not-a-uuid")
      refute Formats.uuid_v7?("")
    end

    test "handles non-string input" do
      refute Formats.uuid_v7?(nil)
      refute Formats.uuid_v7?(123)
    end
  end

  describe "uuid?/1" do
    test "validates both v4 and v7 UUIDs" do
      assert Formats.uuid?("550e8400-e29b-41d4-a716-446655440000")  # v4
      assert Formats.uuid?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")  # v7
    end

    test "rejects invalid UUIDs" do
      refute Formats.uuid?("not-a-uuid")
      refute Formats.uuid?("550e8400-e29b-11d4-a716-446655440000")  # v1
      refute Formats.uuid?("")
    end

    test "handles non-string input" do
      refute Formats.uuid?(nil)
      refute Formats.uuid?(123)
    end
  end

  describe "slug?/1" do
    test "validates correct slugs" do
      assert Formats.slug?("my-blog-post")
      assert Formats.slug?("hello-world")
      assert Formats.slug?("post-123")
      assert Formats.slug?("a")
      assert Formats.slug?("123")
    end

    test "rejects invalid slugs" do
      refute Formats.slug?("Invalid-Slug")  # Uppercase
      refute Formats.slug?("no spaces")
      refute Formats.slug?("under_score")
      refute Formats.slug?("-leading-dash")
      refute Formats.slug?("trailing-dash-")
      refute Formats.slug?("")
    end

    test "handles non-string input" do
      refute Formats.slug?(nil)
      refute Formats.slug?(123)
    end
  end

  describe "username?/1" do
    test "validates correct usernames" do
      assert Formats.username?("john_doe")
      assert Formats.username?("User123")
      assert Formats.username?("user")
      assert Formats.username?("a_b_c")
      assert Formats.username?("123456")
      assert Formats.username?("username_with_30_characters_")
    end

    test "rejects invalid usernames" do
      refute Formats.username?("ab")  # Too short
      refute Formats.username?("a" <> String.duplicate("b", 30))  # Too long
      refute Formats.username?("user-name")  # Hyphen not allowed
      refute Formats.username?("user name")  # Space not allowed
      refute Formats.username?("")
    end

    test "handles non-string input" do
      refute Formats.username?(nil)
      refute Formats.username?(123)
    end
  end

  describe "phone?/1" do
    test "validates correct E.164 phone numbers" do
      assert Formats.phone?("+14155552671")  # USA
      assert Formats.phone?("+442071838750")  # UK
      assert Formats.phone?("+33123456789")  # France
      assert Formats.phone?("+861234567890")  # China
    end

    test "rejects invalid phone numbers" do
      refute Formats.phone?("555-1234")  # No country code
      refute Formats.phone?("+1")  # Too short
      refute Formats.phone?("14155552671")  # Missing +
      refute Formats.phone?("+0123456789")  # Country code can't start with 0
      refute Formats.phone?("")
    end

    test "handles non-string input" do
      refute Formats.phone?(nil)
      refute Formats.phone?(123)
    end
  end

  describe "ipv4?/1" do
    test "validates correct IPv4 addresses" do
      assert Formats.ipv4?("192.168.1.1")
      assert Formats.ipv4?("10.0.0.1")
      assert Formats.ipv4?("255.255.255.255")
      assert Formats.ipv4?("0.0.0.0")
      assert Formats.ipv4?("8.8.8.8")
    end

    test "rejects invalid IPv4 addresses" do
      refute Formats.ipv4?("256.1.1.1")  # Out of range
      refute Formats.ipv4?("192.168.1")  # Incomplete
      refute Formats.ipv4?("192.168.1.1.1")  # Too many octets
      refute Formats.ipv4?("not-an-ip")
      refute Formats.ipv4?("")
    end

    test "handles non-string input" do
      refute Formats.ipv4?(nil)
      refute Formats.ipv4?(123)
    end
  end

  describe "ipv6?/1" do
    test "validates correct IPv6 addresses" do
      assert Formats.ipv6?("2001:0db8:85a3:0000:0000:8a2e:0370:7334")
      assert Formats.ipv6?("::1")  # Loopback
      assert Formats.ipv6?("::")  # All zeros
    end

    test "rejects invalid IPv6 addresses" do
      refute Formats.ipv6?("192.168.1.1")  # IPv4
      refute Formats.ipv6?("not-an-ip")
      refute Formats.ipv6?("")
    end

    test "handles non-string input" do
      refute Formats.ipv6?(nil)
      refute Formats.ipv6?(123)
    end
  end

  describe "validate/2" do
    test "returns {:ok, value} for valid inputs" do
      assert {:ok, "user@example.com"} = Formats.validate(:email, "user@example.com")
      assert {:ok, "https://example.com"} = Formats.validate(:url, "https://example.com")
      assert {:ok, "my-slug"} = Formats.validate(:slug, "my-slug")
    end

    test "returns {:error, message} for invalid inputs" do
      assert {:error, "Invalid email format"} = Formats.validate(:email, "invalid")
      assert {:error, "Invalid URL format"} = Formats.validate(:url, "not-a-url")
      assert {:error, "Invalid slug format"} = Formats.validate(:slug, "Invalid Slug")
    end

    test "handles non-string input" do
      assert {:error, "Invalid email format"} = Formats.validate(:email, nil)
      assert {:error, "Invalid URL format"} = Formats.validate(:url, 123)
    end
  end

  describe "valid?/2" do
    test "returns true for valid formats" do
      assert Formats.valid?(:email, "user@example.com")
      assert Formats.valid?(:url, "https://example.com")
      assert Formats.valid?(:uuid_v4, "550e8400-e29b-41d4-a716-446655440000")
      assert Formats.valid?(:uuid_v7, "01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")
      assert Formats.valid?(:slug, "my-slug")
      assert Formats.valid?(:username, "john_doe")
      assert Formats.valid?(:phone, "+14155552671")
      assert Formats.valid?(:ipv4, "192.168.1.1")
      assert Formats.valid?(:ipv6, "::1")
    end

    test "returns false for invalid formats" do
      refute Formats.valid?(:email, "invalid")
      refute Formats.valid?(:url, "not-a-url")
      refute Formats.valid?(:slug, "Invalid Slug")
    end

    test "returns false for unknown formats" do
      refute Formats.valid?(:unknown_format, "anything")
    end
  end

  describe "regex/1" do
    test "returns regex patterns for all formats" do
      assert %Regex{} = Formats.regex(:email)
      assert %Regex{} = Formats.regex(:url)
      assert %Regex{} = Formats.regex(:uuid_v4)
      assert %Regex{} = Formats.regex(:uuid_v7)
      assert %Regex{} = Formats.regex(:uuid)
      assert %Regex{} = Formats.regex(:slug)
      assert %Regex{} = Formats.regex(:username)
      assert %Regex{} = Formats.regex(:phone)
      assert %Regex{} = Formats.regex(:ipv4)
      assert %Regex{} = Formats.regex(:ipv6)
    end

    test "regex patterns match expected values" do
      email_regex = Formats.regex(:email)
      assert Regex.match?(email_regex, "user@example.com")
      refute Regex.match?(email_regex, "invalid@")

      slug_regex = Formats.regex(:slug)
      assert Regex.match?(slug_regex, "my-slug")
      refute Regex.match?(slug_regex, "Invalid Slug")
    end
  end

  describe "email format edge cases" do
    test "handles plus addressing" do
      assert Formats.email?("user+tag@example.com")
      assert Formats.email?("user+filter+more@example.com")
    end

    test "handles dots in local part" do
      assert Formats.email?("first.last@example.com")
      assert Formats.email?("user.name.tag@example.com")
    end

    test "handles subdomains" do
      assert Formats.email?("user@mail.example.com")
      assert Formats.email?("user@a.b.c.example.com")
    end

    test "handles international TLDs" do
      assert Formats.email?("user@example.co.uk")
      assert Formats.email?("user@example.com.au")
    end

    test "rejects spaces and invalid characters" do
      refute Formats.email?("user name@example.com")
      refute Formats.email?("user@exam ple.com")
      refute Formats.email?("user<>@example.com")
    end
  end

  describe "UUID consistency check" do
    test "uuid?/1 accepts both v4 and v7" do
      v4_uuid = "550e8400-e29b-41d4-a716-446655440000"
      v7_uuid = "01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f"

      # Both should work with uuid?/1
      assert Formats.uuid?(v4_uuid)
      assert Formats.uuid?(v7_uuid)

      # But only match their specific versions
      assert Formats.uuid_v4?(v4_uuid)
      refute Formats.uuid_v7?(v4_uuid)

      refute Formats.uuid_v4?(v7_uuid)
      assert Formats.uuid_v7?(v7_uuid)
    end
  end

  describe "integration scenarios" do
    test "validates user registration data" do
      # Valid user data
      assert Formats.email?("john@example.com")
      assert Formats.username?("john_doe")
      assert Formats.url?("https://johndoe.com")

      # Invalid user data
      refute Formats.email?("not-an-email")
      refute Formats.username?("j")  # Too short
      refute Formats.url?("not-a-url")
    end

    test "validates API endpoints" do
      assert Formats.url?("https://api.example.com/v1/users")
      assert Formats.url?("http://localhost:4000/health")
      refute Formats.url?("ftp://files.example.com")
    end

    test "validates identifiers" do
      assert Formats.uuid?("550e8400-e29b-41d4-a716-446655440000")
      assert Formats.slug?("user-profile-123")
      refute Formats.uuid?("not-a-uuid")
      refute Formats.slug?("Invalid_Identifier")
    end
  end
end
