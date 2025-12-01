defmodule Events.Core.Schema.Slugify do
  @moduledoc """
  Default slugify implementation for Events.Core.Schema.
  Converts text to URL-friendly slugs with optional uniqueness suffix (Medium.com style).

  ## Examples

      iex> Slugify.slugify("Hello World!")
      "hello-world"

      iex> Slugify.slugify("café résumé")
      "cafe-resume"

      iex> Slugify.slugify("Hello World", uniquify: true)
      "hello-world-k3x9m2"  # Random 6-char suffix

      iex> Slugify.slugify("Hello World", separator: "_")
      "hello_world"

      iex> Slugify.slugify("Hello World", uniquify: 8, separator: "_")
      "hello_world_a1b2c3d4"  # Random 8-char suffix
  """

  @doc """
  Convert text to a URL-friendly slug.

  ## Options

    * `:separator` - Character to use as separator (default: "-")
    * `:lowercase` - Convert to lowercase (default: true)
    * `:ascii` - Transliterate to ASCII (default: true)
    * `:uniquify` - Add random suffix for uniqueness. Boolean or integer for suffix length (default: false)
    * `:truncate` - Maximum length before uniquify suffix (default: nil)

  ## Examples

      slugify("Hello World!")
      # => "hello-world"

      slugify("Hello World", uniquify: true)
      # => "hello-world-k3x9m2"

      slugify("Hello World", separator: "_", lowercase: false)
      # => "Hello_World"

      slugify("Very Long Title That Should Be Truncated", truncate: 20, uniquify: true)
      # => "very-long-title-that-a3b9f2"
  """
  def slugify(text, opts \\ []) when is_binary(text) do
    separator = Keyword.get(opts, :separator, "-")
    lowercase = Keyword.get(opts, :lowercase, true)
    ascii = Keyword.get(opts, :ascii, true)
    uniquify = Keyword.get(opts, :uniquify, false)
    truncate = Keyword.get(opts, :truncate)

    slug =
      text
      |> maybe_transliterate(ascii)
      |> maybe_downcase(lowercase)
      |> remove_special_chars(separator)
      |> collapse_separators(separator)
      |> trim_separators(separator)
      |> maybe_truncate(truncate, separator)

    if uniquify do
      suffix_length = if is_integer(uniquify), do: uniquify, else: 6
      suffix = generate_suffix(suffix_length)

      # If slug is empty, just return the suffix without separator
      if slug == "" do
        suffix
      else
        "#{slug}#{separator}#{suffix}"
      end
    else
      slug
    end
  end

  @doc """
  Generate a random alphanumeric suffix for uniqueness.

  ## Examples

      generate_suffix(6)
      # => "k3x9m2"

      generate_suffix(8)
      # => "a1b2c3d4"
  """
  def generate_suffix(length) when is_integer(length) and length > 0 do
    # Use lowercase letters and numbers (36 possible characters)
    chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    char_count = String.length(chars)

    1..length
    |> Enum.map(fn _ ->
      index = :rand.uniform(char_count) - 1
      String.at(chars, index)
    end)
    |> Enum.join()
  end

  # Private helpers

  defp maybe_transliterate(text, true) do
    # Convert accented characters to ASCII equivalents
    # é → e, ñ → n, ü → u, etc.
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
  end

  defp maybe_transliterate(text, false), do: text

  defp maybe_downcase(text, true), do: String.downcase(text)
  defp maybe_downcase(text, false), do: text

  defp remove_special_chars(text, separator) do
    # Keep word characters (\w = letters, digits, underscore) and the separator
    # Replace everything else with the separator
    pattern = ~r/[^\w#{Regex.escape(separator)}]+/u
    String.replace(text, pattern, separator)
  end

  defp collapse_separators(text, separator) do
    # Replace multiple consecutive separators with a single one
    pattern = ~r/#{Regex.escape(separator)}+/
    String.replace(text, pattern, separator)
  end

  defp trim_separators(text, separator) do
    String.trim(text, separator)
  end

  defp maybe_truncate(text, nil, _separator), do: text

  defp maybe_truncate(text, max_length, separator) when is_integer(max_length) do
    text
    |> String.slice(0, max_length)
    |> trim_separators(separator)
  end
end
