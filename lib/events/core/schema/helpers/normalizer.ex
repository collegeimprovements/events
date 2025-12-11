defmodule Events.Core.Schema.Helpers.Normalizer do
  @moduledoc """
  Helper module for normalizing field values.

  Provides various normalization transformations like trim, downcase, slugify, etc.
  Supports chaining multiple normalizations together.

  ## Type-Specific Normalizers

  The module provides domain-specific normalizers for common field types:

  - `normalize_email/1` - Trims and lowercases email addresses
  - `normalize_phone/1` - Strips non-digit characters (except +)
  - `normalize_url/1` - Trims and lowercases URLs
  - `normalize_slug/1` - Converts to URL-safe slug format

  ## Examples

      # General normalization with options
      normalize("  Hello World  ", normalize: [:trim, :downcase])
      #=> "hello world"

      # Type-specific normalizers
      normalize_email("  User@Example.COM  ")
      #=> "user@example.com"

      normalize_phone("+1 (555) 123-4567")
      #=> "+15551234567"
  """

  alias Events.Core.Schema.Slugify

  @doc """
  Apply normalization to a string value based on options.

  Supports:
  - `mappers:` - List of mapper functions applied left to right (recommended)
  - `normalize:` - Legacy normalization options
  - Auto-trim by default (disable with `trim: false`)

  ## Examples

      # Using mappers (recommended)
      normalize(value, mappers: [&String.trim/1, &String.downcase/1])

      # Using normalize (legacy)
      normalize(value, normalize: [:trim, :downcase])

      # Disable auto-trim
      normalize(value, trim: false)
  """
  def normalize(value, opts) when is_binary(value) do
    cond do
      # If mappers is present, use mappers (no auto-trim, mappers control everything)
      opts[:mappers] != nil ->
        apply_mappers(value, opts[:mappers])

      # Legacy normalize path with auto-trim
      true ->
        value
        |> maybe_trim(opts)
        |> apply_normalize(opts)
    end
  end

  def normalize(value, _opts), do: value

  # Apply mappers left to right
  defp apply_mappers(value, mappers) when is_list(mappers) do
    Enum.reduce(mappers, value, fn mapper, acc ->
      apply_mapper(acc, mapper)
    end)
  end

  defp apply_mappers(value, mapper) do
    apply_mapper(value, mapper)
  end

  # Apply a single mapper
  defp apply_mapper(value, fun) when is_function(fun, 1) do
    fun.(value)
  end

  defp apply_mapper(value, mapper) when is_atom(mapper) do
    # Support atom shortcuts like :trim, :downcase
    apply_single(value, mapper)
  end

  defp apply_mapper(value, {mapper, opts}) when is_atom(mapper) and is_list(opts) do
    # Support tuple format like {:slugify, uniquify: true}
    apply_single(value, {mapper, opts})
  end

  defp apply_mapper(value, _), do: value

  # Trim by default unless explicitly disabled with trim: false
  defp maybe_trim(value, opts) do
    if Keyword.get(opts, :trim, true) == false do
      value
    else
      String.trim(value)
    end
  end

  # Apply normalize transformations
  defp apply_normalize(value, opts) do
    case opts[:normalize] do
      nil ->
        value

      normalizers when is_list(normalizers) ->
        # Multiple normalizations - apply in order
        Enum.reduce(normalizers, value, fn normalizer, acc ->
          apply_single(acc, normalizer)
        end)

      fun when is_function(fun, 1) ->
        # Direct function passed
        fun.(value)

      normalizer ->
        apply_single(value, normalizer)
    end
  end

  # Single normalization transformations

  defp apply_single(value, :downcase), do: String.downcase(value)
  defp apply_single(value, :upcase), do: String.upcase(value)
  defp apply_single(value, :capitalize), do: String.capitalize(value)

  defp apply_single(value, :titlecase) do
    value
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp apply_single(value, :trim), do: String.trim(value)

  defp apply_single(value, :squish) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp apply_single(value, :slugify), do: Slugify.slugify(value)

  defp apply_single(value, {:slugify, opts_or_module}) when is_list(opts_or_module) do
    Slugify.slugify(value, opts_or_module)
  end

  defp apply_single(value, {:slugify, module}) when is_atom(module) do
    if Code.ensure_loaded?(module) && function_exported?(module, :slugify, 1) do
      module.slugify(value)
    else
      # Fallback to default slugify
      Slugify.slugify(value)
    end
  end

  defp apply_single(value, {:custom, fun}) when is_function(fun, 1) do
    fun.(value)
  end

  defp apply_single(value, :alphanumeric_only) do
    String.replace(value, ~r/[^a-zA-Z0-9]/, "")
  end

  defp apply_single(value, :digits_only) do
    String.replace(value, ~r/[^0-9]/, "")
  end

  defp apply_single(value, _), do: value

  # ============================================
  # Type-Specific Normalizers
  # ============================================

  @doc """
  Normalizes an email address.

  - Trims leading/trailing whitespace
  - Converts to lowercase

  ## Examples

      iex> normalize_email("  User@Example.COM  ")
      "user@example.com"

      iex> normalize_email(nil)
      nil
  """
  @spec normalize_email(String.t() | nil) :: String.t() | nil
  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  def normalize_email(value), do: value

  @doc """
  Normalizes a phone number.

  - Removes all non-digit characters except leading +
  - Preserves international prefix

  ## Examples

      iex> normalize_phone("+1 (555) 123-4567")
      "+15551234567"

      iex> normalize_phone("555.123.4567")
      "5551234567"

      iex> normalize_phone(nil)
      nil
  """
  @spec normalize_phone(String.t() | nil) :: String.t() | nil
  def normalize_phone(phone) when is_binary(phone) do
    String.replace(phone, ~r/[^\d+]/, "")
  end

  def normalize_phone(value), do: value

  @doc """
  Normalizes a URL.

  - Trims leading/trailing whitespace
  - Converts to lowercase

  ## Examples

      iex> normalize_url("  HTTPS://Example.COM/Path  ")
      "https://example.com/path"

      iex> normalize_url(nil)
      nil
  """
  @spec normalize_url(String.t() | nil) :: String.t() | nil
  def normalize_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.downcase()
  end

  def normalize_url(value), do: value

  @doc """
  Normalizes a value to a URL-safe slug.

  - Trims whitespace
  - Converts to lowercase
  - Replaces non-word characters with hyphens
  - Collapses multiple hyphens
  - Removes leading/trailing hyphens

  ## Examples

      iex> normalize_slug("  Hello World!  ")
      "hello-world"

      iex> normalize_slug("My  --  Post Title")
      "my-post-title"

      iex> normalize_slug(nil)
      nil
  """
  @spec normalize_slug(String.t() | nil) :: String.t() | nil
  def normalize_slug(slug) when is_binary(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^\w-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  def normalize_slug(value), do: value
end
