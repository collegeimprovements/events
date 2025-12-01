defmodule Events.Core.Migration.FieldDefinitions do
  @moduledoc """
  Single source of truth for field definitions in migrations.

  This module provides canonical field definitions including names, types,
  and default options. All migration modules (FieldMacros, FieldBuilders)
  should reference this module to ensure consistency.

  ## Usage

      alias Events.Core.Migration.FieldDefinitions

      # Get a single field definition
      FieldDefinitions.field(:created_by_urm_id)
      # => {:created_by_urm_id, :binary_id, [null: true]}

      # Get all fields for a category
      FieldDefinitions.audit_fields()
      # => [
      #   {:created_by_urm_id, :binary_id, [null: true]},
      #   {:updated_by_urm_id, :binary_id, [null: true]}
      # ]

  ## Type Conventions

  - `:binary_id` - All UUID/ID references (user IDs, URM IDs)
  - `:utc_datetime_usec` - All timestamps (microsecond precision)
  - `:inet` - IP addresses
  - `:string` - Session IDs, short text
  - `:text` - Long text (reasons, descriptions)
  - `:jsonb` - Structured data (history, metadata)
  - `:integer` - Counters, versions
  - `:citext` - Case-insensitive text (status, type fields)
  """

  alias Events.Support.FieldNames

  # ============================================
  # Type Definitions
  # ============================================

  @type field_name :: atom()
  @type field_type :: atom() | {:array, atom()} | {:fragment, String.t()}
  @type field_opts :: keyword()
  @type field_definition :: {field_name(), field_type(), field_opts()}

  # Canonical types for consistency
  @id_type :binary_id
  @timestamp_type :utc_datetime_usec
  @ip_type :inet
  @session_type :string
  @text_type :text
  @json_type :jsonb
  @integer_type :integer
  @citext_type :citext

  # ============================================
  # Individual Field Definitions
  # ============================================

  @doc """
  Returns the definition for a single field by name.

  ## Examples

      FieldDefinitions.field(:created_by_urm_id)
      # => {:created_by_urm_id, :binary_id, [null: true]}

      FieldDefinitions.field(:unknown_field)
      # => nil
  """
  @spec field(field_name()) :: field_definition() | nil
  def field(name) when is_atom(name) do
    all_fields()
    |> Enum.find(fn {field_name, _type, _opts} -> field_name == name end)
  end

  @doc """
  Returns the type for a field by name.

  ## Examples

      FieldDefinitions.type(:created_by_urm_id)
      # => :binary_id

      FieldDefinitions.type(:deleted_at)
      # => :utc_datetime_usec
  """
  @spec type(field_name()) :: field_type() | nil
  def type(name) when is_atom(name) do
    case field(name) do
      {_name, type, _opts} -> type
      nil -> nil
    end
  end

  @doc """
  Returns the default options for a field by name.

  ## Examples

      FieldDefinitions.options(:created_by_urm_id)
      # => [null: true]

      FieldDefinitions.options(:version)
      # => [null: false, default: 1]
  """
  @spec options(field_name()) :: field_opts() | nil
  def options(name) when is_atom(name) do
    case field(name) do
      {_name, _type, opts} -> opts
      nil -> nil
    end
  end

  # ============================================
  # Audit Fields
  # ============================================

  @doc """
  Returns the base audit field definitions.

  These track who created and updated records via User Role Mapping IDs.
  """
  @spec audit_fields() :: [field_definition()]
  def audit_fields do
    [
      {FieldNames.created_by_urm_id(), @id_type, [null: true]},
      {FieldNames.updated_by_urm_id(), @id_type, [null: true]}
    ]
  end

  @doc """
  Returns audit fields for direct user tracking.

  Used when `track_user: true` option is enabled.
  """
  @spec audit_user_fields() :: [field_definition()]
  def audit_user_fields do
    [
      {FieldNames.created_by_user_id(), @id_type, [null: true]},
      {FieldNames.updated_by_user_id(), @id_type, [null: true]}
    ]
  end

  @doc """
  Returns audit fields for IP tracking.

  Used when `track_ip: true` option is enabled.
  """
  @spec ip_tracking_fields() :: [field_definition()]
  def ip_tracking_fields do
    [
      {FieldNames.created_from_ip(), @ip_type, [null: true]},
      {FieldNames.updated_from_ip(), @ip_type, [null: true]}
    ]
  end

  @doc """
  Returns audit fields for session tracking.

  Used when `track_session: true` option is enabled.
  """
  @spec session_tracking_fields() :: [field_definition()]
  def session_tracking_fields do
    [
      {FieldNames.created_session_id(), @session_type, [null: true]},
      {FieldNames.updated_session_id(), @session_type, [null: true]}
    ]
  end

  @doc """
  Returns audit fields for change tracking.

  Used when `track_changes: true` option is enabled.
  """
  @spec change_tracking_fields() :: [field_definition()]
  def change_tracking_fields do
    [
      {FieldNames.change_history(), @json_type, [null: false, default: []]},
      {FieldNames.version(), @integer_type, [null: false, default: 1]}
    ]
  end

  # ============================================
  # Soft Delete Fields
  # ============================================

  @doc """
  Returns soft delete field definitions.
  """
  @spec soft_delete_fields() :: [field_definition()]
  def soft_delete_fields do
    [
      {FieldNames.deleted_at(), @timestamp_type, [null: true]},
      {FieldNames.deleted_by_urm_id(), @id_type, [null: true]}
    ]
  end

  @doc """
  Returns soft delete user tracking field.

  Used when `track_user: true` option is enabled.
  """
  @spec soft_delete_user_field() :: field_definition()
  def soft_delete_user_field do
    {FieldNames.deleted_by_user_id(), @id_type, [null: true]}
  end

  @doc """
  Returns soft delete reason field.

  Used when `track_reason: true` option is enabled.
  """
  @spec soft_delete_reason_field() :: field_definition()
  def soft_delete_reason_field do
    {FieldNames.deletion_reason(), @text_type, [null: true]}
  end

  # ============================================
  # Timestamp Fields
  # ============================================

  @doc """
  Returns the base timestamp field definitions.
  """
  @spec timestamp_fields() :: [field_definition()]
  def timestamp_fields do
    [
      {FieldNames.inserted_at(), @timestamp_type, [null: false]},
      {FieldNames.updated_at(), @timestamp_type, [null: false]}
    ]
  end

  @doc """
  Returns lifecycle timestamp field definitions.

  Used when `with_lifecycle: true` option is enabled.
  """
  @spec lifecycle_timestamp_fields() :: [field_definition()]
  def lifecycle_timestamp_fields do
    [
      {:published_at, @timestamp_type, [null: true]},
      {:archived_at, @timestamp_type, [null: true]},
      {:expires_at, @timestamp_type, [null: true]}
    ]
  end

  # ============================================
  # Type/Status Fields
  # ============================================

  @doc """
  Returns type classification field definitions.

  These use citext for case-insensitive matching.
  """
  @spec type_classification_fields() :: [field_definition()]
  def type_classification_fields do
    [
      {:type, @citext_type, [null: true]},
      {:subtype, @citext_type, [null: true]},
      {:kind, @citext_type, [null: true]},
      {:category, @citext_type, [null: true]},
      {:variant, @citext_type, [null: true]}
    ]
  end

  @doc """
  Returns status field definitions.

  These use citext for case-insensitive matching.
  """
  @spec status_fields() :: [field_definition()]
  def status_fields do
    [
      {:status, @citext_type, [null: true]},
      {:substatus, @citext_type, [null: true]},
      {:state, @citext_type, [null: true]},
      {:workflow_state, @citext_type, [null: true]},
      {:approval_status, @citext_type, [null: true]}
    ]
  end

  @doc """
  Returns status transition tracking field definitions.

  Used when `with_transition: true` option is enabled.
  """
  @spec status_transition_fields() :: [field_definition()]
  def status_transition_fields do
    [
      {:previous_status, @citext_type, [null: true]},
      {:status_changed_at, @timestamp_type, [null: true]},
      {:status_changed_by, @id_type, [null: true]},
      {:status_history, @json_type, [null: false, default: []]}
    ]
  end

  # ============================================
  # All Fields
  # ============================================

  @doc """
  Returns all field definitions as a flat list.

  Useful for validation and introspection.
  """
  @spec all_fields() :: [field_definition()]
  def all_fields do
    audit_fields() ++
      audit_user_fields() ++
      ip_tracking_fields() ++
      session_tracking_fields() ++
      change_tracking_fields() ++
      soft_delete_fields() ++
      [soft_delete_user_field(), soft_delete_reason_field()] ++
      timestamp_fields() ++
      lifecycle_timestamp_fields() ++
      type_classification_fields() ++
      status_fields() ++
      status_transition_fields()
  end

  # ============================================
  # Type Constants (for external access)
  # ============================================

  @doc "Returns the canonical ID type (:binary_id)"
  @spec id_type() :: :binary_id
  def id_type, do: @id_type

  @doc "Returns the canonical timestamp type (:utc_datetime_usec)"
  @spec timestamp_type() :: :utc_datetime_usec
  def timestamp_type, do: @timestamp_type

  @doc "Returns the canonical IP address type (:inet)"
  @spec ip_type() :: :inet
  def ip_type, do: @ip_type

  @doc "Returns the canonical session type (:string)"
  @spec session_type() :: :string
  def session_type, do: @session_type

  @doc "Returns the canonical text type (:text)"
  @spec text_type() :: :text
  def text_type, do: @text_type

  @doc "Returns the canonical JSON type (:jsonb)"
  @spec json_type() :: :jsonb
  def json_type, do: @json_type

  @doc "Returns the canonical integer type (:integer)"
  @spec integer_type() :: :integer
  def integer_type, do: @integer_type

  @doc "Returns the canonical case-insensitive text type (:citext)"
  @spec citext_type() :: :citext
  def citext_type, do: @citext_type
end
