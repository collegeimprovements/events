defmodule Examples.SchemaPresetsUsage do
  @moduledoc """
  Example module demonstrating the use of OmSchema presets.

  This shows how to use the 44 built-in validation presets for common field types.
  """

  use OmSchema
  import OmSchema.Presets

  schema "user_profiles" do
    # Basic Information
    field :email, :string, email()
    field :username, :string, username(min_length: 3, max_length: 20)
    field :password, :string, password(min_length: 12)
    field :website, :string, url(required: false)
    field :bio, :string, max_length: 500

    # Personal Details
    field :age, :integer, age()
    field :phone, :string, phone(required: false)
    field :ssn, :string, ssn()  # US Social Security Number

    # Location
    field :country, :string, country_code()
    field :postal_code, :string, zip_code()
    field :latitude, :float, latitude()
    field :longitude, :float, longitude()
    field :timezone, :string, timezone()

    # Preferences
    field :language, :string, language_code()
    field :currency, :string, currency_code()
    field :theme_color, :string, hex_color()

    # Social Media
    field :twitter_handle, :string, social_handle(required: false)
    field :instagram_handle, :string, social_handle(required: false)
    field :hashtags, {:array, :string}, tags()

    # Technical Fields
    field :ip_address, :string, ipv4()
    field :ipv6_address, :string, ipv6()
    field :mac_address, :string, mac_address()
    field :api_key, :string, uuid()
    field :access_token, :string, jwt()
    field :domain_name, :string, domain()

    # Financial
    field :credit_card, :string, credit_card()
    field :iban, :string, iban()
    field :bitcoin_wallet, :string, bitcoin_address(required: false)
    field :ethereum_wallet, :string, ethereum_address(required: false)
    field :monthly_income, :decimal, money()

    # Product/Service
    field :rating, :integer, rating()
    field :discount_percentage, :integer, percentage()
    field :priority_level, :integer, positive_integer(max: 10)
    field :status, :string, enum(in: ["active", "pending", "inactive"])

    # Content Management
    field :slug, :string, slug()
    field :tags, {:array, :string}, tags(max_length: 10)
    field :metadata, :map, metadata(max_keys: 50)
    field :mime_type, :string, mime_type()
    field :file_path, :string, file_path()

    # Version Control
    field :app_version, :string, semver()
    field :isbn, :string, isbn()
    field :base64_data, :string, base64()

    # Timestamps
    field :verified_at, :utc_datetime, timestamp()
    timestamps()  # Adds created_at and updated_at
  end

  @doc """
  Example of creating a changeset with presets.
  """
  def changeset(user_profile, attrs) do
    user_profile
    |> cast(attrs, __cast_fields__())
    |> validate_required([:email, :username, :password])
    |> __apply_field_validations__()
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end
end

defmodule Examples.PaymentSchema do
  @moduledoc """
  Example schema focused on financial fields.
  """

  use OmSchema
  import OmSchema.Presets

  schema "payments" do
    field :amount, :decimal, money(required: true)
    field :currency, :string, currency_code()
    field :card_number, :string, credit_card()
    field :from_iban, :string, iban()
    field :to_iban, :string, iban()
    field :bitcoin_address, :string, bitcoin_address(required: false)
    field :ethereum_address, :string, ethereum_address(required: false)
    field :tax_percentage, :integer, percentage()
    field :discount_percentage, :integer, percentage()
    field :status, :string, enum(in: ["pending", "processing", "completed", "failed"])

    timestamps()
  end
end

defmodule Examples.NetworkDeviceSchema do
  @moduledoc """
  Example schema for network device management.
  """

  use OmSchema
  import OmSchema.Presets

  schema "network_devices" do
    field :device_name, :string, required: true, max_length: 100
    field :ipv4_address, :string, ipv4()
    field :ipv6_address, :string, ipv6()
    field :mac_address, :string, mac_address()
    field :hostname, :string, domain()
    field :firmware_version, :string, semver()
    field :last_ping_at, :utc_datetime, timestamp()

    timestamps()
  end
end

defmodule Examples.APIClientSchema do
  @moduledoc """
  Example schema for API client configuration.
  """

  use OmSchema
  import OmSchema.Presets

  schema "api_clients" do
    field :client_id, :string, uuid()
    field :client_secret, :string, password(min_length: 32)
    field :access_token, :string, jwt()
    field :refresh_token, :string, jwt()
    field :webhook_url, :string, url()
    field :allowed_ips, {:array, :string}, item_format: ~r/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/
    field :rate_limit, :integer, positive_integer(max: 10000)
    field :api_version, :string, semver()

    timestamps()
  end
end

defmodule Examples.InternationalProductSchema do
  @moduledoc """
  Example schema for international product catalog.
  """

  use OmSchema
  import OmSchema.Presets

  schema "products" do
    field :sku, :string, required: true, unique: true
    field :isbn, :string, isbn()
    field :name, :string, required: true
    field :slug, :string, slug()
    field :price, :decimal, money()
    field :currency, :string, currency_code()
    field :tax_rate, :integer, percentage()
    field :discount_rate, :integer, percentage()
    field :weight_kg, :float, non_negative: true
    field :rating, :float, min: 0.0, max: 5.0
    field :review_count, :integer, positive_integer()
    field :country_of_origin, :string, country_code()
    field :languages, {:array, :string}, item_format: ~r/^[a-z]{2}(-[A-Z]{2})?$/
    field :color_code, :string, hex_color()
    field :tags, {:array, :string}, tags()
    field :metadata, :map, metadata()

    timestamps()
  end
end