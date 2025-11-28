defmodule Events.Test.PropertyHelpers do
  @moduledoc """
  Helpers for property-based testing with StreamData.

  Provides common generators and property testing patterns
  specific to the Events application.

  ## Usage

      use Events.Test.PropertyHelpers

  Or in a test:

      use ExUnitProperties

      property "email validation" do
        check all email <- email_generator() do
          assert Email.valid?(email)
        end
      end

  ## Custom Generators

  - `email_generator/0` - Valid email addresses
  - `slug_generator/0` - URL-safe slugs
  - `phone_generator/0` - Phone numbers
  - `uuid_generator/0` - UUID strings
  - `money_generator/0` - Decimal money values
  - `status_generator/0` - Common status atoms
  - `datetime_generator/0` - DateTime values
  - `s3_uri_generator/0` - S3 URIs
  """

  use ExUnitProperties
  import Bitwise

  # ============================================
  # String Generators
  # ============================================

  @doc """
  Generates valid email addresses.
  """
  def email_generator do
    gen all(
          local <- string(:alphanumeric, min_length: 1, max_length: 20),
          domain <- string(:alphanumeric, min_length: 1, max_length: 10),
          tld <- member_of(["com", "org", "net", "io", "dev", "co"])
        ) do
      "#{local}@#{domain}.#{tld}" |> String.downcase()
    end
  end

  @doc """
  Generates URL-safe slugs.
  """
  def slug_generator do
    gen all(
          words <-
            list_of(string(:alphanumeric, min_length: 1, max_length: 10),
              min_length: 1,
              max_length: 5
            )
        ) do
      words
      |> Enum.join("-")
      |> String.downcase()
    end
  end

  @doc """
  Generates phone numbers (US format).
  """
  def phone_generator do
    gen all(
          area <- integer(200..999),
          exchange <- integer(200..999),
          subscriber <- integer(1000..9999)
        ) do
      "#{area}-#{exchange}-#{subscriber}"
    end
  end

  @doc """
  Generates UUID v4 strings.
  """
  def uuid_generator do
    gen all(bytes <- binary(length: 16)) do
      <<a::32, b::16, _::4, c::12, _::2, d::62>> = bytes

      :io_lib.format(
        "~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b",
        [a, b, c, (d &&& 0x3FFF) ||| 0x8000, d >>> 2]
      )
      |> IO.iodata_to_binary()
    end
  end

  @doc """
  Generates usernames (alphanumeric with underscores).
  """
  def username_generator do
    gen all(
          chars <-
            list_of(one_of([string(:alphanumeric, length: 1), constant("_")]),
              min_length: 3,
              max_length: 20
            ),
          first <- string(:alpha, length: 1)
        ) do
      first <> Enum.join(chars)
    end
  end

  # ============================================
  # Numeric Generators
  # ============================================

  @doc """
  Generates decimal money values (positive, 2 decimal places).
  """
  def money_generator do
    gen all(
          dollars <- integer(0..10_000),
          cents <- integer(0..99)
        ) do
      Decimal.new("#{dollars}.#{String.pad_leading(to_string(cents), 2, "0")}")
    end
  end

  @doc """
  Generates percentages (0.0 to 100.0).
  """
  def percentage_generator do
    gen all(value <- float(min: 0.0, max: 100.0)) do
      Float.round(value, 2)
    end
  end

  @doc """
  Generates positive integers within a range.
  """
  def positive_integer_generator(max \\ 1_000_000) do
    integer(1..max)
  end

  # ============================================
  # Domain Generators
  # ============================================

  @doc """
  Generates common status atoms.
  """
  def status_generator do
    member_of([:pending, :active, :inactive, :archived, :deleted, :draft, :published])
  end

  @doc """
  Generates DateTime values within a reasonable range.
  """
  def datetime_generator do
    gen all(
          year <- integer(2020..2030),
          month <- integer(1..12),
          day <- integer(1..28),
          hour <- integer(0..23),
          minute <- integer(0..59),
          second <- integer(0..59)
        ) do
      {:ok, dt} = NaiveDateTime.new(year, month, day, hour, minute, second)
      DateTime.from_naive!(dt, "Etc/UTC")
    end
  end

  @doc """
  Generates Date values.
  """
  def date_generator do
    gen all(
          year <- integer(2020..2030),
          month <- integer(1..12),
          day <- integer(1..28)
        ) do
      Date.new!(year, month, day)
    end
  end

  @doc """
  Generates S3 URIs.
  """
  def s3_uri_generator do
    gen all(
          bucket <- string(:alphanumeric, min_length: 3, max_length: 20),
          path_segments <-
            list_of(string(:alphanumeric, min_length: 1, max_length: 10),
              min_length: 1,
              max_length: 5
            ),
          filename <- string(:alphanumeric, min_length: 1, max_length: 20),
          extension <- member_of(["txt", "json", "csv", "pdf", "jpg", "png"])
        ) do
      path = Enum.join(path_segments, "/")
      "s3://#{String.downcase(bucket)}/#{path}/#{filename}.#{extension}"
    end
  end

  # ============================================
  # Composite Generators
  # ============================================

  @doc """
  Generates user attribute maps.
  """
  def user_attrs_generator do
    gen all(
          email <- email_generator(),
          name <- string(:alphanumeric, min_length: 2, max_length: 50),
          status <- status_generator()
        ) do
      %{
        email: email,
        name: name,
        status: status
      }
    end
  end

  @doc """
  Generates optional values (value or nil).
  """
  def optional(generator) do
    one_of([generator, constant(nil)])
  end

  @doc """
  Generates maps with string keys from atom-keyed map generator.
  """
  def string_keys(map_generator) do
    gen all(map <- map_generator) do
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end
  end

  # ============================================
  # Shrinking Helpers
  # ============================================

  @doc """
  Runs a property test with custom options.

  ## Options

  - `:max_runs` - Maximum number of test runs (default: 100)
  - `:max_shrinking_steps` - Maximum shrinking iterations (default: 100)

  ## Examples

      property_test "validates emails", max_runs: 500 do
        check all email <- email_generator() do
          assert Email.valid?(email)
        end
      end
  """
  defmacro property_test(name, opts \\ [], do: block) do
    max_runs = Keyword.get(opts, :max_runs, 100)
    max_shrinking = Keyword.get(opts, :max_shrinking_steps, 100)

    quote do
      property unquote(name) do
        check(
          all(
            unquote(block),
            max_runs: unquote(max_runs),
            max_shrinking_steps: unquote(max_shrinking)
          )
        )
      end
    end
  end

  defmacro __using__(_opts) do
    quote do
      use ExUnitProperties
      import Events.Test.PropertyHelpers
    end
  end
end
