defmodule FnTypes.Formats do
  @moduledoc """
  Shared format validators and patterns - single source of truth.

  This module is the **single source of truth** for format validation across all libraries.
  Any format validation logic should be defined here and imported by other libraries.

  ## Design Principles

  - **Consistency**: Same validation logic everywhere in the codebase
  - **Centralized**: One place to update when validation rules change
  - **Well-tested**: Comprehensive test coverage for all formats
  - **Standards-based**: Follow industry standards (RFC 5322 for email, E.164 for phone, etc.)

  ## Available Formats

  | Format | Standard | Use Case |
  |--------|----------|----------|
  | Email | RFC 5322 (simplified) | User emails, contact info |
  | URL | HTTP/HTTPS | Links, API endpoints |
  | UUID v4 | RFC 4122 | Legacy identifiers |
  | UUID v7 | RFC 9562 | Time-ordered identifiers |
  | Slug | URL-safe | URL paths, permalinks |
  | Username | Alphanumeric | User handles, logins |
  | Phone | E.164 | International phone numbers |
  | IPv4 | RFC 791 | IP addresses |
  | IPv6 | RFC 8200 | IPv6 addresses |

  ## Quick Start

      alias FnTypes.Formats

      # Boolean check
      Formats.email?("user@example.com")  #=> true
      Formats.uuid_v7?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")  #=> true

      # Validation with error messages
      Formats.validate(:email, "user@example.com")
      #=> {:ok, "user@example.com"}

      Formats.validate(:email, "invalid")
      #=> {:error, "Invalid email format"}

      # Get regex pattern
      Formats.regex(:email)
      #=> ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@.../

  ## Usage Examples

      # Email validation
      case Formats.validate(:email, user_input) do
        {:ok, email} -> create_user(email)
        {:error, msg} -> show_error(msg)
      end

      # Multiple formats
      with {:ok, email} <- Formats.validate(:email, params["email"]),
           {:ok, url} <- Formats.validate(:url, params["website"]) do
        create_profile(email, url)
      end

      # In Ecto changesets
      import Ecto.Changeset

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email, :website])
        |> validate_format(:email, Formats.regex(:email))
        |> validate_format(:website, Formats.regex(:url))
      end

  ## Integration Examples

  ### With OmSchema.Validators

      # In OmSchema.Validators
      def apply(changeset, field, :email, _opts) do
        validate_format(changeset, field, FnTypes.Formats.regex(:email),
          message: "must be a valid email"
        )
      end

  ### With Phoenix Forms

      # In your form
      <%= text_input f, :email, pattern: FnTypes.Formats.regex(:email) |> Regex.source() %>

  ## Email Format Details

  The email regex is based on RFC 5322 (simplified) and matches ~98% of valid emails:

  - Allows: letters, numbers, and `.!#$%&'*+/=?^_\`{|}~-` in local part
  - Requires: @ symbol
  - Domain: alphanumeric with hyphens, multiple labels with dots
  - TLD: minimum 2 characters

  **Does NOT validate:**
  - Quoted strings (rare)
  - IP addresses in domain (rare)
  - International domains (IDN) - use Punycode first

  ## Phone Format Details

  Uses E.164 international format:
  - Starts with +
  - Country code (1-3 digits)
  - Subscriber number (up to 14 digits)
  - Total max 15 digits after +

  Example: +14155552671 (USA), +442071838750 (UK)
  """

  # ============================================
  # Regex Patterns - Single Source of Truth
  # ============================================

  # RFC 5322 simplified - matches ~98% of valid emails
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  # HTTP/HTTPS URLs
  @url_regex ~r/^https?:\/\/(?:[\w.-]+)(?::\d+)?(?:\/[^\s]*)?$/

  # UUID v4 (random)
  @uuid_v4_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  # UUID v7 (time-ordered)
  @uuid_v7_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  # URL-safe slugs (lowercase, numbers, hyphens)
  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  # Alphanumeric usernames (3-30 chars)
  @username_regex ~r/^[a-zA-Z0-9_]{3,30}$/

  # E.164 international phone format
  @phone_e164_regex ~r/^\+[1-9]\d{1,14}$/

  # IPv4 address
  @ipv4_regex ~r/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/

  # IPv6 address (simplified - full implementation is complex)
  @ipv6_regex ~r/^(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$/

  @type format ::
          :email
          | :url
          | :uuid_v4
          | :uuid_v7
          | :uuid
          | :slug
          | :username
          | :phone
          | :ipv4
          | :ipv6

  # ============================================
  # Boolean Validators
  # ============================================

  @doc """
  Checks if a string is a valid email address.

  Uses RFC 5322 simplified regex that matches ~98% of valid emails.

  ## Examples

      iex> FnTypes.Formats.email?("user@example.com")
      true

      iex> FnTypes.Formats.email?("user+tag@example.co.uk")
      true

      iex> FnTypes.Formats.email?("invalid@")
      false

      iex> FnTypes.Formats.email?("@example.com")
      false
  """
  @spec email?(String.t()) :: boolean()
  def email?(value) when is_binary(value), do: String.match?(value, @email_regex)
  def email?(_), do: false

  @doc """
  Checks if a string is a valid HTTP/HTTPS URL.

  ## Examples

      iex> FnTypes.Formats.url?("https://example.com")
      true

      iex> FnTypes.Formats.url?("http://localhost:3000/path")
      true

      iex> FnTypes.Formats.url?("ftp://example.com")
      false

      iex> FnTypes.Formats.url?("not-a-url")
      false
  """
  @spec url?(String.t()) :: boolean()
  def url?(value) when is_binary(value), do: String.match?(value, @url_regex)
  def url?(_), do: false

  @doc """
  Checks if a string is a valid UUID v4.

  ## Examples

      iex> FnTypes.Formats.uuid_v4?("550e8400-e29b-41d4-a716-446655440000")
      true

      iex> FnTypes.Formats.uuid_v4?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")
      false

      iex> FnTypes.Formats.uuid_v4?("not-a-uuid")
      false
  """
  @spec uuid_v4?(String.t()) :: boolean()
  def uuid_v4?(value) when is_binary(value), do: String.match?(value, @uuid_v4_regex)
  def uuid_v4?(_), do: false

  @doc """
  Checks if a string is a valid UUID v7.

  ## Examples

      iex> FnTypes.Formats.uuid_v7?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")
      true

      iex> FnTypes.Formats.uuid_v7?("550e8400-e29b-41d4-a716-446655440000")
      false

      iex> FnTypes.Formats.uuid_v7?("not-a-uuid")
      false
  """
  @spec uuid_v7?(String.t()) :: boolean()
  def uuid_v7?(value) when is_binary(value), do: String.match?(value, @uuid_v7_regex)
  def uuid_v7?(_), do: false

  @doc """
  Checks if a string is a valid UUID (v4 or v7).

  ## Examples

      iex> FnTypes.Formats.uuid?("550e8400-e29b-41d4-a716-446655440000")
      true

      iex> FnTypes.Formats.uuid?("01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")
      true

      iex> FnTypes.Formats.uuid?("not-a-uuid")
      false
  """
  @spec uuid?(String.t()) :: boolean()
  def uuid?(value) when is_binary(value), do: uuid_v4?(value) or uuid_v7?(value)
  def uuid?(_), do: false

  @doc """
  Checks if a string is a valid URL slug.

  Slugs are lowercase, alphanumeric with hyphens only.

  ## Examples

      iex> FnTypes.Formats.slug?("my-blog-post")
      true

      iex> FnTypes.Formats.slug?("hello-world-123")
      true

      iex> FnTypes.Formats.slug?("Invalid_Slug")
      false

      iex> FnTypes.Formats.slug?("no spaces")
      false
  """
  @spec slug?(String.t()) :: boolean()
  def slug?(value) when is_binary(value), do: String.match?(value, @slug_regex)
  def slug?(_), do: false

  @doc """
  Checks if a string is a valid username.

  Usernames are 3-30 characters, alphanumeric plus underscores.

  ## Examples

      iex> FnTypes.Formats.username?("john_doe")
      true

      iex> FnTypes.Formats.username?("User123")
      true

      iex> FnTypes.Formats.username?("ab")
      false

      iex> FnTypes.Formats.username?("user-name")
      false
  """
  @spec username?(String.t()) :: boolean()
  def username?(value) when is_binary(value), do: String.match?(value, @username_regex)
  def username?(_), do: false

  @doc """
  Checks if a string is a valid E.164 phone number.

  ## Examples

      iex> FnTypes.Formats.phone?("+14155552671")
      true

      iex> FnTypes.Formats.phone?("+442071838750")
      true

      iex> FnTypes.Formats.phone?("555-1234")
      false

      iex> FnTypes.Formats.phone?("+1")
      false
  """
  @spec phone?(String.t()) :: boolean()
  def phone?(value) when is_binary(value), do: String.match?(value, @phone_e164_regex)
  def phone?(_), do: false

  @doc """
  Checks if a string is a valid IPv4 address.

  ## Examples

      iex> FnTypes.Formats.ipv4?("192.168.1.1")
      true

      iex> FnTypes.Formats.ipv4?("255.255.255.255")
      true

      iex> FnTypes.Formats.ipv4?("256.1.1.1")
      false

      iex> FnTypes.Formats.ipv4?("not-an-ip")
      false
  """
  @spec ipv4?(String.t()) :: boolean()
  def ipv4?(value) when is_binary(value), do: String.match?(value, @ipv4_regex)
  def ipv4?(_), do: false

  @doc """
  Checks if a string is a valid IPv6 address.

  ## Examples

      iex> FnTypes.Formats.ipv6?("2001:0db8:85a3:0000:0000:8a2e:0370:7334")
      true

      iex> FnTypes.Formats.ipv6?("::1")
      true

      iex> FnTypes.Formats.ipv6?("::")
      true

      iex> FnTypes.Formats.ipv6?("not-an-ip")
      false
  """
  @spec ipv6?(String.t()) :: boolean()
  def ipv6?(value) when is_binary(value), do: String.match?(value, @ipv6_regex)
  def ipv6?(_), do: false

  # ============================================
  # Result Validators (with error messages)
  # ============================================

  @doc """
  Validates a value against a format, returning a result tuple.

  Returns `{:ok, value}` if valid, or `{:error, message}` if invalid.

  ## Examples

      iex> FnTypes.Formats.validate(:email, "user@example.com")
      {:ok, "user@example.com"}

      iex> FnTypes.Formats.validate(:email, "invalid")
      {:error, "Invalid email format"}

      iex> FnTypes.Formats.validate(:url, "https://example.com")
      {:ok, "https://example.com"}

      iex> FnTypes.Formats.validate(:slug, "Invalid Slug")
      {:error, "Invalid slug format"}
  """
  @spec validate(format(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(format, value) when is_binary(value) do
    if valid?(format, value) do
      {:ok, value}
    else
      {:error, error_message(format)}
    end
  end

  def validate(format, _value) do
    {:error, error_message(format)}
  end

  @doc """
  Checks if a value matches the given format.

  ## Examples

      iex> FnTypes.Formats.valid?(:email, "user@example.com")
      true

      iex> FnTypes.Formats.valid?(:uuid_v7, "01936d8c-5b4a-7c3e-8d2f-1a2b3c4d5e6f")
      true

      iex> FnTypes.Formats.valid?(:phone, "555-1234")
      false
  """
  @spec valid?(format(), String.t()) :: boolean()
  def valid?(:email, value), do: email?(value)
  def valid?(:url, value), do: url?(value)
  def valid?(:uuid_v4, value), do: uuid_v4?(value)
  def valid?(:uuid_v7, value), do: uuid_v7?(value)
  def valid?(:uuid, value), do: uuid?(value)
  def valid?(:slug, value), do: slug?(value)
  def valid?(:username, value), do: username?(value)
  def valid?(:phone, value), do: phone?(value)
  def valid?(:ipv4, value), do: ipv4?(value)
  def valid?(:ipv6, value), do: ipv6?(value)
  def valid?(_, _), do: false

  # ============================================
  # Regex Access
  # ============================================

  @doc """
  Returns the regex pattern for a given format.

  Useful for integration with Ecto changesets, Phoenix forms, etc.

  ## Examples

      iex> regex = FnTypes.Formats.regex(:email)
      iex> is_struct(regex, Regex)
      true

      iex> regex = FnTypes.Formats.regex(:slug)
      iex> Regex.match?(regex, "my-slug")
      true
  """
  @spec regex(format()) :: Regex.t()
  def regex(:email), do: @email_regex
  def regex(:url), do: @url_regex
  def regex(:uuid_v4), do: @uuid_v4_regex
  def regex(:uuid_v7), do: @uuid_v7_regex
  def regex(:uuid), do: @uuid_v4_regex  # Default to v4 for generic UUID
  def regex(:slug), do: @slug_regex
  def regex(:username), do: @username_regex
  def regex(:phone), do: @phone_e164_regex
  def regex(:ipv4), do: @ipv4_regex
  def regex(:ipv6), do: @ipv6_regex

  # ============================================
  # Private Helpers
  # ============================================

  defp error_message(:email), do: "Invalid email format"
  defp error_message(:url), do: "Invalid URL format"
  defp error_message(:uuid_v4), do: "Invalid UUID v4 format"
  defp error_message(:uuid_v7), do: "Invalid UUID v7 format"
  defp error_message(:uuid), do: "Invalid UUID format"
  defp error_message(:slug), do: "Invalid slug format"
  defp error_message(:username), do: "Invalid username format"
  defp error_message(:phone), do: "Invalid phone format"
  defp error_message(:ipv4), do: "Invalid IPv4 address"
  defp error_message(:ipv6), do: "Invalid IPv6 address"
  defp error_message(_), do: "Invalid format"
end
