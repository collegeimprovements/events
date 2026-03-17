defmodule OmMigration.FieldBuilders.Profile do
  @moduledoc """
  Builds profile fields for migrations.

  Profile fields store user/entity profile information:
  bio, avatar, location/address, social links.

  ## Options

  - `:only` - List of profile types to include
  - `:except` - List of profile types to exclude

  ## Available Profile Types

  - `:bio` - Biography/description text field
  - `:avatar` - Avatar URL and thumbnail URL
  - `:location` - Address and geo fields
  - `:social` - Social media links

  ## Examples

      create_table(:users)
      |> Profile.add()                        # All profile fields
      |> Profile.add(only: [:bio, :avatar])   # Specific fields
      |> Profile.add(except: [:social])       # Exclude social
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @all_profile_types [:bio, :avatar, :location, :social]

  @impl true
  def default_config do
    %{
      fields: @all_profile_types
    }
  end

  @impl true
  def build(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_type, acc ->
      add_profile_field(acc, field_type)
    end)
  end

  @impl true
  def indexes(config) do
    config.fields
    |> Enum.flat_map(&indexes_for_type/1)
  end

  # ============================================
  # Profile Field Builders
  # ============================================

  defp add_profile_field(token, :bio) do
    Token.add_field(token, :bio, :text, null: true, comment: "Biography/description")
  end

  defp add_profile_field(token, :avatar) do
    token
    |> Token.add_field(:avatar_url, :string, null: true, comment: "Avatar image URL")
    |> Token.add_field(:avatar_thumbnail_url, :string, null: true, comment: "Avatar thumbnail URL")
  end

  defp add_profile_field(token, :location) do
    token
    # Address fields
    |> Token.add_field(:street_address, :string, null: true, comment: "Street address")
    |> Token.add_field(:street_address_2, :string, null: true, comment: "Address line 2")
    |> Token.add_field(:city, :string, null: true, comment: "City")
    |> Token.add_field(:state, :string, null: true, comment: "State/province")
    |> Token.add_field(:postal_code, :string, null: true, comment: "Postal/ZIP code")
    |> Token.add_field(:country, :string, null: true, comment: "Country")
    |> Token.add_field(:country_code, :string, null: true, comment: "ISO country code")
    # Geo fields
    |> Token.add_field(:latitude, :decimal,
      precision: 10,
      scale: 8,
      null: true,
      comment: "Latitude"
    )
    |> Token.add_field(:longitude, :decimal,
      precision: 11,
      scale: 8,
      null: true,
      comment: "Longitude"
    )
  end

  defp add_profile_field(token, :social) do
    token
    |> Token.add_field(:website_url, :string, null: true, comment: "Personal website")
    |> Token.add_field(:twitter_handle, :string, null: true, comment: "Twitter/X handle")
    |> Token.add_field(:linkedin_url, :string, null: true, comment: "LinkedIn profile URL")
    |> Token.add_field(:github_username, :string, null: true, comment: "GitHub username")
  end

  # ============================================
  # Index Builders
  # ============================================

  defp indexes_for_type(:bio), do: []

  defp indexes_for_type(:avatar), do: []

  defp indexes_for_type(:location) do
    [
      {:location_city_index, [:city], []},
      {:location_country_index, [:country_code], []}
    ]
  end

  defp indexes_for_type(:social), do: []

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds profile fields to a migration token.

  ## Options

  - `:only` - List of profile types to include
  - `:except` - List of profile types to exclude

  ## Examples

      Profile.add(token)
      Profile.add(token, only: [:bio, :avatar])
      Profile.add(token, except: [:social])
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
