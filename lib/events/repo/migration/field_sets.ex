defmodule Events.Repo.Migration.FieldSets do
  @moduledoc """
  Common field set macros for migrations.

  Provides standardized field sets that can be composed together
  using pipelines and pattern matching.
  """

  use Ecto.Migration

  # ============================================
  # Field Set Definitions
  # ============================================

  @doc """
  Adds name fields using pattern matching for options.

  ## Options
  - `:required` - Whether fields are required (default: true)
  - `:unique` - Whether to add unique constraint (default: false)
  - `:type` - Field type (:string or :citext, default: :string)

  ## Examples

      # Basic usage
      name_fields()

      # With options
      name_fields(required: true, unique: true, type: :citext)
  """
  defmacro name_fields(opts \\ []) do
    opts = normalize_options(opts, required: true, type: :string)

    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldSets.build_name_fields()
      |> Enum.each(fn {field, type, field_opts} ->
        add field, type, field_opts
      end)
    end
  end

  @doc false
  def build_name_fields(opts) do
    opts
    |> extract_field_config()
    |> generate_name_field_definitions()
  end

  defp extract_field_config(opts) do
    %{
      type: Keyword.get(opts, :type, :string),
      required: Keyword.get(opts, :required, true),
      unique: Keyword.get(opts, :unique, false)
    }
  end

  defp generate_name_field_definitions(%{type: type, required: required}) do
    [
      {:first_name, type, null: !required},
      {:last_name, type, null: !required},
      {:display_name, type, null: true},
      {:full_name, type, null: true}
    ]
  end

  @doc """
  Adds title fields with configurable options.

  ## Examples

      # English only
      title_fields()

      # With translations
      title_fields(with_translations: true, languages: [:es, :fr])

      # With unique constraint
      title_fields(unique: true, type: :citext)
  """
  defmacro title_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldSets.build_title_fields()
      |> Enum.each(fn {field, type, field_opts} ->
        add field, type, field_opts
      end)
    end
  end

  @doc false
  def build_title_fields(opts) do
    base_fields = build_base_title_fields(opts)
    translation_fields = build_translation_fields(opts, :title)

    base_fields ++ translation_fields
  end

  defp build_base_title_fields(opts) do
    type = Keyword.get(opts, :type, :string)
    required = Keyword.get(opts, :required, true)

    [
      {:title, type, null: !required},
      {:subtitle, type, null: true},
      {:short_title, type, null: true}
    ]
  end

  defp build_translation_fields(opts, prefix) do
    case Keyword.get(opts, :with_translations, false) do
      false ->
        []

      true ->
        opts
        |> Keyword.get(:languages, [:es, :fr, :de])
        |> Enum.flat_map(&translation_fields_for_language(&1, prefix))
    end
  end

  defp translation_fields_for_language(lang, prefix) do
    type = :string

    [
      {:"#{prefix}_#{lang}", type, null: true},
      {:"#{prefix}_short_#{lang}", type, null: true}
    ]
  end

  @doc """
  Adds status field with enum validation.

  ## Examples

      # Default statuses
      status_field()

      # Custom statuses
      status_field(values: ["pending", "processing", "completed", "failed"])

      # With default value
      status_field(default: "draft", required: false)
  """
  defmacro status_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_def = Events.Repo.Migration.FieldSets.build_status_field(opts)
      {field, type, field_opts} = field_def
      add field, type, field_opts
    end
  end

  @doc false
  def build_status_field(opts) do
    default_values = ["draft", "pending", "published", "archived", "deleted"]

    config = %{
      values: Keyword.get(opts, :values, default_values),
      default: Keyword.get(opts, :default, "draft"),
      required: Keyword.get(opts, :required, true),
      type: Keyword.get(opts, :type, :string)
    }

    {:status, config.type, build_field_options(config)}
  end

  defp build_field_options(%{required: required, default: default}) do
    []
    |> add_null_option(required)
    |> add_default_option(default)
  end

  defp add_null_option(opts, required), do: [{:null, !required} | opts]
  defp add_default_option(opts, nil), do: opts
  defp add_default_option(opts, default), do: [{:default, default} | opts]

  @doc """
  Adds metadata JSONB field with proper defaults.

  ## Examples

      # Basic metadata field
      metadata_field()

      # Custom field name
      metadata_field(name: :properties)

      # Multiple metadata fields
      metadata_field(name: :settings, default: %{})
      metadata_field(name: :preferences, required: false)
  """
  defmacro metadata_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field_def = Events.Repo.Migration.FieldSets.build_metadata_field(opts)
      {field, type, field_opts} = field_def
      add field, type, field_opts
    end
  end

  @doc false
  def build_metadata_field(opts) do
    field_name = Keyword.get(opts, :name, :metadata)
    default = Keyword.get(opts, :default, "{}")
    required = Keyword.get(opts, :required, false)

    {field_name, :jsonb, [default: default, null: !required]}
  end

  @doc """
  Adds audit fields for tracking changes.

  ## Examples

      # Basic audit fields
      audit_fields()

      # With user tracking
      audit_fields(with_user: true)

      # With role tracking
      audit_fields(with_role: true, role_table: :custom_roles)
  """
  defmacro audit_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldSets.build_audit_fields()
      |> Enum.each(fn field_def ->
        case field_def do
          {:reference, field, table, ref_opts} ->
            add field, references(table, ref_opts)

          {field, type, field_opts} ->
            add field, type, field_opts
        end
      end)
    end
  end

  @doc false
  def build_audit_fields(opts) do
    base_fields = build_base_audit_fields(opts)
    user_fields = build_user_audit_fields(opts)
    role_fields = build_role_audit_fields(opts)

    base_fields ++ user_fields ++ role_fields
  end

  defp build_base_audit_fields(_opts) do
    [
      {:created_by, :string, null: true},
      {:updated_by, :string, null: true}
    ]
  end

  defp build_user_audit_fields(opts) do
    case Keyword.get(opts, :with_user, false) do
      false ->
        []

      true ->
        [
          {:reference, :created_by_user_id, :users, type: :binary_id, on_delete: :nilify_all},
          {:reference, :updated_by_user_id, :users, type: :binary_id, on_delete: :nilify_all}
        ]
    end
  end

  defp build_role_audit_fields(opts) do
    case Keyword.get(opts, :with_role, false) do
      false ->
        []

      true ->
        role_table = Keyword.get(opts, :role_table, :user_role_mappings)

        [
          {:reference, :created_by_role_id, role_table, type: :binary_id, on_delete: :nilify_all},
          {:reference, :updated_by_role_id, role_table, type: :binary_id, on_delete: :nilify_all}
        ]
    end
  end

  @doc """
  Adds soft delete fields.

  ## Examples

      # Basic soft delete
      deleted_fields()

      # With user tracking
      deleted_fields(with_user: true)

      # With reason tracking
      deleted_fields(with_reason: true)
  """
  defmacro deleted_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldSets.build_deleted_fields()
      |> Enum.each(fn field_def ->
        case field_def do
          {:reference, field, table, ref_opts} ->
            add field, references(table, ref_opts)

          {field, type, field_opts} ->
            add field, type, field_opts
        end
      end)
    end
  end

  @doc false
  def build_deleted_fields(opts) do
    base_fields = [
      {:deleted_at, :utc_datetime, null: true},
      {:deleted_by, :string, null: true}
    ]

    user_fields =
      case Keyword.get(opts, :with_user, false) do
        false ->
          []

        true ->
          [{:reference, :deleted_by_user_id, :users, type: :binary_id, on_delete: :nilify_all}]
      end

    reason_fields =
      case Keyword.get(opts, :with_reason, false) do
        false -> []
        true -> [{:deletion_reason, :text, null: true}]
      end

    base_fields ++ user_fields ++ reason_fields
  end

  @doc """
  Adds type fields for categorization.

  ## Examples

      # Basic type field
      type_fields()

      # With custom types
      type_fields(types: ["product", "service", "bundle"])

      # Multiple type fields
      type_fields(primary: :category, secondary: :subcategory)
  """
  defmacro type_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      opts
      |> Events.Repo.Migration.FieldSets.build_type_fields()
      |> Enum.each(fn {field, type, field_opts} ->
        add field, type, field_opts
      end)
    end
  end

  @doc false
  def build_type_fields(opts) do
    case {Keyword.get(opts, :primary), Keyword.get(opts, :secondary)} do
      {nil, nil} ->
        # Default single type field
        [{:type, :string, null: true}]

      {primary, nil} ->
        # Custom primary field name
        [{primary, :string, null: true}]

      {primary, secondary} ->
        # Both primary and secondary
        [
          {primary, :string, null: true},
          {secondary, :string, null: true}
        ]
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp normalize_options(opts, defaults) do
    defaults
    |> Keyword.merge(opts)
    |> Enum.into([])
  end
end
