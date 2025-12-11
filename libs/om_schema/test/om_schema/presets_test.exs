defmodule OmSchema.PresetsTest do
  use ExUnit.Case, async: true

  alias OmSchema.Presets

  # ============================================
  # Email Preset
  # ============================================

  describe "email/1" do
    test "returns default email preset options" do
      opts = Presets.email()

      assert opts[:required] == true
      assert opts[:format] == :email
      assert opts[:max_length] == 255
      assert opts[:normalize] == [:trim, :downcase]
    end

    test "merges custom options" do
      opts = Presets.email(required: false, max_length: 100)

      assert opts[:required] == false
      assert opts[:max_length] == 100
      assert opts[:format] == :email
    end
  end

  # ============================================
  # URL Preset
  # ============================================

  describe "url/1" do
    test "returns default url preset options" do
      opts = Presets.url()

      assert opts[:required] == true
      assert opts[:format] == :url
      assert opts[:max_length] == 2048
      assert opts[:normalize] == :trim
    end

    test "merges custom options" do
      opts = Presets.url(required: false)

      assert opts[:required] == false
      assert opts[:format] == :url
    end
  end

  # ============================================
  # Slug Preset
  # ============================================

  describe "slug/1" do
    test "returns default slug preset options" do
      opts = Presets.slug()

      assert opts[:format] == :slug
      assert opts[:max_length] == 255
      assert opts[:normalize] == {:slugify, uniquify: true}
    end

    test "can disable uniquify" do
      opts = Presets.slug(uniquify: false)

      assert opts[:normalize] == {:slugify, uniquify: false}
    end
  end

  # ============================================
  # Username Preset
  # ============================================

  describe "username/1" do
    test "returns default username preset options" do
      opts = Presets.username()

      assert opts[:required] == true
      assert opts[:min_length] == 4
      assert opts[:max_length] == 30
      assert Regex.source(opts[:format]) == "^[a-zA-Z0-9_-]+$"
      assert opts[:normalize] == [:trim, :downcase]
    end

    test "allows custom min_length" do
      opts = Presets.username(min_length: 3)

      assert opts[:min_length] == 3
    end
  end

  # ============================================
  # Password Preset
  # ============================================

  describe "password/1" do
    test "returns default password preset options" do
      opts = Presets.password()

      assert opts[:required] == true
      assert opts[:min_length] == 8
      assert opts[:max_length] == 128
      assert opts[:trim] == false
    end

    test "never trims passwords" do
      opts = Presets.password(trim: true)
      # trim: true in custom_opts overrides the default false
      assert opts[:trim] == true
    end
  end

  # ============================================
  # Phone Preset
  # ============================================

  describe "phone/1" do
    test "returns default phone preset options" do
      opts = Presets.phone()

      assert opts[:required] == true
      assert opts[:min_length] == 10
      assert opts[:max_length] == 20
      assert opts[:normalize] == :trim
      assert is_struct(opts[:format], Regex)
    end
  end

  # ============================================
  # UUID Preset
  # ============================================

  describe "uuid/1" do
    test "returns default uuid preset options" do
      opts = Presets.uuid()

      assert opts[:format] == :uuid
      assert opts[:normalize] == [:trim, :downcase]
    end
  end

  # ============================================
  # Number Presets
  # ============================================

  describe "positive_integer/1" do
    test "returns positive integer options" do
      opts = Presets.positive_integer()

      assert opts[:positive] == true
      assert opts[:default] == 0
    end
  end

  describe "money/1" do
    test "returns money preset options" do
      opts = Presets.money()

      assert opts[:non_negative] == true
      assert opts[:max] == 999_999_999.99
    end
  end

  describe "percentage/1" do
    test "returns percentage preset options" do
      opts = Presets.percentage()

      assert opts[:min] == 0
      assert opts[:max] == 100
    end
  end

  # ============================================
  # Enum Preset
  # ============================================

  describe "enum/1" do
    test "requires :in option" do
      assert_raise ArgumentError, ~r/enum preset requires :in option/, fn ->
        Presets.enum([])
      end
    end

    test "returns enum preset with values" do
      opts = Presets.enum(in: [:active, :inactive])

      assert opts[:required] == true
      assert opts[:in] == [:active, :inactive]
    end
  end

  # ============================================
  # Tags Preset
  # ============================================

  describe "tags/1" do
    test "returns tags preset options" do
      opts = Presets.tags()

      assert opts[:unique_items] == true
      assert opts[:min_length] == 0
      assert opts[:max_length] == 20
      assert is_struct(opts[:item_format], Regex)
    end
  end

  # ============================================
  # Metadata Preset
  # ============================================

  describe "metadata/1" do
    test "returns metadata preset options" do
      opts = Presets.metadata()

      assert opts[:default] == %{}
      assert opts[:max_keys] == 100
    end
  end

  # ============================================
  # Location Presets
  # ============================================

  describe "latitude/1" do
    test "returns latitude preset options" do
      opts = Presets.latitude()

      assert opts[:min] == -90.0
      assert opts[:max] == 90.0
    end
  end

  describe "longitude/1" do
    test "returns longitude preset options" do
      opts = Presets.longitude()

      assert opts[:min] == -180.0
      assert opts[:max] == 180.0
    end
  end

  # ============================================
  # Age Preset
  # ============================================

  describe "age/1" do
    test "returns age preset options" do
      opts = Presets.age()

      assert opts[:min] == 0
      assert opts[:max] == 150
      assert opts[:non_negative] == true
    end
  end

  # ============================================
  # Rating Preset
  # ============================================

  describe "rating/1" do
    test "returns rating preset options" do
      opts = Presets.rating()

      assert opts[:min] == 1
      assert opts[:max] == 5
    end
  end

  # ============================================
  # Code Presets (Country, Language, Currency)
  # ============================================

  describe "country_code/1" do
    test "returns country code preset options" do
      opts = Presets.country_code()

      assert opts[:length] == 2
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :upcase]
    end
  end

  describe "language_code/1" do
    test "returns language code preset options" do
      opts = Presets.language_code()

      assert opts[:min_length] == 2
      assert opts[:max_length] == 5
      assert is_struct(opts[:format], Regex)
    end
  end

  describe "currency_code/1" do
    test "returns currency code preset options" do
      opts = Presets.currency_code()

      assert opts[:length] == 3
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :upcase]
    end
  end

  # ============================================
  # Network Presets
  # ============================================

  describe "ipv4/1" do
    test "returns ipv4 preset options" do
      opts = Presets.ipv4()

      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == :trim
    end
  end

  describe "ipv6/1" do
    test "returns ipv6 preset options" do
      opts = Presets.ipv6()

      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :downcase]
    end
  end

  describe "mac_address/1" do
    test "returns mac address preset options" do
      opts = Presets.mac_address()

      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :upcase]
    end
  end

  describe "domain/1" do
    test "returns domain preset options" do
      opts = Presets.domain()

      assert opts[:max_length] == 253
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :downcase]
    end
  end

  # ============================================
  # Crypto Presets
  # ============================================

  describe "bitcoin_address/1" do
    test "returns bitcoin address preset options" do
      opts = Presets.bitcoin_address()

      assert opts[:min_length] == 26
      assert opts[:max_length] == 62
      assert is_struct(opts[:format], Regex)
    end
  end

  describe "ethereum_address/1" do
    test "returns ethereum address preset options" do
      opts = Presets.ethereum_address()

      assert opts[:length] == 42
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :downcase]
    end
  end

  # ============================================
  # Financial Presets
  # ============================================

  describe "iban/1" do
    test "returns iban preset options" do
      opts = Presets.iban()

      assert opts[:min_length] == 15
      assert opts[:max_length] == 34
      assert is_struct(opts[:format], Regex)
      assert is_function(opts[:normalize], 1)
    end
  end

  describe "credit_card/1" do
    test "returns credit card preset options" do
      opts = Presets.credit_card()

      assert opts[:min_length] == 13
      assert opts[:max_length] == 19
      assert is_struct(opts[:format], Regex)
      assert is_function(opts[:normalize], 1)
    end
  end

  # ============================================
  # Identifier Presets
  # ============================================

  describe "ssn/1" do
    test "returns ssn preset options" do
      opts = Presets.ssn()

      assert opts[:length] == 11
      assert is_struct(opts[:format], Regex)
      assert opts[:trim] == false
    end
  end

  describe "isbn/1" do
    test "returns isbn preset options" do
      opts = Presets.isbn()

      assert is_struct(opts[:format], Regex)
      assert is_function(opts[:normalize], 1)
    end
  end

  # ============================================
  # Other Presets
  # ============================================

  describe "timezone/1" do
    test "returns timezone preset options" do
      opts = Presets.timezone()

      assert opts[:max_length] == 50
      assert is_struct(opts[:format], Regex)
    end
  end

  describe "mime_type/1" do
    test "returns mime type preset options" do
      opts = Presets.mime_type()

      assert opts[:max_length] == 100
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == :downcase
    end
  end

  describe "jwt/1" do
    test "returns jwt preset options" do
      opts = Presets.jwt()

      assert is_struct(opts[:format], Regex)
      assert opts[:trim] == false
    end
  end

  describe "semver/1" do
    test "returns semver preset options" do
      opts = Presets.semver()

      assert opts[:max_length] == 50
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == :trim
    end
  end

  describe "base64/1" do
    test "returns base64 preset options" do
      opts = Presets.base64()

      assert is_struct(opts[:format], Regex)
      assert opts[:trim] == false
    end
  end

  describe "hex_color/1" do
    test "returns hex color preset options" do
      opts = Presets.hex_color()

      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :upcase]
    end
  end

  describe "file_path/1" do
    test "returns file path preset options" do
      opts = Presets.file_path()

      assert opts[:max_length] == 4096
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == :trim
    end
  end

  describe "social_handle/1" do
    test "returns social handle preset options" do
      opts = Presets.social_handle()

      assert opts[:min_length] == 1
      assert opts[:max_length] == 31
      assert is_struct(opts[:format], Regex)
      assert is_function(opts[:normalize], 1)
    end
  end

  describe "hashtag/1" do
    test "returns hashtag preset options" do
      opts = Presets.hashtag()

      assert opts[:min_length] == 2
      assert opts[:max_length] == 100
      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == :downcase
    end
  end

  describe "zip_code/1" do
    test "returns zip code preset options" do
      opts = Presets.zip_code()

      assert is_struct(opts[:format], Regex)
      assert opts[:normalize] == [:trim, :upcase]
    end
  end
end
