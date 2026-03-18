defmodule OmSchema.ValidatorsExtendedTest do
  @moduledoc """
  Tests for OmSchema.ValidatorsExtended - Extended validators with
  normalizers, auto_trim, and enhanced validations.

  Covers:
  - validate_field/3 (comprehensive field validation with normalization)
  - validate_email/3 (email normalization + format)
  - validate_url/3 (URL normalization + format)
  - validate_phone/3 (phone normalization + format)
  - validate_money/3 (monetary amount with precision/scale)
  - validate_percentage/3 (0-100 range)
  - validate_slug/3 (slug normalization + format)
  - validate_uuid/3 (UUID format)
  - validate_json/3 (map validation with key constraints)
  - validate_enum/4 (enum inclusion)
  - validate_array/3 (array length, uniqueness)
  - validate_boolean/3 (acceptance)
  - validate_if/5 and validate_unless/5 (conditional validation)
  - validate_confirmation/3 (cross-field matching)
  - validate_comparison/4 (cross-field comparison)
  - validate_exclusive/3 (mutual exclusion)
  """

  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias OmSchema.ValidatorsExtended

  # ============================================
  # Test Schema
  # ============================================

  defmodule TestSchemaExtended do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
      field :email, :string
      field :url, :string
      field :phone, :string
      field :age, :integer
      field :price, :decimal
      field :discount, :float
      field :status, :string
      field :slug, :string
      field :uuid_field, :string
      field :metadata, :map
      field :tags, {:array, :string}
      field :active, :boolean
      field :password, :string
      field :password_confirmation, :string
      field :start_date, :date
      field :end_date, :date
      field :alt_email, :string
      field :alt_phone, :string
    end
  end

  # Schema with a table source, required for unique_constraint tests
  defmodule TestSchemaWithSource do
    use Ecto.Schema

    schema "test_extended" do
      field :email, :string
      field :phone, :string
    end
  end

  @all_fields [
    :name, :email, :url, :phone, :age, :price, :discount, :status,
    :slug, :uuid_field, :metadata, :tags, :active, :password,
    :password_confirmation, :start_date, :end_date, :alt_email, :alt_phone
  ]

  defp changeset(attrs) do
    %TestSchemaExtended{}
    |> cast(attrs, @all_fields)
  end

  defp source_changeset(attrs) do
    %TestSchemaWithSource{}
    |> cast(attrs, [:email, :phone])
  end

  defp errors_on(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end

  # ============================================
  # validate_field/3 - Comprehensive Field Validation
  # ============================================

  describe "validate_field/3 with required option" do
    test "adds error when required field is missing" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_field(:name, required: true)

      refute cs.valid?
      assert errors_on(cs, :name) != []
    end

    test "passes when required field is present" do
      cs = changeset(%{name: "Alice"}) |> ValidatorsExtended.validate_field(:name, required: true)

      assert cs.valid?
    end

    test "does not require field when required is not set" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_field(:name)

      assert cs.valid?
    end
  end

  describe "validate_field/3 auto_trim" do
    test "trims string fields by default" do
      cs = changeset(%{name: "  hello  "}) |> ValidatorsExtended.validate_field(:name)

      assert get_change(cs, :name) == "hello"
    end

    test "does not trim when auto_trim: false" do
      cs =
        changeset(%{name: "  hello  "})
        |> ValidatorsExtended.validate_field(:name, auto_trim: false)

      assert get_change(cs, :name) == "  hello  "
    end
  end

  describe "validate_field/3 string normalization" do
    test "lowercases with lowercase: true" do
      cs =
        changeset(%{name: "  HELLO  "})
        |> ValidatorsExtended.validate_field(:name, lowercase: true)

      assert get_change(cs, :name) == "hello"
    end

    test "uppercases with uppercase: true" do
      cs =
        changeset(%{name: "  hello  "})
        |> ValidatorsExtended.validate_field(:name, uppercase: true)

      assert get_change(cs, :name) == "HELLO"
    end

    test "capitalizes with capitalize: true" do
      cs =
        changeset(%{name: "  hello world  "})
        |> ValidatorsExtended.validate_field(:name, capitalize: true)

      # String.capitalize only capitalizes the first letter of the entire string
      assert get_change(cs, :name) == "Hello world"
    end
  end

  describe "validate_field/3 custom normalizer" do
    test "applies custom normalizer function" do
      cs =
        changeset(%{name: "hello world"})
        |> ValidatorsExtended.validate_field(:name, normalizer: &String.upcase/1)

      assert get_change(cs, :name) == "HELLO WORLD"
    end

    test "custom normalizer takes precedence over default" do
      cs =
        changeset(%{name: "  HELLO  "})
        |> ValidatorsExtended.validate_field(:name, normalizer: &String.reverse/1)

      # Custom normalizer is applied directly, no auto_trim
      assert get_change(cs, :name) == "  OLLEH  "
    end
  end

  describe "validate_field/3 trim_whitespace option" do
    test "trims when trim_whitespace: true" do
      cs =
        changeset(%{name: "  hello  "})
        |> ValidatorsExtended.validate_field(:name, trim_whitespace: true)

      assert get_change(cs, :name) == "hello"
    end

    test "does not trim with trim_whitespace: false (but auto_trim still applies for strings)" do
      cs =
        changeset(%{name: "  hello  "})
        |> ValidatorsExtended.validate_field(:name, trim_whitespace: false)

      # auto_trim defaults to true for strings
      assert get_change(cs, :name) == "hello"
    end
  end

  describe "validate_field/3 format option" do
    test "validates against regex pattern" do
      cs =
        changeset(%{name: "abc123"})
        |> ValidatorsExtended.validate_field(:name, format: ~r/^[a-z]+$/)

      refute cs.valid?
      assert errors_on(cs, :name) != []
    end

    test "passes when format matches" do
      cs =
        changeset(%{name: "abc"})
        |> ValidatorsExtended.validate_field(:name, format: ~r/^[a-z]+$/)

      assert cs.valid?
    end
  end

  describe "validate_field/3 string length (min/max)" do
    test "validates minimum string length" do
      cs =
        changeset(%{name: "ab"})
        |> ValidatorsExtended.validate_field(:name, min: 3)

      refute cs.valid?
      assert errors_on(cs, :name) != []
    end

    test "passes at minimum length" do
      cs =
        changeset(%{name: "abc"})
        |> ValidatorsExtended.validate_field(:name, min: 3)

      assert cs.valid?
    end

    test "validates maximum string length" do
      cs =
        changeset(%{name: "abcdef"})
        |> ValidatorsExtended.validate_field(:name, max: 5)

      refute cs.valid?
    end

    test "passes at maximum length" do
      cs =
        changeset(%{name: "abcde"})
        |> ValidatorsExtended.validate_field(:name, max: 5)

      assert cs.valid?
    end

    test "validates both min and max" do
      cs_short =
        changeset(%{name: "ab"})
        |> ValidatorsExtended.validate_field(:name, min: 3, max: 10)

      cs_long =
        changeset(%{name: "abcdefghijk"})
        |> ValidatorsExtended.validate_field(:name, min: 3, max: 10)

      cs_ok =
        changeset(%{name: "hello"})
        |> ValidatorsExtended.validate_field(:name, min: 3, max: 10)

      refute cs_short.valid?
      refute cs_long.valid?
      assert cs_ok.valid?
    end
  end

  describe "validate_field/3 number range (gt/gte/lt/lte/min/max)" do
    test "validates greater than" do
      cs = changeset(%{age: 5}) |> ValidatorsExtended.validate_field(:age, gt: 5)

      refute cs.valid?
    end

    test "passes greater than" do
      cs = changeset(%{age: 6}) |> ValidatorsExtended.validate_field(:age, gt: 5)

      assert cs.valid?
    end

    test "validates greater than or equal to" do
      cs = changeset(%{age: 17}) |> ValidatorsExtended.validate_field(:age, gte: 18)

      refute cs.valid?
    end

    test "passes at gte boundary" do
      cs = changeset(%{age: 18}) |> ValidatorsExtended.validate_field(:age, gte: 18)

      assert cs.valid?
    end

    test "validates less than" do
      cs = changeset(%{age: 100}) |> ValidatorsExtended.validate_field(:age, lt: 100)

      refute cs.valid?
    end

    test "passes less than" do
      cs = changeset(%{age: 99}) |> ValidatorsExtended.validate_field(:age, lt: 100)

      assert cs.valid?
    end

    test "validates less than or equal to" do
      cs = changeset(%{age: 121}) |> ValidatorsExtended.validate_field(:age, lte: 120)

      refute cs.valid?
    end

    test "passes at lte boundary" do
      cs = changeset(%{age: 120}) |> ValidatorsExtended.validate_field(:age, lte: 120)

      assert cs.valid?
    end

    test "validates min for numbers (same as gte)" do
      cs = changeset(%{age: 17}) |> ValidatorsExtended.validate_field(:age, min: 18)

      refute cs.valid?
    end

    test "validates max for numbers (same as lte)" do
      cs = changeset(%{age: 121}) |> ValidatorsExtended.validate_field(:age, max: 120)

      refute cs.valid?
    end

    test "validates float range" do
      cs = changeset(%{discount: -0.5}) |> ValidatorsExtended.validate_field(:discount, gte: 0.0)

      refute cs.valid?
    end

    test "passes float in range" do
      cs =
        changeset(%{discount: 0.5})
        |> ValidatorsExtended.validate_field(:discount, gte: 0.0, lte: 1.0)

      assert cs.valid?
    end

    test "validates decimal range" do
      cs =
        changeset(%{price: Decimal.new("-1")})
        |> ValidatorsExtended.validate_field(:price, gte: 0)

      refute cs.valid?
    end
  end

  describe "validate_field/3 comparison flags (positive/non_negative/negative/non_positive)" do
    test "positive rejects zero" do
      cs = changeset(%{age: 0}) |> ValidatorsExtended.validate_field(:age, positive: true)

      refute cs.valid?
    end

    test "positive rejects negative" do
      cs = changeset(%{age: -1}) |> ValidatorsExtended.validate_field(:age, positive: true)

      refute cs.valid?
    end

    test "positive passes for positive value" do
      cs = changeset(%{age: 1}) |> ValidatorsExtended.validate_field(:age, positive: true)

      assert cs.valid?
    end

    test "positive: false does not validate" do
      cs = changeset(%{age: -1}) |> ValidatorsExtended.validate_field(:age, positive: false)

      assert cs.valid?
    end

    test "non_negative rejects negative" do
      cs = changeset(%{age: -1}) |> ValidatorsExtended.validate_field(:age, non_negative: true)

      refute cs.valid?
    end

    test "non_negative passes zero" do
      cs = changeset(%{age: 0}) |> ValidatorsExtended.validate_field(:age, non_negative: true)

      assert cs.valid?
    end

    test "non_negative passes positive" do
      cs = changeset(%{age: 5}) |> ValidatorsExtended.validate_field(:age, non_negative: true)

      assert cs.valid?
    end

    test "negative rejects zero" do
      cs = changeset(%{age: 0}) |> ValidatorsExtended.validate_field(:age, negative: true)

      refute cs.valid?
    end

    test "negative rejects positive" do
      cs = changeset(%{age: 1}) |> ValidatorsExtended.validate_field(:age, negative: true)

      refute cs.valid?
    end

    test "negative passes for negative value" do
      cs = changeset(%{age: -1}) |> ValidatorsExtended.validate_field(:age, negative: true)

      assert cs.valid?
    end

    test "non_positive rejects positive" do
      cs = changeset(%{age: 1}) |> ValidatorsExtended.validate_field(:age, non_positive: true)

      refute cs.valid?
    end

    test "non_positive passes zero" do
      cs = changeset(%{age: 0}) |> ValidatorsExtended.validate_field(:age, non_positive: true)

      assert cs.valid?
    end

    test "non_positive passes negative" do
      cs = changeset(%{age: -1}) |> ValidatorsExtended.validate_field(:age, non_positive: true)

      assert cs.valid?
    end
  end

  describe "validate_field/3 inclusion/exclusion" do
    test "validates inclusion with :in option" do
      cs =
        changeset(%{status: "unknown"})
        |> ValidatorsExtended.validate_field(:status, in: ["active", "inactive"])

      refute cs.valid?
    end

    test "passes when value is in allowed list" do
      cs =
        changeset(%{status: "active"})
        |> ValidatorsExtended.validate_field(:status, in: ["active", "inactive"])

      assert cs.valid?
    end

    test "validates exclusion with :not_in option" do
      cs =
        changeset(%{status: "banned"})
        |> ValidatorsExtended.validate_field(:status, not_in: ["banned", "deleted"])

      refute cs.valid?
    end

    test "passes when value is not in forbidden list" do
      cs =
        changeset(%{status: "active"})
        |> ValidatorsExtended.validate_field(:status, not_in: ["banned", "deleted"])

      assert cs.valid?
    end
  end

  describe "validate_field/3 unique option" do
    test "adds unique constraint when unique: true" do
      cs =
        source_changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_field(:email, unique: true)

      # unique_constraint adds to changeset.constraints, not errors
      assert Enum.any?(cs.constraints, fn c -> c.field == :email end)
    end

    test "does not add constraint when unique is not set" do
      cs =
        source_changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_field(:email)

      refute Enum.any?(cs.constraints, fn c -> c.field == :email end)
    end
  end

  describe "validate_field/3 with no change" do
    test "does nothing when field has no change" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_field(:name, min: 3)

      assert cs.valid?
    end
  end

  describe "validate_field/3 combined options" do
    test "applies multiple validations together" do
      cs =
        changeset(%{name: "  AB  "})
        |> ValidatorsExtended.validate_field(:name, required: true, min: 3, lowercase: true)

      # After trim + lowercase, name = "ab" which is 2 chars < min 3
      refute cs.valid?
    end

    test "passes all validations together" do
      cs =
        changeset(%{name: "  Alice  "})
        |> ValidatorsExtended.validate_field(:name,
          required: true,
          min: 3,
          max: 20,
          lowercase: true
        )

      assert cs.valid?
      assert get_change(cs, :name) == "alice"
    end
  end

  # ============================================
  # validate_email/3
  # ============================================

  describe "validate_email/3" do
    test "normalizes email to lowercase and trims" do
      cs =
        changeset(%{email: "  USER@EXAMPLE.COM  "})
        |> ValidatorsExtended.validate_email(:email)

      assert get_change(cs, :email) == "user@example.com"
    end

    test "validates email format" do
      cs =
        changeset(%{email: "not-an-email"})
        |> ValidatorsExtended.validate_email(:email)

      refute cs.valid?
    end

    test "passes valid email" do
      cs =
        changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_email(:email)

      assert cs.valid?
    end

    test "passes email with subdomains" do
      cs =
        changeset(%{email: "user@mail.example.co.uk"})
        |> ValidatorsExtended.validate_email(:email)

      assert cs.valid?
    end

    test "rejects email with spaces" do
      cs =
        changeset(%{email: "user @example.com"})
        |> ValidatorsExtended.validate_email(:email)

      refute cs.valid?
    end

    test "supports required option" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_email(:email, required: true)

      refute cs.valid?
    end

    test "supports unique option" do
      cs =
        source_changeset(%{email: "user@example.com"})
        |> ValidatorsExtended.validate_email(:email, unique: true)

      assert Enum.any?(cs.constraints, fn c -> c.field == :email end)
    end
  end

  # ============================================
  # validate_url/3
  # ============================================

  describe "validate_url/3" do
    test "normalizes URL to lowercase and trims" do
      cs =
        changeset(%{url: "  HTTPS://EXAMPLE.COM/PATH  "})
        |> ValidatorsExtended.validate_url(:url)

      assert get_change(cs, :url) == "https://example.com/path"
    end

    test "validates URL must start with http:// or https://" do
      cs =
        changeset(%{url: "ftp://example.com"})
        |> ValidatorsExtended.validate_url(:url)

      refute cs.valid?
    end

    test "passes valid http URL" do
      cs =
        changeset(%{url: "http://example.com"})
        |> ValidatorsExtended.validate_url(:url)

      assert cs.valid?
    end

    test "passes valid https URL" do
      cs =
        changeset(%{url: "https://example.com/path?q=1"})
        |> ValidatorsExtended.validate_url(:url)

      assert cs.valid?
    end

    test "rejects plain text" do
      cs =
        changeset(%{url: "not a url"})
        |> ValidatorsExtended.validate_url(:url)

      refute cs.valid?
    end

    test "supports required option" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_url(:url, required: true)

      refute cs.valid?
    end
  end

  # ============================================
  # validate_phone/3
  # ============================================

  describe "validate_phone/3" do
    test "normalizes phone by removing formatting characters" do
      cs =
        changeset(%{phone: "+1 (555) 123-4567"})
        |> ValidatorsExtended.validate_phone(:phone)

      assert get_change(cs, :phone) == "+15551234567"
    end

    test "passes valid international number" do
      cs =
        changeset(%{phone: "+15551234567"})
        |> ValidatorsExtended.validate_phone(:phone)

      assert cs.valid?
    end

    test "passes valid number without +" do
      cs =
        changeset(%{phone: "5551234567"})
        |> ValidatorsExtended.validate_phone(:phone)

      # 10 digits, matches ^\\+?[0-9]{10,15}$
      assert cs.valid?
    end

    test "rejects too short number" do
      cs =
        changeset(%{phone: "12345"})
        |> ValidatorsExtended.validate_phone(:phone)

      refute cs.valid?
    end

    test "rejects number with letters" do
      # After normalization, letters are not removed by normalize_phone
      # (only non-digit except + is removed). Letters are digits? No.
      # Actually normalize_phone removes [^\d+], so letters get removed,
      # leaving fewer digits which may fail length check
      cs =
        changeset(%{phone: "abc"})
        |> ValidatorsExtended.validate_phone(:phone)

      refute cs.valid?
    end

    test "supports required option" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_phone(:phone, required: true)

      refute cs.valid?
    end
  end

  # ============================================
  # validate_money/3
  # ============================================

  describe "validate_money/3" do
    test "defaults to non_negative validation" do
      cs =
        changeset(%{price: Decimal.new("-1")})
        |> ValidatorsExtended.validate_money(:price)

      refute cs.valid?
    end

    test "passes zero by default (non_negative)" do
      cs =
        changeset(%{price: Decimal.new("0")})
        |> ValidatorsExtended.validate_money(:price)

      assert cs.valid?
    end

    test "passes positive amount" do
      cs =
        changeset(%{price: Decimal.new("99.99")})
        |> ValidatorsExtended.validate_money(:price)

      assert cs.valid?
    end

    test "validates positive when positive: true" do
      cs =
        changeset(%{price: Decimal.new("0")})
        |> ValidatorsExtended.validate_money(:price, positive: true)

      refute cs.valid?
    end

    test "validates minimum amount" do
      cs =
        changeset(%{price: Decimal.new("0.50")})
        |> ValidatorsExtended.validate_money(:price, min: 1)

      refute cs.valid?
    end

    test "validates maximum amount" do
      cs =
        changeset(%{price: Decimal.new("1000000")})
        |> ValidatorsExtended.validate_money(:price, max: 999_999)

      refute cs.valid?
    end

    test "validates precision for integer decimals" do
      cs =
        changeset(%{price: Decimal.new("12345678")})
        |> ValidatorsExtended.validate_money(:price, precision: 6)

      refute cs.valid?
      assert errors_on(cs, :price) |> Enum.any?(&String.contains?(&1, "precision"))
    end

    test "passes within precision for integer decimals" do
      cs =
        changeset(%{price: Decimal.new("12345")})
        |> ValidatorsExtended.validate_money(:price, precision: 6)

      assert cs.valid?
    end

    test "integer decimal passes scale of 0" do
      # Decimal.new("100") -> "100" has no decimal part, so scale 0 is fine
      cs =
        changeset(%{price: Decimal.new("100")})
        |> ValidatorsExtended.validate_money(:price, scale: 0)

      assert cs.valid?
    end

    test "passes when scale is sufficient for integer decimals" do
      cs =
        changeset(%{price: Decimal.new("100")})
        |> ValidatorsExtended.validate_money(:price, scale: 1)

      # "100.0" splits to ["100", "0"], decimal_part = "0", length 1 <= scale 1
      assert cs.valid?
    end

    test "validates both precision and scale for integer decimals" do
      cs =
        changeset(%{price: Decimal.new("123")})
        |> ValidatorsExtended.validate_money(:price, precision: 3, scale: 1)

      # "123.0" -> ["123", "0"] -> integer_part "123" len 3 <= precision 3,
      # decimal_part "0" len 1 <= scale 1
      assert cs.valid?
    end

    test "allows negative when non_negative: false" do
      cs =
        changeset(%{price: Decimal.new("-5")})
        |> ValidatorsExtended.validate_money(:price, non_negative: false)

      assert cs.valid?
    end
  end

  # ============================================
  # validate_percentage/3
  # ============================================

  describe "validate_percentage/3" do
    test "rejects value below 0" do
      cs =
        changeset(%{discount: -1.0})
        |> ValidatorsExtended.validate_percentage(:discount)

      refute cs.valid?
    end

    test "rejects value above 100" do
      cs =
        changeset(%{discount: 101.0})
        |> ValidatorsExtended.validate_percentage(:discount)

      refute cs.valid?
    end

    test "passes 0" do
      cs =
        changeset(%{discount: 0.0})
        |> ValidatorsExtended.validate_percentage(:discount)

      assert cs.valid?
    end

    test "passes 100" do
      cs =
        changeset(%{discount: 100.0})
        |> ValidatorsExtended.validate_percentage(:discount)

      assert cs.valid?
    end

    test "passes value in range" do
      cs =
        changeset(%{discount: 50.0})
        |> ValidatorsExtended.validate_percentage(:discount)

      assert cs.valid?
    end

    test "supports additional options" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_percentage(:discount, required: true)

      refute cs.valid?
    end

    test "respects overridden bounds" do
      cs =
        changeset(%{discount: 50.0})
        |> ValidatorsExtended.validate_percentage(:discount, lte: 25)

      refute cs.valid?
    end
  end

  # ============================================
  # validate_slug/3
  # ============================================

  describe "validate_slug/3" do
    test "normalizes slug from title-like input" do
      cs =
        changeset(%{slug: "  Hello World!  "})
        |> ValidatorsExtended.validate_slug(:slug)

      assert get_change(cs, :slug) == "hello-world"
    end

    test "normalizes uppercase to lowercase" do
      cs =
        changeset(%{slug: "MY-SLUG"})
        |> ValidatorsExtended.validate_slug(:slug)

      assert get_change(cs, :slug) == "my-slug"
    end

    test "collapses multiple hyphens" do
      cs =
        changeset(%{slug: "hello---world"})
        |> ValidatorsExtended.validate_slug(:slug)

      assert get_change(cs, :slug) == "hello-world"
    end

    test "passes valid slug" do
      cs =
        changeset(%{slug: "valid-slug-123"})
        |> ValidatorsExtended.validate_slug(:slug)

      assert cs.valid?
    end

    test "passes single-word slug" do
      cs =
        changeset(%{slug: "hello"})
        |> ValidatorsExtended.validate_slug(:slug)

      assert cs.valid?
    end

    test "supports required option" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_slug(:slug, required: true)

      refute cs.valid?
    end

    test "supports min/max length" do
      cs =
        changeset(%{slug: "ab"})
        |> ValidatorsExtended.validate_slug(:slug, min: 3)

      refute cs.valid?
    end
  end

  # ============================================
  # validate_uuid/3
  # ============================================

  describe "validate_uuid/3" do
    test "passes valid lowercase UUID" do
      cs =
        changeset(%{uuid_field: "550e8400-e29b-41d4-a716-446655440000"})
        |> ValidatorsExtended.validate_uuid(:uuid_field)

      assert cs.valid?
    end

    test "passes valid uppercase UUID (case insensitive regex)" do
      cs =
        changeset(%{uuid_field: "550E8400-E29B-41D4-A716-446655440000"})
        |> ValidatorsExtended.validate_uuid(:uuid_field)

      assert cs.valid?
    end

    test "rejects invalid UUID" do
      cs =
        changeset(%{uuid_field: "not-a-uuid"})
        |> ValidatorsExtended.validate_uuid(:uuid_field)

      refute cs.valid?
    end

    test "rejects UUID without hyphens" do
      cs =
        changeset(%{uuid_field: "550e8400e29b41d4a716446655440000"})
        |> ValidatorsExtended.validate_uuid(:uuid_field)

      refute cs.valid?
    end

    test "rejects UUID with wrong segment length" do
      cs =
        changeset(%{uuid_field: "550e8400-e29b-41d4-a716-44665544000"})
        |> ValidatorsExtended.validate_uuid(:uuid_field)

      refute cs.valid?
    end

    test "supports required option" do
      cs = changeset(%{}) |> ValidatorsExtended.validate_uuid(:uuid_field, required: true)

      refute cs.valid?
    end
  end

  # ============================================
  # validate_json/3
  # ============================================

  describe "validate_json/3" do
    test "passes valid map" do
      cs =
        changeset(%{metadata: %{"key" => "value"}})
        |> ValidatorsExtended.validate_json(:metadata)

      assert cs.valid?
    end

    test "passes empty map" do
      cs =
        changeset(%{metadata: %{}})
        |> ValidatorsExtended.validate_json(:metadata)

      assert cs.valid?
    end

    test "validates required_keys" do
      cs =
        changeset(%{metadata: %{"name" => "test"}})
        |> ValidatorsExtended.validate_json(:metadata, required_keys: ["name", "type"])

      refute cs.valid?
      assert errors_on(cs, :json) |> Enum.any?(&String.contains?(&1, "missing required keys"))
    end

    test "passes when all required_keys present" do
      cs =
        changeset(%{metadata: %{"name" => "test", "type" => "foo"}})
        |> ValidatorsExtended.validate_json(:metadata, required_keys: ["name", "type"])

      assert cs.valid?
    end

    test "validates forbidden_keys" do
      cs =
        changeset(%{metadata: %{"password" => "secret", "name" => "test"}})
        |> ValidatorsExtended.validate_json(:metadata, forbidden_keys: ["password", "secret"])

      refute cs.valid?
      assert errors_on(cs, :json) |> Enum.any?(&String.contains?(&1, "forbidden keys"))
    end

    test "passes when no forbidden_keys present" do
      cs =
        changeset(%{metadata: %{"name" => "test"}})
        |> ValidatorsExtended.validate_json(:metadata, forbidden_keys: ["password"])

      assert cs.valid?
    end

    test "validates max_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3}})
        |> ValidatorsExtended.validate_json(:metadata, max_keys: 2)

      refute cs.valid?
      assert errors_on(cs, :json) |> Enum.any?(&String.contains?(&1, "exceeds maximum"))
    end

    test "passes at max_keys boundary" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2}})
        |> ValidatorsExtended.validate_json(:metadata, max_keys: 2)

      assert cs.valid?
    end

    test "combines multiple JSON constraints" do
      cs =
        changeset(%{metadata: %{"name" => "test", "password" => "secret", "extra" => 1}})
        |> ValidatorsExtended.validate_json(:metadata,
          required_keys: ["name"],
          forbidden_keys: ["password"],
          max_keys: 2
        )

      # Should have errors for forbidden key and max keys exceeded
      refute cs.valid?
    end

    test "does not validate when field has no change" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_json(:metadata)

      assert cs.valid?
    end
  end

  # ============================================
  # validate_enum/4
  # ============================================

  describe "validate_enum/4" do
    test "validates value is in enum list" do
      cs =
        changeset(%{status: "unknown"})
        |> ValidatorsExtended.validate_enum(:status, ["active", "inactive", "pending"])

      refute cs.valid?
    end

    test "passes valid enum value" do
      cs =
        changeset(%{status: "active"})
        |> ValidatorsExtended.validate_enum(:status, ["active", "inactive", "pending"])

      assert cs.valid?
    end

    test "supports additional options like required" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_enum(:status, ["active", "inactive"], required: true)

      refute cs.valid?
    end

    test "works with atom values" do
      # cast would need to convert atoms, but since status is :string type
      # and we're testing the enum validation, let's use string values
      cs =
        changeset(%{status: "pending"})
        |> ValidatorsExtended.validate_enum(:status, ["active", "inactive"])

      refute cs.valid?
    end
  end

  # ============================================
  # validate_array/3
  # ============================================

  describe "validate_array/3" do
    test "passes valid array" do
      cs =
        changeset(%{tags: ["elixir", "phoenix"]})
        |> ValidatorsExtended.validate_array(:tags)

      assert cs.valid?
    end

    test "validates min_length" do
      cs =
        changeset(%{tags: ["one"]})
        |> ValidatorsExtended.validate_array(:tags, min_length: 2)

      refute cs.valid?
      assert errors_on(cs, :tags) |> Enum.any?(&String.contains?(&1, "at least 2"))
    end

    test "passes at min_length boundary" do
      cs =
        changeset(%{tags: ["one", "two"]})
        |> ValidatorsExtended.validate_array(:tags, min_length: 2)

      assert cs.valid?
    end

    test "validates max_length" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d"]})
        |> ValidatorsExtended.validate_array(:tags, max_length: 3)

      refute cs.valid?
      assert errors_on(cs, :tags) |> Enum.any?(&String.contains?(&1, "at most 3"))
    end

    test "passes at max_length boundary" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ValidatorsExtended.validate_array(:tags, max_length: 3)

      assert cs.valid?
    end

    test "validates unique_items" do
      cs =
        changeset(%{tags: ["a", "b", "a"]})
        |> ValidatorsExtended.validate_array(:tags, unique_items: true)

      refute cs.valid?
      assert errors_on(cs, :tags) |> Enum.any?(&String.contains?(&1, "unique"))
    end

    test "passes when items are unique" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ValidatorsExtended.validate_array(:tags, unique_items: true)

      assert cs.valid?
    end

    test "passes empty array" do
      cs =
        changeset(%{tags: []})
        |> ValidatorsExtended.validate_array(:tags)

      assert cs.valid?
    end

    test "does not validate when field has no change" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_array(:tags, min_length: 1)

      assert cs.valid?
    end
  end

  # ============================================
  # validate_boolean/3
  # ============================================

  describe "validate_boolean/3" do
    test "validates acceptance when acceptance: true" do
      cs =
        changeset(%{active: false})
        |> ValidatorsExtended.validate_boolean(:active, acceptance: true)

      refute cs.valid?
    end

    test "passes when accepted" do
      cs =
        changeset(%{active: true})
        |> ValidatorsExtended.validate_boolean(:active, acceptance: true)

      assert cs.valid?
    end

    test "no validation when acceptance is not set" do
      cs =
        changeset(%{active: false})
        |> ValidatorsExtended.validate_boolean(:active)

      assert cs.valid?
    end

    test "no validation with empty opts" do
      cs =
        changeset(%{active: true})
        |> ValidatorsExtended.validate_boolean(:active, [])

      assert cs.valid?
    end
  end

  # ============================================
  # validate_if/5
  # ============================================

  describe "validate_if/5" do
    test "applies validation when condition is true" do
      cs =
        changeset(%{age: 20})
        |> ValidatorsExtended.validate_if(:phone, :required, fn changeset ->
          get_field(changeset, :email) == nil
        end)

      # email is nil, so phone should be required
      refute cs.valid?
    end

    test "skips validation when condition is false" do
      cs =
        changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_if(:phone, :required, fn changeset ->
          get_field(changeset, :email) == nil
        end)

      # email is present, so phone is NOT required
      assert cs.valid?
    end

    test "condition receives the changeset" do
      cs =
        changeset(%{age: 17})
        |> ValidatorsExtended.validate_if(:name, :required, fn changeset ->
          age = get_field(changeset, :age)
          age != nil && age < 18
        end)

      # age < 18, so name is required
      refute cs.valid?
    end
  end

  # ============================================
  # validate_unless/5
  # ============================================

  describe "validate_unless/5" do
    test "applies validation when condition is false" do
      cs =
        changeset(%{age: 20})
        |> ValidatorsExtended.validate_unless(:phone, :required, fn changeset ->
          get_field(changeset, :email) != nil
        end)

      # email is nil, so condition returns false, so validation IS applied
      refute cs.valid?
    end

    test "skips validation when condition is true" do
      cs =
        changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_unless(:phone, :required, fn changeset ->
          get_field(changeset, :email) != nil
        end)

      # email is present, condition is true, so validation is SKIPPED
      assert cs.valid?
    end

    test "inverse of validate_if" do
      condition = fn changeset -> get_field(changeset, :email) != nil end

      cs_if =
        changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_if(:phone, :required, condition)

      cs_unless =
        changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_unless(:phone, :required, condition)

      # validate_if with true condition => applies validation (phone required, fails)
      refute cs_if.valid?
      # validate_unless with true condition => skips validation (phone not required, passes)
      assert cs_unless.valid?
    end
  end

  # ============================================
  # validate_confirmation/3
  # ============================================

  describe "validate_confirmation/3" do
    test "passes when fields match" do
      cs =
        changeset(%{password: "secret123", password_confirmation: "secret123"})
        |> ValidatorsExtended.validate_confirmation(:password, :password_confirmation)

      assert cs.valid?
    end

    test "fails when fields do not match" do
      cs =
        changeset(%{password: "secret123", password_confirmation: "different"})
        |> ValidatorsExtended.validate_confirmation(:password, :password_confirmation)

      refute cs.valid?
      assert errors_on(cs, :password_confirmation) != []
    end

    test "error message references the original field" do
      cs =
        changeset(%{password: "secret123", password_confirmation: "different"})
        |> ValidatorsExtended.validate_confirmation(:password, :password_confirmation)

      assert errors_on(cs, :password_confirmation) |> Enum.any?(&String.contains?(&1, "password"))
    end

    test "does not validate when primary field has no change" do
      cs =
        changeset(%{password_confirmation: "something"})
        |> ValidatorsExtended.validate_confirmation(:password, :password_confirmation)

      # password has no change, so validate_change is not triggered
      assert cs.valid?
    end

    test "fails when confirmation is nil but field has value" do
      cs =
        changeset(%{password: "secret123"})
        |> ValidatorsExtended.validate_confirmation(:password, :password_confirmation)

      refute cs.valid?
    end
  end

  # ============================================
  # validate_comparison/4
  # ============================================

  describe "validate_comparison/4" do
    test "validates less than or equal" do
      cs =
        changeset(%{start_date: ~D[2024-12-31], end_date: ~D[2024-01-01]})
        |> ValidatorsExtended.validate_comparison(:start_date, :<=, :end_date)

      refute cs.valid?
      assert errors_on(cs, :start_date) != []
    end

    test "passes when comparison holds" do
      cs =
        changeset(%{start_date: ~D[2024-01-01], end_date: ~D[2024-12-31]})
        |> ValidatorsExtended.validate_comparison(:start_date, :<=, :end_date)

      assert cs.valid?
    end

    test "passes when dates are equal with <=" do
      cs =
        changeset(%{start_date: ~D[2024-06-15], end_date: ~D[2024-06-15]})
        |> ValidatorsExtended.validate_comparison(:start_date, :<=, :end_date)

      assert cs.valid?
    end

    test "validates strict less than" do
      cs =
        changeset(%{start_date: ~D[2024-06-15], end_date: ~D[2024-06-15]})
        |> ValidatorsExtended.validate_comparison(:start_date, :<, :end_date)

      refute cs.valid?
    end

    test "validates with numeric fields" do
      cs =
        changeset(%{age: 30, discount: 50.0})
        |> ValidatorsExtended.validate_comparison(:age, :<, :discount)

      assert cs.valid?
    end

    test "error message includes operator and field" do
      cs =
        changeset(%{start_date: ~D[2024-12-31], end_date: ~D[2024-01-01]})
        |> ValidatorsExtended.validate_comparison(:start_date, :<=, :end_date)

      error_messages = errors_on(cs, :start_date)
      assert Enum.any?(error_messages, &String.contains?(&1, "<="))
      assert Enum.any?(error_messages, &String.contains?(&1, "end_date"))
    end

    test "does not validate when first field has no change" do
      cs =
        changeset(%{end_date: ~D[2024-01-01]})
        |> ValidatorsExtended.validate_comparison(:start_date, :<=, :end_date)

      assert cs.valid?
    end
  end

  # ============================================
  # validate_exclusive/3
  # ============================================

  describe "validate_exclusive/3" do
    test "passes when only one field is present" do
      cs =
        changeset(%{email: "test@example.com"})
        |> ValidatorsExtended.validate_exclusive([:email, :phone])

      assert cs.valid?
    end

    test "fails when multiple exclusive fields are present" do
      cs =
        changeset(%{email: "test@example.com", phone: "1234567890"})
        |> ValidatorsExtended.validate_exclusive([:email, :phone])

      refute cs.valid?
      assert errors_on(cs, :base) |> Enum.any?(&String.contains?(&1, "only one"))
    end

    test "passes when no fields are present (without at_least_one)" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_exclusive([:email, :phone])

      assert cs.valid?
    end

    test "fails when no fields present with at_least_one: true" do
      cs =
        changeset(%{})
        |> ValidatorsExtended.validate_exclusive([:email, :phone], at_least_one: true)

      refute cs.valid?
      assert errors_on(cs, :base) |> Enum.any?(&String.contains?(&1, "at least one"))
    end

    test "passes with at_least_one when one field present" do
      cs =
        changeset(%{phone: "1234567890"})
        |> ValidatorsExtended.validate_exclusive([:email, :phone], at_least_one: true)

      assert cs.valid?
    end

    test "fails with at_least_one when multiple fields present" do
      cs =
        changeset(%{email: "test@example.com", phone: "1234567890"})
        |> ValidatorsExtended.validate_exclusive([:email, :phone], at_least_one: true)

      refute cs.valid?
      assert errors_on(cs, :base) |> Enum.any?(&String.contains?(&1, "only one"))
    end

    test "error message lists the field names" do
      cs =
        changeset(%{email: "a", phone: "b"})
        |> ValidatorsExtended.validate_exclusive([:email, :phone])

      error_messages = errors_on(cs, :base)
      assert Enum.any?(error_messages, &String.contains?(&1, "email"))
      assert Enum.any?(error_messages, &String.contains?(&1, "phone"))
    end

    test "handles three or more exclusive fields" do
      cs =
        changeset(%{email: "a", phone: "b", alt_email: "c"})
        |> ValidatorsExtended.validate_exclusive([:email, :phone, :alt_email])

      refute cs.valid?
    end
  end

  # ============================================
  # Edge Cases and Integration
  # ============================================

  describe "edge cases" do
    test "validate_field with nil value and no required" do
      cs = changeset(%{name: nil}) |> ValidatorsExtended.validate_field(:name, min: 3)

      # nil value is not cast as a change for string, so no validation triggered
      assert cs.valid?
    end

    test "validate_field with empty string" do
      cs =
        changeset(%{name: ""})
        |> ValidatorsExtended.validate_field(:name, required: true)

      # Empty string after trim is still empty, required should catch it
      refute cs.valid?
    end

    test "multiple validations on same changeset" do
      cs =
        changeset(%{name: "Alice", email: "alice@example.com", age: 25})
        |> ValidatorsExtended.validate_field(:name, required: true, min: 2)
        |> ValidatorsExtended.validate_email(:email, required: true)
        |> ValidatorsExtended.validate_field(:age, gte: 18, lte: 120)

      assert cs.valid?
    end

    test "multiple validation errors accumulate" do
      cs =
        changeset(%{name: "A", age: -1})
        |> ValidatorsExtended.validate_field(:name, required: true, min: 3)
        |> ValidatorsExtended.validate_field(:age, positive: true)

      refute cs.valid?
      assert errors_on(cs, :name) != []
      assert errors_on(cs, :age) != []
    end

    test "validate_email normalizes before format check" do
      # Uppercase email with spaces should be normalized then validated
      cs =
        changeset(%{email: "  TEST@EXAMPLE.COM  "})
        |> ValidatorsExtended.validate_email(:email)

      assert cs.valid?
      assert get_change(cs, :email) == "test@example.com"
    end

    test "validate_slug normalizes special characters" do
      cs =
        changeset(%{slug: "  My Post Title!  "})
        |> ValidatorsExtended.validate_slug(:slug)

      normalized = get_change(cs, :slug)
      assert normalized == "my-post-title"
      assert cs.valid?
    end
  end
end
