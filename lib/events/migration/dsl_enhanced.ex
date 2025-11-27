defmodule Events.Migration.DSLEnhanced do
  @moduledoc """
  Enhanced DSL for migrations with direct field macro support.

  Allows calling field macros directly within create table blocks:

      create table(:products) do
        uuid_primary_key()
        type_fields()
        status_fields()
        timestamps()
      end

  > #### Prefer FieldBuilders {: .info}
  >
  > For new code, consider using the behavior-based FieldBuilders in
  > `Events.Migration.FieldBuilders.*` which provide better consistency
  > and reference `Events.Migration.FieldDefinitions` for type definitions.
  >
  > The FieldBuilders approach offers:
  > - Consistent types via `FieldDefinitions`
  > - Behavior-based extensibility
  > - Better testability
  """

  import Ecto.Migration

  # ============================================
  # Primary Key Macros
  # ============================================

  @doc """
  Adds UUIDv7 primary key (PostgreSQL 18+).

  ## Examples

      create table(:users) do
        uuid_primary_key()
      end

      # With custom name
      create table(:users) do
        uuid_primary_key(:uuid)
      end
  """
  defmacro uuid_primary_key(name \\ :id) do
    quote do
      add unquote(name), :uuid, primary_key: true, default: fragment("uuidv7()")
    end
  end

  @doc """
  Adds UUID v4 primary key for legacy systems.
  """
  defmacro uuid_v4_primary_key(name \\ :id) do
    quote do
      add unquote(name), :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
    end
  end

  # ============================================
  # Type Field Macros
  # ============================================

  @doc """
  Adds type classification fields.

  ## Options
  - `:only` - List of fields to include
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: :citext)

  ## Examples

      create table(:products) do
        type_fields()
        type_fields(only: [:type, :subtype])
      end
  """
  defmacro type_fields(opts \\ []) do
    fields = [:type, :subtype, :kind, :category, :variant]
    field_type = Keyword.get(opts, :type, :citext)
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    selected_fields =
      if only do
        Enum.filter(fields, &(&1 in only))
      else
        Enum.reject(fields, &(&1 in except))
      end

    quote do
      (unquote_splicing(
         Enum.map(selected_fields, fn field ->
           quote do
             add unquote(field), unquote(field_type), comment: unquote("Type field: #{field}")
           end
         end)
       ))
    end
  end

  @doc """
  Creates indexes for type fields.

  ## Examples

      create table(:products) do
        type_fields()
      end

      type_field_indexes(:products)
      type_field_indexes(:products, only: [:type])
  """
  defmacro type_field_indexes(table_name, opts \\ []) do
    fields = [:type, :subtype, :kind, :category, :variant]
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    selected_fields =
      if only do
        Enum.filter(fields, &(&1 in only))
      else
        Enum.reject(fields, &(&1 in except))
      end

    for field <- selected_fields do
      index_name = :"#{table_name}_#{field}_index"

      quote do
        create index(unquote(table_name), [unquote(field)], name: unquote(index_name))
      end
    end
  end

  # ============================================
  # Status Field Macros
  # ============================================

  @doc """
  Adds status tracking fields.

  ## Options
  - `:only` - List of fields to include
  - `:except` - List of fields to exclude
  - `:type` - Field type (default: :citext)
  - `:with_transition` - Include transition tracking

  ## Examples

      create table(:orders) do
        status_fields()
        status_fields(only: [:status])
        status_fields(with_transition: true)
      end
  """
  defmacro status_fields(opts \\ []) do
    fields = [:status, :substatus, :state, :workflow_state, :approval_status]
    field_type = Keyword.get(opts, :type, :citext)
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])
    with_transition = Keyword.get(opts, :with_transition, false)

    selected_fields =
      if only do
        Enum.filter(fields, &(&1 in only))
      else
        Enum.reject(fields, &(&1 in except))
      end

    base_fields =
      quote do
        (unquote_splicing(
           Enum.map(selected_fields, fn field ->
             quote do
               add unquote(field), unquote(field_type), comment: unquote("Status field: #{field}")
             end
           end)
         ))
      end

    transition_fields =
      if with_transition do
        quote do
          add :previous_status, :citext
          add :status_changed_at, :utc_datetime_usec
          add :status_changed_by, :binary_id
          add :status_history, :jsonb, default: fragment("'[]'::jsonb")
        end
      else
        quote do
        end
      end

    quote do
      unquote(base_fields)
      unquote(transition_fields)
    end
  end

  @doc """
  Creates indexes for status fields.
  """
  defmacro status_field_indexes(table_name, opts \\ []) do
    fields = [:status, :substatus, :state, :workflow_state, :approval_status]
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    selected_fields =
      if only do
        Enum.filter(fields, &(&1 in only))
      else
        Enum.reject(fields, &(&1 in except))
      end

    for field <- selected_fields do
      index_name = :"#{table_name}_#{field}_index"

      quote do
        create index(unquote(table_name), [unquote(field)], name: unquote(index_name))
      end
    end
  end

  # ============================================
  # Audit Field Macros
  # ============================================

  @doc """
  Adds audit tracking fields.

  ## Options
  - `:track_urm` - Include URM tracking (created_by_urm_id, updated_by_urm_id) (default: true)
  - `:track_user` - Include user ID tracking (default: false)
  - `:track_ip` - Include IP address tracking (default: false)
  - `:track_session` - Include session tracking (default: false)
  - `:track_changes` - Include change history (default: false)

  ## Examples

      create table(:documents) do
        # Default: URM tracking only
        audit_fields()

        # User tracking only (no URM)
        audit_fields(track_urm: false, track_user: true)

        # Full audit trail
        audit_fields(track_user: true, track_ip: true)
      end
  """
  defmacro audit_fields(opts \\ []) do
    track_urm = Keyword.get(opts, :track_urm, true)
    track_user = Keyword.get(opts, :track_user, false)
    track_ip = Keyword.get(opts, :track_ip, false)
    track_session = Keyword.get(opts, :track_session, false)
    track_changes = Keyword.get(opts, :track_changes, false)

    # Validate at compile time that at least one tracking option is enabled
    has_any_tracking = track_urm or track_user or track_ip or track_session or track_changes

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

    # URM tracking fields (default: true)
    urm_tracking =
      if track_urm do
        quote do
          add :created_by_urm_id, :binary_id
          add :updated_by_urm_id, :binary_id
        end
      else
        quote do
        end
      end

    user_tracking =
      if track_user do
        quote do
          add :created_by_user_id, :binary_id
          add :updated_by_user_id, :binary_id
        end
      else
        quote do
        end
      end

    ip_tracking =
      if track_ip do
        quote do
          add :created_from_ip, :inet
          add :updated_from_ip, :inet
        end
      else
        quote do
        end
      end

    session_tracking =
      if track_session do
        quote do
          add :created_session_id, :string
          add :updated_session_id, :string
        end
      else
        quote do
        end
      end

    change_tracking =
      if track_changes do
        quote do
          add :change_history, :jsonb, default: fragment("'[]'::jsonb")
          add :version, :integer, default: 1
        end
      else
        quote do
        end
      end

    quote do
      unquote(urm_tracking)
      unquote(user_tracking)
      unquote(ip_tracking)
      unquote(session_tracking)
      unquote(change_tracking)
    end
  end

  @doc """
  Creates indexes for audit fields.

  ## Options
  - `:track_urm` - Create indexes for URM fields (default: true)
  - `:track_user` - Create indexes for user fields (default: false)
  """
  defmacro audit_field_indexes(table_name, opts \\ []) do
    track_urm = Keyword.get(opts, :track_urm, true)
    track_user = Keyword.get(opts, :track_user, false)

    urm_indexes =
      if track_urm do
        [
          quote do
            create index(unquote(table_name), [:created_by_urm_id])
          end,
          quote do
            create index(unquote(table_name), [:updated_by_urm_id])
          end
        ]
      else
        []
      end

    user_indexes =
      if track_user do
        [
          quote do
            create index(unquote(table_name), [:created_by_user_id])
          end,
          quote do
            create index(unquote(table_name), [:updated_by_user_id])
          end
        ]
      else
        []
      end

    urm_indexes ++ user_indexes
  end

  # ============================================
  # Timestamp Macros
  # ============================================

  @doc """
  Adds timestamp fields with utc_datetime_usec precision.

  NOTE: Inside `create table()` blocks, use Ecto.Migration.timestamps() directly
  with type: :utc_datetime_usec, or use this helper outside the block.

  ## Options
  - `:type` - Timestamp type (default: :utc_datetime_usec)

  ## Examples

      # Inside create table - use Ecto's timestamps with our type
      create table(:articles) do
        timestamps(type: :utc_datetime_usec)
      end

      # Or use our helper macros separately
      create table(:articles) do
        add :title, :string
      end
      # Then add timestamps with our defaults
  """
  defmacro event_timestamps(opts \\ []) when is_list(opts) do
    timestamp_type = Keyword.get(opts, :type, :utc_datetime_usec)
    with_deleted = Keyword.get(opts, :with_deleted, false)
    with_lifecycle = Keyword.get(opts, :with_lifecycle, false)

    # Use Ecto.Migration.timestamps for base fields
    base =
      quote do
        Ecto.Migration.timestamps(type: unquote(timestamp_type))
      end

    deleted =
      if with_deleted do
        quote do
          add :deleted_at, unquote(timestamp_type)
        end
      else
        []
      end

    lifecycle =
      if with_lifecycle do
        quote do
          add :published_at, unquote(timestamp_type)
          add :archived_at, unquote(timestamp_type)
          add :expires_at, unquote(timestamp_type)
        end
      else
        []
      end

    [base | deleted ++ [lifecycle]]
  end

  @doc """
  Creates indexes for timestamp fields.
  """
  defmacro timestamp_indexes(table_name, opts \\ []) do
    only = Keyword.get(opts, :only)
    with_deleted = Keyword.get(opts, :with_deleted, false)

    base_fields = [:inserted_at, :updated_at]

    selected_fields =
      if only do
        Enum.filter(base_fields, &(&1 in only))
      else
        base_fields
      end

    base_indexes =
      for field <- selected_fields do
        index_name = :"#{table_name}_#{field}_index"

        quote do
          create index(unquote(table_name), [unquote(field)], name: unquote(index_name))
        end
      end

    deleted_indexes =
      if with_deleted do
        active_index_name = :"#{table_name}_active_records_index"

        [
          quote do
            create index(unquote(table_name), [:deleted_at])
          end,
          quote do
            create index(unquote(table_name), [:id],
                     where: "deleted_at IS NULL",
                     name: unquote(active_index_name)
                   )
          end
        ]
      else
        []
      end

    base_indexes ++ deleted_indexes
  end

  # ============================================
  # Soft Delete Macros
  # ============================================

  @doc """
  Adds soft delete fields.

  ## Options
  - `:track_urm` - Include deleted_by_urm_id (default: true)
  - `:track_user` - Include deleted_by_user_id (default: false)
  - `:track_reason` - Include deletion_reason (default: false)

  ## Examples

      create table(:users) do
        soft_delete_fields()
        soft_delete_fields(track_user: true, track_reason: true)
        soft_delete_fields(track_urm: false)
      end
  """
  defmacro soft_delete_fields(opts \\ []) do
    # Handle deprecated option name
    opts =
      if Keyword.has_key?(opts, :track_role_mapping) do
        IO.warn("track_role_mapping is deprecated, use track_urm instead")
        Keyword.put(opts, :track_urm, Keyword.get(opts, :track_role_mapping))
      else
        opts
      end

    track_urm = Keyword.get(opts, :track_urm, true)
    track_user = Keyword.get(opts, :track_user, false)
    track_reason = Keyword.get(opts, :track_reason, false)

    base =
      quote do
        add :deleted_at, :utc_datetime_usec
      end

    urm_tracking =
      if track_urm do
        quote do
          add :deleted_by_urm_id, :binary_id
        end
      else
        quote do
        end
      end

    user_tracking =
      if track_user do
        quote do
          add :deleted_by_user_id, :binary_id
        end
      else
        quote do
        end
      end

    reason_tracking =
      if track_reason do
        quote do
          add :deletion_reason, :text
        end
      else
        quote do
        end
      end

    quote do
      unquote(base)
      unquote(urm_tracking)
      unquote(user_tracking)
      unquote(reason_tracking)
    end
  end

  # ============================================
  # Metadata Macros
  # ============================================

  @doc """
  Adds JSONB metadata field.

  ## Examples

      create table(:products) do
        metadata_field()
        metadata_field(:properties)
      end
  """
  defmacro metadata_field(name \\ :metadata) do
    quote do
      add unquote(name), :jsonb, default: fragment("'{}'::jsonb")
    end
  end

  @doc """
  Creates GIN index for metadata field.
  """
  defmacro metadata_index(table_name, field_name \\ :metadata) do
    quote do
      index_name = :"#{unquote(table_name)}_#{unquote(field_name)}_gin_index"

      create index(unquote(table_name), [unquote(field_name)],
               using: :gin,
               name: index_name
             )
    end
  end

  @doc """
  Adds tags array field.

  ## Examples

      create table(:articles) do
        tags_field()
        tags_field(:categories)
      end
  """
  defmacro tags_field(name \\ :tags) do
    quote do
      add unquote(name), {:array, :string}, default: fragment("ARRAY[]::text[]")
    end
  end

  @doc """
  Creates GIN index for tags field.
  """
  defmacro tags_index(table_name, field_name \\ :tags) do
    quote do
      index_name = :"#{unquote(table_name)}_#{unquote(field_name)}_gin_index"

      create index(unquote(table_name), [unquote(field_name)],
               using: :gin,
               name: index_name
             )
    end
  end

  # ============================================
  # Money Fields
  # ============================================

  @doc """
  Adds money/decimal fields.

  ## Examples

      create table(:invoices) do
        money_field(:subtotal)
        money_field(:tax)
        money_field(:total)
      end
  """
  defmacro money_field(name, opts \\ []) do
    precision = Keyword.get(opts, :precision, 10)
    scale = Keyword.get(opts, :scale, 2)

    quote do
      add unquote(name), :decimal, precision: unquote(precision), scale: unquote(scale)
    end
  end

  # ============================================
  # Foreign Key Macros
  # ============================================

  @doc """
  Adds a foreign key field with UUID type.

  ## Examples

      create table(:posts) do
        belongs_to_field(:user)
        belongs_to_field(:category)
      end
  """
  defmacro belongs_to_field(name, opts \\ []) do
    field_name = :"#{name}_id"
    null = Keyword.get(opts, :null, false)
    on_delete = Keyword.get(opts, :on_delete, :nothing)

    quote do
      add unquote(field_name),
          references(unquote(:"#{name}s"), type: :binary_id, on_delete: unquote(on_delete)),
          null: unquote(null)
    end
  end

  @doc """
  Creates index for foreign key.
  """
  defmacro foreign_key_index(table_name, field_name) do
    quote do
      index_name = :"#{unquote(table_name)}_#{unquote(field_name)}_index"
      create index(unquote(table_name), [unquote(field_name)], name: index_name)
    end
  end

  # ============================================
  # Composite Helpers
  # ============================================

  @doc """
  Adds all common indexes for a table.

  ## Examples

      create table(:products) do
        type_fields()
        status_fields()
        timestamps()
      end

      create_standard_indexes(:products)
  """
  defmacro create_standard_indexes(table_name, opts \\ []) do
    quote do
      unquote(__MODULE__).type_field_indexes(unquote(table_name), unquote(opts))
      unquote(__MODULE__).status_field_indexes(unquote(table_name), unquote(opts))
      unquote(__MODULE__).audit_field_indexes(unquote(table_name), unquote(opts))
      unquote(__MODULE__).timestamp_indexes(unquote(table_name), unquote(opts))
    end
  end
end
