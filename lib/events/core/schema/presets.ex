defmodule Events.Core.Schema.Presets do
  @moduledoc """
  Common validation presets for frequently used field patterns.

  Provides pre-configured validation options for common field types like
  emails, slugs, URLs, etc. These presets can be used directly or merged
  with custom options.

  ## Usage

      defmodule MyApp.User do
        use Events.Core.Schema
        import Events.Core.Schema.Presets

        schema "users" do
          field :email, :string, email()
          field :website, :string, url(required: false)
          field :username, :string, username(min_length: 3)
        end
      end
  """

  @doc """
  Email field preset with standard validations.

  Options:
  - `required: true`
  - `format: :email`
  - `max_length: 255`
  - `normalize: [:trim, :downcase]`
  """
  @spec email(keyword()) :: keyword()
  def email(custom_opts \\ []) do
    [
      required: true,
      format: :email,
      max_length: 255,
      normalize: [:trim, :downcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  URL field preset with URL validation.

  Options:
  - `required: true`
  - `format: :url`
  - `max_length: 2048`
  - `normalize: :trim`
  """
  @spec url(keyword()) :: keyword()
  def url(custom_opts \\ []) do
    [
      required: true,
      format: :url,
      max_length: 2048,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Slug field preset with uniqueness.

  Options:
  - `format: :slug`
  - `normalize: {:slugify, uniquify: true}`
  - `max_length: 255`
  """
  @spec slug(keyword()) :: keyword()
  def slug(custom_opts \\ []) do
    [
      format: :slug,
      normalize: {:slugify, uniquify: Keyword.get(custom_opts, :uniquify, true)},
      max_length: 255
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Username field preset.

  Options:
  - `required: true`
  - `min_length: 4`
  - `max_length: 30`
  - `format: ~r/^[a-zA-Z0-9_-]+$/`
  - `normalize: [:trim, :downcase]`
  """
  @spec username(keyword()) :: keyword()
  def username(custom_opts \\ []) do
    [
      required: true,
      min_length: 4,
      max_length: 30,
      format: ~r/^[a-zA-Z0-9_-]+$/,
      normalize: [:trim, :downcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Password field preset.

  Options:
  - `required: true`
  - `min_length: 8`
  - `max_length: 128`
  - No normalization (preserves exact input)
  """
  @spec password(keyword()) :: keyword()
  def password(custom_opts \\ []) do
    [
      required: true,
      min_length: 8,
      max_length: 128,
      # Never trim passwords
      trim: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Phone number field preset.

  Options:
  - `required: true`
  - `format: ~r/^[+]?[0-9\s\-().]+$/`
  - `min_length: 10`
  - `max_length: 20`
  - `normalize: :trim`
  """
  @spec phone(keyword()) :: keyword()
  def phone(custom_opts \\ []) do
    [
      required: true,
      format: ~r/^[+]?[0-9\s\-().]+$/,
      min_length: 10,
      max_length: 20,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  UUID field preset.

  Options:
  - `format: :uuid`
  - `normalize: [:trim, :downcase]`
  """
  @spec uuid(keyword()) :: keyword()
  def uuid(custom_opts \\ []) do
    [
      format: :uuid,
      normalize: [:trim, :downcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Positive integer preset (e.g., for counts, quantities).

  Options:
  - `positive: true`
  - `default: 0`
  """
  @spec positive_integer(keyword()) :: keyword()
  def positive_integer(custom_opts \\ []) do
    [
      positive: true,
      default: 0
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Money/price field preset.

  Options:
  - `non_negative: true`
  - `max: 999_999_999.99`
  """
  @spec money(keyword()) :: keyword()
  def money(custom_opts \\ []) do
    [
      non_negative: true,
      max: 999_999_999.99
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Percentage field preset (0-100).

  Options:
  - `min: 0`
  - `max: 100`
  """
  @spec percentage(keyword()) :: keyword()
  def percentage(custom_opts \\ []) do
    [
      min: 0,
      max: 100
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Enum/status field preset.

  Options:
  - `in: values` (required via custom_opts)
  - `required: true`
  """
  @spec enum(keyword()) :: keyword()
  def enum(custom_opts) do
    unless Keyword.has_key?(custom_opts, :in) do
      raise ArgumentError, "enum preset requires :in option with list of values"
    end

    [required: true]
    |> merge_opts(custom_opts)
  end

  @doc """
  Tags array field preset.

  Options:
  - `unique_items: true`
  - `min_length: 0`
  - `max_length: 20`
  - `item_format: ~r/^[a-z0-9-]+$/`
  """
  @spec tags(keyword()) :: keyword()
  def tags(custom_opts \\ []) do
    [
      unique_items: true,
      min_length: 0,
      max_length: 20,
      item_format: ~r/^[a-z0-9-]+$/
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  JSON/metadata field preset.

  Options:
  - `default: %{}`
  - `max_keys: 100`
  """
  @spec metadata(keyword()) :: keyword()
  def metadata(custom_opts \\ []) do
    [
      default: %{},
      max_keys: 100
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Timestamp field preset for created_at/updated_at style fields.

  Options:
  - `required: false`
  - Auto-set by database
  """
  @spec timestamp(keyword()) :: keyword()
  def timestamp(custom_opts \\ []) do
    [required: false]
    |> merge_opts(custom_opts)
  end

  @doc """
  Zip/postal code field preset.

  Options:
  - `format: ~r/^[0-9]{5}(-[0-9]{4})?$/` (US format)
  - `normalize: [:trim, :upcase]`
  """
  @spec zip_code(keyword()) :: keyword()
  def zip_code(custom_opts \\ []) do
    [
      format: ~r/^[0-9]{5}(-[0-9]{4})?$/,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Credit card number field preset.

  Options:
  - `format: ~r/^[0-9]{13,19}$/`
  - `min_length: 13`
  - `max_length: 19`
  - `normalize: fn v -> String.replace(v, ~r/\s+/, "") end`
  """
  @spec credit_card(keyword()) :: keyword()
  def credit_card(custom_opts \\ []) do
    [
      format: ~r/^[0-9]{13,19}$/,
      min_length: 13,
      max_length: 19,
      normalize: fn v -> String.replace(v, ~r/\s+/, "") end
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  IPv4 address field preset.

  Options:
  - `format: ~r/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/`
  - `normalize: :trim`
  """
  @spec ipv4(keyword()) :: keyword()
  def ipv4(custom_opts \\ []) do
    [
      format:
        ~r/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  IPv6 address field preset.

  Options:
  - `format: ~r/^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|::|::[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){0,6})$/`
  - `normalize: [:trim, :downcase]`
  """
  @spec ipv6(keyword()) :: keyword()
  def ipv6(custom_opts \\ []) do
    [
      format:
        ~r/^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|::|::[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){0,6})$/,
      normalize: [:trim, :downcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  MAC address field preset.

  Options:
  - `format: ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/`
  - `normalize: [:trim, :upcase]`
  """
  @spec mac_address(keyword()) :: keyword()
  def mac_address(custom_opts \\ []) do
    [
      format: ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Hex color code field preset.

  Options:
  - `format: ~r/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/`
  - `normalize: [:trim, :upcase]`
  """
  @spec hex_color(keyword()) :: keyword()
  def hex_color(custom_opts \\ []) do
    [
      format: ~r/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  RGB color field preset.

  Options:
  - `format: ~r/^rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)$/`
  - `normalize: :trim`
  """
  @spec rgb_color(keyword()) :: keyword()
  def rgb_color(custom_opts \\ []) do
    [
      format: ~r/^rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)$/,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  File path field preset.

  Options:
  - `format: ~r/^[^<>:"|?*]+$/`
  - `max_length: 4096`
  - `normalize: :trim`
  """
  @spec file_path(keyword()) :: keyword()
  def file_path(custom_opts \\ []) do
    [
      format: ~r/^[^<>:"|?*]+$/,
      max_length: 4096,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Social media handle field preset (Twitter/Instagram style).

  Options:
  - `format: ~r/^@?[a-zA-Z0-9_]{1,30}$/`
  - `min_length: 1`
  - `max_length: 31`
  - `normalize: fn v -> String.replace(v, ~r/^@/, "") |> String.downcase() end`
  """
  @spec social_handle(keyword()) :: keyword()
  def social_handle(custom_opts \\ []) do
    [
      format: ~r/^@?[a-zA-Z0-9_]{1,30}$/,
      min_length: 1,
      max_length: 31,
      normalize: fn v -> String.replace(v, ~r/^@/, "") |> String.downcase() end
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Latitude field preset.

  Options:
  - `min: -90.0`
  - `max: 90.0`
  """
  @spec latitude(keyword()) :: keyword()
  def latitude(custom_opts \\ []) do
    [
      min: -90.0,
      max: 90.0
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Longitude field preset.

  Options:
  - `min: -180.0`
  - `max: 180.0`
  """
  @spec longitude(keyword()) :: keyword()
  def longitude(custom_opts \\ []) do
    [
      min: -180.0,
      max: 180.0
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Age field preset.

  Options:
  - `min: 0`
  - `max: 150`
  - `non_negative: true`
  """
  @spec age(keyword()) :: keyword()
  def age(custom_opts \\ []) do
    [
      min: 0,
      max: 150,
      non_negative: true
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Rating field preset (1-5 stars).

  Options:
  - `min: 1`
  - `max: 5`
  """
  @spec rating(keyword()) :: keyword()
  def rating(custom_opts \\ []) do
    [
      min: 1,
      max: 5
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Country code field preset (ISO 3166-1 alpha-2).

  Options:
  - `format: ~r/^[A-Z]{2}$/`
  - `length: 2`
  - `normalize: [:trim, :upcase]`
  """
  @spec country_code(keyword()) :: keyword()
  def country_code(custom_opts \\ []) do
    [
      format: ~r/^[A-Z]{2}$/,
      length: 2,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Language code field preset (ISO 639-1).

  Options:
  - `format: ~r/^[a-z]{2}(-[A-Z]{2})?$/`
  - `min_length: 2`
  - `max_length: 5`
  - `normalize: :trim`
  """
  @spec language_code(keyword()) :: keyword()
  def language_code(custom_opts \\ []) do
    [
      format: ~r/^[a-z]{2}(-[A-Z]{2})?$/,
      min_length: 2,
      max_length: 5,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Currency code field preset (ISO 4217).

  Options:
  - `format: ~r/^[A-Z]{3}$/`
  - `length: 3`
  - `normalize: [:trim, :upcase]`
  """
  @spec currency_code(keyword()) :: keyword()
  def currency_code(custom_opts \\ []) do
    [
      format: ~r/^[A-Z]{3}$/,
      length: 3,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Domain name field preset.

  Options:
  - `format: ~r/^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/i`
  - `max_length: 253`
  - `normalize: [:trim, :downcase]`
  """
  @spec domain(keyword()) :: keyword()
  def domain(custom_opts \\ []) do
    [
      format: ~r/^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/i,
      max_length: 253,
      normalize: [:trim, :downcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Bitcoin address field preset.

  Options:
  - `format: ~r/^(bc1|[13])[a-zA-HJ-NP-Z0-9]{25,62}$/`
  - `min_length: 26`
  - `max_length: 62`
  - `normalize: :trim`
  """
  @spec bitcoin_address(keyword()) :: keyword()
  def bitcoin_address(custom_opts \\ []) do
    [
      format: ~r/^(bc1|[13])[a-zA-HJ-NP-Z0-9]{25,62}$/,
      min_length: 26,
      max_length: 62,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Ethereum address field preset.

  Options:
  - `format: ~r/^0x[a-fA-F0-9]{40}$/`
  - `length: 42`
  - `normalize: [:trim, :downcase]`
  """
  @spec ethereum_address(keyword()) :: keyword()
  def ethereum_address(custom_opts \\ []) do
    [
      format: ~r/^0x[a-fA-F0-9]{40}$/,
      length: 42,
      normalize: [:trim, :downcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  IBAN (International Bank Account Number) field preset.

  Options:
  - `format: ~r/^[A-Z]{2}[0-9]{2}[A-Z0-9]+$/`
  - `min_length: 15`
  - `max_length: 34`
  - `normalize: fn v -> String.replace(v, ~r/\s+/, "") |> String.upcase() end`
  """
  @spec iban(keyword()) :: keyword()
  def iban(custom_opts \\ []) do
    [
      format: ~r/^[A-Z]{2}[0-9]{2}[A-Z0-9]+$/,
      min_length: 15,
      max_length: 34,
      normalize: fn v -> String.replace(v, ~r/\s+/, "") |> String.upcase() end
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  ISBN (International Standard Book Number) field preset.

  Options:
  - `format: ~r/^(97[89])?[0-9]{9}[0-9Xx]$/`
  - `normalize: fn v -> String.replace(v, ~r/[\s-]/, "") end`
  """
  @spec isbn(keyword()) :: keyword()
  def isbn(custom_opts \\ []) do
    [
      format: ~r/^(97[89])?[0-9]{9}[0-9Xx]$/,
      normalize: fn v -> String.replace(v, ~r/[\s-]/, "") end
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  SSN (Social Security Number) field preset - US format.

  Options:
  - `format: ~r/^[0-9]{3}-[0-9]{2}-[0-9]{4}$/`
  - `length: 11`
  - `trim: false`
  """
  @spec ssn(keyword()) :: keyword()
  def ssn(custom_opts \\ []) do
    [
      format: ~r/^[0-9]{3}-[0-9]{2}-[0-9]{4}$/,
      length: 11,
      trim: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Time zone field preset.

  Options:
  - `format: ~r/^[A-Za-z]+\/[A-Za-z_]+$/`
  - `max_length: 50`
  """
  @spec timezone(keyword()) :: keyword()
  def timezone(custom_opts \\ []) do
    [
      format: ~r/^[A-Za-z]+\/[A-Za-z_]+$/,
      max_length: 50
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  MIME type field preset.

  Options:
  - `format: ~r/^[a-z]+\/[a-z0-9\-\+\.]+$/i`
  - `max_length: 100`
  - `normalize: :downcase`
  """
  @spec mime_type(keyword()) :: keyword()
  def mime_type(custom_opts \\ []) do
    [
      format: ~r/^[a-z]+\/[a-z0-9\-\+\.]+$/i,
      max_length: 100,
      normalize: :downcase
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  JWT (JSON Web Token) field preset.

  Options:
  - `format: ~r/^[A-Za-z0-9-_]{4,}\.[A-Za-z0-9-_]{4,}\.[A-Za-z0-9-_]*$/`
  - `trim: false`
  """
  @spec jwt(keyword()) :: keyword()
  def jwt(custom_opts \\ []) do
    [
      format: ~r/^[A-Za-z0-9-_]{4,}\.[A-Za-z0-9-_]{4,}\.[A-Za-z0-9-_]*$/,
      trim: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Semantic version field preset.

  Options:
  - `format: ~r/^v?\d+\.\d+\.\d+(-[a-z0-9\-\.]+)?(\+[a-z0-9\-\.]+)?$/i`
  - `max_length: 50`
  - `normalize: :trim`
  """
  @spec semver(keyword()) :: keyword()
  def semver(custom_opts \\ []) do
    [
      format: ~r/^v?\d+\.\d+\.\d+(-[a-z0-9\-\.]+)?(\+[a-z0-9\-\.]+)?$/i,
      max_length: 50,
      normalize: :trim
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Base64 encoded field preset.

  Options:
  - `format: ~r/^[A-Za-z0-9+\/]+=*$/`
  - `trim: false`
  """
  @spec base64(keyword()) :: keyword()
  def base64(custom_opts \\ []) do
    [
      format: ~r/^[A-Za-z0-9+\/]+=*$/,
      trim: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Hashtag field preset.

  Options:
  - `format: ~r/^#[a-zA-Z][a-zA-Z0-9_]*$/`
  - `min_length: 2`
  - `max_length: 100`
  - `normalize: :downcase`
  """
  @spec hashtag(keyword()) :: keyword()
  def hashtag(custom_opts \\ []) do
    [
      format: ~r/^#[a-zA-Z][a-zA-Z0-9_]*$/,
      min_length: 2,
      max_length: 100,
      normalize: :downcase
    ]
    |> merge_opts(custom_opts)
  end

  # Private helper to merge options with custom overrides
  defp merge_opts(defaults, custom_opts) do
    Keyword.merge(defaults, custom_opts)
  end
end
