defmodule OmSchema.Validators.StringTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.String, as: StringValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :name, :string
      field :email, :string
      field :url, :string
      field :uuid_field, :string
      field :slug, :string
      field :hex_color, :string
      field :ip_address, :string
      field :code, :string
      field :status, :string
    end

    @fields [:name, :email, :url, :uuid_field, :slug, :hex_color, :ip_address, :code, :status]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # ============================================
  # Behaviour Callbacks
  # ============================================

  describe "field_types/0" do
    test "returns string-related types" do
      assert StringValidator.field_types() == [:string, :citext]
    end
  end

  describe "supported_options/0" do
    test "returns all supported option keys" do
      opts = StringValidator.supported_options()

      assert :min_length in opts
      assert :max_length in opts
      assert :length in opts
      assert :format in opts
      assert :in in opts
      assert :not_in in opts
      assert length(opts) == 6
    end
  end

  # ============================================
  # min_length validation
  # ============================================

  describe "validate/3 with min_length" do
    test "passes when string meets minimum length" do
      cs = changeset(%{name: "abc"}) |> StringValidator.validate(:name, min_length: 3)

      assert cs.valid?
      assert cs.errors[:name] == nil
    end

    test "passes when string exceeds minimum length" do
      cs = changeset(%{name: "abcdef"}) |> StringValidator.validate(:name, min_length: 3)

      assert cs.valid?
    end

    test "fails when string is below minimum length" do
      cs = changeset(%{name: "ab"}) |> StringValidator.validate(:name, min_length: 3)

      refute cs.valid?
      assert cs.errors[:name] != nil
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> StringValidator.validate(:name, min_length: 3)

      assert cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs =
        changeset(%{name: "ab"})
        |> StringValidator.validate(:name, min_length: {3, message: "too short"})

      refute cs.valid?
      {msg, _} = cs.errors[:name]
      assert msg =~ "too short"
    end

    test "boundary: exactly at min_length passes" do
      cs = changeset(%{name: "abc"}) |> StringValidator.validate(:name, min_length: 3)

      assert cs.valid?
    end

    test "boundary: one below min_length fails" do
      cs = changeset(%{name: "ab"}) |> StringValidator.validate(:name, min_length: 3)

      refute cs.valid?
    end

    test "single character passes min_length of 1" do
      cs = changeset(%{name: "a"}) |> StringValidator.validate(:name, min_length: 1)

      assert cs.valid?
    end
  end

  # ============================================
  # max_length validation
  # ============================================

  describe "validate/3 with max_length" do
    test "passes when string is under maximum length" do
      cs = changeset(%{name: "abc"}) |> StringValidator.validate(:name, max_length: 5)

      assert cs.valid?
    end

    test "passes when string is exactly at maximum length" do
      cs = changeset(%{name: "abcde"}) |> StringValidator.validate(:name, max_length: 5)

      assert cs.valid?
    end

    test "fails when string exceeds maximum length" do
      cs = changeset(%{name: "abcdef"}) |> StringValidator.validate(:name, max_length: 5)

      refute cs.valid?
      assert cs.errors[:name] != nil
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> StringValidator.validate(:name, max_length: 5)

      assert cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs =
        changeset(%{name: "abcdef"})
        |> StringValidator.validate(:name, max_length: {5, message: "too long"})

      refute cs.valid?
      {msg, _} = cs.errors[:name]
      assert msg =~ "too long"
    end

    test "boundary: one above max_length fails" do
      cs = changeset(%{name: "abcdef"}) |> StringValidator.validate(:name, max_length: 5)

      refute cs.valid?
    end

    test "empty string passes any max_length" do
      cs = changeset(%{name: ""}) |> StringValidator.validate(:name, max_length: 5)

      assert cs.valid?
    end
  end

  # ============================================
  # exact length validation
  # ============================================

  describe "validate/3 with length (exact)" do
    test "passes when string is exactly the required length" do
      cs = changeset(%{code: "ABCDE"}) |> StringValidator.validate(:code, length: 5)

      assert cs.valid?
    end

    test "fails when string is shorter than required length" do
      cs = changeset(%{code: "ABCD"}) |> StringValidator.validate(:code, length: 5)

      refute cs.valid?
    end

    test "fails when string is longer than required length" do
      cs = changeset(%{code: "ABCDEF"}) |> StringValidator.validate(:code, length: 5)

      refute cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> StringValidator.validate(:code, length: 5)

      assert cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs =
        changeset(%{code: "ABC"})
        |> StringValidator.validate(:code, length: {5, message: "must be exactly 5 chars"})

      refute cs.valid?
      {msg, _} = cs.errors[:code]
      assert msg =~ "must be exactly 5 chars"
    end
  end

  # ============================================
  # Combined length validations
  # ============================================

  describe "validate/3 with combined min_length and max_length" do
    test "passes when string is within range" do
      cs =
        changeset(%{name: "abcd"})
        |> StringValidator.validate(:name, min_length: 3, max_length: 10)

      assert cs.valid?
    end

    test "fails when below min in combined range" do
      cs =
        changeset(%{name: "ab"})
        |> StringValidator.validate(:name, min_length: 3, max_length: 10)

      refute cs.valid?
    end

    test "fails when above max in combined range" do
      cs =
        changeset(%{name: "abcdefghijk"})
        |> StringValidator.validate(:name, min_length: 3, max_length: 10)

      refute cs.valid?
    end
  end

  # ============================================
  # Named format: :email
  # ============================================

  describe "validate/3 with format: :email" do
    test "passes valid email" do
      cs = changeset(%{email: "user@example.com"}) |> StringValidator.validate(:email, format: :email)

      assert cs.valid?
    end

    test "fails email without @" do
      cs = changeset(%{email: "invalid"}) |> StringValidator.validate(:email, format: :email)

      refute cs.valid?
      {msg, _} = cs.errors[:email]
      assert msg == "must be a valid email"
    end

    test "fails email without domain" do
      cs = changeset(%{email: "user@"}) |> StringValidator.validate(:email, format: :email)

      refute cs.valid?
    end

    test "fails email without TLD" do
      cs = changeset(%{email: "user@domain"}) |> StringValidator.validate(:email, format: :email)

      refute cs.valid?
    end

    test "fails email with spaces" do
      cs = changeset(%{email: "user @example.com"}) |> StringValidator.validate(:email, format: :email)

      refute cs.valid?
    end

    test "passes email with subdomains" do
      cs =
        changeset(%{email: "user@sub.domain.com"})
        |> StringValidator.validate(:email, format: :email)

      assert cs.valid?
    end

    test "passes when field is nil" do
      cs = changeset(%{}) |> StringValidator.validate(:email, format: :email)

      assert cs.valid?
    end
  end

  # ============================================
  # Named format: :url
  # ============================================

  describe "validate/3 with format: :url" do
    test "passes valid http URL" do
      cs = changeset(%{url: "http://example.com"}) |> StringValidator.validate(:url, format: :url)

      assert cs.valid?
    end

    test "passes valid https URL" do
      cs = changeset(%{url: "https://example.com"}) |> StringValidator.validate(:url, format: :url)

      assert cs.valid?
    end

    test "fails URL without protocol" do
      cs = changeset(%{url: "example.com"}) |> StringValidator.validate(:url, format: :url)

      refute cs.valid?
      {msg, _} = cs.errors[:url]
      assert msg == "must be a valid URL"
    end

    test "fails URL with ftp protocol" do
      cs = changeset(%{url: "ftp://example.com"}) |> StringValidator.validate(:url, format: :url)

      refute cs.valid?
    end
  end

  # ============================================
  # Named format: :uuid
  # ============================================

  describe "validate/3 with format: :uuid" do
    test "passes valid lowercase UUID" do
      cs =
        changeset(%{uuid_field: "550e8400-e29b-41d4-a716-446655440000"})
        |> StringValidator.validate(:uuid_field, format: :uuid)

      assert cs.valid?
    end

    test "passes valid uppercase UUID" do
      cs =
        changeset(%{uuid_field: "550E8400-E29B-41D4-A716-446655440000"})
        |> StringValidator.validate(:uuid_field, format: :uuid)

      assert cs.valid?
    end

    test "fails invalid UUID" do
      cs =
        changeset(%{uuid_field: "not-a-uuid"})
        |> StringValidator.validate(:uuid_field, format: :uuid)

      refute cs.valid?
      {msg, _} = cs.errors[:uuid_field]
      assert msg == "must be a valid UUID"
    end

    test "fails UUID without dashes" do
      cs =
        changeset(%{uuid_field: "550e8400e29b41d4a716446655440000"})
        |> StringValidator.validate(:uuid_field, format: :uuid)

      refute cs.valid?
    end
  end

  # ============================================
  # Named format: :slug
  # ============================================

  describe "validate/3 with format: :slug" do
    test "passes valid slug" do
      cs = changeset(%{slug: "my-slug-123"}) |> StringValidator.validate(:slug, format: :slug)

      assert cs.valid?
    end

    test "fails slug with uppercase" do
      cs = changeset(%{slug: "My-Slug"}) |> StringValidator.validate(:slug, format: :slug)

      refute cs.valid?
      {msg, _} = cs.errors[:slug]
      assert msg == "must be a valid slug"
    end

    test "fails slug with spaces" do
      cs = changeset(%{slug: "my slug"}) |> StringValidator.validate(:slug, format: :slug)

      refute cs.valid?
    end

    test "fails slug with special characters" do
      cs = changeset(%{slug: "my_slug!"}) |> StringValidator.validate(:slug, format: :slug)

      refute cs.valid?
    end

    test "passes slug with only numbers" do
      cs = changeset(%{slug: "12345"}) |> StringValidator.validate(:slug, format: :slug)

      assert cs.valid?
    end
  end

  # ============================================
  # Named format: :hex_color
  # ============================================

  describe "validate/3 with format: :hex_color" do
    test "passes valid lowercase hex color" do
      cs =
        changeset(%{hex_color: "#ff0000"})
        |> StringValidator.validate(:hex_color, format: :hex_color)

      assert cs.valid?
    end

    test "passes valid uppercase hex color" do
      cs =
        changeset(%{hex_color: "#FF0000"})
        |> StringValidator.validate(:hex_color, format: :hex_color)

      assert cs.valid?
    end

    test "fails hex color without hash" do
      cs =
        changeset(%{hex_color: "ff0000"})
        |> StringValidator.validate(:hex_color, format: :hex_color)

      refute cs.valid?
      {msg, _} = cs.errors[:hex_color]
      assert msg == "must be a valid hex color"
    end

    test "fails 3-digit hex color" do
      cs =
        changeset(%{hex_color: "#f00"})
        |> StringValidator.validate(:hex_color, format: :hex_color)

      refute cs.valid?
    end

    test "fails invalid hex characters" do
      cs =
        changeset(%{hex_color: "#gggggg"})
        |> StringValidator.validate(:hex_color, format: :hex_color)

      refute cs.valid?
    end
  end

  # ============================================
  # Named format: :ip
  # ============================================

  describe "validate/3 with format: :ip" do
    test "passes valid IP address" do
      cs =
        changeset(%{ip_address: "192.168.1.1"})
        |> StringValidator.validate(:ip_address, format: :ip)

      assert cs.valid?
    end

    test "fails IP with letters" do
      cs =
        changeset(%{ip_address: "abc.def.ghi.jkl"})
        |> StringValidator.validate(:ip_address, format: :ip)

      refute cs.valid?
      {msg, _} = cs.errors[:ip_address]
      assert msg == "must be a valid IP address"
    end

    test "fails IP with too few octets" do
      cs =
        changeset(%{ip_address: "192.168.1"})
        |> StringValidator.validate(:ip_address, format: :ip)

      refute cs.valid?
    end
  end

  # ============================================
  # Named format with custom inline message
  # ============================================

  describe "validate/3 with format tuple and custom message" do
    test "uses inline message for named format" do
      cs =
        changeset(%{email: "invalid"})
        |> StringValidator.validate(:email, format: {:email, message: "custom email error"})

      refute cs.valid?
      {msg, _} = cs.errors[:email]
      assert msg == "custom email error"
    end
  end

  # ============================================
  # Regex format
  # ============================================

  describe "validate/3 with format: regex" do
    test "passes when value matches regex" do
      cs =
        changeset(%{code: "ABC123"})
        |> StringValidator.validate(:code, format: ~r/^[A-Z]+\d+$/)

      assert cs.valid?
    end

    test "fails when value does not match regex" do
      cs =
        changeset(%{code: "abc123"})
        |> StringValidator.validate(:code, format: ~r/^[A-Z]+\d+$/)

      refute cs.valid?
    end

    test "passes when field is nil" do
      cs = changeset(%{}) |> StringValidator.validate(:code, format: ~r/^[A-Z]+$/)

      assert cs.valid?
    end

    test "accepts regex tuple with custom message" do
      cs =
        changeset(%{code: "abc"})
        |> StringValidator.validate(:code, format: {~r/^[A-Z]+$/, message: "uppercase only"})

      refute cs.valid?
      {msg, _} = cs.errors[:code]
      assert msg == "uppercase only"
    end
  end

  # ============================================
  # :in (inclusion) validation
  # ============================================

  describe "validate/3 with in" do
    test "passes when value is in list" do
      cs =
        changeset(%{status: "active"})
        |> StringValidator.validate(:status, in: ["active", "inactive", "pending"])

      assert cs.valid?
    end

    test "fails when value is not in list" do
      cs =
        changeset(%{status: "unknown"})
        |> StringValidator.validate(:status, in: ["active", "inactive", "pending"])

      refute cs.valid?
      assert cs.errors[:status] != nil
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> StringValidator.validate(:status, in: ["active", "inactive"])

      assert cs.valid?
    end
  end

  # ============================================
  # :not_in (exclusion) validation
  # ============================================

  describe "validate/3 with not_in" do
    test "passes when value is not in exclusion list" do
      cs =
        changeset(%{status: "active"})
        |> StringValidator.validate(:status, not_in: ["banned", "deleted"])

      assert cs.valid?
    end

    test "fails when value is in exclusion list" do
      cs =
        changeset(%{status: "banned"})
        |> StringValidator.validate(:status, not_in: ["banned", "deleted"])

      refute cs.valid?
      assert cs.errors[:status] != nil
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> StringValidator.validate(:status, not_in: ["banned"])

      assert cs.valid?
    end
  end

  # ============================================
  # No options (passthrough)
  # ============================================

  describe "validate/3 with no relevant options" do
    test "returns changeset unchanged when no string options provided" do
      cs = changeset(%{name: "hello"}) |> StringValidator.validate(:name, [])

      assert cs.valid?
    end
  end

  # ============================================
  # Unknown format name fallback
  # ============================================

  describe "validate/3 with unknown named format" do
    test "uses fallback regex for unknown format name" do
      # Unknown format uses ~r/./ which matches any single character
      cs =
        changeset(%{name: "anything"})
        |> StringValidator.validate(:name, format: :unknown_format)

      assert cs.valid?
    end
  end

  # ============================================
  # Custom :message option
  # ============================================

  describe "validate/3 with global :message option" do
    test "uses global message for min_length" do
      cs =
        changeset(%{name: "ab"})
        |> StringValidator.validate(:name, min_length: 3, message: "custom length error")

      refute cs.valid?
      {msg, _} = cs.errors[:name]
      assert msg == "custom length error"
    end

    test "uses global message for max_length" do
      cs =
        changeset(%{name: "abcdef"})
        |> StringValidator.validate(:name, max_length: 3, message: "custom length error")

      refute cs.valid?
      {msg, _} = cs.errors[:name]
      assert msg == "custom length error"
    end
  end
end
