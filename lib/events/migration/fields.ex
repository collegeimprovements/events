defmodule Events.Migration.Fields do
  @moduledoc """
  Field definitions using pattern matching and functional composition.

  Each function returns a list of field tuples that can be composed
  into larger field sets.
  """

  @type field :: {atom(), atom(), keyword()}

  # ============================================
  # Name Fields
  # ============================================

  @doc """
  Returns name field definitions.

  ## Options
  - `:type` - Field type (:string or :citext)
  - `:required` - Whether fields are required
  """
  @spec name_fields(keyword()) :: [field()]
  def name_fields(opts \\ []) do
    opts
    |> extract_field_config(:name)
    |> build_name_fields()
  end

  defp build_name_fields(%{type: type, required: required}) do
    [
      {:first_name, type, null: !required},
      {:last_name, type, null: !required},
      {:display_name, type, null: true},
      {:full_name, type, null: true}
    ]
  end

  # ============================================
  # Address Fields
  # ============================================

  @doc """
  Returns address field definitions.

  ## Options
  - `:prefix` - Field name prefix
  - `:required` - Whether fields are required
  """
  @spec address_fields(keyword()) :: [field()]
  def address_fields(opts \\ []) do
    opts
    |> extract_field_config(:address)
    |> build_address_fields()
  end

  defp build_address_fields(%{prefix: nil, required: required}) do
    [
      {:street, :string, null: !required},
      {:street2, :string, null: true},
      {:city, :string, null: !required},
      {:state, :string, null: true},
      {:postal_code, :string, null: true},
      {:country, :string, null: true}
    ]
  end

  defp build_address_fields(%{prefix: prefix, required: required}) do
    [
      {:"#{prefix}_street", :string, null: !required},
      {:"#{prefix}_street2", :string, null: true},
      {:"#{prefix}_city", :string, null: !required},
      {:"#{prefix}_state", :string, null: true},
      {:"#{prefix}_postal_code", :string, null: true},
      {:"#{prefix}_country", :string, null: true}
    ]
  end

  # ============================================
  # Geolocation Fields
  # ============================================

  @doc """
  Returns geolocation field definitions.

  ## Options
  - `:prefix` - Field name prefix
  - `:with_altitude` - Include altitude field
  - `:with_accuracy` - Include accuracy field
  """
  @spec geo_fields(keyword()) :: [field()]
  def geo_fields(opts \\ []) do
    opts
    |> extract_field_config(:geo)
    |> build_geo_fields()
  end

  defp build_geo_fields(config) do
    base = build_base_geo_fields(config)
    altitude = build_altitude_field(config)
    accuracy = build_accuracy_field(config)

    base ++ altitude ++ accuracy
  end

  defp build_base_geo_fields(%{prefix: nil}) do
    [
      {:latitude, :decimal, precision: 10, scale: 7, null: true},
      {:longitude, :decimal, precision: 10, scale: 7, null: true}
    ]
  end

  defp build_base_geo_fields(%{prefix: prefix}) do
    [
      {:"#{prefix}_latitude", :decimal, precision: 10, scale: 7, null: true},
      {:"#{prefix}_longitude", :decimal, precision: 10, scale: 7, null: true}
    ]
  end

  defp build_altitude_field(%{with_altitude: false}), do: []

  defp build_altitude_field(%{prefix: nil, with_altitude: true}) do
    [{:altitude, :decimal, precision: 10, scale: 2, null: true}]
  end

  defp build_altitude_field(%{prefix: prefix, with_altitude: true}) do
    [{:"#{prefix}_altitude", :decimal, precision: 10, scale: 2, null: true}]
  end

  defp build_accuracy_field(%{with_accuracy: false}), do: []

  defp build_accuracy_field(%{prefix: nil, with_accuracy: true}) do
    [{:accuracy, :decimal, precision: 10, scale: 2, null: true}]
  end

  defp build_accuracy_field(%{prefix: prefix, with_accuracy: true}) do
    [{:"#{prefix}_accuracy", :decimal, precision: 10, scale: 2, null: true}]
  end

  # ============================================
  # Contact Fields
  # ============================================

  @doc """
  Returns contact field definitions.
  """
  @spec contact_fields(keyword()) :: [field()]
  def contact_fields(opts \\ []) do
    opts
    |> extract_field_config(:contact)
    |> build_contact_fields()
  end

  defp build_contact_fields(%{prefix: nil}) do
    [
      {:email, :citext, null: true},
      {:phone, :string, null: true},
      {:mobile, :string, null: true},
      {:fax, :string, null: true}
    ]
  end

  defp build_contact_fields(%{prefix: prefix}) do
    [
      {:"#{prefix}_email", :citext, null: true},
      {:"#{prefix}_phone", :string, null: true},
      {:"#{prefix}_mobile", :string, null: true},
      {:"#{prefix}_fax", :string, null: true}
    ]
  end

  # ============================================
  # Social Media Fields
  # ============================================

  @doc """
  Returns social media field definitions.
  """
  @spec social_fields(keyword()) :: [field()]
  def social_fields(_opts \\ []) do
    [
      {:website, :string, null: true},
      {:twitter, :string, null: true},
      {:facebook, :string, null: true},
      {:instagram, :string, null: true},
      {:linkedin, :string, null: true},
      {:github, :string, null: true},
      {:youtube, :string, null: true}
    ]
  end

  # ============================================
  # SEO Fields
  # ============================================

  @doc """
  Returns SEO field definitions.
  """
  @spec seo_fields(keyword()) :: [field()]
  def seo_fields(_opts \\ []) do
    [
      {:meta_title, :string, null: true},
      {:meta_description, :text, null: true},
      {:meta_keywords, {:array, :string}, default: []},
      {:canonical_url, :string, null: true},
      {:og_title, :string, null: true},
      {:og_description, :text, null: true},
      {:og_image, :string, null: true}
    ]
  end

  # ============================================
  # File Attachment Fields
  # ============================================

  @doc """
  Returns file attachment field definitions.
  """
  @spec file_fields(atom(), keyword()) :: [field()]
  def file_fields(name, opts \\ []) do
    with_metadata = Keyword.get(opts, :with_metadata, false)

    base = [
      {:"#{name}_url", :string, null: true},
      {:"#{name}_key", :string, null: true}
    ]

    if with_metadata do
      base ++
        [
          {:"#{name}_name", :string, null: true},
          {:"#{name}_size", :integer, null: true},
          {:"#{name}_content_type", :string, null: true},
          {:"#{name}_uploaded_at", :utc_datetime, null: true}
        ]
    else
      base
    end
  end

  # ============================================
  # Counter Fields
  # ============================================

  @doc """
  Returns counter field definitions with non-negative constraints.
  """
  @spec counter_fields(list(atom())) :: [field()]
  def counter_fields(names) when is_list(names) do
    Enum.map(names, &counter_field/1)
  end

  @spec counter_field(atom()) :: field()
  def counter_field(name) do
    {name, :integer, default: 0, null: false}
  end

  # ============================================
  # Money Fields
  # ============================================

  @doc """
  Returns money field definitions with decimal precision.
  """
  @spec money_fields(list(atom()), keyword()) :: [field()]
  def money_fields(names, opts \\ []) when is_list(names) do
    precision = Keyword.get(opts, :precision, 10)
    scale = Keyword.get(opts, :scale, 2)

    Enum.map(names, fn name ->
      {name, :decimal, precision: precision, scale: scale, null: true}
    end)
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp extract_field_config(opts, type) do
    %{
      type: Keyword.get(opts, :type, default_type(type)),
      prefix: Keyword.get(opts, :prefix),
      required: Keyword.get(opts, :required, false),
      with_altitude: Keyword.get(opts, :with_altitude, false),
      with_accuracy: Keyword.get(opts, :with_accuracy, false)
    }
  end

  defp default_type(:name), do: :string
  defp default_type(:address), do: :string
  defp default_type(:contact), do: :string
  defp default_type(_), do: :string
end
