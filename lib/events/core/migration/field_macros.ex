defmodule Events.Core.Migration.FieldMacros do
  @moduledoc """
  Comprehensive field macros for migrations with customizable options.

  All field macros support customization for field selection and types.
  Type fields use citext, timestamps use utc_datetime_usec by default.

  ## Usage Examples

      # Use all default fields
      create_table(:products)
      |> with_type_fields()
      |> with_timestamps()
      |> execute()

      # Customize fields
      create_table(:orders)
      |> with_type_fields(only: [:type])
      |> with_status_fields(only: [:status], type: :string)
      |> with_timestamps(only: [:inserted_at])
      |> execute()

  ## Note

  This module uses `Events.Core.Migration.FieldDefinitions` as the single source
  of truth for field types. For new projects, consider using the behavior-based
  FieldBuilders instead (e.g., `Events.Core.Migration.FieldBuilders.AuditFields`).
  """

  alias Events.Core.Migration.Token
  alias Events.Core.Migration.FieldDefinitions

  # ============================================
  # Type Fields (citext by default)
  # ============================================

  @doc """
  Adds type classification fields.

  ## Options
  - `:only` - List of fields to include (default: all)
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: :citext)
  - `:null` - Whether fields can be null (default: true)

  ## Available Fields
  - `:type` - Primary type classification
  - `:subtype` - Secondary type classification
  - `:kind` - Alternative categorization
  - `:category` - Category classification
  - `:variant` - Variant classification

  ## Examples

      # All type fields
      with_type_fields()

      # Only type and subtype
      with_type_fields(only: [:type, :subtype])

      # All except variant
      with_type_fields(except: [:variant])

      # Custom type
      with_type_fields(type: :string)
  """
  def with_type_fields(%Token{} = token, opts \\ []) do
    defaults = [
      type: :citext,
      null: true,
      fields: [:type, :subtype, :kind, :category, :variant]
    ]

    config = Keyword.merge(defaults, opts)
    fields = filter_fields(config[:fields], config)

    Enum.reduce(fields, token, fn field_name, acc ->
      Token.add_field(acc, field_name, config[:type],
        null: config[:null],
        comment: "Type classification: #{field_name}"
      )
    end)
  end

  # ============================================
  # Status Fields (citext by default)
  # ============================================

  @doc """
  Adds status tracking fields.

  ## Options
  - `:only` - List of fields to include (default: all)
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: :citext)
  - `:null` - Whether fields can be null (default: true)
  - `:with_transition` - Include transition tracking fields (default: false)

  ## Available Fields
  - `:status` - Primary status
  - `:substatus` - Secondary status
  - `:state` - State machine state
  - `:workflow_state` - Workflow state
  - `:approval_status` - Approval status

  ## Examples

      # Basic status field
      with_status_fields(only: [:status])

      # Status with transition tracking
      with_status_fields(with_transition: true)
  """
  def with_status_fields(%Token{} = token, opts \\ []) do
    defaults = [
      type: :citext,
      null: true,
      with_transition: false,
      fields: [:status, :substatus, :state, :workflow_state, :approval_status]
    ]

    config = Keyword.merge(defaults, opts)
    fields = filter_fields(config[:fields], config)

    token
    |> add_status_fields(fields, config)
    |> maybe_add_transition_fields(config[:with_transition])
    |> Token.add_index(:status_index, [:status])
  end

  defp add_status_fields(token, fields, config) do
    Enum.reduce(fields, token, fn field_name, acc ->
      Token.add_field(acc, field_name, config[:type],
        null: config[:null],
        comment: "Status field: #{field_name}"
      )
    end)
  end

  defp maybe_add_transition_fields(token, false), do: token

  defp maybe_add_transition_fields(token, true) do
    token
    |> Token.add_field(:previous_status, :citext, null: true)
    |> Token.add_field(:status_changed_at, :utc_datetime_usec, null: true)
    |> Token.add_field(:status_changed_by, :binary_id, null: true)
    |> Token.add_field(:status_history, :jsonb, default: [], null: false)
  end

  # ============================================
  # Timestamps (utc_datetime_usec by default)
  # ============================================

  @doc """
  Adds timestamp fields.

  ## Options
  - `:only` - List of fields to include (default: [:inserted_at, :updated_at])
  - `:except` - List of fields to exclude
  - `:type` - Timestamp type (default: :utc_datetime_usec)
  - `:null` - Whether fields can be null (default: false)
  - `:with_deleted` - Include deleted_at field (default: false)
  - `:with_lifecycle` - Include lifecycle timestamps (default: false)

  ## Available Fields
  - `:inserted_at` - Record creation time
  - `:updated_at` - Last update time
  - `:deleted_at` - Soft delete time (when with_deleted: true)
  - `:published_at` - Publication time (when with_lifecycle: true)
  - `:archived_at` - Archive time (when with_lifecycle: true)
  - `:expires_at` - Expiration time (when with_lifecycle: true)

  ## Examples

      # Standard timestamps
      with_timestamps()

      # Only inserted_at
      with_timestamps(only: [:inserted_at])

      # With soft delete
      with_timestamps(with_deleted: true)

      # Full lifecycle tracking
      with_timestamps(with_lifecycle: true)
  """
  def with_timestamps(%Token{} = token, opts \\ []) do
    defaults = [
      type: :utc_datetime_usec,
      null: false,
      with_deleted: false,
      with_lifecycle: false,
      fields: [:inserted_at, :updated_at]
    ]

    config = Keyword.merge(defaults, opts)
    base_fields = filter_fields(config[:fields], config)

    token
    |> add_timestamp_fields(base_fields, config)
    |> maybe_add_deleted_timestamp(config[:with_deleted])
    |> maybe_add_lifecycle_timestamps(config[:with_lifecycle])
    |> add_timestamp_indexes(base_fields, config)
  end

  defp add_timestamp_fields(token, fields, config) do
    Enum.reduce(fields, token, fn field_name, acc ->
      Token.add_field(acc, field_name, config[:type],
        null: config[:null],
        comment: "Timestamp: #{field_name}"
      )
    end)
  end

  defp maybe_add_deleted_timestamp(token, false), do: token

  defp maybe_add_deleted_timestamp(token, true) do
    Token.add_field(token, :deleted_at, :utc_datetime_usec,
      null: true,
      comment: "Soft delete timestamp"
    )
  end

  defp maybe_add_lifecycle_timestamps(token, false), do: token

  defp maybe_add_lifecycle_timestamps(token, true) do
    token
    |> Token.add_field(:published_at, :utc_datetime_usec, null: true)
    |> Token.add_field(:archived_at, :utc_datetime_usec, null: true)
    |> Token.add_field(:expires_at, :utc_datetime_usec, null: true)
  end

  defp add_timestamp_indexes(token, fields, _config) do
    Enum.reduce(fields, token, fn field_name, acc ->
      Token.add_index(acc, :"#{field_name}_index", [field_name])
    end)
  end

  # ============================================
  # Audit Fields
  # ============================================

  @doc """
  Adds audit tracking fields.

  ## Options
  - `:track_urm` - Include URM tracking (created_by_urm_id, updated_by_urm_id) (default: true)
  - `:track_user` - Include user ID tracking (default: false)
  - `:track_ip` - Include IP address tracking (default: false)
  - `:track_session` - Include session tracking (default: false)
  - `:track_changes` - Include change history (default: false)

  ## Generated Fields
  - `:created_by_urm_id` - Creator URM identifier (when track_urm: true)
  - `:updated_by_urm_id` - Last updater URM identifier (when track_urm: true)
  - `:created_by_user_id` - Creator user ID (when track_user: true)
  - `:updated_by_user_id` - Last updater user ID (when track_user: true)

  ## Examples

      # Basic audit with URM tracking (default)
      with_audit_fields()

      # User tracking only (no URM)
      with_audit_fields(track_urm: false, track_user: true)

      # Full audit trail
      with_audit_fields(track_user: true, track_ip: true, track_changes: true)
  """
  def with_audit_fields(%Token{} = token, opts \\ []) do
    defaults = [
      track_urm: true,
      track_user: false,
      track_ip: false,
      track_session: false,
      track_changes: false
    ]

    config = Keyword.merge(defaults, opts)

    # Validate that at least one tracking option is enabled
    has_any_tracking =
      config[:track_urm] or config[:track_user] or config[:track_ip] or
        config[:track_session] or config[:track_changes]

    unless has_any_tracking do
      raise ArgumentError, """
      audit_fields() requires at least one tracking option to be enabled.

      You have disabled all tracking options:
        track_urm: false, track_user: false, track_ip: false,
        track_session: false, track_changes: false

      Either enable at least one option or remove the audit_fields() call entirely.

      Examples:
        audit_fields()                              # URM tracking (default)
        audit_fields(track_urm: false, track_user: true)  # User tracking only
        audit_fields(track_ip: true)                # URM + IP tracking
      """
    end

    token
    |> maybe_add_urm_tracking(config[:track_urm])
    |> maybe_add_user_tracking(config[:track_user])
    |> maybe_add_ip_tracking(config[:track_ip])
    |> maybe_add_session_tracking(config[:track_session])
    |> maybe_add_change_tracking(config[:track_changes])
  end

  defp maybe_add_urm_tracking(token, false), do: token

  defp maybe_add_urm_tracking(token, true) do
    token
    |> Token.add_field(:created_by_urm_id, FieldDefinitions.id_type(),
      null: true,
      comment: "Audit: created_by_urm_id"
    )
    |> Token.add_field(:updated_by_urm_id, FieldDefinitions.id_type(),
      null: true,
      comment: "Audit: updated_by_urm_id"
    )
  end

  defp maybe_add_user_tracking(token, false), do: token

  defp maybe_add_user_tracking(token, true) do
    token
    |> Token.add_field(:created_by_user_id, :binary_id, null: true)
    |> Token.add_field(:updated_by_user_id, :binary_id, null: true)
    |> Token.add_index(:created_by_user_index, [:created_by_user_id])
    |> Token.add_index(:updated_by_user_index, [:updated_by_user_id])
  end

  defp maybe_add_ip_tracking(token, false), do: token

  defp maybe_add_ip_tracking(token, true) do
    token
    |> Token.add_field(:created_from_ip, :inet, null: true)
    |> Token.add_field(:updated_from_ip, :inet, null: true)
  end

  defp maybe_add_session_tracking(token, false), do: token

  defp maybe_add_session_tracking(token, true) do
    token
    |> Token.add_field(:created_session_id, :string, null: true)
    |> Token.add_field(:updated_session_id, :string, null: true)
  end

  defp maybe_add_change_tracking(token, false), do: token

  defp maybe_add_change_tracking(token, true) do
    token
    |> Token.add_field(:change_history, :jsonb, default: [], null: false)
    |> Token.add_field(:version, :integer, default: 1, null: false)
  end

  # ============================================
  # Primary Key Customization
  # ============================================

  @doc """
  Sets up UUIDv7 as the primary key (PostgreSQL 18+).

  ## Options
  - `:name` - Primary key field name (default: :id)
  - `:type` - UUID version (:uuidv7, :uuidv4, default: :uuidv7)

  ## Examples

      # Default UUIDv7
      with_uuid_primary_key()

      # Custom name
      with_uuid_primary_key(name: :uuid)

      # UUID v4 for legacy systems
      with_uuid_primary_key(type: :uuidv4)
  """
  def with_uuid_primary_key(%Token{} = token, opts \\ []) do
    name = Keyword.get(opts, :name, :id)
    uuid_type = Keyword.get(opts, :type, :uuidv7)

    fragment =
      case uuid_type do
        :uuidv7 -> "uuidv7()"
        :uuidv4 -> "uuid_generate_v4()"
        _ -> raise "Unsupported UUID type: #{uuid_type}"
      end

    token
    |> Token.put_option(:primary_key, false)
    |> Token.add_field(name, :binary_id,
      primary_key: true,
      default: {:fragment, fragment},
      comment: "Primary key using #{uuid_type}"
    )
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp filter_fields(all_fields, opts) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    fields =
      if only do
        Enum.filter(all_fields, &(&1 in only))
      else
        Enum.reject(all_fields, &(&1 in except))
      end

    if fields == [] do
      raise ArgumentError, "No fields selected after filtering"
    end

    fields
  end
end
