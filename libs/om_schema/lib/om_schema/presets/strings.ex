defmodule OmSchema.Presets.Strings do
  @moduledoc """
  Enhanced string field presets for common use cases.

  ## Usage

      import OmSchema.Presets.Strings

      schema "users" do
        field :first_name, :string, preset: name()
        field :description, :string, preset: short_text()
        field :bio, :string, preset: long_text()
        field :search_query, :string, preset: search_term()
      end
  """

  @doc """
  Name field preset (first name, last name, etc).

  Options:
  - `required: true`
  - `min_length: 2`
  - `max_length: 100`
  - `normalize: [:trim, :titlecase]`
  """
  def name(custom_opts \\ []) do
    [
      required: true,
      min_length: 2,
      max_length: 100,
      normalize: [:trim, :titlecase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Full name field preset.

  Options:
  - `required: true`
  - `min_length: 2`
  - `max_length: 200`
  - `normalize: [:trim, :squish]` - Collapse multiple spaces
  """
  def full_name(custom_opts \\ []) do
    [
      required: true,
      min_length: 2,
      max_length: 200,
      normalize: [:trim, :squish]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Title field preset (post titles, article titles, etc).

  Options:
  - `required: true`
  - `min_length: 3`
  - `max_length: 255`
  - `normalize: [:trim, :squish]`
  """
  def title(custom_opts \\ []) do
    [
      required: true,
      min_length: 3,
      max_length: 255,
      normalize: [:trim, :squish]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Short text field preset (descriptions, summaries, etc).

  Options:
  - `required: false`
  - `max_length: 500`
  - `normalize: [:trim, :squish]`
  """
  def short_text(custom_opts \\ []) do
    [
      required: false,
      max_length: 500,
      normalize: [:trim, :squish]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Medium text field preset.

  Options:
  - `required: false`
  - `max_length: 2000`
  - `normalize: [:trim]`
  """
  def medium_text(custom_opts \\ []) do
    [
      required: false,
      max_length: 2000,
      normalize: [:trim]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Long text field preset (blog posts, articles, etc).

  Options:
  - `required: false`
  - `max_length: 50000`
  - `normalize: [:trim]`
  """
  def long_text(custom_opts \\ []) do
    [
      required: false,
      max_length: 50_000,
      normalize: [:trim]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Search term field preset.

  Options:
  - `required: true`
  - `min_length: 1`
  - `max_length: 255`
  - `normalize: [:trim, :squish]`
  """
  def search_term(custom_opts \\ []) do
    [
      required: true,
      min_length: 1,
      max_length: 255,
      normalize: [:trim, :squish]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Display name preset (public usernames, profile names).

  Options:
  - `required: true`
  - `min_length: 3`
  - `max_length: 50`
  - `normalize: [:trim, :squish]`
  """
  def display_name(custom_opts \\ []) do
    [
      required: true,
      min_length: 3,
      max_length: 50,
      normalize: [:trim, :squish]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Tag field preset (single tag).

  Options:
  - `required: true`
  - `min_length: 2`
  - `max_length: 50`
  - `normalize: [:trim, :downcase]`
  - `format: ~r/^[a-z0-9-]+$/`
  """
  def tag(custom_opts \\ []) do
    [
      required: true,
      min_length: 2,
      max_length: 50,
      normalize: [:trim, :downcase],
      format: ~r/^[a-z0-9-]+$/
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Code field preset (verification codes, promo codes, etc).

  Options:
  - `required: true`
  - `min_length: 4`
  - `max_length: 20`
  - `normalize: [:trim, :upcase, :alphanumeric_only]`
  """
  def code(custom_opts \\ []) do
    [
      required: true,
      min_length: 4,
      max_length: 20,
      normalize: [:trim, :upcase, :alphanumeric_only]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Address line preset (street address).

  Options:
  - `required: false`
  - `min_length: 3`
  - `max_length: 255`
  - `normalize: [:trim, :squish]`
  """
  def address_line(custom_opts \\ []) do
    [
      required: false,
      min_length: 3,
      max_length: 255,
      normalize: [:trim, :squish]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  City name preset.

  Options:
  - `required: false`
  - `min_length: 2`
  - `max_length: 100`
  - `normalize: [:trim, :titlecase]`
  """
  def city(custom_opts \\ []) do
    [
      required: false,
      min_length: 2,
      max_length: 100,
      normalize: [:trim, :titlecase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Postal/ZIP code preset.

  Options:
  - `required: false`
  - `min_length: 3`
  - `max_length: 10`
  - `normalize: [:trim, :upcase]`
  """
  def postal_code(custom_opts \\ []) do
    [
      required: false,
      min_length: 3,
      max_length: 10,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Color hex code preset (#RRGGBB format).

  Options:
  - `required: false`
  - `format: :hex_color`
  - `normalize: [:trim, :upcase]`
  """
  def color_hex(custom_opts \\ []) do
    [
      required: false,
      format: :hex_color,
      normalize: [:trim, :upcase]
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Notes/comments field preset.

  Options:
  - `required: false`
  - `max_length: 5000`
  - `normalize: [:trim]`
  """
  def notes(custom_opts \\ []) do
    [
      required: false,
      max_length: 5000,
      normalize: [:trim]
    ]
    |> merge_opts(custom_opts)
  end

  defp merge_opts(defaults, custom_opts) do
    # Custom options override defaults
    Keyword.merge(defaults, custom_opts)
  end
end
