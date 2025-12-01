defmodule Events.Core.Schema.Mappers do
  @moduledoc """
  Common mapper functions for field transformations.

  Mappers are functions that transform field values. They are applied left to right
  when specified in the `mappers:` option.

  ## Usage

      field :email, :string, mappers: [trim(), downcase()]
      field :name, :string, mappers: [trim(), titlecase()]

  ## Built-in Mappers

  - `trim/0` - Remove leading/trailing whitespace
  - `downcase/0` - Convert to lowercase
  - `upcase/0` - Convert to uppercase
  - `capitalize/0` - Capitalize first letter
  - `titlecase/0` - Capitalize each word
  - `squish/0` - Trim and collapse multiple spaces
  - `slugify/0` - Convert to URL-safe slug

  ## Custom Mappers

  You can also use anonymous functions:

      field :code, :string, mappers: [trim(), fn x -> String.replace(x, "-", "_") end]

  Or define your own mapper functions:

      def remove_dashes(value), do: String.replace(value, "-", "")

      field :code, :string, mappers: [trim(), &remove_dashes/1]
  """

  @doc """
  Remove leading and trailing whitespace.

  Can be used as a mapper or called directly.

  ## Example

      # As mapper name (recommended for schema fields)
      field :name, :string, mappers: [:trim, :downcase]

      # As function
      iex> trim().("  hello  ")
      "hello"
  """
  def trim do
    &String.trim/1
  end

  @doc """
  Convert string to lowercase.

  ## Example

      iex> downcase().("HELLO")
      "hello"
  """
  def downcase do
    &String.downcase/1
  end

  @doc """
  Convert string to uppercase.

  ## Example

      iex> upcase().("hello")
      "HELLO"
  """
  def upcase do
    &String.upcase/1
  end

  @doc """
  Capitalize first letter of string.

  ## Example

      iex> capitalize().("hello world")
      "Hello world"
  """
  def capitalize do
    &String.capitalize/1
  end

  @doc """
  Capitalize first letter of each word.

  ## Example

      iex> titlecase().("hello world")
      "Hello World"
  """
  def titlecase do
    fn value ->
      value
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")
    end
  end

  @doc """
  Trim whitespace and collapse multiple spaces into one.

  ## Example

      iex> squish().("  hello   world  ")
      "hello world"
  """
  def squish do
    fn value ->
      value
      |> String.trim()
      |> String.replace(~r/\s+/, " ")
    end
  end

  @doc """
  Convert string to URL-safe slug.

  ## Example

      iex> slugify().("Hello World!")
      "hello-world"

      # With uniqueness (Medium.com style)
      iex> slugify(uniquify: true).("Hello World!")
      "hello-world-a3x9m2"

      # Custom suffix length
      iex> slugify(uniquify: 8).("Hello World!")
      "hello-world-a1b2c3d4"
  """
  def slugify(opts \\ []) do
    fn value ->
      Events.Core.Schema.Slugify.slugify(value, opts)
    end
  end

  @doc """
  Remove all non-numeric characters.

  ## Example

      iex> digits_only().("abc123def456")
      "123456"
  """
  def digits_only do
    fn value ->
      String.replace(value, ~r/[^0-9]/, "")
    end
  end

  @doc """
  Remove all non-alphanumeric characters.

  ## Example

      iex> alphanumeric_only().("hello-world_123!")
      "helloworld123"
  """
  def alphanumeric_only do
    fn value ->
      String.replace(value, ~r/[^a-zA-Z0-9]/, "")
    end
  end

  @doc """
  Replace multiple occurrences of a pattern with a single replacement.

  ## Example

      iex> replace(~r/-+/, "-").("hello---world")
      "hello-world"
  """
  def replace(pattern, replacement) do
    fn value ->
      String.replace(value, pattern, replacement)
    end
  end

  @doc """
  Compose multiple mappers into a single mapper.

  ## Example

      email_normalizer = compose([trim(), downcase()])
      field :email, :string, mappers: [email_normalizer]
  """
  def compose(mappers) when is_list(mappers) do
    fn value ->
      Enum.reduce(mappers, value, fn mapper, acc ->
        mapper.(acc)
      end)
    end
  end
end
