defmodule Events.Schema do
  @moduledoc """
  Base schema module that provides enhanced Ecto schema functionality.

  This module wraps Ecto.Schema and automatically adds common fields to all schemas:
  - UUIDv7 primary key (`id`)
  - Type classification fields (`type`, `subtype`)
  - Flexible metadata storage (`metadata` JSONB)
  - Audit tracking fields (`created_by_urm_id`, `updated_by_urm_id`)
  - Timestamps (`inserted_at`, `updated_at`)

  ## Usage

  Instead of `use Ecto.Schema`, use `Events.Schema`:

      defmodule MyApp.Accounts.User do
        use Events.Schema

        events_schema "users" do
          field :name, :string
          field :email, :string
        end
      end

  ## Opting Out

  You can disable automatic field additions:

      # Disable audit fields (for foundation tables like User, Role)
      use Events.Schema, audit_fields: false

      # Disable timestamps
      use Events.Schema, timestamps: false

      # Disable metadata
      use Events.Schema, metadata: false

      # Disable type/subtype
      use Events.Schema, type_fields: false

      # Combine options
      use Events.Schema, timestamps: false, audit_fields: false

  ## Custom Options

      # Custom timestamp options (only inserted_at)
      use Events.Schema, timestamps: [updated_at: false]

      # Only type field (no subtype)
      use Events.Schema, type_fields: [only: :type]
  """

  defmacro __using__(opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import Events.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @schema_opts unquote(opts)
    end
  end

  @doc """
  Defines a schema with automatic field additions.

  This macro wraps Ecto.Schema's `schema/2` and automatically adds:
  - Type fields (type, subtype)
  - Metadata field (JSONB)
  - Audit fields (created_by_urm_id, updated_by_urm_id)
  - Timestamps (inserted_at, updated_at)

  Fields can be disabled via module options (see module documentation).
  """
  defmacro events_schema(source, do: block) do
    quote do
      schema unquote(source) do
        # Add type fields unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :type_fields) do
          case Keyword.get(@schema_opts, :type_fields) do
            [only: :type] ->
              field :type, :string

            [only: :subtype] ->
              field :subtype, :string

            _ ->
              field :type, :string
              field :subtype, :string
          end
        end

        # Add metadata field unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :metadata) do
          field :metadata, :map, default: %{}
        end

        # User's custom fields
        unquote(block)

        # Add audit fields unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :audit_fields) do
          case Keyword.get(@schema_opts, :audit_fields) do
            [only: :created_by_urm_id] ->
              field :created_by_urm_id, :binary_id

            [only: :updated_by_urm_id] ->
              field :updated_by_urm_id, :binary_id

            _ ->
              field :created_by_urm_id, :binary_id
              field :updated_by_urm_id, :binary_id
          end
        end

        # Add timestamps unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :timestamps) do
          case Keyword.get(@schema_opts, :timestamps) do
            false ->
              :ok

            [inserted_at: false] ->
              field :updated_at, :utc_datetime_usec

            [updated_at: false] ->
              field :inserted_at, :utc_datetime_usec

            _ ->
              timestamps(type: :utc_datetime_usec)
          end
        end
      end
    end
  end

  @doc false
  def __should_add_field__(opts, field_name) do
    case Keyword.get(opts, field_name, true) do
      false -> false
      [only: _] -> true
      _ -> true
    end
  end
end
