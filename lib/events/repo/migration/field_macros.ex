defmodule Events.Repo.Migration.FieldMacros do
  @moduledoc """
  Additional field macros using pattern matching and pipelines.

  Provides specialized field macros for common patterns like email,
  phone, address, and other domain-specific fields.
  """

  use Ecto.Migration

  @doc """
  Adds email field with proper configuration.

  ## Examples

      # Basic email field
      email_field()

      # Case-insensitive with unique constraint
      email_field(type: :citext, unique: true)

      # Multiple email fields
      email_field(name: :work_email)
      email_field(name: :personal_email)
  """
  defmacro email_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_name = Keyword.get(opts, :name, :email)
      field_type = Keyword.get(opts, :type, :string)
      required = Keyword.get(opts, :required, true)
      unique = Keyword.get(opts, :unique, false)

      add field_name, field_type, null: !required

      if unique do
        create unique_index(table_name(), field_name)
      end
    end
  end

  @doc """
  Adds phone field with formatting options.

  ## Examples

      # Basic phone field
      phone_field()

      # Multiple phone fields
      phone_field(name: :mobile_phone)
      phone_field(name: :work_phone, required: false)
  """
  defmacro phone_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldMacros.build_phone_field()
      |> case do
        {field, type, field_opts} ->
          add field, type, field_opts
      end
    end
  end

  @doc false
  def build_phone_field(opts) do
    {
      Keyword.get(opts, :name, :phone),
      Keyword.get(opts, :type, :string),
      [null: !Keyword.get(opts, :required, false)]
    }
  end

  @doc """
  Adds address fields with configurable components.

  ## Examples

      # Basic address fields
      address_fields()

      # With specific components
      address_fields(components: [:street, :city, :postal_code])

      # With prefix for multiple addresses
      address_fields(prefix: :billing)
      address_fields(prefix: :shipping)
  """
  defmacro address_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldMacros.build_address_fields()
      |> Enum.each(fn {field, type, field_opts} ->
        add field, type, field_opts
      end)
    end
  end

  @doc false
  def build_address_fields(opts) do
    prefix = Keyword.get(opts, :prefix)
    components = Keyword.get(opts, :components, default_address_components())

    components
    |> Enum.map(&build_address_field(&1, prefix))
  end

  defp default_address_components do
    [:street, :street2, :city, :state, :postal_code, :country]
  end

  defp build_address_field(component, nil) do
    {component, :string, [null: true]}
  end

  defp build_address_field(component, prefix) do
    {:"#{prefix}_#{component}", :string, [null: true]}
  end

  @doc """
  Adds URL/URI fields with validation support.

  ## Examples

      # Basic URL field
      url_field()

      # Multiple URL fields
      url_field(name: :website)
      url_field(name: :linkedin_url)
      url_field(name: :github_url)
  """
  defmacro url_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_name = Keyword.get(opts, :name, :url)
      required = Keyword.get(opts, :required, false)

      add field_name, :string, null: !required
    end
  end

  @doc """
  Adds slug field with unique constraint.

  ## Examples

      # Basic slug field
      slug_field()

      # Without unique constraint
      slug_field(unique: false)

      # Custom field name
      slug_field(name: :permalink)
  """
  defmacro slug_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_name = Keyword.get(opts, :name, :slug)
      unique = Keyword.get(opts, :unique, true)

      add field_name, :string, null: true

      if unique do
        create unique_index(table_name(), field_name)
      end
    end
  end

  @doc """
  Adds money/currency fields with precision.

  ## Examples

      # Basic price field
      money_field(:price)

      # With custom precision
      money_field(:amount, precision: 12, scale: 4)

      # Multiple money fields
      money_field(:cost)
      money_field(:tax)
      money_field(:total)
  """
  defmacro money_field(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      precision = Keyword.get(opts, :precision, 10)
      scale = Keyword.get(opts, :scale, 2)
      required = Keyword.get(opts, :required, false)

      add name, :decimal, precision: precision, scale: scale, null: !required
    end
  end

  @doc """
  Adds percentage field with constraints.

  ## Examples

      # Basic percentage field (0-100)
      percentage_field(:discount)

      # As decimal (0.0-1.0)
      percentage_field(:tax_rate, as: :decimal)
  """
  defmacro percentage_field(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      case Keyword.get(opts, :as, :integer) do
        :integer ->
          add name, :integer, null: true

          create constraint(table_name(), :"#{name}_range",
                   check: "#{name} >= 0 AND #{name} <= 100"
                 )

        :decimal ->
          add name, :decimal, precision: 5, scale: 4, null: true
          create constraint(table_name(), :"#{name}_range", check: "#{name} >= 0 AND #{name} <= 1")
      end
    end
  end

  @doc """
  Adds counter fields with non-negative constraint.

  ## Examples

      # View counter
      counter_field(:view_count)

      # Multiple counters
      counter_field(:like_count)
      counter_field(:share_count)
      counter_field(:comment_count)
  """
  defmacro counter_field(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      default = Keyword.get(opts, :default, 0)

      add name, :integer, default: default, null: false
      create constraint(table_name(), :"#{name}_non_negative", check: "#{name} >= 0")
    end
  end

  @doc """
  Adds file attachment fields.

  ## Examples

      # Basic file fields
      file_fields(:avatar)

      # With metadata
      file_fields(:document, with_metadata: true)

      # Multiple attachments
      file_fields(:profile_image)
      file_fields(:cover_photo)
  """
  defmacro file_fields(name, opts \\ []) do
    quote bind_quoted: [name: name, opts: opts] do
      base_name = to_string(name)

      # URL/path to the file
      add :"#{base_name}_url", :string, null: true

      # File metadata
      if Keyword.get(opts, :with_metadata, false) do
        add :"#{base_name}_name", :string, null: true
        add :"#{base_name}_size", :integer, null: true
        add :"#{base_name}_content_type", :string, null: true
        add :"#{base_name}_uploaded_at", :utc_datetime, null: true
      end
    end
  end

  @doc """
  Adds geolocation fields.

  ## Examples

      # Basic lat/lng
      geo_fields()

      # With altitude and accuracy
      geo_fields(with_altitude: true, with_accuracy: true)

      # With prefix
      geo_fields(prefix: :pickup)
      geo_fields(prefix: :delivery)
  """
  defmacro geo_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldMacros.build_geo_fields()
      |> Enum.each(fn {field, type, field_opts} ->
        add field, type, field_opts
      end)
    end
  end

  @doc false
  def build_geo_fields(opts) do
    prefix = Keyword.get(opts, :prefix)
    with_altitude = Keyword.get(opts, :with_altitude, false)
    with_accuracy = Keyword.get(opts, :with_accuracy, false)

    base_fields = [
      build_geo_field(:latitude, :decimal, prefix),
      build_geo_field(:longitude, :decimal, prefix)
    ]

    altitude_fields =
      if with_altitude do
        [build_geo_field(:altitude, :decimal, prefix)]
      else
        []
      end

    accuracy_fields =
      if with_accuracy do
        [build_geo_field(:accuracy, :decimal, prefix)]
      else
        []
      end

    base_fields ++ altitude_fields ++ accuracy_fields
  end

  defp build_geo_field(name, type, nil) do
    {name, type, [precision: 10, scale: 7, null: true]}
  end

  defp build_geo_field(name, type, prefix) do
    {:"#{prefix}_#{name}", type, [precision: 10, scale: 7, null: true]}
  end

  @doc """
  Adds tag fields as array or JSONB.

  ## Examples

      # Array of strings
      tags_field()

      # As JSONB for complex tags
      tags_field(type: :jsonb)

      # Multiple tag fields
      tags_field(name: :categories)
      tags_field(name: :keywords)
  """
  defmacro tags_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_name = Keyword.get(opts, :name, :tags)
      field_type = Keyword.get(opts, :type, {:array, :string})

      case field_type do
        {:array, :string} ->
          add field_name, {:array, :string}, default: [], null: false
          create index(table_name(), [field_name], using: :gin)

        :jsonb ->
          add field_name, :jsonb, default: "[]", null: false
          create index(table_name(), [field_name], using: :gin)
      end
    end
  end

  @doc """
  Adds settings/configuration field as JSONB.

  ## Examples

      # Basic settings field
      settings_field()

      # With custom name and default
      settings_field(name: :preferences, default: %{theme: "light"})

      # Multiple config fields
      settings_field(name: :user_settings)
      settings_field(name: :app_config)
  """
  defmacro settings_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_name = Keyword.get(opts, :name, :settings)
      default = Keyword.get(opts, :default, %{})
      default_json = Jason.encode!(default)

      add field_name, :jsonb, default: fragment("?::jsonb", ^default_json), null: false
      create index(table_name(), [field_name], using: :gin)
    end
  end

  @doc """
  Helper to get the current table name in a migration.
  """
  def table_name do
    # This would need to be implemented based on the migration context
    # For now, returning a placeholder
    :current_table
  end
end
