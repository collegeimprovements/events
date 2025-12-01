defmodule Events.Core.Migration.PipelineExtended do
  @moduledoc """
  Extended pipeline functions for migrations with all field types.

  Provides comprehensive field helpers for building migrations.

  > #### Prefer FieldBuilders {: .info}
  >
  > For new code, consider using the behavior-based FieldBuilders in
  > `Events.Core.Migration.FieldBuilders.*` which provide better consistency
  > and reference `Events.Core.Migration.FieldDefinitions` for type definitions.
  """

  alias Events.Core.Migration.Token
  alias Events.Core.Migration.FieldDefinitions

  # ============================================
  # Type Fields
  # ============================================

  @doc """
  Adds type categorization fields.

  ## Examples

      # Single type field
      |> with_type_fields()

      # Custom field names
      |> with_type_fields(primary: :category, secondary: :subcategory)

      # With custom options
      |> with_type_fields(
          primary: :product_type,
          secondary: :product_subtype,
          required: true
        )
  """
  def with_type_fields(%Token{} = token, opts \\ []) do
    primary = Keyword.get(opts, :primary, :type)
    secondary = Keyword.get(opts, :secondary, :subtype)
    required = Keyword.get(opts, :required, false)

    token
    |> Token.add_field(primary, :string, null: !required)
    |> Token.add_field(secondary, :string, null: true)
    |> Token.add_index(:"#{token.name}_#{primary}_index", [primary])
    |> maybe_add_index(secondary, secondary != :subtype)
  end

  # ============================================
  # Status Field (Enhanced)
  # ============================================

  @doc """
  Adds status field with enum constraint.

  ## Examples

      # Default statuses
      |> with_status_fields()

      # Custom statuses
      |> with_status_fields(
          values: ["pending", "processing", "completed", "failed"],
          default: "pending",
          required: true
        )

      # With index
      |> with_status_fields(indexed: true, partial: "deleted_at IS NULL")
  """
  def with_status_fields(%Token{} = token, opts \\ []) do
    values = Keyword.get(opts, :values, ["draft", "active", "inactive", "archived"])
    default = Keyword.get(opts, :default, "draft")
    required = Keyword.get(opts, :required, true)
    indexed = Keyword.get(opts, :indexed, true)
    partial = Keyword.get(opts, :partial)

    token
    |> Token.add_field(:status, :string,
      null: !required,
      default: default
    )
    |> Token.add_constraint(:status_check, :check,
      check: "status IN (#{values |> Enum.map(&"'#{&1}'") |> Enum.join(", ")})"
    )
    |> maybe_add_status_index(indexed, partial)
  end

  # ============================================
  # Audit Fields (Enhanced)
  # ============================================

  @doc """
  Adds comprehensive audit tracking fields.

  ## Examples

      # Basic audit fields
      |> with_audit_fields()

      # With user tracking
      |> with_audit_fields(track_user: true)

      # With role tracking
      |> with_audit_fields(track_user: true, track_role: true)

      # With IP and user agent
      |> with_audit_fields(
          track_user: true,
          track_ip: true,
          track_user_agent: true
        )
  """
  def with_audit_fields(%Token{} = token, opts \\ []) do
    track_user = Keyword.get(opts, :track_user, false)
    track_role = Keyword.get(opts, :track_role, false)
    track_ip = Keyword.get(opts, :track_ip, false)
    track_user_agent = Keyword.get(opts, :track_user_agent, false)

    token
    |> add_base_audit_fields()
    |> maybe_add_user_audit_fields(track_user)
    |> maybe_add_role_audit_fields(track_role)
    |> maybe_add_ip_tracking(track_ip)
    |> maybe_add_user_agent_tracking(track_user_agent)
  end

  defp add_base_audit_fields(token) do
    # Use FieldDefinitions for consistent types
    id_type = FieldDefinitions.id_type()

    token
    |> Token.add_field(:created_by_urm_id, id_type, null: true)
    |> Token.add_field(:updated_by_urm_id, id_type, null: true)
  end

  defp maybe_add_user_audit_fields(token, false), do: token

  defp maybe_add_user_audit_fields(token, true) do
    id_type = FieldDefinitions.id_type()

    token
    |> Token.add_field(:created_by_user_id, id_type, null: true)
    |> Token.add_field(:updated_by_user_id, id_type, null: true)
    |> Token.add_index(:created_by_user_index, [:created_by_user_id])
    |> Token.add_index(:updated_by_user_index, [:updated_by_user_id])
  end

  defp maybe_add_role_audit_fields(token, false), do: token

  defp maybe_add_role_audit_fields(token, true) do
    id_type = FieldDefinitions.id_type()

    token
    |> Token.add_field(:created_by_role_id, id_type, null: true)
    |> Token.add_field(:updated_by_role_id, id_type, null: true)
  end

  defp maybe_add_ip_tracking(token, false), do: token

  defp maybe_add_ip_tracking(token, true) do
    ip_type = FieldDefinitions.ip_type()

    token
    |> Token.add_field(:created_from_ip, ip_type, null: true)
    |> Token.add_field(:updated_from_ip, ip_type, null: true)
  end

  defp maybe_add_user_agent_tracking(token, false), do: token

  defp maybe_add_user_agent_tracking(token, true) do
    token
    |> Token.add_field(:created_with_user_agent, :string, null: true)
    |> Token.add_field(:updated_with_user_agent, :string, null: true)
  end

  # ============================================
  # Timestamps (Enhanced)
  # ============================================

  @doc """
  Adds timestamp fields with options.

  ## Examples

      # Basic timestamps
      |> with_timestamps()

      # With microsecond precision
      |> with_timestamps(type: :utc_datetime_usec)

      # Only inserted_at
      |> with_timestamps(updated_at: false)

      # Custom names
      |> with_timestamps(
          inserted_at: :created_at,
          updated_at: :modified_at
        )

      # With indexes
      |> with_timestamps(indexed: true)
  """
  def with_timestamps(%Token{} = token, opts \\ []) do
    type = Keyword.get(opts, :type, :utc_datetime)
    inserted_at_name = Keyword.get(opts, :inserted_at, :inserted_at)
    updated_at_name = Keyword.get(opts, :updated_at, :updated_at)
    indexed = Keyword.get(opts, :indexed, false)

    token
    |> maybe_add_timestamp_field(inserted_at_name, type, opts)
    |> maybe_add_timestamp_field(updated_at_name, type, opts)
    |> maybe_add_timestamp_indexes(inserted_at_name, updated_at_name, indexed)
  end

  defp maybe_add_timestamp_field(token, false, _, _), do: token

  defp maybe_add_timestamp_field(token, name, type, _opts) when is_atom(name) do
    Token.add_field(token, name, type, null: false)
  end

  defp maybe_add_timestamp_indexes(token, _, _, false), do: token

  defp maybe_add_timestamp_indexes(token, inserted_at, updated_at, true) do
    token
    |> maybe_add_index(inserted_at, inserted_at != false)
    |> maybe_add_index(updated_at, updated_at != false)
  end

  # ============================================
  # Title Fields
  # ============================================

  @doc """
  Adds title fields with translations.

  ## Examples

      # Basic title fields
      |> with_title_fields()

      # With translations
      |> with_title_fields(
          with_translations: true,
          languages: [:es, :fr, :de]
        )

      # Required and indexed
      |> with_title_fields(required: true, indexed: true)
  """
  def with_title_fields(%Token{} = token, opts \\ []) do
    type = Keyword.get(opts, :type, :string)
    required = Keyword.get(opts, :required, true)
    indexed = Keyword.get(opts, :indexed, false)
    with_translations = Keyword.get(opts, :with_translations, false)
    languages = Keyword.get(opts, :languages, [:es, :fr, :de])

    token
    |> Token.add_field(:title, type, null: !required)
    |> Token.add_field(:subtitle, type, null: true)
    |> Token.add_field(:short_title, type, null: true)
    |> maybe_add_translations(:title, languages, with_translations)
    |> maybe_add_title_indexes(indexed)
  end

  defp maybe_add_translations(token, _field, _languages, false), do: token

  defp maybe_add_translations(token, field, languages, true) do
    Enum.reduce(languages, token, fn lang, acc ->
      acc
      |> Token.add_field(:"#{field}_#{lang}", :string, null: true)
      |> Token.add_field(:"#{field}_short_#{lang}", :string, null: true)
    end)
  end

  # ============================================
  # Name Fields
  # ============================================

  @doc """
  Adds comprehensive name fields.

  ## Examples

      # Basic name fields
      |> with_name_fields()

      # Case-insensitive with unique
      |> with_name_fields(type: :citext, unique: [:username])

      # Required fields
      |> with_name_fields(
          required: [:first_name, :last_name],
          indexed: true
        )
  """
  def with_name_fields(%Token{} = token, opts \\ []) do
    type = Keyword.get(opts, :type, :string)
    required = Keyword.get(opts, :required, [])
    unique = Keyword.get(opts, :unique, [])
    indexed = Keyword.get(opts, :indexed, false)

    fields = [
      {:first_name, type},
      {:last_name, type},
      {:middle_name, type},
      {:display_name, type},
      {:full_name, type},
      {:username, type}
    ]

    token
    |> add_name_fields(fields, required)
    |> add_unique_constraints(unique)
    |> maybe_add_name_indexes(indexed)
  end

  defp add_name_fields(token, fields, required) do
    Enum.reduce(fields, token, fn {field, type}, acc ->
      is_required = field in required
      Token.add_field(acc, field, type, null: !is_required)
    end)
  end

  # ============================================
  # Slug Field
  # ============================================

  @doc """
  Adds slug field with unique constraint.

  ## Examples

      # Basic slug
      |> with_slug_fields()

      # Without unique constraint
      |> with_slug_fields(unique: false)

      # Custom name and type
      |> with_slug_fields(name: :permalink, type: :citext)
  """
  def with_slug_fields(%Token{} = token, opts \\ []) do
    name = Keyword.get(opts, :name, :slug)
    type = Keyword.get(opts, :type, :string)
    unique = Keyword.get(opts, :unique, true)
    indexed = Keyword.get(opts, :indexed, true)

    token
    |> Token.add_field(name, type, null: true)
    |> maybe_add_unique_constraint(name, unique)
    |> maybe_add_index(name, indexed and not unique)
  end

  # ============================================
  # SEO Fields
  # ============================================

  @doc """
  Adds SEO optimization fields.

  ## Examples

      # Basic SEO fields
      |> with_seo_fields()

      # With Open Graph
      |> with_seo_fields(with_og: true)

      # With Twitter Card
      |> with_seo_fields(with_twitter: true)
  """
  def with_seo_fields(%Token{} = token, opts \\ []) do
    with_og = Keyword.get(opts, :with_og, false)
    with_twitter = Keyword.get(opts, :with_twitter, false)

    token
    |> Token.add_field(:meta_title, :string, null: true)
    |> Token.add_field(:meta_description, :text, null: true)
    |> Token.add_field(:meta_keywords, {:array, :string}, default: [], null: false)
    |> Token.add_field(:canonical_url, :string, null: true)
    |> maybe_add_og_fields(with_og)
    |> maybe_add_twitter_fields(with_twitter)
  end

  defp maybe_add_og_fields(token, false), do: token

  defp maybe_add_og_fields(token, true) do
    token
    |> Token.add_field(:og_title, :string, null: true)
    |> Token.add_field(:og_description, :text, null: true)
    |> Token.add_field(:og_image, :string, null: true)
    |> Token.add_field(:og_type, :string, null: true)
  end

  defp maybe_add_twitter_fields(token, false), do: token

  defp maybe_add_twitter_fields(token, true) do
    token
    |> Token.add_field(:twitter_card, :string, null: true)
    |> Token.add_field(:twitter_site, :string, null: true)
    |> Token.add_field(:twitter_creator, :string, null: true)
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp maybe_add_index(token, _field, false), do: token

  defp maybe_add_index(token, field, true) do
    Token.add_index(token, :"#{token.name}_#{field}_index", [field])
  end

  defp maybe_add_status_index(token, false, _), do: token

  defp maybe_add_status_index(token, true, nil) do
    Token.add_index(token, :status_index, [:status])
  end

  defp maybe_add_status_index(token, true, partial) do
    Token.add_index(token, :status_index, [:status], where: partial)
  end

  defp maybe_add_title_indexes(token, false), do: token

  defp maybe_add_title_indexes(token, true) do
    token
    |> Token.add_index(:title_index, [:title])
    |> Token.add_index(:title_fulltext_index, [:title, :subtitle], using: :gin)
  end

  defp maybe_add_name_indexes(token, false), do: token

  defp maybe_add_name_indexes(token, true) do
    token
    |> Token.add_index(:name_index, [:last_name, :first_name])
    |> Token.add_index(:username_index, [:username])
  end

  defp add_unique_constraints(token, fields) when is_list(fields) do
    Enum.reduce(fields, token, fn field, acc ->
      Token.add_index(acc, :"#{token.name}_#{field}_unique", [field], unique: true)
    end)
  end

  defp maybe_add_unique_constraint(token, _field, false), do: token

  defp maybe_add_unique_constraint(token, field, true) do
    Token.add_index(token, :"#{token.name}_#{field}_unique", [field], unique: true)
  end

  # ============================================
  # Backward Compatibility Aliases
  # ============================================

  @doc false
  @deprecated "Use with_status_fields/2 instead"
  def with_status_field(token, opts \\ []), do: with_status_fields(token, opts)

  @doc false
  @deprecated "Use with_slug_fields/2 instead"
  def with_slug_field(token, opts \\ []), do: with_slug_fields(token, opts)
end
