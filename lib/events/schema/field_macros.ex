defmodule Events.Schema.FieldMacros do
  @moduledoc """
  Field macros for Ecto schemas with customizable options.

  Provides macros to add common field sets to schemas with full control
  over which fields to include and their types.

  ## Usage

      defmodule MyApp.Product do
        use Events.Schema
        import Events.Schema.FieldMacros

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
      fields = Events.Schema.FieldMacros.__filter_fields__(config[:fields], config)

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
      fields = Events.Schema.FieldMacros.__filter_fields__(config[:fields], config)

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
  - `:only` - List of fields to include
  - `:except` - List of fields to exclude
  - `:track_user` - Include user ID tracking (default: true)
  - `:track_ip` - Include IP address tracking (default: false)
  - `:track_session` - Include session tracking (default: false)
  - `:track_changes` - Include change history (default: false)

  ## Examples

      schema "products" do
        audit_fields()
        audit_fields(track_ip: true, track_changes: true)
      end
  """
  defmacro audit_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      defaults = [
        track_user: true,
        track_ip: false,
        track_session: false,
        track_changes: false,
        fields: [:created_by, :updated_by]
      ]

      config = Keyword.merge(defaults, opts)
      fields = Events.Schema.FieldMacros.__filter_fields__(config[:fields], config)

      Enum.each(fields, fn field_name ->
        field field_name, :string
      end)

      if config[:track_user] do
        field :created_by_user_id, Ecto.UUID
        field :updated_by_user_id, Ecto.UUID
      end

      if config[:track_ip] do
        field :created_from_ip, :string
        field :updated_from_ip, :string
      end

      if config[:track_session] do
        field :created_session_id, :string
        field :updated_session_id, :string
      end

      if config[:track_changes] do
        field :change_history, {:array, :map}, default: []
        field :version, :integer, default: 1
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

  ## Options
  - `:track_user` - Include deleted_by_user_id field (default: false)
  - `:track_role_mapping` - Include deleted_by_user_role_mapping_id field (default: true)
  - `:track_reason` - Include deletion_reason field (default: false)

  ## Examples

      schema "users" do
        soft_delete_fields()
        soft_delete_fields(track_user: true, track_reason: true)
        soft_delete_fields(track_role_mapping: false)
      end
  """
  defmacro soft_delete_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      field :deleted_at, :utc_datetime_usec

      if Keyword.get(opts, :track_role_mapping, true) do
        field :deleted_by_user_role_mapping_id, Ecto.UUID
      end

      if Keyword.get(opts, :track_user, false) do
        field :deleted_by_user_id, Ecto.UUID
      end

      if Keyword.get(opts, :track_reason, false) do
        field :deletion_reason, :string
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
