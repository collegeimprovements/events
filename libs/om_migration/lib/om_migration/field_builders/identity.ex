defmodule OmMigration.FieldBuilders.Identity do
  @moduledoc """
  Builds identity fields for migrations.

  Identity fields are the unique identifiers for users/entities:
  email, username, phone, name fields.

  ## Options

  - `:only` - List of identity types to include (default: all)
  - `:except` - List of identity types to exclude

  ## Available Identity Types

  - `:email` - Email address (citext, unique, required)
  - `:username` - Username (citext, unique, required)
  - `:phone` - Phone number (string, optional)
  - `:name` - Name fields (first_name, last_name, display_name)

  ## Examples

      create_table(:users)
      |> Identity.add()                            # All identity fields
      |> Identity.add(only: [:email, :username])   # Specific fields
      |> Identity.add(except: [:phone])            # Exclude phone
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @all_identity_types [:email, :username, :phone, :name]

  @impl true
  def default_config do
    %{
      fields: @all_identity_types,
      email_required: true,
      username_required: true
    }
  end

  @impl true
  def build(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_type, acc ->
      add_identity_field(acc, field_type, config)
    end)
  end

  @impl true
  def indexes(config) do
    config.fields
    |> Enum.flat_map(&indexes_for_type/1)
  end

  # ============================================
  # Identity Field Builders
  # ============================================

  defp add_identity_field(token, :email, config) do
    Token.add_field(token, :email, :citext,
      null: !config.email_required,
      comment: "User email address"
    )
  end

  defp add_identity_field(token, :username, config) do
    Token.add_field(token, :username, :citext,
      null: !config.username_required,
      comment: "Unique username"
    )
  end

  defp add_identity_field(token, :phone, _config) do
    Token.add_field(token, :phone, :string,
      null: true,
      comment: "Phone number"
    )
  end

  defp add_identity_field(token, :name, _config) do
    token
    |> Token.add_field(:first_name, :string, null: true, comment: "First name")
    |> Token.add_field(:last_name, :string, null: true, comment: "Last name")
    |> Token.add_field(:display_name, :string, null: true, comment: "Display name")
  end

  # ============================================
  # Index Builders
  # ============================================

  defp indexes_for_type(:email) do
    [{:email_unique_index, [:email], [unique: true]}]
  end

  defp indexes_for_type(:username) do
    [{:username_unique_index, [:username], [unique: true]}]
  end

  defp indexes_for_type(:phone) do
    [{:phone_index, [:phone], []}]
  end

  defp indexes_for_type(:name) do
    [{:name_index, [:last_name, :first_name], []}]
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds identity fields to a migration token.

  ## Options

  - `:only` - List of identity types to include
  - `:except` - List of identity types to exclude
  - `:email_required` - Whether email is required (default: true)
  - `:username_required` - Whether username is required (default: true)

  ## Examples

      Identity.add(token)
      Identity.add(token, only: [:email, :username])
      Identity.add(token, email_required: false)
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
