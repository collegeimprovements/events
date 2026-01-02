defmodule OmSchema.FieldMacros do
  @moduledoc """
  Field macros for Ecto schemas with customizable options.

  Provides macros to add common field sets to schemas with full control
  over which fields to include and their types.

  ## Usage

      defmodule MyApp.Product do
        use OmSchema
        import OmSchema.FieldMacros

        schema "products" do
          field :name, :string

          type_fields(only: [:type, :subtype])
          status_fields(only: [:status])
          timestamps()
        end
      end
  """

  # ============================================
  # Type Fields
  # ============================================

  @doc """
  Adds type classification fields to a schema.

  ## Options
  - `:only` - List of fields to include (default: all)
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: :string for Ecto.Enum compatibility)

  ## Available Fields
  - `:type` - Primary type classification
  - `:subtype` - Secondary type classification
  - `:kind` - Alternative categorization
  - `:category` - Category classification
  - `:variant` - Variant classification

  ## Examples

      schema "products" do
        type_fields()  # All fields
        type_fields(only: [:type, :subtype])
        type_fields(except: [:variant])
      end
  """
  defmacro type_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      defaults = [
        type: :string,
        fields: [:type, :subtype, :kind, :category, :variant]
      ]

      config = Keyword.merge(defaults, opts)
      fields = OmSchema.FieldMacros.__filter_fields__(config[:fields], config)

      Enum.each(fields, fn field_name ->
        field field_name, config[:type]
      end)
    end
  end

  # ============================================
  # Status Fields
  # ============================================

  @doc """
  Adds status tracking fields to a schema.

  ## Options
  - `:only` - List of fields to include (default: all)
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: :string for Ecto.Enum compatibility)
  - `:with_transition` - Include transition tracking fields (default: false)

  ## Available Fields
  - `:status` - Primary status
  - `:substatus` - Secondary status
  - `:state` - State machine state
  - `:workflow_state` - Workflow state
  - `:approval_status` - Approval status

  ## Examples

      schema "orders" do
        status_fields(only: [:status])
        status_fields(with_transition: true)
      end
  """
  defmacro status_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      defaults = [
        type: :string,
        with_transition: false,
        fields: [:status, :substatus, :state, :workflow_state, :approval_status]
      ]

      config = Keyword.merge(defaults, opts)
      fields = OmSchema.FieldMacros.__filter_fields__(config[:fields], config)

      Enum.each(fields, fn field_name ->
        field field_name, config[:type]
      end)

      if config[:with_transition] do
        field :previous_status, :string
        field :status_changed_at, :utc_datetime_usec
        field :status_changed_by, Ecto.UUID
        field :status_history, {:array, :map}, default: []
      end
    end
  end

  # ============================================
  # Audit Fields
  # ============================================

  @doc """
  Adds audit tracking fields to a schema.

  ## Options
  - `:track_urm` - Include URM tracking fields (default: true)
  - `:track_user` - Include direct user ID tracking (default: false)
  - `:track_ip` - Include IP address tracking (default: false)
  - `:track_session` - Include session tracking (default: false)
  - `:track_changes` - Include change history (default: false)

  At least one tracking option must be enabled.

  ## Generated Fields
  - `:created_by_urm_id` - Creator via user role mapping (when track_urm: true)
  - `:updated_by_urm_id` - Updater via user role mapping (when track_urm: true)
  - `:created_by_user_id` - Creator user ID (when track_user: true)
  - `:updated_by_user_id` - Updater user ID (when track_user: true)

  ## Examples

      schema "products" do
        audit_fields()                              # URM tracking (default)
        audit_fields(track_urm: false, track_user: true)  # User tracking only
        audit_fields(track_user: true, track_ip: true)    # Both URM and user + IP
      end
  """
  defmacro audit_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      alias OmFieldNames

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

      # URM tracking (default: true)
      if config[:track_urm] do
        field FieldNames.created_by_urm_id(), Ecto.UUID
        field FieldNames.updated_by_urm_id(), Ecto.UUID
      end

      # Optional: direct user ID tracking
      if config[:track_user] do
        field FieldNames.created_by_user_id(), Ecto.UUID
        field FieldNames.updated_by_user_id(), Ecto.UUID
      end

      # Optional: IP tracking
      if config[:track_ip] do
        field FieldNames.created_from_ip(), :string
        field FieldNames.updated_from_ip(), :string
      end

      # Optional: session tracking
      if config[:track_session] do
        field FieldNames.created_session_id(), :string
        field FieldNames.updated_session_id(), :string
      end

      # Optional: change history tracking
      if config[:track_changes] do
        field FieldNames.change_history(), {:array, :map}, default: []
        field FieldNames.version(), :integer, default: 1
      end
    end
  end

  # ============================================
  # Metadata Fields
  # ============================================

  @doc """
  Adds JSON metadata fields to a schema.

  ## Options
  - `:name` - Field name (default: :metadata)
  - `:default` - Default value (default: %{})

  ## Examples

      schema "products" do
        metadata_field()
        metadata_field(name: :properties)
        metadata_field(name: :settings, default: %{theme: "light"})
      end
  """
  defmacro metadata_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      name = Keyword.get(opts, :name, :metadata)
      default = Keyword.get(opts, :default, %{})

      field name, :map, default: default
    end
  end

  @doc """
  Adds tags array field to a schema.

  ## Options
  - `:name` - Field name (default: :tags)

  ## Examples

      schema "articles" do
        tags_field()
        tags_field(name: :categories)
      end
  """
  defmacro tags_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      name = Keyword.get(opts, :name, :tags)
      field name, {:array, :string}, default: []
    end
  end

  # ============================================
  # Soft Delete Fields
  # ============================================

  @doc """
  Adds soft delete fields to a schema.

  ## Base Fields
  - `:deleted_at` - Soft delete timestamp (always added)

  ## Options
  - `:track_urm` - Include deleted_by_urm_id field (default: true)
  - `:track_user` - Include deleted_by_user_id field (default: false)
  - `:track_reason` - Include deletion_reason field (default: false)

  ## Examples

      schema "users" do
        soft_delete_fields()
        soft_delete_fields(track_user: true, track_reason: true)
        soft_delete_fields(track_urm: false)
      end
  """
  defmacro soft_delete_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      alias OmFieldNames

      # Always add deleted_at
      field FieldNames.deleted_at(), :utc_datetime_usec

      # Default: track who deleted via URM
      if Keyword.get(opts, :track_urm, true) do
        field FieldNames.deleted_by_urm_id(), Ecto.UUID
      end

      # Optional: track direct user ID
      if Keyword.get(opts, :track_user, false) do
        field FieldNames.deleted_by_user_id(), Ecto.UUID
      end

      # Optional: track deletion reason
      if Keyword.get(opts, :track_reason, false) do
        field FieldNames.deletion_reason(), :text
      end
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  @doc false
  def __filter_fields__(all_fields, opts) do
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
